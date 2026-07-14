# Tokcat

**Realtime token usage & cost monitoring for multiple AI coding agents — right in the macOS menu bar, with local-only stats.**  
Optional desktop pixel pet fed by the same usage. Offline by default: no network calls, no uploads.

[English](README.md) | [中文](README.zh-CN.md)

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black.svg)](#requirements)
[![Release](https://img.shields.io/github/v/release/SelinLee/tokcat)](https://github.com/SelinLee/tokcat/releases)

---

## Core: multi-agent usage & cost

Tokcat polls **local agent logs** on your Mac (no cloud hooks, no API-key upload), normalizes them into token events, then gives you:

| Capability | What you get |
|------------|----------------|
| **Live rates** | Menu bar / panel: tok/s and spend rate (e.g. `$/m`) |
| **Today & total** | Today’s tokens, today’s cost, cumulative cost |
| **Model & source** | Active model, agent source, optional relay / provider attribution |
| **Stats dashboard** | Day / week / month trends; group by **Agent / Model / Provider**; Tokens ↔ cost |
| **Local pricing** | Editable rate table; reported real prices + estimates |
| **Recent events** | Compact recent usage in the menu bar |

### Supported agents / sources

| Source | Notes |
|--------|--------|
| **Claude Code** | Local JSONL session logs |
| **Codex CLI** | Rollout / history logs |
| **Cursor** | Local usage records |
| **Gemini CLI** | Local CLI logs |
| **OpenClaw** | Local trajectory logs |
| **WorkBuddy** | Local traces |
| **Kimi** | Local wire.jsonl-style logs |
| **CC Switch** | Proxy request logs for **provider / relay attribution and reported price** |

Adapters can be toggled in Settings. New adapters start tracking from the **end of the file** so first launch does not ingest huge histories.

> The pet is an optional visualization layer: tokens arrive → stats persist → the desktop cat is fed.  
> **You can use monitoring and stats without the pet.**

---

## 60-second tour

1. Install and open Tokcat (cat icon in the menu bar)  
2. Use Claude Code / Codex / Cursor as usual  
3. Watch **tok/s · spend rate** beside the icon; open the panel for today’s usage  
4. Main window → **Stats**: day / week / month charts and breakdowns  

Data stays in local SQLite: `~/Library/Application Support/TokenCat/tokencat.sqlite3`

---

## Feature overview

### 1. Live monitoring (menu bar)
- Custom Tokcat icon; **idle / working / done** expressions tied to agent throughput  
- Optional side metrics: CPU, GPU, memory, network, thermal pressure, **token rate**  
- Dropdown: agent summary (model, speed, today, total cost), recent events, system strip  

### 2. Stats & rates (main window)
- **Stats**: day / week / month; group by provider / model / agent; tokens or cost  
- Async aggregation + cache so period switches stay responsive  
- **Settings → Rates**: model unit prices; works with CC Switch reported prices  

### 3. Desktop pet (optional)
- Default **pixel Tokcat** (eat / level-up / work / sleepy / hungry…)  
- Also: block cat / pink cat / custom USDZ  
- Usage-driven growth: level, smarts / stability / feel, loot & codex  
- Sound effects **off by default**  

### 4. Main navigation
Stats · Pet · Bag · Codex · Settings (left sidebar)

### 5. Privacy
- **The app does not make network requests**  
- Read-only access to local logs and system metrics  
- No account, no cloud sync, no usage upload  

---

## Requirements

- macOS 13 Ventura or later  
- Dev build: Xcode 15+ / Swift 5.10+  

---

## Install

Download `Tokcat-*-macos.zip` from [GitHub Releases](https://github.com/SelinLee/tokcat/releases):

1. Unzip → `Tokcat.app`  
2. Drag into **Applications**  
3. **First launch**: right-click → **Open** (ad-hoc signed; one-time Gatekeeper bypass)  

Build a release locally:

```bash
TOKCAT_VERSION=0.3.0 scripts/package_app.sh
# Artifacts under dist/ (not committed): Tokcat.app and Tokcat-0.3.0-macos.zip
```

---

## Run from source

```bash
git clone https://github.com/SelinLee/tokcat.git
cd tokcat
swift build
swift test
swift run TokcatApp
```

---

## Architecture

```text
Claude Code / Codex / Cursor / Gemini / OpenClaw / WorkBuddy / Kimi / CC Switch
        │  local logs (read-only)
        ▼
  Adapters → TokenEvent (tokens, cost, model, provider)
        │
        ├─ Throughput / daily totals / menu-bar live UI
        ├─ UsageStats (day·week·month · Agent/Model/Provider)
        ├─ SQLite persistence
        └─ PetEngine / Loot (optional)
```

| Path | Role |
|------|------|
| `Sources/TokcatKit/Adapters/` | Per-agent log parsing & provider attribution |
| `Sources/TokcatKit/Economy/` | Pricing, nutrition tiers, **UsageStats** |
| `Sources/TokcatKit/Persistence/` | Local SQLite |
| `App/` | Menu bar, stats window, floating pet |
| `App/PixelPet/` | Pixel animation |
| `docs/` | Pixel / pet design notes (secondary) |

---

## Roadmap (summary)

- [x] Multi-agent local log adapters + live tok/s / cost  
- [x] Day / week / month stats (Agent / Model / Provider)  
- [x] Menu-bar metrics & main window  
- [x] Pixel pet / loot / bag / codex  
- [ ] More agents / log formats  
- [ ] Developer ID signing & notarization  

---

## Contributing

Issues and PRs welcome. Please do **not** commit:

- `dist/`, `.build/`, local `*.sqlite` / personal logs  
- API keys, account paths, private usage exports  

---

## License

[MIT](LICENSE)

Third-party model assets: see the matching `ATTRIBUTION.md` / model README.
