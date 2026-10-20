# Agent support and local data

The README separates live task states, recent activity, conversation reading, and billing. Enabling a usage adapter does not imply that it supplies task lifecycle events.

| Source | Local records | Setup / limits |
|---|---|---|
| Codex | `~/.codex/sessions/**/rollout-*.jsonl`, session index, `~/.codex/sqlite/codex-dev.db` Work catalog | Automatic. Rollout events supply per-turn state/history and billing. ChatGPT-backed Work tasks share the Codex toggle and read only catalog metadata. |
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

Per-session output speed uses changes in the projection's `tokenUsage.totals.outputTokens` over the last 60 seconds. Input and cache tokens are excluded. The first observation establishes a baseline; speed becomes available after a later usage snapshot. Samples survive restart, stop accumulating while the file is unchanged, reset after a new turn or counter rollback, and show zero while waiting. Usage is reported in batches, so this is observed throughput rather than instantaneous decoding speed.

Waiting is visible only when the harness projects an active `ask_user_question` into its session cache. The timed schema does this; the blocking schema in the bundled preset can look like ordinary work. Configure the `tool-ask-user` plugin with `mode: timed`, and use `timeout: -1` if the question should wait indefinitely. tokcat cannot infer a prompt that the source has not exposed.

## What a task state means

New desktop Work tasks (`conversation_origin: tpp` or `flora`) do not write Codex rollouts. tokcat reads their local catalog titles and explicit async status: streaming/busy/background means running, and an unread result means the reply ended. Null, idle realtime and unrecognized codes remain unknown. Ordinary ChatGPT chats are excluded. Account/host identities are retained separately, and Work refreshes never remove native Codex sessions. The catalog may lag the live conversation; it supplies no reliable per-turn timing, waiting/failure signals, output tokens or local transcript. These values remain unavailable, and Work conversations open through their ChatGPT link. No credentials or network requests are used.

Work conversations with an unknown status remain available in the main task browser. Their menu dots, dropdown rows and summary counts share a 13-second uncertainty window (steady for 10 seconds, then flashing for 3 seconds). Old unknown conversations do not reappear merely because the catalog is polled or tokcat restarts. A fresh loss of a previously known cloud status starts one new uncertainty window; a known running state restores the menu entry even if the catalog timestamp has not changed. If the Work catalog stays unreadable for two minutes, cached nonterminal Work states also become unknown and expire from the menu after the same window. Local Codex rollouts and explicit completion reminders are preserved. Missing cloud state never implies completion or failure.

Completion refers to a reported turn end, not completion of the whole project or successful tests. Quiet logs do not prove completion. WorkBuddy and DeepSeek Harness supply session-level states, without invented per-turn start times. A source that explicitly reports ongoing work stays running even during a long tool call. Internal delegated runs are not listed separately. Codex records marked `thread_source: subagent` or carrying `source.subagent` metadata are excluded alongside guardian reviews; upgrading also removes their previously cached state dots and task rows. User-created conversations and forks remain separate.

Unread completion and failure dots remain until read. Bringing the corresponding agent app to the foreground flashes its reminders for three continuous seconds, then marks them read and removes their menu-bar dots. Switching away restarts the countdown on the next visit. Reduced motion keeps the dots steady during the same countdown. Generic terminals and browsers are not mapped to an agent; their reminders can be marked read manually in tokcat.

Missing durations, tool counts or tokens remain unavailable. Activity-only sources do not claim to be running, waiting or completed. The monitor does not show estimated progress percentages without explicit step data.

Codex quota is read from client-written local records only while the desktop client runs. Notifications and Claude hooks are opt-in. Conversation text is read from its source and is not copied into a separate transcript archive.

## Persistence and upgrades

Usage and adapter offsets use `~/Library/Application Support/Tokcat/tokcat.sqlite3`. Agent status/history caches and optional hooks use `~/Library/Application Support/TokenCat/`. The monitor-only redesign preserves those paths and usage records. New databases contain only usage and offset tables; retired pet tables in old databases remain untouched and are no longer read or updated.
