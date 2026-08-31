class_name CharacterFace
extends Node2D

enum Mood { IDLE, FOCUS, HAPPY, SMUG, ANGRY, SAD, SHOCK, SCARE, DIZZY, FERAL, WINK }

var mood: Mood = Mood.IDLE
var _mood_time := 0.0
var _blink := 0.0
var _blink_cd := 1.8
var _look := Vector2.ZERO
var _look_target := Vector2.ZERO
var _mouth := 1.0
var _lid := 0.0
var _brow := 0.0
var _dizzy := 0.0
var _blush := 0.0
var _base_lid := 0.0
var _flip := 0.0
var _rect: ColorRect
var _mat: ShaderMaterial
var _bark: Label

func setup(size: Vector2, flip: bool, base_lid: float = 0.0) -> void:
	_flip = 1.0 if flip else 0.0
	_base_lid = base_lid
	_lid = base_lid
	z_index = 14
	_rect = ColorRect.new()
	_rect.size = size
	_rect.position = -size * 0.5
	_rect.pivot_offset = size * 0.5
	_rect.color = Color(1, 1, 1, 0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/vfx/character_face.gdshader")
	_mat.set_shader_parameter("flip", _flip)
	_mat.set_shader_parameter("lid", _base_lid)
	_rect.material = _mat
	add_child(_rect)

	_bark = Label.new()
	_bark.position = Vector2(-70, -size.y * 0.55 - 18.0)
	_bark.size = Vector2(140, 28)
	_bark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bark.add_theme_font_size_override("font_size", 18)
	_bark.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	_bark.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_bark.add_theme_constant_override("shadow_offset_x", 2)
	_bark.add_theme_constant_override("shadow_offset_y", 2)
	_bark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bark.modulate.a = 0.0
	add_child(_bark)
	_blink_cd = randf_range(1.2, 3.2)

func set_mood(p_mood: Mood, duration: float = 0.7) -> void:
	mood = p_mood
	_mood_time = duration

func maybe_mood(p_mood: Mood, duration: float = 0.45) -> void:
	if _mood_time <= 0.05:
		set_mood(p_mood, duration)

func look_at_point(from_global: Vector2, target_global: Vector2) -> void:
	var d := target_global - from_global
	_look_target = Vector2(clampf(d.x / 420.0, -1.0, 1.0), clampf(d.y / 320.0, -1.0, 1.0))
	if _flip > 0.5:
		_look_target.x *= -1.0

func bark(text: String) -> void:
	if _bark == null:
		return
	_bark.text = text
	_bark.modulate.a = 1.0
	_bark.scale = Vector2(1.15, 1.15)
	var tw := create_tween()
	tw.tween_property(_bark, "scale", Vector2.ONE, 0.12)
	tw.tween_interval(0.55)
	tw.tween_property(_bark, "modulate:a", 0.0, 0.2)

func _process(delta: float) -> void:
	_mood_time = maxf(_mood_time - delta, 0.0)
	if _mood_time <= 0.0 and mood != Mood.IDLE:
		mood = Mood.IDLE

	_blink_cd -= delta
	if _blink_cd <= 0.0:
		_blink = 1.0
		_blink_cd = randf_range(1.6, 4.2)
	_blink = move_toward(_blink, 0.0, delta * 9.0)

	_apply_mood_targets()
	_look = _look.lerp(_look_target, clampf(delta * 10.0, 0.0, 1.0))
	if _mat == null:
		return
	_mat.set_shader_parameter("look", _look)
	_mat.set_shader_parameter("blink", _blink)
	_mat.set_shader_parameter("mouth", _mouth)
	_mat.set_shader_parameter("lid", _lid)
	_mat.set_shader_parameter("brow", _brow)
	_mat.set_shader_parameter("dizzy", _dizzy)
	_mat.set_shader_parameter("blush", _blush)
	_mat.set_shader_parameter("flip", _flip)

func _apply_mood_targets() -> void:
	_dizzy = 0.0
	_blush = 0.0
	_lid = _base_lid
	_brow = 0.0
	_mouth = 1.0
	match mood:
		Mood.IDLE:
			_mouth = 1.0
		Mood.FOCUS:
			_mouth = 0.0
			_lid = _base_lid + 0.15
			_brow = -0.25
		Mood.HAPPY:
			_mouth = 2.0
			_blush = 0.55
			_brow = 0.15
		Mood.SMUG:
			_mouth = 6.0
			_lid = maxf(_base_lid, 0.45)
			_brow = -0.15
		Mood.ANGRY:
			_mouth = 5.0
			_brow = -0.85
			_lid = _base_lid + 0.2
		Mood.SAD:
			_mouth = 3.0
			_brow = 0.8
			_lid = _base_lid + 0.25
		Mood.SHOCK:
			_mouth = 4.0
			_brow = 0.55
			_lid = 0.0
		Mood.SCARE:
			_mouth = 4.0
			_brow = 0.7
			_lid = 0.0
		Mood.DIZZY:
			_mouth = 4.0
			_dizzy = 1.0
			_lid = 0.2
		Mood.FERAL:
			_mouth = 2.0
			_brow = -0.7
			_lid = 0.05
		Mood.WINK:
			_mouth = 6.0
			_blink = 1.0
			_blush = 0.4
