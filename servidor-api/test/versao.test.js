import assert from "node:assert/strict";
import { createServer } from "node:http";
import { test } from "node:test";
import { criarApp } from "../src/app.js";
import { criarVersao } from "../src/versao.js";

const assinados = [{ name: "rustdesk-update.json" }, { name: "rustdesk-update.json.sig" }];
const github = (release, status = 200) => async () =>
  new Response(JSON.stringify(release), { status, headers: { "content-type": "application/json" } });

test("só anuncia release estável que tem a lista assinada", async () => {
  const ok = criarVersao({ repo: "h3/app", buscar: github({ tag_name: "v1.5.4", assets: assinados }) });
  assert.equal(await ok(), "https://github.com/h3/app/releases/tag/v1.5.4");

  for (const release of [
    null,
    { tag_name: "v1.5.4", assets: [{ name: "rustdesk-update.json" }] },
    { tag_name: "v1.5.3-2", assets: assinados },
    { tag_name: "v1.5.4", prerelease: true, assets: assinados },
  ]) {
    assert.equal(await criarVersao({ repo: "h3/app", buscar: github(release) })(), null, JSON.stringify(release));
  }
});

test("GitHub fora mantém a última versão conhecida", async () => {
  let agora = 0;
  let fora = false;
  const buscar = async (...a) => {
    if (fora) throw new Error("rede");
    return github({ tag_name: "v1.5.4", assets: assinados })(...a);
  };
  const ultima = criarVersao({ repo: "h3/app", buscar, relogio: () => agora });
  assert.equal(await ultima(), "https://github.com/h3/app/releases/tag/v1.5.4");
  fora = true;
  agora += 3600_000;
  assert.equal(await ultima(), "https://github.com/h3/app/releases/tag/v1.5.4");
});

test("POST /api/versao responde {url} no formato do app e 404 sem versão", async () => {
  let url = "https://github.com/h3/app/releases/tag/v1.5.4";
  const api = createServer(criarApp({ config: {}, banco: {}, central: {}, versao: async () => url }));
  await new Promise((r) => api.listen(0, "127.0.0.1", r));
  const base = `http://127.0.0.1:${api.address().port}`;
  try {
    const r = await fetch(`${base}/api/versao`, { method: "POST", body: JSON.stringify({ os: "macos", typ: "rustdesk-client" }) });
    assert.equal(r.status, 200);
    assert.deepEqual(await r.json(), { url });
    url = null;
    assert.equal((await fetch(`${base}/api/versao`)).status, 404);
  } finally {
    api.close();
  }
});
