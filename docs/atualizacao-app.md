# Atualização do app pelo próprio app

O H3 Suporte instalado procura versão nova sozinho e, no Windows e no Mac, baixa e instala. Ele só aceita
versões publicadas no GitHub `helivander/h3suporte` **e assinadas com a chave da H3**: ninguém consegue empurrar um
instalador falso para os clientes, nem trocando um arquivo no release.

## Como funciona

```
App instalado ──POST──► keys.h3info.com/h3suporte/api/versao   (servidor-api)
                           └─ último release ESTÁVEL do GitHub que tem rustdesk-update.json + .sig
App ◄── {url: https://github.com/helivander/h3suporte/releases/tag/v1.5.4}
App ──► baixa rustdesk-update.json e .sig do release, confere a assinatura com a chave pública gravada no app,
        baixa o instalador da sua plataforma e confere tamanho e SHA-256 antes de instalar
```

- **Quando procura:** ao abrir o app, se "Procurar atualização ao iniciar" estiver ligado, e uma vez por dia pelo
  serviço quando "Atualização automática" estiver ligada (Configurações → Geral).
- **Windows:** baixa o `.exe` da arquitetura e instala sem perguntar, quando não há conexão remota em andamento
  (atualização automática) ou pelo botão "Atualizar" do aviso.
- **Mac:** baixa o `.dmg` e instala pelo serviço (precisa do serviço instalado). Desde o build `v1.5.3-10` o app,
  o `.dmg` e o `.pkg` saem assinados com Developer ID e notarizados: abrem sem aviso do Gatekeeper.
- **Linux e Android:** o aviso abre a página do release para baixar.
- **Builds de teste** (`v1.5.3-1`, `v1.5.3-2`…) são pré-release e nunca são oferecidos aos clientes.

Peças:

| Onde | O quê |
| --- | --- |
| `src/common.rs` | `H3_UPDATE_CHECK_URL` (servidor-api) e o repositório aceito (`H3_UPDATE_REPO_OWNER/NAME`) |
| `src/update_metadata.rs` | Chave **pública** da H3 (`TRUSTED_UPDATE_KEYS`) |
| `servidor-api/src/versao.js` | Rota `/api/versao`: último release estável com a lista assinada (cache de 10 min) |
| `.github/workflows/release.yml` | Opção **lançamento**: release `vX.Y.Z` estável + job `assinar-atualizacao` |
| `res/update/generate_update_metadata.py` | Gera e assina a lista (`rustdesk-update.json` + `.sig`) |

## Como lançar uma versão para os clientes

1. Suba o número da versão em todos os arquivos e faça commit/push na `master`:

   ```bash
   res/bump.sh 1.5.3 1.5.4
   ```

   (o script troca em `Cargo.toml`, `flutter/pubspec.yaml`, workflows e empacotamentos; confira o `git diff`.)
2. GitHub → Actions → **Release (build + publish)** → Run workflow, com **Versão base** = `1.5.4` e
   **Lançamento** marcado. O build recusa se a versão não bater com o `Cargo.toml` ou se `v1.5.4` já existir.
3. No fim, o job `assinar-atualizacao` baixa os instaladores do release, assina a lista e publica os dois arquivos;
   o `finalize-notes` marca o release como estável e "Latest". Em até 10 minutos o servidor-api passa a oferecer a
   versão.

Para testar antes de liberar a todos: lance numa versão que só você tem instalada e confira o aviso. Para
**segurar** uma versão com problema, marque o release como pré-release no GitHub: o servidor-api volta a oferecer o
anterior estável (quem já atualizou fica na nova; corrija lançando outra versão).

## A chave de assinatura

- Privada: segredo `H3_UPDATE_ED25519_SEED` do repositório no GitHub. Backup em
  `~/.config/h3suporte/update-ed25519-seed.b64` (e `.pem`) no Mac do responsável: **guarde uma cópia num cofre de
  senhas**. Nunca vai para o git, chat ou e-mail.
- Pública: variável `H3_UPDATE_ED25519_PUBLIC_KEY` do repositório e gravada no app (`src/update_metadata.rs`).
  O build confere que as três batem (`generate_update_metadata.py check-key`).
- **Perder a privada:** os apps instalados nunca mais aceitam atualização automática; seria preciso gerar outra chave,
  lançar uma versão com a nova pública e cada cliente instalar essa versão à mão.
- **Vazar a privada:** gere outra chave já, lance uma versão com ela e avise os clientes para atualizarem.

## Limites conhecidos

- Windows instalado pelo `.msi`: o código do RustDesk trata o H3 Suporte como "cliente personalizado" e atualiza pelo
  `.exe`. Teste esse caso antes de vender instalação por MSI.
- O endereço do servidor-api é fixo no app (`H3_UPDATE_CHECK_URL`); mudar exige lançar uma versão antes.
- Linux e Android não instalam sozinhos.

## Assinatura Apple (Mac)

- Certificado **Developer ID Application** do time `4AJ2L98BR4`, criado em 15/11/2026, **vence em 15/12/2027**
  (renove antes no developer.apple.com com um CSR novo e atualize os segredos).
- Chave privada, `.p12` e senha: `~/.config/h3suporte/apple/` no Mac do responsável (fora do git; guarde cópia no
  cofre de senhas). Também instalado no keychain de login.
- **Developer ID Installer** (assina o `.pkg`), criado em 15/11/2026, também **vence em 15/12/2027**; chave e
  `installer-id.p12` na mesma pasta, com a mesma senha. Segredo `MACOS_INSTALLER_P12_BASE64`; o build assina o
  `.pkg`, notariza e grampeia (staple) quando há a chave de notarização.
- Segredos do GitHub: `MACOS_P12_BASE64`, `MACOS_P12_PASSWORD`, `MACOS_CODESIGN_IDENTITY` (com as aspas).
  O build assina o app com hardened runtime (`.github/scripts/sign-macos-app.sh`).
- Notarização: segredo `MACOS_NOTARIZE_JSON` (chave de API da App Store Connect "H3 Suporte notarizacao", ID
  `BS8844T493`, função Desenvolvedor, criada em 15/11/2026; no formato do `rcodesign`). O `.p8` e o JSON ficam em
  `~/.config/h3suporte/apple/` (a Apple só deixa baixar o `.p8` uma vez). Neste Mac também há o perfil
  `h3suporte-notary` do `notarytool`. Sem o segredo o `.dmg` sai assinado mas não notarizado.
