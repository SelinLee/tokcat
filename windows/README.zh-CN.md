# tokcat Windows 预览版

[English](README.md)

在 Windows 10 或 11 上双击 `Tokcat.cmd` 启动。程序需要系统自带的 Windows PowerShell 5.1，不需要 API 密钥。任务栏窗口图标和通知区域图标都会显示任务状态点。关闭窗口后程序仍在通知区域运行；右键图标可重新打开窗口或退出。若图标被折叠，请在任务栏设置中将它设为始终显示。

窗口列出最近七天的任务、状态、项目、阶段、模型和可用的输出 token 数。双击 Codex、DeepSeek 或活动记录可以打开原始文件；双击 Codex Work 任务会打开对应会话。通知区域最多显示六个状态点：黄色表示运行，橙色表示等待回答、等待授权或长时间无活动，红色表示失败，绿色表示本轮结束。日志安静超过两分钟只表示无新活动，不代表失败。图标悬停提示显示汇总信息；右键任务可将完成或失败提醒标记为已读。提醒保存在 `%LOCALAPPDATA%\Tokcat\reminders.json`，重启后仍匹配的未读提醒会恢复，超过七天的记录会过期。

程序还显示 CPU、物理内存、网络收发速率、观察到的输出 tok/s 和 Codex 客户端写入本地日志的额度。网络速度按活动的非回环网卡求和，虚拟网卡可能导致重复计数。输出速度以约 60 秒内报告的输出 token 变化估算，不含输入和缓存；至少需要两次采样，且可能受到批量上报影响。额度显示记录时间；超过记录的重置时间后显示为不可用，直到客户端写入新记录。额度读取范围是 `sessions` 和 `archived_sessions` 中各最多 20 个最近文件的末尾 512 KiB，短于或等于 48 小时的窗口标为 `5h`，较长窗口标为 `周`。

当前支持：

- Codex CLI／桌面端本地会话和 Codex Work 本地目录。
- WorkBuddy、WorkBuddy AI 和 DeepSeek Harness 的本地会话状态。
- Claude Code 的可选 hooks，见下方安装方式。
- OpenClaw、Kimi 的本地活动记录；这些记录不提供可靠的运行、等待或完成状态，因此显示为未知。

任务状态读取首先检查 Codex 日志末尾 512 KiB；若没有生命周期事件，会流式读取完整日志并跳过超过 2 MiB 的单条记录。来源未提供的信息不会推断。Windows 版目前尚未实现用量／费用看板、其他 Agent 接入、通知和桌宠，详细数据路径见 [英文说明](README.md)。

如需启用 Claude Code 状态，在项目根目录运行以下命令并重启现有 Claude 会话：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Configure-ClaudeHooks.ps1
```

需要 Claude Code 2.1.295 或更高版本。配置脚本保留已有设置和其他 hooks，并在设置文件旁创建带时间戳的备份。hooks 只写入会话 ID、项目路径、状态、阶段和时间，不保存提示词、回复或工具输入。同步 hooks 每次事件可能增加少量启动延迟。移动 tokcat 文件夹前，应先使用下方命令移除旧路径的 hooks，移动后重新启用：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Configure-ClaudeHooks.ps1 -Remove
```

移除操作保留其他 hooks 和已有状态文件。可使用以下命令验证本地解析和窗口初始化：

```powershell
powershell.exe -NoProfile -File .\windows\Test-Monitor.ps1
```

在项目根目录运行 `powershell.exe -NoProfile -File .\windows\Package.ps1` 可在 `dist/` 下生成独立 ZIP。解压后运行 `tokcat-windows\Tokcat.cmd`；Windows CI 也会将 ZIP 保存为工作流产物。
