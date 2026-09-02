extends TestCase

## Regression cover for the worst failure mode found by red-teaming: a
## non-finite ball. `Vector2.normalized()` returns zero for a NaN vector, so a
## NaN ball never heals itself. It goes invisible and uncollidable, the point
## can never end, and the match soft-locks. Two of the tuning cases that
## produced it also hung the process outright.

const BALL_SCENE := "res://scenes/ball.tscn"

var _ball: Node

func before_each() -> void:
	var packed: PackedScene = load(BALL_SCENE)
	if packed == null:
		return
	_ball = packed.instantiate()
	tree.root.add_child(_ball)

func after_each() -> void:
	if is_instance_valid(_ball):
		_ball.free()
		_ball = null

func test_ball_scene_loads() -> void:
	not_null(_ball, "ball scene instantiates")

func test_recovers_from_a_nan_position() -> void:
	if _ball == null:
		return
	_ball.global_position = Vector2(NAN, NAN)
	is_true(_ball._recover_if_non_finite(), "reports that it recovered")
	finite_vec(_ball.global_position, "position after recovery")
	finite_vec(_ball.velocity, "velocity after recovery")
	check(_ball.velocity.length() > 0.0, "recovered ball is moving, got %f" % _ball.velocity.length())

func test_recovers_from_a_nan_velocity() -> void:
	if _ball == null:
		return
	_ball.global_position = Vector2(960.0, 540.0)
	_ball.velocity = Vector2(NAN, 0.0)
	is_true(_ball._recover_if_non_finite(), "reports that it recovered")
	finite_vec(_ball.velocity, "velocity after recovery")

func test_recovers_from_infinite_values() -> void:
	if _ball == null:
		return
	_ball.global_position = Vector2(INF, -INF)
	is_true(_ball._recover_if_non_finite(), "infinite position is recovered")
	finite_vec(_ball.global_position, "position after recovery")

func test_recovers_from_a_nan_spin() -> void:
	if _ball == null:
		return
	_ball.global_position = Vector2(960.0, 540.0)
	_ball.velocity = Vector2(800.0, 0.0)
	_ball.spin = NAN
	is_true(_ball._recover_if_non_finite(), "NaN spin is recovered")
	finite(_ball.spin, "spin after recovery")

## The guard must be free when nothing is wrong, and must not move a healthy
## ball; it runs at the top of every physics frame.
func test_healthy_ball_is_left_alone() -> void:
	if _ball == null:
		return
	var pos := Vector2(500.0, 300.0)
	var vel := Vector2(700.0, -120.0)
	_ball.global_position = pos
	_ball.velocity = vel
	_ball.spin = 0.5
	is_false(_ball._recover_if_non_finite(), "healthy ball reports no recovery")
	eq(_ball.global_position, pos, "position untouched")
	eq(_ball.velocity, vel, "velocity untouched")

## A tuning resource carrying NaN is the documented route to a NaN ball: minf()
## and maxf() both return their NaN argument, so the speed cap poisons the
## velocity on the next hit. Validation must scrub it at load.
func test_non_finite_tuning_is_replaced_with_defaults() -> void:
	if _ball == null:
		return
	var bad: BallTuning = load("res://src/tuning/ball_default.tres").duplicate()
	bad.max_speed = NAN
	bad.magnus_accel = NAN
	bad.base_speed = INF
	_ball.tuning = bad
	_ball._ensure_tuning()
	finite(_ball.tuning.max_speed, "max_speed scrubbed")
	finite(_ball.tuning.magnus_accel, "magnus_accel scrubbed")
	finite(_ball.tuning.base_speed, "base_speed scrubbed")
	check(_ball.tuning.max_speed > 0.0, "max_speed restored to something usable")
