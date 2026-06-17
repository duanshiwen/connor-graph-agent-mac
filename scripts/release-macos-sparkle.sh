#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="${SCHEME:-ConnorGraphAgentMacApp}"
PROJECT="${PROJECT:-$ROOT/ConnorGraphAgentMac.xcodeproj}"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT/build/release/ConnorGraphAgentMacApp.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT/build/release/export}"
ARCHIVES_DIR="${ARCHIVES_DIR:-$ROOT/build/release/appcast-archives}"
APPCAST_OUTPUT="${APPCAST_OUTPUT:-$ARCHIVES_DIR/appcast.xml}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/duanshiwen/connor-graph-agent-mac/releases/download/${GITHUB_REF_NAME:-local}}"
SPARKLE_BIN_DIR="${SPARKLE_BIN_DIR:-$ROOT/.build/artifacts/sparkle/Sparkle/bin}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-com.shiwen.connor-graph-agent-mac}"
APP_NAME="${APP_NAME:-康纳同学}"
ARTIFACT_BASENAME="${ARTIFACT_BASENAME:-ConnorGraphAgentMac}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$ROOT/scripts/export-options-developer-id.plist}"

mkdir -p "$ROOT/build/release" "$EXPORT_PATH" "$ARCHIVES_DIR"

swift package resolve

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

APP_PATH="$EXPORT_PATH/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at $APP_PATH" >&2
  find "$EXPORT_PATH" -maxdepth 2 -print >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
ZIP_NAME="${ARTIFACT_BASENAME}-${VERSION}-${BUILD}.zip"
ZIP_PATH="$ARCHIVES_DIR/$ZIP_NAME"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
  xcrun stapler staple "$APP_PATH"
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
else
  echo "Skipping notarization: set NOTARY_PROFILE or APPLE_ID/APPLE_TEAM_ID/APPLE_APP_SPECIFIC_PASSWORD."
fi

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN_DIR/generate_appcast" \
    --ed-key-file - \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    -o "$APPCAST_OUTPUT" \
    "$ARCHIVES_DIR"
else
  "$SPARKLE_BIN_DIR/generate_appcast" \
    --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    -o "$APPCAST_OUTPUT" \
    "$ARCHIVES_DIR"
fi

echo "Release artifact: $ZIP_PATH"
echo "Sparkle appcast: $APPCAST_OUTPUT"
