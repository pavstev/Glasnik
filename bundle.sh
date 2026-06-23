#!/usr/bin/env bash
# Builds Glasnik and wraps it into Glasnik.app — no Xcode required, just the
# Command Line Tools. Ad-hoc signs it ("Sign to Run Locally").
#
# Env overrides:
#   GLASNIK_VERSION=1.2.3   stamp this version into the bundle (CI sets it from the tag)
#   GLASNIK_UNIVERSAL=1     build a universal (arm64 + x86_64) binary
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Glasnik"
CONFIG="release"

# Space-separated (not an array) so it's safe under macOS's bash 3.2, where
# expanding an empty array with `set -u` errors out.
ARCH_FLAGS=""
if [[ "${GLASNIK_UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS="--arch arm64 --arch x86_64"
fi

echo "▶ Building (${CONFIG})…"
# shellcheck disable=SC2086  # intentional word-splitting of the flag list
swift build -c "${CONFIG}" ${ARCH_FLAGS}

# shellcheck disable=SC2086
BIN_DIR="$(swift build -c "${CONFIG}" ${ARCH_FLAGS} --show-bin-path)"
BIN="${BIN_DIR}/${APP_NAME}"
if [[ ! -x "${BIN}" ]]; then
  echo "✗ Built binary not found at ${BIN}" >&2
  exit 1
fi

APP="${APP_NAME}.app"
echo "▶ Assembling ${APP}…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/${APP_NAME}"
cp Info.plist "${APP}/Contents/Info.plist"
printf 'APPL????' > "${APP}/Contents/PkgInfo"

# Stamp the release version (from the git tag in CI) into the bundle so the in-app
# update check compares against an accurate current version.
if [[ -n "${GLASNIK_VERSION:-}" ]]; then
  echo "▶ Stamping version ${GLASNIK_VERSION}…"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${GLASNIK_VERSION}" "${APP}/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${GLASNIK_VERSION}" "${APP}/Contents/Info.plist"
fi

# Copy any SwiftPM resource bundles (Bundle.module) so they resolve inside the .app.
shopt -s nullglob
for bundle in "${BIN_DIR}"/*.bundle; do
  cp -R "${bundle}" "${APP}/Contents/Resources/"
done

echo "▶ Ad-hoc signing…"
codesign --force --sign - "${APP}"

echo "✓ Built ${APP}"
echo "   Run:     open ${APP}"
echo "   Install: cp -R ${APP} /Applications/ && open /Applications/${APP}"
