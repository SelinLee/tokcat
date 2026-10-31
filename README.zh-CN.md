<div align="center">

# tokcat

**多 Agent 同时开工，一眼看清谁在运行、谁在等你。**

原生 macOS 多 Agent 状态监控：实时任务、等待提醒、本地对话、用量趋势，以及安静贴在桌边的人形挂件。

新增快捷运行框：应用搜索、实时计算、终端命令和网站搜索，一个快捷键唤出。

[English](README.md) · [简体中文](README.zh-CN.md)

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black.svg)](#安装) [![Swift](https://img.shields.io/badge/Swift-native-F05138.svg)](#从源码运行) [![MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**[下载应用](https://github.com/SelinLee/tokcat/releases)** · [快捷运行框](#快捷运行框) · [支持的 Agent](#支持的-agent) · [快速开始](#快速开始)

</div>

## 快捷运行框

> **0.7.10 新增**：[下载 macOS 新版](https://github.com/SelinLee/tokcat/releases/latest)。

按 **Control + 空格** 唤出一条圆角输入框，开始输入后才展开匹配或结果；回车提交后立即收起。也可以点击菜单栏的放大镜打开。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-launcher-input-dark.png" />
  <img src="docs/assets/screenshots/readme-launcher-input-light.png" alt="初始只显示一条圆角输入框的 tokcat 运行框" width="640" />
</picture>

| 输入示例 | 功能 | 按回车 |
|---|---|---|
| `Chrome` | 中英文名称、拼音、缩写匹配应用 | 打开选中的应用 |
| `sqrt(9)+2^3` | 实时显示结果 `11` | 复制结果 |
| `> pwd` | 终端命令 | 打开终端并执行 |
| `baidu 人工智能` | 百度搜索；也支持 `google`、`bing` | 在默认浏览器搜索 |
| `example.com` | 识别域名或完整 HTTP(S) 网址 | 打开网站 |
| `setup` | 设置入口 | 打开 tokcat 设置 |
| `empty` | 预设清空废纸篓命令，关键词可修改 | 确认后清空 |
| `gg` | 预设退出其他应用命令，关键词可修改 | 默认确认后请求退出 |

- **历史直接填回输入框**：最多保存 50 条本机记录。空白时按 **↑** 调出历史，再用 **↑ / ↓** 切换；文字随即显示在输入框中，可以继续编辑或回车重用。
- **窗口记住位置**：拖动背景或左侧图标移动，重新唤出或重启后恢复；换屏后自动移回可见区域。
- **先列表，再详情**：「**设置 → 命令**」和「**设置 → 网站**」只列出名称、关键词和启用状态，点击条目才打开详细设置。新增或编辑后点“保存”生效，“取消”保留原配置。
- **快捷键可录入**：在「**设置 → 通用 → 应用启动器**」修改组合键或关闭全局快捷键；快捷键被占用时显示提示。

<details>
<summary>查看计算器、网站搜索和设置界面</summary>

**实时计算**支持括号、四则运算、`^` / `**` 幂运算、后缀百分号（`200*10%`）、科学计数法及 `pi` / `π`、`e` 常量。常用函数包括 `sqrt`、`abs`、`pow`、`min`、`max`、`round`、`floor`、`ceil`、`exp`、`ln`、`log` / `log10`、`log2`、`sin` / `cos` / `tan`（弧度）。也可用 `=` 开头明确进入计算模式；算式未完成、除零或参数不适用时会显示提示。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-launcher-calculator-dark.png" />
  <img src="docs/assets/screenshots/readme-launcher-calculator-light.png" alt="输入 sqrt(9)+2^3 后实时显示结果 11，回车复制" width="640" />
</picture>

**网站关键词**既可直达网站，也可搜索。搜索地址用 `{query}` 表示内容，例如 `https://www.baidu.com/s?wd={query}`；搜索词会作为文本编码。预设 `github` 可直接打开 GitHub。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-launcher-search-dark.png" />
  <img src="docs/assets/screenshots/readme-launcher-search-light.png" alt="输入 baidu 人工智能后显示百度搜索入口" width="640" />
</picture>

**自定义命令**支持终端命令、清空废纸篓和退出其他应用。清空废纸篓前会再次确认；退出应用时保留 tokcat 和访达，由各应用提示保存未完成内容。首次操作终端或访达时，macOS 可能询问自动化权限。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-launcher-websites-dark.png" />
  <img src="docs/assets/screenshots/readme-launcher-websites-light.png" alt="网站设置采用名称、关键词与开关组成的紧凑列表，点击条目进入详情" width="900" />
</picture>

</details>

## 安静贴在桌边的人形挂件

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-avatars-dark.png" />
  <img src="docs/assets/screenshots/readme-avatars-light.png" alt="可手动选择的 toki 男生形象与 biti 三套服装，均为平静表情" width="1040" />
</picture>

新桌宠始终吸附在屏幕边缘、右下角或 Dock 两侧。拖动只沿选定边缘微调位置。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-companion-dark.png" />
  <img src="docs/assets/screenshots/readme-companion-light.png" alt="贴边桌宠的窄幅透明滚动动态、等待回答气泡和点击展开详情" width="1040" />
</picture>

- **平时保持安静**：没有常驻气泡。最近工具调用与阶段信息在人物上方逐行向上滚动，透明背景，宽度随人物。
- **需要时展开详情**：点击人物，或 Agent 等待回答／授权时，气泡在人物上方展开；点击气泡打开任务总览。
- **手动选择形象**：男生 **toki**，或 **biti** 的珊瑚、蓝鲸、紫星三套服装。统一使用平静、无笑容表情；动态文字的模型颜色独立于人物选择。

在「设置 → 桌边挂件」或人物右键菜单选择形象和吸附位置。在该设置页的「头顶信息」可切换为常驻模式：任务名称最多两行，超出部分以省略号结尾，tok/s 在下方单独一行；多个任务纵向排列。[桌宠行为说明](docs/DesktopCompanion.md)

## 在一个窗口里跟进多个 Agent

谁正在运行，谁需要回答，谁已经完成本轮回复，统一放在任务列表中。选中任务后，窗口的大部分空间用于阅读对话。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-tasks-dark.png" />
  <img src="docs/assets/screenshots/readme-tasks-light.png" alt="多 Agent 任务总览：实时任务与选中的本地对话" width="1180" />
</picture>

- **实时任务**：运行、等待回答、等待授权、本轮完成、失败与中断。
- **最近工作**：按 Agent、关键词和 24 小时／7 天／30 天筛选；Codex 按轮次保留任务记录。
- **本地对话**：阅读提问和回复，选择复制、跟随新消息，或打开独立阅读窗口。

## 看一眼菜单栏，就知道任务状态

每个任务对应一个状态点，排在你选择的监控指标后面。在其他应用中工作时，也能关注多个 Agent。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-menubar-dark.png" />
  <img src="docs/assets/screenshots/readme-menubar-light.png" alt="菜单栏中的任务状态点、token 速度、费用速度、系统指标与 Codex 额度" width="1040" />
</picture>

| 状态点 | 含义 |
|---|---|
| 黄色呼吸 | 运行中 |
| 黄色／红色交替 | 需要你回答或授权 |
| 绿色 | 本轮完成；后台完成保留至查看 |
| 红色实心 | 失败 |
| 红色空心 | 运行中的任务超过 2 分钟无新活动；保持显示，新活动到达后恢复 |
| 灰色空心 | 状态未知或已中断，可打开详情查看 |

最多显示六个状态点，其余显示 `+N`。前台完成提示闪烁三秒后自动消失；系统开启「减少动态效果」时使用静态颜色。CPU、GPU、内存、网络、token 速度、费用速度和本地 Codex 额度均可选择显示。

## 点击后，查看具体上下文

下拉面板优先展示对话标题，再显示 Agent、当前状态、耗时与等待时间。运行时间下方显示该会话最近 60 秒的输出 tok/s 估算（包含推理输出，不含输入和缓存；数据不足显示 `—`）。30 秒无新活动时显示持续时长，2 分钟后显示红色「长时间无活动」提示；这不等于任务失败，执行长工具或等待网络也可能触发。可以展开任务、打开对话或项目、将完成标为已读，或进入主窗口。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-dropdown-dark.png" />
  <img src="docs/assets/screenshots/readme-dropdown-light.png" alt="展示任务标题、来源、状态和等待时间的多 Agent 下拉面板" width="430" />
</picture>

## 查看每项任务的监控详情

在「监控详情」中查看耗时、等待时间、当前阶段、观察到的工具调用、模型、可获取的本轮 tokens，以及活动时间线。也可以直接打开原始对话、项目文件夹或本地记录。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-monitor-dark.png" />
  <img src="docs/assets/screenshots/readme-monitor-light.png" alt="任务监控详情中的耗时、等待、工具调用、模型与活动时间线" width="600" />
</picture>

## 对比用量与费用

按日、周、月查看趋势，并按 **Agent、模型或中转站** 分组。展示输入／输出 tokens、费用、计费费率和各组占比；上报费用与费率估算分别标注，费率可以本地修改。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-usage-dark.png" />
  <img src="docs/assets/screenshots/readme-usage-light.png" alt="五种 Agent 的每周 token 趋势与用量明细" width="1180" />
</picture>

<details>
<summary>查看费用视图</summary>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-costs-dark.png" />
  <img src="docs/assets/screenshots/readme-costs-light.png" alt="按 Agent 展示的费用趋势和上报费用明细" width="1180" />
</picture>

CC Switch 可以补充中转站归属、上报费用和计费倍率。Codex 的五小时／每周剩余额度来自客户端写入的本地日志，仅在桌面客户端运行时显示。

</details>

## 支持的 Agent

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/readme-agents-dark.png" />
  <img src="docs/assets/screenshots/readme-agents-light.png" alt="按完整状态与对话、活动与用量、可选用量适配器分组的 Agent 支持列表" width="1040" />
</picture>

| Agent | 实时任务状态 | 最近任务 | 对话阅读 | 用量／费用 |
|---|---|---|---|---|
| **Codex** | 本地生命周期事件 | 按轮次 | ✓ | ✓ |
| **Claude Code** | 自动读取本机会话注册；可选 hooks | ✓ | ✓ | ✓ |
| **WorkBuddy** | 本地数据库状态 | 按会话 | ✓ | ✓ |
| **WorkBuddy AI** | 本地数据库状态 | 按会话 | ✓ | ✓ |
| **DeepSeek Harness** | 本地会话投影状态 | 按会话 | ✓ | ✓ |
| **OpenClaw** | 仅活动记录 | 活动记录 | — | ✓ |
| **Kimi** | 仅活动记录 | 活动记录 | — | ✓ |
| **Cursor** | — | — | — | 兼容 JSONL 日志，可选 |
| **Gemini CLI** | — | — | — | 兼容 JSONL 日志，可选 |

**CC Switch** 是计费集成，补充中转站与上报费用，不提供任务生命周期状态。

Claude Code 有本机会话注册时自动识别运行状态；可选 hooks 补充授权等待、失败和明确的本轮结束，空闲不等于完成。DeepSeek Harness 同时覆盖 `dsh web` 与 DSH Desktop，等待提示需要 Harness 的 **timed ask-user** 模式。Cursor 与 Gemini CLI 默认关闭，需有兼容的本地用量记录。[接入方式与数据源](docs/AgentSupport.md)

状态以本地来源提供的信息为准。日志安静不等于完成，本轮结束不等于整个项目完成。缺少的指标保持不可用，不虚构进度百分比。

## 快速开始

1. 安装并打开 tokcat，照常使用各个 Agent。
2. 有本机会话注册的 Claude Code 自动显示；如需详细生命周期事件或使用旧版客户端，在「设置 → Agent」启用 hooks，再重启已有 Claude Code 会话。
3. 选择菜单栏指标，通过状态点关注任务；打开「任务总览」阅读对话，或「用量统计」查看趋势。
4. 在「设置 → 桌边挂件」选择 toki／biti 和吸附位置。

## 安装

需要 **macOS 13+**。从 [Releases](https://github.com/SelinLee/tokcat/releases) 下载 DMG 或 ZIP，将 `tokcat.app` 放进 Applications。首次打开时右键选择「打开」。当前采用 ad-hoc 签名，尚未进行 Developer ID 公证；0.7.10 安装包为 Apple Silicon 与 Intel Mac 通用构建。

监控仅读取本地记录，无需 API key。用量数据库位于 `~/Library/Application Support/Tokcat/`，任务缓存及可选 Claude hooks 位于 `~/Library/Application Support/TokenCat/`。桌宠与任务监控共用状态来源，升级保留用量历史和监控设置。

## 从源码运行

```sh
git clone https://github.com/SelinLee/tokcat.git
cd tokcat
swift build
swift test
swift run TokcatApp
```

使用 `bash scripts/package_app.sh` 打包发行文件，产物放在 `dist/`。

| 目录 | 用途 |
|---|---|
| `App/` | 菜单栏、任务与对话、用量统计和设置 |
| `App/Companion/` | 透明挂件窗口、气泡、滚动动态和吸附 |
| `Sources/TokcatKit/` | 本地适配器、任务生命周期与历史、定价、用量持久化 |
| `Tests/` | 监控、适配器、用量、设置与桌宠回归检查 |
| `scripts/docs_screenshots/` | 可重复生成的原生功能展示图 |

监控配图使用原生视图、示例数据及展示用英文文案，运行框截图保留当前中文界面；不含私人对话，也不代表应用已完整英语本地化。浅色／深色配图跟随 GitHub 主题。[监控配图生成说明](scripts/docs_screenshots/README.md)

[MIT](LICENSE)。桌宠交互参考 [DeepSeek Balance Whale Widget](https://github.com/MeteorNOX/DeepSeek-Balance-Whale-Widget)，toki／biti 图集沿用项目的人物参考。
