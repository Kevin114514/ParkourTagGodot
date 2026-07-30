"""生成沙漠神殿写实 PBR-albedo 贴图（256x256）。

设计要点：贴图为「高明度细节图」，平均亮度接近白（~0.85），
花纹主要藏在压暗的缝隙/纹路里。这样在 Godot 中与物体自身的
沙色 albedo_color 相乘时，几乎不改变原有配色，只叠加表面质感，
避免整体压暗。配合线性各向异性过滤，得到平滑写实观感。
"""
import os
import math
import random
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
S = 256


def clampc(v):
    return max(0, min(255, int(v)))


def lerp(a, b, t):
    return a + (b - a) * t


def lerp3(c0, c1, t):
    return (lerp(c0[0], c1[0], t), lerp(c0[1], c1[1], t), lerp(c0[2], c1[2], t))


def noise_field(size, base_cells, octaves, persist, seed, aspect=1.0):
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


def make_sand(seed, name):
    """沙地：暖白细粒 + 低频起伏 + 风成波纹（正弦）+ 细颗粒高光。均值偏亮。"""
    base = (236, 224, 200)   # 近白暖沙
    dark = (198, 178, 142)   # 波纹阴影
    dune = noise_field(S, 6, 4, 0.55, seed)          # 低频起伏
    grain = noise_field(S, 90, 2, 0.5, seed + 3)     # 细颗粒
    img = Image.new("RGB", (S, S))
    px = img.load()
    for y in range(S):
        for x in range(S):
            d = dune[y][x]
            # 风成波纹：沿一个方向的正弦压暗
            ripple = 0.5 + 0.5 * math.sin((x * 0.6 + y * 0.18) + d * 3.0)
            t = 0.55 + 0.45 * d
            c = lerp3(dark, base, t)
            c = lerp3(c, dark, (1.0 - ripple) * 0.18)
            # 细颗粒明暗
            g = grain[y][x] - 0.5
            c = (c[0] + g * 20, c[1] + g * 18, c[2] + g * 14)
            px[x, y] = (clampc(c[0]), clampc(c[1]), clampc(c[2]))
    save(img, name)


def make_sandstone(seed, name, dark=False):
    """砂岩：纯沙粒颗粒面，无任何砖砌缝/砌块网格/方向性条纹。

    纹理全部来自多倍频噪声：细密沙粒（grain）+ 超高频沙点（stipple）
    + 低频矿物斑驳（patch）。均值偏亮，靠物体色调染沙色。
    """
    if dark:
        base = (216, 200, 168)
        mott = (192, 172, 138)      # 斑驳暗色
    else:
        base = (240, 228, 202)
        mott = (216, 200, 168)
    # 细密沙粒（高频，多倍频）—— 砂岩表面主质感
    grain = noise_field(S, 64, 3, 0.5, seed + 1)
    # 超高频沙点（单粒沙感，颗粒粗糙）
    stipple = noise_field(S, 140, 2, 0.5, seed + 13)
    # 中频斑驳（矿物色块，不规则、无方向性）
    patch = noise_field(S, 12, 3, 0.55, seed + 5)
    img = Image.new("RGB", (S, S))
    px = img.load()
    for y in range(S):
        for x in range(S):
            # 不规则矿物斑驳（无方向性）
            p = patch[y][x]
            c = lerp3(mott, base, 0.30 + 0.70 * p)
            # 细密沙粒明暗（高频颗粒）
            g = grain[y][x] - 0.5
            c = (c[0] + g * 40, c[1] + g * 36, c[2] + g * 28)
            # 超高频沙点：模拟一粒粒沙子的粗糙感
            s = stipple[y][x] - 0.5
            c = (c[0] + s * 22, c[1] + s * 20, c[2] + s * 16)
            px[x, y] = (clampc(c[0]), clampc(c[1]), clampc(c[2]))
    save(img, name)


def make_wood(seed, name):
    """宝箱旧木：竖向木板 + 板缝暗线 + 木纹 + 铁包角暗点。均值偏亮。"""
    base = (226, 206, 170)
    seam = (150, 120, 84)
    grain = noise_field(S, 6, 4, 0.55, seed, aspect=6.0)   # 竖纹
    fine = noise_field(S, 40, 3, 0.5, seed + 4)
    img = Image.new("RGB", (S, S))
    px = img.load()
    planks = 5
    pw = S / planks
    rnd = random.Random(seed)
    tint = [rnd.uniform(-0.06, 0.06) for _ in range(planks + 1)]
    for y in range(S):
        for x in range(S):
            idx = int(x / pw)
            inp = (x - idx * pw) / pw
            g = grain[y][x]
            shade = 0.7 + 0.5 * g + 0.1 * (fine[y][x] - 0.5)
            shade += tint[idx]
            c = lerp3(seam, base, max(0.0, min(1.3, shade)))
            edge = min(inp, 1.0 - inp)
            if edge < 0.05:
                c = lerp3(seam, c, edge / 0.05)
            px[x, y] = (clampc(c[0]), clampc(c[1]), clampc(c[2]))
    save(img, name)


def make_gold(seed, name):
    """抛光金：暖白金属底 + 拉丝竖纹 + 细划痕 + 高光。均值高亮，靠色调染成金色。"""
    base = (248, 240, 214)
    low = (214, 196, 150)
    brush = noise_field(S, 4, 3, 0.5, seed, aspect=8.0)   # 竖向拉丝
    scratch = noise_field(S, 70, 2, 0.5, seed + 6)
    img = Image.new("RGB", (S, S))
    px = img.load()
    for y in range(S):
        for x in range(S):
            b = brush[y][x]
            c = lerp3(low, base, 0.3 + 0.7 * b)
            s = scratch[y][x]
            if s > 0.78:
                c = lerp3(c, (255, 252, 236), (s - 0.78) / 0.22 * 0.6)
            elif s < 0.12:
                c = lerp3(c, low, (0.12 - s) / 0.12 * 0.4)
            px[x, y] = (clampc(c[0]), clampc(c[1]), clampc(c[2]))
    save(img, name)


if __name__ == "__main__":
    make_sand(101, "sand.png")
    make_sandstone(211, "sandstone.png", dark=False)
    make_sandstone(307, "sandstone_dark.png", dark=True)
    make_wood(419, "chest_wood.png")
    make_gold(523, "gold.png")
    print("done")
