extends SceneTree

## Red-team probe: Escape is swallowed on the results screen.
##
## GameManager._input (src/systems/game_manager.gd:243-249) treats every
## `pause`/`ui_cancel` press as a pause toggle whenever the state is not MENU,
## and marks the event handled. toggle_pause() (game_manager.gd:~740) then does
## nothing at all in MATCH_OVER, because is_live() excludes it. MenuManager._input
## never sees the event, so on the match-results overlay Escape is a dead key.
##
##   godot --headless --path . --script res://tools/redteam_results_esc.gd

var _main: Node
var _t0 := 0
var _stage := 0
var _mark := 0
var _menu_state_before := -1

func _rt() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0

func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_t0 = Time.get_ticks_msec()

func _esc() -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = "pause"
		e.pressed = pressed
		Input.parse_input_event(e)
		var e2 := InputEventAction.new()
		e2.action = "ui_cancel"
		e2.pressed = pressed
		Input.parse_input_event(e2)

func _process(_d: float) -> bool:
	var gm: Node = _main.get_node_or_null("GameManager")
	var b: Node = _main.get_node_or_null("Ball")
	var menu: Node = _main.get_node_or_null("Menu")
	if gm == null or b == null:
		return true
	match _stage:
		0:
			if _rt() < 1.5:
				return false
			gm.call("start_arcade_match", 1.0)
			gm.emit_signal("lab_watch_toggled")
			gm.set("points_to_win_set", 1)
			gm.set("sets_to_win_match", 1)
			_stage = 1
		1:
			if int(gm.get("current_state")) == 2 and not bool(b.get("is_serving")) and not bool(b.get("is_scored")):
				b.set("velocity", Vector2(1500, 0))
				b.set("global_position", Vector2(1930, b.global_position.y))
				_stage = 2
				_mark = Time.get_ticks_msec()
			elif _rt() > 25.0:
				print("could not reach a rally")
				return true
		2:
			if float(Time.get_ticks_msec() - _mark) / 1000.0 < 3.0:
				return false
			if int(gm.get("current_state")) != 5:
				print("did not reach MATCH_OVER (state=%d); retrying" % int(gm.get("current_state")))
				_stage = 1
				return false
			_menu_state_before = int(menu.get("current_state")) if menu else -1
			print("MATCH_OVER reached. menu.current_state=%d tree.paused=%s" % [_menu_state_before, str(paused)])
			print("pressing Escape 10 times...")
			for i in 10:
				_esc()
			_mark = Time.get_ticks_msec()
			_stage = 3
		3:
			if float(Time.get_ticks_msec() - _mark) / 1000.0 < 2.0:
				return false
			var st := int(gm.get("current_state"))
			var ms := int(menu.get("current_state")) if menu else -1
			print("after Escape x10: game state=%d (5=MATCH_OVER) menu.current_state=%d tree.paused=%s" % [
				st, ms, str(paused)])
			if st == 5 and ms == _menu_state_before and not paused:
				print("RT-BUG Escape is a dead key on the results screen: no pause, no menu, no dismiss")
			else:
				print("ok Escape did something on the results screen")
			return true
	return false
