# Default catgirl model — selection & conversion

Tokcat’s desktop pet can render:

1. **Procedural cube cat** — original box rig (`CatSceneBuilder`)
2. **Catgirl** — humanoid catgirl skin (`desktopPetSkin = .catgirl`)
   - Prefers bundled `App/Resources/Models/Catgirl/Catgirl.usdz`
   - Falls back to built-in chibi catgirl rig if no USDZ is present

This document freezes the **asset policy** and the **VRoid → USDZ** pipeline.

---

## 1. Recommended default character policy

We need a model that is **clearly redistributable** (CC0 / public domain / original work).  
There is **no single famous “CC0 catgirl VRM”** that is both high quality and always safe to vendor without review. The practical default path:

### Preferred product default
**Create a Tokcat-original catgirl in VRoid Studio** (cat ears + tail + simple dress), export VRM, convert to USDZ, ship as `Catgirl.usdz`.

Why:
- Clear license ownership for the app
- Looks like a real “猫娘” instead of a cube or a random VR avatar
- Matches Desktop Mate / VRM ecosystem expectations

### Acceptable CC0 bases (if you don’t want to author from scratch)

| Priority | Asset | License | Use |
|---|---|---|---|
| 1 | [MJMoonbow/VRMavatars](https://github.com/MJMoonbow/VRMavatars) `skinnie*.vrm` | CC0-1.0 | Humanoid anime-ish base; add cat ears/tail in Blender |
| 2 | [Open Source Avatars](https://github.com/ToxSam/open-source-avatars) CC0 catalog | CC0 | Search chibi / animal-ear styles; verify entry before vendoring |
| 3 | [cc0_humanoid_vrm](https://github.com/yummy5678/cc0_humanoid_vrm) | Unlicense | Tiny technical humanoid for loader testing only |

**Decision for Tokcat now:**  
Ship **skin switch + procedural chibi catgirl fallback** immediately. Treat real USDZ as an optional drop-in under `App/Resources/Models/Catgirl/`, with CC0/original conversion steps below.

---

## 2. Why USDZ (not raw VRM) for v1

| Format | SceneKit | Expressions / SpringBone | Effort |
|---|---|---|---|
| **USDZ** | Native `SCNScene(url:)` | Bake clips in advance | Low on Apple |
| VRM | Needs glTF + VRM extensions | Runtime MToon/SpringBone | High |

v1 architecture:
```
PetState → CatgirlAnimator / BundledCatgirlAnimator
                ↑
     CatgirlSceneBuilder (fallback)  or  Catgirl.usdz via CatModelLoader
```

Later optional: user-imported VRM (separate feature).

---

## 3. Conversion steps (VRoid → USDZ)

### Tools
- [VRoid Studio](https://vroid.com/en/studio) (authoring)
- [Blender](https://www.blender.org/) 3.6+ or 4.x
- Blender VRM add-on: [saturday06/VRM-Addon-for-Blender](https://github.com/saturday06/VRM-Addon-for-Blender)
- One of:
  - Apple **Reality Converter** (UI), or
  - Xcode / `xcrun usdzconvert` (if available on your macOS/Xcode), or
  - Blender USD export → `.usdc`/`.usdz`

### Step-by-step

1. **Author**
   - VRoid Studio → create female base
   - Add **cat ears** + **tail** accessories
   - Keep polycount modest for a 220×220 desktop window (simple hair/clothes)
   - Export **VRM 0.x or 1.x**

2. **Import to Blender**
   - Install VRM add-on
   - File → Import → VRM
   - Apply transforms, remove unused exports if needed

3. **Normalize for Tokcat**
   - Facing +Z or −Z consistently (SceneKit camera looks at origin from +Z)
   - Feet near world origin, character height ~1.6–1.8 m
   - Optional: create 3 actions
     - `idle` (breathing / slight sway)
     - `happy` (tail up, faster sway)
     - `hungry` (slouch)
   - Or leave static mesh and let `BundledCatgirlAnimator` bob the root (current behavior)

4. **Export USD**
   - File → Export → Universal Scene Description
   - Prefer **USDZ** packing textures, or USDC + textures then pack
   - Name the file `Catgirl.usdz`

5. **Drop into app**
   ```text
   App/Resources/Models/Catgirl/Catgirl.usdz
   App/Resources/Models/Catgirl/ATTRIBUTION.md   # fill author/license
   ```

6. **Build**
   ```bash
   swift build
   swift run TokcatApp
   ```
   Settings → Desktop Pet → Skin → **Catgirl**

### CC0 GitHub VRM → USDZ (same pipeline)
```bash
# example: download a CC0 VRM (illustrative)
# curl -L -o /tmp/base.vrm https://github.com/MJMoonbow/VRMavatars/raw/main/skinnie1_5.vrm
# Import /tmp/base.vrm in Blender (VRM add-on), add cat ears/tail, export USDZ
cp ~/Desktop/Catgirl.usdz App/Resources/Models/Catgirl/Catgirl.usdz
```

---

## 4. Runtime behavior in Tokcat

`CatSceneView` selection:

```text
desktopPetSkin
 ├─ procedural → CatSceneBuilder + CatAnimator
 └─ catgirl
     ├─ CatModelLoader finds Catgirl.usdz → BundledCatgirlAnimator
     └─ else → CatgirlSceneBuilder + CatgirlAnimator
```

`PetState` mapping (both skins):
- **mood** → sway / tail energy / eye scale
- **hunger** → head & ear droop / slouch
- **level up** → bounce + spin

Settings key: `desktopPetSkin` in `tokcat.appSettings` (`UserDefaults`).

---

## 5. Checklist before shipping a real model

- [ ] License is CC0, Unlicense, or original Tokcat work
- [ ] `ATTRIBUTION.md` filled
- [ ] File size reasonable (ideally &lt; 15 MB for menu-bar app)
- [ ] Opaque background not required (pet window is clear)
- [ ] Looks OK at ~200 pt height
- [ ] No DockX / commercial ripped assets

---

## 6. 本机 Blender 一键转换（已准备脚本）

仓库脚本：

```bash
# 查看用法
scripts/convert_catgirl.sh

# 例：CC0 底座 VRM → 内置路径
curl -L -o /tmp/skinnie.vrm \
  https://github.com/MJMoonbow/VRMavatars/raw/main/skinnie1_5.vrm
scripts/convert_catgirl.sh /tmp/skinnie.vrm
```

### 安装清单
1. **安装 Blender.app** 到 `/Applications`（打开 dmg → 拖进去 → 首次右键打开）
2. **安装 VRM 插件**（仅 .vrm 需要）
   - 下载：[VRM-Addon-for-Blender Releases](https://github.com/saturday06/VRM-Addon-for-Blender/releases)
   - Blender → Edit → Preferences → Add-ons → Install… → 选 zip → 勾选启用
3. 运行 `scripts/convert_catgirl.sh your.vrm`
4. `swift run TokcatApp`，设置里选 **猫娘**

### 推荐角色路径（更像猫娘）
- **最好**：VRoid Studio 做猫耳猫尾角色 → 导出 VRM → 上面脚本
- **最快试通**：CC0 `skinnie*.vrm` 先转通加载管线，再换正式猫娘

输出默认写入：

`App/Resources/Models/Catgirl/Catgirl.usdz`

### Steam 版 Blender（本机）

本仓库脚本已支持 Steam 安装路径：

`~/Library/Application Support/Steam/steamapps/common/Blender/Blender.app/Contents/MacOS/Blender`

也可用环境变量覆盖：

```bash
BLENDER="/Users/你/Library/Application Support/Steam/steamapps/common/Blender/Blender.app/Contents/MacOS/Blender" \
  scripts/convert_catgirl.sh model.vrm
```

VRM 插件已可安装到：

`~/Library/Application Support/Blender/5.1/scripts/addons/VRM_Addon_for_Blender`
