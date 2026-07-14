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
| 源画布 | **32×32** px / 帧 |
| 桌面显示 | 整数倍缩放（×4 → 128、×6 → 192） |
| 插值 | **Nearest neighbor**，禁止双线性糊边 |
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

## 分层（为皮肤 / 装备预留）

从下到上：

1. `shadow`（可选，地面省略亦可）
2. `body` 主体 + 腿尾
3. `face` 五官
4. `token_mark` 品牌印记（可并入 body）
5. `equip_back` 背饰
6. `equip_head` 头饰
7. `equip_held` 手持
8. `equip_aura` 特效（克制，少帧附着）
9. `fx` 升级星点等（必须附着轮廓，避免游离碎点）

v1 将 1–4 烘焙进单层帧；Phase 4 以程序化 32×32 overlay 叠装备，皮肤用调色映射（经典/薄荷/午夜）。

## 动作表（v1）

| Clip | 帧数 | 循环 | 触发 |
|------|------|------|------|
| `idle` | 4 | 是 | 默认 content |
| `working` | 4 | 是 | focused / excited / token 速率高 |
| `happy` | 3 | 是 | happy 心情 |
| `sad` | 3 | 是 | sad / lowEnergy |
| `sleepy` | 3 | 是 | sleepy |
| `hungry` | 3 | 是 | hungry |
| `eating` | 4 | 否 | 喂食脉冲 |
| `level_up` | 5 | 否 | 升级脉冲 |
| `interact` | 3 | 否 | 点击互动 |
| `rest` | 4 | 是* | 懒躺/趴窝常驻（*稀疏微动） |
| `pace` | 8 | 否 | 来回踱步（时间驱动） |
| `groom` | 4 | 否 | 理毛舔爪（时间驱动） |
| `look_around` | 6 | 否 | 左顾右盼（时间驱动） |

### 动作要点

- **idle**：呼吸起伏 + 眨眼（至少 1 帧闭眼）
- **working**：前爪轻点 / 身体微倾，表「在干活」；不要画速度线
- **eating**：低头 + 口部开合，可出现小 token 屑（附着）
- **level_up**：拉伸弹跳 + 附着星点；结束后回落 idle/happy
- **interact**：抬爪挥手或歪头

## 文件命名

```
App/Resources/Sprites/TokcatPixel/
  idle_0.png … idle_3.png
  working_0.png …
  happy_0.png …
  sad_0.png …
  sleepy_0.png …
  hungry_0.png …
  eating_0.png …
  level_up_0.png …
  interact_0.png …
  manifest.json
```

`manifest.json` 字段：

```json
{
  "name": "Tokcat Pixel",
  "version": 1,
  "frameSize": 32,
  "clips": {
    "idle": { "frames": 4, "fps": 6, "loop": true },
    "working": { "frames": 4, "fps": 8, "loop": true },
    "level_up": { "frames": 5, "fps": 10, "loop": false }
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
python3 scripts/generate_pixel_tokcat.py
```

输出写入 `App/Resources/Sprites/TokcatPixel/`。
