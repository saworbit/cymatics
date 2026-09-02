extends SceneTree

## Red-team probe: trace the serve timer across a pause taken during goal theatre.
##
## Samples state / Engine.time_scale / GameManager._serve_timer.time_left every
## ~100 ms of real time so a stalled serve can be attributed.
##
##   godot --headless --path . --script res://tools/redteam_serve_watch.gd -- --hold=5 --delay=0.05
##   godot --headless --path . --script res://tools/redteam_serve_watch.gd -- --hold=0 --nopause

var _main: Node
var _t0 := 0
var _hold := 5.0
var _delay := 0.05
var _nopause := false
var _phase := 0
var _goal_ms := 0
var _pause_ms := 0
var _last_log := 0
const STATES := ["MENU", "SERVING", "PLAYING", "PAUSED", "GOAL_SCORED", "MATCH_OVER"]

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hold="):
			_hold = float(a.get_slice("=", 1))
		elif a.begins_with("--delay="):
			_delay = float(a.get_slice("=", 1))
		elif a == "--nopause":
			_nopause = true
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_t0 = Time.get_ticks_msec()

func _rt() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0

func _goal_t() -> float:
	return float(Time.get_ticks_msec() - _goal_ms) / 1000.0 if _goal_ms > 0 else -1.0

func _process(_d: float) -> bool:
	var gm: Node = _main.get_node_or_null("GameManager")
	var ball: Node = _main.get_node_or_null("Ball")
	if gm == null or ball == null:
		return true
	var st: Node = gm.get_node_or_null("ServeTimer")

	if _goal_ms > 0 and Time.get_ticks_msec() - _last_log >= 200:
		_last_log = Time.get_ticks_msec()
		print("T+%6.2f  state=%-11s ts=%.4f paused=%-5s serving=%-5s scored=%-5s serve_timer_left=%.3f stopped=%s" % [
			_goal_t(), STATES[int(gm.get("current_state"))], Engine.time_scale, str(paused),
			str(ball.get("is_serving")), str(ball.get("is_scored")),
			st.get("time_left") if st else -1.0, str(st.is_stopped()) if st else "?"])

	match _phase:
		0:
			if _rt() > 1.5:
				gm.call("start_arcade_match", 1.0)
				gm.emit_signal("lab_watch_toggled")
				_phase = 1
		1:
			if _rt() > 5.0 and not bool(ball.get("is_serving")) and not bool(ball.get("is_scored")):
				ball.set("velocity", Vector2(1500, 0))
				ball.set("global_position", Vector2(1930, ball.global_position.y))
				_goal_ms = Time.get_ticks_msec()
				print("== GOAL FORCED ==")
				_phase = 2 if not _nopause else 4
		2:
			if _goal_t() >= _delay:
				gm.call("pause_match")
				_pause_ms = Time.get_ticks_msec()
				print("== PAUSED at T+%.3f ==" % _goal_t())
				_phase = 3
		3:
			if float(Time.get_ticks_msec() - _pause_ms) / 1000.0 >= _hold:
				gm.call("resume_match")
				print("== RESUMED at T+%.3f ==" % _goal_t())
				_phase = 4
		4:
			if bool(ball.get("is_serving")):
				print("== SERVE HELD at T+%.3f ==" % _goal_t())
				return true
			if _goal_t() > _hold + 30.0:
				print("== FAIL: no serve after T+%.1f (SOFT LOCK) ==" % _goal_t())
				return true
	return false
