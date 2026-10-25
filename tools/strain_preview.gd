extends SceneTree
## Look-only shots of the strain patches where they grow in the forest
## (lavapipe is slow and nothing like a phone: looks only, never performance).
##   xvfb-run -a godot --path . --rendering-method mobile -s res://tools/strain_preview.gd -- <out_dir> [patch_id ...]

var _out := "user://"
var _want: Array = []
var _forest
var _cam: Camera3D
var _queue: Array = []
var _wait := 0
var _t := 0.0
var _pending := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	for a in args.slice(1):
		_want.append(StringName(a))
	root.size = Vector2i(1280, 720)
	root.add_child(load("res://world/forest/forest_level.tscn").instantiate())


func _process(delta: float) -> bool:
	_t += delta
	if _t > 900.0:
		quit(1)
		return true
	if _forest == null:
		_forest = root.find_child("Forest", true, false)
		if _forest == null or _forest.weed == null or _forest.weed.nodes.is_empty():
			_forest = null
			return false
		_cam = Camera3D.new()
		_cam.fov = 50
		_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		root.add_child(_cam)
		for p in _forest.weed.patches:
			if _want.is_empty() or p.id in _want:
				_queue.append(p)
		# Hide the HUD so the plants are the picture.
		for c in root.find_children("*", "CanvasLayer", true, false):
			c.visible = false
		_wait = 90
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if not _pending.is_empty():
		root.get_texture().get_image().save_png("%s/patch_%s.png" % [_out, _pending.id])
		print("strain_preview: ", _pending.id, " ", _pending.strain)
		_pending = {}
	if _queue.is_empty():
		quit()
		return true
	var patch: Dictionary = _queue.pop_front()
	var c: Vector2 = patch.pos
	# Frame the patch from the side with the most open ground, Keling eye height.
	var best_dir := Vector2(0, 1)
	var best_score := -INF
	for k in 8:
		var d := Vector2.from_angle(k * TAU / 8.0)
		var p := c + d * 3.2
		var score: float = -absf(_forest.ground_height(p.x, p.y) - _forest.ground_height(c.x, c.y))
		if score > best_score:
			best_score = score
			best_dir = d
	var eye := c + best_dir * 2.9
	var gy: float = _forest.ground_height(c.x, c.y)
	_cam.current = true
	_cam.look_at_from_position(Vector3(eye.x, _forest.ground_height(eye.x, eye.y) + 1.15, eye.y), Vector3(c.x, gy + 0.55, c.y))
	_pending = patch
	_wait = 6
	return false
