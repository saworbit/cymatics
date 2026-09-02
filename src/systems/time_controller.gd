class_name TimeController
extends Node

## Single owner of Engine.time_scale.
##
## Sources push a scale with a priority; the highest-priority entry wins.
## Default (no entries) is 1.0. Priorities: pause > hit-stop > hyper > lab.

const PRIO_LAB := 10
const PRIO_HYPER := 20
const PRIO_HITSTOP := 30
const PRIO_PAUSE := 40

signal scale_changed(new_scale: float)

var _entries: Dictionary = {} # StringName -> [scale: float, priority: int]
var _current := 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply()

func push(source: StringName, scale: float, priority: int) -> void:
	_entries[source] = [maxf(scale, 0.0), priority]
	_apply()

func pop(source: StringName) -> void:
	if _entries.erase(source):
		_apply()

func has_source(source: StringName) -> bool:
	return _entries.has(source)

func source_scale(source: StringName) -> float:
	if _entries.has(source):
		return _entries[source][0]
	return -1.0

func clear() -> void:
	_entries.clear()
	_apply()

func effective_scale() -> float:
	var best_prio := -1
	var best_scale := 1.0
	for src in _entries:
		var e: Array = _entries[src]
		if int(e[1]) > best_prio:
			best_prio = int(e[1])
			best_scale = float(e[0])
	return best_scale

func _apply() -> void:
	var s := effective_scale()
	if not is_equal_approx(s, _current) or not is_equal_approx(Engine.time_scale, s):
		_current = s
		Engine.time_scale = s
		scale_changed.emit(s)
