# 粉猫模型 — 内置资源与转换

## 当前皮肤

> 默认桌宠已切换为 **像素 Tokcat**（见 `docs/PixelPetRoadmap.md`）。以下为 3D 皮肤说明。

| 皮肤 | 说明 |
|------|------|
| **方块猫** | SceneKit 程序化低模 |
| **粉猫** | 内置 CC0 Chubby Tubby Cat（`App/Resources/Models/Catgirl/Catgirl.usdz`） |
| **自定义** | 用户导入的 `.usdz` / `.scn` 等 |

历史上资源目录与文件名使用 `Catgirl` 路径以兼容旧构建；UI 与设置中已不再提供「猫娘 / Q 版猫娘」皮肤。旧设置值 `"catgirl"` 会在加载时迁移为 `pinkCat`。

## 加载管线

```
PetState
  → BundledCatAnimator（USDZ）或 CatAnimator（方块猫）
  → CatModelLoader（Models/Catgirl/*.usdz）
  → 缺失则回退方块猫
```

## 替换内置粉猫

1. 准备 VRM / glTF 模型  
2. 运行：

```bash
scripts/convert_pet_model.sh /path/to/model.vrm
# 默认输出 App/Resources/Models/Catgirl/Catgirl.usdz
```

3. 更新 `App/Resources/Models/Catgirl/ATTRIBUTION.md`  
4. `swift run TokcatApp`，设置 → 宠物 → **粉猫**

## 自定义模型

用户侧请用设置里的「导入模型」，不要改仓库内置资源。
