#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

DEPLOYMENT_TARGET="${FLOATTABS_MONTEREY_TARGET:-12.0}"
OUTPUT_DIR="${FLOATTABS_OUTPUT_DIR:-$ROOT_DIR/.release-monterey}"
DERIVED_DATA="$OUTPUT_DIR/DerivedData"
STAGE_DIR="$OUTPUT_DIR/dmg-root"
APP_PATH="$DERIVED_DATA/Build/Products/Release/FloatTabs.app"
DSYM_PATH="$DERIVED_DATA/Build/Products/Release/FloatTabs.app.dSYM"
REQUIRED_ARCHITECTURES=(arm64 x86_64)

python3 tools/release/prepare_monterey_sources.py
python3 tools/release/prepare_monterey_webview.py

rm -rf "$DERIVED_DATA" "$STAGE_DIR"
mkdir -p "$OUTPUT_DIR" "$STAGE_DIR"

xcodebuild \
  -project FloatTabs.xcodeproj \
  -scheme FloatTabs \
  -resolvePackageDependencies \
  -onlyUsePackageVersionsFromResolvedFile

xcodebuild \
  -project FloatTabs.xcodeproj \
  -scheme FloatTabs \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: Release app not found at $APP_PATH" >&2
  exit 1
fi

MAIN_BINARY="$APP_PATH/Contents/MacOS/FloatTabs"
ARCHS_FOUND="$(lipo -archs "$MAIN_BINARY")"
for required in "${REQUIRED_ARCHITECTURES[@]}"; do
  if [[ " $ARCHS_FOUND " != *" $required "* ]]; then
    echo "error: missing architecture $required (found: $ARCHS_FOUND)" >&2
    exit 1
  fi
done

MIN_OS_VALUES="$(otool -l "$MAIN_BINARY" | awk '$1 == "minos" {print $2}' | sort -u)"
if [[ -z "$MIN_OS_VALUES" ]]; then
  echo "error: could not resolve LC_BUILD_VERSION minos" >&2
  exit 1
fi
while IFS= read -r min_os; do
  if [[ "$min_os" != "$DEPLOYMENT_TARGET" ]]; then
    echo "error: binary minos is $min_os, expected $DEPLOYMENT_TARGET" >&2
    exit 1
  fi
done <<< "$MIN_OS_VALUES"

PLIST_MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_PATH/Contents/Info.plist")"
if [[ "$PLIST_MIN_OS" != "$DEPLOYMENT_TARGET" ]]; then
  echo "error: Info.plist LSMinimumSystemVersion is $PLIST_MIN_OS, expected $DEPLOYMENT_TARGET" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
PACKAGE_BASE="FloatTabs-${VERSION}-monterey"
DMG_PATH="$OUTPUT_DIR/$PACKAGE_BASE.dmg"
DSYM_ARCHIVE_PATH="$OUTPUT_DIR/$PACKAGE_BASE.dSYM.zip"

if [[ ! -d "$DSYM_PATH" ]]; then
  echo "error: Release dSYM not found at $DSYM_PATH" >&2
  exit 1
fi

rm -f "$DSYM_ARCHIVE_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$DSYM_PATH" "$DSYM_ARCHIVE_PATH"
/usr/bin/ditto "$APP_PATH" "$STAGE_DIR/FloatTabs.app"
ln -s /Applications "$STAGE_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "FloatTabs $VERSION Monterey" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

hdiutil verify "$DMG_PATH"

(
  cd "$OUTPUT_DIR"
  /usr/bin/shasum -a 256 "$PACKAGE_BASE.dmg" > "$PACKAGE_BASE.dmg.sha256"
  /usr/bin/shasum -a 256 "$PACKAGE_BASE.dSYM.zip" > "$PACKAGE_BASE.dSYM.zip.sha256"
)

echo "Monterey compatibility package ready"
echo "Version: $VERSION (Build $BUILD)"
echo "Minimum macOS: $DEPLOYMENT_TARGET"
echo "Architectures: $ARCHS_FOUND"
echo "DMG: $DMG_PATH"
