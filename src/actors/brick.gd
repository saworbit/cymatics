class_name Brick
extends StaticBody2D

signal hit(brick: Brick, hp_left: int)
signal destroyed(brick: Brick, breaker_id: int, pos: Vector2)

@export var max_hp := 2
var current_hp := 2
var brick_size := Vector2(70, 36)
var brick_color := Color(0.2, 0.8, 1.0)
var contains_reward := true
var reward_kind: Powerup.Kind = Powerup.Kind.MULTIBALL

var fluid_sim: FluidSimulator
var vfx_mgr: VFXManager
var audio_mgr: AudioManager
var chaos_director

var _visual: ColorRect
var _mat: ShaderMaterial
var _hit_pulse := 0.0
var _is_destroyed := false

func _ready() -> void:
	z_index = 8
	add_to_group("cymatics_bricks")
	collision_layer = 8
	collision_mask = 1
	_build_components()

func setup(pos: Vector2, size: Vector2, hp: int, col: Color, p_reward: Powerup.Kind, p_fluid: FluidSimulator, p_vfx: VFXManager, p_audio: AudioManager, p_chaos = null) -> void:
	global_position = pos
	brick_size = size
	max_hp = hp
	current_hp = hp
	brick_color = col
	reward_kind = p_reward
	fluid_sim = p_fluid
	vfx_mgr = p_vfx
	audio_mgr = p_audio
	chaos_director = p_chaos
	
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		if not cs.shape.resource_local_to_scene:
			cs.shape = cs.shape.duplicate()
			cs.shape.resource_local_to_scene = true
		(cs.shape as RectangleShape2D).size = brick_size
	if _visual != null:
		_visual.size = brick_size
		_visual.position = -brick_size * 0.5
		_visual.pivot_offset = brick_size * 0.5
	_update_visual_properties()

func _build_components() -> void:
	var shape := RectangleShape2D.new()
	shape.size = brick_size
	shape.resource_local_to_scene = true
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)

	_visual = ColorRect.new()
	_visual.size = brick_size
	_visual.position = -brick_size * 0.5
	_visual.pivot_offset = brick_size * 0.5
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/vfx/brick.gdshader")
	_visual.material = _mat
	add_child(_visual)
	_update_visual_properties()

func _update_visual_properties() -> void:
	if _mat != null:
		_mat.set_shader_parameter("base_color", brick_color)
		_mat.set_shader_parameter("glow_color", Color.WHITE if current_hp > 1 else Color(1.0, 0.4, 0.2))
		_mat.set_shader_parameter("hp_ratio", float(current_hp) / float(maxf(max_hp, 1)))
		_mat.set_shader_parameter("time_offset", randf() * 10.0)

func _process(delta: float) -> void:
	if _hit_pulse > 0.0:
		_hit_pulse = maxf(_hit_pulse - delta * 4.5, 0.0)
		if _mat != null:
			_mat.set_shader_parameter("hit_pulse", _hit_pulse)

func on_ball_hit(ball: Ball, hit_normal: Vector2) -> void:
	if _is_destroyed or current_hp <= 0:
		return

	current_hp -= 1
	_hit_pulse = 1.0
	var breaker := ball.last_hitter_id
	hit.emit(self, current_hp)

	# Physical deflection of the ball
	ball.velocity = ball.velocity.bounce(hit_normal) * 1.02
	ball.hit_wall.emit(global_position, ball.velocity.length())

	if fluid_sim != null:
		fluid_sim.inject_shockwave(global_position, hit_normal, 1800.0, brick_color)
		fluid_sim.inject_dye(global_position, brick_color, 90.0)

	if vfx_mgr != null:
		vfx_mgr.spawn_hit_burst(global_position, brick_color, 1.4)
		vfx_mgr.spawn_shockwave(global_position, brick_color, 160.0, 0.2)
		vfx_mgr.apply_camera_kick(hit_normal, 0.3)

	if audio_mgr != null:
		audio_mgr.trigger_impact(ball.velocity.length() * 0.85, global_position, true)

	if current_hp <= 0:
		_is_destroyed = true
		_shatter(breaker)
	else:
		_update_visual_properties()

func _shatter(breaker_id: int) -> void:
	destroyed.emit(self, breaker_id, global_position)
	if vfx_mgr != null:
		vfx_mgr.spawn_hit_burst(global_position, Color.WHITE, 2.6)
		vfx_mgr.spawn_shockwave(global_position, brick_color, 320.0, 0.35)
		vfx_mgr.flash_screen(brick_color, 0.15, 0.08)

	if fluid_sim != null:
		fluid_sim.inject_shockwave(global_position, Vector2.UP, 3600.0, brick_color)
		fluid_sim.inject_vortex(global_position, 5.0 if breaker_id == 0 else -5.0, 160.0, brick_color)

	if audio_mgr != null:
		audio_mgr.trigger_blast(1.0, global_position)

	# Spawn reward capsule drifting toward the breaker's side of the court
	if contains_reward:
		var drift_dir := Vector2.LEFT if breaker_id == 0 else Vector2.RIGHT
		var drift_spd := randf_range(160.0, 260.0)
		var drift_vel := drift_dir * drift_spd + Vector2(0.0, randf_range(-60.0, 60.0))
		var p_up = preload("res://src/actors/powerup.gd").new()
		var parent := get_parent()
		if parent != null:
			parent.call_deferred("add_child", p_up)
			p_up.setup(reward_kind, global_position, drift_vel, fluid_sim, vfx_mgr, audio_mgr)
			if chaos_director != null:
				p_up.collected.connect(chaos_director._on_powerup_collected)

	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	queue_free()
