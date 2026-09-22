#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

RELEASE_FLAG=0
for arg in "$@"; do
  [ "$arg" = "--release" ] && RELEASE_FLAG=1
done

VERSION_FILE="VERSION"
if [ ! -f "$VERSION_FILE" ]; then
  echo "\033[31merro: $VERSION_FILE não existe\033[0m" >&2
  exit 1
fi
VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")

SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist 2>/dev/null || true)
BUNDLE_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist 2>/dev/null || true)
if [ "$SHORT_VERSION" != "$VERSION" ] || [ "$BUNDLE_VERSION" != "$VERSION" ]; then
  echo "\033[31merro: versão divergente — VERSION=$VERSION, CFBundleShortVersionString=$SHORT_VERSION, CFBundleVersion=$BUNDLE_VERSION\033[0m" >&2
  echo "\033[31matualize Resources/Info.plist (CFBundleShortVersionString e CFBundleVersion) para bater com VERSION\033[0m" >&2
  exit 1
fi

SU_PUBLIC_ED_KEY="${COVE_SU_PUBLIC_ED_KEY:-}"
if [ "$RELEASE_FLAG" = "1" ] && [ -z "$SU_PUBLIC_ED_KEY" ]; then
  echo "\033[31merro: --release exige COVE_SU_PUBLIC_ED_KEY (chave pública EdDSA do Sparkle) no ambiente\033[0m" >&2
  echo "\033[31mgere o par com o binário generate_keys do Sparkle e exporte a chave pública\033[0m" >&2
  exit 1
fi

DEV_ID_IDENTITY=""
if [ "$RELEASE_FLAG" = "1" ]; then
  DEV_ID_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)
  if [ -z "$DEV_ID_IDENTITY" ]; then
    echo "\033[31merro: --release exige uma identidade \"Developer ID Application\" no keychain (security find-identity -v -p codesigning)\033[0m" >&2
    exit 1
  fi
fi

swift build -c release
BIN=".build/release/Cove"

mkdir -p build
TMP_DIR=$(mktemp -d "build/.tmp.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT
TMP_APP="$TMP_DIR/Cove.app"
mkdir -p "$TMP_APP/Contents/MacOS" "$TMP_APP/Contents/Resources" "$TMP_APP/Contents/Frameworks"
cp "$BIN" "$TMP_APP/Contents/MacOS/"

SPARKLE_FRAMEWORK=".build/release/Sparkle.framework"
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
  echo "\033[31merro: $SPARKLE_FRAMEWORK não existe nos produtos do build — o app ficaria sem Sparkle.framework (falha silenciosa depois com 'Library not loaded')\033[0m" >&2
  exit 1
fi
cp -R "$SPARKLE_FRAMEWORK" "$TMP_APP/Contents/Frameworks/"
install_name_tool -add_rpath @executable_path/../Frameworks "$TMP_APP/Contents/MacOS/Cove" 2>/dev/null || true

clang -dynamiclib -fobjc-arc -framework Foundation -o "$TMP_APP/Contents/Resources/mradapter.dylib" adapter/mradapter.m
cp adapter/adapter.pl "$TMP_APP/Contents/Resources/"
python3 scripts/make-sounds.py >/dev/null
cp -R Resources/Sounds "$TMP_APP/Contents/Resources/Sounds"
if [ ! -f build/AppIcon.icns ]; then
  # Compile instead of interpreting: `swift file.swift <args>` passes driver flags
  # (e.g. -frontend) as argv[1] on some toolchains, so the output path is lost.
  swiftc -O scripts/make-icon.swift -o build/make-icon
  ./build/make-icon build/AppIcon.iconset >/dev/null && iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$TMP_APP/Contents/Resources/AppIcon.icns"

SU_PUBLIC_ED_KEY_LINE=""
if [ -n "$SU_PUBLIC_ED_KEY" ]; then
  SU_PUBLIC_ED_KEY_LINE="<key>SUPublicEDKey</key><string>$SU_PUBLIC_ED_KEY</string>"
fi

cat > "$TMP_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Cove</string>
<key>CFBundleIdentifier</key><string>app.cove.notch</string>
<key>CFBundleName</key><string>Cove</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>SUFeedURL</key><string>https://github.com/cove-app/cove/releases/latest/download/appcast.xml</string>
$SU_PUBLIC_ED_KEY_LINE
<key>SUScheduledCheckInterval</key><integer>86400</integer>
<key>NSBluetoothAlwaysUsageDescription</key><string>Cove mostra conexão dos seus dispositivos Bluetooth na ilha.</string>
<key>NSAudioCaptureUsageDescription</key><string>Cove mostra a waveform ao vivo do áudio tocando.</string>
<key>NSCalendarsFullAccessUsageDescription</key><string>Cove mostra seus próximos eventos na ilha.</string>
<key>NSRemindersFullAccessUsageDescription</key><string>Cove cria lembretes pela busca da ilha.</string>
<key>NSMicrophoneUsageDescription</key><string>Cove grava memos de voz pela ilha.</string>
<key>NSCameraUsageDescription</key><string>Cove usa a câmera para cadastrar e reconhecer seu rosto na ilha (desbloqueio por rosto, opcional).</string>
<key>NSSpeechRecognitionUsageDescription</key><string>Cove transcreve seus memos no próprio Mac.</string>
<key>NSAppleEventsUsageDescription</key><string>Controlar Music/Spotify (shuffle, repetir, favoritar) e responder mensagens pelo Mensagens.</string>
</dict></plist>
PLIST

SIGN_ID="-"
if [ -n "$DEV_ID_IDENTITY" ]; then
  SIGN_ID="$DEV_ID_IDENTITY"
elif security find-identity -v -p codesigning | grep -q "Cove Studio Dev"; then
  SIGN_ID="Cove Studio Dev"
fi

CODESIGN_EXTRA_ARGS=()
if [ "$RELEASE_FLAG" = "1" ]; then
  CODESIGN_EXTRA_ARGS=(--options runtime --timestamp)
fi

NESTED_FRAMEWORK="$TMP_APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$NESTED_FRAMEWORK" ]; then
  for comp in \
    "Versions/B/XPCServices/Downloader.xpc" \
    "Versions/B/XPCServices/Installer.xpc" \
    "Versions/B/Autoupdate" \
    "Versions/B/Updater.app"; do
    p="$NESTED_FRAMEWORK/$comp"
    [ -e "$p" ] && codesign -f -s "$SIGN_ID" ${CODESIGN_EXTRA_ARGS[@]+"${CODESIGN_EXTRA_ARGS[@]}"} "$p"
  done
  codesign -f -s "$SIGN_ID" ${CODESIGN_EXTRA_ARGS[@]+"${CODESIGN_EXTRA_ARGS[@]}"} "$NESTED_FRAMEWORK"
fi
ENTITLEMENTS="$TMP_DIR/Cove.entitlements"
plutil -convert xml1 -o "$ENTITLEMENTS" Resources/Cove.entitlements
codesign -f -s "$SIGN_ID" ${CODESIGN_EXTRA_ARGS[@]+"${CODESIGN_EXTRA_ARGS[@]}"} \
  --entitlements "$ENTITLEMENTS" --identifier app.cove.notch "$TMP_APP"

APP=build/Cove.app
rm -rf "$APP"
mv "$TMP_APP" "$APP"
echo "pronto: $APP (v$VERSION)"
