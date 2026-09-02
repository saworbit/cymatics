extends Node

## Settings autoload (registered as `Settings` in project.godot).
##
## Persists user preferences to user://settings.cfg and applies them to the
## engine on load: window mode, vsync, and audio bus volumes. Everything else
## (bloom, chromatic aberration, reduce motion, screen flash) is exposed via the
## `changed` signal and `get_value()` so gameplay systems can read it.
##
## Keys (all in section "settings"):
##   master_volume, music_volume, sfx_volume  : float 0..1
##   fullscreen, vsync                        : bool
##   bloom (0..3), chromatic (0..4)           : float (display shader)
##   reduce_motion, screen_flash              : bool
##   music_enabled                            : bool

signal changed(key: String, value: Variant)

const PATH := "user://settings.cfg"
const SECTION := "settings"

const DEFAULTS := {
	"master_volume": 0.85,
	"music_volume": 0.8,
	"sfx_volume": 0.9,
	"music_enabled": true,
	"fullscreen": false,
	"vsync": true,
	"bloom": 1.2,
	"chromatic": 1.8,
	"reduce_motion": false,
	"screen_flash": true,
}

const BUS_FOR_KEY := {
	"master_volume": "Master",
	"music_volume": "Music",
	"sfx_volume": "SFX",
}

var _values: Dictionary = {}
var _dirty := false
var _save_timer: SceneTreeTimer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_all()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if _dirty:
			save()

# --- Public API ---------------------------------------------------------------

func get_value(key: String, default: Variant = null) -> Variant:
	if _values.has(key):
		return _values[key]
	if DEFAULTS.has(key):
		return DEFAULTS[key]
	return default

func set_value(key: String, value: Variant, persist := true) -> void:
	if _values.has(key) and _values[key] == value:
		return
	_values[key] = value
	_apply(key, value)
	changed.emit(key, value)
	if persist:
		_mark_dirty()

func toggle(key: String) -> bool:
	var v := not bool(get_value(key, false))
	set_value(key, v)
	return v

func reset_to_defaults() -> void:
	for key in DEFAULTS.keys():
		set_value(key, DEFAULTS[key], false)
	_mark_dirty()

func has_bus(bus_name: String) -> bool:
	return AudioServer.get_bus_index(bus_name) >= 0

func load_settings() -> void:
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	var err := cfg.load(PATH)
	if err != OK:
		return
	for key in DEFAULTS.keys():
		if cfg.has_section_key(SECTION, key):
			var v: Variant = cfg.get_value(SECTION, key, DEFAULTS[key])
			# Keep the stored type consistent with the default's type.
			match typeof(DEFAULTS[key]):
				TYPE_FLOAT:
					v = clampf(float(v), 0.0, 10.0)
				TYPE_BOOL:
					v = bool(v)
			_values[key] = v

func save() -> void:
	var cfg := ConfigFile.new()
	for key in _values.keys():
		cfg.set_value(SECTION, key, _values[key])
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("[Settings] Could not save %s (error %d)" % [PATH, err])
	_dirty = false

func apply_all() -> void:
	for key in _values.keys():
		_apply(key, _values[key])

# --- Internals ---------------------------------------------------------------

func _mark_dirty() -> void:
	_dirty = true
	# Debounce: slider drags emit many values; write once they settle.
	if _save_timer != null and _save_timer.time_left > 0.0:
		return
	if not is_inside_tree():
		save()
		return
	_save_timer = get_tree().create_timer(0.5, true, false, true)
	_save_timer.timeout.connect(func():
		if _dirty:
			save()
	)

func _apply(key: String, value: Variant) -> void:
	match key:
		"master_volume", "music_volume", "sfx_volume":
			_apply_bus_volume(BUS_FOR_KEY[key], float(value))
		"fullscreen":
			_apply_fullscreen(bool(value))
		"vsync":
			if DisplayServer.get_name() == "headless":
				return
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if bool(value) else DisplayServer.VSYNC_DISABLED)
		_:
			pass

func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	linear = clampf(linear, 0.0, 1.0)
	if linear <= 0.001:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))

func _apply_fullscreen(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if on == is_full:
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)

func is_fullscreen() -> bool:
	return bool(get_value("fullscreen", false))
