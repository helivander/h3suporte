const numero = (valor, padrao) => {
  const n = Number(valor);
  return valor !== undefined && valor !== "" && Number.isFinite(n) && n >= 0 ? n : padrao;
};

export function lerConfig(env = process.env) {
  const central = (env.CENTRAL_URL ?? "").trim().replace(/\/+$/, "");
  const credencial = (env.CENTRAL_CREDENCIAL ?? "").trim();
  if (!central || !credencial) {
    throw new Error("Defina CENTRAL_URL e CENTRAL_CREDENCIAL (veja .env.example).");
  }
  if (!central.startsWith("https://") && env.PERMITIR_HTTP !== "1") {
    throw new Error("CENTRAL_URL precisa ser https:// (PERMITIR_HTTP=1 só em desenvolvimento).");
  }
  return {
    host: env.HOST || "0.0.0.0",
    porta: numero(env.PORTA, 21114),
    banco: env.BANCO || "dados/h3suporte.db",
    central,
    credencial,
    timeoutMs: numero(env.CENTRAL_TIMEOUT_MS, 8000),
    revalidarMs: numero(env.REVALIDAR_SEG, 300) * 1000,
    toleranciaMs: numero(env.TOLERANCIA_HORAS, 72) * 3600_000,
    confiarProxy: env.CONFIAR_PROXY === "1",
  };
}
