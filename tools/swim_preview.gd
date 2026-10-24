extends SceneTree
## Screenshots of swimming in the forest pond: paddling seen from the side and
## from behind (the wake), treading water, a cannonball splash and wading in
## the shallows. Looks only:
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-method gl_compatibility \
##       -s res://tools/swim_preview.gd -- <out_dir>

var _out := "user://swim_preview"
var _k
var _forest
var _cam: Camera3D
var _t := 0.0
var _step := 0
var _step_t := 0.0
var _target := Vector3.ZERO
var _shots := []
var _chin := Vector3.ZERO
var _head := Vector3.ZERO


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.add_child(load("res://world/forest/forest_level.tscn").instantiate())


func _pond_point(angle: float, f: float) -> Vector3:
	var c := ForestLayout.POND
	var r: float = _forest.layout.pond_radius(angle) * f
	var p := c + Vector2(cos(angle), sin(angle)) * r
	return Vector3(p.x, _forest.ground_height(p.x, p.y), p.y)


func _steer(strength := 1.0) -> void:
	var to: Vector3 = _target - _k.global_position
	to.y = 0.0
	if to.length() < 0.05:
		Input.action_release("move_forward")
		return
	var dir := to.normalized()
	_k.camera_rig.yaw = atan2(-dir.x, -dir.z)
	Input.action_press("move_forward", strength)


## Films the Keling from `offset` (in its facing frame: x left, y up, z ahead).
func _film(offset: Vector3, look_up := 0.55) -> void:
	var f: float = _k.facing
	var fwd := Vector3(sin(f), 0, cos(f))
	var left := Vector3(fwd.z, 0, -fwd.x)
	var p: Vector3 = _k.global_position
	# Afloat, heights are measured from the water surface, not the feet.
	var surface: float = WaterLevel.surface_at(p.x, p.z)
	if surface > p.y:
		p.y = surface - 0.2
	_cam.global_position = p + left * offset.x + Vector3.UP * offset.y + fwd * offset.z
	_cam.look_at(p + Vector3.UP * look_up)
	_cam.make_current()


func _shot(name: String) -> void:
	var p: Vector3 = _k.global_position
	var surface := WaterLevel.surface_at(p.x, p.z)
	print("swim_preview: chin %.2f m over the water, head %.2f" % [_chin.y - surface, _head.y - surface])
	var img := root.get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	print("swim_preview: ", name)


func _process(delta: float) -> bool:
	_t += delta
	_step_t += delta
	if _k == null:
		_k = root.find_child("Keling", true, false)
		_forest = root.find_child("Forest", true, false)
		if _k:
			var skel: Skeleton3D = _k._skeleton
			skel.skeleton_updated.connect(func() -> void:
				var xf := skel.global_transform
				var neck := xf * skel.get_bone_global_pose(skel.find_bone("Neck")).origin
				_head = xf * skel.get_bone_global_pose(skel.find_bone("Head")).origin
				_chin = neck.lerp(_head, -0.5))
			_cam = Camera3D.new()
			_cam.fov = 50.0
			root.add_child(_cam)
		return false
	match _step:
		0:
			if _step_t < 2.0:
				return false
			var start := _pond_point(deg_to_rad(200.0), 0.55)
			var s: float = WaterLevel.surface_at(start.x, start.z)
			_k.global_position = Vector3(start.x, s - 0.75, start.z)
			_target = _pond_point(deg_to_rad(20.0), 0.6)
			_k.facing = atan2(_target.x - start.x, _target.z - start.z)
			_k.reset_physics_interpolation()
			_step = 1
			_step_t = 0.0
		1:
			_steer()
			_film(Vector3(1.8, 0.5, 0.4))
			if _step_t > 3.0:
				_shot("swim_side")
				_step = 2
				_step_t = 0.0
		2:
			_steer()
			_film(Vector3(0.6, 1.6, -2.8), 0.3)
			if _step_t > 1.2:
				_shot("swim_wake")
				_step = 3
				_step_t = 0.0
		3:
			_steer()
			_film(Vector3(-0.9, 0.35, 1.3), 0.7)
			if _step_t > 0.8:
				_shot("swim_front")
				Input.action_release("move_forward")
				_step = 4
				_step_t = 0.0
		4:
			_film(Vector3(1.2, 0.45, 1.2), 0.65)
			if _step_t > 3.0:
				_shot("tread")
				var p := _pond_point(deg_to_rad(110.0), 0.2)
				_k.global_position = Vector3(p.x, WaterLevel.surface_at(p.x, p.z) + 1.4, p.z)
				_k.velocity = Vector3.ZERO
				_k.reset_physics_interpolation()
				_k._enter_air(false)
				_step = 5
				_step_t = 0.0
		5:
			_cam.global_position = _k.global_position * Vector3(1, 0, 1) + Vector3(2.6, WaterLevel.surface_at(_k.global_position.x, _k.global_position.z) + 0.8, 1.2)
			_cam.look_at(_k.global_position * Vector3(1, 0, 1) + Vector3(0, WaterLevel.surface_at(_k.global_position.x, _k.global_position.z) + 0.3, 0))
			_cam.make_current()
			if _k.mode == 9 and _shots.size() < 2:
				_shots.append(_step_t)
			if _shots.size() == 1 and _step_t - float(_shots[0]) > 0.12:
				_shot("plunge")
				_shots.append(0)
			if _step_t > 2.6:
				_shot("plunge_after")
				# Wade in from the bank.
				var start := _pond_point(deg_to_rad(160.0), 1.5)
				_k.global_position = start + Vector3.UP * 0.05
				_k.mode = 0
				_target = _pond_point(deg_to_rad(160.0), 0.85)
				_k.reset_physics_interpolation()
				_step = 6
				_step_t = 0.0
		6:
			_steer()
			_film(Vector3(1.6, 0.7, 1.1), 0.4)
			if _k.water.immersion > 0.12 and _step_t > 1.0:
				_shot("wade")
				_step = 7
				_step_t = 0.0
		7:
			_film(Vector3(1.6, 0.7, 1.1), 0.4)
			_target = _pond_point(deg_to_rad(160.0), 1.6)
			_steer()
			if _k.water.immersion < -0.05 and _step_t > 0.5:
				Input.action_release("move_forward")
			if _k._water_shake > 0.3:
				_shot("shake")
				quit()
			if _step_t > 12.0:
				quit()
	return false
