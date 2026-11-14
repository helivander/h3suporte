# Plano da fase 2: gateway de IA da H3 com login OAuth

Status: proposta, não implementada. Complementa [ai-assistant.md](ai-assistant.md).

## Objetivo

Tirar a chave da API da Anthropic das máquinas dos técnicos. O técnico entra
com a conta da empresa; o app fala com um servidor da H3 (o gateway), e só o
gateway fala com a API do Claude.

Ganhos:

- nenhuma chave da API distribuída nem gravada em texto simples;
- acesso cortado na hora quando um técnico sai da empresa;
- limite de gasto por técnico;
- registro de quem pediu o quê, em qual máquina remota.

Fora do escopo: login com a assinatura pessoal do Claude (Pro/Max). A
Anthropic não permite isso em apps de terceiros sem aprovação.

## Arquitetura

```
App H3 Suporte (técnico)                Gateway H3                    Anthropic
  painel de IA ── HTTPS + token H3 ──>  valida token                  
                                        aplica limites e regras  ──>  POST /v1/messages
                                        grava uso e auditoria   <──   resposta
  painel de IA <── resposta ──────────  devolve a resposta
```

O gateway expõe `POST /v1/messages` com o mesmo formato da API da Anthropic.
Assim o app muda pouco: troca o endereço (já configurável) e manda
`Authorization: Bearer <token H3>` no lugar de `x-api-key`.

## Login: duas opções

A escolha depende do servidor que a H3 usa hoje.

### Opção A: reaproveitar o login de conta do app (se a H3 usa o RustDesk Server Pro)

O app já tem tela de login de conta, com usuário/senha e OIDC (Google,
Microsoft e outros), feita contra o "servidor de API" do RustDesk Server Pro.
Depois do login o app guarda um `access_token` e o manda como Bearer
(`getHttpHeaders()` em `flutter/lib/common.dart`).

Nesse caso:

1. O técnico entra pela tela de login que já existe.
2. O painel de IA manda esse mesmo `access_token` ao gateway.
3. O gateway valida o token chamando `POST {servidor de API}/api/currentUser`
   e guarda o resultado em cache por alguns minutos.
4. O gateway libera só usuários de um grupo ou lista definidos pela H3.

Vantagens: nenhum login novo, nenhum código de OAuth no app, desligar o
usuário no servidor de API desliga a IA também.

### Opção B: login OIDC próprio do gateway (se a H3 usa o hbbs open source)

O hbbs open source não tem servidor de API nem contas. O gateway faz o login:

1. O painel de IA mostra "Entrar". O app abre uma porta local
   (`127.0.0.1`, porta aleatória) e abre o navegador do sistema em
   `https://ia.h3info.com/auth/start`, com PKCE (`code_challenge`) e `state`.
2. O gateway redireciona para o provedor da empresa (Google Workspace ou
   Microsoft Entra ID) com OIDC.
3. O provedor volta ao gateway, que confere o e-mail (domínio da H3 e lista
   de técnicos liberados) e redireciona o navegador para
   `http://127.0.0.1:<porta>/callback?code=...`.
4. O app troca o código, com o `code_verifier` do PKCE, por:
   - token de acesso: 15 minutos;
   - token de renovação: 30 dias, trocado a cada uso.
5. Quando o gateway responde 401, o app renova o token sozinho; se a
   renovação falhar, pede novo login.

Esse é o fluxo recomendado para apps de desktop (RFC 8252: navegador do
sistema, redirecionamento para loopback, PKCE). O app não vê a senha do
técnico.

## Gateway

### Tecnologia (padrões propostos)

- Node.js com Fastify, em contêiner Docker.
- SQLite no início (um arquivo, backup simples); Postgres se crescer.
- HTTPS por um proxy reverso (Caddy ou nginx) em `ia.h3info.com`, no mesmo
  servidor do hbbs ou num separado.
- Chave da Anthropic numa variável de ambiente do servidor; depois, Workload
  Identity Federation para não ter chave fixa.

### Rotas

| Rota | Função |
|---|---|
| `POST /v1/messages` | Repasse para a Anthropic, com as regras abaixo |
| `GET /auth/start`, `GET /auth/callback`, `POST /auth/token` | Login (só na opção B) |
| `POST /auth/logout` | Revoga o token de renovação |
| `GET /me` | Usuário, limite e uso do mês, para o painel mostrar |
| `GET /health` | Verificação de saúde para o deploy |

### Regras aplicadas em `POST /v1/messages`

- Token válido e usuário liberado; senão 401 ou 403.
- Modelo dentro de uma lista permitida (ex.: `claude-opus-5-5`,
  `claude-sonnet-5-5`); `max_tokens` com teto.
- Só a ferramenta `computer_toolset_20260801` é aceita em `tools`.
- O prompt de sistema de segurança é fixado pelo gateway, não pelo app.
- Corpo até 24 MB (as capturas de tela vão no histórico).
- Limite de gasto por técnico por dia e por mês, calculado pelo `usage` de
  cada resposta e pelo preço do modelo; acima do limite, 429 com mensagem
  clara.
- Limite de requisições por minuto por técnico.
- Timeout de 5 minutos por chamada; repetição em 429 e 5xx da Anthropic.

### Auditoria e LGPD

Grava por chamada: técnico, data e hora, ID da máquina remota e da sessão
(cabeçalhos `X-H3-Peer-Id` e `X-H3-Session-Id` enviados pelo app), modelo,
tokens, custo estimado e os nomes das ações devolvidas (`left_click`, `type`
etc.).

Não grava capturas de tela nem o texto digitado. Guarda os registros por um
prazo definido pela H3 (ex.: 90 dias) e apaga depois.

## Mudanças no app

Em `flutter/lib/models/ai_agent_model.dart` e no painel:

- modo "Gateway H3": botão Entrar/Sair, uso do mês, token renovado sozinho;
- `Authorization: Bearer` no lugar de `x-api-key`, mais os cabeçalhos de
  máquina e sessão;
- mensagens para 401 (entrar de novo), 403 (sem permissão) e 429 (limite);
- guardar os tokens cifrados com `encrypt_str_or_original` do `hbb_common`,
  como o app já faz com senhas, em vez de texto simples;
- endereço do gateway fixo no build da H3, com o modo de chave direta
  escondido nas versões de produção (fica só para desenvolvimento).

Na opção A quase tudo isso se reduz a reaproveitar o `access_token`.

## Etapas e estimativas

Estimativas grosseiras para uma pessoa.

| Etapa | Opção A | Opção B |
|---|---|---|
| Gateway: repasse, regras, limites, auditoria | 4 a 5 dias | 4 a 5 dias |
| Login | 1 dia (validar token no servidor de API) | 4 a 5 dias (OIDC, PKCE, renovação) |
| App: modo gateway e tratamento de erros | 2 dias | 3 a 4 dias |
| Deploy (Docker, HTTPS, backup, healthcheck) | 1 a 2 dias | 1 a 2 dias |
| Testes e ajustes | 2 dias | 3 dias |
| Total | cerca de 2 semanas | cerca de 3 semanas |

Ordem sugerida: gateway com uma lista fixa de tokens de teste, depois o app
apontando para ele, depois o login real, por último o deploy.

## Testes

- Gateway: validação de token, lista de técnicos, limite de gasto, regras de
  modelo e ferramentas, com a API da Anthropic simulada.
- Um teste de ponta a ponta com uma chamada real e barata (custa dinheiro;
  rodar com aprovação).
- App: renovação de token e mensagens de 401/403/429.

## Alternativa: OAuth direto no provedor de IA

Levantado em 14/11/2026. O técnico entra com a própria conta do provedor e o
uso sai do plano dele, sem gateway.

- **Anthropic:** não há programa documentado de OAuth para apps de terceiros.
  Login com a conta do claude.ai (Pro/Max) não é permitido sem aprovação
  prévia da Anthropic. O login OAuth do Console (`ant auth login`) é para o
  desenvolvedor na própria máquina e cobra como uso de API da organização.
  Caminho: pedir aprovação à Anthropic (equipe comercial).
- **OpenAI:** "Sign in with ChatGPT" tem permissão opcional de uso do plano
  (OAuth 2.0/OIDC, retorno para loopback, Responses API com `stream: true` e
  `store: false`). Aberto por conta própria para apps open source e locais;
  apps pagos ou hospedados precisam do formulário de interesse. O H3 Suporte é
  AGPL e público, mas é usado num serviço comercial, então a elegibilidade
  precisa ser confirmada com a OpenAI.
  - Teste real em 14/11/2026 (script descartável, conta ChatGPT do usuário):
    - login OAuth com PKCE e loopback em `127.0.0.1:1455` funcionou e concedeu
      `chatgpt.tokens.use.direct`; o `ext_agent_host_id` precisa estar no
      formato `urn:uuid:<uuid>` (só o UUID dá `invalid_authorize_request`);
    - modelos liberados: `gpt-6.1-sol`, `gpt-6-astra`, `gpt-6.1-terra`,
      `gpt-6-sol`, `gpt-6-luna`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`;
    - texto e leitura de imagem funcionaram;
    - **a ferramenta nativa de computer use não é aceita pelo plano**:
      `computer` e `computer_use_preview` voltam 400 `Unsupported tool type`;
    - **funções próprias funcionam**: com uma função `click(x, y)` e a captura
      como imagem, o `gpt-6.1-sol` clicou em (850, 590), dentro do botão Salvar
      de uma tela de teste de 1280x800. Foi um único teste em tela sintética.
  - Consequência: o caminho OpenAI é viável definindo as ações (clicar,
    digitar, teclas, rolar, captura) como funções próprias, executadas pelas
    mesmas rotinas que o app já tem. Exige um adaptador OpenAI ao lado do
    Claude no `ai_agent_model.dart`.
  - O uso conta no plano pessoal de cada técnico (no Plus, um limite de 5 horas
    compartilhado entre todos os apps).

## Decisões em aberto

1. **A H3 usa o RustDesk Server Pro (com servidor de API) ou o hbbs open
   source?** Define a opção A ou B.
2. **Provedor de login da empresa:** Google Workspace ou Microsoft 365.
3. **Onde hospedar o gateway** e com qual domínio.
4. **Limites de gasto** por técnico (dia e mês) e prazo de retenção dos
   registros.
5. **Manter o modo de chave direta** nas versões de produção ou só no
   desenvolvimento.

Padrão aplicado na proposta, a confirmar: gateway em JavaScript (Node.js),
preferência registrada nos outros projetos do usuário.
