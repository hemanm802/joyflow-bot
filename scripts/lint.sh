#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=xcode-env.sh
source "$ROOT/scripts/xcode-env.sh"

command -v swiftlint >/dev/null || { echo "error: swiftlint missing" >&2; exit 1; }
SWIFT_FORMAT="$(command -v swift-format || true)"
if [[ -z "$SWIFT_FORMAT" ]]; then
  echo "error: swift-format missing" >&2
  exit 1
fi

swiftlint lint --config "$ROOT/.swiftlint.yml" \
  Joyflow/App Joyflow/DesignSystem Joyflow/Features Joyflow/Resources \
  JoyflowKit/Sources JoyflowKit/Tests JoyflowKit/Package.swift
"$SWIFT_FORMAT" lint --recursive \
  Joyflow/App Joyflow/DesignSystem Joyflow/Features \
  JoyflowKit/Sources JoyflowKit/Tests JoyflowKit/Package.swift
echo "LINT_OK"
