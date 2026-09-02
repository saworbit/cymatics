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

## Sentinel duration marking a stage (boss loadout) mod that survives point
## resets. Not a feel value: `TournamentManager` passes it by name.
const STAGE_MOD_DURATION := 9999.0
const DEFAULT_TUNING := "res://src/tuning/paddle_default.tres"

@export var player_id := 0
@export var is_ai := false
## Every feel constant lives here. Swap the resource to retune without code.
@export var tuning: PaddleTuning
@export var team_color := Color(0.0, 0.9, 1.0, 1.0)

# Mirrors of the tuning values other systems read or write directly
# (TournamentManager raises `speed` per stage). Seeded in _ready().
var speed := 0.0
var shoot_force := 0.0
var suck_force := 0.0

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
var _capture_radius := 0.0
var _capture_dir := 1.0
var _capture_block := 0.0
## Hold time of the most recent slingshot/break-free (telemetry).
var last_capture_hold := 0.0
var _vortex_active := 0.0
var _vortex_hold := 0.0
var _vortex_mat: ShaderMaterial
## Serve aim (unit vector, kept within tuning.serve_cone_deg of forward).
var serve_aim_dir := Vector2.RIGHT
var _serve_aim_last_emitted := Vector2.ZERO
var _serve_aim_node: Node2D
## Move axis this tick (stick/keys), used by serve aim and slingshot bias.
var _move_axis := Vector2.ZERO

var min_x := 0.0
var max_x := 0.0
var min_y := 0.0
var max_y := 0.0

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
	_ensure_tuning()
	z_index = 6
	if player_id == 1:
		team_color = Color(1.0, 0.0, 0.67, 1.0)
		min_x = tuning.arena_width - tuning.max_x
		max_x = tuning.arena_width - tuning.min_x
	serve_aim_dir = _forward()
	_setup_visuals()

## Loads the default tuning when no resource was assigned, then seeds the
## fields other systems read or write directly.
func _ensure_tuning() -> void:
	if tuning == null:
		tuning = load(DEFAULT_TUNING) as PaddleTuning
	speed = tuning.move_speed
	shoot_force = tuning.shoot_force
	suck_force = tuning.suck_force
	min_x = tuning.min_x
	max_x = tuning.max_x
	min_y = tuning.min_y
	max_y = tuning.max_y
	_capture_radius = tuning.capture_radius_start

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
		# Big enough to frame the widest orbit around the orbit centre.
		vortex_vfx.offset_left = -tuning.vortex_half_size
		vortex_vfx.offset_top = -tuning.vortex_half_size
		vortex_vfx.offset_right = tuning.vortex_half_size
		vortex_vfx.offset_bottom = tuning.vortex_half_size
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
	_serve_aim_node.call("setup", team_color, _forward(), tuning.serve_cone_deg)
	_serve_aim_node.visible = false

	face = preload("res://src/actors/character_face.gd").new()
	add_child(face)
	# Padd (P1, left): wide eager eyes facing right (+X). Lin (P2, right): smug half-lids facing left (-X).
	var lid := 0.05 if player_id == 0 else 0.42
	face.setup(Vector2(92, 128), player_id == 1, lid)
	face.position = Vector2(6.0 if player_id == 0 else -6.0, -8.0)


## Repaint every material that bakes in the team colour. `team_color` is set
## once in `_setup_visuals`, so changing it later (colourblind palettes, boss
## stage colours) needs this to push the new value through.
func apply_team_color(col: Color) -> void:
	team_color = col
	if _body_mat != null:
		_body_mat.set_shader_parameter("glow_color", col)
	if _beam_mat != null:
		_beam_mat.set_shader_parameter("beam_color", col)
	if _vortex_mat != null:
		_vortex_mat.set_shader_parameter("vortex_tint", col)
	if _serve_aim_node != null and _serve_aim_node.has_method("setup"):
		_serve_aim_node.call("setup", col, _forward(), tuning.serve_cone_deg)

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
	return velocity.limit_length(speed * tuning.hit_velocity_cap_factor)

# --- Parry / momentum --------------------------------------------------------------

func consume_parry() -> bool:
	if parry_window > 0.0:
		parry_window = 0.0
		_parry_pending = false
		parried.emit(global_position)
		return true
	return false

func _ball_incoming_close() -> bool:
	var t := tuning
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
			var incoming := b.velocity.x * fwd_x < -t.parry_incoming_speed
			var dx := (b.global_position.x - global_position.x) * fwd_x
			if incoming and dx > t.parry_behind_slack and dx < t.parry_range:
				return true
	return false

## Tap when the ball is incoming and close: opens a 5-frame perfect-hit window.
## Only opens off cooldown; a whiff costs tuning.parry_cooldown.
func try_parry() -> bool:
	if parry_cooldown > 0.0 or stun_time > 0.0:
		return false
	parry_window = tuning.parry_window
	_parry_pending = true
	parry_opened.emit(global_position)
	if vfx_mgr != null:
		vfx_mgr.spawn_hit_burst(global_position + _forward() * 30.0, Color(1.0, 1.0, 1.0, 0.9), 0.55)
	return true

func register_hit(perfect: bool, hit_speed: float) -> void:
	var t := tuning
	var gain := t.momentum_hit_gain + minf(hit_speed / t.momentum_speed_divisor, t.momentum_speed_cap)
	if perfect:
		gain += t.momentum_perfect_bonus
		emote(3, 0.85, "NICE")
	else:
		emote(2 if hit_speed > 1200.0 else 1, 0.45, "HA")
	add_momentum(gain)
	if visual_core != null:
		visual_core.scale = Vector2(t.hit_squash.x * size_mod, t.hit_squash.y * size_mod)

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
	return momentum >= tuning.resonance_ready_threshold

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
	var base_h := tuning.half_height
	if shape_type == Shape.FORTRESS:
		base_h = tuning.half_height_fortress
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
		var body := tuning.body_size
		if shape_type == Shape.FORTRESS:
			body = tuning.body_size_fortress
		elif shape_type == Shape.WEDGE:
			body = tuning.body_size_wedge
		(shape_node.shape as RectangleShape2D).size = body * s

# --- Stun bolt ---------------------------------------------------------------------

## Only fires when armed via the STUN powerup.
func fire_stun_bolt() -> bool:
	if armed_time <= 0.0 or stun_cooldown > 0.0 or stun_time > 0.0:
		return false
	var t := tuning
	stun_cooldown = t.stun_cooldown
	var fwd := _forward()
	var origin := global_position + fwd * t.stun_bolt_offset
	var stun_len := t.stun_duration
	call_deferred("_spawn_stun_bolt", origin, fwd, stun_len)
	if vfx_mgr != null:
		vfx_mgr.spawn_hit_burst(global_position + fwd * t.stun_burst_offset, team_color, t.stun_burst_scale)
		vfx_mgr.apply_camera_kick(fwd, t.stun_camera_kick)
	if audio_mgr != null:
		audio_mgr.trigger_blast(t.stun_audio_strength, global_position)
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
			parry_cooldown = tuning.parry_cooldown
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
		velocity = velocity.move_toward(Vector2.ZERO, tuning.friction_blocked * delta)
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
		velocity = velocity.move_toward(Vector2.ZERO, tuning.friction_stunned * delta)
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
	var cur_min_y := tuning.wall_top_y + hh + tuning.wall_pad
	var cur_max_y := tuning.wall_bottom_y - hh - tuning.wall_pad
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
		if (event as InputEventMouseMotion).relative.length() > tuning.mouse_switch_px:
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
		if jm.device == 0 and (jm.axis == JOY_AXIS_LEFT_X or jm.axis == JOY_AXIS_LEFT_Y) and absf(jm.axis_value) > tuning.stick_deadzone + 0.1:
			next = InputDevice.KEYS
	if next != input_device:
		input_device = next
		input_device_changed.emit(int(input_device))

func _handle_player_input(delta: float) -> void:
	var t := tuning
	var prefix := "p1_" if player_id == 0 else "p2_"
	# Analog magnitude preserved (no normalize).
	var input_dir := Input.get_vector(prefix + "left", prefix + "right", prefix + "up", prefix + "down", t.stick_deadzone)
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

	var accel := t.accel
	var friction := t.friction

	# Mouse follow for P1: 1-to-1 tracking in world space, only while the mouse is the active device.
	if player_id == 0 and input_device == InputDevice.MOUSE:
		var mouse := _play_mouse()
		var hh := _get_half_height()
		var cur_min_y := t.wall_top_y + hh + t.wall_pad
		var cur_max_y := t.wall_bottom_y - hh - t.wall_pad
		var target := Vector2(clampf(mouse.x, min_x, max_x), clampf(mouse.y, cur_min_y, cur_max_y))
		var diff := target - global_position
		velocity = diff * t.mouse_gain
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
	var t := tuning
	var fwd := _forward()
	var target := serve_aim_dir
	if is_ai:
		target = _ai_serve_aim()
	elif player_id == 0 and input_device == InputDevice.MOUSE:
		# Point at where the serve should go: mouse relative to the held ball.
		var origin := global_position + fwd * t.serve_offset
		var rel := _play_mouse() - origin
		if rel.length() > t.serve_mouse_deadzone and rel.dot(fwd) > 0.0:
			target = rel
	elif _move_axis.length() > t.serve_stick_deadzone:
		var y := clampf(_move_axis.y, -1.0, 1.0)
		target = Vector2(fwd.x * (1.0 - t.serve_stick_forward_pull * absf(y)), y * t.serve_stick_y_scale)
	target = _clamp_to_cone(target, t.serve_cone_deg)
	serve_aim_dir = serve_aim_dir.slerp(target, clampf(delta * t.serve_aim_slerp, 0.0, 1.0)).normalized()
	if _serve_aim_last_emitted == Vector2.ZERO or absf(serve_aim_dir.angle_to(_serve_aim_last_emitted)) > deg_to_rad(t.serve_aim_emit_deg):
		_serve_aim_last_emitted = serve_aim_dir
		serve_aimed.emit(serve_aim_dir)
	if _serve_aim_node != null:
		_serve_aim_node.visible = true
		_serve_aim_node.call("set_aim", serve_aim_dir, fwd * t.serve_offset)

## AI picks the far side from the opponent; refreshed each serve by the AI's own timer.
var _ai_serve_target := Vector2.ZERO

func _ai_serve_aim() -> Vector2:
	var t := tuning
	var fwd := _forward()
	if _ai_serve_target == Vector2.ZERO:
		var foe_y := 540.0
		if ball != null and is_instance_valid(ball):
			var foe: Paddle = ball.paddle_right if player_id == 0 else ball.paddle_left
			if foe != null and is_instance_valid(foe):
				foe_y = foe.global_position.y
		var open_y := t.ai_serve_open_y if foe_y < 540.0 else t.ai_serve_closed_y
		var far_x := t.ai_serve_target_x if player_id == 0 else t.arena_width - t.ai_serve_target_x
		var origin := global_position + fwd * t.serve_offset
		var to := Vector2(far_x, open_y + randf_range(-t.ai_serve_y_jitter, t.ai_serve_y_jitter)) - origin
		_ai_serve_target = _clamp_to_cone(to, t.ai_serve_cone_deg)
	return _ai_serve_target

func try_serve() -> bool:
	if ball == null or not is_instance_valid(ball):
		return false
	if not ball.is_serving or ball.serve_paddle != self:
		return false
	var aim := _clamp_to_cone(serve_aim_dir, tuning.serve_cone_deg)
	ball.launch_serve(aim, tuning.serve_speed)
	blast_cooldown = tuning.serve_blast_cooldown
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
	var t := tuning
	var forward_dir := _forward()
	var nozzle_pos := global_position + forward_dir * t.nozzle_offset

	if velocity.length() > t.wake_speed_threshold and fluid_sim != null:
		var wake := velocity.normalized()
		fluid_sim.inject_force(global_position, wake * t.wake_force, t.wake_radius, Color(team_color.r, team_color.g, team_color.b, 0.38))
		var flank := Vector2(-wake.y, wake.x) * t.wake_flank_offset
		var eddy := Color(team_color.r, team_color.g, team_color.b, 0.22)
		fluid_sim.inject_vortex(global_position + flank, t.wake_flank_vortex, t.wake_flank_radius, eddy)
		fluid_sim.inject_vortex(global_position - flank, -t.wake_flank_vortex, t.wake_flank_radius, eddy)
		if audio_mgr != null:
			audio_mgr.register_paddle_movement(velocity.length(), global_position.x / t.arena_width)

	var balls := get_tree().get_nodes_in_group("cymatics_balls") if get_tree() else []
	var mag := t.magnet_multiplier if magnet_time > 0.0 else 1.0

	if is_shooting and fluid_sim != null:
		var stream_dir := (forward_dir + Vector2(0, velocity.y * t.stream_vy_bend)).normalized()
		fluid_sim.inject_force(nozzle_pos, stream_dir * (shoot_force * mag), t.stream_radius * mag, Color(team_color.r, team_color.g, team_color.b, 0.78))
		fluid_sim.inject_vortex(nozzle_pos + stream_dir * t.stream_vortex_distance, (t.stream_vortex if player_id == 0 else -t.stream_vortex) * mag, t.stream_vortex_radius, Color(team_color.r, team_color.g, team_color.b, 0.4))
		for node in balls:
			if node is Ball:
				var b := node as Ball
				if b.is_scored or b.is_serving or b.captured_by != null:
					continue
				var to_ball := b.global_position - global_position
				var in_front := (to_ball.x * forward_dir.x) > 0.0
				if in_front and to_ball.length() < t.stream_ball_range * mag and absf(to_ball.y) < t.stream_ball_lane * size_mod:
					var jet_push := stream_dir * (t.stream_ball_push * mag * delta)
					b.apply_impulse(jet_push.normalized(), jet_push.length())
					b.spin = clampf(b.spin + (stream_dir.y * t.stream_ball_spin * delta), -1.0, 1.0)
		_action_glow = 1.0
		if _beam:
			_beam.visible = true
			_beam_mat.set_shader_parameter("intensity", t.stream_beam_intensity * mag)
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
		var swirl_dir := t.suck_vortex if player_id == 0 else -t.suck_vortex
		# Low dye alpha: these run every tick, anything higher saturates a 300 px disc to white.
		fluid_sim.inject_sink(nozzle_pos, suck_force * mag, t.suck_radius * mag, Color(team_color.r, team_color.g, team_color.b, 0.08))
		fluid_sim.inject_vortex(nozzle_pos, swirl_dir * mag, t.suck_vortex_radius * mag, Color(team_color.r, team_color.g, team_color.b, 0.06))

		if _captured == null:
			for node in balls:
				if node is Ball:
					var b := node as Ball
					if b.is_scored or b.is_serving or b.captured_by != null:
						continue
					var to_paddle := nozzle_pos - b.global_position
					var in_front := (to_paddle.x * -forward_dir.x) > 0.0
					var dist := to_paddle.length()
					if in_front and dist < t.capture_range * mag and _can_capture(b):
						_begin_capture(b)
						break
					if in_front and dist < t.suck_pull_range * mag:
						# Inward gravitational pull
						var pull_strength := clampf(1.0 - dist / (t.suck_pull_range * mag), t.suck_pull_min_factor, 1.0) * t.suck_pull_force * mag
						b.apply_impulse(to_paddle.normalized(), pull_strength * delta)
						if dist < t.suck_preorbit_range * mag:
							# Pre-orbit swirl so the ball curls in rather than slamming the nozzle.
							var orbit_tangent := Vector2(-to_paddle.y, to_paddle.x).normalized() * (1.0 if player_id == 0 else -1.0)
							b.apply_impulse(orbit_tangent, t.suck_preorbit_force * mag * delta)
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

## 0..1: how tight the orbit is (1 at tuning.capture_tighten_time).
func capture_hold_fraction() -> float:
	return clampf(_capture_hold / tuning.capture_tighten_time, 0.0, 1.0) if _captured != null else 0.0

## Seconds until this paddle may capture again after a break-free.
func capture_block_time() -> float:
	return maxf(_capture_block, 0.0)

func capture_center() -> Vector2:
	return global_position + _forward() * tuning.capture_center_offset

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
		dir = (tangent * tuning.slingshot_tangent_weight + aim_hint.normalized() * tuning.slingshot_hint_weight).normalized()
	return _clamp_to_cone(dir, tuning.slingshot_cone_deg)

func _can_capture(b: Ball) -> bool:
	if _capture_block > 0.0 or stun_time > 0.0:
		return false
	# Blast / resonance / slingshot windows are uncapturable: the attacker earned the shot.
	if b.speed_override_time > 0.0:
		return false
	return true

func _begin_capture(b: Ball) -> void:
	var t := tuning
	_captured = b
	b.captured_by = self
	_capture_hold = 0.0
	var rel := b.global_position - capture_center()
	_capture_angle = rel.angle()
	_capture_radius = clampf(rel.length(), t.capture_radius_end, t.capture_radius_start)
	var cross := rel.x * b.velocity.y - rel.y * b.velocity.x
	if absf(cross) > t.capture_dir_cross_threshold:
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
		fluid_sim.inject_vortex(capture_center(), (t.capture_begin_vortex if player_id == 0 else -t.capture_begin_vortex), t.capture_begin_vortex_radius, Color(team_color.r, team_color.g, team_color.b, 0.2))
	suck_captured.emit(b.global_position)

## Drives the orbit: angle advances at capture_orbit_speed / radius, radius tightens
## with hold time, the ball's velocity is set so it lands on the orbit point this tick.
func _update_capture(delta: float) -> void:
	var t := tuning
	var b := _captured
	if b == null or not is_instance_valid(b) or b.is_scored or b.is_serving or b.captured_by != self:
		_drop_capture()
		return
	_capture_hold += delta
	if _capture_hold >= t.capture_max_hold:
		_break_free()
		return
	var frac := clampf(_capture_hold / t.capture_tighten_time, 0.0, 1.0)
	var want_r := lerpf(t.capture_radius_start, t.capture_radius_end, frac)
	_capture_radius = lerpf(_capture_radius, want_r, clampf(delta * t.capture_radius_lerp, 0.0, 1.0))
	var center := capture_center()
	var rel := b.global_position - center
	if rel.length() > 4.0:
		_capture_angle = rel.angle()
	var omega := t.capture_orbit_speed / maxf(_capture_radius, t.capture_orbit_min_radius)
	_capture_angle += omega * delta * _capture_dir
	var target := center + Vector2(cos(_capture_angle), sin(_capture_angle)) * _capture_radius
	target.y = clampf(target.y, t.capture_clamp_min_y + b.radius, t.capture_clamp_max_y - b.radius)
	target.x = clampf(target.x, t.capture_clamp_min_x, t.capture_clamp_max_x)
	var v := (target - b.global_position) / maxf(delta, 0.0001)
	b.velocity = v.limit_length(t.capture_velocity_cap)
	b.spin = clampf(b.spin + _capture_dir * t.capture_spin_gain * delta, -1.0, 1.0)
	if fluid_sim != null:
		# Force only (alpha 0): per-tick dye at this radius would wash the field white.
		fluid_sim.inject_vortex(center, (t.capture_vortex_base + t.capture_vortex_gain * frac) * _capture_dir, _capture_radius * t.capture_vortex_radius_scale, Color(team_color.r, team_color.g, team_color.b, 0.0))

## Hold limit reached: the ball pops out along its tangent and this paddle waits before recapturing.
func _break_free() -> void:
	var b := _captured
	var dir := slingshot_direction()
	last_capture_hold = _capture_hold
	_drop_capture()
	_capture_block = tuning.capture_recapture_block
	if b != null and is_instance_valid(b):
		b.velocity = dir * tuning.break_free_speed
		b.speed_override_time = tuning.break_free_override
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
		if not keep_velocity or b.velocity.length() < tuning.capture_drop_min_velocity:
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
	var t := tuning
	var hint := aim_hint
	if hint == Vector2.ZERO and not is_ai and _move_axis.length() > t.slingshot_hint_deadzone:
		hint = Vector2(_forward().x, _move_axis.y * t.slingshot_hint_y_scale)
	var dir := slingshot_direction(hint)
	var frac := capture_hold_fraction()
	last_capture_hold = _capture_hold
	var launch_speed := t.slingshot_speed + t.slingshot_speed_hold_bonus * frac
	_drop_capture()
	launch_speed = minf(launch_speed, b.max_speed)
	b.velocity = dir * launch_speed
	b.spin = clampf(_capture_dir * (t.slingshot_spin_base + t.slingshot_spin_hold_bonus * frac), -1.0, 1.0)
	b.speed_override_time = maxf(b.speed_override_time, t.slingshot_override)
	_count_return(b, launch_speed)
	b.emote(9, 0.8, "WHEE")
	emote(2, 0.8, "SLING")
	add_momentum(t.slingshot_momentum)
	if fluid_sim != null:
		fluid_sim.inject_shockwave(b.global_position, dir, t.slingshot_fluid_shock + t.slingshot_fluid_shock_hold * frac, team_color)
		fluid_sim.inject_vortex(b.global_position, -_capture_dir * t.slingshot_fluid_vortex, t.slingshot_fluid_vortex_radius, Color.WHITE)
	if vfx_mgr != null:
		vfx_mgr.spawn_shockwave(b.global_position, team_color, t.slingshot_vfx_shock + t.slingshot_vfx_shock_hold * frac, 0.35)
		vfx_mgr.spawn_hit_burst(b.global_position, Color.WHITE, t.slingshot_vfx_burst + frac)
		vfx_mgr.apply_camera_kick(dir, t.slingshot_camera_kick + t.slingshot_camera_kick_hold * frac)
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
	var t := tuning
	var want := 1.0 if is_sucking else 0.0
	_vortex_active = move_toward(_vortex_active, want, delta * (t.vortex_fade_in if is_sucking else t.vortex_fade_out))
	var hold_want := capture_hold_fraction() if _captured != null else 0.0
	_vortex_hold = move_toward(_vortex_hold, hold_want, delta * (t.vortex_hold_in if _captured != null else t.vortex_hold_out))
	if vortex_vfx == null:
		return
	vortex_vfx.visible = _vortex_active > 0.02 or _vortex_hold > 0.02
	if not vortex_vfx.visible:
		return
	var fwd := _forward()
	var center_local := fwd * lerpf(t.nozzle_offset, t.capture_center_offset, _vortex_hold)
	vortex_vfx.position = center_local - Vector2(t.vortex_half_size, t.vortex_half_size)
	if _vortex_mat != null:
		var r_uv := (_capture_radius if _captured != null else t.capture_radius_start) / t.vortex_uv_divisor
		_vortex_mat.set_shader_parameter("active_factor", _vortex_active)
		_vortex_mat.set_shader_parameter("hold", _vortex_hold)
		_vortex_mat.set_shader_parameter("orbit_r", r_uv)
		_vortex_mat.set_shader_parameter("vortex_tint", team_color)

# --- Blast charge --------------------------------------------------------------------------------

func is_charging() -> bool:
	return _charging

## 0..1 charge fraction (tuning.blast_charge_time hold = 1).
func charge_fraction() -> float:
	return clampf(_charge_t / tuning.blast_charge_time, 0.0, 1.0) if _charging else 0.0

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
	if _charge_t >= tuning.blast_tap_time:
		frac = clampf(_charge_t / tuning.blast_charge_time, 0.0, 1.0)
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
	var t := tuning
	_charge_t += delta
	if not _charge_announced and _charge_t >= t.blast_tap_time:
		_charge_announced = true
		blast_charge_started.emit(global_position)
		emote(1, 0.8, "...")
	if _charge_t < t.blast_tap_time:
		return
	var frac := clampf(_charge_t / t.blast_charge_time, 0.0, 1.0)
	var fwd := _forward()
	var pos := global_position + fwd * t.blast_offset
	if fluid_sim != null:
		# Cavitation: the field is drawn in before the release.
		fluid_sim.inject_sink(pos, t.charge_sink_force + t.charge_sink_force_gain * frac, t.charge_sink_radius + t.charge_sink_radius_gain * frac, Color(team_color.r, team_color.g, team_color.b, 0.12))
	_action_glow = maxf(_action_glow, 0.5 + 0.5 * frac)
	if _charge_t >= t.blast_charge_time + t.blast_overhold_extra:
		# Overheld: fire anyway so a stuck key cannot hold a full charge forever.
		release_blast_charge()

# --- Blast / Resonance ---------------------------------------------------------------------------

## True when `b` sits inside this paddle's blast cone for a blast of charge `frac`:
## forward, within reach, and inside a wedge that opens with distance.
func blast_in_cone(b: Ball, frac: float = 0.0) -> bool:
	if b == null or not is_instance_valid(b):
		return false
	var t := tuning
	var fwd := _forward()
	var to_ball := b.global_position - global_position
	var dx := to_ball.x * fwd.x
	if dx <= 0.0:
		return false
	var reach := t.blast_reach + t.blast_reach_charge * clampf(frac, 0.0, 1.0)
	if to_ball.length() >= reach:
		return false
	return absf(to_ball.y) < t.blast_cone_half_height * size_mod + dx * t.blast_cone_spread + t.blast_cone_charge_bonus * clampf(frac, 0.0, 1.0)

## Fluid shockwave forward. `charge` 0..1 (0 = plain tap). Power = 0.35 + 0.65 * charge.
## Ball impulse scales 1.0x..1.8x with power and is exempt from the rally cap for a moment.
## Momentum only when a ball is actually hit; no free stun bolt.
func trigger_blast(charge: float = 0.0) -> void:
	if try_serve():
		return
	if blast_cooldown > 0.0:
		return
	_cancel_charge()

	var t := tuning
	var frac := clampf(charge, 0.0, 1.0)
	var power := t.blast_power_base + t.blast_power_scale * frac
	blast_cooldown = lerpf(t.blast_cooldown, t.blast_cooldown_charged, frac)
	var forward_dir := _forward()
	var blast_pos := global_position + forward_dir * t.blast_offset
	var impulse_mult := lerpf(t.blast_impulse_min, t.blast_impulse_max, frac)
	# Legacy strength scale (1.0 = plain tap) for listeners that predate charging.
	var strength := lerpf(t.blast_strength_min, t.blast_strength_max, frac)

	if fluid_sim != null:
		fluid_sim.inject_shockwave(blast_pos, forward_dir, t.blast_fluid_shock * impulse_mult, team_color)
		fluid_sim.inject_vortex(blast_pos, (t.blast_fluid_vortex if player_id == 0 else -t.blast_fluid_vortex) * impulse_mult, t.blast_fluid_vortex_radius + t.blast_fluid_vortex_radius_charge * frac, Color.WHITE)

	if vfx_mgr != null:
		vfx_mgr.spawn_shockwave(blast_pos, team_color, t.blast_vfx_shock_radius * impulse_mult, 0.4)
		vfx_mgr.spawn_hit_burst(blast_pos, team_color, t.blast_vfx_burst * impulse_mult)
		vfx_mgr.apply_camera_kick(forward_dir, t.blast_camera_kick * impulse_mult)
		if vfx_mgr.has_method("spawn_blast_cone"):
			vfx_mgr.call("spawn_blast_cone", blast_pos, forward_dir, team_color, power)

	if audio_mgr != null:
		audio_mgr.trigger_blast(strength, global_position)

	var hit_any := false
	if _captured != null:
		# Blast during a capture: launch straight out, harder than a slingshot.
		var b := _captured
		var launch := (t.slingshot_speed + t.slingshot_speed_hold_bonus * capture_hold_fraction()) * t.blast_capture_launch_mult * impulse_mult
		var aim := _clamp_to_cone(Vector2(forward_dir.x, (b.global_position.y - global_position.y) * t.blast_capture_aim_scale), t.slingshot_cone_deg)
		last_capture_hold = _capture_hold
		_drop_capture()
		b.velocity = aim * minf(launch, b.max_speed)
		b.spin = clampf((global_position.y - b.global_position.y) * t.blast_capture_spin_scale, -1.0, 1.0)
		b.speed_override_time = maxf(b.speed_override_time, t.blast_capture_override)
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
					var blast_aim := (forward_dir + Vector2(0, to_ball.y * t.blast_aim_y_scale)).normalized()
					b.speed_override_time = maxf(b.speed_override_time, t.blast_override_charged if frac > t.blast_charged_threshold else t.blast_override_tap)
					b.apply_impulse(blast_aim, t.blast_ball_impulse * impulse_mult)
					b.spin = clampf(b.spin + (to_ball.y * t.blast_spin_scale), -1.0, 1.0)
					hit_any = true

	blast_fired.emit(strength, blast_pos)
	blast_charge_released.emit(blast_pos, power)
	if hit_any:
		add_momentum(t.blast_momentum_base + t.blast_momentum_charge * frac)

## Super. Only fires when momentum is full; returns false otherwise.
## Freeze-frame (0.4 s real time) with a trajectory preview, then a 1900 px/s launch.
func trigger_resonance() -> bool:
	if not is_resonance_ready():
		return false
	momentum = 0.0
	_super_announced = false
	momentum_changed.emit(0.0)
	var t := tuning
	blast_cooldown = t.resonance_cooldown
	_cancel_charge()

	var forward_dir := _forward()
	var blast_pos := global_position + forward_dir * t.resonance_offset
	var target_ball: Ball = null
	if _captured != null and is_instance_valid(_captured):
		target_ball = _captured
		_drop_capture()
	elif ball != null and is_instance_valid(ball) and not ball.is_scored and not ball.is_serving and ball.captured_by == null:
		target_ball = ball

	var aim := forward_dir
	var launch_speed := t.resonance_launch_speed
	if target_ball != null:
		var to_ball := target_ball.global_position - global_position
		if to_ball.length() > 8.0 and (to_ball.x * forward_dir.x) > t.resonance_behind_limit:
			aim = (forward_dir * t.resonance_aim_forward + Vector2(0, clampf(to_ball.y * t.resonance_aim_y_scale, -t.resonance_aim_y_clamp, t.resonance_aim_y_clamp))).normalized()
		launch_speed = minf(launch_speed, target_ball.max_speed)
		target_ball.speed_override_time = maxf(target_ball.speed_override_time, t.resonance_override)
		target_ball.velocity = aim * launch_speed
		target_ball.spin = clampf((-to_ball.y) * t.resonance_spin_scale + (t.resonance_spin_bias if player_id == 0 else -t.resonance_spin_bias), -1.0, 1.0)
		target_ball.last_hitter_id = player_id
		target_ball.touch_mask |= (1 << player_id)

	_resonance_freeze()

	if vfx_mgr != null:
		vfx_mgr.spawn_shockwave(blast_pos, Color.WHITE, t.resonance_vfx_shock, t.resonance_vfx_shock_time)
		vfx_mgr.spawn_hit_burst(blast_pos, team_color, t.resonance_vfx_burst)
		vfx_mgr.apply_camera_kick(forward_dir, t.resonance_camera_kick)
		vfx_mgr.flash_screen(Color.WHITE, t.resonance_flash_alpha, t.resonance_flash_time)
		if target_ball != null:
			vfx_mgr.spawn_trajectory(target_ball.global_position, aim * launch_speed, team_color)
			vfx_mgr.spawn_trajectory(target_ball.global_position, aim * launch_speed, Color.WHITE)

	if audio_mgr != null:
		audio_mgr.trigger_super(global_position)

	if fluid_sim != null:
		fluid_sim.inject_shockwave(blast_pos, forward_dir, t.resonance_fluid_shock, Color.WHITE)
		fluid_sim.inject_vortex(blast_pos, t.resonance_fluid_vortex if player_id == 0 else -t.resonance_fluid_vortex, t.resonance_fluid_vortex_radius, Color.WHITE)

	resonance_fired.emit(blast_pos)
	return true

## Freeze-frame via the TimeController (hit-stop priority) in real time.
func _resonance_freeze() -> void:
	var t := tuning
	var tc: TimeController = game_mgr.time_ctrl if game_mgr != null else null
	var tree := get_tree()
	if tc == null or tree == null:
		if vfx_mgr != null:
			vfx_mgr.apply_hit_stop(t.resonance_freeze_time, t.resonance_freeze_scale)
		return
	tc.push(&"resonance", t.resonance_freeze_scale, TimeController.PRIO_HITSTOP)
	var timer := tree.create_timer(t.resonance_freeze_time, false, false, true)
	timer.timeout.connect(func():
		if is_instance_valid(tc):
			tc.pop(&"resonance")
	)

# --- Visuals -----------------------------------------------------------------------------------------

func _update_visuals(delta: float) -> void:
	var t := tuning
	_action_glow = move_toward(_action_glow, 1.0 if (is_shooting or is_sucking) else 0.0, delta * t.action_glow_rate)
	if visual_core != null:
		var charge := charge_fraction()
		var want_scale := Vector2(size_mod, size_mod) * (1.0 - t.core_charge_shrink * charge)
		visual_core.scale = visual_core.scale.lerp(want_scale, clampf(delta * t.core_scale_rate, 0.0, 1.0))
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
		var ready := 1.0 if momentum >= 1.0 else momentum * t.ready_glow_scale
		if armed_time > 0.0:
			ready = 1.0
		if parry_window > 0.0:
			ready = 1.0
		_body_mat.set_shader_parameter("ready_factor", ready)
		_body_mat.set_shader_parameter("action_factor", _action_glow)
		_body_mat.set_shader_parameter("charge", charge_fraction() if _charge_t >= t.blast_tap_time else 0.0)
		_body_mat.set_shader_parameter("time_pulse", Time.get_ticks_msec() * 0.001)

func _update_face() -> void:
	if face == null:
		return
	if ball != null and is_instance_valid(ball) and not ball.is_scored:
		face.look_at_point(global_position, ball.global_position)
		var incoming := (ball.velocity.x < 0.0 and player_id == 0) or (ball.velocity.x > 0.0 and player_id == 1)
		var close := absf(ball.global_position.x - global_position.x) < tuning.face_close_distance
		if _captured != null:
			face.maybe_mood(3, 0.2)
		elif incoming and close and ball.velocity.length() > tuning.face_scare_speed:
			face.maybe_mood(7, 0.28)
		elif momentum >= 1.0:
			face.maybe_mood(1, 0.2)
	else:
		face.look_at_point(global_position, Vector2(960, 540))
