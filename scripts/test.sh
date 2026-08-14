#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=xcode-env.sh
source "$ROOT/scripts/xcode-env.sh"

swift test --package-path JoyflowKit
echo "TEST_OK"
