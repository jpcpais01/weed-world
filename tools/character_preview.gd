extends SceneTree
## Contact sheet of every playable Keling in a row of animation poses, for
## checking rigs and retargets by eye. Needs a real renderer (xvfb + lavapipe
## in the cloud), looks only:
##   xvfb-run godot --path . --rendering-driver vulkan -s res://tools/character_preview.gd -- <out.png> [ids] [clip@t,clip@t...] [yaw]

const CELL := 420

var _frames := 0
var _out := "user://characters.png"
var _views: Array[SubViewport] = []
var _cols := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var ids: Array = Array(args[1].split(",")) if args.size() > 1 and args[1] != "" else KelingCharacters.IDS
	var clips: Array = Array(args[2].split(",")) if args.size() > 2 else ["Idle@0.5", "Walk@0.3", "Jog@0.2", "IdleFoldArms@1.0", "SitIdle@0.5", "Cheer@0.9", "Fall@0.2"]
	var yaw := float(args[3]) if args.size() > 3 else 25.0
	_cols = clips.size()
	for id in ids:
		for c in clips:
			var parts: PackedStringArray = String(c).split("@")
			_views.append(_cell(String(id), parts[0], float(parts[1]) if parts.size() > 1 else 0.0, yaw))


func _cell(id: String, clip: String, at: float, yaw: float) -> SubViewport:
	var sv := SubViewport.new()
	sv.size = Vector2i(CELL, CELL)
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_4X
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sv)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.58, 0.62, 0.6)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.75)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	sv.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.5
	sv.add_child(key)
	var info := KelingCharacters.get_info(id)
	var model: Node3D = (load(info.scene) as PackedScene).instantiate()
	model.rotation_degrees.y = yaw
	sv.add_child(model)
	var ap := AnimationPlayer.new()
	model.add_child(ap)
	ap.add_animation_library("", load(info.animations))
	if ap.has_animation(clip):
		ap.play(clip)
		ap.seek(at, true)
		ap.pause()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.95
	cam.position = Vector3(0, 0.86, 4)
	sv.add_child(cam)
	cam.make_current()
	var label := Label3D.new()
	label.text = "%s  %s" % [id, clip]
	label.pixel_size = 0.0022
	label.position = Vector3(0, 1.76, 0.5)
	label.modulate = Color(0.05, 0.1, 0.05)
	label.outline_size = 0
	sv.add_child(label)
	return sv


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 10:
		return false
	var rows := ceili(float(_views.size()) / _cols)
	var sheet := Image.create(CELL * _cols, CELL * rows, false, Image.FORMAT_RGBA8)
	for i in _views.size():
		var img := _views[i].get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i((i % _cols) * CELL, (i / _cols) * CELL))
	sheet.save_png(_out)
	print("saved ", _out)
	return true
