import { createHash } from "node:crypto";
import { ErroCentral } from "./central.js";

const KB = 1024;
const LIMITE_CORPO = 64 * KB;
const LIMITE_CATALOGO = 2048 * KB;
const EQUIPE_CACHE_MS = 60_000;
const VISTO_INTERVALO_MS = 60_000;

const MENSAGENS = {
  CREDENCIAIS_INVALIDAS: "E-mail ou senha incorretos.",
  TOTP_INVALIDO: "Código de verificação incorreto.",
  TOTP_NAO_CONFIGURADO:
    "Sua assinatura exige verificação em duas etapas. Configure-a no portal do assinante antes de entrar.",
  CONTA_DESATIVADA: "Sua conta foi desativada pelo responsável pela assinatura.",
  CONTA_BLOQUEADA: "Conta bloqueada por tentativas erradas. Tente de novo em alguns minutos.",
  ASSINATURA_INATIVA: "A assinatura do H3 Suporte não está ativa. Fale com o responsável pela assinatura.",
  LIMITE_DISPOSITIVOS:
    "O limite de computadores do plano foi atingido. Peça ao responsável para liberar uma vaga no portal do assinante.",
  MUITAS_TENTATIVAS: "Muitas tentativas. Aguarde alguns minutos e tente de novo.",
  CENTRAL_FORA: "Não foi possível falar com a central de licenças. Tente de novo em instantes.",
};

const hash = (texto) => createHash("sha256").update(texto).digest("hex");

class ErroHttp extends Error {
  constructor(status, mensagem) {
    super(mensagem);
    this.status = status;
  }
}

/** Janela fixa em memória: `consumir(chave)` devolve false quando passou do limite. */
function criarLimite(maximo, janelaMs) {
  const contagem = new Map();
  return {
    consumir(chave, agora) {
      const atual = contagem.get(chave);
      if (!atual || atual.ate <= agora) {
        if (contagem.size > 50_000) {
          for (const [k, v] of contagem) if (v.ate <= agora) contagem.delete(k);
        }
        contagem.set(chave, { n: 1, ate: agora + janelaMs });
        return true;
      }
      atual.n += 1;
      return atual.n <= maximo;
    },
  };
}

function lerCorpo(req, limite) {
  return new Promise((resolve, reject) => {
    const partes = [];
    let tamanho = 0;
    req.on("data", (parte) => {
      tamanho += parte.length;
      if (tamanho > limite) {
        reject(new ErroHttp(413, "Requisição grande demais."));
        req.destroy();
        return;
      }
      partes.push(parte);
    });
    req.on("end", () => resolve(Buffer.concat(partes).toString("utf8")));
    req.on("error", reject);
  });
}

async function lerJson(req, limite = LIMITE_CORPO) {
  const texto = await lerCorpo(req, limite);
  if (!texto.trim()) return {};
  try {
    const v = JSON.parse(texto);
    return v && typeof v === "object" && !Array.isArray(v) ? v : {};
  } catch {
    throw new ErroHttp(400, "JSON inválido.");
  }
}

function enviar(res, status, corpo) {
  const texto = typeof corpo === "string" ? corpo : JSON.stringify(corpo);
  res.writeHead(status, {
    "content-type": typeof corpo === "string" ? "text/plain; charset=utf-8" : "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  res.end(texto);
}

const erro = (res, status, mensagem) => enviar(res, status, { error: mensagem });

/** Usuário no formato `UserPayload` do cliente (flutter/lib/common/hbbs/hbbs.dart). */
const usuario = (conta) => ({
  name: conta.email,
  display_name: conta.nome ?? "",
  email: conta.email,
  note: "",
  status: conta.ativo === false ? 0 : 1,
  is_admin: false,
});

function paginar(url, lista) {
  const atual = Math.max(1, Number(url.searchParams.get("current")) || 1);
  const tamanho = Math.min(100, Math.max(1, Number(url.searchParams.get("pageSize")) || 100));
  return { total: lista.length, data: lista.slice((atual - 1) * tamanho, atual * tamanho) };
}

const texto = (v, max) => (typeof v === "string" && v.trim() ? v.trim().slice(0, max) : null);

/**
 * Handler HTTP com as rotas que o cliente h3suporte (RustDesk) chama no "servidor de API".
 * Contas, senhas e assinaturas ficam na Central; aqui ficam só o catálogo de endereços,
 * os dispositivos e a auditoria.
 */
export function criarApp({ config, banco, central, versao = async () => null, relogio = Date.now }) {
  const limiteLogin = criarLimite(10, 60_000);
  const limiteAuditoria = criarLimite(120, 60_000);
  const validando = new Map();
  const equipes = new Map();
  const vistos = new Map();

  const ipDe = (req) => {
    if (config.confiarProxy) {
      const encaminhado = req.headers["x-forwarded-for"];
      if (typeof encaminhado === "string" && encaminhado.trim()) return encaminhado.split(",")[0].trim();
    }
    return req.socket.remoteAddress ?? "";
  };

  const tokenDe = (req) => {
    const m = /^Bearer\s+(\S+)$/i.exec(req.headers.authorization ?? "");
    return m ? m[1] : null;
  };

  async function revalidar(token, tokenHash, sessao) {
    const agora = relogio();
    try {
      const r = await central.validar(token);
      if (r?.valida === true && r.conta && r.assinatura) {
        banco.salvarSessao(tokenHash, r, agora);
        return { conta: r.conta, assinatura: r.assinatura, validadaEm: agora };
      }
      if (r?.valida === false) {
        banco.apagarSessao(tokenHash);
        return null;
      }
    } catch {
      // Central fora, credencial do serviço recusada ou resposta inesperada: não derruba ninguém.
    }
    if (agora - sessao.validadaEm < config.toleranciaMs) return sessao;
    throw new ErroHttp(503, MENSAGENS.CENTRAL_FORA);
  }

  /** Sessão válida ou `ErroHttp` 401/503. Revalida na Central a cada `revalidarMs`. */
  async function autenticar(req) {
    const token = tokenDe(req);
    if (!token) throw new ErroHttp(401, "Faça login.");
    const tokenHash = hash(token);
    const sessao = banco.lerSessao(tokenHash);
    if (!sessao) throw new ErroHttp(401, "Sessão expirada. Faça login de novo.");
    let atual = sessao;
    if (relogio() - sessao.validadaEm >= config.revalidarMs) {
      let pendente = validando.get(tokenHash);
      if (!pendente) {
        pendente = revalidar(token, tokenHash, sessao).finally(() => validando.delete(tokenHash));
        validando.set(tokenHash, pendente);
      }
      atual = await pendente;
    }
    if (!atual) throw new ErroHttp(401, "Sessão encerrada. Faça login de novo.");
    return { token, tokenHash, ...atual };
  }

  function vincular(corpo, sessao) {
    const id = texto(corpo.id, 64);
    if (!id) return;
    banco.vincularDispositivo(
      {
        id,
        uuid: texto(corpo.uuid, 128),
        nome: texto(corpo.deviceInfo?.name, 120),
        so: texto(corpo.deviceInfo?.os, 120),
        contaId: sessao.conta.id,
        assinaturaId: sessao.assinatura.id,
      },
      relogio(),
    );
  }

  async function login(req, res) {
    const corpo = await lerJson(req);
    if (config.loginDesligado) return erro(res, 503, "Login indisponível no momento. Avise o suporte da H3.");
    const ip = ipDe(req);
    if (!limiteLogin.consumir(ip, relogio())) return erro(res, 429, MENSAGENS.MUITAS_TENTATIVAS);
    const uuid = texto(corpo.uuid, 256);
    if (!uuid) return erro(res, 400, "Dispositivo sem identificação. Atualize o H3 Suporte.");
    const base = {
      dispositivoId: `h3s-${hash(uuid).slice(0, 48)}`,
      rotulo: texto(corpo.deviceInfo?.name, 80) ?? texto(corpo.id, 80) ?? undefined,
    };
    const codigo = texto(corpo.tfaCode, 32) ?? texto(corpo.verificationCode, 32);
    const email = texto(corpo.username, 254)?.toLowerCase();
    let pedido;
    if (texto(corpo.secret, 512) && codigo) {
      pedido = { ...base, desafio: corpo.secret.trim(), codigoTotp: codigo };
    } else {
      if (!email || typeof corpo.password !== "string" || !corpo.password) {
        return erro(res, 400, "Informe e-mail e senha.");
      }
      pedido = { ...base, email, senha: corpo.password };
    }
    try {
      const r = await central.entrar(pedido, ip);
      if (!r?.sessao?.token || !r.conta || !r.assinatura) {
        return erro(res, 502, "Resposta inválida da central de licenças.");
      }
      banco.salvarSessao(hash(r.sessao.token), r, relogio());
      vincular(corpo, r);
      return enviar(res, 200, { type: "access_token", access_token: r.sessao.token, user: usuario(r.conta) });
    } catch (e) {
      if (e.codigo === "TOTP_NECESSARIO" && typeof e.corpo?.desafio === "string") {
        return enviar(res, 200, {
          type: "email_check",
          tfa_type: "tfa_check",
          secret: e.corpo.desafio,
          user: { name: email ?? texto(corpo.username, 254) ?? "" },
        });
      }
      if (!(e instanceof ErroCentral)) throw e;
      if (e.fora) return erro(res, 503, MENSAGENS.CENTRAL_FORA);
      if (MENSAGENS[e.codigo]) return erro(res, e.status, MENSAGENS[e.codigo]);
      // Código desconhecido (credencial sva_ recusada, produto sem contas…): problema de configuração.
      console.error("central recusou o login", e.status, e.codigo, e.message);
      return erro(res, 503, "Login indisponível no momento. Avise o suporte da H3.");
    }
  }

  async function equipe(sessao) {
    const id = sessao.assinatura.id;
    const cache = equipes.get(id);
    if (cache && cache.ate > relogio()) return cache.contas;
    try {
      const r = await central.equipe(sessao.token);
      const contas = Array.isArray(r?.contas) ? r.contas : [sessao.conta];
      equipes.set(id, { contas, ate: relogio() + EQUIPE_CACHE_MS });
      return contas;
    } catch {
      return cache?.contas ?? [sessao.conta];
    }
  }

  async function rotear(req, res) {
    const url = new URL(req.url ?? "/", "http://local");
    const rota = `${req.method} ${url.pathname.replace(/\/+$/, "")}`;
    const agora = relogio();

    switch (rota) {
      case "GET /saude":
        return enviar(res, 200, { ok: true });
      case "GET /api/login-options":
        return enviar(res, 200, []);
      // Atualizador do app: responde {url} com a página do último release assinado.
      case "GET /api/versao":
      case "POST /api/versao": {
        if (req.method === "POST") await lerCorpo(req, LIMITE_CORPO);
        const url = await versao();
        return url ? enviar(res, 200, { url }) : erro(res, 404, "Nenhuma versão publicada.");
      }
      case "POST /api/login":
        return login(req, res);
      case "POST /api/currentUser": {
        const corpo = await lerJson(req);
        const sessao = await autenticar(req);
        vincular(corpo, sessao);
        return enviar(res, 200, usuario(sessao.conta));
      }
      case "POST /api/logout": {
        const corpo = await lerJson(req);
        const token = tokenDe(req);
        if (token) {
          const tokenHash = hash(token);
          const sessao = banco.lerSessao(tokenHash);
          const id = texto(corpo.id, 64);
          if (sessao && id) banco.desvincularDispositivo(id, sessao.conta.id);
          banco.apagarSessao(tokenHash);
          central.sair(token).catch(() => {});
        }
        return enviar(res, 200, {});
      }
      case "POST /api/heartbeat": {
        const corpo = await lerJson(req);
        const id = texto(corpo.id, 64);
        if (id && (vistos.get(id) ?? 0) + VISTO_INTERVALO_MS <= agora) {
          if (vistos.size > 100_000) vistos.clear();
          vistos.set(id, agora);
          banco.marcarVisto(id, agora);
        }
        return enviar(res, 200, {});
      }
      case "POST /api/sysinfo_ver":
        await lerCorpo(req, LIMITE_CORPO);
        return enviar(res, 200, "1");
      case "POST /api/sysinfo": {
        const corpo = await lerJson(req);
        const id = texto(corpo.id, 64);
        if (!id) return enviar(res, 200, "ID_NOT_FOUND");
        banco.registrarSysinfo(
          {
            id,
            uuid: texto(corpo.uuid, 128),
            nome: texto(corpo.hostname, 120),
            so: texto(corpo.os, 120),
            versao: texto(corpo.version, 32),
          },
          agora,
        );
        return enviar(res, 200, "SYSINFO_UPDATED");
      }
      case "GET /api/ab": {
        const sessao = await autenticar(req);
        const dados = banco.lerCatalogo(sessao.conta.id);
        return dados ? enviar(res, 200, { data: dados, licensed_devices: 0 }) : enviar(res, 200, "null");
      }
      case "POST /api/ab": {
        const sessao = await autenticar(req);
        const corpo = await lerJson(req, LIMITE_CATALOGO);
        if (typeof corpo.data !== "string") return erro(res, 400, "Catálogo inválido.");
        try {
          JSON.parse(corpo.data);
        } catch {
          return erro(res, 400, "Catálogo inválido.");
        }
        banco.salvarCatalogo(sessao.conta.id, corpo.data, agora);
        return enviar(res, 200, "");
      }
      case "GET /api/users": {
        const sessao = await autenticar(req);
        const contas = (await equipe(sessao)).filter((c) => c.ativo !== false).map(usuario);
        return enviar(res, 200, paginar(url, contas));
      }
      case "GET /api/peers": {
        const sessao = await autenticar(req);
        const nomes = new Map((await equipe(sessao)).map((c) => [c.id, c.email]));
        const lista = banco
          .dispositivosDaAssinatura(sessao.assinatura.id)
          .filter((d) => nomes.has(d.conta_id))
          .map((d) => ({
            id: d.id,
            info: { device_name: d.nome ?? "", os: d.so ?? "", username: "" },
            status: 1,
            user: nomes.get(d.conta_id),
            user_name: nomes.get(d.conta_id),
            note: "",
          }));
        return enviar(res, 200, paginar(url, lista));
      }
      case "GET /api/device-group/accessible":
        await autenticar(req);
        return enviar(res, 200, { total: 0, data: [] });
      case "POST /api/audit/conn":
      case "POST /api/audit/file":
      case "POST /api/audit/alarm": {
        if (!limiteAuditoria.consumir(ipDe(req), agora)) return erro(res, 429, MENSAGENS.MUITAS_TENTATIVAS);
        const corpo = await lerJson(req);
        banco.registrarAuditoria(
          {
            tipo: rota.slice("POST /api/audit/".length),
            dispositivo: texto(corpo.id, 64),
            nonce: texto(corpo.nonce, 64),
            dados: JSON.stringify(corpo),
          },
          agora,
        );
        return enviar(res, 200, "");
      }
      default:
        return erro(res, 404, "Não encontrado.");
    }
  }

  return async function handler(req, res) {
    try {
      await rotear(req, res);
    } catch (e) {
      if (res.headersSent) return;
      if (e instanceof ErroHttp) return erro(res, e.status, e.message);
      console.error("erro na requisição", req.method, req.url?.split("?")[0], e);
      erro(res, 500, "Erro interno.");
    }
  };
}
