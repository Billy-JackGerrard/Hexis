## Static guard against the class of bug that caused the HQ-upgrade desync:
## +-*/ are IEEE 754-guaranteed bit-identical across CPUs/OSes, but libm
## transcendentals (pow/sin/cos/sqrt/atan2/exp/log/...) are not — two
## lockstepped peers on different machines can compute a ULP-different result
## from the exact same inputs and silently disagree on something like
## resource affordability. See sim/bases/building_stats.gd's _int_pow for the
## fix shape (exponentiation by squaring instead of pow(), for the common
## case of a non-negative integer exponent).
##
## Scans every sim/ script for a banned call, sim/worldgen/ excepted (map
## generation runs once off the shared world_seed before any command is
## issued, and BaseSiteSelector's trig there is a one-time layout choice, not
## a per-tick value both peers must keep agreeing on forever after). Also
## exempt: the file(s) actually implementing the deterministic replacement
## (they legitimately don't call the banned functions, but skip the
## self-referential noise of listing them below).
## Run with:
##   godot --headless --script res://tests/test_deterministic_math.gd
extends SceneTree

var _failures: int = 0
var _regexes: Dictionary = {} ## banned name -> compiled RegEx, word-boundary so "_int_pow(" doesn't match "pow("

const BANNED_CALLS := ["pow", "sin", "cos", "tan", "atan", "atan2", "asin", "acos", "exp", "log", "sqrt"]
const EXEMPT_DIRS := ["res://sim/worldgen/"]

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)

func _init() -> void:
	for banned in BANNED_CALLS:
		var regex := RegEx.new()
		regex.compile("(?<![A-Za-z0-9_])%s\\(" % banned)
		_regexes[banned] = regex

	print("sim/ carries no libm transcendentals outside worldgen (non-deterministic across platforms)")
	_scan("res://sim")
	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

func _scan(dir_path: String) -> void:
	if EXEMPT_DIRS.has(dir_path + "/") or EXEMPT_DIRS.has(dir_path):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full_path := dir_path + "/" + entry
		if dir.current_is_dir():
			_scan(full_path)
		elif entry.ends_with(".gd"):
			_scan_file(full_path)
		entry = dir.get_next()
	dir.list_dir_end()

func _scan_file(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	for i in lines.size():
		var line := lines[i]
		var comment_at := line.find("#")
		var code := line if comment_at == -1 else line.substr(0, comment_at)
		for banned in BANNED_CALLS:
			if (_regexes[banned] as RegEx).search(code) != null:
				_check(false, "%s:%d calls %s() — not guaranteed bit-identical across platforms, breaks lockstep" % [path, i + 1, banned])
