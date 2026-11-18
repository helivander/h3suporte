#!/usr/bin/env bash
# Gera aqui no Mac (Apple Silicon) o .pkg e o .dmg do H3 Suporte para testar, sem o GitHub.
# Assinatura ad-hoc: abre neste Mac sem aviso porque o arquivo não vem da internet. Para entregar a clientes,
# use Actions -> Release (assina com Developer ID e notariza). Preparo em docs/desenvolver-interface.md.
#
#   res/build-mac-local.sh          usa o motor já compilado (compila se faltar)
#   res/build-mac-local.sh motor    recompila o motor antes (depois de mudar Rust)
set -euo pipefail
cd "$(dirname "$0")/.."
RAIZ="$PWD"

export PATH="$HOME/dev/flutter/bin:/opt/homebrew/bin:$PATH"
export VCPKG_ROOT="${VCPKG_ROOT:-$HOME/dev/vcpkg}"
LLVM="$(brew --prefix llvm 2>/dev/null || true)"
[ -n "$LLVM" ] && export LIBCLANG_PATH="$LLVM/lib"
FEATURES="flutter,hwcodec,unix-file-copy-paste,screencapturekit"
VERSAO="$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)"
SAIDA="$HOME/dev/instaladores"
APP="flutter/build/macos/Build/Products/Release/H3Suporte.app"

for f in flutter/lib/generated_bridge.dart src/bridge_generated.rs; do
  [ -f "$f" ] || { echo "Falta $f. Veja 'A ponte' em docs/desenvolver-interface.md."; exit 1; }
done
pgrep -f "Products/Debug/H3Suporte" >/dev/null && { echo "Feche o app aberto pelo res/dev-ui.sh antes."; exit 1; }

if [ "${1:-}" = "motor" ] || [ ! -f target/release/liblibrustdesk.dylib ] || [ ! -f target/release/service ]; then
  MACOSX_DEPLOYMENT_TARGET=12.3 cargo build --locked --features "$FEATURES" --release
fi
cp target/release/liblibrustdesk.dylib target/release/librustdesk.dylib

# Mesmo ajuste do res/dev-ui.sh (Xcode 27 recusa alvo abaixo de macOS 12); os arquivos voltam ao git ao sair.
ARQUIVOS=(flutter/macos/Podfile flutter/macos/Podfile.lock flutter/macos/Runner.xcodeproj/project.pbxproj)
trap 'cd "$RAIZ" && git checkout -- "${ARQUIVOS[@]}"' EXIT
sed -i '' "s/platform :osx, '.*'/platform :osx, '12.3'/" flutter/macos/Podfile
sed -i '' "s/MACOSX_DEPLOYMENT_TARGET = [0-9]*.[0-9]*;/MACOSX_DEPLOYMENT_TARGET = 12.3;/" flutter/macos/Runner.xcodeproj/project.pbxproj
perl -pi -e 's/^(\s*)flutter_additional_macos_build_settings\(target\)$/$&\n$1target.build_configurations.each { |c| c.build_settings["MACOSX_DEPLOYMENT_TARGET"] = "12.3" }/' flutter/macos/Podfile

(cd flutter && FLUTTER_XCODE_ARCHS=arm64 FLUTTER_XCODE_ONLY_ACTIVE_ARCH=YES flutter build macos --release)

# O service entra depois da assinatura do Xcode; sem reassinar o macOS diz que o app está danificado.
cp -f target/release/service "$APP/Contents/MacOS/"
codesign --force --deep --sign - --entitlements flutter/macos/Runner/Release.entitlements "$APP"
codesign --verify --deep --strict "$APP"

mkdir -p "$SAIDA"
BASE="$SAIDA/h3suporte-$VERSAO-local"
rm -rf "$SAIDA/.pkgroot" "$SAIDA/.dmgroot" && mkdir -p "$SAIDA/.pkgroot" "$SAIDA/.dmgroot"
ditto "$APP" "$SAIDA/.pkgroot/H3Suporte.app"
pkgbuild --analyze --root "$SAIDA/.pkgroot" "$SAIDA/.pkg.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$SAIDA/.pkg.plist" ||
  /usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$SAIDA/.pkg.plist"
pkgbuild --root "$SAIDA/.pkgroot" --component-plist "$SAIDA/.pkg.plist" --install-location /Applications \
  --identifier br.com.h3info.h3suporte --version "$VERSAO" "$BASE.pkg" >/dev/null
ditto "$APP" "$SAIDA/.dmgroot/H3Suporte.app" && ln -s /Applications "$SAIDA/.dmgroot/Applications"
rm -f "$BASE.dmg" && hdiutil create -quiet -volname "H3 Suporte" -srcfolder "$SAIDA/.dmgroot" -format UDZO "$BASE.dmg"
rm -rf "$SAIDA/.pkgroot" "$SAIDA/.dmgroot" "$SAIDA/.pkg.plist"

echo; echo "Prontos:"; ls -lh "$BASE.pkg" "$BASE.dmg"
