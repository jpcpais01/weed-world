extends SceneTree
## Headless check of the boot flow: the loading screen loads the level on a
## loader thread, grows the forest on a worker thread, plants it a slice per
## frame, warms up and hands over. Measures the longest main-thread frame
## while the curtain is down. Exits non-zero on failure.
##   godot --headless --path . -s res://tools/loading_check.gd

const LIMIT_SEC := 120.0

var _screen: Node
var _level: Node
var _t := 0.0
var _last_us := 0
var _worst_ms := 0.0
var _frames := 0


func _initialize() -> void:
	_screen = load("res://ui/loading/loading_screen.tscn").instantiate()
	_screen.finished.connect(func(level: Node): _level = level)
	root.add_child(_screen)
	_last_us = Time.get_ticks_usec()


func _process(delta: float) -> bool:
	_t += delta
	var now := Time.get_ticks_usec()
	if _level == null:
		_frames += 1
		# Skip the first frames: engine start-up and the first loader poll.
		if _frames > 3:
			_worst_ms = maxf(_worst_ms, (now - _last_us) / 1000.0)
	_last_us = now
	if _level != null:
		var keling := _level.find_child("Keling", true, false)
		var forest := _level.get_node_or_null("Forest") as Forest
		var ok := keling != null and forest != null and forest.is_built \
			and forest.get_node("Generated").get_child_count() > 3 \
			and _level.can_process() and get_first_node_in_group("orbit_camera") != null
		print("loading_check: %d frames, worst main-thread frame %.1f ms, level ready=%s" % [_frames, _worst_ms, ok])
		print("loading_check: ", "PASS" if ok else "FAIL")
		quit(0 if ok else 1)
	elif _t > LIMIT_SEC:
		print("loading_check: timed out")
		print("loading_check: FAIL")
		quit(1)
	return false
