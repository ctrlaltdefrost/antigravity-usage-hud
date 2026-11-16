#!/usr/bin/env bash
set -euo pipefail

HUD_DIR="${AGY_HUD_DIR:-$HOME/.gemini/antigravity-hud}"
SNAPSHOT_PATH="${AGY_HUD_SNAPSHOT_PATH:-$HUD_DIR/statusline_snapshot.json}"

mkdir -p "$HUD_DIR"

INPUT_JSON="$(cat || true)"

if [ -n "$INPUT_JSON" ]; then
    TMP_FILE="$(mktemp "$HUD_DIR/statusline_snapshot.XXXXXX")"
    printf '%s\n' "$INPUT_JSON" > "$TMP_FILE"
    mv -f "$TMP_FILE" "$SNAPSHOT_PATH"
fi

if command -v python3 >/dev/null 2>&1 && [ -n "$INPUT_JSON" ]; then
    python3 - "$INPUT_JSON" <<'PY' 2>/dev/null || printf "⚡ AGY HUD\n"
import json, sys

try:
    data = json.loads(sys.argv[1])
except Exception:
    print("⚡ AGY HUD")
    sys.exit(0)

model = "AGY"
m = data.get("model")
if isinstance(m, dict):
    model = m.get("display_name") or m.get("name") or model
elif isinstance(m, str) and m:
    model = m

ctx_part = ""
ctx = data.get("context_window")
if isinstance(ctx, dict) and ctx.get("used_percentage") is not None:
    try:
        ctx_part = f" · Ctx {float(ctx['used_percentage']):.0f}%"
    except Exception:
        pass

quota_part = ""
q = data.get("quota")
if isinstance(q, dict):
    rem = q.get("remaining_fraction")
    if rem is None:
        for v in q.values():
            if isinstance(v, dict) and v.get("remaining_fraction") is not None:
                rem = v.get("remaining_fraction")
                break
    if rem is not None:
        try:
            quota_part = f" · Quota {float(rem) * 100.0:.0f}%"
        except Exception:
            pass

print(f"⚡ {model}{ctx_part}{quota_part}")
PY
else
    printf "⚡ AGY HUD\n"
fi
