extends TestCase

## The tuning resources hold ~520 feel constants and are the intended way to
## retune the game. A typo, a bad merge or a modder can put anything in a
## .tres, and several of these values are divisors or loop bounds, so the
## defaults are checked for sanity rather than for specific magic numbers.

const RESOURCES := {
	"ball": "res://src/tuning/ball_default.tres",
	"paddle": "res://src/tuning/paddle_default.tres",
	"ai": "res://src/tuning/ai_default.tres",
}

## Values that would divide by zero, invert a range, or hang a loop.
const MUST_BE_POSITIVE := [
	"radius", "base_speed", "max_speed", "min_speed",
	"hit_offset_divisor", "capture_range", "capture_tighten_time",
	"capture_radius_start", "capture_radius_end", "capture_orbit_speed",
	"blast_charge_time", "serve_speed", "move_speed",
	"reaction_delay",
]

func _load(key: String) -> Resource:
	return load(RESOURCES[key]) as Resource

func test_all_default_resources_load() -> void:
	for key in RESOURCES.keys():
		var res := _load(key)
		not_null(res, "%s resource loads" % key)

## No exported number may be NaN or infinite. A non-finite tuning value
## propagates into a position or velocity, and a non-finite position is the
## fastest way to lose the ball permanently or upset the physics server.
func test_no_value_is_non_finite() -> void:
	for key in RESOURCES.keys():
		var res := _load(key)
		if res == null:
			_fail("%s failed to load" % key)
			continue
		for prop in res.get_property_list():
			if not (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var name: String = prop["name"]
			var v: Variant = res.get(name)
			match typeof(v):
				TYPE_FLOAT:
					finite(float(v), "%s.%s" % [key, name])
				TYPE_VECTOR2:
					finite_vec(v as Vector2, "%s.%s" % [key, name])

## Anything used as a divisor or a rate must be strictly greater than zero.
func test_divisor_like_values_are_positive() -> void:
	for key in RESOURCES.keys():
		var res := _load(key)
		if res == null:
			continue
		for prop in res.get_property_list():
			if not (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var name: String = prop["name"]
			if not MUST_BE_POSITIVE.has(name):
				continue
			var v: Variant = res.get(name)
			if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
				check(float(v) > 0.0, "%s.%s must be > 0, got %s" % [key, name, v])

func test_speed_bounds_are_ordered() -> void:
	var ball := _load("ball")
	if ball == null:
		return
	var min_speed := float(ball.get("min_speed"))
	var base_speed := float(ball.get("base_speed"))
	var max_speed := float(ball.get("max_speed"))
	check(min_speed <= base_speed, "min_speed %f <= base_speed %f" % [min_speed, base_speed])
	check(base_speed <= max_speed, "base_speed %f <= max_speed %f" % [base_speed, max_speed])

func test_orbit_radius_range_is_ordered() -> void:
	var paddle := _load("paddle")
	if paddle == null:
		return
	var start_r := float(paddle.get("capture_radius_start"))
	var end_r := float(paddle.get("capture_radius_end"))
	# The capture orbit tightens from the start radius to the end radius.
	check(end_r <= start_r, "capture_radius_end %f <= capture_radius_start %f" % [end_r, start_r])
	check(end_r > 0.0, "orbit tightens to a positive radius, got %f" % end_r)
	var min_r := float(paddle.get("capture_orbit_min_radius"))
	check(min_r > 0.0, "capture_orbit_min_radius must be > 0, got %f" % min_r)
	check(min_r <= end_r, "min orbit radius %f <= end radius %f" % [min_r, end_r])

## A parry window shorter than a frame is unhittable; longer than ~0.3 s makes
## every hit a perfect. Both were real bugs earlier in development.
func test_parry_window_is_reachable_but_not_free() -> void:
	var paddle := _load("paddle")
	if paddle == null:
		return
	var w := float(paddle.get("parry_window"))
	in_range(w, 1.0 / 60.0, 0.30, "parry_window")

func test_cooldowns_are_non_negative() -> void:
	for key in RESOURCES.keys():
		var res := _load(key)
		if res == null:
			continue
		for prop in res.get_property_list():
			if not (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var name: String = prop["name"]
			if not (name.contains("cooldown") or name.contains("_time") or name.contains("duration")):
				continue
			var v: Variant = res.get(name)
			if typeof(v) == TYPE_FLOAT:
				check(float(v) >= 0.0, "%s.%s must be >= 0, got %f" % [key, name, float(v)])

## The classes must instantiate standalone, because each actor falls back to
## `.new()` semantics via a default resource when its slot is empty.
func test_tuning_classes_instantiate() -> void:
	for path in ["res://src/tuning/ball_tuning.gd", "res://src/tuning/paddle_tuning.gd", "res://src/tuning/ai_tuning.gd"]:
		var script: GDScript = load(path)
		not_null(script, "%s loads" % path)
		if script != null:
			not_null(script.new(), "%s instantiates" % path)
