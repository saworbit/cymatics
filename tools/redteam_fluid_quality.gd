extends SceneTree

## Red-team repro: changing `fluid_quality` while FluidSimulator is on its CPU
## fallback corrupts the sim permanently.
##
## FluidSimulator.set_quality() (src/systems/fluid_simulator.gd:123-125) does
##     if not is_compute_ready:
##         grid_size = grid
##         return
## i.e. it moves grid_size but never re-runs _init_cpu_fallback(), so
## _step_cpu_fallback() indexes buffers sized for the OLD grid with the NEW
## dimensions -> "Out of bounds get index" every physics frame, forever.
##
##   godot --headless --path . --script res://tools/redteam_fluid_quality.gd
##
## Any machine with no compute RenderingDevice (headless, Compatibility renderer)
## takes this path, and the Settings menu exposes the Fluid Detail picker.

var _main: Node
var _t0 := 0
var _phase := 0
var _sim: Node
var _fps_before := 0.0
var _fps_after := 0.0
var _frames := 0
var _mark := 0

var _target := 2

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--target="):
			_target = int(a.get_slice("=", 1))
	_main =(load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_t0 = Time.get_ticks_msec()

func _rt() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0

func _dump(tag: String) -> void:
	print("%-10s grid_size=%s  compute_ready=%s  cpu_fallback=%s  cpu_dye_r.size()=%d  cells_needed=%d  image=%dx%d" % [
		tag, str(_sim.get("grid_size")), str(_sim.get("is_compute_ready")),
		str(_sim.get("_cpu_fallback")), (_sim.get("_cpu_dye_r") as PackedFloat32Array).size(),
		int(_sim.get("grid_size").x) * int(_sim.get("grid_size").y),
		_sim.get("_cpu_image").get_width(), _sim.get("_cpu_image").get_height()])

func _process(_d: float) -> bool:
	_frames += 1
	if _sim == null:
		_sim = _main.get_node_or_null("FluidSimulator")
		if _sim == null:
			return true
	var gm: Node = _main.get_node_or_null("GameManager")
	match _phase:
		0:
			if _rt() > 2.0:
				gm.call("start_arcade_match", 1.0)
				gm.emit_signal("lab_watch_toggled")
				_dump("BOOT")
				_mark = Time.get_ticks_msec()
				_frames = 0
				_phase = 1
		1:
			if _rt() > 7.0:
				_fps_before = float(_frames) / (float(Time.get_ticks_msec() - _mark) / 1000.0)
				print("BEFORE  %.1f main-loop iterations/s over %d frames" % [_fps_before, _frames])
				print(">>> setting fluid_quality = %d via the Settings autoload," % _target)
				print(">>> exactly what the Fluid Detail picker in the settings modal does")
				root.get_node("Settings").call("set_value", "fluid_quality", _target, false)
				_dump("AFTER")
				_mark = Time.get_ticks_msec()
				_frames = 0
				_phase = 2
		2:
			if _rt() > 12.0:
				_fps_after = float(_frames) / (float(Time.get_ticks_msec() - _mark) / 1000.0)
				print("AFTER   %.1f main-loop iterations/s over %d frames" % [_fps_after, _frames])
				print("RESULT rate %.1f -> %.1f (%.0f%% of before); look for repeated"
					% [_fps_before, _fps_after, 100.0 * _fps_after / maxf(_fps_before, 0.001)])
				print("RESULT 'Out of bounds get index' at fluid_simulator.gd:620 above.")
				_dump("FINAL")
				return true
	return false
