<div align="center">

# tokcat

**Keep your agents' work in view.**

A native macOS monitor for multiple AI agents: live task states, waiting alerts, local conversations, usage trends, and a quiet companion at the edge of your desktop.

Now with a quick launcher for apps, live calculations, terminal commands, and websites—one keyboard shortcut away.

[English](README.md) · [简体中文](README.zh-CN.md)

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black.svg)](#install) [![Swift](https://img.shields.io/badge/Swift-native-F05138.svg)](#build-from-source) [![MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**[Download](https://github.com/SelinLee/tokcat/releases)** · [Quick launcher](#quick-launcher) · [Supported agents](#supported-agents) · [Get started](#get-started)

</div>

## Quick launcher

> **New in 0.7.10:** [Download the macOS release](https://github.com/SelinLee/tokcat/releases/latest).

Press **Control + Space** for a compact rounded input field. Matches or results appear only after typing, and the field closes immediately when you submit. The menu-bar magnifying glass opens it too.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-launcher-input-dark.png" />
  <img src="docs/assets/screenshots/readme-launcher-input-light.png" alt="The tokcat launcher initially shows only a compact rounded input field" width="640" />
</picture>

| Try typing | Feature | Press Return to |
|---|---|---|
| `Chrome` | Match English/Chinese app names, pinyin, or initials | Open the selected app |
| `sqrt(9)+2^3` | See the result `11` live | Copy the result |
| `> pwd` | Terminal commands | Open Terminal and execute |
| `baidu artificial intelligence` | Web search; `google` and `bing` work too | Search in your default browser |
| `example.com` | Recognize a domain or full HTTP(S) URL | Open the website |
| `setup` | Settings shortcut | Open tokcat Settings |
| `empty` | Editable preset for emptying Trash | Confirm, then empty Trash |
| `gg` | Editable preset for quitting other apps | Confirm by default, then request quitting |

- **History appears in the input itself:** the latest 50 entries stay on your Mac. Press **↑** in an empty field, then **↑ / ↓** to browse. Each entry replaces the input text so you can edit it or press Return to reuse it.
- **Remembered position:** drag the background or search icon. Reopening or restarting preserves the location; display changes keep it visible.
- **List first, details on click:** **Settings → Commands** and **Settings → Websites** show names, keywords, and enabled states. Click an item for details. Save applies an edit; Cancel keeps the previous configuration.
- **Record your shortcut:** change or disable the global key combination in **Settings → General → Application Launcher**. Registration conflicts appear there.

<details>
<summary>See calculator, web search, and settings previews</summary>

**Live calculation** supports parentheses, arithmetic, `^` / `**` powers, postfix percentages (`200*10%`), scientific notation, and the constants `pi` / `π` and `e`. Functions include `sqrt`, `abs`, `pow`, `min`, `max`, `round`, `floor`, `ceil`, `exp`, `ln`, `log` / `log10`, `log2`, and `sin` / `cos` / `tan` (radians). Prefix with `=` for explicit calculator mode. Incomplete expressions, division by zero, and invalid arguments show inline hints.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-launcher-calculator-dark.png" />
  <img src="docs/assets/screenshots/readme-launcher-calculator-light.png" alt="Typing sqrt(9)+2^3 shows the live result 11, ready to copy with Return" width="640" />
</picture>

**Website keywords** open a favorite site or perform a search. Use `{query}` in the search URL, such as `https://www.baidu.com/s?wd={query}`. Search terms are URL-encoded as text. The `github` preset opens GitHub directly.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-launcher-search-dark.png" />
  <img src="docs/assets/screenshots/readme-launcher-search-light.png" alt="The baidu keyword followed by search terms produces a web search action" width="640" />
</picture>

**Custom commands** support terminal commands, emptying Trash, and quitting other applications. Emptying Trash requires confirmation. Quitting preserves tokcat and Finder and lets each app prompt to save unfinished work. macOS may ask for Automation permission on the first Terminal or Finder action.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-launcher-websites-dark.png" />
  <img src="docs/assets/screenshots/readme-launcher-websites-light.png" alt="Compact website settings list with names, keyword badges, toggles, and click-to-edit details" width="900" />
</picture>

</details>

## A quiet desktop companion

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-avatars-dark.png" />
  <img src="docs/assets/screenshots/readme-avatars-light.png" alt="Manually selectable neutral-faced toki boy and three biti outfits" width="1040" />
</picture>

The new companion stays attached to a screen edge, the bottom-right corner, or either side of the Dock. Dragging only adjusts along the selected edge.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-companion-dark.png" />
  <img src="docs/assets/screenshots/readme-companion-light.png" alt="Edge-attached companions with a narrow transparent ticker, input bubble and click-open details" width="1040" />
</picture>

- **Quiet by default:** no persistent bubble. Recent tools and phases scroll upward one line at a time above the character, within its width.
- **Details when needed:** click the character or wait for an input/approval request to open a bubble above it. Click the bubble to open Tasks.
- **Your choice of character:** male **toki**, or **biti** in coral, whale, or violet outfits. All use calm, neutral expressions. Model families determine activity text colors independently of the character.

Choose the appearance and attachment in **Settings → Desktop companion**, or the character's right-click menu. The **Head information** setting also offers a persistent list: each title takes up to two lines with a trailing ellipsis for overflow, followed by its own output tok/s on a separate line. Tasks stack vertically. [Companion behavior](docs/DesktopCompanion.md)

## Follow multiple agents in one place

See who is running, who needs an answer, and whose reply is ready. The shared task list brings work across agents together, with the selected conversation taking most of the window.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-tasks-dark.png" />
  <img src="docs/assets/screenshots/readme-tasks-light.png" alt="Multi-agent tasks beside the selected local conversation" width="1180" />
</picture>

- **Live tasks:** running, waiting for input, waiting for approval, completed, failed, or interrupted.
- **Recent work:** filter by agent, keyword, or 24 hours / 7 days / 30 days. Codex history separates individual turns.
- **Local conversations:** read prompts and replies, copy text, follow new messages, or open a separate reading window.

## Glance at the menu bar

One status dot per task, next to the metrics you choose. Keep several agents in sight while working in another app.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-menubar-dark.png" />
  <img src="docs/assets/screenshots/readme-menubar-light.png" alt="Task status dots, token throughput, spend rate, system metrics and Codex quota" width="1040" />
</picture>

| Indicator | Meaning |
|---|---|
| Pulsing yellow | Running |
| Alternating yellow / red | Needs your input or approval |
| Green | The turn finished; background replies remain until viewed |
| Solid red | Failed |
| Hollow red | Running task with no new activity for 2 minutes; stays visible until activity resumes or the turn ends |
| Hollow gray | Unknown state or interrupted; see details for context |

The strip shows up to six dots, then `+N`. Foreground completions flash for three seconds and clear automatically. Reduce Motion uses steady colors. CPU, GPU, memory, network, token throughput, spend rate and local Codex quota are optional.

## Click for context

The dropdown shows conversation titles, source agents, current states, elapsed time, and waiting time. Below elapsed time, each task shows estimated output tok/s over the last 60 seconds (including reasoning output, excluding input and cache; `—` means insufficient data). After 30 seconds without activity, it shows the silent interval; after 2 minutes, a red inactivity warning appears. Long tools and network waits can trigger this warning without the task having failed. Expand a task, open its conversation or project, mark a completion as read, or jump to the main window.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-dropdown-dark.png" />
  <img src="docs/assets/screenshots/readme-dropdown-light.png" alt="Named multi-agent tasks and waiting durations in the dropdown" width="430" />
</picture>

## Inspect each task

Open **Monitor** for timing, the latest phase, observed tool calls, model, available per-turn tokens, and the activity timeline. Open the source conversation, project folder, or local log from the same view.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-monitor-dark.png" />
  <img src="docs/assets/screenshots/readme-monitor-light.png" alt="Task timing, waiting, tool calls, model and activity timeline" width="600" />
</picture>

## Understand usage and costs

Compare day, week, or month trends by **agent, model, or provider**. See input/output tokens, costs, billing rates, and each group's share. Reported costs and pricing estimates are labeled separately; rates are editable locally.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-usage-dark.png" />
  <img src="docs/assets/screenshots/readme-usage-light.png" alt="Weekly token trends and usage breakdown across five agents" width="1180" />
</picture>

<details>
<summary>See the cost view</summary>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-costs-dark.png" />
  <img src="docs/assets/screenshots/readme-costs-light.png" alt="Cost trends and per-agent reported cost breakdown" width="1180" />
</picture>

CC Switch can add provider attribution, reported charges, and pricing multipliers. Codex 5-hour / weekly remaining quota comes from local client logs and appears only while the desktop client runs.

</details>

## Supported agents

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-agents-dark.png" />
  <img src="docs/assets/screenshots/readme-agents-light.png" alt="Agent support grouped by live state and conversations, activity and usage, and optional usage adapters" width="1040" />
</picture>

| Agent | Live task state | Recent tasks | Conversation | Usage / cost |
|---|---|---|---|---|
| **Codex** | Local lifecycle events | Per turn | ✓ | ✓ |
| **Claude Code** | Automatic local registry; optional hooks | ✓ | ✓ | ✓ |
| **WorkBuddy** | Local database state | Per session | ✓ | ✓ |
| **WorkBuddy AI** | Local database state | Per session | ✓ | ✓ |
| **DeepSeek Harness** | Local session projection | Per session | ✓ | ✓ |
| **OpenClaw** | Activity records only | Activity | — | ✓ |
| **Kimi** | Activity records only | Activity | — | ✓ |
| **Cursor** | — | — | — | Compatible JSONL logs, optional |
| **Gemini CLI** | — | — | — | Compatible JSONL logs, optional |

**CC Switch** is a billing integration for provider attribution and reported costs. It does not supply task lifecycle states.

Claude Code running state is read automatically from the local session registry when available. Optional hooks add approval waits, failures and explicit turn ends; idle alone does not mean completion. DeepSeek Harness covers `dsh web` and DSH Desktop; waiting prompts require the harness's **timed ask-user** mode. Cursor and Gemini CLI adapters are disabled by default and require compatible local usage records. [Setup and data sources](docs/AgentSupport.md)

tokcat displays what local sources report. A quiet log does not prove completion, and a finished turn does not prove the whole project is done. Missing metrics stay unavailable; no invented progress percentages are shown.

## Get started

1. Install and open tokcat, then use your agents as usual.
2. Claude Code sessions with a local registry appear automatically. For detailed lifecycle events or older clients without a registry, enable hooks in **Settings → Agent**, then restart existing Claude Code sessions.
3. Pick menu-bar metrics and watch the task dots. Open **Tasks** for conversations, or **Usage** for trends.
4. Choose toki / biti and an attachment in **Settings → Desktop companion**.

## Install

Requires **macOS 13+**. Download a DMG or ZIP from [Releases](https://github.com/SelinLee/tokcat/releases), place `tokcat.app` in Applications, then right-click → **Open** on first launch. Builds are ad-hoc signed; Developer ID notarization is not included. The 0.7.10 download is a universal build for Apple Silicon and Intel Macs.

Monitoring reads local records; no API key is required. Usage data stays in `~/Library/Application Support/Tokcat/`, and task caches / optional Claude hooks in `~/Library/Application Support/TokenCat/`. The companion shares the task monitor's state. Upgrading preserves usage history and monitoring preferences.

## Build from source

```sh
git clone https://github.com/SelinLee/tokcat.git
cd tokcat
swift build
swift test
swift run TokcatApp
```

Package a release with `bash scripts/package_app.sh`. Build artifacts stay in `dist/`.

| Location | Purpose |
|---|---|
| `App/` | Menu bar, task/conversation views, usage dashboard and settings |
| `App/Companion/` | Transparent companion window, bubbles, ticker and attachment |
| `Sources/TokcatKit/` | Local adapters, task lifecycle/history, pricing and usage persistence |
| `Tests/` | Monitor, adapter, usage, settings and companion regression checks |
| `scripts/docs_screenshots/` | Reproducible native documentation previews |

Monitoring images use native views with synthetic data and English documentation labels; launcher screenshots retain the current Chinese UI. No private conversations are shown, and the images do not imply full app localization. Light/dark images follow your GitHub theme. [Monitor rendering instructions](scripts/docs_screenshots/README.md)

[MIT](LICENSE). Companion interaction is inspired by [DeepSeek Balance Whale Widget](https://github.com/MeteorNOX/DeepSeek-Balance-Whale-Widget); original toki / biti artwork uses the project's character references.
