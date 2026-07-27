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


def world_to_cell(grid: dict, pos: list[float]) -> tuple[int, int]:
    gx = int(math.floor((float(pos[0]) - grid["min_x"]) / grid["cell_size"]))
    gz = int(math.floor((float(pos[2]) - grid["min_z"]) / grid["cell_size"]))
    return clamp_cell(grid, (gx, gz))


def clamp_cell(grid: dict, cell: tuple[int, int]) -> tuple[int, int]:
    return max(0, min(grid["width"] - 1, cell[0])), max(0, min(grid["height"] - 1, cell[1]))


def is_free(grid: dict, cell: tuple[int, int]) -> bool:
    x, z = cell
    return 0 <= x < grid["width"] and 0 <= z < grid["height"] and not grid["blocked"][x][z]


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
