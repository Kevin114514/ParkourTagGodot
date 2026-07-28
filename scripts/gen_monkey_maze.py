"""生成猴子酒店回廊迷宫（更大更复杂版）。

特性：
- 9x9 单元迷宫，回溯法生成 + braid 去死胡同形成环路（适合追逐、路线复杂）。
- 每个走廊单元都有一盏贴顶暖光灯（无阴影穿透相邻格），配合抬高的环境光，全程无死黑区。
- 约 30% 的灯做成频闪/闪烁/呼吸（min 亮度 > 0，闪灭时靠邻灯与环境光补光，不产生死黑）。
- 天花板整块封顶（出生点已不再从天而降）。
"""
import json
import random

random.seed(20260728)

# ---- 尺寸参数 ----
N = 9                 # 迷宫单元数（NxN）
CELL = 9.0            # 单元边长（走廊宽度基准）
WALL_T = 0.5          # 墙厚
WALL_H = 3.6          # 墙高
CEIL_Y = 3.75         # 天花板中心高
CEIL_T = 0.3
HALF = N * CELL / 2.0 # 半场 = 40.5
HOLE_HALF = 2.0       # 出生口半宽

WALL_COLOR = [0.14, 0.09, 0.1]
GROUND_COLOR = [0.09, 0.06, 0.07]
CEIL_COLOR = [0.1, 0.06, 0.06]
LAMP_COLOR = [0.9, 0.6, 0.35]
LAMP_EMISSION = [1.0, 0.62, 0.26]
LIGHT_COLOR = [1.0, 0.66, 0.32]


def cx(i):
    return (i - (N - 1) / 2.0) * CELL


# ---- 迷宫生成：回溯法 ----
def edge_key(a, b):
    return tuple(sorted([a, b]))


def neighbors(i, j):
    for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ni, nj = i + di, j + dj
        if 0 <= ni < N and 0 <= nj < N:
            yield ni, nj


passages = set()      # 已打通的边集合
visited = set()
stack = [(0, 0)]
visited.add((0, 0))
while stack:
    cur = stack[-1]
    unvis = [nb for nb in neighbors(*cur) if nb not in visited]
    if not unvis:
        stack.pop()
        continue
    nxt = random.choice(unvis)
    passages.add(edge_key(cur, nxt))
    visited.add(nxt)
    stack.append(nxt)

# ---- braid：打通部分死胡同，形成环路 ----
def degree(cell):
    return sum(1 for nb in neighbors(*cell) if edge_key(cell, nb) in passages)

cells = [(i, j) for i in range(N) for j in range(N)]
dead_ends = [c for c in cells if degree(c) == 1]
random.shuffle(dead_ends)
for c in dead_ends:
    if degree(c) != 1:
        continue
    # 打通一条当前封闭的邻边
    closed = [nb for nb in neighbors(*c) if edge_key(c, nb) not in passages]
    if closed and random.random() < 0.85:
        passages.add(edge_key(c, random.choice(closed)))

# ---- 主干道：从左上出生点到右下出生点打通一条居中的阶梯路径，方便双方相遇 ----
mi, mj = 0, 0
step = 0
while (mi, mj) != (N - 1, N - 1):
    go_right = (mi < N - 1) and (mj == N - 1 or step % 2 == 0)
    if go_right:
        passages.add(edge_key((mi, mj), (mi + 1, mj)))
        mi += 1
    else:
        passages.add(edge_key((mi, mj), (mi, mj + 1)))
        mj += 1
    step += 1

objects = []
lights = []

# ---- 地板 ----
objects.append({
    "type": "box", "name": "Ground",
    "position": [0.0, -0.15, 0.0], "size": [N * CELL + 2.0, 0.3, N * CELL + 2.0],
    "color": GROUND_COLOR,
})

# ---- 四面外边界墙 ----
bound_defs = [
    ("BoundN", [0.0, WALL_H / 2.0, -HALF], [N * CELL + WALL_T, WALL_H, WALL_T]),
    ("BoundS", [0.0, WALL_H / 2.0, HALF], [N * CELL + WALL_T, WALL_H, WALL_T]),
    ("BoundW", [-HALF, WALL_H / 2.0, 0.0], [WALL_T, WALL_H, N * CELL + WALL_T]),
    ("BoundE", [HALF, WALL_H / 2.0, 0.0], [WALL_T, WALL_H, N * CELL + WALL_T]),
]
for name, pos, size in bound_defs:
    objects.append({"type": "box", "name": name, "position": pos, "size": size, "color": WALL_COLOR})

# ---- 内部墙：相邻单元未打通处放墙段 ----
wall_idx = 0
for i in range(N):
    for j in range(N):
        # 与右侧 (i+1,j) 之间的垂直墙
        if i + 1 < N and edge_key((i, j), (i + 1, j)) not in passages:
            objects.append({
                "type": "box", "name": "Wall_%d" % wall_idx,
                "position": [cx(i) + CELL / 2.0, WALL_H / 2.0, cx(j)],
                "size": [WALL_T, WALL_H, CELL + WALL_T], "color": WALL_COLOR,
            })
            wall_idx += 1
        # 与下方 (i,j+1) 之间的水平墙
        if j + 1 < N and edge_key((i, j), (i, j + 1)) not in passages:
            objects.append({
                "type": "box", "name": "Wall_%d" % wall_idx,
                "position": [cx(i), WALL_H / 2.0, cx(j) + CELL / 2.0],
                "size": [CELL + WALL_T, WALL_H, WALL_T], "color": WALL_COLOR,
            })
            wall_idx += 1

# ---- 天花板：整块封顶（出生已不再从天而降，无需开洞） ----
runner_spawn = [cx(0), 0.12, cx(0)]           # 左上角单元
tagger_spawn = [cx(N - 1), 0.12, cx(N - 1)]   # 右下角单元

cx_min, cx_max = -(N * CELL / 2.0 + 1.0), (N * CELL / 2.0 + 1.0)
cz_min, cz_max = cx_min, cx_max

objects.append({
    "type": "box", "name": "Ceiling",
    "position": [(cx_min + cx_max) / 2.0, CEIL_Y, (cz_min + cz_max) / 2.0],
    "size": [cx_max - cx_min, CEIL_T, cz_max - cz_min],
    "color": CEIL_COLOR, "collision_layer": 1, "collision_mask": 1,
})
ceil_idx = 1

# ---- 照明：每个单元一盏灯，部分频闪 ----
lamp_idx = 0
for i in range(N):
    for j in range(N):
        px, pz = cx(i), cx(j)
        # 贴顶灯座（发光装饰，无碰撞）
        objects.append({
            "type": "box", "name": "LampFix_%d" % lamp_idx,
            "position": [px, 3.5, pz], "size": [0.7, 0.14, 0.7],
            "color": LAMP_COLOR, "collision": False,
            "emission": LAMP_EMISSION, "emission_energy": 2.2,
        })
        light = {
            "light_type": "omni", "name": "CorridorLamp_%d" % lamp_idx,
            "position": [px, 3.1, pz], "color": LIGHT_COLOR,
            "energy": 2.6, "range": 8.5, "shadow": False,
        }
        # 频闪分配：出生格保持常亮，其余按概率
        is_spawn = (i, j) in ((0, 0), (N - 1, N - 1))
        if not is_spawn:
            r = random.random()
            if r < 0.10:
                light["flicker"] = {"mode": "strobe", "frequency": random.uniform(1.0, 1.8), "min": 0.05, "max": 1.0}
            elif r < 0.32:
                light["flicker"] = {"mode": "flicker", "frequency": random.uniform(3.5, 5.5), "min": 0.18, "max": 1.0}
            elif r < 0.42:
                light["flicker"] = {"mode": "pulse", "frequency": random.uniform(0.25, 0.6), "min": 0.35, "max": 1.0}
        lights.append(light)
        lamp_idx += 1

# ---- 辨向系统：把迷宫按 3x3 分成 9 个区域，每区一个主题色 ----
REGION_COLORS = [
    [0.62, 0.16, 0.16],   # 区0 暗红
    [0.62, 0.36, 0.13],   # 区1 橙
    [0.58, 0.52, 0.14],   # 区2 暗黄
    [0.16, 0.52, 0.22],   # 区3 绿
    [0.13, 0.46, 0.52],   # 区4 青（中心）
    [0.16, 0.32, 0.62],   # 区5 蓝
    [0.42, 0.16, 0.56],   # 区6 紫
    [0.58, 0.16, 0.42],   # 区7 品红
    [0.44, 0.44, 0.5],    # 区8 灰白
]

DIRS = [(0, -1), (1, 0), (0, 1), (-1, 0)]  # N(-z) E(+x) S(+z) W(-x)


def region_color(i, j):
    return REGION_COLORS[(i // 3) * 3 + (j // 3)]


def wall_on(i, j, di, dj):
    ni, nj = i + di, j + dj
    if not (0 <= ni < N and 0 <= nj < N):
        return True
    return edge_key((i, j), (ni, nj)) not in passages


# ---- 墙上挂画：每个单元朝一面实墙挂一幅区域色画作，作为方位路标 ----
paint_idx = 0
for i in range(N):
    for j in range(N):
        wdirs = [d for d in DIRS if wall_on(i, j, *d)]
        if not wdirs:
            continue
        di, dj = wdirs[(i * 3 + j) % len(wdirs)]
        px, pz = cx(i), cx(j)
        col = region_color(i, j)
        face_x = px + di * (CELL / 2.0 - WALL_T / 2.0)
        face_z = pz + dj * (CELL / 2.0 - WALL_T / 2.0)
        pw, ph, th = 1.6, 1.1, 0.08
        if di != 0:
            frame_size = [th + 0.04, ph + 0.22, pw + 0.22]
            canvas_size = [th, ph, pw]
        else:
            frame_size = [pw + 0.22, ph + 0.22, th + 0.04]
            canvas_size = [pw, ph, th]
        yc = 2.0
        objects.append({
            "type": "box", "name": "PaintFrame_%d" % paint_idx,
            "position": [face_x - di * 0.05, yc, face_z - dj * 0.05],
            "size": frame_size, "color": [0.06, 0.05, 0.05], "collision": False,
        })
        objects.append({
            "type": "box", "name": "Painting_%d" % paint_idx,
            "position": [face_x - di * 0.08, yc, face_z - dj * 0.08],
            "size": canvas_size, "color": col, "collision": False,
            "emission": col, "emission_energy": 0.7,
        })
        paint_idx += 1

# ---- 电视：靠墙落地，冷色屏幕 + 闪烁光，增加真实感 ----
tv_cells = [(i, j) for i in range(N) for j in range(N)
            if (i, j) not in ((0, 0), (N - 1, N - 1))
            and any(wall_on(i, j, *d) for d in DIRS)]
random.shuffle(tv_cells)
tv_cells = tv_cells[:12]
tv_idx = 0
for (i, j) in tv_cells:
    di, dj = [d for d in DIRS if wall_on(i, j, *d)][0]
    px, pz = cx(i), cx(j)
    face_x = px + di * (CELL / 2.0 - WALL_T / 2.0)
    face_z = pz + dj * (CELL / 2.0 - WALL_T / 2.0)
    d_depth, d_w = 0.4, 1.3
    nx, nz = -di, -dj  # 朝向单元中心
    bx = face_x + nx * (d_depth / 2.0 + 0.02)
    bz = face_z + nz * (d_depth / 2.0 + 0.02)
    if di != 0:
        stand_size = [0.5, 0.5, 1.0]
        body_size = [d_depth, 0.8, d_w]
        screen_size = [0.05, 0.58, d_w * 0.8]
    else:
        stand_size = [1.0, 0.5, 0.5]
        body_size = [d_w, 0.8, d_depth]
        screen_size = [d_w * 0.8, 0.58, 0.05]
    objects.append({
        "type": "box", "name": "TVStand_%d" % tv_idx,
        "position": [bx, 0.25, bz], "size": stand_size, "color": [0.08, 0.07, 0.07],
    })
    objects.append({
        "type": "box", "name": "TVBody_%d" % tv_idx,
        "position": [bx, 0.95, bz], "size": body_size, "color": [0.05, 0.05, 0.06],
    })
    sx = bx + nx * (d_depth / 2.0 + 0.01)
    sz = bz + nz * (d_depth / 2.0 + 0.01)
    tv_col = [0.55, 0.7, 0.95]
    objects.append({
        "type": "box", "name": "TVScreen_%d" % tv_idx,
        "position": [sx, 0.95, sz], "size": screen_size, "color": tv_col,
        "collision": False, "emission": tv_col, "emission_energy": 1.6,
    })
    lights.append({
        "light_type": "omni", "name": "TVGlow_%d" % tv_idx,
        "position": [bx + nx * 0.6, 1.0, bz + nz * 0.6], "color": [0.5, 0.68, 0.95],
        "energy": 1.3, "range": 4.5, "shadow": False,
        "flicker": {"mode": "flicker", "frequency": random.uniform(4.0, 6.0), "min": 0.35, "max": 1.0},
    })
    tv_idx += 1

data = {
    "format_version": 2,
    "name": "猴子酒店回廊迷宫",
    "runner_spawn": runner_spawn,
    "tagger_spawn": tagger_spawn,
    "environment": {
        "background": "color",
        "background_color": [0.015, 0.01, 0.015],
        "sky_color": [0.015, 0.01, 0.015],
        "ambient_color": [0.16, 0.12, 0.13],
        "ambient_energy": 0.36,
        "fog_enabled": True,
        "fog_color": [0.045, 0.03, 0.032],
        "fog_density": 0.026,
        "tonemap": "filmic",
        "exposure": 0.9,
        "glow": True,
        "sun": {"rotation_degrees": [-70.0, 25.0, 0.0], "energy": 0.06, "color": [0.4, 0.28, 0.3], "shadow": False},
    },
    "objects": objects,
    "lights": lights,
}

with open("maps/monkey_hotel_corridors.json", "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

n_strobe = sum(1 for l in lights if l.get("flicker", {}).get("mode") == "strobe")
n_flicker = sum(1 for l in lights if l.get("flicker", {}).get("mode") == "flicker")
n_pulse = sum(1 for l in lights if l.get("flicker", {}).get("mode") == "pulse")
print("迷宫 %dx%d，尺寸约 %.0fx%.0f" % (N, N, N * CELL, N * CELL))
print("objects=%d  lights=%d" % (len(objects), len(lights)))
print("  墙段=%d  天花板块=%d  灯座=%d  挂画=%d  电视=%d" % (wall_idx, ceil_idx, lamp_idx, paint_idx, tv_idx))
print("  常亮=%d  strobe=%d  flicker=%d  pulse=%d" %
      (len(lights) - n_strobe - n_flicker - n_pulse, n_strobe, n_flicker, n_pulse))
print("  runner_spawn=%s  tagger_spawn=%s" % (runner_spawn, tagger_spawn))
