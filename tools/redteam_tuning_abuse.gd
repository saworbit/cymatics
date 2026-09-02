extends SceneTree

## Red-team probe: simulate a hostile / mis-merged src/tuning/*.tres by writing
## the same values onto the live tuning Resources right after boot, then run an
## AI-vs-AI rally and watch for NaN positions, NaN velocity, frozen balls,
## runaway values and hangs.
##
##   godot --headless --path . --script res://tools/redteam_tuning_abuse.gd -- \
##       --ball=min_speed=nan --seconds=12
##   godot --headless --path . --script res://tools/redteam_tuning_abuse.gd -- \
##       --paddle=capture_orbit_min_radius=0 --paddle=capture_radius_end=0 --seconds=12
##
## Values accepted: any float literal plus `nan`, `inf`, `-inf`.

var _main: Node
var _t0 := 0
var _seconds := 12.0
var _ball_sets: Array = []
var _paddle_sets: Array = []
var _applied := false
var _bugs := 0
var _nan_frames := 0
var _first_nan := -1.0
var _last_log := 0

func _v(s: String) -> float:
	var l := s.to_lower()
	if l == "nan":
		return NAN
	if l == "inf":
		return INF
	if l == "-inf":
		return -INF
	return float(s)

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ball="):
			var kv := a.trim_prefix("--ball=").split("=")
			_ball_sets.append([kv[0], _v(kv[1])])
		elif a.begins_with("--paddle="):
			var kv2 := a.trim_prefix("--paddle=").split("=")
			_paddle_sets.append([kv2[0], _v(kv2[1])])
		elif a.begins_with("--seconds="):
			_seconds = float(a.get_slice("=", 1))
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_t0 = Time.get_ticks_msec()

func _rt() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0

func _apply() -> void:
	var ball: Node = _main.get_node_or_null("Ball")
	if ball != null:
		var bt: Resource = ball.get("tuning")
		for kv in _ball_sets:
			var before = bt.get(kv[0])
			bt.set(kv[0], kv[1])
			print("APPLY ball.%s: %s -> %s" % [kv[0], str(before), str(bt.get(kv[0]))])
		# Mirrors copied onto the node in _ensure_tuning(); refresh them too.
		for m in ["radius", "base_speed", "max_speed", "min_speed", "bounce_damping"]:
			ball.set(m, bt.get(m))
	for pn in ["PaddleLeft", "PaddleRight"]:
		var p: Node = _main.get_node_or_null(pn)
		if p == null:
			continue
		var pt: Resource = p.get("tuning")
		for kv in _paddle_sets:
			var before2 = pt.get(kv[0])
			pt.set(kv[0], kv[1])
			if pn == "PaddleLeft":
				print("APPLY paddle.%s: %s -> %s" % [kv[0], str(before2), str(pt.get(kv[0]))])
	_applied = true

func _bad(v) -> bool:
	if v is Vector2:
		return is_nan(v.x) or is_nan(v.y) or is_inf(v.x) or is_inf(v.y)
	return is_nan(float(v)) or is_inf(float(v))

func _process(_d: float) -> bool:
	var gm: Node = _main.get_node_or_null("GameManager")
	var ball: Node = _main.get_node_or_null("Ball")
	if gm == null or ball == null:
		return true
	if not _applied and _rt() > 1.0:
		_apply()
		gm.call("start_arcade_match", 1.0)
		gm.emit_signal("lab_watch_toggled")
		return false
	if not _applied:
		return false

	var pos: Vector2 = ball.global_position
	var vel: Vector2 = ball.get("velocity")
	if _bad(pos) or _bad(vel) or _bad(ball.get("spin")):
		_nan_frames += 1
		if _first_nan < 0.0:
			_first_nan = _rt()
			print("RT-BUG t=%.2f BALL NON-FINITE pos=%s vel=%s spin=%s" % [_rt(), str(pos), str(vel), str(ball.get("spin"))])
			_bugs += 1
	for pn in ["PaddleLeft", "PaddleRight"]:
		var p: Node = _main.get_node_or_null(pn)
		if p != null and _bad(p.global_position):
			print("RT-BUG t=%.2f %s NON-FINITE pos=%s" % [_rt(), pn, str(p.global_position)])
			_bugs += 1
			return true

	if Time.get_ticks_msec() - _last_log >= 2000:
		_last_log = Time.get_ticks_msec()
		print("t=%5.1f state=%d pos=%s vel=%.1f spin=%.3f rally=%s scored=%s serving=%s ts=%.3f" % [
			_rt(), int(gm.get("current_state")), str(pos), vel.length(), float(ball.get("spin")),
			str(ball.get("rally_hits")), str(ball.get("is_scored")), str(ball.get("is_serving")),
			Engine.time_scale])

	if _rt() > _seconds:
		print("RESULT bugs=%d nan_frames=%d first_nan=%.2f final_pos=%s final_vel=%s score=%s-%s" % [
			_bugs, _nan_frames, _first_nan, str(pos), str(vel),
			str(gm.get("score_p1")), str(gm.get("score_p2"))])
		return true
	return false
