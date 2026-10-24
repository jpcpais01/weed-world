extends SceneTree
## Renders the key art behind the boot splash and the loading screen: the
## whole Keling gang together on the meadow path in golden-hour light.
## Needs a real renderer (not --headless):
##   xvfb-run godot --path . --rendering-driver vulkan --resolution 1920x864 -s res://tools/render_key_art.gd -- <out.png> [--empty]
## --empty renders the same shot without the Kelings (for parallax layers).
## tools/splash_compose.py turns the render into branding/splash.png.

const MODEL := "res://assets/characters/%s/%s.glb"
const ANIMS := "res://assets/characters/%s/%s_animations.res"

## The camera stands on the path looking north up the glade towards the Elder.
const CAM := Vector2(-4.4, 26.6)
const LOOK := Vector2(-4.6, 4.0)
const CAM_HEIGHT := 1.0
## Height of the look-at point above the ground there: low enough that the
## gang stands clear of the loading bar, high enough to leave sky for the title.
const LOOK_HEIGHT := -0.4

## Who stands where. `at` is (sideways metres, metres ahead) from the camera;
## `turn` adds yaw (radians) on top of facing the lens.
const CAST := [
	{"id": "toadstool", "at": Vector2(2.75, 4.5), "anim": "Cheer", "time": 0.7, "turn": -0.25},
	{"id": "blossom", "at": Vector2(-1.45, 4.15), "anim": "Dance", "time": 1.3, "turn": 0.2},
	{"id": "lavender", "at": Vector2(-2.85, 4.7), "anim": "IdleFoldArms", "time": 1.0, "turn": 0.3},
	{"id": "keling", "at": Vector2(0.05, 3.75), "anim": "Cheer", "time": 0.9, "turn": 0.0},
	{"id": "sunflower", "at": Vector2(1.4, 4.15), "anim": "Surprise", "time": 0.4, "turn": -0.2},
]

var _frames := 0
var _out := "user://key_art.png"
var _forest: Forest


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		_out = a[0]
	var empty := "--empty" in a

	root.msaa_3d = Viewport.MSAA_4X
	_forest = load("res://world/forest/forest.tscn").instantiate()
	_forest.preview_camera_when_alone = false
	root.add_child(_forest)

	var cam := Camera3D.new()
	cam.fov = 52.0
	root.add_child(cam)
	var cy := _forest.ground_height(CAM.x, CAM.y) + CAM_HEIGHT
	var ly := _forest.ground_height(LOOK.x, LOOK.y) + LOOK_HEIGHT
	cam.look_at_from_position(Vector3(CAM.x, cy, CAM.y), Vector3(LOOK.x, ly, LOOK.y))
	cam.make_current()
	# Part the grass around the lens too, so no blade sweeps across the shot.
	var lens := Node3D.new()
	lens.add_to_group("player")
	root.add_child(lens)
	lens.position = cam.position + cam.global_basis.z * -0.6

	if empty:
		return
	var fwd := (LOOK - CAM).normalized()
	var right := Vector2(-fwd.y, fwd.x)
	for c in CAST:
		var at: Vector2 = c.at
		var p: Vector2 = CAM + right * at.x + fwd * at.y
		var model: Node3D = load(MODEL % [c.id, c.id]).instantiate()
		root.add_child(model)
		model.position = Vector3(p.x, _forest.ground_height(p.x, p.y), p.y)
		var to_cam := CAM - p
		model.rotation.y = atan2(to_cam.x, to_cam.y) + float(c.turn)
		var ap := AnimationPlayer.new()
		model.add_child(ap)
		# Each Keling has its own retargeted clips (shared ones stretch limbs).
		ap.add_animation_library("", load(ANIMS % [c.id, c.id]))
		ap.play(c.anim)
		ap.seek(float(c.time), true)
		ap.pause()
		# Up to four of them (the first in CAST) part the grass around their feet.
		if get_nodes_in_group("player").size() < 4:
			model.add_to_group("player")
		# A soft warm fill from the lens side, so backlit faces still read.
		var fill := OmniLight3D.new()
		fill.light_color = Color(1.0, 0.88, 0.72)
		fill.light_energy = 1.1
		fill.omni_range = 3.0
		root.add_child(fill)
		var d := to_cam.normalized()
		fill.position = model.position + Vector3(d.x * 1.3, 1.25, d.y * 1.3)


func _process(_delta: float) -> bool:
	_frames += 1
	# A few frames let wind, particles and the shader cache settle.
	if _frames == 24:
		root.get_texture().get_image().save_png(_out)
		print("key art saved: ", _out)
		quit()
	return false
