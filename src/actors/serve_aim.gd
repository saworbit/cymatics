class_name ServeAim
extends Node2D

## Serve aim indicator drawn by the serving paddle: a short arrow from the held
## ball along the current aim plus a dotted arc showing the legal cone.

var aim_dir := Vector2.RIGHT
var origin := Vector2.ZERO
var color := Color(0.0, 0.9, 1.0)
var forward := Vector2.RIGHT
var cone_deg := 55.0
var _pulse := 0.0

func _ready() -> void:
	z_index = 8
	visible = false

func setup(p_color: Color, p_forward: Vector2, p_cone_deg: float) -> void:
	color = p_color
	forward = p_forward
	cone_deg = p_cone_deg
	aim_dir = p_forward

func set_aim(dir: Vector2, p_origin: Vector2) -> void:
	aim_dir = dir.normalized() if dir.length_squared() > 0.0001 else forward
	origin = p_origin
	queue_redraw()

func _process(delta: float) -> void:
	if not visible:
		return
	_pulse += delta * 5.0
	queue_redraw()

func _draw() -> void:
	var glow := 0.75 + 0.25 * sin(_pulse)
	var arc_r := 118.0
	var half := deg_to_rad(cone_deg)
	var base_ang := forward.angle()
	# Dotted arc: the legal serve cone.
	var dots := 15
	var dim := Color(color.r, color.g, color.b, 0.32)
	for i in range(dots + 1):
		var a := base_ang - half + (2.0 * half) * float(i) / float(dots)
		var p := origin + Vector2(cos(a), sin(a)) * arc_r
		draw_circle(p, 2.6, dim)
	# Current aim marker on the arc.
	var marker := origin + aim_dir * arc_r
	draw_circle(marker, 7.0, Color(1.0, 1.0, 1.0, 0.9 * glow))
	draw_circle(marker, 4.0, Color(color.r, color.g, color.b, 1.0))
	# Arrow from the ball along the aim.
	var start := origin + aim_dir * 26.0
	var tip := origin + aim_dir * 92.0
	var bright := Color(color.r, color.g, color.b, 0.95 * glow)
	draw_line(start, tip, Color(1.0, 1.0, 1.0, 0.55 * glow), 7.0, true)
	draw_line(start, tip, bright, 3.5, true)
	var side := Vector2(-aim_dir.y, aim_dir.x)
	var head := PackedVector2Array([
		tip + aim_dir * 14.0,
		tip - aim_dir * 6.0 + side * 10.0,
		tip - aim_dir * 6.0 - side * 10.0,
	])
	draw_colored_polygon(head, Color(1.0, 1.0, 1.0, 0.95 * glow))
	draw_colored_polygon(PackedVector2Array([
		tip + aim_dir * 9.0,
		tip - aim_dir * 3.0 + side * 5.0,
		tip - aim_dir * 3.0 - side * 5.0,
	]), bright)
