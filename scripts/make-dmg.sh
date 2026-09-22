#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Cove.app"
if [ ! -d "$APP" ]; then
  echo "\033[31merro: $APP não existe — rode ./scripts/make-app.sh --universal primeiro\033[0m" >&2
  exit 1
fi

VERSION=$(tr -d '[:space:]' < VERSION)
BUNDLE_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
if [ "$BUNDLE_VERSION" != "$VERSION" ]; then
  echo "\033[31merro: $APP é v$BUNDLE_VERSION mas VERSION diz $VERSION — rebuilde o app\033[0m" >&2
  exit 1
fi

ARCHS=$(lipo -archs "$APP/Contents/MacOS/Cove")
case "$ARCHS" in
  *arm64*x86_64*|*x86_64*arm64*) ;;
  *)
    echo "\033[33maviso: $APP é apenas '$ARCHS' — o DMG não será universal\033[0m" >&2
    echo "\033[33muse ./scripts/make-app.sh --universal para um build arm64+x86_64\033[0m" >&2
    ;;
esac

DMG="build/Cove-$VERSION.dmg"
STAGE=$(mktemp -d "build/.dmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/Cove.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Cove" -srcfolder "$STAGE" -fs APFS \
  -format UDZO -imagekey zlib-level=9 -quiet "$DMG"

echo "pronto: $DMG ($ARCHS, $(du -h "$DMG" | cut -f1))"
