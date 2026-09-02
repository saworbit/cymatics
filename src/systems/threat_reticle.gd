class_name ThreatReticle
extends Node2D

## Goal-line threat reticle. When the ball is flying toward a human paddle's
## goal above a speed threshold, project where it will cross the goal line
## (straight flight with wall reflections) and draw a fading tick there.
## Diegetic lost-ball aid: it says "where will it be", not "where is it".

const ARENA_W := 1920.0
const TOP := 40.0
const BOTTOM := 1040.0
const GOAL_LEFT_X := 30.0
const GOAL_RIGHT_X := 1890.0
const MIN_SPEED := 620.0

var _ball: Ball
var _game_mgr: GameManager
var _paddles: Array[Paddle] = []
var _alpha := 0.0
var _hit_y := 540.0
var _side := 0
var _color := Color.WHITE
var _eta := 0.0

func _ready() -> void:
	z_index = 15
	top_level = true

func setup(ball: Ball, game_mgr: GameManager, left: Paddle, right: Paddle) -> void:
	_ball = ball
	_game_mgr = game_mgr
	_paddles = [left, right]

func _process(delta: float) -> void:
	var want := 0.0
	if _ball != null and _game_mgr != null and _game_mgr.current_state == GameManager.State.PLAYING \
			and not _ball.is_scored and not _ball.is_serving:
		var v := _ball.velocity
		var speed := v.length()
		if speed >= MIN_SPEED and absf(v.x) > speed * 0.25:
			var side := 0 if v.x < 0.0 else 1
			var target: Paddle = _paddles[side] if side < _paddles.size() else null
			if target != null and not target.is_ai:
				var goal_x := GOAL_LEFT_X if side == 0 else GOAL_RIGHT_X
				var t := (goal_x - _ball.global_position.x) / v.x
				if t > 0.0 and t < 2.5:
					_hit_y = _reflect_y(_ball.global_position.y + v.y * t)
					_side = side
					_eta = t
					_color = target.team_color
					# Fade in with urgency: faster and closer means brighter.
					want = 0.35 + clampf((speed - MIN_SPEED) / 900.0, 0.0, 1.0) * 0.35 + clampf(1.0 - t / 1.6, 0.0, 1.0) * 0.3
	_alpha = move_toward(_alpha, want, delta * (6.0 if want > _alpha else 3.0))
	queue_redraw()

func _reflect_y(y: float) -> float:
	var span := BOTTOM - TOP
	var rel := fmod(y - TOP, span * 2.0)
	if rel < 0.0:
		rel += span * 2.0
	if rel > span:
		rel = span * 2.0 - rel
	return TOP + rel

func _draw() -> void:
	if _alpha <= 0.01:
		return
	var x := GOAL_LEFT_X if _side == 0 else GOAL_RIGHT_X
	var dir := 1.0 if _side == 0 else -1.0
	var c := _color
	c.a = _alpha
	var glow := Color(c.r, c.g, c.b, _alpha * 0.35)
	# Tick on the goal line plus a chevron pointing into the court.
	var half := 34.0 + 26.0 * clampf(1.0 - _eta / 2.5, 0.0, 1.0)
	draw_line(Vector2(x, _hit_y - half), Vector2(x, _hit_y + half), c, 7.0, true)
	draw_line(Vector2(x, _hit_y - half * 1.6), Vector2(x, _hit_y + half * 1.6), glow, 14.0, true)
	var tip := Vector2(x + dir * 30.0, _hit_y)
	draw_line(Vector2(x + dir * 8.0, _hit_y - 18.0), tip, c, 4.0, true)
	draw_line(Vector2(x + dir * 8.0, _hit_y + 18.0), tip, c, 4.0, true)
	# Soft pulse ring scaled by ETA so it reads as a countdown.
	var pulse := fmod(Time.get_ticks_msec() * 0.001 * 2.2, 1.0)
	var ring_col := Color(c.r, c.g, c.b, _alpha * (1.0 - pulse) * 0.5)
	draw_arc(Vector2(x + dir * 10.0, _hit_y), 12.0 + pulse * 40.0, 0.0, TAU, 32, ring_col, 2.0, true)
