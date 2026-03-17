#!/bin/zsh

set -euo pipefail

APP_NAME="AppOrigins"
APP_BUNDLE="dist/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICON_SOURCE="assets/${APP_NAME}.icns"

rm -rf dist dmg "${APP_NAME}.dmg"
swift build -c release
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"
cp ".build/release/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

if [[ -f "${ICON_SOURCE}" ]]; then
  cp "${ICON_SOURCE}" "${RESOURCES_DIR}/${APP_NAME}.icns"
fi

/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string ${APP_NAME}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.usamaansari.${APP_NAME}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string ${APP_NAME}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string ${APP_NAME}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "${CONTENTS_DIR}/Info.plist"

if [[ -f "${ICON_SOURCE}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ${APP_NAME}" "${CONTENTS_DIR}/Info.plist"
fi

mkdir -p dmg
cp -R "${APP_BUNDLE}" dmg/
ln -s /Applications dmg/Applications
hdiutil create -volname "${APP_NAME}" -srcfolder dmg -ov -format UDZO "${APP_NAME}.dmg"
