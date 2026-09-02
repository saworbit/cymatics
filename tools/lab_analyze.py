#!/usr/bin/env python3
"""Summarize a CYMATICS AI lab run (events.jsonl + summary.json)."""

from __future__ import annotations

import json
import math
import sys
from collections import Counter
from pathlib import Path


def load_events(path: Path) -> list[dict]:
    rows = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def pct(n: int, d: int) -> str:
    if d <= 0:
        return "n/a"
    return f"{100.0 * n / d:.1f}%"


def mean(xs: list[float]) -> float:
    return sum(xs) / len(xs) if xs else 0.0


def analyze(run_dir: Path) -> str:
    events_path = run_dir / "events.jsonl"
    if not events_path.exists():
        return f"no events.jsonl in {run_dir}"
    rows = load_events(events_path)
    kinds = Counter(r.get("kind") for r in rows)
    goals = [r for r in rows if r.get("kind") == "goal"]
    hits = [r for r in rows if r.get("kind") == "rally_hit"]
    caroms = [r for r in rows if r.get("kind") == "carom"]
    collects = [r for r in rows if r.get("kind") == "powerup_collect"]
    spawns = [r for r in rows if r.get("kind") == "powerup_spawn"]
    stucks = [r for r in rows if r.get("kind") == "stuck_behind"]
    serves = [r for r in rows if r.get("kind") == "serve"]
    samples = [r for r in rows if r.get("kind") == "sample"]

    rally_lens = [float(g.get("data", {}).get("rally_hits") or 0) for g in goals]
    aces = sum(1 for g in goals if g.get("data", {}).get("ace"))
    stuck_goals = sum(1 for g in goals if g.get("data", {}).get("stuck"))
    spins = [abs(float(h.get("data", {}).get("spin") or 0)) for h in hits]
    cuts = [abs(float(c.get("data", {}).get("cut") or 0)) for c in caroms]

    # Ball speed from samples
    speeds = []
    for s in samples:
        b = s.get("data", {}).get("ball") or {}
        vx = float(b.get("vx") or 0)
        vy = float(b.get("vy") or 0)
        speeds.append(math.hypot(vx, vy))

    collect_by = Counter(int(c.get("data", {}).get("player", -1)) for c in collects)
    spawn_x = [float((s.get("data") or {}).get("x") or 0) for s in spawns]

    lines = []
    lines.append(f"AI lab report  {run_dir.name}")
    lines.append("=" * 48)
    lines.append(f"events {len(rows)}   samples {len(samples)}   sim-end kinds: {dict(kinds)}")
    lines.append("")
    lines.append("Scoring")
    lines.append(f"  points {len(goals)}   aces {aces} ({pct(aces, len(goals))})   stuck-behind goals {stuck_goals}")
    lines.append(f"  rally hits at goal: mean {mean(rally_lens):.2f}  max {max(rally_lens) if rally_lens else 0:.0f}")
    lines.append(f"  serves {len(serves)}")
    lines.append("")
    lines.append("Feel / physics")
    lines.append(f"  paddle contacts {len(hits)}   |spin| mean {mean(spins):.2f}")
    lines.append(f"  ball |v| mean {mean(speeds):.0f} px/s")
    lines.append(f"  orb spawns {len(spawns)}  collects {len(collects)}  collect rate {pct(len(collects), len(spawns))}")
    lines.append(f"    Padd grabbed {collect_by.get(0, 0)}  Lin grabbed {collect_by.get(1, 0)}")
    lines.append(f"  caroms {len(caroms)}  |cut| mean {mean(cuts):.2f}  thick cuts {sum(1 for c in cuts if c > 0.32)}")
    if spawn_x:
        lines.append(f"  orb spawn x mean {mean(spawn_x):.0f} (court center 960)")
    lines.append(f"  stuck-behind events {len(stucks)}")
    lines.append("")
    lines.append("What to iterate")
    if goals and mean(rally_lens) < 2.0:
        lines.append("  - rallies die instantly: serve, first-contact, or goal volume")
    elif goals and mean(rally_lens) > 12.0:
        lines.append("  - rallies never end: AI too tight or ball never beats a paddle")
    elif not goals and len(hits) >= 4:
        lines.append("  - no goals in this tape; rallies are happening (paddle contacts %d)" % len(hits))
    if stuck_goals > 0 or len(stucks) > 2:
        lines.append("  - still getting pinned behind a paddle")
    if len(spawns) and len(collects) / max(len(spawns), 1) < 0.25:
        lines.append("  - orbs rarely get grabbed: spawn, mass, or AI seek")
    if mean(cuts) < 0.15 and caroms:
        lines.append("  - caroms are too center: english is not showing up in play")
    if not lines[-1].startswith("  -"):
        lines.append("  - no automatic red flags. watch a Y-key match and read samples.")
    summary = run_dir / "summary.json"
    if summary.exists():
        lines.append("")
        lines.append("Engine summary.json")
        lines.append("  " + summary.read_text(encoding="utf-8").replace("\n", "\n  "))
    return "\n".join(lines)


def latest_run(root: Path) -> Path | None:
    runs = root / "lab" / "runs"
    if not runs.exists():
        return None
    dirs = [p for p in runs.iterdir() if p.is_dir() and (p / "events.jsonl").exists()]
    if not dirs:
        return None
    return max(dirs, key=lambda p: p.stat().st_mtime)


def main() -> int:
    here = Path(__file__).resolve().parents[1]
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else latest_run(here)
    if target is None:
        print("no lab runs yet. start with tools/run_lab.ps1")
        return 1
    if target.is_file():
        target = target.parent
    print(analyze(target))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
