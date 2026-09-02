extends SceneTree

## Red-team probe: report the real geometry of every UIScaleRoot after boot, so a
## corrupt `ui_scale` in user://settings.cfg can be measured rather than guessed.
##
##   godot --headless --path . --script res://tools/redteam_probe_uiscale.gd

var _main: Node
var _f := 0

func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)

func _walk(n: Node, out: Array) -> void:
	if n is UIScaleRoot:
		out.append(n)
	for c in n.get_children():
		_walk(c, out)

func _process(_d: float) -> bool:
	_f += 1
	if _f < 30:
		return false
	var s := root.get_node_or_null("Settings")
	print("PROBE settings.ui_scale raw=%s  ui_scale()=%s" % [
		str(s.call("get_value", "ui_scale", 1.0)) if s else "?",
		str(s.call("ui_scale")) if s else "?"])
	var roots: Array = []
	_walk(root, roots)
	for r in roots:
		var ctl := r as Control
		print("PROBE %s scale=%s size=%s visible_in_tree=%s pos=%s" % [
			ctl.get_path(), str(ctl.scale), str(ctl.size),
			str(ctl.is_visible_in_tree()), str(ctl.position)])
		# Sample a few real children so we can see whether content has geometry.
		var shown := 0
		for c in ctl.get_children():
			var cc := c as Control
			if cc == null:
				continue
			print("PROBE     child %s rect=%s vis=%s" % [cc.name, str(cc.get_global_rect()), str(cc.is_visible_in_tree())])
			shown += 1
			if shown >= 4:
				break
	if roots.is_empty():
		print("PROBE no UIScaleRoot found")
	return true
