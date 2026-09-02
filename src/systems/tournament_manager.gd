class_name TournamentManager
extends Node

signal stage_started(stage_index: int, stage_info: Dictionary)
signal stage_completed(stage_index: int, stage_info: Dictionary)
signal tournament_won
signal tournament_lost

var is_tournament_active := false
var current_stage := 0

var game_mgr: GameManager
var paddle_left: Paddle
var paddle_right: Paddle
var paddle_right_twin: Paddle
var paddle_ai: PaddleAI
var brick_matrix: BrickMatrix
var fluid_sim: FluidSimulator
var vfx_mgr: VFXManager
var audio_mgr: AudioManager
var chaos_director

const STAGES: Array[Dictionary] = [
	{
		"title": "STAGE 1",
		"boss_name": "LIN · THE NEMESIS",
		"subtitle": "Classical Rivalry",
		"description": "High velocity baseline rallies & smug counter-attacks.",
		"color": Color(1.0, 0.0, 0.67),
		"ai_reaction": 0.045,
		"ai_aggression": 0.55,
		"shape": Paddle.Shape.STANDARD,
		"bricks": false,
		"twin": false,
		"quote": "Think you can paddle with the best?"
	},
	{
		"title": "STAGE 2",
		"boss_name": "HYDRA · TWIN SENTINELS",
		"subtitle": "Dual-Paddle Synergy",
		"description": "Two synchronized mini-paddles lock down top & bottom lanes.",
		"color": Color(0.2, 1.0, 0.45),
		"ai_reaction": 0.038,
		"ai_aggression": 0.7,
		"shape": Paddle.Shape.FORK,
		"bricks": false,
		"twin": true,
		"quote": "Two paddles, zero openings!"
	},
	{
		"title": "STAGE 3",
		"boss_name": "AEGIS · THE CITADEL",
		"subtitle": "Crystalline Firewall",
		"description": "Heavy fortified battering ram shielded behind a dense brick matrix.",
		"color": Color(1.0, 0.62, 0.15),
		"ai_reaction": 0.05,
		"ai_aggression": 0.65,
		"shape": Paddle.Shape.FORTRESS,
		"bricks": true,
		"brick_type": "firewall",
		"twin": false,
		"quote": "My barrier is absolute. Break through if you dare."
	},
	{
		"title": "STAGE 4",
		"boss_name": "VORTEX · GRAVITY LORD",
		"subtitle": "Singularity Master",
		"description": "Generates dark vortex sinks & whips razor star-shaped curveballs.",
		"color": Color(0.72, 0.25, 1.0),
		"ai_reaction": 0.032,
		"ai_aggression": 0.85,
		"shape": Paddle.Shape.SCOOP,
		"bricks": false,
		"twin": false,
		"quote": "The currents obey my command!"
	},
	{
		"title": "STAGE 5",
		"boss_name": "CYMATICA · PRIMORDIAL OVERLORD",
		"subtitle": "The Final Resonance",
		"description": "Shapeshifting boss with diamond matrix shields & hyper-fluid storms.",
		"color": Color(1.0, 0.95, 0.35),
		"ai_reaction": 0.025,
		"ai_aggression": 0.95,
		"shape": Paddle.Shape.FORTRESS,
		"bricks": true,
		"brick_type": "diamond",
		"twin": false,
		"quote": "I am the master of all frequencies. SHOW ME YOUR WILL!"
	}
]

var _stage_advance_token := 0
var _pulse_t := 0.0
var _storm_t := 0.0

const VORTEX_PULSE_PERIOD := 4.5
const STORM_PERIOD := 7.0

func setup(p_game: GameManager, p_p1: Paddle, p_p2: Paddle, p_ai: PaddleAI, p_bricks: BrickMatrix, p_fluid: FluidSimulator, p_vfx: VFXManager, p_audio: AudioManager, p_chaos) -> void:
	game_mgr = p_game
	paddle_left = p_p1
	paddle_right = p_p2
	paddle_ai = p_ai
	brick_matrix = p_bricks
	fluid_sim = p_fluid
	vfx_mgr = p_vfx
	audio_mgr = p_audio
	chaos_director = p_chaos

func start_tournament() -> void:
	_stage_advance_token += 1
	is_tournament_active = true
	current_stage = 0
	_pulse_t = 0.0
	_storm_t = 0.0
	_apply_stage(current_stage)

func advance_stage() -> void:
	_stage_advance_token += 1
	current_stage += 1
	if current_stage >= STAGES.size():
		is_tournament_active = false
		tournament_won.emit()
	else:
		_apply_stage(current_stage)

func restart_stage() -> void:
	_stage_advance_token += 1
	_apply_stage(current_stage)

func stop_tournament() -> void:
	_stage_advance_token += 1
	is_tournament_active = false
	if paddle_right_twin != null and is_instance_valid(paddle_right_twin):
		paddle_right_twin.queue_free()
		paddle_right_twin = null
	if paddle_ai != null:
		paddle_ai.twin_paddle = null
	if brick_matrix != null:
		brick_matrix.clear_all_bricks()
	if paddle_right != null:
		paddle_right.team_color = Color(1, 0, 0.67)
		paddle_right.mutate_shape(Paddle.Shape.STANDARD, 0.0)
		paddle_right.clear_mods()

func _apply_stage(stage_idx: int) -> void:
	if stage_idx < 0 or stage_idx >= STAGES.size():
		return
	var info: Dictionary = STAGES[stage_idx]

	# Clean up previous stage entities
	if paddle_right_twin != null and is_instance_valid(paddle_right_twin):
		paddle_right_twin.queue_free()
		paddle_right_twin = null
	if paddle_ai != null:
		paddle_ai.twin_paddle = null
	if brick_matrix != null:
		brick_matrix.clear_all_bricks()

	# Configure Boss Paddle (stage mods survive point resets; see Paddle.clear_rally_mods)
	paddle_right.clear_mods()
	paddle_right.team_color = info["color"]
	paddle_right.mutate_shape(info["shape"], Paddle.STAGE_MOD_DURATION)
	paddle_right.speed = 950.0 + float(stage_idx) * 60.0
	paddle_ai.reaction_delay = info["ai_reaction"]
	paddle_ai.aggression = info["ai_aggression"]

	if info.get("twin", false):
		_spawn_twin_paddle(info["color"])

	if info.get("bricks", false):
		var btype: String = info.get("brick_type", "firewall")
		if btype == "diamond":
			brick_matrix.spawn_diamond()
		else:
			brick_matrix.spawn_firewall(3, 7)

	stage_started.emit(stage_idx, info)
	if paddle_right.face != null:
		paddle_right.emote(3, 3.5, info.get("quote", "FIGHT!"))

func _spawn_twin_paddle(col: Color) -> void:
	var parent := paddle_right.get_parent()
	if parent == null:
		return
	paddle_right_twin = preload("res://scenes/paddle.tscn").instantiate()
	paddle_right_twin.player_id = 1
	paddle_right_twin.is_ai = true
	paddle_right_twin.position = Vector2(1740, 280)
	paddle_right_twin.team_color = col
	parent.add_child(paddle_right_twin)
	paddle_right_twin.setup_dependencies(fluid_sim, vfx_mgr, audio_mgr)
	paddle_right_twin.set_ball_reference(game_mgr.ball)
	paddle_right_twin.mutate_shape(Paddle.Shape.FORK, Paddle.STAGE_MOD_DURATION)
	paddle_right_twin.apply_size_mult(0.72, Paddle.STAGE_MOD_DURATION)
	paddle_right.apply_size_mult(0.72, Paddle.STAGE_MOD_DURATION)
	paddle_right.position = Vector2(1740, 800)
	paddle_ai.twin_paddle = paddle_right_twin

func _process(delta: float) -> void:
	if not is_tournament_active or game_mgr == null or game_mgr.current_state != GameManager.State.PLAYING:
		return

	# Stage 4: Vortex Gravitational Singularity Pulse (accumulated game-time, pauses with the tree)
	if current_stage == 3 and fluid_sim != null:
		_pulse_t += delta
		if _pulse_t >= VORTEX_PULSE_PERIOD:
			_pulse_t -= VORTEX_PULSE_PERIOD
			var pull_center := Vector2(1200.0, randf_range(300.0, 780.0))
			fluid_sim.inject_vortex(pull_center, 6.5 * (1.0 if randf() > 0.5 else -1.0), 160.0, Color(0.7, 0.2, 1.0))
			if game_mgr.ball != null and not game_mgr.ball.is_scored:
				game_mgr.ball.mutate_shape(Ball.Shape.STAR, 4.0)

	# Stage 5: Cymatica Shapeshifting Storm
	elif current_stage == 4 and paddle_right != null and is_instance_valid(paddle_right):
		_storm_t += delta
		if _storm_t >= STORM_PERIOD:
			_storm_t -= STORM_PERIOD
			var shapes := [Paddle.Shape.SCOOP, Paddle.Shape.WEDGE, Paddle.Shape.FORK, Paddle.Shape.FORTRESS]
			var next_s: Paddle.Shape = shapes[randi() % shapes.size()]
			paddle_right.mutate_shape(next_s, 6.0)
			if vfx_mgr != null:
				vfx_mgr.flash_screen(Color(1.0, 0.95, 0.4), 0.2, 0.15)
			if game_mgr.ball != null and not game_mgr.ball.is_scored:
				var bshapes := [Ball.Shape.TRIANGLE, Ball.Shape.CUBE, Ball.Shape.STAR, Ball.Shape.RUGBY]
				game_mgr.ball.mutate_shape(bshapes[randi() % bshapes.size()], 6.0)

func on_match_won(winner_id: int) -> void:
	if not is_tournament_active:
		return
	if winner_id == 0:
		# Player won this stage!
		stage_completed.emit(current_stage, STAGES[current_stage])
		if current_stage + 1 >= STAGES.size():
			tournament_won.emit()
			is_tournament_active = false
		else:
			# Advance to next stage after short pause with token guard
			_stage_advance_token += 1
			var current_token := _stage_advance_token
			var t := get_tree().create_timer(3.0, false)
			t.timeout.connect(func():
				if current_token == _stage_advance_token and is_tournament_active:
					advance_stage()
					game_mgr.restart_match()
			)
	else:
		# Player lost stage
		tournament_lost.emit()
