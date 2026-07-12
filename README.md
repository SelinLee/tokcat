# Tokcat 🐱

一只桌面宠物猫，靠你使用 AI coding agent（目前是 Claude Code）产生的 token 用量喂养和成长。本地优先，默认离线运行，不联网、不上传任何数据。

## 功能

- **菜单栏图标**：黑白猫头（SF Symbols），点开查看当前状态摘要。
- **桌面悬浮宠物**：一只跟随 mood / hunger 变化表情的猫，悬浮在屏幕上，`.floating` 层级。
- **Tier 1 · 通用进程监控**：零配置，通过 `libproc` 轮询已知开发工具/AI CLI 的 CPU、内存占用。
- **Tier 2 · Token 适配器**：解析 `~/.claude/projects/*/*.jsonl` 本地日志，零配置、无需装 hook，可回溯历史会话。
- **Token 价值分层**：按模型单价把 token 分为 premium / standard / economy 三档，分别增强猫的 intelligence / vitality 属性。
- **连续情绪值**：响应延迟映射为 0-1 的连续 mood 值（指数滑动平均），不是三态机。
- **本地 SQLite 持久化**：宠物状态、历史用量事件、适配器读取进度全部落地本地数据库，重启不丢失、不重复计算。

## 环境要求

- macOS 13+
- Xcode 15+ / Swift 5.10+

## 构建与运行

```bash
swift build
swift test
swift run TokcatApp
```

或者用 Xcode 打开 `Package.swift` 直接运行调试。

首次通过 ad-hoc 签名的构建产物运行（非 Xcode 直接运行）时，如果遇到 Gatekeeper 拦截提示"无法打开，因为无法验证开发者"，在 Finder 中右键该 App → "打开"，绕过一次即可。

## 架构

```
Tokcat/
  App/                        # SwiftUI app：菜单栏 + 悬浮宠物窗口
  Sources/TokcatKit/
    Monitor/                  # ProcessMonitor（libproc 轮询，Tier 1）
    Adapters/                 # AgentAdapter 协议 + ClaudeCodeAdapter（Tier 2）
    Economy/                  # TokenEconomy：定价表、营养分层、成本聚合
    Speed/                    # SpeedTracker：连续速度→情绪映射
    Pet/                      # PetEngine：状态机、属性、升级
    Persistence/              # 本地 SQLite 存储
    Models/                   # 数据模型
  Tests/TokcatKitTests/
```

详细设计文档见 [.claude/plan.md](.claude/plan.md)。

## 隐私

Tokcat 只读取本地日志文件和本地进程信息，不做任何网络请求，不上传使用数据。所有状态持久化在 `~/Library/Application Support/TokenCat/tokencat.sqlite3`。

## 路线图

- [x] Phase 1（MVP）：菜单栏 + 悬浮宠物、两层监控、营养分层、连续情绪值、本地持久化
- [ ] Phase 2：扩展适配器（Codex CLI、Cursor、Gemini CLI）、成本可视化面板、更多宠物皮肤、真 3D 悬浮猫模型
- [ ] Phase 3：可选云端效率排行榜（opt-in）
- [ ] Phase 4：团队/组织聚合看板

## License

[MIT](LICENSE)
