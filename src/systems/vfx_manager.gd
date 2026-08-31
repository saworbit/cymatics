class_name VFXManager
extends Node2D

signal flash_requested(color: Color, alpha: float, duration: float)

@export var camera: Camera2D

var _shake_amount := 0.0
var _kick := Vector2.ZERO
var _hitstop_id := 0
var _shock_shader: Shader
var _burst_shader: Shader
var _zoom_punch := 0.0

func _ready() -> void:
	z_index = 20
	_shock_shader = load("res://shaders/vfx/shockwave_ring.gdshader")
	_burst_shader = load("res://shaders/vfx/hit_burst.gdshader")

func _process(delta: float) -> void:
	_shake_amount = maxf(_shake_amount - delta * 48.0, 0.0)
	_kick = _kick.lerp(Vector2.ZERO, clampf(delta * 10.0, 0.0, 1.0))
	_zoom_punch = move_toward(_zoom_punch, 0.0, delta * 2.4)
	if camera != null:
		var jitter := Vector2.ZERO
		if _shake_amount > 0.05:
			jitter = Vector2(randf_range(-_shake_amount, _shake_amount), randf_range(-_shake_amount, _shake_amount))
		camera.offset = _kick + jitter

func spawn_shockwave(pos: Vector2, color: Color, max_size: float = 350.0, duration: float = 0.35) -> void:
	var sw := ColorRect.new()
	sw.z_index = 25
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sw.size = Vector2(max_size, max_size)
	sw.pivot_offset = sw.size * 0.5
	sw.global_position = pos - sw.pivot_offset
	var mat := ShaderMaterial.new()
	mat.shader = _shock_shader
	mat.set_shader_parameter("ring_color", color)
	mat.set_shader_parameter("progress", 0.0)
	sw.material = mat
	add_child(sw)
	var tween := create_tween()
	tween.tween_method(func(val: float):
		if is_instance_valid(sw) and mat != null:
			mat.set_shader_parameter("progress", val)
	, 0.0, 1.0, duration)
	tween.tween_callback(sw.queue_free)

func spawn_hit_burst(pos: Vector2, color: Color, scale_multiplier: float = 1.0) -> void:
	var burst := ColorRect.new()
	burst.z_index = 26
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base_size := 240.0 * scale_multiplier
	burst.size = Vector2(base_size, base_size)
	burst.pivot_offset = burst.size * 0.5
	burst.global_position = pos - burst.pivot_offset
	var mat := ShaderMaterial.new()
	mat.shader = _burst_shader
	mat.set_shader_parameter("star_color", color)
	mat.set_shader_parameter("intensity", 3.2 * scale_multiplier)
	mat.set_shader_parameter("progress", 0.0)
	burst.material = mat
	add_child(burst)
	var tween := create_tween()
	tween.tween_method(func(val: float):
		if is_instance_valid(burst) and mat != null:
			mat.set_shader_parameter("progress", val)
	, 0.0, 1.0, 0.24)
	tween.tween_callback(burst.queue_free)

func spawn_trajectory(origin: Vector2, vel: Vector2, color: Color) -> void:
	var line := Line2D.new()
	line.z_index = 24
	line.width = 6.0
	line.default_color = Color(color.r, color.g, color.b, 0.85)
	line.antialiased = true
	var p := origin
	var v := vel
	for i in range(18):
		line.add_point(p)
		v.y += 0.0
		p += v * 0.018
		if p.y < 54.0:
			p.y = 54.0
			v.y = absf(v.y)
		elif p.y > 1026.0:
			p.y = 1026.0
			v.y = -absf(v.y)
	add_child(line)
	var tween := create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.45)
	tween.tween_callback(line.queue_free)

func apply_camera_kick(direction: Vector2, strength: float) -> void:
	_shake_amount = maxf(_shake_amount, strength * 16.0)
	if direction.length() > 0.01:
		_kick += direction.normalized() * (strength * 22.0)
		_kick = _kick.limit_length(42.0)
	_zoom_punch = maxf(_zoom_punch, strength * 0.045)

func apply_hit_stop(real_duration: float, scale: float = 0.12) -> void:
	if real_duration <= 0.001:
		return
	_hitstop_id += 1
	var id := _hitstop_id
	Engine.time_scale = minf(Engine.time_scale, clampf(scale, 0.04, 1.0))
	var tree := get_tree()
	if tree == null:
		Engine.time_scale = 1.0
		return
	var timer := tree.create_timer(real_duration, true, false, true)
	timer.timeout.connect(func():
		if id == _hitstop_id:
			Engine.time_scale = 1.0
	)

func flash_screen(color: Color, alpha: float, duration: float) -> void:
	flash_requested.emit(color, alpha, duration)

func get_zoom_punch() -> float:
	return _zoom_punch
