#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=xcode-env.sh
source "$ROOT/scripts/xcode-env.sh"

if [[ "${SKIP_XCODEGEN:-0}" != "1" ]]; then
  command -v xcodegen >/dev/null || { echo "error: xcodegen missing (https://github.com/yonaskolb/XcodeGen)" >&2; exit 1; }
  xcodegen generate --quiet
fi

CONFIGURATION="${CONFIGURATION:-Debug}"
INSTALL="${INSTALL:-0}"

xcodebuild \
  -project Joyflow.xcodeproj \
  -scheme Joyflow \
  -destination 'platform=macOS' \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$ROOT/.derivedData" \
  build

APP="$ROOT/.derivedData/Build/Products/${CONFIGURATION}/Joyflow.app"
if [[ ! -d "$APP" ]]; then
  echo "error: Joyflow.app not produced at $APP" >&2
  exit 1
fi
ICON="$ROOT/Joyflow/Resources/AppIcon.icns"
if [[ -f "$ICON" ]]; then
  cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
fi

if [[ "$INSTALL" == "1" || "$INSTALL" == "true" ]]; then
  DEST="${HOME}/Applications/Joyflow.app"
  mkdir -p "${HOME}/Applications"
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  echo "INSTALLED $DEST"
  if [[ -w /Applications ]]; then
    rm -rf /Applications/Joyflow.app
    ditto "$APP" /Applications/Joyflow.app
    echo "INSTALLED /Applications/Joyflow.app"
  fi
fi

echo "BUILD_OK $APP"
