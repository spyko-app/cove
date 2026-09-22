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

# Name the image after what is actually inside it, so a thin build can never be
# mistaken for (or overwrite) the universal one on a Releases page.
ARCHS=$(lipo -archs "$APP/Contents/MacOS/Cove")
case "$ARCHS" in
  *arm64*x86_64*|*x86_64*arm64*) SUFFIX="" ;;
  *x86_64*)                      SUFFIX="-intel" ;;
  *arm64*)                       SUFFIX="-applesilicon" ;;
  *)
    echo "\033[31merro: arquitetura inesperada em $APP: '$ARCHS'\033[0m" >&2
    exit 1
    ;;
esac
if [ -n "$SUFFIX" ]; then
  echo "\033[33maviso: $APP é apenas '$ARCHS' — gerando DMG específico dessa arquitetura\033[0m" >&2
  echo "\033[33muse ./scripts/make-app.sh --universal para um build arm64+x86_64\033[0m" >&2
fi

DMG="build/Cove-$VERSION$SUFFIX.dmg"
STAGE=$(mktemp -d "build/.dmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/Cove.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Cove" -srcfolder "$STAGE" -fs APFS \
  -format UDZO -imagekey zlib-level=9 -quiet "$DMG"

echo "pronto: $DMG ($ARCHS, $(du -h "$DMG" | cut -f1))"
