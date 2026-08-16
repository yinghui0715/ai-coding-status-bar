# Contributing

## Development setup

Requirements:

- macOS 14+
- Xcode 16 or newer with Swift 6
- SQLite 3 system library

Run the local checks before submitting a pull request:

```bash
swift test
swift build -c release
```

## Pull requests

- Keep the Collector independent from SwiftUI.
- Do not add mock values to production data paths.
- Preserve graceful fallback when an optional Codex source is unavailable.
- Add or update tests when changing Session parsing or path discovery.
- Never commit Session files, local databases, signing credentials or screenshots containing real task content.

## Compatibility reports

When reporting a parser regression, provide an anonymized minimal JSONL fixture rather than a complete Session.
