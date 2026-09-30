# Agent support and local data

The README separates live task states, recent activity, conversation reading, and billing. Enabling a usage adapter does not imply that it supplies task lifecycle events.

| Source | Local records | Setup / limits |
|---|---|---|
| Codex | `~/.codex/sessions/**/rollout-*.jsonl`, session index | Automatic. Lifecycle events supply per-turn state/history; token events supply billing. |
| Claude Code | `~/.claude/projects/*/*.jsonl` and optional local hook events | Enable hooks in Settings → Agent, then restart Claude sessions. Existing settings are backed up and merged. Re-enable hooks after moving the app. |
| WorkBuddy | `~/.workbuddy` trace database and linked local conversation logs | Read-only database access. Explicit session state is retained while the database remains readable. |
| WorkBuddy AI | `~/.workbuddy-ai` trace database and linked local conversation logs | Separate from WorkBuddy. Same session-state behavior. |
| DeepSeek Harness | `~/.dsh/storages/session_projcache/sessions` | Covers `dsh web` and DSH Desktop. Open steps mean running; projected active questions mean waiting. Conversation text comes from the turn outline. Compressed transcripts are not read. |
| OpenClaw | `~/.openclaw/agents/**/sessions/*.trajectory.jsonl` | Recent activity and `model.completed` usage, without full task lifecycle or conversation reading. |
| Kimi | Local Kimi Desktop `wire.jsonl` records | Recent activity and `usage.record` billing, without full task lifecycle or conversation reading. |
| Cursor | Compatible JSONL usage records under `~/.cursor` / Cursor Application Support | Best effort, disabled by default. Does not parse full task state or conversations. |
| Gemini CLI | Compatible JSONL usage records under `~/.gemini` | Best effort, disabled by default. Does not parse full task state or conversations. |
| CC Switch | `~/.cc-switch/cc-switch.db` | Provider attribution, reported charges and multipliers; proxy events are deduplicated against native agent logs. No task lifecycle. |

## DeepSeek Harness waiting prompts

Waiting is visible only when the harness projects an active `ask_user_question` into its session cache. The timed schema does this; the blocking schema in the bundled preset can look like ordinary work. Configure the `tool-ask-user` plugin with `mode: timed`, and use `timeout: -1` if the question should wait indefinitely. Tokcat cannot infer a prompt that the source has not exposed.

## What a task state means

Completion refers to a reported turn end, not completion of the whole project or successful tests. Quiet logs do not prove completion. WorkBuddy and DeepSeek Harness supply session-level states, without invented per-turn start times. A source that explicitly reports ongoing work stays running even during a long tool call. Internal delegated runs are not listed separately.

Missing durations, tool counts or tokens remain unavailable. Activity-only sources do not claim to be running, waiting or completed. The monitor does not show estimated progress percentages without explicit step data.

Codex quota is read from client-written local records only while the desktop client runs. Notifications and Claude hooks are opt-in. Conversation text is read from its source and is not copied into a separate transcript archive.

## Persistence and upgrades

Usage and adapter offsets use `~/Library/Application Support/Tokcat/tokcat.sqlite3`. Agent status/history caches and optional hooks use `~/Library/Application Support/TokenCat/`. The monitor-only redesign preserves those paths and usage records. New databases contain only usage and offset tables; retired pet tables in old databases remain untouched and are no longer read or updated.
