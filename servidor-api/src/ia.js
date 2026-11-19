// Instaladores com IA (-ia): saem do CI só como artefato privado do workflow (zip, 30 dias). Aqui o servidor baixa o
// artefato mais recente de cada plataforma com o token do GitHub, extrai o instalador para o disco e o entrega direto,
// sem expor o link do GitHub. Quem pode ver e baixar é decidido em app.js (plano da assinatura).
import { createReadStream } from "node:fs";
import { mkdir, readdir, rename, rm, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { inflateRawSync } from "node:zlib";

const SUCESSO_MS = 10 * 60_000;
const FALHA_MS = 60_000;
const ARTEFATO = /^h3suporte-ia-(windows|macos)-([a-z0-9_]+)$/;
const INSTALADOR_IA = /^h3suporte-.+-ia\.(exe|msi|dmg|pkg)$/i;
const VERSAO = /^h3suporte-(\d+\.\d+\.\d+)/;
const LIMITE_ARQUIVO = 600 * 1024 * 1024;

/** Instaladores (nome → conteúdo) de dentro de um zip de artefato; ignora pastas e qualquer outro arquivo. */
export function extrairInstaladores(zip) {
  const fim = zip.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]), zip.length - 22);
  if (fim < 0) throw new Error("zip inválido");
  const total = zip.readUInt16LE(fim + 10);
  let p = zip.readUInt32LE(fim + 16);
  const arquivos = new Map();
  for (let i = 0; i < total; i++) {
    if (zip.readUInt32LE(p) !== 0x02014b50) throw new Error("zip inválido");
    const metodo = zip.readUInt16LE(p + 10);
    const comprimido = zip.readUInt32LE(p + 20);
    const tamanho = zip.readUInt32LE(p + 24);
    const nome = zip.toString("utf8", p + 46, p + 46 + zip.readUInt16LE(p + 28));
    const local = zip.readUInt32LE(p + 42);
    p += 46 + zip.readUInt16LE(p + 28) + zip.readUInt16LE(p + 30) + zip.readUInt16LE(p + 32);
    if (!INSTALADOR_IA.test(nome)) continue;
    if (tamanho > LIMITE_ARQUIVO) throw new Error(`${nome} grande demais`);
    if (zip.readUInt32LE(local) !== 0x04034b50) throw new Error("zip inválido");
    const inicio = local + 30 + zip.readUInt16LE(local + 26) + zip.readUInt16LE(local + 28);
    const dados = zip.subarray(inicio, inicio + comprimido);
    const conteudo = metodo === 0 ? dados : metodo === 8 ? inflateRawSync(dados) : null;
    if (!conteudo || conteudo.length !== tamanho) throw new Error(`não foi possível ler ${nome}`);
    arquivos.set(nome, conteudo);
  }
  return arquivos;
}

export function criarIa({ repo, token = "", dir, buscar = fetch, relogio = Date.now, timeoutMs = 8000 }) {
  let cache = { dados: null, ate: 0 };
  let emAndamento = null;
  const headers = { accept: "application/vnd.github+json", "user-agent": "h3suporte-servidor-api", authorization: `Bearer ${token}` };

  async function arquivosDe(pasta) {
    const lista = [];
    for (const nome of await readdir(pasta)) lista.push({ nome, tamanho: (await stat(join(pasta, nome))).size });
    return lista;
  }

  async function materializar(artefato) {
    const pasta = join(dir, String(artefato.id));
    try {
      return await arquivosDe(pasta);
    } catch (e) {
      if (e.code !== "ENOENT") throw e;
    }
    const resp = await buscar(artefato.archive_download_url, { headers, signal: AbortSignal.timeout(5 * 60_000) });
    if (!resp.ok) throw new Error(`GitHub respondeu ${resp.status} ao baixar ${artefato.name}`);
    const instaladores = extrairInstaladores(Buffer.from(await resp.arrayBuffer()));
    if (instaladores.size === 0) throw new Error(`${artefato.name} não traz instalador`);
    const temp = join(dir, `.tmp-${artefato.id}-${relogio()}`);
    await mkdir(temp, { recursive: true });
    try {
      for (const [nome, conteudo] of instaladores) await writeFile(join(temp, nome), conteudo);
      await rename(temp, pasta);
    } catch (e) {
      await rm(temp, { recursive: true, force: true });
      if (e.code !== "ENOTEMPTY" && e.code !== "EEXIST") throw e;
    }
    return arquivosDe(pasta);
  }

  async function consultar() {
    const resp = await buscar(`https://api.github.com/repos/${repo}/actions/artifacts?per_page=100`, {
      headers,
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!resp.ok) throw new Error(`GitHub respondeu ${resp.status}`);
    // Do mais novo para o mais antigo: vale o primeiro de cada nome.
    const vistos = new Map();
    for (const a of (await resp.json()).artifacts ?? []) {
      if (!a.expired && ARTEFATO.test(a.name) && !vistos.has(a.name)) vistos.set(a.name, a);
    }
    await mkdir(dir, { recursive: true });
    const instaladores = [];
    for (const a of vistos.values()) {
      const [, plataforma, arquitetura] = ARTEFATO.exec(a.name);
      try {
        const arquivos = await materializar(a);
        const nomes = arquivos.map((f) => f.nome);
        instaladores.push({
          artefato: `${plataforma}-${arquitetura}`,
          plataforma,
          arquitetura,
          versao: VERSAO.exec(nomes[0] ?? "")?.[1] ?? null,
          criadoEm: a.created_at ?? null,
          arquivos: arquivos.map((f) => ({ ...f, tipo: f.nome.split(".").pop().toLowerCase() })),
          pasta: join(dir, String(a.id)),
        });
      } catch (e) {
        console.warn(`ia: ${a.name} indisponível (${e.message})`);
      }
    }
    const manter = new Set([...vistos.values()].map((a) => String(a.id)));
    for (const nome of await readdir(dir)) if (!manter.has(nome)) await rm(join(dir, nome), { recursive: true, force: true });
    return instaladores;
  }

  /** Instaladores com IA disponíveis (um item por plataforma/arquitetura) ou [] sem artefato; null sem token. */
  async function listar() {
    if (!token) return null;
    if (relogio() < cache.ate) return cache.dados;
    emAndamento ??= consultar()
      .then((dados) => (cache = { dados, ate: relogio() + SUCESSO_MS }).dados)
      .catch((erro) => {
        console.warn(`ia: falha ao consultar o GitHub (${erro.message}); mantendo a última conhecida`);
        cache = { dados: cache.dados ?? [], ate: relogio() + FALHA_MS };
        return cache.dados;
      })
      .finally(() => (emAndamento = null));
    return emAndamento;
  }

  /** Arquivo listado → { caminho, nome, tamanho, versao }; o nome nunca vira caminho sem passar pela lista. */
  async function arquivo(artefato, nome) {
    const item = (await listar())?.find((i) => i.artefato === artefato);
    const f = item?.arquivos.find((a) => a.nome === nome);
    return f ? { caminho: join(item.pasta, f.nome), nome: f.nome, tamanho: f.tamanho, versao: item.versao } : null;
  }

  return { listar, arquivo, abrir: (caminho) => createReadStream(caminho) };
}
