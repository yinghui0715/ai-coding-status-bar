#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AI Coding Status Bar"
PRODUCT_NAME="AICodingStatusBar"
INFO_PLIST="$PROJECT_ROOT/Resources/Info.plist"
DIST_DIR="$PROJECT_ROOT/dist"
BUILD_ROOT="$(mktemp -d "$PROJECT_ROOT/.build/release.XXXXXX")"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
ARCHS="${ARCHS:-arm64 x86_64}"
SWIFT_OPTIMIZATION="${SWIFT_OPTIMIZATION:--O}"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/clang-module-cache"

cleanup() {
  rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Release packaging requires macOS." >&2
  exit 1
fi

if ! xcrun xcodebuild -version >/dev/null 2>&1; then
  echo "Full Xcode 16 or newer is required to build release packages." >&2
  echo "Install Xcode, then select it with: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
ZIP_PATH="$DIST_DIR/AI-Coding-Status-Bar-v$VERSION-universal.zip"
DMG_PATH="$DIST_DIR/AI-Coding-Status-Bar-v$VERSION-universal.dmg"

if [[ "$DIST_DIR" != "$PROJECT_ROOT/dist" ]]; then
  echo "Refusing to clean an unexpected output directory." >&2
  exit 1
fi
rm -rf "$DIST_DIR"
mkdir -p "$MACOS_DIR"

SOURCE_FILES=(
  "$PROJECT_ROOT/Sources/AICodingStatusBar/App.swift"
  "$PROJECT_ROOT/Sources/AICodingStatusBar/CodexEnvironment.swift"
  "$PROJECT_ROOT/Sources/AICodingStatusBar/CodexSources.swift"
  "$PROJECT_ROOT/Sources/AICodingStatusBar/Collector.swift"
  "$PROJECT_ROOT/Sources/AICodingStatusBar/Database.swift"
  "$PROJECT_ROOT/Sources/AICodingStatusBar/Models.swift"
  "$PROJECT_ROOT/Sources/AICodingStatusBar/DashboardView.swift"
)

BINARIES=()
for ARCH in $ARCHS; do
  OUTPUT="$BUILD_ROOT/$PRODUCT_NAME-$ARCH"
  echo "Building $PRODUCT_NAME for $ARCH..."
  xcrun swiftc \
    -parse-as-library \
    "$SWIFT_OPTIMIZATION" \
    -target "$ARCH-apple-macosx14.0" \
    -I "$PROJECT_ROOT/Sources/CSQLite" \
    "${SOURCE_FILES[@]}" \
    -o "$OUTPUT" \
    -lsqlite3 \
    -framework SwiftUI \
    -framework AppKit
  BINARIES+=("$OUTPUT")
done

if [[ "${#BINARIES[@]}" -eq 1 ]]; then
  ditto "${BINARIES[0]}" "$MACOS_DIR/$PRODUCT_NAME"
else
  xcrun lipo -create "${BINARIES[@]}" -output "$MACOS_DIR/$PRODUCT_NAME"
fi

ditto "$INFO_PLIST" "$CONTENTS/Info.plist"
chmod 755 "$MACOS_DIR/$PRODUCT_NAME"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "Creating an ad-hoc signed development package."
  codesign --force --sign - "$APP_BUNDLE"
else
  echo "Signing with Developer ID: $SIGN_IDENTITY"
  codesign \
    --force \
    --sign "$SIGN_IDENTITY" \
    --options runtime \
    --timestamp \
    "$APP_BUNDLE"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "NOTARY_PROFILE requires a Developer ID signature." >&2
    exit 1
  fi
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
  rm -f "$ZIP_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
fi

DMG_SOURCE="$BUILD_ROOT/dmg"
mkdir -p "$DMG_SOURCE"
ditto "$APP_BUNDLE" "$DMG_SOURCE/$APP_NAME.app"
ln -s /Applications "$DMG_SOURCE/Applications"
hdiutil create \
  -quiet \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_SOURCE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
fi

(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$ZIP_PATH")" "$(basename "$DMG_PATH")" > SHA256SUMS.txt
)

echo
echo "Release artifacts:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
echo "  $DIST_DIR/SHA256SUMS.txt"
