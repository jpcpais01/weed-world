extends SceneTree
## Look-dev for lighting up and smoking: a Keling alone on a lawn lights a
## fresh joint, takes the first puff, then a second one, and frames are
## saved at chosen moments. The smoke is simulated, so run with a fixed
## frame rate to make every shot repeatable however slow the renderer:
##   xvfb-run godot --path . --fixed-fps 30 -s res://tools/smoke_studio.gd -- <out_dir> [t1,t2,...]
## Times count from lighting up; the second puff starts at SECOND_PUFF.

const TIMES := [0.45, 0.6, 0.9, 1.2, 1.5, 1.75, 2.05, 2.3, 3.2, 3.9, 4.6, 5.0, 5.4, 5.9, 6.6, 7.6, 8.8, 11.6, 12.4]
const SECOND_PUFF := 9.0

var _out := "user://"
var _times: Array = TIMES
var _k
var _cam: Camera3D
var _frame := 0
var _shot := 0
var _view := 0
var _t := -1.0
var _second := false
var _armed := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_times = []
		for s in args[1].split(","):
			_times.append(float(s))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://weed.cfg"))
	root.size = Vector2i(960, 540)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.42, 0.36)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.85)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-140), 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	root.add_child(sun)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.36, 0.55, 0.25)
	pm.material = pmat
	plane.mesh = pm
	floor_body.add_child(plane)
	root.add_child(floor_body)
	_k = load("res://player/keling.tscn").instantiate()
	root.add_child(_k)
	_cam = Camera3D.new()
	_cam.fov = 38
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(_cam)


func _process(delta: float) -> bool:
	_frame += 1
	if _frame < 20:
		return false
	var weed = _k.weed
	if _t < 0.0:
		if not _k.is_on_floor():
			return false
		if _frame < 60:
			# Hold a fresh joint for a moment first.
			weed.joint_strain = &"starlit"
			weed.joint_puffs = weed.HITS
			weed.lit = false
			return false
		weed.use()
		print("smoke_studio: lighting up")
		_t = 0.0
		return false
	_t += delta
	if not _second and _t >= SECOND_PUFF:
		_second = true
		weed.use()
	if _shot >= _times.size():
		quit(0)
		return true
	var t: float = _times[_shot]
	if _view == 0 and not _armed and _t < t:
		return false
	if not _armed:
		# Point the camera this frame, save what it sees on the next.
		_aim()
		_armed = true
		return false
	var img := root.get_texture().get_image()
	img.save_png("%s/%05.2f_%s.png" % [_out, t, ["game", "side", "close", "joint"][_view]])
	_armed = false
	_view += 1
	if _view > 3:
		_view = 0
		_shot += 1
	return false


func _aim() -> void:
	var weed = _k.weed
	var f: float = _k.facing
	var fwd := Vector3(sin(f), 0, cos(f))
	var right := Vector3(-cos(f), 0, sin(f))
	var base: Vector3 = _k.global_position
	if weed.hud:
		weed.hud.visible = _view == 0
	if _view == 0:
		_k.camera_rig.camera.current = true
		return
	_cam.current = true
	if _view == 1:
		_cam.fov = 40
		_cam.look_at_from_position(base + fwd * 2.3 + right * 1.2 + Vector3.UP * 1.25, _mouth() + Vector3(0, 0.3, 0))
	elif _view == 2:
		_cam.fov = 30
		_cam.look_at_from_position(_mouth() + fwd * 0.9 + right * 0.55 + Vector3.UP * 0.1, _mouth() + fwd * 0.1 + Vector3(0, 0.05, 0))
	else:
		# Right up to the joint, to see the paper and the crutch.
		var j: Node3D = weed._joint.root
		var mid := j.global_transform * Vector3(0.07, 0, 0)
		_cam.fov = 30
		_cam.look_at_from_position(mid + fwd * 0.3 + right * 0.12 + Vector3.UP * 0.08, mid)


func _mouth() -> Vector3:
	return _k.weed._rig.global_transform * _k.weed.MOUTH
