extends SceneTree
## Renders the little animated Kelings of the loading screen roster: for every
## playable Keling, an idle loop and a dance loop as sprite sheets with a
## transparent background. Same camera for all, so their sizes stay true.
## Needs a real renderer (not --headless):
##   xvfb-run godot --path . --rendering-driver vulkan --resolution 384x384 -s res://tools/render_keling_sprites.gd -- [out_dir]
## Writes <out_dir>/<id>_<clip>.png (COLS x ROWS grid of CELL px frames).

const IDS := ["keling", "blossom", "sunflower", "lavender", "toadstool"]
const MODEL := "res://assets/characters/%s/%s.glb"
const ANIMS := "res://assets/characters/%s/%s_animations.res"
## clip name -> frames in the loop.
const CLIPS := {"Idle": 16, "Dance": 24}
const CELL := 192
const COLS := 8
const RENDER := 384

var _out := "res://ui/loading/sprites"
var _jobs: Array[Dictionary] = []
var _model: Node3D
var _player: AnimationPlayer
var _sheet: Image
var _job := -1
var _frame := 0
var _wait := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	root.size = Vector2i(RENDER, RENDER)
	root.transparent_bg = true
	root.msaa_3d = Viewport.MSAA_4X

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.72, 0.64)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	_light(Color(1.0, 0.86, 0.66), 2.2, Vector3(-32, 38, 0))
	_light(Color(0.6, 0.75, 1.0), 0.5, Vector3(-10, -60, 0))
	_light(Color(0.9, 1.0, 0.6), 2.6, Vector3(-20, 210, 0))
	_light(Color(1.0, 0.78, 0.95), 1.3, Vector3(-15, 140, 0))

	var cam := Camera3D.new()
	cam.fov = 22.0
	cam.look_at_from_position(Vector3(0, 1.0, 4.75), Vector3(0, 0.86, 0))
	root.add_child(cam)
	cam.make_current()

	for id in IDS:
		for clip in CLIPS:
			_jobs.append({"id": id, "clip": clip, "frames": CLIPS[clip]})
	_next_job()


func _light(color: Color, energy: float, rot: Vector3) -> void:
	var l := DirectionalLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.rotation_degrees = rot
	root.add_child(l)


func _next_job() -> void:
	_job += 1
	if _job >= _jobs.size():
		print("sprites done")
		quit()
		return
	var j := _jobs[_job]
	if _model == null or _model.get_meta("id") != j.id:
		if _model:
			_model.free()
		_model = load(MODEL % [j.id, j.id]).instantiate()
		_model.set_meta("id", j.id)
		_model.rotation_degrees.y = 18.0
		root.add_child(_model)
		_player = AnimationPlayer.new()
		_model.add_child(_player)
		_player.add_animation_library("", load(ANIMS % [j.id, j.id]))
	var rows := ceili(float(j.frames) / COLS)
	_sheet = Image.create_empty(CELL * COLS, CELL * rows, false, Image.FORMAT_RGBA8)
	_frame = 0
	_pose()


func _pose() -> void:
	var j := _jobs[_job]
	_player.play(j.clip)
	var length := _player.current_animation_length
	_player.seek(length * float(_frame) / float(j.frames), true)
	_player.pause()
	_wait = 2


func _process(_delta: float) -> bool:
	if _job >= _jobs.size():
		return false
	# Let the pose reach the GPU before reading the frame back.
	_wait -= 1
	if _wait > 0:
		return false
	var j := _jobs[_job]
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
	_sheet.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i((_frame % COLS) * CELL, (_frame / COLS) * CELL))
	_frame += 1
	if _frame >= j.frames:
		var path := "%s/%s_%s.png" % [_out, j.id, String(j.clip).to_lower()]
		_sheet.save_png(path)
		print("saved ", path)
		_next_job()
	else:
		_pose()
	return false
