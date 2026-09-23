# Tokcat

**Monitor AI work from your Mac’s menu bar.**

See which agents are running, which replies are ready, and which tasks need your input. Tokcat brings **Codex, Claude Code, and WorkBuddy** into one view: glance at the menu bar, open the dropdown for context, then read conversations and inspect activity in the main window.

[English](README.md) | [中文](README.zh-CN.md)

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black.svg)](#requirements)
[![Release](https://img.shields.io/github/v/release/SelinLee/tokcat)](https://github.com/SelinLee/tokcat/releases)

**[Download Tokcat](https://github.com/SelinLee/tokcat/releases)** · [Get started](#start-in-60-seconds) · [Agent support](#agent-support)

## 1. Monitor from the menu bar

Keep AI task status beside the metrics you already watch. **One dot per task**, placed after your selected monitoring indicators.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-menubar-dark.png" />
    <img src="docs/assets/screenshots/readme-menubar-light.png" alt="Tokcat menu-bar close-up: live metrics, Codex quota, and colored task dots" width="900" />
  </picture>
</p>

- **Choose your metrics:** CPU, GPU, memory, network traffic, token throughput, and spend rate.
- **Watch Codex limits:** optional 5-hour and weekly remaining quota, using your local login.
- **Keep it compact:** up to three dots per column, six visible dots, then `+N`. Metrics and task dots can be enabled independently.

| Task dot | What it means |
|---|---|
| 🟡 Pulsing yellow | The task is running. |
| 🟡🔴 Alternating yellow / red | Your input or approval is needed; colors switch every 0.8 seconds. |
| 🟢 Green | A reply has finished. In the foreground agent, it flashes for 3 seconds and clears automatically. Background completions stay visible until viewed. |
| 🔴 Solid red | The turn failed. |
| ◯ Hollow gray | Updates are unavailable or the turn was interrupted; after 10 seconds, flashes for 3 seconds and hides until a fresh update. Details remain available. |

Completed tasks clear even when you have stayed in the same agent throughout the task. Switching away during the 3-second countdown keeps the reminder for your next visit. With **Reduce Motion**, waiting dots stay red and completion dots stay green during the countdown.

## 2. Open the dropdown for context

Click the menu-bar item to see **conversation titles first**, with the agent, state, duration, and recent activity underneath.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-dropdown-dark.png" />
    <img src="docs/assets/screenshots/readme-dropdown-light.png" alt="English dropdown preview with named tasks, agent status, elapsed time, and quick actions" width="430" />
  </picture>
</p>

- Spot tasks waiting for input or approval, and see how long they have been waiting.
- Expand a task for more context, open its conversation or project, or mark its completion as read.
- Check recent completions, Codex quota, and optional usage or system details.
- Jump straight to the main window or settings. The dropdown stays attached to the menu bar as its content grows or shrinks.

## 3. Explore tasks in the main window

**Tasks on the left. The conversation in focus.** A shared task list brings recent work across agents into one place, with most of the window reserved for the selected task.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-tasks-dark.png" />
    <img src="docs/assets/screenshots/readme-tasks-light.png" alt="English task dashboard: live and recent multi-agent tasks beside a large conversation pane" width="1100" />
  </picture>
</p>

| Area | What you can do |
|---|---|
| **Live tasks** | Check current status, elapsed time, waiting time, and latest activity. |
| **Recent tasks** | Browse by last activity; filter by agent, 24 hours / 7 days / 30 days, or keyword. Codex turns are archived separately. |
| **Conversation** | Read local prompts and AI replies, select and copy text, follow new messages, or open a separate reading window. |
| **Monitor** | Inspect timing, observed tool calls, model, available per-turn tokens, and an activity timeline. |

<details>
<summary><strong>See the detailed task monitor</strong></summary>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-monitor-dark.png" />
    <img src="docs/assets/screenshots/readme-monitor-light.png" alt="English task monitor showing elapsed time, waiting time, tool calls, session information, and activity timeline" width="600" />
  </picture>
</p>

Open the source conversation, reveal its local log, or jump to the project folder from the task details.

</details>

**Usage and costs:** live token and spend rates, daily totals, and day / week / month trends grouped by agent, model, or provider. Rates are editable locally; CC Switch can supply reported costs and provider attribution.

**Optional desktop companion:** a cat that reacts to activity, with gear and a collection book. Monitoring works fully with the pet disabled. Sound is off by default.

*Images show native previews with synthetic tasks and English labels prepared for documentation. They contain no private conversations. Light and dark images follow your GitHub theme.*

## Agent support

Task state, task history, conversations, and usage are separate capabilities. Tokcat shows only what each local source provides.

| Source | Task state | Recent tasks | Conversation | Token / cost usage |
|---|---|---|---|---|
| **Codex** | Local lifecycle events | Yes, per turn | Yes | Yes |
| **Claude Code** | Opt-in local hooks | Yes | Yes | Yes |
| **WorkBuddy** | Explicit local database status | Yes, per session | Yes | Yes |
| **DeepSeek Harness** | Activity records only | Yes | — | Yes |
| **OpenClaw** | Activity records only | Yes | — | Yes |
| **Kimi** | Activity records only | Yes | — | Yes |
| **Cursor / Gemini CLI** | — | — | — | When local data is available |
| **CC Switch** | — | — | — | Provider attribution, reported cost, multiplier |

Codex reads local rollout events. Enable Claude Code lifecycle monitoring in **Settings → Agent**, then restart Claude Code sessions. Installation backs up and merges local hook settings; moving Tokcat requires re-enabling the hooks. WorkBuddy reads `~/.workbuddy/workbuddy.db` in read-only mode and links local conversation logs; an explicitly working session stays running while the database remains readable.

A quiet log is **not proof of completion**. An ended turn is not proof that a project is complete or tests passed. WorkBuddy does not infer per-turn start times. Activity-only records do not claim live execution state, and missing metrics remain unavailable. No estimated progress percentage is displayed without explicit step data.

## Start in 60 seconds

1. [Install Tokcat](https://github.com/SelinLee/tokcat/releases) and open it from Applications.
2. Use Codex or WorkBuddy as usual. For Claude Code task states, enable local hooks in **Settings → Agent**.
3. Choose your metrics in **Settings → Menu Bar**, then watch task dots and click for context.
4. Open **Tasks** to read conversations and inspect work, or **Usage** to review token and cost trends.

## Local data and privacy

Task monitoring reads local logs, explicit lifecycle events, and local state databases. No account or cloud sync is required, and usage and conversations are not uploaded. **The optional Codex quota readout** contacts the ChatGPT usage endpoint using a local Codex login; it can be disabled in settings.

- Task metadata and read state: `~/Library/Application Support/TokenCat/agent-sessions.json` and `agent-task-history.json`.
- Task archive: up to **30 days / 500 records**. Initial import scans logs modified in the last seven days with bounded reads, so older turns may be absent.
- Conversations: loaded on demand from the linked session, bounded to the last **4 MB / 200 messages**, with truncation notices. Text stays in view memory and is not copied to the archive. Attachments use placeholders; system messages, tool internals, and reasoning records are excluded.
- Claude hooks store sanitized lifecycle metadata, not conversation text or tool arguments, in the local `session-inbox/` directory.
- Usage statistics: local `tokencat.sqlite3`. Usage adapters start at the end of existing files rather than backfilling entire histories.

## Requirements

- macOS 13 Ventura or later  
- Dev build: Xcode 15+ / Swift 5.10+  

---

## Install

Download from [GitHub Releases](https://github.com/SelinLee/tokcat/releases):

### Recommended: DMG
1. Open `Tokcat-*-macos.dmg`  
2. Drag `Tokcat.app` into **Applications**  
3. **First launch**: right-click → **Open** (ad-hoc signed; one-time Gatekeeper bypass)  

### Alternative: Zip
1. Download `Tokcat-*-macos.zip` and unzip → `Tokcat.app`  
2. Drag into **Applications**  
3. Same first-launch step: right-click → **Open**  

Build a release locally:

```bash
TOKCAT_VERSION=0.5.0 scripts/package_app.sh
# Artifacts under dist/ (not committed):
#   Tokcat.app
#   Tokcat-0.5.0-macos.zip
#   Tokcat-0.5.0-macos.dmg
#   Tokcat-0.5.0-macos.sha256
#   INSTALL.txt
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
  ├─ AgentSessionMonitor → task state / history / conversations
  └─ Adapters → TokenEvent (tokens, cost, model, provider)
        │
        ├─ Throughput / daily totals / menu-bar live UI
        ├─ UsageStats (day·week·month · Agent/Model/Provider)
        ├─ SQLite persistence
        └─ PetEngine / Loot (optional)
```

| Path | Role |
|------|------|
| `Sources/TokcatKit/Monitor/` | Agent lifecycle, task history, conversation readers, optional quota |
| `Sources/TokcatKit/Adapters/` | Per-agent log parsing & provider attribution |
| `Sources/TokcatKit/Economy/` | Pricing, nutrition tiers, **UsageStats** |
| `Sources/TokcatKit/Monitor/CodexUsageMonitor.swift` | Optional Codex 5h/weekly quota fetch (local `auth.json` → ChatGPT usage endpoint) |
| `Sources/TokcatKit/Persistence/` | Local SQLite |
| `App/` | Menu bar, main window, floating pet |
| `App/PixelPet/` | Pixel animation |
| `docs/assets/screenshots/` | Product screenshots used in this README |
| `docs/` | Pixel / pet design notes (secondary) |

---

## Roadmap (summary)

- [x] Multi-agent task monitor, menu-bar dots, conversation details, WorkBuddy state
- [x] Multi-agent local log adapters + live tok/s / cost  
- [x] Day / week / month stats (Agent / Model / Provider)  
- [x] Menu-bar metrics & main window  
- [x] Pixel pet / loot / bag / codex  
- [x] DMG + Zip release packaging  
- [ ] More agents / log formats  
- [ ] Developer ID signing & notarization  

---

## Contributing

Issues and PRs welcome. Please **do not** commit:

- `dist/`, `.build/`, local `*.sqlite` / personal logs  
- API keys, account paths, private usage exports  

---

## License

[MIT](LICENSE)

Third-party model assets: see corresponding `ATTRIBUTION.md` / model READMEs.
