extends SceneTree
## Look-dev for Dragon Breath in the forest: the Keling stands by the first
## weed patch with a lit joint, holds the puff, and frames are saved at set
## moments of the draw, the blast, the swim, the dive and the rainbow. Looks
## only (lavapipe is nothing like a phone). Run at a fixed frame rate so the
## shots repeat however slowly it renders:
##   xvfb-run godot --path . --rendering-method mobile --fixed-fps 30 \
##       -s res://tools/dragon_studio.gd -- <out_dir> [yaw_offset_deg] [first_shot]

# [name, seconds after the press, camera]
const SHOTS := [
	["1_draw", 1.9, "face"], ["2_blast", 2.95, "side"], ["3_emerge", 3.35, "behind"],
	["4_swim", 4.1, "chase"], ["5_swim_side", 4.7, "flank"], ["6_swim_far", 5.3, "behind_high"],
	["7_dive", 6.4, "flank"], ["8_splash", 7.0, "impact"], ["9_rainbow", 9.0, "rainbow"],
]

var _out := "user://"
var _yaw_off := 0.0
var _k
var _forest
var _cam: Camera3D
var _t := -1.0
var _wait := 0.0
var _shot := 0
var _armed := false
var _breath


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_yaw_off = deg_to_rad(float(args[1]))
	if args.size() > 2:
		_shot = int(args[2])
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
		if _wait < 2.0 or not _k.is_on_floor():
			return false
		if _wait < 2.1:
			var plant = _forest.weed.nodes[0]
			var pp: Vector3 = plant.global_position
			var stand: Vector3 = pp + Vector3(1, 0, 0.35).normalized() * 6.0
			stand.y = _forest.ground_height(stand.x, stand.z) + 0.05
			_k.global_position = stand
			var to := pp - stand
			_k.facing = atan2(to.x, to.z) + _yaw_off
			_k.camera_rig.set_yaw(_k.facing + PI)
			_k.weed.joint_strain = &"starlit"
			_k.weed.joint_puffs = 3
			_k.weed.lit = true
			return false
		if _wait < 3.5:
			return false
		_k.weed.use_dragon()
		_t = 0.0
		print("dragon_studio: breathing")
		return false
	_t += delta
	if _breath == null:
		_breath = _k.find_child("DragonBreath", true, false)
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
	print("dragon_studio: ", s[0])
	_armed = false
	_shot += 1
	return false


func _aim(kind: String) -> void:
	_cam.current = true
	var f: float = _k.facing
	var fwd := Vector3(sin(f), 0, cos(f))
	var right := Vector3(cos(f), 0, -sin(f))
	var base: Vector3 = _k.global_position
	var head := Vector3.ZERO
	var mid := Vector3.ZERO
	if is_instance_valid(_breath) and _breath._pts.size() > 1:
		head = _breath._pos_at(minf(_breath._head, _breath._len))
		mid = _breath._pos_at(clampf(_breath._head - 3.5, 0.0, _breath._len))
	match kind:
		"face":
			_cam.fov = 40
			_cam.look_at_from_position(base + fwd * 1.5 + right * 0.5 + Vector3.UP * 1.0, base + Vector3.UP * 0.8)
		"side":
			_cam.fov = 55
			_cam.look_at_from_position(base + right * 4.0 + fwd * 2.0 + Vector3.UP * 1.3, base + fwd * 2.5 + Vector3.UP * 0.9)
		"behind":
			_cam.fov = 60
			_cam.look_at_from_position(base - fwd * 2.6 + right * 0.8 + Vector3.UP * 1.7, base + fwd * 6.0 + Vector3.UP * 1.4)
		"behind_high":
			_cam.fov = 60
			_cam.look_at_from_position(base - fwd * 3.0 + Vector3.UP * 3.0, mid)
		"chase":
			_cam.fov = 55
			_cam.look_at_from_position(mid - fwd * 4.5 + right * 3.0 + Vector3.UP * 1.0, mid)
		"flank":
			_cam.fov = 55
			_cam.look_at_from_position(mid + right * 8.0 + Vector3.UP * 0.6, mid)
		"impact":
			var p: Vector3 = _breath.impact_point if is_instance_valid(_breath) else base + fwd * 20.0
			_cam.fov = 55
			_cam.look_at_from_position(p - fwd * 7.0 + right * 3.0 + Vector3.UP * 2.0, p + Vector3.UP * 1.0)
		"rainbow":
			var p: Vector3 = _breath.impact_point if is_instance_valid(_breath) else base + fwd * 20.0
			_cam.fov = 60
			_cam.look_at_from_position(base + Vector3.UP * 1.6 - fwd * 1.0, p + Vector3.UP * 2.0)
