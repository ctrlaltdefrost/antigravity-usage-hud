# Antigravity HUD ⚡🛰️

**Antigravity HUD** is a futuristic, zero-overhead macOS menu bar and floating telemetry HUD for **Google Antigravity** and the **`agy` CLI**.

Inspired by sci-fi tactical interfaces and arc-reactor command decks, it provides real-time visibility into token burn velocity, rolling usage windows, multi-agent swarms, CLI quotas, and project-level spend—completely **free of token cost** and running 100% locally on your Mac.

---

## ⚡ Highlights

- **Zero-Token Telemetry**: Never consumes tokens to monitor tokens. Reads local read-only conversation databases and incrementally tails transcript logs with microsecond latency.
- **Orbital Command Deck & Compact Pill**: Seamlessly toggle between a full tactical telemetry dashboard and an unobtrusive, floating compact pill with ghost click-through mode (`⌘⇧G`).
- **Live `agy` CLI Quota Bridge**: Automatically bridges the `agy` statusline hook to stream live quota countdowns, model states, and context window saturation.
- **Project Spend Radar & Priority Pinning**: Pin your primary project and receive immediate **Priority Drift** alerts whenever background swarms or unpinned tasks outpace your focus budget.
- **Sci-Fi Audio & Metal Shaders**: Features hardware-accelerated Metal reactor core backdrops, kinetic circular orbital gauges, real-time burn sparklines, and synthesized procedural audio pings.
- **Cybernetic Themes**: Switch dynamically between **Jarvis Cyan**, **Cyberpunk Neon**, **Solar Reactor**, and **Stealth Obsidian**.

---

## 🛠️ System Requirements

- **macOS Sonoma (14.0)** or later (Apple Silicon or Intel)
- **Xcode Command Line Tools** (`swift --version` >= 5.10)
- **Google Antigravity** or **`agy` CLI** installed locally

---

## 🚀 Quick Start

### 1-Click Automated Install (Recommended)

To build, install to `/Applications/AntigravityHUD.app`, wire the `agy` CLI hook, and launch the HUD automatically:

```bash
git clone https://github.com/ctrlaltdefrost/antigravity-usage-hud.git
cd antigravity-usage-hud
./install.sh
```

---

### Manual Build & Launch

If you prefer building and running directly from source without installing to `/Applications`:

```bash
git clone https://github.com/ctrlaltdefrost/antigravity-usage-hud.git
cd antigravity-usage-hud
./scripts/build_app.sh
open dist/AntigravityHUD.app
```

Launching `AntigravityHUD.app` automatically opens both the floating tactical **Orbital Command Deck** and the live macOS **Menu Bar readout** (e.g., `⚡ 42K/5h · 98%`). You can seamlessly switch between Compact Pill mode, the Command Deck, or Ghost click-through mode (`⌘⇧G`).

### 3. Connect Live `agy` CLI Telemetry (Optional)

To stream real-time quota countdowns and context percentages directly from the `agy` CLI terminal into your HUD:

1. Click the Antigravity HUD menu bar icon.
2. Select **Enable Live CLI Quota Hook**.
3. Alternatively, manually install the hook into `~/.gemini/antigravity-cli/settings.json`:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "/path/to/scripts/agy-hud-hook.sh"
     }
   }
   ```

---

## 🧪 Running Tests

The test suite validates incremental log parsing, SQLite read-only access, priority drift heuristics, and non-destructive hook management:

```bash
swift test
```

---

## 🔒 Privacy & Architecture

- **100% Local**: Antigravity HUD makes zero external network calls. All telemetry is computed on-device.
- **Safe & Non-Destructive**: Reads Antigravity databases in read-only mode (`SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | mode=ro`) with strict timeouts to prevent file locks.
- **Clean Configuration**: Hook installer preserves all existing user preferences in `settings.json` and supports full single-click rollback.

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
