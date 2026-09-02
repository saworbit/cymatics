class_name MenuManager
extends CanvasLayer

## MenuManager: Orchestrates the living fluid title screen, sandbox laboratory,
## boss gauntlet dossier, game mode selection, how-to-play codex, settings,
## quit confirmation, and in-game pause overlay.
##
## Navigation: every button is focusable; arrows / d-pad move focus, ui_accept
## activates, ui_cancel closes the current modal (or asks to quit from the
## title). Hovering with the mouse also moves focus so there is one highlight.

enum MenuState { MAIN, GAUNTLET_DOSSIER, SANDBOX_LAB, CODEX, SETTINGS, IN_GAME_PAUSE, HIDDEN }

var current_state: MenuState = MenuState.MAIN
var _settings_return_state: MenuState = MenuState.MAIN
var _quit_confirm_open := false

# Core References
var fluid_sim: FluidSimulator
var game_mgr: GameManager
var audio_mgr: AudioManager
var vfx_mgr: VFXManager
var display_mat: ShaderMaterial

# Palette and sandbox configuration
var current_palette: int = 0
const PALETTE_NAMES := ["Cyberpunk", "Solar Flare", "Toxic Venom", "Deep Cosmos", "Prismatic"]
const PALETTE_COLORS := [
	Color(0.0, 0.9, 1.0),      # Cyan
	Color(1.0, 0.45, 0.05),    # Orange
	Color(0.4, 1.0, 0.2),      # Lime
	Color(0.68, 0.15, 0.95),   # Violet
	Color(1.0, 0.9, 0.3)       # Gold
]

# Sandbox Tool modes
enum ToolMode { STREAM, VORTEX, SINKHOLE, SHOCKWAVE, ORB_SPAWNER }
var current_tool: ToolMode = ToolMode.STREAM
var brush_radius: float = 140.0
var _last_mouse_pos := Vector2.ZERO

# Toy Sandbox Orbs on Title Screen
var _toy_orbs: Array[Dictionary] = []
const MAX_TOY_ORBS := 8

# Interactive Mascot tracking & quotes
var padd_face: CharacterFace
var lin_face: CharacterFace
var _mascot_bark_cd := 0.0

# Focus bookkeeping
var _suppress_focus_sfx := false
var _focus_tween: Tween

# --- UI node references (unique names in menu.tscn) --------------------------
@onready var top_toolbar: Control = %TopToolbar
@onready var palette_btn: Button = %PaletteBtn
@onready var spawn_orb_btn: Button = %SpawnOrbBtn
@onready var clear_fluid_btn: Button = %ClearFluidBtn
@onready var sandbox_btn: Button = %SandboxBtn
@onready var sound_btn: Button = %SoundBtn
@onready var fullscreen_btn: Button = %FullscreenBtn

@onready var main_menu_panel: Control = %MainMenuPanel
@onready var title_text: Label = %TitleText
@onready var mode_cards_container: HBoxContainer = %ModeCardsContainer
@onready var card_arcade: ModeCard = %CardArcade
@onready var card_gauntlet: ModeCard = %CardGauntlet
@onready var card_pvp: ModeCard = %CardPVP
@onready var card_zen: ModeCard = %CardZen
@onready var codex_btn: Button = %CodexBtn
@onready var settings_btn: Button = %SettingsBtn
@onready var quit_btn: Button = %QuitBtn

@onready var gauntlet_dossier_modal: Control = %GauntletDossierModal
@onready var dossier_card: PanelContainer = %DossierCard
@onready var stage_tabs: HBoxContainer = %StageTabs
@onready var stage_number_lbl: Label = %StageNumber
@onready var boss_name_lbl: Label = %BossName
@onready var boss_quote_lbl: Label = %BossQuote
@onready var boss_desc_lbl: Label = %BossDescription
@onready var portrait_glow: ColorRect = %PortraitGlow
@onready var hazard_badge_lbl: Label = %HazardBadge
@onready var launch_gauntlet_btn: Button = %LaunchGauntletBtn
@onready var close_dossier_btn: Button = %CloseDossierBtn

@onready var sandbox_hud: Control = %SandboxHUD
@onready var tool_stream_btn: Button = %ToolStream
@onready var tool_vortex_btn: Button = %ToolVortex
@onready var tool_sinkhole_btn: Button = %ToolSinkhole
@onready var tool_shockwave_btn: Button = %ToolShockwave
@onready var tool_orb_btn: Button = %ToolOrb
@onready var vorticity_slider: HSlider = %VorticitySlider
@onready var dissipation_slider: HSlider = %DissipationSlider
@onready var spawn_bricks_btn: Button = %SpawnBricksBtn
@onready var launch_from_sandbox_btn: Button = %LaunchFromSandboxBtn
@onready var back_to_menu_btn: Button = %BackToMenuBtn

@onready var codex_modal: Control = %CodexModal
@onready var close_codex_btn: Button = %CloseCodexBtn

@onready var settings_modal: Control = %SettingsModal
@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SFXSlider
@onready var bloom_slider: HSlider = %BloomSlider
@onready var ca_slider: HSlider = %CASlider
@onready var fullscreen_toggle: CheckButton = %FullscreenToggle
@onready var vsync_toggle: CheckButton = %VSyncToggle
@onready var reduce_motion_toggle: CheckButton = %ReduceMotionToggle
@onready var screen_flash_toggle: CheckButton = %ScreenFlashToggle
@onready var close_settings_btn: Button = %CloseSettingsBtn
@onready var reset_settings_btn: Button = %ResetSettingsBtn

@onready var pause_overlay: Control = %PauseOverlay
@onready var resume_btn: Button = %ResumeBtn
@onready var restart_btn: Button = %RestartBtn
@onready var pause_settings_btn: Button = %PauseSettingsBtn
@onready var main_menu_btn: Button = %MainMenuBtn

@onready var quit_confirm: Control = %QuitConfirm
@onready var quit_yes_btn: Button = %QuitYesBtn
@onready var quit_no_btn: Button = %QuitNoBtn

@onready var quick_banner: Label = %QuickBanner

var _stage_tab_buttons: Array[Button] = []

# Gauntlet dossier selected stage
var dossier_selected_stage: int = 0

func setup(p_fluid: FluidSimulator, p_game: GameManager, p_audio: AudioManager, p_vfx: VFXManager, p_mat: ShaderMaterial = null) -> void:
	fluid_sim = p_fluid
	game_mgr = p_game
	audio_mgr = p_audio
	vfx_mgr = p_vfx
	display_mat = p_mat

	if game_mgr != null:
		game_mgr.game_paused.connect(_on_game_paused)
		game_mgr.menu_entered.connect(_on_menu_entered)
		game_mgr.match_started.connect(_on_match_started)

	_setup_mascots()
	_bind_ui_events()
	_bind_card_hover()
	_setup_settings_controls()
	_wire_focus_neighbors()
	_apply_palette(0)
	_refresh_toolbar_labels()
	_switch_state(MenuState.MAIN)

	# Spawn initial toy orbs for menu background ambiance
	for i in range(3):
		_spawn_toy_orb(Vector2(randf_range(300, 1600), randf_range(200, 800)), Vector2(randf_range(-180, 180), randf_range(-180, 180)))

# --- Helpers for optional collaborator APIs -----------------------------------

func _audio(method: String, args: Array = []) -> void:
	if audio_mgr != null and audio_mgr.has_method(method):
		audio_mgr.callv(method, args)

func _sfx_confirm() -> void:
	if audio_mgr == null:
		return
	if audio_mgr.has_method("trigger_ui_confirm"):
		audio_mgr.trigger_ui_confirm()
	elif audio_mgr.has_method("trigger_ui_click"):
		audio_mgr.trigger_ui_click()

func _sfx_navigate() -> void:
	if audio_mgr == null:
		return
	if audio_mgr.has_method("trigger_ui_navigate"):
		audio_mgr.trigger_ui_navigate()
	elif audio_mgr.has_method("trigger_ui_hover"):
		audio_mgr.trigger_ui_hover()

func _sfx_back() -> void:
	_audio("trigger_ui_back")

func _reduce_motion() -> bool:
	return bool(_setting("reduce_motion", false))

# --- Settings autoload access (looked up by path so --check-only and a
# missing autoload both degrade gracefully) -----------------------------------

var _settings_node: Node

func _get_settings() -> Node:
	if _settings_node == null or not is_instance_valid(_settings_node):
		_settings_node = get_node_or_null("/root/Settings")
	return _settings_node

func _setting(key: String, default: Variant = null) -> Variant:
	var s := _get_settings()
	if s == null:
		return default
	return s.call("get_value", key, default)

func _set_setting(key: String, value: Variant) -> void:
	var s := _get_settings()
	if s != null:
		s.call("set_value", key, value)

func _toggle_setting(key: String) -> bool:
	var s := _get_settings()
	if s == null:
		return false
	return bool(s.call("toggle", key))

func _settings_call(method: String) -> void:
	var s := _get_settings()
	if s != null and s.has_method(method):
		s.call(method)

func _bus_for_key(key: String) -> String:
	var s := _get_settings()
	if s == null:
		return ""
	var map: Variant = s.get("BUS_FOR_KEY")
	if map is Dictionary:
		return String(map.get(key, ""))
	return ""

func _has_bus(bus: String) -> bool:
	return not bus.is_empty() and AudioServer.get_bus_index(bus) >= 0

# --- Setup --------------------------------------------------------------------

func _setup_mascots() -> void:
	var padd_container := main_menu_panel.get_node_or_null("MascotPadd") as Control
	if padd_container != null:
		padd_face = CharacterFace.new()
		padd_face.setup(Vector2(90, 90), false, 0.0)
		padd_container.add_child(padd_face)
		padd_face.position = Vector2(45, 45)

	var lin_container := main_menu_panel.get_node_or_null("MascotLin") as Control
	if lin_container != null:
		lin_face = CharacterFace.new()
		lin_face.setup(Vector2(90, 90), true, 0.15)
		lin_container.add_child(lin_face)
		lin_face.position = Vector2(45, 45)

func _bind_ui_events() -> void:
	# Main mode cards
	_hook_button(card_arcade.button, _on_arcade_clicked)
	_hook_button(card_gauntlet.button, _on_gauntlet_clicked)
	_hook_button(card_pvp.button, _on_pvp_clicked)
	_hook_button(card_zen.button, _on_zen_clicked)

	# Bottom quick buttons
	_hook_button(codex_btn, func(): _switch_state(MenuState.CODEX))
	_hook_button(settings_btn, func(): _open_settings(MenuState.MAIN))
	_hook_button(quit_btn, _on_quit_clicked)

	# Top toolbar
	_hook_button(palette_btn, _on_cycle_palette_clicked)
	_hook_button(spawn_orb_btn, func():
		_spawn_toy_orb(get_viewport().get_mouse_position(), Vector2(randf_range(-300, 300), randf_range(-300, 300)))
		_show_banner("SPAWNED TOY ORB")
	)
	_hook_button(clear_fluid_btn, _on_clear_fluid_clicked)
	_hook_button(sandbox_btn, func(): _switch_state(MenuState.SANDBOX_LAB))
	_hook_button(sound_btn, _on_toggle_sound_clicked)
	_hook_button(fullscreen_btn, _on_toggle_fullscreen_clicked)

	# Gauntlet dossier
	_stage_tab_buttons.clear()
	for child in stage_tabs.get_children():
		if child is Button:
			var idx := _stage_tab_buttons.size()
			_stage_tab_buttons.append(child)
			_hook_button(child, func(): _select_dossier_stage(idx))
	_hook_button(launch_gauntlet_btn, _on_launch_gauntlet_from_dossier)
	_hook_button(close_dossier_btn, _close_modal_to_main)

	# Sandbox lab
	_hook_button(tool_stream_btn, func(): _select_tool(ToolMode.STREAM))
	_hook_button(tool_vortex_btn, func(): _select_tool(ToolMode.VORTEX))
	_hook_button(tool_sinkhole_btn, func(): _select_tool(ToolMode.SINKHOLE))
	_hook_button(tool_shockwave_btn, func(): _select_tool(ToolMode.SHOCKWAVE))
	_hook_button(tool_orb_btn, func(): _select_tool(ToolMode.ORB_SPAWNER))
	_hook_button(spawn_bricks_btn, _on_sandbox_spawn_bricks)
	_hook_button(launch_from_sandbox_btn, func():
		if game_mgr != null:
			game_mgr.start_zen_match()
	)
	_hook_button(back_to_menu_btn, _close_modal_to_main)

	vorticity_slider.value_changed.connect(func(v: float):
		if fluid_sim != null: fluid_sim.vorticity = v
	)
	dissipation_slider.value_changed.connect(func(v: float):
		if fluid_sim != null: fluid_sim.dissipation = v
	)

	# Codex
	_hook_button(close_codex_btn, _close_modal_to_main)

	# Settings
	_hook_button(close_settings_btn, _close_settings)
	_hook_button(reset_settings_btn, func():
		_settings_call("reset_to_defaults")
		_show_banner("SETTINGS RESET")
	)

	# Pause overlay
	_hook_button(resume_btn, _on_pause_resume_clicked)
	_hook_button(restart_btn, _on_pause_restart_clicked)
	_hook_button(pause_settings_btn, func(): _open_settings(MenuState.IN_GAME_PAUSE))
	_hook_button(main_menu_btn, _on_pause_menu_clicked)

	# Quit confirm
	_hook_button(quit_no_btn, _close_quit_confirm)
	_hook_button(quit_yes_btn, _on_quit_confirmed)

	# Focus feedback for every focusable control in the menu
	_bind_focus_feedback(self)

func _hook_button(btn: Button, on_click: Callable) -> void:
	if btn == null:
		push_warning("[MenuManager] Tried to hook a null button")
		return
	btn.pressed.connect(func():
		_punch_button(btn)
		_sfx_confirm()
		if fluid_sim != null:
			var center: Vector2 = btn.global_position + btn.size * 0.5
			fluid_sim.inject_shockwave(center, Vector2.ZERO, 380.0, _get_current_color())
		on_click.call()
	)

## Mouse hover moves keyboard focus so mouse and pad share one highlight.
func _bind_focus_feedback(root: Node) -> void:
	for child in root.get_children():
		if child is Control and (child is BaseButton or child is Slider or child is OptionButton):
			var ctrl := child as Control
			ctrl.focus_entered.connect(func(): _on_control_focused(ctrl))
			ctrl.mouse_entered.connect(func():
				if ctrl.focus_mode != Control.FOCUS_NONE and ctrl.is_visible_in_tree():
					ctrl.grab_focus()
			)
		_bind_focus_feedback(child)

func _on_control_focused(ctrl: Control) -> void:
	if not _suppress_focus_sfx:
		_sfx_navigate()
	if ctrl is Button:
		_hover_button(ctrl)
	if fluid_sim != null and ctrl.is_visible_in_tree():
		var center: Vector2 = ctrl.global_position + ctrl.size * 0.5
		fluid_sim.inject_vortex(center, 4.0, 90.0, _get_current_color() * 0.7)

## Explicit neighbours where geometry cannot cross top-level containers.
func _wire_focus_neighbors() -> void:
	var card_buttons: Array[Button] = [card_arcade.button, card_gauntlet.button, card_pvp.button, card_zen.button]
	var toolbar_buttons: Array[Button] = [palette_btn, spawn_orb_btn, clear_fluid_btn, sandbox_btn, sound_btn, fullscreen_btn]
	var nav_buttons: Array[Button] = [codex_btn, settings_btn, quit_btn]

	for i in card_buttons.size():
		var b := card_buttons[i]
		var tb := toolbar_buttons[mini(i + 1, toolbar_buttons.size() - 1)]
		b.focus_neighbor_top = b.get_path_to(tb)
		b.focus_neighbor_bottom = b.get_path_to(nav_buttons[mini(i, nav_buttons.size() - 1)])
	# Arcade card: the difficulty dropdown sits above the button.
	card_arcade.button.focus_neighbor_top = card_arcade.button.get_path_to(card_arcade.diff_option)
	card_arcade.diff_option.focus_neighbor_top = card_arcade.diff_option.get_path_to(toolbar_buttons[1])
	card_arcade.diff_option.focus_neighbor_bottom = card_arcade.diff_option.get_path_to(card_arcade.button)

	for tb in toolbar_buttons:
		tb.focus_neighbor_bottom = tb.get_path_to(card_arcade.button)
	for i in nav_buttons.size():
		nav_buttons[i].focus_neighbor_top = nav_buttons[i].get_path_to(card_buttons[mini(i + 1, card_buttons.size() - 1)])

	# Dossier: tabs row above the action row.
	for tab in _stage_tab_buttons:
		tab.focus_neighbor_bottom = tab.get_path_to(launch_gauntlet_btn)
	launch_gauntlet_btn.focus_neighbor_top = launch_gauntlet_btn.get_path_to(_stage_tab_buttons[0] if not _stage_tab_buttons.is_empty() else launch_gauntlet_btn)
	close_dossier_btn.focus_neighbor_top = close_dossier_btn.get_path_to(_stage_tab_buttons[-1] if not _stage_tab_buttons.is_empty() else close_dossier_btn)

	# Settings: sliders then toggles then buttons, wrap top/bottom.
	var settings_chain: Array[Control] = [master_slider, music_slider, sfx_slider, bloom_slider, ca_slider,
		fullscreen_toggle, vsync_toggle, reduce_motion_toggle, screen_flash_toggle, close_settings_btn]
	for i in settings_chain.size():
		var c := settings_chain[i]
		var up := settings_chain[(i - 1 + settings_chain.size()) % settings_chain.size()]
		var down := settings_chain[(i + 1) % settings_chain.size()]
		c.focus_neighbor_top = c.get_path_to(up)
		c.focus_neighbor_bottom = c.get_path_to(down)
		c.focus_next = c.get_path_to(down)
		c.focus_previous = c.get_path_to(up)
	reset_settings_btn.focus_neighbor_top = reset_settings_btn.get_path_to(screen_flash_toggle)
	reset_settings_btn.focus_neighbor_bottom = reset_settings_btn.get_path_to(master_slider)

	# Pause: wrap vertically.
	var pause_chain: Array[Control] = [resume_btn, restart_btn, pause_settings_btn, main_menu_btn]
	for i in pause_chain.size():
		var c := pause_chain[i]
		c.focus_neighbor_top = c.get_path_to(pause_chain[(i - 1 + pause_chain.size()) % pause_chain.size()])
		c.focus_neighbor_bottom = c.get_path_to(pause_chain[(i + 1) % pause_chain.size()])

# --- Settings -----------------------------------------------------------------

func _setup_settings_controls() -> void:
	_bind_setting_slider(master_slider, "master_volume", 100.0)
	_bind_setting_slider(music_slider, "music_volume", 100.0)
	_bind_setting_slider(sfx_slider, "sfx_volume", 100.0)
	_bind_setting_slider(bloom_slider, "bloom", 1.0)
	_bind_setting_slider(ca_slider, "chromatic", 1.0)
	_bind_setting_toggle(fullscreen_toggle, "fullscreen")
	_bind_setting_toggle(vsync_toggle, "vsync")
	_bind_setting_toggle(reduce_motion_toggle, "reduce_motion")
	_bind_setting_toggle(screen_flash_toggle, "screen_flash")

	var s := _get_settings()
	if s != null and not s.is_connected("changed", _on_setting_changed):
		s.connect("changed", _on_setting_changed)

	# Push the persisted values into systems that Settings does not own.
	if s == null:
		return
	for key in ["bloom", "chromatic", "reduce_motion", "music_enabled", "master_volume", "music_volume", "sfx_volume"]:
		_apply_setting_to_systems(key, _setting(key))

func _bind_setting_slider(slider: HSlider, key: String, scale: float) -> void:
	slider.set_value_no_signal(float(_setting(key, 0.0)) * scale)
	slider.value_changed.connect(func(v: float):
		_set_setting(key, v / scale)
	)

func _bind_setting_toggle(toggle: CheckButton, key: String) -> void:
	var on := bool(_setting(key, false))
	toggle.set_pressed_no_signal(on)
	toggle.text = "ON" if on else "OFF"
	toggle.toggled.connect(func(pressed: bool):
		_sfx_confirm()
		_set_setting(key, pressed)
	)

func _on_setting_changed(key: String, value: Variant) -> void:
	# Keep the widgets in sync when a setting changes from elsewhere
	# (toolbar buttons, reset to defaults).
	match key:
		"master_volume": master_slider.set_value_no_signal(float(value) * 100.0)
		"music_volume": music_slider.set_value_no_signal(float(value) * 100.0)
		"sfx_volume": sfx_slider.set_value_no_signal(float(value) * 100.0)
		"bloom": bloom_slider.set_value_no_signal(float(value))
		"chromatic": ca_slider.set_value_no_signal(float(value))
		"fullscreen": _sync_toggle(fullscreen_toggle, bool(value))
		"vsync": _sync_toggle(vsync_toggle, bool(value))
		"reduce_motion": _sync_toggle(reduce_motion_toggle, bool(value))
		"screen_flash": _sync_toggle(screen_flash_toggle, bool(value))
	_apply_setting_to_systems(key, value)
	_refresh_toolbar_labels()

func _sync_toggle(toggle: CheckButton, on: bool) -> void:
	toggle.set_pressed_no_signal(on)
	toggle.text = "ON" if on else "OFF"

func _apply_setting_to_systems(key: String, value: Variant) -> void:
	match key:
		"bloom":
			if display_mat != null:
				display_mat.set_shader_parameter("bloom_intensity", float(value))
		"chromatic":
			if display_mat != null:
				display_mat.set_shader_parameter("chromatic_aberration", float(value))
		"reduce_motion":
			if vfx_mgr != null and "reduce_motion" in vfx_mgr:
				vfx_mgr.set("reduce_motion", bool(value))
		"music_enabled":
			_audio("set_music_enabled", [bool(value)])
		"master_volume", "music_volume", "sfx_volume":
			# Settings drives the buses directly; fall back to AudioManager's
			# own setters when a bus is missing from the layout.
			var bus: String = _bus_for_key(key)
			if not _has_bus(bus):
				match key:
					"master_volume": _audio("set_master_volume", [float(value)])
					"music_volume": _audio("set_music_volume", [float(value)])
					"sfx_volume": _audio("set_sfx_volume", [float(value)])

func _refresh_toolbar_labels() -> void:
	var music_on := bool(_setting("music_enabled", true))
	if audio_mgr != null and audio_mgr.has_method("is_music_enabled"):
		music_on = bool(audio_mgr.call("is_music_enabled"))
	sound_btn.text = "MUSIC: %s" % ("ON" if music_on else "OFF")
	fullscreen_btn.text = "🖥️ WINDOWED" if bool(_setting("fullscreen", false)) else "🖥️ FULLSCREEN"

# --- Per-frame ----------------------------------------------------------------

func _process(delta: float) -> void:
	_update_toy_orbs(delta)
	_update_mascots(delta)
	_handle_mouse_fluid_interaction(delta)
	_animate_title_breathing(delta)

func _handle_mouse_fluid_interaction(delta: float) -> void:
	if current_state == MenuState.HIDDEN or current_state == MenuState.IN_GAME_PAUSE:
		return
	if get_tree().paused:
		return

	var mpos := get_viewport().get_mouse_position()
	var mouse_vel := (mpos - _last_mouse_pos) / maxf(delta, 0.001)
	_last_mouse_pos = mpos

	var over_canvas := _is_mouse_over_canvas()

	# Gentle passive wake on cursor movement
	if over_canvas and mouse_vel.length_squared() > 100.0 and fluid_sim != null:
		fluid_sim.inject_force(mpos, mouse_vel * 0.08, 65.0, _get_current_color() * 0.4)

	if not over_canvas or fluid_sim == null:
		return

	# Active mouse drawing / vortex injection on canvas
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		match current_tool:
			ToolMode.STREAM:
				fluid_sim.inject_force(mpos, mouse_vel * 0.45 + Vector2(120.0, 0.0), brush_radius, _get_current_color())
			ToolMode.VORTEX:
				fluid_sim.inject_vortex(mpos, 5.5, brush_radius * 1.2, _get_current_color())
			ToolMode.SINKHOLE:
				fluid_sim.inject_sink(mpos, 900.0, brush_radius * 1.4, _get_current_color())
			ToolMode.SHOCKWAVE:
				if fmod(Time.get_ticks_msec() * 0.001, 0.25) < delta:
					fluid_sim.inject_shockwave(mpos, Vector2.RIGHT, 450.0, _get_current_color())
			ToolMode.ORB_SPAWNER:
				if fmod(Time.get_ticks_msec() * 0.001, 0.3) < delta:
					_spawn_toy_orb(mpos, mouse_vel * 0.5)
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		fluid_sim.inject_vortex(mpos, 7.0, brush_radius * 1.3, _get_current_color())

## True when the cursor is over bare arena (no button, panel, or backdrop).
func _is_mouse_over_canvas() -> bool:
	if current_state == MenuState.HIDDEN or current_state == MenuState.IN_GAME_PAUSE or _quit_confirm_open:
		return false
	return get_viewport().gui_get_hovered_control() == null

# --- Input --------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if current_state == MenuState.HIDDEN:
		return
	if not event.is_action_pressed("ui_cancel"):
		return

	if _quit_confirm_open:
		_close_quit_confirm()
		_sfx_back()
		get_viewport().set_input_as_handled()
		return

	match current_state:
		MenuState.GAUNTLET_DOSSIER, MenuState.CODEX:
			_sfx_back()
			_switch_state(MenuState.MAIN)
			get_viewport().set_input_as_handled()
		MenuState.SETTINGS:
			_sfx_back()
			_close_settings()
			get_viewport().set_input_as_handled()
		MenuState.SANDBOX_LAB:
			# Only intercept when no match is running; otherwise GameManager pauses.
			if game_mgr == null or game_mgr.current_state == GameManager.State.MENU:
				_sfx_back()
				_switch_state(MenuState.MAIN)
				get_viewport().set_input_as_handled()
		MenuState.MAIN:
			_open_quit_confirm()
			get_viewport().set_input_as_handled()
		_:
			pass # IN_GAME_PAUSE: GameManager handles resume.

func _unhandled_input(event: InputEvent) -> void:
	if current_state == MenuState.HIDDEN or current_state == MenuState.IN_GAME_PAUSE:
		return

	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if fluid_sim != null and _is_mouse_over_canvas():
				fluid_sim.inject_shockwave(mb.position, Vector2.ZERO, 700.0, _get_current_color())
				_audio("trigger_blast", [1.2, mb.position])
				_show_banner("SONIC PULSE")
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			brush_radius = minf(brush_radius + 15.0, 300.0)
			_show_banner("BRUSH SIZE: %d px" % int(brush_radius))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			brush_radius = maxf(brush_radius - 15.0, 40.0)
			_show_banner("BRUSH SIZE: %d px" % int(brush_radius))

	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE and (current_state == MenuState.MAIN or current_state == MenuState.SANDBOX_LAB):
			# Space on a focused button is ui_accept and never reaches here.
			var mpos := get_viewport().get_mouse_position()
			if fluid_sim != null:
				fluid_sim.inject_shockwave(mpos, Vector2.ZERO, 650.0, _get_current_color())
				_audio("trigger_blast", [1.0, mpos])
				_show_banner("SHOCKWAVE")

func _exit_tree() -> void:
	for orb in _toy_orbs:
		var node: ColorRect = orb.get("node")
		if node != null and is_instance_valid(node):
			node.queue_free()
	_toy_orbs.clear()

# --- Toy orbs -----------------------------------------------------------------

func _update_toy_orbs(delta: float) -> void:
	if _toy_orbs.is_empty():
		return

	var kept_orbs: Array[Dictionary] = []
	for orb in _toy_orbs:
		var pos: Vector2 = orb["pos"]
		var vel: Vector2 = orb["vel"]
		var color: Color = orb["color"]
		var radius: float = orb["radius"]
		var life: float = orb["life"] - delta

		if not is_finite(pos.x) or not is_finite(pos.y):
			pos = Vector2(960.0, 540.0)
			vel = Vector2.ZERO
		if not is_finite(vel.x) or not is_finite(vel.y):
			vel = Vector2.ZERO

		if fluid_sim != null:
			var fluid_v := fluid_sim.sample_velocity_at(pos)
			if is_finite(fluid_v.x) and is_finite(fluid_v.y):
				vel += fluid_v * (delta * 14.0)

		vel = vel.limit_length(1000.0)
		pos += vel * delta
		vel *= 0.985

		if pos.x - radius < 40.0:
			pos.x = 40.0 + radius
			vel.x = absf(vel.x) * 0.88
		elif pos.x + radius > 1880.0:
			pos.x = 1880.0 - radius
			vel.x = -absf(vel.x) * 0.88

		if pos.y - radius < 50.0:
			pos.y = 50.0 + radius
			vel.y = absf(vel.y) * 0.88
		elif pos.y + radius > 1030.0:
			pos.y = 1030.0 - radius
			vel.y = -absf(vel.y) * 0.88

		if fluid_sim != null and vel.length_squared() > 100.0:
			fluid_sim.inject_force(pos, vel * 0.12, radius * 1.4, color * 0.6)

		orb["pos"] = pos
		orb["vel"] = vel
		orb["life"] = life

		var node: ColorRect = orb.get("node")
		if node != null and is_instance_valid(node):
			node.position = pos - Vector2(radius, radius)
			node.modulate.a = clampf(life / 1.0, 0.0, 1.0) if life < 1.0 else 1.0

		if life > 0.0:
			kept_orbs.append(orb)
		else:
			if node != null and is_instance_valid(node):
				node.queue_free()

	_toy_orbs = kept_orbs

func _spawn_toy_orb(pos: Vector2, initial_vel: Vector2 = Vector2.ZERO) -> void:
	if _toy_orbs.size() >= MAX_TOY_ORBS:
		var oldest: Dictionary = _toy_orbs.pop_front()
		var old_node: ColorRect = oldest.get("node")
		if old_node != null and is_instance_valid(old_node):
			old_node.queue_free()

	var radius := randf_range(16.0, 26.0)
	var rect := ColorRect.new()
	rect.size = Vector2(radius * 2.0, radius * 2.0)
	rect.position = pos - Vector2(radius, radius)
	rect.pivot_offset = Vector2(radius, radius)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/vfx/orb.gdshader")
	mat.set_shader_parameter("core_color", Color(1.0, 1.0, 1.0))
	var col := _get_current_color()
	mat.set_shader_parameter("glow_color", col)
	mat.set_shader_parameter("pulse", 1.0)
	mat.set_shader_parameter("shape_type", randi() % 5)
	rect.material = mat
	add_child(rect)
	# Keep orbs behind the UI overlays.
	move_child(rect, 0)

	_toy_orbs.append({
		"pos": pos,
		"vel": initial_vel if initial_vel != Vector2.ZERO else Vector2(randf_range(-160, 160), randf_range(-160, 160)),
		"radius": radius,
		"color": col,
		"life": 45.0,
		"node": rect
	})

	if fluid_sim != null:
		fluid_sim.inject_shockwave(pos, initial_vel.normalized() * 300.0, 260.0, col)

# --- Mascots and title --------------------------------------------------------

## Each mode card makes its mascot glance at the card and bark once.
func _bind_card_hover() -> void:
	var cards: Array = [
		[card_arcade, 0, CharacterFace.Mood.HAPPY, "Warm-up time!"],
		[card_gauntlet, 1, CharacterFace.Mood.SMUG, "Five of us. Good luck."],
		[card_pvp, 1, CharacterFace.Mood.FOCUS, "Bring a friend."],
		[card_zen, 0, CharacterFace.Mood.WINK, "Just vibes."],
	]
	for entry in cards:
		var card: ModeCard = entry[0]
		if card == null or not card.has_signal("hovered"):
			continue
		var who: int = entry[1]
		var mood: CharacterFace.Mood = entry[2]
		var line: String = entry[3]
		card.hovered.connect(func(): _on_card_hovered(card, who, mood, line))

func _on_card_hovered(card: Control, who: int, mood: CharacterFace.Mood, line: String) -> void:
	if current_state != MenuState.MAIN:
		return
	var face: CharacterFace = padd_face if who == 0 else lin_face
	if face == null or not is_instance_valid(face):
		return
	var target := card.global_position + card.size * 0.5
	face.look_at_point(face.global_position, target)
	_mascot_glance[who] = 0.9
	face.maybe_mood(mood, 1.0)
	if _mascot_bark_cd <= 0.0:
		face.bark(line)
		_mascot_bark_cd = 2.5

var _mascot_glance: Array[float] = [0.0, 0.0]

func _update_mascots(delta: float) -> void:
	_mascot_bark_cd = maxf(_mascot_bark_cd - delta, 0.0)
	if current_state != MenuState.MAIN:
		return
	var mpos := get_viewport().get_mouse_position()
	for i in 2:
		_mascot_glance[i] = maxf(_mascot_glance[i] - delta, 0.0)

	if padd_face != null and is_instance_valid(padd_face):
		if _mascot_glance[0] <= 0.0:
			padd_face.look_at_point(padd_face.global_position, mpos)
		var dist_l := padd_face.global_position.distance_to(mpos)
		if dist_l < 110.0 and _mascot_bark_cd <= 0.0:
			padd_face.set_mood(CharacterFace.Mood.HAPPY, 1.2)
			padd_face.bark("Let's Paddle!")
			_mascot_bark_cd = 3.5

	if lin_face != null and is_instance_valid(lin_face):
		if _mascot_glance[1] <= 0.0:
			lin_face.look_at_point(lin_face.global_position, mpos)
		var dist_r := lin_face.global_position.distance_to(mpos)
		if dist_r < 110.0 and _mascot_bark_cd <= 0.0:
			lin_face.set_mood(CharacterFace.Mood.SMUG, 1.2)
			lin_face.bark("You ready?")
			_mascot_bark_cd = 3.5

var _title_energy := 0.3

func _animate_title_breathing(delta: float) -> void:
	if title_text == null or current_state != MenuState.MAIN:
		return
	# Feed the shimmer shader the fluid energy so the glow pulses with the field.
	if title_text.material is ShaderMaterial:
		var want := fluid_sim.get_flow_energy_norm() if fluid_sim != null else 0.3
		_title_energy = lerpf(_title_energy, clampf(want, 0.0, 1.0), clampf(delta * 2.0, 0.0, 1.0))
		var m: ShaderMaterial = title_text.material
		m.set_shader_parameter("energy", _title_energy)
		m.set_shader_parameter("width_px", maxf(title_text.size.x, 1.0))
		m.set_shader_parameter("shimmer", 0.0 if _reduce_motion() else 0.6)
	if _reduce_motion():
		title_text.scale = Vector2.ONE
		return
	var t := Time.get_ticks_msec() * 0.001
	title_text.pivot_offset = title_text.size * 0.5
	title_text.scale = Vector2.ONE * (1.0 + sin(t * 1.8) * (0.015 + _title_energy * 0.015))

# --- State machine ------------------------------------------------------------

func _switch_state(new_state: MenuState) -> void:
	var previous := current_state
	current_state = new_state
	if _quit_confirm_open:
		_close_quit_confirm(false)

	main_menu_panel.visible = (current_state == MenuState.MAIN)
	top_toolbar.visible = (current_state == MenuState.MAIN or current_state == MenuState.SANDBOX_LAB)
	gauntlet_dossier_modal.visible = (current_state == MenuState.GAUNTLET_DOSSIER)
	sandbox_hud.visible = (current_state == MenuState.SANDBOX_LAB)
	codex_modal.visible = (current_state == MenuState.CODEX)
	settings_modal.visible = (current_state == MenuState.SETTINGS)
	pause_overlay.visible = (current_state == MenuState.IN_GAME_PAUSE)

	if current_state == MenuState.GAUNTLET_DOSSIER:
		_select_dossier_stage(dossier_selected_stage, false)

	var focus_target: Control = null
	match current_state:
		MenuState.MAIN:
			_punch_container(main_menu_panel)
			focus_target = card_arcade.button
		MenuState.GAUNTLET_DOSSIER:
			_punch_container(gauntlet_dossier_modal)
			focus_target = _stage_tab_buttons[dossier_selected_stage] if dossier_selected_stage < _stage_tab_buttons.size() else launch_gauntlet_btn
		MenuState.SANDBOX_LAB:
			_punch_container(sandbox_hud)
			focus_target = tool_stream_btn
		MenuState.CODEX:
			_punch_container(codex_modal)
			focus_target = close_codex_btn
		MenuState.SETTINGS:
			_punch_container(settings_modal)
			focus_target = master_slider
		MenuState.IN_GAME_PAUSE:
			_punch_container(pause_overlay)
			focus_target = resume_btn
		MenuState.HIDDEN:
			pass

	if previous != current_state and current_state != MenuState.HIDDEN:
		_audio("trigger_menu_open")

	_grab_focus_quiet(focus_target)

func _grab_focus_quiet(target: Control) -> void:
	if target == null:
		var vp := get_viewport()
		if vp != null:
			vp.gui_release_focus()
		return
	_suppress_focus_sfx = true
	target.grab_focus()
	# Visibility may only propagate at the end of the frame; retry deferred.
	target.call_deferred("grab_focus")
	call_deferred("_release_focus_suppression")

func _release_focus_suppression() -> void:
	_suppress_focus_sfx = false

func _close_modal_to_main() -> void:
	_switch_state(MenuState.MAIN)

func _open_settings(return_to: MenuState) -> void:
	_settings_return_state = return_to
	_switch_state(MenuState.SETTINGS)

func _close_settings() -> void:
	if game_mgr != null and game_mgr.current_state == GameManager.State.PAUSED:
		_switch_state(MenuState.IN_GAME_PAUSE)
	elif _settings_return_state == MenuState.IN_GAME_PAUSE:
		# Match ended or resumed while settings were open.
		_switch_state(MenuState.HIDDEN)
	else:
		_switch_state(MenuState.MAIN)

func _open_quit_confirm() -> void:
	_quit_confirm_open = true
	quit_confirm.visible = true
	_punch_container(quit_confirm)
	_audio("trigger_menu_open")
	_grab_focus_quiet(quit_no_btn)

func _close_quit_confirm(refocus := true) -> void:
	_quit_confirm_open = false
	quit_confirm.visible = false
	if refocus and current_state == MenuState.MAIN:
		_grab_focus_quiet(quit_btn)

# --- Dossier ------------------------------------------------------------------

func _select_dossier_stage(stage_idx: int, play_feedback := true) -> void:
	dossier_selected_stage = stage_idx
	var stages: Array = TournamentManager.STAGES
	if stage_idx < 0 or stage_idx >= stages.size():
		return

	for i in _stage_tab_buttons.size():
		_stage_tab_buttons[i].set_pressed_no_signal(i == stage_idx)

	var info: Dictionary = stages[stage_idx]
	var col: Color = info.get("color", Color.WHITE)
	stage_number_lbl.text = "%s  ·  %s" % [info.get("title", ""), info.get("subtitle", "")]
	boss_name_lbl.text = info.get("boss_name", "")
	boss_name_lbl.add_theme_color_override("font_color", col)
	boss_quote_lbl.text = "\"%s\"" % info.get("quote", "")
	boss_desc_lbl.text = info.get("description", "")
	portrait_glow.color = col * 0.7
	var shape_name := "STANDARD"
	match info.get("shape", 0):
		1: shape_name = "SCOOP HYDRO"
		2: shape_name = "WEDGE DEFLECT"
		3: shape_name = "TWIN FORK"
		4: shape_name = "FORTRESS BARRICADE"
	hazard_badge_lbl.text = "TRAIT: %s  |  BRICKS: %s  |  TWINS: %s" % [shape_name, "YES" if info.get("bricks", false) else "NO", "YES" if info.get("twin", false) else "NO"]
	hazard_badge_lbl.add_theme_color_override("font_color", col)

	if play_feedback:
		_audio("trigger_sting", [380.0 + float(stage_idx) * 80.0, 0.4])
		if fluid_sim != null:
			fluid_sim.inject_vortex(Vector2(960, 540), 5.0, 200.0, col)

# --- Sandbox ------------------------------------------------------------------

func _select_tool(tool_mode: ToolMode) -> void:
	current_tool = tool_mode
	_audio("trigger_sandbox_tool")
	match tool_mode:
		ToolMode.STREAM: _show_banner("TOOL: PLASMA DYE STREAM")
		ToolMode.VORTEX: _show_banner("TOOL: GRAVITATIONAL VORTEX")
		ToolMode.SINKHOLE: _show_banner("TOOL: SUCTION SINKHOLE")
		ToolMode.SHOCKWAVE: _show_banner("TOOL: SONIC SHOCKWAVE")
		ToolMode.ORB_SPAWNER: _show_banner("TOOL: TOY ORB EMITTER")

func _apply_palette(idx: int) -> void:
	current_palette = idx % PALETTE_NAMES.size()
	if display_mat != null:
		display_mat.set_shader_parameter("palette_mode", current_palette)
	palette_btn.text = "PALETTE: %s" % PALETTE_NAMES[current_palette].to_upper()
	palette_btn.add_theme_color_override("font_color", _get_current_color())

func _get_current_color() -> Color:
	return PALETTE_COLORS[current_palette % PALETTE_COLORS.size()]

func _show_banner(text: String) -> void:
	if quick_banner == null:
		return
	quick_banner.text = "— %s —" % text
	quick_banner.add_theme_color_override("font_color", _get_current_color())
	quick_banner.modulate.a = 1.0
	quick_banner.pivot_offset = quick_banner.size * 0.5
	quick_banner.scale = Vector2.ONE if _reduce_motion() else Vector2(1.15, 1.15)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(quick_banner, "scale", Vector2.ONE, 0.12)
	tw.tween_interval(0.9)
	tw.tween_property(quick_banner, "modulate:a", 0.0, 0.3)

# --- Button actions -----------------------------------------------------------

func _on_arcade_clicked() -> void:
	var diff := card_arcade.get_difficulty_multiplier() if card_arcade != null else 1.0
	_switch_state(MenuState.HIDDEN)
	if game_mgr != null:
		game_mgr.start_arcade_match(diff)

func _on_gauntlet_clicked() -> void:
	_switch_state(MenuState.GAUNTLET_DOSSIER)

func _on_launch_gauntlet_from_dossier() -> void:
	_switch_state(MenuState.HIDDEN)
	if game_mgr != null:
		game_mgr.start_gauntlet_match()

func _on_pvp_clicked() -> void:
	_switch_state(MenuState.HIDDEN)
	if game_mgr != null:
		game_mgr.start_pvp_match()

func _on_zen_clicked() -> void:
	_switch_state(MenuState.SANDBOX_LAB)
	if game_mgr != null:
		game_mgr.start_zen_match()

func _on_cycle_palette_clicked() -> void:
	_apply_palette(current_palette + 1)
	_show_banner("THEME: %s" % PALETTE_NAMES[current_palette].to_upper())
	if fluid_sim != null:
		fluid_sim.inject_shockwave(Vector2(960, 540), Vector2.ZERO, 500.0, _get_current_color())

func _on_clear_fluid_clicked() -> void:
	for orb in _toy_orbs:
		var node: ColorRect = orb.get("node")
		if node != null and is_instance_valid(node):
			node.queue_free()
	_toy_orbs.clear()
	if fluid_sim != null:
		fluid_sim.inject_shockwave(Vector2(960, 540), Vector2.ZERO, 900.0, Color.BLACK)
	_show_banner("FIELD CLEARED")

func _on_toggle_sound_clicked() -> void:
	var on := not bool(_setting("music_enabled", true))
	if audio_mgr != null and audio_mgr.has_method("is_music_enabled"):
		on = not bool(audio_mgr.call("is_music_enabled"))
	_set_setting("music_enabled", on)
	_refresh_toolbar_labels()
	_show_banner("MUSIC: %s" % ("ON" if on else "OFF"))

func _on_toggle_fullscreen_clicked() -> void:
	var on := _toggle_setting("fullscreen")
	_show_banner("FULLSCREEN" if on else "WINDOWED")

func _on_sandbox_spawn_bricks() -> void:
	if game_mgr != null and game_mgr.chaos != null:
		var bmat := game_mgr.get_parent().get_node_or_null("BrickMatrix") as BrickMatrix
		if bmat != null:
			bmat.spawn_firewall(3, 7)
			_show_banner("SPAWNED BRICK WALL")

func _on_quit_clicked() -> void:
	_open_quit_confirm()

func _on_quit_confirmed() -> void:
	_settings_call("save")
	get_tree().quit()

# Pause overlay handlers
func _on_pause_resume_clicked() -> void:
	if game_mgr != null:
		game_mgr.resume_match()

func _on_pause_restart_clicked() -> void:
	if game_mgr != null:
		game_mgr.resume_match()
		game_mgr.restart_match()

func _on_pause_menu_clicked() -> void:
	if game_mgr != null:
		game_mgr.return_to_menu()

# --- GameManager signal callbacks --------------------------------------------

func _on_game_paused(is_paused: bool) -> void:
	if is_paused:
		_switch_state(MenuState.IN_GAME_PAUSE)
	else:
		if current_state == MenuState.IN_GAME_PAUSE:
			_switch_state(MenuState.HIDDEN)
		elif current_state == MenuState.SETTINGS and _settings_return_state == MenuState.IN_GAME_PAUSE:
			_switch_state(MenuState.HIDDEN)

func _on_menu_entered() -> void:
	_switch_state(MenuState.MAIN)

func _on_match_started() -> void:
	if current_state != MenuState.SANDBOX_LAB:
		_switch_state(MenuState.HIDDEN)

# --- UI micro-animations ------------------------------------------------------

func _punch_button(btn: Button) -> void:
	if _reduce_motion():
		return
	btn.pivot_offset = btn.size * 0.5
	btn.scale = Vector2(0.92, 0.92)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(btn, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _hover_button(btn: Button) -> void:
	if _reduce_motion():
		return
	btn.pivot_offset = btn.size * 0.5
	btn.scale = Vector2(1.04, 1.04)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(btn, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _punch_container(ctrl: Control) -> void:
	ctrl.modulate.a = 0.0
	ctrl.pivot_offset = ctrl.size * 0.5
	ctrl.scale = Vector2.ONE if _reduce_motion() else Vector2(0.96, 0.96)
	var tw := create_tween().set_parallel(true)
	tw.set_ignore_time_scale(true)
	tw.tween_property(ctrl, "modulate:a", 1.0, 0.15)
	tw.tween_property(ctrl, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
