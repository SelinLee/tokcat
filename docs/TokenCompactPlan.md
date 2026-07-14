# 令牌密契 · 开发计划（Token Compact Plan）

> 将宠物成长从「偏高数值 + 幼/成/老猫」重置为 **拉长成长线 + 三途径分支 + 装备权能 + 双层文案**。  
> **设定与 UX 规范**：[`TokenCompactLore.md`](./TokenCompactLore.md)  
> **像素资源规范**：[`PixelPetArtBible.md`](./PixelPetArtBible.md)  
> **像素路线图**：[`PixelPetRoadmap.md`](./PixelPetRoadmap.md)

---

## 0. 背景与目标

### 现状问题

| 区域 | 现状 | 问题 |
|------|------|------|
| XP | `80+45*L^1.35`，`xpPerToken=1/650`，softcap 420 | 早期日升多级，线太短 |
| 属性 | premium INT 过猛，energy 批次高 | 成就阈值易爆 |
| 模型 | 仅 3 档 nutrition | 扮演差异弱 |
| 装备 | overlay 外观 only | 无门槛、无 build |
| 掉落 | 全池近似开放 | 无等级/途径门控 |
| 叙事 | PetStage 幼/成/老 | 缺 IP，命名劝退风险 |

### 目标

1. **拉长**全局成长（见 Lore §9 节奏）  
2. **三途径**（聪明/稳定/手感）门控内容  
3. **装备**有需求 + 有数值权能 + 帽子上菜单栏  
4. **双层文案**：明文主显，密契副显  
5. **可迁移**：软重置重算等级属性，尽量保留背包  

### 非目标（本计划外）

- 云端同步 / 排行榜  
- 完整序列 0 专属剧情  
- 一次做完全部新像素冠美术（可程序占位 → 后补）

---

## 1. 架构落点

```text
TokenEvent
  → PetEngine (+ GrowthBalance, equipment bonuses)
  → PetState (level/xp/stats 真相源，字段兼容)
  → CompactLore / ManifestTier / PathwayProgress   // 显示与门控
  → LootEngine (池过滤 + 权重表 + 装备加成)
  → Inventory / EquipmentLoadout (+ req & effects)
  → UI: 档案 / 背包 / 菜单栏 / Toast
  → PixelPetOverlayRenderer + MenuBar hat sigil
```

### 建议新增文件

| 路径 | 职责 |
|------|------|
| `Sources/TokcatKit/Lore/CompactCopy.swift` | 明文/密契字符串、品质名、槽位名 |
| `Sources/TokcatKit/Lore/PathwayLore.swift` | 途径、称号表、主途判定、启程条件 |
| `Sources/TokcatKit/Lore/ManifestTier.swift` | 显化阶 / 序列标签 / 阶段色 token |
| `Sources/TokcatKit/Pet/GrowthBalance.swift` | XP/属性/softcap 全部常量 |
| `Sources/TokcatKit/Loot/ItemEffect.swift` | 效果与需求结构、聚合 cap |
| （可选）`Sources/TokcatKit/Economy/ModelProfile.swift` | 模型扮演偏置 |

### 主要改动文件

| 文件 | 改动 |
|------|------|
| `PetEngine.swift` | 读 GrowthBalance；属性降速；装备 XP/softcap 加成 |
| `PetDerivedStatus.swift` | Stage → ManifestTier 映射；喂养 hint 双层文案 |
| `PetAchievement.swift` | 证印阈值与途径成就 |
| `ItemModels.swift` / `ItemCatalog.swift` | 需求、效果、途径、lore 字段 |
| `LootEngine.swift` | 池过滤、权重表、掉落率加成 |
| `AppModel.swift` | 装备校验、迁移触发、bonus 注入 |
| `PetProfileView.swift` / `InventoryView.swift` / `MenuBarContentView.swift` | 双层 UI |
| `MenuBarCatIcon.swift` 等 | 冠徽叠加 |
| `PetStore.swift` | schemaVersion / 迁移标记 |
| `Tests/*` | 曲线、门控、效果 cap、文案锚点 |

### 存储兼容

- **保留** `level`, `xp`, `stats.*`, inventory, equipment 表  
- 新增可选：`balance_version`, `pathway` 缓存字段（可派生则不落库）  
- Item 定义以代码目录为准，不强制 DB 存 effect  

---

## 2. 分期里程碑

### Phase C0 · 文档冻结 ✅（本提交）

- [x] `docs/TokenCompactLore.md`
- [x] `docs/TokenCompactPlan.md`
- [x] README「路线图」链到上述文档

**验收**：产品/设计可只读文档对齐名词与节奏。

---

### Phase C1 · 文案与显示层（Lore UI） ✅

**目的**：先让现有数值「看起来像新体系」，降低术语劝退。

#### 任务

1. [x] 实现 `CompactCopy` / `PathwayLore` / `ManifestTier`
2. [x] `PetStage` 映射到 `ManifestTier`（废弃对外「幼猫/成猫/老猫」文案）
3. [x] 档案页 / 菜单栏 / 升级 toast / 事件时间线：
   - 主显 `Lv.n`
   - 副显序列称号（若有）
   - 属性：聪明/稳定/手感 + 整数；括号或小字智识/存续/闪流
4. [x] 稀有度：色 + 明文「普通…传说」；字母角标
5. [x] 装备槽副标题：帽子/眼镜/…
6. [x] 成就列表标题改为证印风但保留条件数字
7. [x] README / PixelPetRoadmap 增加「令牌密契」指针

#### 验收

- [x] 菜单栏可见 `Lv.n`
- [x] 档案无「老猫」作为主标签
- [x] 物品至少「品质明文 + 色」
- [x] 单元测试：level→manifestTier / sequenceLabel 映射表

#### 风险

- 文案散落：必须集中 Copy 表，禁止 View 内硬编码中文散落新增

---

### Phase C2 · 数值内核重置（GrowthBalance） ✅

**目的**：拉长成长、压属性。

#### 任务

1. [x] `GrowthBalance` 收敛常量（Lore §9）
2. [x] `PetEngine` 全面改用 Balance；删除魔法数
3. [x] 属性 softcap
4. [x] 成就阈值重标
5. [x] **软重置迁移**（推荐默认）：
   - 读 `balance_version < 2`
   - 用 `totalTokensFed`（及可选历史抽样）重算 level/xp/stats
   - 保留 inventory；equipment 保留但进入 C3 再校验效果
   - 写 `balance_version = 2`
6. [x] 档案页可选：「按 v2 规则重算成长」（已迁移则 disabled）
7. [x] 测试：曲线抽点、softcap、迁移幂等

#### 建议迁移算法（可调）

```text
// 简化：按 totalTokensFed * 平均 tier 系数回放 XP
assumedTierMult = 1.0  // 或按历史 events 聚合
totalXP = totalTokensFed * xpPerToken * assumedTierMult
// 再 while 扣 xpToNext 得到 level/xp
// stats：按 totalXP 比例拆分或二次扫描 events（若性能允许）
```

重度用户 level 会下降 → Toast 说明：「成长规则已更新，等级已按新平衡重算；背包保留。」

#### 验收

- [x] 中度模拟：满 softcap 约 2 周到 Lv10 量级（测试或脚本断言区间）
- [x] 属性不再在极短 token 内破旧成就线
- [x] 迁移跑两次结果一致

---

### Phase C3 · 装备需求与权能 ✅

**目的**：装备从外观变成 build 零件。

#### 任务

1. `StatRequirement` + `ItemEffect` 挂到 `ItemDefinition`
2. `ItemCatalog` 填第一批 6–8 件门槛与效果（Lore §6）
3. `EquipmentBonuses.aggregate(loadout) -> ActiveBonuses`（含 cap）
4. `PetEngine.apply` / `LootEngine.evaluate` 注入：
   - xpMultiplier
   - dailyXPSoftCapBonus
   - dropChanceBonus
   - hungerDecayMultiplier（tick）
5. 装备 UI：
   - 需求绿/红
   - 效果明文数字
   - 不满足：可保持外观，`effectsActive == false`
6. `InventoryMutations.equip` 返回失败原因（可选 enum）

#### 验收

- [x] 不满足需求时权能不能生效（测试）
- [x] 多件装备经验加成不超过 +20%
- [x] 档案或背包可见「当前加成汇总」

---

### Phase C4 · 途径门控 + 掉落池 ✅

**目的**：不同线看到不同内容。

#### 任务

1. `PathwayProgress.evaluate(state) -> unlocked pathways & titles`
2. Loot 池过滤：minLevel、pathway 启程、稀有带
3. 等级稀有度权重表
4. `minTokensForFeedRoll` 等 LootConfig v2
5. 启程 toast：`解锁成长线：聪明线` + 密契授衔副行
6. 档案「下一仪式/下一解锁」模块（纯明文条件）

#### 验收

- [x] 未启程聪明线时，聪明专属装备不进掉落池（测试 seed RNG）
- [x] 每日 cap / pity 行为与 v1 兼容可测
- [x] 下一解锁文案含数字条件

---

### Phase C5 · 菜单栏信标帽 + 表现 ✅

**目的**：头饰反馈到菜单栏，途径可辨。

#### 任务

1. `menuBarHatID` → `MenuBarCatIcon` / tokcat 绘制路径叠加  
2. 无 hat 时主途底色/小符文（轻量）  
3. 升级 / 启程角标闪烁（可选）  
4. Pixel overlay 与 hat 资源：程序占位几何 → 后换真像素  
5. 音效 / 飘字文案走 CompactCopy

#### 验收

- [x] 装备冷帽后菜单栏 tokcat 可见差异  
- [x] 非 tokcat 图标风格不崩溃（降级策略）  
- [ ] 截图点检三途径色不冲突

---

### Phase C6 · 模型扮演增强（可选增强） ✅

#### 任务

1. [x] `ModelProfile` 或 PricingEntry 扩展 bias  
2. [x] 延迟 → 手感途径亲和  
3. [x] UI 喂养建议与途径一致（双层文案）

#### 验收

- [x] 同 token 不同 model 导致属性增量可测差异  

---

### Phase C7 · 打磨与内容扩充 ✅（首批）

- 更多器物 / 证印 / 途径称号微调  
- 序列 0 视觉  
- 平衡回访（真实用量一周）  
- 本地化键稳定（若后续 en）  

---

## 3. 实施顺序（推荐）

```text
C0 文档
 → C1 显示层（低风险、立刻改善认知）
 → C2 数值 + 迁移（核心体感）
 → C3 器物权能
 → C4 途径掉落门控
 → C5 菜单栏帽
 → C6 模型偏置
 → C7 内容与打磨
```

**可并行**：C1 文案表与 C2 Balance 常量；C5 美术与 C3/C4 逻辑。

---

## 4. 测试计划

| 层级 | 内容 |
|------|------|
| 单元 | xpToNext 抽点、tier 倍率、属性 softcap、迁移幂等 |
| 单元 | Pathway 启程、标题表、ManifestTier 映射 |
| 单元 | ItemEffect 聚合 cap、需求失败效果关闭 |
| 单元 | Loot 池过滤 + SeededLootRNG 快照 |
| UI 手测 | 档案扫读 10 秒测试；升级/掉落 toast；装备红绿需求 |
| 回归 | 现有 Adapter / Store / Loot 旧测试全绿 |

命令：

```bash
swift test
```

---

## 5. 迁移与发布

### 版本标记

- `PetStore` 或 meta 表：`balance_version = 2`  
- App 版本建议：`0.3.0`（行为变更）或 `0.2.x` + 公告（团队自定）

### 用户沟通（设置 / 首次迁移）

```text
成长平衡已更新
· 升级更慢，长期更有追求
· 等级与属性已按新规则重算
· 背包与已收集物品保留
· 装备将逐步具备效果与佩戴条件
```

### 回滚

- Balance 常量集中，可用 `balance_version` feature flag 切回 v1 曲线（仅应急；UI 文案可不回滚）

---

## 6. 任务拆分清单（开发用）

### C1

- [ ] `CompactCopy.swift` 品质/槽位/属性俗名  
- [ ] `ManifestTier.swift` + 替换对外 PetStage 文案  
- [ ] `PathwayLore.swift` 称号与主途（可先只做显示）  
- [ ] PetProfileView 双层信息架构  
- [ ] MenuBarContentView Lv 主显  
- [ ] InventoryView 品质明文  
- [ ] 事件工厂文案  
- [ ] 测试映射  
- [ ] README 链接  

### C2

- [ ] `GrowthBalance.swift`  
- [ ] PetEngine 接线  
- [ ] 成就阈值  
- [ ] 软重置  
- [ ] 设置项 / 迁移提示  
- [ ] PetEngineTests 更新  

### C3

- [x] Item 模型扩展  
- [x] Catalog 填效果  
- [x] Bonus 聚合  
- [x] Engine 注入  
- [x] UI 需求与汇总  
- [x] 测试 cap / 休眠  

### C4

- [x] 启程状态机  
- [x] Loot 过滤与权重表  
- [x] LootConfig v2  
- [x] 下一解锁 UI  
- [x] 测试池过滤  

### C5

- [x] menuBarHat 绘制  
- [x] 占位像素几何  
- [x] 降级策略  
- [ ] 手测三途径  

### C6+

- [x] ModelProfile  
- [x] 内容扩充（首批器物/证印）  

---

## 7. 依赖关系图

```text
        C0 docs
           │
           ▼
        C1 UI/Lore ──────────────┐
           │                     │
           ▼                     │
        C2 Balance+Migrate       │
           │                     │
           ├──────────► C3 Effects
           │                     │
           └──────────► C4 Gates ◄┘
                         │
                         ▼
                        C5 Hat
                         │
                         ▼
                        C6 Model bias
                         │
                         ▼
                        C7 Polish
```

---

## 8. 成功标准（Release gate）

1. **认知**：新用户不读 lore 也能升级、看属性、辨品质、懂为何不能装备  
2. **节奏**：成长显著长于 v1；日 softcap 下早期不会一天连跳大量级  
3. **差异**：三途径启程后掉落/可装备集合可区分  
4. **装备**：至少 1 件帽子改变菜单栏；至少 3 件有可测数值效果  
5. **稳定**：`swift test` 全绿；迁移不丢 inventory  

---

## 9. 开放决策（已选默认）

| 项 | 默认 | 备选 |
|----|------|------|
| IP 名 | 令牌密契 / Token Compact | — |
| 序列方向 | 副显 9→0；主显 Lv 递增 | 仅 Lv |
| 多途径 | 三线并行 | 单主途锁定 |
| 调性 | 轻奇幻桌宠 | 更黑 |
| 术语模式 | 明文主+密契副，无复杂开关 | 三档浓度 |
| 重置 | 软重置重算 | 硬清档 |
| 门槛失败 | 外观保留、效果休眠 | 强制卸下 |
| 菜单栏帽 | 优先 tokcat 风格 | 全部图标风格 |

变更决策时先改 `TokenCompactLore.md`，再改本计划与代码。

---

## 10. 文档维护

| 文档 | 何时更新 |
|------|----------|
| `TokenCompactLore.md` | 名词、色板、门槛、数值锚点变更 |
| `TokenCompactPlan.md` | 分期完成时勾选；顺序变更时改 §3 |
| `PixelPetRoadmap.md` | C5 美术任务并入像素 phase 时 |
| `README.md` | 对外功能点与路线图链接 |

---



### Balance v3 · 一轮对话基线（2026-07-14）

以真实一轮对话 ≈ 15k–40k tokens 为锚，修正 v2「属性/成就过密」：

| 项 | v2 | v3 |
|----|----|----|
| xpPerToken | 1/1800 | **1/3800** |
| dailyXPSoftCap | 220 | **120** |
| 属性 | 按 event 累加易爆 | **token 尺度 + 单批硬顶** |
| 能量 | 每个 latency 样本累加 | **批内平均一次** |
| 启程 | Lv10 · 属性≥8 | **Lv8 · 属性≥3**（绝对值随尺度下调） |
| 掉落 | 5% / cap4 / min2k | **3% / cap3 / min8k** |
| balance_version | 2 | **3**（启动软重置 level/stats） |

一轮 30k premium 约：XP ~10、聪明 ~0.25（封顶 0.35），**不应**连升多级或点亮一串证印。

## 11. 当前状态

| Phase | 状态 |
|-------|------|
| C0 文档 | **Done**（本文件 + Lore） |
| C1 显示层 | **Done** |
| C2 数值迁移 | **Done** |
| C3 器物权能 | **Done** |
| C4 途径掉落 | **Done** |
| C5 信标帽 | **Done** |
| C6 模型偏置 | **Done** |
| C7 打磨 | **Partial**（器物/证印首批；序列0视觉/平衡回访后续） |

令牌密契主线 C0–C6 已完成；C7 内容与平衡回访可按真实用量继续扩充。
