# That's a Paddlin' (codename CYMATICS)

Godot 4.7 arcade sport: two paddles, a ball, a GPU fluid field that acts as a
third player. GDScript only, no addons, no autoloads except `Settings`.

## Run and verify

- Editor binary on this machine: `C:/Godot/godot.cmd` (CI uses 4.7.2 Linux).
- Parse every script: `bash tools/check_scripts.sh C:/Godot/godot.cmd`
- Tests: `bash tools/run_tests.sh C:/Godot/godot.cmd` (unit + integration).
  Unit tests are `tests/test_*.gd` extending `TestCase`; add a file there and
  the runner finds it. `tests/integration_run.gd` boots the real scene and
  asserts invariants (finite positions, sane time scale, no node leak) while
  driving pause, restart, mode switches and fluid-quality changes.
  Godot exits 0 on a GDScript runtime error, so the wrapper also greps the log
  for `SCRIPT ERROR`; run tests through the wrapper, not the runner directly.
- Headless smoke: `godot --headless --path . --quit-after 300`
- AI vs AI lab: `tools/run_lab.ps1` or `tools/run_lab.sh`, then `python tools/lab_analyze.py`
- Visual check without a human: `godot --path . --resolution 1920x1080 --script res://tools/screenshot_run.gd -- --out=<dir>`
  boots the menu, starts an arcade match, flips to AI vs AI, pauses, and saves PNGs. Read them.
- Headless runs have no RenderingDevice, so the fluid falls back to CPU and
  logs a warning. That is expected.
- A fresh clone or worktree needs one import before anything resolves
  `class_name` types (`godot --headless --path . --import`); without it you get
  a wall of "Could not find type" parse errors. `tools/run_tests.sh` does this
  for you.
- `tools/redteam_*` are adversarial probes kept from a red-team pass: malformed
  settings, hostile tuning values, NaN injection, fluid-quality churn, results
  screen input. Use them when touching those areas.

## Architecture (what is actually true)

- One scene, `scenes/main.tscn`. `Main._ready` (src/systems/main.gd) creates
  `TimeController`, `ChaosDirector`, `BrickMatrix`, `TournamentManager` in code
  and hand-injects references into every system. Order matters; add new
  systems there.
- The menu (`MenuManager`, CanvasLayer) is an overlay on the live arena, not a
  separate scene. `GameManager.State.MENU` is the idle state.
- Enter modes only via `GameManager.start_*_match()`. Hotkeys G/T/Z/Y exist
  for dev use and bypass the menu.
- `TimeController` is the only writer of `Engine.time_scale` (priority
  stack: pause > hit-stop > hyper > lab). Never set `Engine.time_scale`
  directly. Pause is `get_tree().paused`; Menu, HUD, GameManager and
  AudioManager are `PROCESS_MODE_ALWAYS`.
- Fluid: `FluidSimulator` runs 5 compute passes on a 256x144 grid; the display
  shader (`shaders/cymatics_display.gdshader`) maps dye to a palette and
  leaves HDR headroom for the 2D glow (`WorldEnvironment` in arena.tscn,
  `rendering/viewport/hdr_2d=true`). Gameplay forces come from the analytic
  `_active_flow_nodes` list, not from the grid.
- Audio: `AudioManager` is a scene node; buses live in
  `assets/audio/default_bus_layout.tres` (Master > Music / SFX{Impact, Blast,
  World} / Drone / UI). It binds to game signals in `bind_match()`; add new
  event sounds there rather than in callers. Generated SFX come from
  `tools/gen_sfx.py` and the synth stems from `tools/gen_music.py`
  (deterministic, CC0). Both output to gitignored directories, so a fresh
  clone must run them or the game plays near-silent; CI generates them too.
- UI: one theme, `assets/ui/theme.tres`, set as the project theme. HUD
  popups go through `HUD.show_callout(text, color, priority)`; do not add
  ad-hoc labels. Frosted glass must sit on a ColorRect behind a panel.
- Settings persist via the `Settings` autoload (`user://settings.cfg`).
  Everything read from that file is untrusted: `Settings.coerce()` forces type
  and range per key and rejects NaN/infinity. Add new keys to `DEFAULTS` and,
  if bounded, to `RANGES`. Point `config_path` elsewhere in tests.
- Fluid compute: advect runs in its own compute list. Godot 4.7 rejects its
  push constant when it shares a list with other push-constant pipelines.
- `tools/screenshot_run.gd` plans: default (AI rally + pause), `--plan=human`
  (P1 serves; exercises the threat reticle and serve aim), `--plan=goal`
  (forced goals; exercises goal theatre), `--plan=vfx` (fires each VFX method).

## Input map

P1: WASD or mouse, LMB/J stream, RMB/K suck (hold = capture, release =
slingshot), Space blast (tap) / charge (hold) / parry (tap on arrival), Left
Shift resonance, gamepad 0. P2: arrows, `,` stream, `.` suck, `/` blast, Right Shift
resonance, gamepad 1. `pause` = Esc / P / Start. Dev: R rematch, T AI, G
gauntlet, Z zen, Y lab, M music.

## Conventions

- Tabs, `class_name` on public types, typed locals (`:=`), `push_warning`
  instead of `print`.
- Arena is a hard-coded 1920x1080 world; the window letterboxes (`aspect=keep`).
- Do not commit `.godot/`, `.mcp/`, `lab/runs/*`, `build/`.
- Design docs under `docs/design/` are partly aspirational; each carries a
  status banner. `docs/POLISH_PLAN.md` is the live plan. Update it.
- Do not commit unless asked. Work on a branch.
