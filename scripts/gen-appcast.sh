#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

RELEASES_DIR="${1:-}"
if [ -z "$RELEASES_DIR" ] || [ ! -d "$RELEASES_DIR" ]; then
  echo "uso: $0 <diretório com os .zip/.dmg de release>" >&2
  exit 1
fi

GEN_APPCAST=".build/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [ ! -x "$GEN_APPCAST" ]; then
  echo "\033[31merro: $GEN_APPCAST não encontrado — rode 'swift package resolve' primeiro\033[0m" >&2
  exit 1
fi

mkdir -p appcast
"$GEN_APPCAST" "$RELEASES_DIR"

if [ -f "$RELEASES_DIR/appcast.xml" ]; then
  cp "$RELEASES_DIR/appcast.xml" appcast/appcast.xml
  echo "pronto: appcast/appcast.xml"
else
  echo "\033[31merro: generate_appcast não produziu appcast.xml em $RELEASES_DIR\033[0m" >&2
  exit 1
fi
