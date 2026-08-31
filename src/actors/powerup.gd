class_name Powerup
extends Area2D

enum Kind { MULTIBALL, GROW, TINY, STUN_ARM, MAGNET, FIREBALL, HYPER }

signal collected(kind: Kind, hitter_id: int, ball: Ball)

var kind: Kind = Kind.MULTIBALL
var _life := 11.0
var _bob := 0.0
var _visual: ColorRect
var _label: Label

const LABELS := {
	Kind.MULTIBALL: "MULTI",
	Kind.GROW: "GIANT",
	Kind.TINY: "TINY",
	Kind.STUN_ARM: "STUN",
	Kind.MAGNET: "MAG",
	Kind.FIREBALL: "FIRE",
	Kind.HYPER: "HYPER",
}

const COLORS := {
	Kind.MULTIBALL: Color(1.0, 0.92, 0.25),
	Kind.GROW: Color(0.3, 1.0, 0.45),
	Kind.TINY: Color(1.0, 0.45, 0.9),
	Kind.STUN_ARM: Color(0.55, 0.85, 1.0),
	Kind.MAGNET: Color(0.4, 0.7, 1.0),
	Kind.FIREBALL: Color(1.0, 0.4, 0.08),
	Kind.HYPER: Color(1.0, 0.2, 0.35),
}

func _ready() -> void:
	z_index = 9
	collision_layer = 4
	collision_mask = 1
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	var shape := CircleShape2D.new()
	shape.radius = 28.0
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	_build_visual()

func setup(p_kind: Kind, pos: Vector2) -> void:
	kind = p_kind
	global_position = pos
	_refresh_visual()

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

func _process(delta: float) -> void:
	_life -= delta
	_bob += delta * 5.0
	if _visual != null:
		_visual.position.y = -44.0 + sin(_bob) * 6.0
		_visual.rotation += delta * 1.8
	if _life <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body is Ball:
		var b := body as Ball
		if b.is_scored or b.is_serving:
			return
		collected.emit(kind, b.last_hitter_id, b)
		queue_free()
