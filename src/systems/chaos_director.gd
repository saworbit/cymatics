class_name ChaosDirector
extends Node

signal powerup_collected(kind: int, owner_id: int)
signal multiball_started(count: int)

var ball_scene: PackedScene
var fluid_sim: FluidSimulator
var vfx_mgr: VFXManager
var audio_mgr: AudioManager
var game_mgr: GameManager
var paddle_left: Paddle
var paddle_right: Paddle
var primary: Ball
var host: Node2D

var extra_balls: Array[Ball] = []
var live_powerup = null
var _spawn_cd := 2.4
var _hazard_cd := 5.0
var _hyper_time := 0.0

func setup(p_host: Node2D, p_primary: Ball, p_p1: Paddle, p_p2: Paddle, p_gm: GameManager, p_fluid: FluidSimulator, p_vfx: VFXManager, p_audio: AudioManager) -> void:
	host = p_host
	primary = p_primary
	paddle_left = p_p1
	paddle_right = p_p2
	game_mgr = p_gm
	fluid_sim = p_fluid
	vfx_mgr = p_vfx
	audio_mgr = p_audio
	ball_scene = load("res://scenes/ball.tscn")
	if primary != null:
		primary.add_to_group("cymatics_balls")

func _physics_process(delta: float) -> void:
	if _hyper_time > 0.0:
		_hyper_time -= delta
		if _hyper_time <= 0.0:
			Engine.time_scale = 1.0
	_prune_balls()
	if game_mgr == null:
		return
	if game_mgr.current_state != GameManager.State.PLAYING:
		return
	if live_powerup != null and not is_instance_valid(live_powerup):
		live_powerup = null

	_spawn_cd -= delta
	if live_powerup == null and _spawn_cd <= 0.0 and extra_balls.size() < 4:
		_spawn_powerup()
		_spawn_cd = randf_range(5.5, 8.5)

	# Dynamic Hydrodynamic Field Hazards
	if game_mgr.rally_hits >= 4:
		_hazard_cd -= delta
		if _hazard_cd <= 0.0:
			_spawn_fluid_hazard()
			_hazard_cd = randf_range(6.0, 9.5)

func _spawn_fluid_hazard() -> void:
	if fluid_sim == null:
		return
	var hazard_type := randi() % 2
	if hazard_type == 0:
		# Center Arena Vortex
		var vpos := Vector2(randf_range(820.0, 1100.0), randf_range(320.0, 760.0))
		var swirl := randf_range(4.0, 7.0) * (1.0 if randf() > 0.5 else -1.0)
		var col := Color(0.7, 0.4, 1.0, 0.6)
		fluid_sim.inject_vortex(vpos, swirl, 140.0, col)
		if vfx_mgr != null:
			vfx_mgr.spawn_shockwave(vpos, col, 320.0, 0.5)
			vfx_mgr.spawn_hit_burst(vpos, col, 1.4)
		if game_mgr != null:
			game_mgr.callout.emit("VORTEX", col)
		if audio_mgr != null:
			audio_mgr.trigger_sting(340.0, 0.35)
	else:
		# Mid-court Hydrodynamic Cross-Current
		var cpos := Vector2(960.0, randf_range(280.0, 800.0))
		var cdir := Vector2(0.0, 1.0 if randf() > 0.5 else -1.0) * randf_range(1600.0, 2400.0)
		var col := Color(0.2, 0.9, 1.0, 0.55)
		fluid_sim.inject_force(cpos, cdir, 160.0, col)
		if vfx_mgr != null:
			vfx_mgr.spawn_shockwave(cpos, col, 280.0, 0.4)
		if game_mgr != null:
			game_mgr.callout.emit("CURRENT", col)
		if audio_mgr != null:
			audio_mgr.trigger_sting(480.0, 0.3)

func _spawn_powerup() -> void:
	var p = preload("res://src/actors/powerup.gd").new()
	var PowerupScript = preload("res://src/actors/powerup.gd")
	var kinds: Array = [
		PowerupScript.Kind.MULTIBALL,
		PowerupScript.Kind.MULTIBALL,
		PowerupScript.Kind.GROW,
		PowerupScript.Kind.TINY,
		PowerupScript.Kind.STUN_ARM,
		PowerupScript.Kind.STUN_ARM,
		PowerupScript.Kind.MAGNET,
		PowerupScript.Kind.FIREBALL,
		PowerupScript.Kind.HYPER,
	]
	var kind: int = kinds[randi() % kinds.size()]
	var pos := Vector2(randf_range(720.0, 1200.0), randf_range(220.0, 860.0))
	p.collected.connect(_on_powerup_collected)
	live_powerup = p
	_attach_powerup.call_deferred(p, kind, pos)

func _attach_powerup(p, kind: int, pos: Vector2) -> void:
	if host == null or not is_instance_valid(p):
		return
	host.add_child(p)
	p.setup(kind, pos)
	var PowerupScript = preload("res://src/actors/powerup.gd")
	if vfx_mgr != null:
		vfx_mgr.spawn_hit_burst(p.global_position, PowerupScript.COLORS[kind], 1.4)

func _on_powerup_collected(kind: int, hitter_id: int, ball: Ball) -> void:
	live_powerup = null
	_spawn_cd = randf_range(3.5, 5.5)
	var PowerupScript = preload("res://src/actors/powerup.gd")
	var owner_id := hitter_id
	if owner_id < 0:
		owner_id = 0 if ball.velocity.x > 0.0 else 1
	var self_p := paddle_left if owner_id == 0 else paddle_right
	var foe_p := paddle_right if owner_id == 0 else paddle_left
	var label = PowerupScript.LABELS.get(kind, "POWER")
	var color: Color = PowerupScript.COLORS.get(kind, Color.WHITE)
	if game_mgr != null:
		game_mgr.callout.emit(str(label) + "!", color)
	if audio_mgr != null:
		audio_mgr.trigger_sting(660.0, 0.45)
	if vfx_mgr != null:
		vfx_mgr.spawn_shockwave(ball.global_position, color, 420.0, 0.35)
		vfx_mgr.flash_screen(color, 0.16, 0.12)

	match kind:
		PowerupScript.Kind.MULTIBALL:
			_split_multiball.call_deferred(ball)
		PowerupScript.Kind.GROW:
			if self_p:
				self_p.apply_size_mod(1.55, 8.0)
		PowerupScript.Kind.TINY:
			if foe_p:
				foe_p.apply_size_mod(0.62, 8.0)
		PowerupScript.Kind.STUN_ARM:
			if self_p:
				self_p.arm_cannon(10.0)
		PowerupScript.Kind.MAGNET:
			if self_p:
				self_p.apply_magnet(8.0)
		PowerupScript.Kind.FIREBALL:
			ball.ignite_fireball(8.0)
			for extra in extra_balls:
				if is_instance_valid(extra):
					extra.ignite_fireball(8.0)
		PowerupScript.Kind.HYPER:
			_hyper_time = 4.0
			Engine.time_scale = 1.18
			if self_p:
				self_p.apply_size_mod(1.2, 4.0)
			if ball:
				ball.ignite_fireball(4.0)
	powerup_collected.emit(kind, owner_id)

func _split_multiball(source: Ball) -> void:
	if extra_balls.size() >= 4 or ball_scene == null:
		return
	var n := 2 if extra_balls.is_empty() else 1
	for i in range(n):
		if extra_balls.size() >= 4:
			break
		var clone: Ball = ball_scene.instantiate()
		clone.is_clone = true
		host.add_child(clone)
		clone.setup_dependencies(fluid_sim, vfx_mgr, audio_mgr)
		clone.set_paddles(paddle_left, paddle_right)
		var spread := Vector2(source.velocity.x, source.velocity.y + (i * 2 - 1) * 420.0)
		if spread.length() < 200.0:
			spread = Vector2(source.velocity.x, (i * 2 - 1) * 500.0)
		clone.reset_ball(source.global_position + Vector2(0, (i * 2 - 1) * 18.0), spread.normalized())
		clone.velocity = spread.normalized() * maxf(source.velocity.length() * 0.92, clone.min_speed)
		clone.rally_hits = source.rally_hits
		clone.last_hitter_id = source.last_hitter_id
		clone.add_to_group("cymatics_balls")
		clone.goal_reached.connect(_on_clone_goal)
		clone.hit_paddle.connect(func(p: Paddle, spd: float, perf: bool):
			if game_mgr != null:
				game_mgr._on_ball_hit_paddle(p, spd, perf)
		)
		extra_balls.append(clone)
	multiball_started.emit(extra_balls.size() + 1)
	if source:
		source.emote(2, 1.0, "FRIENDS")
	if game_mgr != null:
		game_mgr.callout.emit("MULTIBALL x%d" % (extra_balls.size() + 1), Color(1.0, 0.9, 0.3))
	if vfx_mgr != null:
		vfx_mgr.apply_camera_kick(Vector2.UP, 1.1)
		vfx_mgr.spawn_hit_burst(source.global_position, Color(1.0, 0.92, 0.3), 2.6)

func _on_clone_goal(side: int) -> void:
	if game_mgr != null:
		game_mgr.on_clone_goal(side)

func _prune_balls() -> void:
	var kept: Array[Ball] = []
	for b in extra_balls:
		if is_instance_valid(b) and not b.is_scored:
			kept.append(b)
		elif is_instance_valid(b) and b.is_scored:
			b.queue_free()
	extra_balls = kept

func active_balls() -> Array[Ball]:
	var out: Array[Ball] = []
	if primary != null and is_instance_valid(primary) and not primary.is_scored:
		out.append(primary)
	for b in extra_balls:
		if is_instance_valid(b) and not b.is_scored:
			out.append(b)
	return out

func threat_ball_for(p: Paddle) -> Ball:
	var best: Ball = primary
	var best_score := -99999.0
	for b in active_balls():
		var toward := 1.0 if p.player_id == 1 else -1.0
		var incoming := b.velocity.x * toward
		var dist := absf(b.global_position.x - p.global_position.x)
		var score := incoming * 2.0 - dist * 0.01
		if incoming > 0.0:
			score += 400.0
		if score > best_score:
			best_score = score
			best = b
	return best

func clear_point() -> void:
	if live_powerup != null and is_instance_valid(live_powerup):
		live_powerup.set_deferred("monitoring", false)
		live_powerup.queue_free()
	live_powerup = null
	for b in extra_balls:
		if is_instance_valid(b):
			b.queue_free()
	extra_balls.clear()
	_spawn_cd = 2.8
	_hyper_time = 0.0
	if Engine.time_scale > 1.0:
		Engine.time_scale = 1.0
	if primary != null:
		primary.fireball_time = 0.0
	if paddle_left:
		paddle_left.clear_mods()
	if paddle_right:
		paddle_right.clear_mods()
