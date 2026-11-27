# TokenPulse

A lightweight, native macOS menu bar monitor for local AI coding agents (**GPT / Codex**, **Gemini / Antigravity**, and **Claude Code**).

## Features

- **Zero-proxy local collection**: Reads local session logs and SQLite metadata read-only with incremental `(mtime, size)` caching — no MITM certificates, no API keys required.
  - **GPT (Codex)**: `~/.codex/sessions/*/*/*/*.jsonl` & `~/.codex/state_5.sqlite`
  - **Gemini (Antigravity / IDE / CLI)**: `~/.gemini/antigravity*/conversation_summaries.db` & `brain/*/transcript.jsonl`
  - **Claude Code**: `~/.claude/projects/*/*.jsonl`
- **Live ECG menu bar icon**:
  - **Idle**: Calm monochrome breathing ECG waveform.
  - **Running**: Smooth ECG sweep colored by the active provider (GPT emerald, Gemini blue, Claude violet — automatically blended when multiple providers run simultaneously), with sweep speed scaled to live TPS.
  - **Needs action**: Warm amber-orange breathing pulse + optional `Pop` sound alert when an agent waits for your approval or input.
- **3-mode menu bar readout**: Switch between icon-only, live TPS, or rolling 24h equivalent USD cost (`$XX.XX`) right from the panel footer.
- **Interactive light-mode dashboard**:
  - Rolling `24h` / `7d` / `30d` / `All` time filters and per-provider filters.
  - Interactive token usage bar chart & TPS sparkline with hover tooltips.
  - Equivalent API cost and cache-savings estimation.
  - Clickable active sessions and alerts to jump straight back to the source app.
  - Native macOS Launch at Login (`SMAppService`) toggle and OS-level `flock` single-instance lock.

## Requirements

- macOS 13.0+
- Swift 6.0+ (Xcode Command Line Tools are sufficient; full Xcode is not required)

## Build & Install

```bash
./build_app.sh
cp -R TokenPulse.app /Applications/TokenPulse.app
open /Applications/TokenPulse.app
```

CLI probe (prints aggregated local stats without launching the UI):

```bash
/Applications/TokenPulse.app/Contents/MacOS/TokenPulse --probe
```

## Project Structure

```text
TokenPulse/
├── Package.swift
├── build_app.sh
└── Sources/TokenPulse/
    ├── main.swift                  # Entry point, --probe mode, flock single-instance lock
    ├── AppDelegate.swift           # Menu bar NSStatusItem, custom ECG rendering, popover/window
    ├── Models.swift                # Core models, pricing estimator, formatters
    ├── MonitorEngine.swift         # 2s background polling, aggregation, login item & sound alert
    ├── CodexCollector.swift        # Incremental Codex JSONL + SQLite collector
    ├── AntigravityCollector.swift  # Incremental Antigravity transcript + SQLite collector
    ├── ClaudeCollector.swift       # Incremental Claude Code JSONL collector
    ├── SQLiteReader.swift          # Read-only C sqlite3 wrapper
    ├── WebDashboardView.swift      # WKWebView host & Swift <-> JS bridge
    └── DashboardHTML.swift         # Self-contained light-mode web dashboard
```
