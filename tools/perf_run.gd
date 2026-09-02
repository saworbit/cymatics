extends SceneTree

## Frame-time harness. Boots the real scene, drives it through menu, serve and
## an AI-vs-AI rally, and reports frame-time percentiles per phase.
##
##   godot --path . --resolution 1920x1080 --script res://tools/perf_run.gd
##
## Runs with vsync and the FPS cap disabled so the numbers are the engine's
## real cost, not the refresh rate. Percentiles matter more than the mean: a
## good mean with a bad p99 is a stutter the player feels.

const PHASES := [
	{"name": "menu", "start": 2.0, "end": 6.0},
	{"name": "serve", "start": 7.5, "end": 10.0},
	{"name": "rally", "start": 12.0, "end": 34.0},
]
const END_TIME := 35.0

var _main: Node
var _start_ms := 0
var _samples := {}
var _last_usec := 0
var _vsync_forced := false
var _step := 0
var _plan := [
	[6.5, "arcade"],
	[10.5, "press:toggle_lab"],
]

func _initialize() -> void:
	# Measure real cost, not the monitor's refresh rate.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	# Plain Array, not PackedFloat32Array: packed arrays are value types, so
	# appending through a dictionary lookup would write to a throwaway copy.
	for p in PHASES:
		_samples[p["name"]] = []
	var packed: PackedScene = load("res://scenes/main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	_start_ms = Time.get_ticks_msec()
	_last_usec = Time.get_ticks_usec()

func _process(_delta: float) -> bool:
	var t := float(Time.get_ticks_msec() - _start_ms) / 1000.0

	# True wall-clock frame time, including GPU wait. The _process delta is
	# scaled by Engine.time_scale (hit-stop, goal slow motion) and would lie.
	# The Settings autoload applies the user's vsync preference in its _ready,
	# after _initialize ran, so re-assert the override once the tree is up.
	if not _vsync_forced and t > 1.0:
		_vsync_forced = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0

	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_usec) / 1000.0
	_last_usec = now
	for p in PHASES:
		if t >= float(p["start"]) and t < float(p["end"]):
			(_samples[p["name"]] as Array).append(frame_ms)

	if _step < _plan.size() and t >= float(_plan[_step][0]):
		var cmd: String = _plan[_step][1]
		_step += 1
		var parts := cmd.split(":")
		match parts[0]:
			"arcade":
				var menu: Node = _main.get_node_or_null("Menu")
				if menu != null and menu.has_method("_on_arcade_clicked"):
					menu.call("_on_arcade_clicked")
			"press":
				var ev := InputEventAction.new()
				ev.action = parts[1]
				ev.pressed = true
				Input.parse_input_event(ev)

	if t >= END_TIME:
		_report()
		return true
	return false

func _pct(arr: Array, p: float) -> float:
	if arr.is_empty():
		return 0.0
	var sorted := arr.duplicate()
	sorted.sort()
	var idx := int(clampf(p * float(sorted.size() - 1), 0.0, float(sorted.size() - 1)))
	return sorted[idx]

func _report() -> void:
	print("\n=== FRAME TIME (ms, lower is better) ===")
	print("phase      samples   mean    p50    p95    p99    max   est.fps(p95)")
	for p in PHASES:
		var name: String = p["name"]
		var arr: Array = _samples[name]
		if arr.is_empty():
			print("%-10s no samples" % name)
			continue
		var total := 0.0
		for v in arr:
			total += float(v)
		var mean := total / float(arr.size())
		var p95 := _pct(arr, 0.95)
		print("%-10s %7d %6.2f %6.2f %6.2f %6.2f %6.2f %8.0f" % [
			name, arr.size(), mean, _pct(arr, 0.5), p95, _pct(arr, 0.99), _pct(arr, 1.0),
			(1000.0 / p95) if p95 > 0.001 else 0.0,
		])
	print("\n=== RENDER ===")
	print("draw calls (last frame): ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	print("video memory MB: ", "%.1f" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0))
	print("objects: ", Performance.get_monitor(Performance.OBJECT_COUNT))
	print("nodes: ", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
