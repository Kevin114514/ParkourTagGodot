import bpy
import os

PROJECT_ROOT = r"D:\ParkourTagGodot"
SRC_BLEND = os.path.join(PROJECT_ROOT, "maps", "forest_prototype.blend")
OUT_GLB = os.path.join(PROJECT_ROOT, "maps", "forest_island_map.glb")


def ensure_output_dir(path: str):
    os.makedirs(os.path.dirname(path), exist_ok=True)


def main():
    ensure_output_dir(OUT_GLB)

    # 如果当前不是目标文件，先打开 blend
    current_path = bpy.data.filepath.replace("\\", "/")
    if current_path.lower() != SRC_BLEND.replace("\\", "/").lower():
        bpy.ops.wm.open_mainfile(filepath=SRC_BLEND)

    bpy.ops.object.select_all(action='SELECT')

    # 仅使用跨版本稳定参数，避免不同 Blender 版本导出参数差异导致失败
    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB,
        export_format='GLB',
        use_selection=False,
        export_yup=True,
        export_apply=True,
    )

    print(f"[OK] 导出完成: {OUT_GLB}")


if __name__ == "__main__":
    main()
