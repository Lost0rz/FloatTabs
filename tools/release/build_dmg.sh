#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

OUTPUT_DIR="${FLOATTABS_OUTPUT_DIR:-$ROOT_DIR/.release}"
DERIVED_DATA="$OUTPUT_DIR/DerivedData"
STAGE_DIR="$OUTPUT_DIR/dmg-root"
APP_PATH="$DERIVED_DATA/Build/Products/Release/FloatTabs.app"
DSYM_PATH="$DERIVED_DATA/Build/Products/Release/FloatTabs.app.dSYM"
SIGN_IDENTITY="${FLOATTABS_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${FLOATTABS_NOTARY_PROFILE:-}"
REQUIRED_ARCHITECTURES=(arm64 x86_64)

rm -rf "$DERIVED_DATA" "$STAGE_DIR"
mkdir -p "$OUTPUT_DIR" "$STAGE_DIR"

xcodebuild \
  -project FloatTabs.xcodeproj \
  -scheme FloatTabs \
  -resolvePackageDependencies \
  -onlyUsePackageVersionsFromResolvedFile

# v0.1.0 ships one Universal 2 application containing both Apple Silicon and
# Intel slices. Build against a generic macOS destination so the result does not
# collapse to the architecture of whichever runner happens to execute the job.
xcodebuild \
  -project FloatTabs.xcodeproj \
  -scheme FloatTabs \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: Release app not found at $APP_PATH" >&2
  exit 1
fi

verify_universal_binary() {
  local binary="$1"
  local architectures

  architectures="$(lipo -archs "$binary")"
  for required in "${REQUIRED_ARCHITECTURES[@]}"; do
    if [[ " $architectures " != *" $required "* ]]; then
      echo "error: $binary is missing required architecture $required (found: $architectures)" >&2
      return 1
    fi
  done

  echo "Universal binary verified: $binary [$architectures]"
}

verify_universal_app() {
  local app="$1"
  local candidate
  local found_macho=0

  if [[ ! -d "$app" ]]; then
    echo "error: app bundle not found for architecture verification: $app" >&2
    return 1
  fi

  while IFS= read -r -d '' candidate; do
    if /usr/bin/file -b "$candidate" | /usr/bin/grep -q 'Mach-O'; then
      found_macho=1
      verify_universal_binary "$candidate"
    fi
  done < <(/usr/bin/find "$app/Contents" -type f -print0)

  if ((found_macho == 0)); then
    echo "error: no Mach-O binaries found in $app" >&2
    return 1
  fi
}

verify_universal_app "$APP_PATH"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$OUTPUT_DIR/FloatTabs-$VERSION.dmg"
DSYM_ARCHIVE_PATH="$OUTPUT_DIR/FloatTabs-$VERSION.dSYM.zip"

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing FloatTabs.app with Developer ID identity: $SIGN_IDENTITY"
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$APP_PATH"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
else
  echo "Building unsigned QA app (no FLOATTABS_SIGN_IDENTITY supplied)."
fi

if [[ ! -d "$DSYM_PATH" ]]; then
  echo "error: Release dSYM not found at $DSYM_PATH" >&2
  exit 1
fi
rm -f "$DSYM_ARCHIVE_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$DSYM_PATH" "$DSYM_ARCHIVE_PATH"

/usr/bin/ditto "$APP_PATH" "$STAGE_DIR/FloatTabs.app"
verify_universal_app "$STAGE_DIR/FloatTabs.app"
ln -s /Applications "$STAGE_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "FloatTabs $VERSION" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

# On fresh macOS runners diskimages-helper can hold the newly-created image for
# a short moment after `hdiutil create` returns. Retry verification only for
# that transient handoff; a persistently invalid DMG still fails the build.
verify_dmg() {
  local attempt
  local max_attempts=5

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if hdiutil verify "$DMG_PATH"; then
      return 0
    fi

    if ((attempt == max_attempts)); then
      echo "error: DMG verification failed after $max_attempts attempts: $DMG_PATH" >&2
      return 1
    fi

    echo "DMG verify attempt $attempt failed; retrying in 2 seconds..." >&2
    sleep 2
  done
}

verify_dmg

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "error: FLOATTABS_NOTARY_PROFILE requires FLOATTABS_SIGN_IDENTITY." >&2
    exit 1
  fi

  echo "Submitting DMG for notarization with keychain profile: $NOTARY_PROFILE"
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
  echo "Signed/notarized Universal 2 DMG ready: $DMG_PATH"
else
  echo "Universal 2 QA DMG ready: $DMG_PATH"
  echo "Architectures: ${REQUIRED_ARCHITECTURES[*]}"
  echo "Version: $VERSION ($BUILD)"
  echo "NOTE: This is not a public notarized release unless Developer ID + notary credentials were supplied."
fi

/usr/bin/shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
/usr/bin/shasum -a 256 "$DSYM_ARCHIVE_PATH" > "$DSYM_ARCHIVE_PATH.sha256"
echo "Debug symbols: $DSYM_ARCHIVE_PATH"
echo "Checksums: $DMG_PATH.sha256 and $DSYM_ARCHIVE_PATH.sha256"
