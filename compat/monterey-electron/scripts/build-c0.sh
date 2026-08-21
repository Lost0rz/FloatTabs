#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
BUILD_ROOT="${PROJECT_DIR}/build/c0"
PACKAGED_DIR="${BUILD_ROOT}/packaged"
DMG_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/floattabs-monterey-c0-dmg.XXXXXX")"
APP_NAME="FloatTabs Monterey Chromium Baseline"
BUNDLE_ID="com.lost0rz.FloatTabs.MontereyChromiumBaseline"
APP_VERSION="0.1.3"
DOWNLOADS_DIR="${HOME}/Downloads"
DMG_PATH="${DOWNLOADS_DIR}/FloatTabs-0.1.3-Monterey-Chromium-C0-x64.dmg"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "MC-C0 build requires macOS for x64 Electron packaging." >&2
  exit 1
fi

mkdir -p "${PACKAGED_DIR}" "${DOWNLOADS_DIR}"

cd "${PROJECT_DIR}"
ELECTRON_INSTALL_ARCH=x64 npm_config_arch=x64 npm ci

ELECTRON_INSTALL_ARCH=x64 npm_config_arch=x64 "${PROJECT_DIR}/node_modules/.bin/electron-packager" "${PROJECT_DIR}" "${APP_NAME}" \
  --platform=darwin \
  --arch=x64 \
  --out="${PACKAGED_DIR}" \
  --overwrite \
  --prune=true \
  --app-bundle-id="${BUNDLE_ID}" \
  --app-version="${APP_VERSION}" \
  --build-version="${APP_VERSION}"

APP_PATH="${PACKAGED_DIR}/${APP_NAME}-darwin-x64/${APP_NAME}.app"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "Packaged application not found: ${APP_PATH}" >&2
  exit 1
fi

/usr/bin/plutil -replace LSMinimumSystemVersion -string 12.0 "${APP_PATH}/Contents/Info.plist"
codesign --force --deep --sign - "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

cp -R "${APP_PATH}" "${DMG_STAGE}/"
ln -s /Applications "${DMG_STAGE}/Applications"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${DMG_STAGE}" \
  -format UDZO \
  -ov \
  "${DMG_PATH}"
hdiutil verify "${DMG_PATH}"

echo "DMG: ${DMG_PATH}"
shasum -a 256 "${DMG_PATH}"
