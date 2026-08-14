#!/usr/bin/env bash
# Release-build Joyflow and wrap it in a UDZO disk image:
#   Joyflow.app + Applications → /Applications
# Usage:
#   scripts/package-dmg.sh
#   SKIP_BUILD=1 APP=/path/to/Joyflow.app DMG=/path/to/out.dmg scripts/package-dmg.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=xcode-env.sh
source "$ROOT/scripts/xcode-env.sh"

OUT="${DMG:-$ROOT/dist/Joyflow.dmg}"
VOLNAME="${VOLNAME:-Joyflow}"
SKIP_BUILD="${SKIP_BUILD:-0}"

if [[ "$SKIP_BUILD" != "1" && "$SKIP_BUILD" != "true" ]]; then
  CONFIGURATION=Release INSTALL=0 "$ROOT/scripts/build.sh"
fi

APP="${APP:-$ROOT/.derivedData/Build/Products/Release/Joyflow.app}"
if [[ ! -d "$APP" ]]; then
  echo "error: Joyflow.app not found at $APP" >&2
  echo "  run scripts/build.sh with CONFIGURATION=Release, or set APP=" >&2
  exit 1
fi

BINARY="$APP/Contents/MacOS/Joyflow"
if [[ ! -f "$BINARY" ]]; then
  echo "error: $BINARY is missing" >&2
  exit 1
fi

STAGE="$(mktemp -d "${TMPDIR:-/var/folders}/joyflow-dmg.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

ditto "$APP" "$STAGE/Joyflow.app"
if command -v xattr >/dev/null; then
  xattr -cr "$STAGE/Joyflow.app" || true
fi
ln -s /Applications "$STAGE/Applications"

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$OUT" >/dev/null

if [[ "${STAPLE:-0}" == "1" || "${STAPLE:-0}" == "true" ]]; then
  xcrun stapler staple "$OUT" || echo "(DMG staple skipped — notarize the app first)"
fi

echo "DMG_OK $OUT"
