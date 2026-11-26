// Última versão do H3 Suporte para o atualizador do app: o release estável mais recente do GitHub
// que já tem a lista assinada (rustdesk-update.json + .sig). Pré-releases (builds de teste) ficam de fora.
const SUCESSO_MS = 10 * 60_000;
const FALHA_MS = 60_000;
const TAG_ESTAVEL = /^v\d+\.\d+\.\d+$/;
const ARQUIVOS_ASSINADOS = ["rustdesk-update.json", "rustdesk-update.json.sig"];

export function criarVersao({ repo, token = "", buscar = fetch, relogio = Date.now, timeoutMs = 8000 }) {
  let cache = { url: null, ate: 0 };
  let emAndamento = null;

  async function consultar() {
    const headers = { accept: "application/vnd.github+json", "user-agent": "h3suporte-servidor-api" };
    if (token) headers.authorization = `Bearer ${token}`;
    const resp = await buscar(`https://api.github.com/repos/${repo}/releases/latest`, {
      headers,
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (resp.status === 404) return null;
    if (!resp.ok) throw new Error(`GitHub respondeu ${resp.status}`);
    const release = await resp.json();
    if (!release || typeof release !== "object") return null;
    const nomes = new Set((release.assets ?? []).map((a) => a.name));
    const pronto =
      !release.draft &&
      !release.prerelease &&
      TAG_ESTAVEL.test(release.tag_name ?? "") &&
      ARQUIVOS_ASSINADOS.every((n) => nomes.has(n));
    return pronto ? `https://github.com/${repo}/releases/tag/${release.tag_name}` : null;
  }

  /** URL da página do release (o formato que o app espera) ou null quando não há versão publicada. */
  return async function ultima() {
    if (relogio() < cache.ate) return cache.url;
    emAndamento ??= consultar()
      .then((url) => (cache = { url, ate: relogio() + SUCESSO_MS }).url)
      .catch((erro) => {
        console.warn(`versão: falha ao consultar o GitHub (${erro.message}); mantendo a última conhecida`);
        cache = { url: cache.url, ate: relogio() + FALHA_MS };
        return cache.url;
      })
      .finally(() => (emAndamento = null));
    return emAndamento;
  };
}
