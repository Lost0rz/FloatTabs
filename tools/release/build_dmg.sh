#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

OUTPUT_DIR="${FLOATTABS_OUTPUT_DIR:-$ROOT_DIR/.release}"
DERIVED_DATA="$OUTPUT_DIR/DerivedData"
STAGE_DIR="$OUTPUT_DIR/dmg-root"
APP_PATH="$DERIVED_DATA/Build/Products/Release/FloatTabs.app"
SIGN_IDENTITY="${FLOATTABS_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${FLOATTABS_NOTARY_PROFILE:-}"

rm -rf "$DERIVED_DATA" "$STAGE_DIR"
mkdir -p "$OUTPUT_DIR" "$STAGE_DIR"

xcodebuild   -project FloatTabs.xcodeproj   -scheme FloatTabs   -resolvePackageDependencies   -onlyUsePackageVersionsFromResolvedFile

xcodebuild   -project FloatTabs.xcodeproj   -scheme FloatTabs   -configuration Release   -destination 'platform=macOS,arch=arm64'   -derivedDataPath "$DERIVED_DATA"   CODE_SIGNING_ALLOWED=NO   build

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: Release app not found at $APP_PATH" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$OUTPUT_DIR/FloatTabs-$VERSION.dmg"

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing FloatTabs.app with Developer ID identity: $SIGN_IDENTITY"
  codesign     --force     --deep     --options runtime     --timestamp     --sign "$SIGN_IDENTITY"     "$APP_PATH"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
else
  echo "Building unsigned QA app (no FLOATTABS_SIGN_IDENTITY supplied)."
fi

/usr/bin/ditto "$APP_PATH" "$STAGE_DIR/FloatTabs.app"
ln -s /Applications "$STAGE_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create   -volname "FloatTabs $VERSION"   -srcfolder "$STAGE_DIR"   -ov   -format UDZO   "$DMG_PATH"

hdiutil verify "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "error: FLOATTABS_NOTARY_PROFILE requires FLOATTABS_SIGN_IDENTITY." >&2
    exit 1
  fi
  echo "Submitting DMG for notarization with keychain profile: $NOTARY_PROFILE"
  xcrun notarytool submit "$DMG_PATH"     --keychain-profile "$NOTARY_PROFILE"     --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  echo "Signed/notarized DMG ready: $DMG_PATH"
else
  echo "QA DMG ready: $DMG_PATH"
  echo "Version: $VERSION ($BUILD)"
  echo "NOTE: This is not a public notarized release unless Developer ID + notary credentials were supplied."
fi
