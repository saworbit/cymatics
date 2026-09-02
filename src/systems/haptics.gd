class_name Haptics
extends Node

## Gamepad rumble. Owned and instantiated by `VFXManager`, wired to gameplay
## signals by `GameManager.setup_references` via `bind_match()`.
##
## Device mapping follows the input map: player 0 (left / Padd) drives joypad
## device 0, player 1 (right / Lin) drives device 1. AI-controlled paddles never
## rumble, and nothing fires while the tree is paused or the game sits in the
## menu.
##
## Settings keys: `haptics` (bool) and `haptics_strength` (0..1). Both are read
## live so a change in the settings modal takes effect on the next event.
##
## Debug: run with `--haptics-debug` in the user args (or set the `haptics_debug`
## setting) to log every event as `[Haptics] <event> dev=N weak=.. strong=.. dur=..`.
## That is the only way to verify the table without a controller attached.

## Sustained effects re-issue this often so a driver timeout cannot cut them short.
const SUSTAIN_REFRESH := 0.12
## Hard ceiling on a held effect (matches the 2 s suck capture cap plus slack).
const SUSTAIN_MAX := 2.4
## Charge rumble ramps from this to 1.0 over `CHARGE_RAMP` seconds.
const CHARGE_MIN := 0.14
const CHARGE_RAMP := 0.7

var debug_log := false

var _game: Node
var _paddles: Array[Node] = [null, null]
## Per player: sustained effect name, elapsed hold time, refresh countdown.
var _hold_name: Array[String] = ["", ""]
var _hold_time: Array[float] = [0.0, 0.0]
var _hold_refresh: Array[float] = [0.0, 0.0]
var _settings_node: Node

func _ready() -> void:
	# Rumble must keep ticking while hit-stop scales time down, and must stop
	# itself the moment the tree pauses, so run always and gate in `_can_fire`.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg == "--haptics-debug":
			debug_log = true
	if not debug_log and bool(_setting("haptics_debug", false)):
		debug_log = true

# --- Settings ------------------------------------------------------------------

func _settings() -> Node:
	if _settings_node == null or not is_instance_valid(_settings_node):
		_settings_node = get_node_or_null("/root/Settings")
	return _settings_node

func _setting(key: String, default: Variant = null) -> Variant:
	var s := _settings()
	if s == null:
		return default
	return s.call("get_value", key, default)

func is_enabled() -> bool:
	return bool(_setting("haptics", true))

func strength() -> float:
	return clampf(float(_setting("haptics_strength", 0.8)), 0.0, 1.0)

# --- Binding -------------------------------------------------------------------

## Connect to a live match. Safe to call again; existing connections are skipped.
func bind_match(p_left: Node, p_right: Node, p_ball: Node, p_game: Node) -> void:
	_game = p_game
	_paddles[0] = p_left
	_paddles[1] = p_right
	for i in 2:
		_bind_paddle(_paddles[i], i)
	_bind_ball(p_ball)
	_bind_game(p_game)

func _connect_once(src: Object, sig: String, cb: Callable) -> void:
	if src == null or not is_instance_valid(src):
		return
	if not src.has_signal(sig):
		return
	if src.is_connected(sig, cb):
		return
	src.connect(sig, cb)

func _bind_paddle(p: Node, idx: int) -> void:
	if p == null:
		return
	_connect_once(p, "blast_charge_started", func(_pos: Vector2): charge_started(idx))
	_connect_once(p, "blast_charge_released", func(_pos: Vector2, power: float): blast_released(idx, power))
	_connect_once(p, "suck_captured", func(_pos: Vector2): suck_captured(idx))
	_connect_once(p, "slingshot_fired", func(_pos: Vector2, speed: float): slingshot(idx, speed))
	_connect_once(p, "parried", func(_pos: Vector2): perfect_parry(idx))
	_connect_once(p, "stunned", func(_d: float): stun(idx))
	_connect_once(p, "resonance_fired", func(_pos: Vector2): resonance(idx))

func _bind_ball(b: Node) -> void:
	if b == null:
		return
	_connect_once(b, "hit_paddle", _on_ball_hit_paddle)
	_connect_once(b, "hit_wall", func(_pos: Vector2, speed: float): wall_bounce(speed))
	_connect_once(b, "cymatic_lock_entered", cymatic_lock)

func _bind_game(g: Node) -> void:
	if g == null:
		return
	# Stop everything the instant the match pauses or the menu takes over.
	_connect_once(g, "game_paused", func(paused: bool):
		if paused:
			stop_all()
	)
	_connect_once(g, "menu_entered", stop_all)
	_connect_once(g, "match_reset", stop_all)
	_connect_once(g, "goal_theatre_started", func(side: int, _pos: Vector2): goal(side))
	_connect_once(g, "match_won", func(winner: int): match_won(winner))

func _on_ball_hit_paddle(p: Node, speed: float, perfect: bool) -> void:
	var idx := player_index(p)
	if idx < 0:
		return
	# `parried` covers the parry crack; a "perfect" contact is just a firmer tap
	# so the two never stack into one long rumble.
	paddle_hit(idx, speed * (1.35 if perfect else 1.0))

## Which player owns this paddle, or -1 when it is not one of the two bound.
func player_index(p: Node) -> int:
	for i in 2:
		if _paddles[i] != null and _paddles[i] == p:
			return i
	return -1

# --- Gating --------------------------------------------------------------------

func _is_human(player: int) -> bool:
	var p: Node = _paddles[player] if player >= 0 and player < 2 else null
	if p == null or not is_instance_valid(p):
		# Nothing bound yet: allow, so the debug run still exercises the table.
		return true
	if "is_ai" in p:
		return not bool(p.get("is_ai"))
	return true

func _can_fire(player: int) -> bool:
	if player < 0 or player > 1:
		return false
	if not is_enabled() or strength() <= 0.001:
		return false
	var tree := get_tree()
	if tree == null or tree.paused:
		return false
	if _game != null and is_instance_valid(_game) and "current_state" in _game:
		var st := int(_game.get("current_state"))
		if st == GameManager.State.MENU or st == GameManager.State.PAUSED:
			return false
	return _is_human(player)

# --- Low-level -----------------------------------------------------------------

## One-shot rumble. `weak` is the high-frequency motor, `strong` the low one.
func _fire(player: int, event: String, weak: float, strong: float, duration: float) -> void:
	if not _can_fire(player):
		return
	var s := strength()
	var w := clampf(weak * s, 0.0, 1.0)
	var st := clampf(strong * s, 0.0, 1.0)
	var d := maxf(duration, 0.0)
	if debug_log:
		push_warning("[Haptics] %s dev=%d weak=%.2f strong=%.2f dur=%.2f" % [event, player, w, st, d])
	if w <= 0.001 and st <= 0.001:
		return
	Input.start_joy_vibration(player, w, st, d)

## A rumble made of several beats. `beats` is an array of [weak, strong, duration]
## triples; `gap` is the real-time pause between them.
func _pattern(player: int, event: String, beats: Array, gap: float) -> void:
	if not _can_fire(player):
		return
	var tree := get_tree()
	for i in beats.size():
		var b: Array = beats[i]
		if i == 0:
			_fire(player, "%s.%d" % [event, i + 1], b[0], b[1], b[2])
			continue
		if tree == null:
			continue
		# Real-time timer: patterns must not stretch under hit-stop or slow-mo.
		var wait := (float(b[2]) + gap) * float(i)
		var t := tree.create_timer(wait, false, false, true)
		t.timeout.connect(func():
			_fire(player, "%s.%d" % [event, i + 1], b[0], b[1], b[2])
		)

## Start a sustained effect that runs until `release()` or `SUSTAIN_MAX`.
func _hold(player: int, event: String, weak: float, strong: float) -> void:
	if not _can_fire(player):
		return
	_hold_name[player] = event
	_hold_time[player] = 0.0
	_hold_refresh[player] = 0.0
	_fire(player, event, weak, strong, SUSTAIN_REFRESH * 1.6)

func release(player: int) -> void:
	if player < 0 or player > 1:
		return
	if _hold_name[player].is_empty():
		return
	if debug_log:
		push_warning("[Haptics] %s.release dev=%d" % [_hold_name[player], player])
	_hold_name[player] = ""
	_hold_time[player] = 0.0
	Input.stop_joy_vibration(player)

func stop_all() -> void:
	for i in 2:
		if not _hold_name[i].is_empty():
			_hold_name[i] = ""
			_hold_time[i] = 0.0
		Input.stop_joy_vibration(i)

func _process(delta: float) -> void:
	# Sustained effects tick in real time so a hit-stop cannot freeze the ramp.
	var real_dt := clampf(delta / maxf(Engine.time_scale, 0.0001), 0.0, 0.1)
	for i in 2:
		if _hold_name[i].is_empty():
			continue
		if not _can_fire(i):
			release(i)
			continue
		_hold_time[i] += real_dt
		if _hold_time[i] >= SUSTAIN_MAX:
			release(i)
			continue
		_hold_refresh[i] -= real_dt
		if _hold_refresh[i] > 0.0:
			continue
		_hold_refresh[i] = SUSTAIN_REFRESH
		var s := strength()
		match _hold_name[i]:
			"charge":
				# Rising weak rumble as the blast charges.
				var t := clampf(_hold_time[i] / CHARGE_RAMP, 0.0, 1.0)
				var w := clampf((CHARGE_MIN + t * (0.72 - CHARGE_MIN)) * s, 0.0, 1.0)
				Input.start_joy_vibration(i, w, clampf(t * 0.18 * s, 0.0, 1.0), SUSTAIN_REFRESH * 1.6)
			"suck":
				# Low sustained hum while the ball is held.
				Input.start_joy_vibration(i, 0.0, clampf(0.26 * s, 0.0, 1.0), SUSTAIN_REFRESH * 1.6)
			_:
				release(i)

# --- Event table ---------------------------------------------------------------
# Keep this list and the doc comment in sync; it is the contract the settings
# screen and the design doc describe.

## Regular paddle contact: short, light tap that grows a little with speed.
func paddle_hit(player: int, speed: float = 900.0) -> void:
	var t := clampf((speed - 500.0) / 1300.0, 0.0, 1.0)
	_fire(player, "paddle_hit", 0.22 + 0.22 * t, 0.10 + 0.18 * t, 0.07 + 0.03 * t)

## Perfect parry: two sharp cracks, the second slightly softer.
func perfect_parry(player: int) -> void:
	_pattern(player, "parry", [[0.95, 0.55, 0.05], [0.70, 0.40, 0.06]], 0.045)

## Blast charge begins: rising weak rumble held until release.
func charge_started(player: int) -> void:
	_hold(player, "charge", CHARGE_MIN, 0.0)

## Blast release. `power` 0..1 scales both motors and the duration.
func blast_released(player: int, power: float = 1.0) -> void:
	release(player)
	var p := clampf(power, 0.0, 1.0)
	_fire(player, "blast", 0.30 + 0.35 * p, 0.40 + 0.50 * p, 0.11 + 0.11 * p)

## Suck capture: low sustained hum for as long as the ball is held.
func suck_captured(player: int) -> void:
	_hold(player, "suck", 0.0, 0.26)

## Slingshot release: one sharp snap that scales with exit speed.
func slingshot(player: int, speed: float = 1200.0) -> void:
	release(player)
	var t := clampf((speed - 800.0) / 1200.0, 0.0, 1.0)
	_fire(player, "slingshot", 0.50 + 0.30 * t, 0.55 + 0.35 * t, 0.09 + 0.05 * t)

## Wall bounce: very light tick on both pads (nobody owns the wall).
func wall_bounce(speed: float = 800.0) -> void:
	var t := clampf((speed - 500.0) / 1400.0, 0.0, 1.0)
	for i in 2:
		_fire(i, "wall", 0.10 + 0.08 * t, 0.0, 0.04 + 0.02 * t)

## Goal: `side` is the goal line crossed, so the paddle on that side conceded.
## The conceding pad gets one long strong hit; the scorer gets a short cheer.
func goal(side: int) -> void:
	var conceder := clampi(side, 0, 1)
	var scorer := 1 - conceder
	_fire(conceder, "goal_conceded", 0.55, 0.95, 0.34)
	_pattern(scorer, "goal_scored", [[0.65, 0.30, 0.08], [0.55, 0.25, 0.08], [0.75, 0.45, 0.14]], 0.06)

## Resonance super: heavy double thump for the firing player.
func resonance(player: int) -> void:
	_pattern(player, "resonance", [[0.8, 0.9, 0.14], [0.4, 0.7, 0.22]], 0.05)

## Stun: buzzy high-frequency motor for the stunned player.
func stun(player: int) -> void:
	_fire(player, "stun", 0.85, 0.10, 0.42)

## Cymatic Lock: subtle heartbeat felt by both players.
func cymatic_lock() -> void:
	for i in 2:
		_pattern(i, "lock_heartbeat", [[0.0, 0.32, 0.09], [0.0, 0.22, 0.07]], 0.10)

## Match end: a long celebratory roll for the winner only.
func match_won(winner: int) -> void:
	_pattern(clampi(winner, 0, 1), "match_won", [[0.7, 0.8, 0.18], [0.5, 0.6, 0.14], [0.8, 1.0, 0.30]], 0.08)
