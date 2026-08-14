# Swift / xcodebuild environment. Source from build.sh / test.sh / lint.sh.
# Probes several Xcode locations so contributors are not locked to one machine path.

if [[ -n "${DEVELOPER_DIR:-}" && -d "${DEVELOPER_DIR}" ]]; then
  export DEVELOPER_DIR
else
  selected="$(xcode-select -p 2>/dev/null || true)"
  if [[ -n "$selected" && -d "$selected" && "$selected" != *CommandLineTools* ]]; then
    export DEVELOPER_DIR="$selected"
  fi
fi

if [[ -z "${DEVELOPER_DIR:-}" || ! -d "${DEVELOPER_DIR}" ]]; then
  candidates=(
    "/Applications/Xcode.app/Contents/Developer"
    "/Applications/Xcode-beta.app/Contents/Developer"
    "${HOME}/Downloads/Xcode-beta.app/Contents/Developer"
    "${HOME}/Downloads/Xcode.app/Contents/Developer"
  )
  for cand in "${candidates[@]}"; do
    if [[ -d "$cand" ]]; then
      export DEVELOPER_DIR="$cand"
      break
    fi
  done
fi

if [[ -z "${DEVELOPER_DIR:-}" || ! -d "${DEVELOPER_DIR}" ]]; then
  echo "error: Joyflow needs a full Xcode (not only Command Line Tools)." >&2
  echo "  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer" >&2
  echo "  or install Xcode and re-run." >&2
  exit 1
fi

export SOURCEKIT_TOOLCHAIN_PATH="${SOURCEKIT_TOOLCHAIN_PATH:-$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain}"
