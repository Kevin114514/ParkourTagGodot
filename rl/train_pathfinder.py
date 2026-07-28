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

# 默认联合训练的官方地图（与 game.gd 的 OFFICIAL_MAPS 对应）。
# 策略状态是"相对目标偏移 + 邻格障碍掩码"，因此在多张地图上联合训练可以泛化，
# 让 AI 在任意官方地图都不容易卡在墙里。
DEFAULT_MAPS = [
    "maps/default_arena.json",
    "maps/ring_training.json",
    "maps/two_story_villa.json",
    "maps/woodland_mansion.json",
    "maps/desert_temple.json",
]


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


def build_grid(map_data: dict, cell_size: float, agent_radius: float) -> dict | None:
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
        if not all_bounds:
            return None
        min_x = min(b[0] for b in all_bounds) - 2.0
        max_x = max(b[1] for b in all_bounds) + 2.0
        min_z = min(b[2] for b in all_bounds) - 2.0
        max_z = max(b[3] for b in all_bounds) + 2.0
    else:
        min_x, max_x, min_z, max_z = ground_bounds

    width = int(math.floor((max_x - min_x) / cell_size)) + 1
    height = int(math.floor((max_z - min_z) / cell_size)) + 1
    if width < 3 or height < 3:
        return None
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
    for _ in range(10000):
        cell = (random.randrange(grid["width"]), random.randrange(grid["height"]))
        if is_free(grid, cell):
            return cell
    raise RuntimeError("map has no free cell")


def compute_components(grid: dict) -> list[list[tuple[int, int]]]:
    """把 2D 导航网格划分为连通分量，保证训练/评估只用可达的 (agent, target) 对，
    避免多层地图被压平后出现根本走不到的目标污染学习。"""
    labels = [[-1 for _ in range(grid["height"])] for _ in range(grid["width"])]
    comps: list[list[tuple[int, int]]] = []
    cid = 0
    for sx in range(grid["width"]):
        for sz in range(grid["height"]):
            if not is_free(grid, (sx, sz)) or labels[sx][sz] != -1:
                continue
            cells = []
            q = deque([(sx, sz)])
            labels[sx][sz] = cid
            while q:
                c = q.popleft()
                cells.append(c)
                for dx, dz in MOVE_ACTIONS:
                    nx, nz = c[0] + dx, c[1] + dz
                    if 0 <= nx < grid["width"] and 0 <= nz < grid["height"] and is_free(grid, (nx, nz)) and labels[nx][nz] == -1:
                        labels[nx][nz] = cid
                        q.append((nx, nz))
            comps.append(cells)
            cid += 1
    return comps


def sample_reachable_pair(components: list[list[tuple[int, int]]], min_dist: float = 4.0) -> tuple[tuple[int, int], tuple[int, int]] | None:
    big = [c for c in components if len(c) >= 6]
    if not big:
        big = [c for c in components if len(c) >= 2]
    if not big:
        return None
    comp = random.choices(big, weights=[len(c) for c in big])[0]
    for _ in range(24):
        a = random.choice(comp)
        t = random.choice(comp)
        if distance(a, t) >= min_dist:
            return a, t
    return None


def distance(a: tuple[int, int], b: tuple[int, int]) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def blocked_mask(grid: dict, agent: tuple[int, int]) -> int:
    """相邻 8 方向的障碍掩码（与运行时 _blocked_mask 的 8 条射线一致）。"""
    mask = 0
    for i, (dx, dz) in enumerate(MOVE_ACTIONS):
        if not is_free(grid, (agent[0] + dx, agent[1] + dz)):
            mask |= 1 << i
    return mask


def state_key(grid: dict, agent: tuple[int, int], target: tuple[int, int]) -> tuple[int, int, int]:
    dx = max(-MAX_RELATIVE_CELLS, min(MAX_RELATIVE_CELLS, target[0] - agent[0]))
    dz = max(-MAX_RELATIVE_CELLS, min(MAX_RELATIVE_CELLS, target[1] - agent[1]))
    return dx, dz, blocked_mask(grid, agent)


def distance_field(grid: dict, target: tuple[int, int]) -> dict[tuple[int, int], int]:
    """从目标出发的 8 连通 BFS 测地距离（最少移动步数）。
    用作势能塑形奖励，使奖励梯度始终指向最优绕行路径，消除"朝目标直线走却撞墙"的局部最优。"""
    field: dict[tuple[int, int], int] = {target: 0}
    q = deque([target])
    while q:
        c = q.popleft()
        d = field[c]
        for dx, dz in MOVE_ACTIONS:
            nxt = (c[0] + dx, c[1] + dz)
            if nxt in field or not is_free(grid, nxt):
                continue
            field[nxt] = d + 1
            q.append(nxt)
    return field


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


def optimal_action(grid: dict, field: dict, agent: tuple[int, int], target: tuple[int, int]) -> int | None:
    """给定目标的测地距离场，返回 agent 处的最优动作（沿最短路走一步，相邻则抓捕）。"""
    if distance(agent, target) <= CATCH_DISTANCE_CELLS:
        return CATCH_ACTION_INDEX
    here = field.get(agent)
    if here is None:
        return None
    best_a = None
    best_d = here
    for i, (dx, dz) in enumerate(MOVE_ACTIONS):
        nxt = (agent[0] + dx, agent[1] + dz)
        if not is_free(grid, nxt):
            continue
        d = field.get(nxt)
        if d is not None and d < best_d:
            best_d = d
            best_a = i
    return best_a


def train(maps: list[dict], episodes: int, max_steps: int, seed: int) -> tuple[dict, dict]:
    """用测地最短路（BFS 距离场）作为专家，对"相对目标偏移 + 邻格障碍掩码"这一反应式
    状态做行为克隆（apprenticeship learning）：统计每个状态下专家最优动作的票数，取多数票。
    这样学到的反应式策略等价于最优的局部导航规则，稳定优于朴素贪心，也不会把 AI 引向撞墙。"""
    random.seed(seed)
    votes: dict = defaultdict(lambda: [0] * len(ACTIONS))
    samples = 0

    for m in maps:
        m["starts"] = candidate_starts(m["grid"], m["runner_spawn"], m["tagger_spawn"])

    # episodes 复用为"采样目标数"：每选一个目标就算一次全场距离场，覆盖大量状态。
    for _ in range(episodes):
        m = random.choice(maps)
        grid = m["grid"]
        big = [c for c in m["components"] if len(c) >= 6]
        if not big:
            continue
        comp = random.choices(big, weights=[len(c) for c in big])[0]
        target = random.choice(comp)
        field = distance_field(grid, target)
        # 从该分量里抽样一批 agent 位置，为其状态记录专家动作票。
        cells = comp if len(comp) <= 90 else random.sample(comp, 90)
        for c in cells:
            if c == target:
                continue
            a = optimal_action(grid, field, c, target)
            if a is None:
                continue
            votes[state_key(grid, c, target)][a] += 1
            samples += 1

    policy = build_policy(votes)
    metrics = evaluate(maps, policy, max_steps, seed + 1)
    metrics["expert_samples"] = samples
    metrics["states"] = len(votes)
    metrics["policy_states"] = len(policy)
    return policy, metrics


def build_policy(votes: dict, confidence: float = 0.5) -> dict:
    """取每个状态的多数票动作；仅当多数票占比够高、且该动作不撞墙时保留，
    其余状态运行时回退到安全的贪心步（并有硬性脱困兜底）。"""
    policy: dict = {}
    for key, counts in votes.items():
        total = sum(counts)
        if total <= 0:
            continue
        best = max(range(len(counts)), key=lambda i: counts[i])
        if counts[best] / total < confidence:
            continue
        if best != CATCH_ACTION_INDEX and (key[2] >> best) & 1:
            continue
        policy[key] = best
    return policy


def policy_action(policy: dict, key: tuple[int, int, int]) -> int | None:
    return policy.get(key)


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


def evaluate(maps: list[dict], policy: dict, max_steps: int, seed: int) -> dict:
    random.seed(seed)
    cases = []
    per_map = max(40, 300 // len(maps))
    for m in maps:
        grid = m["grid"]
        components = m["components"]
        cases.append((grid, m["tagger_spawn"], m["runner_spawn"]))
        got = 0
        attempts = 0
        while got < per_map and attempts < per_map * 20:
            attempts += 1
            pair = sample_reachable_pair(components)
            if pair is None:
                break
            cases.append((grid, pair[0], pair[1]))
            got += 1

    def run(cases: list, use_policy: bool) -> tuple[int, int, int]:
        successes = 0
        total_steps = 0
        fallback_actions = 0
        for grid, start_agent, target in cases:
            agent = start_agent
            for step in range(max_steps):
                if distance(agent, target) <= CATCH_DISTANCE_CELLS:
                    successes += 1
                    total_steps += step + 1
                    break
                action_index = None
                if use_policy:
                    action_index = policy_action(policy, state_key(grid, agent, target))
                if action_index is None or action_index == CATCH_ACTION_INDEX:
                    if use_policy and action_index is None:
                        fallback_actions += 1
                    action_index = fallback_action(grid, agent, target)
                    if action_index == CATCH_ACTION_INDEX:
                        # 已相邻却未满足抓捕：下一轮循环顶部会判定成功
                        continue
                dx, dz = ACTIONS[action_index]
                nxt = (agent[0] + dx, agent[1] + dz)
                if is_free(grid, nxt):
                    agent = nxt
            else:
                total_steps += max_steps
        return successes, total_steps, fallback_actions

    successes, total_steps, fallback_actions = run(cases, True)
    greedy_successes, _, _ = run(cases, False)

    return {
        "eval_success_rate": successes / len(cases),
        "eval_avg_steps": total_steps / len(cases),
        "eval_cases": len(cases),
        "eval_fallback_actions": fallback_actions,
        "greedy_baseline_success_rate": greedy_successes / len(cases),
    }


def export_policy(path: Path, maps: list[dict], grid: dict, policy: dict, metrics: dict, seed: int) -> None:
    policy_str = {",".join(str(v) for v in key): action for key, action in policy.items()}

    out = {
        "metadata": {
            "algorithm": "geodesic_bfs_behavior_cloning_relative_obstacle_mask_multimap",
            "source_maps": [m["path"] for m in maps],
            "map_names": [m["name"] for m in maps],
            "seed": seed,
            "cell_size": grid["cell_size"],
            "max_relative_cells": MAX_RELATIVE_CELLS,
            "catch_action_index": CATCH_ACTION_INDEX,
            "catch_distance_cells": CATCH_DISTANCE_CELLS,
            # 相对状态表示：运行时使用相对目标偏移量查表，不再依赖单地图边界。
            "relative_state": True,
            "actions": ACTIONS,
            "metrics": metrics,
        },
        "policy": policy_str,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))


def main() -> None:
    parser = argparse.ArgumentParser(description="Train a small tabular RL pathfinding policy for ParkourTag maps (multi-map).")
    parser.add_argument("--maps", default=",".join(DEFAULT_MAPS), help="逗号分隔的地图列表，用于联合训练。")
    parser.add_argument("--out", default="rl/trained_policy.json")
    parser.add_argument("--episodes", type=int, default=14000)
    parser.add_argument("--max-steps", type=int, default=140)
    parser.add_argument("--cell-size", type=float, default=2.0)
    parser.add_argument("--agent-radius", type=float, default=0.5)
    parser.add_argument("--seed", type=int, default=114514)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    out_path = (root / args.out).resolve()

    maps: list[dict] = []
    for rel in [s.strip() for s in args.maps.split(",") if s.strip()]:
        map_path = (root / rel).resolve()
        if not map_path.exists():
            print(f"[skip] map not found: {rel}")
            continue
        map_data = load_map(map_path)
        grid = build_grid(map_data, args.cell_size, args.agent_radius)
        if grid is None:
            print(f"[skip] cannot build navigation grid for: {rel}")
            continue
        try:
            runner_spawn = nearest_free(grid, world_to_cell(grid, map_data.get("runner_spawn", [0.0, 0.0, 0.0])))
            tagger_spawn = nearest_free(grid, world_to_cell(grid, map_data.get("tagger_spawn", [0.0, 0.0, 0.0])))
        except RuntimeError:
            print(f"[skip] map has no free cell: {rel}")
            continue
        maps.append({
            "path": map_path.relative_to(root).as_posix(),
            "name": map_data.get("name", map_path.stem),
            "grid": grid,
            "runner_spawn": runner_spawn,
            "tagger_spawn": tagger_spawn,
            "components": compute_components(grid),
        })

    if not maps:
        raise SystemExit("no trainable maps")

    print(f"training on {len(maps)} maps: {[m['name'] for m in maps]}")
    q, metrics = train(maps, args.episodes, args.max_steps, args.seed)
    export_policy(out_path, maps, maps[0]["grid"], q, metrics, args.seed)
    print(json.dumps(metrics, ensure_ascii=False, indent=2))
    if metrics["eval_success_rate"] < 0.8:
        print(f"[warn] eval_success_rate={metrics['eval_success_rate']:.3f} below 0.8 target")


if __name__ == "__main__":
    main()
