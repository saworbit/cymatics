class_name GoalWall
extends Node2D

## Goal energy membrane for one side of the court. Draws a tall additive
## ColorRect with `goal_wall.gdshader`; intensity follows ball threat
## (distance and inbound speed), a ripple sits where the ball would cross,
## and a goal fires a pulse plus a fracture flash.
##
## Finds Ball / GameManager / ThreatReticle lazily on the Main node so the
## arena scene stays free of hard references.

const ARENA_W := 1920.0
const TOP := 40.0
const BOTTOM := 1040.0
const WIDTH := 150.0
const THREAT_RANGE := 640.0

@export var side := 0 # 0 = left (P1 goal), 1 = right (P2 goal)
@export var team_color := Color(0.0, 0.9, 1.0)

var _rect: ColorRect
var _mat: ShaderMaterial
var _ball: Ball
var _game_mgr: GameManager
var _reticle: Node2D
var _bound := false
var _threat := 0.0
var _ripple := 0.0
var _ripple_y := 0.5
var _pulse := 0.0
var _fracture := 0.0
var _idle := 0.18

func _ready() -> void:
	z_index = 6
	_rect = ColorRect.new()
	_rect.name = "Membrane"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.WHITE
	_rect.size = Vector2(WIDTH, BOTTOM - TOP)
	_rect.position = Vector2(0.0 if side == 0 else ARENA_W - WIDTH, TOP)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/vfx/goal_wall.gdshader")
	_mat.set_shader_parameter("team_color", team_color)
	_mat.set_shader_parameter("flip", 1.0 if side == 1 else 0.0)
	_mat.set_shader_parameter("aspect", WIDTH / (BOTTOM - TOP))
	_rect.material = _mat
	add_child(_rect)
	call_deferred("_bind")

func _bind() -> void:
	if _bound:
		return
	var main := get_parent().get_parent() if get_parent() != null else null
	if main == null:
		return
	_ball = main.get_node_or_null("Ball") as Ball
	_game_mgr = main.get_node_or_null("GameManager") as GameManager
	_reticle = main.get_node_or_null("ThreatReticle") as Node2D
	if _ball == null:
		_ball = get_tree().get_first_node_in_group("cymatics_balls") as Ball
	if _ball == null or _game_mgr == null:
		return
	_bound = true
	if _game_mgr.has_signal("goal_theatre_started"):
		_game_mgr.connect("goal_theatre_started", _on_goal_theatre)
	else:
		_ball.goal_reached.connect(_on_goal_reached)
	if _game_mgr.has_signal("serving_started"):
		_game_mgr.serving_started.connect(func(_id: int): _fracture = 0.0)

## Public hook so other systems (VFX agent, bosses) can flash a wall directly.
func flash(strength := 1.0, at_y := 540.0) -> void:
	_pulse = maxf(_pulse, strength)
	_fracture = maxf(_fracture, clampf(strength, 0.0, 1.0))
	_ripple_y = clampf((at_y - TOP) / (BOTTOM - TOP), 0.0, 1.0)
	_ripple = maxf(_ripple, 1.0)

func _on_goal_theatre(p_side: int, pos: Vector2) -> void:
	if p_side != side:
		return
	flash(1.6, pos.y)

func _on_goal_reached(player_side: int) -> void:
	if player_side != side:
		return
	var y := _ball.global_position.y if _ball != null else 540.0
	flash(1.6, y)

func _process(delta: float) -> void:
	if not _bound:
		_bind()
	var want_threat := 0.0
	var want_ripple := 0.0
	var in_menu := _game_mgr == null or _game_mgr.current_state == GameManager.State.MENU
	var want_idle := 0.16 if in_menu else 0.3

	if _bound and not in_menu and not _ball.is_scored and not _ball.is_serving:
		var v := _ball.velocity
		var inbound := (v.x < 0.0) if side == 0 else (v.x > 0.0)
		if inbound:
			var goal_x := 0.0 if side == 0 else ARENA_W
			var dist := absf(_ball.global_position.x - goal_x)
			var speed := v.length()
			var near := clampf(1.0 - dist / THREAT_RANGE, 0.0, 1.0)
			var fast := clampf((speed - 400.0) / 1400.0, 0.0, 1.0)
			want_threat = near * (0.35 + fast * 0.65)
			if absf(v.x) > 1.0:
				var t := (goal_x - _ball.global_position.x) / v.x
				if t > 0.0 and t < 2.0:
					var y := _reflect_y(_ball.global_position.y + v.y * t)
					_ripple_y = lerpf(_ripple_y, (y - TOP) / (BOTTOM - TOP), clampf(delta * 10.0, 0.0, 1.0))
					want_ripple = clampf(1.0 - t / 1.4, 0.0, 1.0) * (0.4 + fast * 0.6)
		# Borrow the reticle's alpha when it is live so both aids agree.
		if _reticle != null and is_instance_valid(_reticle):
			var ra: Variant = _reticle.get("_alpha")
			var rs: Variant = _reticle.get("_side")
			if ra is float and rs is int and int(rs) == side:
				want_ripple = maxf(want_ripple, float(ra))
		if _ball.is_in_cymatic_lock:
			want_idle = 0.45
		elif _ball.is_in_overdrive:
			want_idle = 0.38

	_threat = move_toward(_threat, want_threat, delta * (5.0 if want_threat > _threat else 2.2))
	_ripple = move_toward(_ripple, want_ripple, delta * 4.0)
	_pulse = move_toward(_pulse, 0.0, delta * 2.4)
	_fracture = move_toward(_fracture, 0.0, delta * 0.9)
	_idle = lerpf(_idle, want_idle, clampf(delta * 3.0, 0.0, 1.0))

	_mat.set_shader_parameter("threat", _threat)
	_mat.set_shader_parameter("ripple", _ripple)
	_mat.set_shader_parameter("ripple_y", _ripple_y)
	_mat.set_shader_parameter("pulse", _pulse)
	_mat.set_shader_parameter("fracture", _fracture)
	_mat.set_shader_parameter("idle", _idle)

func _reflect_y(y: float) -> float:
	var span := BOTTOM - TOP
	var rel := fmod(y - TOP, span * 2.0)
	if rel < 0.0:
		rel += span * 2.0
	if rel > span:
		rel = span * 2.0 - rel
	return TOP + rel
