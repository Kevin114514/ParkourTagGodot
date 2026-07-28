"""Self-play reinforcement learning for ParkourTag.

Unlike ``train_pathfinder.py`` (which behaviour-clones a BFS expert for a
*static* target), this script pits the chasing AI (tagger) and the hiding AI
(runner) against each other and lets *both* learn simultaneously with tabular
Q-learning. The two agents share the same grid world, take turns acting, and
receive opposing rewards, so each one keeps adapting to the other's improving
behaviour ("对着打一会").

The exported policies reuse the exact state/action convention consumed by the
game side (``scripts/rl_policy_tagger.gd`` / ``scripts/rl_policy_runner.gd``):

    state  = (clamped dx, clamped dz, 8-neighbour blocked mask)
    action = 8 move directions + 1 "catch/hold" action (index 8)

so no changes to the runtime lookup format are required.
"""

import argparse
import json
import math
import random
import time
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
RUNNER_HITS_TO_WIN = 10

DEFAULT_REWARD_CONFIG = {
    "tagger_speed_advantage": 0.08,
    "tagger_step_penalty": 0.025,
    "runner_step_reward": 0.01,
    "tagger_gap_gain_scale": 1.25,
    "tagger_gap_loss_scale": 0.25,
    "runner_gap_gain_scale": 0.55,
    "runner_pressure_scale": 0.8,
    "pressure_radius": 4.75,
    "tagger_pressure_bonus": 0.22,
    "runner_pressure_penalty": 0.28,
    "throw_min_distance": 2.0,
    "throw_max_distance": 9.0,
    "throw_ideal_distance": 5.25,
    "throw_cooldown_steps": 2,
    "throw_window_reward": 1.25,
    "runner_hit_reward": 14.0,
    "tagger_hit_penalty": 5.0,
    "runner_hit_win_reward": 65.0,
    "tagger_hit_win_penalty": 28.0,
    "catch_reward": 36.0,
    "caught_penalty": 30.0,
    "timeout_runner_reward": 18.0,
    "timeout_tagger_penalty": 18.0,
    "bad_catch_penalty": 0.65,
    "runner_hold_penalty": 0.3,
    "runner_bad_throw_penalty": 0.9,
    "runner_panic_hold_penalty": 0.75,
}

DEFAULT_MAPS = [
    "maps/default_arena.json",
    "maps/ring_training.json",
    "maps/two_story_villa.json",
    "maps/woodland_mansion.json",
    "maps/desert_temple.json",
]


# --------------------------------------------------------------------------
# Map / grid helpers (kept identical to train_pathfinder.py so both policies
# operate on the same discretisation).
# --------------------------------------------------------------------------
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


def build_grid(map_data: dict, cell_size: float, agent_radius: float):
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


def compute_components(grid: dict):
    labels = [[-1 for _ in range(grid["height"])] for _ in range(grid["width"])]
    comps = []
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


def distance(a, b) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def blocked_mask(grid: dict, agent) -> int:
    mask = 0
    for i, (dx, dz) in enumerate(MOVE_ACTIONS):
        if not is_free(grid, (agent[0] + dx, agent[1] + dz)):
            mask |= 1 << i
    return mask


def state_key(agent, target, grid) -> tuple:
    dx = max(-MAX_RELATIVE_CELLS, min(MAX_RELATIVE_CELLS, target[0] - agent[0]))
    dz = max(-MAX_RELATIVE_CELLS, min(MAX_RELATIVE_CELLS, target[1] - agent[1]))
    return dx, dz, blocked_mask(grid, agent)


def geodesic_field(grid: dict, source):
    field = {source: 0}
    q = deque([source])
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


def line_clear(grid: dict, a, b) -> bool:
    steps = max(abs(a[0] - b[0]), abs(a[1] - b[1]))
    if steps <= 1:
        return True
    for i in range(1, steps):
        t = i / steps
        cell = (round(a[0] + (b[0] - a[0]) * t), round(a[1] + (b[1] - a[1]) * t))
        if not is_free(grid, cell):
            return False
    return True


def legal_moves(grid: dict, agent):
    """Indices of move actions that stay on a free cell (plus the hold action)."""
    moves = []
    for i, (dx, dz) in enumerate(MOVE_ACTIONS):
        if is_free(grid, (agent[0] + dx, agent[1] + dz)):
            moves.append(i)
    moves.append(CATCH_ACTION_INDEX)
    return moves


def step_cell(grid: dict, agent, action_index):
    if action_index == CATCH_ACTION_INDEX:
        return agent
    dx, dz = ACTIONS[action_index]
    nxt = (agent[0] + dx, agent[1] + dz)
    return nxt if is_free(grid, nxt) else agent


# --------------------------------------------------------------------------
# Self-play Q-learning
# --------------------------------------------------------------------------
class QTable:
    def __init__(self, epsilon: float, alpha: float, gamma: float):
        self.q = defaultdict(lambda: [0.0] * len(ACTIONS))
        self.epsilon = epsilon
        self.alpha = alpha
        self.gamma = gamma

    def choose(self, key, legal, greedy=False):
        if not greedy and random.random() < self.epsilon:
            return random.choice(legal)
        values = self.q[key]
        best = legal[0]
        best_v = values[best]
        for a in legal[1:]:
            if values[a] > best_v:
                best_v = values[a]
                best = a
        return best

    def update(self, key, action, reward, next_key, next_legal, done):
        cur = self.q[key][action]
        if done or not next_legal:
            target = reward
        else:
            nxt_vals = self.q[next_key]
            target = reward + self.gamma * max(nxt_vals[a] for a in next_legal)
        self.q[key][action] = cur + self.alpha * (target - cur)


def sample_start_pair(grid: dict, components, min_dist: float):
    big = [c for c in components if len(c) >= 8] or [c for c in components if len(c) >= 2]
    if not big:
        return None
    comp = random.choices(big, weights=[len(c) for c in big])[0]
    for _ in range(64):
        a = random.choice(comp)
        b = random.choice(comp)
        if distance(a, b) >= min_dist:
            return a, b
    return None


def run_episode(grid, components, tagger_q, runner_q, max_steps, reward_cfg, min_start_dist, greedy=False):
    """Play one chase episode. Returns (caught, runner_hit_win, steps, runner_hits)."""
    pair = sample_start_pair(grid, components, min_dist=min_start_dist)
    if pair is None:
        return None
    tagger, runner = pair

    caught = False
    runner_hit_win = False
    runner_hits = 0
    runner_throw_cooldown = 0
    tagger_speed_credit = 0.0
    for step in range(max_steps):
        if distance(tagger, runner) <= CATCH_DISTANCE_CELLS:
            caught = True
            break

        prev_gap = distance(tagger, runner)

        t_key = state_key(tagger, runner, grid)
        t_legal = legal_moves(grid, tagger)
        t_action = tagger_q.choose(t_key, t_legal, greedy)

        r_key = state_key(runner, tagger, grid)
        r_legal = legal_moves(grid, runner)
        r_action = runner_q.choose(r_key, r_legal, greedy)

        new_tagger = step_cell(grid, tagger, t_action)
        new_runner = step_cell(grid, runner, r_action)
        tagger_speed_credit += reward_cfg["tagger_speed_advantage"]
        if tagger_speed_credit >= 1.0 and new_tagger != new_runner:
            extra_tagger = step_cell(grid, new_tagger, t_action)
            if distance(extra_tagger, new_runner) < distance(new_tagger, new_runner):
                new_tagger = extra_tagger
            tagger_speed_credit -= 1.0

        new_gap = distance(new_tagger, new_runner)
        now_caught = new_gap <= CATCH_DISTANCE_CELLS
        throw_ready = runner_throw_cooldown <= 0
        in_throw_range = reward_cfg["throw_min_distance"] <= new_gap <= reward_cfg["throw_max_distance"]
        can_hit_tagger = throw_ready and in_throw_range and line_clear(grid, new_runner, new_tagger)
        runner_scored_hit = False
        if can_hit_tagger and not now_caught:
            # Runtime throwing is handled by game.gd's AI throwable strategy, not
            # directly by the movement policy. In training, treat a clear throw
            # window as an automatic hit opportunity so the runner learns to keep
            # the right distance and line of sight for scoring 10 hits.
            runner_hits += 1
            runner_scored_hit = True
            runner_throw_cooldown = int(reward_cfg["throw_cooldown_steps"])
        else:
            runner_throw_cooldown = max(0, runner_throw_cooldown - 1)

        runner_hit_win = runner_hits >= RUNNER_HITS_TO_WIN
        done = now_caught or runner_hit_win or step == max_steps - 1

        gap_gain = prev_gap - new_gap
        gap_loss = new_gap - prev_gap
        close_pressure = max(0.0, reward_cfg["pressure_radius"] - new_gap)
        throw_error = abs(new_gap - reward_cfg["throw_ideal_distance"])

        tagger_reward = -reward_cfg["tagger_step_penalty"]
        runner_reward = reward_cfg["runner_step_reward"]

        if gap_gain > 0.0:
            tagger_reward += gap_gain * reward_cfg["tagger_gap_gain_scale"]
            runner_reward -= gap_gain * reward_cfg["runner_pressure_scale"]
        elif gap_loss > 0.0:
            tagger_reward -= gap_loss * reward_cfg["tagger_gap_loss_scale"]
            runner_reward += gap_loss * reward_cfg["runner_gap_gain_scale"]

        if in_throw_range and line_clear(grid, new_runner, new_tagger):
            runner_reward += max(0.0, reward_cfg["throw_window_reward"] - throw_error * 0.08)
            tagger_reward -= 0.08

        if close_pressure > 0.0:
            tagger_reward += close_pressure * reward_cfg["tagger_pressure_bonus"]
            runner_reward -= close_pressure * reward_cfg["runner_pressure_penalty"]

        if runner_scored_hit:
            runner_reward += reward_cfg["runner_hit_reward"] + runner_hits * 0.2
            tagger_reward -= reward_cfg["tagger_hit_penalty"]
        elif r_action == CATCH_ACTION_INDEX:
            runner_reward -= reward_cfg["runner_bad_throw_penalty"]
            if new_gap <= reward_cfg["pressure_radius"] + 1.0:
                runner_reward -= reward_cfg["runner_panic_hold_penalty"]

        if runner_hit_win:
            runner_reward += reward_cfg["runner_hit_win_reward"]
            tagger_reward -= reward_cfg["tagger_hit_win_penalty"]
        elif now_caught:
            tagger_reward += reward_cfg["catch_reward"]
            runner_reward -= reward_cfg["caught_penalty"]
        elif done:
            runner_reward += reward_cfg["timeout_runner_reward"]
            tagger_reward -= reward_cfg["timeout_tagger_penalty"]

        if t_action == CATCH_ACTION_INDEX and not now_caught:
            tagger_reward -= reward_cfg["bad_catch_penalty"]

        if not greedy:
            nt_key = state_key(new_tagger, new_runner, grid)
            nt_legal = legal_moves(grid, new_tagger)
            tagger_q.update(t_key, t_action, tagger_reward, nt_key, nt_legal, done)

            nr_key = state_key(new_runner, new_tagger, grid)
            nr_legal = legal_moves(grid, new_runner)
            runner_q.update(r_key, r_action, runner_reward, nr_key, nr_legal, done)

        tagger, runner = new_tagger, new_runner
        if now_caught:
            caught = True
            break
        if runner_hit_win:
            break

    return caught, runner_hit_win, step + 1, runner_hits


def _format_seconds(seconds: float) -> str:
    minutes = int(seconds // 60)
    secs = int(seconds % 60)
    return f"{minutes:02d}:{secs:02d}"


def _print_progress(elapsed, interval_elapsed, interval_played, interval_catches, interval_runner_hit_wins, interval_hit_sum, total_played) -> None:
    if interval_played <= 0:
        print(f"[progress {_format_seconds(elapsed)}] last_{interval_elapsed:.0f}s_episodes=0 total_episodes={total_played}", flush=True)
        return
    interval_timeouts = interval_played - interval_catches - interval_runner_hit_wins
    runner_total_wins = interval_runner_hit_wins + interval_timeouts
    print(
        f"[progress {_format_seconds(elapsed)}] "
        f"last_{interval_elapsed:.0f}s_episodes={interval_played} "
        f"runner_total_win_rate={runner_total_wins / interval_played:.2%} "
        f"tagger_catch_win_rate={interval_catches / interval_played:.2%} "
        f"runner_10hit_win_rate={interval_runner_hit_wins / interval_played:.2%} "
        f"runner_timeout_win_rate={interval_timeouts / interval_played:.2%} "
        f"avg_runner_hits={interval_hit_sum / interval_played:.2f} "
        f"total_episodes={total_played}",
        flush=True,
    )


def train(
    maps,
    episodes,
    max_steps,
    seed,
    alpha,
    gamma,
    epsilon_start,
    epsilon_end,
    reward_cfg,
    start_min_dist,
    end_min_dist,
    duration_seconds=0.0,
    progress_interval=0.0,
):
    random.seed(seed)
    tagger_q = QTable(epsilon_start, alpha, gamma)
    runner_q = QTable(epsilon_start, alpha, gamma)

    catches = 0
    runner_hit_wins = 0
    hit_sum = 0
    played = 0
    ep = 0
    start_time = time.monotonic()
    last_progress_time = start_time
    interval_played = 0
    interval_catches = 0
    interval_runner_hit_wins = 0
    interval_hit_sum = 0

    while True:
        now = time.monotonic()
        elapsed = now - start_time
        if duration_seconds > 0.0:
            if elapsed >= duration_seconds:
                break
            frac = min(1.0, elapsed / max(duration_seconds, 0.001))
        else:
            if ep >= episodes:
                break
            frac = ep / max(1, episodes - 1)
        ep += 1

        eps = epsilon_start + (epsilon_end - epsilon_start) * frac
        min_start_dist = start_min_dist + (end_min_dist - start_min_dist) * frac
        tagger_q.epsilon = eps
        runner_q.epsilon = eps

        m = random.choice(maps)
        result = run_episode(
            m["grid"],
            m["components"],
            tagger_q,
            runner_q,
            max_steps,
            reward_cfg,
            min_start_dist,
        )
        if result is None:
            continue
        caught, runner_hit_win, _, runner_hits = result
        played += 1
        interval_played += 1
        hit_sum += runner_hits
        interval_hit_sum += runner_hits
        if caught:
            catches += 1
            interval_catches += 1
        if runner_hit_win:
            runner_hit_wins += 1
            interval_runner_hit_wins += 1

        now = time.monotonic()
        if progress_interval > 0.0 and now - last_progress_time >= progress_interval:
            interval_elapsed = now - last_progress_time
            _print_progress(now - start_time, interval_elapsed, interval_played, interval_catches, interval_runner_hit_wins, interval_hit_sum, played)
            last_progress_time = now
            interval_played = 0
            interval_catches = 0
            interval_runner_hit_wins = 0
            interval_hit_sum = 0

    total_train_seconds = time.monotonic() - start_time
    if progress_interval > 0.0 and interval_played > 0:
        _print_progress(total_train_seconds, time.monotonic() - last_progress_time, interval_played, interval_catches, interval_runner_hit_wins, interval_hit_sum, played)

    tagger_policy = greedy_policy(tagger_q)
    runner_policy = greedy_policy(runner_q)
    metrics = evaluate(maps, tagger_q, runner_q, max_steps, reward_cfg, end_min_dist, seed + 7)
    metrics["train_seconds"] = total_train_seconds
    metrics["train_episodes"] = played
    train_timeouts = played - catches - runner_hit_wins
    metrics["train_runner_total_win_rate"] = ((runner_hit_wins + train_timeouts) / played) if played else 0.0
    metrics["train_catch_rate"] = (catches / played) if played else 0.0
    metrics["train_runner_hit_win_rate"] = (runner_hit_wins / played) if played else 0.0
    metrics["train_runner_timeout_win_rate"] = (train_timeouts / played) if played else 0.0
    metrics["train_avg_runner_hits"] = (hit_sum / played) if played else 0.0
    metrics["tagger_states"] = len(tagger_policy)
    metrics["runner_states"] = len(runner_policy)
    return tagger_policy, runner_policy, metrics


def greedy_policy(qtable: QTable) -> dict:
    """Freeze the learned Q-table into a deterministic best-action table.

    We drop states whose best action is a wall move (mask bit set) so the game
    side falls back to its safe navigation instead of steering into geometry.
    """
    policy = {}
    for key, values in qtable.q.items():
        mask = key[2]
        best = None
        best_v = -1e18
        for a in range(len(ACTIONS)):
            if a != CATCH_ACTION_INDEX and (mask >> a) & 1:
                continue
            if values[a] > best_v:
                best_v = values[a]
                best = a
        if best is None:
            continue
        if abs(best_v) < 1e-9:
            continue  # never actually learned anything useful for this state
        policy[key] = best
    return policy


def evaluate(maps, tagger_q, runner_q, max_steps, reward_cfg, min_start_dist, seed) -> dict:
    random.seed(seed)
    total = 0
    caught_count = 0
    runner_hit_win_count = 0
    step_sum = 0
    hit_sum = 0
    per_map = 40
    for m in maps:
        for _ in range(per_map):
            result = run_episode(
                m["grid"],
                m["components"],
                tagger_q,
                runner_q,
                max_steps,
                reward_cfg,
                min_start_dist,
                greedy=True,
            )
            if result is None:
                continue
            caught, runner_hit_win, steps, runner_hits = result
            total += 1
            step_sum += steps
            hit_sum += runner_hits
            if caught:
                caught_count += 1
            if runner_hit_win:
                runner_hit_win_count += 1
    timeout_count = total - caught_count - runner_hit_win_count
    return {
        "eval_episodes": total,
        "eval_runner_total_win_rate": ((runner_hit_win_count + timeout_count) / total) if total else 0.0,
        "eval_tagger_catch_rate": (caught_count / total) if total else 0.0,
        "eval_runner_hit_win_rate": (runner_hit_win_count / total) if total else 0.0,
        "eval_runner_timeout_win_rate": (timeout_count / total) if total else 0.0,
        "eval_avg_runner_hits": (hit_sum / total) if total else 0.0,
        "eval_avg_chase_steps": (step_sum / total) if total else 0.0,
    }


def export_policy(path: Path, maps, grid, policy, metrics, seed, role, reward_cfg, training_cfg) -> None:
    policy_str = {",".join(str(v) for v in key): action for key, action in policy.items()}
    out = {
        "metadata": {
            "algorithm": "selfplay_q_learning_relative_obstacle_mask_multimap",
            "role": role,
            "source_maps": [m["path"] for m in maps],
            "map_names": [m["name"] for m in maps],
            "seed": seed,
            "cell_size": grid["cell_size"],
            "max_relative_cells": MAX_RELATIVE_CELLS,
            "catch_action_index": CATCH_ACTION_INDEX,
            "catch_distance_cells": CATCH_DISTANCE_CELLS,
            "runner_hits_to_win": RUNNER_HITS_TO_WIN,
            "relative_state": True,
            "actions": ACTIONS,
            "reward_config": reward_cfg,
            "training_config": training_cfg,
            "metrics": metrics,
        },
        "policy": policy_str,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))


def main() -> None:
    parser = argparse.ArgumentParser(description="Self-play RL: tagger vs runner learn against each other.")
    parser.add_argument("--maps", default=",".join(DEFAULT_MAPS))
    parser.add_argument("--tagger-out", default="rl/trained_policy.json")
    parser.add_argument("--runner-out", default="rl/trained_runner_policy.json")
    parser.add_argument("--episodes", type=int, default=8500)
    parser.add_argument("--max-steps", type=int, default=80)
    parser.add_argument("--cell-size", type=float, default=2.0)
    parser.add_argument("--agent-radius", type=float, default=0.5)
    parser.add_argument("--alpha", type=float, default=0.18)
    parser.add_argument("--gamma", type=float, default=0.95)
    parser.add_argument("--epsilon-start", type=float, default=0.95)
    parser.add_argument("--epsilon-end", type=float, default=0.02)
    parser.add_argument("--start-min-dist", type=float, default=3.0)
    parser.add_argument("--end-min-dist", type=float, default=7.0)
    parser.add_argument("--duration-seconds", type=float, default=0.0, help="Train by wall-clock time; 0 means use --episodes.")
    parser.add_argument("--progress-interval", type=float, default=0.0, help="Print interval training stats every N seconds; 0 disables progress output.")
    parser.add_argument("--seed", type=int, default=114514)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    tagger_out = (root / args.tagger_out).resolve()
    runner_out = (root / args.runner_out).resolve()

    maps = []
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

    reward_cfg = dict(DEFAULT_REWARD_CONFIG)
    training_cfg = {
        "episodes": args.episodes,
        "max_steps": args.max_steps,
        "alpha": args.alpha,
        "gamma": args.gamma,
        "epsilon_start": args.epsilon_start,
        "epsilon_end": args.epsilon_end,
        "start_min_dist": args.start_min_dist,
        "end_min_dist": args.end_min_dist,
        "duration_seconds": args.duration_seconds,
        "progress_interval": args.progress_interval,
    }

    print(f"self-play training on {len(maps)} maps: {[m['name'] for m in maps]}")
    print(json.dumps({"training_config": training_cfg, "reward_config": reward_cfg}, ensure_ascii=False, indent=2))
    tagger_policy, runner_policy, metrics = train(
        maps,
        args.episodes,
        args.max_steps,
        args.seed,
        args.alpha,
        args.gamma,
        args.epsilon_start,
        args.epsilon_end,
        reward_cfg,
        args.start_min_dist,
        args.end_min_dist,
        args.duration_seconds,
        args.progress_interval,
    )
    export_policy(tagger_out, maps, maps[0]["grid"], tagger_policy, metrics, args.seed, "tagger", reward_cfg, training_cfg)
    export_policy(runner_out, maps, maps[0]["grid"], runner_policy, metrics, args.seed, "runner", reward_cfg, training_cfg)
    print(json.dumps(metrics, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
