class_name BrickMatrix
extends Node2D

signal matrix_cleared
signal brick_shattered(breaker_id: int, pos: Vector2)

var fluid_sim: FluidSimulator
var vfx_mgr: VFXManager
var audio_mgr: AudioManager

var _active_bricks: Array[Brick] = []

func setup(p_fluid: FluidSimulator, p_vfx: VFXManager, p_audio: AudioManager) -> void:
	fluid_sim = p_fluid
	vfx_mgr = p_vfx
	audio_mgr = p_audio

func clear_all_bricks() -> void:
	for b in _active_bricks:
		if is_instance_valid(b):
			b.queue_free()
	_active_bricks.clear()

func has_active_bricks() -> bool:
	return _active_bricks.size() > 0

func spawn_firewall(columns: int = 3, rows: int = 7) -> void:
	clear_all_bricks()
	var center := Vector2(960, 540)
	var brick_w := 64.0
	var brick_h := 38.0
	var gap_x := 18.0
	var gap_y := 16.0

	var total_w := float(columns) * (brick_w + gap_x) - gap_x
	var total_h := float(rows) * (brick_h + gap_y) - gap_y
	var start_pos := center - Vector2(total_w * 0.5, total_h * 0.5) + Vector2(brick_w * 0.5, brick_h * 0.5)

	var reward_pool := [
		Powerup.Kind.BALL_TRI,
		Powerup.Kind.BALL_CUBE,
		Powerup.Kind.BALL_STAR,
		Powerup.Kind.BALL_RUGBY,
		Powerup.Kind.PADDLE_SCOOP,
		Powerup.Kind.PADDLE_WEDGE,
		Powerup.Kind.PADDLE_FORTRESS,
		Powerup.Kind.MULTIBALL,
		Powerup.Kind.STUN_ARM,
		Powerup.Kind.HYPER,
		Powerup.Kind.FIREBALL
	]

	for c in range(columns):
		for r in range(rows):
			var pos := start_pos + Vector2(float(c) * (brick_w + gap_x), float(r) * (brick_h + gap_y))
			var col := Color(0.2, 0.85, 1.0) if c == 0 else (Color(1.0, 0.35, 0.8) if c == columns - 1 else Color(1.0, 0.88, 0.25))
			var hp := 2 if c == 1 else 1
			var reward: Powerup.Kind = reward_pool[randi() % reward_pool.size()]
			_spawn_brick(pos, Vector2(brick_w, brick_h), hp, col, reward)

func spawn_diamond() -> void:
	clear_all_bricks()
	var center := Vector2(960, 540)
	var brick_size := Vector2(58, 34)
	var coords := [
		Vector2(0, -3),
		Vector2(-1, -2), Vector2(0, -2), Vector2(1, -2),
		Vector2(-2, -1), Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(2, -1),
		Vector2(-3, 0), Vector2(-2, 0), Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(3, 0),
		Vector2(-2, 1), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1), Vector2(2, 1),
		Vector2(-1, 2), Vector2(0, 2), Vector2(1, 2),
		Vector2(0, 3)
	]

	var rewards := [
		Powerup.Kind.BALL_STAR,
		Powerup.Kind.BALL_TRI,
		Powerup.Kind.BALL_CUBE,
		Powerup.Kind.PADDLE_SCOOP,
		Powerup.Kind.PADDLE_FORTRESS,
		Powerup.Kind.MULTIBALL,
		Powerup.Kind.HYPER
	]

	for pt in coords:
		var pos := center + Vector2(pt.x * 68.0, pt.y * 42.0)
		var dist := absf(pt.x) + absf(pt.y)
		var col := Color.from_hsv(fmod(dist * 0.15 + 0.5, 1.0), 0.85, 1.0)
		var hp := 3 if dist <= 1.0 else (2 if dist == 2.0 else 1)
		var reward: Powerup.Kind = rewards[randi() % rewards.size()]
		_spawn_brick(pos, brick_size, hp, col, reward)

func spawn_boss_bastion(boss_color: Color) -> void:
	clear_all_bricks()
	var center := Vector2(1380, 540) # Spawns in front of the boss paddle
	var brick_w := 60.0
	var brick_h := 40.0
	var gap_y := 18.0

	var rewards := [
		Powerup.Kind.PADDLE_FORTRESS,
		Powerup.Kind.BALL_STAR,
		Powerup.Kind.STUN_ARM,
		Powerup.Kind.HYPER,
		Powerup.Kind.FIREBALL
	]

	for r in range(-4, 5):
		var pos := center + Vector2(sin(float(r) * 0.4) * 45.0, float(r) * (brick_h + gap_y))
		var reward: Powerup.Kind = rewards[randi() % rewards.size()]
		_spawn_brick(pos, Vector2(brick_w, brick_h), 2, boss_color, reward)

func _spawn_brick(pos: Vector2, size: Vector2, hp: int, col: Color, reward: Powerup.Kind) -> void:
	var brick = preload("res://src/actors/brick.gd").new()
	add_child(brick)
	brick.setup(pos, size, hp, col, reward, fluid_sim, vfx_mgr, audio_mgr)
	brick.destroyed.connect(_on_brick_destroyed)
	_active_bricks.append(brick)

func _on_brick_destroyed(brick: Brick, breaker_id: int, pos: Vector2) -> void:
	_active_bricks.erase(brick)
	brick_shattered.emit(breaker_id, pos)
	if _active_bricks.is_empty():
		matrix_cleared.emit()
		if vfx_mgr != null:
			vfx_mgr.flash_screen(Color.WHITE, 0.4, 0.2)
			vfx_mgr.spawn_shockwave(Vector2(960, 540), Color(1.0, 0.9, 0.3), 640.0, 0.5)
