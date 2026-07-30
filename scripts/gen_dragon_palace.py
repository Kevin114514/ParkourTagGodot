"""生成《Mario Kart 8 Deluxe》对战场地 Dragon Palace（龙之宫殿）。

空间依据公开关卡俯视图、MarioWiki 内外景截图，以及多段完整游玩视频重建：
- 南侧是近八角形四合院庭院，两尊 Gobblegut 龙像隔着中央纹章相对。
- 北侧是平坦的圆形木质大厅，而不是下沉式多环竞技场。
- 庭院到宫殿共有四条主要路径：正面两道屏风门通一层，左右贴墙长坡通二层。
- 室内二层是沿外墙的圆环回廊，两条对称弧坡回落到一层，形成闭合循环。
"""
import json
import math
from pathlib import Path

objects = []
lights = []

HALL_Z = -24.0
HALL_R = 22.5
UPPER_Y = 5.0
COURT_Z = 17.0


def add(kind, name, position, **kwargs):
    item = {"type": kind, "name": name, "position": [round(v, 4) for v in position]}
    item.update(kwargs)
    objects.append(item)
    return item


def box(name, position, size, material, collision=True, rotation=None, visible=True):
    data = {"size": [round(v, 4) for v in size], "material_id": material}
    if not collision:
        data["collision"] = "none"
    if rotation is not None:
        data["rotation_degrees"] = [round(v, 4) for v in rotation]
    if not visible:
        data["visible"] = False
    return add("box", name, position, **data)


def cylinder(name, position, radius, height, material, collision=False, rotation=None, visible=True):
    data = {"radius": radius, "height": height, "material_id": material}
    if not collision:
        data["collision"] = "none"
    if rotation is not None:
        data["rotation_degrees"] = [round(v, 4) for v in rotation]
    if not visible:
        data["visible"] = False
    return add("cylinder", name, position, **data)


def sphere(name, position, radius, material, collision=False, scale=None, visible=True):
    data = {"radius": radius, "material_id": material}
    if not collision:
        data["collision"] = "none"
    if scale is not None:
        data["scale"] = [round(v, 4) for v in scale]
    if not visible:
        data["visible"] = False
    return add("sphere", name, position, **data)


def ellipsoid(name, position, scale, material, collision=False, visible=True):
    return sphere(name, position, 1.0, material, collision, scale, visible)


def model(name, position, path, scale, rotation, material=None, collision_shapes=None):
    data = {
        "path": path,
        "scale": scale,
        "rotation_degrees": rotation,
        "collision": "proxy" if collision_shapes else "none",
    }
    if material:
        data["material_id"] = material
    if collision_shapes:
        data["collision_shapes"] = collision_shapes
    return add("model", name, position, **data)


def covered(item, proxy_name):
    """标记可见细节由同一复合物的简化代理碰撞覆盖。"""
    item["collision"] = "none"
    item["collision_proxy"] = proxy_name
    return item


def path_mesh(name, points, width, material, thickness=0.42):
    return add("path_mesh", name, (0.0, 0.0, 0.0),
               points=[[round(v, 4) for v in point] for point in points],
               width=width, thickness=thickness, material_id=material,
               collision="trimesh")


def path_segment(name, start, end, width, thickness, material, collision=True,
                 extend_start=0.0, extend_end=0.0):
    x1, y1, z1 = start
    x2, y2, z2 = end
    dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    length = max(math.sqrt(dx * dx + dy * dy + dz * dz), 0.001)
    ux, uy, uz = dx / length, dy / length, dz / length
    x1, y1, z1 = x1 - ux * extend_start, y1 - uy * extend_start, z1 - uz * extend_start
    x2, y2, z2 = x2 + ux * extend_end, y2 + uy * extend_end, z2 + uz * extend_end
    horizontal = math.hypot(dx, dz)
    yaw = math.degrees(math.atan2(dx, dz))
    pitch = -math.degrees(math.atan2(dy, max(horizontal, 0.001)))
    return box(name, ((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2),
               (width, thickness, length + extend_start + extend_end), material, collision,
               (pitch, yaw, 0.0))


def surface_segment(name, start, end, width, thickness, material, collision=True,
                    extend_start=0.0, extend_end=0.0):
    """以输入点作为行走表面而非盒体中心，消除坡脚台阶。"""
    x1, y1, z1 = start
    x2, y2, z2 = end
    dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    horizontal = max(math.hypot(dx, dz), 0.001)
    slope = math.atan2(dy, horizontal)
    hx, hz = dx / horizontal, dz / horizontal
    normal = (-math.sin(slope) * hx, math.cos(slope), -math.sin(slope) * hz)
    offset = tuple(-component * thickness / 2 for component in normal)
    shifted_start = tuple(start[i] + offset[i] for i in range(3))
    shifted_end = tuple(end[i] + offset[i] for i in range(3))
    return path_segment(name, shifted_start, shifted_end, width, thickness, material,
                        collision, extend_start, extend_end)


def _rail_points(points, width, side, height=0.9):
    offset = side * (width / 2 - 0.14)
    result = []
    for index, point in enumerate(points):
        directions = []
        if index > 0:
            previous = points[index - 1]
            length = max(math.hypot(point[0] - previous[0], point[2] - previous[2]), 0.001)
            directions.append(((point[0] - previous[0]) / length,
                               (point[2] - previous[2]) / length))
        if index + 1 < len(points):
            following = points[index + 1]
            length = max(math.hypot(following[0] - point[0], following[2] - point[2]), 0.001)
            directions.append(((following[0] - point[0]) / length,
                               (following[2] - point[2]) / length))
        dx = sum(direction[0] for direction in directions)
        dz = sum(direction[1] for direction in directions)
        length = max(math.hypot(dx, dz), 0.001)
        dx, dz = dx / length, dz / length
        result.append((point[0] - dz * offset, point[1] + height / 2,
                       point[2] + dx * offset))
    return result


def smooth_points(points, subdivisions=4):
    """用单调高程 Catmull-Rom 加密控制线，避免道路急折。"""
    result = []
    for index in range(len(points) - 1):
        p0 = points[max(0, index - 1)]
        p1 = points[index]
        p2 = points[index + 1]
        p3 = points[min(len(points) - 1, index + 2)]
        for step in range(subdivisions):
            t = step / subdivisions
            t2, t3 = t * t, t * t * t
            values = []
            for axis in range(3):
                value = 0.5 * ((2 * p1[axis]) + (-p0[axis] + p2[axis]) * t
                               + (2 * p0[axis] - 5 * p1[axis] + 4 * p2[axis] - p3[axis]) * t2
                               + (-p0[axis] + 3 * p1[axis] - 3 * p2[axis] + p3[axis]) * t3)
                if axis == 1:
                    value = max(min(p1[axis], p2[axis]), min(max(p1[axis], p2[axis]), value))
                values.append(value)
            result.append(tuple(values))
    result.append(tuple(points[-1]))
    return result


def _joint_extensions(points, width):
    extensions = [0.12] * len(points)
    for index in range(1, len(points) - 1):
        previous = points[index - 1]
        point = points[index]
        following = points[index + 1]
        a = (point[0] - previous[0], point[2] - previous[2])
        b = (following[0] - point[0], following[2] - point[2])
        length_a = max(math.hypot(*a), 0.001)
        length_b = max(math.hypot(*b), 0.001)
        dot = max(-1.0, min(1.0, (a[0] * b[0] + a[1] * b[1]) / (length_a * length_b)))
        turn = math.acos(dot)
        extensions[index] = min(width * 0.14, width * 0.5 * math.tan(turn / 2) + 0.08)
    return extensions


def curved_path(name, points, width, material, rails=True):
    path_mesh(f"{name}Deck", points, width, material, 0.42)
    if rails:
        for side in (-1, 1):
            rail = _rail_points(points, width, side)
            for i in range(len(rail) - 1):
                path_segment(f"{name}Rail{side}_{i:02d}", rail[i], rail[i + 1],
                             0.28, 0.9, "red_lacquer", True, 0.12, 0.12)


def circle_point(radius, angle_deg, y=0.0):
    angle = math.radians(angle_deg)
    return (math.sin(angle) * radius, y, HALL_Z + math.cos(angle) * radius)


def ring(name, radius, y, width, material, segments=48, collision=True, thickness=0.42,
         openings=()):
    points = [circle_point(radius, i * 360 / segments, y) for i in range(segments)]
    overlap = width * 0.5 * math.tan(math.pi / segments) + 0.08
    for i in range(segments):
        angle = (i + 0.5) * 360 / segments
        if angle_near(angle, openings):
            continue
        path_segment(f"{name}{i:02d}", points[i], points[(i + 1) % segments], width, thickness,
                     material, collision, overlap, overlap)


def angle_near(angle, targets):
    return any(abs((angle - target + 180) % 360 - 180) < span for target, span in targets)


def segmented_wall(name, radius, y, height, material, segments=56, openings=(), width=0.72,
                   collision=True):
    for i in range(segments):
        angle = (i + 0.5) * 360 / segments
        if angle_near(angle, openings):
            continue
        a = circle_point(radius, i * 360 / segments, y)
        b = circle_point(radius, (i + 1) * 360 / segments, y)
        path_segment(f"{name}{i:02d}", a, b, width, height, material, collision,
                     width * 0.65, width * 0.65)


def arc_ramp(name, radius, angle_start, angle_end, y_start, y_end, width, material, steps=18,
             rails=False):
    points = []
    for i in range(steps + 1):
        t = i / steps
        angle = angle_start + (angle_end - angle_start) * t
        points.append(circle_point(radius, angle, y_start + (y_end - y_start) * t))
    curved_path(name, points, width, material, rails)


def lantern(name, x, y, z, scale=1.0, lit=False):
    proxy_name = f"{name}Proxy"
    model(name, (x, y + 0.18 * scale, z),
          "../assets/dragon_palace/decor/hanging_lantern_kaylousberg_cc0.glb",
          [0.58 * scale, 0.58 * scale, 0.58 * scale], [0.0, 0.0, 0.0],
          None, [{"type": "box", "name": proxy_name,
                  "position": [0.0, -0.604, 0.0], "size": [0.70, 1.50, 0.70]}])
    if lit:
        lights.append({
            "light_type": "omni", "name": f"{name}Light", "position": [x, y, z],
            "color": [1.0, 0.30, 0.08], "energy": 0.85, "range": 5.5, "shadow": False,
        })


def screen_door(name, x, z, width=5.6):
    # 门扇收进两侧，视觉开口与实际碰撞一致；不再允许角色穿过整张纸门。
    panel_width = width * 0.22
    offset = width / 2 - panel_width / 2
    for side in (-1, 1):
        panel_x = x + side * offset
        proxy_name = f"{name}Paper{side}"
        box(proxy_name, (panel_x, 1.65, z),
            (panel_width, 3.25, 0.16), "screen_paper", True)
        for i in range(3):
            px = panel_x - panel_width / 2 + panel_width * i / 2
            covered(box(f"{name}V{side}_{i}", (px, 1.65, z - 0.125),
                        (0.08, 3.25, 0.08), "wood_dark", False), proxy_name)
        for i in range(7):
            py = 0.10 + i * 0.53
            covered(box(f"{name}H{side}_{i}", (panel_x, py, z - 0.125),
                        (panel_width, 0.08, 0.08), "wood_dark", False), proxy_name)


def lattice_panel(name, center, size, rotation=None):
    x, y, z = center
    w, h = size
    proxy_name = f"{name}Back"
    box(proxy_name, center, (w, h, 0.24), "window_dark", True, rotation)
    for i in range(6):
        px = x - w / 2 + w * i / 5
        covered(box(f"{name}V{i}", (px, y, z - 0.165), (0.09, h, 0.08),
                    "window_lattice", False, rotation), proxy_name)
    for i in range(5):
        py = y - h / 2 + h * i / 4
        covered(box(f"{name}H{i}", (x, py, z - 0.165), (w, 0.09, 0.08),
                    "window_lattice", False, rotation), proxy_name)


def pagoda_roof(name, cx, cz, half_x, half_z, y, material):
    proxy_name = f"{name}Proxy"
    covered(box(f"{name}Main", (cx, y, cz),
                (half_x * 2 + 2.6, 0.52, half_z * 2 + 2.6), material, False), proxy_name)
    covered(box(f"{name}RidgeX", (cx, y + 0.38, cz),
                (half_x * 2 + 3.2, 0.24, 0.34), "gold_trim", False), proxy_name)
    covered(box(f"{name}RidgeZ", (cx, y + 0.42, cz),
                (0.34, 0.24, half_z * 2 + 3.2), "gold_trim", False), proxy_name)
    for sx in (-1, 1):
        for sz in (-1, 1):
            covered(sphere(f"{name}Corner{sx}{sz}",
                           (cx + sx * (half_x + 1.35), y + 0.25,
                            cz + sz * (half_z + 1.35)),
                           0.38, "jade_trim", False, (1.8, 0.45, 1.8)), proxy_name)
    box(proxy_name, (cx, y + 0.18, cz),
        (half_x * 2 + 3.5, 1.05, half_z * 2 + 3.5), material, True, visible=False)


def side_hall(name, x, z, length):
    box(f"{name}Body", (x, 2.15, z), (5.8, 4.3, length), "red_wall", True)
    face_x = x - math.copysign(2.96, x)
    for i in range(max(1, int(length // 5))):
        pz = z - length / 2 + 2.8 + i * 5.0
        covered(box(f"{name}Window{i}", (face_x, 2.35, pz),
                    (0.12, 2.1, 3.4), "window_lattice", False), f"{name}Body")
        lantern(f"{name}Lantern{i}", face_x - math.copysign(0.25, x), 3.65, pz, 0.9, i % 2 == 0)
    roof_proxy = f"{name}RoofProxy"
    covered(box(f"{name}Roof", (x, 4.75, z), (8.2, 0.56, length + 2.4),
                "roof_red", False, (0.0, 0.0, -math.copysign(5.0, x))), roof_proxy)
    covered(box(f"{name}Ridge", (x, 5.15, z), (0.30, 0.28, length + 3.0),
                "gold_trim", False), roof_proxy)
    box(roof_proxy, (x, 4.95, z), (8.6, 1.1, length + 3.2),
        "roof_red", True, visible=False)


def dragon(name, x, z, facing, body_mat, mane_mat, belly_mat):
    def px(local_x):
        return x + facing * local_x

    box(f"{name}Base", (x, 0.72, z), (8.0, 1.44, 5.8), "statue_base", True)
    box(f"{name}BaseTop", (x, 1.49, z), (8.5, 0.22, 6.3), "gold_trim", False)
    for sx in (-1, 1):
        for sz in (-1, 1):
            box(f"{name}Foot{sx}{sz}", (x + sx * 3.25, 0.55, z + sz * 2.25),
                (0.72, 1.0, 0.72), "statue_base", True)

    ellipsoid(f"{name}Haunch", (px(-1.85), 3.15, z), (2.7, 2.35, 2.55), body_mat)
    ellipsoid(f"{name}Belly", (px(-0.15), 4.15, z), (2.15, 2.55, 2.15), body_mat)
    ellipsoid(f"{name}BellyPlate", (px(0.75), 4.05, z), (1.25, 2.0, 1.35), belly_mat)
    ellipsoid(f"{name}Chest", (px(1.25), 5.35, z), (1.65, 2.0, 1.75), body_mat)
    box(f"{name}BodyClip", (px(-0.4), 3.7, z), (6.5, 6.2, 4.8), body_mat, True, visible=False)

    for side in (-1, 1):
        ellipsoid(f"{name}HindLeg{side}", (px(-1.55), 2.15, z + side * 1.85),
                  (1.35, 1.15, 1.0), body_mat)
        ellipsoid(f"{name}HindPaw{side}", (px(-0.45), 1.55, z + side * 2.0),
                  (1.25, 0.55, 0.82), body_mat)
        for claw in range(3):
            ellipsoid(f"{name}HindClaw{side}_{claw}",
                      (px(0.55 + claw * 0.14), 1.42, z + side * (2.0 + (claw - 1) * 0.24)),
                      (0.38, 0.12, 0.13), "ivory")

    ellipsoid(f"{name}Neck0", (px(1.75), 6.1, z), (1.25, 1.35, 1.3), body_mat)
    ellipsoid(f"{name}Neck1", (px(2.05), 7.0, z), (1.15, 1.25, 1.2), body_mat)
    ellipsoid(f"{name}Head", (px(2.65), 7.75, z), (1.55, 1.3, 1.5), body_mat)
    ellipsoid(f"{name}Muzzle", (px(4.0), 7.45, z), (1.45, 0.82, 1.02), body_mat)
    ellipsoid(f"{name}Jaw", (px(3.65), 6.92, z), (1.25, 0.42, 0.92), belly_mat)
    box(f"{name}HeadClip", (px(3.0), 7.35, z), (3.8, 2.8, 3.0), body_mat, True, visible=False)

    for side in (-1, 1):
        sphere(f"{name}Eye{side}", (px(3.25), 7.95, z + side * 0.76), 0.18, "eye_glow")
        ellipsoid(f"{name}Brow{side}", (px(3.05), 8.2, z + side * 0.72),
                  (0.65, 0.25, 0.30), mane_mat)
        cylinder(f"{name}Horn{side}", (px(1.95), 8.75, z + side * 0.65), 0.18, 2.15,
                 "ivory", False, (0.0, 0.0, -facing * 48.0))
        cylinder(f"{name}Whisker{side}", (px(4.55), 7.15, z + side * 0.72), 0.055, 2.6,
                 "gold_trim", False, (62.0, 0.0, side * 30.0))
    for i, (lx, ly, radius) in enumerate(((1.7, 8.0, 0.48), (1.1, 7.4, 0.44),
                                           (0.6, 6.7, 0.40), (0.0, 6.0, 0.36))):
        sphere(f"{name}Mane{i}", (px(lx), ly, z), radius, mane_mat, False, (0.8, 1.45, 1.1))

    for side in (-1, 1):
        cylinder(f"{name}ForeArm{side}", (px(2.05), 5.0, z + side * 1.42), 0.40, 2.6,
                 body_mat, False, (side * 8.0, 0.0, -facing * 28.0))
        ellipsoid(f"{name}ForePaw{side}", (px(2.75), 4.05, z + side * 1.58),
                  (0.75, 0.62, 0.72), body_mat)
        for claw in range(3):
            ellipsoid(f"{name}ForeClaw{side}_{claw}",
                      (px(3.45 + claw * 0.16), 3.95, z + side * (1.58 + (claw - 1) * 0.22)),
                      (0.34, 0.11, 0.12), "ivory")

    tail = [(-2.5, 4.1), (-3.4, 5.1), (-3.9, 6.4), (-3.9, 7.8), (-3.3, 9.1),
            (-2.2, 10.0), (-0.9, 10.35), (0.25, 10.0), (0.95, 9.2)]
    for i, (lx, ly) in enumerate(tail):
        radius = 1.02 - i * 0.085
        ellipsoid(f"{name}Tail{i}", (px(lx), ly, z), (radius, radius * 1.12, radius), body_mat)
        if i % 2 == 1:
            sphere(f"{name}TailSpine{i}", (px(lx - 0.12), ly + radius, z), 0.25,
                   mane_mat, False, (0.65, 1.35, 0.72))
    box(f"{name}TailClip", (px(-3.1), 6.7, z), (2.8, 7.2, 2.8), body_mat, True, visible=False)


texture_root = "../assets/dragon_palace/textures"

def pbr(prefix, color, roughness, uv_scale=(2.0, 2.0, 2.0)):
    return {
        "color": color,
        "albedo_texture": f"{texture_root}/{prefix}_diff.jpg",
        "normal_texture": f"{texture_root}/{prefix}_normal.jpg",
        "roughness_texture": f"{texture_root}/{prefix}_rough.jpg",
        "roughness": roughness,
        "uv_scale": list(uv_scale),
    }


materials = {
    "foundation": {"color": [0.24, 0.25, 0.24], "roughness": 0.98},
    "stone_floor": pbr("stone", [0.86, 0.84, 0.78], 0.88, (1.15, 1.15, 1.15)),
    "stone_line": {"color": [0.58, 0.46, 0.20], "roughness": 0.74},
    "statue_base": pbr("stone", [0.48, 0.54, 0.52], 0.86, (1.7, 1.7, 1.7)),
    "wood_floor": pbr("wood", [0.78, 0.56, 0.36], 0.68, (1.4, 1.4, 1.4)),
    "wood_floor_dark": pbr("wood", [0.50, 0.29, 0.15], 0.72, (1.4, 1.4, 1.4)),
    "red_lacquer": pbr("red_plaster", [0.75, 0.11, 0.07], 0.42, (2.0, 2.0, 2.0)),
    "red_wall": pbr("red_plaster", [0.60, 0.11, 0.07], 0.60, (2.2, 2.2, 2.2)),
    "yellow_plaster": pbr("yellow_plaster", [0.92, 0.72, 0.34], 0.80, (2.0, 2.0, 2.0)),
    "green_panel": {"color": [0.08, 0.29, 0.20], "roughness": 0.54},
    "wood_dark": {"color": [0.17, 0.052, 0.025], "roughness": 0.66},
    "window_dark": {"color": [0.07, 0.12, 0.10], "roughness": 0.48},
    "window_lattice": {"color": [0.28, 0.07, 0.035], "roughness": 0.56},
    "screen_paper": {"color": [0.94, 0.81, 0.51, 0.82], "roughness": 0.72},
    "roof_jade": pbr("roof", [0.10, 0.48, 0.30], 0.46, (2.5, 2.5, 2.5)),
    "jade_trim": pbr("roof", [0.06, 0.30, 0.20], 0.50, (2.5, 2.5, 2.5)),
    "roof_red": pbr("roof", [0.67, 0.14, 0.08], 0.54, (2.5, 2.5, 2.5)),
    "gold": {"color": [0.98, 0.61, 0.055], "roughness": 0.25, "metallic": 0.72},
    "gold_trim": {"color": [0.78, 0.46, 0.055], "roughness": 0.32, "metallic": 0.58},
    "dragon_gold": {"color": [0.89, 0.58, 0.08], "roughness": 0.28, "metallic": 0.64},
    "dragon_stone": {"color": [0.60, 0.65, 0.63], "roughness": 0.74, "metallic": 0.04},
    "mane_gold": {"color": [0.97, 0.74, 0.16], "roughness": 0.30, "metallic": 0.56},
    "mane_stone": {"color": [0.45, 0.52, 0.50], "roughness": 0.80},
    "belly_gold": {"color": [0.96, 0.84, 0.49], "roughness": 0.42, "metallic": 0.30},
    "belly_stone": {"color": [0.74, 0.77, 0.73], "roughness": 0.74},
    "ivory": {"color": [0.95, 0.88, 0.65], "roughness": 0.48},
    "lantern_red": {"color": [0.96, 0.07, 0.025], "emission": [1.0, 0.07, 0.015],
                    "emission_energy": 1.35, "roughness": 0.34},
    "lantern_cream": {"color": [0.96, 0.88, 0.60], "emission": [1.0, 0.80, 0.34],
                      "emission_energy": 1.2, "roughness": 0.38},
    "eye_glow": {"color": [0.98, 0.91, 0.20], "emission": [1.0, 0.72, 0.08],
                 "emission_energy": 2.2, "roughness": 0.18},
    "banner_red": {"color": [0.69, 0.035, 0.02], "roughness": 0.56},
    "mountain": {"color": [0.31, 0.43, 0.36], "roughness": 0.96},
    "leaf": {"color": [0.12, 0.35, 0.13], "roughness": 0.88},
}

# 密闭安全壳：底板与四壁在所有边和角重叠1米，不留坠落缝。
box("SafetyFoundation", (0.0, -1.0, 1.0), (69.0, 1.6, 100.0),
    "foundation", True, visible=False)
box("BoundaryWallWest", (-33.5, 8.0, 1.0), (1.2, 20.0, 100.0),
    "foundation", True, visible=False)
box("BoundaryWallEast", (33.5, 8.0, 1.0), (1.2, 20.0, 100.0),
    "foundation", True, visible=False)
box("BoundaryWallNorth", (0.0, 8.0, -48.0), (68.2, 20.0, 1.2),
    "foundation", True, visible=False)
box("BoundaryWallSouth", (0.0, 8.0, 50.0), (68.2, 20.0, 1.2),
    "foundation", True, visible=False)

# 庭院改为单一连续石板：取代此前互相覆盖的矩形、圆地板、北前坪和116条薄纹样，
# 从根源消除广场 Z-fighting、重复地面碰撞与毫米级绊脚边。
box("CourtyardMain", (0.0, -0.11, 23.75), (48.0, 0.34, 50.5),
    "stone_floor", True)

dragon_model_path = "../assets/dragon_palace/chinese_dragon_cc0.glb"
# 每座龙像（模型+底座）只使用一个大长方体，随父节点4.55倍缩放。
# 世界尺寸约10.01 × 7.28 × 7.28米，从地面完整包住台座、角、爪和高卷尾。
dragon_collision = [
    {"type": "box", "name": "DragonCollision", "position": [0.0, -0.16, 0.0],
     "size": [2.20, 1.60, 1.60]},
]
for name, x, yaw, material in (
    ("WestStoneDragon", -12.2, 0.0, "dragon_stone"),
    ("EastGoldenDragon", 12.2, 180.0, "dragon_gold"),
):
    covered(box(f"{name}Base", (x, 0.72, 17.0), (9.2, 1.44, 6.4),
                "statue_base", False), name)
    covered(box(f"{name}BaseTop", (x, 1.50, 17.0), (9.7, 0.22, 6.9),
                "gold_trim", False), name)
    model(name, (x, 4.28, 17.0), dragon_model_path, [4.55, 4.55, 4.55],
          [0.0, yaw, 0.0], material, dragon_collision)

side_hall("WestCourtyardHall", -27.2, 22.0, 32.0)
side_hall("EastCourtyardHall", 27.2, 22.0, 32.0)
for side in (-1, 1):
    # 坡脚保留完整净空，两侧用实体门墩和连廊收边，避免视觉上直接看到地图外。
    for suffix, center_x, wall_width in (("Inner", 15.0, 1.0), ("Outer", 27.0, 1.0)):
        box(f"NorthYellowWall{side}{suffix}", (side * center_x, 1.35, 3.0),
            (wall_width, 2.7, 0.62), "yellow_plaster", True)
        box(f"NorthYellowCap{side}{suffix}", (side * center_x, 2.82, 3.0),
            (wall_width + 0.5, 0.24, 1.1), "roof_red", True)
    gate_x = side * 21.0
    box(f"RampGateBeam{side}", (gate_x, 4.35, 3.0),
        (11.0, 0.46, 0.72), "red_lacquer", True)
    for pillar_x in (16.0, 26.0):
        cylinder(f"RampGatePillar{side}_{pillar_x:g}", (side * pillar_x, 2.15, 3.0),
                 0.34, 4.3, "red_lacquer", True)
    box(f"RampGateRoof{side}", (gate_x, 5.05, 3.0),
        (12.2, 0.50, 2.4), "roof_jade", True)
    for i, window_x in enumerate((15.0, 27.0)):
        cylinder(f"NorthRoundWindow{side}_{i}", (side * window_x, 1.55, 2.64),
                 0.32, 0.10, "window_dark", True, (90.0, 0.0, 0.0))

for side in (-1, 1):
    box(f"SouthReturnWall{side}", (side * 17.0, 1.8, 40.5), (18.0, 3.6, 0.72), "red_wall", True)
    box(f"SouthReturnRoof{side}", (side * 17.0, 4.15, 40.5),
        (20.0, 0.48, 4.0), "roof_red", True)
    # 可见角楼填住侧殿与南墙交界的两个空角。
    corner_x = side * 28.8
    box(f"SouthCornerTower{side}Body", (corner_x, 2.35, 39.3),
        (7.2, 4.7, 7.2), "red_wall", True)
    pagoda_roof(f"SouthCornerTower{side}Roof", corner_x, 39.3, 4.0, 4.0,
                5.35, "roof_jade")
box("SouthGateBeam", (0.0, 4.25, 40.5), (15.0, 0.85, 0.85), "red_lacquer", True)
for x in (-7.0, 7.0):
    cylinder(f"SouthGateColumn{x:g}", (x, 2.25, 40.5), 0.44, 4.5, "red_lacquer", True)
box("SouthGateClosedDoors", (0.0, 1.6, 40.5), (13.0, 3.2, 0.65), "green_panel", True)
pagoda_roof("SouthGateRoof", 0.0, 40.5, 9.0, 2.5, 5.55, "roof_jade")
box("SouthGateSign", (0.0, 4.2, 40.0), (4.8, 1.25, 0.12), "gold", True)
for i, x in enumerate((-6.0, -3.0, 0.0, 3.0, 6.0)):
    lantern(f"SouthGateLantern{i}", x, 3.55, 39.7, 0.9, i in (0, 2, 4))

cylinder("HallGroundFloor", (0.0, -0.12, HALL_Z), HALL_R, 0.36,
         "wood_floor", True)
# 门桥略高于大厅和庭院，仅作为明确的门槛过渡；移除原来的264条相交薄片地纹。
box("HallDoorBridge", (0.0, -0.08, -2.15), (17.0, 0.36, 3.6),
    "wood_floor_dark", True)

low_openings = ((0, 25),)
upper_openings = ((0, 18), (90, 16), (270, 16))
segmented_wall("HallWallLow", HALL_R + 0.15, 2.25, 4.5, "red_wall", 56, low_openings, 0.78)
segmented_wall("HallWallMid", HALL_R + 0.15, 5.7, 2.4, "window_lattice", 56, upper_openings, 0.72)
# 高墙也必须复制东西二层出口；否则楼板以上只有 1.65m，所有角色都会顶头。
segmented_wall("HallWallHigh", HALL_R + 0.15, 8.8, 3.8, "window_lattice", 56,
               ((0, 14), (90, 16), (270, 16)), 0.72)
ring("HallBeamLow", HALL_R + 0.2, 4.45, 0.55, "wood_dark", 56, True, 0.48,
     ((0, 18), (90, 16), (270, 16)))
ring("HallBeamMid", HALL_R + 0.2, 6.95, 0.55, "gold_trim", 56, True, 0.42,
     ((0, 18), (90, 16), (270, 16)))
ring("HallBeamTop", HALL_R + 0.2, 10.75, 0.62, "gold_trim", 56, True, 0.46,
     ((0, 18), (90, 16), (270, 16)))

for angle in range(0, 360, 20):
    if angle_near(angle, ((0, 16), (90, 15), (270, 15))):
        continue
    x, _, z = circle_point(20.8, angle, 5.4)
    cylinder(f"HallOuterColumn{angle}", (x, 5.4, z), 0.40, 10.8, "red_lacquer", True)

ring("UpperGallery", 17.5, UPPER_Y, 8.6, "wood_floor", 52, True, 0.46)
segmented_wall("UpperInnerRail", 13.05, UPPER_Y + 0.66, 1.18, "red_lacquer", 52,
               ((110, 19), (250, 19)), 0.24)
for angle in range(0, 360, 30):
    if angle in (90, 270):
        continue
    x, _, z = circle_point(20.5, angle, 2.35)
    cylinder(f"GallerySupport{angle}", (x, 2.35, z), 0.30, 4.7, "red_lacquer", True)

# 二楼到一楼改成连续螺旋样条：先在同高程穿过环廊内缘，再平滑转弯下降。
# 坡外缘下降后始终小于回廊内缘13.2m，不会钻入楼板；取消90度L形接头平台。
upper_surface_y = UPPER_Y + 0.23
hall_surface_y = 0.06
inner_routes = (
    ("EastInnerRamp", ((17.0, 110.0, 5.255), (13.0, 110.0, 5.255),
                       (10.4, 105.0, 4.85), (9.6, 85.0, 3.80),
                       (9.6, 60.0, 2.50), (9.6, 35.0, 1.10), (9.6, 20.0, 0.085))),
    ("WestInnerRamp", ((17.0, 250.0, 5.255), (13.0, 250.0, 5.255),
                       (10.4, 255.0, 4.85), (9.6, 275.0, 3.80),
                       (9.6, 300.0, 2.50), (9.6, 325.0, 1.10), (9.6, 340.0, 0.085))),
)
for name, controls in inner_routes:
    points = [circle_point(radius, angle, y) for radius, angle, y in controls]
    curved_path(name, smooth_points(points, 12), 5.8, "wood_floor_dark", False)
for side in (-1, 1):
    # 平台从回廊外缘 x=±21.8 开始，和环廊只接边不重叠，消除整片共面闪烁。
    box(f"UpperSideLanding{side}", (side * 25.0, UPPER_Y, HALL_Z),
        (6.4, 0.46, 8.5), "wood_floor", True)
    box(f"UpperLandingOuterParapet{side}", (side * 28.4, UPPER_Y + 0.75, HALL_Z),
        (0.40, 1.5, 8.7), "red_lacquer", True)


def exterior_ramp(name, side):
    points = [
        (side * 17.5, 0.085, 6.5),
        (side * 21.0, 0.28, 3.0),
        (side * 24.8, 1.03, -3.0),
        (side * 27.8, 2.03, -9.0),
        (side * 29.0, 3.08, -15.0),
        (side * 27.0, 4.25, -20.5),
        (side * 23.8, upper_surface_y + 0.025, -24.0),
    ]
    # 坡道端面比庭院/平台高2.5厘米，避免同平面闪烁；删除会与庭院重叠的坡脚垫板。
    route = smooth_points(points, 10)
    curved_path(name, route, 6.4, "stone_floor", True)
    for rail_side in (-1, 1):
        rail = _rail_points(route, 6.4, rail_side)
        for endpoint_name, endpoint in (("Foot", rail[0]), ("Top", rail[-1])):
            cylinder(f"{name}{endpoint_name}Post{rail_side}", endpoint,
                     0.34, 1.35, "gold_trim", True)


exterior_ramp("EastExteriorRamp", 1)
exterior_ramp("WestExteriorRamp", -1)

# 外坡背后以可见山墙遮挡空气墙和世界边缘，墙段避开坡道本体。
for side in (-1, 1):
    for index, (z, length) in enumerate(((-6.5, 8.0), (-14.0, 6.5), (-36.0, 16.0))):
        box(f"OuterScenicWall{side}_{index}", (side * 32.6, 2.25, z),
            (0.5, 4.5, length), "yellow_plaster", True)
        box(f"OuterScenicWallCap{side}_{index}", (side * 32.6, 4.62, z),
            (1.0, 0.28, length + 0.2), "roof_jade", True)

screen_door("FacadeDoorWest", -5.0, -1.05, 6.0)
screen_door("FacadeDoorEast", 5.0, -1.05, 6.0)
box("FacadeCenterPier", (0.0, 2.5, -1.1), (1.2, 5.0, 1.1), "red_lacquer", True)
for x in (-14.0, -10.0, 10.0, 14.0):
    cylinder(f"FacadeColumn{x:g}", (x, 2.65, -1.0), 0.42, 5.3, "red_lacquer", True)
box("FacadeWestBlock", (-13.0, 2.4, -1.35), (6.0, 4.8, 1.0), "red_wall", True)
box("FacadeEastBlock", (13.0, 2.4, -1.35), (6.0, 4.8, 1.0), "red_wall", True)
box("FacadeBeam", (0.0, 5.15, -1.0), (31.0, 0.78, 0.9), "red_lacquer", True)
box("FacadeSign", (0.0, 5.5, -0.4), (5.4, 1.35, 0.14), "gold", True)
pagoda_roof("FacadeRoof", 0.0, -3.0, 18.0, 5.2, 7.65, "roof_jade")
for i, x in enumerate((-14, -10, -6, -2, 2, 6, 10, 14)):
    lantern(f"FacadeLantern{i}", x, 4.15, -0.25, 0.95, i in (0, 3, 4, 7))

# 中央吊灯改为精致的七灯中式吊灯组，替代五个横向椭球鼓灯。
cylinder("CentralChandelierCanopy", (0.0, 10.65, HALL_Z), 2.35, 0.42,
         "gold_trim", True)
cylinder("CentralChandelierChain", (0.0, 11.55, HALL_Z), 0.10, 1.8,
         "gold", True)
for angle in range(0, 360, 60):
    radians = math.radians(angle)
    lantern(f"CentralChandelierLantern{angle}",
            math.sin(radians) * 1.75, 8.75, HALL_Z + math.cos(radians) * 1.75,
            0.82, False)
lantern("CentralChandelierMain", 0.0, 8.0, HALL_Z, 1.25, True)
lights.append({
    "light_type": "omni", "name": "CentralChandelierFill",
    "position": [0.0, 8.0, HALL_Z], "color": [1.0, 0.66, 0.27],
    "energy": 1.65, "range": 13.0, "shadow": True,
})
for i, (x, z) in enumerate(((-4.3, HALL_Z), (4.3, HALL_Z), (0.0, HALL_Z - 4.3), (0.0, HALL_Z + 4.3))):
    banner_name = f"CentralBanner{i}"
    box(banner_name, (x, 7.35, z), (1.1, 7.0, 0.12), "banner_red", True,
        (0.0, 90.0 if x else 0.0, 0.0))
    covered(box(f"CentralBannerTrim{i}", (x, 7.35, z - 0.07),
                (0.14, 7.0, 0.16), "gold_trim", False,
                (0.0, 90.0 if x else 0.0, 0.0)), banner_name)
for angle in range(15, 360, 30):
    x, _, z = circle_point(20.0, angle, 3.6)
    lantern(f"HallLantern{angle}", x, 3.6, z, 0.9, angle % 60 == 15)

ring("HallLowerEave", HALL_R - 0.1, 11.4, 5.2, "roof_jade", 40, True, 0.50)
for tier, (half, base_y, height) in enumerate(((15.0, 12.4, 3.6), (11.8, 16.3, 3.3),
                                              (8.6, 19.9, 3.0), (5.8, 23.2, 2.7))):
    body_name = f"TowerTier{tier}Body"
    box(body_name, (0.0, base_y, HALL_Z),
        (half * 2, height, half * 2), "red_wall", True)
    for sx in (-1, 1):
        for sz in (-1, 1):
            covered(box(f"TowerTier{tier}Column{sx}{sz}",
                        (sx * (half - 0.35), base_y, HALL_Z + sz * (half - 0.35)),
                        (0.46, height - 0.12, 0.46), "red_lacquer", False), body_name)
    lattice_panel(f"TowerTier{tier}Front", (0.0, base_y, HALL_Z + half + 0.06),
                  (half * 1.45, height * 0.72))
    pagoda_roof(f"TowerTier{tier}Roof", 0.0, HALL_Z, half + 0.7, half + 0.7,
                base_y + height / 2 + 0.72, "roof_jade")
cylinder("TowerSpire", (0.0, 26.9, HALL_Z), 0.22, 3.2, "gold", True)
sphere("TowerPearl", (0.0, 28.5, HALL_Z), 0.58, "gold", True)

for side in (-1, 1):
    for i, z in enumerate((9.0, 26.0, 34.0)):
        lantern(f"CourtSideLantern{side}_{i}", side * 22.5, 3.45, z, 0.9, i != 1)
    for i, z in enumerate((29.0, 34.0)):
        x = side * (18.0 + i * 1.5)
        proxy_name = f"TrainingProxy{side}_{i}"
        covered(cylinder(f"TrainingPost{side}_{i}", (x, 1.0, z), 0.25, 2.0,
                         "wood_floor_dark", False), proxy_name)
        covered(cylinder(f"TrainingArm{side}_{i}", (x, 1.45, z), 0.09, 1.6,
                         "wood_dark", False, (0.0, 0.0, 90.0)), proxy_name)
        covered(cylinder(f"TrainingBase{side}_{i}", (x, 0.16, z), 0.62, 0.32,
                         "statue_base", False), proxy_name)
        cylinder(proxy_name, (x, 1.05, z), 0.78, 2.1,
                 "wood_floor_dark", True, visible=False)

for i, (mx, mz, scale) in enumerate((
    (-52, -38, (4.8, 13.0, 4.8)), (-43, -55, (5.2, 17.0, 5.2)),
    (-24, -63, (4.2, 12.0, 4.2)), (24, -63, (4.2, 14.0, 4.2)),
    (43, -54, (5.2, 18.0, 5.2)), (52, -37, (4.8, 13.0, 4.8)),
    (-50, 32, (4.0, 10.0, 4.0)), (50, 32, (4.0, 11.0, 4.0)),
)):
    boundary_proxy = "BoundaryWallWest" if mx < 0 else "BoundaryWallEast"
    covered(sphere(f"Mountain{i}", (mx, 5.0, mz), 2.5,
                   "mountain", False, scale), boundary_proxy)
for side in (-1, 1):
    z = 36.5
    tree_name = f"CourtyardPine{side}"
    model(tree_name, (side * 22.0, 0.18, z),
          "../assets/dragon_palace/decor/pine_quaternius_cc0.glb",
          [0.75, 0.75, 0.75], [0.0, 18.0 * side, 0.0], None,
          [{"type": "box", "name": f"{tree_name}Collision",
            "position": [0.22, 4.13, -0.67], "size": [6.65, 8.95, 6.45]}])
    covered(cylinder(f"{tree_name}Pot", (side * 22.0, 0.35, z), 0.82, 0.70,
                     "statue_base", False), tree_name)

lights.extend([
    {"light_type": "omni", "name": "HallWarmFill", "position": [0.0, 5.5, HALL_Z],
     "color": [1.0, 0.52, 0.23], "energy": 2.1, "range": 28.0, "shadow": True},
    {"light_type": "omni", "name": "CourtyardFill", "position": [0.0, 7.0, COURT_Z],
     "color": [1.0, 0.70, 0.37], "energy": 1.2, "range": 30.0, "shadow": False},
])

# 所有可见实体必须拥有自身碰撞，或明确由同一复合物的光滑代理覆盖。
# 禁止再次把地砖线、窗格、灯笼零件等细碎装饰各自变成卡人的薄碰撞体。
object_names = {obj["name"] for obj in objects}
missing_visible_collisions = [
    obj["name"] for obj in objects
    if obj.get("visible", True)
    and obj.get("collision", "default") == "none"
    and not obj.get("collision_proxy")
]
dangling_proxies = [
    (obj["name"], obj.get("collision_proxy")) for obj in objects
    if obj.get("collision_proxy") and obj["collision_proxy"] not in object_names
]
if missing_visible_collisions:
    raise RuntimeError(f"visible objects without collision coverage: {missing_visible_collisions}")
if dangling_proxies:
    raise RuntimeError(f"missing collision proxies: {dangling_proxies}")

data = {
    "format_version": 2,
    "name": "Dragon Palace · 龙之宫殿",
    "runner_spawn": [-18.0, 0.4, 30.0],
    "tagger_spawn": [18.0, 0.4, 8.0],
    "environment": {
        "background": "color",
        "background_color": [0.46, 0.69, 0.95],
        "sky_color": [0.46, 0.69, 0.95],
        "ambient_color": [0.70, 0.77, 0.84],
        "ambient_energy": 0.80,
        "fog_enabled": True,
        "fog_color": [0.58, 0.71, 0.78],
        "fog_density": 0.0028,
        "tonemap": "filmic",
        "exposure": 1.08,
        "ssao": True,
        "ssr": True,
        "glow": True,
        "sun": {
            "visible": True,
            "rotation_degrees": [-48.0, -35.0, 0.0],
            "energy": 2.1,
            "color": [1.0, 0.91, 0.73],
            "shadow": True,
        },
    },
    "materials": materials,
    "prefabs": {},
    "objects": objects,
    "lights": lights,
    "gameplay": {"world_radius": 70.0},
}

output = Path(__file__).resolve().parents[1] / "maps" / "dragon_palace.json"
output.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"generated {output}: objects={len(objects)}, lights={len(lights)}")
