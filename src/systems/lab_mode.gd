class_name LabMode
extends RefCounted

## Dual-AI telemetry lab. Static flags. See docs/design/ai-lab.md.

static var parsed := false
static var active := false
static var watch := false
static var matches := 2
static var seconds := 0.0
static var time_scale := 4.0
static var quiet := false

static func parse() -> void:
	if parsed:
		return
	parsed = true
	for a in OS.get_cmdline_user_args():
		if a == "--lab":
			active = true
		elif a.begins_with("--lab-matches="):
			active = true
			matches = maxi(int(a.get_slice("=", 1)), 1)
		elif a.begins_with("--lab-seconds="):
			active = true
			seconds = maxf(float(a.get_slice("=", 1)), 0.0)
		elif a.begins_with("--lab-scale="):
			active = true
			time_scale = clampf(float(a.get_slice("=", 1)), 1.0, 8.0)
		elif a == "--lab-quiet":
			quiet = true
	if active and DisplayServer.get_name() == "headless":
		quiet = true

static func apply_clock() -> void:
	if not active:
		return
	Engine.time_scale = 1.0 if watch else time_scale

static func enable_watch() -> void:
	active = true
	watch = true
	time_scale = 1.0
	apply_clock()
