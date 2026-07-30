"""生成冬日小镇「暖光窗户」卡通贴图（256x256）。

产出两张：
  window_glow.png          —— albedo（暖黄玻璃 + 深木窗框 + 十字窗棂 + 玻璃反光 + 底部积雪）
  window_glow_emission.png —— emission 遮罩（仅玻璃格发暖光，窗框/积雪不发光）

风格：手绘卡通暖色调，和冬日小镇夜晚亮灯的木屋窗户一致。
在 Godot 中：albedo_texture 提供窗户外观，emission_texture 让玻璃自发光。
"""
import os
import math
import random
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
S = 256


def clampc(v):
    return max(0, min(255, int(v)))


def lerp(a, b, t):
    return a + (b - a) * t


def lerp3(c0, c1, t):
    return (lerp(c0[0], c1[0], t), lerp(c0[1], c1[1], t), lerp(c0[2], c1[2], t))


def make_window():
    # ---- 颜色 ----
    frame_dark = (74, 46, 26)      # 深木窗框
    frame_light = (112, 74, 44)    # 木框高光
    glass_hi = (255, 236, 176)     # 玻璃中心亮暖黄
    glass_lo = (238, 176, 74)      # 玻璃边缘暖橙
    snow = (240, 244, 250)         # 底部积雪
    snow_shadow = (206, 216, 230)

    img = Image.new("RGB", (S, S))
    px = img.load()
    rnd = random.Random(7)

    frame = int(S * 0.10)          # 外框厚度
    mull = int(S * 0.045)          # 窗棂（十字）半宽
    cx = S // 2
    cy = S // 2

    for y in range(S):
        for x in range(S):
            # 外框区域
            in_frame = (x < frame or x >= S - frame or y < frame or y >= S - frame)
            # 十字窗棂
            in_mull = (abs(x - cx) < mull or abs(y - cy) < mull)

            if in_frame or in_mull:
                # 木框：带竖木纹明暗
                g = 0.5 + 0.5 * math.sin(y * 0.15 + x * 0.05)
                c = lerp3(frame_dark, frame_light, 0.25 + 0.5 * g)
                # 外框边缘做一点立体高光
                if in_frame:
                    edge = min(x, y, S - 1 - x, S - 1 - y)
                    if edge < 4:
                        c = lerp3(c, (150, 104, 66), 1.0 - edge / 4.0)
                px[x, y] = (clampc(c[0]), clampc(c[1]), clampc(c[2]))
            else:
                # 玻璃：从每个窗格中心向外的径向暖光渐变
                # 计算当前格中心（四格之一）
                qx = frame + (S - 2 * frame) * 0.25 if x < cx else frame + (S - 2 * frame) * 0.75
                qy = frame + (S - 2 * frame) * 0.25 if y < cy else frame + (S - 2 * frame) * 0.75
                half = (S - 2 * frame - 2 * mull) * 0.25
                dx = (x - qx) / max(1.0, half)
                dy = (y - qy) / max(1.0, half)
                d = min(1.0, math.sqrt(dx * dx + dy * dy))
                t = 1.0 - d
                c = lerp3(glass_lo, glass_hi, max(0.0, min(1.0, t)))
                # 斜向玻璃反光条
                shine = math.sin((x + y) * 0.08)
                if shine > 0.85:
                    c = lerp3(c, (255, 252, 236), (shine - 0.85) / 0.15 * 0.55)
                # 轻微暖噪点
                n = (rnd.random() - 0.5) * 10
                c = (c[0] + n, c[1] + n * 0.8, c[2] + n * 0.4)
                px[x, y] = (clampc(c[0]), clampc(c[1]), clampc(c[2]))

    # ---- 底部积雪堆（窗台雪） ----
    draw = ImageDraw.Draw(img)
    snow_top = int(S * 0.80)
    for x in range(S):
        # 起伏的雪面
        hump = math.sin(x * 0.05) * 6 + math.sin(x * 0.13 + 1.0) * 4
        top = int(snow_top + hump)
        for y in range(top, S):
            tt = (y - top) / max(1.0, (S - top))
            c = lerp3(snow, snow_shadow, tt * 0.6)
            # 雪面细颗粒高光
            if rnd.random() > 0.94:
                c = (255, 255, 255)
            px[x, y] = (clampc(c[0]), clampc(c[1]), clampc(c[2]))

    img = img.filter(ImageFilter.SMOOTH)
    img.save(os.path.join(HERE, "window_glow.png"))
    print("saved window_glow.png")

    # ---- emission 遮罩：玻璃发光，木框/积雪不发光 ----
    emis = Image.new("RGB", (S, S), (0, 0, 0))
    epx = emis.load()
    for y in range(S):
        for x in range(S):
            in_frame = (x < frame or x >= S - frame or y < frame or y >= S - frame)
            in_mull = (abs(x - cx) < mull or abs(y - cy) < mull)
            # 积雪区域
            hump = math.sin(x * 0.05) * 6 + math.sin(x * 0.13 + 1.0) * 4
            in_snow = y >= int(S * 0.80 + hump)
            if in_frame or in_mull or in_snow:
                epx[x, y] = (0, 0, 0)
            else:
                # 玻璃暖光，中心更亮
                qx = frame + (S - 2 * frame) * 0.25 if x < cx else frame + (S - 2 * frame) * 0.75
                qy = frame + (S - 2 * frame) * 0.25 if y < cy else frame + (S - 2 * frame) * 0.75
                half = (S - 2 * frame - 2 * mull) * 0.25
                dx = (x - qx) / max(1.0, half)
                dy = (y - qy) / max(1.0, half)
                d = min(1.0, math.sqrt(dx * dx + dy * dy))
                v = 0.55 + 0.45 * (1.0 - d)
                epx[x, y] = (clampc(255 * v), clampc(150 * v), clampc(40 * v))
    emis = emis.filter(ImageFilter.SMOOTH)
    emis.save(os.path.join(HERE, "window_glow_emission.png"))
    print("saved window_glow_emission.png")


if __name__ == "__main__":
    make_window()
    print("done")
