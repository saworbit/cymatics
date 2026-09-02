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
##   fluid_quality (0..3)                     : int (Low/Medium/High/Ultra grid)
##   colorblind_mode (0..3)                   : int (Off/Deut/Prot/Trit)
##   ui_scale (0.8/1.0/1.25/1.5)              : float (HUD + menu CanvasLayers)
##   screen_shake (0..1)                      : float (camera shake intensity)
##   haptics                                  : bool (gamepad vibration)
##   haptics_strength (0..1)                  : float

signal changed(key: String, value: Variant)

const PATH := "user://settings.cfg"
const SECTION := "settings"

## Where this instance reads and writes. Overridable so tests can run against a
## scratch file instead of the player's real settings.
var config_path := PATH

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
	"fluid_quality": 1,
	"colorblind_mode": 0,
	"ui_scale": 1.0,
	"screen_shake": 1.0,
	"haptics": true,
	"haptics_strength": 0.8,
}

## Inclusive valid range per key. Anything read from user://settings.cfg is
## untrusted: the file is plain text, can be hand-edited, and can be truncated
## by a crash mid-save. Values outside these bounds are clamped rather than
## rejected so the game always boots with something usable.
const RANGES := {
	"master_volume": [0.0, 1.0],
	"music_volume": [0.0, 1.0],
	"sfx_volume": [0.0, 1.0],
	"bloom": [0.0, 3.0],
	"chromatic": [0.0, 5.0],
	"fluid_quality": [0, 3],
	"colorblind_mode": [0, 3],
	"ui_scale": [0.5, 2.0],
	"screen_shake": [0.0, 1.0],
	"haptics_strength": [0.0, 1.0],
}

## Accessibility palettes. Index matches `colorblind_mode`.
## 0 Off (cyan / magenta), 1 Deuteranopia, 2 Protanopia, 3 Tritanopia.
## Each entry is [player 0 colour, player 1 colour]; both pairs stay separable
## in luminance as well as hue so the two teams read even in greyscale.
enum ColorblindMode { OFF, DEUTERANOPIA, PROTANOPIA, TRITANOPIA }

const COLORBLIND_MODE_NAMES := ["OFF", "DEUTERANOPIA", "PROTANOPIA", "TRITANOPIA"]

const TEAM_PALETTES := [
	[Color(0.0, 0.898, 1.0), Color(1.0, 0.0, 0.667)],   # Off: cyan / magenta
	[Color(0.0, 0.75, 1.0), Color(1.0, 0.54, 0.0)],     # Deuteranopia: blue / orange
	[Color(0.15, 0.72, 1.0), Color(1.0, 0.78, 0.05)],   # Protanopia: blue / amber
	[Color(0.0, 0.78, 0.9), Color(1.0, 0.28, 0.28)],    # Tritanopia: teal / red
]

## Allowed UI scale steps; the settings modal cycles through these.
const UI_SCALES := [0.8, 1.0, 1.25, 1.5]

## Fluid simulation grid presets. FluidSimulator owns the actual grid sizes and
## rebuilds itself when `fluid_quality` changes.
const FLUID_QUALITY_NAMES := ["LOW", "MEDIUM", "HIGH", "ULTRA"]

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
	value = coerce(key, value)
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

# --- Accessibility helpers ----------------------------------------------------

## Single source of truth for team colour. `player_id` 0 = left/Padd, 1 = right/Lin.
## Every UI and gameplay call site that paints a team should route through this.
func team_color(player_id: int) -> Color:
	var mode := clampi(int(get_value("colorblind_mode", 0)), 0, TEAM_PALETTES.size() - 1)
	var pair: Array = TEAM_PALETTES[mode]
	return pair[clampi(player_id, 0, 1)]

## Dimmer variant for fills and bars.
func team_color_dim(player_id: int, alpha: float = 0.85) -> Color:
	var c := team_color(player_id)
	return Color(c.r, c.g, c.b, alpha)

## Remaps a hard-coded team colour to the current palette. Anything close to the
## default cyan maps to player 0, anything close to the default magenta to
## player 1; everything else (gold, white, boss hues) is returned untouched.
func remap_team_color(c: Color) -> Color:
	if int(get_value("colorblind_mode", 0)) == 0:
		return c
	var base: Array = TEAM_PALETTES[0]
	for i in 2:
		var b: Color = base[i]
		if absf(c.r - b.r) < 0.28 and absf(c.g - b.g) < 0.28 and absf(c.b - b.b) < 0.28:
			var t := team_color(i)
			return Color(t.r, t.g, t.b, c.a)
	return c

## Display names for the colourblind picker, in `colorblind_mode` order.
func colorblind_mode_names() -> Array:
	return COLORBLIND_MODE_NAMES.duplicate()

## Allowed UI scale steps, smallest first.
func ui_scale_steps() -> Array:
	return UI_SCALES.duplicate()

## Display names for the fluid detail picker, in `fluid_quality` order.
func fluid_quality_names() -> Array:
	return FLUID_QUALITY_NAMES.duplicate()

func colorblind_mode() -> int:
	return clampi(int(get_value("colorblind_mode", 0)), 0, TEAM_PALETTES.size() - 1)

func ui_scale() -> float:
	return clampf(float(get_value("ui_scale", 1.0)), 0.6, 2.0)

## 0..1 multiplier for camera shake and kick. Reduce motion halves it again.
func shake_scale() -> float:
	return clampf(float(get_value("screen_shake", 1.0)), 0.0, 1.0)

func haptics_enabled() -> bool:
	return bool(get_value("haptics", true))

func haptics_strength() -> float:
	return clampf(float(get_value("haptics_strength", 0.8)), 0.0, 1.0)

func reset_to_defaults() -> void:
	for key in DEFAULTS.keys():
		set_value(key, DEFAULTS[key], false)
	_mark_dirty()

func has_bus(bus_name: String) -> bool:
	return AudioServer.get_bus_index(bus_name) >= 0

func load_settings() -> void:
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	var err := cfg.load(config_path)
	if err != OK:
		return
	for key in DEFAULTS.keys():
		if cfg.has_section_key(SECTION, key):
			_values[key] = coerce(key, cfg.get_value(SECTION, key, DEFAULTS[key]))

## Force `value` into the type and range the key promises, falling back to the
## default when it cannot be salvaged. NaN and infinity must never escape here:
## a non-finite volume reaches AudioServer as a NaN decibel, and a non-finite
## ui_scale divides the UI canvas by zero.
func coerce(key: String, value: Variant) -> Variant:
	if not DEFAULTS.has(key):
		return value
	var fallback: Variant = DEFAULTS[key]
	match typeof(fallback):
		TYPE_FLOAT:
			if not (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT):
				return fallback
			var f := float(value)
			if not is_finite(f):
				return fallback
			if RANGES.has(key):
				return clampf(f, float(RANGES[key][0]), float(RANGES[key][1]))
			return f
		TYPE_INT:
			if typeof(value) == TYPE_BOOL:
				return 1 if value else 0
			if not (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT):
				return fallback
			if typeof(value) == TYPE_FLOAT and not is_finite(float(value)):
				return fallback
			var i := int(value)
			if RANGES.has(key):
				return clampi(i, int(RANGES[key][0]), int(RANGES[key][1]))
			return i
		TYPE_BOOL:
			# bool() is not a constructor in GDScript 2; convert explicitly.
			match typeof(value):
				TYPE_BOOL:
					return value
				TYPE_INT, TYPE_FLOAT:
					return float(value) != 0.0
				TYPE_STRING, TYPE_STRING_NAME:
					var t := String(value).strip_edges().to_lower()
					return t == "true" or t == "1" or t == "yes" or t == "on"
				_:
					return fallback
	return value

func save() -> void:
	var cfg := ConfigFile.new()
	for key in _values.keys():
		cfg.set_value(SECTION, key, _values[key])
	var err := cfg.save(config_path)
	if err != OK:
		push_warning("[Settings] Could not save %s (error %d)" % [config_path, err])
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
