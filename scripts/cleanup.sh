#!/usr/bin/env bash
# Clean-slate precondition for installing Glasnik. Removes any prior install and stops
# anything left running so install.sh starts fresh. Idempotent — safe to run anytime.
#
#   ./scripts/cleanup.sh           quit + uninstall the app, clear local build artifacts
#   ./scripts/cleanup.sh --purge   ALSO delete saved history + the downloaded Whisper model
#
# (This is the place to add teardown for any future moving parts — e.g. a bundled
#  server, a Docker service, or a launch agent. Glasnik currently has none of those.)
set -euo pipefail

PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

echo "▶ Quitting Glasnik if running…"
osascript -e 'tell application "Glasnik" to quit' >/dev/null 2>&1 || true
pkill -x Glasnik 2>/dev/null || true

echo "▶ Removing installed app…"
rm -rf "/Applications/Glasnik.app" "$HOME/Applications/Glasnik.app"

if [[ -f Package.swift ]]; then
  echo "▶ Clearing local build artifacts…"
  rm -rf .build Glasnik.app Glasnik.xcodeproj
  rm -rf ./*.iconset 2>/dev/null || true
fi

if [[ $PURGE -eq 1 ]]; then
  echo "▶ Purging saved history + downloaded model…"
  rm -rf "$HOME/Library/Application Support/Glasnik"
  rm -rf "$HOME/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3"
fi

echo "✓ Clean slate. (Ollama, if installed, is left untouched.)"
