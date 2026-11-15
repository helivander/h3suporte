import { createServer } from "node:http";
import { criarApp } from "./app.js";
import { abrirBanco } from "./banco.js";
import { criarCentral } from "./central.js";
import { lerConfig } from "./config.js";
import { criarVersao } from "./versao.js";

const config = lerConfig();
const banco = abrirBanco(config.banco);
const central = criarCentral({ url: config.central, credencial: config.credencial, timeoutMs: config.timeoutMs });
const versao = criarVersao({ repo: config.repoGithub, token: config.tokenGithub });
const servidor = createServer(criarApp({ config, banco, central, versao }));
servidor.requestTimeout = 30_000;
servidor.headersTimeout = 15_000;

banco.limpar(Date.now());
const limpeza = setInterval(() => banco.limpar(Date.now()), 6 * 3600_000);
limpeza.unref();

if (config.loginDesligado)
  console.warn("CENTRAL_CREDENCIAL ausente ou inválida: o login fica desligado até ela ser configurada.");

servidor.listen(config.porta, config.host, () => {
  console.log(`servidor-api do h3suporte em ${config.host}:${config.porta}, central ${config.central}`);
});

for (const sinal of ["SIGTERM", "SIGINT"]) {
  process.on(sinal, () => {
    servidor.close(() => {
      banco.fechar();
      process.exit(0);
    });
    setTimeout(() => process.exit(0), 5000).unref();
  });
}
