# Tokcat

**本地优先的 macOS 菜单栏宠物**：靠你使用 AI coding agent 产生的 token 用量喂养、成长、掉落装备。  
默认离线，不联网、不上传任何数据。

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black.svg)](#环境要求)

---

## 它是什么

Tokcat 住在菜单栏里，也可以在桌面悬浮。你写代码、跑 Claude Code / Codex / Cursor 等工具时，它会从**本机 agent 日志**读到 token 用量，用来：

- 涨经验、升级、改三围（聪明 / 稳定 / 手感）
- 改变心情与饱食，驱动像素猫表情与动作
- 掉落皮肤、装备、道具；可装备、可图鉴收集
- 在主界面看用量统计（日 / 周 / 月）、费率与设置

> 名字里的 token = 模型用量；猫 = 桌面陪伴。全部计算与存储都在本机完成。

---

## 功能一览

### 菜单栏
- 自绘 Tokcat 猫头（template），随 **空闲 / 工作中 / 完成** 切换表情与浮标（zzz / 蒸汽·灯泡 / OK）
- 可选旁显示：CPU、GPU、内存、网速、温度压力、token 速率
- 紧凑下拉面板：系统条、宠物状态横排、Agent 摘要、最近 2 条事件、快捷操作

### 桌面宠物
- **默认像素 Tokcat**：事件驱动动画（吃、升级、互动、工作、困、饿…）
- 也支持：方块猫 / 粉猫（CC0）/ 自定义 USDZ
- 可拖动位置（记忆）、点击互动；装备可叠帽子等外观
- 音效默认关闭（设置里可开）

### 主界面（左侧导航）
| 页 | 内容 |
|----|------|
| **统计** | 日 / 周 / 月 token 与费用趋势；按中转站 / 模型 / Agent 分组 |
| **宠物** | 角色卡：等级、序列称号、三围、途径、目标、喂养与证印 |
| **背包** | 人偶装备栏 + 物品格 + 检视；掉落规则与加成 |
| **图鉴** | 皮肤 / 装备 / 道具收集进度；可启用已拥有外观 |
| **设置** | 菜单栏、监控、Agent、费率、宠物、通用 |

### 养成与「令牌密契」
- 营养分层喂属性；拉长成长曲线 + 日 XP 软上限
- **明文主显 + 密契副文案**（新人只看等级与俗名也能玩）
- 三途径（聪明 / 稳定 / 手感）门控与称号
- 掉落 / 保底 / 装备权能（需求不满足时外观可在、权能休眠）

### 多 Agent 适配（本地日志）
开箱可读本机日志，无需 hook 上云，例如：

Claude Code · Codex CLI · Cursor · Gemini CLI · OpenClaw · WorkBuddy · Kimi · CC Switch 代理归因 等  

新适配器默认从文件**末尾**跟踪，避免一次灌入海量历史。

### 隐私
- **零网络请求**（应用本身不访问互联网）
- 只读本机日志与进程/系统指标
- 数据：`~/Library/Application Support/TokenCat/tokencat.sqlite3`  
  卸载 App 不会自动删库；可手动删除该目录

---

## 环境要求

- macOS 13 Ventura 或更高
- 开发构建：Xcode 15+ / Swift 5.10+

---

## 安装（普通用户）

从 [GitHub Releases](https://github.com/SelinLee/tokcat/releases) 下载最新 `Tokcat-*-macos.zip`：

1. 解压得到 `Tokcat.app`
2. 拖到「应用程序」
3. **首次启动**：右键 App → **打开**（当前为 ad-hoc 签名，需绕过 Gatekeeper 一次）
4. 菜单栏出现猫头后，点图标可开主界面 / 设置

### 要不要做 DMG？

| 格式 | 体验 | 说明 |
|------|------|------|
| **Zip（当前）** | 解压 → 拖到应用程序 | 小、简单、GitHub Release 友好 |
| **DMG** | 打开磁盘映像 → 拖到 Applications | 更「安装器」感，体积与步骤多一步 |

在 **未做 Apple Developer ID 签名 + 公证** 的前提下：

- DMG **不会**比 Zip 更容易过 Gatekeeper  
- 用户仍要「右键 → 打开」一次  
- 因此默认继续提供 **Zip**；有公证后再上 DMG 更有意义  

本地打包：

```bash
TOKCAT_VERSION=0.3.0 scripts/package_app.sh
# 产物（不入库）：dist/Tokcat.app 与 dist/Tokcat-0.3.0-macos.zip
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

也可用 Xcode 打开 `Package.swift` 调试。

---

## 架构（简图）

```text
本机 Agent 日志 / 系统指标
        │
        ▼
  TokcatKit 适配器 + 经济 + PetEngine + Loot
        │
        ├─ SQLite（本机）
        │
        ▼
  菜单栏 · 悬浮像素宠物 · 主界面（统计/宠物/背包/图鉴/设置）
```

| 路径 | 职责 |
|------|------|
| `App/` | SwiftUI 菜单栏、主窗、悬浮宠物 |
| `App/PixelPet/` | 像素动画状态机与叠加渲染 |
| `App/Pet3D/` | 可选 3D / USDZ 皮肤 |
| `Sources/TokcatKit/` | 适配器、成长、掉落、统计、SQLite |
| `docs/` | 像素路线图、令牌密契设定与计划 |

设计备忘：[`docs/PixelPetRoadmap.md`](docs/PixelPetRoadmap.md) · [`docs/TokenCompactLore.md`](docs/TokenCompactLore.md) · [`docs/TokenCompactPlan.md`](docs/TokenCompactPlan.md)

---

## 路线图（摘要）

- [x] 菜单栏宠物 + 本地 token 喂养 + SQLite  
- [x] 多 Agent 适配与费率  
- [x] 像素 Tokcat、掉落 / 背包 / 装备 / 图鉴  
- [x] 主界面统计看板与性能优化（异步统计、图鉴滚动等）  
- [ ] 节日内容与打磨  
- [ ] Developer ID 签名 / 公证（可选 DMG）  

---

## 贡献

欢迎 Issue / PR。请勿提交：

- `dist/`、`.build/`、本地 `.sqlite` / 个人日志  
- 含 API Key、账号路径、私人 usage 导出的文件  

---

## 许可

[MIT](LICENSE)

粉猫等第三方资源见对应 `ATTRIBUTION.md` / 模型 README。
