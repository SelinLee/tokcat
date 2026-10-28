# tokcat for Windows (preview)

Double-click `Tokcat.cmd` on Windows 10 or 11. Windows PowerShell 5.1 and Windows Forms are included with Windows; no API key is needed. The application shows a taskbar window and a notification-area icon. Closing the window keeps the icon running; use its menu to reopen or quit. Windows may initially hide the icon in the overflow area; enable it in taskbar settings to keep it visible.

The preview reads Codex CLI/Desktop rollout JSONL under `%CODEX_HOME%\sessions`, or `%USERPROFILE%\.codex\sessions` when `CODEX_HOME` is unset, and the corresponding `session_index.jsonl`. It also reads the local Codex Work catalog in `sqlite\codex-dev.db` and DeepSeek Harness session projections under `%DSH_HOME%` or `%USERPROFILE%\.dsh`, and common Desktop directories under `%APPDATA%`. It reads files locally and does not modify them. The list includes sessions updated in the last seven days, task state, title, project, phase, model, output tokens when reported, and latest activity. Double-click a row to open its raw record or Work conversation. Yellow means running, orange means waiting or no activity for two minutes, red means failure, and green means a completed turn. Silence does not imply failure. A single icon summarizes multiple tasks; the window lists them separately.

This is an independent Windows preview, not feature parity with the macOS application. It currently supports local Codex rollout events, the local Work catalog, and DeepSeek Harness projections. Claude Code, other agents, approval state, usage/cost dashboards, notifications, and desktop companion are not implemented. The monitor reads only the last 512 KiB of each rollout; when that does not contain a lifecycle event, its state is unknown. Logs, catalog, and projections do not always expose approvals or other lifecycle signals; missing information is not inferred. Work status comes from a client-maintained catalog that can lag and does not include output tokens. The token count is the most recent reported count and may be per-turn or cumulative depending on the log format. The monitor makes no network requests and uses no credentials.

Launch with an alternate data directory:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\windows\Tokcat.ps1 -CodexHome 'C:\path\to\.codex'
```

Run parser checks with `powershell.exe -NoProfile -File .\windows\Test-Monitor.ps1`.
