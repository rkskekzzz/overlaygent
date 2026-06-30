# Overlaygent

Minimal Swift/AppKit scaffold for the Overlaygent macOS menu bar app.

## Public Documentation

- [Privacy Policy](docs/PRIVACY.md)
- [Support](docs/SUPPORT.md)
- [Public release checklist](PUBLIC_RELEASE_CHECKLIST.md)

## License

Overlaygent is released under the [MIT License](LICENSE).

## Build

```sh
swift build
```

## Direct Release Build

Release artifacts are built separately from local dev artifacts so the
production bundle id does not inherit dev defaults.

```sh
scripts/build-release-app.sh
scripts/package-release-dmg.sh
```

Defaults:

- bundle id: `com.suhshin.overlaygent`
- app name: `Overlaygent`
- version/build: `0.1.0` / `1`

To notarize the generated DMG, first create a local notarytool keychain profile,
then run:

```sh
OVERLAYGENT_NOTARY_PROFILE=my-notary scripts/notarize-release-dmg.sh
scripts/verify-release-artifacts.sh
```

Without notarization, Gatekeeper assessment is expected to reject the Developer
ID-signed app as `Unnotarized Developer ID`.

The notarization script staples the ticket and rewrites the `.sha256` file after
stapling, because stapling changes the DMG bytes.

## Run

```sh
swift run Overlaygent
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
