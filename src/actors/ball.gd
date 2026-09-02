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
## Ball burst into debris at a goal (VFX hook; audio binds here by name).
signal shattered(pos: Vector2, vel: Vector2)

enum Shape { ROUND, TRIANGLE, CUBE, STAR, RUGBY }

@export var radius := 18.0
@export var base_speed := 820.0
@export var max_speed := 2100.0
@export var min_speed := 560.0
@export var bounce_damping := 0.95
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
## While > 0 the rally speed cap is bypassed (blast/resonance windows). Hard max still applies.
var speed_override_time := 0.0
## Velocity at the moment the ball crossed a goal line (used by the shatter cone).
var goal_velocity := Vector2.ZERO
## Paddle holding this ball in a suction orbit (null when free). While set the
## rally speed floor/cap, fluid coupling and external impulses are bypassed; the
## captor drives `velocity` directly each tick (see Paddle._update_capture).
var captured_by: Paddle = null

var fluid_sim: FluidSimulator
var vfx_mgr: VFXManager
var audio_mgr: AudioManager
var game_mgr: GameManager
var paddle_left: Paddle
var paddle_right: Paddle

var _trail: Line2D
var _trail_core: Line2D
var _trail_pts: Array[Vector2] = []
var _trail_ages: Array[float] = []
var _trail_active := false
var _tick_pos := Vector2.ZERO
var _prev_tick_pos := Vector2.ZERO
var _squash := Vector2.ONE
var _orb_mat: ShaderMaterial
var _crossed_left := false
var _crossed_right := false
var _serve_bob := 0.0
var _ghost_cd := 0.0
var _pulse_cd := 0.0
var _ghost_shader: Shader
var _sparks: GPUParticles2D
var face

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
	_orb_mat = ShaderMaterial.new()
	_orb_mat.shader = load("res://shaders/vfx/orb.gdshader")
	visual_corona.material = _orb_mat

func _setup_trail() -> void:
	_trail = Line2D.new()
	_trail.z_index = 10
	_trail.width = 40.0
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
	# Point 0 is the ball head: wide and bright there, tapering to nothing.
	wcurve.add_point(Vector2(0.0, 1.0))
	wcurve.add_point(Vector2(0.45, 0.55))
	wcurve.add_point(Vector2(1.0, 0.04))
	_trail.width_curve = wcurve
	add_child(_trail)
	_trail.top_level = true

	_trail_core = Line2D.new()
	_trail_core.z_index = 11
	_trail_core.width = 12.0
	_trail_core.antialiased = true
	_trail_core.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail_core.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail_core.end_cap_mode = Line2D.LINE_CAP_ROUND
	var core_mat := CanvasItemMaterial.new()
	core_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_trail_core.material = core_mat
	var core_grad := Gradient.new()
	core_grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 0.85, 0.35, 0.55),
		Color(1.0, 0.55, 0.05, 0.0)
	])
	_trail_core.gradient = core_grad
	var core_w := Curve.new()
	core_w.add_point(Vector2(0.0, 1.0))
	core_w.add_point(Vector2(0.25, 0.45))
	core_w.add_point(Vector2(1.0, 0.05))
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
	captured_by = null
	velocity = Vector2.ZERO
	if p != null and is_instance_valid(p):
		var fwd := Vector2.RIGHT if p.player_id == 0 else Vector2.LEFT
		global_position = p.global_position + fwd * 78.0
		if p.has_method("begin_serve_hold"):
			p.begin_serve_hold()
	spin = 0.0
	rally_hits = 0
	is_in_overdrive = false
	is_in_cymatic_lock = false
	last_hitter_id = -1
	touch_mask = 0
	last_hit_was_perfect = false
	_crossed_left = false
	_crossed_right = false
	_clear_trail()
	_squash = Vector2.ONE
	fireball_time = 0.0
	speed_override_time = 0.0
	shape_type = Shape.ROUND
	shape_time = 0.0
	shape_angle = 0.0
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	reset_physics_interpolation()
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
	captured_by = null
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
	_clear_trail()
	_squash = Vector2.ONE
	fireball_time = 0.0
	speed_override_time = 0.0
	shape_type = Shape.ROUND
	shape_time = 0.0
	shape_angle = 0.0
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	reset_physics_interpolation()
	_update_visuals()

## Match over: stop and hide. Trail and sparks clear.
func settle() -> void:
	is_scored = true
	is_serving = false
	serve_paddle = null
	captured_by = null
	velocity = Vector2.ZERO
	speed_override_time = 0.0
	_clear_trail()
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	visible = false

func _physics_process(delta: float) -> void:
	if game_mgr != null and game_mgr.current_state == GameManager.State.MENU:
		velocity = Vector2.ZERO
		visible = false
		return

	if is_scored:
		_trail_active = false
		return

	if fireball_time > 0.0:
		fireball_time -= delta
	if speed_override_time > 0.0:
		speed_override_time -= delta

	if shape_time > 0.0:
		shape_time -= delta
		if shape_time <= 0.0 and shape_type != Shape.ROUND:
			shape_type = Shape.ROUND
			_squash = Vector2(1.3, 0.7)
	shape_angle += (spin * 14.0 + velocity.x * 0.003) * delta

	if is_serving:
		_process_serve(delta)
		_update_visuals()
		_trail_active = false
		if face:
			face.maybe_mood(1, 0.2)
			if serve_paddle:
				face.look_at_point(global_position, Vector2(960, serve_paddle.global_position.y))
		return

	_integrate_flight(delta)
	_handle_walls_and_goals()
	_check_near_miss()
	_prev_tick_pos = _tick_pos
	_tick_pos = global_position
	_trail_active = not is_scored
	_spawn_afterimage(delta)
	_update_lock_pulse(delta)
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
	if captured_by != null:
		if is_instance_valid(captured_by) and captured_by.captured_ball() == self:
			_integrate_captured(delta)
			return
		captured_by = null
	var speed := velocity.length()
	if speed < 1.0:
		velocity = Vector2.RIGHT * min_speed
		speed = min_speed

	# Continuous Hydrodynamic 2-Way Coupling
	if fluid_sim != null:
		# Clamped: the field is a nudge, never a teleport. Guards the CPU fallback,
		# whose grid accumulates the ball's own wake without projection.
		var field_cap := 2400.0
		if fluid_sim.get("_cpu_fallback"):
			# The CPU grid has no projection and hoards the ball's own wake; keep it advisory.
			field_cap = 120.0
		var fluid_vel := fluid_sim.sample_velocity_at(global_position).limit_length(field_cap)
		var curl := clampf(fluid_sim.sample_curl_at(global_position), -6.0, 6.0)
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
	speed = clampf(speed, floor_speed, _speed_cap())
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
			_bounce_off_wall(collision.get_normal(), collision.get_position())

## Suction orbit: the captor sets `velocity` so the ball lands on its orbit
## point this tick. No speed floor, no fluid coupling, no wall juice; the
## captor's own body is passed through so the orbit can hug the paddle.
func _integrate_captured(delta: float) -> void:
	var speed := velocity.length()
	var heading := velocity / speed if speed > 1.0 else Vector2.RIGHT
	spin = move_toward(spin, 0.0, delta * 0.05)
	if fluid_sim != null:
		fluid_sim.inject_dye(global_position, Color(1.0, 0.9, 0.45, 0.6), radius * 1.6)
		if speed > 200.0:
			fluid_sim.inject_force(global_position, heading * (speed * 0.5), radius * 2.0, Color(1.0, 0.85, 0.3, 0.5))
	var stretch := clampf((speed - 200.0) / 900.0, 0.0, 0.6)
	_squash = _squash.lerp(Vector2(1.0 + stretch * 0.4, 1.0 - stretch * 0.2), clampf(delta * 10.0, 0.0, 1.0))
	var step := velocity * delta
	var collision := move_and_collide(step, true)
	if collision != null and collision.get_collider() == captured_by:
		# Pass through the captor: the orbit is authored around its body.
		global_position += step
		return
	collision = move_and_collide(step)
	if collision != null:
		var collider := collision.get_collider()
		if collider is Powerup:
			_handle_powerup_carom(collider as Powerup, collision)
		elif collider != null and collider.has_method("on_ball_hit"):
			if velocity.dot(collision.get_normal()) < 0.0:
				collider.on_ball_hit(self, collision.get_normal())

## Shared wall contact: shape deflection, damping, and juice (fluid, camera, SFX, signal).
func _bounce_off_wall(surface_normal: Vector2, contact: Vector2) -> void:
	var normal := surface_normal
	if shape_type == Shape.TRIANGLE:
		var facet_deflect := Vector2(cos(shape_angle), sin(shape_angle)) * 0.24
		normal = (normal + facet_deflect).normalized()
		if fluid_sim != null:
			fluid_sim.inject_vortex(contact, 4.0 * signf(spin), 120.0, Color(0.3, 1.0, 0.8, 0.6))
	elif shape_type == Shape.CUBE:
		_squash = Vector2(0.5, 1.5)
	elif shape_type == Shape.STAR:
		spin = clampf(spin * -1.2 + randf_range(-0.3, 0.3), -1.0, 1.0)
	elif shape_type == Shape.RUGBY:
		_squash = Vector2(1.6, 0.5)

	if velocity.dot(normal) < 0.0:
		velocity = velocity.bounce(normal)
	velocity *= bounce_damping
	var spd := velocity.length()
	if shape_type != Shape.CUBE and shape_type != Shape.RUGBY:
		_squash = Vector2(1.25, 0.7) if absf(normal.y) > 0.5 else Vector2(0.72, 1.28)
	var t := clampf((spd - 500.0) / 1400.0, 0.0, 1.0)
	if fluid_sim != null:
		var wcol := Color(1.0, 0.95, 0.8, 0.5 + 0.35 * t)
		fluid_sim.inject_shockwave(contact, normal, 700.0 + 1300.0 * t, wcol)
	if vfx_mgr != null:
		vfx_mgr.spawn_wall_hit(contact, normal, t)
		vfx_mgr.apply_camera_kick(normal, 0.12 + 0.3 * t)
	if audio_mgr != null:
		if audio_mgr.has_method("trigger_wall_hit"):
			audio_mgr.call("trigger_wall_hit", contact, spd)
		else:
			audio_mgr.trigger_impact(spd * 0.7, contact, false)
	hit_wall.emit(contact, spd)
	if spd > 1000.0:
		emote(4, 0.3, "OW")

func _handle_walls_and_goals() -> void:
	if captured_by != null:
		# Orbiting: keep inside the court silently; the captor clamps the orbit itself.
		global_position.y = clampf(global_position.y, 58.0, 1022.0)
		global_position.x = clampf(global_position.x, 40.0, 1880.0)
		return
	if global_position.y < 58.0:
		global_position.y = 58.0
		if velocity.y < 0.0:
			_bounce_off_wall(Vector2.DOWN, Vector2(global_position.x, 40.0))
	elif global_position.y > 1022.0:
		global_position.y = 1022.0
		if velocity.y > 0.0:
			_bounce_off_wall(Vector2.UP, Vector2(global_position.x, 1040.0))

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
	captured_by = null
	last_hit_speed = velocity.length()
	goal_velocity = velocity
	emote(3, 0.8, "BOOM")
	velocity = Vector2.ZERO
	visible = true
	global_position.x = clampf(global_position.x, 36.0, 1884.0)
	_clear_trail()
	goal_reached.emit(side)

## Goal theatre: hide the ball and burst it into a debris cone along `goal_velocity`.
## The ball reappears on the next `hold_for_serve` / `reset_ball`.
func shatter(color: Color = Color(1.0, 0.9, 0.6)) -> void:
	var vel := goal_velocity if goal_velocity.length_squared() > 1.0 else velocity
	visible = false
	_clear_trail()
	if vfx_mgr != null:
		vfx_mgr.spawn_goal_shatter(global_position, vel, color)
	shattered.emit(global_position, vel)

## Lost-ball pulse: soft ring every 0.5 s in Cymatic Lock, every 1.0 s in overdrive.
func _update_lock_pulse(delta: float) -> void:
	if not (is_in_cymatic_lock or is_in_overdrive) or vfx_mgr == null or is_clone:
		_pulse_cd = 0.0
		return
	_pulse_cd -= delta
	if _pulse_cd > 0.0:
		return
	if is_in_cymatic_lock:
		_pulse_cd = 0.5
		vfx_mgr.spawn_lock_pulse(global_position, Color(1.0, 1.0, 1.0), 0.38, 300.0)
	else:
		_pulse_cd = 1.0
		vfx_mgr.spawn_lock_pulse(global_position, Color(1.0, 0.6, 0.2), 0.22, 240.0)

func _check_near_miss() -> void:
	if captured_by != null:
		return
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
		new_vel = new_vel.normalized() * clampf(spd, min_speed * 0.82, _speed_cap())
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

	var pvel := paddle.hit_velocity()
	out_dir += pvel * 0.0009
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
		spin = clampf(-hit_offset * 1.45 + pvel.y * 0.0045, -1.0, 1.0)
	else:
		spin = clampf(-hit_offset * 1.12 + pvel.y * 0.003, -1.0, 1.0)

	var bonus_flat := 48.0
	if paddle.shape_type == Paddle.Shape.FORTRESS:
		bonus_flat += 280.0
	var out_speed := minf(incoming * speed_boost + bonus_flat, _speed_cap())
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
		if perfect:
			# Anamorphic star + flung star ring + white flash; chromatic kick via impact_pulse.
			vfx_mgr.spawn_parry_star(global_position, paddle.team_color, out_dir)
			if game_mgr != null:
				game_mgr.impact_pulse.emit(1.0)
		else:
			vfx_mgr.spawn_paddle_hit(global_position, out_dir, paddle.team_color, clampf(rally_hits * 0.08, 0.0, 1.0))
		vfx_mgr.apply_camera_kick(out_dir, 0.9 if perfect else 0.45 + minf(rally_hits * 0.04, 0.4))
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

## Effective cap: rally cap normally, hard max during a blast/resonance override window.
func _speed_cap() -> float:
	if speed_override_time > 0.0:
		return max_speed
	return _rally_speed_cap()

func apply_impulse(dir: Vector2, amount: float) -> void:
	if is_serving or is_scored or captured_by != null:
		return
	velocity += dir.normalized() * amount
	var spd := clampf(velocity.length(), min_speed, _speed_cap())
	velocity = velocity.normalized() * spd

func _clear_trail() -> void:
	_trail_pts.clear()
	_trail_ages.clear()
	_tick_pos = global_position
	_prev_tick_pos = global_position
	if _trail:
		_trail.clear_points()
	if _trail_core:
		_trail_core.clear_points()
	if _sparks:
		_sparks.emitting = false

## Trail is rebuilt per rendered frame from the interpolated transform so it
## never stutters at frame rates above the physics tick.
func _process(delta: float) -> void:
	if _trail == null:
		return
	if not _trail_active or is_scored or is_serving or not visible:
		if not _trail_pts.is_empty() or _trail.get_point_count() > 0:
			_clear_trail()
		return
	# Same interpolation the renderer applies between physics ticks.
	var pos := _prev_tick_pos.lerp(_tick_pos, Engine.get_physics_interpolation_fraction())
	var heat := 1.0 if is_in_cymatic_lock else (0.75 if is_in_overdrive else clampf((velocity.length() - 500.0) / 1100.0, 0.25, 1.0))
	if fireball_time > 0.0:
		heat = 1.0
	var life := 0.30 if heat > 0.7 else 0.22
	if is_clone:
		life = 0.16
	# Age existing samples (scaled delta, so hit-stop freezes the comet too).
	for i in range(_trail_ages.size()):
		_trail_ages[i] += delta
	if _trail_pts.is_empty() or _trail_pts[0].distance_squared_to(pos) > 2.0:
		_trail_pts.push_front(pos)
		_trail_ages.push_front(0.0)
	while not _trail_ages.is_empty() and _trail_ages[_trail_ages.size() - 1] > life:
		_trail_ages.pop_back()
		_trail_pts.pop_back()
	var max_pts := 40
	if _trail_pts.size() > max_pts:
		_trail_pts.resize(max_pts)
		_trail_ages.resize(max_pts)
	_trail.clear_points()
	if _trail_core:
		_trail_core.clear_points()
	for p in _trail_pts:
		_trail.add_point(p)
		if _trail_core:
			_trail_core.add_point(p)
	_trail.width = 30.0 + heat * 18.0
	if _trail_core:
		_trail_core.width = 8.0 + heat * 8.0
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
	if _ghost_shader == null:
		_ghost_shader = load("res://shaders/vfx/afterimage.gdshader")
	var ghost := ColorRect.new()
	ghost.z_index = 9
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sz := 64.0 if fireball_time > 0.0 else 56.0
	ghost.size = Vector2(sz, sz)
	ghost.pivot_offset = ghost.size * 0.5
	ghost.global_position = global_position - ghost.pivot_offset
	ghost.scale = _squash
	ghost.rotation = velocity.angle()
	var mat := ShaderMaterial.new()
	mat.shader = _ghost_shader
	var tint := Color(1.0, 0.5, 0.1) if fireball_time > 0.0 else Color(1.0, 0.85, 0.35)
	if is_in_cymatic_lock:
		tint = Color(0.9, 0.95, 1.0)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("intensity", 1.1 if is_clone else 1.4)
	mat.set_shader_parameter("progress", 0.0)
	ghost.material = mat
	var parent := get_parent()
	if parent:
		parent.add_child(ghost)
		var tw := ghost.create_tween()
		tw.set_ignore_time_scale(true)
		tw.set_parallel(true)
		tw.tween_method(func(v: float):
			if is_instance_valid(ghost):
				mat.set_shader_parameter("progress", v)
		, 0.0, 1.0, 0.2)
		tw.tween_property(ghost, "scale", _squash * 0.35, 0.2).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(ghost.queue_free)

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
