# Tokcat 🐱

一只桌面宠物猫，靠你使用 AI coding agent（目前是 Claude Code）产生的 token 用量喂养和成长。本地优先，默认离线运行，不联网、不上传任何数据。

## 功能

- **菜单栏图标**：自绘立体黑白猫头（template），可选旁显示 CPU/内存/网速/温度压力。
- **菜单栏系统指标**：整机 CPU、内存、网速、热压力；可在设置中开关。
- **Agent Token 监控**：菜单栏只展示 token/成本相关内容（今日用量、总成本、最近事件），不再混入工具进程 CPU。
- **独立设置窗口（中文分页）**：菜单栏 / 监控 / 宠物 / 通用；图标库、指标旁路显示、皮肤库与自定义模型导入；偏好写入 `UserDefaults`。
- **桌面悬浮宠物**：透明悬浮 3D 宠物，跟随 mood / hunger 做待机与表情动画。皮肤库：**方块猫 / 粉猫（CC0）/ Q版猫娘 / 自定义 USDZ 导入**。
- **Tier 1 · 通用进程监控**：`libproc` 仍可用于已知工具进程（内部保留）；菜单栏默认聚焦整机指标。
- **Tier 2 · Token 适配器**：解析 `~/.claude/projects/*/*.jsonl` 本地日志，零配置、无需装 hook，可回溯历史会话。
- **Token 价值分层**：按模型单价把 token 分为 premium / standard / economy 三档，分别增强猫的 intelligence / vitality 属性。
- **连续情绪值**：响应延迟映射为 0-1 的连续 mood 值（指数滑动平均），不是三态机。
- **本地 SQLite 持久化**：宠物状态、历史用量事件、适配器读取进度全部落地本地数据库，重启不丢失、不重复计算。

## 环境要求

- macOS 13+
- Xcode 15+ / Swift 5.10+

## 发行版

从 [GitHub Releases](https://github.com/SelinLee/tokcat/releases) 下载 `Tokcat-*-macos.zip`：

1. 解压得到 `Tokcat.app`
2. 拖到「应用程序」
3. 首次启动：右键 → 打开（ad-hoc 签名，需绕过 Gatekeeper 一次）

本地打包：

```bash
TOKCAT_VERSION=0.2.0 scripts/package_app.sh
# 产物：dist/Tokcat.app 与 dist/Tokcat-0.2.0-macos.zip
```

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
  App/Pet3D/                  # SceneKit 宠物：cube cat / catgirl / USDZ loader
  App/Resources/Models/       # 可选 USDZ 等模型资源
  docs/CatgirlModel.md        # 猫娘资产许可与 VRoid→USDZ 转换步骤
  Sources/TokcatKit/
    Monitor/                  # SystemMetricsMonitor + ProcessMonitor
    Settings/                 # AppSettings + UserDefaults store
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
- [ ] Phase 2：扩展适配器（Codex CLI、Cursor、Gemini CLI）、成本可视化面板、更多宠物皮肤
- [x] Phase 1.5：桌面宠物皮肤库（方块猫 / 粉猫 / Q版猫娘 / 自定义导入）+ 待机表情动画 + USDZ 管线（见 [docs/CatgirlModel.md](docs/CatgirlModel.md)）
- [x] Phase 1.6：macOS `.app` 打包脚本与 GitHub Release 分发
- [ ] Phase 3：可选云端效率排行榜（opt-in）
- [ ] Phase 4：团队/组织聚合看板

## License

[MIT](LICENSE)
