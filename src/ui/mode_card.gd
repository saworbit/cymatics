@tool
class_name ModeCard
extends Control

## One game-mode card on the title screen. Instanced four times in menu.tscn
## with exported title/description/accent so the layout lives in one place.

signal activated
## Emitted once each time the cursor enters the card (MenuManager uses it to
## make the mascots react).
signal hovered

@export var icon := "🚀":
	set(v):
		icon = v
		_apply_texts()
@export var title := "MODE":
	set(v):
		title = v
		_apply_texts()
@export_multiline var description := "":
	set(v):
		description = v
		_apply_texts()
@export var badge := "":
	set(v):
		badge = v
		_apply_texts()
@export var button_text := "PLAY":
	set(v):
		button_text = v
		_apply_texts()
@export var accent := Color(0.0, 0.898, 1.0):
	set(v):
		accent = v
		_apply_accent()
@export var show_difficulty := false:
	set(v):
		show_difficulty = v
		_apply_texts()

@onready var panel: PanelContainer = %Panel
@onready var icon_label: Label = %Icon
@onready var title_label: Label = %CardTitle
@onready var desc_label: Label = %CardDesc
@onready var badge_label: Label = %Badge
@onready var diff_row: HBoxContainer = %DiffRow
@onready var diff_option: OptionButton = %DiffOption
@onready var button: Button = %PlayBtn

const TILT_DEG := 3.0
const HOVER_SCALE := 1.025

var _hover := false
var _settings_node: Node

func _ready() -> void:
	_apply_texts()
	_apply_accent()
	if not Engine.is_editor_hint():
		button.pressed.connect(func(): activated.emit())
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(func(): _hover = false)
		pivot_offset = size * 0.5
		resized.connect(func(): pivot_offset = size * 0.5)

func _on_mouse_entered() -> void:
	_hover = true
	hovered.emit()

func _reduce_motion() -> bool:
	if _settings_node == null or not is_instance_valid(_settings_node):
		_settings_node = get_node_or_null("/root/Settings")
	if _settings_node == null:
		return false
	return bool(_settings_node.call("get_value", "reduce_motion", false))

## Hover parallax: the card leans a few degrees toward the cursor and lifts
## slightly. Rotation is around the centre so the HBox layout is untouched.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var want_rot := 0.0
	var want_scale := 1.0
	if _hover and is_visible_in_tree() and not _reduce_motion():
		var local := get_local_mouse_position() - size * 0.5
		var nx := clampf(local.x / maxf(size.x * 0.5, 1.0), -1.0, 1.0)
		var ny := clampf(local.y / maxf(size.y * 0.5, 1.0), -1.0, 1.0)
		# Lean toward the cursor: right side of the card tips clockwise when
		# the cursor is above it, so mix x and y for a "toward" feel.
		want_rot = deg_to_rad(TILT_DEG) * (nx * 0.8 - ny * 0.35 * signf(nx + 0.001))
		want_scale = HOVER_SCALE
	var k := clampf(delta * 10.0, 0.0, 1.0)
	rotation = lerpf(rotation, want_rot, k)
	var sc := lerpf(scale.x, want_scale, k)
	scale = Vector2(sc, sc)

func _apply_texts() -> void:
	if not is_node_ready():
		return
	icon_label.text = icon
	title_label.text = title
	desc_label.text = description
	badge_label.text = badge
	badge_label.visible = not badge.is_empty()
	button.text = button_text
	diff_row.visible = show_difficulty

func _apply_accent() -> void:
	if not is_node_ready():
		return
	title_label.add_theme_color_override("font_color", accent)
	button.add_theme_color_override("font_color", accent)
	button.add_theme_color_override("font_hover_color", accent.lightened(0.35))
	button.add_theme_color_override("font_focus_color", accent.lightened(0.35))
	var base := panel.get_theme_stylebox("panel", "PanelContainer")
	if base is StyleBoxFlat:
		var sb: StyleBoxFlat = base.duplicate()
		sb.border_color = Color(accent.r, accent.g, accent.b, 0.45)
		panel.add_theme_stylebox_override("panel", sb)

## Difficulty multiplier chosen in the option button (arcade card only).
func get_difficulty_multiplier() -> float:
	if diff_option == null:
		return 1.0
	match diff_option.selected:
		0: return 0.75
		1: return 1.0
		2: return 1.35
		3: return 1.8
	return 1.0
