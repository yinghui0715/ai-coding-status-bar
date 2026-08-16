# Security Policy

## Reporting a vulnerability

Please use GitHub Private Vulnerability Reporting when it is enabled for the repository. Do not include real Codex Session files, task content, access tokens, account identifiers or local database files in a public Issue.

Include the affected version, macOS version, Codex installation type and a minimal anonymized reproduction.

## Supported versions

Security fixes are applied to the latest published release.

## Trust model

The application reads local Codex data and launches the locally installed Codex executable for an account rate-limit request. Release binaries should therefore be built from tagged source, signed with Developer ID, notarized by Apple and accompanied by a SHA-256 checksum.
