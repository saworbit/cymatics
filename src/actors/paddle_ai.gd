class_name PaddleAI
extends Node

## Rally-first opponent that still ends rallies: captures slow balls and
## slingshots them at the open corner, charges a blast when the opponent is out
## of position, and stops sucking a ball that is already slow and near.
## Misses more when ahead, tightens up when behind.
## `aggression` (0..1) scales blast/resonance/slingshot usage and approach speed.

@export var enabled := true
@export var reaction_delay := 0.07
@export var difficulty := 1.0
@export var aggression := 0.55

var paddle: Paddle
var twin_paddle: Paddle
var ball: Ball
var game_mgr: GameManager
var chaos

var _timer := 0.0
var _target_pos := Vector2(1720, 540)
var _twin_target_pos := Vector2(1720, 320)
var _serve_delay := 0.8
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

	_timer += delta
	var think_interval := reaction_delay / maxf(difficulty, 0.4)
	if _timer >= think_interval:
		var elapsed := _timer
		_timer = 0.0
		_evaluate_tactics(elapsed)

	var to_target := _target_pos - paddle.global_position
	var desired := Vector2.ZERO
	if absf(to_target.y) > 12.0:
		desired.y = signf(to_target.y)
	if absf(to_target.x) > 22.0:
		desired.x = signf(to_target.x)

	var spd := paddle.speed * clampf(0.72 + difficulty * 0.28, 0.65, 1.25) * _approach_mult()
	paddle.velocity = paddle.velocity.move_toward(desired * spd, 7000.0 * delta)
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
		if absf(twin_to.y) > 12.0:
			twin_des.y = signf(twin_to.y)
		if absf(twin_to.x) > 22.0:
			twin_des.x = signf(twin_to.x)
		twin_paddle.velocity = twin_paddle.velocity.move_toward(twin_des * spd, 7000.0 * delta)
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
		elif paddle.is_resonance_ready() and randf() < 0.3 + aggression * 0.5:
			paddle.trigger_resonance()
		else:
			paddle.trigger_blast(0.0)

## Holds a capture for the planned time, then slingshots at the open corner.
func _drive_capture() -> void:
	var capturing := paddle.is_capturing()
	if capturing and not _was_capturing:
		_capture_plan_hold = lerpf(1.0, 0.4, clampf(aggression, 0.0, 1.0)) * randf_range(0.85, 1.15)
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
	if paddle.is_charging():
		var dist := paddle.global_position.distance_to(ball.global_position)
		var incoming := _is_incoming(ball.velocity)
		var frac := paddle.charge_fraction()
		var held := frac * Paddle.BLAST_CHARGE_TIME
		var in_cone := paddle.blast_in_cone(ball, frac)
		var fire := (in_cone and dist < 260.0) or (held >= _charge_plan and (in_cone or dist < 120.0))
		fire = fire or held >= Paddle.BLAST_CHARGE_TIME + 0.4 or (not incoming and dist > 400.0)
		if fire:
			paddle.release_blast_charge()
		_intent_charge = false
		return
	if _intent_charge:
		_intent_charge = false
		if paddle.begin_blast_charge():
			_charge_plan = randf_range(0.45, 0.7)

func _open_corner_dir(from_ball: Ball) -> Vector2:
	var origin := from_ball.global_position if from_ball != null and is_instance_valid(from_ball) else paddle.global_position
	var foe_y := 540.0
	var foe := _foe()
	if foe != null:
		foe_y = foe.global_position.y
	var goal_x := 1860.0 if paddle.player_id == 0 else 60.0
	var corner_y := 130.0 if foe_y > 540.0 else 950.0
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
	return clampf(0.88 + aggression * 0.24, 0.85, 1.15)

func _blast_mult() -> float:
	return clampf(0.5 + aggression, 0.5, 1.5)

func _evaluate_tactics(elapsed: float = -1.0) -> void:
	_intent_blast = false
	_intent_shoot = false
	_intent_suck = false
	_intent_charge = false
	if elapsed < 0.0:
		elapsed = reaction_delay / maxf(difficulty, 0.4)

	if ball.is_serving:
		if ball.serve_paddle == paddle:
			_serve_delay -= elapsed
			_target_pos = Vector2(_court_x(90.0), 540.0 + sin(Time.get_ticks_msec() * 0.002) * 80.0)
			if _serve_delay <= 0.0:
				_intent_blast = true
				_serve_delay = randf_range(0.45, 1.1)
		else:
			_target_pos = Vector2(_goal_x(50.0), 540.0)
		return
	_serve_delay = randf_range(0.5, 1.0)

	if ball.is_scored:
		_target_pos = Vector2(_court_x(80.0), 540.0)
		return

	if paddle.is_capturing():
		# Orbit in progress: step forward so the orbit has room, let _drive_capture time the release.
		_intent_suck = true
		_target_pos = Vector2(_goal_x(330.0), clampf(paddle.global_position.y, 200.0, 880.0))
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
		_noise = lerpf(_noise, randf_range(-error, error), 0.2)
		return

	var incoming_now := _is_incoming(ball_vel)
	if incoming_now and not _was_incoming:
		_roll_approach_bias(ball_speed)
	_was_incoming = incoming_now

	if incoming_now:
		var at_x := _goal_x(36.0)
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
				pred_pos = orb.global_position - Vector2(track.radius + 26.0, 0.0)
				_intent_suck = true
				cutting = true
		var predicted_y := _predict_y(pred_pos, pred_vel, pred_spin, at_x)
		predicted_y += _noise + randf_range(-error, error) + _approach_bias
		predicted_y = _fold_walls(predicted_y)
		var english := _choose_english(track, predicted_y)
		_target_pos = Vector2(at_x, clampf(predicted_y - english * 52.0, 110.0, 970.0))
		if twin_paddle != null and is_instance_valid(twin_paddle):
			if predicted_y < 540.0:
				_twin_target_pos = Vector2(_goal_x(36.0), clampf(predicted_y, 110.0, 520.0))
				_target_pos = Vector2(_court_x(50.0), 780.0)
			else:
				_target_pos = Vector2(_goal_x(36.0), clampf(predicted_y, 560.0, 970.0))
				_twin_target_pos = Vector2(_court_x(50.0), 300.0)

		var foe := _foe()
		var foe_off_lane := 0.0
		if foe != null:
			foe_off_lane = absf(foe.global_position.y - ball_pos.y)

		# End rallies: capture slow balls for a slingshot, charge when the foe is out of
		# position, tap-blast a ball at the paddle, and never suck a ball that is already slow and near.
		if paddle.armed_time > 0.0 and vertical < 90.0 and randf() < 0.35 * _blast_mult():
			_intent_blast = true
		elif dist < 280.0 and ball_speed < 950.0 and can_capture and randf() < 0.45 + 0.5 * aggression:
			# Slow and near: hold suck so the nozzle captures it, then slingshot.
			_intent_suck = true
		elif _plan_charge and dist > 380.0 and dist < 900.0 and ball_speed > 520.0 and foe_off_lane > 240.0:
			_plan_charge = false
			_intent_charge = true
		elif _plan_tap and dist < 240.0 and vertical < 60.0 and track.rally_hits >= 3 and paddle.blast_in_cone(track, 0.0):
			_plan_tap = false
			_intent_blast = true
		elif dist < 320.0 and ball_speed < 700.0:
			# Slow ball at the paddle and no capture available: push it out, do not suck.
			_intent_shoot = true
		elif dist > 300.0 and dist < 780.0 and vertical > 40.0 and ball_speed > 620.0:
			_intent_suck = true
		elif (not cutting) and dist < 420.0 and vertical < 140.0:
			_intent_shoot = randf() < 0.42
	else:
		var orb_pos := _orb_seek_pos()
		if orb_pos != Vector2.ZERO:
			_target_pos = orb_pos
			_intent_suck = true
		else:
			_target_pos = Vector2(_court_x(70.0), clampf(ball_pos.y + randf_range(-error, error), 180.0, 900.0))
		if twin_paddle != null and is_instance_valid(twin_paddle):
			_twin_target_pos = Vector2(_court_x(70.0), 300.0)
		var on_court_side := (paddle.player_id == 1 and ball_pos.x < paddle.global_position.x) \
			or (paddle.player_id == 0 and ball_pos.x > paddle.global_position.x)
		if on_court_side and vertical < 150.0 and ball_vel.x * _side_sign() < -80.0:
			_intent_shoot = true
		elif on_court_side and dist < 260.0 and ball_speed < 600.0 and can_capture and randf() < 0.3 + 0.4 * aggression:
			# A ball dribbling away in front of us is a free slingshot.
			_intent_suck = true
		else:
			_intent_shoot = randf() < 0.08

	_noise = lerpf(_noise, randf_range(-error, error), 0.2)

## One read error per approach. Fast balls are misread more; difficulty tightens it.
func _roll_approach_bias(ball_speed: float) -> void:
	var fast := clampf((ball_speed - 600.0) / 1300.0, 0.0, 1.0)
	var mag := (32.0 + fast * 150.0) * clampf(1.6 - difficulty * 0.6, 0.6, 1.4)
	var sign := 1.0 if randf() < 0.5 else -1.0
	_approach_bias = sign * mag * randf_range(0.35, 1.0)
	_plan_charge = randf() < (0.10 + 0.25 * aggression) * clampf(difficulty, 0.5, 1.3)
	_plan_tap = randf() < 0.10 * _blast_mult()

func _side_sign() -> float:
	return 1.0 if paddle.player_id == 1 else -1.0

func _is_incoming(vel: Vector2) -> bool:
	return vel.x * _side_sign() > 40.0

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
		return orb_x > ball_x and orb_x < paddle.global_position.x + 24.0
	return orb_x < ball_x and orb_x > paddle.global_position.x - 24.0

func _predict_y(pos: Vector2, vel: Vector2, p_spin: float, at_x: float) -> float:
	var vx := vel.x
	if absf(vx) < 30.0:
		return pos.y
	var t := clampf((at_x - pos.x) / vx, 0.0, 1.8)
	var spd := vel.length()
	var mag_y := 0.0
	if spd > 1.0:
		mag_y = (vel.x / spd) * p_spin * Ball.MAGNUS_ACCEL
	return pos.y + vel.y * t + 0.5 * mag_y * t * t

func _choose_english(track: Ball, predicted_y: float) -> float:
	if track.rally_hits < 2:
		return 0.0
	var foe_y := 540.0
	var foe := _foe()
	if foe != null:
		foe_y = foe.global_position.y
	var want := 0.0
	if foe_y < predicted_y - 40.0:
		want = 0.55
	elif foe_y > predicted_y + 40.0:
		want = -0.55
	else:
		want = 0.4 if predicted_y < 540.0 else -0.4
	if randf() > clampf(0.28 + difficulty * 0.4, 0.2, 0.85):
		return 0.0
	return want

func _orb_seek_pos() -> Vector2:
	if chaos == null or chaos.live_powerup == null or not is_instance_valid(chaos.live_powerup):
		return Vector2.ZERO
	var pos: Vector2 = chaos.live_powerup.global_position
	if pos.x < paddle.min_x - 90.0 or pos.x > paddle.max_x + 50.0:
		return Vector2.ZERO
	return Vector2(
		clampf(pos.x, paddle.min_x + 24.0, paddle.max_x - 24.0),
		clampf(pos.y, 120.0, 960.0)
	)

func _is_behind(p: Paddle, ball_pos: Vector2) -> bool:
	var margin := 24.0 * p.size_mod
	if p.player_id == 1:
		return ball_pos.x > p.global_position.x + margin
	return ball_pos.x < p.global_position.x - margin

func _recover_from_behind(p: Paddle, track: Ball, error: float) -> void:
	var ball_pos := track.global_position
	var hh := 80.0 * p.size_mod
	var goal_x := p.max_x - 20.0 if p.player_id == 1 else p.min_x + 20.0
	var away := 1.0 if p.global_position.y >= ball_pos.y else -1.0
	if ball_pos.y < 180.0:
		away = 1.0
	elif ball_pos.y > 900.0:
		away = -1.0
	var dodge_y := clampf(ball_pos.y + away * (hh + 56.0) + randf_range(-error, error), 110.0, 970.0)

	# Step off the ball's lane first, then slide past it toward the goal line
	# so a backhand / stream can send it back onto the court.
	if absf(p.global_position.y - ball_pos.y) < hh:
		_target_pos = Vector2(p.global_position.x, dodge_y)
		_intent_shoot = false
		_intent_suck = false
	else:
		_target_pos = Vector2(goal_x, dodge_y)
		var on_goal_side := (p.player_id == 1 and p.global_position.x >= ball_pos.x - 12.0) \
			or (p.player_id == 0 and p.global_position.x <= ball_pos.x + 12.0)
		if on_goal_side and absf(p.global_position.y - ball_pos.y) < hh + 40.0:
			_intent_shoot = true
			_intent_blast = true
		else:
			_intent_shoot = false

	if twin_paddle != null and is_instance_valid(twin_paddle):
		_twin_target_pos = Vector2(p.min_x + 70.0, clampf(540.0 - away * 220.0, 160.0, 920.0))

func _error_budget() -> float:
	var err := 22.0 + (1.15 - difficulty) * 48.0
	err += ball.velocity.length() * 0.018
	if game_mgr != null:
		var lead := game_mgr.score_p2 - game_mgr.score_p1
		if lead >= 2:
			err += lead * 16.0
		elif lead <= -2:
			err *= 0.55
	if ball.rally_hits < 2:
		err *= 0.7
	return err

func _fold_walls(y: float) -> float:
	var pred := y
	var guard := 0
	while (pred < 80.0 or pred > 1000.0) and guard < 6:
		guard += 1
		if pred < 80.0:
			pred = 160.0 - pred
		if pred > 1000.0:
			pred = 2000.0 - pred
	return pred
