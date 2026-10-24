extends SceneTree
## Renders the full-body portraits the character picker shows, one per
## playable Keling, on transparent backgrounds (ui/character/portraits/).
## Needs a real renderer (xvfb + lavapipe in the cloud), not --headless:
##   xvfb-run godot --path . --rendering-driver vulkan -s res://tools/render_character_cards.gd -- [out_dir] [ids]
## Rerun it whenever a character's model or look changes.

const SIZE := Vector2i(320, 400)
## A friendly, characterful pose for each: clip and time.
const POSE := {
	"keling": ["Idle", 0.6], "blossom": ["Idle", 0.6], "sunflower": ["Idle", 0.6],
	"lavender": ["Idle", 0.6], "toadstool": ["Idle", 0.6],
}

var _frames := 0
var _out := "res://ui/character/portraits"
var _views := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] != "":
		_out = args[0]
	var ids: Array = Array(args[1].split(",")) if args.size() > 1 else KelingCharacters.IDS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	for id in ids:
		_views[id] = _view(String(id))


func _view(id: String) -> SubViewport:
	var sv := SubViewport.new()
	sv.size = SIZE * 2
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.msaa_3d = Viewport.MSAA_4X
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sv)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.7, 0.62)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	sv.add_child(we)

	var info := KelingCharacters.get_info(id)
	var model: Node3D = KelingCharacters.scene(id).instantiate()
	model.rotation_degrees.y = 22.0
	sv.add_child(model)
	var ap := AnimationPlayer.new()
	model.add_child(ap)
	ap.add_animation_library("", KelingCharacters.animations(id))
	var pose: Array = POSE.get(id, ["Idle", 0.6])
	if ap.has_animation(pose[0]):
		ap.play(pose[0])
		ap.seek(pose[1], true)
		ap.pause()

	# Warm key, cool fill, and a rim in the character's own colour.
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.88, 0.7)
	key.light_energy = 2.2
	key.rotation_degrees = Vector3(-32, 38, 0)
	sv.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.6, 0.75, 1.0)
	fill.light_energy = 0.5
	fill.rotation_degrees = Vector3(-10, -60, 0)
	sv.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.light_color = (info.colors[0] as Color).lerp(Color.WHITE, 0.35)
	rim.light_energy = 3.0
	rim.rotation_degrees = Vector3(-20, 210, 0)
	sv.add_child(rim)

	# Same scale for everyone, so the picker shows who is tall and who is small.
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.95
	cam.position = Vector3(0, 0.86, 4)
	sv.add_child(cam)
	cam.make_current()
	return sv


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 12:
		return false
	for id in _views:
		var img: Image = (_views[id] as SubViewport).get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
		var path := "%s/%s.png" % [_out, id]
		img.save_png(ProjectSettings.globalize_path(path))
		print("saved ", path)
	return true
