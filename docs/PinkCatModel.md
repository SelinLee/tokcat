# 3D 宠物模型（自定义）

> 默认桌宠为 **高清 2D Tokcat**（见 `docs/PixelPetArtBible.md`）。内置粉猫 USDZ 已移除。

| 皮肤 | 说明 |
|------|------|
| **高清 Tokcat** | 128×128 插画帧动画（默认） |
| **方块猫** | SceneKit 程序化低模 |
| **自定义** | 用户导入的 `.usdz` / `.scn` 等 |

旧设置值 `"catgirl"` / `"pinkCat"` 会在加载时迁移为高清 Tokcat。

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
