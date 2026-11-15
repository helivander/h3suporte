import assert from "node:assert/strict";
import { createServer } from "node:http";
import { after, before, beforeEach, test } from "node:test";
import { criarApp } from "../src/app.js";
import { abrirBanco } from "../src/banco.js";
import { criarCentral } from "../src/central.js";

// Central simulada com o contrato de docs/central-contas-assinante.md.
const estado = {};
function reiniciarCentral() {
  Object.assign(estado, {
    fora: false,
    assinatura: { id: "ass-1", estado: "ATIVA", plano: { id: "p1", nome: "Equipe" } },
    contas: [
      { id: "c1", email: "ana@empresa.com", nome: "Ana", papel: "TITULAR", ativo: true, senha: "senha-da-ana-123" },
      { id: "c2", email: "bia@empresa.com", nome: "Bia", papel: "MEMBRO", ativo: true, senha: "senha-da-bia-123", totp: "654321" },
    ],
    sessoes: new Map(),
    desafios: new Map(),
    credencialRecebida: null,
  });
}
const publica = ({ senha, totp, ...c }) => c;

async function lerJson(req) {
  let t = "";
  for await (const p of req) t += p;
  return t ? JSON.parse(t) : {};
}

const central = createServer(async (req, res) => {
  estado.credencialRecebida = req.headers.authorization;
  const responder = (status, corpo) => {
    res.writeHead(status, { "content-type": "application/json" });
    res.end(corpo === undefined ? "" : JSON.stringify(corpo));
  };
  if (estado.fora) return responder(502, { message: "bad gateway" });
  const d = await lerJson(req);
  const rota = req.url.replace("/api/api-servico/contas/", "");
  const sessaoDe = (token) => estado.contas.find((c) => c.id === estado.sessoes.get(token));
  if (rota === "entrar") {
    let conta;
    if (d.desafio) {
      conta = estado.contas.find((c) => c.id === estado.desafios.get(d.desafio));
      if (!conta) return responder(401, { codigo: "CREDENCIAIS_INVALIDAS", message: "x" });
      if (d.codigoTotp !== conta.totp) return responder(401, { codigo: "TOTP_INVALIDO", message: "x" });
      estado.desafios.delete(d.desafio);
    } else {
      conta = estado.contas.find((c) => c.email === d.email && c.senha === d.senha);
      if (!conta) return responder(401, { codigo: "CREDENCIAIS_INVALIDAS", message: "x" });
      if (conta.totp) {
        estado.desafios.set("desafio-1", conta.id);
        return responder(401, { codigo: "TOTP_NECESSARIO", message: "x", desafio: "desafio-1" });
      }
    }
    if (estado.assinatura.estado !== "ATIVA") return responder(403, { codigo: "ASSINATURA_INATIVA", message: "x" });
    const token = `cs_${conta.id}_${estado.sessoes.size}`;
    estado.sessoes.set(token, conta.id);
    return responder(200, { sessao: { token }, conta: publica(conta), assinatura: estado.assinatura });
  }
  if (rota === "validar") {
    const conta = sessaoDe(d.sessao);
    if (!conta) return responder(200, { valida: false, motivo: "SESSAO_INVALIDA" });
    if (estado.assinatura.estado !== "ATIVA") return responder(200, { valida: false, motivo: "ASSINATURA_INATIVA" });
    return responder(200, { valida: true, conta: publica(conta), assinatura: estado.assinatura });
  }
  if (rota === "sair") {
    estado.sessoes.delete(d.sessao);
    return responder(204);
  }
  if (rota === "equipe") {
    if (!sessaoDe(d.sessao)) return responder(401, { codigo: "SESSAO_INVALIDA", message: "x" });
    return responder(200, { contas: estado.contas.map(publica) });
  }
  responder(404, { message: "?" });
});

let agora = 1_000_000;
let api;
let base;
const config = { revalidarMs: 300_000, toleranciaMs: 72 * 3600_000, confiarProxy: false };

before(async () => {
  await new Promise((r) => central.listen(0, "127.0.0.1", r));
  const cliente = criarCentral({
    url: `http://127.0.0.1:${central.address().port}/api`,
    credencial: "sva_teste",
    timeoutMs: 2000,
  });
  const banco = abrirBanco(":memory:");
  api = createServer(criarApp({ config, banco, central: cliente, relogio: () => agora }));
  await new Promise((r) => api.listen(0, "127.0.0.1", r));
  base = `http://127.0.0.1:${api.address().port}`;
});
after(() => {
  api.close();
  central.close();
});
beforeEach(reiniciarCentral);

async function chamar(metodo, caminho, corpo, token) {
  const r = await fetch(base + caminho, {
    method: metodo,
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: corpo === undefined ? undefined : JSON.stringify(corpo),
  });
  const texto = await r.text();
  let json;
  try {
    json = JSON.parse(texto);
  } catch {
    json = undefined;
  }
  return { status: r.status, texto, json };
}

const loginAna = (extra = {}) =>
  chamar("POST", "/api/login", {
    username: "Ana@Empresa.com ",
    password: "senha-da-ana-123",
    id: "123456789",
    uuid: "dXVpZC1hbmE=",
    type: "account",
    deviceInfo: { os: "windows", type: "client", name: "NOTE-ANA" },
    ...extra,
  });

test("login com e-mail e senha devolve o token no formato do cliente e libera currentUser e catálogo", async () => {
  const r = await loginAna();
  assert.equal(r.status, 200);
  assert.equal(r.json.type, "access_token");
  assert.match(r.json.access_token, /^cs_c1_/);
  assert.equal(r.json.user.name, "ana@empresa.com");
  assert.equal(r.json.user.display_name, "Ana");
  assert.equal(r.json.user.funcoes, null, "produto sem funções por plano: tudo liberado");
  assert.equal(estado.credencialRecebida, "Bearer sva_teste");
  const token = r.json.access_token;

  const eu = await chamar("POST", "/api/currentUser", { id: "123456789", uuid: "dXVpZC1hbmE=" }, token);
  assert.equal(eu.status, 200);
  assert.equal(eu.json.email, "ana@empresa.com");

  assert.equal((await chamar("GET", "/api/ab", undefined, token)).texto, "null");
  const dados = JSON.stringify({ tags: ["clientes"], peers: [{ id: "987654321", alias: "Loja" }] });
  assert.equal((await chamar("POST", "/api/ab", { data: dados }, token)).status, 200);
  const ab = await chamar("GET", "/api/ab", undefined, token);
  assert.equal(ab.json.data, dados);

  const pessoal = await chamar("POST", "/api/ab/personal", undefined, token);
  assert.equal(pessoal.status, 404, "404 põe o cliente no modo de catálogo legado");
});

test("login e currentUser levam ao app as funções liberadas pelo plano", async () => {
  estado.assinatura.funcoes = ["terminal"];
  try {
    const r = await loginAna();
    assert.equal(r.status, 200);
    assert.deepEqual(r.json.user.funcoes, ["terminal"]);
    const eu = await chamar("POST", "/api/currentUser", {}, r.json.access_token);
    assert.deepEqual(eu.json.funcoes, ["terminal"]);
  } finally {
    delete estado.assinatura.funcoes;
  }
});

test("senha errada e chamadas sem token são recusadas com mensagem em português", async () => {
  const r = await loginAna({ password: "errada-errada-1" });
  assert.equal(r.status, 401);
  assert.equal(r.json.error, "E-mail ou senha incorretos.");
  assert.equal((await chamar("GET", "/api/ab")).status, 401);
  assert.equal((await chamar("POST", "/api/currentUser", {}, "cs_inventado")).status, 401);
});

test("conta com 2FA pede o código e entra no segundo passo", async () => {
  const p1 = await chamar("POST", "/api/login", {
    username: "bia@empresa.com",
    password: "senha-da-bia-123",
    id: "222",
    uuid: "dXVpZC1iaWE=",
  });
  assert.equal(p1.status, 200);
  assert.equal(p1.json.type, "email_check");
  assert.equal(p1.json.tfa_type, "tfa_check");
  assert.equal(p1.json.user.name, "bia@empresa.com");

  const errado = await chamar("POST", "/api/login", {
    username: "bia@empresa.com",
    secret: p1.json.secret,
    tfaCode: "000000",
    verificationCode: "000000",
    type: "email_code",
    id: "222",
    uuid: "dXVpZC1iaWE=",
  });
  assert.equal(errado.status, 401);
  assert.equal(errado.json.error, "Código de verificação incorreto.");

  const p2 = await chamar("POST", "/api/login", {
    username: "bia@empresa.com",
    secret: p1.json.secret,
    tfaCode: "654321",
    verificationCode: "654321",
    type: "email_code",
    id: "222",
    uuid: "dXVpZC1iaWE=",
  });
  assert.equal(p2.status, 200);
  assert.equal(p2.json.type, "access_token");
});

test("assinatura suspensa na Central derruba a sessão na próxima revalidação", async () => {
  const token = (await loginAna()).json.access_token;
  estado.assinatura.estado = "SUSPENSA";
  assert.equal((await chamar("POST", "/api/currentUser", {}, token)).status, 200, "ainda dentro do cache");
  agora += config.revalidarMs;
  assert.equal((await chamar("POST", "/api/currentUser", {}, token)).status, 401);
  estado.assinatura.estado = "ATIVA";
  assert.equal((await chamar("POST", "/api/currentUser", {}, token)).status, 401, "sessão apagada");
  assert.equal((await loginAna()).status, 200);
});

test("Central fora: segue dentro da tolerância offline e recusa com 503 depois dela", async () => {
  const token = (await loginAna()).json.access_token;
  estado.fora = true;
  agora += config.revalidarMs;
  assert.equal((await chamar("POST", "/api/currentUser", {}, token)).status, 200);
  agora += config.toleranciaMs;
  const r = await chamar("POST", "/api/currentUser", {}, token);
  assert.equal(r.status, 503, "503 não faz o cliente apagar o login");
  const login = await loginAna();
  assert.equal(login.status, 503);
});

test("grupo mostra a equipe e os computadores em que cada conta entrou", async () => {
  const ana = (await loginAna()).json.access_token;
  await chamar("POST", "/api/sysinfo", { id: "123456789", hostname: "NOTE-ANA", os: "Windows 11" });
  const usuarios = await chamar("GET", "/api/users?current=1&pageSize=100&accessible=&status=1", undefined, ana);
  assert.deepEqual(
    usuarios.json.data.map((u) => u.name),
    ["ana@empresa.com", "bia@empresa.com"],
  );
  const pares = await chamar("GET", "/api/peers?current=1&pageSize=100", undefined, ana);
  const doNote = pares.json.data.find((p) => p.id === "123456789");
  assert.equal(doNote.user_name, "ana@empresa.com");
  assert.equal(doNote.info.os, "Windows 11");

  await chamar("POST", "/api/logout", { id: "123456789" }, ana);
  assert.equal((await chamar("POST", "/api/currentUser", {}, ana)).status, 401);
  assert.equal(estado.sessoes.size, 0, "sessão encerrada também na Central");
});

test("heartbeat, sysinfo, auditoria e opções de login respondem como o cliente espera", async () => {
  assert.deepEqual((await chamar("GET", "/api/login-options")).json, []);
  assert.deepEqual((await chamar("POST", "/api/heartbeat", { id: "1", uuid: "x", ver: 1 })).json, {});
  assert.equal((await chamar("POST", "/api/sysinfo", { id: "1", hostname: "PC" })).texto, "SYSINFO_UPDATED");
  assert.equal((await chamar("POST", "/api/sysinfo_ver", undefined)).texto, "1");
  assert.equal((await chamar("POST", "/api/audit/conn", { id: "1", nonce: "n1", action: "new" })).status, 200);
});

test("sem credencial da Central o login responde indisponível e o resto funciona", async () => {
  const banco = abrirBanco(":memory:");
  const semCredencial = createServer(
    criarApp({ config: { ...config, loginDesligado: true }, banco, central: {}, relogio: () => agora }),
  );
  await new Promise((r) => semCredencial.listen(0, "127.0.0.1", r));
  const url = `http://127.0.0.1:${semCredencial.address().port}`;
  const login = await fetch(`${url}/api/login`, { method: "POST", body: JSON.stringify({ username: "a@b.c", password: "x", uuid: "u" }) });
  assert.equal(login.status, 503);
  const hb = await fetch(`${url}/api/heartbeat`, { method: "POST", body: JSON.stringify({ id: "1" }) });
  assert.equal(hb.status, 200);
  semCredencial.close();
});
