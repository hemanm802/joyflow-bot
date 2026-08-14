#!/usr/bin/env bash
# Notarize + staple the exported Joyflow.app (and the DMG if it exists).
# Requires a one-time: xcrun notarytool store-credentials AC_PASSWORD …
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="${APP:-$ROOT/build/export/Joyflow.app}"
PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"
DMG="${DMG:-$ROOT/dist/Joyflow.dmg}"

if [[ ! -d "$APP" ]]; then
  echo "error: no app at $APP. Run scripts/build-release.sh first." >&2
  exit 1
fi

ZIP="$ROOT/build/Joyflow.zip"
mkdir -p "$ROOT/build"
rm -f "$ZIP"
echo "▸ Zipping $APP…"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ Submitting app to Apple notary (profile: $PROFILE)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "▸ Stapling ticket onto app…"
xcrun stapler staple "$APP"
spctl --assess --verbose=4 --type execute "$APP" || true

if [[ -f "$DMG" ]]; then
  echo "▸ Submitting DMG to Apple notary…"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  echo "▸ Stapling ticket onto DMG…"
  xcrun stapler staple "$DMG"
fi

echo "NOTARY_OK $APP"
