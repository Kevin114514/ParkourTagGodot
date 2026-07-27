import bpy
import random
import os
import bmesh
from math import radians, sin, cos, sqrt

# =========================
# 基础配置
# =========================
random.seed(20260727)

PROJECT_ROOT = r"D:\ParkourTagGodot"
OUTPUT_BLEND = os.path.join(PROJECT_ROOT, "maps", "forest_prototype.blend")

MAP_SIZE = 220.0
ISLAND_RADIUS = 82.0
SEA_LEVEL = -1.35
LAKE_WATER_LEVEL = 0.20
LAKE_COUNT = 5

TREE_COUNT = 250
ROCK_COUNT = 70
BUSH_COUNT = 95


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
    for block in bpy.data.textures:
        if block.users == 0:
            bpy.data.textures.remove(block)


def new_material(name, color, roughness=0.75, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
    return mat


def create_terrain_material(name="Ground_Mat"):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes = nt.nodes
    links = nt.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    out.location = (540, 0)

    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (300, 0)
    bsdf.inputs["Roughness"].default_value = 0.92

    tex_coord = nodes.new("ShaderNodeTexCoord")
    tex_coord.location = (-860, -20)

    mapping = nodes.new("ShaderNodeMapping")
    mapping.location = (-650, -20)
    mapping.inputs["Scale"].default_value = (0.08, 0.08, 0.08)

    noise = nodes.new("ShaderNodeTexNoise")
    noise.location = (-430, -20)
    noise.inputs["Scale"].default_value = 8.0
    noise.inputs["Detail"].default_value = 7.0
    noise.inputs["Roughness"].default_value = 0.65

    color_ramp = nodes.new("ShaderNodeValToRGB")
    color_ramp.location = (-210, 0)
    color_ramp.color_ramp.elements[0].position = 0.34
    color_ramp.color_ramp.elements[0].color = (0.17, 0.30, 0.14, 1)
    color_ramp.color_ramp.elements[1].position = 0.84
    color_ramp.color_ramp.elements[1].color = (0.28, 0.40, 0.19, 1)

    bump = nodes.new("ShaderNodeBump")
    bump.location = (-40, -180)
    bump.inputs["Strength"].default_value = 0.18

    links.new(tex_coord.outputs["Object"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    links.new(noise.outputs["Fac"], color_ramp.inputs["Fac"])
    links.new(color_ramp.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    return mat


def create_foliage_material(name, base_a, base_b):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes = nt.nodes
    links = nt.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    out.location = (520, 0)

    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (300, 0)
    bsdf.inputs["Roughness"].default_value = 0.82
    if "Subsurface Weight" in bsdf.inputs:
        bsdf.inputs["Subsurface Weight"].default_value = 0.08

    tex_coord = nodes.new("ShaderNodeTexCoord")
    tex_coord.location = (-880, -20)

    mapping = nodes.new("ShaderNodeMapping")
    mapping.location = (-670, -20)
    mapping.inputs["Scale"].default_value = (1.2, 1.2, 1.2)

    noise = nodes.new("ShaderNodeTexNoise")
    noise.location = (-450, -20)
    noise.inputs["Scale"].default_value = 5.0
    noise.inputs["Detail"].default_value = 6.0

    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.location = (-220, 0)
    ramp.color_ramp.elements[0].position = 0.28
    ramp.color_ramp.elements[0].color = (*base_a, 1)
    ramp.color_ramp.elements[1].position = 0.80
    ramp.color_ramp.elements[1].color = (*base_b, 1)

    bump = nodes.new("ShaderNodeBump")
    bump.location = (-40, -180)
    bump.inputs["Strength"].default_value = 0.12

    links.new(tex_coord.outputs["Object"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    return mat


def create_water_material(name="Water_Mat"):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes = nt.nodes
    links = nt.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    out.location = (660, 0)

    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (360, 0)
    bsdf.inputs["Base Color"].default_value = (0.05, 0.30, 0.54, 1)
    bsdf.inputs["Roughness"].default_value = 0.05
    bsdf.inputs["Metallic"].default_value = 0.0
    if "Transmission Weight" in bsdf.inputs:
        bsdf.inputs["Transmission Weight"].default_value = 0.92
    if "IOR" in bsdf.inputs:
        bsdf.inputs["IOR"].default_value = 1.333

    tex_coord = nodes.new("ShaderNodeTexCoord")
    tex_coord.location = (-910, -20)

    mapping = nodes.new("ShaderNodeMapping")
    mapping.location = (-700, -20)
    mapping.inputs["Scale"].default_value = (0.42, 0.42, 0.42)

    wave = nodes.new("ShaderNodeTexWave")
    wave.location = (-480, 90)
    wave.inputs["Scale"].default_value = 3.6
    wave.inputs["Detail"].default_value = 5.5
    wave.inputs["Distortion"].default_value = 5.5

    noise = nodes.new("ShaderNodeTexNoise")
    noise.location = (-480, -160)
    noise.inputs["Scale"].default_value = 10.0
    noise.inputs["Detail"].default_value = 7.0

    mix = nodes.new("ShaderNodeMix")
    mix.location = (-250, -20)
    mix.data_type = 'FLOAT'
    mix.inputs["Factor"].default_value = 0.55

    bump = nodes.new("ShaderNodeBump")
    bump.location = (-40, -130)
    bump.inputs["Strength"].default_value = 0.22

    links.new(tex_coord.outputs["Object"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], wave.inputs["Vector"])
    links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    links.new(wave.outputs["Fac"], mix.inputs[2])
    links.new(noise.outputs["Fac"], mix.inputs[3])
    links.new(mix.outputs["Result"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    return mat


def assign_material(obj, mat):
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)


def setup_world_and_lighting():
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0

    if 'BLENDER_EEVEE' in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items.keys():
        scene.render.engine = 'BLENDER_EEVEE'
    else:
        scene.render.engine = 'CYCLES'

    if hasattr(scene, 'eevee'):
        if hasattr(scene.eevee, 'use_shadows'):
            scene.eevee.use_shadows = True
        if hasattr(scene.eevee, 'taa_render_samples'):
            scene.eevee.taa_render_samples = 32

    world = scene.world
    if world is None:
        world = bpy.data.worlds.new("World")
        scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.50, 0.66, 0.92, 1.0)
        bg.inputs[1].default_value = 1.0

    bpy.ops.object.light_add(type='SUN', location=(35, -20, 55))
    sun = bpy.context.active_object
    sun.name = "Sun"
    sun.rotation_euler = (radians(35), radians(10), radians(25))
    sun.data.energy = 3.2


def create_ocean(water_mat):
    bpy.ops.mesh.primitive_plane_add(size=MAP_SIZE * 2.4, location=(0, 0, SEA_LEVEL))
    ocean = bpy.context.active_object
    ocean.name = "Ocean"
    assign_material(ocean, water_mat)


def build_lake_specs():
    lakes = []
    for _ in range(LAKE_COUNT):
        for _ in range(80):
            angle = random.uniform(0.0, 6.283185307)
            radius = random.uniform(30.0, ISLAND_RADIUS * 0.74)
            x = radius * cos(angle)
            y = radius * sin(angle)
            r = random.uniform(4.5, 8.0)
            depth = random.uniform(0.9, 1.6)

            # 避免与中心跑酷空地和其他湖泊重叠
            if sqrt(x * x + y * y) < 26.0:
                continue

            overlap = False
            for cx, cy, cr, _ in lakes:
                if sqrt((x - cx) ** 2 + (y - cy) ** 2) < (r + cr + 7.0):
                    overlap = True
                    break
            if overlap:
                continue

            lakes.append((x, y, r, depth))
            break
    return lakes


def create_island_terrain(ground_mat):
    bpy.ops.mesh.primitive_plane_add(size=MAP_SIZE, location=(0, 0, 0))
    terrain = bpy.context.active_object
    terrain.name = "IslandTerrain"

    subd = terrain.modifiers.new(name="Subd", type='SUBSURF')
    subd.levels = 6
    subd.render_levels = 6

    tex = bpy.data.textures.new("TerrainNoise", type='CLOUDS')
    tex.noise_scale = 10.0
    tex.noise_depth = 4

    disp = terrain.modifiers.new(name="Displace", type='DISPLACE')
    disp.texture = tex
    disp.strength = 2.6
    disp.mid_level = 0.5

    bpy.context.view_layer.objects.active = terrain
    bpy.ops.object.modifier_apply(modifier="Subd")
    bpy.ops.object.modifier_apply(modifier="Displace")

    # 塑造成岛：边缘下降入海，中心保持可跑区域
    mesh = terrain.data
    bm = bmesh.new()
    bm.from_mesh(mesh)

    for v in bm.verts:
        x = v.co.x
        y = v.co.y
        d = sqrt(x * x + y * y)
        t = min(max(d / ISLAND_RADIUS, 0.0), 2.0)

        if d <= ISLAND_RADIUS:
            v.co.z += 1.4 - (t ** 3.2) * 3.8
        else:
            edge_dist = d - ISLAND_RADIUS
            v.co.z += -2.6 - edge_dist * 0.18

    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    bpy.ops.object.shade_smooth()
    assign_material(terrain, ground_mat)
    return terrain


def carve_lakes_on_terrain(terrain, lakes):
    mesh = terrain.data
    bm = bmesh.new()
    bm.from_mesh(mesh)

    for v in bm.verts:
        x = v.co.x
        y = v.co.y

        for cx, cy, r, depth in lakes:
            dx = x - cx
            dy = y - cy
            dist = sqrt(dx * dx + dy * dy)
            if dist < r:
                falloff = 1.0 - (dist / r)
                carve = (falloff ** 2.2) * depth
                v.co.z -= carve

    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def create_lake_water_surfaces(lakes, water_mat):
    for i, (cx, cy, r, _) in enumerate(lakes):
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=40,
            radius=r * 0.93,
            depth=0.07,
            location=(cx, cy, LAKE_WATER_LEVEL),
        )
        lake = bpy.context.active_object
        lake.name = f"LakeWater_{i:02d}"
        assign_material(lake, water_mat)


def create_clearing(ground_mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=22, depth=0.16, location=(0, 0.10, 0))
    clearing = bpy.context.active_object
    clearing.name = "CentralClearing"
    assign_material(clearing, ground_mat)


def create_shore_rocks(rock_mat):
    for i in range(42):
        angle = random.uniform(0.0, 6.283185307)
        ring_r = random.uniform(ISLAND_RADIUS * 0.90, ISLAND_RADIUS * 1.08)
        x = ring_r * cos(angle)
        y = ring_r * sin(angle)

        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=random.uniform(1.2, 2.6), location=(x, y, random.uniform(-0.6, 1.0)))
        rock = bpy.context.active_object
        rock.name = f"ShoreRock_{i:02d}"
        rock.scale = (1.0, random.uniform(0.65, 1.25), random.uniform(0.45, 0.95))
        rock.rotation_euler = (random.uniform(0, 0.8), random.uniform(0, 0.8), random.uniform(0, 6.28))
        assign_material(rock, rock_mat)
        bpy.ops.object.shade_smooth()


def create_spawn_markers():
    runner_mat = new_material("RunnerSpawn_Mat", (0.07, 0.41, 0.90), 0.38, 0.0)
    tagger_mat = new_material("TaggerSpawn_Mat", (0.88, 0.12, 0.10), 0.38, 0.0)

    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=2.0, depth=0.25, location=(-34, 0.18, 34))
    runner = bpy.context.active_object
    runner.name = "RunnerSpawnMarker"
    assign_material(runner, runner_mat)

    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=2.0, depth=0.25, location=(34, 0.18, -34))
    tagger = bpy.context.active_object
    tagger.name = "TaggerSpawnMarker"
    assign_material(tagger, tagger_mat)


def create_parkour_elements(wood_mat, platform_mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(-20, 1.2, -10))
    ramp_a = bpy.context.active_object
    ramp_a.name = "Ramp_A"
    ramp_a.scale = (7.0, 0.5, 10.0)
    ramp_a.rotation_euler = (radians(14), 0, radians(8))
    assign_material(ramp_a, wood_mat)

    bpy.ops.mesh.primitive_cube_add(size=1, location=(-5, 3.6, 2))
    platform_mid = bpy.context.active_object
    platform_mid.name = "Platform_Mid"
    platform_mid.scale = (8.0, 0.5, 5.0)
    assign_material(platform_mid, platform_mat)

    bpy.ops.mesh.primitive_cube_add(size=1, location=(8, 2.5, -2))
    ramp_b = bpy.context.active_object
    ramp_b.name = "Ramp_B"
    ramp_b.scale = (6.0, 0.45, 9.0)
    ramp_b.rotation_euler = (radians(18), 0, radians(-12))
    assign_material(ramp_b, wood_mat)

    bpy.ops.mesh.primitive_cube_add(size=1, location=(18, 5.2, 11))
    high_platform = bpy.context.active_object
    high_platform.name = "Platform_High"
    high_platform.scale = (6.0, 0.5, 6.0)
    assign_material(high_platform, platform_mat)

    for i in range(9):
        x = random.uniform(-24, 24)
        y = random.uniform(-12, 18)
        z = random.uniform(0.65, 1.1)

        bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=random.uniform(0.6, 1.0), depth=random.uniform(1.0, 1.8), location=(x, y, z))
        stump = bpy.context.active_object
        stump.name = f"Stump_{i:02d}"
        assign_material(stump, wood_mat)


def create_tree_prototype(trunk_mat, leaf_mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.20, depth=2.6, location=(0, 0, 1.3))
    trunk = bpy.context.active_object
    trunk.name = "TreePrototype_Trunk"
    assign_material(trunk, trunk_mat)

    bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=1.35, depth=3.2, location=(0, 0, 3.4))
    crown = bpy.context.active_object
    crown.name = "TreePrototype_Crown"
    assign_material(crown, leaf_mat)

    bpy.ops.object.select_all(action='DESELECT')
    trunk.select_set(True)
    crown.select_set(True)
    bpy.context.view_layer.objects.active = trunk
    bpy.ops.object.join()

    tree = bpy.context.active_object
    tree.name = "TreePrototype"
    return tree


def create_rock_prototype(rock_mat):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.9, location=(0, 0, 0.9))
    rock = bpy.context.active_object
    rock.name = "RockPrototype"

    rock.scale = (1.0, 0.8, 0.65)
    assign_material(rock, rock_mat)
    bpy.ops.object.shade_smooth()
    return rock


def create_bush_prototype(bush_mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=0.8, location=(0, 0, 0.7))
    bush = bpy.context.active_object
    bush.name = "BushPrototype"
    bush.scale = (1.0, 1.2, 0.7)
    assign_material(bush, bush_mat)
    bpy.ops.object.shade_smooth()
    return bush


def inside_lake(x, y, lakes, margin=0.0):
    for cx, cy, r, _ in lakes:
        if sqrt((x - cx) ** 2 + (y - cy) ** 2) < (r + margin):
            return True
    return False


def random_forest_point(lakes, min_r=22.0, max_r=ISLAND_RADIUS * 0.90):
    for _ in range(100):
        angle = random.uniform(0.0, 6.283185307)
        radius = random.uniform(min_r, max_r)
        x = radius * cos(angle)
        y = radius * sin(angle)

        if inside_lake(x, y, lakes, margin=2.2):
            continue
        return x, y

    # 兜底
    return random.uniform(-20, 20), random.uniform(-20, 20)


def scatter_assets(tree_proto, rock_proto, bush_proto, lakes):
    for i in range(TREE_COUNT):
        x, y = random_forest_point(lakes)

        tree = tree_proto.copy()
        tree.data = tree_proto.data
        bpy.context.collection.objects.link(tree)

        tree.location = (x, y, random.uniform(0.5, 2.2))
        s = random.uniform(0.85, 1.9)
        tree.scale = (s, s, random.uniform(0.9, 1.6) * s)
        tree.rotation_euler[2] = random.uniform(0, 6.28)
        tree.name = f"Tree_{i:03d}"

    for i in range(ROCK_COUNT):
        x, y = random_forest_point(lakes, 16.0, ISLAND_RADIUS * 0.92)
        rock = rock_proto.copy()
        rock.data = rock_proto.data
        bpy.context.collection.objects.link(rock)

        rock.location = (x + random.uniform(-2.2, 2.2), y + random.uniform(-2.2, 2.2), random.uniform(0.2, 1.3))
        s = random.uniform(0.55, 1.8)
        rock.scale = (s, s * random.uniform(0.7, 1.3), s * random.uniform(0.45, 0.9))
        rock.rotation_euler = (random.uniform(0, 1.1), random.uniform(0, 1.1), random.uniform(0, 6.28))
        rock.name = f"Rock_{i:03d}"

    for i in range(BUSH_COUNT):
        x, y = random_forest_point(lakes, 14.0, ISLAND_RADIUS * 0.91)
        bush = bush_proto.copy()
        bush.data = bush_proto.data
        bpy.context.collection.objects.link(bush)

        bush.location = (x + random.uniform(-1.5, 1.5), y + random.uniform(-1.5, 1.5), random.uniform(0.2, 1.1))
        s = random.uniform(0.55, 1.4)
        bush.scale = (s, s * random.uniform(0.9, 1.4), s * random.uniform(0.5, 0.9))
        bush.rotation_euler[2] = random.uniform(0, 6.28)
        bush.name = f"Bush_{i:03d}"


def add_camera():
    bpy.ops.object.camera_add(location=(96, -92, 76), rotation=(radians(56), 0, radians(46)))
    camera = bpy.context.active_object
    camera.name = "OverviewCamera"
    bpy.context.scene.camera = camera


def main():
    ensure_output_dir(OUTPUT_BLEND)
    clear_scene()
    setup_world_and_lighting()

    # 材质（增强着色）
    ground_mat = create_terrain_material("Ground_Mat")
    clearing_mat = new_material("Clearing_Mat", (0.30, 0.40, 0.23), roughness=0.96)
    rock_mat = create_foliage_material("Rock_Mat", (0.26, 0.28, 0.28), (0.39, 0.41, 0.40))
    wood_mat = create_foliage_material("Wood_Mat", (0.22, 0.14, 0.07), (0.34, 0.24, 0.11))
    leaf_mat = create_foliage_material("Leaf_Mat", (0.10, 0.30, 0.10), (0.17, 0.48, 0.16))
    platform_mat = new_material("Platform_Mat", (0.25, 0.27, 0.30), roughness=0.86)
    bush_mat = create_foliage_material("Bush_Mat", (0.10, 0.34, 0.12), (0.18, 0.48, 0.19))
    water_mat = create_water_material("Water_Mat")

    create_ocean(water_mat)
    terrain = create_island_terrain(ground_mat)

    lakes = build_lake_specs()
    carve_lakes_on_terrain(terrain, lakes)
    create_lake_water_surfaces(lakes, water_mat)

    # 按需求移除中间板件与空中辅助物：不再生成中心板、出生标记与跑酷板件
    create_shore_rocks(rock_mat)

    tree_proto = create_tree_prototype(wood_mat, leaf_mat)
    rock_proto = create_rock_prototype(rock_mat)
    bush_proto = create_bush_prototype(bush_mat)

    scatter_assets(tree_proto, rock_proto, bush_proto, lakes)
    add_camera()

    # 保留原型对象，但放到偏远位置便于后续替换
    tree_proto.location = (1000, 1000, 0)
    rock_proto.location = (1005, 1000, 0)
    bush_proto.location = (1010, 1000, 0)

    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND)
    print(f"[OK] 小岛森林原型地图已生成: {OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
