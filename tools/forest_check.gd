extends SceneTree
## Headless check of the Whispering Glade: grows the forest, drops the Keling
## at the spawn, walks it towards the Elder tree and checks it stays on the
## ground. Exits non-zero on failure.
##   godot --headless --path . -s res://tools/forest_check.gd

var _t := 0.0
var _keling: CharacterBody3D
var _start := Vector3.ZERO


func _initialize() -> void:
	root.add_child(load("res://world/forest/forest_level.tscn").instantiate())


func _physics_process(delta: float) -> bool:
	_t += delta
	if _keling == null:
		_keling = root.find_child("Keling", true, false) as CharacterBody3D
		if _keling:
			_start = _keling.global_position
		return false
	if _t > 1.0 and _t - delta <= 1.0:
		Input.action_press("move_forward", 1.0)
	if _t > 5.0:
		Input.action_release("move_forward")
		var p := _keling.global_position
		var moved := Vector2(p.x - _start.x, p.z - _start.z).length()
		print("forest_check: start=%s end=%s moved=%.2f m on_floor=%s" % [_start, p, moved, _keling.is_on_floor()])
		var ok := _keling.is_on_floor() and moved > 2.0 and p.y > -5.0
		print("forest_check: ", "PASS" if ok else "FAIL")
		quit(0 if ok else 1)
	return false
