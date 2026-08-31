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

var chaos
var brick_matrix: BrickMatrix
var tournament_mgr: TournamentManager
var _display_mat: ShaderMaterial
var _pulse := 0.0
var _lock_zoom := 0.0
var _goal_glow_left: ColorRect
var _goal_glow_right: ColorRect

func _ready() -> void:
	vfx_mgr.camera = camera
	camera.position = Vector2(960, 540)

	paddle_left.setup_dependencies(fluid_sim, vfx_mgr, audio_mgr)
	paddle_left.set_ball_reference(ball)
	paddle_right.setup_dependencies(fluid_sim, vfx_mgr, audio_mgr)
	paddle_right.set_ball_reference(ball)
	ball.setup_dependencies(fluid_sim, vfx_mgr, audio_mgr)
	ball.set_paddles(paddle_left, paddle_right)
	paddle_ai.setup(paddle_right, ball)

	chaos = preload("res://src/systems/chaos_director.gd").new()
	chaos.name = "ChaosDirector"
	add_child(chaos)
	chaos.setup(self, ball, paddle_left, paddle_right, game_mgr, fluid_sim, vfx_mgr, audio_mgr)
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

	game_mgr.impact_pulse.connect(func(amt: float): _pulse = maxf(_pulse, amt))
	game_mgr.serving_started.connect(func(_id: int): _lock_zoom = 0.0)

	if fluid_display != null and fluid_display.material is ShaderMaterial:
		_display_mat = fluid_display.material
	_goal_glow_left = arena.get_node_or_null("GoalGlowLeft") as ColorRect
	_goal_glow_right = arena.get_node_or_null("GoalGlowRight") as ColorRect
	_update_display_texture()

func _physics_process(delta: float) -> void:
	if fluid_sim != null:
		fluid_sim.step_simulation(delta)
	if audio_mgr != null and fluid_sim != null:
		audio_mgr.update_fluid_drone(fluid_sim.get_average_kinetic_energy())
	_update_camera(delta)
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

func _process(_delta: float) -> void:
	_update_display_texture()
	_update_goal_glows()

func _update_camera(delta: float) -> void:
	if camera == null or ball == null:
		return
	var target := Vector2(960, 540)
	if not ball.is_scored and not ball.is_serving:
		target = target.lerp(ball.global_position, 0.045)
	camera.position = camera.position.lerp(target, clampf(delta * 6.0, 0.0, 1.0))

	var want_zoom := 0.0
	if ball.is_in_cymatic_lock:
		want_zoom = 0.12
	elif ball.is_in_overdrive:
		want_zoom = 0.06
	_lock_zoom = lerpf(_lock_zoom, want_zoom, clampf(delta * 2.5, 0.0, 1.0))
	var z := 1.0 + _lock_zoom + (vfx_mgr.get_zoom_punch() if vfx_mgr else 0.0)
	camera.zoom = camera.zoom.lerp(Vector2(z, z), clampf(delta * 8.0, 0.0, 1.0))

func _update_goal_glows() -> void:
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

func _update_display_texture() -> void:
	if fluid_display != null and fluid_sim != null:
		var tex := fluid_sim.get_display_texture()
		if fluid_display.texture != tex:
			fluid_display.texture = tex
