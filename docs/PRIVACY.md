# Overlaygent Privacy Policy

Last updated: 2026-06-30

Overlaygent is a macOS menu bar writing assistant. It runs locally on your Mac and sends writing-assistance requests only when you explicitly run an active agent.

## What Overlaygent reads

Overlaygent may read:

- the text in the currently focused editable field;
- selected text, if you have selected text before running an agent;
- basic foreground app information needed for compatibility and app rules;
- optional visible app context, such as nearby conversation text in supported apps, when that feature is enabled.

Overlaygent is designed to reject secure text fields, password fields, and unsupported private input states.

## What is sent to LLM providers

When you run an agent, Overlaygent sends the minimum request data needed for the selected writing task to your configured third-party LLM provider. This may include:

- the current input text or selected text;
- the active agent instructions, tone, and terminology rules;
- optional visible app context, if you enabled that context feature;
- provider settings such as model name and endpoint.

The third-party LLM provider processes this data under its own terms and privacy policy. Do not use Overlaygent with sensitive text unless you are comfortable sending that text to the provider you configured.

## API keys and local settings

Overlaygent stores API keys in the local macOS Keychain. Non-secret settings, such as provider name, base URL, model, agent configuration, and app preferences, may be stored locally on your Mac.

Overlaygent does not require an Overlaygent account and does not operate an Overlaygent cloud service for the current open-source release.

## Response storage and retention

By default, Overlaygent does not cache LLM responses. Request results are used for the current correction run and are not retained by Overlaygent after the run.

Some local configuration data, such as provider settings, agent profiles, and app rules, remains on your Mac until you change or delete it.

## Clipboard fallback

Clipboard fallback is disabled by default. If a future setting enables clipboard fallback, Overlaygent should only use it as an explicit opt-in compatibility path for apps where direct Accessibility-based reading or writing is not available.

## Logs and diagnostics

Overlaygent diagnostics are intended to avoid raw input text, provider responses, and API keys. If you share logs or screenshots when reporting an issue, review them first and remove any sensitive information.

## Data deletion

You can remove local Overlaygent data by deleting saved provider settings, agent profiles, and related app configuration from the app when deletion controls are available. API keys can also be removed from macOS Keychain.

Until in-app deletion controls are complete, advanced users can remove local development data manually from their macOS user Library and Keychain. Be careful when deleting Keychain items or application support files.

## Contact

For privacy questions or issue reports, open an issue at:

https://github.com/rkskekzzz/overlaygent/issues
