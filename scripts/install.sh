#!/usr/bin/env bash
set -euo pipefail

# Builds the app and installs it as /Applications/MacTubeConverter.app.
# An existing copy is moved to the Trash first (reversible), never deleted.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MacTubeConverter"
DEST="${MACTUBE_INSTALL_DIR:-/Applications}/$APP_NAME.app"

"$ROOT_DIR/scripts/build-app.sh"
SOURCE="$ROOT_DIR/build/$APP_NAME.app"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

if [[ -e "$DEST" ]]; then
  STAMP="$(date +%Y%m%d-%H%M%S)"
  mv "$DEST" "$HOME/.Trash/$APP_NAME-$STAMP.app"
  echo "Moved the previous copy to the Trash."
fi

ditto "$SOURCE" "$DEST"
codesign --verify --strict "$DEST"
echo "Installed $DEST"
