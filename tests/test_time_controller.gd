extends TestCase

## TimeController is the only writer of Engine.time_scale. If its priority
## stack is wrong the game can silently unpause itself or stay frozen, which
## was a real bug before it existed, so these cases are worth guarding.

var _tc: TimeController
var _saved_scale := 1.0

func before_each() -> void:
	_saved_scale = Engine.time_scale
	_tc = TimeController.new()
	tree.root.add_child(_tc)

func after_each() -> void:
	if is_instance_valid(_tc):
		_tc.clear()
		_tc.free()
	Engine.time_scale = _saved_scale

func test_default_scale_is_one() -> void:
	approx(_tc.effective_scale(), 1.0, 0.0001, "no sources")
	approx(Engine.time_scale, 1.0, 0.0001, "engine scale")

func test_single_source_applies() -> void:
	_tc.push(&"hitstop", 0.1, TimeController.PRIO_HITSTOP)
	approx(_tc.effective_scale(), 0.1, 0.0001, "single push")
	approx(Engine.time_scale, 0.1, 0.0001, "engine follows")

func test_highest_priority_wins_regardless_of_push_order() -> void:
	# Pause must beat hit-stop even when hit-stop is pushed afterwards.
	_tc.push(&"pause", 0.0, TimeController.PRIO_PAUSE)
	_tc.push(&"hitstop", 0.1, TimeController.PRIO_HITSTOP)
	approx(_tc.effective_scale(), 0.0, 0.0001, "pause outranks later hit-stop")

	_tc.clear()
	_tc.push(&"hitstop", 0.1, TimeController.PRIO_HITSTOP)
	_tc.push(&"pause", 0.0, TimeController.PRIO_PAUSE)
	approx(_tc.effective_scale(), 0.0, 0.0001, "pause outranks earlier hit-stop")

func test_pop_restores_lower_priority_source() -> void:
	_tc.push(&"lab", 4.0, TimeController.PRIO_LAB)
	_tc.push(&"pause", 0.0, TimeController.PRIO_PAUSE)
	approx(_tc.effective_scale(), 0.0, 0.0001, "paused")
	_tc.pop(&"pause")
	approx(_tc.effective_scale(), 4.0, 0.0001, "lab clock resumes after unpause")

func test_pop_unknown_source_is_harmless() -> void:
	_tc.push(&"lab", 4.0, TimeController.PRIO_LAB)
	_tc.pop(&"never_pushed")
	approx(_tc.effective_scale(), 4.0, 0.0001, "unrelated pop must not disturb the stack")

func test_repeated_push_replaces_not_stacks() -> void:
	# Hit-stop fires on every hit; repeated pushes must not accumulate entries
	# that a single pop then fails to clear.
	for i in 10:
		_tc.push(&"hitstop", 0.1, TimeController.PRIO_HITSTOP)
	_tc.pop(&"hitstop")
	approx(_tc.effective_scale(), 1.0, 0.0001, "one pop clears repeated pushes")
	is_false(_tc.has_source(&"hitstop"), "source gone")

func test_negative_scale_is_clamped() -> void:
	_tc.push(&"bad", -5.0, TimeController.PRIO_HITSTOP)
	# A negative time scale runs the engine backwards; it must never reach it.
	check(_tc.effective_scale() >= 0.0, "negative scale clamped, got %f" % _tc.effective_scale())

func test_clear_resets_to_one() -> void:
	_tc.push(&"pause", 0.0, TimeController.PRIO_PAUSE)
	_tc.push(&"hyper", 1.18, TimeController.PRIO_HYPER)
	_tc.clear()
	approx(_tc.effective_scale(), 1.0, 0.0001, "cleared")
	approx(Engine.time_scale, 1.0, 0.0001, "engine restored")

func test_equal_priority_sources_do_not_crash() -> void:
	_tc.push(&"a", 0.5, TimeController.PRIO_HITSTOP)
	_tc.push(&"b", 0.25, TimeController.PRIO_HITSTOP)
	var s := _tc.effective_scale()
	finite(s, "equal priority resolves to a finite scale")
	check(s == 0.5 or s == 0.25, "resolved to one of the pushed values, got %f" % s)

func test_source_scale_reports_pushed_value() -> void:
	_tc.push(&"hyper", 1.18, TimeController.PRIO_HYPER)
	approx(_tc.source_scale(&"hyper"), 1.18, 0.0001, "reports its own scale")
	approx(_tc.source_scale(&"absent"), -1.0, 0.0001, "absent source reports -1")
