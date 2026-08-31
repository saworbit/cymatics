class_name PaddleAI
extends Node

## Rally-first opponent. Misses more when ahead, tightens up when behind.

@export var enabled := true
@export var reaction_delay := 0.07
@export var difficulty := 1.0

var paddle: Paddle
var ball: Ball
var game_mgr: GameManager
var chaos

var _timer := 0.0
var _target_pos := Vector2(1720, 540)
var _serve_delay := 0.8
var _intent_blast := false
var _intent_shoot := false
var _intent_suck := false
var _noise := 0.0

func setup(p_paddle: Paddle, p_ball: Ball) -> void:
	paddle = p_paddle
	ball = p_ball
	paddle.is_ai = true

func _physics_process(delta: float) -> void:
	if not enabled or paddle == null or ball == null:
		return
	if paddle.stun_time > 0.0:
		return

	_timer += delta
	if _timer >= reaction_delay / maxf(difficulty, 0.4):
		_timer = 0.0
		_evaluate_tactics()

	var to_target := _target_pos - paddle.global_position
	var desired := Vector2.ZERO
	if absf(to_target.y) > 12.0:
		desired.y = signf(to_target.y)
	if absf(to_target.x) > 22.0:
		desired.x = signf(to_target.x)

	var spd := paddle.speed * clampf(0.72 + difficulty * 0.28, 0.65, 1.15)
	paddle.velocity = paddle.velocity.move_toward(desired * spd, 7000.0 * delta)
	paddle.move_and_slide()
	paddle.global_position.x = clampf(paddle.global_position.x, paddle.min_x, paddle.max_x)
	paddle.global_position.y = clampf(paddle.global_position.y, paddle.min_y, paddle.max_y)

	paddle.is_shooting = _intent_shoot
	paddle.is_sucking = _intent_suck

	if _intent_blast and paddle.blast_cooldown <= 0.0:
		_intent_blast = false
		if ball.is_serving and ball.serve_paddle == paddle:
			paddle.try_serve()
		elif paddle.armed_time > 0.0:
			paddle.fire_stun_bolt()
		elif paddle.momentum >= 1.0 and randf() < 0.55:
			paddle.trigger_resonance()
		else:
			paddle.trigger_blast(1.0)

func _evaluate_tactics() -> void:
	_intent_blast = false
	_intent_shoot = false
	_intent_suck = false

	if ball.is_serving:
		if ball.serve_paddle == paddle:
			_serve_delay -= reaction_delay
			_target_pos = Vector2(paddle.min_x + 90.0, 540.0 + sin(Time.get_ticks_msec() * 0.002) * 80.0)
			if _serve_delay <= 0.0:
				_intent_blast = true
				_serve_delay = randf_range(0.45, 1.1)
		else:
			_target_pos = Vector2(paddle.max_x - 50.0, 540.0)
		return
	_serve_delay = randf_range(0.5, 1.0)

	if ball.is_scored:
		_target_pos = Vector2(paddle.min_x + 80.0, 540.0)
		return

	var track: Ball = chaos.threat_ball_for(paddle) if chaos != null else ball
	if track == null:
		track = ball
	var ball_pos := track.global_position
	var ball_vel: Vector2 = track.velocity
	var dist := paddle.global_position.distance_to(ball_pos)
	var vertical := absf(ball_pos.y - paddle.global_position.y)
	var error := _error_budget()

	if ball_vel.x > 40.0:
		var time_to_reach := (paddle.global_position.x - ball_pos.x) / maxf(ball_vel.x, 90.0)
		var predicted_y := ball_pos.y + ball_vel.y * time_to_reach + _noise
		predicted_y = _fold_walls(predicted_y)
		predicted_y += randf_range(-error, error)
		_target_pos = Vector2(paddle.max_x - 36.0, clampf(predicted_y, 110.0, 970.0))

		# Build rallies: suction slingshots, stream deflections, and tactical blasts
		if paddle.armed_time > 0.0 and vertical < 90.0 and randf() < 0.35:
			_intent_blast = true
		elif dist < 180.0 and paddle.is_sucking and randf() < 0.45 * difficulty:
			# Slingshot release from suction orbit
			_intent_blast = true
		elif dist < 220.0 and vertical < 80.0 and track.rally_hits >= 3 and randf() < 0.18 * difficulty:
			_intent_blast = true
		elif dist > 260.0 and dist < 780.0 and vertical > 40.0:
			_intent_suck = true
		elif dist < 420.0 and vertical < 140.0:
			_intent_shoot = randf() < 0.42
	else:
		_target_pos = Vector2(paddle.min_x + 70.0, clampf(ball_pos.y + randf_range(-error, error), 180.0, 900.0))
		if ball_pos.x < paddle.global_position.x and vertical < 150.0 and ball_vel.x < -80.0:
			_intent_shoot = true
		else:
			_intent_shoot = randf() < 0.08

	_noise = lerpf(_noise, randf_range(-error, error), 0.2)

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
