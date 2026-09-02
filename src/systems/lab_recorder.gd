extends Node

## Writes JSONL telemetry while two AIs play. See docs/design/ai-lab.md.

var game_mgr: GameManager
var ball: Ball
var paddle_left: Paddle
var paddle_right: Paddle
var chaos
var paddle_ai_left: PaddleAI
var paddle_ai_right: PaddleAI

var run_dir := ""
var _file: FileAccess
var _t := 0.0
var _sample_i := 0
var _matches_done := 0
var _points := 0
var _rallies: Array[float] = []
var _current_rally_hits := 0
var _behind_t := [0.0, 0.0]
var _behind_latched := [false, false]
var _last_orb = null
var _events := 0
var _goals := 0
var _caroms := 0
var _collects := 0
var _stucks := 0
var _aces := 0
var _captures := 0
var _slingshots := 0
var _charged_blasts := 0
var _started_unix := 0
var _last_points := 0

func setup(p_game: GameManager, p_ball: Ball, p_left: Paddle, p_right: Paddle, p_chaos, p_ai_l: PaddleAI, p_ai_r: PaddleAI) -> void:
	game_mgr = p_game
	ball = p_ball
	paddle_left = p_left
	paddle_right = p_right
	chaos = p_chaos
	paddle_ai_left = p_ai_l
	paddle_ai_right = p_ai_r
	_started_unix = int(Time.get_unix_time_from_system())
	_open_run()
	_hook()
	emit_event("lab_start", {
		"matches": LabMode.matches,
		"seconds": LabMode.seconds,
		"time_scale": Engine.time_scale,
		"lab_scale": LabMode.time_scale,
		"headless": DisplayServer.get_name() == "headless",
		"watch": LabMode.watch,
	})

func _open_run() -> void:
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	run_dir = ProjectSettings.globalize_path("res://lab/runs/%s" % stamp)
	DirAccess.make_dir_recursive_absolute(run_dir)
	_file = FileAccess.open(run_dir.path_join("events.jsonl"), FileAccess.WRITE)
	if _file == null:
		push_error("[LabRecorder] cannot write %s (%s)" % [run_dir, error_string(FileAccess.get_open_error())])

func _hook() -> void:
	if game_mgr != null:
		game_mgr.score_updated.connect(_on_score)
		game_mgr.serving_started.connect(_on_serve)
		game_mgr.match_won.connect(_on_match_won)
		game_mgr.match_reset.connect(func(): emit_event("match_reset", {}))
		game_mgr.rally_updated.connect(func(h: int): _current_rally_hits = h)
	if ball != null:
		if ball.has_signal("carom_hit"):
			ball.carom_hit.connect(_on_carom)
		ball.hit_paddle.connect(_on_hit)
		ball.near_miss.connect(func(side: int, _p: Vector2): emit_event("near_miss", {"side": side}))
	if chaos != null and chaos.has_signal("powerup_collected"):
		chaos.powerup_collected.connect(_on_collect)
	for p in [paddle_left, paddle_right]:
		if p == null:
			continue
		var pid: int = p.player_id
		if p.has_signal("suck_captured"):
			p.suck_captured.connect(func(pos: Vector2):
				_captures += 1
				emit_event("capture", {"player": pid, "x": pos.x, "y": pos.y, "ball_speed": ball.velocity.length() if ball else 0.0})
			)
		if p.has_signal("slingshot_fired"):
			p.slingshot_fired.connect(func(pos: Vector2, spd: float):
				_slingshots += 1
				emit_event("slingshot", {"player": pid, "x": pos.x, "y": pos.y, "speed": spd, "hold": p.get("last_capture_hold")})
			)
		if p.has_signal("blast_charge_released"):
			p.blast_charge_released.connect(func(pos: Vector2, power: float):
				if power > 0.4:
					_charged_blasts += 1
				emit_event("blast", {"player": pid, "x": pos.x, "y": pos.y, "power": power})
			)

func _physics_process(delta: float) -> void:
	_t += delta
	_sample_i += 1
	_watch_behind(delta)
	_watch_orb()
	if _sample_i % 8 == 0:
		_write_sample()
	if LabMode.seconds > 0.0 and _t >= LabMode.seconds:
		_finish("time")

func _watch_behind(delta: float) -> void:
	if ball == null or ball.is_serving or ball.is_scored:
		_behind_t[0] = 0.0
		_behind_t[1] = 0.0
		_behind_latched[0] = false
		_behind_latched[1] = false
		return
	for side in [0, 1]:
		var p: Paddle = paddle_left if side == 0 else paddle_right
		if p == null:
			continue
		var behind := false
		if side == 1:
			behind = ball.global_position.x > p.global_position.x + 24.0
		else:
			behind = ball.global_position.x < p.global_position.x - 24.0
		if behind:
			_behind_t[side] += delta
			if _behind_t[side] >= 0.7 and not _behind_latched[side]:
				_behind_latched[side] = true
				_stucks += 1
				emit_event("stuck_behind", {
					"side": side,
					"duration": _behind_t[side],
					"ball": _ball_snap(),
					"paddle_y": p.global_position.y,
				})
		else:
			_behind_t[side] = 0.0
			_behind_latched[side] = false

func _watch_orb() -> void:
	if chaos == null:
		return
	var live = chaos.live_powerup
	if live == _last_orb:
		return
	if live != null and is_instance_valid(live):
		if not live.is_inside_tree() or live.global_position.x <= 1.0:
			return
		emit_event("powerup_spawn", {
			"kind": live.kind,
			"x": live.global_position.x,
			"y": live.global_position.y,
		})
	_last_orb = live

func _write_sample() -> void:
	var orb := {}
	if chaos != null and chaos.live_powerup != null and is_instance_valid(chaos.live_powerup):
		var o = chaos.live_powerup
		orb = {
			"x": o.global_position.x,
			"y": o.global_position.y,
			"vx": o.drift_velocity.x,
			"vy": o.drift_velocity.y,
			"kind": o.kind,
		}
	emit_event("sample", {
		"ball": _ball_snap(),
		"p1": _paddle_snap(paddle_left, paddle_ai_left),
		"p2": _paddle_snap(paddle_right, paddle_ai_right),
		"orb": orb,
		"score": [game_mgr.score_p1 if game_mgr else 0, game_mgr.score_p2 if game_mgr else 0],
		"sets": [game_mgr.sets_p1 if game_mgr else 0, game_mgr.sets_p2 if game_mgr else 0],
		"rally": _current_rally_hits,
		"state": game_mgr.current_state if game_mgr else -1,
	})

func _ball_snap() -> Dictionary:
	if ball == null:
		return {}
	return {
		"x": ball.global_position.x,
		"y": ball.global_position.y,
		"vx": ball.velocity.x,
		"vy": ball.velocity.y,
		"spin": ball.spin,
		"hits": ball.rally_hits,
	}

func _paddle_snap(p: Paddle, ai: PaddleAI) -> Dictionary:
	if p == null:
		return {}
	var d := {
		"x": p.global_position.x,
		"y": p.global_position.y,
		"shoot": p.is_shooting,
		"suck": p.is_sucking,
		"stun": p.stun_time,
	}
	if ai != null:
		d["tx"] = ai._target_pos.x
		d["ty"] = ai._target_pos.y
		d["diff"] = ai.difficulty
	return d

func _on_serve(server_id: int) -> void:
	LabMode.apply_clock()
	emit_event("serve", {"server": server_id})

func _on_hit(p: Paddle, speed: float, perfect: bool) -> void:
	emit_event("rally_hit", {
		"player": p.player_id if p else -1,
		"speed": speed,
		"perfect": perfect,
		"spin": ball.spin if ball else 0.0,
		"hits": ball.rally_hits if ball else 0,
	})

func _on_score(s1: int, s2: int) -> void:
	var n := s1 + s2
	if n <= _last_points:
		_last_points = n
		return
	_last_points = n
	_points += 1
	_goals += 1
	# GameManager zeroes rally_updated before score_updated; the ball still holds the count.
	var hits_at_goal: int = ball.rally_hits if ball != null else _current_rally_hits
	_rallies.append(float(hits_at_goal))
	var ace := ball != null and ball.rally_hits <= 1
	if ace:
		_aces += 1
	emit_event("goal", {
		"score": [s1, s2],
		"rally_hits": hits_at_goal,
		"ace": ace,
		"spin": ball.spin if ball else 0.0,
		"ball": _ball_snap(),
		"stuck": _behind_latched[0] or _behind_latched[1],
	})

func _on_carom(cut: float, new_spin: float) -> void:
	_caroms += 1
	emit_event("carom", {"cut": cut, "spin": new_spin})

func _on_collect(kind: int, owner_id: int) -> void:
	_collects += 1
	emit_event("powerup_collect", {"kind": kind, "player": owner_id})

func _on_match_won(winner: int) -> void:
	_matches_done += 1
	emit_event("match_won", {"winner": winner, "sets": [game_mgr.sets_p1, game_mgr.sets_p2]})
	if LabMode.active and not LabMode.watch and _matches_done >= LabMode.matches:
		_finish("matches")
	elif LabMode.active and not LabMode.watch and game_mgr != null:
		game_mgr.restart_match()

func emit_event(kind: String, payload: Dictionary) -> void:
	if _file == null:
		return
	var row := {
		"t": snapped(_t, 0.001),
		"kind": kind,
		"data": payload,
	}
	_file.store_line(JSON.stringify(row))
	_events += 1

var _finished := false

func _finish(reason: String) -> void:
	if _finished:
		return
	_finished = true
	emit_event("lab_end", {"reason": reason, "matches": _matches_done, "events": _events})
	var summary := {
		"reason": reason,
		"sim_seconds": snapped(_t, 0.01),
		"wall_seconds": int(Time.get_unix_time_from_system()) - _started_unix,
		"matches": _matches_done,
		"points": _points,
		"goals": _goals,
		"aces": _aces,
		"captures": _captures,
		"slingshots": _slingshots,
		"charged_blasts": _charged_blasts,
		"caroms": _caroms,
		"collects": _collects,
		"stuck_behind": _stucks,
		"events": _events,
		"rally_hits_mean": _mean(_rallies),
		"rally_hits_max": _maxv(_rallies),
		"run_dir": run_dir,
	}
	var sf := FileAccess.open(run_dir.path_join("summary.json"), FileAccess.WRITE)
	if sf:
		sf.store_string(JSON.stringify(summary, "\t"))
		sf.close()
	if _file:
		_file.flush()
		_file.close()
		_file = null
	print("[LabRecorder] %s" % JSON.stringify(summary))
	# Windowed runs used to fall through here every physics frame, rewriting
	# summary.json ~60 times a second forever. Latch, and stop recording even
	# when we cannot quit the process.
	set_physics_process(false)
	if DisplayServer.get_name() == "headless":
		get_tree().quit()

func _mean(xs: Array[float]) -> float:
	if xs.is_empty():
		return 0.0
	var s := 0.0
	for x in xs:
		s += x
	return s / float(xs.size())

func _maxv(xs: Array[float]) -> float:
	var m := 0.0
	for x in xs:
		if x > m:
			m = x
	return m
