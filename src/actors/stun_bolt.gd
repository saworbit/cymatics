class_name StunBolt
extends Area2D

signal hit_paddle(paddle: Paddle)

var team_id := 0
var velocity := Vector2.ZERO
var _life := 1.1
var _consumed := false
var _visual: ColorRect

func _ready() -> void:
	z_index = 11
	collision_layer = 8
	collision_mask = 2
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(70, 22)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	_visual = ColorRect.new()
	_visual.size = Vector2(90, 36)
	_visual.position = Vector2(-45, -18)
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/vfx/stun_bolt.gdshader")
	_visual.material = mat
	add_child(_visual)

func setup(origin: Vector2, dir: Vector2, p_team: int, color: Color) -> void:
	team_id = p_team
	global_position = origin
	velocity = dir.normalized() * 1750.0
	rotation = dir.angle()
	if _visual != null and _visual.material is ShaderMaterial:
		(_visual.material as ShaderMaterial).set_shader_parameter("bolt_color", color)

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	_life -= delta
	if _life <= 0.0 or global_position.x < -40.0 or global_position.x > 1960.0:
		set_deferred("monitoring", false)
		queue_free()

func _on_body_entered(body: Node) -> void:
	if _consumed:
		return
	if body is Paddle:
		var p := body as Paddle
		if p.player_id == team_id:
			return
		_consumed = true
		hit_paddle.emit(p)
		set_deferred("monitoring", false)
		queue_free()
