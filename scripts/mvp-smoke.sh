#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

log() {
    printf '[mvp-smoke] %s\n' "$*"
}

usage() {
    cat <<'USAGE'
Usage: bash scripts/mvp-smoke.sh [full|parser-provider-engine|context-adapters|all]

Runs SwiftPM XCTest smoke checks only. These commands use mocked fixtures and do
not launch the app, call an LLM API, connect to Slack/ChannelTalk, paste from
the clipboard, or write through Accessibility.
USAGE
}

run_step() {
    local label="$1"
    shift

    log "START: ${label}"
    log "CMD: $*"
    "$@"
    local status=$?

    if [ "${status}" -ne 0 ]; then
        log "FAILED (${status}): ${label}"
        exit "${status}"
    fi

    log "OK: ${label}"
}

cd "${ROOT_DIR}" || exit 1

mode="${1:-full}"

case "${mode}" in
    full)
        run_step "full mocked XCTest suite" swift test
        ;;
    parser-provider-engine)
        run_step \
            "parser/provider/engine focused tests" \
            swift test --filter 'CorrectionResultParserTests|OpenAICompatibleProviderTests|CorrectionEngineTests'
        ;;
    context-adapters)
        run_step \
            "context adapter focused tests" \
            swift test --filter 'AppContextAdapterTests|SlackContextAdapterTests|ChannelTalkContextAdapterTests'
        ;;
    all)
        run_step \
            "parser/provider/engine focused tests" \
            swift test --filter 'CorrectionResultParserTests|OpenAICompatibleProviderTests|CorrectionEngineTests'
        run_step \
            "context adapter focused tests" \
            swift test --filter 'AppContextAdapterTests|SlackContextAdapterTests|ChannelTalkContextAdapterTests'
        run_step "full mocked XCTest suite" swift test
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        log "Unknown smoke mode: ${mode}"
        usage
        exit 64
        ;;
esac
