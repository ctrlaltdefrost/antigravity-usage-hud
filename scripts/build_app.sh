#!/usr/bin/env bash
set -euo pipefail

# Determine repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== [1/5] Building AntigravityHUD (Release) ==="
cd "${REPO_ROOT}"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
SRC_BIN="${BIN_DIR}/AntigravityHUDApp"

if [ ! -f "${SRC_BIN}" ]; then
    echo "ERROR: Executable not found at ${SRC_BIN}" >&2
    exit 1
fi

APP_BUNDLE="${REPO_ROOT}/dist/AntigravityHUD.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "=== [2/5] Creating App Bundle Structure ==="
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "=== [3/5] Installing Executable & Info.plist ==="
cp "${SRC_BIN}" "${MACOS_DIR}/AntigravityHUD"
chmod +x "${MACOS_DIR}/AntigravityHUD"

cat << 'PLIST' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AntigravityHUD</string>
    <key>CFBundleDisplayName</key>
    <string>Antigravity HUD</string>
    <key>CFBundleIdentifier</key>
    <string>com.antigravity.hud</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>AntigravityHUD</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "=== [4/5] Generating Futuristic Reactor Icon (.icns) & Bundling CLI Hook ==="
HOOK_SRC="${REPO_ROOT}/scripts/agy-hud-hook.sh"
if [ -f "${HOOK_SRC}" ]; then
    cp "${HOOK_SRC}" "${RESOURCES_DIR}/agy-hud-hook.sh"
    chmod +x "${RESOURCES_DIR}/agy-hud-hook.sh"
fi

ICON_SCRIPT="${SCRIPT_DIR}/generate_icon.swift"
if [ -f "${ICON_SCRIPT}" ]; then
    swift "${ICON_SCRIPT}" "${RESOURCES_DIR}/AppIcon.icns"
else
    echo "Warning: Icon script not found at ${ICON_SCRIPT}, skipping icon generation"
fi

echo "=== [5/5] Ad-hoc Codesigning App Bundle ==="
codesign --force --deep --sign - "${APP_BUNDLE}"
codesign --verify --deep --strict "${APP_BUNDLE}"

echo "=== Build Complete ==="
echo "App bundle: ${APP_BUNDLE}"
ls -ld "${APP_BUNDLE}"
