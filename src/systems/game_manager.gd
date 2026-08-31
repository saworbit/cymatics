class_name GameManager
extends Node

## Match flow: serve ritual, rally stakes, goal theater, comeback rubber-band.

signal score_updated(score_p1: int, score_p2: int)
signal set_won(winner: int, sets_p1: int, sets_p2: int)
signal match_won(winner: int)
signal match_reset
signal rally_updated(hits: int)
signal milestone_reached(milestone_name: String)
signal callout(text: String, color: Color)
signal ai_toggled(enabled: bool)
signal zen_mode_toggled(enabled: bool)
signal serving_started(server_id: int)
signal impact_pulse(amount: float)

enum State { SERVING, PLAYING, GOAL_SCORED, MATCH_OVER }

@export var points_to_win_set := 7
@export var sets_to_win_match := 2

var current_state := State.SERVING
var score_p1 := 0
var score_p2 := 0
var sets_p1 := 0
var sets_p2 := 0
var rally_hits := 0
var next_server := 0

var is_ai_enabled := true
var is_zen_mode := false
var _serve_token := 0

var ball: Ball
var paddle_left: Paddle
var paddle_right: Paddle
var paddle_ai: PaddleAI
var vfx_mgr: VFXManager
var audio_mgr: AudioManager
var chaos

func setup_references(p_ball: Ball, p_p1: Paddle, p_p2: Paddle, p_ai: PaddleAI, p_vfx: VFXManager, p_audio: AudioManager) -> void:
	ball = p_ball
	paddle_left = p_p1
	paddle_right = p_p2
	paddle_ai = p_ai
	vfx_mgr = p_vfx
	audio_mgr = p_audio

	ball.goal_reached.connect(_on_goal_reached)
	ball.hit_paddle.connect(_on_ball_hit_paddle)
	ball.overdrive_entered.connect(func(): _banner("OVERDRIVE", Color(1.0, 0.45, 0.1)))
	ball.cymatic_lock_entered.connect(func():
		_banner("CYMATIC LOCK", Color(1.0, 1.0, 1.0))
		if vfx_mgr != null:
			vfx_mgr.apply_hit_stop(0.12, 0.1)
			vfx_mgr.flash_screen(Color.WHITE, 0.2, 0.18)
	)
	ball.near_miss.connect(_on_near_miss)
	ball.served.connect(func(_d: Vector2):
		current_state = State.PLAYING
		rally_hits = 0
		rally_updated.emit(0)
	)
	paddle_left.super_ready.connect(func(): _banner("RESONANCE READY", paddle_left.team_color))
	paddle_right.super_ready.connect(func(): _banner("RESONANCE READY", paddle_right.team_color))
	paddle_left.resonance_fired.connect(func(_p: Vector2): _banner("RESONANCE", paddle_left.team_color))
	paddle_right.resonance_fired.connect(func(_p: Vector2): _banner("RESONANCE", paddle_right.team_color))

	paddle_left.stunned.connect(func(_d: float): _banner("STUNNED", Color(0.7, 0.9, 1.0)))
	paddle_right.stunned.connect(func(_d: float): _banner("STUNNED", Color(0.7, 0.9, 1.0)))
	paddle_left.armed.connect(func(): _banner("CANNON ARMED", paddle_left.team_color))
	paddle_right.armed.connect(func(): _banner("CANNON ARMED", paddle_right.team_color))
	call_deferred("start_serve", 0)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_ai"):
		is_ai_enabled = not is_ai_enabled
		if paddle_ai != null:
			paddle_ai.enabled = is_ai_enabled
		if paddle_right != null:
			paddle_right.is_ai = is_ai_enabled
		ai_toggled.emit(is_ai_enabled)

	if event.is_action_pressed("restart_game"):
		restart_match()

	if event.is_action_pressed("zen_mode_toggle"):
		is_zen_mode = not is_zen_mode
		zen_mode_toggled.emit(is_zen_mode)

func start_serve(server_id: int) -> void:
	if current_state == State.MATCH_OVER:
		return
	Engine.time_scale = 1.0
	current_state = State.SERVING
	next_server = server_id
	rally_hits = 0
	rally_updated.emit(0)
	if chaos != null:
		chaos.clear_point()
	var server := paddle_left if server_id == 0 else paddle_right
	if ball != null:
		ball.hold_for_serve(server)
	serving_started.emit(server_id)

func _banner(text: String, color: Color) -> void:
	callout.emit(text, color)
	if text in ["OVERDRIVE", "CYMATIC LOCK", "MATCH POINT", "RESONANCE", "ACE", "THAT'S A PADDLIN'!", "MULTIBALL", "STUNNED"]:
		milestone_reached.emit(text)

func _on_ball_hit_paddle(p: Paddle, speed: float, perfect: bool) -> void:
	rally_hits = ball.rally_hits if ball != null else rally_hits + 1
	rally_updated.emit(rally_hits)
	impact_pulse.emit(clampf(speed / 1800.0, 0.2, 1.0))

	if perfect:
		_banner("PERFECT", Color(1.0, 0.95, 0.4))
		if audio_mgr != null:
			audio_mgr.trigger_sting(880.0, 0.5)

	if rally_hits == 3:
		_banner("RALLY x3", Color(1.0, 0.85, 0.3))
	elif rally_hits == 4:
		_banner("HEATING UP", Color(1.0, 0.7, 0.2))
	elif rally_hits == 8:
		_banner("ON FIRE", Color(1.0, 0.4, 0.1))
	elif rally_hits == 15:
		_banner("UNREAL", Color(1.0, 1.0, 1.0))

	_tune_ai_for_drama()

func _on_near_miss(side: int, pos: Vector2) -> void:
	if vfx_mgr != null:
		vfx_mgr.spawn_hit_burst(pos, Color(1.0, 0.9, 0.4), 1.3)
		vfx_mgr.apply_camera_kick(Vector2.LEFT if side == 0 else Vector2.RIGHT, 0.35)
	var scared: Paddle = paddle_left if side == 0 else paddle_right
	if scared:
		scared.emote(6, 0.5, "!!!")
	if ball:
		ball.emote(3, 0.4, "heh")
	callout.emit("CLOSE!", Color(1.0, 0.85, 0.3))
	if audio_mgr != null:
		audio_mgr.trigger_sting(220.0, 0.25)

func _on_goal_reached(scorer_id: int) -> void:
	if current_state == State.MATCH_OVER:
		return

	if is_zen_mode:
		var dir := Vector2(1 if scorer_id == 0 else -1, randf_range(-0.3, 0.3)).normalized()
		ball.reset_ball(Vector2(960, 540), dir)
		return

	current_state = State.GOAL_SCORED
	rally_hits = 0
	rally_updated.emit(0)

	if scorer_id == 1:
		score_p1 += 1
	else:
		score_p2 += 1

	var speed := ball.last_hit_speed if ball != null else 800.0
	var is_ace := ball != null and ball.touch_mask != 0 and (ball.touch_mask & (ball.touch_mask - 1)) == 0 and ball.rally_hits <= 1
	var is_smash := speed >= 1400.0

	if vfx_mgr != null:
		var col := Color(0.0, 0.9, 1.0) if scorer_id == 1 else Color(1.0, 0.0, 0.67)
		var goal_pos := Vector2(1920 if scorer_id == 1 else 0, 540)
		vfx_mgr.apply_hit_stop(0.18, 0.07)
		vfx_mgr.apply_camera_kick(Vector2.RIGHT if scorer_id == 1 else Vector2.LEFT, 1.8)
		vfx_mgr.spawn_shockwave(goal_pos, col, 900.0, 0.7)
		vfx_mgr.spawn_hit_burst(goal_pos, col, 3.0)
		vfx_mgr.flash_screen(col, 0.28, 0.2)

	if audio_mgr != null:
		audio_mgr.trigger_goal(scorer_id, is_smash)

	var scorer: Paddle = paddle_left if scorer_id == 1 else paddle_right
	var loser: Paddle = paddle_right if scorer_id == 1 else paddle_left
	if scorer:
		scorer.emote(2, 1.5, "THAT'S A PADDLIN'!")
	if loser:
		loser.emote(5, 1.4, "aww")

	if is_ace:
		_banner("ACE", Color(1.0, 0.95, 0.45))
	elif is_smash:
		_banner("THAT'S A PADDLIN'!", Color(1.0, 0.85, 0.25))
	else:
		_banner("THAT'S A PADDLIN'!", Color(0.0, 0.9, 1.0) if scorer_id == 1 else Color(1.0, 0.0, 0.67))

	score_updated.emit(score_p1, score_p2)

	if paddle_left != null and scorer_id == 1:
		paddle_left.add_momentum(0.12)
	if paddle_right != null and scorer_id == 0:
		paddle_right.add_momentum(0.12)

	# Cleanly despawn any clone balls when a regulation goal or set ends
	if chaos != null:
		chaos.clear_point()

	var set_ended := _maybe_finish_set()
	if current_state == State.MATCH_OVER:
		return

	var server := 0 if scorer_id == 0 else 1
	var pause := 1.15 if set_ended else 0.85
	_serve_token += 1
	var current_token := _serve_token
	var timer := get_tree().create_timer(pause, true, false, true)
	timer.timeout.connect(func():
		if current_state != State.MATCH_OVER and current_token == _serve_token:
			start_serve(server)
	)

func _maybe_finish_set() -> bool:
	var p1_set := score_p1 >= points_to_win_set and score_p1 - score_p2 >= 2
	var p2_set := score_p2 >= points_to_win_set and score_p2 - score_p1 >= 2
	if score_p1 == score_p2 and score_p1 >= points_to_win_set - 1:
		_banner("DEUCE", Color(1.0, 0.9, 0.5))
	elif not p1_set and not p2_set:
		_announce_stakes()

	if not p1_set and not p2_set:
		return false

	var set_winner := 0 if p1_set else 1
	if set_winner == 0:
		sets_p1 += 1
	else:
		sets_p2 += 1

	score_p1 = 0
	score_p2 = 0
	score_updated.emit(score_p1, score_p2)
	set_won.emit(set_winner, sets_p1, sets_p2)
	_banner("SET " + str(sets_p1) + " - " + str(sets_p2), Color(1.0, 0.9, 0.4))

	if sets_p1 >= sets_to_win_match or sets_p2 >= sets_to_win_match:
		var match_winner := 0 if sets_p1 >= sets_to_win_match else 1
		current_state = State.MATCH_OVER
		Engine.time_scale = 1.0
		match_won.emit(match_winner)
		if vfx_mgr != null:
			vfx_mgr.flash_screen(Color.WHITE, 0.4, 0.35)
		if audio_mgr != null:
			audio_mgr.trigger_goal(match_winner, true)
		return true
	return true

func _announce_stakes() -> void:
	var p1_set_point := score_p1 >= points_to_win_set - 1 and score_p1 > score_p2
	var p2_set_point := score_p2 >= points_to_win_set - 1 and score_p2 > score_p1
	if not p1_set_point and not p2_set_point:
		return
	var leader := 0 if p1_set_point else 1
	var would_win_match := (leader == 0 and sets_p1 + 1 >= sets_to_win_match) or (leader == 1 and sets_p2 + 1 >= sets_to_win_match)
	if would_win_match:
		_banner("MATCH POINT", Color(1.0, 0.3, 0.2))
	else:
		_banner("SET POINT", Color(1.0, 0.75, 0.25))

func _tune_ai_for_drama() -> void:
	if paddle_ai == null or not is_ai_enabled:
		return
	var lead := score_p2 - score_p1
	var diff := 1.0
	if lead >= 3:
		diff = 0.72
	elif lead >= 2:
		diff = 0.85
	elif lead <= -3:
		diff = 1.35
	elif lead <= -2:
		diff = 1.2
	if ball != null and ball.is_in_cymatic_lock:
		diff *= 0.92
	paddle_ai.difficulty = diff

func on_clone_goal(scorer_id: int) -> void:
	if current_state == State.MATCH_OVER:
		return
	if is_zen_mode:
		return
	if scorer_id == 1:
		score_p1 += 1
	else:
		score_p2 += 1
	_banner("MULTI GOAL", Color(1.0, 0.85, 0.2))
	score_updated.emit(score_p1, score_p2)
	if vfx_mgr != null:
		var col := Color(0.0, 0.9, 1.0) if scorer_id == 1 else Color(1.0, 0.0, 0.67)
		vfx_mgr.spawn_shockwave(Vector2(1920 if scorer_id == 1 else 0, 540), col, 520.0, 0.4)
		vfx_mgr.apply_camera_kick(Vector2.RIGHT if scorer_id == 1 else Vector2.LEFT, 1.1)
	if audio_mgr != null:
		audio_mgr.trigger_sting(520.0, 0.4)
	var set_ended := _maybe_finish_set()
	if current_state == State.MATCH_OVER:
		if chaos:
			chaos.clear_point()
		return
	var live: Array = chaos.active_balls() if chaos != null else []
	if live.is_empty() and current_state != State.MATCH_OVER:
		var server := 0 if scorer_id == 0 else 1
		current_state = State.GOAL_SCORED
		_serve_token += 1
		var current_token := _serve_token
		var timer := get_tree().create_timer(0.7, true, false, true)
		timer.timeout.connect(func():
			if current_state != State.MATCH_OVER and current_token == _serve_token:
				start_serve(server)
		)
	elif set_ended:
		if chaos:
			chaos.clear_point()
		var server := 0 if scorer_id == 0 else 1
		_serve_token += 1
		var current_token := _serve_token
		var timer := get_tree().create_timer(0.9, true, false, true)
		timer.timeout.connect(func():
			if current_state != State.MATCH_OVER and current_token == _serve_token:
				start_serve(server)
		)

func restart_match() -> void:
	Engine.time_scale = 1.0
	score_p1 = 0
	score_p2 = 0
	sets_p1 = 0
	sets_p2 = 0
	rally_hits = 0
	current_state = State.SERVING
	next_server = 0

	score_updated.emit(0, 0)
	set_won.emit(0, 0, 0)
	rally_updated.emit(0)
	match_reset.emit()

	if paddle_left != null:
		paddle_left.reset_momentum()
		paddle_left.global_position = Vector2(180, 540)
		paddle_left.velocity = Vector2.ZERO
	if paddle_right != null:
		paddle_right.reset_momentum()
		paddle_right.global_position = Vector2(1740, 540)
		paddle_right.velocity = Vector2.ZERO
	start_serve(0)
