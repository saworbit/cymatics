class_name Ball
extends CharacterBody2D

signal hit_paddle(paddle: Paddle, hit_speed: float, perfect: bool)
signal hit_wall(pos: Vector2, hit_speed: float)
signal goal_reached(player_side: int) # 0 = Left (P2 scores), 1 = Right (P1 scores)
signal overdrive_entered
signal cymatic_lock_entered
signal near_miss(side: int, pos: Vector2)
signal served(dir: Vector2)
signal carom_hit(cut: float, new_spin: float)

enum Shape { ROUND, TRIANGLE, CUBE, STAR, RUGBY }

@export var radius := 18.0
@export var base_speed := 820.0
@export var max_speed := 2100.0
@export var min_speed := 560.0
@export var bounce_damping := 1.0
const MAGNUS_ACCEL := 620.0

var spin := 0.0
var rally_hits := 0
var is_in_overdrive := false
var is_in_cymatic_lock := false
var is_scored := false
var is_serving := false
var is_clone := false
var fireball_time := 0.0
var shape_type: Shape = Shape.ROUND
var shape_time := 0.0
var shape_angle := 0.0
var serve_paddle: Paddle = null
var last_hitter_id := -1
var touch_mask := 0
var last_hit_was_perfect := false
var last_hit_speed := 0.0

var fluid_sim: FluidSimulator
var vfx_mgr: VFXManager
var audio_mgr: AudioManager
var game_mgr: GameManager
var paddle_left: Paddle
var paddle_right: Paddle

var _trail: Line2D
var _trail_core: Line2D
var _trail_pts: Array[Vector2] = []
var _squash := Vector2.ONE
var _orb_mat: ShaderMaterial
var _crossed_left := false
var _crossed_right := false
var _serve_bob := 0.0
var _ghost_cd := 0.0
var _sparks: GPUParticles2D
var face

@onready var visual_core: ColorRect = $VisualCore
@onready var visual_corona: ColorRect = $VisualCorona
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func setup_dependencies(p_fluid_sim: FluidSimulator, p_vfx: VFXManager, p_audio: AudioManager, p_game: GameManager = null) -> void:
	fluid_sim = p_fluid_sim
	vfx_mgr = p_vfx
	audio_mgr = p_audio
	game_mgr = p_game

func set_paddles(p_left: Paddle, p_right: Paddle) -> void:
	paddle_left = p_left
	paddle_right = p_right

func _ready() -> void:
	z_index = 12
	add_to_group("cymatics_balls")
	_setup_orb()
	_setup_trail()
	_setup_sparks()
	_setup_face()
	if collision_shape and collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = radius
	collision_mask = collision_mask | 4

func _exit_tree() -> void:
	if _trail != null and is_instance_valid(_trail):
		_trail.queue_free()
	if _trail_core != null and is_instance_valid(_trail_core):
		_trail_core.queue_free()

func _setup_orb() -> void:
	if visual_core != null:
		visual_core.visible = false
	if visual_corona == null:
		return
	visual_corona.offset_left = -70.0
	visual_corona.offset_top = -70.0
	visual_corona.offset_right = 70.0
	visual_corona.offset_bottom = 70.0
	visual_corona.pivot_offset = Vector2(70, 70)
	visual_corona.z_index = 2
	visual_corona.color = Color(1, 1, 1, 0)
	visual_corona.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_corona.clip_contents = true
	_orb_mat = ShaderMaterial.new()
	_orb_mat.shader = load("res://shaders/vfx/orb.gdshader")
	visual_corona.material = _orb_mat

func _setup_trail() -> void:
	_trail = Line2D.new()
	_trail.z_index = 10
	_trail.width = 54.0
	_trail.antialiased = true
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	var strip := Image.create(64, 8, false, Image.FORMAT_RGBA8)
	strip.fill(Color.WHITE)
	_trail.texture = ImageTexture.create_from_image(strip)
	var comet := ShaderMaterial.new()
	comet.shader = load("res://shaders/vfx/comet_trail.gdshader")
	_trail.material = comet
	var wcurve := Curve.new()
	wcurve.add_point(Vector2(0.0, 0.08))
	wcurve.add_point(Vector2(0.55, 0.55))
	wcurve.add_point(Vector2(1.0, 1.0))
	_trail.width_curve = wcurve
	add_child(_trail)
	_trail.top_level = true

	_trail_core = Line2D.new()
	_trail_core.z_index = 11
	_trail_core.width = 16.0
	_trail_core.antialiased = true
	_trail_core.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail_core.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail_core.end_cap_mode = Line2D.LINE_CAP_ROUND
	var core_mat := CanvasItemMaterial.new()
	core_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_trail_core.material = core_mat
	var core_grad := Gradient.new()
	core_grad.colors = PackedColorArray([
		Color(1.0, 0.55, 0.05, 0.0),
		Color(1.0, 0.85, 0.35, 0.55),
		Color(1.0, 1.0, 1.0, 1.0)
	])
	_trail_core.gradient = core_grad
	var core_w := Curve.new()
	core_w.add_point(Vector2(0.0, 0.05))
	core_w.add_point(Vector2(0.75, 0.45))
	core_w.add_point(Vector2(1.0, 1.0))
	_trail_core.width_curve = core_w
	add_child(_trail_core)
	_trail_core.top_level = true

func _setup_sparks() -> void:
	_sparks = GPUParticles2D.new()
	_sparks.z_index = 11
	_sparks.amount = 28
	_sparks.lifetime = 0.35
	_sparks.explosiveness = 0.0
	_sparks.local_coords = false
	_sparks.texture = _spark_texture()
	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 6.0
	mat.direction = Vector3(-1, 0, 0)
	mat.spread = 28.0
	mat.initial_velocity_min = 40.0
	mat.initial_velocity_max = 160.0
	mat.gravity = Vector3(0, 0, 0)
	mat.scale_min = 0.25
	mat.scale_max = 0.7
	mat.color = Color(1.0, 0.9, 0.45, 1.0)
	_sparks.process_material = mat
	add_child(_sparks)

static var _shared_spark_tex: Texture2D = null

func _spark_texture() -> Texture2D:
	if _shared_spark_tex != null:
		return _shared_spark_tex
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	for y in 24:
		for x in 24:
			var p := Vector2(x - 11.5, y - 11.5)
			var d := p.length() / 12.0
			var a := exp(-d * d * 7.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_shared_spark_tex = ImageTexture.create_from_image(img)
	return _shared_spark_tex

func _setup_face() -> void:
	face = preload("res://src/actors/character_face.gd").new()
	add_child(face)
	face.setup(Vector2(84, 84), false, 0.08)
	face.position = Vector2(0, 4)
	face.z_index = 15
	if is_clone:
		face.set_mood(2, 1.2)
		face.bark("WHEE")

func emote(mood: int, duration: float = 0.7, line: String = "") -> void:
	if face == null:
		return
	face.set_mood(mood, duration)
	if line != "":
		face.bark(line)

func ignite_fireball(duration: float) -> void:
	fireball_time = maxf(fireball_time, duration)
	emote(9, duration, "HOT")

func mutate_shape(new_shape: Shape, duration: float) -> void:
	shape_type = new_shape
	shape_time = maxf(shape_time, duration)
	_squash = Vector2(1.55, 0.65)
	var col := Color(1.0, 0.9, 0.3)
	var mood_line := "MORPH"
	match new_shape:
		Shape.TRIANGLE:
			col = Color(0.3, 1.0, 0.8)
			mood_line = "PRISM"
		Shape.CUBE:
			col = Color(0.9, 0.4, 1.0)
			mood_line = "CUBE"
		Shape.STAR:
			col = Color(1.0, 0.85, 0.15)
			mood_line = "STAR"
		Shape.RUGBY:
			col = Color(1.0, 0.35, 0.65)
			mood_line = "BLOB"
	if vfx_mgr != null:
		vfx_mgr.spawn_hit_burst(global_position, col, 1.8)
		vfx_mgr.spawn_shockwave(global_position, col, 320.0, 0.35)
	if audio_mgr != null:
		audio_mgr.trigger_sting(580.0, 0.4)
	emote(3, duration, mood_line)

func hold_for_serve(p: Paddle) -> void:
	is_serving = true
	is_scored = false
	visible = true
	serve_paddle = p
	velocity = Vector2.ZERO
	if p != null and is_instance_valid(p):
		var fwd := Vector2.RIGHT if p.player_id == 0 else Vector2.LEFT
		global_position = p.global_position + fwd * 78.0
	spin = 0.0
	rally_hits = 0
	is_in_overdrive = false
	is_in_cymatic_lock = false
	last_hitter_id = -1
	touch_mask = 0
	last_hit_was_perfect = false
	_crossed_left = false
	_crossed_right = false
	_trail_pts.clear()
	_squash = Vector2.ONE
	fireball_time = 0.0
	shape_type = Shape.ROUND
	shape_time = 0.0
	shape_angle = 0.0
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	_update_visuals()

func launch_serve(dir: Vector2, spd: float = -1.0) -> void:
	if not is_serving:
		return
	is_serving = false
	serve_paddle = null
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	var launch_speed := base_speed if spd < 0.0 else spd
	velocity = dir.normalized() * launch_speed
	served.emit(dir)
	if vfx_mgr != null:
		vfx_mgr.spawn_hit_burst(global_position, Color(1.0, 0.9, 0.4), 1.6)
		vfx_mgr.spawn_shockwave(global_position, Color(1.0, 0.95, 0.6), 280.0, 0.28)
		vfx_mgr.apply_camera_kick(dir, 0.7)
	if audio_mgr != null:
		audio_mgr.trigger_impact(launch_speed, global_position, true)

func reset_ball(start_pos: Vector2, dir: Vector2) -> void:
	is_serving = false
	is_scored = false
	visible = true
	serve_paddle = null
	global_position = start_pos
	velocity = dir.normalized() * base_speed
	spin = 0.0
	rally_hits = 0
	is_in_overdrive = false
	is_in_cymatic_lock = false
	last_hitter_id = -1
	touch_mask = 0
	_crossed_left = false
	_crossed_right = false
	_trail_pts.clear()
	_squash = Vector2.ONE
	fireball_time = 0.0
	shape_type = Shape.ROUND
	shape_time = 0.0
	shape_angle = 0.0
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	_update_visuals()

func _physics_process(delta: float) -> void:
	if game_mgr != null and game_mgr.current_state == GameManager.State.MENU:
		velocity = Vector2.ZERO
		visible = false
		return

	if is_scored:
		return

	if fireball_time > 0.0:
		fireball_time -= delta

	if shape_time > 0.0:
		shape_time -= delta
		if shape_time <= 0.0 and shape_type != Shape.ROUND:
			shape_type = Shape.ROUND
			_squash = Vector2(1.3, 0.7)
	shape_angle += (spin * 14.0 + velocity.x * 0.003) * delta

	if is_serving:
		_process_serve(delta)
		_update_visuals()
		_update_trail(false)
		if face:
			face.maybe_mood(1, 0.2)
			if serve_paddle:
				face.look_at_point(global_position, Vector2(960, serve_paddle.global_position.y))
		return

	_integrate_flight(delta)
	_handle_walls_and_goals()
	_check_near_miss()
	_update_trail(true)
	_spawn_afterimage(delta)
	_update_face()
	_squash = _squash.lerp(Vector2.ONE, clampf(delta * 14.0, 0.0, 1.0))

	if audio_mgr != null:
		var curl_val := fluid_sim.sample_curl_at(global_position) if fluid_sim else 0.0
		audio_mgr.update_ball_state(velocity.length(), curl_val, global_position.x / 1920.0)

	_update_visuals()

func _process_serve(delta: float) -> void:
	_serve_bob += delta * 7.0
	if serve_paddle != null and is_instance_valid(serve_paddle):
		var fwd := Vector2.RIGHT if serve_paddle.player_id == 0 else Vector2.LEFT
		global_position = serve_paddle.global_position + fwd * 78.0
		global_position.y += sin(_serve_bob) * 7.0
	else:
		global_position = Vector2(960, 540 + sin(_serve_bob) * 10.0)

func _integrate_flight(delta: float) -> void:
	var speed := velocity.length()
	if speed < 1.0:
		velocity = Vector2.RIGHT * min_speed
		speed = min_speed

	# Continuous Hydrodynamic 2-Way Coupling
	if fluid_sim != null:
		var fluid_vel := fluid_sim.sample_velocity_at(global_position)
		var curl := fluid_sim.sample_curl_at(global_position)
		var heading := velocity / speed

		# Ride currents: strong sideways deflection, modest aligned boost. Never steal speed.
		var aligned := fluid_vel.dot(heading)
		var lateral := fluid_vel - heading * aligned
		velocity += lateral * (3.4 * delta)
		if aligned > 40.0:
			velocity += heading * (minf(aligned, 1600.0) * 0.28 * delta)
		elif aligned < -80.0:
			velocity += heading * (aligned * 0.08 * delta)

		spin = clampf(spin + curl * (0.85 * delta), -1.0, 1.0)
		spin = move_toward(spin, 0.0, delta * 0.12)
		var mag_dir := Vector2(-heading.y, heading.x)
		var lift_mult := 1.75 if shape_type == Shape.STAR else 1.0
		velocity += mag_dir * (spin * MAGNUS_ACCEL * lift_mult * delta)
		if absf(curl) > 1.4:
			velocity += mag_dir * (signf(curl) * 280.0 * delta)

		# 3. Bow shock and fluid wake injection
		var wake_color := Color(1.0, 0.85, 0.2, 0.85)
		if shape_type == Shape.TRIANGLE:
			wake_color = Color(0.3, 1.0, 0.8, 0.9)
		elif shape_type == Shape.CUBE:
			wake_color = Color(0.9, 0.4, 1.0, 0.9)
		elif shape_type == Shape.STAR:
			wake_color = Color(1.0, 0.85, 0.15, 0.95)
		elif shape_type == Shape.RUGBY:
			wake_color = Color(1.0, 0.35, 0.65, 0.9)
		elif fireball_time > 0.0:
			wake_color = Color(1.0, 0.25, 0.04, 1.0)
		elif is_in_cymatic_lock:
			wake_color = Color(1.0, 1.0, 1.0, 1.0)
		elif is_in_overdrive:
			wake_color = Color(1.0, 0.28, 0.05, 0.95)

		if speed > 400.0:
			var wake_force := heading * (speed * 0.9)
			var wake_rad := radius * (2.2 + clampf((speed - 500.0) / 900.0, 0.0, 1.8))
			fluid_sim.inject_force(global_position, wake_force, wake_rad, wake_color)

			# Fast ball generates flanking von Kármán vortex eddies
			if speed > 850.0 or shape_type == Shape.STAR:
				var flank_offset := mag_dir * (radius * 1.5)
				fluid_sim.inject_vortex(global_position + flank_offset, 3.5 * (speed / 1000.0), wake_rad * 0.8, wake_color)
				fluid_sim.inject_vortex(global_position - flank_offset, -3.5 * (speed / 1000.0), wake_rad * 0.8, wake_color)
		else:
			fluid_sim.inject_dye(global_position, wake_color, radius * 2.0)

	speed = velocity.length()
	var floor_speed := min_speed + minf(rally_hits * 16.0, 140.0)
	if is_in_overdrive:
		floor_speed += 70.0
	if is_in_cymatic_lock:
		floor_speed += 140.0
	speed = clampf(speed, floor_speed, _rally_speed_cap())
	velocity = velocity.normalized() * speed

	# Stretch along velocity
	var stretch := clampf((speed - 500.0) / 1400.0, 0.0, 1.0)
	var target_squash := Vector2(1.0 + stretch * 0.55, 1.0 - stretch * 0.28)
	_squash = _squash.lerp(target_squash, clampf(delta * 10.0, 0.0, 1.0))

	var collision := move_and_collide(velocity * delta)
	if collision != null:
		var collider := collision.get_collider()
		if collider is Paddle:
			_handle_paddle_collision(collider, collision.get_normal())
		elif collider is Powerup:
			_handle_powerup_carom(collider as Powerup, collision)
		elif collider.has_method("on_ball_hit"):
			# Brick matrix interaction
			if velocity.dot(collision.get_normal()) < 0.0:
				collider.on_ball_hit(self, collision.get_normal())
		else:
			var normal := collision.get_normal()
			if shape_type == Shape.TRIANGLE:
				var facet_deflect := Vector2(cos(shape_angle), sin(shape_angle)) * 0.24
				normal = (normal + facet_deflect).normalized()
				if fluid_sim != null:
					fluid_sim.inject_vortex(collision.get_position(), 4.0 * signf(spin), 120.0, Color(0.3, 1.0, 0.8, 0.6))
			elif shape_type == Shape.CUBE:
				_squash = Vector2(0.5, 1.5)
			elif shape_type == Shape.STAR:
				spin = clampf(spin * -1.2 + randf_range(-0.3, 0.3), -1.0, 1.0)
			elif shape_type == Shape.RUGBY:
				_squash = Vector2(1.6, 0.5)

			velocity = velocity.bounce(normal) * bounce_damping
			hit_wall.emit(collision.get_position(), velocity.length())
			_squash = Vector2(0.72, 1.28)
			if vfx_mgr != null:
				vfx_mgr.spawn_shockwave(collision.get_position(), Color(1.0, 1.0, 1.0, 0.8), 160.0, 0.2)
				vfx_mgr.apply_camera_kick(collision.get_normal(), 0.25)
			if audio_mgr != null:
				audio_mgr.trigger_impact(velocity.length() * 0.7, collision.get_position(), false)
			emote(4, 0.35, "OW")

func _handle_walls_and_goals() -> void:
	if global_position.y < 58.0:
		global_position.y = 58.0
		velocity.y = absf(velocity.y) * bounce_damping
		_squash = Vector2(1.25, 0.7)
	elif global_position.y > 1022.0:
		global_position.y = 1022.0
		velocity.y = -absf(velocity.y) * bounce_damping
		_squash = Vector2(1.25, 0.7)

	if not is_scored:
		if global_position.x < 22.0:
			_score_goal(0)
		elif global_position.x > 1898.0:
			_score_goal(1)

func _update_face() -> void:
	if face == null:
		return
	if velocity.length() > 40.0:
		var ahead := global_position + velocity.normalized() * 220.0
		face.look_at_point(global_position, ahead)
	if fireball_time > 0.0:
		face.maybe_mood(9, 0.2)
	elif is_in_cymatic_lock or is_in_overdrive:
		face.maybe_mood(9, 0.2)

func _score_goal(side: int) -> void:
	is_scored = true
	last_hit_speed = velocity.length()
	emote(3, 0.8, "BOOM")
	velocity = Vector2.ZERO
	visible = true
	global_position.x = clampf(global_position.x, 36.0, 1884.0)
	_trail_pts.clear()
	if _trail:
		_trail.clear_points()
	goal_reached.emit(side)

func _check_near_miss() -> void:
	if paddle_left != null and velocity.x < 0.0 and global_position.x < paddle_left.global_position.x - 8.0:
		if not _crossed_left:
			_crossed_left = true
			var thresh_l := 70.0 * paddle_left.size_mod + 45.0
			if absf(global_position.y - paddle_left.global_position.y) < thresh_l:
				near_miss.emit(0, global_position)
	elif velocity.x > 0.0:
		_crossed_left = false

	if paddle_right != null and velocity.x > 0.0 and global_position.x > paddle_right.global_position.x + 8.0:
		if not _crossed_right:
			_crossed_right = true
			var thresh_r := 70.0 * paddle_right.size_mod + 45.0
			if absf(global_position.y - paddle_right.global_position.y) < thresh_r:
				near_miss.emit(1, global_position)
	elif velocity.x < 0.0:
		_crossed_right = false

func magnus_accel(p_vel: Vector2 = Vector2.ZERO, p_spin: float = INF) -> Vector2:
	var vel := velocity if p_vel == Vector2.ZERO else p_vel
	var s := spin if p_spin == INF else p_spin
	var spd := vel.length()
	if spd < 1.0:
		return Vector2.ZERO
	var heading := vel / spd
	return Vector2(-heading.y, heading.x) * (s * MAGNUS_ACCEL)

func resolve_carom(orb: Powerup, bpos: Vector2, bvel: Vector2, bspin: float) -> Dictionary:
	var empty := {
		"valid": false,
		"n": Vector2.RIGHT,
		"cut": 0.0,
		"closing": 0.0,
		"ball_vel": bvel,
		"ball_spin": bspin,
		"orb_impulse": Vector2.ZERO,
	}
	if orb == null:
		return empty
	var n := orb.global_position - bpos
	if n.length_squared() < 0.0001:
		n = bvel.normalized() if bvel.length_squared() > 1.0 else Vector2.RIGHT
	n = n.normalized()
	var v_rel := bvel - orb.drift_velocity
	var closing := v_rel.dot(n)
	if closing < 8.0:
		return empty
	var heading := v_rel.normalized() if v_rel.length_squared() > 1.0 else n
	var tangent := Vector2(-n.y, n.x)
	var cut := heading.x * n.y - heading.y * n.x
	var m1 := 1.0
	var m2 := orb.MASS
	var restitution := 0.78
	var impulse := (1.0 + restitution) * maxf(closing, 80.0) / ((1.0 / m1) + (1.0 / m2))
	var new_vel := bvel - n * (impulse / m1) + tangent * (cut * closing * 0.22)
	var spd := new_vel.length()
	if spd < 1.0:
		new_vel = -n * min_speed
	else:
		new_vel = new_vel.normalized() * clampf(spd, min_speed * 0.82, _rally_speed_cap())
	var english := clampf(cut * 1.55 + bspin * 0.18, -1.0, 1.0)
	var orb_impulse := n * (impulse / m2) + tangent * (cut * impulse / m2 * 0.28)
	return {
		"valid": true,
		"n": n,
		"cut": cut,
		"closing": closing,
		"ball_vel": new_vel,
		"ball_spin": english,
		"orb_impulse": orb_impulse,
	}

func preview_powerup_carom(orb: Powerup) -> Dictionary:
	var miss := { "hit": false, "t": 0.0, "velocity": velocity, "spin": spin, "orb_velocity": Vector2.ZERO }
	if orb == null or not is_instance_valid(orb):
		return miss
	var w := global_position - orb.global_position
	var v := velocity - orb.drift_velocity
	var a := v.dot(v)
	if a < 4.0:
		return miss
	var t := -w.dot(v) / a
	if t < 0.0 or t > 1.35:
		return miss
	var closest := w + v * t
	if closest.length() > radius + orb.RADIUS + 10.0:
		return miss
	var at := global_position + velocity * t
	var solved := resolve_carom(orb, at, velocity, spin)
	if not solved["valid"]:
		return miss
	return {
		"hit": true,
		"t": t,
		"velocity": solved["ball_vel"],
		"spin": solved["ball_spin"],
		"orb_velocity": orb.drift_velocity + solved["orb_impulse"],
		"cut": solved["cut"],
		"n": solved["n"],
	}

func _handle_powerup_carom(orb: Powerup, collision: KinematicCollision2D = null) -> void:
	if orb == null or not orb.can_carom():
		return
	var bpos := global_position
	if collision != null:
		bpos = collision.get_position() - (orb.global_position - global_position).normalized() * radius
	var solved := resolve_carom(orb, bpos, velocity, spin)
	if not solved["valid"]:
		return
	velocity = solved["ball_vel"]
	spin = solved["ball_spin"]
	orb.apply_carom(solved["orb_impulse"], solved["n"])
	global_position -= solved["n"] * 12.0
	_squash = Vector2(0.7, 1.25)
	var hit_pos := collision.get_position() if collision != null else global_position
	if fluid_sim != null:
		fluid_sim.inject_shockwave(hit_pos, solved["n"], 900.0, Color(1.0, 0.95, 0.7, 0.7))
		fluid_sim.inject_vortex(hit_pos, solved["ball_spin"] * 5.0, 70.0, Color(1.0, 0.9, 0.4, 0.55))
	if vfx_mgr != null:
		vfx_mgr.apply_camera_kick(solved["n"], 0.22)
	if audio_mgr != null:
		audio_mgr.trigger_impact(solved["closing"], hit_pos, false)
	carom_hit.emit(solved["cut"], solved["ball_spin"])
	if absf(solved["cut"]) > 0.32:
		emote(2, 0.3, "CUT")
	else:
		emote(2, 0.25, "KNOCK")

func _handle_paddle_collision(paddle: Paddle, _normal: Vector2) -> void:
	var behind := false
	if paddle.player_id == 0:
		behind = global_position.x < paddle.global_position.x - 10.0
	else:
		behind = global_position.x > paddle.global_position.x + 10.0

	# Ignore only when the ball is in front and already leaving. A backhand still counts.
	if not behind:
		if paddle.player_id == 0 and velocity.x > 40.0:
			return
		elif paddle.player_id == 1 and velocity.x < -40.0:
			return

	rally_hits += 1
	last_hitter_id = paddle.player_id
	touch_mask |= (1 << paddle.player_id)
	if paddle.player_id == 0:
		_crossed_left = false
		global_position.x = paddle.global_position.x + 36.0 if behind else maxf(global_position.x, paddle.global_position.x + 28.0)
	else:
		_crossed_right = false
		global_position.x = paddle.global_position.x - 36.0 if behind else minf(global_position.x, paddle.global_position.x - 28.0)

	var hit_offset := clampf((global_position.y - paddle.global_position.y) / 70.0, -1.0, 1.0)
	var forward_dir := Vector2.RIGHT if paddle.player_id == 0 else Vector2.LEFT
	var out_dir := forward_dir

	# Paddle Shape Mutator Deflections
	if paddle.shape_type == Paddle.Shape.SCOOP:
		hit_offset *= 0.32
		out_dir.y = hit_offset * 0.7
	elif paddle.shape_type == Paddle.Shape.WEDGE:
		var sgn := signf(hit_offset) if absf(hit_offset) > 0.05 else (1.0 if randf() > 0.5 else -1.0)
		out_dir.y = sgn * (0.82 + absf(hit_offset) * 0.35)
	elif paddle.shape_type == Paddle.Shape.FORK:
		if absf(hit_offset) < 0.28:
			out_dir.y = 0.0
		else:
			out_dir.y = signf(hit_offset) * 0.95
	else:
		out_dir.y = hit_offset * 0.95

	out_dir += paddle.velocity * 0.0009
	out_dir = out_dir.normalized()

	var incoming := maxf(velocity.length(), min_speed)
	var speed_boost := 1.045 + minf(rally_hits * 0.012, 0.22)
	if is_in_overdrive:
		speed_boost += 0.03
	if is_in_cymatic_lock:
		speed_boost += 0.05
	if paddle.shape_type == Paddle.Shape.SCOOP:
		speed_boost += 0.08
	elif paddle.shape_type == Paddle.Shape.FORTRESS:
		speed_boost += 0.18
	elif paddle.shape_type == Paddle.Shape.FORK and absf(hit_offset) < 0.28:
		speed_boost += 0.25

	var perfect := paddle.consume_parry()
	last_hit_was_perfect = perfect
	if perfect:
		speed_boost += 0.22
		spin = clampf(-hit_offset * 1.45 + paddle.velocity.y * 0.0045, -1.0, 1.0)
	else:
		spin = clampf(-hit_offset * 1.12 + paddle.velocity.y * 0.003, -1.0, 1.0)

	var bonus_flat := 48.0
	if paddle.shape_type == Paddle.Shape.FORTRESS:
		bonus_flat += 280.0
	var out_speed := minf(incoming * speed_boost + bonus_flat, _rally_speed_cap())
	velocity = out_dir * out_speed
	last_hit_speed = out_speed
	_squash = Vector2(0.55, 1.45)

	if fluid_sim != null:
		var wave_power := 2200.0 if perfect else 1600.0
		if paddle.shape_type == Paddle.Shape.FORTRESS:
			wave_power += 1400.0
		fluid_sim.inject_shockwave(global_position, out_dir, wave_power, paddle.team_color)
		fluid_sim.inject_vortex(global_position, spin * 6.5, 96.0, paddle.team_color)

	if vfx_mgr != null:
		var burst_scale := 2.4 if perfect else (1.7 + minf(rally_hits * 0.08, 1.2))
		vfx_mgr.spawn_hit_burst(global_position, Color.WHITE if perfect else paddle.team_color, burst_scale)
		vfx_mgr.spawn_shockwave(global_position, paddle.team_color, 280.0 if perfect else 200.0, 0.28 if perfect else 0.2)
		vfx_mgr.apply_camera_kick(out_dir, 0.9 if perfect else 0.45 + minf(rally_hits * 0.04, 0.4))
		vfx_mgr.flash_screen(Color.WHITE if perfect else paddle.team_color, 0.22 if perfect else 0.08, 0.09)
		vfx_mgr.apply_hit_stop(0.055 if perfect else 0.028, 0.07 if perfect else 0.12)

	if audio_mgr != null:
		if perfect:
			audio_mgr.trigger_parry(out_speed, global_position)
		else:
			audio_mgr.trigger_impact(out_speed, global_position, true)
		audio_mgr.set_rally(rally_hits)

	paddle.register_hit(perfect, out_speed)
	hit_paddle.emit(paddle, out_speed, perfect)
	if perfect:
		emote(3, 0.6, "OOH")
	else:
		emote(2, 0.4, "BAM")

	if rally_hits == 7 and not is_in_overdrive:
		is_in_overdrive = true
		overdrive_entered.emit()
		emote(9, 1.4, "YEAH")
	elif rally_hits == 11 and not is_in_cymatic_lock:
		is_in_cymatic_lock = true
		cymatic_lock_entered.emit()
		emote(9, 2.0, "LOCK")

func _rally_speed_cap() -> float:
	var cap := base_speed + 120.0 + float(rally_hits) * 85.0
	if is_in_overdrive:
		cap += 220.0
	if is_in_cymatic_lock:
		cap += 380.0
	if fireball_time > 0.0:
		cap += 280.0
	return minf(cap, max_speed)

func apply_impulse(dir: Vector2, amount: float) -> void:
	if is_serving or is_scored:
		return
	velocity += dir.normalized() * amount
	var spd := clampf(velocity.length(), min_speed, _rally_speed_cap())
	velocity = velocity.normalized() * spd

func _update_trail(active: bool) -> void:
	if _trail == null:
		return
	if not active or is_scored or is_serving:
		_trail.clear_points()
		if _trail_core:
			_trail_core.clear_points()
		if _sparks:
			_sparks.emitting = false
		return
	_trail_pts.push_front(global_position)
	var heat := 1.0 if is_in_cymatic_lock else (0.75 if is_in_overdrive else clampf((velocity.length() - 500.0) / 1100.0, 0.25, 1.0))
	if fireball_time > 0.0:
		heat = 1.0
	var max_pts := 22 if heat > 0.7 else 16
	if is_clone:
		max_pts = 12
	if _trail_pts.size() > max_pts:
		_trail_pts.resize(max_pts)
	_trail.clear_points()
	if _trail_core:
		_trail_core.clear_points()
	for p in _trail_pts:
		_trail.add_point(p)
		if _trail_core:
			_trail_core.add_point(p)
	_trail.width = 42.0 + heat * 28.0
	if _trail_core:
		_trail_core.width = 10.0 + heat * 10.0
	if _trail.material is ShaderMaterial:
		(_trail.material as ShaderMaterial).set_shader_parameter("heat", heat)
		(_trail.material as ShaderMaterial).set_shader_parameter("hot_color", Color(1.0, 1.0, 0.85) if fireball_time <= 0.0 else Color(1.0, 0.85, 0.35))
		(_trail.material as ShaderMaterial).set_shader_parameter("cool_color", Color(1.0, 0.45, 0.08) if fireball_time > 0.0 else Color(1.0, 0.7, 0.15))
	if _sparks:
		_sparks.emitting = velocity.length() > 620.0
		_sparks.amount = 18 if is_clone else 28
		var back := -velocity.normalized()
		if _sparks.process_material is ParticleProcessMaterial:
			(_sparks.process_material as ParticleProcessMaterial).direction = Vector3(back.x, back.y, 0)
			(_sparks.process_material as ParticleProcessMaterial).color = Color(1.0, 0.45, 0.08) if fireball_time > 0.0 else Color(1.0, 0.92, 0.5)

func _spawn_afterimage(delta: float) -> void:
	_ghost_cd -= delta
	if _ghost_cd > 0.0 or velocity.length() < 700.0:
		return
	_ghost_cd = 0.045 if fireball_time > 0.0 else 0.07
	var ghost := ColorRect.new()
	ghost.z_index = 9
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.size = Vector2(36, 36)
	ghost.pivot_offset = Vector2(18, 18)
	ghost.global_position = global_position - ghost.pivot_offset
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ghost.material = add_mat
	ghost.color = Color(1.0, 0.55, 0.12, 0.55) if fireball_time > 0.0 else Color(1.0, 0.92, 0.55, 0.45)
	var parent := get_parent()
	if parent:
		parent.add_child(ghost)
		var tw := ghost.create_tween()
		tw.tween_property(ghost, "modulate:a", 0.0, 0.18)
		tw.tween_callback(ghost.queue_free)

func _update_visuals() -> void:
	if visual_corona == null:
		return
	visual_corona.scale = _squash
	visual_corona.rotation = spin * 0.6
	if _orb_mat != null:
		var speed_ratio := clampf((velocity.length() - 500.0) / 1200.0, 0.0, 1.0)
		if is_serving:
			speed_ratio = 0.35 + 0.15 * sin(_serve_bob * 2.0)
		var heat := 1.0 if is_in_overdrive else speed_ratio
		var lock := 1.0 if is_in_cymatic_lock else 0.0
		_orb_mat.set_shader_parameter("heat", heat)
		_orb_mat.set_shader_parameter("lock", lock)
		_orb_mat.set_shader_parameter("fireball", 1.0 if fireball_time > 0.0 else 0.0)
		_orb_mat.set_shader_parameter("shape_type", int(shape_type))
		_orb_mat.set_shader_parameter("shape_angle", shape_angle)
		if shape_type == Shape.TRIANGLE:
			_orb_mat.set_shader_parameter("glow_color", Color(0.25, 1.0, 0.85))
		elif shape_type == Shape.CUBE:
			_orb_mat.set_shader_parameter("glow_color", Color(0.92, 0.35, 1.0))
		elif shape_type == Shape.STAR:
			_orb_mat.set_shader_parameter("glow_color", Color(1.0, 0.88, 0.15))
		elif shape_type == Shape.RUGBY:
			_orb_mat.set_shader_parameter("glow_color", Color(1.0, 0.32, 0.65))
		elif lock > 0.5:
			_orb_mat.set_shader_parameter("glow_color", Color(1.0, 1.0, 1.0))
		elif fireball_time > 0.0 or heat > 0.65:
			_orb_mat.set_shader_parameter("glow_color", Color(1.0, 0.38, 0.06))
		else:
			_orb_mat.set_shader_parameter("glow_color", Color(1.0, 0.88, 0.25))
