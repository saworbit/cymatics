class_name PaddleTuning
extends Resource

## Every feel constant a paddle obeys, in one inspector-editable resource.
## `src/tuning/paddle_default.tres` holds the shipping values.
## Node layout (visual offsets, shader parameter names) stays in `paddle.gd`;
## this resource owns movement, timing windows, forces and reach.

# --- Movement ------------------------------------------------------------------

@export_group("Movement")
## Top keyboard/stick speed.
@export var move_speed := 920.0
## Acceleration toward the input direction.
@export var accel := 7800.0
## Deceleration when the stick is centred.
@export var friction := 6200.0
## Deceleration while the match is not live (menu / match over).
@export var friction_blocked := 6200.0
## Deceleration while stunned.
@export var friction_stunned := 3800.0
## Mouse follow gain: velocity = (target - position) * this.
@export var mouse_gain := 28.0
## Mouse motion over this many px hands P1 control back to the mouse.
@export var mouse_switch_px := 2.0
## Stick deadzone for movement and for device arbitration.
@export var stick_deadzone := 0.2
## Paddle velocity handed to the ball is capped at move_speed * this.
@export var hit_velocity_cap_factor := 1.5

# --- Court bounds --------------------------------------------------------------

@export_group("Court bounds")
## P1 x range. P2's is mirrored about the 1920 px arena.
@export var min_x := 50.0
@export var max_x := 540.0
## Arena width used to mirror the x range for P2.
@export var arena_width := 1920.0
## Fallback y range (the live clamp uses the half-height below).
@export var min_y := 80.0
@export var max_y := 1000.0
## Live y clamp: top wall + half-height + the pad below.
@export var wall_top_y := 40.0
@export var wall_bottom_y := 1040.0
@export var wall_pad := 4.0
## Gameplay half-height, plain and FORTRESS, before size_mod.
@export var half_height := 70.0
@export var half_height_fortress := 80.0
## Collision box before size_mod: plain, FORTRESS, WEDGE.
@export var body_size := Vector2(36.0, 140.0)
@export var body_size_fortress := Vector2(52.0, 160.0)
@export var body_size_wedge := Vector2(44.0, 140.0)

# --- Parry ---------------------------------------------------------------------

@export_group("Parry")
## Perfect-hit window (~5 frames at 60 Hz).
@export var parry_window := 0.083
## Cost of a whiffed parry.
@export var parry_cooldown := 0.35
## A ball this close counts as "incoming and close" for the parry gate.
@export var parry_range := 300.0
## Ball must be closing faster than this to arm the parry gate.
@export var parry_incoming_speed := 40.0
## Ball may already be this far past the paddle and still count.
@export var parry_behind_slack := -20.0

# --- Blast ---------------------------------------------------------------------

@export_group("Blast")
## Cooldown for a plain tap, and for a fully charged release.
@export var blast_cooldown := 0.42
@export var blast_cooldown_charged := 0.9
## Hold under this is a tap, not a charge.
@export var blast_tap_time := 0.12
## Hold time for a full charge.
@export var blast_charge_time := 0.7
## Extra hold before an overheld charge auto-fires.
@export var blast_overhold_extra := 0.6
## Power = this + the scale below * charge fraction.
@export var blast_power_base := 0.35
@export var blast_power_scale := 0.65
## Ball impulse multiplier from a tap to a full charge.
@export var blast_impulse_min := 1.0
@export var blast_impulse_max := 1.8
## Legacy strength scale handed to listeners, tap to full charge.
@export var blast_strength_min := 1.0
@export var blast_strength_max := 1.6
## Blast origin, in front of the paddle.
@export var blast_offset := 54.0
## Cone reach for a tap, plus this much more at full charge.
@export var blast_reach := 280.0
@export var blast_reach_charge := 160.0
## Cone half-height at the paddle (scaled by size_mod).
@export var blast_cone_half_height := 64.0
## Cone opening per px of forward distance.
@export var blast_cone_spread := 0.22
## Extra cone half-height at full charge.
@export var blast_cone_charge_bonus := 30.0
## Impulse handed to a ball in the cone (before the charge multiplier).
@export var blast_ball_impulse := 820.0
## Aim is bent by (ball.y - paddle.y) * this.
@export var blast_aim_y_scale := 0.003
## Spin added by (ball.y - paddle.y) * this.
@export var blast_spin_scale := -0.005
## Rally-cap override granted to the struck ball, charged and tap.
@export var blast_override_charged := 0.5
@export var blast_override_tap := 0.35
## Charge fraction over this counts as a charged blast for the override.
@export var blast_charged_threshold := 0.05
## Momentum earned on a connecting blast: this plus the charge term.
@export var blast_momentum_base := 0.06
@export var blast_momentum_charge := 0.06
## Fluid shockwave / vortex on release (before the charge multiplier).
@export var blast_fluid_shock := 3600.0
@export var blast_fluid_vortex := 4.2
@export var blast_fluid_vortex_radius := 120.0
@export var blast_fluid_vortex_radius_charge := 60.0
## Cavitation sink while charging: strength and radius, base plus charge term.
@export var charge_sink_force := 500.0
@export var charge_sink_force_gain := 900.0
@export var charge_sink_radius := 70.0
@export var charge_sink_radius_gain := 60.0
## VFX shockwave / burst / camera kick on release.
@export var blast_vfx_shock_radius := 440.0
@export var blast_vfx_burst := 1.6
@export var blast_camera_kick := 0.85

# --- Suction capture -----------------------------------------------------------

@export_group("Suction capture")
## Ball within this of the nozzle is captured into an orbit.
@export var capture_range := 220.0
## The orbit breaks free after this long.
@export var capture_max_hold := 2.0
## Time for the orbit to tighten from start to end radius.
@export var capture_tighten_time := 1.2
## Orbit radius at capture, and once fully tightened.
@export var capture_radius_start := 280.0
@export var capture_radius_end := 120.0
## Tangential orbit speed (px/s); angular rate is this over the radius.
@export var capture_orbit_speed := 320.0
## Cooldown after a break-free before this paddle may capture again.
@export var capture_recapture_block := 0.8
## Orbit centre, in front of the paddle.
@export var capture_center_offset := 110.0
## Rate the live orbit radius chases its target.
@export var capture_radius_lerp := 6.0
## Floor on the radius used for the angular rate.
@export var capture_orbit_min_radius := 40.0
## Cap on the velocity the captor writes onto the ball each tick.
@export var capture_velocity_cap := 2600.0
## Spin wound onto the ball per second of orbit.
@export var capture_spin_gain := 1.5
## Cross product over this reads the ball's approach as a clear orbit direction.
@export var capture_dir_cross_threshold := 20.0
## Orbit is kept inside these x bounds.
@export var capture_clamp_min_x := 60.0
@export var capture_clamp_max_x := 1860.0
## Orbit is kept inside these y bounds (before the ball radius is subtracted).
@export var capture_clamp_min_y := 58.0
@export var capture_clamp_max_y := 1022.0
## Ball is nudged to min_speed on a silent drop if it is slower than this.
@export var capture_drop_min_velocity := 200.0
## Break-free: speed the ball pops out at, and its rally-cap override.
@export var break_free_speed := 640.0
@export var break_free_override := 0.15
## Orbit vortex strength: this plus the tighten term, times the orbit direction.
@export var capture_vortex_base := 3.0
@export var capture_vortex_gain := 4.0
## Orbit vortex radius, as a fraction of the orbit radius.
@export var capture_vortex_radius_scale := 1.1
## Capture-moment vortex strength and radius.
@export var capture_begin_vortex := 7.0
@export var capture_begin_vortex_radius := 240.0

# --- Slingshot -----------------------------------------------------------------

@export_group("Slingshot")
## Release is clamped to within this many degrees of forward.
@export var slingshot_cone_deg := 50.0
## Launch speed at zero hold, plus this much at a full tighten.
@export var slingshot_speed := 1100.0
@export var slingshot_speed_hold_bonus := 500.0
## Spin at zero hold, plus this much at a full tighten.
@export var slingshot_spin_base := 0.35
@export var slingshot_spin_hold_bonus := 0.4
## Rally-cap override granted to the launched ball.
@export var slingshot_override := 0.4
## Momentum earned on a slingshot.
@export var slingshot_momentum := 0.12
## Tangent / aim-hint blend when a hint is supplied.
@export var slingshot_tangent_weight := 0.4
@export var slingshot_hint_weight := 0.6
## Human aim hint needs a move axis longer than this.
@export var slingshot_hint_deadzone := 0.2
## Human aim hint y scale.
@export var slingshot_hint_y_scale := 0.9
## Blasting out of a capture launches this much harder than a slingshot.
@export var blast_capture_launch_mult := 1.3
## Rally-cap override for a blast out of a capture.
@export var blast_capture_override := 0.5
## Aim bend for a blast out of a capture, and its spin.
@export var blast_capture_aim_scale := 0.002
@export var blast_capture_spin_scale := 0.004
## Fluid shockwave on release: base plus the hold term.
@export var slingshot_fluid_shock := 3200.0
@export var slingshot_fluid_shock_hold := 2200.0
## Counter-vortex left behind on release.
@export var slingshot_fluid_vortex := 5.0
@export var slingshot_fluid_vortex_radius := 160.0
## VFX shockwave radius: base plus the hold term.
@export var slingshot_vfx_shock := 380.0
@export var slingshot_vfx_shock_hold := 240.0
## VFX burst scale: base plus the hold fraction.
@export var slingshot_vfx_burst := 1.5
## Camera kick: base plus the hold term.
@export var slingshot_camera_kick := 0.9
@export var slingshot_camera_kick_hold := 0.8

# --- Serve ---------------------------------------------------------------------

@export_group("Serve")
## Serve aim is clamped to within this many degrees of forward.
@export var serve_cone_deg := 55.0
## Serve launch speed.
@export var serve_speed := 780.0
## Distance the held ball floats in front of the paddle.
@export var serve_offset := 78.0
## Rate the aim vector chases the requested direction.
@export var serve_aim_slerp := 14.0
## Aim moved this many degrees re-emits `serve_aimed`.
@export var serve_aim_emit_deg := 4.0
## Cooldown stamped on the paddle after a serve.
@export var serve_blast_cooldown := 0.25
## Mouse aim needs to be this far from the ball to count.
@export var serve_mouse_deadzone := 60.0
## Stick aim: forward is pulled in by this much of |y|, y is scaled by the next.
@export var serve_stick_forward_pull := 0.35
@export var serve_stick_y_scale := 0.85
## Stick aim needs a move axis longer than this.
@export var serve_stick_deadzone := 0.05
## AI serve: cone it aims inside, target x, open/closed y, and the y jitter.
@export var ai_serve_cone_deg := 40.0
@export var ai_serve_target_x := 1760.0
@export var ai_serve_open_y := 900.0
@export var ai_serve_closed_y := 180.0
@export var ai_serve_y_jitter := 120.0

# --- Momentum ------------------------------------------------------------------

@export_group("Momentum")
## Momentum per return: this plus hit speed over the divisor, capped.
@export var momentum_hit_gain := 0.11
@export var momentum_speed_divisor := 12000.0
@export var momentum_speed_cap := 0.08
## Extra momentum on a perfect hit.
@export var momentum_perfect_bonus := 0.18
## Momentum at or above this is a ready Resonance.
@export var resonance_ready_threshold := 0.99

# --- Resonance -----------------------------------------------------------------

@export_group("Resonance")
## Blast cooldown stamped after a Resonance.
@export var resonance_cooldown := 0.7
## Resonance origin, in front of the paddle.
@export var resonance_offset := 70.0
## Launch speed (clamped to the ball's hard max).
@export var resonance_launch_speed := 1900.0
## Rally-cap override granted to the launched ball.
@export var resonance_override := 0.7
## Freeze-frame length (real seconds) and the time scale during it.
@export var resonance_freeze_time := 0.4
@export var resonance_freeze_scale := 0.05
## Aim: forward weight, y bend per px, and the bend clamp.
@export var resonance_aim_forward := 1.6
@export var resonance_aim_y_scale := 0.004
@export var resonance_aim_y_clamp := 0.4
## Ball must not already be this far behind the paddle to be aimed at.
@export var resonance_behind_limit := -40.0
## Spin: this much per px of offset, plus a flat side-dependent bias.
@export var resonance_spin_scale := 0.004
@export var resonance_spin_bias := 0.45
## Fluid shockwave / vortex on release.
@export var resonance_fluid_shock := 5200.0
@export var resonance_fluid_vortex := 6.0
@export var resonance_fluid_vortex_radius := 200.0
## VFX shockwave radius / duration, burst scale, camera kick, flash.
@export var resonance_vfx_shock := 820.0
@export var resonance_vfx_shock_time := 0.7
@export var resonance_vfx_burst := 3.4
@export var resonance_camera_kick := 2.2
@export var resonance_flash_alpha := 0.35
@export var resonance_flash_time := 0.16

# --- Stream (shoot) ------------------------------------------------------------

@export_group("Stream")
## Fluid force injected by the jet.
@export var shoot_force := 2000.0
## Jet nozzle, in front of the paddle.
@export var nozzle_offset := 40.0
## Jet injection radius.
@export var stream_radius := 62.0
## Jet direction is bent by paddle velocity.y * this.
@export var stream_vy_bend := 0.0008
## Swirl shed at the end of the jet: strength, distance, radius.
@export var stream_vortex := 2.4
@export var stream_vortex_distance := 70.0
@export var stream_vortex_radius := 48.0
## A ball this close in front and inside the lane is pushed by the jet.
@export var stream_ball_range := 680.0
@export var stream_ball_lane := 130.0
## Push per second, and the spin it winds on.
@export var stream_ball_push := 620.0
@export var stream_ball_spin := 0.4
## Beam intensity.
@export var stream_beam_intensity := 1.25

# --- Suction (field) -----------------------------------------------------------

@export_group("Suction")
## Fluid sink strength.
@export var suck_force := 1600.0
## Sink radius.
@export var suck_radius := 120.0
## Swirl strength and radius around the nozzle.
@export var suck_vortex := 4.5
@export var suck_vortex_radius := 130.0
## Balls within this are pulled toward the nozzle.
@export var suck_pull_range := 720.0
## Peak pull force, and the floor on its distance falloff.
@export var suck_pull_force := 1250.0
@export var suck_pull_min_factor := 0.2
## Inside this the pull adds a tangential curl so the ball spirals in.
@export var suck_preorbit_range := 260.0
@export var suck_preorbit_force := 900.0
## MAGNET powerup multiplier on every suction / stream range and force.
@export var magnet_multiplier := 1.55

# --- Paddle wake ---------------------------------------------------------------

@export_group("Paddle wake")
## Paddle leaves a wake above this speed.
@export var wake_speed_threshold := 40.0
## Wake force and radius.
@export var wake_force := 900.0
@export var wake_radius := 40.0
## Flanking eddies: offset, strength, radius.
@export var wake_flank_offset := 28.0
@export var wake_flank_vortex := 2.2
@export var wake_flank_radius := 42.0

# --- Stun bolt -----------------------------------------------------------------

@export_group("Stun bolt")
## Cooldown between stun bolts.
@export var stun_cooldown := 0.55
## Stun applied to the paddle that is hit.
@export var stun_duration := 1.9
## Bolt origin, in front of the paddle.
@export var stun_bolt_offset := 70.0
## VFX burst offset / scale and camera kick on firing.
@export var stun_burst_offset := 40.0
@export var stun_burst_scale := 1.4
@export var stun_camera_kick := 0.55
## Blast SFX strength for the bolt.
@export var stun_audio_strength := 0.85

# --- Presentation --------------------------------------------------------------

@export_group("Presentation")
## Action glow chase rate.
@export var action_glow_rate := 8.0
## Vortex VFX fade in / out rates while sucking and while free.
@export var vortex_fade_in := 7.0
@export var vortex_fade_out := 4.0
## Vortex hold fade rates while capturing and while free.
@export var vortex_hold_in := 4.0
@export var vortex_hold_out := 6.0
## Vortex quad half-size, and the uv divisor for the orbit radius.
@export var vortex_half_size := 320.0
@export var vortex_uv_divisor := 640.0
## Squash stamped on the core when a hit lands.
@export var hit_squash := Vector2(1.35, 0.78)
## Core scale chase rate, and how far a full charge shrinks it.
@export var core_scale_rate := 12.0
@export var core_charge_shrink := 0.08
## Ready glow while momentum is not full.
@export var ready_glow_scale := 0.35
## Face: distance that counts as close, and the incoming speed that scares.
@export var face_close_distance := 400.0
@export var face_scare_speed := 1100.0
