class_name HUD
extends CanvasLayer

@onready var p1_score_label: Label = $TopPanel/ScoreContainer/P1Score
@onready var p2_score_label: Label = $TopPanel/ScoreContainer/P2Score
@onready var sets_label: Label = $TopPanel/ScoreContainer/SetsLabel
@onready var rally_label: Label = $TopPanel/RallyContainer/RallyCount
@onready var milestone_banner: Label = $CenterContainer/MilestoneBanner
@onready var p1_momentum_bar: ProgressBar = $BottomPanel/P1Container/P1Momentum
@onready var p2_momentum_bar: ProgressBar = $BottomPanel/P2Container/P2Momentum
@onready var ai_status_label: Label = $BottomPanel/StatusContainer/AIStatus
@onready var win_overlay: Control = $WinOverlay
@onready var win_label: Label = $WinOverlay/WinPanel/WinLabel

var game_mgr: GameManager
var _flash: ColorRect
var _callout: Label
var _serve_hint: Label
var _combo: Label
var _p1_ready: Label
var _p2_ready: Label
var _help: Label
var _callout_tween: Tween
var _serve_tween: Tween
var _help_fading := false

func setup(p_game_mgr: GameManager, p_p1: Paddle, p_p2: Paddle) -> void:
	game_mgr = p_game_mgr
	game_mgr.score_updated.connect(update_score)
	game_mgr.set_won.connect(update_sets)
	game_mgr.rally_updated.connect(update_rally)
	game_mgr.milestone_reached.connect(show_milestone)
	game_mgr.match_won.connect(show_match_winner)
	game_mgr.match_reset.connect(_on_match_reset)
	game_mgr.ai_toggled.connect(update_ai_status)
	game_mgr.zen_mode_toggled.connect(update_zen_status)
	game_mgr.serving_started.connect(_on_serving)
	game_mgr.callout.connect(show_callout)
	if p_game_mgr.vfx_mgr != null:
		p_game_mgr.vfx_mgr.flash_requested.connect(_on_flash)

	if p_p1 != null:
		p_p1.momentum_changed.connect(func(v: float):
			p1_momentum_bar.value = v * 100.0
			if p_p1.armed_time <= 0.0 and p_p1.stun_time <= 0.0:
				_p1_ready.text = "SUPER READY"
				_p1_ready.visible = v >= 1.0
		)
		p_p1.super_ready.connect(func(): _pulse_ready(_p1_ready))
		p_p1.armed.connect(func():
			_p1_ready.text = "CANNON ARMED"
			_p1_ready.visible = true
			_pulse_ready(_p1_ready)
		)
		p_p1.stunned.connect(func(_d: float):
			_p1_ready.text = "STUNNED"
			_p1_ready.visible = true
		)
	if p_p2 != null:
		p_p2.momentum_changed.connect(func(v: float):
			p2_momentum_bar.value = v * 100.0
			if p_p2.armed_time <= 0.0 and p_p2.stun_time <= 0.0:
				_p2_ready.text = "SUPER READY"
				_p2_ready.visible = v >= 1.0
		)
		p_p2.super_ready.connect(func():
			_p2_ready.text = "SUPER READY"
			_pulse_ready(_p2_ready)
		)
		p_p2.armed.connect(func():
			_p2_ready.text = "CANNON ARMED"
			_p2_ready.visible = true
			_pulse_ready(_p2_ready)
		)
		p_p2.stunned.connect(func(_d: float):
			_p2_ready.text = "STUNNED"
			_p2_ready.visible = true
		)

	win_overlay.visible = false
	milestone_banner.modulate.a = 0.0
	_build_juice_nodes()
	_fade_help_later()

func _build_juice_nodes() -> void:
	_flash = ColorRect.new()
	_flash.name = "ScreenFlash"
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.z_index = 80
	add_child(_flash)

	_callout = Label.new()
	_callout.name = "Callout"
	_callout.set_anchors_preset(Control.PRESET_CENTER)
	_callout.offset_left = -420.0
	_callout.offset_right = 420.0
	_callout.offset_top = -40.0
	_callout.offset_bottom = 80.0
	_callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_callout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_callout.add_theme_font_size_override("font_size", 64)
	_callout.add_theme_color_override("font_color", Color(1, 0.92, 0.4))
	_callout.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_callout.add_theme_constant_override("shadow_offset_x", 3)
	_callout.add_theme_constant_override("shadow_offset_y", 3)
	_callout.modulate.a = 0.0
	_callout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_callout.pivot_offset = Vector2(420, 60)
	add_child(_callout)

	_combo = Label.new()
	_combo.name = "ComboLabel"
	_combo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_combo.offset_left = -200.0
	_combo.offset_right = 200.0
	_combo.offset_top = 120.0
	_combo.offset_bottom = 170.0
	_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo.add_theme_font_size_override("font_size", 28)
	_combo.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	_combo.text = ""
	_combo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_combo)

	_serve_hint = Label.new()
	_serve_hint.name = "ServeHint"
	_serve_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_serve_hint.offset_left = -320.0
	_serve_hint.offset_right = 320.0
	_serve_hint.offset_top = -180.0
	_serve_hint.offset_bottom = -130.0
	_serve_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_serve_hint.add_theme_font_size_override("font_size", 26)
	_serve_hint.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	_serve_hint.text = "CLICK / SPACE TO SERVE"
	_serve_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_serve_hint.visible = false
	add_child(_serve_hint)

	_p1_ready = Label.new()
	_p1_ready.text = "SUPER READY"
	_p1_ready.add_theme_font_size_override("font_size", 16)
	_p1_ready.add_theme_color_override("font_color", Color(0.0, 0.95, 1.0))
	_p1_ready.position = Vector2(50, 980)
	_p1_ready.visible = false
	_p1_ready.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_p1_ready)

	_p2_ready = Label.new()
	_p2_ready.text = "SUPER READY"
	_p2_ready.add_theme_font_size_override("font_size", 16)
	_p2_ready.add_theme_color_override("font_color", Color(1.0, 0.2, 0.7))
	_p2_ready.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_p2_ready.position = Vector2(1570, 980)
	_p2_ready.size = Vector2(300, 24)
	_p2_ready.visible = false
	_p2_ready.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_p2_ready)

	_help = get_node_or_null("BottomPanel/StatusContainer/ControlsHelp") as Label

	var title := Label.new()
	title.name = "GameTitle"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -280.0
	title.offset_right = 280.0
	title.offset_top = 6.0
	title.offset_bottom = 28.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45, 0.85))
	title.text = "THAT'S A PADDLIN'"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

func _fade_help_later() -> void:
	if _help == null:
		return
	var t := get_tree().create_timer(7.0)
	t.timeout.connect(func():
		if _help == null:
			return
		var tw := create_tween()
		tw.tween_property(_help, "modulate:a", 0.0, 0.8)
	)

func update_score(s1: int, s2: int) -> void:
	p1_score_label.text = "%02d" % s1
	p2_score_label.text = "%02d" % s2
	_punch_scale(p1_score_label, 1.45)
	_punch_scale(p2_score_label, 1.45)

func update_sets(_winner: int, set1: int, set2: int) -> void:
	sets_label.text = "SETS: %d - %d" % [set1, set2]
	_punch_scale(sets_label, 1.2)

func update_rally(hits: int) -> void:
	rally_label.text = "RALLY: %d" % hits
	if hits >= 3:
		_combo.text = "x%d" % hits
		_combo.modulate = Color(1, 0.7 + minf(hits * 0.03, 0.3), 0.2)
		_punch_scale(_combo, 1.0 + minf(hits * 0.06, 0.8))
	else:
		_combo.text = ""
	if hits == 0:
		var serving := game_mgr != null and game_mgr.current_state == GameManager.State.SERVING
		_serve_hint.visible = serving
		if not serving and _serve_tween != null:
			_serve_tween.kill()
	else:
		_serve_hint.visible = false
		if _serve_tween != null:
			_serve_tween.kill()

func show_milestone(title: String) -> void:
	milestone_banner.text = "— %s —" % title
	milestone_banner.scale = Vector2(0.7, 0.7)
	var tween := create_tween()
	tween.set_parallel(false)
	tween.tween_property(milestone_banner, "modulate:a", 1.0, 0.08)
	tween.tween_property(milestone_banner, "scale", Vector2(1.18, 1.18), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(milestone_banner, "scale", Vector2(1.0, 1.0), 0.12)
	tween.tween_interval(0.9)
	tween.tween_property(milestone_banner, "modulate:a", 0.0, 0.3)

func show_callout(text: String, color: Color) -> void:
	_callout.text = text
	_callout.add_theme_color_override("font_color", color)
	_callout.scale = Vector2(0.6, 0.6)
	_callout.modulate.a = 1.0
	if _callout_tween != null and _callout_tween.is_running():
		_callout_tween.kill()
	_callout_tween = create_tween()
	_callout_tween.tween_property(_callout, "scale", Vector2(1.12, 1.12), 0.1).set_trans(Tween.TRANS_BACK)
	_callout_tween.tween_property(_callout, "scale", Vector2(1.0, 1.0), 0.1)
	_callout_tween.tween_interval(0.45)
	_callout_tween.tween_property(_callout, "modulate:a", 0.0, 0.22)

func show_match_winner(winner_id: int) -> void:
	win_overlay.visible = true
	var winner_name := "PADD" if winner_id == 0 else "LIN"
	win_label.text = "%s WINS\n\nTHAT'S A PADDLIN'\n\nPress [R]  ·  one more?" % winner_name
	_serve_hint.visible = false
	if game_mgr:
		if winner_id == 0 and game_mgr.paddle_left:
			game_mgr.paddle_left.emote(2, 4.0, "THAT'S A PADDLIN'!")
		elif game_mgr.paddle_right:
			game_mgr.paddle_right.emote(2, 4.0, "THAT'S A PADDLIN'!")

func update_ai_status(enabled: bool) -> void:
	ai_status_label.text = "[T] AI: %s" % ("ON" if enabled else "OFF · 2P")

func update_zen_status(enabled: bool) -> void:
	if enabled:
		sets_label.text = "ZEN MODE"
	else:
		sets_label.text = "SETS: %d - %d" % [game_mgr.sets_p1, game_mgr.sets_p2]

func _on_serving(server_id: int) -> void:
	_serve_hint.visible = true
	if server_id == 0:
		_serve_hint.text = "PADD  ·  SPACE / CLICK TO SERVE"
	else:
		_serve_hint.text = "LIN IS SERVING..."
	if _serve_tween != null and _serve_tween.is_running():
		_serve_tween.kill()
	_serve_hint.modulate.a = 1.0
	_serve_tween = create_tween().set_loops()
	_serve_tween.tween_property(_serve_hint, "modulate:a", 0.3, 0.4)
	_serve_tween.tween_property(_serve_hint, "modulate:a", 1.0, 0.4)

func _on_match_reset() -> void:
	win_overlay.visible = false
	_combo.text = ""
	_p1_ready.visible = false
	_p2_ready.visible = false
	if _serve_tween != null:
		_serve_tween.kill()

func _on_flash(color: Color, alpha: float, duration: float) -> void:
	_flash.color = Color(color.r, color.g, color.b, alpha)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, maxf(duration, 0.05))

func _pulse_ready(node: Label) -> void:
	node.visible = true
	node.scale = Vector2(1.3, 1.3)
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector2.ONE, 0.2)

func _punch_scale(node: Control, amount: float) -> void:
	node.scale = Vector2(amount, amount)
	var tween := create_tween()
	tween.tween_property(node, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
