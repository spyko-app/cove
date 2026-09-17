#!/bin/zsh
# Gera appcast/appcast.xml a partir dos .app/.zip de release, usando o
# generate_appcast oficial do Sparkle (baixado como artefato SwiftPM).
#
# Uso: scripts/gen-appcast.sh <diretório com os .zip/.dmg de release>
#
# Pré-requisito: rodar `swift package resolve` ao menos uma vez (baixa o
# artefato do Sparkle em .build/artifacts/sparkle/Sparkle/bin/generate_appcast).
# A chave privada EdDSA usada pelo generate_appcast fica no Keychain do
# item "Sparkle Private Key EdDSA key" — gerada com o `generate_keys` do
# Sparkle (ver README §Sparkle / task-30-report.md, "passos do dono").
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

# generate_appcast escreve appcast.xml dentro de $RELEASES_DIR — copia pra
# appcast/ (o diretório versionado/hospedado deste repo).
if [ -f "$RELEASES_DIR/appcast.xml" ]; then
  cp "$RELEASES_DIR/appcast.xml" appcast/appcast.xml
  echo "pronto: appcast/appcast.xml"
else
  echo "\033[31merro: generate_appcast não produziu appcast.xml em $RELEASES_DIR\033[0m" >&2
  exit 1
fi
