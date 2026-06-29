#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/dev-app/Overlaygent.app"
APP_EXEC="$APP_DIR/Contents/MacOS/Overlaygent"

find_app_pid() {
  ps -axo pid=,args= | awk -v exe="$APP_EXEC" '$2 == exe { print $1; exit }'
}

launchctl remove OverlaygentDev 2>/dev/null || true
pkill -x Overlaygent 2>/dev/null || true
pkill -f "$APP_EXEC" 2>/dev/null || true

for _ in {1..80}; do
  if [[ -z "$(find_app_pid)" ]]; then
    break
  fi
  sleep 0.25
done

bash "$ROOT_DIR/scripts/build-dev-app.sh"

open -n "$APP_DIR"

APP_PID=""
for _ in {1..80}; do
  APP_PID="$(find_app_pid)"
  if [[ -n "$APP_PID" ]]; then
    break
  fi
  sleep 0.25
done

if [[ -z "$APP_PID" ]]; then
  echo "Overlaygent failed to stay running after launch." >&2
  exit 1
fi

echo "$APP_PID $APP_EXEC"
codesign -dv --verbose=2 "$APP_EXEC" 2>&1 | sed -n '1,18p' || true
