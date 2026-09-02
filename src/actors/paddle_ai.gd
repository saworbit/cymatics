class_name PaddleAI
extends Node

## Rally-first opponent that still ends rallies: captures slow balls and
## slingshots them at the open corner, charges a blast when the opponent is out
## of position, and stops sucking a ball that is already slow and near.
## Misses more when ahead, tightens up when behind.
## `aggression` (0..1) scales blast/resonance/slingshot usage and approach speed.

const DEFAULT_TUNING := "res://src/tuning/ai_default.tres"

@export var enabled := true
## Every feel constant lives here. Swap the resource to retune without code.
@export var tuning: AITuning

# Seeded from the tuning in _ready(); GameManager and TournamentManager
# override these per match / per stage.
var reaction_delay := 0.0
var difficulty := 0.0
var aggression := 0.0

var paddle: Paddle
var twin_paddle: Paddle
var ball: Ball
var game_mgr: GameManager
var chaos

var _timer := 0.0
var _target_pos := Vector2(1720, 540)
var _twin_target_pos := Vector2(1720, 320)
var _serve_delay := 0.0
var _intent_blast := false
var _intent_shoot := false
var _intent_suck := false
var _intent_charge := false
var _noise := 0.0
## Slingshot plan: how long to hold the current capture before releasing.
var _capture_plan_hold := 0.6
var _was_capturing := false
## Charged blast plan: seconds to hold before releasing regardless of range.
var _charge_plan := 0.5

func _ready() -> void:
	_ensure_tuning()

## Loads the default tuning when no resource was assigned, then seeds the
## runtime knobs GameManager / TournamentManager later override.
func _ensure_tuning() -> void:
	if tuning == null:
		tuning = load(DEFAULT_TUNING) as AITuning
	reaction_delay = tuning.reaction_delay
	difficulty = tuning.difficulty
	aggression = tuning.aggression
	_serve_delay = tuning.serve_delay_initial
## Read error for the current approach: rolled once when the ball turns toward us,
## grows with ball speed so fast shots (slingshots, charged blasts) can be misread.
var _approach_bias := 0.0
var _was_incoming := false
## Per-approach plans (rolled with the read error): one charged blast attempt, one tap blast.
var _plan_charge := false
var _plan_tap := false

func setup(p_paddle: Paddle, p_ball: Ball) -> void:
	paddle = p_paddle
	ball = p_ball
	paddle.is_ai = true

func _physics_process(delta: float) -> void:
	if not enabled or paddle == null or ball == null:
		return
	if game_mgr != null and (game_mgr.current_state == GameManager.State.MENU or game_mgr.current_state == GameManager.State.MATCH_OVER):
		return
	if paddle.stun_time > 0.0:
		_was_capturing = false
		return

	var t := tuning
	_timer += delta
	var think_interval := reaction_delay / maxf(difficulty, t.think_difficulty_floor)
	if _timer >= think_interval:
		var elapsed := _timer
		_timer = 0.0
		_evaluate_tactics(elapsed)

	var to_target := _target_pos - paddle.global_position
	var desired := Vector2.ZERO
	if absf(to_target.y) > t.move_deadzone_y:
		desired.y = signf(to_target.y)
	if absf(to_target.x) > t.move_deadzone_x:
		desired.x = signf(to_target.x)

	var spd := paddle.speed * clampf(t.speed_factor_base + difficulty * t.speed_factor_difficulty, t.speed_factor_min, t.speed_factor_max) * _approach_mult()
	paddle.velocity = paddle.velocity.move_toward(desired * spd, t.accel * delta)
	paddle.move_and_slide()
	paddle.global_position.x = clampf(paddle.global_position.x, paddle.min_x, paddle.max_x)
	paddle.global_position.y = clampf(paddle.global_position.y, paddle.min_y, paddle.max_y)

	_drive_capture()
	_drive_charge()

	paddle.is_shooting = _intent_shoot
	paddle.is_sucking = _intent_suck

	# Twin Paddle coordination for Hydra Stage
	if twin_paddle != null and is_instance_valid(twin_paddle) and twin_paddle.stun_time <= 0.0:
		var twin_to := _twin_target_pos - twin_paddle.global_position
		var twin_des := Vector2.ZERO
		if absf(twin_to.y) > t.move_deadzone_y:
			twin_des.y = signf(twin_to.y)
		if absf(twin_to.x) > t.move_deadzone_x:
			twin_des.x = signf(twin_to.x)
		twin_paddle.velocity = twin_paddle.velocity.move_toward(twin_des * spd, t.accel * delta)
		twin_paddle.move_and_slide()
		twin_paddle.global_position.x = clampf(twin_paddle.global_position.x, paddle.min_x, paddle.max_x)
		twin_paddle.global_position.y = clampf(twin_paddle.global_position.y, paddle.min_y, paddle.max_y)
		twin_paddle.is_shooting = _intent_shoot
		twin_paddle.is_sucking = _intent_suck and not paddle.is_capturing()

	if _intent_blast and paddle.blast_cooldown <= 0.0 and not paddle.is_charging():
		_intent_blast = false
		if ball.is_serving and ball.serve_paddle == paddle:
			paddle.try_serve()
		elif paddle.armed_time > 0.0 and paddle.stun_cooldown <= 0.0:
			paddle.fire_stun_bolt()
		elif paddle.is_resonance_ready() and randf() < t.resonance_chance_base + aggression * t.resonance_chance_aggression:
			paddle.trigger_resonance()
		else:
			paddle.trigger_blast(0.0)

## Holds a capture for the planned time, then slingshots at the open corner.
func _drive_capture() -> void:
	var capturing := paddle.is_capturing()
	if capturing and not _was_capturing:
		_capture_plan_hold = lerpf(tuning.capture_hold_relaxed, tuning.capture_hold_aggressive, clampf(aggression, 0.0, 1.0)) * randf_range(tuning.capture_hold_jitter_min, tuning.capture_hold_jitter_max)
	_was_capturing = capturing
	if not capturing:
		return
	_intent_suck = true
	_intent_shoot = false
	if paddle.capture_hold_time() >= _capture_plan_hold:
		var hint := _open_corner_dir(paddle.captured_ball())
		_intent_suck = false
		paddle.release_capture(hint)

## Starts / releases a charged blast: fires when the ball reaches the paddle or the plan runs out.
func _drive_charge() -> void:
	var t := tuning
	if paddle.is_charging():
		var charge_time := paddle.tuning.blast_charge_time
		var dist := paddle.global_position.distance_to(ball.global_position)
		var incoming := _is_incoming(ball.velocity)
		var frac := paddle.charge_fraction()
		var held := frac * charge_time
		var in_cone := paddle.blast_in_cone(ball, frac)
		var fire := (in_cone and dist < t.charge_fire_cone_dist) or (held >= _charge_plan and (in_cone or dist < t.charge_fire_close_dist))
		fire = fire or held >= charge_time + t.charge_overhold or (not incoming and dist > t.charge_abandon_dist)
		if fire:
			paddle.release_blast_charge()
		_intent_charge = false
		return
	if _intent_charge:
		_intent_charge = false
		if paddle.begin_blast_charge():
			_charge_plan = randf_range(t.charge_plan_min, t.charge_plan_max)

func _open_corner_dir(from_ball: Ball) -> Vector2:
	var origin := from_ball.global_position if from_ball != null and is_instance_valid(from_ball) else paddle.global_position
	var foe_y := 540.0
	var foe := _foe()
	if foe != null:
		foe_y = foe.global_position.y
	var goal_x := tuning.corner_goal_x if paddle.player_id == 0 else paddle.tuning.arena_width - tuning.corner_goal_x
	var corner_y := tuning.corner_high_y if foe_y > 540.0 else tuning.corner_low_y
	var to := Vector2(goal_x, corner_y) - origin
	return to.normalized() if to.length_squared() > 1.0 else Vector2.RIGHT * -_side_sign()

func _foe() -> Paddle:
	if chaos != null:
		var f: Paddle = chaos.paddle_right if paddle.player_id == 0 else chaos.paddle_left
		if f != null and is_instance_valid(f):
			return f
	if ball != null:
		var f2: Paddle = ball.paddle_right if paddle.player_id == 0 else ball.paddle_left
		if f2 != null and is_instance_valid(f2):
			return f2
	return null

func _approach_mult() -> float:
	return clampf(tuning.approach_mult_base + aggression * tuning.approach_mult_aggression, tuning.approach_mult_min, tuning.approach_mult_max)

func _blast_mult() -> float:
	return clampf(tuning.blast_mult_base + aggression, tuning.blast_mult_min, tuning.blast_mult_max)

func _evaluate_tactics(elapsed: float = -1.0) -> void:
	_intent_blast = false
	_intent_shoot = false
	_intent_suck = false
	_intent_charge = false
	var t := tuning
	if elapsed < 0.0:
		elapsed = reaction_delay / maxf(difficulty, t.think_difficulty_floor)

	if ball.is_serving:
		if ball.serve_paddle == paddle:
			_serve_delay -= elapsed
			_target_pos = Vector2(_court_x(t.serve_wait_inset), 540.0 + sin(Time.get_ticks_msec() * t.serve_bob_rate) * t.serve_bob_amplitude)
			if _serve_delay <= 0.0:
				_intent_blast = true
				_serve_delay = randf_range(t.serve_delay_min, t.serve_delay_max)
		else:
			_target_pos = Vector2(_goal_x(t.receive_inset), 540.0)
		return
	_serve_delay = randf_range(t.serve_wait_delay_min, t.serve_wait_delay_max)

	if ball.is_scored:
		_target_pos = Vector2(_court_x(t.dead_ball_inset), 540.0)
		return

	if paddle.is_capturing():
		# Orbit in progress: step forward so the orbit has room, let _drive_capture time the release.
		_intent_suck = true
		_target_pos = Vector2(_goal_x(t.capture_stand_inset), clampf(paddle.global_position.y, t.capture_stand_min_y, t.capture_stand_max_y))
		return

	var track: Ball = chaos.threat_ball_for(paddle) if chaos != null else ball
	if track == null:
		track = ball
	var ball_pos := track.global_position
	var ball_vel: Vector2 = track.velocity
	var ball_speed := ball_vel.length()
	var dist := paddle.global_position.distance_to(ball_pos)
	var vertical := absf(ball_pos.y - paddle.global_position.y)
	var error := _error_budget()
	var can_capture := paddle.capture_block_time() <= 0.0 and track.captured_by == null and track.speed_override_time <= 0.0

	if _is_behind(paddle, ball_pos):
		_recover_from_behind(paddle, track, error)
		_noise = lerpf(_noise, randf_range(-error, error), t.noise_lerp)
		return

	var incoming_now := _is_incoming(ball_vel)
	if incoming_now and not _was_incoming:
		_roll_approach_bias(ball_speed)
	_was_incoming = incoming_now

	if incoming_now:
		var at_x := _goal_x(t.defend_inset)
		var pred_vel := ball_vel
		var pred_spin := track.spin
		var pred_pos := ball_pos
		var cutting := false
		var orb = chaos.live_powerup if chaos != null else null
		if orb != null and is_instance_valid(orb) and _orb_between(orb.global_position.x, ball_pos.x):
			var preview: Dictionary = track.preview_powerup_carom(orb)
			if preview.get("hit", false):
				pred_vel = preview["velocity"]
				pred_spin = preview["spin"]
				pred_pos = orb.global_position - Vector2(track.radius + t.carom_intercept_offset, 0.0)
				_intent_suck = true
				cutting = true
		var predicted_y := _predict_y(pred_pos, pred_vel, pred_spin, at_x)
		predicted_y += _noise + randf_range(-error, error) + _approach_bias
		predicted_y = _fold_walls(predicted_y)
		var english := _choose_english(track, predicted_y)
		_target_pos = Vector2(at_x, clampf(predicted_y - english * t.english_offset, t.defend_min_y, t.defend_max_y))
		if twin_paddle != null and is_instance_valid(twin_paddle):
			if predicted_y < 540.0:
				_twin_target_pos = Vector2(_goal_x(t.defend_inset), clampf(predicted_y, t.twin_high_min_y, t.twin_high_max_y))
				_target_pos = Vector2(_court_x(t.twin_partner_inset), t.twin_partner_low_y)
			else:
				_target_pos = Vector2(_goal_x(t.defend_inset), clampf(predicted_y, t.twin_low_min_y, t.twin_low_max_y))
				_twin_target_pos = Vector2(_court_x(t.twin_partner_inset), t.twin_partner_high_y)

		var foe := _foe()
		var foe_off_lane := 0.0
		if foe != null:
			foe_off_lane = absf(foe.global_position.y - ball_pos.y)

		# End rallies: capture slow balls for a slingshot, charge when the foe is out of
		# position, tap-blast a ball at the paddle, and never suck a ball that is already slow and near.
		if paddle.armed_time > 0.0 and vertical < t.stun_vertical and randf() < t.stun_chance * _blast_mult():
			_intent_blast = true
		elif dist < t.capture_dist and ball_speed < t.capture_speed and can_capture and randf() < t.capture_chance_base + t.capture_chance_aggression * aggression:
			# Slow and near: hold suck so the nozzle captures it, then slingshot.
			_intent_suck = true
		elif _plan_charge and dist > t.charge_min_dist and dist < t.charge_max_dist and ball_speed > t.charge_min_ball_speed and foe_off_lane > t.charge_foe_off_lane:
			_plan_charge = false
			_intent_charge = true
		elif _plan_tap and dist < t.tap_dist and vertical < t.tap_vertical and track.rally_hits >= t.tap_min_rally and paddle.blast_in_cone(track, 0.0):
			_plan_tap = false
			_intent_blast = true
		elif dist < t.push_dist and ball_speed < t.push_speed:
			# Slow ball at the paddle and no capture available: push it out, do not suck.
			_intent_shoot = true
		elif dist > t.pull_min_dist and dist < t.pull_max_dist and vertical > t.pull_vertical and ball_speed > t.pull_min_speed:
			_intent_suck = true
		elif (not cutting) and dist < t.approach_shoot_dist and vertical < t.approach_shoot_vertical:
			_intent_shoot = randf() < t.approach_shoot_chance
	else:
		var orb_pos := _orb_seek_pos()
		if orb_pos != Vector2.ZERO:
			_target_pos = orb_pos
			_intent_suck = true
		else:
			_target_pos = Vector2(_court_x(t.idle_inset), clampf(ball_pos.y + randf_range(-error, error), t.idle_min_y, t.idle_max_y))
		if twin_paddle != null and is_instance_valid(twin_paddle):
			_twin_target_pos = Vector2(_court_x(t.idle_inset), t.twin_idle_y)
		var on_court_side := (paddle.player_id == 1 and ball_pos.x < paddle.global_position.x) \
			or (paddle.player_id == 0 and ball_pos.x > paddle.global_position.x)
		if on_court_side and vertical < t.idle_shoot_vertical and ball_vel.x * _side_sign() < t.idle_shoot_speed:
			_intent_shoot = true
		elif on_court_side and dist < t.idle_capture_dist and ball_speed < t.idle_capture_speed and can_capture and randf() < t.idle_capture_chance_base + t.idle_capture_chance_aggression * aggression:
			# A ball dribbling away in front of us is a free slingshot.
			_intent_suck = true
		else:
			_intent_shoot = randf() < t.idle_shoot_chance

	_noise = lerpf(_noise, randf_range(-error, error), t.noise_lerp)

## One read error per approach. Fast balls are misread more; difficulty tightens it.
func _roll_approach_bias(ball_speed: float) -> void:
	var t := tuning
	var fast := clampf((ball_speed - t.read_error_speed_ref) / t.read_error_speed_span, 0.0, 1.0)
	var mag := (t.read_error_base + fast * t.read_error_speed_gain) * clampf(t.read_error_difficulty_base - difficulty * t.read_error_difficulty_gain, t.read_error_difficulty_min, t.read_error_difficulty_max)
	var sign := 1.0 if randf() < 0.5 else -1.0
	_approach_bias = sign * mag * randf_range(t.read_error_jitter_min, t.read_error_jitter_max)
	_plan_charge = randf() < (t.plan_charge_chance_base + t.plan_charge_chance_aggression * aggression) * clampf(difficulty, t.plan_charge_difficulty_min, t.plan_charge_difficulty_max)
	_plan_tap = randf() < t.plan_tap_chance * _blast_mult()

func _side_sign() -> float:
	return 1.0 if paddle.player_id == 1 else -1.0

func _is_incoming(vel: Vector2) -> bool:
	return vel.x * _side_sign() > tuning.incoming_speed_threshold

func _goal_x(inset: float) -> float:
	if paddle.player_id == 1:
		return paddle.max_x - inset
	return paddle.min_x + inset

func _court_x(inset: float) -> float:
	if paddle.player_id == 1:
		return paddle.min_x + inset
	return paddle.max_x - inset

func _orb_between(orb_x: float, ball_x: float) -> bool:
	if paddle.player_id == 1:
		return orb_x > ball_x and orb_x < paddle.global_position.x + tuning.orb_seek_x_pad
	return orb_x < ball_x and orb_x > paddle.global_position.x - tuning.orb_seek_x_pad

func _predict_y(pos: Vector2, vel: Vector2, p_spin: float, at_x: float) -> float:
	var tune := tuning
	var vx := vel.x
	if absf(vx) < tune.predict_min_vx:
		return pos.y
	var t := clampf((at_x - pos.x) / vx, 0.0, tune.predict_max_time)
	var spd := vel.length()
	var mag_y := 0.0
	if spd > 1.0:
		mag_y = (vel.x / spd) * p_spin * ball.tuning.magnus_accel
	return pos.y + vel.y * t + 0.5 * mag_y * t * t

func _choose_english(track: Ball, predicted_y: float) -> float:
	var t := tuning
	if track.rally_hits < t.english_min_rally:
		return 0.0
	var foe_y := 540.0
	var foe := _foe()
	if foe != null:
		foe_y = foe.global_position.y
	var want := 0.0
	if foe_y < predicted_y - t.english_foe_margin:
		want = t.english_open
	elif foe_y > predicted_y + t.english_foe_margin:
		want = -t.english_open
	else:
		want = t.english_centred if predicted_y < 540.0 else -t.english_centred
	if randf() > clampf(t.english_chance_base + difficulty * t.english_chance_difficulty, t.english_chance_min, t.english_chance_max):
		return 0.0
	return want

func _orb_seek_pos() -> Vector2:
	if chaos == null or chaos.live_powerup == null or not is_instance_valid(chaos.live_powerup):
		return Vector2.ZERO
	var t := tuning
	var pos: Vector2 = chaos.live_powerup.global_position
	if pos.x < paddle.min_x - t.orb_seek_back_margin or pos.x > paddle.max_x + t.orb_seek_front_margin:
		return Vector2.ZERO
	return Vector2(
		clampf(pos.x, paddle.min_x + t.orb_seek_x_pad, paddle.max_x - t.orb_seek_x_pad),
		clampf(pos.y, t.orb_seek_min_y, t.orb_seek_max_y)
	)

func _is_behind(p: Paddle, ball_pos: Vector2) -> bool:
	var margin := tuning.behind_margin * p.size_mod
	if p.player_id == 1:
		return ball_pos.x > p.global_position.x + margin
	return ball_pos.x < p.global_position.x - margin

func _recover_from_behind(p: Paddle, track: Ball, error: float) -> void:
	var t := tuning
	var ball_pos := track.global_position
	var hh := t.recover_half_height * p.size_mod
	var goal_x := p.max_x - t.recover_goal_inset if p.player_id == 1 else p.min_x + t.recover_goal_inset
	var away := 1.0 if p.global_position.y >= ball_pos.y else -1.0
	if ball_pos.y < t.recover_top_y:
		away = 1.0
	elif ball_pos.y > t.recover_bottom_y:
		away = -1.0
	var dodge_y := clampf(ball_pos.y + away * (hh + t.recover_dodge_clearance) + randf_range(-error, error), t.recover_min_y, t.recover_max_y)

	# Step off the ball's lane first, then slide past it toward the goal line
	# so a backhand / stream can send it back onto the court.
	if absf(p.global_position.y - ball_pos.y) < hh:
		_target_pos = Vector2(p.global_position.x, dodge_y)
		_intent_shoot = false
		_intent_suck = false
	else:
		_target_pos = Vector2(goal_x, dodge_y)
		var on_goal_side := (p.player_id == 1 and p.global_position.x >= ball_pos.x - t.recover_goal_side_slack) \
			or (p.player_id == 0 and p.global_position.x <= ball_pos.x + t.recover_goal_side_slack)
		if on_goal_side and absf(p.global_position.y - ball_pos.y) < hh + t.recover_swing_slack:
			_intent_shoot = true
			_intent_blast = true
		else:
			_intent_shoot = false

	if twin_paddle != null and is_instance_valid(twin_paddle):
		_twin_target_pos = Vector2(p.min_x + t.twin_recover_inset, clampf(540.0 - away * t.twin_recover_spread, t.twin_recover_min_y, t.twin_recover_max_y))

func _error_budget() -> float:
	var t := tuning
	var err := t.error_base + (t.error_difficulty_ref - difficulty) * t.error_difficulty_gain
	err += ball.velocity.length() * t.error_speed_gain
	if game_mgr != null:
		var lead := game_mgr.score_p2 - game_mgr.score_p1
		if lead >= t.error_lead_threshold:
			err += lead * t.error_lead_gain
		elif lead <= -t.error_lead_threshold:
			err *= t.error_trail_scale
	if ball.rally_hits < t.error_early_rally_hits:
		err *= t.error_early_scale
	return err

func _fold_walls(y: float) -> float:
	var top := tuning.fold_top_y
	var bottom := tuning.fold_bottom_y
	var pred := y
	var guard := 0
	while (pred < top or pred > bottom) and guard < 6:
		guard += 1
		if pred < top:
			pred = top * 2.0 - pred
		if pred > bottom:
			pred = bottom * 2.0 - pred
	return pred
