extends SceneTree

## Headless-friendly screenshot driver for visual checks.
##
## Usage (from the project root):
##   godot --path . --resolution 1920x1080 --script res://tools/screenshot_run.gd -- --out=C:/tmp/shots
##
## Boots the main scene, walks the menu, starts an arcade match, switches to
## AI vs AI (lab watch) so a rally plays without input, and saves PNGs at fixed
## timestamps. Uses unscaled wall-clock time so pause and hit-stop cannot stall
## the schedule.

var _out := "user://shots/"
var _start_ms := 0
var _step := 0
var _main: Node
var _pending: Array = []
var _plan := [
	[2.5, "shot:menu"],
	[2.6, "state:1"], [3.1, "shot:menu_gauntlet_dossier"],
	[3.2, "state:3"], [3.7, "shot:menu_codex"],
	[3.8, "state:4"], [4.3, "shot:menu_settings"],
	[4.4, "state:0"],
	[4.5, "arcade"],
	[5.5, "shot:match_serve"],
	[7.0, "press:toggle_lab"],
	[10.0, "shot:match_rally1"],
	[14.0, "shot:match_rally2"],
	[20.0, "shot:match_rally3"],
	[28.0, "shot:match_rally4"],
	[36.0, "shot:match_rally5"],
	[36.5, "press:ui_cancel"],
	[37.5, "shot:match_pause"],
	[38.0, "quit"],
]

## `--plan=human` serves as P1 and shoots a burst of frames while the human
## paddle sits still, which exercises the goal-line threat reticle.
var _plan_human := [
	[2.5, "arcade"],
	[4.0, "press:p1_blast"],
	[4.6, "shot:human_1"],
	[5.2, "shot:human_2"],
	[5.8, "shot:human_3"],
	[6.4, "shot:human_4"],
	[7.0, "shot:human_5"],
	[7.6, "shot:human_6"],
	[8.2, "shot:human_7"],
	[8.8, "shot:human_8"],
	[9.4, "shot:human_9"],
	[10.0, "shot:human_10"],
	[10.6, "shot:human_11"],
	[11.2, "shot:human_12"],
	[11.8, "shot:human_13"],
	[12.4, "shot:human_14"],
	[13.0, "quit"],
]

## `--plan=goal` starts an arcade match, fires a P1 blast (cone frames), then
## flips to AI vs AI and forces a goal on each side with a burst of frames
## every 40-100 ms so the freeze, slow-mo and debris cone are all captured.
func _plan_goal() -> Array:
	var plan := [
		[2.5, "arcade"],
		[4.0, "press:p1_blast"], # launches the serve
		[5.2, "press:p1_blast"], # blast in flight -> cone
		[5.24, "shot:blast_1"],
		[5.3, "shot:blast_2"],
		[5.4, "shot:blast_3"],
		[6.0, "press:toggle_lab"],
	]
	for g in [[8.0, 1, "goal_r"], [15.5, 0, "goal_l"]]:
		var t0: float = g[0]
		plan.append([t0, "goal:" + str(g[1])])
		var offs := [0.03, 0.07, 0.11, 0.16, 0.22, 0.3, 0.4, 0.5, 0.65, 0.85, 1.1, 1.6, 2.2]
		for i in offs.size():
			plan.append([t0 + offs[i], "shot:%s_%02d" % [g[2], i]])
	plan.append([18.5, "quit"])
	return plan

## `--plan=vfx` fires each VFXManager event directly at fixed positions during
## the serve hold and shoots frames at fixed offsets, isolating the effects from
## gameplay timing (serve ritual, captures, cooldowns).
func _plan_vfx() -> Array:
	var plan := [[2.5, "arcade"]]
	var t := 4.0
	for ev in ["shatter", "cone", "parry", "shards", "wall", "hit"]:
		plan.append([t, "vfx:" + ev])
		for off in [0.04, 0.12, 0.25, 0.5]:
			plan.append([t + off, "shot:vfx_%s_%03d" % [ev, int(off * 1000)]])
		t += 1.2
	plan.append([t, "quit"])
	return plan

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg == "--plan=human":
			_plan = _plan_human
		elif arg == "--plan=goal":
			_plan = _plan_goal()
		elif arg == "--plan=vfx":
			_plan = _plan_vfx()
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(_out)
	var packed: PackedScene = load("res://scenes/main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	_start_ms = Time.get_ticks_msec()

func _process(_delta: float) -> bool:
	if _step >= _plan.size():
		_flush_shots()
		return true
	var t := float(Time.get_ticks_msec() - _start_ms) / 1000.0
	if t < float(_plan[_step][0]):
		return false
	var cmd: String = _plan[_step][1]
	_step += 1
	var parts := cmd.split(":")
	var menu: Node = _main.get_node_or_null("Menu")
	match parts[0]:
		"shot":
			var vfxn: Node = _main.get_node_or_null("VFXManager")
			if vfxn != null and OS.get_cmdline_user_args().has("--debug-vfx"):
				var names := []
				for c in vfxn.get_children():
					names.append("%s@%s" % [c.get_class(), str(c.global_position)])
				print("DBG t=%.3f ts=%.2f paused=%s kids=%s" % [t, Engine.time_scale, str(paused), str(names)])
			# PNG encoding costs ~0.8 s per frame, which would stretch every
			# short effect out of the plan; buffer and write at quit instead.
			var img := root.get_viewport().get_texture().get_image()
			_pending.append([_out + parts[1] + ".png", img])
			if _pending.size() >= 40:
				_flush_shots()
		"state":
			if menu != null and menu.has_method("_switch_state"):
				menu.call("_switch_state", int(parts[1]))
		"arcade":
			if menu != null and menu.has_method("_on_arcade_clicked"):
				menu.call("_on_arcade_clicked")
		"press":
			var ev := InputEventAction.new()
			ev.action = parts[1]
			ev.pressed = true
			Input.parse_input_event(ev)
		"vfx":
			var vfx: Node = _main.get_node_or_null("VFXManager")
			var cyan := Color(0.0, 0.9, 1.0)
			var pink := Color(1.0, 0.0, 0.67)
			if vfx != null:
				match parts[1]:
					"shatter":
						vfx.call("spawn_goal_shatter", Vector2(960, 540), Vector2(-1500, 0), cyan)
					"cone":
						vfx.call("spawn_blast_cone", Vector2(700, 540), Vector2.RIGHT, cyan, 1.0)
					"parry":
						vfx.call("spawn_parry_star", Vector2(960, 540), pink, Vector2.RIGHT)
					"shards":
						vfx.call("spawn_brick_shards", Vector2(960, 540), Vector2(70, 36), Color(1.0, 0.6, 0.2), 16)
						vfx.call("spawn_brick_chips", Vector2(1300, 540), Vector2.LEFT, Color(0.2, 0.8, 1.0))
					"wall":
						vfx.call("spawn_wall_hit", Vector2(960, 40), Vector2.DOWN, 0.8)
					"hit":
						vfx.call("spawn_paddle_hit", Vector2(960, 540), Vector2(0.8, -0.6).normalized(), pink, 1.0)
		"goal":
			# Push the live ball past a goal line so the goal theatre fires.
			var ball: Node = _main.get_node_or_null("Ball")
			if ball != null and bool(ball.get("is_serving")):
				print("GOAL SKIPPED: ball is serving")
			elif ball != null and not bool(ball.get("is_scored")):
				var side := int(parts[1])
				ball.set("velocity", Vector2(1500.0 if side == 1 else -1500.0, 0.0))
				ball.set("global_position", Vector2(1930.0 if side == 1 else -10.0, ball.global_position.y))
		"quit":
			_flush_shots()
			return true
	return false

func _flush_shots() -> void:
	for entry in _pending:
		(entry[1] as Image).save_png(entry[0])
		print("SHOT ", entry[0])
	_pending.clear()
