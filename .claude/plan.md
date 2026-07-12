# TokenCat 项目规划

## 1. 定位与差异化

在现有开源方案（AgentPet / ClaudeBar / Tokengochi / claude-pet）基础上，TokenCat 的差异化点：

1. **监控范围不限于 AI coding agent** —— 通用进程活动监控作为独立层，AI token 是其中一种特殊数据源，而非唯一数据源。
2. **Token 价值分层 → 宠物多维属性**，不是单一 XP 曲线。贵/高价值 token 增强"智力"类属性，普通 token 增强"体力/基础成长"。
3. **响应速度 → 连续情绪值**，不是 running/waiting/done 三态机。
4. **成本可视化**：token 换算为实际花费，预算燃烧率预测。
5. **效率导向排行榜**（用得省/产出高，而非用得多），Phase 3 才做，且默认关闭。
6. **本地优先**：默认离线运行，联网同步/排行榜全部 opt-in。

## 2. 技术栈决策

- **Swift / SwiftUI 原生 macOS app**（`MenuBarExtra` 做菜单栏，独立 `NSWindow` 悬浮窗做桌面宠物）。原生体验最好，且与 AgentPet 同技术栈，方便未来互相参考代码。
- 分发方式对齐 AgentPet：ad-hoc 签名 + Homebrew/DMG，README 注明 Gatekeeper 首次打开需右键"打开"。

## 3. 监控架构：两层设计

**Tier 1 · 通用进程监控（零配置）**
用 `libproc` 轮询运行中进程的 CPU / 内存占用，按 bundle ID / 进程名匹配已知开发工具、AI CLI，产出统一的"活跃度"信号。不做 per-process 网络监控——macOS 上这需要 NetworkExtension 系统级权限，复杂度和签名成本都不匹配 MVP，明确排除到风险清单。

**Tier 2 · Token 适配器（协议化，可扩展）**
定义 `AgentAdapter` 协议，每个协议实现负责读取某个 AI 工具的本地用量数据。MVP 只做一个适配器：

- **ClaudeCodeAdapter**：解析 `~/.claude/projects/*/*.jsonl` 本地日志（同 ccusage/Claude-Code-Usage-Monitor 的做法），零配置、无需装 hook、可回溯历史会话。用消息时间戳近似 TTFT/响应延迟。

Phase 2 再扩展 Codex CLI、Cursor、Gemini CLI 等适配器，复用同一协议，这是"支持众多 agent"需求的正确落地方式——不是一次性支持全部，而是先把适配层做对，逐个加。

## 4. 核心模块（Swift Package `TokenCatKit` + App 层）

```
TokenCat/
  App/                        # SwiftUI app target：菜单栏 + 悬浮宠物窗口
  Sources/TokenCatKit/
    Monitor/                  # ProcessMonitor（libproc 轮询）
    Adapters/                 # AgentAdapter 协议 + ClaudeCodeAdapter
    Economy/                  # TokenEconomy：定价表、营养分层、成本聚合
    Speed/                    # SpeedTracker：连续速度→情绪映射
    Pet/                      # PetEngine：状态机、属性、升级、成就
    Persistence/              # 本地 SQLite 存储 + 版本迁移
    Models/                   # 数据模型
  Tests/TokenCatKitTests/
  Resources/Sprites/          # 宠物精灵资源（猫为默认，皮肤系统可扩展狗/虚拟人）
```

## 5. 数据模型草图

```swift
struct TokenEvent {
    var timestamp: Date
    var source: AgentSource      // .claudeCode, .codex, ...
    var model: String
    var inputTokens: Int
    var outputTokens: Int
    var cachedTokens: Int
    var costUSD: Double
    var latencyMs: Double?       // 近似 TTFT，来自日志时间戳
}

enum NutritionTier { case premium, standard, economy }  // 按模型单价分层

struct PetStats {
    var intelligence: Double     // 高价值 token 累积
    var vitality: Double         // 持续使用时长/连续性
    var energy: Double           // 速度体验累计
}

struct PetState {
    var level: Int
    var xp: Double
    var stats: PetStats
    var hunger: Double            // 0-1，随时间衰减，喂食恢复
    var mood: Double               // 0-1，连续值，来自 SpeedTracker
}

protocol AgentAdapter {
    var source: AgentSource { get }
    func pollNewEvents() -> [TokenEvent]
}
```

宠物引擎按"皮肤"抽象，猫是默认皮肤，狗/虚拟人后续作为新皮肤加入，不需要改动状态机。

## 6. 路线图

**Phase 1（MVP）**
- 菜单栏 + 桌面悬浮宠物窗口框架
- Tier 1 通用进程监控（CPU/内存）
- Tier 2：ClaudeCodeAdapter（日志解析）
- 营养分层（至少 3 档）→ 至少 2 个宠物属性
- 连续速度→情绪映射
- 本地 SQLite 持久化，零网络依赖
- 1 只猫，多帧精灵动画，状态按 mood/hunger 混合
- 开源基础设施：MIT License、README、CI（对齐 AgentPet 的 GitHub Actions 模式）

**Phase 2**
- 扩展适配器：Codex CLI、Cursor、Gemini CLI（复用 `AgentAdapter` 协议）
- 成本可视化面板 + 预算燃烧率预测
- 更多宠物皮肤（狗、虚拟人）

**Phase 3**
- 可选云端：效率导向排行榜（匿名聚合指标，非消耗量排行），opt-in 账号
- 跨设备同步（可选）

**Phase 4（stretch）**
- 团队/组织聚合看板
- 多宠物桌面互动场景化

## 7. 关键技术风险

- Per-process 网络监控在 macOS 上成本过高，MVP 明确不做。
- 非 App Store 分发需 ad-hoc 签名，首次启动会被 Gatekeeper 拦截，需在文档中说明绕过步骤。
- Claude Code 本地日志格式可能随版本变化，适配器需要做版本兼容层。
- 被动读日志得到的延迟是近似值，非真实 TTFT；更高精度的方案（如装 statusline hook）作为 Phase 2 可选增强，而非 MVP 强制要求。
