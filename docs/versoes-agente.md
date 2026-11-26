# Versões do agente: sem IA e com IA

O H3 Suporte tem **duas versões do app de acesso (Windows e macOS)**. A diferença é só o assistente de IA da sessão remota
([docs/ai-assistant.md](ai-assistant.md)).

| | **Sem IA** (padrão, vai para os clientes) | **Com IA** (só administrador do sistema) |
| --- | --- | --- |
| Arquivo (Windows) | `h3suporte-<versão>-x86_64.exe` / `.msi` | `h3suporte-<versão>-x86_64-ia.exe` / `.msi` |
| Arquivo (macOS) | `h3suporte-<versão>-<arch>.dmg` e `h3suporte-<versão>-macos-<apple-silicon\|intel>.pkg` | os mesmos com `-ia` antes da extensão (`-aarch64-ia.dmg`, `-macos-apple-silicon-ia.pkg`) |
| Botão do robô na barra da sessão | não existe | existe |
| Painel do assistente (`AiChatPanel`) | não é montado na sessão | montado |
| Quem baixa | qualquer cliente com assinatura | **somente assinatura com plano DEV** (`PLANOS_IA` no servidor-api) |
| Onde fica o instalador | release público do GitHub + lista assinada do atualizador | **só artefato do workflow**, fora do release (não é privado: veja Limites) (`h3suporte-ia-windows-x86_64`, `h3suporte-ia-macos-aarch64`, `h3suporte-ia-macos-x86_64`; 30 dias) |
| Atualização automática | sim, pela lista assinada | **não**: o build `-ia` nunca procura atualização |

No macOS o app e o `.dmg`/`.pkg` da versão com IA saem pelo mesmo caminho de assinatura e notarização da versão padrão.

A versão **-cliente** (só recebe conexão) continua como está e nunca tem IA.

## Como a separação é feita

- `flutter/lib/consts.dart`: `kH3IaBuild = bool.fromEnvironment('H3_IA')`. Sem o marcador o valor é `false`, então a
  **versão padrão não tem IA mesmo que alguém esqueça de configurar algo**.
- `flutter/lib/desktop/widgets/remote_toolbar.dart` só cria o botão do assistente com `kH3IaBuild`, e
  `flutter/lib/common/widgets/overlay.dart` só liga o painel com `kH3IaBuild`.
- `build.py`: com a variável de ambiente `H3_IA=true`, o `flutter build windows` (e o de macOS) recebe
  `--dart-define=H3_IA=true`; o mesmo `H3_IA=true` chega ao `cargo` (`option_env!("H3_IA")`, `build.rs` refaz a compilação
  quando ele muda).
- `.github/workflows/flutter-build.yml`: a matriz do Windows e a do macOS (Intel e Apple Silicon) ganharam entradas `name-suffix: "-ia"` com `ia: "true"`.
  Esse build **não** entra no passo "Publish Release" nem nos artefatos que alimentam a lista assinada
  (`rustdesk-update.json`); ele é enviado só como artefato (`h3suporte-ia-windows-x86_64`, `h3suporte-ia-macos-<arch>`).

Gerar as duas versões: Actions → **Release (build + publish)** como sempre; o workflow já compila as duas.

## Regra para o site da Central

O código da Central (portal e painel do administrador) fica fora deste repositório. A regra que ele deve seguir:

1. **Download padrão** (`h3suporte-<versão>-x86_64.exe`/`.msi`): visível para titular, membro e parceiro, como hoje.
2. **Download com IA** (`...-ia.exe`/`.msi`/`.dmg`/`.pkg`): **só aparece e só baixa com sessão de uma assinatura do plano DEV**.
   Os demais planos e visitantes não veem o botão, o link nem o nome do arquivo. Quem serve é o `servidor-api`
   (`GET /api/downloads-ia`, veja o README dele); a Central só consome essas rotas.
3. A checagem é **no servidor**: esconder o botão não basta. As rotas respondem `404` para quem não tem o plano e
   não revelam se o arquivo existe.
4. O arquivo vem do artefato `h3suporte-ia-windows-x86_64` ou `h3suporte-ia-macos-<arch>` (API do GitHub, token com leitura de Actions guardado só
   no `servidor-api`), é extraído do zip e entregue direto pelo servidor. Nunca publicar o `-ia` no release do GitHub nem
   repassar o link do artefato.
5. A auditoria (`download_ia`) registra conta, arquivo e versão.
6. Mostrar a versão e o nome "Com IA — uso interno" separado da lista de downloads dos clientes.

## Limites conhecidos

- **Artefato não é privado:** o repositório `helivander/h3suporte` é um fork público, e no GitHub qualquer usuário
  logado com acesso de leitura baixa os artefatos do workflow, inclusive os `-ia` (e o
  `rustdesk-unsigned-windows-x86_64-ia`). A trava do plano DEV vale só para o download pela Central e pelo
  `servidor-api`. Restringir de fato exige gerar ou guardar o `-ia` fora deste repositório.
- **Atualização:** o `-ia` não se atualiza (no Rust, `do_check_software_update` em `src/common.rs` sai na hora quando o
  build tem `H3_IA=true`, o que cobre o aviso, a atualização automática do Windows e a do serviço do Mac). A cada
  versão nova o administrador reinstala o `-ia` pelo artefato do workflow.
- Quem já tem o instalador `-ia` pode repassá-lo: a restrição vale para a distribuição, não para o arquivo.
- Só Windows x64 e macOS (Intel e Apple Silicon) geram a versão com IA; Linux e Android não.
- Cada entrada `-ia` refaz o build inteiro (cerca de uma hora por arquitetura): o macOS ganhou dois builds
  e o do Windows ganhou mais um: são 3 builds a mais por lançamento.
- Não testei o build `-ia` no CI nem uma sessão real; só a análise do Dart, a sintaxe do YAML e do `build.py`, e a
  compilação do Rust (`cargo check`) com e sem `H3_IA`.
