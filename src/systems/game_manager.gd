class_name GameManager
extends Node

## Match flow: serve ritual, rally stakes, goal theater, comeback rubber-band.
##
## Runs with PROCESS_MODE_ALWAYS (set in main.tscn) so the pause action still
## fires while the scene tree is paused. Everything else is guarded.

signal score_updated(score_p1: int, score_p2: int)
signal set_won(winner: int, sets_p1: int, sets_p2: int)
signal scores_reset
signal match_won(winner: int)
signal match_reset
signal match_started
signal game_paused(is_paused: bool)
signal menu_entered
signal rally_updated(hits: int)
signal milestone_reached(milestone_name: String)
signal callout(text: String, color: Color)
## Same as `callout` but carries a priority (higher = more important). HUD may queue on this.
signal callout_queued(text: String, color: Color, priority: int)
signal ai_toggled(enabled: bool)
signal zen_mode_toggled(enabled: bool)
signal gauntlet_mode_toggled(enabled: bool)
signal serving_started(server_id: int)
## Three-beat READY pulse after `start_serve` (beat 1, 2, 3 at 0.35 s intervals).
signal serve_ready_beat(beat: int)
## Human server is running out of serve time.
signal serve_clock_warning(seconds_left: float)
## The serve clock expired and the ball was launched with the current aim.
signal auto_served(server_id: int)
signal impact_pulse(amount: float)
## Goal theatre began: `side` is the goal line crossed (0 left, 1 right), `pos` the crossing point.
signal goal_theatre_started(side: int, pos: Vector2)
signal lab_watch_toggled
signal state_changed(new_state: int)

enum State { MENU, SERVING, PLAYING, PAUSED, GOAL_SCORED, MATCH_OVER }

const PRIO_LOW := 0
const PRIO_NORMAL := 1
const PRIO_HIGH := 2
const PRIO_CRITICAL := 3

@export var points_to_win_set := 7
@export var sets_to_win_match := 2

var current_state := State.MENU
var _previous_state := State.SERVING
var score_p1 := 0
var score_p2 := 0
var sets_p1 := 0
var sets_p2 := 0
var rally_hits := 0
var next_server := 0

var is_ai_enabled := true
var is_zen_mode := false
var is_gauntlet_mode := false
var _serve_token := 0
var _serve_timer: Timer
var _pending_server := 0
## Serve cadence: READY beats and the human auto-serve clock (sim seconds since start_serve).
const SERVE_BEAT_INTERVAL := 0.35
const SERVE_CLOCK := 4.0
const SERVE_CLOCK_WARN := 1.5
var _serve_clock := 0.0
var _serve_clock_active := false
var _serve_beats_sent := 0
var _serve_warned := false

var ball: Ball
var paddle_left: Paddle
var paddle_right: Paddle
var paddle_ai: PaddleAI
var paddle_ai_left: PaddleAI
var vfx_mgr: VFXManager
var audio_mgr: AudioManager
var time_ctrl: TimeController
var chaos
var tournament_mgr: TournamentManager

var _settings_node: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var st := _settings()
	if st != null and not st.is_connected("changed", _on_setting_changed):
		st.connect("changed", _on_setting_changed)
	_serve_timer = Timer.new()
	_serve_timer.name = "ServeTimer"
	_serve_timer.one_shot = true
	# Pauses with the tree and respects Engine.time_scale (not real time).
	_serve_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	_serve_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	add_child(_serve_timer)
	_serve_timer.timeout.connect(_on_serve_timer)

# --- Team colour (accessibility) ----------------------------------------------

## Settings autoload looked up by path so `--check-only` still compiles.
func _settings() -> Node:
	if _settings_node == null or not is_instance_valid(_settings_node):
		_settings_node = get_node_or_null("/root/Settings")
	return _settings_node

## Single source of truth for team colour, honouring `colorblind_mode`.
## `player_id` 0 = left / Padd, 1 = right / Lin.
func team_color(player_id: int) -> Color:
	var st := _settings()
	if st != null and st.has_method("team_color"):
		return st.call("team_color", player_id)
	return Color(0.0, 0.898, 1.0) if player_id == 0 else Color(1.0, 0.0, 0.667)

## Colour of whoever just scored. `scorer_id` follows `goal_reached`:
## 1 means the left paddle (player 0) scored.
func _scorer_color(scorer_id: int) -> Color:
	return team_color(0 if scorer_id == 1 else 1)

func _on_setting_changed(key: String, _value: Variant) -> void:
	if key != "colorblind_mode":
		return
	_apply_team_colors()

## Team-coloured shader uniforms a paddle builds in `_setup_visuals()`.
const TEAM_SHADER_PARAMS := ["glow_color", "beam_color", "vortex_tint", "team_color"]

## Repaint both paddles from the current palette. Boss stages override the right
## paddle's colour on their own; this only runs on palette changes and match start.
func _apply_team_colors() -> void:
	_repaint_paddle(paddle_left, team_color(0))
	if not is_gauntlet_mode:
		_repaint_paddle(paddle_right, team_color(1))
	_apply_goal_wall_colors()

## The two `GoalWall` membranes live in arena.tscn with an exported team colour
## baked into their shader on `_ready`. Repaint them from here so the goal a
## player defends keeps their colour under every palette. Left wall is player 0.
func _apply_goal_wall_colors() -> void:
	for wall in _find_goal_walls(get_parent()):
		var col := team_color(0 if int(wall.get("side")) == 0 else 1)
		wall.set("team_color", col)
		_retint_shader_materials(wall, col)

func _find_goal_walls(n: Node, found: Array[Node] = []) -> Array[Node]:
	if n == null:
		return found
	if n is GoalWall:
		found.append(n)
	for c in n.get_children():
		_find_goal_walls(c, found)
	return found

## `Paddle.team_color` is a plain export with no setter, and the body / beam /
## vortex materials bake it once in `_setup_visuals()`. Until Paddle grows a
## setter, push the new colour into those uniforms from here so a palette change
## reaches the paddle art and not just the HUD.
func _repaint_paddle(p: Paddle, col: Color) -> void:
	if p == null or not is_instance_valid(p):
		return
	p.team_color = col
	if p.has_method("apply_team_color"):
		p.call("apply_team_color", col)
		return
	_retint_shader_materials(p, col)

func _retint_shader_materials(n: Node, col: Color) -> void:
	var ci := n as CanvasItem
	if ci != null and ci.material is ShaderMaterial:
		var sm: ShaderMaterial = ci.material
		if sm.shader != null:
			for u in sm.shader.get_shader_uniform_list():
				var uname := String(u.get("name", ""))
				if uname in TEAM_SHADER_PARAMS:
					sm.set_shader_parameter(uname, col)
	for c in n.get_children():
		_retint_shader_materials(c, col)

func setup_references(p_ball: Ball, p_p1: Paddle, p_p2: Paddle, p_ai: PaddleAI, p_vfx: VFXManager, p_audio: AudioManager) -> void:
	ball = p_ball
	paddle_left = p_p1
	paddle_right = p_p2
	paddle_ai = p_ai
	vfx_mgr = p_vfx
	audio_mgr = p_audio

	_apply_team_colors()
	if vfx_mgr != null and vfx_mgr.haptics != null:
		vfx_mgr.haptics.bind_match(paddle_left, paddle_right, ball, self)

	ball.goal_reached.connect(_on_goal_reached)
	ball.hit_paddle.connect(on_ball_hit_paddle)
	ball.overdrive_entered.connect(func(): _banner("OVERDRIVE", Color(1.0, 0.45, 0.1), PRIO_HIGH))
	ball.cymatic_lock_entered.connect(func():
		_banner("CYMATIC LOCK", Color(1.0, 1.0, 1.0), PRIO_HIGH)
		if vfx_mgr != null:
			vfx_mgr.apply_hit_stop(0.12, 0.1)
			vfx_mgr.flash_screen(Color.WHITE, 0.2, 0.18)
	)
	ball.near_miss.connect(_on_near_miss)
	ball.served.connect(func(_d: Vector2):
		if current_state != State.MENU:
			_set_state(State.PLAYING)
		rally_hits = 0
		rally_updated.emit(0)
	)
	paddle_left.super_ready.connect(func(): _banner("RESONANCE READY", paddle_left.team_color, PRIO_NORMAL))
	paddle_right.super_ready.connect(func(): _banner("RESONANCE READY", paddle_right.team_color, PRIO_NORMAL))
	paddle_left.resonance_fired.connect(func(_p: Vector2): _banner("RESONANCE", paddle_left.team_color, PRIO_HIGH))
	paddle_right.resonance_fired.connect(func(_p: Vector2): _banner("RESONANCE", paddle_right.team_color, PRIO_HIGH))
	paddle_left.stunned.connect(func(_d: float): _banner("STUNNED", Color(0.7, 0.9, 1.0), PRIO_NORMAL))
	paddle_right.stunned.connect(func(_d: float): _banner("STUNNED", Color(0.7, 0.9, 1.0), PRIO_NORMAL))
	paddle_left.armed.connect(func(): _banner("CANNON ARMED", paddle_left.team_color, PRIO_NORMAL))
	paddle_right.armed.connect(func(): _banner("CANNON ARMED", paddle_right.team_color, PRIO_NORMAL))
	for p: Paddle in [paddle_left, paddle_right]:
		if p.has_signal("slingshot_fired"):
			p.slingshot_fired.connect(func(_pos: Vector2, spd: float):
				if spd >= 1400.0:
					post_callout("SLINGSHOT", p.team_color, PRIO_LOW)
			)
		if p.has_signal("blast_charge_released"):
			p.blast_charge_released.connect(func(_pos: Vector2, power: float):
				if power >= 0.9:
					post_callout("FULL CHARGE", p.team_color, PRIO_LOW)
			)

func _input(event: InputEvent) -> void:
	# Escape is bound to both `pause` and `ui_cancel`; handle it exactly once.
	var is_pause := event.is_action_pressed("pause") \
		or (event.is_action_pressed("ui_cancel") and not event.is_action("pause"))
	if is_pause:
		# Only claim Escape when it will actually do something. On the results
		# screen toggle_pause() is a no-op, so Escape used to be a dead key
		# with no way back except the mouse; there it backs out to the menu.
		if current_state == State.MATCH_OVER:
			return_to_menu()
			get_viewport().set_input_as_handled()
			return
		if current_state != State.MENU and (is_live() or current_state == State.PAUSED):
			toggle_pause()
			get_viewport().set_input_as_handled()
			return

	var tree := get_tree()
	if tree != null and tree.paused:
		return
	if current_state == State.PAUSED:
		return

	if event.is_action_pressed("toggle_lab"):
		lab_watch_toggled.emit()
		get_viewport().set_input_as_handled()
		return

	if current_state == State.MENU:
		return

	if event.is_action_pressed("toggle_ai"):
		is_ai_enabled = not is_ai_enabled
		if paddle_ai != null:
			paddle_ai.enabled = is_ai_enabled
		if paddle_right != null:
			paddle_right.is_ai = is_ai_enabled
		ai_toggled.emit(is_ai_enabled)
		_update_mouse_mode()

	if event.is_action_pressed("restart_game"):
		restart_match()

	if event.is_action_pressed("zen_mode_toggle"):
		is_zen_mode = not is_zen_mode
		zen_mode_toggled.emit(is_zen_mode)

	if event.is_action_pressed("toggle_gauntlet"):
		is_gauntlet_mode = not is_gauntlet_mode
		if is_gauntlet_mode:
			if tournament_mgr != null:
				tournament_mgr.start_tournament()
			_banner("GAUNTLET MODE", Color(1.0, 0.85, 0.2), PRIO_HIGH)
		else:
			if tournament_mgr != null:
				tournament_mgr.stop_tournament()
			_banner("ARCADE MODE", Color(0.2, 0.9, 1.0), PRIO_HIGH)
		gauntlet_mode_toggled.emit(is_gauntlet_mode)
		restart_match()

# --- State / clock / mouse -------------------------------------------------

func _set_state(new_state: State) -> void:
	if current_state == new_state:
		return
	current_state = new_state
	state_changed.emit(int(new_state))
	_update_mouse_mode()

func is_live() -> bool:
	return current_state == State.PLAYING or current_state == State.SERVING or current_state == State.GOAL_SCORED

func _apply_clock() -> void:
	if LabMode.active:
		LabMode.apply_clock()
	elif time_ctrl != null:
		time_ctrl.pop(&"lab")
	else:
		Engine.time_scale = 1.0

func _update_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var human_p1 := paddle_left != null and not paddle_left.is_ai
	if is_live() and human_p1:
		if Input.mouse_mode != Input.MOUSE_MODE_CONFINED:
			Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	else:
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# --- Serve -------------------------------------------------------------------

func _schedule_serve(server_id: int, delay: float) -> void:
	_serve_token += 1
	_pending_server = server_id
	if _serve_timer != null:
		_serve_timer.stop()
		_serve_timer.start(maxf(delay, 0.01))

func _cancel_serve() -> void:
	_serve_token += 1
	if _serve_timer != null:
		_serve_timer.stop()

func _on_serve_timer() -> void:
	if current_state == State.MATCH_OVER or current_state == State.MENU:
		return
	if current_state == State.PAUSED:
		# Pause landed on the same tick; re-arm for after resume.
		_serve_timer.start(0.05)
		return
	start_serve(_pending_server)

func start_serve(server_id: int) -> void:
	if current_state == State.MATCH_OVER:
		return
	_cancel_serve()
	_apply_clock()
	_set_state(State.SERVING)
	next_server = server_id
	rally_hits = 0
	rally_updated.emit(0)
	if chaos != null:
		chaos.clear_rally_mods()
	var server := paddle_left if server_id == 0 else paddle_right
	if ball != null:
		ball.hold_for_serve(server)
	_serve_clock = 0.0
	_serve_clock_active = true
	_serve_beats_sent = 0
	_serve_warned = false
	serving_started.emit(server_id)

## Serve cadence tick: READY beats at 0.35 s intervals, then the auto-serve clock for humans.
func _physics_process(delta: float) -> void:
	if not _serve_clock_active:
		return
	var tree := get_tree()
	if tree != null and tree.paused:
		return
	if current_state != State.SERVING or ball == null or not ball.is_serving:
		_serve_clock_active = false
		return
	_serve_clock += delta
	var server: Paddle = paddle_left if next_server == 0 else paddle_right
	var col := server.team_color if server != null else Color.WHITE
	while _serve_beats_sent < 3 and _serve_clock >= SERVE_BEAT_INTERVAL * float(_serve_beats_sent + 1):
		_serve_beats_sent += 1
		if _serve_beats_sent == 1:
			post_callout("READY", col, PRIO_LOW)
		elif _serve_beats_sent == 3 and server != null:
			post_callout(server.character_name(), col, PRIO_LOW)
		serve_ready_beat.emit(_serve_beats_sent)
	if server == null or server.is_ai:
		return
	if not _serve_warned and _serve_clock >= SERVE_CLOCK - SERVE_CLOCK_WARN:
		_serve_warned = true
		serve_clock_warning.emit(SERVE_CLOCK_WARN)
		post_callout("SERVE!", Color(1.0, 0.85, 0.3), PRIO_NORMAL)
	if _serve_clock >= SERVE_CLOCK:
		_serve_clock_active = false
		var id := next_server
		if server.try_serve():
			auto_served.emit(id)

# --- Callouts ----------------------------------------------------------------

## Public callout entry point. Emits `callout(text, color)` and `callout_queued(text, color, priority)`.
func post_callout(text: String, color: Color, priority: int = PRIO_LOW) -> void:
	callout.emit(text, color)
	callout_queued.emit(text, color, priority)

func _banner(text: String, color: Color, priority: int = PRIO_NORMAL) -> void:
	post_callout(text, color, priority)
	if text in ["OVERDRIVE", "CYMATIC LOCK", "MATCH POINT", "RESONANCE", "ACE", "THAT'S A PADDLIN'!", "MULTIBALL", "STUNNED"]:
		milestone_reached.emit(text)

# --- Rally events --------------------------------------------------------------

## Public hook for any ball (primary or clone) striking a paddle.
func on_ball_hit_paddle(_p: Paddle, speed: float, perfect: bool) -> void:
	rally_hits = ball.rally_hits if ball != null else rally_hits + 1
	rally_updated.emit(rally_hits)
	impact_pulse.emit(clampf(speed / 1800.0, 0.2, 1.0))

	if perfect:
		_banner("PERFECT", Color(1.0, 0.95, 0.4), PRIO_NORMAL)

	if rally_hits == 3:
		_banner("RALLY x3", Color(1.0, 0.85, 0.3), PRIO_LOW)
	elif rally_hits == 4:
		_banner("HEATING UP", Color(1.0, 0.7, 0.2), PRIO_LOW)
	elif rally_hits == 8:
		_banner("ON FIRE", Color(1.0, 0.4, 0.1), PRIO_NORMAL)
	elif rally_hits == 15:
		_banner("UNREAL", Color(1.0, 1.0, 1.0), PRIO_HIGH)

	_tune_ai_for_drama()

func _on_near_miss(side: int, pos: Vector2) -> void:
	if vfx_mgr != null:
		vfx_mgr.spawn_hit_burst(pos, Color(1.0, 0.9, 0.4), 1.3)
		vfx_mgr.apply_camera_kick(Vector2.LEFT if side == 0 else Vector2.RIGHT, 0.35)
	var scared: Paddle = paddle_left if side == 0 else paddle_right
	if scared:
		scared.emote(6, 0.5, "!!!")
	if ball:
		ball.emote(3, 0.4, "heh")
	post_callout("CLOSE!", Color(1.0, 0.85, 0.3), PRIO_LOW)
	if audio_mgr != null:
		audio_mgr.trigger_sting(220.0, 0.25)

func _on_goal_reached(scorer_id: int) -> void:
	if current_state == State.MATCH_OVER:
		return

	if is_zen_mode:
		var dir := Vector2(1 if scorer_id == 0 else -1, randf_range(-0.3, 0.3)).normalized()
		ball.reset_ball(Vector2(960, 540), dir)
		return

	_set_state(State.GOAL_SCORED)
	rally_hits = 0
	rally_updated.emit(0)

	if scorer_id == 1:
		score_p1 += 1
	else:
		score_p2 += 1

	var speed := ball.last_hit_speed if ball != null else 800.0
	var is_ace := ball != null and ball.touch_mask != 0 and (ball.touch_mask & (ball.touch_mask - 1)) == 0 and ball.rally_hits <= 1
	var is_smash := speed >= 1400.0

	# Goal theatre: 2-frame freeze, 0.3x slow-mo, ball shatters into a debris cone,
	# goal line rings and pulses, camera pushes toward the goal (VFXManager owns the sequence).
	var goal_side := scorer_id # goal_reached side: 0 = left line, 1 = right line
	var goal_hit_pos := ball.global_position if ball != null else Vector2(1920 if scorer_id == 1 else 0, 540)
	goal_theatre_started.emit(goal_side, goal_hit_pos)
	if vfx_mgr != null:
		var col := _scorer_color(scorer_id)
		vfx_mgr.play_goal_theatre(ball, goal_side, col)
		vfx_mgr.apply_camera_kick(Vector2.RIGHT if scorer_id == 1 else Vector2.LEFT, 1.8)

	if audio_mgr != null:
		audio_mgr.trigger_goal(scorer_id, is_smash)

	var scorer: Paddle = paddle_left if scorer_id == 1 else paddle_right
	var loser: Paddle = paddle_right if scorer_id == 1 else paddle_left
	if scorer:
		scorer.emote(2, 1.5, "THAT'S A PADDLIN'!")
	if loser:
		loser.emote(5, 1.4, "aww")

	if is_ace:
		_banner("ACE", Color(1.0, 0.95, 0.45), PRIO_HIGH)
	elif is_smash:
		_banner("THAT'S A PADDLIN'!", Color(1.0, 0.85, 0.25), PRIO_HIGH)
	else:
		_banner("THAT'S A PADDLIN'!", _scorer_color(scorer_id), PRIO_HIGH)

	score_updated.emit(score_p1, score_p2)

	if paddle_left != null and scorer_id == 1:
		paddle_left.add_momentum(0.12)
	if paddle_right != null and scorer_id == 0:
		paddle_right.add_momentum(0.12)

	# Cleanly despawn any clone balls when a regulation goal or set ends
	if chaos != null:
		chaos.clear_rally_mods()

	var set_ended := _maybe_finish_set()
	if current_state == State.MATCH_OVER:
		return

	var server := 0 if scorer_id == 0 else 1
	_schedule_serve(server, 1.15 if set_ended else 0.85)

func _maybe_finish_set() -> bool:
	var p1_set := score_p1 >= points_to_win_set and score_p1 - score_p2 >= 2
	var p2_set := score_p2 >= points_to_win_set and score_p2 - score_p1 >= 2
	if score_p1 == score_p2 and score_p1 >= points_to_win_set - 1:
		_banner("DEUCE", Color(1.0, 0.9, 0.5), PRIO_HIGH)
	elif not p1_set and not p2_set:
		_announce_stakes()

	if not p1_set and not p2_set:
		return false

	var set_winner := 0 if p1_set else 1
	if set_winner == 0:
		sets_p1 += 1
	else:
		sets_p2 += 1

	score_p1 = 0
	score_p2 = 0
	score_updated.emit(score_p1, score_p2)
	set_won.emit(set_winner, sets_p1, sets_p2)
	_banner("SET " + str(sets_p1) + " - " + str(sets_p2), Color(1.0, 0.9, 0.4), PRIO_HIGH)

	if sets_p1 >= sets_to_win_match or sets_p2 >= sets_to_win_match:
		var match_winner := 0 if sets_p1 >= sets_to_win_match else 1
		_finish_match(match_winner)
		return true
	return true

func _finish_match(match_winner: int) -> void:
	_cancel_serve()
	_set_state(State.MATCH_OVER)
	_apply_clock()
	if ball != null:
		ball.settle()
	if paddle_left != null:
		paddle_left.halt()
	if paddle_right != null:
		paddle_right.halt()
	match_won.emit(match_winner)
	if vfx_mgr != null:
		vfx_mgr.flash_screen(Color.WHITE, 0.4, 0.35)
	if audio_mgr != null:
		audio_mgr.trigger_goal(match_winner, true)
	if is_gauntlet_mode and tournament_mgr != null:
		tournament_mgr.on_match_won(match_winner)

func _announce_stakes() -> void:
	var p1_set_point := score_p1 >= points_to_win_set - 1 and score_p1 > score_p2
	var p2_set_point := score_p2 >= points_to_win_set - 1 and score_p2 > score_p1
	if not p1_set_point and not p2_set_point:
		return
	var leader := 0 if p1_set_point else 1
	var would_win_match := (leader == 0 and sets_p1 + 1 >= sets_to_win_match) or (leader == 1 and sets_p2 + 1 >= sets_to_win_match)
	if would_win_match:
		_banner("MATCH POINT", Color(1.0, 0.3, 0.2), PRIO_CRITICAL)
	else:
		_banner("SET POINT", Color(1.0, 0.75, 0.25), PRIO_HIGH)

func _tune_ai_for_drama() -> void:
	if LabMode.active:
		if paddle_ai != null:
			paddle_ai.difficulty = 1.0
		if paddle_ai_left != null:
			paddle_ai_left.difficulty = 1.0
		return
	if paddle_ai == null or not is_ai_enabled:
		return
	var lead := score_p2 - score_p1
	var diff := 1.0
	if lead >= 3:
		diff = 0.72
	elif lead >= 2:
		diff = 0.85
	elif lead <= -3:
		diff = 1.35
	elif lead <= -2:
		diff = 1.2
	if ball != null and ball.is_in_cymatic_lock:
		diff *= 0.92
	paddle_ai.difficulty = diff

func on_clone_goal(scorer_id: int) -> void:
	if current_state == State.MATCH_OVER:
		return
	if is_zen_mode:
		return
	if scorer_id == 1:
		score_p1 += 1
	else:
		score_p2 += 1
	_banner("MULTI GOAL", Color(1.0, 0.85, 0.2), PRIO_NORMAL)
	score_updated.emit(score_p1, score_p2)
	if vfx_mgr != null:
		var col := _scorer_color(scorer_id)
		vfx_mgr.spawn_shockwave(Vector2(1920 if scorer_id == 1 else 0, 540), col, 520.0, 0.4)
		vfx_mgr.apply_camera_kick(Vector2.RIGHT if scorer_id == 1 else Vector2.LEFT, 1.1)
	if audio_mgr != null:
		audio_mgr.trigger_sting(520.0, 0.4)
	var set_ended := _maybe_finish_set()
	if current_state == State.MATCH_OVER:
		if chaos:
			chaos.clear_rally_mods()
		return
	var live: Array = chaos.active_balls() if chaos != null else []
	var server := 0 if scorer_id == 0 else 1
	if live.is_empty():
		_set_state(State.GOAL_SCORED)
		_schedule_serve(server, 0.7)
	elif set_ended:
		if chaos:
			chaos.clear_rally_mods()
		_schedule_serve(server, 0.9)

# --- Match lifecycle -----------------------------------------------------------

func restart_match() -> void:
	_cancel_serve()
	_apply_team_colors()
	var tree := get_tree()
	if tree != null and tree.paused:
		tree.paused = false
	_apply_clock()
	score_p1 = 0
	score_p2 = 0
	sets_p1 = 0
	sets_p2 = 0
	rally_hits = 0
	_set_state(State.SERVING)
	next_server = 0

	score_updated.emit(0, 0)
	scores_reset.emit()
	set_won.emit(0, 0, 0) # legacy reset hack; HUD may switch to `scores_reset`
	rally_updated.emit(0)
	match_reset.emit()

	if paddle_left != null:
		paddle_left.reset_momentum()
		paddle_left.teleport(Vector2(180, 540))
	if paddle_right != null:
		paddle_right.reset_momentum()
		paddle_right.teleport(Vector2(1740, 540))
	if is_gauntlet_mode and tournament_mgr != null:
		tournament_mgr.restart_stage()
	elif chaos != null:
		chaos.clear_stage_mods()
	start_serve(0)

func start_lab_match() -> void:
	is_ai_enabled = true
	is_gauntlet_mode = false
	is_zen_mode = false
	if tournament_mgr != null:
		tournament_mgr.stop_tournament()
	if paddle_ai != null:
		paddle_ai.enabled = true
		paddle_ai.difficulty = 1.0
	if paddle_ai_left != null:
		paddle_ai_left.enabled = true
		paddle_ai_left.difficulty = 1.0
	if paddle_right != null:
		paddle_right.is_ai = true
	if paddle_left != null:
		paddle_left.is_ai = true
	ai_toggled.emit(true)
	gauntlet_mode_toggled.emit(false)
	zen_mode_toggled.emit(false)
	match_started.emit()
	restart_match()

func start_arcade_match(difficulty_mult: float = 1.0) -> void:
	is_ai_enabled = true
	is_gauntlet_mode = false
	is_zen_mode = false
	if tournament_mgr != null:
		tournament_mgr.stop_tournament()
	if paddle_ai != null:
		paddle_ai.enabled = true
		paddle_ai.difficulty = difficulty_mult
	if paddle_right != null:
		paddle_right.is_ai = true
		paddle_right.team_color = team_color(1)
		paddle_right.mutate_shape(Paddle.Shape.STANDARD, 0.0)
	if paddle_left != null:
		paddle_left.is_ai = false
		paddle_left.team_color = team_color(0)
		paddle_left.mutate_shape(Paddle.Shape.STANDARD, 0.0)
	ai_toggled.emit(true)
	gauntlet_mode_toggled.emit(false)
	zen_mode_toggled.emit(false)
	match_started.emit()
	restart_match()

func start_gauntlet_match() -> void:
	is_gauntlet_mode = true
	is_ai_enabled = true
	is_zen_mode = false
	if paddle_left != null:
		paddle_left.is_ai = false
		paddle_left.team_color = team_color(0)
		paddle_left.mutate_shape(Paddle.Shape.STANDARD, 0.0)
	if paddle_right != null:
		paddle_right.is_ai = true
	if tournament_mgr != null:
		tournament_mgr.start_tournament()
	gauntlet_mode_toggled.emit(true)
	ai_toggled.emit(true)
	zen_mode_toggled.emit(false)
	match_started.emit()
	restart_match()

func start_pvp_match() -> void:
	is_ai_enabled = false
	is_gauntlet_mode = false
	is_zen_mode = false
	if tournament_mgr != null:
		tournament_mgr.stop_tournament()
	if paddle_ai != null:
		paddle_ai.enabled = false
	if paddle_right != null:
		paddle_right.is_ai = false
		paddle_right.team_color = team_color(1)
		paddle_right.mutate_shape(Paddle.Shape.STANDARD, 0.0)
	if paddle_left != null:
		paddle_left.is_ai = false
		paddle_left.team_color = team_color(0)
		paddle_left.mutate_shape(Paddle.Shape.STANDARD, 0.0)
	ai_toggled.emit(false)
	gauntlet_mode_toggled.emit(false)
	zen_mode_toggled.emit(false)
	match_started.emit()
	restart_match()

func start_zen_match() -> void:
	is_zen_mode = true
	is_gauntlet_mode = false
	if tournament_mgr != null:
		tournament_mgr.stop_tournament()
	zen_mode_toggled.emit(true)
	gauntlet_mode_toggled.emit(false)
	match_started.emit()
	restart_match()

# --- Pause ---------------------------------------------------------------------

func toggle_pause() -> void:
	if current_state == State.PAUSED:
		resume_match()
	elif is_live():
		pause_match()

func pause_match() -> void:
	if not is_live():
		return
	_previous_state = current_state
	current_state = State.PAUSED
	var tree := get_tree()
	if tree != null:
		tree.paused = true
	state_changed.emit(int(current_state))
	_update_mouse_mode()
	game_paused.emit(true)

func resume_match() -> void:
	if current_state != State.PAUSED:
		return
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	var back := _previous_state
	if back == State.PAUSED or back == State.MENU or back == State.MATCH_OVER:
		back = State.PLAYING
	current_state = back
	_apply_clock()
	state_changed.emit(int(current_state))
	_update_mouse_mode()
	game_paused.emit(false)

func return_to_menu() -> void:
	_cancel_serve()
	var tree := get_tree()
	if tree != null and tree.paused:
		tree.paused = false
	_apply_clock()
	_set_state(State.MENU)
	if chaos != null:
		chaos.clear_rally_mods()
		chaos.clear_stage_mods()
	if tournament_mgr != null:
		tournament_mgr.stop_tournament()
	if ball != null:
		ball.velocity = Vector2.ZERO
		ball.global_position = Vector2(960, 540)
		ball.is_serving = false
		ball.is_scored = false
		ball.serve_paddle = null
		ball.reset_physics_interpolation()
	if paddle_left != null:
		paddle_left.teleport(Vector2(180, 540))
	if paddle_right != null:
		paddle_right.teleport(Vector2(1740, 540))
	game_paused.emit(false)
	menu_entered.emit()
