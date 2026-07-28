import argparse
import json
import math
import random
from collections import defaultdict, deque
from pathlib import Path

MOVE_ACTIONS = [
    (1, 0),
    (-1, 0),
    (0, 1),
    (0, -1),
    (1, 1),
    (1, -1),
    (-1, 1),
    (-1, -1),
]
CATCH_ACTION = (0, 0)
ACTIONS = MOVE_ACTIONS + [CATCH_ACTION]
CATCH_ACTION_INDEX = len(ACTIONS) - 1
MAX_RELATIVE_CELLS = 14
CATCH_DISTANCE_CELLS = 1.0
# 走进虚空（脚下没有 L1 地面）的死亡惩罚，"reward = -无穷" 的工程近似。
VOID_DEATH_REWARD = -1000.0
# 判定 L1 可站立地面的高度上限：只有 y 接近 0 的薄板才算 L1 路面，
# 高层平台（L2 y≈8 / L3 y≈16）压平后不应被当成 L1 可走地。
L1_FLOOR_MAX_Y = 3.0
# L1 障碍高度上限：底部高于此值的结构（上层地板/走廊/天花板）在 L1 人物头顶之上，
# 地面追捕者从下方穿过，不算障碍。约 L1 人物身高 1.8m + 余量。
L1_OBSTACLE_TOP_Y = 2.2
# 追捕者助跑跳跃可跨越的缺口宽度（格）。tagger.gd 跳跃覆盖约 7.4m，cell_size≈2 → 约 3 格。
GAP_JUMP_CELLS = 3
# 可直接迈过的矮镶边/门槛/台阶顶面高度上限（m）。顶面低于此值不算障碍。
L1_STEP_OVER_Y = 1.1


def load_map(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def object_bounds(obj: dict) -> tuple[float, float, float, float] | None:
    pos = obj.get("position", [0.0, 0.0, 0.0])
    x, _, z = float(pos[0]), float(pos[1]), float(pos[2])
    typ = str(obj.get("type", "box"))
    if typ == "box":
        size = obj.get("size", [1.0, 1.0, 1.0])
        return x - float(size[0]) * 0.5, x + float(size[0]) * 0.5, z - float(size[2]) * 0.5, z + float(size[2]) * 0.5
    if typ in ("cylinder", "sphere", "capsule"):
        radius = float(obj.get("radius", 0.5))
        if typ == "capsule":
            height = float(obj.get("height", radius * 2.0))
            radius = max(radius, height * 0.5)
        return x - radius, x + radius, z - radius, z + radius
    return None


def build_grid(map_data: dict, cell_size: float, agent_radius: float) -> dict:
    ground_bounds = None
    for obj in map_data.get("objects", []):
        if obj.get("type") != "box":
            continue
        name = str(obj.get("name", "")).lower()
        size = obj.get("size", [0.0, 0.0, 0.0])
        if "ground" in name or (len(size) >= 3 and float(size[1]) <= 0.35 and float(size[0]) > 10.0 and float(size[2]) > 10.0):
            ground_bounds = object_bounds(obj)
            break
    if ground_bounds is None:
        all_bounds = [b for b in (object_bounds(o) for o in map_data.get("objects", [])) if b is not None]
        min_x = min(b[0] for b in all_bounds) - 2.0
        max_x = max(b[1] for b in all_bounds) + 2.0
        min_z = min(b[2] for b in all_bounds) - 2.0
        max_z = max(b[3] for b in all_bounds) + 2.0
    else:
        min_x, max_x, min_z, max_z = ground_bounds

    width = int(math.floor((max_x - min_x) / cell_size)) + 1
    height = int(math.floor((max_z - min_z) / cell_size)) + 1
    blocked = [[False for _ in range(height)] for _ in range(width)]

    obstacle_bounds = []
    # L1 可站立地面（实心平台 + 追捕者能助跑跳过的断桥缺口 Gap）的覆盖范围。
    floor_bounds = []
    for obj in map_data.get("objects", []):
        name = str(obj.get("name", "")).lower()
        typ = str(obj.get("type", "box"))
        size = obj.get("size", [0.0, 0.0, 0.0])
        y = float(obj.get("position", [0.0, 0.0, 0.0])[1])
        collision = str(obj.get("collision", "")).lower()
        bounds = object_bounds(obj)

        is_thin = typ == "box" and len(size) >= 3 and float(size[1]) <= 0.6
        is_l1 = y <= L1_FLOOR_MAX_Y  # 仅 L1 层：地面追捕者上不去 L2(y≈8)/L3(y≈16)。
        # 实心 L1 落脚面：主地面、pad，或 y 接近 0 的薄板路面（排除无碰撞装饰）。
        solid_floor = collision != "none" and is_l1 and (
            "ground" in name or "pad" in name or "floor" in name or "path" in name
            or ("bridge" in name and "gap" not in name)
            or "plaza" in name or "court" in name or "hub" in name
            or (is_thin and "rail" not in name and "wall" not in name and "trim" not in name)
        )
        # 断桥缺口（collision:none 的 Gap）：游戏里追捕者会助跑跳过（见 tagger.gd
        # _gap_edge_ahead/_has_landing_across_gap），所以训练网格中视为可通过，而非致命虚空。
        crossable_gap = is_l1 and "gap" in name and collision == "none"
        if (solid_floor or crossable_gap) and bounds is not None:
            floor_bounds.append(bounds)

        if "ground" in name or "pad" in name:
            continue
        if typ == "box" and len(size) >= 3 and float(size[1]) <= 0.25:
            continue
        if typ == "box" and y < 0.15 and float(size[1]) < 0.65:
            continue
        obj_top = y + (float(size[1]) * 0.5 if typ == "box" and len(size) >= 3 else 0.0)
        obj_bottom = y - (float(size[1]) * 0.5 if typ == "box" and len(size) >= 3 else 0.0)
        # 矮镶边 / 门槛 / 台阶（trim、curb、ledge、step 等）顶面很低，玩家可直接迈过，
        # 不应把整条 Hub 边缘封成墙。顶面低于可跨越高度即放行。
        low_curb = typ == "box" and obj_top <= L1_STEP_OVER_Y
        curb_named = any(k in name for k in ("trim", "curb", "ledge", "step", "border", "edge"))
        if low_curb and (curb_named or obj_top <= 1.0):
            continue
        # 上层结构（L2/L3 的地板、走廊、天花板、楼梯高段等）底部远高于 L1 人物头顶，
        # L1 追捕者从下方穿过，不构成障碍。仅用底部高度过滤，避免把整座 Hub 误判成墙。
        if obj_bottom > L1_OBSTACLE_TOP_Y:
            continue
        if bounds is not None:
            obstacle_bounds.append(bounds)

    # 若地图没有显式主地面（依赖各平台拼接），把兜底大边界也算作地面，避免整图判虚空。
    has_explicit_floor = bool(floor_bounds)

    void = [[False for _ in range(height)] for _ in range(width)]
    for gx in range(width):
        for gz in range(height):
            x = min_x + gx * cell_size
            z = min_z + gz * cell_size
            for bx0, bx1, bz0, bz1 in obstacle_bounds:
                if bx0 - agent_radius <= x <= bx1 + agent_radius and bz0 - agent_radius <= z <= bz1 + agent_radius:
                    blocked[gx][gz] = True
                    break
            if has_explicit_floor and not blocked[gx][gz]:
                supported = False
                for fx0, fx1, fz0, fz1 in floor_bounds:
                    if fx0 - agent_radius <= x <= fx1 + agent_radius and fz0 - agent_radius <= z <= fz1 + agent_radius:
                        supported = True
                        break
                if not supported:
                    void[gx][gz] = True

    # 后处理：把「窄缺口」上的 void 恢复为可通过。
    # 游戏里追捕者会助跑跳越断桥缺口（tagger.gd 覆盖约 7.4m ≈ 4 格），
    # 因此一段 void 若在四个正交方向中任一方向的两端 GAP_JUMP_CELLS 格内都有实心地面，
    # 判定为「可跳越缺口」而非致命虚空，避免地图被断桥切成互不连通的孤岛。
    def _solid(cx: int, cz: int) -> bool:
        return 0 <= cx < width and 0 <= cz < height and not blocked[cx][cz] and not void[cx][cz]

    crossable = [[False for _ in range(height)] for _ in range(width)]
    for gx in range(width):
        for gz in range(height):
            if not void[gx][gz]:
                continue
            for dx, dz in ((1, 0), (0, 1)):
                # 向负方向找最近实心地面
                neg_ok = False
                for step in range(1, GAP_JUMP_CELLS + 1):
                    cx, cz = gx - dx * step, gz - dz * step
                    if not (0 <= cx < width and 0 <= cz < height) or blocked[cx][cz]:
                        break
                    if _solid(cx, cz):
                        neg_ok = True
                        break
                if not neg_ok:
                    continue
                pos_ok = False
                for step in range(1, GAP_JUMP_CELLS + 1):
                    cx, cz = gx + dx * step, gz + dz * step
                    if not (0 <= cx < width and 0 <= cz < height) or blocked[cx][cz]:
                        break
                    if _solid(cx, cz):
                        pos_ok = True
                        break
                if pos_ok:
                    crossable[gx][gz] = True
                    break
    for gx in range(width):
        for gz in range(height):
            if crossable[gx][gz]:
                void[gx][gz] = False

    return {
        "min_x": min_x,
        "max_x": max_x,
        "min_z": min_z,
        "max_z": max_z,
        "width": width,
        "height": height,
        "blocked": blocked,
        "void": void,
        "cell_size": cell_size,
    }


def world_to_cell(grid: dict, pos: list[float]) -> tuple[int, int]:
    gx = int(math.floor((float(pos[0]) - grid["min_x"]) / grid["cell_size"]))
    gz = int(math.floor((float(pos[2]) - grid["min_z"]) / grid["cell_size"]))
    return clamp_cell(grid, (gx, gz))


def clamp_cell(grid: dict, cell: tuple[int, int]) -> tuple[int, int]:
    return max(0, min(grid["width"] - 1, cell[0])), max(0, min(grid["height"] - 1, cell[1]))


def is_void(grid: dict, cell: tuple[int, int]) -> bool:
    x, z = cell
    if not (0 <= x < grid["width"] and 0 <= z < grid["height"]):
        return True
    return bool(grid.get("void", [[False]])[x][z])


def is_free(grid: dict, cell: tuple[int, int]) -> bool:
    """可安全站立：在界内、非障碍、且脚下有地面（非虚空）。"""
    x, z = cell
    if not (0 <= x < grid["width"] and 0 <= z < grid["height"]):
        return False
    return not grid["blocked"][x][z] and not is_void(grid, cell)


def nearest_free(grid: dict, start: tuple[int, int]) -> tuple[int, int]:
    if is_free(grid, start):
        return start
    q = deque([start])
    seen = {start}
    while q:
        cell = q.popleft()
        for dx, dz in MOVE_ACTIONS:
            nxt = (cell[0] + dx, cell[1] + dz)
            if nxt in seen or not (0 <= nxt[0] < grid["width"] and 0 <= nxt[1] < grid["height"]):
                continue
            if is_free(grid, nxt):
                return nxt
            seen.add(nxt)
            q.append(nxt)
    raise RuntimeError("map has no free cell")


def random_free_cell(grid: dict) -> tuple[int, int]:
    while True:
        cell = (random.randrange(grid["width"]), random.randrange(grid["height"]))
        if is_free(grid, cell):
            return cell


def distance(a: tuple[int, int], b: tuple[int, int]) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def blocked_mask(grid: dict, agent: tuple[int, int]) -> int:
    mask = 0
    for i, (dx, dz) in enumerate(MOVE_ACTIONS):
        if not is_free(grid, (agent[0] + dx, agent[1] + dz)):
            mask |= 1 << i
    return mask


def state_key(grid: dict, agent: tuple[int, int], target: tuple[int, int]) -> tuple[int, int, int]:
    dx = max(-MAX_RELATIVE_CELLS, min(MAX_RELATIVE_CELLS, target[0] - agent[0]))
    dz = max(-MAX_RELATIVE_CELLS, min(MAX_RELATIVE_CELLS, target[1] - agent[1]))
    return dx, dz, blocked_mask(grid, agent)


def candidate_starts(grid: dict, runner_spawn: tuple[int, int], tagger_spawn: tuple[int, int]) -> list[tuple[tuple[int, int], tuple[int, int]]]:
    starts = [(tagger_spawn, runner_spawn)]
    for gx in range(1, grid["width"] - 1, 3):
        for gz in range(1, grid["height"] - 1, 3):
            agent = (gx, gz)
            if not is_free(grid, agent):
                continue
            for tx, tz in ((grid["width"] - 2 - gx, grid["height"] - 2 - gz), (gx, grid["height"] - 2 - gz), (grid["width"] - 2 - gx, gz)):
                target = nearest_free(grid, clamp_cell(grid, (tx, tz)))
                if distance(agent, target) > 4.0:
                    starts.append((agent, target))
    return starts


def train(grid: dict, runner_spawn: tuple[int, int], tagger_spawn: tuple[int, int], episodes: int, max_steps: int, seed: int) -> tuple[dict, dict]:
    random.seed(seed)
    q = defaultdict(lambda: [0.0] * len(ACTIONS))
    alpha = 0.22
    gamma = 0.92
    epsilon = 0.45
    epsilon_min = 0.04
    successes = 0
    steps_when_success = []
    starts = candidate_starts(grid, runner_spawn, tagger_spawn)

    for episode in range(episodes):
        agent, target = starts[episode % len(starts)] if episode % 4 == 0 else random.choice(starts)
        if agent == target:
            target = random_free_cell(grid)
        epsilon = max(epsilon_min, epsilon * 0.999)
        last_dist = distance(agent, target)

        for step in range(max_steps):
            key = state_key(grid, agent, target)
            if random.random() < epsilon:
                action_index = random.randrange(len(ACTIONS))
            else:
                action_index = max(range(len(ACTIONS)), key=lambda i: q[key][i])

            if action_index == CATCH_ACTION_INDEX:
                reward = 14.0 if last_dist <= CATCH_DISTANCE_CELLS else -1.2 - min(last_dist, 8.0) * 0.08
                next_key = key
                q[key][action_index] += alpha * (reward + gamma * max(q[next_key]) - q[key][action_index])
                if last_dist <= CATCH_DISTANCE_CELLS:
                    successes += 1
                    steps_when_success.append(step + 1)
                    break
                continue

            dx, dz = ACTIONS[action_index]
            nxt = (agent[0] + dx, agent[1] + dz)

            # 踏空：目标格是虚空（脚下没有 L1 地面）→ 直接坠落身亡，巨额负奖励并终止回合。
            if is_void(grid, nxt):
                q[key][action_index] += alpha * (VOID_DEATH_REWARD - q[key][action_index])
                break

            hit_block = not is_free(grid, nxt)
            if hit_block:
                nxt = agent

            new_dist = distance(nxt, target)
            reward = (last_dist - new_dist) * 1.0 - 0.025
            if hit_block:
                reward -= 0.45
            if new_dist <= CATCH_DISTANCE_CELLS:
                reward += 0.8

            next_key = state_key(grid, nxt, target)
            q[key][action_index] += alpha * (reward + gamma * max(q[next_key]) - q[key][action_index])
            agent = nxt
            last_dist = new_dist

    metrics = evaluate(grid, q, runner_spawn, tagger_spawn, max_steps, seed + 1)
    metrics["train_success_rate"] = successes / max(1, episodes)
    metrics["train_avg_success_steps"] = sum(steps_when_success) / max(1, len(steps_when_success))
    metrics["states"] = len(q)
    return q, metrics


def greedy_action(q: dict, key: tuple[int, int, int]) -> int | None:
    if key not in q:
        return None
    values = q[key]
    return max(range(len(values)), key=lambda i: values[i])


def fallback_action(grid: dict, agent: tuple[int, int], target: tuple[int, int]) -> int:
    if distance(agent, target) <= CATCH_DISTANCE_CELLS:
        return CATCH_ACTION_INDEX
    best = 0
    best_dist = 1e9
    for i, (dx, dz) in enumerate(MOVE_ACTIONS):
        nxt = (agent[0] + dx, agent[1] + dz)
        if not is_free(grid, nxt):
            continue
        d = distance(nxt, target)
        if d < best_dist:
            best_dist = d
            best = i
    return best


def evaluate(grid: dict, q: dict, runner_spawn: tuple[int, int], tagger_spawn: tuple[int, int], max_steps: int, seed: int) -> dict:
    random.seed(seed)
    cases = [(tagger_spawn, runner_spawn)]
    for _ in range(199):
        agent = random_free_cell(grid)
        target = random_free_cell(grid)
        if distance(agent, target) > 4.0:
            cases.append((agent, target))

    successes = 0
    total_steps = 0
    fallback_actions = 0
    for agent, target in cases:
        for step in range(max_steps):
            key = state_key(grid, agent, target)
            action_index = greedy_action(q, key)
            if action_index is None:
                fallback_actions += 1
                action_index = fallback_action(grid, agent, target)
            if action_index == CATCH_ACTION_INDEX:
                if distance(agent, target) <= CATCH_DISTANCE_CELLS:
                    successes += 1
                    total_steps += step + 1
                    break
                fallback_actions += 1
                action_index = fallback_action(grid, agent, target)
                if action_index == CATCH_ACTION_INDEX:
                    continue
            dx, dz = ACTIONS[action_index]
            nxt = (agent[0] + dx, agent[1] + dz)
            if is_free(grid, nxt):
                agent = nxt
            else:
                fallback_actions += 1
                action_index = fallback_action(grid, agent, target)
                if action_index == CATCH_ACTION_INDEX:
                    if distance(agent, target) <= CATCH_DISTANCE_CELLS:
                        successes += 1
                        total_steps += step + 1
                        break
                    continue
                dx, dz = ACTIONS[action_index]
                nxt = (agent[0] + dx, agent[1] + dz)
                if is_free(grid, nxt):
                    agent = nxt
        else:
            total_steps += max_steps

    return {
        "eval_success_rate": successes / len(cases),
        "eval_avg_steps": total_steps / len(cases),
        "eval_cases": len(cases),
        "eval_fallback_actions": fallback_actions,
    }


def export_policy(path: Path, map_path: Path, map_data: dict, grid: dict, q: dict, metrics: dict, seed: int) -> None:
    policy = {}
    for key, values in q.items():
        action_index = max(range(len(values)), key=lambda i: values[i])
        policy[",".join(str(v) for v in key)] = action_index

    out = {
        "metadata": {
            "algorithm": "tabular_q_learning_relative_obstacle_mask_with_catch",
            "source_map": map_path.as_posix(),
            "map_name": map_data.get("name", map_path.stem),
            "seed": seed,
            "cell_size": grid["cell_size"],
            "max_relative_cells": MAX_RELATIVE_CELLS,
            "catch_action_index": CATCH_ACTION_INDEX,
            "catch_distance_cells": CATCH_DISTANCE_CELLS,
            "bounds": {
                "min_x": grid["min_x"],
                "max_x": grid["max_x"],
                "min_z": grid["min_z"],
                "max_z": grid["max_z"],
                "width": grid["width"],
                "height": grid["height"],
            },
            "actions": ACTIONS,
            "metrics": metrics,
        },
        "policy": policy,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))


def main() -> None:
    parser = argparse.ArgumentParser(description="Train a small tabular RL pathfinding policy for ParkourTag maps.")
    parser.add_argument("--map", default="maps/ring_training.json")
    parser.add_argument("--out", default="rl/trained_policy.json")
    parser.add_argument("--episodes", type=int, default=10000)
    parser.add_argument("--max-steps", type=int, default=120)
    parser.add_argument("--cell-size", type=float, default=2.0)
    parser.add_argument("--agent-radius", type=float, default=0.45)
    parser.add_argument("--seed", type=int, default=114514)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    map_path = (root / args.map).resolve()
    out_path = (root / args.out).resolve()
    map_data = load_map(map_path)
    grid = build_grid(map_data, args.cell_size, args.agent_radius)
    runner_spawn = nearest_free(grid, world_to_cell(grid, map_data.get("runner_spawn", [0.0, 0.0, 0.0])))
    tagger_spawn = nearest_free(grid, world_to_cell(grid, map_data.get("tagger_spawn", [0.0, 0.0, 0.0])))
    q, metrics = train(grid, runner_spawn, tagger_spawn, args.episodes, args.max_steps, args.seed)
    export_policy(out_path, map_path.relative_to(root), map_data, grid, q, metrics, args.seed)
    print(json.dumps(metrics, ensure_ascii=False, indent=2))
    if metrics["eval_success_rate"] < 0.8:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
