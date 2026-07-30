"""生成猴子酒店回廊迷宫（更大更复杂版）。

特性：
- 17x17 单元迷宫，窄走廊（净宽约2.5）。全量 braid 消除【所有死路】，形成极其复杂的回廊迷宫（处处成环）。
- braid 打通时避免形成 2x2 开阔小室；残留的开阔小室用中央立柱改造成环形回廊，杜绝斜向望穿。
- 并加入交错隔断/立柱打断长直视线、制造不规则遮挡；放置时做全局净距校验，杜绝"看得见开口却穿不过"的窄缝。
- 每个走廊单元都有一盏贴顶暖光灯（无阴影穿透相邻格），配合抬高的环境光，全程无死黑区。
- 约 88% 的走廊灯为强频闪，另有少量随机闪烁/呼吸灯；仅出生点及约 2% 的普通灯保持常亮。
- 天花板整块封顶（出生点已不再从天而降）。
- 灯与壁画在【所有到顶实体（中央立柱/隔断/立柱）】放置完毕后再生成：灯若落入实体则挪到最近空走廊，
  壁画若与实体显著重叠则跳过，杜绝"灯/画卡在墙（柱）中间"。
"""
import json
import random

random.seed(20260728)

# ---- 尺寸参数 ----
N = 17                # 迷宫单元数（NxN，更大更复杂）
CELL = 3.0            # 单元边长≈走廊净宽（人物直径约0.7，稍宽以便通行/错身）
WALL_T = 0.5          # 墙厚
WALL_H = 3.6          # 墙高
CEIL_Y = 3.75         # 天花板中心高
CEIL_T = 0.3
HALF = N * CELL / 2.0 # 半场 = N*CELL/2
HOLE_HALF = 2.0       # 出生口半宽

# 各表面的染色 tint（乘在贴图上）。贴图本身已是暗色恐怖风，tint 略压暗以保持氛围，
# 又不过黑，让墙纸/地毯/霉斑等纹理细节仍清晰可辨。
WALL_COLOR = [0.82, 0.78, 0.78]
GROUND_COLOR = [0.78, 0.7, 0.7]
CEIL_COLOR = [0.7, 0.68, 0.68]
PILLAR_COLOR = [0.76, 0.72, 0.72]
CORE_COLOR = [0.72, 0.68, 0.68]
LAMP_COLOR = [0.9, 0.6, 0.35]
LAMP_EMISSION = [1.0, 0.62, 0.26]
LIGHT_COLOR = [1.0, 0.66, 0.32]

# ---- 贴图材质表：只放贴图与粗糙度，不放 color/uv_scale，让每个物体自带 tint 与平铺次数 ----
# 路径相对地图文件（maps/）解析；map_loader 支持 materials 表 + material_id 引用。
MATERIALS = {
    "wall":     {"albedo_texture": "textures/wall_wallpaper.png",  "roughness": 0.95, "metallic": 0.0},
    "floor":    {"albedo_texture": "textures/floor_carpet.png",    "roughness": 0.98, "metallic": 0.0},
    "ceiling":  {"albedo_texture": "textures/ceiling_plaster.png", "roughness": 0.95, "metallic": 0.0},
    "pillar":   {"albedo_texture": "textures/pillar_concrete.png", "roughness": 0.9,  "metallic": 0.0},
    "painting": {"albedo_texture": "textures/painting_horror.png", "roughness": 0.85, "metallic": 0.0},
}


def tex_uv(size, tile=2.0):
    """竖直物体（墙/柱/隔断）：按水平最大边×高度估算平铺次数，使每 tile 米重复一次。"""
    sx, sy, sz = size
    horiz = max(sx, sz)
    return [max(1.0, round(horiz / tile)), max(1.0, round(sy / tile)), 1.0]


def floor_uv(size, tile=3.0):
    """水平大面（地板/天花板）：按 X×Z 估算平铺次数。"""
    sx, _sy, sz = size
    return [max(1.0, round(sx / tile)), max(1.0, round(sz / tile)), 1.0]


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

def degree(cell):
    return sum(1 for nb in neighbors(*cell) if edge_key(cell, nb) in passages)

cells = [(i, j) for i in range(N) for j in range(N)]

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

# ---- 开阔小室检测 ----
# 一个 2x2 单元格若 4 条内部边全部打通，其中心的墙角柱就消失，形成无墙开阔小室，
# 玩家可从中斜向望穿很远。回廊迷宫必须避免此情况。
def block_fully_open(bi, bj, pset):
    if not (0 <= bi < N - 1 and 0 <= bj < N - 1):
        return False
    e = (edge_key((bi, bj), (bi + 1, bj)),
         edge_key((bi, bj + 1), (bi + 1, bj + 1)),
         edge_key((bi, bj), (bi, bj + 1)),
         edge_key((bi + 1, bj), (bi + 1, bj + 1)))
    return all(x in pset for x in e)


def would_open_area(a, b):
    """假设打通 a-b，是否会使其所属的某个 2x2 区块变成开阔小室。"""
    key = edge_key(a, b)
    added = key not in passages
    passages.add(key)
    (ai, aj), (bi, bj) = a, b
    if ai != bi:                       # 沿 X 相邻（竖直边）
        lo = min(ai, bi)
        blocks = ((lo, aj), (lo, aj - 1))
    else:                              # 沿 Z 相邻（水平边）
        lo = min(aj, bj)
        blocks = ((ai, lo), (ai - 1, lo))
    bad = any(block_fully_open(bx, bz, passages) for bx, bz in blocks)
    if added:
        passages.discard(key)
    return bad


# ---- braid：打通【所有】死胡同，形成没有死路的复杂回廊迷宫。 ----
# 打通时优先选择不会制造开阔小室（斜向透视）的连边。
guard = 0
while True:
    des = [c for c in cells if degree(c) == 1]
    if not des:
        break
    guard += 1
    if guard > 4 * N * N:
        break
    random.shuffle(des)
    for c in des:
        if degree(c) != 1:
            continue
        closed = [nb for nb in neighbors(*c) if edge_key(c, nb) not in passages]
        if not closed:
            continue
        safe = [nb for nb in closed if not would_open_area(c, nb)]
        pick = random.choice(safe) if safe else random.choice(closed)
        passages.add(edge_key(c, pick))

objects = []
lights = []

# ---- 到顶阻挡物登记表：用于消除"看得见开口却穿不过"的窄缝 ----
# 记录所有会挡住人物且到顶的实体在 XZ 平面的 AABB。放置任何新遮挡前先做净距校验：
# 若它会与已有的墙/立柱形成 (GAP_VISIBLE, PERSON) 之间的平行窄缝（肉眼可见却过不去），
# 则放弃该遮挡。保留下来的间隙要么 >=PERSON 可通行，要么 ~=0 贴合成实墙。
PERSON = 0.75         # 人物直径约0.7，留余量
GAP_VISIBLE = 0.12    # 大于此宽度即形成肉眼可见的开口
GAP_MINLEN = 0.4      # 缝需有一定长度才算"显著"（避免角对角的无关近邻误判）
blocker_aabbs = []    # [(x0, x1, z0, z1), ...]


def reg_blocker(px, pz, sx, sz):
    blocker_aabbs.append((px - sx / 2.0, px + sx / 2.0, pz - sz / 2.0, pz + sz / 2.0))


def makes_narrow_gap(px, pz, sx, sz):
    """新遮挡(px,pz,sx,sz)是否会与任一已登记阻挡物形成穿不过的显著窄缝。"""
    nx0, nx1, nz0, nz1 = px - sx / 2.0, px + sx / 2.0, pz - sz / 2.0, pz + sz / 2.0
    for (ax0, ax1, az0, az1) in blocker_aabbs:
        ox = min(nx1, ax1) - max(nx0, ax0)   # x 投影重叠
        oz = min(nz1, az1) - max(nz0, az0)   # z 投影重叠
        if ox > GAP_MINLEN and oz < 0 and GAP_VISIBLE < -oz < PERSON:
            return True
        if oz > GAP_MINLEN and ox < 0 and GAP_VISIBLE < -ox < PERSON:
            return True
    return False


# ---- 到顶实体登记表：供【灯具/壁画】避让，杜绝"灯/画卡进墙（柱）里" ----
# 记录所有"到天花板"的实体（外/内墙、转角柱、中央立柱、到顶隔断、到顶立柱）在 XZ 的 AABB。
# 贴顶灯座(y≈3.5)与壁画(y≈1.9)若落入其中就会被埋进实体 → 放置时据此避让。
tall_aabbs = []       # [(x0, x1, z0, z1), ...]


def reg_tall(px, pz, sx, sz):
    tall_aabbs.append((px - sx / 2.0, px + sx / 2.0, pz - sz / 2.0, pz + sz / 2.0))


def point_in_tall(x, z, margin=0.0):
    """点 (x,z)（含灯具半宽 margin）是否落入任一到顶实体内。"""
    for (x0, x1, z0, z1) in tall_aabbs:
        if x0 - margin < x < x1 + margin and z0 - margin < z < z1 + margin:
            return True
    return False


def box_hits_tall(bx0, bx1, bz0, bz1, min_overlap=0.03):
    """矩形足迹与任一到顶实体在两个方向都有显著重叠（> min_overlap）时判为冲突。
    仅贴合边缘（如壁画贴在其安装墙上，法向重叠≈0）不算冲突。"""
    for (ax0, ax1, az0, az1) in tall_aabbs:
        ox = min(bx1, ax1) - max(bx0, ax0)
        oz = min(bz1, az1) - max(bz0, az0)
        if ox > min_overlap and oz > min_overlap:
            return True
    return False


# ---- 地板 ----
_ground_size = [N * CELL + 2.0, 0.3, N * CELL + 2.0]
objects.append({
    "type": "box", "name": "Ground",
    "position": [0.0, -0.15, 0.0], "size": _ground_size,
    "color": GROUND_COLOR, "material_id": "floor", "uv_scale": floor_uv(_ground_size),
})

# ---- 四面外边界墙 ----
# 南北墙占满整条宽（含 4 个外角方块）；东西墙两端各缩 WALL_T/2 顶住南北墙内侧，
# 避免 4 个外角处两墙重叠出同向共面（虽在朝外背面、玩家看不到，仍一并消除）。
bound_defs = [
    ("BoundN", [0.0, WALL_H / 2.0, -HALF], [N * CELL + WALL_T, WALL_H, WALL_T]),
    ("BoundS", [0.0, WALL_H / 2.0, HALF], [N * CELL + WALL_T, WALL_H, WALL_T]),
    ("BoundW", [-HALF, WALL_H / 2.0, 0.0], [WALL_T, WALL_H, N * CELL - WALL_T]),
    ("BoundE", [HALF, WALL_H / 2.0, 0.0], [WALL_T, WALL_H, N * CELL - WALL_T]),
]
for name, pos, size in bound_defs:
    objects.append({"type": "box", "name": name, "position": pos, "size": size,
                    "color": WALL_COLOR, "material_id": "wall", "uv_scale": tex_uv(size)})
    reg_blocker(pos[0], pos[2], size[0], size[2])
    reg_tall(pos[0], pos[2], size[0], size[2])

# ---- 内部墙 + 转角角柱 ----
# 关键修复（墙角持续闪烁抖动的主因）：
# 上一版把共线墙段合并成长墙，消除了【同向共线重叠】；但墙角仍在闪，原因是每根墙
# 都比单元多伸出 WALL_T/2（旧 SEG=CELL+WALL_T）去“填补墙角”。于是在 L 型转角处，
# 【横墙的端面】正好落在【竖墙的外侧面】同一平面上、且法线同向 → 同向共面、深度相等
# → GPU 每帧随机选谁在前 → 墙角闪烁（合并与 Y 向 EMBED 都管不到这种“端面压侧面”）。
#
# 正确解法（几何上彻底杜绝所有共面）：
#  1) 墙段只延伸到【单元边界线=顶点中心】（SEG=CELL，不再多伸 WALL_T/2）。这样墙端要么
#     被【垂直穿过该顶点的直墙】完全埋住（端面在直墙内部，不可见），要么被外边界墙埋住，
#     要么顶住角柱——都不再有裸露的同向共面。
#  2) 十字/直穿口：两条直墙互相垂直，一条只提供 X 面、一条只提供 Z 面，无同向共面 → 不闪。
#  3) 只在【真正的 L 型转角】（既有横墙又有竖墙、且两者都在此终止而非直穿）放一根
#     WALL_T×WALL_T 角柱填实墙角，并把在此终止的墙端各缩短 WALL_T/2 去顶住柱侧面
#     （背靠背贴合、法线相反 → 不 Z-fighting、无缝）。
SEG = CELL   # 墙段基础跨度：正好覆盖单元，端点落在单元边界线（顶点中心）


def is_wall_v(i, j):
    """列线 i（x=cx(i)+CELL/2）上、单元行 j 处是否有竖墙。"""
    return 0 <= i < N - 1 and 0 <= j < N and edge_key((i, j), (i + 1, j)) not in passages


def is_wall_h(i, j):
    """行线 j（z=cx(j)+CELL/2）上、单元列 i 处是否有横墙。"""
    return 0 <= i < N and 0 <= j < N - 1 and edge_key((i, j), (i, j + 1)) not in passages


# 内部顶点 (vi,vj)（vi,vj∈0..N-2）四方向墙臂：S/N 为竖墙上下臂，W/E 为横墙左右臂
def vertex_arms(vi, vj):
    s = is_wall_v(vi, vj)          # 竖墙-下（行 vj）
    n = is_wall_v(vi, vj + 1)      # 竖墙-上（行 vj+1）
    w = is_wall_h(vi, vj)          # 横墙-左（列 vi）
    e = is_wall_h(vi + 1, vj)      # 横墙-右（列 vi+1）
    return s, n, w, e


# 需要角柱的顶点：既有竖臂又有横臂，且【两向都不直穿】（否则直穿的那条墙已填满该顶点方块）
post_vertices = set()
for vi in range(N - 1):
    for vj in range(N - 1):
        s, n, w, e = vertex_arms(vi, vj)
        vert_through = s and n
        horiz_through = w and e
        if (not vert_through) and (not horiz_through) and (s or n) and (w or e):
            post_vertices.add((vi, vj))


def emit_wall(px, pz, sx, sz, idx, name="Wall"):
    size = [sx, WALL_H, sz]
    objects.append({
        "type": "box", "name": "%s_%d" % (name, idx),
        "position": [px, WALL_H / 2.0, pz],
        "size": size, "color": WALL_COLOR,
        "material_id": "wall", "uv_scale": tex_uv(size),
    })
    reg_blocker(px, pz, sx, sz)
    reg_tall(px, pz, sx, sz)


wall_idx = 0
# 竖墙（沿 Z 延伸）：按列线 vi 分组，合并行方向连续墙段为一根长墙
for vi in range(N - 1):
    j = 0
    while j < N:
        if not is_wall_v(vi, j):
            j += 1
            continue
        j0 = j
        while j < N and is_wall_v(vi, j):
            j += 1
        j1 = j - 1
        z_lo = cx(j0) - CELL / 2.0            # 北端（行 j0 上边界线）
        z_hi = cx(j1) + CELL / 2.0            # 南端（行 j1 下边界线）
        if (vi, j0 - 1) in post_vertices:     # 北端顶住角柱 → 缩短
            z_lo += WALL_T / 2.0
        if (vi, j1) in post_vertices:         # 南端顶住角柱 → 缩短
            z_hi -= WALL_T / 2.0
        emit_wall(cx(vi) + CELL / 2.0, (z_lo + z_hi) / 2.0, WALL_T, z_hi - z_lo, wall_idx)
        wall_idx += 1
# 横墙（沿 X 延伸）：按行线 vj 分组，合并列方向连续墙段为一根长墙
for vj in range(N - 1):
    i = 0
    while i < N:
        if not is_wall_h(i, vj):
            i += 1
            continue
        i0 = i
        while i < N and is_wall_h(i, vj):
            i += 1
        i1 = i - 1
        x_lo = cx(i0) - CELL / 2.0            # 西端（列 i0 左边界线）
        x_hi = cx(i1) + CELL / 2.0            # 东端（列 i1 右边界线）
        if (i0 - 1, vj) in post_vertices:     # 西端顶住角柱 → 缩短
            x_lo += WALL_T / 2.0
        if (i1, vj) in post_vertices:         # 东端顶住角柱 → 缩短
            x_hi -= WALL_T / 2.0
        emit_wall((x_lo + x_hi) / 2.0, cx(vj) + CELL / 2.0, x_hi - x_lo, WALL_T, wall_idx)
        wall_idx += 1
# 转角角柱：填实 L 型墙角（四周墙端各缩短 WALL_T/2 顶住其侧面，背靠背不闪）
n_posts = 0
for (vi, vj) in sorted(post_vertices):
    emit_wall(cx(vi) + CELL / 2.0, cx(vj) + CELL / 2.0, WALL_T, WALL_T, wall_idx, name="WallPost")
    wall_idx += 1
    n_posts += 1

# ---- 天花板：整块封顶（出生已不再从天而降，无需开洞） ----
runner_spawn = [cx(0), 0.12, cx(0)]           # 左上角单元
tagger_spawn = [cx(N - 1), 0.12, cx(N - 1)]   # 右下角单元

cx_min, cx_max = -(N * CELL / 2.0 + 1.0), (N * CELL / 2.0 + 1.0)
cz_min, cz_max = cx_min, cx_max

_ceil_size = [cx_max - cx_min, CEIL_T, cz_max - cz_min]
objects.append({
    "type": "box", "name": "Ceiling",
    "position": [(cx_min + cx_max) / 2.0, CEIL_Y, (cz_min + cz_max) / 2.0],
    "size": _ceil_size,
    "color": CEIL_COLOR, "collision_layer": 1, "collision_mask": 1,
    "material_id": "ceiling", "uv_scale": floor_uv(_ceil_size),
})
ceil_idx = 1

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
    ri = min(2, i * 3 // N)
    rj = min(2, j * 3 // N)
    return REGION_COLORS[ri * 3 + rj]


def wall_on(i, j, di, dj):
    ni, nj = i + di, j + dj
    if not (0 <= ni < N and 0 <= nj < N):
        return True
    return edge_key((i, j), (ni, nj)) not in passages


# ---- 中央立柱：把 braid 后仍残留的开阔小室改造成环形回廊，堵住斜向透视 ----
# 在 2x2 开阔小室的公共内部顶点放一根到顶立柱，四周留出约 1.25 净宽的环形走廊，
# 既彻底消除斜向望穿，又强化"回廊"迷宫的观感（绕柱成环）。
core_idx = 0
for bi in range(N - 1):
    for bj in range(N - 1):
        if not block_fully_open(bi, bj, passages):
            continue
        vx = cx(bi) + CELL / 2.0            # 2x2 区块的公共内部顶点
        vz = cx(bj) + CELL / 2.0
        cw = 2.0 * CELL - WALL_T - 2.5      # 使四周各留约 1.25 的环形走廊
        objects.append({
            "type": "box", "name": "CoreColumn_%d" % core_idx,
            "position": [vx, WALL_H / 2.0, vz],
            "size": [cw, WALL_H, cw], "color": CORE_COLOR,
            "material_id": "pillar", "uv_scale": tex_uv([cw, WALL_H, cw]),
        })
        reg_blocker(vx, vz, cw, cw)
        reg_tall(vx, vz, cw, cw)
        core_idx += 1

# ---- 遮挡与不规则：交错半隔断打断长直视线 + 贴墙立柱/矮箱增加不规则感 ----
obstacle_idx = 0
for i in range(N):
    for j in range(N):
        if (i, j) in ((0, 0), (N - 1, N - 1)):
            continue
        px, pz = cx(i), cx(j)
        opens = [d for d in DIRS if not wall_on(i, j, *d)]
        n_open = len(opens)
        ns = ((0, -1) in opens) and ((0, 1) in opens)
        ew = ((1, 0) in opens) and ((-1, 0) in opens)
        inner = CELL - WALL_T              # 走廊净宽（墙内表面之间的距离）
        if n_open == 2 and (ns or ew) and random.random() < 0.72:
            # 直走廊：从一侧墙内表面伸出的半隔断（不及对面），逼迫绕行、遮断长视线。
            # seg 基于净宽计算，确保另一侧至少留出 inner*0.4≈1.0 的通道（> 人物直径 0.7）。
            side = 1 if (i + j) % 2 == 0 else -1
            seg = inner * random.uniform(0.45, 0.6)
            off = side * (inner / 2.0 - seg / 2.0)   # 一端精确贴墙内表面，另一端留缝
            if ns:   # 南北走廊：挡板沿 X 横跨
                bpx, bpz, bsx, bsz = px + off, pz, seg, WALL_T
            else:    # 东西走廊：挡板沿 Z 横跨
                bpx, bpz, bsx, bsz = px, pz + off, WALL_T, seg
            # 与相邻走廊/隔断叠加会夹出穿不过的窄缝时，放弃此隔断。
            if not makes_narrow_gap(bpx, bpz, bsx, bsz):
                objects.append({
                    "type": "box", "name": "Baffle_%d" % obstacle_idx,
                    "position": [bpx, WALL_H / 2.0, bpz],
                    "size": [bsx, WALL_H, bsz], "color": WALL_COLOR,
                    "material_id": "wall", "uv_scale": tex_uv([bsx, WALL_H, bsz]),
                })
                reg_blocker(bpx, bpz, bsx, bsz)
                reg_tall(bpx, bpz, bsx, bsz)   # 到顶隔断：登记供灯/画避让
                obstacle_idx += 1
        elif n_open >= 2 and random.random() < 0.5:
            # 拐角/路口：贴一面实墙放立柱或矮箱，通道保留在对侧。
            walls = [d for d in DIRS if wall_on(i, j, *d)]
            if not walls:
                continue
            di, dj = random.choice(walls)
            w = random.uniform(0.55, 0.85)
            # 立柱外表面精确贴墙内表面，沿墙方向仅做小幅偏移，避免探入交叉口。
            slide = random.uniform(-0.3, 0.3)
            bx = px + di * (inner / 2.0 - w / 2.0) + (0.0 if di != 0 else slide)
            bz = pz + dj * (inner / 2.0 - w / 2.0) + (0.0 if dj != 0 else slide)
            # 立柱靠近相邻墙端/中央立柱/其它立柱而夹出穿不过的窄缝时，放弃此立柱。
            if makes_narrow_gap(bx, bz, w, w):
                continue
            if random.random() < 0.7:
                h = WALL_H                     # 到顶立柱：遮断视线
                col = PILLAR_COLOR
                is_tall = True
            else:
                h = random.uniform(1.0, 1.5)   # 矮箱：可翻越，增加杂乱
                col = [0.6, 0.56, 0.54]        # 稍暗一档，与到顶柱区分
                is_tall = False
            objects.append({
                "type": "box", "name": "Pillar_%d" % obstacle_idx,
                "position": [bx, h / 2.0, bz], "size": [w, h, w], "color": col,
                "material_id": "pillar", "uv_scale": tex_uv([w, h, w]),
            })
            reg_blocker(bx, bz, w, w)
            if is_tall:                        # 仅到顶立柱登记供灯/画避让（矮箱不及灯/画高度）
                reg_tall(bx, bz, w, w)
            obstacle_idx += 1

# ---- 电视：靠墙落地，冷色屏幕 + 闪烁光，增加真实感 ----
tv_cells = [(i, j) for i in range(N) for j in range(N)
            if (i, j) not in ((0, 0), (N - 1, N - 1))
            and any(wall_on(i, j, *d) for d in DIRS)]
random.shuffle(tv_cells)
tv_idx = 0
for (i, j) in tv_cells:
    if tv_idx >= 8:
        break
    di, dj = [d for d in DIRS if wall_on(i, j, *d)][0]
    px, pz = cx(i), cx(j)
    face_x = px + di * (CELL / 2.0 - WALL_T / 2.0)
    face_z = pz + dj * (CELL / 2.0 - WALL_T / 2.0)
    d_depth, d_w = 0.3, 1.0
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
    # 电视与相邻遮挡/立柱夹出穿不过的窄缝时，另选一个位置。
    if makes_narrow_gap(bx, bz, stand_size[0], stand_size[2]):
        continue
    reg_blocker(bx, bz, stand_size[0], stand_size[2])
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
        "collision": False, "emission": tv_col, "emission_energy": 1.2,
    })
    lights.append({
        "light_type": "omni", "name": "TVGlow_%d" % tv_idx,
        "position": [bx + nx * 0.6, 1.0, bz + nz * 0.6], "color": [0.5, 0.68, 0.95],
        "energy": 0.6, "range": 3.5, "shadow": False,
        "flicker": {"mode": "flicker", "frequency": random.uniform(4.0, 6.0), "min": 0.0, "max": 1.0},
    })
    tv_idx += 1

# ---- 照明：每个单元一盏灯，部分频闪 ----
# 【关键修复】灯必须在所有到顶实体（中央立柱/隔断/立柱）之后放置，才能据 tall_aabbs 避让。
# 若灯座中心落入到顶实体，则沿四周（含斜向）挪到最近的空走廊格，避免"灯卡进墙/柱里"。
LAMP_HALF = 0.22   # 灯座半宽（0.4/2）+ 余量


def lamp_free(x, z):
    return not point_in_tall(x, z, margin=LAMP_HALF)


# 灯光使用独立随机源，调整闪烁比例不会连带改变后续壁画的位置与数量。
lamp_rng = random.Random(20260730)
lamp_idx = 0
for i in range(N):
    for j in range(N):
        px, pz = cx(i), cx(j)
        lx, lz = px, pz
        if not lamp_free(lx, lz):
            # 落在到顶实体里：向周围空走廊挪位（小幅度优先；斜向可移出中央立柱的角落）。
            moved = False
            cand = []
            for mag in (0.7, 0.95):
                for dx, dz in ((-1, 0), (1, 0), (0, -1), (0, 1),
                               (-1, -1), (1, -1), (-1, 1), (1, 1)):
                    cand.append((px + dx * mag, pz + dz * mag))
            for (oxp, ozp) in cand:
                if lamp_free(oxp, ozp):
                    lx, lz, moved = oxp, ozp, True
                    break
            if not moved:
                continue   # 该格已被到顶实体完全占据，无地面可照，跳过
        # 频闪分配：两个出生格固定常亮；其余约 88% 为强频闪、8% 随机闪烁、2% 呼吸、仅 2% 常亮。
        # strobe/flicker 会完全闪灭（min=0），靠密集邻灯与环境光避免整片区域同时死黑。
        is_spawn = (i, j) in ((0, 0), (N - 1, N - 1))
        flicker = None
        if not is_spawn:
            # 保持旧版全局随机数消耗不变，以免此次灯光调整移动后续壁画。
            legacy_r = random.random()
            if legacy_r < 0.46:
                random.uniform(0.0, 1.0)
            r = lamp_rng.random()
            if r < 0.88:
                flicker = {"mode": "strobe", "frequency": lamp_rng.uniform(0.35, 0.7), "min": 0.0, "max": 1.0}
            elif r < 0.96:
                flicker = {"mode": "flicker", "frequency": lamp_rng.uniform(3.5, 6.0), "min": 0.0, "max": 1.0}
            elif r < 0.98:
                flicker = {"mode": "pulse", "frequency": lamp_rng.uniform(0.25, 0.6), "min": 0.12, "max": 1.0}
        # 贴顶灯座（无碰撞）：全部带暖黄自发光，看起来就是亮黄的发光体。
        # 频闪灯座的自发光亮度由 flicker 脚本与灯光同步驱动：灯亮时亮黄、灯灭瞬间变黑，不残留黄色。
        fix = {
            "type": "box", "name": "LampFix_%d" % lamp_idx,
            "position": [lx, 3.5, lz], "size": [0.4, 0.12, 0.4],
            "collision": False,
            "color": LAMP_COLOR,
            "emission": LAMP_EMISSION,
            "emission_energy": 1.0,
        }
        objects.append(fix)
        light = {
            "light_type": "omni", "name": "CorridorLamp_%d" % lamp_idx,
            "position": [lx, 3.1, lz], "color": LIGHT_COLOR,
            "energy": 0.75, "range": 4.4, "shadow": False,
        }
        if flicker is not None:
            light["flicker"] = flicker
            light["emissive_fixture"] = "LampFix_%d" % lamp_idx   # 灯座自发光跟随频闪同步明灭
            light["fixture_emission_base"] = 1.0
        lights.append(light)
        lamp_idx += 1

# ---- 墙上恐怖壁画：完全不发光、暗色调、稀疏随机分布，营造诡异氛围 ----
# 【关键修复】壁画同样在所有到顶实体之后放置：若画框足迹与到顶实体显著重叠（被立柱/隔断/
# 中央柱挡在前面、埋进实体里），则跳过该处壁画。仅与安装墙贴合（法向重叠≈0）不算冲突。
HORROR_COLORS = [
    [0.15, 0.03, 0.03],   # 干涸血红
    [0.09, 0.07, 0.04],   # 陈旧黄褐
    [0.05, 0.08, 0.06],   # 惨绿
    [0.06, 0.05, 0.09],   # 阴冷紫
    [0.03, 0.03, 0.03],   # 近黑
    [0.11, 0.06, 0.05],   # 锈褐
]
paint_idx = 0
for i in range(N):
    for j in range(N):
        wdirs = [d for d in DIRS if wall_on(i, j, *d)]
        if not wdirs:
            continue
        if random.random() > 0.45:   # 稀疏：约 45% 的可挂墙面才挂画
            continue
        di, dj = random.choice(wdirs)
        px, pz = cx(i), cx(j)
        face_x = px + di * (CELL / 2.0 - WALL_T / 2.0)
        face_z = pz + dj * (CELL / 2.0 - WALL_T / 2.0)
        # 壁画源图为正方形；画布保持 1:1，避免非等比缩放。仍消耗两次随机数以保持后续地图随机序列不变。
        pw_raw, ph_raw, th = random.uniform(0.9, 1.3), random.uniform(0.7, 1.05), 0.06
        side = min(pw_raw, ph_raw)
        if di != 0:
            frame_size = [th + 0.04, side + 0.22, side + 0.22]
            canvas_size = [th, side, side]
        else:
            frame_size = [side + 0.22, side + 0.22, th + 0.04]
            canvas_size = [side, side, th]
        yc = random.uniform(1.7, 2.1)
        fcx = face_x - di * 0.05
        fcz = face_z - dj * 0.05
        # 画框在 XZ 的足迹被到顶实体显著遮挡（埋进立柱/隔断/中央柱）→ 跳过此画。
        if box_hits_tall(fcx - frame_size[0] / 2.0, fcx + frame_size[0] / 2.0,
                         fcz - frame_size[2] / 2.0, fcz + frame_size[2] / 2.0):
            continue
        objects.append({
            "type": "box", "name": "PaintFrame_%d" % paint_idx,
            "position": [fcx, yc, fcz],
            "size": frame_size, "color": [0.03, 0.02, 0.02], "collision": False,
        })
        # 画布保持正方形 1:1 比例，确保源图不被非等比拉伸；使用有厚度的 BoxMesh 保证各朝向正常受光。
        objects.append({
            "type": "box", "name": "Painting_%d" % paint_idx,
            "position": [face_x - di * 0.08, yc, face_z - dj * 0.08],
            "size": canvas_size, "color": [0.9, 0.9, 0.9], "collision": False,
            "material_id": "painting",
        })
        paint_idx += 1

# ---- 消除 Z-fighting（贴图闪烁抖动）----
# 墙底面(y=0)与地板顶面(y=0)、墙顶面(y=WALL_H)与天花板底面(y=WALL_H)精确共面，
# 深度相等时 GPU 每帧随机决定谁在前 → 交界处贴图闪烁。
# 解法：让所有竖直墙类（wall/pillar：含边界墙、内墙、隔断、立柱、中央柱、矮箱）
# 沿 Y 上下各膨胀 EMBED，中心不变，使底面沉入地板、顶面插进天花板，彻底错开共面。
# 嵌入部分被地板/天花板遮住，肉眼不可见；对碰撞与 UV 平铺影响可忽略。
EMBED = 0.03
for _o in objects:
    if _o.get("type", "box") == "box" and _o.get("material_id") in ("wall", "pillar"):
        _sx, _sy, _sz = _o["size"]
        _o["size"] = [_sx, _sy + 2.0 * EMBED, _sz]

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
        "ambient_energy": 0.2,
        "fog_enabled": True,
        "fog_color": [0.045, 0.03, 0.032],
        "fog_density": 0.026,
        "tonemap": "filmic",
        "exposure": 0.9,
        "glow": True,
        "sun": {"rotation_degrees": [-70.0, 25.0, 0.0], "energy": 0.045, "color": [0.4, 0.28, 0.3], "shadow": False},
    },
    "materials": MATERIALS,
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
n_dead = sum(1 for c in cells if degree(c) == 1)
n_open = sum(1 for bi in range(N - 1) for bj in range(N - 1) if block_fully_open(bi, bj, passages))
print("  墙件=%d（含转角柱=%d）  天花板块=%d  灯座=%d  壁画=%d  中央立柱=%d  遮挡=%d  电视=%d" % (wall_idx, n_posts, ceil_idx, lamp_idx, paint_idx, core_idx, obstacle_idx, tv_idx))
print("  死路数=%d（应为0）  开阔小室=%d（均已用中央立柱围成回廊）" % (n_dead, n_open))
print("  常亮=%d  strobe=%d  flicker=%d  pulse=%d" %
      (len(lights) - n_strobe - n_flicker - n_pulse, n_strobe, n_flicker, n_pulse))
print("  runner_spawn=%s  tagger_spawn=%s" % (runner_spawn, tagger_spawn))
