# Assistente de IA na sessão remota

Painel de chat ao lado da sessão remota (desktop) em que o técnico descreve uma
tarefa e um modelo de IA a executa na máquina remota, com mouse e teclado.

## Como funciona

O agente roda no lado do técnico. Não há mudança de protocolo nem no programa
instalado na máquina controlada.

1. O técnico escreve a tarefa no painel (botão do robô na barra da sessão).
2. O app pede uma captura da tela remota (`sessionTakeScreenshot`), reduz para
   no máximo 1280 px no lado maior e envia ao modelo como JPEG.
3. O modelo responde com ações da ferramenta de computer use
   (`computer_toolset_20260801` da API da Anthropic).
4. O app converte as coordenadas para a área de trabalho remota e envia as
   ações por `sessionSendMouse`, `sessionInputKey` e `sessionInputString`.
5. O ciclo repete até o modelo concluir, o técnico parar ou o limite de 50
   passos por execução.

## Arquivos

| Arquivo | Papel |
|---|---|
| `flutter/lib/models/ai_agent_model.dart` | Ciclo do agente, chamada da API, execução das ações, captura |
| `flutter/lib/models/ai_agent_utils.dart` | Funções puras: escala, coordenadas, teclas |
| `flutter/lib/desktop/widgets/ai_chat_panel.dart` | Painel de chat |
| `flutter/test/ai_agent_utils_test.dart` | Testes das funções puras |

Ganchos em arquivos existentes: campo `aiAgentModel` no `FFI` e desvio do
evento `screenshot` em `model.dart`, uma linha em `BlockableOverlayState.applyFfi`
e o botão em `remote_toolbar.dart`.

## Configuração

Na engrenagem do painel, gravada nas opções locais do app:

| Opção | Padrão |
|---|---|
| `ai-agent-api-key` | vazio |
| `ai-agent-model` | `claude-opus-5-5` |
| `ai-agent-base-url` | `https://api.anthropic.com` |

O endereço é configurável para apontar para um proxy próprio (fase 2).

## Provedor ChatGPT (login com a conta)

Na engrenagem do painel, escolha "ChatGPT (entrar com sua conta)" e clique em
"Entrar com o ChatGPT". O navegador abre o login da OpenAI; ao autorizar, o uso
sai do plano ChatGPT (Plus ou Pro) do técnico.

- Login: "Sign in with ChatGPT" com uso do plano, OAuth 2.0 com PKCE e retorno
  para `http://127.0.0.1:1455/auth/callback` (porta aleatória se a 1455 estiver
  ocupada). O identificador da máquina segue o formato `urn:uuid:<uuid>`.
- Na primeira vez a OpenAI registra o app e devolve um `client_id`
  (`ai-agent-chatgpt-client-id`), reaproveitado nos logins seguintes.
- O token de acesso dura cerca de 1 hora e é renovado sozinho; se a renovação
  for recusada, o painel pede novo login.
- Chamadas: `POST https://api.openai.com/v1/responses` com `store: false` e
  `stream: true`. Modelo padrão `gpt-6.1-sol` (`ai-agent-chatgpt-model`).
- A ferramenta nativa de computer use da OpenAI não é aceita pelo plano. As
  ações são oferecidas como funções próprias com os mesmos nomes e campos do
  Claude (`screenshot`, `left_click`, `type`, `key` ...), e a mesma rotina do
  app executa os dois provedores.
- Código: `flutter/lib/models/ai_chatgpt_auth.dart` (login e tokens),
  `flutter/lib/models/ai_chatgpt_utils.dart` (funções puras, com testes em
  `flutter/test/ai_chatgpt_utils_test.dart`) e `_runChatGpt` em
  `ai_agent_model.dart`.

Limites do provedor ChatGPT:

- Tokens gravados em texto simples nas opções locais, como a chave da API.
- A assinatura do `id_token` não é verificada; ele só serve para mostrar o
  e-mail. A autorização real é feita pela API com o token de acesso.
- Uso do plano por apps comerciais pode exigir o formulário de interesse da
  OpenAI; o teste foi feito com a conta do usuário.

## Segurança

- "Confirmar cada ação" vem ligado: o técnico aprova cada lote de ações antes
  de ser executado. Capturas e esperas não pedem confirmação.
- O botão de parar interrompe a chamada em curso e as ações restantes.
- O prompt do sistema instrui o modelo a obedecer só ao chat do técnico, a não
  digitar senhas e a pedir confirmação antes de ações destrutivas. Isso é uma
  instrução ao modelo, não uma garantia técnica.
- As capturas da tela do cliente são enviadas ao provedor de IA. É preciso o
  consentimento do cliente.

## Limites conhecidos (fase 1)

- A chave fica em texto simples nas opções locais. A fase 2 move a chave para
  um proxy com login do técnico.
- A máquina remota precisa suportar captura de tela (`is_screenshot_supported`)
  e a sessão precisa mostrar um único monitor.
- O histórico não é podado: cada captura fica na conversa. O app recusa novos
  envios acima de 24 MB e pede para limpar a conversa.
- As chamadas usam o pacote `http` direto e não passam pelo proxy configurado
  no app.
- Mexer no mouse da sessão não pausa o agente; use o botão de parar.
- Não há indicador de "IA no controle" na máquina remota nem registro de
  auditoria.
- Só desktop nativo. Sem versão web nem mobile.

## Estado da verificação

- Build do CI em 14/11/2026 ([execução 43606931446](https://github.com/helivander/h3suporte/actions/runs/43606931446),
  commit `7e58c2c34`): compilou em Windows (x64, x86, ARM64 e variante
  cliente), macOS (Intel e Apple Silicon), Linux (x86_64, ARM64 e DRM) e
  Android (ARM64, ARMv7 e x86_64). Os testes Dart passaram (180 passaram, 2
  pulados), incluindo `ai_agent_utils_test.dart` e `ai_chatgpt_utils_test.dart`.
- As ferramentas e o prompt do provedor ChatGPT foram validados contra a API
  real com uma tela de teste.
- Falta testar numa sessão remota real, nos dois provedores.

## Próximas fases

2. Proxy com a chave, login do técnico, limite de uso e auditoria.
3. Campo de tarefa na tela de conexão, antes de conectar.
4. Canal de terminal para tarefas de comando.
5. Indicador na máquina remota, pausa ao mexer no mouse, consentimento.
