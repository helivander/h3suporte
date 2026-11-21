#!/usr/bin/env bash
# Gera aqui no Mac (Apple Silicon) o .pkg e o .dmg do H3 Suporte para testar, sem o GitHub.
# Assina com o Developer ID do keychain e notariza (ad-hoc se o certificado faltar). Para a entrega oficial a
# clientes use Actions -> Release. Preparo em docs/desenvolver-interface.md.
#
#   res/build-mac-local.sh          recompila o que mudou (motor e interface) e gera os instaladores
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

# Sempre roda o cargo: é incremental e só recompila se algo mudou. Imagens como o ícone da barra de menus
# (res/mac-tray-*.png) ficam embutidas no motor; sem recompilar, o instalador sairia com o ícone antigo.
MACOSX_DEPLOYMENT_TARGET=12.3 cargo build --locked --features "$FEATURES" --release
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
ID_APP="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
ID_PKG="$(security find-identity -v | sed -n 's/.*"\(Developer ID Installer:[^"]*\)".*/\1/p' | head -1)"
if [ -n "$ID_APP" ]; then
  # O servidor de carimbo de tempo da Apple falha de vez em quando ("A timestamp was expected"): o codesign de cada
  # binário é repetido por um atalho no PATH, sem mexer no script de assinatura compartilhado com o CI.
  ATALHO="$(mktemp -d)"
  printf '#!/bin/bash\nfor i in 1 2 3 4 5 6 7 8; do /usr/bin/codesign "$@" && exit 0; sleep 3; done; exit 1\n' > "$ATALHO/codesign"
  chmod +x "$ATALHO/codesign"
  PATH="$ATALHO:$PATH" bash .github/scripts/sign-macos-app.sh "$APP" "$ID_APP" flutter/macos/Runner/Release.entitlements
  rm -rf "$ATALHO"
else
  codesign --force --deep --sign - --entitlements flutter/macos/Runner/Release.entitlements "$APP"
fi
codesign --verify --deep --strict "$APP"

mkdir -p "$SAIDA"
BASE="$SAIDA/h3suporte-$VERSAO-local"
rm -rf "$SAIDA/.pkgroot" "$SAIDA/.dmgroot" && mkdir -p "$SAIDA/.pkgroot" "$SAIDA/.dmgroot"
ditto "$APP" "$SAIDA/.pkgroot/H3Suporte.app"
pkgbuild --analyze --root "$SAIDA/.pkgroot" "$SAIDA/.pkg.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$SAIDA/.pkg.plist" ||
  /usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$SAIDA/.pkg.plist"
for tentativa in 1 2 3 4 5 6 7 8; do
  pkgbuild --root "$SAIDA/.pkgroot" --component-plist "$SAIDA/.pkg.plist" --install-location /Applications \
    --identifier br.com.h3info.h3suporte --version "$VERSAO" ${ID_PKG:+--sign "$ID_PKG" --timestamp} "$BASE.pkg" >/dev/null && break
  [ "$tentativa" = 8 ] && exit 1
  sleep 3
done
ditto "$APP" "$SAIDA/.dmgroot/H3Suporte.app" && ln -s /Applications "$SAIDA/.dmgroot/Applications"
# Ícone H3 no volume do dmg (aparece no Finder e na área de trabalho quando montado).
cp flutter/macos/Runner/AppIcon.icns "$SAIDA/.dmgroot/.VolumeIcon.icns" && SetFile -a C "$SAIDA/.dmgroot"
rm -f "$BASE.dmg" && hdiutil create -quiet -volname "H3 Suporte" -srcfolder "$SAIDA/.dmgroot" -format UDZO "$BASE.dmg"
rm -rf "$SAIDA/.pkgroot" "$SAIDA/.dmgroot" "$SAIDA/.pkg.plist"

# Com Developer ID, assina o dmg e notariza os dois (perfil h3suporte-notary do notarytool); sem ele, fica só assinado.
if [ -n "$ID_APP" ]; then
  for tentativa in 1 2 3 4 5 6; do
    codesign --force --sign "$ID_APP" --timestamp "$BASE.dmg" && break
    [ "$tentativa" = 6 ] && exit 1
    sleep 5
  done
  if xcrun notarytool history --keychain-profile h3suporte-notary >/dev/null 2>&1; then
    for f in "$BASE.pkg" "$BASE.dmg"; do
      xcrun notarytool submit "$f" --keychain-profile h3suporte-notary --wait && xcrun stapler staple "$f"
    done
  else
    echo "Perfil h3suporte-notary ausente: assinado, mas não notarizado."
  fi
fi

# Ícone H3 também nos arquivos .pkg e .dmg deste Mac (ícone de arquivo não viaja pela internet: vale só aqui).
VERSAO="$VERSAO" swift - "$SAIDA" "$RAIZ/flutter/macos/Runner/AppIcon.icns" <<'SW' 2>/dev/null || true
import AppKit
let a = CommandLine.arguments
let icone = NSImage(contentsOfFile: a[2])!
for ext in ["pkg", "dmg"] {
  NSWorkspace.shared.setIcon(icone, forFile: "\(a[1])/h3suporte-\(ProcessInfo.processInfo.environment["VERSAO"] ?? "")-local.\(ext)", options: [])
}
SW

echo; echo "Prontos:"; ls -lh "$BASE.pkg" "$BASE.dmg"
