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

DEVICE="${DEVICE:-0}"
TEAM="${DEVELOPMENT_TEAM:-}"
BUNDLE_ID="dev.joyflow.Joyflow.ios"

if [[ "$DEVICE" == "1" || "$DEVICE" == "true" || "$DEVICE" == "auto" ]]; then
  DEVICE_JSON="$(mktemp -t joyflow-devices).json"
  xcrun devicectl list devices --json-output "$DEVICE_JSON" >/dev/null
  DEVICE_INFO="$(python3 - "$DEVICE_JSON" <<'PY'
import json, sys
data = json.loads(open(sys.argv[1]).read())
devices = data.get("result", {}).get("devices", [])
best = None
for d in devices:
    hw = d.get("hardwareProperties") or {}
    conn = d.get("connectionProperties") or {}
    props = d.get("deviceProperties") or {}
    if hw.get("reality") == "simulated":
        continue
    kind = str(hw.get("deviceType") or "")
    product = str(hw.get("productType") or "")
    platform = str(hw.get("platform") or "")
    if "iPhone" not in kind and "iPhone" not in product and "iPad" not in kind and "iPad" not in product and platform.lower() not in ("ios", "ipados"):
        continue
    state = str(conn.get("tunnelState") or conn.get("pairingState") or "").lower()
    available = conn.get("pairingState") == "paired" and "unavailable" not in state
    tablet = "iPad" in kind or "iPad" in product
    score = 0
    if available:
        score += 4
    if not tablet:
        score += 2
    if score == 0:
        score = 1
    row = {
        "id": d.get("identifier"),
        "udid": hw.get("udid"),
        "name": props.get("name") or "iPhone",
        "available": available,
    }
    if best is None or score > best[0]:
        best = (score, row)
if not best:
    sys.exit(0)
print(best[1]["id"] + "\t" + (best[1]["udid"] or "") + "\t" + best[1]["name"])
PY
)"
  rm -f "$DEVICE_JSON"
  if [[ -z "$DEVICE_INFO" ]]; then
    echo "error: no paired physical iPhone found" >&2
    exit 1
  fi
  CORE_ID="${DEVICE_INFO%%$'\t'*}"
  REST="${DEVICE_INFO#*$'\t'}"
  DEVICE_UDID="${REST%%$'\t'*}"
  DEVICE_NAME="${REST#*$'\t'}"
  echo "Using iPhone: $DEVICE_NAME ($CORE_ID)"

  if [[ -z "$TEAM" ]]; then
    TEAM="9F2JXY8TCK"
  fi

  # Generic device SDK so a locked or briefly-unavailable iPhone does not fail the compile.
  DESTINATION="generic/platform=iOS"

  xcodebuild \
    -project Joyflow.xcodeproj \
    -scheme JoyflowiOS \
    -destination "$DESTINATION" \
    -configuration Debug \
    -derivedDataPath "$ROOT/.derivedData-ios" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_STYLE=Automatic \
    CODE_SIGN_IDENTITY="Apple Development" \
    build

  APP="$ROOT/.derivedData-ios/Build/Products/Debug-iphoneos/Joyflow.app"
  if [[ ! -d "$APP" ]]; then
    echo "error: Joyflow.app not produced at $APP" >&2
    exit 1
  fi
  echo "BUILD_OK $APP"

  xcrun devicectl device install app --device "$CORE_ID" "$APP"
  if ! xcrun devicectl device process launch --device "$CORE_ID" "$BUNDLE_ID"; then
    echo "INSTALLED_ON $DEVICE_NAME (unlock the phone to open Joyflow)"
  else
    echo "INSTALLED_ON $DEVICE_NAME"
  fi
  exit 0
fi

xcodebuild \
  -project Joyflow.xcodeproj \
  -scheme JoyflowiOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  -derivedDataPath "$ROOT/.derivedData" \
  build

APP="$ROOT/.derivedData/Build/Products/Debug-iphonesimulator/Joyflow.app"
if [[ ! -d "$APP" ]]; then
  echo "error: Joyflow.app not produced at $APP" >&2
  exit 1
fi
echo "BUILD_OK $APP"
