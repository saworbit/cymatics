extends TestCase

## Rumble that fires in a menu, while paused, or for an AI paddle is the kind
## of bug players report as "my controller buzzes forever". The gate is one
## function, so it is worth pinning down directly.

var _haptics: Node
var _settings: Node

class FakePaddle:
	extends Node
	var is_ai := false

class FakeGame:
	extends Node
	var current_state := 0

func before_each() -> void:
	var script: GDScript = load("res://src/systems/haptics.gd")
	_haptics = script.new()
	tree.root.add_child(_haptics)
	# A private settings instance so the player's real config is untouched.
	_settings = load("res://src/systems/settings.gd").new()
	_settings.config_path = "user://haptics_under_test.cfg"
	_haptics._settings_node = _settings

func after_each() -> void:
	if is_instance_valid(_haptics):
		_haptics.free()
	if is_instance_valid(_settings):
		_settings.free()
	tree.paused = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://haptics_under_test.cfg"))

func _bind(left_ai: bool, right_ai: bool, state: int) -> void:
	var l := FakePaddle.new()
	l.is_ai = left_ai
	var r := FakePaddle.new()
	r.is_ai = right_ai
	var g := FakeGame.new()
	g.current_state = state
	tree.root.add_child(l)
	tree.root.add_child(r)
	tree.root.add_child(g)
	var bound: Array[Node] = [l, r]
	_haptics._paddles = bound
	_haptics._game = g

func _cleanup_bound() -> void:
	for n in [_haptics._paddles[0], _haptics._paddles[1], _haptics._game]:
		if n != null and is_instance_valid(n):
			n.free()
	var cleared: Array[Node] = [null, null]
	_haptics._paddles = cleared
	_haptics._game = null

func test_fires_for_a_human_during_play() -> void:
	_settings.set_value("haptics", true, false)
	_settings.set_value("haptics_strength", 0.8, false)
	_bind(false, false, GameManager.State.PLAYING)
	is_true(_haptics._can_fire(0), "human player 0 during play")
	is_true(_haptics._can_fire(1), "human player 1 during play")
	_cleanup_bound()

func test_never_fires_for_an_ai_paddle() -> void:
	_settings.set_value("haptics", true, false)
	_settings.set_value("haptics_strength", 0.8, false)
	_bind(false, true, GameManager.State.PLAYING)
	is_true(_haptics._can_fire(0), "human side still rumbles")
	is_false(_haptics._can_fire(1), "AI side must never rumble")
	_cleanup_bound()

func test_never_fires_in_the_menu() -> void:
	_settings.set_value("haptics", true, false)
	_settings.set_value("haptics_strength", 0.8, false)
	_bind(false, false, GameManager.State.MENU)
	is_false(_haptics._can_fire(0), "menu must be silent")
	is_false(_haptics._can_fire(1), "menu must be silent")
	_cleanup_bound()

func test_never_fires_while_paused_state() -> void:
	_settings.set_value("haptics", true, false)
	_settings.set_value("haptics_strength", 0.8, false)
	_bind(false, false, GameManager.State.PAUSED)
	is_false(_haptics._can_fire(0), "paused state must be silent")
	_cleanup_bound()

func test_never_fires_while_the_tree_is_paused() -> void:
	_settings.set_value("haptics", true, false)
	_settings.set_value("haptics_strength", 0.8, false)
	_bind(false, false, GameManager.State.PLAYING)
	tree.paused = true
	is_false(_haptics._can_fire(0), "tree pause must be silent")
	tree.paused = false
	_cleanup_bound()

func test_respects_the_disable_setting() -> void:
	_settings.set_value("haptics", false, false)
	_settings.set_value("haptics_strength", 1.0, false)
	_bind(false, false, GameManager.State.PLAYING)
	is_false(_haptics._can_fire(0), "disabled by setting")
	_cleanup_bound()

func test_zero_strength_is_treated_as_off() -> void:
	_settings.set_value("haptics", true, false)
	_settings.set_value("haptics_strength", 0.0, false)
	_bind(false, false, GameManager.State.PLAYING)
	is_false(_haptics._can_fire(0), "zero strength must not fire")
	_cleanup_bound()

func test_out_of_range_player_index_is_rejected() -> void:
	_settings.set_value("haptics", true, false)
	_settings.set_value("haptics_strength", 0.8, false)
	_bind(false, false, GameManager.State.PLAYING)
	is_false(_haptics._can_fire(-1), "negative index")
	is_false(_haptics._can_fire(2), "index past the second pad")
	is_false(_haptics._can_fire(99), "far out of range")
	_cleanup_bound()

## Strength scales the motors, so it must stay a finite 0..1 even if the
## setting is nonsense.
func test_strength_is_bounded() -> void:
	for v in [-10.0, 0.0, 0.5, 1.0, 99.0]:
		_settings.set_value("haptics_strength", v, false)
		in_range(float(_haptics.strength()), 0.0, 1.0, "strength for setting %f" % v)
