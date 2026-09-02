class_name ArenaAmbience
extends Node2D

## Ambient arena life: drifting motes that follow a gentle curl field, a hex
## lattice on the walls, and a dashed centre line that breathes with the
## serve beats and the rally. Deliberately quiet; it dims further while the
## ball is live so it never competes with play.

const ARENA_W := 1920.0
const ARENA_H := 1080.0

var _motes: GPUParticles2D
var _mote_mat: ShaderMaterial
var _wall_top: ColorRect
var _wall_bottom: ColorRect
var _centre: ColorRect
var _centre_mat: ShaderMaterial
var _ball: Ball
var _game_mgr: GameManager
var _bound := false

var _breath := 0.0
var _energy := 0.0
var _wall_energy := 0.0
var _life := 1.0
var _hit_top := 0.0
var _hit_bottom := 0.0
var _hit_top_x := 0.5
var _hit_bottom_x := 0.5
var _rally := 0

func _ready() -> void:
	z_index = 4
	_wall_top = get_node_or_null("../BoundaryWalls/WallTopVisual") as ColorRect
	_wall_bottom = get_node_or_null("../BoundaryWalls/WallBottomVisual") as ColorRect
	_centre = get_node_or_null("../CenterLine") as ColorRect
	if _centre != null and _centre.material is ShaderMaterial:
		_centre_mat = _centre.material
	_build_motes()
	call_deferred("_bind")

func _build_motes() -> void:
	_motes = GPUParticles2D.new()
	_motes.name = "Motes"
	_motes.position = Vector2(ARENA_W * 0.5, ARENA_H * 0.5)
	_motes.amount = 96
	_motes.lifetime = 14.0
	_motes.preprocess = 8.0
	_motes.randomness = 0.6
	_motes.explosiveness = 0.0
	_motes.local_coords = true
	_motes.visibility_rect = Rect2(-ARENA_W * 0.5, -ARENA_H * 0.5, ARENA_W, ARENA_H)

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(ARENA_W * 0.48, ARENA_H * 0.44, 0.0)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 180.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 16.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = 0.0
	pm.damping_max = 0.0
	pm.scale_min = 0.35
	pm.scale_max = 1.0
	# Gentle curl field: turbulence in 4.x gives the motes an eddying drift.
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.9
	pm.turbulence_noise_scale = 3.5
	pm.turbulence_noise_speed = Vector3(0.05, 0.03, 0.0)
	pm.turbulence_noise_speed_random = 0.2
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.14
	# Fade in and out over the life so nothing pops.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.15, 1.0))
	curve.add_point(Vector2(0.85, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.alpha_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.55, 0.45, 1.0, 0.9))
	grad.set_color(1, Color(0.35, 0.9, 1.0, 0.9))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_initial_ramp = gt
	_motes.process_material = pm

	# A small radial sprite gives each mote a 12 px quad; scale_min/max above
	# then spreads sizes between ~4 and 12 px.
	var sprite := GradientTexture2D.new()
	sprite.width = 12
	sprite.height = 12
	sprite.fill = GradientTexture2D.FILL_RADIAL
	sprite.fill_from = Vector2(0.5, 0.5)
	sprite.fill_to = Vector2(1.0, 0.5)
	var sg := Gradient.new()
	sg.set_color(0, Color.WHITE)
	sg.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	sprite.gradient = sg
	_motes.texture = sprite
	_mote_mat = ShaderMaterial.new()
	_mote_mat.shader = load("res://shaders/vfx/mote.gdshader")
	_motes.material = _mote_mat
	add_child(_motes)

func _bind() -> void:
	if _bound:
		return
	var main := get_parent().get_parent() if get_parent() != null else null
	if main == null:
		return
	_ball = main.get_node_or_null("Ball") as Ball
	_game_mgr = main.get_node_or_null("GameManager") as GameManager
	if _ball == null:
		_ball = get_tree().get_first_node_in_group("cymatics_balls") as Ball
	if _game_mgr == null:
		return
	_bound = true
	_game_mgr.rally_updated.connect(func(hits: int):
		if hits > _rally:
			_breath = maxf(_breath, 0.35)
		_rally = hits
	)
	_game_mgr.serving_started.connect(func(_id: int):
		_rally = 0
		_breath = maxf(_breath, 0.5)
	)
	if _game_mgr.has_signal("serve_ready_beat"):
		_game_mgr.connect("serve_ready_beat", _on_serve_beat)
	if _ball != null:
		_ball.hit_wall.connect(_on_wall_hit)

func _on_serve_beat(beat: int) -> void:
	_breath = clampf(0.55 + 0.15 * float(beat), 0.0, 1.0)

func _on_wall_hit(pos: Vector2, hit_speed: float) -> void:
	var s := clampf(hit_speed / 1600.0, 0.3, 1.0)
	if pos.y < ARENA_H * 0.5:
		_hit_top = maxf(_hit_top, s)
		_hit_top_x = clampf(pos.x / ARENA_W, 0.0, 1.0)
	else:
		_hit_bottom = maxf(_hit_bottom, s)
		_hit_bottom_x = clampf(pos.x / ARENA_W, 0.0, 1.0)

func _process(delta: float) -> void:
	if not _bound:
		_bind()
	var live := false
	if _bound and _ball != null:
		live = _game_mgr.current_state == GameManager.State.PLAYING and not _ball.is_scored and not _ball.is_serving
	var want_life := 0.4 if live else 1.0
	_life = move_toward(_life, want_life, delta * 0.8)

	var want_energy := clampf(float(_rally) / 12.0, 0.0, 1.0) if live else 0.0
	_energy = move_toward(_energy, want_energy, delta * 0.6)
	_breath = move_toward(_breath, 0.0, delta * 1.4)
	_hit_top = move_toward(_hit_top, 0.0, delta * 2.2)
	_hit_bottom = move_toward(_hit_bottom, 0.0, delta * 2.2)
	_wall_energy = lerpf(_wall_energy, _energy, clampf(delta * 2.0, 0.0, 1.0))

	if _mote_mat != null:
		_mote_mat.set_shader_parameter("brightness", 0.55 * _life + 0.25)
	if _centre_mat != null:
		_centre_mat.set_shader_parameter("breath", _breath)
		_centre_mat.set_shader_parameter("energy", _energy)
	_set_wall(_wall_top, _hit_top, _hit_top_x)
	_set_wall(_wall_bottom, _hit_bottom, _hit_bottom_x)

func _set_wall(rect: ColorRect, hit: float, hit_x: float) -> void:
	if rect == null or not (rect.material is ShaderMaterial):
		return
	var m: ShaderMaterial = rect.material
	m.set_shader_parameter("energy", _wall_energy)
	m.set_shader_parameter("hit", hit)
	m.set_shader_parameter("hit_x", hit_x)
