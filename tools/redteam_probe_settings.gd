extends SceneTree

## Red-team probe: print what the Settings autoload actually ended up with after
## load_settings(), so a corrupt user://settings.cfg can be traced key by key.
##
##   python tools/redteam_setcfg.py 'master_volume={"a":1}' 'fluid_quality=3'
##   godot --headless --path . --script res://tools/redteam_probe_settings.gd

const KEYS := ["master_volume", "music_volume", "sfx_volume", "music_enabled",
	"fullscreen", "vsync", "bloom", "chromatic", "reduce_motion", "screen_flash",
	"fluid_quality", "colorblind_mode", "ui_scale", "screen_shake", "haptics",
	"haptics_strength"]

func _process(_d: float) -> bool:
	var s := root.get_node_or_null("Settings")
	if s == null:
		print("PROBE no Settings autoload")
		return true
	for k in KEYS:
		print("PROBE %-18s = %s" % [k, str(s.call("get_value", k))])
	return true
