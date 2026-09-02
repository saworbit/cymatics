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

## Phase 3: structure

- `MatchState` owner (scores, rally, server, live checks).
- Split Ball/Paddle into body + view; `PaddleIntent` input abstraction.
- Tuning resources (`BallTuning.tres`, `PaddleTuning.tres`).
- Fluid (partly landed 2026-09-02): compute lists merged from ~70 to 7 per
  frame (Godot 4.7 rejects the advect push constant when it shares a list
  with other push-constant pipelines, so advect runs alone), pressure and
  divergence are R32F, velocity-driven aberration and schlieren shading are
  in. Still open: bounded splat dispatch, mipmaps, grid presets.
