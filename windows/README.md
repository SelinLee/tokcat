# tokcat for Windows (preview)

[简体中文](README.zh-CN.md)

Double-click `Tokcat.cmd` on Windows 10 or 11. Windows PowerShell 5.1 and Windows Forms are included with Windows; no API key is needed. The application shows a taskbar window and a notification-area icon, both displaying the current task dots. Closing the window keeps the notification-area icon running; use its menu to reopen or quit. Windows may initially hide the notification-area icon in the overflow area; enable it in taskbar settings to keep it visible.

The preview reads Codex CLI/Desktop rollout JSONL under `%CODEX_HOME%\sessions`, or `%USERPROFILE%\.codex\sessions` when `CODEX_HOME` is unset, and the corresponding `session_index.jsonl`. It also reads the local Codex Work catalog in `sqlite\codex-dev.db`, WorkBuddy and WorkBuddy AI databases under `%USERPROFILE%\.workbuddy` and `%USERPROFILE%\.workbuddy-ai`, and DeepSeek Harness session projections under `%DSH_HOME%` or `%USERPROFILE%\.dsh`, and common Desktop directories under `%APPDATA%`. OpenClaw trajectory logs in `%USERPROFILE%\.openclaw\agents` and Kimi wire logs in `%USERPROFILE%\.kimi-work`, `%USERPROFILE%\.kimi-webbridge`, or the `kimi-desktop` and `kimi` folders under `%APPDATA%` are read as recent activity only; they cannot establish a running, waiting or completed state. The monitor reads source records locally and does not modify them. The list includes sessions updated in the last seven days, task state, title, project, phase, model, output tokens when reported, and latest activity. Double-click a Codex, DeepSeek or activity row to open its raw record, or a Work row to open its conversation. Yellow means running, orange means waiting or no activity for two minutes, red means failure, and green means a completed turn. Silence does not imply failure. The notification-area icon shows up to six task dots; hover to see counts, including when more than six are active. Completion and failure dots observed while tokcat runs remain until you right-click the corresponding task and mark it read. Unread reminder IDs and revisions are stored in `%LOCALAPPDATA%\Tokcat\reminders.json` and restored after restart when the same state is still present; entries older than seven days expire. Earlier completed tasks remain in the window without generating a new reminder.

This is an independent Windows preview, not feature parity with the macOS application. It currently supports local Codex rollout events, the local Work catalog, WorkBuddy session databases, DeepSeek Harness projections, and optional Claude Code hooks. CPU utilization, physical memory usage, network rates and locally reported Codex quota are shown in the window and notification-area tooltip. Network rates sum active non-loopback adapters; virtual adapters may count traffic more than once. Quota uses the most recent valid event found in the last 512 KiB of up to 20 recent files in each of the `sessions` and `archived_sessions` folders; its record time is displayed. A short window (up to 48 hours) is labeled `5h`, and a longer one `周`; after the recorded reset time it becomes unavailable until a new event arrives. These are client-written observations, not a live account query. Other agents, usage/cost dashboards, notifications, and desktop companion are not implemented. For task state, the monitor first reads the last 512 KiB of a Codex rollout; if that has no lifecycle event, it streams the full log, skipping individual records over 2 MiB. Logs, catalog, and projections do not always expose approvals or other lifecycle signals; missing information is not inferred. Work status comes from a client-maintained catalog that can lag and does not include output tokens. WorkBuddy and Claude status are session-level and do not supply a transcript link or output tokens. The token count is the most recent reported count and may be per-turn or cumulative depending on the log format. Output tok/s is a rolling estimate from observed output-counter changes (approximately 60 seconds), excludes input and cache, starts after two samples and may reflect batched updates. It is unavailable after a turn finishes. The monitor makes no network requests and uses no credentials.

## Optional Claude Code monitoring

Run the following command to add tokcat's hooks to `%USERPROFILE%\.claude\settings.json`, then restart existing Claude Code sessions:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Configure-ClaudeHooks.ps1
```

The setup retains unrelated settings and hooks and writes a timestamped backup alongside the settings file. It uses Claude Code's [command-hook `args` format and `onFailure` option](https://code.claude.com/docs/en/hooks); use Claude Code 2.1.295 or later. Hooks record only session ID, project path, state, phase and timestamps in `%LOCALAPPDATA%\Tokcat\claude`; prompts, responses and tool inputs are not saved. Synchronous hooks may add startup latency per event. If you move the tokcat folder, remove the old hooks before moving and install again at the new location. To remove hooks installed from the current folder, run the same command with `-Remove`; this preserves other hooks and leaves prior state files intact.

Launch with an alternate data directory:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\windows\Tokcat.ps1 -CodexHome 'C:\path\to\.codex'
```

Run parser checks with `powershell.exe -NoProfile -File .\windows\Test-Monitor.ps1`.

Build a redistributable ZIP with `powershell.exe -NoProfile -File .\windows\Package.ps1`. It creates a new archive under `dist/`; extract it and run `tokcat-windows\Tokcat.cmd`. Windows CI publishes the ZIP as a workflow artifact.
