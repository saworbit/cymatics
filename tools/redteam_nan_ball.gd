extends SceneTree

## Red-team repro: one NaN written into Ball.global_position is permanent.
##
## Nothing in Ball._physics_process / _integrate_flight / _handle_walls_and_goals
## ever tests global_position for finiteness, so the ball stays at (nan, nan)
## forever: invisible, uncollidable, never crossing a goal line. The rally never
## ends and the match cannot progress -> soft lock with no way out but Esc.
##
##   godot --headless --path . --script res://tools/redteam_nan_ball.gd -- --watch=25

var _main: Node
var _t0 := 0
var _stage := 0
var _inject_ms := 0
var _watch := 25.0
var _last := 0
var _goals := 0

func _rt() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--watch="):
			_watch = float(a.get_slice("=", 1))
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_t0 = Time.get_ticks_msec()

func _process(_d: float) -> bool:
	var gm: Node = _main.get_node_or_null("GameManager")
	var b: Node = _main.get_node_or_null("Ball")
	if gm == null or b == null:
		return true
	if _stage == 0:
		if _rt() < 1.5:
			return false
		gm.call("start_arcade_match", 1.0)
		gm.emit_signal("lab_watch_toggled")
		gm.connect("score_updated", func(a: int, c: int): _goals = a + c)
		_stage = 1
		return false
	if _stage == 1:
		if int(gm.get("current_state")) == 2 and not bool(b.get("is_serving")) and not bool(b.get("is_scored")):
			print("INJECT one NaN into Ball.global_position at t=%.2f (was %s)" % [_rt(), str(b.global_position)])
			b.set("global_position", Vector2(NAN, 540.0))
			_inject_ms = Time.get_ticks_msec()
			_stage = 2
		elif _rt() > 20.0:
			print("could not reach a rally")
			return true
		return false
	var since := float(Time.get_ticks_msec() - _inject_ms) / 1000.0
	if Time.get_ticks_msec() - _last >= 2000:
		_last = Time.get_ticks_msec()
		print("T+%5.1f state=%d pos=%s vel=%s scored=%s serving=%s rally=%s goals=%d ts=%.3f" % [
			since, int(gm.get("current_state")), str(b.global_position), str(b.get("velocity")),
			str(b.get("is_scored")), str(b.get("is_serving")), str(b.get("rally_hits")),
			_goals, Engine.time_scale])
	if since > _watch:
		var stuck := not is_finite(b.global_position.x) and int(gm.get("current_state")) == 2 \
			and not bool(b.get("is_scored")) and not bool(b.get("is_serving"))
		print("RESULT after %.0f s: %s (pos=%s goals=%d state=%d)" % [
			since, "SOFT LOCK - ball never recovers and no goal ever lands" if stuck
			else "recovered", str(b.global_position), _goals, int(gm.get("current_state"))])
		return true
	return false
