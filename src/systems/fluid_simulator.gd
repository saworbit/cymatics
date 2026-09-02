class_name FluidSimulator
extends Node

## GPU Fluid Simulator for Godot 4.7.2+ using RenderingDevice compute shaders.
## Implements Jos Stam's Stable Fluids with Vorticity Confinement & Viscoelastic Filaments.
## Provides real-time continuous hydrodynamic force & curl coupling for ball flight and paddle combat.

signal step_completed(frame_index: int)

@export var grid_size := Vector2i(256, 144)
@export var jacobi_iterations := 20
@export var sub_steps := 3
@export var viscosity := 0.0001
@export var vorticity := 0.95
@export var surface_tension := 0.11
@export var dissipation := 0.995

var rd: RenderingDevice
var is_compute_ready := false

# Shaders
var shader_advect: RID
var shader_splat: RID
var shader_divergence: RID
var shader_pressure: RID
var shader_project: RID

# Pipelines
var pipe_advect: RID
var pipe_splat: RID
var pipe_divergence: RID
var pipe_pressure: RID
var pipe_project: RID

# Textures (Ping-Pong pairs)
var tex_velocity: Array[RID] = []
var tex_dye: Array[RID] = []
var tex_pressure: Array[RID] = []
var tex_divergence: RID

# Uniform Sets
var us_advect: Array[RID] = []
var us_splat: Array[RID] = []
var us_divergence: Array[RID] = []
var us_pressure: Array[RID] = []
var us_project: Array[RID] = []

var p_idx := 0
var frame_counter := 0

var display_texture: Texture2DRD
var _pending_splats: Array[Dictionary] = []
var _average_kinetic_energy := 200.0

# Active hydrodynamic emitters for continuous 2-way physics coupling
var _active_flow_nodes: Array[Dictionary] = []
var _ambient_t := 0.0

var _cpu_fallback := false
var _cpu_vel_x: PackedFloat32Array
var _cpu_vel_y: PackedFloat32Array
var _cpu_dye_r: PackedFloat32Array
var _cpu_dye_g: PackedFloat32Array
var _cpu_dye_b: PackedFloat32Array
var _cpu_byte_buffer: PackedByteArray
var _cpu_image: Image
var _cpu_texture: ImageTexture

func _ready() -> void:
	_init_simulation()

func _exit_tree() -> void:
	_cleanup_rids()

func _init_simulation() -> void:
	rd = RenderingServer.get_rendering_device()

	if rd != null:
		var success := _init_compute_pipeline()
		if success:
			is_compute_ready = true
			print("[FluidSimulator] Vulkan Compute Pipeline Initialized. Grid: ", grid_size)
			return

	print("[FluidSimulator] Warning: Initializing CPU Hybrid fallback.")
	_init_cpu_fallback()

func _init_compute_pipeline() -> bool:
	var format_vel := RDTextureFormat.new()
	format_vel.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	format_vel.width = grid_size.x
	format_vel.height = grid_size.y
	format_vel.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT

	var format_dye := RDTextureFormat.new()
	format_dye.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	format_dye.width = grid_size.x
	format_dye.height = grid_size.y
	format_dye.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	var view := RDTextureView.new()

	for i in range(2):
		var tv := rd.texture_create(format_vel, view)
		var td := rd.texture_create(format_dye, view)
		var tp := rd.texture_create(format_vel, view)
		if not (tv.is_valid() and td.is_valid() and tp.is_valid()):
			return false
		tex_velocity.append(tv)
		tex_dye.append(td)
		tex_pressure.append(tp)
	
	tex_divergence = rd.texture_create(format_vel, view)
	if not tex_divergence.is_valid():
		return false

	shader_advect = _load_compute_shader("res://shaders/compute/cymatics_advect.glsl")
	shader_splat = _load_compute_shader("res://shaders/compute/cymatics_splat.glsl")
	shader_divergence = _load_compute_shader("res://shaders/compute/cymatics_divergence.glsl")
	shader_pressure = _load_compute_shader("res://shaders/compute/cymatics_pressure.glsl")
	shader_project = _load_compute_shader("res://shaders/compute/cymatics_project.glsl")

	if not (shader_advect.is_valid() and shader_splat.is_valid() and shader_divergence.is_valid() and shader_pressure.is_valid() and shader_project.is_valid()):
		return false

	pipe_advect = rd.compute_pipeline_create(shader_advect)
	pipe_splat = rd.compute_pipeline_create(shader_splat)
	pipe_divergence = rd.compute_pipeline_create(shader_divergence)
	pipe_pressure = rd.compute_pipeline_create(shader_pressure)
	pipe_project = rd.compute_pipeline_create(shader_project)

	for r in range(2):
		var w := 1 - r
		us_advect.append(_create_uniform_set(shader_advect, [tex_velocity[r], tex_dye[r], tex_velocity[w], tex_dye[w]]))
		us_splat.append(_create_uniform_set(shader_splat, [tex_velocity[r], tex_velocity[w], tex_dye[r], tex_dye[w]]))
		us_divergence.append(_create_uniform_set(shader_divergence, [tex_velocity[r], tex_divergence]))
		us_pressure.append(_create_uniform_set(shader_pressure, [tex_pressure[r], tex_pressure[w], tex_divergence]))
		# Jacobi iteration 19 always outputs converged pressure to tex_pressure[0]
		us_project.append(_create_uniform_set(shader_project, [tex_velocity[r], tex_velocity[w], tex_pressure[0], tex_dye[r], tex_dye[w]]))

	display_texture = Texture2DRD.new()
	display_texture.texture_rd_rid = tex_dye[0]

	return true

func _load_compute_shader(path: String) -> RID:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr("[FluidSimulator] Failed to read shader file: ", path)
		return RID()

	var source_text := file.get_as_text()
	file.close()

	if source_text.begins_with("#[compute]"):
		source_text = source_text.substr(source_text.find("\n") + 1).strip_edges()

	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = source_text

	var spirv := rd.shader_compile_spirv_from_source(src)
	if spirv == null or spirv.compile_error_compute != "":
		printerr("[FluidSimulator] Shader compile error in ", path, ":\n", spirv.compile_error_compute if spirv else "Null SPIR-V")
		return RID()

	return rd.shader_create_from_spirv(spirv)

func _create_uniform_set(shader: RID, textures: Array[RID]) -> RID:
	var uniforms: Array[RDUniform] = []
	for b in range(textures.size()):
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u.binding = b
		u.add_id(textures[b])
		uniforms.append(u)
	return rd.uniform_set_create(uniforms, shader, 0)

func _cleanup_rids() -> void:
	if rd == null or not is_compute_ready:
		return

	for u in us_advect: if u.is_valid(): rd.free_rid(u)
	for u in us_splat: if u.is_valid(): rd.free_rid(u)
	for u in us_divergence: if u.is_valid(): rd.free_rid(u)
	for u in us_pressure: if u.is_valid(): rd.free_rid(u)
	for u in us_project: if u.is_valid(): rd.free_rid(u)

	if pipe_advect.is_valid(): rd.free_rid(pipe_advect)
	if pipe_splat.is_valid(): rd.free_rid(pipe_splat)
	if pipe_divergence.is_valid(): rd.free_rid(pipe_divergence)
	if pipe_pressure.is_valid(): rd.free_rid(pipe_pressure)
	if pipe_project.is_valid(): rd.free_rid(pipe_project)

	if shader_advect.is_valid(): rd.free_rid(shader_advect)
	if shader_splat.is_valid(): rd.free_rid(shader_splat)
	if shader_divergence.is_valid(): rd.free_rid(shader_divergence)
	if shader_pressure.is_valid(): rd.free_rid(shader_pressure)
	if shader_project.is_valid(): rd.free_rid(shader_project)

	for t in tex_velocity: if t.is_valid(): rd.free_rid(t)
	for t in tex_dye: if t.is_valid(): rd.free_rid(t)
	for t in tex_pressure: if t.is_valid(): rd.free_rid(t)
	if tex_divergence.is_valid(): rd.free_rid(tex_divergence)

func _init_cpu_fallback() -> void:
	_cpu_fallback = true
	var cell_count := grid_size.x * grid_size.y
	_cpu_vel_x.resize(cell_count)
	_cpu_vel_y.resize(cell_count)
	_cpu_dye_r.resize(cell_count)
	_cpu_dye_g.resize(cell_count)
	_cpu_dye_b.resize(cell_count)
	
	_cpu_vel_x.fill(0.0)
	_cpu_vel_y.fill(0.0)
	_cpu_dye_r.fill(0.0)
	_cpu_dye_g.fill(0.0)
	_cpu_dye_b.fill(0.0)

	_cpu_byte_buffer.resize(cell_count * 4)
	_cpu_byte_buffer.fill(0)
	_cpu_image = Image.create_from_data(grid_size.x, grid_size.y, false, Image.FORMAT_RGBA8, _cpu_byte_buffer)
	_cpu_texture = ImageTexture.create_from_image(_cpu_image)

func _queue_splat(world_pos: Vector2, force: Vector2, radius_px: float, color: Color, mode: float, strength: float = 1.0) -> void:
	if not is_finite(world_pos.x) or not is_finite(world_pos.y):
		return
	if not is_finite(force.x) or not is_finite(force.y):
		force = Vector2.ZERO
	_pending_splats.append({
		"point": Vector2(clampf(world_pos.x / 1920.0, 0.0, 1.0), clampf(world_pos.y / 1080.0, 0.0, 1.0)),
		"force": force,
		"color": color,
		"radius": clampf(radius_px / 1920.0, 0.005, 0.4),
		"mode": mode,
		"strength": strength
	})

func _register_flow(pos: Vector2, vel: Vector2, radius: float, p_vorticity: float, life: float = 1.2, decay: float = 1.0) -> void:
	if not is_finite(pos.x) or not is_finite(pos.y):
		return
	if not is_finite(vel.x) or not is_finite(vel.y):
		vel = Vector2.ZERO
	if _active_flow_nodes.size() > 64:
		_active_flow_nodes.pop_front()
	_active_flow_nodes.append({
		"pos": pos,
		"vel": vel,
		"radius": radius,
		"vorticity": p_vorticity,
		"life": life,
		"decay": decay
	})

func inject_force(world_pos: Vector2, force: Vector2, radius_px: float, color: Color) -> void:
	_queue_splat(world_pos, force, radius_px, color, 0.0, 1.0)
	_register_flow(world_pos, force * 0.8, radius_px, 0.0, 1.2, 0.9)
	_average_kinetic_energy = clampf(_average_kinetic_energy + force.length() * 0.06, 50.0, 9000.0)

func inject_vortex(world_pos: Vector2, swirl_strength: float, radius_px: float, color: Color) -> void:
	_queue_splat(world_pos, Vector2(swirl_strength * 22.0, 0.0), radius_px, color, 1.0, 1.2)
	_register_flow(world_pos, Vector2.ZERO, radius_px * 1.2, swirl_strength * 0.04, 1.8, 0.6)
	_average_kinetic_energy = clampf(_average_kinetic_energy + absf(swirl_strength) * 45.0, 50.0, 9000.0)

func inject_sink(world_pos: Vector2, pull_strength: float, radius_px: float, color: Color) -> void:
	_queue_splat(world_pos, Vector2(pull_strength * 0.08, 0.0), radius_px, color, 2.0, 1.1)
	_register_flow(world_pos, Vector2.ZERO, radius_px * 1.5, pull_strength * 0.002, 1.6, 0.7)
	_average_kinetic_energy = clampf(_average_kinetic_energy + pull_strength * 0.08, 50.0, 9000.0)

func inject_shockwave(world_pos: Vector2, dir: Vector2, power: float, color: Color) -> void:
	_queue_splat(world_pos, dir * (power * 0.14), 160.0, Color(color.r, color.g, color.b, 0.85), 0.0, 1.3)
	_queue_splat(world_pos, Vector2(power * 0.04, 0.0), 190.0, Color(1, 1, 1, 0.35), 2.0, 0.7)
	_register_flow(world_pos, dir * power, 180.0, 0.0, 1.1, 0.9)

func inject_dye(world_pos: Vector2, color: Color, radius_px: float) -> void:
	_queue_splat(world_pos, Vector2.ZERO, radius_px, color, 0.0, 0.85)

func sample_velocity_at(world_pos: Vector2) -> Vector2:
	if not is_finite(world_pos.x) or not is_finite(world_pos.y):
		return Vector2.ZERO
	if _cpu_fallback:
		if _cpu_vel_x.is_empty() or _cpu_vel_y.is_empty() or grid_size.x <= 0 or grid_size.y <= 0:
			return Vector2.ZERO
		var nx := clampf(world_pos.x / 1920.0, 0.0, 0.9999)
		var ny := clampf(world_pos.y / 1080.0, 0.0, 0.9999)
		var gx := clampi(int(nx * float(grid_size.x)), 0, grid_size.x - 1)
		var gy := clampi(int(ny * float(grid_size.y)), 0, grid_size.y - 1)
		var idx := gy * grid_size.x + gx
		if idx < 0 or idx >= _cpu_vel_x.size() or idx >= _cpu_vel_y.size():
			return Vector2.ZERO
		return Vector2(_cpu_vel_x[idx], _cpu_vel_y[idx]) * 20.0
	
	var vel_total := Vector2.ZERO
	for node in _active_flow_nodes:
		var npos: Vector2 = node.get("pos", Vector2.ZERO) as Vector2
		if not is_finite(npos.x) or not is_finite(npos.y):
			continue
		var delta: Vector2 = world_pos - npos
		var dist := delta.length()
		var r: float = maxf(float(node.get("radius", 8.0)), 8.0)
		if dist < r * 3.2:
			var life_n: float = clampf(float(node.get("life", 0.0)) / 1.8, 0.15, 1.2)
			var inf: float = exp(-(dist * dist) / (r * r * 1.15)) * life_n
			var nvel: Vector2 = node.get("vel", Vector2.ZERO) as Vector2
			vel_total += nvel * (inf * 0.85)
			var vort: float = float(node.get("vorticity", 0.0))
			if absf(vort) > 0.01 and dist > 6.0:
				var tang := Vector2(-delta.y, delta.x) / dist
				vel_total += tang * (vort * inf * 140.0)
	return vel_total

func sample_curl_at(world_pos: Vector2) -> float:
	if not is_finite(world_pos.x) or not is_finite(world_pos.y):
		return 0.0
	var curl_total := 0.0
	for node in _active_flow_nodes:
		var npos: Vector2 = node.get("pos", Vector2.ZERO) as Vector2
		if not is_finite(npos.x) or not is_finite(npos.y):
			continue
		var delta: Vector2 = world_pos - npos
		var dist := delta.length()
		var r: float = maxf(float(node.get("radius", 8.0)), 8.0)
		if dist < r * 3.0:
			var inf: float = exp(-(dist * dist) / (r * r))
			curl_total += float(node.get("vorticity", 0.0)) * inf * clampf(float(node.get("life", 0.0)) / 1.8, 0.2, 1.0)
	return clampf(curl_total, -5.0, 5.0)

func get_average_kinetic_energy() -> float:
	return _average_kinetic_energy

func get_flow_energy_norm() -> float:
	return clampf(_average_kinetic_energy / 4500.0, 0.0, 1.0)

func _seed_ambient(delta: float) -> void:
	_ambient_t += delta
	var t := _ambient_t
	var left := Vector2(460.0 + sin(t * 0.35) * 80.0, 540.0 + cos(t * 0.27) * 160.0)
	var right := Vector2(1460.0 + sin(t * 0.35 + 2.1) * 80.0, 540.0 + cos(t * 0.27 + 1.4) * 160.0)
	var fog := Color(0.22, 0.04, 0.40, 0.028)
	_queue_splat(left, Vector2(10.0, 0.0), 180.0, fog, 1.0, 0.16)
	_queue_splat(right, Vector2(-10.0, 0.0), 180.0, fog, 1.0, 0.16)
	if fmod(t, 0.45) < delta + 0.001:
		_register_flow(left, Vector2(50.0, -24.0), 180.0, 1.4, 1.5, 0.48)
		_register_flow(right, Vector2(-50.0, 24.0), 180.0, -1.4, 1.5, 0.48)

func step_simulation(delta: float) -> void:
	frame_counter += 1
	_average_kinetic_energy = lerpf(_average_kinetic_energy, 100.0, 0.02)

	_seed_ambient(delta)
	var kept_nodes: Array[Dictionary] = []
	for node in _active_flow_nodes:
		node["life"] -= delta * node["decay"]
		var nvel: Vector2 = node["vel"]
		if nvel.length_squared() > 1.0:
			node["pos"] = (node["pos"] as Vector2) + nvel * (delta * 0.12)
		if node["life"] > 0.0:
			var p: Vector2 = node["pos"]
			p.x = clampf(p.x, 40.0, 1880.0)
			p.y = clampf(p.y, 50.0, 1030.0)
			node["pos"] = p
			kept_nodes.append(node)
	_active_flow_nodes = kept_nodes

	if not is_compute_ready:
		_step_cpu_fallback(delta)
		_pending_splats.clear()
		step_completed.emit(frame_counter)
		return

	var sub_dt: float = delta / float(sub_steps)
	var groups_x := int(ceil(grid_size.x / 8.0))
	var groups_y := int(ceil(grid_size.y / 8.0))

	# 1. Force & Dye Splatting Pass (Applied ONCE per frame)
	if _pending_splats.size() > 0:
		for splat in _pending_splats:
			var r := p_idx
			var w := 1 - p_idx
			var list := rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(list, pipe_splat)
			rd.compute_list_bind_uniform_set(list, us_splat[r], 0)

			var pt: Vector2 = splat["point"]
			var frc: Vector2 = splat["force"]
			var col: Color = splat["color"]
			var pc_splat := PackedFloat32Array([
				pt.x, pt.y,
				frc.x, frc.y,
				col.r, col.g, col.b, col.a,
				splat["radius"],
				splat["strength"],
				splat.get("mode", 0.0),
				0.0
			]).to_byte_array()
			rd.compute_list_set_push_constant(list, pc_splat, pc_splat.size())
			rd.compute_list_dispatch(list, groups_x, groups_y, 1)
			rd.compute_list_end()

			p_idx = w

	_pending_splats.clear()

	# 2. Sub-stepped Navier-Stokes Simulation
	for s in range(sub_steps):
		var r := p_idx
		var w := 1 - p_idx

		# 2a. Advection Pass
		var list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list, pipe_advect)
		rd.compute_list_bind_uniform_set(list, us_advect[r], 0)
		var pc_advect := PackedFloat32Array([
			1.0 / float(grid_size.x), 1.0 / float(grid_size.y),
			sub_dt,
			dissipation
		]).to_byte_array()
		rd.compute_list_set_push_constant(list, pc_advect, pc_advect.size())
		rd.compute_list_dispatch(list, groups_x, groups_y, 1)
		rd.compute_list_end()

		p_idx = w
		r = p_idx
		w = 1 - p_idx

		# 2b. Divergence Pass
		list = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list, pipe_divergence)
		rd.compute_list_bind_uniform_set(list, us_divergence[r], 0)
		var pc_div := PackedFloat32Array([1.0 / float(grid_size.x), 1.0 / float(grid_size.y)]).to_byte_array()
		rd.compute_list_set_push_constant(list, pc_div, pc_div.size())
		rd.compute_list_dispatch(list, groups_x, groups_y, 1)
		rd.compute_list_end()

		# 2c. Jacobi Pressure Solve (20 ping-pong iterations, ends on tex_pressure[0])
		var p_read := 0
		var p_write := 1
		for j in range(jacobi_iterations):
			list = rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(list, pipe_pressure)
			rd.compute_list_bind_uniform_set(list, us_pressure[p_read], 0)
			rd.compute_list_dispatch(list, groups_x, groups_y, 1)
			rd.compute_list_end()
			p_read = 1 - p_read
			p_write = 1 - p_write

		# 2d. Projection & Vorticity Pass (reads converged tex_pressure[0])
		list = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list, pipe_project)
		rd.compute_list_bind_uniform_set(list, us_project[r], 0)
		var pc_proj := PackedFloat32Array([
			1.0 / float(grid_size.x), 1.0 / float(grid_size.y),
			vorticity,
			surface_tension,
			sub_dt
		]).to_byte_array()
		rd.compute_list_set_push_constant(list, pc_proj, pc_proj.size())
		rd.compute_list_dispatch(list, groups_x, groups_y, 1)
		rd.compute_list_end()

		p_idx = w

	if display_texture.texture_rd_rid != tex_dye[p_idx]:
		display_texture.texture_rd_rid = tex_dye[p_idx]
	step_completed.emit(frame_counter)

func _step_cpu_fallback(_delta: float) -> void:
	var w := grid_size.x
	var h := grid_size.y
	
	for splat in _pending_splats:
		var center := Vector2(splat["point"].x * w, splat["point"].y * h)
		var r: float = splat["radius"] * w
		var col: Color = splat["color"]
		var frc: Vector2 = splat["force"] * 10.0
		var r_int := int(ceil(r * 2.0))
		var min_x := maxi(int(center.x - r_int), 0)
		var max_x := mini(int(center.x + r_int), w - 1)
		var min_y := maxi(int(center.y - r_int), 0)
		var max_y := mini(int(center.y + r_int), h - 1)

		for y in range(min_y, max_y + 1):
			for x in range(min_x, max_x + 1):
				var d_sq := Vector2(x, y).distance_squared_to(center)
				var rad_sq := maxf(r * r, 1.0)
				if d_sq < rad_sq * 4.0:
					var inf := exp(-d_sq / rad_sq)
					var idx := y * w + x
					_cpu_vel_x[idx] += frc.x * inf
					_cpu_vel_y[idx] += frc.y * inf
					_cpu_dye_r[idx] = clampf(_cpu_dye_r[idx] + col.r * inf * col.a, 0.0, 1.0)
					_cpu_dye_g[idx] = clampf(_cpu_dye_g[idx] + col.g * inf * col.a, 0.0, 1.0)
					_cpu_dye_b[idx] = clampf(_cpu_dye_b[idx] + col.b * inf * col.a, 0.0, 1.0)

	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			_cpu_dye_r[idx] *= dissipation
			_cpu_dye_g[idx] *= dissipation
			_cpu_dye_b[idx] *= dissipation
			_cpu_vel_x[idx] *= dissipation
			_cpu_vel_y[idx] *= dissipation

			var b_idx := idx * 4
			_cpu_byte_buffer[b_idx + 0] = int(clampf(_cpu_dye_r[idx] * 255.0, 0.0, 255.0))
			_cpu_byte_buffer[b_idx + 1] = int(clampf(_cpu_dye_g[idx] * 255.0, 0.0, 255.0))
			_cpu_byte_buffer[b_idx + 2] = int(clampf(_cpu_dye_b[idx] * 255.0, 0.0, 255.0))
			_cpu_byte_buffer[b_idx + 3] = int(clampf(maxf(_cpu_dye_r[idx], maxf(_cpu_dye_g[idx], _cpu_dye_b[idx])) * 255.0, 0.0, 255.0))

	_cpu_image.set_data(w, h, false, Image.FORMAT_RGBA8, _cpu_byte_buffer)
	_cpu_texture.update(_cpu_image)

func get_display_texture() -> Texture2D:
	if is_compute_ready and display_texture != null:
		return display_texture
	return _cpu_texture
