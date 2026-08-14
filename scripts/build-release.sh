#!/usr/bin/env bash
# Archive + export a Developer ID-signed, hardened-runtime Joyflow.app.
# Does not notarize — run scripts/notarize.sh next.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=xcode-env.sh
source "$ROOT/scripts/xcode-env.sh"

command -v xcodegen >/dev/null || { echo "error: xcodegen missing" >&2; exit 1; }
xcodegen generate --quiet

BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
rm -rf "$BUILD_DIR/Joyflow.xcarchive" "$BUILD_DIR/export"
mkdir -p "$BUILD_DIR"

echo "▸ Archiving Release…"
xcodebuild \
  -project Joyflow.xcodeproj \
  -scheme Joyflow \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  archive \
  -archivePath "$BUILD_DIR/Joyflow.xcarchive" \
  -derivedDataPath "$ROOT/.derivedData"

echo "▸ Exporting Developer ID app…"
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/Joyflow.xcarchive" \
  -exportPath "$BUILD_DIR/export" \
  -exportOptionsPlist "$ROOT/ExportOptions.plist"

APP="$BUILD_DIR/export/Joyflow.app"
if [[ ! -d "$APP" ]]; then
  echo "error: export missing $APP" >&2
  exit 1
fi

echo "RELEASE_OK $APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E "Authority|Runtime|Identifier" || true
echo "Next: scripts/notarize.sh"
