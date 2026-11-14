/** Erro de uma chamada à Central. `fora` = rede, tempo esgotado ou 5xx: não é resposta sobre a conta. */
export class ErroCentral extends Error {
  constructor(status, codigo, mensagem, corpo = null) {
    super(mensagem);
    this.status = status;
    this.codigo = codigo;
    this.corpo = corpo;
    this.fora = status === 0 || status >= 500;
  }
}

/** Cliente das rotas `/api-servico/contas/*` (docs/central-contas-assinante.md). */
export function criarCentral({ url, credencial, timeoutMs = 8000, fetch: buscar = fetch }) {
  async function chamar(rota, corpo, ipCliente) {
    const cabecalhos = {
      authorization: `Bearer ${credencial}`,
      "content-type": "application/json",
      accept: "application/json",
    };
    if (ipCliente) cabecalhos["x-cliente-ip"] = ipCliente;
    let resp;
    try {
      resp = await buscar(`${url}/api-servico/contas/${rota}`, {
        method: "POST",
        headers: cabecalhos,
        body: JSON.stringify(corpo),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch {
      throw new ErroCentral(0, "CENTRAL_FORA", "Central indisponível");
    }
    if (resp.status === 204) return null;
    let dados = null;
    try {
      dados = await resp.json();
    } catch {
      dados = null;
    }
    if (resp.ok && dados) return dados;
    if (resp.ok) throw new ErroCentral(502, "RESPOSTA_INVALIDA", "Resposta inválida da Central");
    throw new ErroCentral(resp.status, dados?.codigo ?? "", dados?.message ?? `HTTP ${resp.status}`, dados);
  }

  return {
    entrar: (pedido, ipCliente) => chamar("entrar", pedido, ipCliente),
    validar: (sessao) => chamar("validar", { sessao }),
    sair: (sessao) => chamar("sair", { sessao }),
    equipe: (sessao) => chamar("equipe", { sessao }),
  };
}
