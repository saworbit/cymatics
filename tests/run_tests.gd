extends SceneTree

## Headless test runner. No addons: discovery is a directory scan, reporting is
## print, and the process exit code is 1 if anything failed so CI can gate on it.
##
##   godot --headless --path . --script res://tests/run_tests.gd
##   godot --headless --path . --script res://tests/run_tests.gd -- --filter=time
##
## Test files are res://tests/test_*.gd extending TestCase. Every method whose
## name starts with "test_" is run, with before_each/after_each around it.

const TEST_DIR := "res://tests/"

var _filter := ""
var _passed := 0
var _failed := 0
var _assertions := 0
var _failed_names: Array[String] = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			_filter = arg.trim_prefix("--filter=")

## Tests run on the first processed frame, not in _initialize. Nodes added to
## the tree during _initialize never receive _ready, which silently skips the
## initialisation of anything under test.
func _process(_delta: float) -> bool:
	var files := _discover()
	if files.is_empty():
		print("No test files found in ", TEST_DIR)
		quit(1)
		return true

	print("Running %d test file(s)%s\n" % [files.size(), (" matching '%s'" % _filter) if _filter != "" else ""])
	for path in files:
		_run_file(path)

	print("\n%s" % ("-".repeat(60)))
	print("%d passed, %d failed, %d assertions" % [_passed, _failed, _assertions])
	if _failed > 0:
		print("\nFailed tests:")
		for n in _failed_names:
			print("  - ", n)
		quit(1)
		return true
	print("OK")
	quit(0)
	return true

func _discover() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.begins_with("test_") and f.ends_with(".gd"):
			out.append(TEST_DIR + f)
		f = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out

func _run_file(path: String) -> void:
	var script: GDScript = load(path)
	if script == null:
		_failed += 1
		_failed_names.append("%s (failed to load)" % path)
		print("LOAD FAIL ", path)
		return

	var file_name := path.get_file()
	print("== ", file_name)

	# A file that fails to parse still loads as a script object with no
	# methods. Counting that as "nothing to run" would let a broken test file
	# pass CI silently, so an empty file is a failure.
	var declared := 0
	for m in script.get_script_method_list():
		if String(m["name"]).begins_with("test_"):
			declared += 1
	if declared == 0:
		_failed += 1
		_failed_names.append("%s (no test_ methods; did it fail to parse?)" % file_name)
		print("  FAIL <file declares no tests>")
		return

	for method in script.get_script_method_list():
		var name: String = method["name"]
		if not name.begins_with("test_"):
			continue
		if _filter != "" and not (name.contains(_filter) or file_name.contains(_filter)):
			continue

		# A fresh instance per test so state never leaks between them.
		var case: TestCase = script.new()
		case.tree = self
		var label := "%s::%s" % [file_name, name]
		case.before_each()
		case.call(name)
		case.after_each()
		_assertions += case.assertions

		if case.failures.is_empty() and case.assertions == 0:
			# A GDScript runtime error aborts the method and returns control
			# here, indistinguishable from a clean return. A test that made no
			# assertions is treated as a failure so those cannot pass silently.
			_failed += 1
			_failed_names.append("%s (made no assertions; runtime error?)" % label)
			print("  FAIL ", name, "  <no assertions ran>")
		elif case.failures.is_empty():
			_passed += 1
			print("  PASS ", name)
		else:
			_failed += 1
			_failed_names.append(label)
			print("  FAIL ", name)
			for msg in case.failures:
				print("       ", msg)
