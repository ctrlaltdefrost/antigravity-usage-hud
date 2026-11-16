#!/usr/bin/env bash
set -euo pipefail

HUD_DIR="${AGY_HUD_DIR:-$HOME/.gemini/antigravity-hud}"
SNAPSHOT_PATH="${AGY_HUD_SNAPSHOT_PATH:-$HUD_DIR/statusline_snapshot.json}"

mkdir -p "$HUD_DIR"

INPUT_JSON="$(cat || true)"

if [ -n "$INPUT_JSON" ]; then
    TMP_FILE="$(mktemp "$HUD_DIR/statusline_snapshot.XXXXXX")"
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$INPUT_JSON" "$SNAPSHOT_PATH" "$TMP_FILE" <<'PY' 2>/dev/null || printf '%s\n' "$INPUT_JSON" > "$TMP_FILE"
import json, os, sys

raw_in, snap_path, tmp_path = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    data = json.loads(raw_in)
    if not isinstance(data, dict):
        raise ValueError("not dict")
except Exception:
    with open(tmp_path, "w", encoding="utf-8") as f:
        f.write(raw_in + "\n")
    sys.exit(0)

data.pop("email", None)

q = data.get("quota")
has_non_empty_quota = isinstance(q, (dict, list)) and len(q) > 0

if has_non_empty_quota:
    data["_has_live_quota"] = True
else:
    data["_has_live_quota"] = False
    if os.path.exists(snap_path):
        try:
            with open(snap_path, "r", encoding="utf-8") as prev_f:
                prev = json.load(prev_f)
            if isinstance(prev, dict):
                prev_q = prev.get("quota")
                if isinstance(prev_q, (dict, list)) and len(prev_q) > 0:
                    data["quota"] = prev_q
                if not data.get("plan_tier") and prev.get("plan_tier"):
                    data["plan_tier"] = prev["plan_tier"]
        except Exception:
            pass

with open(tmp_path, "w", encoding="utf-8") as f:
    json.dump(data, f)
    f.write("\n")
PY
    else
        printf '%s\n' "$INPUT_JSON" > "$TMP_FILE"
    fi
    mv -f "$TMP_FILE" "$SNAPSHOT_PATH"
fi

if command -v python3 >/dev/null 2>&1 && [ -n "$INPUT_JSON" ]; then
    python3 - "$SNAPSHOT_PATH" "$INPUT_JSON" <<'PY' 2>/dev/null || printf "⚡ AGY HUD\n"
import json, os, sys

snap_path, raw_in = sys.argv[1], sys.argv[2]
data = {}
try:
    if os.path.exists(snap_path):
        with open(snap_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    else:
        data = json.loads(raw_in)
except Exception:
    print("⚡ AGY HUD")
    sys.exit(0)

model = data.get("plan_tier") or "AGY"
m = data.get("model")
if isinstance(m, dict):
    model = m.get("display_name") or m.get("name") or model
elif isinstance(m, str) and m:
    model = m

ctx_part = ""
ctx = data.get("context_window")
if isinstance(ctx, dict) and ctx.get("used_percentage") is not None:
    try:
        pct = float(ctx["used_percentage"])
        if pct > 0:
            ctx_part = f" · Ctx {pct:.0f}%"
    except Exception:
        pass

quota_part = ""
q = data.get("quota")
if isinstance(q, dict):
    rem = q.get("remaining_fraction")
    if rem is None:
        for k in ("gemini-5h", "3p-5h", "gemini-weekly", "3p-weekly"):
            v = q.get(k)
            if isinstance(v, dict) and v.get("remaining_fraction") is not None:
                rem = v.get("remaining_fraction")
                break
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
