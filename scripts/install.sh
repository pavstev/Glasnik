#!/usr/bin/env bash
# Installs the latest released Glasnik.app from GitHub Releases. Cleans up any prior
# install first, downloads the release, strips the Gatekeeper quarantine (the app is
# ad-hoc signed), installs to /Applications, and launches. Safe to re-run.
#
#   ./scripts/install.sh
# or, without cloning the repo:
#   curl -fsSL https://raw.githubusercontent.com/pavstev/Glasnik/main/scripts/install.sh | bash
set -euo pipefail

REPO="pavstev/Glasnik"
APP="/Applications/Glasnik.app"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"

echo "▶ Cleaning up any prior install…"
if [[ -n "$HERE" && -x "$HERE/cleanup.sh" ]]; then
  "$HERE/cleanup.sh" || true
else
  osascript -e 'tell application "Glasnik" to quit' >/dev/null 2>&1 || true
  pkill -x Glasnik 2>/dev/null || true
  rm -rf "$APP"
fi

echo "▶ Finding the latest release…"
asset_url="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(next(a['browser_download_url'] for a in d['assets'] if a['name'].endswith('.zip')))")"
[[ -n "$asset_url" ]] || { echo "✗ No .zip asset on the latest release"; exit 1; }
echo "  $asset_url"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "▶ Downloading…"
curl -fsSL "$asset_url" -o "$tmp/Glasnik.zip"
echo "▶ Unzipping…"
ditto -x -k "$tmp/Glasnik.zip" "$tmp"
echo "▶ Installing to /Applications…"
rm -rf "$APP"
cp -R "$tmp/Glasnik.app" "$APP"
echo "▶ Removing quarantine (ad-hoc signed)…"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "▶ Launching…"
open "$APP"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "?")"
echo "✓ Installed Glasnik ${version}. Look for the Г in your menu bar (no Dock icon)."
echo "  First launch downloads the ~2.9 GB Whisper model and asks for the microphone — allow it."
echo "  Optional polish: brew install ollama && ollama pull qwen2.5:3b && ollama serve"
