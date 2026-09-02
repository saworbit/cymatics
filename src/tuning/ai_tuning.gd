class_name AITuning
extends Resource

## Every feel constant the AI opponent obeys, in one inspector-editable
## resource. `src/tuning/ai_default.tres` holds the shipping values.
## `difficulty`, `aggression` and `reaction_delay` seed the node's runtime
## fields; `TournamentManager` and `GameManager` still override them per stage.

# --- Reaction ------------------------------------------------------------------

@export_group("Reaction")
## Seconds between tactical re-evaluations at difficulty 1.
@export var reaction_delay := 0.07
## Starting difficulty (scales think rate, read error and English).
@export var difficulty := 1.0
## Starting aggression 0..1 (scales blasts, slingshots and approach speed).
@export var aggression := 0.55
## Think interval = reaction_delay / max(difficulty, this).
@export var think_difficulty_floor := 0.4

# --- Movement ------------------------------------------------------------------

@export_group("Movement")
## Dead bands around the target before the AI bothers to move.
@export var move_deadzone_y := 12.0
@export var move_deadzone_x := 22.0
## Approach speed = paddle.move_speed * (base + difficulty * gain), clamped.
@export var speed_factor_base := 0.72
@export var speed_factor_difficulty := 0.28
@export var speed_factor_min := 0.65
@export var speed_factor_max := 1.25
## Aggression multiplier on the approach speed, clamped.
@export var approach_mult_base := 0.88
@export var approach_mult_aggression := 0.24
@export var approach_mult_min := 0.85
@export var approach_mult_max := 1.15
## Acceleration toward the desired velocity.
@export var accel := 7000.0

# --- Aggression scaling --------------------------------------------------------

@export_group("Aggression scaling")
## Blast willingness multiplier: base + aggression, clamped.
@export var blast_mult_base := 0.5
@export var blast_mult_min := 0.5
@export var blast_mult_max := 1.5
## Chance a ready Resonance is spent rather than a plain blast.
@export var resonance_chance_base := 0.3
@export var resonance_chance_aggression := 0.5

# --- Capture / slingshot -------------------------------------------------------

@export_group("Capture and slingshot")
## Planned hold before releasing: lerped from this at aggression 0 ...
@export var capture_hold_relaxed := 1.0
## ... to this at aggression 1.
@export var capture_hold_aggressive := 0.4
## Random jitter applied to the planned hold.
@export var capture_hold_jitter_min := 0.85
@export var capture_hold_jitter_max := 1.15
## While orbiting the AI stands this far off its goal line, y clamped.
@export var capture_stand_inset := 330.0
@export var capture_stand_min_y := 200.0
@export var capture_stand_max_y := 880.0
## Open corner it slings at, and the goal line it aims for.
@export var corner_goal_x := 1860.0
@export var corner_high_y := 130.0
@export var corner_low_y := 950.0

# --- Charged blast -------------------------------------------------------------

@export_group("Charged blast")
## Planned hold before releasing a charge.
@export var charge_plan_min := 0.45
@export var charge_plan_max := 0.7
## Fire when the ball is in the cone within this range ...
@export var charge_fire_cone_dist := 260.0
## ... or the plan ran out and the ball is in the cone or inside this range.
@export var charge_fire_close_dist := 120.0
## Overheld: fire this long past a full charge no matter what.
@export var charge_overhold := 0.4
## Abandon the charge if the ball is outgoing and further than this.
@export var charge_abandon_dist := 400.0

# --- Read error ----------------------------------------------------------------

@export_group("Read error")
## Per-approach read error: this many px, plus the speed term below.
@export var read_error_base := 32.0
@export var read_error_speed_gain := 150.0
## Speed at which the read error starts growing, and the span it grows over.
@export var read_error_speed_ref := 600.0
@export var read_error_speed_span := 1300.0
## Difficulty tightening: (base - difficulty * gain), clamped.
@export var read_error_difficulty_base := 1.6
@export var read_error_difficulty_gain := 0.6
@export var read_error_difficulty_min := 0.6
@export var read_error_difficulty_max := 1.4
## The rolled error is scaled by a random factor in this range.
@export var read_error_jitter_min := 0.35
@export var read_error_jitter_max := 1.0
## Per-approach plans: chance of one charged blast and one tap blast.
@export var plan_charge_chance_base := 0.10
@export var plan_charge_chance_aggression := 0.25
@export var plan_charge_difficulty_min := 0.5
@export var plan_charge_difficulty_max := 1.3
@export var plan_tap_chance := 0.10

# --- Tracking error ------------------------------------------------------------

@export_group("Tracking error")
## Continuous aim error: this, plus a difficulty term and a ball-speed term.
@export var error_base := 22.0
@export var error_difficulty_ref := 1.15
@export var error_difficulty_gain := 48.0
@export var error_speed_gain := 0.018
## Catch-up: the AI misses more when this far ahead ...
@export var error_lead_threshold := 2
@export var error_lead_gain := 16.0
## ... and tightens up by this factor when equally far behind.
@export var error_trail_scale := 0.55
## Early in a rally the error is scaled by this.
@export var error_early_rally_hits := 2
@export var error_early_scale := 0.7
## Rate the smoothed aim noise chases a fresh sample.
@export var noise_lerp := 0.2

# --- Prediction ----------------------------------------------------------------

@export_group("Prediction")
## Ball closing faster than this counts as incoming.
@export var incoming_speed_threshold := 40.0
## |vx| under this is not worth predicting from.
@export var predict_min_vx := 30.0
## Intercept point offset behind a powerup the ball is about to carom off.
@export var carom_intercept_offset := 26.0
## Prediction horizon in seconds.
@export var predict_max_time := 1.8
## Predicted y is folded back inside these walls.
@export var fold_top_y := 80.0
@export var fold_bottom_y := 1000.0
## English: needs a rally at least this long.
@export var english_min_rally := 2
## Foe this far off the predicted line opens a side to aim at.
@export var english_foe_margin := 40.0
## English strength when the foe is out of position, and when centred.
@export var english_open := 0.55
@export var english_centred := 0.4
## Chance the English is actually applied: base + difficulty * gain, clamped.
@export var english_chance_base := 0.28
@export var english_chance_difficulty := 0.4
@export var english_chance_min := 0.2
@export var english_chance_max := 0.85
## Aim offset per unit of English.
@export var english_offset := 52.0

# --- Positioning ---------------------------------------------------------------

@export_group("Positioning")
## Inset from the goal line while defending an incoming ball.
@export var defend_inset := 36.0
## Aim clamp while defending.
@export var defend_min_y := 110.0
@export var defend_max_y := 970.0
## Inset from the court side while idle, and the y clamp there.
@export var idle_inset := 70.0
@export var idle_min_y := 180.0
@export var idle_max_y := 900.0
## Standing spot while the ball is dead, and while waiting for a serve.
@export var dead_ball_inset := 80.0
@export var serve_wait_inset := 90.0
## Serve bob amplitude and rate while holding the ball.
@export var serve_bob_amplitude := 80.0
@export var serve_bob_rate := 0.002
## Standing spot while receiving a serve.
@export var receive_inset := 50.0
## Powerup seek: how far outside the court an orb is still worth chasing.
@export var orb_seek_back_margin := 90.0
@export var orb_seek_front_margin := 50.0
@export var orb_seek_x_pad := 24.0
@export var orb_seek_min_y := 120.0
@export var orb_seek_max_y := 960.0

# --- Serve ---------------------------------------------------------------------

@export_group("Serve")
## Delay before the very first serve.
@export var serve_delay_initial := 0.8
## Delay rolled after each serve.
@export var serve_delay_min := 0.45
@export var serve_delay_max := 1.1
## Delay armed while waiting to receive.
@export var serve_wait_delay_min := 0.5
@export var serve_wait_delay_max := 1.0

# --- Tactics -------------------------------------------------------------------

@export_group("Tactics")
## Stun bolt: fire when the ball is this well lined up, with this chance.
@export var stun_vertical := 90.0
@export var stun_chance := 0.35
## Capture a slow near ball: range, speed ceiling, and the chance.
@export var capture_dist := 280.0
@export var capture_speed := 950.0
@export var capture_chance_base := 0.45
@export var capture_chance_aggression := 0.5
## Charged blast: distance band, minimum ball speed, foe off-lane distance.
@export var charge_min_dist := 380.0
@export var charge_max_dist := 900.0
@export var charge_min_ball_speed := 520.0
@export var charge_foe_off_lane := 240.0
## Tap blast: range, lane, and the rally length it needs.
@export var tap_dist := 240.0
@export var tap_vertical := 60.0
@export var tap_min_rally := 3
## Stream a slow ball out: range and speed ceiling.
@export var push_dist := 320.0
@export var push_speed := 700.0
## Suck a fast ball off its line: distance band, lane, minimum speed.
@export var pull_min_dist := 300.0
@export var pull_max_dist := 780.0
@export var pull_vertical := 40.0
@export var pull_min_speed := 620.0
## Opportunist stream on approach: range, lane, chance.
@export var approach_shoot_dist := 420.0
@export var approach_shoot_vertical := 140.0
@export var approach_shoot_chance := 0.42
## Idle stream at a ball crossing in front: lane and the closing speed it needs.
@export var idle_shoot_vertical := 150.0
@export var idle_shoot_speed := -80.0
## Idle capture of a ball dribbling away: range, speed ceiling, chance.
@export var idle_capture_dist := 260.0
@export var idle_capture_speed := 600.0
@export var idle_capture_chance_base := 0.3
@export var idle_capture_chance_aggression := 0.4
## Chance of an idle stream with nothing else to do.
@export var idle_shoot_chance := 0.08

# --- Recovery ------------------------------------------------------------------

@export_group("Recovery")
## Ball this far past the paddle (times size_mod) counts as behind.
@export var behind_margin := 24.0
## Body half-height used while recovering (times size_mod).
@export var recover_half_height := 80.0
## Inset from the goal line while recovering.
@export var recover_goal_inset := 20.0
## Extra clearance sought when dodging out of the ball's lane.
@export var recover_dodge_clearance := 56.0
## Aim clamp while recovering.
@export var recover_min_y := 110.0
@export var recover_max_y := 970.0
## Near the top / bottom wall the dodge direction is forced.
@export var recover_top_y := 180.0
@export var recover_bottom_y := 900.0
## Slack when deciding the paddle is back on the goal side of the ball.
@export var recover_goal_side_slack := 12.0
## Extra lane width that still allows a desperate backhand blast.
@export var recover_swing_slack := 40.0

# --- Twin paddle (Hydra) -------------------------------------------------------

@export_group("Twin paddle")
## Lane split: the twin covers the half the main paddle is not.
@export var twin_high_min_y := 110.0
@export var twin_high_max_y := 520.0
@export var twin_low_min_y := 560.0
@export var twin_low_max_y := 970.0
## Where the main paddle waits while the twin covers a lane.
@export var twin_partner_inset := 50.0
@export var twin_partner_low_y := 780.0
@export var twin_partner_high_y := 300.0
## Twin idle spot and its recovery spot.
@export var twin_idle_y := 300.0
@export var twin_recover_inset := 70.0
@export var twin_recover_spread := 220.0
@export var twin_recover_min_y := 160.0
@export var twin_recover_max_y := 920.0
