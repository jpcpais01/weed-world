extends SceneTree
## Look-dev turntable for the weed strains: every strain's plant with its
## buds in place, from the front and the side, a close-up of its crown cola
## and a row of its loose buds (shown big to read the shape),
## on a soft studio backdrop. Lavapipe is slow and nothing like a phone: use
## these for looks only, never for performance.
##   xvfb-run -a godot --path . --rendering-method mobile -s res://tools/strain_studio.gd -- <out_dir> [strain ...]

var _out := "user://"
var _ids: Array = []
var _i := 0
var _frame := 0
var _stage: Node3D
var _cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	for a in args.slice(1):
		_ids.append(StringName(a))
	if _ids.is_empty():
		_ids = WeedStrains.ORDER.duplicate()
	root.size = Vector2i(1200, 900)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.78, 0.84, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.85)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	root.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.36, 0.3, 0.24)
	floor_mi.material_override = fm
	root.add_child(floor_mi)
	_cam = Camera3D.new()
	_cam.fov = 34
	root.add_child(_cam)
	_cam.current = true


func _build(id: StringName) -> void:
	if _stage:
		_stage.queue_free()
	_stage = Node3D.new()
	root.add_child(_stage)
	var info := WeedStrains.info(id)
	var plant := WeedPlant.new()
	plant.setup(id, info.height, 0.0)
	_stage.add_child(plant)
	# A row of loose buds at the plant's feet, big enough to read the shape.
	for k in 3:
		var b := WeedKit.make_bud(id, 2.2)
		b.position = Vector3(-0.42 + k * 0.42, 0.18, 0.55)
		b.rotation = Vector3(0, k * 1.1, 0)
		_stage.add_child(b)
	var lbl := Label3D.new()
	lbl.text = "%s  (%s)" % [info.name, id]
	lbl.font_size = 48
	lbl.pixel_size = 0.002
	lbl.position = Vector3(0, -0.05, 0.9)
	lbl.rotation.x = -0.4
	_stage.add_child(lbl)


func _process(_delta: float) -> bool:
	if _i >= _ids.size():
		quit()
		return true
	var id: StringName = _ids[_i]
	var h: float = WeedStrains.info(id).height
	if _frame == 0:
		_build(id)
	var look := Vector3(0, h * 0.5, 0.15)
	var d := maxf(h * 2.1, 2.2)
	if _frame == 3:
		_cam.look_at_from_position(look + Vector3(0.0, h * 0.25, d), look)
	elif _frame == 6:
		_snap("%s_front" % id)
		_cam.look_at_from_position(look + Vector3(d * 0.85, h * 0.6, d * 0.5), look)
	elif _frame == 9:
		_snap("%s_side" % id)
		# Close up on the crown cola, about where a Keling's eyes would be.
		var crown: Vector3 = WeedKit.bud_anchors(id)[0]
		_cam.look_at_from_position(Vector3(crown.x + 0.55, maxf(crown.y + 0.2, 0.9), crown.z + 0.75), crown)
	elif _frame == 12:
		_snap("%s_close" % id)
		_cam.look_at_from_position(Vector3(0, 0.75, 1.55), Vector3(0, 0.2, 0.55))
	elif _frame == 15:
		_snap("%s_buds" % id)
		_frame = -1
		_i += 1
	_frame += 1
	return false


func _snap(n: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, n])
	print("strain_studio: ", n)
