# Editar a interface sem compilar tudo

A interface é Flutter (`flutter/lib/`). Com o app aberto em modo de desenvolvimento, salvar um arquivo `.dart`
atualiza a tela em cerca de 1 segundo (hot reload), sem build nem release. O motor (Rust) só é recompilado
quando o código Rust muda.

```bash
res/dev-ui.sh          # abre o app; compila o motor na primeira vez
res/dev-ui.sh motor    # recompila o motor depois de mexer em código Rust (src/ ou libs/)
```

Com o app aberto no terminal: `r` recarrega a tela, `R` reinicia o app, `q` fecha.

## Preparo (uma vez, Mac Apple Silicon)

Já feito neste Mac, tudo fora do repositório em `~/dev/`:

- **Flutter 3.24.5** em `~/dev/flutter`, com os dois ajustes que o CI aplica (patch do `DropdownMenu` em
  `.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff` e a linha `_setFramesEnabledState(false);`
  comentada em `packages/flutter/lib/src/scheduler/binding.dart`). O release de Mac Apple Silicon usa o Flutter
  3.44, mas o 3.44 exige patches nos arquivos versionados; para desenvolver, o 3.24.5 compila os arquivos como estão.
- **vcpkg** em `~/dev/vcpkg` (commit `VCPKG_COMMIT_ID` do `flutter-build.yml`) com as bibliotecas de vídeo e áudio
  de `vcpkg.json`, triplet `arm64-osx`.
- `brew install cmake ninja nasm autoconf automake libtool llvm`.
- **A ponte** Rust↔Dart (`src/bridge_generated*.rs`, `flutter/lib/generated_bridge*.dart` e os
  `bridge_generated.h`) não fica no git; o CI a gera. Baixe a do último build e copie para o projeto:

  ```bash
  gh run download <id-do-run> -R helivander/h3suporte -n bridge-artifact -D ~/dev/bridge
  cp -R ~/dev/bridge/src/. src/ && cp -R ~/dev/bridge/flutter/. flutter/
  ```

  Não rode `flutter_rust_bridge_codegen` (veja `AGENTS.md`). Se mudar uma função exposta em
  `src/flutter_ffi.rs`, a ponte precisa ser regerada: dispare um build no GitHub e baixe a nova.

## O que o script faz sozinho

- Compila o motor em release na primeira vez (cerca de 6 minutos) e aponta `target/debug` para ele.
- O Xcode 27 recusa alvo mínimo abaixo do macOS 12 (o projeto declara 10.14). O script aplica o alvo 12.3, o mesmo
  do CI no Apple Silicon, em `Podfile`, `project.pbxproj` e nos pods, e **desfaz tudo ao fechar o app**. Com o app
  aberto, `git status` mostra esses 3 arquivos modificados: é o ajuste temporário, não commite.

## Limites

- Mudou só Dart (telas, textos, cores, layout)? Hot reload, sem recompilar nada.
- Mudou texto de tradução (`src/lang/*.rs`)? É Rust: `res/dev-ui.sh motor`.
- O app aberto assim é de desenvolvimento (debug, sem assinatura): mais lento que o instalado e **não** serve
  para distribuir. Para entregar, siga o fluxo de sempre (Actions → Release).
- O release de Mac Apple Silicon usa Flutter 3.44; mudanças de tela que só quebram no 3.44 só aparecem no build do CI.
