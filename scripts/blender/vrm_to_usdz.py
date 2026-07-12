"""
Tokcat helper: import a VRM (via VRM add-on) or glTF, normalize, export USDZ/USDA.

Usage (headless):
  /Applications/Blender.app/Contents/MacOS/Blender -b -P scripts/blender/vrm_to_usdz.py -- \\
    --input /path/to/model.vrm --output App/Resources/Models/Catgirl/Catgirl.usdz

Requirements:
  - Blender 3.6+ or 4.x
  - VRM add-on installed when input is .vrm:
      https://github.com/saturday06/VRM-Addon-for-Blender
"""

from __future__ import annotations

import argparse
import math
import os
import sys
from pathlib import Path


def _argv_after_double_dash(argv: list[str]) -> list[str]:
    if "--" in argv:
        return argv[argv.index("--") + 1 :]
    return []


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Convert VRM/glTF to USDZ for Tokcat")
    parser.add_argument("--input", required=True, help="Input .vrm / .glb / .gltf path")
    parser.add_argument("--output", required=True, help="Output .usdz or .usda path")
    parser.add_argument(
        "--target-height",
        type=float,
        default=1.7,
        help="Normalize character height in meters (default 1.7)",
    )
    parser.add_argument(
        "--face-camera",
        action="store_true",
        default=True,
        help="Rotate model to face +Z (SceneKit camera)",
    )
    return parser.parse_args(_argv_after_double_dash(sys.argv))


def enable_vrm_addon() -> None:
    """Enable VRM add-on if installed (needed for .vrm import)."""
    import addon_utils
    import bpy

    candidates = []
    for mod in addon_utils.modules():
        name = mod.__name__
        if "vrm" in name.lower():
            candidates.append(name)
    candidates.extend(["VRM_Addon_for_Blender", "vrm"])

    enabled = False
    for name in dict.fromkeys(candidates):  # unique, preserve order
        try:
            bpy.ops.preferences.addon_enable(module=name)
            print(f"[tokcat] enabled add-on: {name}")
            enabled = True
            break
        except Exception as exc:  # noqa: BLE001
            print(f"[tokcat] could not enable {name}: {exc}")
    if not enabled:
        print("[tokcat] warning: VRM add-on not enabled; .vrm import may fail")


def clear_scene() -> None:
    import bpy

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    # Also clear orphans meshes/materials lightly
    for block in list(bpy.data.meshes):
        if block.users == 0:
            bpy.data.meshes.remove(block)


def import_model(path: Path) -> None:
    import bpy

    suffix = path.suffix.lower()
    if suffix == ".vrm":
        # Prefer official VRM operator names across addon versions.
        tried = []
        for op_path in (
            ("import_scene", "vrm"),
            ("import_scene", "vrm0"),
            ("import_scene", "vrm1"),
            ("wm", "vrm_import"),
        ):
            mod, name = op_path
            op = getattr(getattr(bpy.ops, mod, None), name, None)
            if op is None:
                tried.append(f"bpy.ops.{mod}.{name}")
                continue
            result = op(filepath=str(path))
            if "FINISHED" in result:
                return
            tried.append(f"bpy.ops.{mod}.{name} -> {result}")
        raise RuntimeError(
            "Failed to import VRM. Install/enable 'VRM Add-on for Blender' first.\n"
            "Tried: " + ", ".join(tried)
        )

    if suffix in {".glb", ".gltf"}:
        bpy.ops.import_scene.gltf(filepath=str(path))
        return

    if suffix in {".fbx"}:
        bpy.ops.import_scene.fbx(filepath=str(path))
        return

    raise RuntimeError(f"Unsupported input format: {suffix}")


def mesh_objects():
    import bpy

    return [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]


def scene_bounds():
    import bpy
    from mathutils import Vector

    mins = Vector((math.inf, math.inf, math.inf))
    maxs = Vector((-math.inf, -math.inf, -math.inf))
    found = False
    for obj in mesh_objects():
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            mins.x = min(mins.x, world.x)
            mins.y = min(mins.y, world.y)
            mins.z = min(mins.z, world.z)
            maxs.x = max(maxs.x, world.x)
            maxs.y = max(maxs.y, world.y)
            maxs.z = max(maxs.z, world.z)
            found = True
    if not found:
        raise RuntimeError("No mesh objects found after import")
    return mins, maxs


def normalize(target_height: float, face_camera: bool) -> None:
    import bpy
    from mathutils import Vector

    # Select all root-ish objects and join transforms via empty parent.
    bpy.ops.object.select_all(action="DESELECT")
    roots = [obj for obj in bpy.context.scene.objects if obj.parent is None]
    for obj in roots:
        obj.select_set(True)
    if not roots:
        raise RuntimeError("No root objects to normalize")

    bpy.context.view_layer.objects.active = roots[0]
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 0))
    empty = bpy.context.active_object
    empty.name = "TokcatRoot"

    for obj in roots:
        if obj == empty:
            continue
        obj.select_set(True)
    empty.select_set(True)
    bpy.context.view_layer.objects.active = empty
    # Parent keep transform
    for obj in list(roots):
        if obj == empty:
            continue
        obj.parent = empty
        obj.matrix_parent_inverse = empty.matrix_world.inverted()

    mins, maxs = scene_bounds()
    size = maxs - mins
    height = size.z if size.z > 1e-6 else max(size.x, size.y)
    scale = target_height / height
    empty.scale = (scale, scale, scale)
    bpy.context.view_layer.update()

    mins, maxs = scene_bounds()
    center_x = (mins.x + maxs.x) * 0.5
    center_y = (mins.y + maxs.y) * 0.5
    empty.location -= Vector((center_x, center_y, mins.z))
    bpy.context.view_layer.update()

    if face_camera:
        # VRM is often -Z forward; SceneKit pet camera looks from +Z toward origin.
        # A 180° Z rotation makes the character face the camera in common cases.
        empty.rotation_euler[2] = math.pi


def export_usd(path: Path) -> None:
    import bpy

    path.parent.mkdir(parents=True, exist_ok=True)
    suffix = path.suffix.lower()
    export = getattr(bpy.ops.wm, "usd_export", None)
    if export is None:
        raise RuntimeError("This Blender build has no wm.usd_export operator")

    # Prefer a real usdz package; if texture packing fails on some Blender builds,
    # also emit a sibling .usdc that SceneKit can often still load via CatModelLoader.
    targets = [path]
    if suffix == ".usdz":
        targets.append(path.with_suffix(".usdc"))

    last_error = None
    for target in targets:
        kwargs_options = [
            {
                "filepath": str(target),
                "export_materials": True,
                "export_textures": True,
                "export_animation": False,
                "relative_paths": True,
                "export_textures_mode": "EXPORT",
            },
            {
                "filepath": str(target),
                "export_materials": True,
                "export_textures": True,
                "relative_paths": True,
            },
            {"filepath": str(target)},
        ]
        for kwargs in kwargs_options:
            try:
                result = export(**kwargs)
            except TypeError as exc:
                last_error = exc
                continue
            if "FINISHED" in result and target.exists():
                print(f"[tokcat] wrote {target} ({target.stat().st_size} bytes)")
                break
        else:
            continue
        break
    else:
        raise RuntimeError(f"USD export failed: {last_error}")

    if not path.exists():
        # Accept sibling usdc if usdz packaging failed.
        usdc = path.with_suffix(".usdc")
        if usdc.exists():
            print(f"[warn] usdz missing, but {usdc.name} exists and will be loadable by CatModelLoader")
        else:
            raise RuntimeError(f"Export reported success but file missing: {path}")


def main() -> None:
    args = parse_args()
    input_path = Path(args.input).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()
    if not input_path.exists():
        raise SystemExit(f"Input not found: {input_path}")

    enable_vrm_addon()
    clear_scene()
    print(f"[tokcat] import {input_path}")
    import_model(input_path)
    print("[tokcat] normalize")
    normalize(target_height=args.target_height, face_camera=args.face_camera)
    print(f"[tokcat] export {output_path}")
    export_usd(output_path)
    print("[tokcat] done")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 - surface to shell clearly
        print(f"[tokcat] ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
