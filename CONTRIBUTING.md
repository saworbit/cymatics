# Contributing

Thanks for paddlin' with us.

## Setup

- Godot **4.7.2** (Forward+).
- Open the repo root (`project.godot`).

## Layout

| Path | What goes there |
| --- | --- |
| `src/actors/` | Characters and interactables (paddles, ball, powerups, bolts) |
| `src/systems/` | Match, fluids, audio, VFX, HUD |
| `scenes/` | `.tscn` scenes |
| `shaders/` | Canvas and compute shaders |
| `assets/` | Icons and baked art |
| `docs/design/` | Specs (codename CYMATICS) |

Keep `res://` paths matching that tree.

## Pull requests

1. Branch from `main`.
2. One idea per PR.
3. CI must import the project headless.
4. If you change gameplay feel, note it in the PR body.

Use the [pull request template](.github/PULL_REQUEST_TEMPLATE.md).

## Code style

- GDScript: tabs, `class_name` on public types, typed locals where Godot will infer.
- Don't commit `.godot/`, `.mcp/`, or `mcp_bridge.gd`.
