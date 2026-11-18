# Versões do agente: sem IA e com IA

O H3 Suporte tem **duas versões do app de acesso (Windows)**. A diferença é só o assistente de IA da sessão remota
([docs/ai-assistant.md](ai-assistant.md)).

| | **Sem IA** (padrão, vai para os clientes) | **Com IA** (só administrador do sistema) |
| --- | --- | --- |
| Arquivo | `h3suporte-<versão>-x86_64.exe` / `.msi` | `h3suporte-<versão>-x86_64-ia.exe` / `.msi` |
| Botão do robô na barra da sessão | não existe | existe |
| Painel do assistente (`AiChatPanel`) | não é montado na sessão | montado |
| Quem baixa | qualquer cliente com assinatura | **somente administrador da Central** |
| Onde fica o instalador | release público do GitHub + lista assinada do atualizador | **só artefato privado do workflow** (`h3suporte-ia-windows-x86_64`, 30 dias) |
| Atualização automática | sim, pela lista assinada | não (veja "Limites") |

A versão **-cliente** (só recebe conexão) continua como está e nunca tem IA.

## Como a separação é feita

- `flutter/lib/consts.dart`: `kH3IaBuild = bool.fromEnvironment('H3_IA')`. Sem o marcador o valor é `false`, então a
  **versão padrão não tem IA mesmo que alguém esqueça de configurar algo**.
- `flutter/lib/desktop/widgets/remote_toolbar.dart` só cria o botão do assistente com `kH3IaBuild`, e
  `flutter/lib/common/widgets/overlay.dart` só liga o painel com `kH3IaBuild`.
- `build.py`: com a variável de ambiente `H3_IA=true`, o `flutter build windows` (e o de macOS) recebe
  `--dart-define=H3_IA=true`.
- `.github/workflows/flutter-build.yml`: a matriz do Windows ganhou a entrada `name-suffix: "-ia"` com `ia: "true"`.
  Esse build **não** entra no passo "Publish Release" nem nos artefatos que alimentam a lista assinada
  (`rustdesk-update.json`); ele é enviado só como artefato `h3suporte-ia-windows-x86_64`.

Gerar as duas versões: Actions → **Release (build + publish)** como sempre; o workflow já compila as duas.

## Regra para o site da Central

O código da Central (portal e painel do administrador) fica fora deste repositório. A regra que ele deve seguir:

1. **Download padrão** (`h3suporte-<versão>-x86_64.exe`/`.msi`): visível para titular, membro e parceiro, como hoje.
2. **Download com IA** (`...-ia.exe`/`.msi`): **só aparece e só baixa com sessão de administrador da Central**.
   Titular, membro, parceiro e visitante não veem o botão, o link nem o nome do arquivo.
3. A checagem é **no servidor**: esconder o botão não basta. A rota de download do `-ia` responde `403` para quem não
   for administrador e não revela se o arquivo existe.
4. O arquivo vem do artefato `h3suporte-ia-windows-x86_64` (API do GitHub, token com leitura de Actions guardado só
   no servidor da Central) e é entregue pelo servidor da Central. Nunca publicar o `-ia` no release do GitHub nem
   repassar o link do artefato.
5. Registrar na auditoria quem baixou, quando e qual versão.
6. Mostrar a versão e o nome "Com IA — uso interno" separado da lista de downloads dos clientes.

## Limites conhecidos

- **Atualização:** o atualizador só conhece a versão sem IA. Um computador com a versão com IA que atualizar sozinho
  passaria para a versão sem IA. Hoje o administrador reinstala o `-ia` a cada versão. Impedir a atualização
  automática no `-ia` exige o app saber que é `-ia` também no lado Rust (hoje o marcador só existe no Dart).
- Quem já tem o instalador `-ia` pode repassá-lo: a restrição vale para a distribuição, não para o arquivo.
- Só Windows x64 gera a versão com IA. O macOS aceita o marcador (`H3_IA=true` no `build.py`) mas o CI ainda não tem
  a entrada `-ia` para ele.
- Não testei o build `-ia` no CI nem uma sessão real; só a análise do Dart, a sintaxe do YAML e do `build.py`.
