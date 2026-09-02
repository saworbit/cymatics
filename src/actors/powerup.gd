class_name Powerup
extends CharacterBody2D

enum Kind {
	MULTIBALL,
	GROW,
	TINY,
	STUN_ARM,
	MAGNET,
	FIREBALL,
	HYPER,
	BALL_TRI,
	BALL_CUBE,
	BALL_STAR,
	BALL_RUGBY,
	PADDLE_SCOOP,
	PADDLE_WEDGE,
	PADDLE_FORTRESS
}

signal collected(kind: Kind, hitter_id: int, ball: Ball)

const MASS := 2.8
const RADIUS := 26.0
const MAX_SPEED := 420.0

var kind: Kind = Kind.MULTIBALL
var drift_velocity := Vector2.ZERO
var fluid_sim: FluidSimulator
var vfx_mgr: VFXManager
var audio_mgr: AudioManager
var _life := 22.0
var _bob := 0.0
var _consumed := false
var _carom_lock := 0.0
var _roll := 0.0
var _visual: ColorRect
var _label: Label
var _grab: Area2D

const LABELS := {
	Kind.MULTIBALL: "MULTI",
	Kind.GROW: "GIANT",
	Kind.TINY: "TINY",
	Kind.STUN_ARM: "STUN",
	Kind.MAGNET: "MAG",
	Kind.FIREBALL: "FIRE",
	Kind.HYPER: "HYPER",
	Kind.BALL_TRI: "PRISM",
	Kind.BALL_CUBE: "CUBE",
	Kind.BALL_STAR: "STAR",
	Kind.BALL_RUGBY: "BLOB",
	Kind.PADDLE_SCOOP: "SCOOP",
	Kind.PADDLE_WEDGE: "WEDGE",
	Kind.PADDLE_FORTRESS: "AEGIS",
}

const COLORS := {
	Kind.MULTIBALL: Color(1.0, 0.92, 0.25),
	Kind.GROW: Color(0.3, 1.0, 0.45),
	Kind.TINY: Color(1.0, 0.45, 0.9),
	Kind.STUN_ARM: Color(0.55, 0.85, 1.0),
	Kind.MAGNET: Color(0.4, 0.7, 1.0),
	Kind.FIREBALL: Color(1.0, 0.4, 0.08),
	Kind.HYPER: Color(1.0, 0.2, 0.35),
	Kind.BALL_TRI: Color(0.25, 1.0, 0.85),
	Kind.BALL_CUBE: Color(0.92, 0.35, 1.0),
	Kind.BALL_STAR: Color(1.0, 0.88, 0.15),
	Kind.BALL_RUGBY: Color(1.0, 0.32, 0.65),
	Kind.PADDLE_SCOOP: Color(0.2, 0.95, 1.0),
	Kind.PADDLE_WEDGE: Color(1.0, 0.6, 0.1),
	Kind.PADDLE_FORTRESS: Color(0.85, 0.8, 1.0),
}

func _ready() -> void:
	z_index = 9
	motion_mode = MOTION_MODE_FLOATING
	add_to_group("cymatics_powerups")
	# Layer 3 (bit 4): ball can carom off these. Mask 1: only the ball.
	collision_layer = 4
	collision_mask = 1
	var body_shape := CircleShape2D.new()
	body_shape.radius = RADIUS
	var cs := CollisionShape2D.new()
	cs.shape = body_shape
	add_child(cs)
	_build_grabber()
	_build_visual()

func setup(p_kind: Kind, pos: Vector2, p_drift: Vector2 = Vector2.ZERO, p_fluid: FluidSimulator = null, p_vfx: VFXManager = null, p_audio: AudioManager = null) -> void:
	kind = p_kind
	global_position = pos
	drift_velocity = p_drift
	fluid_sim = p_fluid
	vfx_mgr = p_vfx
	audio_mgr = p_audio
	_refresh_visual()

func can_carom() -> bool:
	return not _consumed and _carom_lock <= 0.0

func apply_carom(impulse: Vector2, along: Vector2) -> void:
	if _consumed:
		return
	_carom_lock = 0.12
	drift_velocity += impulse
	_roll = clampf(_roll + impulse.length() * 0.012 * signf(along.x + along.y), -8.0, 8.0)
	if drift_velocity.length() > MAX_SPEED:
		drift_velocity = drift_velocity.normalized() * MAX_SPEED
	global_position += along * 10.0
	if vfx_mgr != null:
		var col: Color = COLORS.get(kind, Color.WHITE)
		vfx_mgr.spawn_hit_burst(global_position, col, 0.9)
		vfx_mgr.spawn_shockwave(global_position, col, 140.0, 0.16)
	if audio_mgr != null:
		audio_mgr.trigger_impact(impulse.length(), global_position, false)

func _build_grabber() -> void:
	_grab = Area2D.new()
	_grab.collision_layer = 0
	_grab.collision_mask = 2
	_grab.monitoring = true
	_grab.monitorable = false
	var gshape := CircleShape2D.new()
	gshape.radius = RADIUS + 6.0
	var gcs := CollisionShape2D.new()
	gcs.shape = gshape
	_grab.add_child(gcs)
	_grab.body_entered.connect(_on_grab_body)
	add_child(_grab)

func _build_visual() -> void:
	_visual = ColorRect.new()
	_visual.size = Vector2(88, 88)
	_visual.position = Vector2(-44, -44)
	_visual.pivot_offset = Vector2(44, 44)
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/vfx/powerup.gdshader")
	_visual.material = mat
	add_child(_visual)
	_label = Label.new()
	_label.position = Vector2(-46, 36)
	_label.size = Vector2(92, 22)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_refresh_visual()

func _refresh_visual() -> void:
	if _label != null:
		_label.text = LABELS.get(kind, "?")
		_label.add_theme_color_override("font_color", COLORS.get(kind, Color.WHITE))
	if _visual != null and _visual.material is ShaderMaterial:
		var col: Color = COLORS.get(kind, Color.WHITE)
		(_visual.material as ShaderMaterial).set_shader_parameter("core_color", Color.WHITE)
		(_visual.material as ShaderMaterial).set_shader_parameter("glow_color", col)

func _physics_process(delta: float) -> void:
	if _consumed:
		return
	_carom_lock = maxf(_carom_lock - delta, 0.0)
	_life -= delta
	_ride_fluid(delta)
	drift_velocity = drift_velocity.lerp(Vector2.ZERO, clampf(delta * 1.15, 0.0, 1.0))
	if drift_velocity.length() > MAX_SPEED:
		drift_velocity = drift_velocity.normalized() * MAX_SPEED
	velocity = drift_velocity
	move_and_collide(drift_velocity * delta)
	_bounce_cushions()
	if _life <= 0.0:
		_begin_despawn()

func _process(delta: float) -> void:
	_bob += delta * 5.0
	if _visual != null:
		_visual.position.y = -44.0 + sin(_bob) * 6.0
		_visual.rotation += delta * (1.8 + _roll)
	_roll = move_toward(_roll, 0.0, delta * 2.4)

func _ride_fluid(delta: float) -> void:
	if fluid_sim == null:
		return
	var fv := fluid_sim.sample_velocity_at(global_position)
	var curl := fluid_sim.sample_curl_at(global_position)
	# Heavier than the ball: take lateral current, ignore most of the aligned shove.
	drift_velocity += fv * (0.72 * delta)
	if absf(curl) > 0.55:
		var tang := Vector2(-(fv.y), fv.x)
		if tang.length_squared() > 1.0:
			drift_velocity += tang.normalized() * (curl * 28.0 * delta)
	var col: Color = COLORS.get(kind, Color.WHITE)
	fluid_sim.inject_dye(global_position, Color(col.r, col.g, col.b, 0.22), 12.0)

func _bounce_cushions() -> void:
	var min_x := 90.0
	var max_x := 1830.0
	var min_y := 90.0
	var max_y := 990.0
	if global_position.x < min_x:
		global_position.x = min_x
		drift_velocity.x = absf(drift_velocity.x) * 0.72
	elif global_position.x > max_x:
		global_position.x = max_x
		drift_velocity.x = -absf(drift_velocity.x) * 0.72
	if global_position.y < min_y:
		global_position.y = min_y
		drift_velocity.y = absf(drift_velocity.y) * 0.72
	elif global_position.y > max_y:
		global_position.y = max_y
		drift_velocity.y = -absf(drift_velocity.y) * 0.72

func _on_grab_body(body: Node) -> void:
	if _consumed:
		return
	if body is Paddle:
		_consumed = true
		if _grab != null:
			_grab.set_deferred("monitoring", false)
		call_deferred("_finish_collect", (body as Paddle).player_id, null)

func _begin_despawn() -> void:
	if _consumed:
		return
	_consumed = true
	if _grab != null:
		_grab.set_deferred("monitoring", false)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	queue_free()

func _finish_collect(hitter_id: int, ball: Ball) -> void:
	if not is_instance_valid(self):
		return
	collected.emit(kind, hitter_id, ball if is_instance_valid(ball) else null)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	queue_free()
