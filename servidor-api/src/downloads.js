// Instaladores da última versão publicada, para a Central montar os links de download sem ficar velha.
// Diferente do atualizador (versao.js), que exige release estável com a lista assinada, aqui vale o release mais recente
// que não seja rascunho e tenha instaladores (os releases do CI saem como pré-lançamento, ex.: v1.5.3-13). O build com IA
// (-ia) nunca é listado: ele é só para o administrador e não vai para o release público.
const SUCESSO_MS = 10 * 60_000;
const FALHA_MS = 60_000;
const TAG_VERSAO = /^v\d+\.\d+\.\d+(-\d+)?$/;
const PLATAFORMAS = { exe: "windows", msi: "windows", dmg: "macos", pkg: "macos", deb: "linux", rpm: "linux", apk: "android" };
const INSTALADOR = /^h3suporte-.+\.(exe|msi|dmg|pkg|deb|rpm|apk)$/i;
const COM_IA = /-ia\.[a-z]+$/i;

export function criarDownloads({ repo, token = "", buscar = fetch, relogio = Date.now, timeoutMs = 8000 }) {
  let cache = { dados: null, ate: 0 };
  let emAndamento = null;

  async function consultar() {
    const headers = { accept: "application/vnd.github+json", "user-agent": "h3suporte-servidor-api" };
    if (token) headers.authorization = `Bearer ${token}`;
    const resp = await buscar(`https://api.github.com/repos/${repo}/releases?per_page=15`, {
      headers,
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (resp.status === 404) return null;
    if (!resp.ok) throw new Error(`GitHub respondeu ${resp.status}`);
    const instaladores = (release) =>
      (release.assets ?? []).filter((a) => INSTALADOR.test(a.name) && !COM_IA.test(a.name) && a.browser_download_url);
    // A API lista do mais novo para o mais antigo.
    const lista = await resp.json();
    const release = (Array.isArray(lista) ? lista : []).find(
      (r) => !r.draft && TAG_VERSAO.test(r.tag_name ?? "") && instaladores(r).length > 0,
    );
    if (!release) return null;
    const arquivos = instaladores(release).map((a) => ({
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
