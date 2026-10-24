extends SceneTree
## Look-dev for the rolling ritual: a Keling alone on a lawn in soft light,
## posed at chosen moments of the roll (act_t is pinned, so every shot is
## exact however slow the renderer), seen through its own close-up camera and
## from a tight hands camera. lavapipe-friendly; looks only.
##   xvfb-run godot --path . -s res://tools/roll_studio.gd -- <out_dir> [t1,t2,...]

const TIMES := [0.3, 0.6, 0.9, 1.05, 1.45, 1.7, 2.3, 3.0, 3.45, 3.75, 4.1, 4.45, 4.9, 5.4, 5.9, 6.5, 6.8, 7.05, 7.7, 8.2, 8.4, 8.78, 8.98, 9.2, 9.6, 9.9]
const SETTLE := 4

var _out := "user://"
var _times: Array = TIMES
var _k
var _cam: Camera3D
var _frame := 0
var _shot := 0
var _view := 0
var _wait := 0
var _started := false


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
	env.background_color = Color(0.62, 0.78, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.85)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
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
	_cam.fov = 30
	root.add_child(_cam)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 20:
		return false
	var weed = _k.weed
	if not _started:
		if not _k.is_on_floor():
			return false
		weed.discovered.append(&"starlit")
		weed.add_bud(&"starlit")
		weed.use()
		print("roll_studio: act ", weed.act)
		weed.set_physics_process(false)
		_started = true
		return false
	if _shot >= _times.size():
		quit(0)
		return true
	var t: float = _times[_shot]
	weed.act_t = t
	_wait += 1
	if weed.hud:
		weed.hud.visible = _view == 0
	if _view == 0:
		_k.camera_rig.camera.current = true
	else:
		_cam.current = true
		var f: float = _k.facing
		var fwd := Vector3(sin(f), 0, cos(f))
		var right := Vector3(-cos(f), 0, sin(f))
		var base: Vector3 = _k.global_position
		_cam.look_at_from_position(base + fwd * 1.45 + right * 0.45 + Vector3.UP * 1.45, base + Vector3(0, 0.8, 0) + fwd * 0.4)
	if _wait < SETTLE + (6 if _shot == 0 and _view == 0 else 0):
		return false
	var img := root.get_texture().get_image()
	img.save_png("%s/%05.2f_%s.png" % [_out, t, "game" if _view == 0 else "hands"])
	_wait = 0
	_view += 1
	if _view > 1:
		_view = 0
		_shot += 1
	return false
