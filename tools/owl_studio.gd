extends SceneTree
## Look-dev for Owl Flight in the forest: the Keling stands on the meadow,
## breathes out an owl gift and rides it; frames are saved at set moments of
## the gathering, the swoop, the ride (with a turn and a climb pressed on the
## stick) and the landing. Looks only (lavapipe is nothing like a phone). Run
## at a fixed frame rate so the shots repeat however slowly it renders:
##   xvfb-run godot --path . --rendering-method mobile --fixed-fps 30 \
##       -s res://tools/owl_studio.gd -- <out_dir> [first_shot]

# [name, seconds after the cast, camera ("game" = the player's own camera)]
const SHOTS := [
	["1_gather", 0.9, "reveal"], ["2_formed", 2.1, "reveal"], ["3_face", 2.25, "face"],
	["4_swoop", 2.95, "side"], ["5_catch", 3.35, "game"], ["6_ride", 6.0, "game"],
	["7_flank", 7.5, "flank"], ["8_front", 9.0, "front"], ["9_turn", 11.5, "game"],
	["10_climb", 14.0, "game"], ["11_below", 15.0, "below"], ["12_land", 19.0, "game"],
	["13_vanish", 20.2, "watch"],
]

var _out := "user://"
var _k
var _forest
var _cam: Camera3D
var _t := -1.0
var _wait := 0.0
var _shot := 0
var _armed := false
var _gift


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_shot = int(args[1])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://weed.cfg"))
	root.size = Vector2i(1280, 720)
	root.add_child(load("res://world/forest/forest_level.tscn").instantiate())


func _process(delta: float) -> bool:
	if _k == null:
		_k = root.find_child("Keling", true, false)
		_forest = root.find_child("Forest", true, false)
		if _k:
			_cam = Camera3D.new()
			_cam.fov = 50
			_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			root.add_child(_cam)
		return false
	if _t < 0.0:
		_wait += delta
		if _wait < 2.0 or not _k.is_on_floor() or _k.weed.gifts == null:
			return false
		if _wait < 2.1:
			var stand := Vector3(-2.0, 0.0, 12.0)
			stand.y = _forest.ground_height(stand.x, stand.z) + 0.05
			_k.global_position = stand
			_k.facing = PI
			_k.camera_rig.set_yaw(_k.facing + PI)
			return false
		if _wait < 3.0:
			return false
		_k.weed.gifts.ready_gift = &"owl"
		_k.weed.gifts.charges = 1
		_k.weed.gifts.cast()
		_t = 0.0
		print("owl_studio: cast")
		return false
	_t += delta
	if _gift == null:
		_gift = _k.find_child("Gift_owl", true, false)
	# Steer: a long left turn, then a climb, then let it land.
	if _t > 9.5 and _t < 12.0:
		Input.action_press("move_left", 0.8)
	else:
		Input.action_release("move_left")
	if _t > 12.3 and _t < 14.5:
		Input.action_press("jump")
	else:
		Input.action_release("jump")
	if _t > 16.0 and is_instance_valid(_gift) and not _gift.ending:
		_gift.end()
	if _shot >= SHOTS.size():
		quit(0)
		return true
	var s: Array = SHOTS[_shot]
	if not _armed and _t < float(s[1]):
		return false
	if not _armed:
		_aim(s[2])
		_armed = true
		return false
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, s[0]])
	print("owl_studio: ", s[0], " phase ", _gift.phase if is_instance_valid(_gift) else -1, " keling ", _k.global_position)
	_armed = false
	_shot += 1
	return false


func _aim(kind: String) -> void:
	if kind == "game":
		_k.camera_rig.get_node("SpringArm3D/Camera3D").current = true
		return
	_cam.current = true
	var f: float = _k.facing
	var fwd := Vector3(sin(f), 0, cos(f))
	var right := Vector3(cos(f), 0, -sin(f))
	var base: Vector3 = _k.global_position
	var owl: Vector3 = _gift.owl_xform.origin if is_instance_valid(_gift) else base
	var ob: Basis = _gift.owl_xform.basis if is_instance_valid(_gift) else Basis()
	match kind:
		"reveal":
			_cam.fov = 60
			_cam.look_at_from_position(base - fwd * 3.0 + right * 1.0 + Vector3.UP * 1.4, owl + Vector3.UP * 0.3)
		"face":
			_cam.fov = 50
			_cam.look_at_from_position(owl + ob.z * 7.0 + Vector3.UP * 0.5, owl - Vector3.UP * 0.6)
		"side":
			_cam.fov = 60
			_cam.look_at_from_position(base + right * 7.0 + Vector3.UP * 2.0, base + Vector3.UP * 1.5)
		"flank":
			_cam.fov = 55
			_cam.look_at_from_position(owl + ob.x * 10.0 + ob.z * 2.0 + Vector3.UP * 1.0, owl)
		"front":
			_cam.fov = 55
			_cam.look_at_from_position(owl + ob.z * 9.0 + ob.y * 2.0, owl)
		"below":
			_cam.fov = 60
			_cam.look_at_from_position(owl - ob.z * 6.0 - Vector3.UP * 5.0 + ob.x * 2.0, owl)
		"watch":
			_cam.fov = 55
			_cam.look_at_from_position(base + Vector3.UP * 1.5 - fwd * 4.0, owl)
