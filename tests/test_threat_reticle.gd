extends TestCase

## The threat reticle predicts where an inbound ball crosses the goal line,
## folding the straight-line path back off the top and bottom walls. If that
## fold is wrong the marker points somewhere the ball never goes, which is
## worse than showing nothing.

var _reticle: Node

func before_each() -> void:
	_reticle = ThreatReticle.new()

func after_each() -> void:
	if is_instance_valid(_reticle):
		_reticle.free()

func _top() -> float:
	return float(ThreatReticle.TOP)

func _bottom() -> float:
	return float(ThreatReticle.BOTTOM)

## Whatever the raw projection is, the folded result must land on the court.
func test_reflection_always_lands_inside_the_court() -> void:
	var top := _top()
	var bottom := _bottom()
	for raw in [-100000.0, -5000.0, -1.0, 0.0, 40.0, 539.0, 1040.0, 1041.0, 5000.0, 123456.0]:
		var y := float(_reticle._reflect_y(raw))
		in_range(y, top, bottom, "reflect_y(%f)" % raw)

func test_values_already_inside_are_unchanged() -> void:
	for raw in [_top(), 300.0, 540.0, 900.0, _bottom()]:
		approx(float(_reticle._reflect_y(raw)), raw, 0.001, "inside value %f untouched" % raw)

## One bounce off the bottom wall mirrors by the overshoot.
func test_single_bounce_mirrors_the_overshoot() -> void:
	var bottom := _bottom()
	var overshoot := 100.0
	approx(float(_reticle._reflect_y(bottom + overshoot)), bottom - overshoot, 0.001, "bounce off the bottom")
	var top := _top()
	approx(float(_reticle._reflect_y(top - overshoot)), top + overshoot, 0.001, "bounce off the top")

## Two bounces bring the path back to where a straight line would have been,
## one court height further along.
func test_double_bounce_returns_to_the_original_offset() -> void:
	var span := _bottom() - _top()
	var y := _top() + 250.0
	approx(float(_reticle._reflect_y(y + span * 2.0)), y, 0.001, "two spans down")
	approx(float(_reticle._reflect_y(y - span * 2.0)), y, 0.001, "two spans up")

func test_reflection_is_finite_for_extreme_inputs() -> void:
	for raw in [1.0e12, -1.0e12]:
		finite(float(_reticle._reflect_y(raw)), "reflect_y(%s)" % raw)

## The goal lines must sit inside the court, or the reticle draws off-screen.
func test_goal_lines_are_inside_the_arena() -> void:
	in_range(float(ThreatReticle.GOAL_LEFT_X), 0.0, 1920.0, "left goal x")
	in_range(float(ThreatReticle.GOAL_RIGHT_X), 0.0, 1920.0, "right goal x")
	check(float(ThreatReticle.GOAL_LEFT_X) < float(ThreatReticle.GOAL_RIGHT_X), "left goal is left of right goal")
	check(_top() < _bottom(), "top is above bottom")

## Below this speed the reticle stays hidden; a zero or negative threshold
## would leave it on screen permanently.
func test_min_speed_threshold_is_positive() -> void:
	check(float(ThreatReticle.MIN_SPEED) > 0.0, "MIN_SPEED must be > 0, got %f" % float(ThreatReticle.MIN_SPEED))
