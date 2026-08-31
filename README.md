# That's a Paddlin'

**Codename: CYMATICS**

A hyper-kinetic 1v1 arcade sport inside a living plasma field. You are **Padd**. They are **Lin**. The ball is **Bam**. Stir, suck, blast, and paddlin'.

Spiritual successor to [Plasma Pong](https://en.wikipedia.org/wiki/Plasma_Pong) (Steve Taylor, 2006) — see [`third_party/plasma_pong/`](third_party/plasma_pong/).

![Godot 4.7](https://img.shields.io/badge/Godot-4.7.2-478cbf?logo=godotengine&logoColor=white)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![CI](https://github.com/saworbit/cymatics/actions/workflows/ci.yml/badge.svg)

## Play

| Control | Action |
| --- | --- |
| Mouse on your side, or WASD | Move Padd |
| LMB / J | Stream plasma |
| RMB / K | Suction vortex |
| Space | Blast / stun cannon / super |
| Time Space on contact | **PERFECT** parry |
| G | Toggle Gauntlet Mode (5 Boss Stages) |
| T | Toggle AI (Lin) |
| R | Rematch / Retry |
| Z | Zen mode |
| M | Toggle match music |

Grab mid-rally orbs: **MULTI**, **GIANT**, **TINY**, **STUN**, **MAG**, **FIRE**, **HYPER**, plus shapeshifters **PRISM**, **CUBE**, **STAR**, **BLOB**, **SCOOP**, **WEDGE**, **AEGIS**.

First to 7, win by 2, best of 3.

## Run locally

1. Install **Godot 4.7.2** (Forward+).
2. Open this folder as a project (`project.godot`).
3. Press Play. Main scene is `scenes/main.tscn`.

```text
That's a Paddlin'/
├── assets/           # icons and static art
├── docs/             # design docs (codename CYMATICS)
├── scenes/           # Godot scenes
├── shaders/          # display, VFX, compute fluids
├── src/
│   ├── actors/       # Padd, Lin, Bam, orbs, bolts
│   └── systems/      # match flow, fluids, audio, HUD
├── third_party/      # historical Plasma Pong source (not MIT)
└── .github/          # CI and templates
```

## Design docs

- [Game design](docs/design/gdd.md)
- [Technical spec](docs/design/technical.md)
- [Visual](docs/design/visual.md)
- [Audio](docs/design/audio.md)
- [Netcode (planned)](docs/design/netcode.md)
- [API (planned)](docs/design/api.md)

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
