extends TestCase

## Settings is persisted to user://settings.cfg, which is a plain text file the
## player (or a bad write, or a half-finished save) can corrupt. Anything read
## from it must be treated as untrusted: the game has to boot with sane values
## no matter what the file says.

## Tests run against a scratch file, never the player's real settings.
const PATH := "user://settings_under_test.cfg"

var _settings: Node

func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

func after_each() -> void:
	if is_instance_valid(_settings):
		_settings.free()
		_settings = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

func _write_raw(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _fresh_settings() -> Node:
	# A standalone instance, not the autoload, so tests never disturb the
	# running game's state.
	var script: GDScript = load("res://src/systems/settings.gd")
	var s: Node = script.new()
	s.config_path = PATH
	s.load_settings()
	return s

## Every default must be usable as-is: finite, and non-zero where a zero would
## divide or collapse a layout.
func test_defaults_are_sane() -> void:
	_settings = _fresh_settings()
	var defaults: Dictionary = _settings.DEFAULTS
	check(defaults.size() > 0, "there are defaults")
	for key in defaults.keys():
		var v: Variant = defaults[key]
		if typeof(v) == TYPE_FLOAT:
			finite(float(v), "default %s" % key)
	var scale := float(_settings.get_value("ui_scale", 1.0))
	check(scale > 0.0, "default ui_scale must be > 0, got %f" % scale)

func test_missing_file_yields_defaults() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	_settings = _fresh_settings()
	approx(float(_settings.get_value("master_volume", -1.0)), float(_settings.DEFAULTS["master_volume"]), 0.0001, "missing file")

func test_garbage_file_does_not_crash() -> void:
	_write_raw("this is not a config file\n" + String.chr(0) + String.chr(1) + "binary junk\n[[[")
	_settings = _fresh_settings()
	# Reaching here without crashing is the assertion.
	not_null(_settings.get_value("master_volume", null), "still returns a value after garbage input")

func test_wrong_types_are_coerced() -> void:
	_write_raw("[settings]\nmaster_volume=\"loud\"\nfullscreen=\"yes\"\nfluid_quality=\"ultra\"\n")
	_settings = _fresh_settings()
	var vol: Variant = _settings.get_value("master_volume", 0.5)
	check(typeof(vol) == TYPE_FLOAT or typeof(vol) == TYPE_INT, "volume coerced to a number, got type %d" % typeof(vol))
	finite(float(vol), "coerced volume")

## A NaN or infinity that survives into a bus volume or a UI scale divides or
## blanks the game. clampf() does not remove NaN, so this is a real risk.
func test_non_finite_values_are_rejected() -> void:
	_write_raw("[settings]\nmaster_volume=nan\nmusic_volume=inf\nui_scale=nan\n")
	_settings = _fresh_settings()
	finite(float(_settings.get_value("master_volume", 0.5)), "master_volume from 'nan'")
	finite(float(_settings.get_value("music_volume", 0.5)), "music_volume from 'inf'")
	var scale := float(_settings.get_value("ui_scale", 1.0))
	finite(scale, "ui_scale from 'nan'")
	check(scale > 0.0, "ui_scale must stay > 0 to avoid a divide by zero, got %f" % scale)

func test_out_of_range_values_are_clamped() -> void:
	_write_raw("[settings]\nmaster_volume=1e9\nmusic_volume=-5.0\nui_scale=0.0\nfluid_quality=999\ncolorblind_mode=-7\n")
	_settings = _fresh_settings()
	in_range(float(_settings.get_value("master_volume", 0.5)), 0.0, 1.0, "master_volume clamped to a linear 0..1")
	in_range(float(_settings.get_value("music_volume", 0.5)), 0.0, 1.0, "music_volume clamped")
	var scale := float(_settings.get_value("ui_scale", 1.0))
	check(scale > 0.0, "ui_scale 0 must not survive, got %f" % scale)
	# Out-of-range enums must resolve to something the consumers can index.
	var q := int(_settings.get_value("fluid_quality", 1))
	in_range(float(q), 0.0, 3.0, "fluid_quality clamped to a real preset")
	var cb := int(_settings.get_value("colorblind_mode", 0))
	in_range(float(cb), 0.0, 3.0, "colorblind_mode clamped to a real palette")

func test_team_color_is_valid_for_every_palette() -> void:
	_settings = _fresh_settings()
	for mode in range(-2, 8):
		_settings.set_value("colorblind_mode", mode, false)
		for pid in [0, 1]:
			var c: Color = _settings.team_color(pid)
			in_range(c.r, 0.0, 1.0, "mode %d player %d red" % [mode, pid])
			in_range(c.g, 0.0, 1.0, "mode %d player %d green" % [mode, pid])
			in_range(c.b, 0.0, 1.0, "mode %d player %d blue" % [mode, pid])
		var a: Color = _settings.team_color(0)
		var b: Color = _settings.team_color(1)
		# The two teams must never be the same colour, or the match is unreadable.
		check(a != b, "mode %d gives the two teams distinct colours" % mode)

func test_round_trip_survives_save_and_load() -> void:
	_settings = _fresh_settings()
	_settings.set_value("master_volume", 0.42, false)
	_settings.set_value("fluid_quality", 3, false)
	_settings.set_value("reduce_motion", true, false)
	_settings.save()
	var reloaded: Node = load("res://src/systems/settings.gd").new()
	reloaded.config_path = PATH
	reloaded.load_settings()
	approx(float(reloaded.get_value("master_volume", 0.0)), 0.42, 0.001, "float round trip")
	eq(int(reloaded.get_value("fluid_quality", 0)), 3, "int round trip")
	eq(bool(reloaded.get_value("reduce_motion", false)), true, "bool round trip")
	reloaded.free()

## Red team found that a single badly-typed key aborted load_settings() mid-loop,
## silently reverting that key and every key after it to defaults, on every boot.
func test_a_bad_key_does_not_discard_later_keys() -> void:
	_write_raw("[settings]
master_volume=0.11
fluid_quality=3
screen_shake={\"a\": 1}
haptics_strength=0.33
ui_scale=1.5
")
	_settings = _fresh_settings()
	approx(float(_settings.get_value("master_volume", 0.0)), 0.11, 0.001, "key before the bad one survives")
	eq(int(_settings.get_value("fluid_quality", 0)), 3, "int key before the bad one survives")
	approx(float(_settings.get_value("haptics_strength", 0.0)), 0.33, 0.001, "key after the bad one survives")
	approx(float(_settings.get_value("ui_scale", 0.0)), 1.5, 0.001, "later key survives")
	# The unreadable key itself falls back rather than taking the file down.
	finite(float(_settings.get_value("screen_shake", 1.0)), "bad key falls back to a usable value")

## The very first key being unreadable used to wipe all sixteen settings.
func test_a_bad_first_key_does_not_wipe_everything() -> void:
	_write_raw("[settings]
master_volume={\"a\": 1}
fluid_quality=2
ui_scale=1.25
")
	_settings = _fresh_settings()
	eq(int(_settings.get_value("fluid_quality", 0)), 2, "later int survives a bad first key")
	approx(float(_settings.get_value("ui_scale", 0.0)), 1.25, 0.001, "later float survives a bad first key")
