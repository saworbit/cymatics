class_name HUD
extends CanvasLayer

## In-match HUD: scoreboard, momentum bars, one queued callout system, serve
## hint, controls help line, screen flash, and the match results overlay.

## Fallback team colours; the live values come from `Settings.team_color()` so
## the colourblind palettes reach every score, bar, label and callout.
const P1_COLOR := Color(0.0, 0.898, 1.0)
const P2_COLOR := Color(1.0, 0.0, 0.667)
const GOLD := Color(1.0, 0.8, 0.0)

# Callout timings (seconds, unscaled)
const CALLOUT_IN := 0.18
const CALLOUT_HOLD := 0.9
const CALLOUT_OUT := 0.25
const CALLOUT_STALE_MS := 1500
const CALLOUT_QUEUE_MAX := 4

# Callout priorities used by the HUD itself. GameManager may pass its own.
const PRIO_LOW := 0
const PRIO_NORMAL := 1
const PRIO_MILESTONE := 2
const PRIO_STAGE := 3

@onready var p1_score_label: Label = %P1Score
@onready var p2_score_label: Label = %P2Score
@onready var p1_score_slot: Control = %P1ScoreSlot
@onready var p2_score_slot: Control = %P2ScoreSlot
@onready var state_chip: PanelContainer = %StateChip
@onready var state_chip_text: Label = %StateChipText
@onready var serve_dots: HBoxContainer = %ServeDots
@onready var p1_comet: ColorRect = %P1Comet
@onready var p2_comet: ColorRect = %P2Comet
@onready var sets_label: Label = %SetsLabel
@onready var rally_label: Label = %RallyCount
@onready var combo_label: Label = %ComboLabel
@onready var callout_label: Label = %Callout
@onready var sub_callout_label: Label = %SubCallout
@onready var serve_hint: Label = %ServeHint
@onready var p1_label: Label = %P1Label
@onready var p2_label: Label = %P2Label
@onready var p1_momentum_bar: ProgressBar = %P1Momentum
@onready var p2_momentum_bar: ProgressBar = %P2Momentum
@onready var p1_ready: Label = %P1Ready
@onready var p2_ready: Label = %P2Ready
@onready var ai_status_label: Label = %AIStatus
@onready var help_label: Label = %ControlsHelp
@onready var flash_rect: ColorRect = %ScreenFlash
@onready var win_overlay: Control = %WinOverlay
@onready var win_backdrop: ColorRect = %Backdrop
@onready var win_frame: Control = %WinFrame
@onready var win_eyebrow: Label = %WinEyebrow
@onready var winner_name_label: Label = %WinnerName
@onready var win_subtitle: Label = %WinSubtitle
@onready var win_score: Label = %WinScore
@onready var win_stats: Label = %WinStats
@onready var rematch_btn: Button = %RematchBtn
@onready var next_stage_btn: Button = %NextStageBtn
@onready var win_menu_btn: Button = %WinMenuBtn

var game_mgr: GameManager
var tournament_mgr: TournamentManager

var _serve_tween: Tween
var _help_tween: Tween
var _win_tween: Tween
var _flash_tween: Tween

var _callout_queue: Array[Dictionary] = []
var _callout_active: Dictionary = {}
var _callout_tween: Tween

var _longest_rally := 0
var _last_rally := 0
var _charged_tweens: Array[Tween] = [null, null]
var _result_action := "rematch" # rematch | gauntlet | retry

# Momentum comet state per paddle: target fill, smoothed fill, lagging trail,
# head flare, and whether the bar is at READY.
var _comet_target: Array[float] = [0.0, 0.0]
var _comet_fill: Array[float] = [0.0, 0.0]
var _comet_trail: Array[float] = [0.0, 0.0]
var _comet_head: Array[float] = [0.0, 0.0]
var _comet_ready: Array[float] = [0.0, 0.0]
var _chip_tween: Tween
var _score_tweens: Array[Tween] = [null, null]
var _dot_tweens: Array[Tween] = [null, null, null]
var _scale_root: UIScaleRoot
## Boss stages paint the right side; remember so the palette pass does not undo it.
var _p2_color_override := false

func _ready() -> void:
	_scale_root = UIScaleRoot.install(self)
	_apply_ui_scale()
	var st := _settings_autoload()
	if st != null and not st.is_connected("changed", _on_setting_changed):
		st.connect("changed", _on_setting_changed)
	_apply_team_palette()

# --- Accessibility ------------------------------------------------------------

func _settings_autoload() -> Node:
	if _settings_node == null or not is_instance_valid(_settings_node):
		_settings_node = get_node_or_null("/root/Settings")
	return _settings_node

## Live team colour. Falls back to the hard-coded pair when Settings is absent
## (script check runs, isolated tests).
func team_color(player_id: int) -> Color:
	var st := _settings_autoload()
	if st != null and st.has_method("team_color"):
		return st.call("team_color", player_id)
	return P1_COLOR if player_id == 0 else P2_COLOR

## Maps a caller-supplied colour onto the active palette when it is one of the
## two default team hues; gold, white and boss colours pass through untouched.
func _remap(c: Color) -> Color:
	var st := _settings_autoload()
	if st != null and st.has_method("remap_team_color"):
		return st.call("remap_team_color", c)
	return c

func _on_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"colorblind_mode":
			_apply_team_palette()
		"ui_scale":
			_apply_ui_scale()

func _apply_ui_scale() -> void:
	if _scale_root == null:
		return
	_scale_root.set_ui_scale(float(_setting("ui_scale", 1.0)))

## Push the palette into the shared theme so the 'TeamP1' / 'TeamP2' type
## variations follow the colourblind mode for anyone who uses them.
func _apply_theme_tokens(c1: Color, c2: Color) -> void:
	# HUD is a CanvasLayer, so there is no local theme; the project theme is the
	# one every Control here inherits.
	var th := ThemeDB.get_project_theme()
	if th == null:
		return
	th.set_color(&'font_color', &'TeamP1', c1)
	th.set_color(&'font_color', &'TeamP2', c2)

## Repaint every team-coloured HUD element from the current palette.
func _apply_team_palette() -> void:
	var c1 := team_color(0)
	var c2 := team_color(1)
	_apply_theme_tokens(c1, c2)
	for pair in [[p1_score_label, c1], [p1_label, c1], [p1_ready, c1]]:
		var l: Label = pair[0]
		if l != null:
			l.add_theme_color_override("font_color", pair[1])
	if p1_ready != null:
		p1_ready.add_theme_color_override("font_outline_color", Color(c1.r, c1.g, c1.b, 0.35))
	if p2_score_label != null:
		p2_score_label.add_theme_color_override("font_color", c2)
	if not _p2_color_override:
		for l2: Label in [p2_label, p2_ready]:
			if l2 != null:
				l2.add_theme_color_override("font_color", c2)
		if p2_ready != null:
			p2_ready.add_theme_color_override("font_outline_color", Color(c2.r, c2.g, c2.b, 0.35))
	_tint_momentum(p1_momentum_bar, c1)
	_tint_momentum(p2_momentum_bar, c2 if not _p2_color_override else _p2_current_color())
	_tint_comet(p1_comet, c1)
	_tint_comet(p2_comet, c2 if not _p2_color_override else _p2_current_color())

func _p2_current_color() -> Color:
	if p2_label != null:
		return p2_label.get_theme_color("font_color")
	return team_color(1)

func _tint_momentum(bar: ProgressBar, col: Color) -> void:
	if bar == null:
		return
	var sb := bar.get_theme_stylebox("fill")
	if not (sb is StyleBoxFlat):
		return
	var flat: StyleBoxFlat = (sb as StyleBoxFlat).duplicate()
	flat.bg_color = Color(col.r, col.g, col.b, 0.85)
	flat.shadow_color = Color(col.r, col.g, col.b, 0.35)
	bar.add_theme_stylebox_override("fill", flat)

func _tint_comet(rect: ColorRect, col: Color) -> void:
	if rect == null or not (rect.material is ShaderMaterial):
		return
	(rect.material as ShaderMaterial).set_shader_parameter("team_color", col)

func setup(p_game_mgr: GameManager, p_p1: Paddle, p_p2: Paddle, p_tournament: TournamentManager = null) -> void:
	game_mgr = p_game_mgr
	tournament_mgr = p_tournament
	game_mgr.score_updated.connect(update_score)
	game_mgr.set_won.connect(update_sets)
	if game_mgr.has_signal("scores_reset"):
		game_mgr.connect("scores_reset", _on_scores_reset)
	game_mgr.rally_updated.connect(update_rally)
	game_mgr.milestone_reached.connect(show_milestone)
	game_mgr.match_won.connect(show_match_winner)
	game_mgr.match_reset.connect(_on_match_reset)
	game_mgr.ai_toggled.connect(update_ai_status)
	game_mgr.zen_mode_toggled.connect(update_zen_status)
	game_mgr.gauntlet_mode_toggled.connect(update_gauntlet_status)
	game_mgr.serving_started.connect(_on_serving)
	# Prefer the prioritised callout signal when GameManager provides it.
	if game_mgr.has_signal("callout_queued"):
		game_mgr.connect("callout_queued", show_callout)
	else:
		game_mgr.callout.connect(show_callout)
	game_mgr.match_started.connect(_on_match_started)
	game_mgr.menu_entered.connect(_on_menu_entered)
	if p_game_mgr.vfx_mgr != null:
		p_game_mgr.vfx_mgr.flash_requested.connect(_on_flash)
	# Optional signals that other systems may add; guard so the HUD stays
	# compatible with an older GameManager.
	if game_mgr.has_signal("serve_ready_beat"):
		game_mgr.connect("serve_ready_beat", _on_serve_ready_beat)
	if game_mgr.has_signal("serve_clock_warning"):
		game_mgr.connect("serve_clock_warning", _on_serve_clock_warning)
	if game_mgr.has_signal("state_changed"):
		game_mgr.connect("state_changed", _on_state_changed)
	_bind_ball_chips()

	if tournament_mgr != null:
		tournament_mgr.stage_started.connect(_on_tournament_stage_started)
		tournament_mgr.stage_completed.connect(_on_tournament_stage_completed)
		tournament_mgr.tournament_won.connect(_on_tournament_won)
		tournament_mgr.tournament_lost.connect(_on_tournament_lost)

	_bind_paddle(p_p1, 0, p1_momentum_bar, p1_ready)
	_bind_paddle(p_p2, 1, p2_momentum_bar, p2_ready)

	rematch_btn.pressed.connect(_on_rematch_pressed)
	next_stage_btn.pressed.connect(_on_next_stage_pressed)
	win_menu_btn.pressed.connect(_on_win_menu_pressed)
	for b in [rematch_btn, next_stage_btn, win_menu_btn]:
		b.focus_entered.connect(func(): _audio("trigger_ui_navigate"))
		b.mouse_entered.connect(func():
			if b.is_visible_in_tree():
				b.grab_focus()
		)

	win_overlay.visible = false
	callout_label.modulate.a = 0.0
	sub_callout_label.modulate.a = 0.0
	combo_label.text = ""
	state_chip.visible = false
	serve_dots.visible = false
	visible = (game_mgr != null and game_mgr.current_state != GameManager.State.MENU)
	_fade_help_later()

func _audio(method: String, args: Array = []) -> void:
	if game_mgr == null or game_mgr.audio_mgr == null:
		return
	if game_mgr.audio_mgr.has_method(method):
		game_mgr.audio_mgr.callv(method, args)

func _reduce_motion() -> bool:
	return bool(_setting("reduce_motion", false))

var _settings_node: Node

## Settings autoload looked up by path so --check-only still compiles.
func _setting(key: String, default: Variant = null) -> Variant:
	if _settings_node == null or not is_instance_valid(_settings_node):
		_settings_node = get_node_or_null("/root/Settings")
	if _settings_node == null:
		return default
	return _settings_node.call("get_value", key, default)

func _new_tween() -> Tween:
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	return tw

# --- Momentum bars ------------------------------------------------------------

func _bind_paddle(p: Paddle, idx: int, bar: ProgressBar, ready_lbl: Label) -> void:
	if p == null:
		return
	p.momentum_changed.connect(func(v: float):
		bar.value = v * 100.0
		if v > _comet_target[idx] + 0.002:
			_comet_head[idx] = minf(_comet_head[idx] + (v - _comet_target[idx]) * 6.0 + 0.4, 1.6)
		_comet_target[idx] = clampf(v, 0.0, 1.0)
		if p.armed_time <= 0.0 and p.stun_time <= 0.0:
			ready_lbl.text = "RESONANCE READY"
			_set_charged(idx, bar, ready_lbl, v >= 1.0)
	)
	p.super_ready.connect(func():
		ready_lbl.text = "RESONANCE READY"
		_set_charged(idx, bar, ready_lbl, true)
		_pulse_label(ready_lbl)
	)
	p.armed.connect(func():
		ready_lbl.text = "CANNON ARMED"
		ready_lbl.visible = true
		_pulse_label(ready_lbl)
	)
	p.stunned.connect(func(_d: float):
		ready_lbl.text = "STUNNED"
		ready_lbl.visible = true
		_set_charged(idx, bar, ready_lbl, false, true)
	)

func _process(delta: float) -> void:
	_tick_comets(delta)

## Comet head chases the real fill; the trail lags further behind so a big
## gain draws a streak, and a loss leaves the head sliding back with no tail.
func _tick_comets(delta: float) -> void:
	for i in 2:
		var mat_rect := p1_comet if i == 0 else p2_comet
		if mat_rect == null or not (mat_rect.material is ShaderMaterial):
			continue
		var target := _comet_target[i]
		_comet_fill[i] = lerpf(_comet_fill[i], target, clampf(delta * 9.0, 0.0, 1.0))
		if _comet_fill[i] > _comet_trail[i]:
			_comet_trail[i] = lerpf(_comet_trail[i], _comet_fill[i], clampf(delta * 2.2, 0.0, 1.0))
		else:
			_comet_trail[i] = _comet_fill[i]
		_comet_head[i] = move_toward(_comet_head[i], 0.0, delta * 2.5)
		var m: ShaderMaterial = mat_rect.material
		m.set_shader_parameter("fill", _comet_fill[i])
		m.set_shader_parameter("trail", _comet_trail[i])
		m.set_shader_parameter("head", _comet_head[i])
		m.set_shader_parameter("ready", _comet_ready[i])

func _set_charged(idx: int, bar: ProgressBar, ready_lbl: Label, charged: bool, keep_label := false) -> void:
	var tw: Tween = _charged_tweens[idx]
	_comet_ready[idx] = 1.0 if charged else 0.0
	if charged:
		ready_lbl.visible = true
		if tw != null and tw.is_valid() and tw.is_running():
			return
		bar.modulate = Color(1.25, 1.25, 1.25)
		if _reduce_motion():
			return
		tw = _new_tween().set_loops()
		tw.tween_property(bar, "modulate", Color(1.0, 1.0, 1.0, 0.65), 0.45).set_trans(Tween.TRANS_SINE)
		tw.tween_property(bar, "modulate", Color(1.25, 1.25, 1.25, 1.0), 0.45).set_trans(Tween.TRANS_SINE)
		_charged_tweens[idx] = tw
	else:
		if tw != null and tw.is_valid():
			tw.kill()
		_charged_tweens[idx] = null
		bar.modulate = Color.WHITE
		if not keep_label:
			ready_lbl.visible = false

func _pulse_label(node: Label) -> void:
	node.visible = true
	if _reduce_motion():
		return
	node.pivot_offset = Vector2(0.0 if node.horizontal_alignment != HORIZONTAL_ALIGNMENT_RIGHT else node.size.x, node.size.y * 0.5)
	node.scale = Vector2(1.3, 1.3)
	var tw := _new_tween()
	tw.tween_property(node, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# --- Scoreboard ---------------------------------------------------------------

func update_score(s1: int, s2: int) -> void:
	_roll_score(0, p1_score_label, p1_score_slot, "%02d" % s1)
	_roll_score(1, p2_score_label, p2_score_slot, "%02d" % s2)

## Odometer roll: the old digits slide up and fade while the new ones rise
## in from below. The slot clips so nothing spills over the glass.
func _roll_score(idx: int, label: Label, slot: Control, new_text: String) -> void:
	if label.text == new_text:
		return
	var old_text := label.text
	label.text = new_text
	if _reduce_motion() or slot == null:
		_punch_scale(label, 1.3)
		return
	var tw: Tween = _score_tweens[idx]
	if tw != null and tw.is_valid():
		tw.kill()
	var h := slot.size.y
	var ghost := label.duplicate() as Label
	ghost.name = "Ghost"
	ghost.text = old_text
	ghost.position = Vector2.ZERO
	ghost.modulate = label.modulate
	slot.add_child(ghost)
	label.position = Vector2(0.0, h)
	label.modulate.a = 0.0
	label.scale = Vector2.ONE
	tw = _new_tween().set_parallel(true)
	tw.tween_property(ghost, "position:y", -h, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(ghost, "modulate:a", 0.0, 0.18)
	tw.tween_property(label, "position:y", 0.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.04)
	tw.tween_property(label, "modulate:a", 1.0, 0.16).set_delay(0.04)
	tw.chain().tween_callback(ghost.queue_free)
	_score_tweens[idx] = tw

func update_sets(_winner: int, set1: int, set2: int) -> void:
	_set_sets_text(set1, set2)
	_punch_scale(sets_label, 1.2)
	# Gold flash that settles back to the theme colour.
	sets_label.remove_theme_color_override("font_color")
	var base := sets_label.get_theme_color("font_color")
	sets_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	var tw := _new_tween()
	tw.tween_interval(0.25)
	tw.tween_method(func(c: Color): sets_label.add_theme_color_override("font_color", c), Color(1.0, 0.95, 0.7), base, 0.5)
	tw.tween_callback(sets_label.remove_theme_color_override.bind("font_color"))

func _on_scores_reset() -> void:
	p1_score_label.text = "00"
	p2_score_label.text = "00"
	p1_score_label.position = Vector2.ZERO
	p2_score_label.position = Vector2.ZERO
	p1_score_label.modulate.a = 1.0
	p2_score_label.modulate.a = 1.0
	_set_sets_text(0, 0)
	_longest_rally = 0
	_hide_chip()

func _set_sets_text(set1: int, set2: int) -> void:
	if game_mgr != null and game_mgr.is_zen_mode:
		sets_label.text = "ZEN MODE"
	elif game_mgr != null and game_mgr.is_gauntlet_mode and tournament_mgr != null:
		var stg := tournament_mgr.current_stage + 1
		sets_label.text = "GAUNTLET %d/5 · SETS: %d - %d" % [stg, set1, set2]
	else:
		sets_label.text = "SETS: %d - %d" % [set1, set2]

func update_rally(hits: int) -> void:
	rally_label.text = "RALLY: %d" % hits
	if hits > _last_rally:
		_punch_scale(rally_label, 1.0 + minf(0.12 + hits * 0.015, 0.35))
	_last_rally = hits
	if hits > 0:
		serve_dots.visible = false
	_longest_rally = maxi(_longest_rally, hits)
	if hits >= 3:
		combo_label.text = "RALLY x%d" % hits
		combo_label.add_theme_color_override("font_color", Color(1.0, 0.7 + minf(hits * 0.03, 0.3), 0.2))
		_punch_scale(combo_label, 1.0 + minf(hits * 0.05, 0.6))
	else:
		combo_label.text = ""
	if hits == 0:
		var serving := game_mgr != null and game_mgr.current_state == GameManager.State.SERVING
		serve_hint.visible = serving
		if not serving and _serve_tween != null:
			_serve_tween.kill()
	else:
		serve_hint.visible = false
		if _serve_tween != null:
			_serve_tween.kill()

# --- Callouts (one queued system) --------------------------------------------

func show_milestone(title: String) -> void:
	# GameManager also emits the same text as a callout; do not double up.
	if String(_callout_active.get("text", "")) == title:
		callout_label.text = "— %s —" % title
		return
	show_callout("— %s —" % title, GOLD, PRIO_MILESTONE)

## Show a big centre callout. Higher priority interrupts the current one;
## lower priority waits in the queue and is dropped if it goes stale.
func show_callout(text: String, color: Color = GOLD, priority: int = PRIO_NORMAL, sub: String = "", hold: float = CALLOUT_HOLD) -> void:
	var item := {
		"text": text,
		"color": _remap(color),
		"priority": priority,
		"sub": sub,
		"hold": hold,
		"time": Time.get_ticks_msec(),
	}
	if _callout_active.is_empty():
		_play_callout(item)
		return
	if priority >= int(_callout_active.get("priority", 0)):
		_play_callout(item)
		return
	_callout_queue.append(item)
	while _callout_queue.size() > CALLOUT_QUEUE_MAX:
		_callout_queue.pop_front()

func _play_callout(item: Dictionary) -> void:
	if _callout_tween != null and _callout_tween.is_valid():
		_callout_tween.kill()
	_callout_active = item

	callout_label.text = item.text
	callout_label.add_theme_color_override("font_color", item.color)
	callout_label.pivot_offset = callout_label.size * 0.5
	callout_label.modulate.a = 1.0
	sub_callout_label.text = item.sub
	sub_callout_label.modulate.a = 1.0 if not String(item.sub).is_empty() else 0.0
	sub_callout_label.pivot_offset = sub_callout_label.size * 0.5

	var reduce := _reduce_motion()
	var prio := int(item.priority)
	callout_label.visible_ratio = 1.0
	callout_label.remove_theme_color_override("font_outline_color")
	callout_label.remove_theme_constant_override("outline_size")
	callout_label.scale = Vector2.ONE
	sub_callout_label.scale = Vector2.ONE

	_callout_tween = _new_tween()
	if reduce:
		callout_label.modulate.a = 0.0
		_callout_tween.tween_property(callout_label, "modulate:a", 1.0, CALLOUT_IN)
	elif prio <= PRIO_LOW:
		# LOW: small, quiet fade. No scale pop.
		callout_label.scale = Vector2(0.72, 0.72)
		sub_callout_label.scale = Vector2(0.85, 0.85)
		callout_label.modulate.a = 0.0
		_callout_tween.tween_property(callout_label, "modulate:a", 1.0, 0.14)
	elif prio == PRIO_NORMAL:
		# NORMAL: scale pop.
		callout_label.scale = Vector2(0.6, 0.6)
		sub_callout_label.scale = callout_label.scale
		_callout_tween.tween_property(callout_label, "scale", Vector2(1.08, 1.08), CALLOUT_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_callout_tween.parallel().tween_property(sub_callout_label, "scale", Vector2.ONE, CALLOUT_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_callout_tween.tween_property(callout_label, "scale", Vector2.ONE, 0.08)
	elif prio == PRIO_MILESTONE:
		# HIGH: slam down from large with a one-frame white outline.
		callout_label.scale = Vector2(1.7, 1.7)
		sub_callout_label.scale = Vector2(1.2, 1.2)
		callout_label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 1.0))
		callout_label.add_theme_constant_override("outline_size", 16)
		_callout_tween.tween_property(callout_label, "scale", Vector2(0.96, 0.96), 0.09).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		_callout_tween.parallel().tween_property(sub_callout_label, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		_callout_tween.parallel().tween_interval(0.017)
		_callout_tween.tween_callback(func():
			callout_label.remove_theme_color_override("font_outline_color")
			callout_label.remove_theme_constant_override("outline_size")
		)
		_callout_tween.tween_property(callout_label, "scale", Vector2.ONE, 0.07)
	else:
		# CRITICAL: letter-spaced slow reveal.
		var spaced := ""
		for ch in String(item.text):
			spaced += ch + " "
		callout_label.text = spaced.strip_edges()
		callout_label.visible_ratio = 0.0
		callout_label.scale = Vector2(1.04, 1.04)
		sub_callout_label.modulate.a = 0.0
		_callout_tween.tween_property(callout_label, "visible_ratio", 1.0, 0.55)
		_callout_tween.parallel().tween_property(callout_label, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_SINE)
		if not String(item.sub).is_empty():
			_callout_tween.tween_property(sub_callout_label, "modulate:a", 1.0, 0.25)
	_callout_tween.tween_interval(float(item.hold))
	_callout_tween.tween_property(callout_label, "modulate:a", 0.0, CALLOUT_OUT)
	_callout_tween.parallel().tween_property(sub_callout_label, "modulate:a", 0.0, CALLOUT_OUT)
	if not reduce and prio >= PRIO_NORMAL:
		_callout_tween.parallel().tween_property(callout_label, "scale", Vector2(0.9, 0.9), CALLOUT_OUT)
	_callout_tween.finished.connect(_on_callout_finished)

func _on_callout_finished() -> void:
	_callout_active = {}
	var now := Time.get_ticks_msec()
	while not _callout_queue.is_empty():
		var next: Dictionary = _callout_queue.pop_front()
		if now - int(next.time) > CALLOUT_STALE_MS:
			continue
		_play_callout(next)
		return

func _clear_callouts() -> void:
	_callout_queue.clear()
	_callout_active = {}
	if _callout_tween != null and _callout_tween.is_valid():
		_callout_tween.kill()
	callout_label.modulate.a = 0.0
	sub_callout_label.modulate.a = 0.0

# --- State chips (OVERDRIVE / CYMATIC LOCK) -----------------------------------

func _bind_ball_chips() -> void:
	var ball: Node = game_mgr.get("ball") if game_mgr != null else null
	if ball == null:
		ball = get_tree().get_first_node_in_group("cymatics_balls")
	if ball == null:
		return
	if ball.has_signal("overdrive_entered"):
		ball.connect("overdrive_entered", func(): _show_chip("OVERDRIVE", Color(1.0, 0.55, 0.15)))
	if ball.has_signal("cymatic_lock_entered"):
		ball.connect("cymatic_lock_entered", func(): _show_chip("CYMATIC LOCK", Color(1.0, 1.0, 1.0)))

func _show_chip(text: String, color: Color) -> void:
	state_chip_text.text = text
	state_chip_text.add_theme_color_override("font_color", color)
	var sb := state_chip.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		var flat: StyleBoxFlat = sb.duplicate()
		flat.border_color = Color(color.r, color.g, color.b, 0.9)
		state_chip.add_theme_stylebox_override("panel", flat)
	state_chip.visible = true
	state_chip.pivot_offset = Vector2(0.0, state_chip.size.y * 0.5)
	if _chip_tween != null and _chip_tween.is_valid():
		_chip_tween.kill()
	if _reduce_motion():
		state_chip.modulate = Color.WHITE
		state_chip.scale = Vector2.ONE
		return
	state_chip.scale = Vector2(0.6, 0.6)
	_chip_tween = _new_tween()
	_chip_tween.tween_property(state_chip, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_chip_tween.tween_property(state_chip, "modulate", Color(1.0, 1.0, 1.0, 0.7), 0.6).set_trans(Tween.TRANS_SINE)
	_chip_tween.tween_property(state_chip, "modulate", Color(1.3, 1.3, 1.3, 1.0), 0.6).set_trans(Tween.TRANS_SINE)
	_chip_tween.set_loops()

func _hide_chip() -> void:
	if _chip_tween != null and _chip_tween.is_valid():
		_chip_tween.kill()
	state_chip.visible = false
	state_chip.modulate = Color.WHITE

# --- Serve READY dots ---------------------------------------------------------

func _reset_serve_dots(show: bool) -> void:
	serve_dots.visible = show
	for i in serve_dots.get_child_count():
		var d := serve_dots.get_child(i) as Control
		if d == null:
			continue
		var tw: Tween = _dot_tweens[i] if i < _dot_tweens.size() else null
		if tw != null and tw.is_valid():
			tw.kill()
		d.modulate = Color(1.0, 1.0, 1.0, 0.22)
		d.scale = Vector2.ONE
		d.pivot_offset = d.size * 0.5

func _on_serve_ready_beat(beat: int) -> void:
	if game_mgr == null or game_mgr.current_state != GameManager.State.SERVING:
		return
	serve_dots.visible = true
	var idx := clampi(beat - 1, 0, serve_dots.get_child_count() - 1)
	var d := serve_dots.get_child(idx) as Control
	if d == null:
		return
	d.pivot_offset = d.size * 0.5
	if _reduce_motion():
		d.modulate = Color.WHITE
		return
	var tw: Tween = _dot_tweens[idx]
	if tw != null and tw.is_valid():
		tw.kill()
	d.modulate = Color(1.6, 1.5, 1.2, 1.0)
	d.scale = Vector2(1.7, 1.7)
	tw = _new_tween().set_parallel(true)
	tw.tween_property(d, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(d, "modulate", Color.WHITE, 0.3)
	_dot_tweens[idx] = tw

func _on_serve_clock_warning(seconds_left: float) -> void:
	if not serve_hint.visible:
		return
	# Warm the hint and quicken its pulse as the auto-serve clock runs down.
	var urgency := clampf(1.0 - seconds_left / 3.0, 0.0, 1.0)
	serve_hint.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7).lerp(Color(1.0, 0.55, 0.35), urgency))
	_punch_scale(serve_hint, 1.0 + 0.12 * urgency)
	if _serve_tween != null and _serve_tween.is_valid():
		_serve_tween.kill()
	serve_hint.modulate.a = 1.0
	if _reduce_motion():
		return
	var period := lerpf(0.4, 0.15, urgency)
	_serve_tween = create_tween().set_loops()
	_serve_tween.tween_property(serve_hint, "modulate:a", 0.3, period)
	_serve_tween.tween_property(serve_hint, "modulate:a", 1.0, period)

func _on_state_changed(new_state: int) -> void:
	if new_state != GameManager.State.SERVING:
		serve_dots.visible = false

# --- Results overlay ----------------------------------------------------------

func show_match_winner(winner_id: int) -> void:
	var is_p1 := winner_id == 0
	var winner_name := "PADD" if is_p1 else (p2_label.text if p2_label != null else "RIVAL")
	var col := team_color(0) if is_p1 else p2_label.get_theme_color("font_color")
	var sets1 := game_mgr.sets_p1 if game_mgr != null else 0
	var sets2 := game_mgr.sets_p2 if game_mgr != null else 0
	_result_action = "rematch"
	_show_results("MATCH OVER", winner_name, col, "WINS THE MATCH", "SETS  %d - %d" % [sets1, sets2], "REMATCH", false)
	serve_hint.visible = false
	if game_mgr:
		if is_p1 and game_mgr.paddle_left:
			game_mgr.paddle_left.emote(2, 4.0, "THAT'S A PADDLIN'!")
		elif game_mgr.paddle_right:
			game_mgr.paddle_right.emote(2, 4.0, "THAT'S A PADDLIN'!")

func _show_results(eyebrow: String, winner: String, col: Color, subtitle: String, score: String, rematch_text: String, show_next: bool) -> void:
	_clear_callouts()
	win_eyebrow.text = eyebrow
	winner_name_label.text = winner
	winner_name_label.add_theme_color_override("font_color", col)
	win_subtitle.text = subtitle
	win_score.text = score
	win_stats.text = "LONGEST RALLY: %d" % _longest_rally if _longest_rally > 0 else ""
	win_stats.visible = _longest_rally > 0
	rematch_btn.text = rematch_text
	rematch_btn.visible = not rematch_text.is_empty()
	next_stage_btn.visible = show_next

	var first_visible := true
	if not win_overlay.visible:
		win_overlay.visible = true
	else:
		first_visible = false

	# Only restart the entry tween on first show; a follow-up call in the same
	# frame (tournament refining the card) must not kill the fade-in.
	if first_visible:
		if _win_tween != null and _win_tween.is_valid():
			_win_tween.kill()
		win_backdrop.modulate.a = 0.0
		win_frame.modulate.a = 0.0
		win_frame.pivot_offset = win_frame.size * 0.5
		win_frame.scale = Vector2.ONE if _reduce_motion() else Vector2(0.9, 0.9)
		_win_tween = _new_tween().set_parallel(true)
		_win_tween.tween_property(win_backdrop, "modulate:a", 1.0, 0.35)
		_win_tween.tween_property(win_frame, "modulate:a", 1.0, 0.3).set_delay(0.15)
		_win_tween.tween_property(win_frame, "scale", Vector2.ONE, 0.4).set_delay(0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_audio("trigger_menu_open")

	var focus_target: Button = rematch_btn if rematch_btn.visible else (next_stage_btn if next_stage_btn.visible else win_menu_btn)
	focus_target.call_deferred("grab_focus")

func _hide_results() -> void:
	if _win_tween != null and _win_tween.is_valid():
		_win_tween.kill()
	win_overlay.visible = false
	if rematch_btn.has_focus() or next_stage_btn.has_focus() or win_menu_btn.has_focus():
		get_viewport().gui_release_focus()

func _on_rematch_pressed() -> void:
	_audio("trigger_ui_confirm")
	if game_mgr == null:
		return
	match _result_action:
		"gauntlet":
			game_mgr.start_gauntlet_match()
		_:
			game_mgr.restart_match()

func _on_next_stage_pressed() -> void:
	# The tournament advances on its own timer; this just clears the card.
	_audio("trigger_ui_confirm")
	_hide_results()

func _on_win_menu_pressed() -> void:
	_audio("trigger_ui_back")
	if game_mgr != null:
		game_mgr.return_to_menu()

# --- Status lines -------------------------------------------------------------

func update_ai_status(enabled: bool) -> void:
	if LabMode.active:
		ai_status_label.text = "[Y] LAB AI vs AI"
		return
	ai_status_label.text = "[T] AI: %s" % ("ON" if enabled else "OFF · 2P")

func show_lab_banner(watch: bool) -> void:
	ai_status_label.text = "[Y] LAB AI vs AI" if watch else "LAB AI vs AI"
	if help_label != null:
		help_label.text = "LAB  ·  Padd (AI) vs Lin (AI)  ·  telemetry writing to lab/runs/"

func update_zen_status(enabled: bool) -> void:
	if enabled:
		sets_label.text = "ZEN MODE"
	elif game_mgr != null:
		_set_sets_text(game_mgr.sets_p1, game_mgr.sets_p2)

func update_gauntlet_status(enabled: bool) -> void:
	if enabled:
		sets_label.text = "GAUNTLET 1/5"
	else:
		if game_mgr != null:
			_set_sets_text(game_mgr.sets_p1, game_mgr.sets_p2)
		_p2_color_override = false
		p2_label.text = "LIN"
		_apply_team_palette()

# --- Tournament ---------------------------------------------------------------

func _on_tournament_stage_started(stage_idx: int, info: Dictionary) -> void:
	var col: Color = info.get("color", team_color(1))
	_p2_color_override = true
	p2_label.text = info.get("boss_name", "BOSS")
	p2_label.add_theme_color_override("font_color", col)
	p2_ready.add_theme_color_override("font_color", col)
	sets_label.text = "GAUNTLET %d/5" % (stage_idx + 1)
	show_callout("%s: %s" % [info.get("title", "STAGE"), info.get("boss_name", "BOSS")], col, PRIO_STAGE,
		"%s  —  %s" % [info.get("subtitle", ""), info.get("description", "")], 2.6)

func _on_tournament_stage_completed(stage_idx: int, info: Dictionary) -> void:
	var total := TournamentManager.STAGES.size()
	if stage_idx + 1 < total:
		_result_action = "rematch"
		_show_results("STAGE %d / %d CLEARED" % [stage_idx + 1, total], "PADD", team_color(0),
			"%s DEFEATED" % String(info.get("boss_name", "BOSS")).to_upper(),
			"NEXT: %s" % String(TournamentManager.STAGES[stage_idx + 1].get("boss_name", "???")).to_upper(),
			"", true)
		next_stage_btn.text = "CONTINUE"

func _on_tournament_won() -> void:
	_result_action = "gauntlet"
	_show_results("GAUNTLET COMPLETE", "PADD", GOLD, "TOURNAMENT CHAMPION", "ALL 5 RIVALS DEFEATED", "RUN AGAIN", false)

func _on_tournament_lost() -> void:
	_result_action = "retry"
	var boss := p2_label.text if p2_label != null else "RIVAL"
	var col := p2_label.get_theme_color("font_color") if p2_label != null else team_color(1)
	var stg := (tournament_mgr.current_stage + 1) if tournament_mgr != null else 1
	_show_results("DEFEATED IN THE GAUNTLET", boss, col, "HOLDS STAGE %d" % stg,
		"SETS  %d - %d" % [game_mgr.sets_p1 if game_mgr else 0, game_mgr.sets_p2 if game_mgr else 0], "RETRY STAGE", false)

# --- Serve / reset / flash ----------------------------------------------------

func _on_serving(server_id: int) -> void:
	serve_hint.visible = true
	serve_hint.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	_hide_chip()
	_reset_serve_dots(game_mgr != null and game_mgr.has_signal("serve_ready_beat"))
	if server_id == 0:
		serve_hint.text = "PADD  ·  SPACE / CLICK TO SERVE"
	else:
		serve_hint.text = "%s IS SERVING..." % p2_label.text
	if _serve_tween != null and _serve_tween.is_valid():
		_serve_tween.kill()
	serve_hint.modulate.a = 1.0
	if _reduce_motion():
		return
	_serve_tween = create_tween().set_loops()
	_serve_tween.tween_property(serve_hint, "modulate:a", 0.3, 0.4)
	_serve_tween.tween_property(serve_hint, "modulate:a", 1.0, 0.4)

func _on_match_reset() -> void:
	_hide_results()
	combo_label.text = ""
	_longest_rally = 0
	_last_rally = 0
	_hide_chip()
	_reset_serve_dots(false)
	for i in 2:
		_comet_target[i] = 0.0
		_comet_fill[i] = 0.0
		_comet_trail[i] = 0.0
		_comet_head[i] = 0.0
	_set_charged(0, p1_momentum_bar, p1_ready, false)
	_set_charged(1, p2_momentum_bar, p2_ready, false)
	_clear_callouts()
	if _serve_tween != null:
		_serve_tween.kill()

func _on_flash(color: Color, alpha: float, duration: float) -> void:
	# VFXManager owns the reduce-motion softening and the per-second flash cap;
	# this stays as a backstop for anything that emits `flash_requested` directly.
	if not bool(_setting("screen_flash", true)):
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	flash_rect.color = Color(color.r, color.g, color.b, alpha)
	_flash_tween = _new_tween()
	_flash_tween.tween_property(flash_rect, "color:a", 0.0, maxf(duration, 0.05))

func _punch_scale(node: Control, amount: float) -> void:
	if _reduce_motion():
		return
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(amount, amount)
	var tween := _new_tween()
	tween.tween_property(node, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# --- Help line ----------------------------------------------------------------

func _fade_help_later() -> void:
	if help_label == null:
		return
	if _help_tween != null and _help_tween.is_valid():
		_help_tween.kill()
	help_label.modulate.a = 1.0
	_help_tween = _new_tween()
	_help_tween.tween_interval(6.0)
	_help_tween.tween_property(help_label, "modulate:a", 0.0, 0.8)

func _on_match_started() -> void:
	visible = true
	_hide_results()
	_fade_help_later()

func _on_menu_entered() -> void:
	visible = false
	_hide_results()
	_clear_callouts()
	_hide_chip()
	_reset_serve_dots(false)
	serve_hint.visible = false
	if _serve_tween != null:
		_serve_tween.kill()
