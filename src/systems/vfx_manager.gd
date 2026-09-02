class_name VFXManager
extends Node2D

signal flash_requested(color: Color, alpha: float, duration: float)

@export var camera: Camera2D

## Halves shake / zoom punch and particle counts, softens flashes and hit-stop.
## Pushed by MenuManager and re-read from Settings on `changed`.
var reduce_motion := false
## 0..1 user slider on top of `reduce_motion`. 0 disables camera shake entirely.
var shake_scale := 1.0
var time_ctrl: TimeController
## Owned here so no edit to main.gd is needed; GameManager binds it to a match.
var haptics: Haptics

const MAX_SHAKE_OFFSET := 34.0
const MAX_SHAKE_ROT := 0.028
const TRAUMA_DECAY := 2.1 # 1.0 -> 0.0 in ~0.48 s
## Screen-space rings each copy the back buffer; cap how many can be live at once.
const MAX_LIVE_RINGS := 6
const GOAL_SLOWMO_SCALE := 0.3
const GOAL_SLOWMO_TIME := 0.45
## Photosensitivity guard: at most this many full-screen flashes per second,
## so a brick volley or a multiball scramble cannot strobe.
const MAX_FLASHES_PER_SEC := 3
const FLASH_WINDOW := 1.0

var trauma := 0.0
var _kick := Vector2.ZERO
var _hitstop_id := 0
var _shock_shader: Shader
var _burst_shader: Shader
var _star_shader: Shader
var _cone_shader: Shader
var _goal_wall_shader: Shader
var _zoom_punch := 0.0
var _noise := FastNoiseLite.new()
var _noise_t := 0.0
var _live_rings := 0

# Goal focus: camera push toward `pos` plus a brief zoom-out. Read by Main._update_camera.
var _goal_focus_pos := Vector2(960, 540)
var _goal_focus_t := 0.0
var _goal_focus_total := 0.0
## Rolling window of recent flash timestamps (msec) for the rate cap.
var _flash_times: Array[int] = []
var _settings_node: Node

# Generated particle textures, shared across spawns.
var _streak_tex: Texture2D
var _shard_tex: Texture2D
var _chip_tex: Texture2D
var _dot_tex: Texture2D

func _ready() -> void:
	z_index = 20
	_shock_shader = load("res://shaders/vfx/shockwave_ring.gdshader")
	_burst_shader = load("res://shaders/vfx/hit_burst.gdshader")
	_star_shader = load("res://shaders/vfx/spark_star.gdshader")
	_cone_shader = load("res://shaders/vfx/blast_cone.gdshader")
	_goal_wall_shader = load("res://shaders/vfx/goal_line_pulse.gdshader")
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = 1337
	haptics = Haptics.new()
	haptics.name = "Haptics"
	add_child(haptics)
	_read_accessibility_settings()
	var s := _settings()
	if s != null and not s.is_connected("changed", _on_setting_changed):
		s.connect("changed", _on_setting_changed)

# --- Accessibility settings ----------------------------------------------------

func _settings() -> Node:
	if _settings_node == null or not is_instance_valid(_settings_node):
		_settings_node = get_node_or_null("/root/Settings")
	return _settings_node

func _setting(key: String, default: Variant) -> Variant:
	var s := _settings()
	if s == null:
		return default
	return s.call("get_value", key, default)

func _read_accessibility_settings() -> void:
	reduce_motion = bool(_setting("reduce_motion", false))
	shake_scale = clampf(float(_setting("screen_shake", 1.0)), 0.0, 1.0)

func _on_setting_changed(key: String, value: Variant) -> void:
	match key:
		"reduce_motion":
			reduce_motion = bool(value)
		"screen_shake":
			shake_scale = clampf(float(value), 0.0, 1.0)

## Combined motion multiplier: the user slider, halved again by reduce motion.
func _motion_scale() -> float:
	return shake_scale * (0.5 if reduce_motion else 1.0)

func _process(delta: float) -> void:
	# Shake and kick decay in real time so hit-stop does not freeze the camera mid-shake.
	var real_dt := clampf(delta / maxf(Engine.time_scale, 0.0001), 0.0, 0.1)
	if Engine.time_scale <= 0.0001:
		real_dt = 1.0 / 60.0
	trauma = maxf(trauma - real_dt * TRAUMA_DECAY, 0.0)
	_kick = _kick.lerp(Vector2.ZERO, clampf(real_dt * 10.0, 0.0, 1.0))
	_zoom_punch = move_toward(_zoom_punch, 0.0, real_dt * 2.4)
	_goal_focus_t = maxf(_goal_focus_t - real_dt, 0.0)
	_noise_t += real_dt * 28.0
	if camera == null:
		return
	var shake := trauma * trauma
	var motion_mult := _motion_scale()
	var jitter := Vector2.ZERO
	var rot := 0.0
	if shake > 0.001:
		jitter = Vector2(
			_noise.get_noise_2d(_noise_t, 0.0),
			_noise.get_noise_2d(0.0, _noise_t + 71.3)
		) * (MAX_SHAKE_OFFSET * shake * motion_mult)
		rot = _noise.get_noise_2d(_noise_t + 143.7, 37.1) * MAX_SHAKE_ROT * shake * motion_mult
	camera.offset = _kick * motion_mult + jitter
	camera.rotation = rot

func _make_tween() -> Tween:
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	return tw

func _count(n: int) -> int:
	return maxi(n / 2, 1) if reduce_motion else n

# --- Screen-space ring and additive burst -----------------------------------

func spawn_shockwave(pos: Vector2, color: Color, max_size: float = 350.0, duration: float = 0.35) -> void:
	if _live_rings >= MAX_LIVE_RINGS:
		return
	var sw := ColorRect.new()
	sw.z_index = 25
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sw.size = Vector2(max_size, max_size)
	sw.pivot_offset = sw.size * 0.5
	sw.global_position = pos - sw.pivot_offset
	var mat := ShaderMaterial.new()
	mat.shader = _shock_shader
	mat.set_shader_parameter("ring_color", color)
	mat.set_shader_parameter("progress", 0.0)
	sw.material = mat
	add_child(sw)
	_live_rings += 1
	var tween := _make_tween()
	tween.tween_method(func(val: float):
		if is_instance_valid(sw) and mat != null:
			mat.set_shader_parameter("progress", val)
	, 0.0, 1.0, duration)
	tween.tween_callback(func():
		_live_rings = maxi(_live_rings - 1, 0)
		if is_instance_valid(sw):
			sw.queue_free()
	)

## Additive diffraction burst. `dir` + `elongation` > 1 stretch the burst along
## the ball's outgoing direction so a paddle hit reads as a directional smear.
func spawn_hit_burst(pos: Vector2, color: Color, scale_multiplier: float = 1.0, dir: Vector2 = Vector2.ZERO, elongation: float = 1.0, duration: float = 0.24) -> void:
	var burst := ColorRect.new()
	burst.z_index = 26
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base_size := 240.0 * scale_multiplier
	burst.size = Vector2(base_size, base_size)
	burst.pivot_offset = burst.size * 0.5
	burst.global_position = pos - burst.pivot_offset
	if elongation > 1.001 and dir.length_squared() > 0.0001:
		burst.rotation = dir.angle()
		burst.scale = Vector2(elongation, 1.0 / sqrt(elongation))
	var mat := ShaderMaterial.new()
	mat.shader = _burst_shader
	mat.set_shader_parameter("star_color", color)
	mat.set_shader_parameter("intensity", 3.2 * scale_multiplier)
	mat.set_shader_parameter("progress", 0.0)
	burst.material = mat
	add_child(burst)
	var tween := _make_tween()
	tween.tween_method(func(val: float):
		if is_instance_valid(burst) and mat != null:
			mat.set_shader_parameter("progress", val)
	, 0.0, 1.0, duration)
	tween.tween_callback(burst.queue_free)

## Regular paddle hit: small burst smeared along the outgoing direction and a short ring.
func spawn_paddle_hit(pos: Vector2, out_dir: Vector2, color: Color, strength: float = 1.0) -> void:
	spawn_hit_burst(pos, color, 1.1 + strength * 0.5, out_dir, 2.4, 0.2)
	spawn_shockwave(pos, Color(color.r, color.g, color.b, 0.8), 170.0 + strength * 60.0, 0.18)

# --- Perfect parry -------------------------------------------------------------

func _make_star(pos: Vector2, size: Vector2, tint: Color, core: Color, points: int, sharp: float) -> Array:
	var star := ColorRect.new()
	star.z_index = 27
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star.size = size
	star.pivot_offset = size * 0.5
	star.global_position = pos - star.pivot_offset
	var mat := ShaderMaterial.new()
	mat.shader = _star_shader
	mat.set_shader_parameter("points", points)
	mat.set_shader_parameter("sharpness", sharp)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("core_tint", core)
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("spin", 0.0)
	star.material = mat
	add_child(star)
	return [star, mat]

## Four-point anamorphic star, rotating, plus a ring of small stars flung outward.
func spawn_parry_star(pos: Vector2, color: Color, out_dir: Vector2 = Vector2.RIGHT) -> void:
	var hot := Color(color.r * 1.6 + 0.8, color.g * 1.6 + 0.8, color.b * 1.6 + 0.8)
	var core := Color(2.6, 2.5, 2.2)
	var main: Array = _make_star(pos, Vector2(520.0, 240.0), hot, core, 4, 22.0)
	var star: ColorRect = main[0]
	var mat: ShaderMaterial = main[1]
	star.rotation = out_dir.angle() * 0.25
	var tween := _make_tween()
	tween.set_parallel(true)
	tween.tween_method(func(val: float):
		if is_instance_valid(star) and mat != null:
			mat.set_shader_parameter("progress", val)
			mat.set_shader_parameter("spin", val * 0.9)
	, 0.0, 1.0, 0.35)
	tween.tween_property(star, "scale", Vector2(1.35, 0.85), 0.35).from(Vector2(0.35, 1.2)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.chain().tween_callback(star.queue_free)

	var n := _count(8)
	var base_ang := randf() * TAU
	for i in n:
		var ang := base_ang + TAU * float(i) / float(n)
		var fling := Vector2.from_angle(ang)
		var arr: Array = _make_star(pos, Vector2(64.0, 64.0), hot, core, 4, 14.0)
		var s: ColorRect = arr[0]
		var m: ShaderMaterial = arr[1]
		var dist := 90.0 + randf() * 70.0 + maxf(fling.dot(out_dir), 0.0) * 60.0
		var tw := _make_tween()
		tw.set_parallel(true)
		tw.tween_property(s, "global_position", s.global_position + fling * dist, 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
		tw.tween_property(s, "rotation", randf_range(-2.5, 2.5), 0.32)
		tw.tween_property(s, "scale", Vector2(0.25, 0.25), 0.32).set_ease(Tween.EASE_IN)
		tw.tween_method(func(val: float):
			if is_instance_valid(s) and m != null:
				m.set_shader_parameter("progress", val)
		, 0.0, 1.0, 0.32)
		tw.chain().tween_callback(s.queue_free)
	flash_screen(Color.WHITE, 0.2, 0.08)
	spawn_shockwave(pos, Color(1.0, 1.0, 1.0, 0.9), 300.0, 0.26)

# --- Blast cone ----------------------------------------------------------------

## Team-coloured wedge that expands from the nozzle along `dir` and fades over 0.25 s.
func spawn_blast_cone(pos: Vector2, dir: Vector2, color: Color, power: float = 1.0) -> void:
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	var length := 420.0 * clampf(power, 0.5, 2.0)
	var width := 300.0 * clampf(power, 0.5, 2.0)
	var cone := ColorRect.new()
	cone.z_index = 26
	cone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cone.size = Vector2(length, width)
	cone.pivot_offset = Vector2(0.0, width * 0.5)
	cone.global_position = pos - cone.pivot_offset
	cone.rotation = dir.angle()
	var mat := ShaderMaterial.new()
	mat.shader = _cone_shader
	mat.set_shader_parameter("tint", color)
	mat.set_shader_parameter("intensity", 2.2 * clampf(power, 0.6, 1.6))
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("seed", randf() * 100.0)
	cone.material = mat
	add_child(cone)
	var tween := _make_tween()
	tween.tween_method(func(val: float):
		if is_instance_valid(cone) and mat != null:
			mat.set_shader_parameter("progress", val)
	, 0.0, 1.0, 0.28)
	tween.tween_callback(cone.queue_free)
	# A few hot embers ride the cone.
	_spawn_particles(pos, dir, color, _count(14), 0.3, 520.0 * power, 980.0 * power, 22.0, _dot_texture(), 0.35, 0.9, 6.0, 0.0, 26)

# --- Particles: goal debris, brick shards, chips -------------------------------

func _spawn_particles(pos: Vector2, dir: Vector2, color: Color, count: int, life: float,
		vel_min: float, vel_max: float, spread_deg: float, tex: Texture2D, scale_min: float, scale_max: float,
		damping: float, spin: float, z: int, align: bool = false, additive: bool = true, hot_start: bool = true) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.z_index = z
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(count, 1)
	p.lifetime = life
	p.local_coords = false
	p.texture = tex
	p.global_position = pos
	if additive:
		var cm := CanvasItemMaterial.new()
		cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = cm
	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.particle_flag_align_y = align
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 8.0
	var d := dir if dir.length_squared() > 0.0001 else Vector2.RIGHT
	mat.direction = Vector3(d.x, d.y, 0.0)
	mat.spread = spread_deg
	mat.initial_velocity_min = vel_min
	mat.initial_velocity_max = vel_max
	mat.gravity = Vector3.ZERO
	mat.damping_min = damping
	mat.damping_max = damping * 1.6
	mat.scale_min = scale_min
	mat.scale_max = scale_max
	if spin > 0.0:
		mat.angle_min = -180.0
		mat.angle_max = 180.0
		mat.angular_velocity_min = -spin
		mat.angular_velocity_max = spin
	var grad := Gradient.new()
	var hot := Color(2.4, 2.3, 2.0, 1.0) if hot_start else Color(color.r * 1.6, color.g * 1.6, color.b * 1.6, 1.0)
	grad.colors = PackedColorArray([
		hot,
		Color(color.r * 1.8, color.g * 1.8, color.b * 1.8, 1.0),
		Color(color.r, color.g, color.b, 0.6),
		Color(color.r * 0.6, color.g * 0.6, color.b * 0.6, 0.0)
	])
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	ramp.use_hdr = true
	mat.color_ramp = ramp
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.6, 0.75))
	curve.add_point(Vector2(1.0, 0.1))
	var ct := CurveTexture.new()
	ct.curve = curve
	mat.scale_curve = ct
	p.process_material = mat
	add_child(p)
	p.emitting = true
	# Real-time cleanup; `finished` never fires on renderers without particles.
	var tree := get_tree()
	if tree != null:
		var timer := tree.create_timer(life * 1.3 + 0.1, false, false, true)
		timer.timeout.connect(func():
			if is_instance_valid(p):
				p.queue_free()
		)
	return p

## Ball debris cone at a goal: 40-70 additive streaks along the ball's velocity.
func spawn_goal_shatter(pos: Vector2, vel: Vector2, color: Color) -> void:
	var dir := vel.normalized() if vel.length_squared() > 1.0 else Vector2.RIGHT
	var speed := clampf(vel.length(), 700.0, 2100.0)
	# The ball breaks against the goal wall: debris splashes back into the court
	# along the reflected velocity, so the cone stays on screen.
	var origin := pos
	if pos.x > 1700.0 and dir.x > 0.0:
		dir.x = -dir.x
		origin.x = minf(pos.x, 1880.0)
	elif pos.x < 220.0 and dir.x < 0.0:
		dir.x = -dir.x
		origin.x = maxf(pos.x, 40.0)
	var n := _count(40 + int((speed - 700.0) / 1400.0 * 30.0))
	# Long streaks along the splash path, short hot chunks that lag behind.
	_spawn_particles(origin, dir, color, n, 0.75, speed * 0.45, speed * 1.2, 38.0, _streak_texture(), 0.5, 1.4, 4.0, 0.0, 27, true)
	_spawn_particles(origin, dir, Color(1.0, 0.85, 0.45), _count(18), 0.6, speed * 0.15, speed * 0.6, 80.0, _dot_texture(), 0.4, 1.1, 5.0, 0.0, 27)

## Brick shatter: 12-20 spinning shard quads with drag and no gravity.
func spawn_brick_shards(pos: Vector2, size: Vector2, color: Color, count: int = 16) -> void:
	var n := _count(clampi(count, 12, 20))
	var p := _spawn_particles(pos, Vector2.RIGHT, color, n, 0.8, 220.0, 620.0, 180.0, _shard_texture(), 0.55, 1.35, 3.5, 14.0, 9, false, false, false)
	if p.process_material is ParticleProcessMaterial:
		var m := p.process_material as ParticleProcessMaterial
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		m.emission_box_extents = Vector3(size.x * 0.45, size.y * 0.45, 1.0)
	spawn_hit_burst(pos, Color(1.0, 1.0, 1.0), 1.6, Vector2.RIGHT, 1.6, 0.2)

## Brick hit: angular chips off the struck face plus a crack flash pressed against it.
func spawn_brick_chips(pos: Vector2, normal: Vector2, color: Color) -> void:
	var nrm := normal.normalized() if normal.length_squared() > 0.0001 else Vector2.UP
	_spawn_particles(pos + nrm * 6.0, nrm, color, _count(9), 0.42, 240.0, 520.0, 55.0, _chip_texture(), 0.4, 0.9, 5.0, 18.0, 9, false, false, false)
	# Crack flash: a thin bright line along the face (perpendicular to the normal).
	var along := Vector2(-nrm.y, nrm.x)
	spawn_hit_burst(pos + nrm * 4.0, Color(1.0, 1.0, 1.0), 0.7, along, 3.2, 0.14)
	spawn_shockwave(pos, Color(color.r, color.g, color.b, 0.7), 140.0, 0.18)

# --- Wall bounce -----------------------------------------------------------------

## Flattened burst pressed against the wall plus a thin ripple line along it.
func spawn_wall_hit(contact: Vector2, normal: Vector2, t: float) -> void:
	var nrm := normal.normalized() if normal.length_squared() > 0.0001 else Vector2.UP
	var along := Vector2(-nrm.y, nrm.x)
	spawn_hit_burst(contact + nrm * 10.0, Color(1.0, 0.98, 0.9), 0.55 + t * 0.6, along, 2.8, 0.16)
	if t > 0.35:
		spawn_shockwave(contact, Color(1.0, 1.0, 1.0, 0.4 + 0.4 * t), 110.0 + 120.0 * t, 0.18)
	var half := 90.0 + t * 120.0
	var line := Line2D.new()
	line.z_index = 24
	line.width = 4.0 + t * 4.0
	line.antialiased = true
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 0.9, 0.5, 0.0),
		Color(1.8, 1.7, 1.4, 1.0),
		Color(1.0, 0.9, 0.5, 0.0)
	])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	line.gradient = grad
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	line.material = cm
	var wall := contact + nrm * 2.0
	line.add_point(wall - along * half)
	line.add_point(wall)
	line.add_point(wall + along * half)
	add_child(line)
	var tween := _make_tween()
	tween.set_parallel(true)
	tween.tween_property(line, "modulate:a", 0.0, 0.2)
	tween.tween_property(line, "width", line.width * 0.3, 0.2)
	tween.chain().tween_callback(line.queue_free)

# --- Lost-ball pulse -------------------------------------------------------------

## Soft expanding ring from the ball during Cymatic Lock / overdrive. Yields to busier rings.
func spawn_lock_pulse(pos: Vector2, color: Color, alpha: float = 0.35, size: float = 260.0) -> void:
	if _live_rings >= MAX_LIVE_RINGS - 2:
		return
	spawn_shockwave(pos, Color(color.r, color.g, color.b, alpha), size, 0.5)

# --- Goal theatre ------------------------------------------------------------------

## Camera push toward `pos` with a brief zoom-out. Main._update_camera reads `goal_focus_*`.
func request_goal_focus(pos: Vector2, duration: float = 0.5) -> void:
	_goal_focus_pos = pos
	_goal_focus_total = maxf(duration, 0.05)
	_goal_focus_t = _goal_focus_total

## 0..1 envelope: fast in, slow out. 0 when idle.
func goal_focus_weight() -> float:
	if _goal_focus_t <= 0.0 or _goal_focus_total <= 0.0:
		return 0.0
	var p := 1.0 - _goal_focus_t / _goal_focus_total
	var w := clampf(minf(p / 0.18, 1.0) * minf((1.0 - p) / 0.45, 1.0), 0.0, 1.0)
	# Reduce motion halves the camera push and zoom-out; the slow-motion beat
	# and the goal VFX stay, so the moment still reads.
	return w * (0.5 if reduce_motion else 1.0)

func goal_focus_pos() -> Vector2:
	return _goal_focus_pos

## Additive energy sheet on the goal wall with a ripple spreading from the hit height.
func spawn_goal_wall_pulse(side: int, hit_y: float, color: Color) -> void:
	var w := 220.0
	var wall := ColorRect.new()
	wall.z_index = 25
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wall.size = Vector2(w, 1000.0)
	wall.global_position = Vector2(0.0 if side == 0 else 1920.0 - w, 40.0)
	var mat := ShaderMaterial.new()
	mat.shader = _goal_wall_shader
	mat.set_shader_parameter("tint", color)
	mat.set_shader_parameter("side", side)
	mat.set_shader_parameter("hit_v", clampf((hit_y - 40.0) / 1000.0, 0.0, 1.0))
	mat.set_shader_parameter("progress", 0.0)
	wall.material = mat
	add_child(wall)
	var tween := _make_tween()
	tween.tween_method(func(val: float):
		if is_instance_valid(wall) and mat != null:
			mat.set_shader_parameter("progress", val)
	, 0.0, 1.0, 0.55)
	tween.tween_callback(wall.queue_free)

## Goal: 2-frame freeze, then 0.3x slow-mo while the ball shatters into a debris
## cone, the goal line rings and pulses, and the camera pushes toward the goal.
## `ball` must already be scored (velocity kept in `ball.goal_velocity`).
func play_goal_theatre(ball: Node, side: int, color: Color) -> void:
	_goal_sequence(ball, side, color)

func _goal_sequence(ball: Node, side: int, color: Color) -> void:
	var tree := get_tree()
	if tree == null:
		return
	if time_ctrl != null:
		time_ctrl.push(&"goal", 0.0, TimeController.PRIO_HITSTOP - 1)
	await tree.process_frame
	await tree.process_frame
	if time_ctrl != null:
		time_ctrl.push(&"goal", GOAL_SLOWMO_SCALE, TimeController.PRIO_HITSTOP - 1)
	var pos := Vector2(40.0 if side == 0 else 1880.0, 540.0)
	var vel := Vector2.LEFT if side == 0 else Vector2.RIGHT
	if is_instance_valid(ball):
		pos = ball.global_position
		if ball.has_method("shatter"):
			vel = ball.get("goal_velocity")
			ball.call("shatter", color)
	var line_pos := Vector2(0.0 if side == 0 else 1920.0, pos.y)
	spawn_shockwave(line_pos, color, 900.0, 0.7)
	spawn_goal_wall_pulse(side, pos.y, color)
	spawn_hit_burst(line_pos, color, 2.4, vel, 1.8, 0.3)
	request_goal_focus(line_pos, 0.5)
	add_trauma(0.55 * maxf(_motion_scale(), 0.35), 0.8)
	flash_screen(color, 0.24, 0.2)
	var timer := tree.create_timer(GOAL_SLOWMO_TIME, false, false, true)
	await timer.timeout
	if time_ctrl != null:
		time_ctrl.pop(&"goal")

# --- Generated textures --------------------------------------------------------------

func _dot_texture() -> Texture2D:
	if _dot_tex != null:
		return _dot_tex
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	for y in 24:
		for x in 24:
			var d := Vector2(x - 11.5, y - 11.5).length() / 12.0
			img.set_pixel(x, y, Color(1, 1, 1, exp(-d * d * 7.0)))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex

## Vertical streak with a hot core; used with align_y so it lies along velocity.
func _streak_texture() -> Texture2D:
	if _streak_tex != null:
		return _streak_tex
	var w := 16
	var h := 56
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var ax := absf(x - (w - 1) * 0.5) / (w * 0.5)
			var ay := absf(y - (h - 1) * 0.5) / (h * 0.5)
			var a := exp(-ax * ax * 6.0) * exp(-pow(ay, 4.0) * 3.0)
			var head := exp(-pow((y - 10.0) / 8.0, 2.0))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a * (0.55 + head * 0.6), 0.0, 1.0)))
	_streak_tex = ImageTexture.create_from_image(img)
	return _streak_tex

static func _inside_poly(p: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var j := poly.size() - 1
	for i in poly.size():
		var a := poly[i]
		var b := poly[j]
		if (a.y > p.y) != (b.y > p.y):
			var x := a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
			if p.x < x:
				inside = not inside
		j = i
	return inside

## Irregular quad shard, opaque body with a brighter edge.
func _shard_texture() -> Texture2D:
	if _shard_tex != null:
		return _shard_tex
	var s := 28
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var poly := PackedVector2Array([Vector2(4, 9), Vector2(21, 3), Vector2(25, 18), Vector2(10, 25)])
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5)
			if _inside_poly(p, poly):
				var edge := 1.0
				for k in poly.size():
					var a := poly[k]
					var b := poly[(k + 1) % poly.size()]
					var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
					edge = minf(edge, d / 3.0)
				var v := 0.75 + (1.0 - clampf(edge, 0.0, 1.0)) * 0.6
				img.set_pixel(x, y, Color(v, v, v, 1.0))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	_shard_tex = ImageTexture.create_from_image(img)
	return _shard_tex

## Small triangular chip.
func _chip_texture() -> Texture2D:
	if _chip_tex != null:
		return _chip_tex
	var s := 12
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var poly := PackedVector2Array([Vector2(1, 10), Vector2(6, 1), Vector2(11, 9)])
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, 1.0) if _inside_poly(p, poly) else Color(0, 0, 0, 0))
	_chip_tex = ImageTexture.create_from_image(img)
	return _chip_tex

# --- Trajectory, camera, time --------------------------------------------------------

func spawn_trajectory(origin: Vector2, vel: Vector2, color: Color) -> void:
	var line := Line2D.new()
	line.z_index = 24
	line.width = 6.0
	line.default_color = Color(color.r, color.g, color.b, 0.85)
	line.antialiased = true
	var p := origin
	var v := vel
	for i in range(18):
		line.add_point(p)
		p += v * 0.018
		if p.y < 54.0:
			p.y = 54.0
			v.y = absf(v.y)
		elif p.y > 1026.0:
			p.y = 1026.0
			v.y = -absf(v.y)
	add_child(line)
	var tween := _make_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.45)
	tween.tween_callback(line.queue_free)

## Adds trauma (0..1). Each call is capped so one source cannot saturate the shake alone.
func add_trauma(amount: float, per_source_cap: float = 0.75) -> void:
	var add := maxf(amount, 0.0)
	trauma = clampf(maxf(trauma, minf(trauma + add, maxf(per_source_cap, trauma))), 0.0, 1.0)

## Directional kick plus trauma shake. `strength` ~0.2 (wall tap) .. 2.2 (resonance).
func apply_camera_kick(direction: Vector2, strength: float) -> void:
	add_trauma(clampf(strength * 0.26, 0.0, 0.6), clampf(0.3 + strength * 0.25, 0.3, 0.9))
	if direction.length() > 0.01:
		_kick += direction.normalized() * (strength * 22.0 * _motion_scale())
		_kick = _kick.limit_length(42.0)
	_zoom_punch = maxf(_zoom_punch, strength * 0.045 * _motion_scale())

func add_kick(direction: Vector2, strength: float) -> void:
	apply_camera_kick(direction, strength)

func apply_hit_stop(real_duration: float, scale: float = 0.12) -> void:
	if real_duration <= 0.001:
		return
	var tree := get_tree()
	if tree == null:
		return
	_hitstop_id += 1
	var id := _hitstop_id
	var s := clampf(scale, 0.04, 1.0)
	if reduce_motion:
		# Halve the freeze and keep time closer to normal: the read stays, the
		# lurch does not.
		real_duration *= 0.5
		s = clampf(lerpf(s, 1.0, 0.5), 0.04, 1.0)
	if time_ctrl != null:
		var existing := time_ctrl.source_scale(&"hitstop")
		if existing >= 0.0:
			s = minf(s, existing)
		time_ctrl.push(&"hitstop", s, TimeController.PRIO_HITSTOP)
	else:
		Engine.time_scale = minf(Engine.time_scale, s)
	# Real-time timer, paused with the tree; only the most recent hit-stop releases.
	var timer := tree.create_timer(real_duration, false, false, true)
	timer.timeout.connect(func():
		if id != _hitstop_id:
			return
		if time_ctrl != null:
			time_ctrl.pop(&"hitstop")
		else:
			Engine.time_scale = 1.0
	)

## Full-screen flash. Reduce motion keeps the cue but drops it to a soft, longer
## wash instead of a hard pop, and the rate cap drops anything past
## `MAX_FLASHES_PER_SEC` so repeated impacts cannot strobe.
func flash_screen(color: Color, alpha: float, duration: float) -> void:
	if not bool(_setting("screen_flash", true)):
		return
	var a := alpha
	var d := duration
	if reduce_motion:
		a *= 0.3
		d = maxf(d * 1.5, 0.2)
	if not _allow_flash():
		return
	flash_requested.emit(color, a, d)

func _allow_flash() -> bool:
	var now := Time.get_ticks_msec()
	var cutoff := now - int(FLASH_WINDOW * 1000.0)
	while not _flash_times.is_empty() and _flash_times[0] < cutoff:
		_flash_times.pop_front()
	if _flash_times.size() >= MAX_FLASHES_PER_SEC:
		return false
	_flash_times.append(now)
	return true

func get_zoom_punch() -> float:
	return _zoom_punch

func get_shake() -> float:
	return trauma * trauma
