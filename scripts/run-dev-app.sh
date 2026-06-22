#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$("$ROOT_DIR/scripts/build-dev-app.sh" | tail -n 1)"

launchctl remove PersonaWritingAgentDev 2>/dev/null || true
pkill -x PersonaWritingAgent 2>/dev/null || true

open -n "$APP_DIR"
sleep 2

pgrep -fl PersonaWritingAgent || true
codesign -dv --verbose=2 "$APP_DIR" 2>&1 | sed -n '1,18p'
