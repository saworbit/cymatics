class_name UIScaleRoot
extends Control

## Wrapper inserted at the top of a UI `CanvasLayer` so the `ui_scale` setting
## can enlarge or shrink the whole layer without breaking anchors.
##
## Controls parented directly to a CanvasLayer always lay out against the full
## viewport rect, so scaling the layer alone pushes edge-anchored widgets off
## screen. Instead every child is reparented under this Control, which is sized
## to `viewport / scale` and then scaled back up: anchors resolve inside a
## smaller virtual canvas that ends up exactly filling the screen.
##
## Install once from the layer's `_ready`, after `@onready` references resolve
## (reparenting keeps node instances and their owner, so `%UniqueName` and cached
## references stay valid).

const MIN_SCALE := 0.6
const MAX_SCALE := 2.0

var _scale := 1.0

## Reparents every existing child of `layer` under a new UIScaleRoot.
## Returns the wrapper, or the existing one when called twice.
static func install(layer: CanvasLayer) -> UIScaleRoot:
	if layer == null:
		return null
	for c in layer.get_children():
		if c is UIScaleRoot:
			return c as UIScaleRoot
	var moved: Array[Node] = []
	for c in layer.get_children():
		moved.append(c)
	var root := UIScaleRoot.new()
	root.name = "UIScaleRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	layer.add_child(root)
	layer.move_child(root, 0)
	for c in moved:
		c.reparent(root, false)
	return root

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_refresh):
		vp.size_changed.connect(_refresh)
	_refresh()

## 0.8 / 1.0 / 1.25 / 1.5 from the `ui_scale` setting.
func set_ui_scale(value: float) -> void:
	# clampf() passes NaN straight through, and a NaN scale propagates into
	# Control.size, which the engine rejects and which blanks the whole HUD.
	if not is_finite(value) or value <= 0.0:
		push_warning("[UIScaleRoot] ignoring a non-finite ui_scale (%s)" % value)
		value = 1.0
	_scale = clampf(value, MIN_SCALE, MAX_SCALE)
	_refresh()

func _refresh() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	var vp_size := Vector2(1920.0, 1080.0)
	if vp != null:
		var r := vp.get_visible_rect().size
		if r.x > 1.0 and r.y > 1.0:
			vp_size = r
	position = Vector2.ZERO
	scale = Vector2(_scale, _scale)
	# The virtual canvas the children lay out inside.
	size = vp_size / _scale
