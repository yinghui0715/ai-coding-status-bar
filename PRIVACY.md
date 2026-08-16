# Privacy

AI Coding Status Bar is a local-only macOS utility.

## Data the app reads

The app may read the following data on the current Mac:

- Codex Session JSONL files
- Codex Thread Writer Lock files
- Codex project metadata
- Local account rate-limit information exposed by the installed Codex `app-server`

This data can include project paths, task titles, timestamps and token counts.

## Data storage

Normalized task history and token deltas are stored locally at:

```text
~/Library/Application Support/AICodingStatusBar/status.sqlite
```

Deleting this folder removes the app's persisted history.

## Network and telemetry

The app does not include analytics, advertising, crash-reporting or telemetry SDKs. It does not implement an upload endpoint for Session content. Weekly account limits are requested through the locally installed Codex `app-server`, which may use Codex's normal account connectivity.

## Screenshots and bug reports

Session titles and project paths may be sensitive. Before opening a public Issue, remove or anonymize screenshots, logs, database files and Session content.

## Changes

Any future feature that transmits local Codex data must be documented here and made explicit to the user before release.
