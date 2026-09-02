extends SceneTree

## Integration harness. Boots the real scene, drives it through the transitions
## that historically broke things, and checks a set of invariants on every
## frame. Exits 1 on the first violation so CI gates on it.
##
##   godot --headless --path . --script res://tests/integration_run.gd
##   godot --path . --script res://tests/integration_run.gd -- --seconds=60
##
## Headless has no RenderingDevice, so the fluid falls back to CPU. That is
## expected and does not affect the invariants checked here.

const ARENA := Vector2(1920.0, 1080.0)
## Generous margin: the ball legitimately passes the goal line before a reset.
const POS_MARGIN := 900.0
## Well above the hard speed cap; this catches runaway integration, not tuning.
const SPEED_CEILING := 6000.0

var _main: Node
var _start_ms := 0
var _seconds := 45.0
var _violations: Array[String] = []
var _step := 0
var _baseline_nodes := 0
var _peak_nodes := 0
var _frames := 0

## Each entry is [at_seconds, action]. The actions deliberately collide with
## one another: pausing inside goal theatre, restarting mid-rally and changing
## fluid quality mid-match have all produced stuck states before.
var _plan := [
	[2.0, "arcade"],
	[3.0, "lab"],
	[8.0, "pause"],
	[9.0, "unpause"],
	[11.0, "restart"],
	[14.0, "quality:3"],
	[18.0, "quality:0"],
	[21.0, "pause"],
	[21.5, "restart"],
	[22.0, "unpause"],
	[26.0, "quality:1"],
	[30.0, "menu"],
	[32.0, "arcade"],
	[36.0, "gauntlet"],
	[40.0, "zen"],
	[43.0, "menu"],
]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			_seconds = float(arg.trim_prefix("--seconds="))
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_violate("main.tscn failed to load")
		_finish()
		return
	_main = packed.instantiate()
	root.add_child(_main)
	_start_ms = Time.get_ticks_msec()

func _violate(msg: String) -> void:
	# One line per distinct violation; repeats of the same message are noise.
	if not _violations.has(msg):
		_violations.append(msg)
		print("VIOLATION: ", msg)

func _process(_delta: float) -> bool:
	_frames += 1
	var t := float(Time.get_ticks_msec() - _start_ms) / 1000.0

	if _frames == 120:
		_baseline_nodes = _count_nodes()
	_peak_nodes = maxi(_peak_nodes, _count_nodes())

	_check_invariants()

	if _step < _plan.size() and t >= float(_plan[_step][0]):
		var action: String = _plan[_step][1]
		_step += 1
		_do(action)

	if t >= _seconds:
		_finish()
		return true
	return false

func _count_nodes() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

func _node(path: String) -> Node:
	return _main.get_node_or_null(path) if _main != null else null

func _do(action: String) -> void:
	var parts := action.split(":")
	var game = _node("GameManager")
	var menu = _node("Menu")
	match parts[0]:
		"arcade":
			if menu != null and menu.has_method("_on_arcade_clicked"):
				menu.call("_on_arcade_clicked")
		"gauntlet":
			if game != null and game.has_method("start_gauntlet_match"):
				game.call("start_gauntlet_match")
		"zen":
			if game != null and game.has_method("start_zen_match"):
				game.call("start_zen_match")
		"menu":
			if game != null and game.has_method("return_to_menu"):
				game.call("return_to_menu")
		"pause":
			if game != null and game.has_method("pause_match"):
				game.call("pause_match")
		"unpause":
			if game != null and game.has_method("resume_match"):
				game.call("resume_match")
		"restart":
			if game != null and game.has_method("restart_match"):
				game.call("restart_match")
		"lab":
			var ev := InputEventAction.new()
			ev.action = "toggle_lab"
			ev.pressed = true
			Input.parse_input_event(ev)
		"quality":
			var fluid = _node("FluidSimulator")
			if fluid != null and fluid.has_method("set_quality"):
				fluid.call("set_quality", int(parts[1]))
	print("  [%5.1fs] %s" % [float(Time.get_ticks_msec() - _start_ms) / 1000.0, action])

func _check_invariants() -> void:
	# Time scale: never negative (runs the engine backwards), never NaN, and
	# never absurdly large. Zero is legitimate while paused.
	var ts := Engine.time_scale
	if not is_finite(ts):
		_violate("Engine.time_scale is not finite (%f)" % ts)
	elif ts < 0.0 or ts > 10.0:
		_violate("Engine.time_scale out of range (%f)" % ts)

	for ball in get_nodes_in_group("cymatics_balls"):
		if not is_instance_valid(ball):
			continue
		var pos: Vector2 = ball.global_position
		if not (is_finite(pos.x) and is_finite(pos.y)):
			_violate("ball position is not finite (%s)" % pos)
		elif pos.x < -POS_MARGIN or pos.x > ARENA.x + POS_MARGIN \
				or pos.y < -POS_MARGIN or pos.y > ARENA.y + POS_MARGIN:
			_violate("ball escaped the arena (%s)" % pos)
		var vel: Vector2 = ball.get("velocity")
		if not (is_finite(vel.x) and is_finite(vel.y)):
			_violate("ball velocity is not finite (%s)" % vel)
		elif vel.length() > SPEED_CEILING:
			_violate("ball speed %f exceeds the ceiling" % vel.length())

	var game = _node("GameManager")
	if game != null:
		for key in ["score_left", "score_right"]:
			var v: Variant = game.get(key)
			if v != null and typeof(v) == TYPE_INT:
				if int(v) < 0:
					_violate("%s went negative (%d)" % [key, int(v)])
				elif int(v) > 100:
					_violate("%s is implausibly large (%d)" % [key, int(v)])

	for paddle_path in ["PaddleLeft", "PaddleRight"]:
		var p = _node(paddle_path)
		if p != null:
			var pp: Vector2 = p.global_position
			if not (is_finite(pp.x) and is_finite(pp.y)):
				_violate("%s position is not finite (%s)" % [paddle_path, pp])

func _finish() -> void:
	# Node growth: transient VFX and audio voices come and go, so allow healthy
	# headroom. This catches an unbounded leak, not normal churn.
	if _baseline_nodes > 0:
		var final_nodes := _count_nodes()
		var growth := final_nodes - _baseline_nodes
		print("\nnodes: baseline %d, peak %d, final %d (growth %d)" % [_baseline_nodes, _peak_nodes, final_nodes, growth])
		if growth > 400:
			_violate("node count grew by %d, which suggests a leak" % growth)

	print("\n%s" % ("-".repeat(60)))
	if _violations.is_empty():
		print("Integration OK: %d frames, no invariant violations" % _frames)
		quit(0)
		return
	print("Integration FAILED: %d violation(s) over %d frames" % [_violations.size(), _frames])
	for v in _violations:
		print("  - ", v)
	quit(1)
