# AI vs AI lab

A closed loop for iterating on That's a Paddlin' without sitting in every rally yourself.

Two copies of the same paddle brain play each other. Every serve, contact, carom, grab, goal, and stuck-behind pin is written to disk. A small analyzer turns that into a one-page report so the next change has numbers, not vibes.

## Why

Human play is slow and noisy. The interesting bugs (Lin pinned with Bam behind him, orbs dying in midcourt, english that never shows up) show up in volume only when the match runs itself. The lab is that volume.

It is not a ranked ELO ladder and it is not training a new model. It is a telemetry bench for the game we already have.

## Two ways in

### Watch it (editor)

1. Play `scenes/main.tscn`.
2. Press **Y**.
3. Padd and Lin both go AI. HUD says `LAB AI vs AI`.
4. Events stream to `lab/runs/<timestamp>/`.

Scoring stays first-to-7 / best-of-3 so you can watch a real match. Clock stays 1x.

### Batch it (headless)

From the repo root, with Godot 4.7.2 on `PATH` or `GODOT` set:

```powershell
.\tools\run_lab.ps1
```

Defaults: one short match (first to 3, one set), 90 simulated seconds cap, 4x clock, audio muted.

```powershell
.\tools\run_lab.ps1 -Matches 3 -Seconds 180 -Scale 4
```

Equivalent raw launch:

```text
godot --headless --path . -- --lab --lab-matches=1 --lab-seconds=90 --lab-scale=4 --lab-quiet
```

Headless scoring is shortened on purpose (3 points, 1 set) so a change-test-report loop fits in a couple of minutes.

Then:

```text
python tools/lab_analyze.py
python tools/lab_analyze.py lab/runs/<timestamp>
```

## Flags

| Flag | Meaning |
| --- | --- |
| `--lab` | Dual AI + recorder |
| `--lab-matches=N` | Stop after N finished matches (headless) |
| `--lab-seconds=S` | Stop after S **simulated** seconds |
| `--lab-scale=F` | `Engine.time_scale` (1–8). Watch mode ignores this |
| `--lab-quiet` | Mute the Master bus. Headless implies this |

User args must sit after `--` so Godot does not eat them.

## What gets written

Each run is a folder:

```text
lab/runs/2026-09-02_17-05-01/
  events.jsonl
  summary.json
```

`events.jsonl` is one JSON object per line.

| `kind` | When | Useful fields |
| --- | --- | --- |
| `lab_start` / `lab_end` | boot / stop | matches, time_scale, reason |
| `sample` | every 8 physics frames | ball x/y/vx/vy/spin, both paddles, orb, score |
| `serve` | serve ritual | server 0/1 |
| `rally_hit` | paddle contact | player, speed, spin, perfect, hits |
| `carom` | ball strikes an orb | cut, spin |
| `powerup_spawn` | orb appears | kind, x, y |
| `powerup_collect` | paddle grabs orb | kind, player |
| `stuck_behind` | ball behind a paddle ≥ 0.7s | side, duration |
| `near_miss` | ball skims a paddle | side |
| `goal` | point scored | rally_hits, ace, stuck, ball snapshot |
| `match_won` | set/match over | winner, sets |

`summary.json` is the engine's own roll-up: points, aces, caroms, collects, stuck-behind count, mean rally length.

Runs are gitignored. Keep the analyzer, not the raw tape.

## How to read a report

The analyzer prints a short lab sheet plus red flags:

- **rallies die instantly** — serve, first contact, or the goal is too hungry
- **rallies never end** — AI too tight, or Bam cannot beat a paddle
- **stuck-behind** — the pin we just fixed is back
- **orbs rarely get grabbed** — spawn lane, mass, or seek
- **caroms too center** — english is not happening in real rallies

Use that list as the next playtest ticket. Change one thing. Run the lab again. Diff the two `summary.json` files.

## Architecture

```text
Y or --lab
    │
    ▼
Main._start_lab
    ├─ PaddleAI on Padd (left)     same brain, mirrored incoming
    ├─ PaddleAI on Lin (right)     existing node
    ├─ LabMode.apply_clock
    └─ LabRecorder → lab/runs/<id>/events.jsonl
                            └─ summary.json
                                    │
                                    ▼
                           tools/lab_analyze.py
```

The paddle brain (`src/actors/paddle_ai.gd`) is side-agnostic: incoming is `velocity.x` toward that paddle's goal, intercept is the goal-side X, english aims at the other paddle. Lab mode freezes difficulty at 1.0 so drama rubber-banding does not pollute the tape.

Recorder lives in `src/systems/lab_recorder.gd`. Flag parsing lives in `src/systems/lab_mode.gd`. Neither runs unless lab is on.

## Iterate loop

1. Name the feel you want in one sentence ("orbs should get grabbed at least half the time").
2. Run `.\tools\run_lab.ps1 -Seconds 90`.
3. Read the analyzer. If the number did not move, the change did not hit the rally.
4. Repeat. Watch with **Y** only when the number moved and you need to see *why*.

Do not treat a single 90-second tape as truth. Two or three runs is a trend. A watched match is a story.

## Limits

- Not deterministic. Fluids, AI noise, and serve jitter move. Compare distributions, not single goals.
- Headless uses whatever GPU/CPU fallback the machine has. Reports from a laptop and a 3070 are not the same tape.
- High `lab-scale` (above ~6) can make hydro look drunk. Stay at 4 unless you are only counting goals.
- This does not replace playing the game. It tells you where to play.
