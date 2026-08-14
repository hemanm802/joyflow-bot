#!/usr/bin/env bash
# Sign dist/Joyflow.dmg with Sparkle EdDSA and write appcast.xml.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DMG="${DMG:-$ROOT/dist/Joyflow.dmg}"
VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-5}"
TAG="${TAG:-v$VERSION}"
REPO="${REPO:-robzilla1738/joyflow-bot}"

if [[ ! -f "$DMG" ]]; then
  echo "error: no DMG at $DMG" >&2
  exit 1
fi

find_sign_update() {
  if command -v sign_update >/dev/null 2>&1; then
    command -v sign_update
    return
  fi
  local found
  found="$(find "$ROOT/.derivedData/SourcePackages" -type f -name sign_update 2>/dev/null | head -n 1 || true)"
  if [[ -n "$found" ]]; then
    echo "$found"
    return
  fi
  found="$(find "$HOME/Library/Developer/Xcode/DerivedData" -type f -path '*/artifacts/sparkle/*/bin/sign_update' 2>/dev/null | head -n 1 || true)"
  if [[ -n "$found" ]]; then
    echo "$found"
    return
  fi
  return 1
}

SIGN_UPDATE="$(find_sign_update)" || {
  echo "error: sign_update not found. Build Release once so Sparkle resolves." >&2
  exit 1
}

# sign_update prints: sparkle:edSignature="…" length="…"
SIG_LINE="$("$SIGN_UPDATE" "$DMG")"
ED_SIG="$(printf '%s\n' "$SIG_LINE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(printf '%s\n' "$SIG_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
if [[ -z "$ED_SIG" || -z "$LENGTH" ]]; then
  echo "error: could not parse sign_update output:" >&2
  echo "$SIG_LINE" >&2
  exit 1
fi

PUB_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
ENCLOSURE="https://github.com/${REPO}/releases/download/${TAG}/Joyflow.dmg"

cat > "$ROOT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Joyflow</title>
    <link>https://github.com/${REPO}/releases/latest/download/appcast.xml</link>
    <description>Most recent updates to Joyflow</description>
    <language>en</language>
    <item>
      <title>${VERSION}</title>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <pubDate>${PUB_DATE}</pubDate>
      <description><![CDATA[
        <p>First public Mac build. Native workspace, iPhone pair, ask-first computer tools, Sparkle updates.</p>
        <p>Notes: https://github.com/${REPO}/blob/main/CHANGELOG.md</p>
      ]]></description>
      <enclosure
        url="${ENCLOSURE}"
        sparkle:edSignature="${ED_SIG}"
        length="${LENGTH}"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML

echo "APPCAST_OK $ROOT/appcast.xml"
echo "$SIG_LINE"
