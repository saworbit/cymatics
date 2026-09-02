class_name BallTuning
extends Resource

## Every feel constant the ball obeys, in one inspector-editable resource.
## `src/tuning/ball_default.tres` holds the shipping values; drop a copy on a
## `Ball` node's `tuning` slot to try a different feel without touching code.
## Purely cosmetic values (palette colours, shader parameter names) stay in
## `ball.gd`; this resource owns anything that changes how the ball plays or
## how big/long/fast its readability cues are.

# --- Core flight ---------------------------------------------------------------

@export_group("Core flight")
## Collision + visual radius, and the unit for every wake/dye radius below.
@export var radius := 18.0
## Speed a reset (non-served) ball starts at.
@export var base_speed := 820.0
## Absolute ceiling. No cap, blast or super may exceed it.
@export var max_speed := 2100.0
## Speed floor at rally hit 0. Grows with the rally (see Speed floor).
@export var min_speed := 560.0
## Velocity kept after a wall bounce.
@export var bounce_damping := 0.95
## Sideways acceleration per unit of spin (Magnus lift).
@export var magnus_accel := 620.0

# --- Speed floor ---------------------------------------------------------------

@export_group("Speed floor")
## Added to `min_speed` per rally hit.
@export var floor_growth_per_hit := 16.0
## Ceiling on the per-rally floor growth.
@export var floor_growth_cap := 140.0
## Extra floor while in overdrive.
@export var floor_overdrive_bonus := 70.0
## Extra floor while in Cymatic Lock.
@export var floor_lock_bonus := 140.0

# --- Rally speed cap -----------------------------------------------------------

@export_group("Rally speed cap")
## Cap = base_speed + this + rally_hits * cap_per_hit.
@export var cap_base_bonus := 120.0
## Cap growth per rally hit.
@export var cap_per_hit := 85.0
## Extra cap in overdrive.
@export var cap_overdrive_bonus := 220.0
## Extra cap in Cymatic Lock.
@export var cap_lock_bonus := 380.0
## Extra cap while the ball is a fireball.
@export var cap_fireball_bonus := 280.0

# --- Rally milestones ----------------------------------------------------------

@export_group("Rally milestones")
## Rally hit that trips overdrive.
@export var overdrive_rally_hits := 7
## Rally hit that trips Cymatic Lock.
@export var lock_rally_hits := 11

# --- Paddle contact ------------------------------------------------------------

@export_group("Paddle contact")
## Ball is "behind" the paddle past this many px on the wrong side.
@export var behind_margin := 10.0
## A ball in front already leaving faster than this is ignored (no double hit).
@export var leaving_speed_ignore := 40.0
## Push-out distance when the ball was struck from behind.
@export var contact_push_behind := 36.0
## Minimum clearance kept in front of the paddle after a normal hit.
@export var contact_push_front := 28.0
## Contact offset is (ball.y - paddle.y) / this, clamped to +-1.
@export var hit_offset_divisor := 70.0
## Out-angle from contact offset on a plain paddle.
@export var out_angle_standard := 0.95
## SCOOP squeezes the contact offset by this before aiming.
@export var out_angle_scoop_offset_scale := 0.32
## SCOOP out-angle multiplier on the squeezed offset.
@export var out_angle_scoop := 0.7
## WEDGE always kicks out at least this far off-axis.
@export var out_angle_wedge_base := 0.82
## WEDGE adds this much per unit of contact offset.
@export var out_angle_wedge_offset := 0.35
## |offset| under this counts as a FORK centre hit (dead straight, big boost).
@export var fork_center_threshold := 0.28
## FORK out-angle for an off-centre hit.
@export var out_angle_fork := 0.95
## Paddle velocity folded into the out direction (px/s -> direction units).
@export var paddle_velocity_influence := 0.0009

# --- Hit speed -----------------------------------------------------------------

@export_group("Hit speed")
## Base multiplier applied to the incoming speed on every paddle hit.
@export var speed_boost_base := 1.045
## Extra multiplier per rally hit.
@export var speed_boost_per_hit := 0.012
## Ceiling on the per-rally multiplier growth.
@export var speed_boost_rally_cap := 0.22
## Extra multiplier in overdrive.
@export var speed_boost_overdrive := 0.03
## Extra multiplier in Cymatic Lock.
@export var speed_boost_lock := 0.05
## Extra multiplier off a SCOOP paddle.
@export var speed_boost_scoop := 0.08
## Extra multiplier off a FORTRESS paddle.
@export var speed_boost_fortress := 0.18
## Extra multiplier off a FORK centre hit.
@export var speed_boost_fork_center := 0.25
## Extra multiplier on a perfect (parried) hit.
@export var speed_boost_perfect := 0.22
## Flat px/s added to every paddle hit.
@export var bonus_flat := 48.0
## Extra flat px/s off a FORTRESS paddle.
@export var bonus_flat_fortress := 280.0
## Spin from contact offset on a perfect hit.
@export var spin_offset_perfect := 1.45
## Spin from paddle velocity on a perfect hit.
@export var spin_paddle_vel_perfect := 0.0045
## Spin from contact offset on a normal hit.
@export var spin_offset_normal := 1.12
## Spin from paddle velocity on a normal hit.
@export var spin_paddle_vel_normal := 0.003

# --- Fluid coupling ------------------------------------------------------------

@export_group("Fluid coupling")
## Sampled fluid velocity is clamped to this on the GPU sim.
@export var fluid_sample_cap_gpu := 2400.0
## Tighter clamp for the CPU fallback, whose grid hoards the ball's own wake.
@export var fluid_sample_cap_cpu := 120.0
## Sampled curl is clamped to +-this.
@export var curl_clamp := 6.0
## Sideways deflection gain from the fluid (per second).
@export var flow_lateral_gain := 3.4
## Aligned flow under this is ignored.
@export var flow_aligned_threshold := 40.0
## Aligned flow is clamped to this before the boost.
@export var flow_aligned_cap := 1600.0
## Aligned boost gain (per second).
@export var flow_aligned_gain := 0.28
## Head-on flow below this starts to drag.
@export var flow_drag_threshold := -80.0
## Head-on drag gain (per second).
@export var flow_drag_gain := 0.08
## Spin picked up from curl (per second).
@export var spin_curl_gain := 0.85
## Spin bleed back toward zero (per second).
@export var spin_decay := 0.12
## Magnus lift multiplier while the ball is a STAR.
@export var star_lift_mult := 1.75
## |curl| over this adds a flat sideways kick.
@export var curl_kick_threshold := 1.4
## Size of that kick (per second).
@export var curl_kick_accel := 280.0
## Spin bleed while held in a suction orbit (per second).
@export var capture_spin_decay := 0.05

# --- Fluid wake ----------------------------------------------------------------

@export_group("Fluid wake")
## Below this speed the ball only dyes the field; above it, it pushes.
@export var wake_speed_threshold := 400.0
## Wake force = speed * this.
@export var wake_force_scale := 0.9
## Wake radius = radius * (this + speed term).
@export var wake_radius_base := 2.2
## Speed at which the wake radius starts growing.
@export var wake_radius_speed_ref := 500.0
## Speed span over which the wake radius grows.
@export var wake_radius_speed_span := 900.0
## Extra wake radius multiplier at full speed.
@export var wake_radius_speed_gain := 1.8
## Speed at which flanking von Karman eddies start shedding.
@export var vortex_speed_threshold := 850.0
## Eddy strength at `vortex_speed_ref`.
@export var vortex_strength := 3.5
## Reference speed for eddy strength.
@export var vortex_speed_ref := 1000.0
## Eddy radius as a fraction of the wake radius.
@export var vortex_radius_scale := 0.8
## Eddies are shed this many radii off the flight line.
@export var vortex_flank_offset := 1.5
## Dye radius (in ball radii) for a slow ball.
@export var idle_dye_radius_scale := 2.0
## Dye radius (in ball radii) while held in a suction orbit.
@export var capture_dye_radius_scale := 1.6
## Orbiting ball pushes the field only above this speed.
@export var capture_force_speed_threshold := 200.0
## Orbiting wake force = speed * this.
@export var capture_force_scale := 0.5
## Orbiting wake radius, in ball radii.
@export var capture_force_radius_scale := 2.0

# --- Wall bounce ---------------------------------------------------------------

@export_group("Wall bounce")
## TRIANGLE facet deflection added to the surface normal.
@export var triangle_facet_deflect := 0.24
## TRIANGLE wall-hit vortex strength.
@export var triangle_wall_vortex := 4.0
## TRIANGLE wall-hit vortex radius.
@export var triangle_wall_vortex_radius := 120.0
## STAR flips and jitters its spin on a wall hit.
@export var star_wall_spin_flip := -1.2
## STAR spin jitter range on a wall hit.
@export var star_wall_spin_jitter := 0.3
## Speed at which wall juice starts ramping.
@export var wall_juice_speed_ref := 500.0
## Speed span over which wall juice reaches full.
@export var wall_juice_speed_span := 1400.0
## Fluid shockwave strength at zero juice.
@export var wall_shock_base := 700.0
## Extra fluid shockwave strength at full juice.
@export var wall_shock_gain := 1300.0
## Camera kick at zero juice.
@export var wall_camera_kick_base := 0.12
## Extra camera kick at full juice.
@export var wall_camera_kick_gain := 0.3
## Ball complains about wall hits harder than this.
@export var wall_ow_speed := 1000.0

# --- Court geometry ------------------------------------------------------------

@export_group("Court geometry")
## Top wall: ball centre is clamped here.
@export var court_top_y := 58.0
## Bottom wall: ball centre is clamped here.
@export var court_bottom_y := 1022.0
## Contact point reported for a top-wall hit (used by VFX and the fluid).
@export var wall_contact_top_y := 40.0
## Contact point reported for a bottom-wall hit.
@export var wall_contact_bottom_y := 1040.0
## Left goal line.
@export var goal_left_x := 22.0
## Right goal line.
@export var goal_right_x := 1898.0
## Scored ball is parked between these x bounds for the goal theatre.
@export var goal_rest_min_x := 36.0
@export var goal_rest_max_x := 1884.0
## An orbiting ball is kept inside these x bounds silently.
@export var capture_clamp_min_x := 40.0
@export var capture_clamp_max_x := 1880.0
## Distance the held ball floats in front of the serving paddle.
@export var serve_offset := 78.0
## Serve bob rate (rad/s) and amplitude (px).
@export var serve_bob_rate := 7.0
@export var serve_bob_amplitude := 7.0
## Bob amplitude when no serving paddle is set (centre-court fallback).
@export var serve_bob_amplitude_loose := 10.0

# --- Near miss -----------------------------------------------------------------

@export_group("Near miss")
## Crossing test margin past the paddle plane.
@export var near_miss_cross_margin := 8.0
## Near-miss half-height = this * paddle.size_mod + the flat term below.
@export var near_miss_height_scale := 70.0
@export var near_miss_height_flat := 45.0

# --- Powerup carom -------------------------------------------------------------

@export_group("Powerup carom")
## Bounciness of a ball/orb carom.
@export var carom_restitution := 0.78
## Closing speed under this is not a carom.
@export var carom_min_closing := 8.0
## Impulse is computed from at least this much closing speed.
@export var carom_min_impulse_closing := 80.0
## Tangential (cut) transfer onto the ball.
@export var carom_cut_transfer := 0.22
## Floor on the outgoing speed, as a fraction of `min_speed`.
@export var carom_speed_floor_scale := 0.82
## English from the cut angle.
@export var carom_english_cut := 1.55
## English carried over from the previous spin.
@export var carom_english_spin := 0.18
## Tangential share of the impulse handed to the orb.
@export var carom_orb_cut_share := 0.28
## Ball is nudged this far back along the normal after a carom.
@export var carom_separation := 12.0
## Look-ahead (seconds) for the AI's carom preview.
@export var carom_preview_time := 1.35
## Slack added to the radii in the carom preview test.
@export var carom_preview_slack := 10.0
## |cut| over this reads as a proper cut shot.
@export var carom_cut_callout := 0.32

# --- Presentation --------------------------------------------------------------

@export_group("Presentation")
## Squash relaxes back toward round at this rate.
@export var squash_relax_rate := 14.0
## Speed at which flight stretch starts.
@export var stretch_speed_ref := 500.0
## Speed span over which flight stretch reaches full.
@export var stretch_speed_span := 1400.0
## Stretch along / squeeze across the flight line at full speed.
@export var stretch_along := 0.55
@export var stretch_across := 0.28
## Rate the flight stretch is approached at.
@export var stretch_lerp_rate := 10.0
## Squash on a paddle hit.
@export var squash_paddle_hit := Vector2(0.55, 1.45)
## Squash on a carom.
@export var squash_carom := Vector2(0.7, 1.25)
## Trail sample lifetime when hot / cool / on a multiball clone.
@export var trail_life_hot := 0.30
@export var trail_life_cool := 0.22
@export var trail_life_clone := 0.16
## Heat over this counts as hot for the trail lifetime.
@export var trail_hot_threshold := 0.7
## Speed at which the trail heat starts ramping, and the span it ramps over.
@export var trail_heat_speed_ref := 500.0
@export var trail_heat_speed_span := 1100.0
## Trail heat floor for a slow ball.
@export var trail_heat_min := 0.25
## Heat used in overdrive (Lock is always 1.0).
@export var trail_heat_overdrive := 0.75
## Maximum trail samples.
@export var trail_max_points := 40
## Minimum squared distance between trail samples.
@export var trail_min_step_sq := 2.0
## Outer trail width: this + heat * the gain below.
@export var trail_width_base := 30.0
@export var trail_width_heat := 18.0
## Inner core width: this + heat * the gain below.
@export var trail_core_width_base := 8.0
@export var trail_core_width_heat := 8.0
## Sparks emit above this speed.
@export var spark_speed_threshold := 620.0
## Spark count, normal and on a clone.
@export var spark_amount := 28
@export var spark_amount_clone := 18
## Afterimages start above this speed.
@export var afterimage_speed_threshold := 700.0
## Seconds between afterimages, normal and while a fireball.
@export var afterimage_interval := 0.07
@export var afterimage_interval_fireball := 0.045
## Afterimage quad size, normal and while a fireball.
@export var afterimage_size := 56.0
@export var afterimage_size_fireball := 64.0
## Afterimage fade length in seconds.
@export var afterimage_fade := 0.2
## Afterimage intensity, normal and on a clone.
@export var afterimage_intensity := 1.4
@export var afterimage_intensity_clone := 1.1
## Lost-ball pulse period in Cymatic Lock and in overdrive.
@export var lock_pulse_period := 0.5
@export var overdrive_pulse_period := 1.0
## Lost-ball pulse alpha and radius in Cymatic Lock.
@export var lock_pulse_alpha := 0.38
@export var lock_pulse_radius := 300.0
## Lost-ball pulse alpha and radius in overdrive.
@export var overdrive_pulse_alpha := 0.22
@export var overdrive_pulse_radius := 240.0
## Shape spin rate from ball spin, and from forward speed.
@export var shape_spin_from_spin := 14.0
@export var shape_spin_from_vx := 0.003
## Face look-ahead distance, and the speed above which the ball looks ahead.
@export var face_look_ahead := 220.0
@export var face_look_speed := 40.0

# --- Hit feedback --------------------------------------------------------------

@export_group("Hit feedback")
## Fluid shockwave strength on a normal / perfect paddle hit.
@export var hit_wave_power := 1600.0
@export var hit_wave_power_perfect := 2200.0
## Extra shockwave strength off a FORTRESS paddle.
@export var hit_wave_power_fortress := 1400.0
## Spin-driven vortex strength and radius on a paddle hit.
@export var hit_vortex_strength := 6.5
@export var hit_vortex_radius := 96.0
## Camera kick on a perfect hit.
@export var hit_camera_kick_perfect := 0.9
## Camera kick on a normal hit: this plus the rally term below.
@export var hit_camera_kick_base := 0.45
@export var hit_camera_kick_per_hit := 0.04
@export var hit_camera_kick_rally_cap := 0.4
## Hit-stop duration / time scale on a perfect hit.
@export var hit_stop_perfect := 0.055
@export var hit_stop_scale_perfect := 0.07
## Hit-stop duration / time scale on a normal hit.
@export var hit_stop_normal := 0.028
@export var hit_stop_scale_normal := 0.12
## Paddle-hit VFX intensity ramp per rally hit.
@export var hit_vfx_rally_scale := 0.08
