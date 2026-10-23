extends SceneTree
## Measures foot sliding: while running in a straight line at a steady speed,
## the lower (planted) foot should barely move in world space.
##   godot --headless --path . -s res://tools/foot_slip_test.gd

const PHASES := [["walk", 0.42, false], ["walk+", 0.6, false], ["jog", 1.0, false], ["sprint", 1.0, true]]

var _player: Node
var _skel: Skeleton3D
var _t := 0.0
var _phase := -1
var _prev := {}
var _samples := []
var _sweep := []  # model-space backward speed of the planted foot
var _rows := []


func _initialize() -> void:
	var scene: Node = load("res://scenes/test_grounds.tscn").instantiate()
	root.add_child(scene)
	_player = scene.get_node("Keling")
	_player.position = Vector3(0, 0.05, -40)


func _physics_process(delta: float) -> bool:
	if _skel == null:
		_skel = _player.model.find_child("Skeleton3D", true, false)
	_t += delta
	var phase := int(_t / 4.0)
	if phase != _phase:
		if _phase >= 0:
			_report(PHASES[_phase][0])
		if phase >= PHASES.size():
			return true
		_phase = phase
		var cfg: Array = PHASES[phase]
		Input.action_press("move_back", cfg[1])  # camera looks +Z at start, so "back" runs towards -Z... direction doesn't matter
		if cfg[2]:
			Input.action_press("sprint")
		else:
			Input.action_release("sprint")
		_samples.clear()
		_sweep.clear()
		_rows.clear()
		_prev.clear()
	if fmod(_t, 4.0) < 1.5:
		return false  # let speed settle
	var feet := {}
	var local := {}
	for n in ["LeftFoot", "RightFoot"]:
		var o := _skel.get_bone_global_pose(_skel.find_bone(n)).origin
		local[n] = o
		feet[n] = _skel.global_transform * o
	var low: String = "LeftFoot" if feet["LeftFoot"].y < feet["RightFoot"].y else "RightFoot"
	if _prev.has(low):
		var d: Vector3 = feet[low] - _prev[low]
		_rows.append([local[low].y, Vector2(d.x, d.z).length() / delta, -(local[low].z - _prev["local_" + low].z) / delta])
	_prev = feet
	for n in local:
		_prev["local_" + n] = local[n]
	return false


func _report(name: String) -> void:
	var min_y := INF
	for r in _rows:
		min_y = minf(min_y, r[0])
	for r in _rows:
		if r[0] < min_y + 0.012:
			_samples.append(r[1])
			_sweep.append(r[2])
	_sweep.sort()
	var sweep: float = _sweep[_sweep.size() / 2] if _sweep.size() > 0 else 0.0
	var cadence: float = _player.animator.get("parameters/Move/cadence/scale")
	var s := _samples.duplicate()
	s.sort()
	var med: float = s[s.size() / 2] if s.size() > 0 else -1.0
	var mean := 0.0
	for v in s:
		mean += v
	mean /= maxf(s.size(), 1)
	var speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	print("%-7s body %.2f m/s  planted-foot slip: median %.3f m/s, mean %.3f m/s (%.0f%% of body speed)  sweep %.2f m/s at cadence x%.2f -> natural %.2f m/s" % [name, speed, med, mean, 100.0 * med / maxf(speed, 0.01), sweep, cadence, sweep / maxf(cadence, 0.01)])
