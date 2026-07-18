# Pixel Tokcat Art Bible

## 角色

- **名称**：Tokcat（像素形态）
- **定位**：本地 AI coding 桌宠；吃 token 成长的原创像素猫
- **气质**：圆润、清醒、轻微「工程师」感；亲和但不幼态到无特征
- **原创约束**：可参考「像素桌面猫」品类气质，**禁止**复刻 Claude 猫轮廓 / 配色 / 标志性剪影

## 识别特征

1. **Token 印记**：胸口或额头一枚六边形 / 小芯片色块（品牌锚点）
2. **耳部**：外耳深描边，内耳青瓷色（`#5FBFB5` 一带）
3. **眼**：大而清醒的深色瞳 + 高光点；专注态瞳孔更竖
4. **体色**：暖米白底 + 杏橙点缀（非纯橙团、非纯黑）
5. **姿态**：略前倾坐姿，可抬前爪做「敲代码 / 挥手」

## 画布与显示

| 项 | 规范 |
|----|------|
| 源画布 | **128×128** px / 帧（v9 高清插画） |
| 桌面显示 | 平滑缩放铺满悬浮窗 |
| 插值 | **双线性 / 高质量**（非像素风） |
| 背景 | 全透明 |
| 描边 | 1px 深色硬边（`#2A2430`） |
| 色板 | ≤ 16 色（含透明） |

## 推荐色板（v1）

| 角色 | Hex | 用途 |
|------|-----|------|
| Outline | `#2A2430` | 轮廓 |
| Fur Light | `#F6E7D8` | 主体 |
| Fur Mid | `#E7C2A0` | 阴影体积 |
| Accent | `#E89B5F` | 耳尖 / 尾 / 斑 |
| Inner Ear | `#5FBFB5` | 内耳 |
| Token | `#6C8CFF` | token 印记 |
| Token Hi | `#B7C6FF` | 印记高光 |
| Eye | `#1E1A24` | 瞳 |
| Eye Hi | `#FFFFFF` | 眼高光 |
| Nose | `#D4728A` | 鼻 |
| Cheek | `#F0A8A0` | 腮红（happy） |
| Shadow | `#C9A48A` | 腹底阴影 |
| Spark | `#FFE28A` | 升级高光 |

## 分层（v9 高清）

从下到上：

1. `scene` 场景道具（desk / bowl）— **不与猫烘焙在一起**
2. `base` 主体整帧 128×128 插画（体 + 脸 + token 印记）
3. `gear_back` / `gear_held` / `gear_head` / `gear_face` / `gear_aura` — 真像素 PNG
4. `fx` 升级星点等（可并入 base 或 aura）

约定：

- **皮肤**：仅对 `base` 做色板 remap（经典 / 薄荷 / 午夜）；不改剪影
- **装备**：`gear/{item_id}.png`，在 **sit 姿态族** 下绘制整幅 32×32，运行时按 `poseFamily` 锚点偏移
- **场景**：`scene_desk*.png` / `scene_bowl.png`，由 manifest `clips.*.scene` 绑定
- **不拆** 头/身/腿每帧独立骨骼层（32×32 下收益低、易碎）

## 动作表（v5 · 多轮廓大动作）

| Clip | 帧数 | 循环 | 触发 | Codex 对应 |
|------|------|------|------|------------|
| `idle` | 4 | 是* | 默认 content | idle |
| `working` | 4 | 是* | focused / excited / agent working | running（工作，非奔跑） |
| `happy` | 3 | 是* | happy / completed 庆祝 | — |
| `sad` | 3 | 是* | sad / lowEnergy | — |
| `sleepy` | 3 | 是* | sleepy | — |
| `hungry` | 3 | 是* | hungry | — |
| `waiting` | 4 | 是* | 低能量等待确认 | waiting |
| `failed` | 4 | 是* | 极低 mood / 受挫 | failed |
| `review` | 6 | 是* | 任务完成后审阅 | review |
| `wave` | 4 | 否 | 点击/ambient 招呼 | waving |
| `jump` | 5 | 否 | ambient 庆祝弹跳 | jumping |
| `eating` | 4 | 否 | 喂食脉冲 | — |
| `level_up` | 5 | 否 | 升级脉冲 | — |
| `interact` | 3 | 否 | 点击互动 | waving 变体 |
| `rest` | 4 | 是* | 懒躺/趴窝 | — |
| `pace` | 8 | 否 | 来回踱步（时间驱动） | running-right/left 轻量替代 |
| `groom` | 4 | 否 | 理毛舔爪（时间驱动） | — |
| `look_around` | 6 | 否 | 左顾右盼（时间驱动） | look directions 轻量替代 |

\* 基础态采用「静止 hold + 稀疏微动」，不无限循环刷帧。



### 轮廓差异（v5）

为避免“全是坐姿微调”，基础态改用不同剪影：

| Clip | 剪影 |
|------|------|
| `idle` / `happy` / `sad` / `wave` | 坐姿 |
| `working` / `review` | **工作台 + 屏幕**（右侧坐、前肢键盘） |
| `sleepy` | **侧躺** 全身横卧 |
| `rest` | **loaf 趴窝** 扁圆团 |
| `failed` | **瘫软 pancake** |
| `hungry` | **前伸 + 小碗** |
| `waiting` | **蹲伏抬爪** |
| `pace` | **站立行走** 腿可见 |
| `jump` / `level_up` | 坐姿大幅上下位移 |

### 动作要点

- **idle**：呼吸起伏 + 眨眼（至少 1 帧闭眼）
- **working**：前爪轻点 / 身体微倾 / 下巴思考，表「在干活」；不要画速度线、不要 literal 跑步
- **waiting**：前爪前伸、身体前倾，表「在等你确认」
- **failed**：低头 + 附着泪点 / 耷拉眉；禁止红叉、游离特效
- **review**：歪头扫视、瞳孔收紧，检查刚完成的输出
- **wave / interact**：抬爪挥手，禁止挥动手势线
- **jump / level_up**：仅用身体位移表现起跳；禁止地面阴影与冲击波
- **eating**：低头 + 口部开合，可出现小 token 屑（附着）
- **pace / look_around**：桌宠 ambient；对应 Codex 移动与 look 方向的轻量表达

## 文件命名

```
App/Resources/Sprites/TokcatPixel/
  idle_0.png …              # base：仅猫
  working_0.png …
  scene_desk.png            # scene 层
  scene_desk_0.png / _1.png # 显示器闪烁
  scene_bowl.png
  gear/
    eq_beanie.png           # sit 锚点装备
    eq_spark_aura_0.png …
  manifest.json
```

`manifest.json` 关键字段（v8）：

```json
{
  "name": "Tokcat Pixel",
  "version": 8,
  "frameSize": 32,
  "layers": {
    "order": ["scene", "base", "gear_back", "gear_held", "gear_head", "gear_face", "gear_aura"],
    "scene": { "desk": { "file": "scene_desk" }, "bowl": { "file": "scene_bowl" } },
    "gearSubdir": "gear"
  },
  "clips": {
    "idle": { "frames": 4, "fps": 6, "loop": true, "scene": null },
    "working": { "frames": 4, "fps": 8, "loop": true, "scene": "desk" },
    "hungry": { "frames": 3, "fps": 5, "loop": true, "scene": "bowl" }
  }
}
```

## Stage 差异（Phase 2+）

| Stage | 等级 | 视觉 |
|-------|------|------|
| 幼猫 | 1–9 | scale 0.86，斑纹更淡 |
| 成猫 | 10–24 | scale 1.0，标准 |
| 老猫 | 25+ | scale 1.12，token 印记更亮 / 可加小冠 |

## 禁止项

- 文字、UI、对话框、棋盘透明底
- 大面积柔光、投影、运动残影
- 游离在画布外的星星 / 眼泪 / 灰尘
- 与 Claude 官方猫过于近似的剪影与配色
- 非整数缩放导致的半像素

## 生成

```bash
python3 scripts/generate_hd_tokcat.py
```

输出写入 `App/Resources/Sprites/TokcatPixel/`。


## 装备外观契约（v5）

装备**不重画整只猫**，只在基础动作帧上叠局部层。多轮廓动作通过「姿态族锚点」对齐：

| 层 | 可变范围 | 不可变 |
|----|----------|--------|
| **皮肤** | 体色 remap（fur light/mid/accent/shadow） | 剪影、五官布局、动作帧 |
| **head** | 帽/耳机/冠等头顶局部 | 不改头骨轮廓 |
| **face** | 眼镜/面罩/徽章眼部局部 | 不替换整张脸 |
| **back** | 披风/背包/围巾 | 不改身体体积 |
| **held** | 手持小道具 | 不引入第二角色 |
| **aura** | 附着点光点 | 禁止大片光晕/投影 |

### 姿态族可见性

| 姿态族 | 典型 clip | 可见槽位 |
|--------|-----------|----------|
| sit | idle/happy/wave… | 全部 |
| desk | working/review | head/face/back/aura（隐藏 held，桌面已有键盘） |
| walk | pace | 全部 |
| crouch | waiting | 全部 |
| loaf | rest | head/face/aura |
| side/flop | sleepy/failed | face/aura |
| stretch | hungry | head/face/back/aura |

实现：`PixelPetOverlayRenderer` 合成 `scene → base(recolor) → gear PNG(优先)/程序化回退`；锚点 `anchor(for:)` + `visibleSlots(for:)` 由 `PixelPetClip.poseFamily` 驱动。
