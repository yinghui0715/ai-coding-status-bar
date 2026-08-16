# Codex Compatibility

AI Coding Status Bar reads local Codex implementation data. These formats may change between Codex releases.

## Discovery order

Codex data directory:

1. `AI_CODING_CODEX_HOME`
2. `CODEX_HOME`
3. `~/.codex`

Codex executable:

1. `AI_CODING_CODEX_EXECUTABLE`
2. ChatGPT desktop app bundled executable
3. Executable named `codex` in `PATH`
4. Common Homebrew locations

## Graceful degradation

- Missing Session directories produce an empty dashboard with a local diagnostic.
- Missing Writer Locks produce `Unknown` rather than a false Running state.
- Missing or incompatible account rate limits produce `Unavailable`.
- Unrecognized JSONL records are ignored.

## Release testing

Before every release:

1. Run unit tests against anonymized JSONL fixtures.
2. Test ChatGPT desktop and standalone Codex CLI installations.
3. Verify an active Writer Lock and an interrupted task.
4. Compare Today Token totals with the source Session events.
5. Verify Weekly Usage falls back to `Unavailable` when the local method changes.

Compatibility is best effort. No Session content should be sent to maintainers without explicit anonymization.
