extends SceneTree
## Grab check: walks the Keling up to each kind of herb in the test grounds,
## grabs, and measures how close the hand gets to the target when the fingers
## close. Optional screenshots with a close camera (needs a rendering driver):
##   godot --headless --path . -s res://tools/grab_test.gd
##   godot --path . -s res://tools/grab_test.gd -- <dir>

const CASES := [
	["low tuft", Vector3(2.4, 0.0, 2.6), Vector3(0.0, 0.0, -0.75)],
	["ledge", Vector3(4.3, 0.3, 2.1), Vector3(0.0, 0.0, -0.7)],
	["hanging vine", Vector3(5.75, 1.51, 3.6), Vector3(-0.1, 0.0, -0.7)],
	["nothing nearby", Vector3(-20.0, 0.0, -20.0), Vector3(0.0, 0.0, -1.0)],
]
const SHOTS := [0.3, 0.55, 0.75, 1.0, 1.3, 1.7]

var _player: Node
var _case := -1
var _t := 0.0
var _gripped_at := -1.0
var _results := []
var _shot_dir := ""
var _cam: Camera3D
var _shots_left := []


func _initialize() -> void:
	var scene: Node = load("res://scenes/test_grounds.tscn").instantiate()
	root.add_child(scene)
	_player = scene.get_node("Keling")
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_shot_dir = args[0]
		_cam = Camera3D.new()
		_cam.fov = 40
		scene.add_child(_cam)


func _next_case() -> bool:
	_case += 1
	if _case >= CASES.size():
		return false
	var c: Array = CASES[_case]
	var herb_base: Vector3 = c[1]
	_player.global_position = Vector3(herb_base.x, 0.05, herb_base.z) + c[2]
	_player.velocity = Vector3.ZERO
	_player.facing = 0.0
	_t = 0.0
	_gripped_at = -1.0
	_shots_left = SHOTS.duplicate()
	return true


func _physics_process(delta: float) -> bool:
	if _case == -1:
		_t += delta
		if _t < 0.5:
			return false
		_player.grab.gripped.connect(_on_gripped)
		_next_case()
		return false
	_t += delta
	if absf(_t - 0.4) < delta * 0.5:
		Input.action_press("grab")
	elif absf(_t - 0.5) < delta * 0.5:
		Input.action_release("grab")
	if _cam:
		var fwd := Vector3(sin(_player.facing), 0, cos(_player.facing))
		var side := Vector3(fwd.z, 0, -fwd.x)
		_cam.global_position = _player.global_position + side * 2.4 + fwd * 1.3 + Vector3(0, 0.9, 0)
		_cam.look_at(_player.global_position + fwd * 0.2 + Vector3(0, 0.6, 0))
		_cam.current = true
		if not _shots_left.is_empty() and _t - 0.4 >= _shots_left[0]:
			var st: float = _shots_left.pop_front()
			_capture.call_deferred("%s/grab_%d_%.2f.png" % [_shot_dir, _case, st])
	if _t > 3.2:
		if _gripped_at < 0.0:
			_results.append("%-15s no grip" % CASES[_case][0])
		if not _next_case():
			for r in _results:
				print(r)
			print("player mode at end: ", _player.Mode.keys()[_player.mode])
			return true
	return false


func _on_gripped() -> void:
	_gripped_at = _t
	# The signal fires mid-modification; read the finished pose once the
	# skeleton has run all its modifiers this frame.
	var skel: Skeleton3D = _player.model.find_child("Skeleton3D", true, false)
	await skel.skeleton_updated
	var side: String = _player.grab.side
	var tip := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(side + "MiddleDistal")).origin
	var hand := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(side + "Hand")).origin
	var target: Vector3 = _player.grab.target_world
	var grip_center := hand.lerp(tip, 0.5)
	_results.append("%-15s %s hand, target y %.2f, grip centre %.3f m from target (hand %.3f)" % [CASES[_case][0], side, target.y, grip_center.distance_to(target), hand.distance_to(target)])


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
