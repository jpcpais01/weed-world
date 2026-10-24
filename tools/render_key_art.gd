extends SceneTree
## Renders the Whispering Glade key art behind the boot splash and the loading
## screen: a low golden-hour shot down the meadow path with a Keling waving
## hello. Needs a real renderer (not --headless):
##   xvfb-run godot --path . --rendering-driver vulkan --resolution 2400x1080 -s res://tools/render_key_art.gd -- <out.png> [cam_x cam_z look_x look_z keling_x keling_z]

var _frames := 0
var _out := "user://key_art.png"
var _forest: Forest


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		_out = a[0]
	var v := func(i: int, d: float) -> float: return float(a[i]) if a.size() > i else d
	var cam_p := Vector2(v.call(1, -4.4), v.call(2, 26.6))
	var look_p := Vector2(v.call(3, -4.6), v.call(4, 4.0))
	var kel_p := Vector2(v.call(5, -5.5), v.call(6, 23.5))

	root.msaa_3d = Viewport.MSAA_4X
	_forest = load("res://world/forest/forest.tscn").instantiate()
	_forest.preview_camera_when_alone = false
	root.add_child(_forest)

	var cam := Camera3D.new()
	cam.fov = 52.0
	root.add_child(cam)
	var cy := _forest.ground_height(cam_p.x, cam_p.y) + 1.0
	var ly := _forest.ground_height(look_p.x, look_p.y) + 2.6
	cam.look_at_from_position(Vector3(cam_p.x, cy, cam_p.y), Vector3(look_p.x, ly, look_p.y))
	cam.make_current()
	# Part the grass around the lens too, so no blade sweeps across the shot.
	var lens := Node3D.new()
	lens.add_to_group("player")
	root.add_child(lens)
	lens.position = cam.position + (cam.global_basis.z * -0.6)

	var model: Node3D = load("res://assets/characters/keling/keling.glb").instantiate()
	model.add_to_group("player")
	root.add_child(model)
	model.position = Vector3(kel_p.x, _forest.ground_height(kel_p.x, kel_p.y), kel_p.y)
	var to_cam := cam_p - kel_p
	model.rotation.y = atan2(to_cam.x, to_cam.y) - 0.35
	var ap := AnimationPlayer.new()
	model.add_child(ap)
	ap.add_animation_library("", load("res://assets/characters/keling/keling_animations.res"))
	# A soft warm fill, so the backlit Keling's face still reads.
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.88, 0.7)
	fill.light_energy = 1.4
	fill.omni_range = 3.5
	root.add_child(fill)
	fill.position = model.position + Vector3(to_cam.normalized().x * 1.4, 1.3, to_cam.normalized().y * 1.4)
	ap.play("Surprise")
	ap.seek(0.4, true)
	ap.pause()


func _process(_delta: float) -> bool:
	_frames += 1
	# A few frames let wind, particles and the shader cache settle.
	if _frames == 24:
		root.get_texture().get_image().save_png(_out)
		print("key art saved: ", _out)
		quit()
	return false
