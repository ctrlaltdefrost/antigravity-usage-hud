#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"

echo "=============================================="
echo "⚡ Antigravity HUD — 1-Click Installer"
echo "=============================================="

# 1. Check prerequisites
if ! command -v swift >/dev/null 2>&1; then
    echo "❌ Error: Swift / Xcode Command Line Tools not found." >&2
    echo "👉 Please install Xcode Command Line Tools by running:" >&2
    echo "     xcode-select --install" >&2
    exit 1
fi

# 2. Build release application bundle
echo ""
echo "[1/4] Building Antigravity HUD..."
"${REPO_ROOT}/scripts/build_app.sh"

APP_SRC="${REPO_ROOT}/dist/AntigravityHUD.app"
APP_DEST="/Applications/AntigravityHUD.app"

if [ ! -d "${APP_SRC}" ]; then
    echo "❌ Error: Build output not found at ${APP_SRC}" >&2
    exit 1
fi

# 3. Install to /Applications
echo ""
echo "[2/4] Installing to ${APP_DEST}..."
pkill -x AntigravityHUD 2>/dev/null || true
sleep 1
rm -rf "${APP_DEST}"
ditto "${APP_SRC}" "${APP_DEST}"

# 4. Wire agy CLI statusLine hook safely (preserving all existing settings)
echo ""
echo "[3/4] Syncing agy CLI StatusLine hook..."
HOOK_DEST_DIR="${HOME}/.gemini/antigravity-hud"
HOOK_DEST="${HOOK_DEST_DIR}/agy-hud-hook.sh"
mkdir -p "${HOOK_DEST_DIR}"
cp "${REPO_ROOT}/scripts/agy-hud-hook.sh" "${HOOK_DEST}"
chmod +x "${HOOK_DEST}"

SETTINGS_DIR="${HOME}/.gemini/antigravity-cli"
SETTINGS_FILE="${SETTINGS_DIR}/settings.json"
mkdir -p "${SETTINGS_DIR}"

python3 - << PYEOF
import json, os

settings_path = os.path.expanduser("${SETTINGS_FILE}")
hook_path = os.path.expanduser("${HOOK_DEST}")
backup_key = "_antigravity_hud_backup_statusLine"

data = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception:
        data = {}

if "statusLine" in data:
    cur = data["statusLine"]
    cmd = cur if isinstance(cur, str) else (cur.get("command", "") if isinstance(cur, dict) else "")
    if "agy-hud-hook.sh" not in cmd and backup_key not in data:
        data[backup_key] = cur

data["statusLine"] = {
    "type": "command",
    "command": hook_path
}

with open(settings_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
print("✓ Live CLI hook installed cleanly in ~/.gemini/antigravity-cli/settings.json")
PYEOF

# 5. Launch application
echo ""
echo "[4/4] Launching Antigravity HUD..."
open "${APP_DEST}"

echo ""
echo "=============================================="
echo "✅ Antigravity HUD is installed and running!"
echo "   - Menu Bar icon: Live token burn & quota"
echo "   - Command Deck: Tactical orbital dashboard"
echo "   - CLI Sync: Active in agy terminal sessions"
echo "=============================================="
