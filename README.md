# That's a Paddlin'

**Codename: CYMATICS**

A hyper-kinetic 1v1 arcade sport inside a living plasma field. You are **Padd**. They are **Lin**. The ball is **Bam**. Stir, suck, blast, and paddlin'.

Spiritual successor to [Plasma Pong](https://en.wikipedia.org/wiki/Plasma_Pong) (Steve Taylor, 2006) — see [`third_party/plasma_pong/`](third_party/plasma_pong/).

![Godot 4.7](https://img.shields.io/badge/Godot-4.7.2-478cbf?logo=godotengine&logoColor=white)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![CI](https://github.com/saworbit/cymatics/actions/workflows/ci.yml/badge.svg)

## Play

| Padd (P1) | Lin (P2, local duel) | Action |
| --- | --- | --- |
| Mouse or WASD, pad 1 left stick | Arrows, pad 2 left stick | Move |
| LMB / J / RT | `,` / RT | Stream plasma |
| RMB / K / LT | `.` / LT | Suck. Hold near the ball to **capture** it into an orbit, release to **slingshot** it along the tangent |
| Space / pad A | `/` / pad A | Tap: blast. Hold: **charge** a bigger blast. Tap as the ball arrives: **PERFECT** parry |
| Left Shift / pad B | Right Shift / pad B | Resonance super (when the momentum bar is full) |
| Move axis while serving | | Aim the serve (4 s serve clock, then it auto-serves) |
| Esc, P, Start | | Pause |

Mouse and keyboard hand P1 off to whichever you touched last. Dev hotkeys in a match: **R** rematch, **T** toggle AI, **G** gauntlet, **Z** zen, **M** music, **Y** AI-vs-AI lab.

Grab mid-rally orbs: **MULTI**, **GIANT**, **TINY**, **STUN**, **MAG**, **FIRE**, **HYPER**, plus shapeshifters **PRISM**, **CUBE**, **STAR**, **BLOB**, **SCOOP**, **WEDGE**, **AEGIS**.

First to 7, win by 2, best of 3.

## Run locally

1. Install **Godot 4.7.2** (Forward+).
2. Generate the audio (once, needs Python with `numpy` and `scipy`):

   ```bash
   python tools/gen_sfx.py && python tools/gen_music.py
   ```

   Sound effects and the synth soundtrack are synthesised, not stored in the
   repo. The generators are deterministic and take about ten seconds. Skip
   this and the game still runs, just mostly silent.
3. Open this folder as a project (`project.godot`).
4. Press Play. Main scene is `scenes/main.tscn`.

```text
That's a Paddlin'/
├── assets/           # audio, UI theme, icons
├── docs/             # design docs (codename CYMATICS)
├── scenes/           # Godot scenes
├── shaders/          # display, VFX, compute fluids
├── src/
│   ├── actors/       # Padd, Lin, Bam, orbs, bolts
│   └── systems/      # match flow, fluids, audio, HUD
├── third_party/      # historical Plasma Pong source (not MIT)
├── tools/            # lab runner, SFX generator, screenshot driver, script check
└── .github/          # CI and templates
```

## Tests

```bash
bash tools/run_tests.sh /path/to/godot
```

Unit tests live in `tests/test_*.gd`; `tests/integration_run.gd` boots the real
scene and checks invariants while hammering pause, restart, mode switches and
fluid-quality changes. Both run headless and gate CI.

Polish status and roadmap: [`docs/POLISH_PLAN.md`](docs/POLISH_PLAN.md). Agent notes: [`CLAUDE.md`](CLAUDE.md).

## Design docs

- [Game design](docs/design/gdd.md)
- [Technical spec](docs/design/technical.md)
- [Visual](docs/design/visual.md)
- [Audio](docs/design/audio.md)
- [Netcode (planned)](docs/design/netcode.md)
- [API (planned)](docs/design/api.md)
- [AI vs AI lab](docs/design/ai-lab.md)

## AI lab

Two AIs play each other and dump rally telemetry so we can iterate without sitting every point.

Watch: press **Y** in a running match.

Batch:

```powershell
.\tools\run_lab.ps1
python tools/lab_analyze.py
```

Details: [docs/design/ai-lab.md](docs/design/ai-lab.md).

## Credits

- **That's a Paddlin' / CYMATICS** — Shane Wall, 2026. MIT.
- **Plasma Pong** — Steve Taylor, 2006. Original source lives in `third_party/plasma_pong/` and is **not** covered by this MIT license.
- Fluid method after **Jos Stam**, *Real-Time Fluid Dynamics for Games* (GDC 2003).
- Title from the Simpsons "that's a paddlin'" bit. Not affiliated with the Simpsons.
- Match music: MintoDog, *Hope (Orchestral battle music)*, CC0.
- SFX: Kenney.nl interface, sci-fi, and digital packs, CC0. See [`assets/audio/CREDITS.md`](assets/audio/CREDITS.md).

## License

Game code and original assets: [MIT](LICENSE).

Plasma Pong files under `third_party/plasma_pong/` remain copyright Steve Taylor (2006). See [NOTICE](third_party/plasma_pong/NOTICE.md).
