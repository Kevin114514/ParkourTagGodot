"""ParkourTag dual-agent self-play RL v2.

This trainer models the current hit-win mode: the runner wins after ten grenade
hits or by surviving 300 seconds; the tagger wins by a valid active catch.
Both agents learn movement and a separate skill decision with Double Q-learning.
The exported relative policies are consumed by rl_policy_tagger.gd and
rl_policy_runner.gd, while the game's navigation safety layer remains active.
"""

import argparse
import json
import math
import random
import time
from collections import defaultdict, deque
from pathlib import Path

# Target-relative movement: toward, away, left, right, diagonals, hold.
MOVE_NAMES = [
    "toward", "away", "left", "right",
    "toward_left", "toward_right", "away_left", "away_right", "hold",
]
MOVE_COUNT = len(MOVE_NAMES)
ACTION_COUNT = MOVE_COUNT * 2  # move + optional role skill
DEFAULT_HITS_TO_WIN = 10
DEFAULT_ROUND_SECONDS = 300.0
DEFAULT_DECISION_SECONDS = 1.0
CATCH_DISTANCE_CELLS = 1.3
CATCH_COOLDOWN_STEPS = 2
THROW_COOLDOWN_STEPS = 2
SLOW_STEPS = 3
THROW_MIN_CELLS = 2.0
THROW_MAX_CELLS = 9.0
THROW_IDEAL_CELLS = 5.25

DEFAULT_MAPS = [
    "maps/default_arena.json",
    "maps/ring_training.json",
    "maps/two_story_villa.json",
    "maps/woodland_mansion.json",
    "maps/desert_temple.json",
    "maps/forest_island_map.json",
    "maps/nether_fortress.json",
    "maps/winter_town.json",
    "maps/urban_training_site.json",
    "maps/monkey_hotel_corridors.json",
]

REWARD = {
    "tagger_step": -0.02,
    "runner_step": 0.018,
    "tagger_close": 0.72,
    "runner_open": 0.38,
    "pressure": 0.16,
    "catch": 90.0,
    "caught": -90.0,
    "bad_catch": -1.1,
    "hit": 17.0,
    "hit_against": -11.0,
    "bad_throw": -1.25,
    "hit_win": 125.0,
    "hit_loss": -110.0,
    "timeout_win": 48.0,
    "timeout_loss": -48.0,
    "wall": -0.8,
    "hold_pressure": -0.7,
}


def load_map(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream)


def _bool_value(value, default=True) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() not in ("false", "0", "no", "off")


def object_bounds(obj: dict):
    pos = obj.get("position", [0.0, 0.0, 0.0])
    x, z = float(pos[0]), float(pos[2])
    typ = str(obj.get("type", "box")).lower()
    if typ == "box":
        size = obj.get("size", [1.0, 1.0, 1.0])
        sx, sz = float(size[0]), float(size[2])
        rotation = obj.get("rotation_degrees", obj.get("rotation", [0.0, 0.0, 0.0]))
        yaw = math.radians(float(rotation[1])) if "rotation_degrees" in obj else float(rotation[1])
        half_x = abs(math.cos(yaw)) * sx * 0.5 + abs(math.sin(yaw)) * sz * 0.5
        half_z = abs(math.sin(yaw)) * sx * 0.5 + abs(math.cos(yaw)) * sz * 0.5
        return x - half_x, x + half_x, z - half_z, z + half_z
    if typ in ("cylinder", "csg_cylinder", "sphere", "capsule"):
        radius = float(obj.get("radius", 0.5))
        return x - radius, x + radius, z - radius, z + radius
    return None


def build_grid(map_data: dict, cell_size: float, agent_radius: float):
    objects = map_data.get("objects", [])
    floor_candidates = []
    all_bounds = []
    for obj in objects:
        bounds = object_bounds(obj)
        if bounds is not None:
            all_bounds.append(bounds)
        if str(obj.get("type", "")).lower() != "box":
            continue
        name = str(obj.get("name", "")).lower()
        size = obj.get("size", [0.0, 0.0, 0.0])
        y = float(obj.get("position", [0.0, 0.0, 0.0])[1])
        if len(size) >= 3 and ("ground" in name or "floor" in name or "terrain" in name or (float(size[1]) <= 0.45 and float(size[0]) >= 8.0 and float(size[2]) >= 8.0)):
            floor_candidates.append((abs(y), float(size[0]) * float(size[2]), bounds))
    if floor_candidates:
        # Prefer the largest low floor. Upper floors must not collapse into L1.
        low = [item for item in floor_candidates if item[0] <= 3.0] or floor_candidates
        _, _, ground_bounds = max(low, key=lambda item: item[1])
        min_x, max_x, min_z, max_z = ground_bounds
    elif all_bounds:
        min_x = min(v[0] for v in all_bounds) - 2.0
        max_x = max(v[1] for v in all_bounds) + 2.0
        min_z = min(v[2] for v in all_bounds) - 2.0
        max_z = max(v[3] for v in all_bounds) + 2.0
    else:
        return None

    width = int(math.floor((max_x - min_x) / cell_size)) + 1
    height = int(math.floor((max_z - min_z) / cell_size)) + 1
    if width < 3 or height < 3 or width * height > 35000:
        return None
    blocked = [[False] * height for _ in range(width)]
    obstacles = []
    floor_words = ("ground", "floor", "terrain", "ramp", "slope", "stair", "step", "bridge", "platform")
    for obj in objects:
        if not _bool_value(obj.get("collision", True)):
            continue
        name = str(obj.get("name", "")).lower()
        typ = str(obj.get("type", "box")).lower()
        size = obj.get("size", [0.0, 0.0, 0.0])
        pos = obj.get("position", [0.0, 0.0, 0.0])
        y = float(pos[1])
        sy = float(size[1]) if len(size) >= 3 else float(obj.get("height", 1.0))
        if any(word in name for word in floor_words):
            continue
        if typ == "box" and sy <= 0.55:
            continue
        # Ignore structures wholly above the base navigation layer.
        if y - sy * 0.5 > 2.2:
            continue
        bounds = object_bounds(obj)
        if bounds is not None:
            obstacles.append(bounds)
    for gx in range(width):
        x = min_x + gx * cell_size
        for gz in range(height):
            z = min_z + gz * cell_size
            blocked[gx][gz] = any(
                x0 - agent_radius <= x <= x1 + agent_radius
                and z0 - agent_radius <= z <= z1 + agent_radius
                for x0, x1, z0, z1 in obstacles
            )
    return {
        "min_x": min_x, "min_z": min_z, "width": width, "height": height,
        "blocked": blocked, "cell_size": cell_size,
    }


def is_free(grid: dict, cell) -> bool:
    x, z = cell
    return 0 <= x < grid["width"] and 0 <= z < grid["height"] and not grid["blocked"][x][z]


def legal_step(grid: dict, start, step) -> bool:
    dx, dz = step
    end = (start[0] + dx, start[1] + dz)
    if not is_free(grid, end):
        return False
    if dx and dz:
        return is_free(grid, (start[0] + dx, start[1])) and is_free(grid, (start[0], start[1] + dz))
    return True


def nearest_free(grid: dict, start):
    start = (max(0, min(grid["width"] - 1, start[0])), max(0, min(grid["height"] - 1, start[1])))
    if is_free(grid, start):
        return start
    queue, seen = deque([start]), {start}
    while queue:
        cell = queue.popleft()
        for step in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nxt = (cell[0] + step[0], cell[1] + step[1])
            if nxt in seen or not (0 <= nxt[0] < grid["width"] and 0 <= nxt[1] < grid["height"]):
                continue
            if is_free(grid, nxt):
                return nxt
            seen.add(nxt)
            queue.append(nxt)
    raise RuntimeError("map has no free cell")


def world_to_cell(grid: dict, pos):
    return nearest_free(grid, (
        int(round((float(pos[0]) - grid["min_x"]) / grid["cell_size"])),
        int(round((float(pos[2]) - grid["min_z"]) / grid["cell_size"])),
    ))


def components(grid: dict):
    result, seen = [], set()
    for x in range(grid["width"]):
        for z in range(grid["height"]):
            start = (x, z)
            if start in seen or not is_free(grid, start):
                continue
            comp, queue = [], deque([start])
            seen.add(start)
            while queue:
                cell = queue.popleft()
                comp.append(cell)
                for step in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
                    nxt = (cell[0] + step[0], cell[1] + step[1])
                    if nxt not in seen and legal_step(grid, cell, step):
                        seen.add(nxt)
                        queue.append(nxt)
            if len(comp) >= 8:
                result.append(comp)
    return result


def distance(a, b) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def line_clear(grid: dict, a, b) -> bool:
    count = max(abs(a[0] - b[0]), abs(a[1] - b[1]))
    for index in range(1, count):
        t = index / max(1, count)
        cell = (round(a[0] + (b[0] - a[0]) * t), round(a[1] + (b[1] - a[1]) * t))
        if not is_free(grid, cell):
            return False
    return True


def _quantize_vector(x: float, z: float):
    length = math.hypot(x, z)
    if length < 1e-6:
        return 0, 0
    x, z = x / length, z / length
    return (1 if x > 0.35 else -1 if x < -0.35 else 0, 1 if z > 0.35 else -1 if z < -0.35 else 0)


def relative_steps(agent, target):
    tx, tz = target[0] - agent[0], target[1] - agent[1]
    length = math.hypot(tx, tz)
    if length < 1e-6:
        tx, tz, length = 1.0, 0.0, 1.0
    tx, tz = tx / length, tz / length
    lx, lz = -tz, tx
    vectors = [
        (tx, tz), (-tx, -tz), (lx, lz), (-lx, -lz),
        (tx + lx, tz + lz), (tx - lx, tz - lz),
        (-tx + lx, -tz + lz), (-tx - lx, -tz - lz), (0.0, 0.0),
    ]
    return [_quantize_vector(x, z) for x, z in vectors]


def blocked_mask(grid: dict, agent, target) -> int:
    mask = 0
    for index, step in enumerate(relative_steps(agent, target)[:-1]):
        if not legal_step(grid, agent, step):
            mask |= 1 << index
    return mask


def distance_bucket(value: float) -> int:
    for index, limit in enumerate((1.3, 2.5, 4.0, 6.0, 9.0, 13.0)):
        if value <= limit:
            return index
    return 6


def progress_bucket(hits: int, target: int) -> int:
    ratio = hits / max(1, target)
    return min(3, int(ratio * 4.0))


def time_bucket(step: int, max_steps: int) -> int:
    return min(3, int(step / max(1, max_steps) * 4.0))


def state_key(role: str, agent, target, grid, skill_ready: bool, affected: bool, hits: int, hits_to_win: int, step: int, max_steps: int):
    gap = distance(agent, target)
    return (
        distance_bucket(gap),
        blocked_mask(grid, agent, target),
        int(line_clear(grid, agent, target)),
        int(skill_ready),
        int(affected),
        progress_bucket(hits, hits_to_win),
        time_bucket(step, max_steps),
    )


def legal_actions(grid: dict, agent, target):
    result = []
    steps = relative_steps(agent, target)
    for skill in (0, 1):
        for move_index, move in enumerate(steps):
            if move_index == MOVE_COUNT - 1 or legal_step(grid, agent, move):
                result.append(move_index + skill * MOVE_COUNT)
    return result


def move_agent(grid: dict, agent, target, action: int):
    move_index = action % MOVE_COUNT
    step = relative_steps(agent, target)[move_index]
    if move_index == MOVE_COUNT - 1:
        return agent, False
    if legal_step(grid, agent, step):
        return (agent[0] + step[0], agent[1] + step[1]), False
    return agent, True


class DoubleQ:
    def __init__(self, alpha: float, gamma: float):
        self.a = defaultdict(lambda: [0.0] * ACTION_COUNT)
        self.b = defaultdict(lambda: [0.0] * ACTION_COUNT)
        self.alpha = alpha
        self.gamma = gamma

    def choose(self, state, legal, epsilon: float):
        if random.random() < epsilon:
            return random.choice(legal)
        return max(legal, key=lambda action: self.a[state][action] + self.b[state][action])

    def update(self, state, action, reward, next_state, next_legal, done):
        qa, qb = (self.a, self.b) if random.random() < 0.5 else (self.b, self.a)
        current = qa[state][action]
        if done:
            target = reward
        else:
            best = max(next_legal, key=lambda candidate: qa[next_state][candidate])
            target = reward + self.gamma * qb[next_state][best]
        qa[state][action] = current + self.alpha * (target - current)

    def policy(self):
        keys = set(self.a) | set(self.b)
        return {key: max(range(ACTION_COUNT), key=lambda action: self.a[key][action] + self.b[key][action]) for key in keys}


def sample_pair(comps, min_distance):
    if not comps:
        return None
    comp = random.choices(comps, weights=[len(item) for item in comps])[0]
    for _ in range(80):
        tagger, runner = random.choice(comp), random.choice(comp)
        if distance(tagger, runner) >= min_distance:
            return tagger, runner
    return None


def run_episode(map_info, tagger_q, runner_q, max_steps, hits_to_win, epsilon, learn_role=None):
    pair = sample_pair(map_info["components"], random.uniform(3.0, 8.0))
    if pair is None:
        return None
    grid = map_info["grid"]
    tagger, runner = pair
    hits = 0
    catch_cd = throw_cd = slow_left = 0
    runner_has_item = random.random() < 0.75
    item_reload = 0 if runner_has_item else random.randint(2, 6)
    tagger_speed_credit = 0.0
    outcome = "timeout"

    for step in range(max_steps):
        catch_ready = catch_cd <= 0 and slow_left <= 0
        throw_ready = runner_has_item and throw_cd <= 0
        t_state = state_key("tagger", tagger, runner, grid, catch_ready, slow_left > 0, hits, hits_to_win, step, max_steps)
        r_state = state_key("runner", runner, tagger, grid, throw_ready, False, hits, hits_to_win, step, max_steps)
        t_legal = legal_actions(grid, tagger, runner)
        r_legal = legal_actions(grid, runner, tagger)
        tagger_epsilon = epsilon if learn_role == "tagger" else min(0.08, epsilon)
        runner_epsilon = epsilon if learn_role == "runner" else min(0.08, epsilon)
        t_action = tagger_q.choose(t_state, t_legal, tagger_epsilon)
        r_action = runner_q.choose(r_state, r_legal, runner_epsilon)

        old_gap = distance(tagger, runner)
        new_tagger, tagger_wall = move_agent(grid, tagger, runner, t_action)
        new_runner, runner_wall = move_agent(grid, runner, tagger, r_action)
        tagger_speed_credit += 0.10 if slow_left <= 0 else -0.42
        if tagger_speed_credit >= 1.0:
            extra, _ = move_agent(grid, new_tagger, new_runner, t_action)
            if distance(extra, new_runner) < distance(new_tagger, new_runner):
                new_tagger = extra
            tagger_speed_credit -= 1.0
        elif tagger_speed_credit <= -1.0:
            new_tagger = tagger
            tagger_speed_credit += 1.0

        catch_cd = max(0, catch_cd - 1)
        throw_cd = max(0, throw_cd - 1)
        slow_left = max(0, slow_left - 1)
        if not runner_has_item:
            item_reload -= 1
            if item_reload <= 0:
                runner_has_item = True

        gap = distance(new_tagger, new_runner)
        clear = line_clear(grid, new_tagger, new_runner)
        t_skill = t_action >= MOVE_COUNT
        r_skill = r_action >= MOVE_COUNT
        caught = hit = False
        bad_catch = bad_throw = False

        if t_skill:
            if catch_ready:
                catch_cd = CATCH_COOLDOWN_STEPS
                caught = gap <= CATCH_DISTANCE_CELLS and clear
                bad_catch = not caught
            else:
                bad_catch = True

        if r_skill and not caught:
            if throw_ready:
                throw_cd = THROW_COOLDOWN_STEPS
                runner_has_item = False
                item_reload = random.randint(3, 7)
                valid = THROW_MIN_CELLS <= gap <= THROW_MAX_CELLS and clear
                accuracy = max(0.30, 0.96 - abs(gap - THROW_IDEAL_CELLS) * 0.075)
                hit = valid and random.random() <= accuracy
                bad_throw = not hit
                if hit:
                    hits += 1
                    slow_left = SLOW_STEPS
            else:
                bad_throw = True

        hit_win = hits >= hits_to_win
        timeout = step == max_steps - 1
        done = caught or hit_win or timeout
        new_gap = distance(new_tagger, new_runner)
        gap_delta = old_gap - new_gap
        pressure = max(0.0, 4.5 - new_gap)

        t_reward = REWARD["tagger_step"] + gap_delta * REWARD["tagger_close"] + pressure * REWARD["pressure"]
        r_reward = REWARD["runner_step"] - gap_delta * REWARD["runner_open"] - pressure * REWARD["pressure"]
        if tagger_wall:
            t_reward += REWARD["wall"]
        if runner_wall:
            r_reward += REWARD["wall"]
        if t_action % MOVE_COUNT == MOVE_COUNT - 1 and gap > CATCH_DISTANCE_CELLS:
            t_reward += REWARD["hold_pressure"]
        if r_action % MOVE_COUNT == MOVE_COUNT - 1 and gap < 4.5:
            r_reward += REWARD["hold_pressure"]
        if bad_catch:
            t_reward += REWARD["bad_catch"]
        if bad_throw:
            r_reward += REWARD["bad_throw"]
        if hit:
            r_reward += REWARD["hit"] + hits * 0.35
            t_reward += REWARD["hit_against"]
        if caught:
            t_reward += REWARD["catch"]
            r_reward += REWARD["caught"]
            outcome = "catch"
        elif hit_win:
            r_reward += REWARD["hit_win"]
            t_reward += REWARD["hit_loss"]
            outcome = "hits"
        elif timeout:
            r_reward += REWARD["timeout_win"]
            t_reward += REWARD["timeout_loss"]

        next_catch_ready = max(0, catch_cd) <= 0 and slow_left <= 0
        next_throw_ready = runner_has_item and throw_cd <= 0
        nt_state = state_key("tagger", new_tagger, new_runner, grid, next_catch_ready, slow_left > 0, hits, hits_to_win, step + 1, max_steps)
        nr_state = state_key("runner", new_runner, new_tagger, grid, next_throw_ready, False, hits, hits_to_win, step + 1, max_steps)
        if learn_role == "tagger":
            tagger_q.update(t_state, t_action, t_reward, nt_state, legal_actions(grid, new_tagger, new_runner), done)
        elif learn_role == "runner":
            runner_q.update(r_state, r_action, r_reward, nr_state, legal_actions(grid, new_runner, new_tagger), done)

        tagger, runner = new_tagger, new_runner
        if done:
            return outcome, step + 1, hits
    return outcome, max_steps, hits


def evaluate(maps, tagger_q, runner_q, max_steps, hits_to_win, episodes=300):
    counts = {"catch": 0, "hits": 0, "timeout": 0}
    hit_sum = step_sum = 0
    for _ in range(episodes):
        result = run_episode(random.choice(maps), tagger_q, runner_q, max_steps, hits_to_win, 0.0, None)
        if result is None:
            continue
        outcome, steps, hits = result
        counts[outcome] += 1
        hit_sum += hits
        step_sum += steps
    total = sum(counts.values())
    return {
        "eval_episodes": total,
        "eval_tagger_catch_rate": counts["catch"] / total if total else 0.0,
        "eval_runner_hit_win_rate": counts["hits"] / total if total else 0.0,
        "eval_runner_timeout_win_rate": counts["timeout"] / total if total else 0.0,
        "eval_avg_runner_hits": hit_sum / total if total else 0.0,
        "eval_avg_steps": step_sum / total if total else 0.0,
    }


def train(maps, args):
    random.seed(args.seed)
    tagger_q = DoubleQ(args.alpha, args.gamma)
    runner_q = DoubleQ(args.alpha, args.gamma)
    start = last_report = time.monotonic()
    episode = 0
    recent = deque(maxlen=500)
    while True:
        elapsed = time.monotonic() - start
        if args.duration_seconds > 0 and elapsed >= args.duration_seconds:
            break
        if args.duration_seconds <= 0 and episode >= args.episodes:
            break
        progress = min(1.0, elapsed / args.duration_seconds) if args.duration_seconds > 0 else episode / max(1, args.episodes - 1)
        epsilon = args.epsilon_start + (args.epsilon_end - args.epsilon_start) * progress
        learn_role = "tagger" if episode % 2 == 0 else "runner"
        result = run_episode(random.choice(maps), tagger_q, runner_q, args.max_steps, args.hits_to_win, epsilon, learn_role)
        if result is not None:
            recent.append(result)
            episode += 1
        now = time.monotonic()
        if args.progress_interval > 0 and now - last_report >= args.progress_interval:
            outcomes = [item[0] for item in recent]
            print(
                f"[selfplay-v2 {elapsed:7.1f}s] episodes={episode} epsilon={epsilon:.3f} "
                f"catch={outcomes.count('catch') / max(1, len(outcomes)):.1%} "
                f"hit_win={outcomes.count('hits') / max(1, len(outcomes)):.1%} "
                f"timeout={outcomes.count('timeout') / max(1, len(outcomes)):.1%}",
                flush=True,
            )
            last_report = now
    metrics = evaluate(maps, tagger_q, runner_q, args.max_steps, args.hits_to_win)
    metrics.update({
        "train_seconds": time.monotonic() - start,
        "train_episodes": episode,
        "tagger_states": len(tagger_q.policy()),
        "runner_states": len(runner_q.policy()),
    })
    return tagger_q.policy(), runner_q.policy(), metrics


def export_policy(path: Path, policy: dict, maps, args, role: str, metrics: dict):
    output = {
        "metadata": {
            "version": 2,
            "algorithm": "alternating_double_q_selfplay",
            "role": role,
            "relative_actions": True,
            "move_names": MOVE_NAMES,
            "move_action_count": MOVE_COUNT,
            "skill_action_offset": MOVE_COUNT,
            "state_fields": ["distance_bucket", "blocked_mask", "line_clear", "skill_ready", "affected", "hit_progress_bucket", "time_bucket"],
            "cell_size": args.cell_size,
            "hits_to_win": args.hits_to_win,
            "round_seconds": args.round_seconds,
            "decision_seconds": args.decision_seconds,
            "source_maps": [item["path"] for item in maps],
            "metrics": metrics,
            "reward_config": REWARD,
        },
        "policy": {",".join(map(str, key)): action for key, action in policy.items()},
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as stream:
        json.dump(output, stream, ensure_ascii=False, separators=(",", ":"))


def main():
    parser = argparse.ArgumentParser(description="ParkourTag dual-agent self-play RL v2")
    parser.add_argument("--maps", default=",".join(DEFAULT_MAPS))
    parser.add_argument("--tagger-out", default="rl/trained_policy.json")
    parser.add_argument("--runner-out", default="rl/trained_runner_policy.json")
    parser.add_argument("--episodes", type=int, default=30000)
    parser.add_argument("--duration-seconds", type=float, default=0.0)
    parser.add_argument("--round-seconds", type=float, default=DEFAULT_ROUND_SECONDS)
    parser.add_argument("--decision-seconds", type=float, default=DEFAULT_DECISION_SECONDS)
    parser.add_argument("--max-steps", type=int, default=0, help="0 derives steps from round/decision seconds")
    parser.add_argument("--hits-to-win", type=int, default=DEFAULT_HITS_TO_WIN)
    parser.add_argument("--cell-size", type=float, default=2.0)
    parser.add_argument("--agent-radius", type=float, default=0.5)
    parser.add_argument("--alpha", type=float, default=0.17)
    parser.add_argument("--gamma", type=float, default=0.97)
    parser.add_argument("--epsilon-start", type=float, default=0.90)
    parser.add_argument("--epsilon-end", type=float, default=0.025)
    parser.add_argument("--progress-interval", type=float, default=10.0)
    parser.add_argument("--seed", type=int, default=114514)
    args = parser.parse_args()
    args.max_steps = args.max_steps or max(1, int(math.ceil(args.round_seconds / args.decision_seconds)))

    root = Path(__file__).resolve().parents[1]
    maps = []
    for relative in (item.strip() for item in args.maps.split(",") if item.strip()):
        path = (root / relative).resolve()
        if not path.exists():
            print(f"[skip] missing map: {relative}")
            continue
        data = load_map(path)
        grid = build_grid(data, args.cell_size, args.agent_radius)
        if grid is None:
            print(f"[skip] cannot build safe grid: {relative}")
            continue
        comps = components(grid)
        if not comps:
            print(f"[skip] no navigable component: {relative}")
            continue
        maps.append({"path": path.relative_to(root).as_posix(), "name": data.get("name", path.stem), "grid": grid, "components": comps})
    if not maps:
        raise SystemExit("no trainable maps")

    print(f"self-play RL v2 maps={len(maps)} rules={args.hits_to_win} hits/{args.round_seconds:.0f}s max_steps={args.max_steps}")
    print("maps:", ", ".join(item["name"] for item in maps))
    tagger_policy, runner_policy, metrics = train(maps, args)
    export_policy((root / args.tagger_out).resolve(), tagger_policy, maps, args, "tagger", metrics)
    export_policy((root / args.runner_out).resolve(), runner_policy, maps, args, "runner", metrics)
    print(json.dumps(metrics, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
