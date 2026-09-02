class_name Paddle
extends CharacterBody2D

signal blast_fired(strength: float, pos: Vector2)
signal parried(pos: Vector2)
signal parry_opened(pos: Vector2)
signal momentum_changed(new_val: float)
signal resonance_fired(pos: Vector2)
signal super_ready
signal stunned(duration: float)
signal armed
signal stun_fired(pos: Vector2)
signal input_device_changed(device: int)
## Blast button held past the tap threshold: a charge is building.
signal blast_charge_started(pos: Vector2)
## Blast released. `power` 0..1 (0.35 = plain tap, 1.0 = full charge).
signal blast_charge_released(pos: Vector2, power: float)
## The ball entered this paddle's suction orbit.
signal suck_captured(pos: Vector2)
## Suction released: ball fired along the orbit tangent at `speed`.
signal slingshot_fired(pos: Vector2, speed: float)
## Serve aim direction changed materially while this paddle holds the serve.
signal serve_aimed(dir: Vector2)

enum Shape { STANDARD, SCOOP, WEDGE, FORK, FORTRESS }
enum InputDevice { MOUSE, KEYS }

const PARRY_WINDOW := 0.083 # ~5 frames at 60 Hz
const PARRY_COOLDOWN := 0.35
const PARRY_RANGE := 300.0
const BLAST_COOLDOWN := 0.42
const BLAST_COOLDOWN_CHARGED := 0.9
const BLAST_TAP_TIME := 0.12
const BLAST_CHARGE_TIME := 0.7
const STAGE_MOD_DURATION := 9999.0
const MOUSE_SWITCH_PX := 2.0
const STICK_DEADZONE := 0.2
## Suction capture (Plasma Pong slingshot).
const CAPTURE_RANGE := 220.0
const CAPTURE_MAX_HOLD := 2.0
const CAPTURE_TIGHTEN_TIME := 1.2
const CAPTURE_RADIUS_START := 280.0
const CAPTURE_RADIUS_END := 120.0
const CAPTURE_ORBIT_SPEED := 320.0
const CAPTURE_RECAPTURE_BLOCK := 0.8
const CAPTURE_CENTER_OFFSET := 110.0
const SLINGSHOT_CONE_DEG := 50.0
const SERVE_CONE_DEG := 55.0
const SERVE_SPEED := 780.0

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
var parry_window := 0.0
var parry_cooldown := 0.0
var _parry_pending := false
var input_device := InputDevice.MOUSE
var _body_mat: ShaderMaterial
var _beam: ColorRect
var _beam_mat: ShaderMaterial
var _action_glow := 0.0
var _super_announced := false
var stun_time := 0.0
var armed_time := 0.0
var size_mod := 1.0
var size_mod_time := 0.0
var shape_type: Shape = Shape.STANDARD
var shape_time := 0.0
## Stage-applied (boss loadout) mods. Survive point resets; cleared by clear_stage_mods().
var stage_shape: Shape = Shape.STANDARD
var stage_size := 1.0
var magnet_time := 0.0
var stun_cooldown := 0.0
var _stun_fx: ColorRect
var _cannon: ColorRect
var face

## Blast charge state.
var _charging := false
var _charge_t := 0.0
var _charge_announced := false
var _blast_press_consumed := false
## Suction capture state.
var _captured: Ball = null
var _capture_hold := 0.0
var _capture_angle := 0.0
var _capture_radius := CAPTURE_RADIUS_START
var _capture_dir := 1.0
var _capture_block := 0.0
## Hold time of the most recent slingshot/break-free (telemetry).
var last_capture_hold := 0.0
var _vortex_active := 0.0
var _vortex_hold := 0.0
var _vortex_mat: ShaderMaterial
## Serve aim (unit vector, kept within SERVE_CONE_DEG of forward).
var serve_aim_dir := Vector2.RIGHT
var _serve_aim_last_emitted := Vector2.ZERO
var _serve_aim_node: Node2D
## Move axis this tick (stick/keys), used by serve aim and slingshot bias.
var _move_axis := Vector2.ZERO

var min_x := 50.0
var max_x := 540.0
var min_y := 80.0
var max_y := 1000.0

@onready var visual_core: ColorRect = $VisualCore
@onready var vortex_vfx: ColorRect = $VortexVFX

var fluid_sim: FluidSimulator
var vfx_mgr: VFXManager
var audio_mgr: AudioManager
var game_mgr: GameManager
var ball: Ball

const _P1_DIGITAL_ACTIONS: Array[StringName] = [
	&"p1_left", &"p1_right", &"p1_up", &"p1_down",
	&"p1_shoot", &"p1_suck", &"p1_blast", &"p1_super",
]

func _ready() -> void:
	z_index = 6
	if player_id == 1:
		team_color = Color(1.0, 0.0, 0.67, 1.0)
		min_x = 1920.0 - 540.0
		max_x = 1920.0 - 50.0
	serve_aim_dir = _forward()
	_setup_visuals()

func _forward() -> Vector2:
	return Vector2.RIGHT if player_id == 0 else Vector2.LEFT

func _setup_visuals() -> void:
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

	if vortex_vfx != null:
		# Big enough to frame the widest orbit (280 px) around the orbit centre.
		vortex_vfx.offset_left = -320.0
		vortex_vfx.offset_top = -320.0
		vortex_vfx.offset_right = 320.0
		vortex_vfx.offset_bottom = 320.0
		vortex_vfx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vortex_vfx.z_index = 2
		if vortex_vfx.material is ShaderMaterial:
			_vortex_mat = vortex_vfx.material as ShaderMaterial
			_vortex_mat.set_shader_parameter("vortex_tint", team_color)
			_vortex_mat.set_shader_parameter("active_factor", 0.0)
			_vortex_mat.set_shader_parameter("hold", 0.0)

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

	_serve_aim_node = preload("res://src/actors/serve_aim.gd").new()
	_serve_aim_node.name = "ServeAim"
	add_child(_serve_aim_node)
	_serve_aim_node.call("setup", team_color, _forward(), SERVE_CONE_DEG)
	_serve_aim_node.visible = false

	face = preload("res://src/actors/character_face.gd").new()
	add_child(face)
	# Padd (P1, left): wide eager eyes facing right (+X). Lin (P2, right): smug half-lids facing left (-X).
	var lid := 0.05 if player_id == 0 else 0.42
	face.setup(Vector2(92, 128), player_id == 1, lid)
	face.position = Vector2(6.0 if player_id == 0 else -6.0, -8.0)

func setup_dependencies(p_fluid_sim: FluidSimulator, p_vfx: VFXManager, p_audio: AudioManager, p_game: GameManager = null) -> void:
	fluid_sim = p_fluid_sim
	vfx_mgr = p_vfx
	audio_mgr = p_audio
	game_mgr = p_game

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

## Moves the paddle without leaving an interpolation streak.
func teleport(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	reset_physics_interpolation()

## Freezes gameplay intent (match over).
func halt() -> void:
	velocity = Vector2.ZERO
	is_shooting = false
	is_sucking = false
	parry_window = 0.0
	_parry_pending = false
	_cancel_charge()
	_drop_capture()

## Velocity as seen by the ball for out-angle and spin. Mouse-driven velocity is capped.
func hit_velocity() -> Vector2:
	return velocity.limit_length(speed * 1.5)

# --- Parry / momentum --------------------------------------------------------------

func consume_parry() -> bool:
	if parry_window > 0.0:
		parry_window = 0.0
		_parry_pending = false
		parried.emit(global_position)
		return true
	return false

func _ball_incoming_close() -> bool:
	var fwd_x := 1.0 if player_id == 0 else -1.0
	var tree := get_tree()
	var balls: Array = tree.get_nodes_in_group("cymatics_balls") if tree else []
	if balls.is_empty() and ball != null:
		balls = [ball]
	for node in balls:
		if node is Ball:
			var b := node as Ball
			if b.is_scored or b.is_serving or b.captured_by != null:
				continue
			var incoming := b.velocity.x * fwd_x < -40.0
			var dx := (b.global_position.x - global_position.x) * fwd_x
			if incoming and dx > -20.0 and dx < PARRY_RANGE:
				return true
	return false

## Tap when the ball is incoming and close: opens a 5-frame perfect-hit window.
## Only opens off cooldown; a whiff costs PARRY_COOLDOWN.
func try_parry() -> bool:
	if parry_cooldown > 0.0 or stun_time > 0.0:
		return false
	parry_window = PARRY_WINDOW
	_parry_pending = true
	parry_opened.emit(global_position)
	if vfx_mgr != null:
		vfx_mgr.spawn_hit_burst(global_position + _forward() * 30.0, Color(1.0, 1.0, 1.0, 0.9), 0.55)
	return true

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
		emote(1, 1.2, "LET'S GO")
		super_ready.emit()
		if vfx_mgr != null:
			vfx_mgr.spawn_hit_burst(global_position, team_color, 2.2)
			vfx_mgr.flash_screen(team_color, 0.12, 0.12)

func reset_momentum() -> void:
	momentum = 0.0
	_super_announced = false
	momentum_changed.emit(momentum)

func is_resonance_ready() -> bool:
	return momentum >= 0.99

# --- Mods ------------------------------------------------------------------------

func apply_stun(duration: float) -> void:
	stun_time = maxf(stun_time, duration)
	emote(8, duration, "UHH") # DIZZY
	stunned.emit(duration)
	_cancel_charge()
	_drop_capture(true)
	if vfx_mgr != null:
		vfx_mgr.spawn_hit_burst(global_position, Color(0.7, 0.9, 1.0), 2.2)
		vfx_mgr.flash_screen(Color(0.7, 0.95, 1.0), 0.2, 0.12)
	if audio_mgr != null:
		audio_mgr.trigger_stun(global_position)

func arm_cannon(duration: float) -> void:
	armed_time = maxf(armed_time, duration)
	emote(3, 1.1, "HEH") # SMUG
	armed.emit()

## duration >= STAGE_MOD_DURATION marks a stage (boss loadout) size that survives point resets.
func apply_size_mod(mult: float, duration: float) -> void:
	if duration >= STAGE_MOD_DURATION:
		stage_size = mult
		size_mod = mult
		size_mod_time = 0.0
	elif duration <= 0.0:
		stage_size = 1.0
		size_mod = mult
		size_mod_time = 0.0
	else:
		size_mod = mult
		size_mod_time = duration
	if mult > 1.15:
		emote(2, 1.0, "BIG")
	elif mult < 0.85:
		emote(7, 1.0, "eep") # SCARE
	call_deferred("_apply_size_visual")

func apply_size_mult(mult: float, duration: float) -> void:
	apply_size_mod(mult, duration)

func apply_magnet(duration: float) -> void:
	magnet_time = maxf(magnet_time, duration)

## duration >= STAGE_MOD_DURATION: stage shape (survives clear_rally_mods).
## duration <= 0: hard reset of both rally and stage shape.
func mutate_shape(new_shape: Shape, duration: float) -> void:
	var was := shape_type
	if duration >= STAGE_MOD_DURATION:
		stage_shape = new_shape
		shape_type = new_shape
		shape_time = 0.0
	elif duration <= 0.0:
		stage_shape = new_shape
		shape_type = new_shape
		shape_time = 0.0
	else:
		shape_type = new_shape
		shape_time = maxf(shape_time, duration)
	if new_shape == Shape.STANDARD and was == Shape.STANDARD:
		call_deferred("_apply_size_visual")
		return
	var label := "SCOOP"
	match new_shape:
		Shape.STANDARD: label = "PLAIN"
		Shape.SCOOP: label = "SCOOP"
		Shape.WEDGE: label = "WEDGE"
		Shape.FORK: label = "FORK"
		Shape.FORTRESS: label = "AEGIS"
	if vfx_mgr != null:
		vfx_mgr.spawn_hit_burst(global_position, team_color, 1.8)
		vfx_mgr.spawn_shockwave(global_position, team_color, 360.0, 0.4)
	if audio_mgr != null:
		audio_mgr.trigger_sting(520.0, 0.4)
	emote(2, 1.2, label)
	call_deferred("_apply_size_visual")

## Clears powerup-granted (timed) mods; stage loadout remains.
func clear_rally_mods() -> void:
	armed_time = 0.0
	magnet_time = 0.0
	size_mod_time = 0.0
	size_mod = stage_size
	shape_time = 0.0
	shape_type = stage_shape
	stun_time = 0.0
	stun_cooldown = 0.0
	parry_window = 0.0
	parry_cooldown = 0.0
	_parry_pending = false
	_cancel_charge()
	_drop_capture()
	_capture_block = 0.0
	call_deferred("_apply_size_visual")

## Clears the stage loadout (boss shape/size) and reverts to a plain paddle.
func clear_stage_mods() -> void:
	stage_shape = Shape.STANDARD
	stage_size = 1.0
	if shape_time <= 0.0:
		shape_type = Shape.STANDARD
	if size_mod_time <= 0.0:
		size_mod = 1.0
	call_deferred("_apply_size_visual")

## Full reset (rally + stage).
func clear_mods() -> void:
	clear_stage_mods()
	clear_rally_mods()

func _get_half_height() -> float:
	var base_h := 70.0
	if shape_type == Shape.FORTRESS:
		base_h = 80.0
	return base_h * size_mod

func _apply_size_visual() -> void:
	var s := size_mod
	if visual_core != null:
		visual_core.scale = Vector2(s, s)
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node and shape_node.shape is RectangleShape2D:
		if not shape_node.shape.resource_local_to_scene:
			shape_node.shape = shape_node.shape.duplicate()
			shape_node.shape.resource_local_to_scene = true
		var base_w := 36.0
		var base_h := 140.0
		if shape_type == Shape.FORTRESS:
			base_w = 52.0
			base_h = 160.0
		elif shape_type == Shape.WEDGE:
			base_w = 44.0
			base_h = 140.0
		(shape_node.shape as RectangleShape2D).size = Vector2(base_w * s, base_h * s)

# --- Stun bolt ---------------------------------------------------------------------

## Only fires when armed via the STUN powerup.
func fire_stun_bolt() -> bool:
	if armed_time <= 0.0 or stun_cooldown > 0.0 or stun_time > 0.0:
		return false
	stun_cooldown = 0.55
	var fwd := _forward()
	var origin := global_position + fwd * 70.0
	var stun_len := 1.9
	call_deferred("_spawn_stun_bolt", origin, fwd, stun_len)
	if vfx_mgr != null:
		vfx_mgr.spawn_hit_burst(global_position + fwd * 40.0, team_color, 1.4)
		vfx_mgr.apply_camera_kick(fwd, 0.55)
	if audio_mgr != null:
		audio_mgr.trigger_blast(0.85, global_position)
	stun_fired.emit(global_position)
	armed_time = 0.0
	return true

func _spawn_stun_bolt(origin: Vector2, fwd: Vector2, stun_len: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var bolt = preload("res://src/actors/stun_bolt.gd").new()
	parent.add_child(bolt)
	bolt.setup(origin, fwd, player_id, team_color)
	bolt.hit_paddle.connect(func(p: Paddle):
		p.apply_stun(stun_len)
	)

# --- Tick ------------------------------------------------------------------------------

func _update_timers(delta: float) -> void:
	if blast_cooldown > 0.0:
		blast_cooldown -= delta
	if parry_cooldown > 0.0:
		parry_cooldown -= delta
	if parry_window > 0.0:
		parry_window -= delta
		if parry_window <= 0.0 and _parry_pending:
			# Whiffed: window closed without a hit.
			_parry_pending = false
			parry_cooldown = PARRY_COOLDOWN
	if stun_cooldown > 0.0:
		stun_cooldown -= delta
	if armed_time > 0.0:
		armed_time -= delta
	if magnet_time > 0.0:
		magnet_time -= delta
	if _capture_block > 0.0:
		_capture_block -= delta
	if shape_time > 0.0:
		shape_time -= delta
		if shape_time <= 0.0 and shape_type != stage_shape:
			shape_type = stage_shape
			call_deferred("_apply_size_visual")
	if size_mod_time > 0.0:
		size_mod_time -= delta
		if size_mod_time <= 0.0:
			size_mod = stage_size
			call_deferred("_apply_size_visual")
	if stun_time > 0.0:
		stun_time -= delta

func _gameplay_blocked() -> bool:
	if game_mgr == null:
		return false
	return game_mgr.current_state == GameManager.State.MENU \
		or game_mgr.current_state == GameManager.State.MATCH_OVER

func _physics_process(delta: float) -> void:
	if _gameplay_blocked():
		velocity = velocity.move_toward(Vector2.ZERO, 6200.0 * delta)
		is_shooting = false
		is_sucking = false
		_cancel_charge()
		_drop_capture()
		if velocity.length_squared() > 1.0:
			move_and_slide()
		_update_visuals(delta)
		_update_face()
		if _beam:
			_beam.visible = false
		if vortex_vfx:
			vortex_vfx.visible = false
		if _serve_aim_node:
			_serve_aim_node.visible = false
		return

	if stun_time > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, 3800.0 * delta)
		move_and_slide()
		_update_timers(delta)
		is_sucking = false
		is_shooting = false
		_apply_hydro(delta)
		_update_visuals(delta)
		_update_face()
		if _stun_fx:
			_stun_fx.visible = true
		return
	if _stun_fx:
		_stun_fx.visible = false

	_update_timers(delta)

	var serving_me := _is_serving_me()
	if not is_ai:
		_handle_player_input(delta)
	elif serving_me:
		is_shooting = false
		is_sucking = false
		_move_axis = Vector2.ZERO
	if serving_me and is_ai:
		_update_serve_aim(delta)

	var hh := _get_half_height()
	var cur_min_y := 40.0 + hh + 4.0
	var cur_max_y := 1040.0 - hh - 4.0
	global_position.x = clampf(global_position.x, min_x, max_x)
	global_position.y = clampf(global_position.y, cur_min_y, cur_max_y)

	_update_charge(delta)
	_apply_hydro(delta)
	_update_visuals(delta)
	_update_face()

func _is_serving_me() -> bool:
	return ball != null and is_instance_valid(ball) and ball.is_serving and ball.serve_paddle == self

# --- Input --------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Device arbitration for P1 only: last-used device drives movement.
	if player_id != 0 or is_ai:
		return
	var next := input_device
	if event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() > MOUSE_SWITCH_PX:
			next = InputDevice.MOUSE
	elif event is InputEventMouseButton:
		if (event as InputEventMouseButton).pressed:
			next = InputDevice.MOUSE
	elif event is InputEventKey or event is InputEventJoypadButton:
		if event.is_pressed() and not event.is_echo():
			for a in _P1_DIGITAL_ACTIONS:
				if event.is_action(a):
					next = InputDevice.KEYS
					break
	elif event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if jm.device == 0 and (jm.axis == JOY_AXIS_LEFT_X or jm.axis == JOY_AXIS_LEFT_Y) and absf(jm.axis_value) > STICK_DEADZONE + 0.1:
			next = InputDevice.KEYS
	if next != input_device:
		input_device = next
		input_device_changed.emit(int(input_device))

func _handle_player_input(delta: float) -> void:
	var prefix := "p1_" if player_id == 0 else "p2_"
	# Analog magnitude preserved (no normalize); deadzone 0.2.
	var input_dir := Input.get_vector(prefix + "left", prefix + "right", prefix + "up", prefix + "down", STICK_DEADZONE)
	_move_axis = input_dir

	var serving_me := _is_serving_me()
	if serving_me:
		is_shooting = false
		is_sucking = false
		_cancel_charge()
		_update_serve_aim(delta)
		if Input.is_action_just_pressed(prefix + "shoot") or Input.is_action_just_pressed(prefix + "blast"):
			try_serve()
	else:
		is_shooting = Input.is_action_pressed(prefix + "shoot")
		is_sucking = Input.is_action_pressed(prefix + "suck")
		if Input.is_action_just_pressed(prefix + "super"):
			if is_resonance_ready():
				trigger_resonance()
			elif blast_cooldown <= 0.0:
				trigger_blast(0.0)
		if Input.is_action_just_pressed(prefix + "blast"):
			_blast_press_consumed = true
			if armed_time > 0.0 and stun_cooldown <= 0.0:
				fire_stun_bolt()
			elif _ball_incoming_close() and try_parry():
				pass # Parry stays on press; the release does nothing.
			else:
				_blast_press_consumed = not begin_blast_charge()
		if Input.is_action_just_released(prefix + "blast"):
			if _charging and not _blast_press_consumed:
				release_blast_charge()
			_blast_press_consumed = false

	var accel := 7800.0
	var friction := 6200.0

	# Mouse follow for P1: 1-to-1 tracking in world space, only while the mouse is the active device.
	if player_id == 0 and input_device == InputDevice.MOUSE:
		var mouse := _play_mouse()
		var hh := _get_half_height()
		var cur_min_y := 40.0 + hh + 4.0
		var cur_max_y := 1040.0 - hh - 4.0
		var target := Vector2(clampf(mouse.x, min_x, max_x), clampf(mouse.y, cur_min_y, cur_max_y))
		var diff := target - global_position
		velocity = diff * 28.0
		move_and_slide()
		if (global_position.y <= cur_min_y and velocity.y < 0.0) or (global_position.y >= cur_max_y and velocity.y > 0.0):
			velocity.y = 0.0
		return

	if input_dir.length() > 0.001:
		var target_vel := input_dir.limit_length(1.0) * speed
		velocity = velocity.move_toward(target_vel, accel * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	move_and_slide()

func _play_mouse() -> Vector2:
	return get_global_mouse_position()

# --- Serve aim ---------------------------------------------------------------------------------

## Clamps `dir` to within `cone_deg` of this paddle's forward.
func _clamp_to_cone(dir: Vector2, cone_deg: float) -> Vector2:
	var fwd := _forward()
	if dir.length_squared() < 0.0001:
		return fwd
	var d := dir.normalized()
	var ang := fwd.angle_to(d)
	var lim := deg_to_rad(cone_deg)
	if absf(ang) > lim:
		d = fwd.rotated(lim * signf(ang))
	return d

func _update_serve_aim(delta: float) -> void:
	var fwd := _forward()
	var target := serve_aim_dir
	if is_ai:
		target = _ai_serve_aim()
	elif player_id == 0 and input_device == InputDevice.MOUSE:
		# Point at where the serve should go: mouse relative to the held ball.
		var origin := global_position + fwd * 78.0
		var rel := _play_mouse() - origin
		if rel.length() > 60.0 and rel.dot(fwd) > 0.0:
			target = rel
	elif _move_axis.length() > 0.05:
		var y := clampf(_move_axis.y, -1.0, 1.0)
		target = Vector2(fwd.x * (1.0 - 0.35 * absf(y)), y * 0.85)
	target = _clamp_to_cone(target, SERVE_CONE_DEG)
	serve_aim_dir = serve_aim_dir.slerp(target, clampf(delta * 14.0, 0.0, 1.0)).normalized()
	if _serve_aim_last_emitted == Vector2.ZERO or absf(serve_aim_dir.angle_to(_serve_aim_last_emitted)) > deg_to_rad(4.0):
		_serve_aim_last_emitted = serve_aim_dir
		serve_aimed.emit(serve_aim_dir)
	if _serve_aim_node != null:
		_serve_aim_node.visible = true
		_serve_aim_node.call("set_aim", serve_aim_dir, fwd * 78.0)

## AI picks the far side from the opponent; refreshed each serve by the AI's own timer.
var _ai_serve_target := Vector2.ZERO

func _ai_serve_aim() -> Vector2:
	var fwd := _forward()
	if _ai_serve_target == Vector2.ZERO:
		var foe_y := 540.0
		if ball != null and is_instance_valid(ball):
			var foe: Paddle = ball.paddle_right if player_id == 0 else ball.paddle_left
			if foe != null and is_instance_valid(foe):
				foe_y = foe.global_position.y
		var open_y := 900.0 if foe_y < 540.0 else 180.0
		var far_x := 1760.0 if player_id == 0 else 160.0
		var origin := global_position + fwd * 78.0
		var to := Vector2(far_x, open_y + randf_range(-120.0, 120.0)) - origin
		_ai_serve_target = _clamp_to_cone(to, 40.0)
	return _ai_serve_target

func try_serve() -> bool:
	if ball == null or not is_instance_valid(ball):
		return false
	if not ball.is_serving or ball.serve_paddle != self:
		return false
	var aim := _clamp_to_cone(serve_aim_dir, SERVE_CONE_DEG)
	ball.launch_serve(aim, SERVE_SPEED)
	blast_cooldown = 0.25
	_ai_serve_target = Vector2.ZERO
	_serve_aim_last_emitted = Vector2.ZERO
	if _serve_aim_node != null:
		_serve_aim_node.visible = false
	return true

## Called when this paddle receives the serve (GameManager.start_serve -> Ball.hold_for_serve).
func begin_serve_hold() -> void:
	serve_aim_dir = _forward()
	_ai_serve_target = Vector2.ZERO
	_serve_aim_last_emitted = Vector2.ZERO
	_cancel_charge()
	_drop_capture()

# --- Hydro -------------------------------------------------------------------------------------

func _apply_hydro(delta: float) -> void:
	var forward_dir := _forward()
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
				if b.is_scored or b.is_serving or b.captured_by != null:
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

	# Suction. A held suck near the ball captures it into an orbit; letting go slingshots it.
	if _captured != null:
		if not is_sucking:
			release_capture()
		else:
			_update_capture(delta)

	if is_sucking and fluid_sim != null:
		var swirl_dir := 4.5 if player_id == 0 else -4.5
		# Low dye alpha: these run every tick, anything higher saturates a 300 px disc to white.
		fluid_sim.inject_sink(nozzle_pos, suck_force * mag, 120.0 * mag, Color(team_color.r, team_color.g, team_color.b, 0.08))
		fluid_sim.inject_vortex(nozzle_pos, swirl_dir * mag, 130.0 * mag, Color(team_color.r, team_color.g, team_color.b, 0.06))

		if _captured == null:
			for node in balls:
				if node is Ball:
					var b := node as Ball
					if b.is_scored or b.is_serving or b.captured_by != null:
						continue
					var to_paddle := nozzle_pos - b.global_position
					var in_front := (to_paddle.x * -forward_dir.x) > 0.0
					var dist := to_paddle.length()
					if in_front and dist < CAPTURE_RANGE * mag and _can_capture(b):
						_begin_capture(b)
						break
					if in_front and dist < 720.0 * mag:
						# Inward gravitational pull
						var pull_strength := clampf(1.0 - dist / (720.0 * mag), 0.2, 1.0) * 1250.0 * mag
						b.apply_impulse(to_paddle.normalized(), pull_strength * delta)
						if dist < 260.0 * mag:
							# Pre-orbit swirl so the ball curls in rather than slamming the nozzle.
							var orbit_tangent := Vector2(-to_paddle.y, to_paddle.x).normalized() * (1.0 if player_id == 0 else -1.0)
							b.apply_impulse(orbit_tangent, 900.0 * mag * delta)
		_action_glow = 1.0

	_update_vortex_vfx(delta)

# --- Suction capture / slingshot ------------------------------------------------------------------

func captured_ball() -> Ball:
	return _captured

func is_capturing() -> bool:
	return _captured != null

## Seconds the current capture has been held (0 when free).
func capture_hold_time() -> float:
	return _capture_hold if _captured != null else 0.0

## 0..1: how tight the orbit is (1 at CAPTURE_TIGHTEN_TIME).
func capture_hold_fraction() -> float:
	return clampf(_capture_hold / CAPTURE_TIGHTEN_TIME, 0.0, 1.0) if _captured != null else 0.0

## Seconds until this paddle may capture again after a break-free.
func capture_block_time() -> float:
	return maxf(_capture_block, 0.0)

func capture_center() -> Vector2:
	return global_position + _forward() * CAPTURE_CENTER_OFFSET

## Direction the ball would fly if released right now (tangent, cone-clamped).
func slingshot_direction(aim_hint: Vector2 = Vector2.ZERO) -> Vector2:
	var fwd := _forward()
	if _captured == null or not is_instance_valid(_captured):
		return fwd
	var rel := _captured.global_position - capture_center()
	var tangent := Vector2(-rel.y, rel.x).normalized() * _capture_dir
	if tangent.length_squared() < 0.001:
		tangent = fwd
	var dir := tangent
	if aim_hint.length_squared() > 0.01:
		dir = (tangent * 0.4 + aim_hint.normalized() * 0.6).normalized()
	return _clamp_to_cone(dir, SLINGSHOT_CONE_DEG)

func _can_capture(b: Ball) -> bool:
	if _capture_block > 0.0 or stun_time > 0.0:
		return false
	# Blast / resonance / slingshot windows are uncapturable: the attacker earned the shot.
	if b.speed_override_time > 0.0:
		return false
	return true

func _begin_capture(b: Ball) -> void:
	_captured = b
	b.captured_by = self
	_capture_hold = 0.0
	var rel := b.global_position - capture_center()
	_capture_angle = rel.angle()
	_capture_radius = clampf(rel.length(), CAPTURE_RADIUS_END, CAPTURE_RADIUS_START)
	var cross := rel.x * b.velocity.y - rel.y * b.velocity.x
	if absf(cross) > 20.0:
		_capture_dir = signf(cross)
	else:
		_capture_dir = 1.0 if player_id == 0 else -1.0
	b.speed_override_time = 0.0
	b.emote(7, 0.6, "WHOA")
	emote(3, 0.6, "GOTCHA")
	if vfx_mgr != null:
		vfx_mgr.spawn_hit_burst(b.global_position, team_color, 1.1)
		vfx_mgr.spawn_shockwave(capture_center(), team_color, 360.0, 0.3)
	if fluid_sim != null:
		fluid_sim.inject_vortex(capture_center(), (7.0 if player_id == 0 else -7.0), 240.0, Color(team_color.r, team_color.g, team_color.b, 0.2))
	suck_captured.emit(b.global_position)

## Drives the orbit: angle advances at CAPTURE_ORBIT_SPEED / radius, radius tightens
## with hold time, the ball's velocity is set so it lands on the orbit point this tick.
func _update_capture(delta: float) -> void:
	var b := _captured
	if b == null or not is_instance_valid(b) or b.is_scored or b.is_serving or b.captured_by != self:
		_drop_capture()
		return
	_capture_hold += delta
	if _capture_hold >= CAPTURE_MAX_HOLD:
		_break_free()
		return
	var frac := clampf(_capture_hold / CAPTURE_TIGHTEN_TIME, 0.0, 1.0)
	var want_r := lerpf(CAPTURE_RADIUS_START, CAPTURE_RADIUS_END, frac)
	_capture_radius = lerpf(_capture_radius, want_r, clampf(delta * 6.0, 0.0, 1.0))
	var center := capture_center()
	var rel := b.global_position - center
	if rel.length() > 4.0:
		_capture_angle = rel.angle()
	var omega := CAPTURE_ORBIT_SPEED / maxf(_capture_radius, 40.0)
	_capture_angle += omega * delta * _capture_dir
	var target := center + Vector2(cos(_capture_angle), sin(_capture_angle)) * _capture_radius
	target.y = clampf(target.y, 58.0 + b.radius, 1022.0 - b.radius)
	target.x = clampf(target.x, 60.0, 1860.0)
	var v := (target - b.global_position) / maxf(delta, 0.0001)
	b.velocity = v.limit_length(2600.0)
	b.spin = clampf(b.spin + _capture_dir * 1.5 * delta, -1.0, 1.0)
	if fluid_sim != null:
		# Force only (alpha 0): per-tick dye at this radius would wash the field white.
		fluid_sim.inject_vortex(center, (3.0 + 4.0 * frac) * _capture_dir, _capture_radius * 1.1, Color(team_color.r, team_color.g, team_color.b, 0.0))

## Hold limit reached: the ball pops out along its tangent and this paddle waits before recapturing.
func _break_free() -> void:
	var b := _captured
	var dir := slingshot_direction()
	last_capture_hold = _capture_hold
	_drop_capture()
	_capture_block = CAPTURE_RECAPTURE_BLOCK
	if b != null and is_instance_valid(b):
		b.velocity = dir * 640.0
		b.speed_override_time = 0.15
		b.emote(2, 0.5, "FREE")
		if vfx_mgr != null:
			vfx_mgr.spawn_hit_burst(b.global_position, Color(1.0, 0.95, 0.7), 0.9)
			vfx_mgr.spawn_shockwave(b.global_position, team_color, 220.0, 0.22)
		if fluid_sim != null:
			fluid_sim.inject_shockwave(b.global_position, dir, 1200.0, team_color)
		if audio_mgr != null:
			audio_mgr.trigger_impact(600.0, b.global_position, false)
	emote(5, 0.6, "SLIPPED")

## Silent detach (point reset, stun, menu). `keep_velocity` leaves the orbit velocity on the ball.
func _drop_capture(keep_velocity: bool = true) -> void:
	if _captured == null:
		return
	var b := _captured
	_captured = null
	_capture_hold = 0.0
	if b != null and is_instance_valid(b) and b.captured_by == self:
		b.captured_by = null
		if not keep_velocity or b.velocity.length() < 200.0:
			b.velocity = _forward() * b.min_speed

## Slingshot: fire along the orbit tangent toward the opponent. Speed grows with hold time.
## `aim_hint` (optional) biases the direction (move axis for humans, target corner for AI).
func release_capture(aim_hint: Vector2 = Vector2.ZERO) -> bool:
	if _captured == null:
		return false
	var b := _captured
	if not is_instance_valid(b):
		_captured = null
		return false
	var hint := aim_hint
	if hint == Vector2.ZERO and not is_ai and _move_axis.length() > 0.2:
		hint = Vector2(_forward().x, _move_axis.y * 0.9)
	var dir := slingshot_direction(hint)
	var frac := capture_hold_fraction()
	last_capture_hold = _capture_hold
	var launch_speed := 1100.0 + 500.0 * frac
	_drop_capture()
	launch_speed = minf(launch_speed, b.max_speed)
	b.velocity = dir * launch_speed
	b.spin = clampf(_capture_dir * (0.35 + 0.4 * frac), -1.0, 1.0)
	b.speed_override_time = maxf(b.speed_override_time, 0.4)
	_count_return(b, launch_speed)
	b.emote(9, 0.8, "WHEE")
	emote(2, 0.8, "SLING")
	add_momentum(0.12)
	if fluid_sim != null:
		fluid_sim.inject_shockwave(b.global_position, dir, 3200.0 + 2200.0 * frac, team_color)
		fluid_sim.inject_vortex(b.global_position, -_capture_dir * 5.0, 160.0, Color.WHITE)
	if vfx_mgr != null:
		vfx_mgr.spawn_shockwave(b.global_position, team_color, 380.0 + 240.0 * frac, 0.35)
		vfx_mgr.spawn_hit_burst(b.global_position, Color.WHITE, 1.5 + frac)
		vfx_mgr.apply_camera_kick(dir, 0.9 + 0.8 * frac)
		vfx_mgr.spawn_trajectory(b.global_position, dir * launch_speed, team_color)
	if audio_mgr != null:
		audio_mgr.trigger_impact(launch_speed, b.global_position, true)
	slingshot_fired.emit(b.global_position, launch_speed)
	return true

## A slingshot is a return: it counts toward the rally like a paddle contact.
func _count_return(b: Ball, launch_speed: float) -> void:
	b.rally_hits += 1
	b.last_hitter_id = player_id
	b.touch_mask |= (1 << player_id)
	b.last_hit_speed = launch_speed
	if game_mgr != null and game_mgr.has_method("on_ball_hit_paddle"):
		game_mgr.on_ball_hit_paddle(self, launch_speed, false)

func _update_vortex_vfx(delta: float) -> void:
	var want := 1.0 if is_sucking else 0.0
	_vortex_active = move_toward(_vortex_active, want, delta * (7.0 if is_sucking else 4.0))
	var hold_want := capture_hold_fraction() if _captured != null else 0.0
	_vortex_hold = move_toward(_vortex_hold, hold_want, delta * (4.0 if _captured != null else 6.0))
	if vortex_vfx == null:
		return
	vortex_vfx.visible = _vortex_active > 0.02 or _vortex_hold > 0.02
	if not vortex_vfx.visible:
		return
	var fwd := _forward()
	var center_local := fwd * lerpf(40.0, CAPTURE_CENTER_OFFSET, _vortex_hold)
	vortex_vfx.position = center_local - Vector2(320.0, 320.0)
	if _vortex_mat != null:
		var r_uv := (_capture_radius if _captured != null else CAPTURE_RADIUS_START) / 640.0
		_vortex_mat.set_shader_parameter("active_factor", _vortex_active)
		_vortex_mat.set_shader_parameter("hold", _vortex_hold)
		_vortex_mat.set_shader_parameter("orbit_r", r_uv)
		_vortex_mat.set_shader_parameter("vortex_tint", team_color)

# --- Blast charge --------------------------------------------------------------------------------

func is_charging() -> bool:
	return _charging

## 0..1 charge fraction (BLAST_CHARGE_TIME hold = 1).
func charge_fraction() -> float:
	return clampf(_charge_t / BLAST_CHARGE_TIME, 0.0, 1.0) if _charging else 0.0

## Starts holding a blast. Returns false when on cooldown or stunned.
func begin_blast_charge() -> bool:
	if _charging:
		return true
	if blast_cooldown > 0.0 or stun_time > 0.0 or _is_serving_me():
		return false
	_charging = true
	_charge_t = 0.0
	_charge_announced = false
	return true

## Lets go: a short hold is a plain tap, a long hold is a charged blast.
func release_blast_charge() -> void:
	if not _charging:
		return
	var frac := 0.0
	if _charge_t >= BLAST_TAP_TIME:
		frac = clampf(_charge_t / BLAST_CHARGE_TIME, 0.0, 1.0)
	_charging = false
	_charge_t = 0.0
	_charge_announced = false
	trigger_blast(frac)

func _cancel_charge() -> void:
	_charging = false
	_charge_t = 0.0
	_charge_announced = false

func _update_charge(delta: float) -> void:
	if not _charging:
		return
	_charge_t += delta
	if not _charge_announced and _charge_t >= BLAST_TAP_TIME:
		_charge_announced = true
		blast_charge_started.emit(global_position)
		emote(1, 0.8, "...")
	if _charge_t < BLAST_TAP_TIME:
		return
	var frac := clampf(_charge_t / BLAST_CHARGE_TIME, 0.0, 1.0)
	var fwd := _forward()
	var pos := global_position + fwd * 54.0
	if fluid_sim != null:
		# Cavitation: the field is drawn in before the release.
		fluid_sim.inject_sink(pos, 500.0 + 900.0 * frac, 70.0 + 60.0 * frac, Color(team_color.r, team_color.g, team_color.b, 0.12))
	_action_glow = maxf(_action_glow, 0.5 + 0.5 * frac)
	if _charge_t >= BLAST_CHARGE_TIME + 0.6:
		# Overheld: fire anyway so a stuck key cannot hold a full charge forever.
		release_blast_charge()

# --- Blast / Resonance ---------------------------------------------------------------------------

## True when `b` sits inside this paddle's blast cone for a blast of charge `frac`:
## forward, within reach, and inside a wedge that opens with distance.
func blast_in_cone(b: Ball, frac: float = 0.0) -> bool:
	if b == null or not is_instance_valid(b):
		return false
	var fwd := _forward()
	var to_ball := b.global_position - global_position
	var dx := to_ball.x * fwd.x
	if dx <= 0.0:
		return false
	var reach := 280.0 + 160.0 * clampf(frac, 0.0, 1.0)
	if to_ball.length() >= reach:
		return false
	return absf(to_ball.y) < 64.0 * size_mod + dx * 0.22 + 30.0 * clampf(frac, 0.0, 1.0)

## Fluid shockwave forward. `charge` 0..1 (0 = plain tap). Power = 0.35 + 0.65 * charge.
## Ball impulse scales 1.0x..1.8x with power and is exempt from the rally cap for a moment.
## Momentum only when a ball is actually hit; no free stun bolt.
func trigger_blast(charge: float = 0.0) -> void:
	if try_serve():
		return
	if blast_cooldown > 0.0:
		return
	_cancel_charge()

	var frac := clampf(charge, 0.0, 1.0)
	var power := 0.35 + 0.65 * frac
	blast_cooldown = lerpf(BLAST_COOLDOWN, BLAST_COOLDOWN_CHARGED, frac)
	var forward_dir := _forward()
	var blast_pos := global_position + forward_dir * 54.0
	var impulse_mult := lerpf(1.0, 1.8, frac)
	# Legacy strength scale (1.0 = plain tap) for listeners that predate charging.
	var strength := lerpf(1.0, 1.6, frac)

	if fluid_sim != null:
		fluid_sim.inject_shockwave(blast_pos, forward_dir, 3600.0 * impulse_mult, team_color)
		fluid_sim.inject_vortex(blast_pos, (4.2 if player_id == 0 else -4.2) * impulse_mult, 120.0 + 60.0 * frac, Color.WHITE)

	if vfx_mgr != null:
		vfx_mgr.spawn_shockwave(blast_pos, team_color, 440.0 * impulse_mult, 0.4)
		vfx_mgr.spawn_hit_burst(blast_pos, team_color, 1.6 * impulse_mult)
		vfx_mgr.apply_camera_kick(forward_dir, 0.85 * impulse_mult)
		if vfx_mgr.has_method("spawn_blast_cone"):
			vfx_mgr.call("spawn_blast_cone", blast_pos, forward_dir, team_color, power)

	if audio_mgr != null:
		audio_mgr.trigger_blast(strength, global_position)

	var hit_any := false
	if _captured != null:
		# Blast during a capture: launch straight out, harder than a slingshot.
		var b := _captured
		var launch := (1100.0 + 500.0 * capture_hold_fraction()) * 1.3 * impulse_mult
		var aim := _clamp_to_cone(Vector2(forward_dir.x, (b.global_position.y - global_position.y) * 0.002), SLINGSHOT_CONE_DEG)
		last_capture_hold = _capture_hold
		_drop_capture()
		b.velocity = aim * minf(launch, b.max_speed)
		b.spin = clampf((global_position.y - b.global_position.y) * 0.004, -1.0, 1.0)
		b.speed_override_time = maxf(b.speed_override_time, 0.5)
		_count_return(b, b.velocity.length())
		slingshot_fired.emit(b.global_position, b.velocity.length())
		hit_any = true
	else:
		var balls := get_tree().get_nodes_in_group("cymatics_balls") if get_tree() else []
		for node in balls:
			if node is Ball:
				var b := node as Ball
				if b.is_scored or b.is_serving or b.captured_by != null:
					continue
				var to_ball := b.global_position - global_position
				if blast_in_cone(b, frac):
					var blast_aim := (forward_dir + Vector2(0, to_ball.y * 0.003)).normalized()
					b.speed_override_time = maxf(b.speed_override_time, 0.5 if frac > 0.05 else 0.35)
					b.apply_impulse(blast_aim, 820.0 * impulse_mult)
					b.spin = clampf(b.spin + (to_ball.y * -0.005), -1.0, 1.0)
					hit_any = true

	blast_fired.emit(strength, blast_pos)
	blast_charge_released.emit(blast_pos, power)
	if hit_any:
		add_momentum(0.06 + 0.06 * frac)

## Super. Only fires when momentum is full; returns false otherwise.
## Freeze-frame (0.4 s real time) with a trajectory preview, then a 1900 px/s launch.
func trigger_resonance() -> bool:
	if not is_resonance_ready():
		return false
	momentum = 0.0
	_super_announced = false
	momentum_changed.emit(0.0)
	blast_cooldown = 0.7
	_cancel_charge()

	var forward_dir := _forward()
	var blast_pos := global_position + forward_dir * 70.0
	var target_ball: Ball = null
	if _captured != null and is_instance_valid(_captured):
		target_ball = _captured
		_drop_capture()
	elif ball != null and is_instance_valid(ball) and not ball.is_scored and not ball.is_serving and ball.captured_by == null:
		target_ball = ball

	var aim := forward_dir
	var launch_speed := 1900.0
	if target_ball != null:
		var to_ball := target_ball.global_position - global_position
		if to_ball.length() > 8.0 and (to_ball.x * forward_dir.x) > -40.0:
			aim = (forward_dir * 1.6 + Vector2(0, clampf(to_ball.y * 0.004, -0.4, 0.4))).normalized()
		launch_speed = minf(launch_speed, target_ball.max_speed)
		target_ball.speed_override_time = maxf(target_ball.speed_override_time, 0.7)
		target_ball.velocity = aim * launch_speed
		target_ball.spin = clampf((-to_ball.y) * 0.004 + (0.45 if player_id == 0 else -0.45), -1.0, 1.0)
		target_ball.last_hitter_id = player_id
		target_ball.touch_mask |= (1 << player_id)

	_resonance_freeze()

	if vfx_mgr != null:
		vfx_mgr.spawn_shockwave(blast_pos, Color.WHITE, 820.0, 0.7)
		vfx_mgr.spawn_hit_burst(blast_pos, team_color, 3.4)
		vfx_mgr.apply_camera_kick(forward_dir, 2.2)
		vfx_mgr.flash_screen(Color.WHITE, 0.35, 0.16)
		if target_ball != null:
			vfx_mgr.spawn_trajectory(target_ball.global_position, aim * launch_speed, team_color)
			vfx_mgr.spawn_trajectory(target_ball.global_position, aim * launch_speed, Color.WHITE)

	if audio_mgr != null:
		audio_mgr.trigger_super(global_position)

	if fluid_sim != null:
		fluid_sim.inject_shockwave(blast_pos, forward_dir, 5200.0, Color.WHITE)
		fluid_sim.inject_vortex(blast_pos, 6.0 if player_id == 0 else -6.0, 200.0, Color.WHITE)

	resonance_fired.emit(blast_pos)
	return true

## Freeze-frame via the TimeController (hit-stop priority) for 0.4 s of real time.
func _resonance_freeze() -> void:
	var tc: TimeController = game_mgr.time_ctrl if game_mgr != null else null
	var tree := get_tree()
	if tc == null or tree == null:
		if vfx_mgr != null:
			vfx_mgr.apply_hit_stop(0.4, 0.05)
		return
	tc.push(&"resonance", 0.05, TimeController.PRIO_HITSTOP)
	var timer := tree.create_timer(0.4, false, false, true)
	timer.timeout.connect(func():
		if is_instance_valid(tc):
			tc.pop(&"resonance")
	)

# --- Visuals -----------------------------------------------------------------------------------------

func _update_visuals(delta: float) -> void:
	_action_glow = move_toward(_action_glow, 1.0 if (is_shooting or is_sucking) else 0.0, delta * 8.0)
	if visual_core != null:
		var charge := charge_fraction()
		var want_scale := Vector2(size_mod, size_mod) * (1.0 - 0.08 * charge)
		visual_core.scale = visual_core.scale.lerp(want_scale, clampf(delta * 12.0, 0.0, 1.0))
	if face != null:
		face.scale = Vector2(size_mod, size_mod)
		face.position = Vector2((6.0 if player_id == 0 else -6.0) * size_mod, -8.0 * size_mod)
	if _cannon != null:
		_cannon.visible = armed_time > 0.0
		if armed_time > 0.0:
			_cannon.color = Color(1.0, 0.95, 0.4, 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.02))
	if _body_mat != null:
		_body_mat.set_shader_parameter("glow_color", team_color)
		_body_mat.set_shader_parameter("shape_type", int(shape_type))
		_body_mat.set_shader_parameter("flip", 1.0 if player_id == 1 else 0.0)
		var ready := 1.0 if momentum >= 1.0 else momentum * 0.35
		if armed_time > 0.0:
			ready = 1.0
		if parry_window > 0.0:
			ready = 1.0
		_body_mat.set_shader_parameter("ready_factor", ready)
		_body_mat.set_shader_parameter("action_factor", _action_glow)
		_body_mat.set_shader_parameter("charge", charge_fraction() if _charge_t >= BLAST_TAP_TIME else 0.0)
		_body_mat.set_shader_parameter("time_pulse", Time.get_ticks_msec() * 0.001)

func _update_face() -> void:
	if face == null:
		return
	if ball != null and is_instance_valid(ball) and not ball.is_scored:
		face.look_at_point(global_position, ball.global_position)
		var incoming := (ball.velocity.x < 0.0 and player_id == 0) or (ball.velocity.x > 0.0 and player_id == 1)
		var close := absf(ball.global_position.x - global_position.x) < 400.0
		if _captured != null:
			face.maybe_mood(3, 0.2)
		elif incoming and close and ball.velocity.length() > 1100.0:
			face.maybe_mood(7, 0.28)
		elif momentum >= 1.0:
			face.maybe_mood(1, 0.2)
	else:
		face.look_at_point(global_position, Vector2(960, 540))
