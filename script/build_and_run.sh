#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
case "$MODE" in run|--verify|--logs|--debug|--telemetry) ;; *) exit 2 ;; esac
pkill -x MacTubeConverter >/dev/null 2>&1 || true
"$ROOT_DIR/scripts/build-app.sh"
APP="$ROOT_DIR/build/MacTubeConverter.app"
if [[ "$MODE" == "--debug" ]]; then
  lldb -- "$APP/Contents/MacOS/MacTubeConverter"
else
  /usr/bin/open -n "$APP"
  case "$MODE" in
    --verify) sleep 1; pgrep -x MacTubeConverter >/dev/null ;;
    --logs|--telemetry) /usr/bin/log stream --info --predicate 'process == "MacTubeConverter"' ;;
  esac
fi
