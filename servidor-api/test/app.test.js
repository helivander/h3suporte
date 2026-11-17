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
const config = { revalidarMs: 300_000, toleranciaMs: 72 * 3600_000, confiarProxy: false, chaveDispositivos: Buffer.alloc(32, 7) };

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

test("Central fora com pagoAte futuro mantém a sessão só até pagoAte", async () => {
  estado.assinatura.pagoAte = new Date(agora + 3600_000).toISOString();
  const token = (await loginAna()).json.access_token;
  estado.fora = true;
  agora += config.revalidarMs;
  assert.equal((await chamar("POST", "/api/currentUser", {}, token)).status, 200, "antes de pagoAte");
  agora += 3600_000;
  assert.equal((await chamar("POST", "/api/currentUser", {}, token)).status, 401, "depois de pagoAte, mesmo dentro da tolerância");
});

test("Central fora com pagoAte já vencido corta a sessão", async () => {
  const token = (await loginAna()).json.access_token;
  estado.assinatura.pagoAte = new Date(agora - 1000).toISOString();
  estado.fora = false;
  agora += config.revalidarMs;
  assert.equal((await chamar("POST", "/api/currentUser", {}, token)).status, 200, "Central responde e vale");
  estado.fora = true;
  agora += config.revalidarMs;
  assert.equal((await chamar("POST", "/api/currentUser", {}, token)).status, 401);
});

test("Central fora com pagoAte nulo (provedor) segue a tolerância de 72 h", async () => {
  estado.assinatura.pagoAte = null;
  const token = (await loginAna()).json.access_token;
  estado.fora = true;
  agora += config.revalidarMs;
  assert.equal((await chamar("POST", "/api/currentUser", {}, token)).status, 200);
  agora += config.toleranciaMs;
  assert.equal((await chamar("POST", "/api/currentUser", {}, token)).status, 503);
});

test("limite de acessos simultâneos do plano: recusa o que passa, libera ao fechar e ao expirar", async () => {
  estado.assinatura.limiteAcessos = 2;
  const token = (await loginAna()).json.access_token;
  const abrir = (id, peer) => chamar("POST", "/api/acessos/abrir", { id, peer }, token);
  assert.deepEqual((await abrir("a1", "111")).json, { limite: 2, em_uso: 1 });
  assert.equal((await abrir("a2", "111")).json.em_uso, 1, "outra janela no mesmo computador não conta de novo");
  assert.equal((await abrir("a3", "222")).status, 200);
  const recusado = await abrir("a4", "333");
  assert.equal(recusado.status, 409);
  assert.match(recusado.json.error, /2 acessos remotos ao mesmo tempo/);
  assert.equal((await abrir("a1", "111")).status, 200, "renovar um acesso aberto sempre passa");
  await chamar("POST", "/api/acessos/fechar", { id: "a3" }, token);
  assert.equal((await abrir("a4", "333")).status, 200, "fechar libera a vaga");
  assert.equal((await abrir("a5", "444")).status, 409);
  agora += 150_000;
  assert.equal((await abrir("a5", "444")).status, 200, "acesso sem renovação expira");
  assert.equal((await chamar("POST", "/api/acessos/abrir", { id: "x", peer: "1" })).status, 401, "exige login");
});

test("plano sem limite de acessos (campo ausente) não recusa", async () => {
  const token = (await loginAna()).json.access_token;
  for (const n of [1, 2, 3, 4, 5]) {
    const r = await chamar("POST", "/api/acessos/abrir", { id: `s${n}`, peer: `9${n}` }, token);
    assert.equal(r.status, 200);
    assert.equal(r.json.limite, null);
  }
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

test("meus dispositivos: registra ID e senha na conta, lista sem a senha e entrega a senha de um dispositivo por vez", async () => {
  const ana = (await loginAna()).json.access_token;

  assert.equal((await chamar("GET", "/api/dispositivos-conta")).status, 401, "sem login não lista");
  const salvo = await chamar("POST", "/api/dispositivos-conta", { id: "555111222", nome: "PC-FINANCEIRO", so: "windows", senha: "Segredo123" }, ana);
  assert.equal(salvo.status, 200);

  const lista = await chamar("GET", "/api/dispositivos-conta", undefined, ana);
  assert.equal(lista.json.total, 1);
  assert.deepEqual(
    { id: lista.json.data[0].id, nome: lista.json.data[0].nome, so: lista.json.data[0].so, online: lista.json.data[0].online },
    { id: "555111222", nome: "PC-FINANCEIRO", so: "windows", online: false },
  );
  assert.ok(!lista.texto.includes("Segredo123"), "a lista nunca traz a senha");

  await chamar("POST", "/api/sysinfo", { id: "555111222", hostname: "PC-FINANCEIRO" });
  await chamar("POST", "/api/heartbeat", { id: "555111222" });
  assert.equal((await chamar("GET", "/api/dispositivos-conta", undefined, ana)).json.data[0].online, true);

  assert.equal((await chamar("POST", "/api/dispositivos-conta/senha", { id: "555111222" }, ana)).json.senha, "Segredo123");
  assert.equal((await chamar("POST", "/api/dispositivos-conta/senha", { id: "000" }, ana)).status, 404);

  // Registrar de novo troca a senha e mantém o nome.
  await chamar("POST", "/api/dispositivos-conta", { id: "555111222", senha: "Outra456" }, ana);
  const de = await chamar("POST", "/api/dispositivos-conta/senha", { id: "555111222" }, ana);
  assert.equal(de.json.senha, "Outra456");
  assert.equal((await chamar("GET", "/api/dispositivos-conta", undefined, ana)).json.data[0].nome, "PC-FINANCEIRO");

  assert.equal((await chamar("POST", "/api/dispositivos-conta/remover", { id: "555111222" }, ana)).status, 200);
  assert.equal((await chamar("GET", "/api/dispositivos-conta", undefined, ana)).json.total, 0);
});

test("meus dispositivos: cada conta só vê e lê os seus, e a senha fica cifrada no banco", async () => {
  const banco = abrirBanco(":memory:");
  const chave = Buffer.alloc(32, 9);
  const cliente = criarCentral({ url: `http://127.0.0.1:${central.address().port}/api`, credencial: "sva_teste", timeoutMs: 2000 });
  const outra = createServer(criarApp({ config: { ...config, chaveDispositivos: chave }, banco, central: cliente, relogio: () => agora }));
  await new Promise((r) => outra.listen(0, "127.0.0.1", r));
  const url = `http://127.0.0.1:${outra.address().port}`;
  const post = async (caminho, corpo, token) =>
    (await fetch(url + caminho, { method: "POST", headers: { authorization: `Bearer ${token}` }, body: JSON.stringify(corpo) }));
  const entrar = async (email, senha) =>
    (await (await fetch(url + "/api/login", { method: "POST", body: JSON.stringify({ username: email, password: senha, uuid: email }) })).json()).access_token;
  const ana = await entrar("ana@empresa.com", "senha-da-ana-123");
  estado.contas[1].totp = undefined;
  const bia = await entrar("bia@empresa.com", "senha-da-bia-123");

  assert.equal((await post("/api/dispositivos-conta", { id: "777", senha: "SoDaAna1" }, ana)).status, 200);
  assert.equal((await post("/api/dispositivos-conta/senha", { id: "777" }, bia)).status, 404, "outra conta não lê");
  assert.equal((await post("/api/dispositivos-conta/remover", { id: "777" }, bia)).status, 404, "outra conta não remove");
  const guardada = banco.senhaDoDispositivoConta("c1", "777");
  assert.ok(guardada.startsWith("v1:") && !guardada.includes("SoDaAna1"));
  // Linha copiada para outro dispositivo/conta não decifra (o contexto entra na autenticação).
  banco.salvarDispositivoConta({ contaId: "c1", id: "888", senha: guardada }, agora);
  assert.equal((await post("/api/dispositivos-conta/senha", { id: "888" }, ana)).status, 500);
  outra.close();
});

test("meus dispositivos: sem a chave de cifra o recurso responde indisponível", async () => {
  const banco = abrirBanco(":memory:");
  const cliente = criarCentral({ url: `http://127.0.0.1:${central.address().port}/api`, credencial: "sva_teste", timeoutMs: 2000 });
  const semChave = createServer(criarApp({ config: { ...config, chaveDispositivos: null }, banco, central: cliente, relogio: () => agora }));
  await new Promise((r) => semChave.listen(0, "127.0.0.1", r));
  const url = `http://127.0.0.1:${semChave.address().port}`;
  const login = await (await fetch(url + "/api/login", { method: "POST", body: JSON.stringify({ username: "ana@empresa.com", password: "senha-da-ana-123", uuid: "u" }) })).json();
  const r = await fetch(url + "/api/dispositivos-conta", { headers: { authorization: `Bearer ${login.access_token}` } });
  assert.equal(r.status, 503);
  semChave.close();
});
