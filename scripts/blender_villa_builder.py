import bpy
import bmesh
import os
from math import radians

PROJECT_ROOT = r"D:\ParkourTagGodot"
OUTPUT_BLEND = os.path.join(PROJECT_ROOT, "maps", "villa_prototype.blend")


def ensure_output_dir(path: str):
    os.makedirs(os.path.dirname(path), exist_ok=True)


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

    for block in bpy.data.meshes:
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in bpy.data.materials:
        if block.users == 0:
            bpy.data.materials.remove(block)


def new_material(name, color, roughness=0.6, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
    return mat


def assign_material(obj, mat):
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)


def setup_scene():
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'

    if 'BLENDER_EEVEE' in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items.keys():
        scene.render.engine = 'BLENDER_EEVEE'
    else:
        scene.render.engine = 'CYCLES'

    world = scene.world
    if world is None:
        world = bpy.data.worlds.new("World")
        scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.64, 0.73, 0.90, 1.0)
        bg.inputs[1].default_value = 0.95

    bpy.ops.object.light_add(type='SUN', location=(24, -18, 38))
    sun = bpy.context.active_object
    sun.name = "Sun"
    sun.rotation_euler = (radians(42), radians(6), radians(22))
    sun.data.energy = 3.6


def create_ground(ground_mat, grass_mat):
    bpy.ops.mesh.primitive_plane_add(size=160, location=(0, 0, -0.02))
    ground = bpy.context.active_object
    ground.name = "Ground"
    assign_material(ground, grass_mat)

    bpy.ops.mesh.primitive_plane_add(size=44, location=(0, 0, 0.0))
    yard = bpy.context.active_object
    yard.name = "Yard"
    assign_material(yard, ground_mat)


def create_house_body(wall_mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 4.0))
    house = bpy.context.active_object
    house.name = "VillaBody"
    house.scale = (9.5, 7.0, 4.0)
    assign_material(house, wall_mat)
    return house


def create_roof(roof_mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 8.8))
    roof = bpy.context.active_object
    roof.name = "Roof"
    roof.scale = (10.5, 8.2, 0.55)
    roof.rotation_euler = (radians(16), 0, 0)
    assign_material(roof, roof_mat)

    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 10.1))
    roof2 = bpy.context.active_object
    roof2.name = "RoofTop"
    roof2.scale = (8.0, 6.2, 0.42)
    roof2.rotation_euler = (radians(16), 0, 0)
    assign_material(roof2, roof_mat)


def create_front_portico(wall_mat, pillar_mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -8.0, 2.9))
    awning = bpy.context.active_object
    awning.name = "PorticoAwning"
    awning.scale = (4.0, 1.6, 0.3)
    assign_material(awning, wall_mat)

    for i, x in enumerate([-2.8, -1.1, 1.1, 2.8]):
        bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.22, depth=3.0, location=(x, -7.2, 1.5))
        p = bpy.context.active_object
        p.name = f"PorticoPillar_{i:02d}"
        assign_material(p, pillar_mat)


def create_door_and_windows(frame_mat, glass_mat, wood_mat):
    # 门框
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -7.02, 1.55))
    door = bpy.context.active_object
    door.name = "MainDoor"
    door.scale = (1.15, 0.08, 1.55)
    assign_material(door, wood_mat)

    # 窗户（正面 + 两侧）
    front_positions = [(-5.2, -7.01, 2.9), (-2.9, -7.01, 2.9), (2.9, -7.01, 2.9), (5.2, -7.01, 2.9)]
    side_positions = [(-9.01, -2.2, 2.8), (-9.01, 2.2, 2.8), (9.01, -2.2, 2.8), (9.01, 2.2, 2.8)]

    for idx, (x, y, z) in enumerate(front_positions + side_positions):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, z))
        frame = bpy.context.active_object
        frame.name = f"WindowFrame_{idx:02d}"
        if abs(x) > 8.5:
            frame.scale = (0.08, 1.05, 1.05)
        else:
            frame.scale = (1.05, 0.08, 1.05)
        assign_material(frame, frame_mat)

        bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, z))
        pane = bpy.context.active_object
        pane.name = f"WindowGlass_{idx:02d}"
        if abs(x) > 8.5:
            pane.scale = (0.03, 0.88, 0.88)
        else:
            pane.scale = (0.88, 0.03, 0.88)
        assign_material(pane, glass_mat)


def create_balcony(frame_mat, floor_mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -7.5, 5.6))
    floor = bpy.context.active_object
    floor.name = "BalconyFloor"
    floor.scale = (3.8, 1.8, 0.2)
    assign_material(floor, floor_mat)

    rail_positions = [(-3.6, -7.5, 6.5), (3.6, -7.5, 6.5), (0, -9.2, 6.5)]
    rail_scales = [(0.12, 1.8, 0.7), (0.12, 1.8, 0.7), (3.7, 0.12, 0.7)]

    for i, (pos, scl) in enumerate(zip(rail_positions, rail_scales)):
        bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
        rail = bpy.context.active_object
        rail.name = f"BalconyRail_{i:02d}"
        rail.scale = scl
        assign_material(rail, frame_mat)


def create_path_and_pool(path_mat, water_mat):
    # 入户步道
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -20, 0.04))
    path = bpy.context.active_object
    path.name = "EntrancePath"
    path.scale = (2.2, 12.0, 0.04)
    assign_material(path, path_mat)

    # 小泳池
    bpy.ops.mesh.primitive_cube_add(size=1, location=(12.0, -4.0, -0.22))
    pool_hole = bpy.context.active_object
    pool_hole.name = "PoolBase"
    pool_hole.scale = (4.6, 3.2, 0.9)
    assign_material(pool_hole, path_mat)

    bpy.ops.mesh.primitive_cube_add(size=1, location=(12.0, -4.0, 0.32))
    pool_water = bpy.context.active_object
    pool_water.name = "PoolWater"
    pool_water.scale = (4.1, 2.7, 0.05)
    assign_material(pool_water, water_mat)


def create_trees(trunk_mat, leaf_mat):
    coords = [(-19, 14), (-16, 9), (-20, -8), (18, 15), (20, 7), (18, -10), (10, 18), (-8, 17)]
    for i, (x, y) in enumerate(coords):
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.26, depth=2.4, location=(x, y, 1.2))
        trunk = bpy.context.active_object
        trunk.name = f"TreeTrunk_{i:02d}"
        assign_material(trunk, trunk_mat)

        bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=1.8, depth=3.2, location=(x, y, 3.35))
        crown = bpy.context.active_object
        crown.name = f"TreeCrown_{i:02d}"
        assign_material(crown, leaf_mat)


def add_camera():
    bpy.ops.object.camera_add(location=(34, -38, 24), rotation=(radians(62), 0, radians(42)))
    cam = bpy.context.active_object
    cam.name = "OverviewCamera"
    bpy.context.scene.camera = cam


def main():
    ensure_output_dir(OUTPUT_BLEND)
    clear_scene()
    setup_scene()

    wall_mat = new_material("Wall_Mat", (0.86, 0.84, 0.80), roughness=0.82)
    roof_mat = new_material("Roof_Mat", (0.30, 0.23, 0.20), roughness=0.78)
    pillar_mat = new_material("Pillar_Mat", (0.76, 0.76, 0.74), roughness=0.72)
    frame_mat = new_material("Frame_Mat", (0.18, 0.19, 0.20), roughness=0.45)
    wood_mat = new_material("Wood_Mat", (0.33, 0.22, 0.12), roughness=0.7)
    glass_mat = new_material("Glass_Mat", (0.72, 0.86, 0.92), roughness=0.06)
    path_mat = new_material("Path_Mat", (0.55, 0.55, 0.55), roughness=0.92)
    water_mat = new_material("PoolWater_Mat", (0.08, 0.38, 0.65), roughness=0.08)
    ground_mat = new_material("Yard_Mat", (0.45, 0.41, 0.35), roughness=0.95)
    grass_mat = new_material("Grass_Mat", (0.24, 0.40, 0.22), roughness=0.94)
    trunk_mat = new_material("Trunk_Mat", (0.28, 0.20, 0.12), roughness=0.9)
    leaf_mat = new_material("Leaf_Mat", (0.18, 0.45, 0.21), roughness=0.92)

    create_ground(ground_mat, grass_mat)
    create_house_body(wall_mat)
    create_roof(roof_mat)
    create_front_portico(wall_mat, pillar_mat)
    create_door_and_windows(frame_mat, glass_mat, wood_mat)
    create_balcony(frame_mat, ground_mat)
    create_path_and_pool(path_mat, water_mat)
    create_trees(trunk_mat, leaf_mat)
    add_camera()

    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND)
    print(f"[OK] 别墅原型已生成: {OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
