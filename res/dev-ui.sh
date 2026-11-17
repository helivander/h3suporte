#!/usr/bin/env bash
# Edita a interface (Flutter) com o app aberto e recarrega a tela na hora, sem build nem release.
# Só para Mac Apple Silicon. Preparo e passo a passo em docs/desenvolver-interface.md.
#
#   res/dev-ui.sh          compila o motor se faltar e abre o app com hot reload
#   res/dev-ui.sh motor    recompila o motor (depois de mudar código Rust)
set -euo pipefail
cd "$(dirname "$0")/.."

export PATH="$HOME/dev/flutter/bin:/opt/homebrew/bin:$PATH"
export VCPKG_ROOT="${VCPKG_ROOT:-$HOME/dev/vcpkg}"
LLVM="$(brew --prefix llvm 2>/dev/null || true)"
[ -n "$LLVM" ] && export LIBCLANG_PATH="$LLVM/lib"
FEATURES="flutter,hwcodec,unix-file-copy-paste,screencapturekit"

for f in flutter/lib/generated_bridge.dart src/bridge_generated.rs; do
  [ -f "$f" ] || { echo "Falta $f. Veja 'A ponte' em docs/desenvolver-interface.md."; exit 1; }
done

motor() { MACOSX_DEPLOYMENT_TARGET=10.14 cargo build --locked --features "$FEATURES" --release; cp target/release/liblibrustdesk.dylib target/release/librustdesk.dylib; }
# O modo debug do Xcode procura o motor em target/debug; aponta para o de release (não compila duas vezes).
mkdir -p target/debug && ln -sf ../release/librustdesk.dylib target/debug/librustdesk.dylib && ln -sf ../release/liblibrustdesk.dylib target/debug/liblibrustdesk.dylib

if [ "${1:-}" = "motor" ] || [ ! -f target/release/liblibrustdesk.dylib ]; then motor; fi

# O Xcode 27 recusa alvo abaixo de macOS 12; o CI do Apple Silicon usa 12.3. Aqui o ajuste vale só enquanto o
# app está aberto, e os arquivos voltam ao que está no git ao sair.
ARQUIVOS=(flutter/macos/Podfile flutter/macos/Podfile.lock flutter/macos/Runner.xcodeproj/project.pbxproj)
RAIZ="$PWD"
trap 'cd "$RAIZ" && git checkout -- "${ARQUIVOS[@]}"' EXIT
sed -i '' "s/platform :osx, '.*'/platform :osx, '12.3'/" flutter/macos/Podfile
sed -i '' "s/MACOSX_DEPLOYMENT_TARGET = [0-9]*.[0-9]*;/MACOSX_DEPLOYMENT_TARGET = 12.3;/" flutter/macos/Runner.xcodeproj/project.pbxproj
# Os pods trazem o próprio alvo (10.13/10.14); força 12.3 em todos.
perl -pi -e 's/^(\s*)flutter_additional_macos_build_settings\(target\)$/$&\n$1target.build_configurations.each { |c| c.build_settings["MACOSX_DEPLOYMENT_TARGET"] = "12.3" }/' flutter/macos/Podfile

cd flutter
FLUTTER_XCODE_ARCHS=arm64 FLUTTER_XCODE_ONLY_ACTIVE_ARCH=YES flutter run -d macos
