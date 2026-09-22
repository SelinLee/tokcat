# Tokcat

**菜单栏里的多 Agent AI 任务监控工具：谁还在运行、谁已完成、谁需要你，一眼看清。**

将 **Codex、Claude Code、WorkBuddy 等本地 AI 工具**汇总到一个监控界面。菜单栏用状态点提醒，主界面按时间整理任务，点开即可阅读对话、查看耗时与活动记录；同时保留 Token、费用、系统指标与可选桌面猫咪。

[English](README.md) | [中文](README.zh-CN.md)

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black.svg)](#环境要求)
[![Release](https://img.shields.io/github/v/release/SelinLee/tokcat)](https://github.com/SelinLee/tokcat/releases)

## 菜单栏：一眼看清 AI 任务状态

<p align="center">
  <img src="docs/assets/screenshots/ai-monitor-light.png" alt="浅色模式：菜单栏监控指标、任务状态点与详情面板" width="430" />
  <img src="docs/assets/screenshots/ai-monitor-dark.png" alt="深色模式：菜单栏指标与 AI 任务详情面板" width="430" />
</p>

*浅色与深色原生面板预览，任务均为演示数据。状态点和监控指标可在「设置 → 菜单栏」分别开关。*

任务点放在**已选监控指标后方**。以左侧文字的上下边缘为限均匀排列：每列最多 3 个，第 4 个从右侧新列顶部开始。最多展示 6 个，其余显示 `+N`。

![1 到 7 个任务点的排列示例，包含超出数量提示](docs/assets/screenshots/task-dot-spacing-light.png)

*示例覆盖运行、等待、完成、失败及暂无更新状态，并展示运行黄点呼吸最暗时的效果。*

| 圆点 | 含义 |
|---|---|
| 🟡 黄色呼吸 | 正在运行；呼吸最暗时也保持清晰 |
| 🟢 绿色常亮 | 本轮结束且未读；查看或标为已读后消失 |
| 🟡🔴 黄红交替闪烁 | 等待批准；开启系统“减少动态效果”时显示红色常亮 |
| 🟡 黄色常亮 | 等待输入 |
| 🔴 红色常亮 | 本轮失败 |
| ◯ 灰色空心 | 暂无更新或已中断；安静不等于已完成 |

下拉栏优先显示对话标题，并列出 Agent、项目、状态、耗时及最近活动。Codex 标题读取自本地会话索引，WorkBuddy 使用本地数据库标题；没有标题时回退显示项目名。切回已识别的 Codex、WorkBuddy / WorkBuddy AI、Claude 桌面应用并停留至少 1.5 秒，会按 Agent 清除进入应用前已完成的绿点。普通终端无法区分其中的 Agent，仍可手动标为已读；已读状态重启后保留。

任务点与 CPU / GPU / 内存 / 网速 / Token / 费用指标可分别开关；任务点排在已选指标后面，两者可以同时显示。可选系统通知用于提醒任务结束或等待操作，启动时不重放历史通知。本机有 Codex 登录信息时，还可显示 5 小时与周窗口的剩余额度和重置时间。

## 不用来回切窗口，也知道 AI 的工作状态

| 你关心的 | Tokcat 展示的 |
|---|---|
| 哪些 Agent 还在工作？ | 每个进行中或未读任务一个菜单栏状态点，与已有监控指标并排显示 |
| 回复完成了吗？ | 绿点提醒，手动已读或回到对应桌面 Agent 后清除 |
| 有没有任务正在等我？ | 数据源明确报告的输入 / 授权等待状态，以及累计等待时间 |
| 最近在各工具里做了什么？ | 跨工具任务按最后活动时间排列，支持来源、时间范围、关键词筛选 |
| AI 具体说了什么？ | 大面积对话详情，支持复制、刷新、跟随最新消息 |
| 一个任务经历了什么？ | 耗时、可观测的工具调用、可用的 Token 数、模型与活动时间线 |
| 花了多少 Token 和钱？ | 实时速率及日 / 周 / 月统计，按 Agent、模型、中转站分组 |

## 主界面：左侧找任务，右侧读对话、看监控

默认打开**任务总览**，收窄导航与任务列表，将大部分空间留给选中任务的详情。

![多 Agent 任务总览与对话详情](docs/assets/screenshots/task-dashboard-light.png)

- **实时任务**：当前状态、项目、耗时、等待时间与最近活动。
- **最近任务**：汇总不同 Agent 的记录，按时间排序；按工具、24 小时 / 7 天 / 30 天、关键词筛选。同一 Codex 会话的不同轮次独立留存。
- **对话**：直接阅读 Codex、Claude Code、WorkBuddy 的用户提问与 AI 回复，支持选择复制、自动刷新、跟随最新消息和独立阅读窗口。
- **监控详情**：本轮耗时、等待时间、可观测的工具调用数、模型、可用的本轮 Token 与活动时间线；可打开项目文件夹、定位源记录，或跳转回有效的 Codex 会话。

![深色任务总览与对话详情](docs/assets/screenshots/task-dashboard-dark.png)

### 任务监控详情

<p align="center">
  <img src="docs/assets/screenshots/task-monitor-light.png" alt="任务监控详情：耗时、等待时间、工具调用、会话信息与活动时间线" width="650" />
</p>


*任务截图均使用演示数据，不包含私人对话。*

## Agent 接入能力

任务状态、历史记录、对话阅读和用量统计是不同能力，界面只展示数据源实际提供的信息。

| 来源 | 任务状态 | 最近任务 | 对话阅读 | Token / 费用 |
|---|---|---|---|---|
| **Codex** | 本地生命周期事件 | 支持，按轮次 | 支持 | 支持 |
| **Claude Code** | 可选本地事件接入 | 支持 | 支持 | 支持 |
| **WorkBuddy** | 本地数据库明确状态 | 支持，按会话 | 支持 | 支持 |
| **DeepSeek Harness** | 仅活动记录 | 支持 | — | 支持 |
| **OpenClaw** | 仅活动记录 | 支持 | — | 支持 |
| **Kimi** | 仅活动记录 | 支持 | — | 支持 |
| **Cursor / Gemini CLI** | — | — | — | 本机有数据时显示 |
| **CC Switch** | — | — | — | 中转站归因、上报费用与倍率 |

Codex 自动读取本地 rollout 事件。Claude Code 需在**设置 → Agent**启用本地状态接入，再重启 Claude Code 会话；接入会备份、合并现有 hook 设置，移动 Tokcat 后需重新启用。WorkBuddy 只读 `~/.workbuddy/workbuddy.db` 并关联本地对话日志；只要数据库仍明确报告工作中，就不会仅因暂时没有新消息而变成空心点。

**日志安静不等于完成，本轮结束不等于项目完成或测试通过。** WorkBuddy 不推测每轮起点；仅有活动记录的来源不冒充实时任务状态。缺失的指标显示为未提供，没有明确步骤数据时不显示推测的进度百分比。

## Token 与费用统计

![用量统计看板](docs/assets/screenshots/stats-dashboard.png)

- 实时 Token / 费用速率、今日用量与累计费用。
- 日 / 周 / 月趋势，按 **Agent、模型、中转站 / Provider** 分组。
- 可编辑本地费率，支持结合 CC Switch 上报的实际费用。
- 可选 CPU、GPU、内存、网速与温度压力，与 AI 任务状态一起查看。

## 60 秒上手

1. 安装并打开 Tokcat，菜单栏出现图标。
2. 正常使用 Codex 或 WorkBuddy；Claude Code 任务状态需在**设置 → Agent**启用本地接入。
3. 在已有监控指标旁查看任务点，点击展开简要状态。
4. 打开**任务总览**阅读对话、查看实时与最近任务；在**统计**页查看 Token 和费用趋势。

## 本地数据与隐私

任务监控读取本机日志、明确的生命周期事件和本地状态数据库，不需要账号或云同步，不上传用量与对话。**可选的 Codex 额度显示**会使用本机 Codex 登录信息请求 ChatGPT 用量接口，可在设置中关闭。

- 任务元数据与已读状态保存在 `~/Library/Application Support/TokenCat/agent-sessions.json` 和 `agent-task-history.json`。
- 最多保留 **30 天 / 500 条**任务；首次扫描最近 7 天修改过的日志，读取量有限，不保证回填全部历史轮次。
- 对话按需读取整个关联会话，最多读取末尾 **4 MB / 最近 200 条消息**，截断时明确提示。正文只在视图内存中，不写入任务存档；附件显示占位，不展示系统消息、工具内部数据与推理记录。
- Claude hook 在本地 `session-inbox/` 写入经过筛选的生命周期信息，不保存对话正文或工具参数。
- 用量统计写入本机 `tokencat.sqlite3`；用量适配器从已有文件末尾开始跟踪，避免回填大量历史。

## 可选桌面猫咪

<p align="center">
  <img src="docs/assets/screenshots/tokcat-states-row.png?v=5" alt="可选桌面猫咪：空闲、工作、饥饿、开心、招手、休息" width="720" />
</p>

猫咪随活动改变状态、随用量成长，提供装备、背包与图鉴。关闭桌宠也能完整使用监控和统计；音效默认关闭。

---

## 环境要求

- macOS 13 Ventura 或更高  
- 开发构建：Xcode 15+ / Swift 5.10+  

---

## 安装

从 [GitHub Releases](https://github.com/SelinLee/tokcat/releases) 下载安装包：

### 推荐：DMG
1. 打开 `Tokcat-*-macos.dmg`  
2. 将 `Tokcat.app` 拖到「应用程序」  
3. **首次启动**：右键 → **打开**（ad-hoc 签名，需绕过 Gatekeeper 一次）  

### 备选：Zip
1. 下载 `Tokcat-*-macos.zip` 并解压得到 `Tokcat.app`  
2. 拖到「应用程序」  
3. 同样：右键 → **打开**  

本地打包：

```bash
TOKCAT_VERSION=0.5.0 scripts/package_app.sh
# 产物在 dist/（不入库）：
#   Tokcat.app
#   Tokcat-0.5.0-macos.zip
#   Tokcat-0.5.0-macos.dmg
#   Tokcat-0.5.0-macos.sha256
#   INSTALL.txt
```

---

## 从源码运行

```bash
git clone https://github.com/SelinLee/tokcat.git
cd tokcat
swift build
swift test
swift run TokcatApp
```

---

## 架构

```text
Claude Code / Codex / Cursor / Gemini / OpenClaw / WorkBuddy / Kimi / CC Switch
        │  本机日志（只读）
        ▼
  ├─ AgentSessionMonitor → task state / history / conversations
  └─ Adapters → TokenEvent（token、费用、模型、provider）
        │
        ├─ Throughput / 今日累计 / 菜单栏实时
        ├─ UsageStats（日周月 · Agent/模型/中转站）
        ├─ SQLite 持久化
        └─ PetEngine / Loot（可选养成）
```

| 路径 | 职责 |
|------|------|
| `Sources/TokcatKit/Monitor/` | Agent 生命周期、任务历史、对话读取与可选额度 |
| `Sources/TokcatKit/Adapters/` | 各 Agent 日志解析与 provider 归因 |
| `Sources/TokcatKit/Economy/` | 定价、营养分层、**UsageStats 看板** |
| `Sources/TokcatKit/Persistence/` | 本地 SQLite |
| `App/` | 菜单栏、统计主窗、悬浮宠物 |
| `App/PixelPet/` | 像素动画 |
| `docs/assets/screenshots/` | 本 README 使用的产品截图 |
| `docs/` | 像素与养成设定（次要） |

---

## 路线图（摘要）

- [x] 多 Agent 任务监控、菜单栏状态点、对话详情与 WorkBuddy 状态接入
- [x] 多 Agent 本地日志适配 + 实时 tok/s / 费用  
- [x] 日周月统计看板（Agent / 模型 / 中转站）  
- [x] 菜单栏指标与主界面  
- [x] 像素宠物 / 掉落 / 背包 / 图鉴  
- [x] DMG + Zip 发布打包  
- [ ] 更多 agent / 日志格式  
- [ ] Developer ID 签名与公证  

---

## 贡献

欢迎 Issue / PR。请勿提交：

- `dist/`、`.build/`、本地 `*.sqlite` / 个人日志  
- API Key、账号路径、私人 usage 导出  

---

## 许可

[MIT](LICENSE)

第三方模型资源见对应 `ATTRIBUTION.md` / 模型 README。
