class_name MenuManager
extends CanvasLayer

## MenuManager: Orchestrates the living fluid title screen, sandbox laboratory,
## boss gauntlet dossier, game mode selection, how-to-play codex, settings,
## and in-game pause overlay.

signal arcade_requested(difficulty: float)
signal gauntlet_requested
signal pvp_requested
signal zen_requested
signal restart_requested
signal resume_requested
signal main_menu_requested

enum MenuState { MAIN, GAUNTLET_DOSSIER, SANDBOX_LAB, CODEX, SETTINGS, IN_GAME_PAUSE, HIDDEN }

var current_state: MenuState = MenuState.MAIN

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

# UI Node References
@onready var main_menu_panel: Control = $MainMenuPanel
@onready var title_header: Control = $MainMenuPanel/TitleHeader
@onready var mode_cards_container: HBoxContainer = $MainMenuPanel/ModeCardsContainer
@onready var top_toolbar: Control = $TopToolbar
@onready var gauntlet_dossier_modal: Control = $GauntletDossierModal
@onready var sandbox_hud: Control = $SandboxHUD
@onready var codex_modal: Control = $CodexModal
@onready var settings_modal: Control = $SettingsModal
@onready var pause_overlay: Control = $PauseOverlay
@onready var quick_banner: Label = $QuickBanner

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
	_apply_palette(0)
	_switch_state(MenuState.MAIN)

	# Spawn initial toy orbs for menu background ambiance
	for i in range(3):
		_spawn_toy_orb(Vector2(randf_range(300, 1600), randf_range(200, 800)), Vector2(randf_range(-180, 180), randf_range(-180, 180)))

func _setup_mascots() -> void:
	var padd_container := get_node_or_null("MainMenuPanel/MascotPadd") as Control
	if padd_container != null:
		padd_face = CharacterFace.new()
		padd_face.setup(Vector2(90, 90), false, 0.0)
		padd_container.add_child(padd_face)
		padd_face.position = Vector2(45, 45)

	var lin_container := get_node_or_null("MainMenuPanel/MascotLin") as Control
	if lin_container != null:
		lin_face = CharacterFace.new()
		lin_face.setup(Vector2(90, 90), true, 0.15)
		lin_container.add_child(lin_face)
		lin_face.position = Vector2(45, 45)

func _bind_ui_events() -> void:
	# Main Mode Cards
	_hook_button("MainMenuPanel/ModeCardsContainer/CardArcade/CardLayout/PlayArcadeBtn", _on_arcade_clicked)
	_hook_button("MainMenuPanel/ModeCardsContainer/CardGauntlet/CardLayout/OpenGauntletBtn", _on_gauntlet_clicked)
	_hook_button("MainMenuPanel/ModeCardsContainer/CardPVP/CardLayout/PlayPVPBtn", _on_pvp_clicked)
	_hook_button("MainMenuPanel/ModeCardsContainer/CardZen/CardLayout/PlayZenBtn", _on_zen_clicked)

	# Bottom Quick Buttons
	_hook_button("MainMenuPanel/BottomNav/CodexBtn", func(): _switch_state(MenuState.CODEX))
	_hook_button("MainMenuPanel/BottomNav/SettingsBtn", func(): _switch_state(MenuState.SETTINGS))
	_hook_button("MainMenuPanel/BottomNav/QuitBtn", _on_quit_clicked)

	# Top Toolbar Buttons
	_hook_button("TopToolbar/ToolbarContent/PaletteBtn", _on_cycle_palette_clicked)
	_hook_button("TopToolbar/ToolbarContent/SpawnOrbBtn", func():
		_spawn_toy_orb(get_viewport().get_mouse_position(), Vector2(randf_range(-300, 300), randf_range(-300, 300)))
		_show_banner("SPAWNED TOY ORB")
	)
	_hook_button("TopToolbar/ToolbarContent/ClearFluidBtn", _on_clear_fluid_clicked)
	_hook_button("TopToolbar/ToolbarContent/SandboxBtn", func(): _switch_state(MenuState.SANDBOX_LAB))
	_hook_button("TopToolbar/ToolbarContent/SoundBtn", _on_toggle_sound_clicked)
	_hook_button("TopToolbar/ToolbarContent/FullscreenBtn", _on_toggle_fullscreen_clicked)

	# Gauntlet Dossier Modal Buttons
	for i in range(5):
		var tab_path := "GauntletDossierModal/DossierCard/DossierLayout/StageTabs/StageTab%d" % (i + 1)
		var btn := _find_button_by_path_or_name(tab_path, "StageTab%d" % (i + 1))
		if btn != null:
			var idx := i
			_hook_existing_button(btn, func(): _select_dossier_stage(idx))
	_hook_button("GauntletDossierModal/DossierCard/DossierLayout/DossierAction/LaunchGauntletBtn", _on_launch_gauntlet_from_dossier)
	_hook_button("GauntletDossierModal/DossierCard/DossierLayout/DossierAction/CloseDossierBtn", func(): _switch_state(MenuState.MAIN))

	# Sandbox Lab HUD Buttons
	_hook_button("SandboxHUD/LabBar/ToolStream", func(): _select_tool(ToolMode.STREAM))
	_hook_button("SandboxHUD/LabBar/ToolVortex", func(): _select_tool(ToolMode.VORTEX))
	_hook_button("SandboxHUD/LabBar/ToolSinkhole", func(): _select_tool(ToolMode.SINKHOLE))
	_hook_button("SandboxHUD/LabBar/ToolShockwave", func(): _select_tool(ToolMode.SHOCKWAVE))
	_hook_button("SandboxHUD/LabBar/ToolOrb", func(): _select_tool(ToolMode.ORB_SPAWNER))
	_hook_button("SandboxHUD/LabBar/SpawnBricksBtn", _on_sandbox_spawn_bricks)
	_hook_button("SandboxHUD/LabBar/LaunchFromSandboxBtn", func():
		if game_mgr != null:
			game_mgr.start_zen_match()
	)
	_hook_button("SandboxHUD/LabBar/BackToMenuBtn", func(): _switch_state(MenuState.MAIN))

	# Codex Modal
	_hook_button("CodexModal/CodexPanel/CodexLayout/CloseCodexBtn", func(): _switch_state(MenuState.MAIN))

	# Settings Modal
	_hook_button("SettingsModal/SettingsPanel/SettingsLayout/CloseSettingsBtn", func():
		if game_mgr != null and game_mgr.current_state == GameManager.State.PAUSED:
			_switch_state(MenuState.IN_GAME_PAUSE)
		else:
			_switch_state(MenuState.MAIN)
	)
	_setup_settings_controls()

	# Pause Overlay
	_hook_button("PauseOverlay/PausePanel/PauseLayout/ResumeBtn", _on_pause_resume_clicked)
	_hook_button("PauseOverlay/PausePanel/PauseLayout/RestartBtn", _on_pause_restart_clicked)
	_hook_button("PauseOverlay/PausePanel/PauseLayout/SettingsBtn", func(): _switch_state(MenuState.SETTINGS))
	_hook_button("PauseOverlay/PausePanel/PauseLayout/MainMenuBtn", _on_pause_menu_clicked)

func _find_button_by_path_or_name(path: String, target_name: String) -> Button:
	var btn := get_node_or_null(path) as Button
	if btn == null:
		btn = _find_node_by_name(self, target_name) as Button
	return btn

func _find_node_by_name(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child in root.get_children():
		var found := _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null

func _hook_button(path: String, on_click: Callable) -> void:
	var target_name := path.get_file()
	var btn := _find_button_by_path_or_name(path, target_name)
	if btn == null:
		push_warning("[MenuManager] Warning: could not find button at %s" % path)
		return
	_hook_existing_button(btn, on_click)

func _hook_existing_button(btn: Button, on_click: Callable) -> void:
	btn.pressed.connect(func():
		_punch_button(btn)
		if audio_mgr != null:
			audio_mgr.trigger_ui_click()
		if fluid_sim != null:
			var center: Vector2 = btn.global_position + btn.size * 0.5
			fluid_sim.inject_shockwave(center, Vector2.ZERO, 380.0, _get_current_color())
		on_click.call()
	)
	btn.mouse_entered.connect(func():
		_hover_button(btn)
		if audio_mgr != null:
			audio_mgr.trigger_ui_hover()
		if fluid_sim != null:
			var center: Vector2 = btn.global_position + btn.size * 0.5
			fluid_sim.inject_vortex(center, 4.0, 90.0, _get_current_color() * 0.7)
	)

func _setup_settings_controls() -> void:
	var master_slider := _find_node_by_name(self, "MasterVolume")
	if master_slider != null:
		var s := master_slider.get_node_or_null("Slider") as Slider
		if s != null:
			s.value = 85.0
			s.value_changed.connect(func(v: float):
				if audio_mgr != null: audio_mgr.set_master_volume(v / 100.0)
			)

	var music_slider := _find_node_by_name(self, "MusicVolume")
	if music_slider != null:
		var s := music_slider.get_node_or_null("Slider") as Slider
		if s != null:
			s.value = 80.0
			s.value_changed.connect(func(v: float):
				if audio_mgr != null: audio_mgr.set_music_volume(v / 100.0)
			)

	var sfx_slider := _find_node_by_name(self, "SFXVolume")
	if sfx_slider != null:
		var s := sfx_slider.get_node_or_null("Slider") as Slider
		if s != null:
			s.value = 90.0
			s.value_changed.connect(func(v: float):
				if audio_mgr != null: audio_mgr.set_sfx_volume(v / 100.0)
			)

	var bloom_slider := _find_node_by_name(self, "BloomSlider")
	if bloom_slider != null:
		var s := bloom_slider.get_node_or_null("Slider") as Slider
		if s != null:
			s.value = 1.2
			s.value_changed.connect(func(v: float):
				if display_mat != null: display_mat.set_shader_parameter("bloom_intensity", v)
			)

	var ca_slider := _find_node_by_name(self, "CASlider")
	if ca_slider != null:
		var s := ca_slider.get_node_or_null("Slider") as Slider
		if s != null:
			s.value = 1.8
			s.value_changed.connect(func(v: float):
				if display_mat != null: display_mat.set_shader_parameter("chromatic_aberration", v)
			)

	# Sandbox Lab physics sliders
	var vort_node := _find_node_by_name(self, "Vorticity")
	if vort_node != null:
		var s := vort_node.get_node_or_null("Slider") as Slider
		if s != null:
			s.value = 0.95
			s.value_changed.connect(func(v: float):
				if fluid_sim != null: fluid_sim.vorticity = v
			)

	var diss_node := _find_node_by_name(self, "Dissipation")
	if diss_node != null:
		var s := diss_node.get_node_or_null("Slider") as Slider
		if s != null:
			s.value = 0.995
			s.value_changed.connect(func(v: float):
				if fluid_sim != null: fluid_sim.dissipation = v
			)

func _process(delta: float) -> void:
	_update_toy_orbs(delta)
	_update_mascots(delta)
	_handle_mouse_fluid_interaction(delta)
	_animate_title_breathing(delta)

func _handle_mouse_fluid_interaction(delta: float) -> void:
	if current_state == MenuState.HIDDEN:
		return

	var mpos := get_viewport().get_mouse_position()
	var mouse_vel := (mpos - _last_mouse_pos) / maxf(delta, 0.001)

	# Gentle passive wake on cursor movement
	if mouse_vel.length_squared() > 100.0 and fluid_sim != null:
		fluid_sim.inject_force(mpos, mouse_vel * 0.08, 65.0, _get_current_color() * 0.4)

	# Active mouse drawing / vortex injection on canvas
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _is_mouse_over_canvas(mpos):
		if fluid_sim != null:
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

	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and _is_mouse_over_canvas(mpos):
		if fluid_sim != null:
			fluid_sim.inject_vortex(mpos, 7.0, brush_radius * 1.3, _get_current_color())

	_last_mouse_pos = mpos

func _unhandled_input(event: InputEvent) -> void:
	if current_state == MenuState.HIDDEN:
		return

	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if fluid_sim != null:
				fluid_sim.inject_shockwave(mb.position, Vector2.ZERO, 700.0, _get_current_color())
				if audio_mgr != null: audio_mgr.trigger_blast(1.2, mb.position)
				_show_banner("SONIC PULSE")
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			brush_radius = minf(brush_radius + 15.0, 300.0)
			_show_banner("BRUSH SIZE: %d px" % int(brush_radius))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			brush_radius = maxf(brush_radius - 15.0, 40.0)
			_show_banner("BRUSH SIZE: %d px" % int(brush_radius))

	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE and (current_state == MenuState.MAIN or current_state == MenuState.SANDBOX_LAB):
			var mpos := get_viewport().get_mouse_position()
			if fluid_sim != null:
				fluid_sim.inject_shockwave(mpos, Vector2.ZERO, 650.0, _get_current_color())
				if audio_mgr != null: audio_mgr.trigger_blast(1.0, mpos)
				_show_banner("SHOCKWAVE")

func _is_mouse_over_canvas(mpos: Vector2) -> bool:
	if current_state == MenuState.MAIN:
		if mode_cards_container != null and mode_cards_container.get_global_rect().has_point(mpos):
			return false
		if top_toolbar != null and top_toolbar.get_global_rect().has_point(mpos):
			return false
	elif current_state == MenuState.GAUNTLET_DOSSIER:
		var dcard := _find_node_by_name(self, "DossierCard") as Control
		if dcard != null and dcard.get_global_rect().has_point(mpos):
			return false
	elif current_state == MenuState.CODEX:
		var ccard := _find_node_by_name(self, "CodexPanel") as Control
		if ccard != null and ccard.get_global_rect().has_point(mpos):
			return false
	elif current_state == MenuState.SETTINGS:
		var scard := _find_node_by_name(self, "SettingsPanel") as Control
		if scard != null and scard.get_global_rect().has_point(mpos):
			return false
	elif current_state == MenuState.SANDBOX_LAB:
		var sbar := _find_node_by_name(self, "SandboxHUD") as Control
		if sbar != null and sbar.get_global_rect().has_point(mpos):
			return false
		if top_toolbar != null and top_toolbar.get_global_rect().has_point(mpos):
			return false
	elif current_state == MenuState.IN_GAME_PAUSE:
		return false
	return true

func _exit_tree() -> void:
	for orb in _toy_orbs:
		var node: ColorRect = orb.get("node")
		if node != null and is_instance_valid(node):
			node.queue_free()
	_toy_orbs.clear()

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

		# Sample fluid current velocity and push the orb
		if fluid_sim != null:
			var fluid_v := fluid_sim.sample_velocity_at(pos)
			if is_finite(fluid_v.x) and is_finite(fluid_v.y):
				vel += fluid_v * (delta * 14.0)

		vel = vel.limit_length(1000.0)
		pos += vel * delta
		vel *= 0.985 # Gentle drag

		# Arena boundaries bounce
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

		# Inject fluid wake from moving orb
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

func _update_mascots(delta: float) -> void:
	_mascot_bark_cd = maxf(_mascot_bark_cd - delta, 0.0)
	var mpos := get_viewport().get_mouse_position()

	if padd_face != null and is_instance_valid(padd_face):
		padd_face.look_at_point(padd_face.global_position, mpos)
		var dist_l := padd_face.global_position.distance_to(mpos)
		if dist_l < 110.0 and _mascot_bark_cd <= 0.0:
			padd_face.set_mood(CharacterFace.Mood.HAPPY, 1.2)
			padd_face.bark("Let's Paddle!")
			_mascot_bark_cd = 3.5

	if lin_face != null and is_instance_valid(lin_face):
		lin_face.look_at_point(lin_face.global_position, mpos)
		var dist_r := lin_face.global_position.distance_to(mpos)
		if dist_r < 110.0 and _mascot_bark_cd <= 0.0:
			lin_face.set_mood(CharacterFace.Mood.SMUG, 1.2)
			lin_face.bark("You ready?")
			_mascot_bark_cd = 3.5

func _animate_title_breathing(_delta: float) -> void:
	if title_header == null or current_state != MenuState.MAIN:
		return
	var t := Time.get_ticks_msec() * 0.001
	var title_lbl := _find_node_by_name(self, "TitleText") as Label
	if title_lbl != null:
		title_lbl.scale = Vector2.ONE * (1.0 + sin(t * 1.8) * 0.02)

func _switch_state(new_state: MenuState) -> void:
	current_state = new_state

	main_menu_panel.visible = (current_state == MenuState.MAIN)
	top_toolbar.visible = (current_state == MenuState.MAIN or current_state == MenuState.SANDBOX_LAB)
	gauntlet_dossier_modal.visible = (current_state == MenuState.GAUNTLET_DOSSIER)
	sandbox_hud.visible = (current_state == MenuState.SANDBOX_LAB)
	codex_modal.visible = (current_state == MenuState.CODEX)
	settings_modal.visible = (current_state == MenuState.SETTINGS)
	pause_overlay.visible = (current_state == MenuState.IN_GAME_PAUSE)

	if current_state == MenuState.GAUNTLET_DOSSIER:
		_select_dossier_stage(dossier_selected_stage)

	if current_state == MenuState.MAIN:
		_punch_container(main_menu_panel)
	elif current_state == MenuState.GAUNTLET_DOSSIER:
		_punch_container(gauntlet_dossier_modal)
	elif current_state == MenuState.CODEX:
		_punch_container(codex_modal)
	elif current_state == MenuState.SETTINGS:
		_punch_container(settings_modal)
	elif current_state == MenuState.IN_GAME_PAUSE:
		_punch_container(pause_overlay)

func _select_dossier_stage(stage_idx: int) -> void:
	dossier_selected_stage = stage_idx
	var stages: Array = TournamentManager.STAGES
	if stage_idx < 0 or stage_idx >= stages.size():
		return

	var info: Dictionary = stages[stage_idx]
	var stage_num_lbl := _find_node_by_name(self, "StageNumber") as Label
	var boss_name_lbl := _find_node_by_name(self, "BossName") as Label
	var quote_lbl := _find_node_by_name(self, "BossQuote") as Label
	var desc_lbl := _find_node_by_name(self, "BossDescription") as Label
	var portrait_glow := _find_node_by_name(self, "PortraitGlow") as ColorRect
	var badge_hazard := _find_node_by_name(self, "HazardBadge") as Label

	var col: Color = info.get("color", Color.WHITE)
	if stage_num_lbl != null: stage_num_lbl.text = "%s  ·  %s" % [info.get("title", ""), info.get("subtitle", "")]
	if boss_name_lbl != null:
		boss_name_lbl.text = info.get("boss_name", "")
		boss_name_lbl.add_theme_color_override("font_color", col)
	if quote_lbl != null: quote_lbl.text = "\"%s\"" % info.get("quote", "")
	if desc_lbl != null: desc_lbl.text = info.get("description", "")
	if portrait_glow != null: portrait_glow.color = col * 0.7
	if badge_hazard != null:
		var shape_name := "STANDARD"
		match info.get("shape", 0):
			1: shape_name = "SCOOP HYDRO"
			2: shape_name = "WEDGE DEFLECT"
			3: shape_name = "TWIN FORK"
			4: shape_name = "FORTRESS BARRICADE"
		badge_hazard.text = "TRAIT: %s  |  BRICKS: %s  |  TWINS: %s" % [shape_name, "YES" if info.get("bricks", false) else "NO", "YES" if info.get("twin", false) else "NO"]
		badge_hazard.add_theme_color_override("font_color", col)

	if audio_mgr != null: audio_mgr.trigger_sting(380.0 + float(stage_idx) * 80.0, 0.4)
	if fluid_sim != null:
		fluid_sim.inject_vortex(Vector2(960, 540), 5.0, 200.0, col)

func _select_tool(tool_mode: ToolMode) -> void:
	current_tool = tool_mode
	if audio_mgr != null: audio_mgr.trigger_sandbox_tool()
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
	var palette_btn := _find_node_by_name(self, "PaletteBtn") as Button
	if palette_btn != null:
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
	quick_banner.scale = Vector2(1.15, 1.15)
	var tw := create_tween()
	tw.tween_property(quick_banner, "scale", Vector2.ONE, 0.12)
	tw.tween_interval(0.9)
	tw.tween_property(quick_banner, "modulate:a", 0.0, 0.3)

# Button Actions
func _on_arcade_clicked() -> void:
	var diff_opt := _find_node_by_name(self, "DiffOption") as OptionButton
	var diff := 1.0
	if diff_opt != null:
		match diff_opt.selected:
			0: diff = 0.75 # Casual
			1: diff = 1.0  # Balanced
			2: diff = 1.35 # Veteran
			3: diff = 1.8  # Chaos God
	_switch_state(MenuState.HIDDEN)
	arcade_requested.emit(diff)
	if game_mgr != null:
		game_mgr.start_arcade_match(diff)

func _on_gauntlet_clicked() -> void:
	_switch_state(MenuState.GAUNTLET_DOSSIER)

func _on_launch_gauntlet_from_dossier() -> void:
	_switch_state(MenuState.HIDDEN)
	gauntlet_requested.emit()
	if game_mgr != null:
		game_mgr.start_gauntlet_match()

func _on_pvp_clicked() -> void:
	_switch_state(MenuState.HIDDEN)
	pvp_requested.emit()
	if game_mgr != null:
		game_mgr.start_pvp_match()

func _on_zen_clicked() -> void:
	_switch_state(MenuState.SANDBOX_LAB)
	zen_requested.emit()
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
	if audio_mgr != null:
		audio_mgr._music_on = not audio_mgr._music_on
		if audio_mgr._music != null:
			audio_mgr._music.stream_paused = not audio_mgr._music_on
		var btn := _find_node_by_name(self, "SoundBtn") as Button
		if btn != null:
			btn.text = "SFX/BGM: %s" % ("ON" if audio_mgr._music_on else "MUTED")
		_show_banner("AUDIO: %s" % ("ON" if audio_mgr._music_on else "MUTED"))

func _on_toggle_fullscreen_clicked() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_show_banner("WINDOWED")
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_show_banner("FULLSCREEN")

func _on_sandbox_spawn_bricks() -> void:
	if game_mgr != null and game_mgr.chaos != null:
		var bmat := game_mgr.get_parent().get_node_or_null("BrickMatrix") as BrickMatrix
		if bmat != null:
			bmat.spawn_firewall(3, 7)
			_show_banner("SPAWNED BRICK WALL")

func _on_quit_clicked() -> void:
	get_tree().quit()

# Pause Overlay Handlers
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

# Game Manager Signal Callbacks
func _on_game_paused(is_paused: bool) -> void:
	if is_paused:
		_switch_state(MenuState.IN_GAME_PAUSE)
	else:
		if current_state == MenuState.IN_GAME_PAUSE:
			_switch_state(MenuState.HIDDEN)

func _on_menu_entered() -> void:
	_switch_state(MenuState.MAIN)

func _on_match_started() -> void:
	if current_state != MenuState.SANDBOX_LAB:
		_switch_state(MenuState.HIDDEN)

# UI Micro-animations & Juice
func _punch_button(btn: Button) -> void:
	btn.pivot_offset = btn.size * 0.5
	btn.scale = Vector2(0.92, 0.92)
	var tw := create_tween()
	tw.tween_property(btn, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _hover_button(btn: Button) -> void:
	btn.pivot_offset = btn.size * 0.5
	var tw := create_tween()
	tw.tween_property(btn, "scale", Vector2(1.04, 1.04), 0.1)

func _punch_container(ctrl: Control) -> void:
	ctrl.modulate.a = 0.0
	ctrl.scale = Vector2(0.96, 0.96)
	ctrl.pivot_offset = Vector2(960, 540)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ctrl, "modulate:a", 1.0, 0.15)
	tw.tween_property(ctrl, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
