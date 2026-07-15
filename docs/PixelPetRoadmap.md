# Pixel Tokcat Roadmap

> 将桌面宠物从 3D 主路径演进为 **原创像素风 Tokcat**：事件驱动动画、阶段外观变化、后续皮肤/道具/装备与可控掉落。

## 产品定位

- **本地优先**：成长、背包、掉落均本地；默认离线。
- **Token 养成**：继续用 AI coding agent 用量喂养（复用 `PetEngine` / 营养分层 / mood）。
- **像素表现**：原创像素猫（参考「可爱桌面猫」气质，**非** Claude 形象复刻）。
- **事件演出**：喂食 / 工作 / 升级 / 互动等映射明确动作。
- **收集扩展**：皮肤、道具、装备 + 可控概率掉落（Phase 3–4 已落地）。

## 与现状关系

| 模块 | 策略 |
|------|------|
| `PetEngine` / `PetState` | 保留为成长真相源 |
| `PetDerivedStatus` / `PetStage` | 映射到像素持续态与体型阶段 |
| `PetApplyResult` 脉冲 | 继续驱动一次性演出（feed / level / interact） |
| `App/Pet3D/*` | 兼容保留（方块猫 / 粉猫 / 自定义 USDZ） |
| `Resources/Sprites` | 像素主资源落地 |
| `DesktopPetSkin` | 新增 `pixelTokcat`，并作为新安装默认 |

## 架构

```
Token 事件
  → PetEngine（XP / level / stats / hunger / mood）
  → PetDerivedStatus + 脉冲事件（feed / levelUp / interact）
  → PixelPetAnimator（优先级状态机）
  → PixelPetView（最近邻缩放帧动画）

已落地：
  PetTimelineEvent → LootEngine → Inventory / Equipment → PixelPetOverlayRenderer
```

### 动画优先级

一次性动作优先于持续态，播完回落：

1. `levelUp`
2. `jump`（庆祝弹跳）
3. `eating`（喂食）
4. `interact` / `wave`（点击 / 招呼）
5. 持续态：`working` / `review` / `waiting` / `failed` / `hungry` / `sleepy` / `sad` / `happy` / `idle`

### 目标数据模型（Phase 2–4 已落地）

```swift
enum PetEvent {
    case fed(tokens: Int, tier: NutritionTier)
    case levelUp(from: Int, to: Int)
    case achievement(id: String)
    case working(speed: Double)
    case idle
    case hungry
    case clicked
    case lootDropped(itemID: String, rarity: Rarity)
    case equipped(itemID: String)
}

enum ItemKind { case skin, prop, equipment }
enum Rarity { case common, uncommon, rare, epic, legendary }
enum EquipSlot { case head, face, back, held, aura }

struct ItemDefinition { /* id, kind, rarity, overlay, slot… */ }
struct InventoryItem { /* itemID, quantity, obtainedAt, source */ }
struct EquipmentLoadout { /* slot → itemID */ }

struct LootTable {
    // trigger, baseChance, pity, rarityWeights, modifiers, dailyCap
}
```

## 里程碑

### Phase 0 · 规范（文档）

- [x] `docs/PixelPetRoadmap.md`
- [x] `docs/PixelPetArtBible.md`
- 角色：原创像素 Tokcat，token 印记，有限色板，分层预留

### Phase 1 · 像素渲染内核

- [x] `DesktopPetSkin.pixelTokcat`
- [x] `App/PixelPet/*` 帧动画视图 + 状态机
- [x] 内置精灵帧（`App/Resources/Sprites/TokcatPixel`）
- [x] 桌面窗可切换像素 / 3D
- [x] 状态：idle / working / happy / sad / sleepy / hungry + feed / levelUp / interact

**验收**

- 设置可选「像素 Tokcat」
- 悬浮窗显示像素猫并循环 idle
- 工作 / 饥饿 / 升级 / 点击有可辨认动作切换

### Phase 2 · 事件总线与演出完善

- [x] `PetApplyResult` 扩展 events（`PetTimelineEvent`）
- [x] 档案页「最近事件」时间线（SQLite 持久化）
- [x] Stage 视觉差异（幼/成/老：色调、体型缩放、小配件）
- [x] 飘字 + 可选音效（系统轻提示音，设置可关）

### Phase 3 · 掉落与库存

- [x] `LootEngine` + 配置表（8% / 首充+15% / 保底 25 / 日 cap 6）
- [x] SQLite：`inventory` / `equipment` / `loot_rolls` + progress meta
- [x] 日 cap、软保底、批次合并（反刷：一喂食批一次 roll）
- [x] 背包 UI、掉落 toast / 时间线 / 装备栏

**建议初值**

| 规则 | 初值 |
|------|------|
| 有效喂食批次基础掉落 | 8% |
| 升级 | 100% 小奖励 |
| 每日首充加成 | +15% |
| 保底 | 25 次未掉 → common+ |
| 日 cap | 6 |

### Phase 4 · 皮肤 / 装备可视化

- [x] 叠加层渲染（base + gear overlays，程序化 32×32 像素叠层）
- [x] 皮肤 = 整套 recolor（经典 / 薄荷 / 午夜）；装备 = 局部 overlay
- [x] 图鉴（已得 / 剪影）
- [x] 出厂内容：3 皮肤 + 道具/装备目录（可掉落）
- [x] 背包/图鉴实时像素预览；启动时校验未拥有装备/皮肤；装备事件入时间线

### Phase 5 · 内容与打磨

- 节日皮、成就绑定掉落、模型彩蛋
- 像素 QA（接缝、高 DPI、整数缩放）
- 性能（约 8–12 fps 循环）
- 3D 降为可选实验皮肤

## 排期粗估（单人）

| 里程碑 | 内容 | 可玩性 |
|--------|------|--------|
| M1 | 像素 idle + 切换 | 新猫活了 |
| M2 | 事件动作 + 升级演出 | 有灵魂 |
| M3 | 掉落 + 背包 + 保底 | 有收集欲 |
| M4 | 装备叠加 + 图鉴 | 养成闭环 |
| M5 | 内容扩充 | 长期可玩 |

完整闭环约 **5–8 周**；M1–M2 有美术加速时可压到 2–3 周。

## 明确不做（近期）

- 在线商城 / 付费抽卡
- 一次做上百件装备
- 废弃 token 成长数值、只剩换装

## 工程触点

- 设置：`Sources/TokcatKit/Settings/AppSettings.swift` → `DesktopPetSkin`
- 窗口：`App/PetWindowController.swift`（像素 / SceneKit 双路径）
- 渲染：`App/PixelPet/`
- 资源：`App/Resources/Sprites/TokcatPixel/`
- 生成脚本：`scripts/generate_pixel_tokcat.py`
- 掉落：`Sources/TokcatKit/Loot/*` + `App/InventoryView.swift` / `App/CodexView.swift`
- 叠层：`App/PixelPet/PixelPetOverlayRenderer.swift` / `PixelPetPreviewView.swift`
- 测试：设置编解码覆盖 `pixelTokcat`；`LootEngineTests` / 库存 round-trip

## 成功标准

用户感知：

> 用 AI coding 时，桌上一只像素猫跟着干活；升级会庆祝；之后还能掉装备、换皮肤。

而不是：

> 菜单栏在记账，旁边挂了个静态模型。

---

## 与「令牌密契」的关系

成长叙事、三途径、双层文案与数值重置见：

- [`TokenCompactLore.md`](./TokenCompactLore.md) — 设定与 UX（明文主显 + 密契副显）
- [`TokenCompactPlan.md`](./TokenCompactPlan.md) — 分期 C0–C7

像素阶段外观将从「幼/成/老」文案迁移为 **显化阶**（`ManifestTier`）；叠加层与菜单栏冠徽在密契 **Phase C5** 与本路线图表现层汇合。

