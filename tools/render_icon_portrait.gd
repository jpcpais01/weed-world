extends SceneTree
## Renders the Keling portrait used for the game icon and splash art onto a
## transparent background. Needs a real renderer (not --headless):
##   xvfb-run godot --path . --rendering-driver vulkan --resolution 1024x1024 -s res://tools/render_icon_portrait.gd -- <out.png> [anim] [time] [yaw_deg] [framing]
## art_source/icon_compose.py turns the portrait into every icon size.

var _frames := 0
var _out := "user://keling_portrait.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var anim := args[1] if args.size() > 1 else "Cheer"
	var at := float(args[2]) if args.size() > 2 else 0.9
	var yaw := float(args[3]) if args.size() > 3 else 24.0
	var framing := args[4] if args.size() > 4 else "bust"

	root.size = Vector2i(1024, 1024)
	root.transparent_bg = true
	root.msaa_3d = Viewport.MSAA_4X

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.7, 0.62)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var model: Node3D = load("res://assets/characters/keling/keling.glb").instantiate()
	model.rotation_degrees.y = yaw
	root.add_child(model)
	var ap := AnimationPlayer.new()
	model.add_child(ap)
	ap.add_animation_library("", load("res://assets/characters/keling/keling_animations.res"))
	ap.play(anim)
	ap.seek(at, true)
	ap.pause()

	# Warm golden-hour key, cool fill, bright lime rim from behind.
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.86, 0.66)
	key.light_energy = 2.3
	key.rotation_degrees = Vector3(-32, 38, 0)
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.6, 0.75, 1.0)
	fill.light_energy = 0.5
	fill.rotation_degrees = Vector3(-10, -60, 0)
	root.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.85, 1.0, 0.55)
	rim.light_energy = 3.2
	rim.rotation_degrees = Vector3(-20, 180 + 30, 0)
	root.add_child(rim)
	var rim2 := DirectionalLight3D.new()
	rim2.light_color = Color(1.0, 0.75, 0.95)
	rim2.light_energy = 1.6
	rim2.rotation_degrees = Vector3(-15, 180 - 40, 0)
	root.add_child(rim2)

	var cam := Camera3D.new()
	cam.fov = 22.0
	if framing == "full":
		cam.position = Vector3(0, 0.85, 4.6)
		cam.look_at_from_position(cam.position, Vector3(0, 0.84, 0))
	else:
		cam.position = Vector3(0, 1.25, 3.5)
		cam.look_at_from_position(cam.position, Vector3(0, 1.12, 0))
	root.add_child(cam)
	cam.make_current()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 12:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("portrait saved: ", _out)
		quit()
	return false
