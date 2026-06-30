# Overlaygent Support

Last updated: 2026-06-30

Overlaygent is an open-source macOS menu bar writing assistant.

## Getting help

For bugs, installation problems, feature requests, or privacy questions, open a GitHub issue:

https://github.com/rkskekzzz/overlaygent/issues

When reporting a bug, include:

- your macOS version;
- Overlaygent version;
- the app you were using, such as Slack, ChannelTalk, Discord, Notion, or VS Code;
- what you expected to happen;
- what actually happened;
- whether Accessibility permission is enabled for Overlaygent.

Do not include API keys, private messages, provider responses, or other sensitive text in public issues.

## Installation notes

Overlaygent is distributed as a Developer ID-signed and notarized macOS app. For direct distribution builds, download the DMG, open it, and drag Overlaygent into `/Applications`.

If macOS blocks the app, verify that you downloaded the notarized release artifact from the project repository or another trusted release page.

## Required macOS permission

Overlaygent needs Accessibility permission to read the currently focused editable field and position its suggestion overlay.

To enable it:

1. Open System Settings.
2. Go to Privacy & Security.
3. Open Accessibility.
4. Enable Overlaygent.
5. Restart Overlaygent if the permission state does not update immediately.

## LLM provider setup

Overlaygent uses your configured LLM provider. The current release is designed around OpenAI-compatible chat completion providers.

You are responsible for:

- creating and managing your provider API key;
- selecting the model and endpoint;
- reviewing the provider's pricing, terms, and privacy policy.

## Known limitations

- App compatibility varies because macOS Accessibility support differs across apps.
- Electron-based apps may require additional Accessibility handling.
- Rich text editors may not preserve all formatting.
- Clipboard fallback is disabled by default.
- Local data deletion controls and App Rules UI are still release-readiness follow-up items.

## Security and privacy reports

For sensitive security or privacy issues, avoid posting private details in a public issue. Open a minimal GitHub issue requesting a private coordination path, or contact the maintainer through the repository owner profile.
