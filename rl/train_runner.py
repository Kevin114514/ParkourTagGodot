"""离线训练躲藏者（Runner）逃跑策略。

与 train_pathfinder.py（追捕者）对称：同样是表格 Q-Learning，
状态 = (追捕者相对格子 dx, dz, 自身周围阻挡掩码)，动作 = 8 个移动方向。
区别在于奖励：躲藏者要拉开与追捕者的距离、尽量存活；被抓到则重罚。
训练时对手（追捕者）用「向躲藏者贪心逼近」来模拟，逼迫躲藏者学会绕障碍甩开。

产物 rl/trained_runner_policy.json 会被 scripts/rl_policy_runner.gd 加载；
查不到的状态由手写 runner_ai.gd 兜底。
"""
import argparse
import json
import math
import random
from collections import defaultdict, deque
from pathlib import Path

# 8 个移动方向；躲藏者不需要 catch 动作
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
MAX_RELATIVE_CELLS = 14
CATCH_DISTANCE_CELLS = 1.0


def load_map(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def object_bounds(obj: dict):
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
    for obj in map_data.get("objects", []):
        name = str(obj.get("name", "")).lower()
        typ = str(obj.get("type", "box"))
        size = obj.get("size", [0.0, 0.0, 0.0])
        y = float(obj.get("position", [0.0, 0.0, 0.0])[1])
        if "ground" in name or "pad" in name:
            continue
        if typ == "box" and len(size) >= 3 and float(size[1]) <= 0.25:
            continue
        if typ == "box" and y < 0.15 and float(size[1]) < 0.65:
            continue
        bounds = object_bounds(obj)
        if bounds is not None:
            obstacle_bounds.append(bounds)

    for gx in range(width):
        for gz in range(height):
            x = min_x + gx * cell_size
            z = min_z + gz * cell_size
            for bx0, bx1, bz0, bz1 in obstacle_bounds:
                if bx0 - agent_radius <= x <= bx1 + agent_radius and bz0 - agent_radius <= z <= bz1 + agent_radius:
                    blocked[gx][gz] = True
                    break

    return {
        "min_x": min_x,
        "max_x": max_x,
        "min_z": min_z,
        "max_z": max_z,
        "width": width,
        "height": height,
        "blocked": blocked,
        "cell_size": cell_size,
    }


def world_to_cell(grid: dict, pos):
    gx = int(math.floor((float(pos[0]) - grid["min_x"]) / grid["cell_size"]))
    gz = int(math.floor((float(pos[2]) - grid["min_z"]) / grid["cell_size"]))
    return clamp_cell(grid, (gx, gz))


def clamp_cell(grid: dict, cell):
    return max(0, min(grid["width"] - 1, cell[0])), max(0, min(grid["height"] - 1, cell[1]))


def is_free(grid: dict, cell) -> bool:
    x, z = cell
    return 0 <= x < grid["width"] and 0 <= z < grid["height"] and not grid["blocked"][x][z]


def nearest_free(grid: dict, start):
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


def random_free_cell(grid: dict):
    while True:
        cell = (random.randrange(grid["width"]), random.randrange(grid["height"]))
        if is_free(grid, cell):
            return cell


def distance(a, b) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def blocked_mask(grid: dict, agent) -> int:
    mask = 0
    for i, (dx, dz) in enumerate(MOVE_ACTIONS):
        if not is_free(grid, (agent[0] + dx, agent[1] + dz)):
            mask |= 1 << i
    return mask


def state_key(grid: dict, runner, tagger):
    """状态 = 追捕者相对躲藏者的格子偏移 + 躲藏者周围阻挡掩码。"""
    dx = max(-MAX_RELATIVE_CELLS, min(MAX_RELATIVE_CELLS, tagger[0] - runner[0]))
    dz = max(-MAX_RELATIVE_CELLS, min(MAX_RELATIVE_CELLS, tagger[1] - runner[1]))
    return dx, dz, blocked_mask(grid, runner)


def chaser_step(grid: dict, tagger, runner):
    """追捕者贪心逼近：在可行相邻格中选择离躲藏者最近的一格。"""
    if distance(tagger, runner) <= CATCH_DISTANCE_CELLS:
        return tagger
    best = tagger
    best_dist = distance(tagger, runner)
    for dx, dz in MOVE_ACTIONS:
        nxt = (tagger[0] + dx, tagger[1] + dz)
        if not is_free(grid, nxt):
            continue
        d = distance(nxt, runner)
        if d < best_dist:
            best_dist = d
            best = nxt
    return best


def candidate_starts(grid: dict, runner_spawn, tagger_spawn):
    starts = [(runner_spawn, tagger_spawn)]
    for gx in range(1, grid["width"] - 1, 3):
        for gz in range(1, grid["height"] - 1, 3):
            runner = (gx, gz)
            if not is_free(grid, runner):
                continue
            for tx, tz in ((grid["width"] - 2 - gx, grid["height"] - 2 - gz), (gx, grid["height"] - 2 - gz), (grid["width"] - 2 - gx, gz)):
                tagger = nearest_free(grid, clamp_cell(grid, (tx, tz)))
                if distance(runner, tagger) > 4.0:
                    starts.append((runner, tagger))
    return starts


def train(grid: dict, runner_spawn, tagger_spawn, episodes: int, max_steps: int, seed: int):
    random.seed(seed)
    q = defaultdict(lambda: [0.0] * len(MOVE_ACTIONS))
    alpha = 0.2
    gamma = 0.95
    epsilon = 0.45
    epsilon_min = 0.05
    escapes = 0
    survive_steps = []
    starts = candidate_starts(grid, runner_spawn, tagger_spawn)

    for episode in range(episodes):
        runner, tagger = starts[episode % len(starts)] if episode % 4 == 0 else random.choice(starts)
        if runner == tagger:
            tagger = random_free_cell(grid)
        epsilon = max(epsilon_min, epsilon * 0.999)
        last_dist = distance(runner, tagger)
        survived = True

        for step in range(max_steps):
            key = state_key(grid, runner, tagger)
            if random.random() < epsilon:
                action_index = random.randrange(len(MOVE_ACTIONS))
            else:
                action_index = max(range(len(MOVE_ACTIONS)), key=lambda i: q[key][i])

            dx, dz = MOVE_ACTIONS[action_index]
            nxt = (runner[0] + dx, runner[1] + dz)
            hit_block = not is_free(grid, nxt)
            if hit_block:
                nxt = runner

            # 对手（追捕者）随后向躲藏者新位置逼近
            tagger = chaser_step(grid, tagger, nxt)
            new_dist = distance(nxt, tagger)
            caught = new_dist <= CATCH_DISTANCE_CELLS

            reward = 0.04 + (new_dist - last_dist) * 0.6
            if hit_block:
                reward -= 0.4
            if caught:
                reward -= 12.0
                survived = False
            elif step == max_steps - 1:
                reward += 6.0

            next_key = state_key(grid, nxt, tagger)
            best_next = 0.0 if caught else max(q[next_key])
            q[key][action_index] += alpha * (reward + gamma * best_next - q[key][action_index])
            runner = nxt
            last_dist = new_dist
            if caught:
                break

        if survived:
            escapes += 1
        survive_steps.append(step + 1)

    metrics = evaluate(grid, q, runner_spawn, tagger_spawn, max_steps, seed + 1)
    metrics["train_escape_rate"] = escapes / max(1, episodes)
    metrics["train_avg_survive_steps"] = sum(survive_steps) / max(1, len(survive_steps))
    metrics["states"] = len(q)
    return q, metrics


def greedy_action(q: dict, key):
    if key not in q:
        return None
    values = q[key]
    return max(range(len(values)), key=lambda i: values[i])


def fallback_action(grid: dict, runner, tagger) -> int:
    """兜底：选择离追捕者最远的可行方向。"""
    best = 0
    best_dist = -1e9
    for i, (dx, dz) in enumerate(MOVE_ACTIONS):
        nxt = (runner[0] + dx, runner[1] + dz)
        if not is_free(grid, nxt):
            continue
        d = distance(nxt, tagger)
        if d > best_dist:
            best_dist = d
            best = i
    return best


def evaluate(grid: dict, q: dict, runner_spawn, tagger_spawn, max_steps: int, seed: int) -> dict:
    random.seed(seed)
    cases = [(runner_spawn, tagger_spawn)]
    for _ in range(199):
        runner = random_free_cell(grid)
        tagger = random_free_cell(grid)
        if distance(runner, tagger) > 4.0:
            cases.append((runner, tagger))

    escapes = 0
    total_steps = 0
    fallback_actions = 0
    for runner, tagger in cases:
        for step in range(max_steps):
            key = state_key(grid, runner, tagger)
            action_index = greedy_action(q, key)
            if action_index is None:
                fallback_actions += 1
                action_index = fallback_action(grid, runner, tagger)
            dx, dz = MOVE_ACTIONS[action_index]
            nxt = (runner[0] + dx, runner[1] + dz)
            if not is_free(grid, nxt):
                fallback_actions += 1
                action_index = fallback_action(grid, runner, tagger)
                dx, dz = MOVE_ACTIONS[action_index]
                nxt = (runner[0] + dx, runner[1] + dz)
                if not is_free(grid, nxt):
                    nxt = runner
            tagger = chaser_step(grid, tagger, nxt)
            runner = nxt
            if distance(runner, tagger) <= CATCH_DISTANCE_CELLS:
                total_steps += step + 1
                break
        else:
            escapes += 1
            total_steps += max_steps

    return {
        "eval_escape_rate": escapes / len(cases),
        "eval_avg_survive_steps": total_steps / len(cases),
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
            "algorithm": "tabular_q_learning_runner_evasion_relative_obstacle_mask",
            "role": "runner",
            "source_map": map_path.as_posix(),
            "map_name": map_data.get("name", map_path.stem),
            "seed": seed,
            "cell_size": grid["cell_size"],
            "max_relative_cells": MAX_RELATIVE_CELLS,
            "catch_distance_cells": CATCH_DISTANCE_CELLS,
            "bounds": {
                "min_x": grid["min_x"],
                "max_x": grid["max_x"],
                "min_z": grid["min_z"],
                "max_z": grid["max_z"],
                "width": grid["width"],
                "height": grid["height"],
            },
            "actions": MOVE_ACTIONS,
            "metrics": metrics,
        },
        "policy": policy,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))


def main() -> None:
    parser = argparse.ArgumentParser(description="Train a small tabular RL evasion policy for the ParkourTag runner.")
    parser.add_argument("--map", default="maps/ring_training.json")
    parser.add_argument("--out", default="rl/trained_runner_policy.json")
    parser.add_argument("--episodes", type=int, default=12000)
    parser.add_argument("--max-steps", type=int, default=160)
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
    if metrics["eval_escape_rate"] < 0.3:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
