# Tokcat

**在 macOS 菜单栏实时监控多种 AI coding agent 的 token 用量与费用，并提供本地统计。**  
附带一只用这些用量喂养的桌面像素宠物。默认离线，不联网、不上传。

[English](README.md) | [中文](README.zh-CN.md)

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black.svg)](#环境要求)
[![Release](https://img.shields.io/github/v/release/SelinLee/tokcat)](https://github.com/SelinLee/tokcat/releases)

---

## 核心能力：多 Agent 用量与费用

Tokcat 轮询读取**本机 agent 日志**（无需 cloud hook、无需 API Key 上报），统一为 token 事件后：

| 能力 | 说明 |
|------|------|
| **实时速率** | 菜单栏 / 面板显示 tok/s、费用速率（如 `$/m`） |
| **今日与累计** | 今日 token、今日费用、累计费用 |
| **模型与来源** | 当前模型、Agent 来源、可选中转站 / provider 归因 |
| **统计看板** | 日 / 周 / 月趋势；按 **Agent / 模型 / 中转站** 分组；Tokens ↔ 费用切换 |
| **本地费率** | 可编辑定价表；支持上报实价与估算价混合展示 |
| **最近事件** | 菜单栏紧凑展示最近用量事件 |

### 已支持的 Agent / 来源

| 来源 | 说明 |
|------|------|
| **Claude Code** | 本机 JSONL 会话日志 |
| **Codex CLI** | rollout / 历史日志 |
| **Cursor** | 本机相关用量记录 |
| **Gemini CLI** | 本机 CLI 日志 |
| **OpenClaw** | trajectory 等本地轨迹 |
| **WorkBuddy** | 本机 traces |
| **Kimi** | wire.jsonl 等本地日志 |
| **CC Switch** | 代理请求日志，用于 **provider / 中转站归因与实价** |

设置里可开关各适配器。新适配器默认从文件**末尾**跟踪，避免首次启动灌入海量历史。

> 宠物养成是「用量可视化」的可选壳层：token 进来 → 统计落库 → 同时喂养桌面猫。  
> **即使不使用宠物，统计与费用监控也可单独使用。**

---

## 一分钟体验

1. 安装并打开 Tokcat（菜单栏出现猫头）  
2. 正常使用 Claude Code / Codex / Cursor 等  
3. 菜单栏可看 **tok/s · 费用速率**；点开面板查看今日用量  
4. 主界面 → **统计**：日 / 周 / 月曲线与明细  

数据仅写入本机 SQLite：`~/Library/Application Support/TokenCat/tokencat.sqlite3`

---

## 功能一览

### 1. 实时监控（菜单栏）
- 自绘 Tokcat 图标；随 **空闲 / 工作中 / 完成** 切换表情（与 agent 吞吐联动）
- 可选旁路指标：CPU、GPU、内存、网速、温度压力、**Token 速率**
- 下拉：Agent 摘要（模型、速度、今日、累计费用）、最近事件、系统条

### 2. 统计与费率（主界面）
- **统计**：日 / 周 / 月；分组 = 中转站 / 模型 / Agent；Tokens 或费用  
- 异步聚合 + 缓存，切换周期不阻塞主线程  
- **设置 → 费率**：维护模型单价；可与 CC Switch 上报价配合  

### 3. 桌面宠物（可选）
- 默认 **像素 Tokcat**（吃 / 升级 / 工作 / 困 / 饿…）
- 也可用方块猫 / 粉猫 / 自定义 USDZ  
- 用量驱动成长：等级、聪明 / 稳定 / 手感、掉落装备与图鉴  
- 音效默认关闭  

### 4. 主界面导航
统计 · 宠物 · 背包 · 图鉴 · 设置（左侧栏）

### 5. 隐私
- **应用本身不做网络请求**  
- 只读本机日志与系统指标  
- 无账号、无云同步、无 usage 上传  

---

## 环境要求

- macOS 13 Ventura 或更高  
- 开发构建：Xcode 15+ / Swift 5.10+  

---

## 安装

从 [GitHub Releases](https://github.com/SelinLee/tokcat/releases) 下载 `Tokcat-*-macos.zip`：

1. 解压得到 `Tokcat.app`  
2. 拖到「应用程序」  
3. **首次启动**：右键 → **打开**（ad-hoc 签名，需绕过 Gatekeeper 一次）  

本地打包：

```bash
TOKCAT_VERSION=0.3.0 scripts/package_app.sh
# 产物在 dist/（不入库）：Tokcat.app 与 Tokcat-0.3.0-macos.zip
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
  Adapters → TokenEvent（token、费用、模型、provider）
        │
        ├─ Throughput / 今日累计 / 菜单栏实时
        ├─ UsageStats（日周月 · Agent/模型/中转站）
        ├─ SQLite 持久化
        └─ PetEngine / Loot（可选养成）
```

| 路径 | 职责 |
|------|------|
| `Sources/TokcatKit/Adapters/` | 各 Agent 日志解析与 provider 归因 |
| `Sources/TokcatKit/Economy/` | 定价、营养分层、**UsageStats 看板** |
| `Sources/TokcatKit/Persistence/` | 本地 SQLite |
| `App/` | 菜单栏、统计主窗、悬浮宠物 |
| `App/PixelPet/` | 像素动画 |
| `docs/` | 像素与养成设定（次要） |

---

## 路线图（摘要）

- [x] 多 Agent 本地日志适配 + 实时 tok/s / 费用  
- [x] 日周月统计看板（Agent / 模型 / 中转站）  
- [x] 菜单栏指标与主界面  
- [x] 像素宠物 / 掉落 / 背包 / 图鉴  
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
