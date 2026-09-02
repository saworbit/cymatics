extends TestCase

## Fluid quality presets rebuild every simulation texture and the CPU fallback
## arrays. Getting that wrong is expensive: a stale grid size indexes past the
## end of the CPU arrays, and a stale texel size makes the display shader
## sample the wrong neighbourhood.
##
## These run headless, so the simulator takes its CPU fallback path. That is
## the path most likely to be under-tested, which makes it worth covering.

var _fluid: Node

func before_each() -> void:
	var script: GDScript = load("res://src/systems/fluid_simulator.gd")
	_fluid = script.new()
	tree.root.add_child(_fluid)

func after_each() -> void:
	if is_instance_valid(_fluid):
		_fluid.free()
		_fluid = null

func test_every_preset_maps_to_a_positive_grid() -> void:
	var grids: Dictionary = _fluid.QUALITY_GRIDS
	eq(grids.size(), 4, "four presets")
	for key in grids.keys():
		var g: Vector2i = grids[key]
		check(g.x > 0 and g.y > 0, "preset %s has a positive grid, got %s" % [key, g])
		# The compute shaders dispatch in 8x8 groups; a grid that is not a
		# multiple of 8 wastes invocations and complicates bounded dispatch.
		eq(g.x % 8, 0, "preset %s width is a multiple of 8" % key)
		eq(g.y % 8, 0, "preset %s height is a multiple of 8" % key)

func test_presets_are_ordered_by_detail() -> void:
	var grids: Dictionary = _fluid.QUALITY_GRIDS
	var low: Vector2i = grids[0]
	var med: Vector2i = grids[1]
	var high: Vector2i = grids[2]
	var ultra: Vector2i = grids[3]
	check(low.x < med.x, "low < medium")
	check(med.x < high.x, "medium < high")
	check(high.x < ultra.x, "high < ultra")

func test_set_quality_updates_the_grid() -> void:
	for q in range(4):
		_fluid.set_quality(q)
		var expected: Vector2i = _fluid.QUALITY_GRIDS[q]
		eq(_fluid.grid_size, expected, "grid after set_quality(%d)" % q)

## The display shader is told the texel size; if it does not follow the grid,
## the gradient and LIC taps sample the wrong distance.
func test_texel_size_tracks_the_grid() -> void:
	for q in range(4):
		_fluid.set_quality(q)
		var texel: Vector2 = _fluid.get_sim_texel_size()
		finite_vec(texel, "texel at quality %d" % q)
		approx(texel.x, 1.0 / float(_fluid.grid_size.x), 0.000001, "texel x at quality %d" % q)
		approx(texel.y, 1.0 / float(_fluid.grid_size.y), 0.000001, "texel y at quality %d" % q)

## Regression: changing quality on the CPU fallback used to leave the scratch
## arrays sized for the previous grid, and the next step indexed past the end.
func test_stepping_after_each_quality_change_is_safe() -> void:
	for q in [3, 0, 2, 1]:
		_fluid.set_quality(q)
		# Queue work at the extremes of the field, then step a few frames.
		_fluid.inject_force(Vector2(30.0, 20.0), Vector2(600.0, 0.0), 80.0, Color(1, 1, 1, 0.5))
		_fluid.inject_force(Vector2(1890.0, 1060.0), Vector2(-600.0, 0.0), 80.0, Color(1, 1, 1, 0.5))
		_fluid.inject_vortex(Vector2(960.0, 540.0), 5.0, 140.0, Color(1, 1, 1, 0.5))
		for i in 3:
			_fluid.step_simulation(1.0 / 60.0)
		check(true, "stepped safely at quality %d" % q)

## Out-of-range presets must fall back rather than produce a zero-sized grid.
func test_invalid_quality_is_survivable() -> void:
	_fluid.set_quality(99)
	check(_fluid.grid_size.x > 0 and _fluid.grid_size.y > 0, "grid stays positive after an invalid preset, got %s" % _fluid.grid_size)
	_fluid.step_simulation(1.0 / 60.0)
	_fluid.set_quality(-5)
	check(_fluid.grid_size.x > 0 and _fluid.grid_size.y > 0, "grid stays positive after a negative preset, got %s" % _fluid.grid_size)
	_fluid.step_simulation(1.0 / 60.0)

## Injections carrying NaN must not poison the field.
func test_non_finite_injections_are_ignored() -> void:
	_fluid.set_quality(1)
	var nan_v := Vector2(NAN, NAN)
	_fluid.inject_force(nan_v, Vector2(100.0, 0.0), 60.0, Color.WHITE)
	_fluid.inject_force(Vector2(960.0, 540.0), nan_v, 60.0, Color.WHITE)
	_fluid.inject_vortex(nan_v, 4.0, 100.0, Color.WHITE)
	for i in 3:
		_fluid.step_simulation(1.0 / 60.0)
	var sample: Vector2 = _fluid.sample_velocity_at(Vector2(960.0, 540.0))
	finite_vec(sample, "velocity sample after NaN injections")
	finite(_fluid.get_average_kinetic_energy(), "kinetic energy after NaN injections")

func test_sampling_outside_the_arena_is_finite() -> void:
	_fluid.set_quality(1)
	_fluid.step_simulation(1.0 / 60.0)
	for p in [Vector2(-5000.0, -5000.0), Vector2(99999.0, 99999.0), Vector2(0.0, 0.0), Vector2(1920.0, 1080.0)]:
		finite_vec(_fluid.sample_velocity_at(p), "sample at %s" % p)
		finite(_fluid.sample_curl_at(p), "curl at %s" % p)
