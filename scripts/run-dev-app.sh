#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$("$ROOT_DIR/scripts/build-dev-app.sh" | tail -n 1)"
APP_EXEC="$APP_DIR/Contents/MacOS/Overlaygent"

launchctl remove OverlaygentDev 2>/dev/null || true
pkill -x Overlaygent 2>/dev/null || true

open -n "$APP_DIR"

APP_PID=""
for _ in {1..20}; do
  APP_PID="$(pgrep -f "$APP_EXEC" | head -n 1 || true)"
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
codesign -dv --verbose=2 "$APP_EXEC" 2>&1 | sed -n '1,18p'
