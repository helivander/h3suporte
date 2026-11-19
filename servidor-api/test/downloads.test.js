import assert from "node:assert/strict";
import { createServer } from "node:http";
import { test } from "node:test";
import { criarApp } from "../src/app.js";
import { criarDownloads } from "../src/downloads.js";

const asset = (name, size = 10) => ({ name, size, browser_download_url: `https://dl/${name}` });
const assets = [
  asset("rustdesk-update.json"),
  asset("rustdesk-update.json.sig"),
  asset("h3suporte-1.5.4-x86_64.exe"),
  asset("h3suporte-1.5.4-x86_64.msi"),
  asset("h3suporte-1.5.4-x86_64-ia.exe"),
  asset("h3suporte-1.5.4-x86_64-ia.msi"),
  asset("h3suporte-1.5.4-macos-apple-silicon.pkg"),
  asset("SHA256SUMS.txt"),
];
const github = (releases, status = 200) => async () =>
  new Response(JSON.stringify(releases), { status, headers: { "content-type": "application/json" } });

test("lista só os instaladores públicos da última versão, sem o -ia", async () => {
  const dados = await criarDownloads({ repo: "h3/app", buscar: github([{ tag_name: "v1.5.4", assets }]) })();
  assert.equal(dados.versao, "1.5.4");
  assert.deepEqual(
    dados.arquivos.map((a) => [a.nome, a.plataforma, a.tipo]),
    [
      ["h3suporte-1.5.4-x86_64.exe", "windows", "exe"],
      ["h3suporte-1.5.4-x86_64.msi", "windows", "msi"],
      ["h3suporte-1.5.4-macos-apple-silicon.pkg", "macos", "pkg"],
    ],
  );
  assert.equal(dados.arquivos[0].url, "https://dl/h3suporte-1.5.4-x86_64.exe");
});

test("vale o pré-lançamento mais recente com instaladores, sem exigir a lista assinada", async () => {
  const dados = await criarDownloads({
    repo: "h3/app",
    buscar: github([
      { tag_name: "v1.5.3-14", draft: true, assets },
      { tag_name: "v1.5.3-13", prerelease: true, assets: [asset("h3suporte-1.5.3-x86_64.exe"), asset("h3suporte-1.5.3-x86_64.dmg")] },
      { tag_name: "v1.5.3-12", prerelease: true, assets },
    ]),
  })();
  assert.equal(dados.versao, "1.5.3-13");
  assert.deepEqual(dados.arquivos.map((a) => a.nome), ["h3suporte-1.5.3-x86_64.exe", "h3suporte-1.5.3-x86_64.dmg"]);
});

test("sem release com instaladores não há downloads", async () => {
  for (const releases of [
    [],
    [{ tag_name: "v1.5.3-8", prerelease: true, assets: [asset("rustdesk.sbom.json")] }],
    [{ tag_name: "v1.5.4", draft: true, assets }],
    [{ tag_name: "nightly", assets }],
  ]) {
    assert.equal(await criarDownloads({ repo: "h3/app", buscar: github(releases) })(), null);
  }
});

test("GET /api/downloads responde os dados e 404 sem versão", async () => {
  let dados = { versao: "1.5.4", arquivos: [] };
  const api = createServer(criarApp({ config: {}, banco: {}, central: {}, downloads: async () => dados }));
  await new Promise((r) => api.listen(0, "127.0.0.1", r));
  const base = `http://127.0.0.1:${api.address().port}`;
  try {
    const r = await fetch(`${base}/api/downloads`);
    assert.equal(r.status, 200);
    assert.deepEqual(await r.json(), dados);
    dados = null;
    assert.equal((await fetch(`${base}/api/downloads`)).status, 404);
  } finally {
    api.close();
  }
});
