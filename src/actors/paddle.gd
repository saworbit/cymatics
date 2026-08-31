class_name Paddle
extends CharacterBody2D

signal blast_fired(strength: float, pos: Vector2)
signal parried(pos: Vector2)
signal momentum_changed(new_val: float)
signal resonance_fired(pos: Vector2)
signal super_ready
signal stunned(duration: float)
signal armed
signal stun_fired(pos: Vector2)

@export var player_id := 0
@export var is_ai := false
@export var speed := 920.0
@export var shoot_force := 2000.0
@export var suck_force := 1600.0
@export var team_color := Color(0.0, 0.9, 1.0, 1.0)

var momentum := 0.0
var is_shooting := false
var is_sucking := false
var blast_cooldown := 0.0
var last_velocity := Vector2.ZERO
var parry_window := 0.0
var resonance_available := false
var _mouse_control := false
var _last_mouse := Vector2.ZERO
var _body_mat: ShaderMaterial
var _beam: ColorRect
var _beam_mat: ShaderMaterial
var _action_glow := 0.0
var _super_announced := false
var stun_time := 0.0
var armed_time := 0.0
var size_mod := 1.0
var size_mod_time := 0.0
var magnet_time := 0.0
var stun_cooldown := 0.0
var _stun_fx: ColorRect
var _cannon: ColorRect
var face

var min_x := 50.0
var max_x := 540.0
var min_y := 80.0
var max_y := 1000.0

@onready var visual_core: ColorRect = $VisualCore
@onready var visual_glow: ColorRect = $VisualGlow
@onready var vortex_vfx: ColorRect = $VortexVFX

var fluid_sim: FluidSimulator
var vfx_mgr: VFXManager
var audio_mgr: AudioManager
var ball: Ball

func _ready() -> void:
	z_index = 6
	if player_id == 1:
		team_color = Color(1.0, 0.0, 0.67, 1.0)
		min_x = 1920.0 - 540.0
		max_x = 1920.0 - 50.0
	_setup_visuals()
	_last_mouse = get_global_mouse_position()

func _setup_visuals() -> void:
	if visual_glow != null:
		visual_glow.visible = false
	if visual_core != null:
		visual_core.offset_left = -44.0
		visual_core.offset_top = -110.0
		visual_core.offset_right = 44.0
		visual_core.offset_bottom = 110.0
		visual_core.pivot_offset = Vector2(44, 110)
		visual_core.color = Color.WHITE
		visual_core.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body_mat = ShaderMaterial.new()
		_body_mat.shader = load("res://shaders/vfx/paddle_body.gdshader")
		_body_mat.set_shader_parameter("glow_color", team_color)
		_body_mat.set_shader_parameter("core_color", Color(1.0, 1.0, 1.0))
		visual_core.material = _body_mat

	_beam = ColorRect.new()
	_beam.size = Vector2(280, 70)
	_beam.position = Vector2(18, -35) if player_id == 0 else Vector2(-298, -35)
	_beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_beam.visible = false
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = load("res://shaders/vfx/beam.gdshader")
	_beam_mat.set_shader_parameter("beam_color", team_color)
	_beam.material = _beam_mat
	if player_id == 1:
		_beam.scale.x = -1.0
		_beam.position = Vector2(-18, -35)
	add_child(_beam)

	if vortex_vfx != null and vortex_vfx.material is ShaderMaterial:
		(vortex_vfx.material as ShaderMaterial).set_shader_parameter("vortex_tint", team_color)

	_stun_fx = ColorRect.new()
	_stun_fx.size = Vector2(120, 200)
	_stun_fx.position = Vector2(-60, -100)
	_stun_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stun_fx.visible = false
	var bolt_mat := ShaderMaterial.new()
	bolt_mat.shader = load("res://shaders/vfx/stun_bolt.gdshader")
	bolt_mat.set_shader_parameter("bolt_color", Color(0.8, 0.95, 1.0))
	_stun_fx.material = bolt_mat
	add_child(_stun_fx)

	_cannon = ColorRect.new()
	_cannon.size = Vector2(70, 18)
	_cannon.position = Vector2(18, -9) if player_id == 0 else Vector2(-88, -9)
	_cannon.color = Color(1, 1, 1, 0.9)
	_cannon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cannon.visible = false
	add_child(_cannon)

	face = preload("res://src/actors/character_face.gd").new()
	add_child(face)
	# Padd (P1, left): wide eager eyes facing right (+X). Lin (P2, right): smug half-lids facing left (-X).
	var lid := 0.05 if player_id == 0 else 0.42
	face.setup(Vector2(92, 128), player_id == 1, lid)
	face.position = Vector2(6.0 if player_id == 0 else -6.0, -8.0)

func setup_dependencies(p_fluid_sim: FluidSimulator, p_vfx: VFXManager, p_audio: AudioManager) -> void:
	fluid_sim = p_fluid_sim
	vfx_mgr = p_vfx
	audio_mgr = p_audio

func set_ball_reference(p_ball: Ball) -> void:
	ball = p_ball

func character_name() -> String:
	return "PADD" if player_id == 0 else "LIN"

func emote(mood: int, duration: float = 0.7, line: String = "") -> void:
	if face == null:
		return
	face.set_mood(mood, duration)
	if line != "":
		face.bark(line)

func consume_parry() -> bool:
	if parry_window > 0.0:
		parry_window = 0.0
		parried.emit(global_position)
		return true
	return false

func register_hit(perfect: bool, hit_speed: float) -> void:
	var gain := 0.11 + minf(hit_speed / 12000.0, 0.08)
	if perfect:
		gain += 0.18
		emote(3, 0.85, "NICE")
	else:
		emote(2 if hit_speed > 1200.0 else 1, 0.45, "HA")
	add_momentum(gain)
	if visual_core != null:
		visual_core.scale = Vector2(1.35 * size_mod, 0.78 * size_mod)

func add_momentum(amount: float) -> void:
	var was_ready := momentum >= 1.0
	momentum = clampf(momentum + amount, 0.0, 1.0)
	momentum_changed.emit(momentum)
	if momentum >= 1.0 and not was_ready and not _super_announced:
		_super_announced = true
		resonance_available = true
		emote(1, 1.2, "LET'S GO")
		super_ready.emit()
		if vfx_mgr != null:
			vfx_mgr.spawn_hit_burst(global_position, team_color, 2.2)
			vfx_mgr.flash_screen(team_color, 0.12, 0.12)

func reset_momentum() -> void:
	momentum = 0.0
	resonance_available = false
	_super_announced = false
	momentum_changed.emit(momentum)

func apply_stun(duration: float) -> void:
	stun_time = maxf(stun_time, duration)
	emote(8, duration, "UHH") # DIZZY
	stunned.emit(duration)
	if vfx_mgr != null:
		vfx_mgr.spawn_hit_burst(global_position, Color(0.7, 0.9, 1.0), 2.2)
		vfx_mgr.flash_screen(Color(0.7, 0.95, 1.0), 0.2, 0.12)
	if audio_mgr != null:
		audio_mgr.trigger_parry(900.0, global_position)

func arm_cannon(duration: float) -> void:
	armed_time = maxf(armed_time, duration)
	emote(3, 1.1, "HEH") # SMUG
	armed.emit()

func apply_size_mod(mult: float, duration: float) -> void:
	size_mod = mult
	size_mod_time = duration
	if mult > 1.15:
		emote(2, 1.0, "BIG")
	elif mult < 0.85:
		emote(7, 1.0, "eep") # SCARE
	_apply_size_visual()

func apply_magnet(duration: float) -> void:
	magnet_time = maxf(magnet_time, duration)

func clear_mods() -> void:
	armed_time = 0.0
	magnet_time = 0.0
	size_mod_time = 0.0
	size_mod = 1.0
	stun_time = 0.0
	_apply_size_visual()

func _apply_size_visual() -> void:
	var s := size_mod
	if visual_core != null:
		visual_core.scale = Vector2(s, s)
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node and shape_node.shape is RectangleShape2D:
		if not shape_node.shape.resource_local_to_scene:
			shape_node.shape = shape_node.shape.duplicate()
			shape_node.shape.resource_local_to_scene = true
		(shape_node.shape as RectangleShape2D).size = Vector2(36 * s, 140 * s)

func fire_stun_bolt() -> void:
	if stun_cooldown > 0.0 or stun_time > 0.0:
		return
	stun_cooldown = 0.55 if armed_time > 0.0 else 1.7
	var fwd := Vector2.RIGHT if player_id == 0 else Vector2.LEFT
	var bolt = preload("res://src/actors/stun_bolt.gd").new()
	var parent := get_parent()
	if parent == null:
		return
	parent.add_child(bolt)
	bolt.setup(global_position + fwd * 70.0, fwd, player_id, team_color)
	bolt.hit_paddle.connect(func(p: Paddle):
		p.apply_stun(1.35 if armed_time <= 0.0 else 1.9)
	)
	if vfx_mgr != null:
		vfx_mgr.spawn_hit_burst(global_position + fwd * 40.0, team_color, 1.4)
		vfx_mgr.apply_camera_kick(fwd, 0.55)
	if audio_mgr != null:
		audio_mgr.trigger_blast(0.85, global_position)
	stun_fired.emit(global_position)
	if armed_time > 0.0:
		armed_time = 0.0

func _physics_process(delta: float) -> void:
	if blast_cooldown > 0.0:
		blast_cooldown -= delta
	if parry_window > 0.0:
		parry_window -= delta
	if stun_cooldown > 0.0:
		stun_cooldown -= delta
	if armed_time > 0.0:
		armed_time -= delta
	if magnet_time > 0.0:
		magnet_time -= delta
	if size_mod_time > 0.0:
		size_mod_time -= delta
		if size_mod_time <= 0.0:
			size_mod = 1.0
			_apply_size_visual()
	if stun_time > 0.0:
		stun_time -= delta
		velocity = Vector2.ZERO
		is_shooting = false
		is_sucking = false
		_update_visuals(delta)
		if _stun_fx:
			_stun_fx.visible = true
		return
	if _stun_fx:
		_stun_fx.visible = false

	if not is_ai:
		_handle_player_input(delta)
	elif ball != null and ball.is_serving and ball.serve_paddle == self:
		is_shooting = false
		is_sucking = false

	var cur_min_y := 40.0 + 70.0 * size_mod + 4.0
	var cur_max_y := 1040.0 - 70.0 * size_mod - 4.0
	global_position.x = clampf(global_position.x, min_x, max_x)
	global_position.y = clampf(global_position.y, cur_min_y, cur_max_y)

	_apply_hydro(delta)
	_update_visuals(delta)
	_update_face()
	last_velocity = velocity

func _handle_player_input(delta: float) -> void:
	var prefix := "p1_" if player_id == 0 else "p2_"
	var input_dir := Input.get_vector(prefix + "left", prefix + "right", prefix + "up", prefix + "down")

	if ball != null and ball.is_serving and ball.serve_paddle == self:
		is_shooting = false
		is_sucking = false
		if Input.is_action_just_pressed(prefix + "shoot") or Input.is_action_just_pressed(prefix + "blast"):
			try_serve()
	else:
		is_shooting = Input.is_action_pressed(prefix + "shoot")
		is_sucking = Input.is_action_pressed(prefix + "suck")
		if Input.is_action_just_pressed(prefix + "blast"):
			parry_window = 0.11
			if blast_cooldown <= 0.0:
				if armed_time > 0.0:
					fire_stun_bolt()
					trigger_blast(0.7)
				elif momentum >= 1.0:
					trigger_resonance()
				else:
					trigger_blast(1.0)

	var accel := 7800.0
	var friction := 6200.0

	# Mouse is the Plasma Pong feel for P1. Use play-space coords so camera shake
	# does not look like the cursor moved.
	if player_id == 0:
		var mouse := _play_mouse()
		var cur_min_y := 40.0 + 70.0 * size_mod + 4.0
		var cur_max_y := 1040.0 - 70.0 * size_mod - 4.0
		var in_zone := mouse.x >= 0.0 and mouse.x <= max_x + 140.0 and mouse.y >= cur_min_y - 60.0 and mouse.y <= cur_max_y + 60.0
		if in_zone and (mouse - global_position).length() > 6.0:
			var target := Vector2(clampf(mouse.x, min_x, max_x), clampf(mouse.y, cur_min_y, cur_max_y))
			var diff := target - global_position
			var follow_speed := maxf(speed * 1.35, diff.length() * 18.0)
			velocity = velocity.move_toward(diff.normalized() * minf(diff.length() * 26.0, follow_speed), accel * 1.5 * delta)
			move_and_slide()
			return

	if input_dir.length() > 0.05:
		var target_vel := input_dir.normalized() * speed
		velocity = velocity.move_toward(target_vel, accel * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	move_and_slide()

func _play_mouse() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2(960, 540)
	var p := vp.get_mouse_position()
	return Vector2(clampf(p.x, 0.0, 1920.0), clampf(p.y, 0.0, 1080.0))

func try_serve() -> bool:
	if ball == null or not is_instance_valid(ball):
		return false
	if not ball.is_serving or ball.serve_paddle != self:
		return false
	var fwd := Vector2.RIGHT if player_id == 0 else Vector2.LEFT
	var aim := Vector2(fwd.x, clampf(velocity.y * 0.0012, -0.55, 0.55))
	if absf(aim.y) < 0.08:
		aim.y = randf_range(-0.18, 0.18)
	ball.launch_serve(aim.normalized(), 780.0)
	blast_cooldown = 0.25
	if audio_mgr != null:
		audio_mgr.trigger_blast(0.7, global_position)
	return true

func _apply_hydro(delta: float) -> void:
	var forward_dir := Vector2.RIGHT if player_id == 0 else Vector2.LEFT
	var nozzle_pos := global_position + forward_dir * 40.0

	if velocity.length() > 40.0 and fluid_sim != null:
		var wake := velocity.normalized()
		fluid_sim.inject_force(global_position, wake * 900.0, 40.0, Color(team_color.r, team_color.g, team_color.b, 0.38))
		var flank := Vector2(-wake.y, wake.x) * 28.0
		var eddy := Color(team_color.r, team_color.g, team_color.b, 0.22)
		fluid_sim.inject_vortex(global_position + flank, 2.2, 42.0, eddy)
		fluid_sim.inject_vortex(global_position - flank, -2.2, 42.0, eddy)
		if audio_mgr != null:
			audio_mgr.register_paddle_movement(velocity.length(), global_position.x / 1920.0)

	var balls := get_tree().get_nodes_in_group("cymatics_balls") if get_tree() else []
	var mag := 1.55 if magnet_time > 0.0 else 1.0

	if is_shooting and fluid_sim != null:
		var stream_dir := (forward_dir + Vector2(0, velocity.y * 0.0008)).normalized()
		fluid_sim.inject_force(nozzle_pos, stream_dir * (shoot_force * mag), 62.0 * mag, Color(team_color.r, team_color.g, team_color.b, 0.78))
		fluid_sim.inject_vortex(nozzle_pos + stream_dir * 70.0, (2.4 if player_id == 0 else -2.4) * mag, 48.0, Color(team_color.r, team_color.g, team_color.b, 0.4))
		for node in balls:
			if node is Ball:
				var b := node as Ball
				if b.is_scored or b.is_serving:
					continue
				var to_ball := b.global_position - global_position
				var in_front := (to_ball.x * forward_dir.x) > 0.0
				if in_front and to_ball.length() < 680.0 * mag and absf(to_ball.y) < 130.0 * size_mod:
					var jet_push := stream_dir * (620.0 * mag * delta)
					b.apply_impulse(jet_push.normalized(), jet_push.length())
					b.spin = clampf(b.spin + (stream_dir.y * 0.4 * delta), -1.0, 1.0)
		_action_glow = 1.0
		if _beam:
			_beam.visible = true
			_beam_mat.set_shader_parameter("intensity", 1.25 * mag)
	else:
		if _beam:
			_beam.visible = false

	if is_sucking and fluid_sim != null:
		var swirl_dir := 4.5 if player_id == 0 else -4.5
		fluid_sim.inject_sink(nozzle_pos, suck_force * mag, 120.0 * mag, Color(team_color.r, team_color.g, team_color.b, 0.55))
		fluid_sim.inject_vortex(nozzle_pos, swirl_dir * mag, 130.0 * mag, Color(team_color.r, team_color.g, team_color.b, 0.5))

		if vortex_vfx != null:
			vortex_vfx.visible = true
			if vortex_vfx.material is ShaderMaterial:
				(vortex_vfx.material as ShaderMaterial).set_shader_parameter("active_factor", 1.0)
				(vortex_vfx.material as ShaderMaterial).set_shader_parameter("vortex_tint", team_color)

		for node in balls:
			if node is Ball:
				var b := node as Ball
				if b.is_scored or b.is_serving:
					continue
				var to_paddle := nozzle_pos - b.global_position
				var in_front := (to_paddle.x * -forward_dir.x) > 0.0
				var dist := to_paddle.length()

				if in_front and dist < 720.0 * mag:
					# Inward gravitational pull
					var pull_strength := clampf(1.0 - dist / (720.0 * mag), 0.2, 1.0) * 1250.0 * mag
					b.apply_impulse(to_paddle.normalized(), pull_strength * delta)

					# Orbital swirl capture when close to nozzle (Plasma Pong slingshot orbit)
					if dist < 210.0 * mag:
						var orbit_tangent := Vector2(-to_paddle.y, to_paddle.x).normalized() * (1.0 if player_id == 0 else -1.0)
						b.apply_impulse(orbit_tangent, 1350.0 * mag * delta)
						b.spin = clampf(b.spin + (2.5 if player_id == 0 else -2.5) * delta, -1.0, 1.0)

		_action_glow = 1.0
	else:
		if vortex_vfx != null:
			vortex_vfx.visible = false

func trigger_blast(strength: float = 1.0) -> void:
	if try_serve():
		return
	if momentum >= 1.0:
		trigger_resonance()
		return

	blast_cooldown = 0.42
	parry_window = maxf(parry_window, 0.09)
	var forward_dir := Vector2.RIGHT if player_id == 0 else Vector2.LEFT
	var blast_pos := global_position + forward_dir * 54.0
	var power := clampf(strength, 0.5, 1.4)

	if fluid_sim != null:
		fluid_sim.inject_shockwave(blast_pos, forward_dir, 3600.0 * power, team_color)
		fluid_sim.inject_vortex(blast_pos, (4.2 if player_id == 0 else -4.2) * power, 120.0, Color.WHITE)

	if vfx_mgr != null:
		vfx_mgr.spawn_shockwave(blast_pos, team_color, 440.0 * power, 0.4)
		vfx_mgr.spawn_hit_burst(blast_pos, team_color, 1.6 * power)
		vfx_mgr.apply_camera_kick(forward_dir, 0.85 * power)

	if audio_mgr != null:
		audio_mgr.trigger_blast(power, global_position)

	var balls := get_tree().get_nodes_in_group("cymatics_balls") if get_tree() else []
	var hit_any := false
	for node in balls:
		if node is Ball:
			var b := node as Ball
			if b.is_scored or b.is_serving:
				continue
			var to_ball := b.global_position - global_position
			if (to_ball.x * forward_dir.x) > 0.0 and to_ball.length() < 280.0:
				var blast_aim := (forward_dir + Vector2(0, to_ball.y * 0.003)).normalized()
				b.apply_impulse(blast_aim, 820.0 * power)
				b.spin = clampf(b.spin + (to_ball.y * -0.005), -1.0, 1.0)
				hit_any = true
	if not hit_any and stun_cooldown <= 0.0:
		fire_stun_bolt()

	blast_fired.emit(power, blast_pos)
	add_momentum(0.06)

func trigger_resonance() -> void:
	if momentum < 0.99:
		trigger_blast(1.2)
		return
	momentum = 0.0
	resonance_available = false
	_super_announced = false
	momentum_changed.emit(0.0)
	blast_cooldown = 0.7

	var forward_dir := Vector2.RIGHT if player_id == 0 else Vector2.LEFT
	var blast_pos := global_position + forward_dir * 70.0

	if vfx_mgr != null:
		vfx_mgr.apply_hit_stop(0.22, 0.08)
		vfx_mgr.spawn_shockwave(blast_pos, Color.WHITE, 820.0, 0.7)
		vfx_mgr.spawn_hit_burst(blast_pos, team_color, 3.4)
		vfx_mgr.apply_camera_kick(forward_dir, 2.2)
		vfx_mgr.flash_screen(Color.WHITE, 0.35, 0.16)
		if ball != null and is_instance_valid(ball) and not ball.is_scored:
			vfx_mgr.spawn_trajectory(ball.global_position, forward_dir * 2000.0, team_color)

	if audio_mgr != null:
		audio_mgr.trigger_super(global_position)

	if fluid_sim != null:
		fluid_sim.inject_shockwave(blast_pos, forward_dir, 5200.0, Color.WHITE)
		fluid_sim.inject_vortex(blast_pos, 6.0 if player_id == 0 else -6.0, 200.0, Color.WHITE)

	if ball != null and is_instance_valid(ball) and not ball.is_scored and not ball.is_serving:
		var to_ball := ball.global_position - global_position
		var aim := forward_dir
		if to_ball.length() > 8.0 and (to_ball.x * forward_dir.x) > -40.0:
			aim = (forward_dir * 1.6 + Vector2(0, clampf(to_ball.y * 0.004, -0.4, 0.4))).normalized()
		ball.velocity = aim * minf(ball.max_speed, 1680.0)
		ball.spin = clampf((-to_ball.y) * 0.004, -1.0, 1.0)

	resonance_fired.emit(blast_pos)

func trigger_parry() -> void:
	parry_window = 0.12
	trigger_blast(0.85)

func _update_visuals(delta: float) -> void:
	_action_glow = move_toward(_action_glow, 1.0 if (is_shooting or is_sucking) else 0.0, delta * 8.0)
	if visual_core != null:
		visual_core.scale = visual_core.scale.lerp(Vector2(size_mod, size_mod), clampf(delta * 12.0, 0.0, 1.0))
	if face != null:
		face.scale = Vector2(size_mod, size_mod)
		face.position = Vector2((6.0 if player_id == 0 else -6.0) * size_mod, -8.0 * size_mod)
	if _cannon != null:
		_cannon.visible = armed_time > 0.0
		if armed_time > 0.0:
			_cannon.color = Color(1.0, 0.95, 0.4, 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.02))
	if _body_mat != null:
		_body_mat.set_shader_parameter("glow_color", team_color)
		var ready := 1.0 if momentum >= 1.0 else momentum * 0.35
		if armed_time > 0.0:
			ready = 1.0
		_body_mat.set_shader_parameter("ready_factor", ready)
		_body_mat.set_shader_parameter("action_factor", _action_glow)
		_body_mat.set_shader_parameter("time_pulse", Time.get_ticks_msec() * 0.001)

func _update_face() -> void:
	if face == null:
		return
	if ball != null and is_instance_valid(ball) and not ball.is_scored:
		face.look_at_point(global_position, ball.global_position)
		var incoming := (ball.velocity.x < 0.0 and player_id == 0) or (ball.velocity.x > 0.0 and player_id == 1)
		var close := absf(ball.global_position.x - global_position.x) < 400.0
		if incoming and close and ball.velocity.length() > 1100.0:
			face.maybe_mood(7, 0.28)
		elif momentum >= 1.0:
			face.maybe_mood(1, 0.2)
	else:
		face.look_at_point(global_position, Vector2(960, 540))
