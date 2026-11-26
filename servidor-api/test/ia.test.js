import assert from "node:assert/strict";
import { createServer } from "node:http";
import { mkdtemp, readdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { deflateRawSync } from "node:zlib";
import { criarApp } from "../src/app.js";
import { criarIa, extrairInstaladores } from "../src/ia.js";

/** Zip mínimo (deflate) só para os testes. */
function zip(arquivos) {
  const locais = [];
  const centrais = [];
  let deslocamento = 0;
  for (const [nome, conteudo] of Object.entries(arquivos)) {
    const comprimido = deflateRawSync(conteudo);
    const n = Buffer.from(nome);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(8, 8);
    local.writeUInt32LE(comprimido.length, 18);
    local.writeUInt32LE(conteudo.length, 22);
    local.writeUInt16LE(n.length, 26);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(8, 10);
    central.writeUInt32LE(comprimido.length, 20);
    central.writeUInt32LE(conteudo.length, 24);
    central.writeUInt16LE(n.length, 28);
    central.writeUInt32LE(deslocamento, 42);
    locais.push(local, n, comprimido);
    centrais.push(central, n);
    deslocamento += 30 + n.length + comprimido.length;
  }
  const cd = Buffer.concat(centrais);
  const fim = Buffer.alloc(22);
  fim.writeUInt32LE(0x06054b50, 0);
  fim.writeUInt16LE(Object.keys(arquivos).length, 10);
  fim.writeUInt32LE(cd.length, 12);
  fim.writeUInt32LE(deslocamento, 16);
  return Buffer.concat([...locais, cd, fim]);
}

const EXE = Buffer.from("conteudo do exe com ia ".repeat(50));
const artefatos = (expirado = false) => ({
  artifacts: [
    { id: 7, name: "h3suporte-ia-windows-x86_64", expired: expirado, archive_download_url: "https://api/zip/7", created_at: "2026-11-18T00:00:00Z" },
    { id: 3, name: "h3suporte-ia-windows-x86_64", expired: false, archive_download_url: "https://api/zip/3", created_at: "2026-11-01T00:00:00Z" },
    { id: 9, name: "rustdesk-unsigned-windows-x86_64-ia", expired: false, archive_download_url: "https://api/zip/9" },
  ],
});
const github = (baixados = []) => async (url, { headers }) => {
  assert.equal(headers.authorization, "Bearer tk");
  if (url.includes("/actions/artifacts")) return Response.json(artefatos());
  baixados.push(url);
  return new Response(zip({ "h3suporte-1.5.4-x86_64-ia.exe": EXE, "LEIAME.txt": Buffer.from("x") }));
};

test("extrai só os instaladores -ia de dentro do zip", () => {
  const achados = extrairInstaladores(zip({ "h3suporte-1.5.4-x86_64-ia.msi": EXE, "outro.txt": EXE, "../h3suporte-x-ia.exe": EXE }));
  assert.deepEqual([...achados.keys()], ["h3suporte-1.5.4-x86_64-ia.msi"]);
  assert.deepEqual(achados.get("h3suporte-1.5.4-x86_64-ia.msi"), EXE);
});

test("rejeita zips malformados ou truncados sem RangeError", () => {
  const valido = zip({ "h3suporte-1.5.4-x86_64-ia.exe": EXE });
  const fim = valido.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));

  const cdFora = Buffer.from(valido);
  cdFora.writeUInt32LE(valido.length + 100, fim + 16);

  const localFora = Buffer.from(valido);
  const cdOffset = valido.readUInt32LE(fim + 16);
  localFora.writeUInt32LE(valido.length + 100, cdOffset + 42);

  const dadosTruncados = Buffer.from(valido);
  dadosTruncados.writeUInt32LE(valido.length + 100, cdOffset + 20);

  for (const ruim of [Buffer.alloc(0), Buffer.alloc(10), valido.subarray(0, fim + 10), cdFora, localFora, dadosTruncados]) {
    assert.throws(() => extrairInstaladores(ruim), (err) => !(err instanceof RangeError) && /zip inválido/.test(err.message));
  }
});

test("baixa o artefato mais recente, extrai para o disco e não baixa de novo", async () => {
  const baixados = [];
  const ia = criarIa({ repo: "h3/app", token: "tk", dir: await mkdtemp(join(tmpdir(), "ia-")), buscar: github(baixados) });
  const [item] = await ia.listar();
  assert.deepEqual([item.artefato, item.versao], ["windows-x86_64", "1.5.4"]);
  assert.deepEqual(item.arquivos.map((a) => [a.nome, a.tipo, a.tamanho]), [["h3suporte-1.5.4-x86_64-ia.exe", "exe", EXE.length]]);
  assert.deepEqual(baixados, ["https://api/zip/7"]);
  assert.equal(await ia.arquivo("windows-x86_64", "../x"), null);
  assert.equal((await ia.arquivo("windows-x86_64", "h3suporte-1.5.4-x86_64-ia.exe")).tamanho, EXE.length);
});

test("sem token a função fica desligada", async () => {
  assert.equal(await criarIa({ repo: "h3/app", dir: "x", buscar: async () => assert.fail() }).listar(), null);
});

async function servidor(plano) {
  const auditoria = [];
  const sessao = { conta: { id: 1, email: "a@b.c" }, assinatura: { id: 1, plano: { nome: plano } }, validadaEm: Date.now() };
  const banco = { lerSessao: (h) => (h ? sessao : null), registrarAuditoria: (a) => auditoria.push(a) };
  const ia = criarIa({ repo: "h3/app", token: "tk", dir: await mkdtemp(join(tmpdir(), "ia-")), buscar: github() });
  const api = createServer(criarApp({ config: { revalidarMs: 1e12 }, banco, central: {}, ia }));
  await new Promise((r) => api.listen(0, "127.0.0.1", r));
  return { api, auditoria, base: `http://127.0.0.1:${api.address().port}` };
}
const auth = { authorization: "Bearer abc" };

test("plano DEV lista e baixa o instalador direto, com auditoria", async () => {
  const { api, auditoria, base } = await servidor("dev");
  try {
    const lista = await (await fetch(`${base}/api/downloads-ia`, { headers: auth })).json();
    assert.equal(lista.arquivos.length, 1);
    assert.equal(lista.arquivos[0].url, "/api/downloads-ia/windows-x86_64/h3suporte-1.5.4-x86_64-ia.exe");
    const r = await fetch(base + lista.arquivos[0].url, { headers: auth });
    assert.equal(r.status, 200);
    assert.match(r.headers.get("content-disposition"), /h3suporte-1\.5\.4-x86_64-ia\.exe/);
    assert.deepEqual(Buffer.from(await r.arrayBuffer()), EXE);
    assert.equal(auditoria[0].tipo, "download_ia");
    assert.equal((await fetch(`${base}/api/downloads-ia/windows-x86_64/outro.exe`, { headers: auth })).status, 404);
  } finally {
    api.close();
  }
});

test("outro plano, ou sem login, não vê nem baixa", async () => {
  const { api, base } = await servidor("Básico");
  try {
    for (const u of ["/api/downloads-ia", "/api/downloads-ia/windows-x86_64/h3suporte-1.5.4-x86_64-ia.exe"]) {
      assert.equal((await fetch(base + u, { headers: auth })).status, 404);
      assert.equal((await fetch(base + u)).status, 401);
    }
  } finally {
    api.close();
  }
});
