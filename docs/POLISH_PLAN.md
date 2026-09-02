# Polish plan (toward AAA)

Status doc for the polish push that started 2026-09-02. Audits of gameplay,
visuals, audio, and UX/project health fed this list. Keep it current: tick
items as they land, add findings as they appear.

## Ground truth (2026-09-02, before work started)

- Single scene (`scenes/main.tscn`); the menu is a CanvasLayer overlay on the
  live arena. No autoloads. Manual dependency injection in `Main._ready`.
- The dye field saturates into a white/pastel wall within one rally. Display
  "bloom" is a brightness boost with no spatial spread. No HDR 2D.
- Three screen-space shaders use an inverted aspect factor, stretching rings
  and the suck lens about 3x horizontally.
- Mouse and keyboard fight for P1; parry/blast/super share one button and
  can be spammed for free momentum and perfect hits; walls are silent and
  unlit; rally speed cap clamps blast and super within one tick; boss
  loadouts are wiped on the first serve by `clear_point`.
- `Engine.time_scale` has five writers (pause, hit-stop, hyper, lab, goal
  timers). Pause is `time_scale = 0`, so its own overlay tween never plays.
- Audio: Master bus only, sliders are no-ops, several double triggers, no
  panning, ~20 silent events. Music is one 70 s CC0 loop with an audible wrap.
- No Theme, no font asset, no settings persistence, mouse-only menus, no
  results screen, no export presets, CI cannot fail on script errors.
- Docs (`technical.md`, `netcode.md`, `api.md`, parts of `gdd.md`) describe
  an aspirational build (rollback, GDExtension DSP, 2v2) that does not exist.

## Phase 1: foundation (landed 2026-09-02, branch `polish/phase-1`)

Known follow-ups from this pass: `p1_super`/`p2_super` both bind physical Shift (location-dependent); AI-vs-AI rallies now run very long (suction stalemates), so the lab needs an AI aggression pass; a display font is still missing (needs a download approval); event-specific VFX (goal, parry, blast, brick) are still the generic burst + ring.

### Visual pipeline
- [x] Dye economy: cap per-splat dye, lower ambient fog and wake alpha, raise
      dissipation on dye only, re-curve display energy so mid-tones survive.
- [x] HDR 2D + WorldEnvironment glow; remove fake bloom line from display.
- [x] Fix aspect factor in shockwave/vortex/glass shaders; drop needless mipmap
      screen-texture hints; make `hit_burst` additive.
- [x] Grain hash that does not streak; radial aberration falloff; vignette
      that does not bury the goal lines.
- [x] Display shader texel size from a uniform, velocity-aware shading.
- [x] Frosted glass: real multi-tap blur, inner light edge, applied to a
      ColorRect behind panels (the PanelContainer trick renders nothing).

### Game feel and controls
- [x] `TimeController`: single owner of `Engine.time_scale` with a priority
      stack (pause > hit-stop > hyper > lab). Pause uses the scene tree.
- [x] Physics interpolation on; camera follow in `_process`.
- [x] Input arbitration: last-used device drives P1; mouse velocity capped for
      spin/angle; analog stick magnitude; sane P2 keys; P2 gamepad (device 1).
- [x] Parry separated from blast; no free momentum or stun bolt on whiff.
- [x] Blast and Resonance exempt from the rally cap for a short window.
- [x] Walls: reachable collision juice, damping 0.95.
- [x] Boss loadouts survive `clear_point` (rally mods vs stage mods).
- [x] One cancellable serve timer that respects pause and restart.
- [x] Trauma-based shake with noise, callout priority queue.

### Audio
- [x] Bus layout: Master > Music / SFX (Impact, Blast, World) / Drone / UI,
      limiter on Master, sidechain compressor on Music keyed from Impact.
- [x] Sliders drive bus volume; one music enable API; settings persist.
- [x] Per-stream retrigger interval, voice cap, +-4% pitch, round-robin.
- [x] Panning by x position.
- [x] Synthesised SFX set (`tools/gen_sfx.py`) for the silent events.
- [x] Music: fade in/out, low-pass on pause, rally intensity filter.

### UX and project health
- [x] Theme resource; consistent type scale; one callout system.
- [x] Results screen (rematch / menu / next stage) with keyboard and pad.
- [x] Settings persistence (`user://settings.cfg`), fullscreen/vsync.
- [x] Keyboard and gamepad menu navigation; Esc closes modals; quit confirm.
- [x] `stretch/aspect = keep`, sane default window size.
- [x] CLAUDE.md, README controls truth pass, docs status banners.
- [x] CI: per-script `--check-only`, warnings as errors; export presets.

### Ball readability (landed 2026-09-02)
- [x] Palette ownership: the field tops out at team hues and violet; white and
      gold belong to the ball, its trail and sparks.
- [x] Cavitation void: the display shader darkens and desaturates dye around
      the ball with a bright rim, scaled by speed and Lock.
- [x] Trail reads as a pointer: wide bright head, thin tail, beams stay
      team-coloured.
- [x] Goal-line threat reticle (`ThreatReticle`) for human paddles when the
      ball is inbound above 620 px/s.
- [x] Screen flash only on perfects, goals, stun and resonance.
- [x] Lost-ball pulse ring at Cymatic Lock (0.5 s) and overdrive (1.0 s); soft
      low-alpha rings from `Ball._update_lock_pulse`. Heartbeat sync is audio's call.

## Phase 2: signature moments (next)

- [x] Event-specific VFX vocabulary (landed 2026-09-02): goal theatre (2-frame
      freeze, 0.3x slow-mo via `time_ctrl` source `goal`, ball `shatter()` debris
      cone that splashes back off the goal wall, goal-line pulse shader, camera
      push + zoom-out through `VFXManager.request_goal_focus`), parry anamorphic
      star + flung star ring (`spark_star.gdshader`), directional blast cone
      (`blast_cone.gdshader`, bound to `Paddle.blast_fired`), brick chips + crack
      flash and spinning shard quads, additive afterimages (`afterimage.gdshader`),
      wall-bounce flattened burst + ripple line, screen-space ring cap of 6.
      Verify with `--plan=goal` / `--plan=vfx` in `tools/screenshot_run.gd`.
- [x] Suck capture and slingshot release (`Ball.captured_by`, 2 s cap, 0.8 s
      recapture block); blast charge (hold up to 0.7 s, power 0.35..1.0, cone
      hit test); Resonance freeze-frame via `time_ctrl` + trajectory preview;
      serve aim indicator (`ServeAim`), 3-beat READY pulse, 4 s auto-serve.
- [x] AI aggression pass: per-approach read error scaled by ball speed, one
      charged-blast / tap-blast plan per approach, slingshots at the open
      corner, no sucking of slow near balls. Headless lab: 6 points / 90 s,
      mean rally 8 (was 0 points; the CPU fluid fallback used to steer the
      ball, now clamped in `Ball._integrate_flight`).
- [x] Goal energy wall (`GoalWall` x2 in arena.tscn, `goal_wall.gdshader`:
      threat-driven membrane, crossing ripple, goal pulse + fracture).
- [x] Ambient arena life (`ArenaAmbience`: curl-drift motes, hex lattice
      walls with hit glow, breathing dashed centre line).
- [x] HUD motion: score odometer roll, set flash, momentum comet + READY
      shimmer, rally tick pop, per-priority callout entries, OVERDRIVE /
      CYMATIC LOCK chip, 3-dot serve READY, serve-clock warning.
- [x] Title: shimmer shader synced to fluid energy, card hover tilt, mascots
      glance and bark at hovered cards. Powerup text tag removed (glyph only).
- [x] Faces squint when the ball is fast and close.
- Music stems (intro + seamless loop, intensity layer, heartbeat at lock).
- Display font (needs an OFL font download; ask before fetching).

## Phase 4: hardening (landed 2026-09-03, branch `polish/phase-4-hardening`)

The project had no tests. It now has a headless suite (`tools/run_tests.sh`):
59 unit tests / 790 assertions plus an integration harness that boots the real
scene and checks invariants while hammering pause, restart, mode switches and
fluid-quality changes.

Two flaws in the harness itself were found and fixed while building it, both of
which would have let broken tests pass CI: a test file that fails to parse
loads as a script with no methods (now a failure), and a GDScript runtime error
aborts a test method indistinguishably from a clean return (a test that records
no assertions is now a failure). Tests also run on the first processed frame,
not in `_initialize`, because nodes added during `_initialize` never receive
`_ready`.

### Red team findings and their fixes

An adversarial pass in an isolated worktree attacked persisted state, tuning
resources, the state machine, input, lifetimes and numeric edges. Findings, all
fixed and verified with the attacker's own repro scripts (`tools/redteam_*`):

- **Fluid detail on the CPU fallback** left the scratch arrays sized for the old
  grid and threw ~60 out-of-bounds errors a second forever, freezing the field
  for anyone without a compute device. Now re-inits and emits `grid_changed`.
- **`ui_scale = nan`** blanked the entire HUD, and stuck across boots, because
  `clampf()` passes NaN through. Rejected at load and guarded in `UIScaleRoot`.
- **One badly-typed key** in settings.cfg aborted the load loop, silently
  reverting that key and every key after it on every boot. `Settings.coerce()`
  now type-checks per key, clamps to `RANGES`, and rejects NaN and infinity.
- **A NaN ball position was permanent**: `normalized()` returns zero for a NaN
  vector, so the ball went invisible and uncollidable and the point could never
  end. `Ball` now recovers, and scrubs the tuning that caused it.
- **Non-finite tuning values** propagated through `minf()`/`maxf()`, which
  return their NaN argument. Tuning is validated per property at load.
- **A windowed lab run never terminated**, rewriting `summary.json` ~60 times a
  second indefinitely. `_finish` is latched and stops recording.
- **Escape was a dead key on the results screen**; it now backs out to the menu.
- **Pausing during goal theatre** held the slow-motion release hostage; its
  timer is now `process_always`.

Verified unchanged after the fixes: 1311 normalize warnings became 1, NaN ball
events 0, lab summary writes 9,766 became 1, HUD geometry finite again.

Not fixed, and honestly reported: injecting NaN into a *live* tuning resource
after load still leaves the process not fully exiting at teardown (Godot logs
"A Thread object is being destroyed without its completion having been
realized"). The game itself completes its run correctly; this is a shutdown
artifact under a synthetic mutation, not a player-reachable path.

Red team also confirmed what held up under load: the state machine survived
three 180-200 s soak runs drawing from 23 hostile actions with zero soft-locks,
mode hammering, capture/slingshot lifetime, 12 of 13 numeric edge cases, no
object or RID leaks over 240 s runs, no VRAM growth over 240 fluid rebuilds,
and both previously-audited exploits (blast whiff, parry spam) stayed closed.

## Phase 3: structure

- `MatchState` owner (scores, rally, server, live checks). Deferred: it is a
  pure refactor of working code, so the regression risk outweighs the benefit
  until something else forces it.
- Split Ball/Paddle into body + view; `PaddleIntent` input abstraction.
  Deferred for the same reason; maintainability only, no player-visible gain.

### Audio generation (fixed 2026-09-02)

`patch_import` only edited an existing `.import`, so the first import on a
fresh clone or in CI applied Godot's default QOA compression. That made the
three music stems different lengths, failed the sample-identical check and
silently disabled the synth soundtrack. The generators now write a complete
`.import` when none exists, pinning PCM and forward looping.
- [x] Tuning resources: `BallTuning` (174 exports), `PaddleTuning` (201) and
  `AITuning` (148) under `src/tuning/`, with default `.tres` instances that
  reproduce the previous behaviour exactly. Feel is now data, editable in the
  inspector without touching code.
- Fluid (landed 2026-09-02): compute lists merged from ~70 to 7 per frame
  (Godot 4.7 rejects the advect push constant when it shares a list with
  other push-constant pipelines, so advect runs alone), pressure and
  divergence are R32F, velocity-driven aberration and schlieren shading are
  in, splats run in place with a dispatch bounded to their radius, and
  quality presets (Low 128x72 / Medium 256x144 / High 384x216 / Ultra
  512x288) rebuild the grid live from the `fluid_quality` setting.
  Still open: dye mipmaps.

### Performance (measured 2026-09-02)

`tools/perf_run.gd` reports wall-clock frame-time percentiles per phase with
vsync and the FPS cap forced off. Re-run it after any rendering change.

On an RTX 3070 Ti at 1920x1080: menu 1.6 ms mean / 2.0 ms p95, rally 1.25 ms
mean / 1.8 ms p95, about 60 draw calls. Ultra costs the same as Medium, so
the fluid is not the bottleneck and the presets exist to scale *down* for
weak hardware. There is roughly 14 ms of headroom at 60 fps. Untested on
integrated graphics and handhelds; that is the real risk, not the desktop.

Two resolution bugs found and fixed while adding the presets:

- The display Sprite2D had a hard-coded 7.5x scale sized for a 256-wide
  texture, so any other grid covered the wrong screen area. `Main` now
  derives the scale from `grid_size`.
- Newly created RD textures are not zeroed. Uninitialised velocity made
  advection backtrace from garbage and wiped the dye, which looked like an
  empty field whenever the grid grew. All sim textures are now cleared on
  creation.

## Phase 3: accessibility and haptics (landed 2026-09-03)

New `Settings` keys and defaults: `colorblind_mode` 0 (Off / Deuteranopia /
Protanopia / Tritanopia), `ui_scale` 1.0 (0.8 / 1.0 / 1.25 / 1.5),
`screen_shake` 1.0, `haptics` true, `haptics_strength` 0.8.

- [x] Gamepad haptics (`src/systems/haptics.gd`, a GDD pillar that was never
      implemented). Owned and instantiated by `VFXManager`; `GameManager`
      binds it to the live match in `setup_references`, so no actor file
      changed. Device 0 = player 0, device 1 = player 1; AI paddles never
      rumble and nothing fires while paused or in the menu. Events: paddle hit,
      perfect parry (double crack), blast charge (rising hold), blast release
      (scaled by power), suck capture (held hum), slingshot, wall bounce, goal
      (strong for the conceder, three-beat cheer for the scorer), stun,
      resonance, Cymatic Lock heartbeat, match win. Run with `--haptics-debug`
      in the user args to log every call.
- [x] Colourblind palettes. `Settings.team_color(player_id)` is the single
      source of truth, with `remap_team_color()` for hard-coded call sites.
      Applied to the HUD scores / labels / momentum fills / comet shaders,
      callout colours, goal theatre and clone-goal colours, paddle
      `team_color`, the mode-card accents and mascot plates, and new
      `TeamP1` / `TeamP2` theme tokens.
- [x] UI scale. `UIScaleRoot` (`src/systems/ui_scale_root.gd`) reparents a UI
      CanvasLayer's children under a Control sized to `viewport / scale`, so
      anchors resolve in a smaller virtual canvas and the layer fills the
      screen at any scale. Installed by `HUD._ready` and `MenuManager._ready`.
      The settings modal is anchor-proportional with a `ScrollContainer` so it
      still fits at 150 %.
- [x] Motion and photosensitivity. `VFXManager.shake_scale` (new
      `screen_shake` slider) multiplies shake, kick and zoom punch, and
      `reduce_motion` halves it again; hit-stop is halved and pulled toward
      normal speed; the goal camera push is halved (the slow-motion beat
      stays, so goals still read); `flash_screen` softens to a longer, dimmer
      wash instead of dropping out, and a rolling cap of 3 full-screen flashes
      per second stops a brick volley from strobing.
- [x] Settings modal gained an ACCESSIBILITY section (colourblind mode, UI
      scale, screen shake, reduce motion, screen flash, gamepad rumble, rumble
      strength), keyboard and pad navigable like the rest.

Not rerouted through `Settings.team_color` (other owners): `Ball` wake and
trail colours, the fluid display and goal-wall shaders' palettes,
`ArenaAmbience`, and `TournamentManager.STAGES` boss colours.
