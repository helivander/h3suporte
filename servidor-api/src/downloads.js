// Instaladores da última versão estável, para a Central montar os links de download sem ficar velha.
// Mesmo critério do atualizador (versao.js): release estável com a lista assinada. O build com IA (-ia)
// nunca é listado: ele é só para o administrador e não vai para o release público.
const SUCESSO_MS = 10 * 60_000;
const FALHA_MS = 60_000;
const TAG_ESTAVEL = /^v\d+\.\d+\.\d+$/;
const ARQUIVOS_ASSINADOS = ["rustdesk-update.json", "rustdesk-update.json.sig"];
const PLATAFORMAS = { exe: "windows", msi: "windows", dmg: "macos", pkg: "macos", deb: "linux", rpm: "linux", apk: "android" };
const INSTALADOR = /^h3suporte-.+\.(exe|msi|dmg|pkg|deb|rpm|apk)$/i;
const COM_IA = /-ia\.[a-z]+$/i;

export function criarDownloads({ repo, token = "", buscar = fetch, relogio = Date.now, timeoutMs = 8000 }) {
  let cache = { dados: null, ate: 0 };
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
    const assets = release.assets ?? [];
    const nomes = new Set(assets.map((a) => a.name));
    const pronto =
      !release.draft &&
      !release.prerelease &&
      TAG_ESTAVEL.test(release.tag_name ?? "") &&
      ARQUIVOS_ASSINADOS.every((n) => nomes.has(n));
    if (!pronto) return null;
    const arquivos = assets
      .filter((a) => INSTALADOR.test(a.name) && !COM_IA.test(a.name) && a.browser_download_url)
      .map((a) => ({
        nome: a.name,
        plataforma: PLATAFORMAS[a.name.split(".").pop().toLowerCase()],
        tipo: a.name.split(".").pop().toLowerCase(),
        tamanho: a.size ?? null,
        url: a.browser_download_url,
      }));
    return {
      versao: release.tag_name.slice(1),
      tag: release.tag_name,
      publicadoEm: release.published_at ?? null,
      pagina: `https://github.com/${repo}/releases/tag/${release.tag_name}`,
      arquivos,
    };
  }

  /** Dados da última versão estável ou null quando não há versão publicada. */
  return async function ultima() {
    if (relogio() < cache.ate) return cache.dados;
    emAndamento ??= consultar()
      .then((dados) => (cache = { dados, ate: relogio() + SUCESSO_MS }).dados)
      .catch((erro) => {
        console.warn(`downloads: falha ao consultar o GitHub (${erro.message}); mantendo a última conhecida`);
        cache = { dados: cache.dados, ate: relogio() + FALHA_MS };
        return cache.dados;
      })
      .finally(() => (emAndamento = null));
    return emAndamento;
  };
}
