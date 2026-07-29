"""生成 256x256 写实风格 PBR-albedo 贴图（覆盖同名文件）。

从早期 16/32 像素风改为写实路线：
- 分辨率提升到 256，去马赛克；
- 用多层 value noise(fbm) 合成连续、自然的材质纹理，而非硬边像素块；
- 木纹带方向性拉伸 + 年轮木节，石面带卵石缝与苔藓渗透，
  地毯带织物经纬 + 磨损破洞，枝叶带明暗叶簇通透感。
配合地图去掉 nearest 过滤、恢复线性各向异性，得到平滑写实观感。
"""
import os
import math
import random
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
S = 256  # 写实分辨率


def clampc(v):
    return max(0, min(255, int(v)))


def lerp(a, b, t):
    return a + (b - a) * t


def lerp3(c0, c1, t):
    return (lerp(c0[0], c1[0], t), lerp(c0[1], c1[1], t), lerp(c0[2], c1[2], t))


def noise_field(size, base_cells, octaves, persist, seed, aspect=1.0):
    """多层 value noise（fbm）。返回 size×size 的 [0,1] 浮点二维数组。
    低频随机格点用 BICUBIC 放大得到平滑层，逐层叠加。
    aspect<1 让水平方向变化更慢（纹理沿水平拉长，用于木纹）。"""
    field = [[0.0] * size for _ in range(size)]
    amp = 1.0
    total = 0.0
    cells = base_cells
    for o in range(octaves):
        cx = max(2, int(round(cells * aspect)))
        cy = max(2, cells)
        rnd = random.Random(seed * 1009 + o * 97)
        small = Image.new("L", (cx, cy))
        small.putdata([rnd.randint(0, 255) for _ in range(cx * cy)])
        big = small.resize((size, size), Image.BICUBIC)
        bpx = big.load()
        for y in range(size):
            row = field[y]
            for x in range(size):
                row[x] += amp * (bpx[x, y] / 255.0)
        total += amp
        amp *= persist
        cells *= 2
    inv = 1.0 / total
    for y in range(size):
        row = field[y]
        for x in range(size):
            row[x] *= inv
    return field


def save(img, name):
    img = img.filter(ImageFilter.SMOOTH_MORE)
    img.save(os.path.join(HERE, name))
    print("saved", name)


def make_planks(base, seam, knot, seed, name, planks=6, horizontal=True):
    """写实木板：沿板长方向拉长的木纹 + 板缝暗线 + 随机年轮木节 + 端头微阴影。"""
    grain = noise_field(S, 6, 4, 0.55, seed, aspect=0.14)      # 长木纹
    fine = noise_field(S, 48, 3, 0.5, seed + 5, aspect=0.5)    # 细纹理
    img = Image.new("RGB", (S, S))
    px = img.load()
    plank_w = S / planks
    rnd = random.Random(seed)
    # 每块板一个整体色偏，模拟不同木料
    plank_tint = [rnd.uniform(-0.10, 0.10) for _ in range(planks + 1)]
    # 木节中心
    knots = [(rnd.randint(0, S - 1), rnd.randint(0, S - 1), rnd.uniform(6, 14))
             for _ in range(rnd.randint(4, 7))]
    for y in range(S):
        for x in range(S):
            # 板方向：horizontal 时板缝为竖线，木纹沿水平
            along = x if horizontal else y
            cross = y if horizontal else x
            idx = int(cross / plank_w)
            in_plank = (cross - idx * plank_w) / plank_w
            g = grain[y][x]
            f = fine[y][x]
            shade = 0.72 + 0.5 * g + 0.10 * (f - 0.5)
            shade += plank_tint[idx]
            # 板缝：跨向靠近边界压暗
            edge = min(in_plank, 1.0 - in_plank)
            if edge < 0.045:
                shade *= 0.45 + edge / 0.045 * 0.4
            c = lerp3(seam, base, max(0.0, min(1.35, shade)) / 1.0)
            # 年轮木节
            for (kx, ky, kr) in knots:
                d = math.hypot(x - kx, y - ky)
                if d < kr:
                    ring = 0.5 + 0.5 * math.cos(d * 1.4)
                    kk = lerp3(knot, base, 0.3 + 0.4 * ring)
                    w = 1.0 - d / kr
                    c = lerp3(c, kk, w * 0.85)
            px[x, y] = (clampc(c[0]), clampc(c[1]), clampc(c[2]))
    save(img, name)


def make_cobble(base_dark, base_light, seam, moss, mossy, seed, name):
    """写实苔藓石面：fbm 灰岩起伏 + 卵石缝网 + 低洼处苔藓渗透 + 高光。"""
    body = noise_field(S, 5, 5, 0.55, seed)
    stone = noise_field(S, 14, 2, 0.5, seed + 3)     # 卵石块分布
    crack = noise_field(S, 20, 3, 0.5, seed + 7)     # 缝隙
    mo = noise_field(S, 8, 4, 0.6, seed + 11)        # 苔藓分布
    img = Image.new("RGB", (S, S))
    px = img.load()
    for y in range(S):
        for x in range(S):
            t = body[y][x] * 0.7 + stone[y][x] * 0.3
            c = lerp3(base_dark, base_light, t)
            # 缝隙：crack 极值处压暗成石缝
            cv = crack[y][x]
            gap = min(cv, 1.0 - cv)
            if gap < 0.14:
                c = lerp3(seam, c, gap / 0.14)
            # 高光点缀
            if t > 0.82:
                c = lerp3(c, (185, 185, 185), (t - 0.82) / 0.18 * 0.5)
            # 苔藓：湿润低洼 + 苔噪聚集处渗绿
            if mossy:
                m = mo[y][x] * (1.0 - body[y][x] * 0.6)
                if m > 0.5:
                    mw = min(1.0, (m - 0.5) / 0.35)
                    c = lerp3(c, moss, mw * 0.8)
            px[x, y] = (clampc(c[0]), clampc(c[1]), clampc(c[2]))
    save(img, name)


def make_carpet(base, dark, thread, seed, name):
    """写实破旧地毯：暗红羊毛 + 经纬织纹 + 低频磨损褪色 + 破洞露底。"""
    wool = noise_field(S, 10, 4, 0.55, seed)
    wear = noise_field(S, 5, 3, 0.5, seed + 4)       # 磨损斑
    holes = noise_field(S, 7, 3, 0.55, seed + 9)     # 破洞
    img = Image.new("RGB", (S, S))
    px = img.load()
    for y in range(S):
        for x in range(S):
            c = lerp3(dark, base, 0.4 + 0.6 * wool[y][x])
            # 经纬织纹：正弦交织
            weave = 0.5 + 0.5 * math.sin(x * 0.9) * math.sin(y * 0.9)
            c = lerp3(c, thread, weave * 0.18)
            # 磨损褪色（变亮泛白）
            w = wear[y][x]
            if w > 0.62:
                c = lerp3(c, (150, 120, 110), (w - 0.62) / 0.38 * 0.55)
            # 破洞：露出深色底
            h = holes[y][x]
            if h < 0.16:
                c = lerp3(dark, c, h / 0.16)
            px[x, y] = (clampc(c[0]), clampc(c[1]), clampc(c[2]))
    save(img, name)


def make_leaves(base, dark, light, seed, name):
    """写实橡树枝叶：绿色 fbm 明暗 + 叶簇团块 + 暗色间隙通透 + 亮叶尖。"""
    canopy = noise_field(S, 7, 5, 0.6, seed)
    detail = noise_field(S, 30, 3, 0.5, seed + 6)
    gap = noise_field(S, 12, 4, 0.55, seed + 13)
    img = Image.new("RGB", (S, S))
    px = img.load()
    for y in range(S):
        for x in range(S):
            t = canopy[y][x]
            c = lerp3(dark, light, t)
            c = lerp3(c, base, 0.35)
            # 细叶纹
            d = detail[y][x]
            c = lerp3(c, light, (d - 0.5) * 0.3 if d > 0.5 else 0.0)
            # 叶间暗缝通透
            g = gap[y][x]
            if g < 0.24:
                c = lerp3(dark, c, g / 0.24)
            # 亮叶尖高光
            if t > 0.8 and d > 0.6:
                c = lerp3(c, (150, 200, 110), 0.4)
            px[x, y] = (clampc(c[0]), clampc(c[1]), clampc(c[2]))
    save(img, name)


if __name__ == "__main__":
    make_planks((176, 140, 86), (86, 62, 34), (104, 74, 40), 11, "old_plank_floor.png", planks=6, horizontal=True)
    make_planks((92, 62, 36), (40, 26, 14), (58, 38, 20), 23, "mossy_dark_oak.png", planks=5, horizontal=False)
    make_cobble((92, 92, 94), (150, 150, 152), (54, 54, 56), (74, 104, 46), True, 37, "mossy_stone.png")
    make_carpet((150, 42, 40), (66, 20, 20), (182, 96, 78), 53, "tattered_carpet.png")
    make_leaves((46, 96, 40), (24, 56, 22), (104, 158, 70), 71, "oak_leaves.png")
    print("done")
