class_name TestCase
extends RefCounted

## Base class for CYMATICS tests.
##
## GDScript has no exceptions, so an assertion records a failure and returns
## false; a test that must not continue after a failed assertion should return
## early on that false. Tests that need the scene tree use `tree`.

var failures: Array[String] = []
var assertions := 0
var tree: SceneTree = null

## Optional per-test hooks.
func before_each() -> void:
	pass

func after_each() -> void:
	pass

func _fail(msg: String) -> bool:
	failures.append(msg)
	return false

func check(condition: bool, msg: String) -> bool:
	assertions += 1
	if condition:
		return true
	return _fail(msg)

func eq(actual: Variant, expected: Variant, msg := "") -> bool:
	assertions += 1
	if actual == expected:
		return true
	return _fail("%s expected %s, got %s" % [msg, expected, actual])

func approx(actual: float, expected: float, tolerance := 0.0001, msg := "") -> bool:
	assertions += 1
	if is_nan(actual) and is_nan(expected):
		return true
	if is_nan(actual) or is_nan(expected):
		return _fail("%s expected %f, got %f (NaN mismatch)" % [msg, expected, actual])
	if absf(actual - expected) <= tolerance:
		return true
	return _fail("%s expected %f +/- %f, got %f" % [msg, expected, tolerance, actual])

func is_true(v: bool, msg := "") -> bool:
	return check(v, "%s expected true" % msg)

func is_false(v: bool, msg := "") -> bool:
	return check(not v, "%s expected false" % msg)

func not_null(v: Variant, msg := "") -> bool:
	return check(v != null, "%s expected non-null" % msg)

## Finite means "a number the engine can act on": not NaN, not +/-inf.
## Positions and velocities that go non-finite poison the physics server, so
## this is the single most valuable assertion in the suite.
func finite(v: float, msg := "") -> bool:
	assertions += 1
	if is_finite(v):
		return true
	return _fail("%s expected a finite number, got %f" % [msg, v])

func finite_vec(v: Vector2, msg := "") -> bool:
	assertions += 1
	if is_finite(v.x) and is_finite(v.y):
		return true
	return _fail("%s expected a finite vector, got %s" % [msg, v])

func in_range(v: float, lo: float, hi: float, msg := "") -> bool:
	assertions += 1
	if is_finite(v) and v >= lo and v <= hi:
		return true
	return _fail("%s expected %f..%f, got %f" % [msg, lo, hi, v])
