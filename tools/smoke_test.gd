extends SceneTree
## Headless smoke test: loads the test grounds, drives the Keling through a
## scripted sequence of inputs and prints controller / animation state.
##   godot --headless --path . -s res://tools/smoke_test.gd

const SCRIPT := [
	# [time, action, pressed, strength]
	[0.5, "move_forward", true, 0.4],
	[2.0, "move_forward", true, 1.0],
	[3.5, "sprint", true, 1.0],
	[6.0, "move_forward", false, 0.0],
	[6.05, "move_back", true, 1.0],
	[7.5, "move_back", false, 0.0],
	[7.5, "sprint", false, 0.0],
	[9.0, "move_right", true, 1.0],
	[9.3, "move_right", false, 0.0],
	[11.0, "jump", true, 1.0],
	[11.3, "jump", false, 0.0],
	[13.0, "move_forward", true, 1.0],
	[13.5, "jump", true, 1.0],
	[13.8, "jump", false, 0.0],
	[15.0, "move_forward", false, 0.0],
	[16.0, "emote_sit", true, 1.0],
	[16.1, "emote_sit", false, 0.0],
	[19.0, "move_left", true, 1.0],
	[21.0, "move_left", false, 0.0],
]

var _t := 0.0
var _i := 0
var _player: Node
var _log_t := 0.0
var _states := {}
var _shots: Array = []  # times to capture screenshots at (when rendering)
var _shot_dir := ""


func _initialize() -> void:
	var scene: Node = load("res://scenes/test_grounds.tscn").instantiate()
	root.add_child(scene)
	_player = scene.get_node("Keling")
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2:
		_shot_dir = args[0]
		for a in args.slice(1):
			_shots.append(float(a))


func _physics_process(delta: float) -> bool:
	_t += delta
	while _i < SCRIPT.size() and _t >= SCRIPT[_i][0]:
		var e: Array = SCRIPT[_i]
		if e[2]:
			Input.action_press(e[1], e[3])
		else:
			Input.action_release(e[1])
		_i += 1
	_log_t += delta
	var st: String = _player.animator.current_state()
	_states[st] = true
	if _log_t >= 0.25:
		_log_t = 0.0
		var p: Vector3 = _player.global_position
		print("t=%5.2f pos=(%.2f,%.2f,%.2f) facing=%6.1f %s" % [_t, p.x, p.y, p.z, rad_to_deg(_player.facing), _player.get_debug_text().replace("\n", " | ")])
	if not _shots.is_empty() and _t >= _shots[0]:
		var t: float = _shots.pop_front()
		_capture.call_deferred(t)
	if _t > 23.0:
		print("states visited: ", _states.keys())
		return true
	return false


func _capture(t: float) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/shot_%05.2f.png" % [_shot_dir, t])
