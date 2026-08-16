# Releasing

## Prerequisites

- A clean tagged commit
- Apple Developer Program membership
- A `Developer ID Application` certificate
- App Store Connect API credentials or a configured `notarytool` keychain profile

## Local release

```bash
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="ai-coding-status-bar"
scripts/build-release.sh
```

The script builds Apple Silicon and Intel executables, creates a Universal 2 app, signs it with Hardened Runtime, creates ZIP and DMG containers, notarizes and staples them when `NOTARY_PROFILE` is set, then writes SHA-256 checksums.

For a local test package without Developer ID:

```bash
scripts/build-release.sh
```

This produces an ad-hoc signed package and must not be presented as a trusted public release.

## GitHub Actions secrets

For a signed and notarized release, configure these repository secrets before pushing a `v*` tag:

- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `DEVELOPER_ID_APPLICATION`
- `APPLE_API_KEY_P8_BASE64`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`

When all secrets are present, the Release workflow imports the temporary certificate, configures `notarytool`, builds the packages and creates a trusted GitHub Release using the tagged version.

When the signing secrets are absent, the same workflow creates an **Unsigned Beta** prerelease with ad-hoc signed ZIP and DMG files. This fallback is suitable for early testers, but macOS may require Right-click > Open or approval in Privacy & Security.

## Verification

```bash
codesign --verify --deep --strict --verbose=2 "dist/AI Coding Status Bar.app"
spctl --assess --type execute --verbose=2 "dist/AI Coding Status Bar.app"
shasum -a 256 -c dist/SHA256SUMS.txt
```

Test the downloaded Release on a separate Mac user account before announcing it publicly.
