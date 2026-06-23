# Persona Writing Agent

Minimal Swift/AppKit scaffold for the Persona Writing Agent macOS menu bar app.

## Build

```sh
swift build
```

## Run

```sh
swift run PersonaWritingAgent
```

## MVP Smoke

These smoke commands run mocked XCTest coverage only. They do not launch the
app, call a real LLM API, connect to Slack or ChannelTalk, paste through the
clipboard, or write through Accessibility.

```sh
# Full SwiftPM test suite
bash scripts/mvp-smoke.sh full

# Parser, provider request-building, and correction engine
bash scripts/mvp-smoke.sh parser-provider-engine

# App context adapter registry, Slack fixtures, and ChannelTalk fixtures
bash scripts/mvp-smoke.sh context-adapters
```

The underlying commands are:

```sh
swift test
swift test --filter 'CorrectionResultParserTests|OpenAICompatibleProviderTests|CorrectionEngineTests'
swift test --filter 'AppContextAdapterTests|SlackContextAdapterTests|ChannelTalkContextAdapterTests'
```

Latest local verification on 2026-06-15:

```sh
swift build
bash scripts/mvp-smoke.sh all
```

Result: build passed, focused parser/provider/engine tests passed
(`23 tests, 0 failures`), focused context adapter tests passed
(`15 tests, 0 failures`), and the full mocked XCTest suite passed
(`158 tests, 0 failures`).

## MVP Scope

The current MVP is a SwiftPM/AppKit menu bar prototype with:

- menu bar agent toggles and `Control + Command + O` run command
- provider and persona dashboard screens
- Accessibility-based focused text snapshots with secure-field rejection
- OpenAI-compatible mocked provider pipeline and structured correction parsing
- multi-agent suggestion overlay shell and edit applier strategies
- Slack and ChannelTalk fixture-based visible context adapters
- diagnostics, onboarding, and privacy dashboard copy

Known limitations:

- real Slack/ChannelTalk manual AX smoke testing is still required
- apply actions are wired as preview callbacks; production apply UX still needs user-confirmed integration
- app-specific enable/disable persistence for the current foreground app is not complete
- clipboard fallback is implemented as an opt-in strategy but is not enabled by default
