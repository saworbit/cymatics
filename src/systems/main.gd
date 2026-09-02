class_name Main
extends Node2D

@onready var camera: Camera2D = $Camera2D
@onready var fluid_sim: FluidSimulator = $FluidSimulator
@onready var vfx_mgr: VFXManager = $VFXManager
@onready var audio_mgr: AudioManager = $AudioManager
@onready var game_mgr: GameManager = $GameManager
@onready var arena: Node2D = $Arena
@onready var fluid_display: Sprite2D = $Arena/FluidDisplay
@onready var paddle_left: Paddle = $PaddleLeft
@onready var paddle_right: Paddle = $PaddleRight
@onready var paddle_ai: PaddleAI = $PaddleAI
@onready var ball: Ball = $Ball
@onready var hud: HUD = $HUD
@onready var menu: MenuManager = $Menu

var chaos
var brick_matrix: BrickMatrix
var tournament_mgr: TournamentManager
var time_ctrl: TimeController
var paddle_ai_left: PaddleAI
var lab_recorder: Node
var _display_mat: ShaderMaterial
var _pulse := 0.0
var _lock_zoom := 0.0
var _goal_glow_left: ColorRect
var _goal_glow_right: ColorRect

func _ready() -> void:
	LabMode.parse()
	time_ctrl = TimeController.new()
	time_ctrl.name = "TimeController"
	add_child(time_ctrl)
	move_child(time_ctrl, 0)
	LabMode.time_ctrl = time_ctrl
	vfx_mgr.time_ctrl = time_ctrl
	game_mgr.time_ctrl = time_ctrl
	vfx_mgr.camera = camera
	camera.position = Vector2(960, 540)

	paddle_left.setup_dependencies(fluid_sim, vfx_mgr, audio_mgr, game_mgr)
	paddle_left.set_ball_reference(ball)
	paddle_right.setup_dependencies(fluid_sim, vfx_mgr, audio_mgr, game_mgr)
	paddle_right.set_ball_reference(ball)
	ball.setup_dependencies(fluid_sim, vfx_mgr, audio_mgr, game_mgr)
	ball.set_paddles(paddle_left, paddle_right)
	paddle_ai.setup(paddle_right, ball)

	chaos = preload("res://src/systems/chaos_director.gd").new()
	chaos.name = "ChaosDirector"
	add_child(chaos)
	chaos.setup(self, ball, paddle_left, paddle_right, game_mgr, fluid_sim, vfx_mgr, audio_mgr)
	chaos.time_ctrl = time_ctrl
	game_mgr.chaos = chaos
	paddle_ai.game_mgr = game_mgr
	paddle_ai.chaos = chaos

	brick_matrix = preload("res://src/systems/brick_matrix.gd").new()
	brick_matrix.name = "BrickMatrix"
	add_child(brick_matrix)
	brick_matrix.setup(fluid_sim, vfx_mgr, audio_mgr, chaos)

	game_mgr.setup_references(ball, paddle_left, paddle_right, paddle_ai, vfx_mgr, audio_mgr)

	tournament_mgr = preload("res://src/systems/tournament_manager.gd").new()
	tournament_mgr.name = "TournamentManager"
	add_child(tournament_mgr)
	tournament_mgr.setup(game_mgr, paddle_left, paddle_right, paddle_ai, brick_matrix, fluid_sim, vfx_mgr, audio_mgr, chaos)
	game_mgr.tournament_mgr = tournament_mgr

	hud.setup(game_mgr, paddle_left, paddle_right, tournament_mgr)
	var reticle := ThreatReticle.new()
	reticle.name = "ThreatReticle"
	add_child(reticle)
	reticle.setup(ball, game_mgr, paddle_left, paddle_right)
	if audio_mgr != null and audio_mgr.has_method("bind_match"):
		audio_mgr.bind_match(game_mgr, ball, paddle_left, paddle_right, tournament_mgr, chaos)

	game_mgr.impact_pulse.connect(func(amt: float): _pulse = maxf(_pulse, amt))
	game_mgr.serving_started.connect(func(_id: int): _lock_zoom = 0.0)
	game_mgr.lab_watch_toggled.connect(_toggle_watch_lab)

	if fluid_display != null and fluid_display.material is ShaderMaterial:
		_display_mat = fluid_display.material
		if fluid_sim != null:
			_display_mat.set_shader_parameter("sim_texel", fluid_sim.get_sim_texel_size())
	_goal_glow_left = arena.get_node_or_null("GoalGlowLeft") as ColorRect
	_goal_glow_right = arena.get_node_or_null("GoalGlowRight") as ColorRect
	_update_display_texture()

	if menu != null:
		menu.setup(fluid_sim, game_mgr, audio_mgr, vfx_mgr, _display_mat)

	if LabMode.active:
		_start_lab(false)

func _physics_process(delta: float) -> void:
	if fluid_sim != null:
		fluid_sim.step_simulation(delta)
	if audio_mgr != null and fluid_sim != null:
		audio_mgr.update_fluid_drone(fluid_sim.get_average_kinetic_energy())
	_pulse = move_toward(_pulse, 0.0, delta * 1.8)
	if _display_mat != null and ball != null and fluid_sim != null:
		var heat := 0.0
		if ball.is_in_cymatic_lock:
			heat = 1.0
		elif ball.is_in_overdrive:
			heat = 0.55
		_display_mat.set_shader_parameter("impact_pulse", _pulse)
		_display_mat.set_shader_parameter("heat", heat)
		_display_mat.set_shader_parameter("flow_energy", fluid_sim.get_flow_energy_norm())

func _process(delta: float) -> void:
	_update_camera(delta)
	_update_display_texture()
	_update_goal_glows()
	_update_ball_void(delta)

var _void_strength := 0.0

func _update_ball_void(delta: float) -> void:
	if _display_mat == null or ball == null:
		return
	var live := game_mgr != null and game_mgr.current_state != GameManager.State.MENU and not ball.is_scored
	var want := 1.0 if live else 0.0
	_void_strength = move_toward(_void_strength, want, delta * 3.0)
	var speed := ball.velocity.length()
	var radius := 70.0 + clampf(speed / 2100.0, 0.0, 1.0) * 70.0
	if ball.is_in_cymatic_lock:
		radius += 30.0
	_display_mat.set_shader_parameter("ball_uv", ball.global_position / Vector2(1920.0, 1080.0))
	_display_mat.set_shader_parameter("void_radius_px", radius)
	_display_mat.set_shader_parameter("void_strength", _void_strength)

func _update_camera(delta: float) -> void:
	if camera == null:
		return
	if game_mgr != null and game_mgr.current_state == GameManager.State.MENU:
		camera.position = camera.position.lerp(Vector2(960, 540), clampf(delta * 6.0, 0.0, 1.0))
		camera.zoom = camera.zoom.lerp(Vector2.ONE, clampf(delta * 8.0, 0.0, 1.0))
		return
	if ball == null:
		return
	# Camera runs on real time so the goal slow-mo/freeze does not stall the push.
	var real_dt := clampf(delta / maxf(Engine.time_scale, 0.0001), 0.0, 0.1)
	if Engine.time_scale <= 0.0001:
		real_dt = 1.0 / 60.0
	var target := Vector2(960, 540)
	if not ball.is_scored and not ball.is_serving:
		target = target.lerp(ball.global_position, 0.045)
		# Subtle look-ahead toward where the ball is going.
		target += (ball.velocity * 0.05).limit_length(60.0)
	# Goal focus: push toward the goal line and zoom out briefly.
	var focus_w := vfx_mgr.goal_focus_weight() if vfx_mgr else 0.0
	if focus_w > 0.0:
		target = target.lerp(vfx_mgr.goal_focus_pos(), focus_w * 0.08)
	camera.position = camera.position.lerp(target, clampf(real_dt * 6.0, 0.0, 1.0))

	var want_zoom := 0.0
	if ball.is_in_cymatic_lock:
		want_zoom = 0.12
	elif ball.is_in_overdrive:
		want_zoom = 0.06
	_lock_zoom = lerpf(_lock_zoom, want_zoom, clampf(real_dt * 2.5, 0.0, 1.0))
	var z := 1.0 + _lock_zoom + (vfx_mgr.get_zoom_punch() if vfx_mgr else 0.0)
	z *= 1.0 - 0.07 * focus_w
	camera.zoom = camera.zoom.lerp(Vector2(z, z), clampf(real_dt * 8.0, 0.0, 1.0))

func _update_goal_glows() -> void:
	if game_mgr != null and game_mgr.current_state == GameManager.State.MENU:
		if _goal_glow_left != null:
			_goal_glow_left.color.a = 0.35
			_goal_glow_left.size.x = 8.0
		if _goal_glow_right != null:
			_goal_glow_right.color.a = 0.35
			_goal_glow_right.size.x = 8.0
			_goal_glow_right.position.x = 1920.0 - 8.0
		return

	if _goal_glow_left != null:
		var threat_l := 0.0
		if ball != null and not ball.is_scored and not ball.is_serving and ball.velocity.x < 0.0:
			threat_l = clampf((220.0 - ball.global_position.x) / 220.0, 0.0, 1.0)
		_goal_glow_left.color.a = lerpf(_goal_glow_left.color.a, 0.35 + threat_l * 0.65, 0.2)
		_goal_glow_left.size.x = lerpf(_goal_glow_left.size.x, 8.0 + threat_l * 28.0, 0.2)

	if _goal_glow_right != null:
		var threat_r := 0.0
		if ball != null and not ball.is_scored and not ball.is_serving and ball.velocity.x > 0.0:
			threat_r = clampf((ball.global_position.x - 1700.0) / 220.0, 0.0, 1.0)
		_goal_glow_right.color.a = lerpf(_goal_glow_right.color.a, 0.35 + threat_r * 0.65, 0.2)
		_goal_glow_right.size.x = lerpf(_goal_glow_right.size.x, 8.0 + threat_r * 28.0, 0.2)
		_goal_glow_right.position.x = 1920.0 - _goal_glow_right.size.x

func _toggle_watch_lab() -> void:
	if LabMode.active and paddle_ai_left != null:
		return
	LabMode.enable_watch()
	_start_lab(true)

func _start_lab(watch: bool) -> void:
	paddle_left.is_ai = true
	paddle_right.is_ai = true
	if paddle_ai != null:
		paddle_ai.enabled = true
		paddle_ai.difficulty = 1.0
	if paddle_ai_left == null:
		paddle_ai_left = PaddleAI.new()
		paddle_ai_left.name = "PaddleAILeft"
		add_child(paddle_ai_left)
		paddle_ai_left.setup(paddle_left, ball)
		paddle_ai_left.game_mgr = game_mgr
		paddle_ai_left.chaos = chaos
		paddle_ai_left.difficulty = 1.0
	game_mgr.paddle_ai_left = paddle_ai_left
	game_mgr.is_ai_enabled = true
	if not LabMode.watch:
		game_mgr.points_to_win_set = 3
		game_mgr.sets_to_win_match = 1
	if LabMode.quiet and audio_mgr != null:
		AudioServer.set_bus_mute(0, true)
	LabMode.apply_clock()
	if lab_recorder == null:
		lab_recorder = preload("res://src/systems/lab_recorder.gd").new()
		lab_recorder.name = "LabRecorder"
		add_child(lab_recorder)
		lab_recorder.setup(game_mgr, ball, paddle_left, paddle_right, chaos, paddle_ai_left, paddle_ai)
	if hud != null:
		hud.show_lab_banner(watch)
	game_mgr.start_lab_match()
	if watch:
		game_mgr.callout.emit("LAB: AI vs AI", Color(1.0, 0.9, 0.4))

func _update_display_texture() -> void:
	if fluid_display != null and fluid_sim != null:
		var tex := fluid_sim.get_display_texture()
		if fluid_display.texture != tex:
			fluid_display.texture = tex
		if _display_mat != null and fluid_sim.has_method("get_velocity_texture"):
			var vel_tex: Texture2D = fluid_sim.get_velocity_texture()
			if vel_tex != null and _display_mat.get_shader_parameter("velocity_tex") != vel_tex:
				_display_mat.set_shader_parameter("velocity_tex", vel_tex)
