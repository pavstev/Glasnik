#!/usr/bin/env bash
# Installs the latest released Sapat.app from GitHub Releases. Cleans up any prior
# install first, downloads the release, strips the Gatekeeper quarantine (the app is
# ad-hoc signed), installs to /Applications, and launches. Safe to re-run.
#
#   ./scripts/install.sh
# or, without cloning the repo:
#   curl -fsSL https://raw.githubusercontent.com/pavstev/sapat/main/scripts/install.sh | bash
set -euo pipefail

REPO="pavstev/sapat"
APP="/Applications/Sapat.app"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"

echo "▶ Cleaning up any prior install…"
if [[ -n "$HERE" && -x "$HERE/cleanup.sh" ]]; then
  "$HERE/cleanup.sh" || true
else
  osascript -e 'tell application "Sapat" to quit' >/dev/null 2>&1 || true
  pkill -x Sapat 2>/dev/null || true
  rm -rf "$APP"
fi

echo "▶ Finding the latest release…"
release_json="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")"
asset_url="$(printf '%s' "$release_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(next(a['browser_download_url'] for a in d['assets'] if a['name'].endswith('.zip')))")"
[[ -n "$asset_url" ]] || { echo "✗ No .zip asset on the latest release"; exit 1; }
echo "  $asset_url"
csum_url="$(printf '%s' "$release_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(next((a['browser_download_url'] for a in d['assets'] if a['name'].endswith('.sha256')), ''))")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "▶ Downloading…"
curl -fsSL "$asset_url" -o "$tmp/Sapat.zip"

# Integrity pre-check: verify the published SHA-256 if present. (The in-app updater additionally
# verifies an ed25519 signature; this bootstrap installer checks the checksum.)
if [[ -n "$csum_url" ]]; then
  echo "▶ Verifying checksum…"
  curl -fsSL "$csum_url" -o "$tmp/Sapat.zip.sha256"
  expected="$(awk '{print $1}' "$tmp/Sapat.zip.sha256" | head -n1)"
  actual="$(shasum -a 256 "$tmp/Sapat.zip" | awk '{print $1}')"
  if [[ "$expected" != "$actual" ]]; then
    echo "✗ Checksum mismatch — refusing to install (expected $expected, got $actual)"; exit 1
  fi
  echo "  ✓ checksum verified"
else
  echo "  (no checksum published for this release — skipping)"
fi

echo "▶ Unzipping…"
ditto -x -k "$tmp/Sapat.zip" "$tmp"
echo "▶ Installing to /Applications…"
rm -rf "$APP"
cp -R "$tmp/Sapat.app" "$APP"
echo "▶ Removing quarantine (ad-hoc signed)…"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "▶ Launching…"
open "$APP"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "?")"
echo "✓ Installed Šapat ${version}. Look for the Ш in your menu bar (no Dock icon)."
echo "  First launch downloads the speech model (WhisperKit) and the reasoner model (MLX),"
echo "  cached outside the app bundle (~/Library/Application Support/Sapat/Models) so updates"
echo "  never re-download them, and asks once for the microphone — allow it."
echo "  No other apps are required: inference runs in-process. Hotkey: ⌥⇧Space to start/stop."
