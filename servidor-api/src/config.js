const numero = (valor, padrao) => {
  if (valor === undefined || String(valor).trim() === "") return padrao;
  const n = Number(valor);
  return Number.isFinite(n) && n >= 0 ? n : padrao;
};

/** Chave AES-256 das senhas dos dispositivos: 64 caracteres hex ou 32 bytes em base64. Vazia = recurso desligado. */
function lerChave(valor) {
  const v = (valor ?? "").trim();
  if (!v) return null;
  let chave;
  if (/^[0-9a-fA-F]{64}$/.test(v)) {
    chave = Buffer.from(v, "hex");
  } else if (/^[A-Za-z0-9+/]+={0,2}$/.test(v)) {
    chave = Buffer.from(v, "base64");
  } else {
    throw new Error("CHAVE_DISPOSITIVOS precisa ter 32 bytes (64 caracteres hex ou base64).");
  }
  if (chave.length !== 32) throw new Error("CHAVE_DISPOSITIVOS precisa ter 32 bytes (64 caracteres hex ou base64).");
  return chave;
}

export function lerConfig(env = process.env) {
  const central = (env.CENTRAL_URL ?? "").trim().replace(/\/+$/, "");
  const credencial = (env.CENTRAL_CREDENCIAL ?? "").trim();
  if (!central) throw new Error("Defina CENTRAL_URL (veja .env.example).");
  let urlCentral;
  try {
    urlCentral = new URL(central);
  } catch {
    throw new Error("CENTRAL_URL inválida.");
  }
  if (urlCentral.protocol !== "https:" && !(env.PERMITIR_HTTP === "1" && urlCentral.protocol === "http:")) {
    throw new Error("CENTRAL_URL precisa ser https:// (PERMITIR_HTTP=1 só em desenvolvimento).");
  }
  return {
    host: env.HOST || "0.0.0.0",
    porta: numero(env.PORTA, 21114),
    banco: env.BANCO || "dados/h3suporte.db",
    central,
    credencial,
    // Sem credencial o serviço sobe (saúde, heartbeat), mas o login responde "indisponível".
    loginDesligado: !credencial.startsWith("sva_"),
    timeoutMs: numero(env.CENTRAL_TIMEOUT_MS, 8000),
    revalidarMs: numero(env.REVALIDAR_SEG, 300) * 1000,
    toleranciaMs: numero(env.TOLERANCIA_HORAS, 72) * 3600_000,
    confiarProxy: env.CONFIAR_PROXY === "1",
    // Cifra as senhas guardadas em "Meus dispositivos". Sem a chave, essas rotas respondem "indisponível".
    chaveDispositivos: lerChave(env.CHAVE_DISPOSITIVOS),
    // Releases do app para o atualizador; o token é opcional (só aumenta o limite de consultas ao GitHub).
    repoGithub: (env.GITHUB_REPO || "helivander/h3suporte").trim(),
    tokenGithub: (env.GITHUB_TOKEN ?? "").trim(),
    // Instaladores com IA: quem os vê (nomes dos planos, separados por vírgula) e onde ficam extraídos. Precisa de
    // GITHUB_TOKEN com leitura de Actions para baixar os artefatos do workflow.
    planosIa: (env.PLANOS_IA || "DEV").split(",").map((p) => p.trim().toLowerCase()).filter(Boolean),
    dirIa: env.DIR_IA || "dados/ia",
  };
}
