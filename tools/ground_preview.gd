extends SceneTree
## Look-only close-ups of where the forest meets the ground: path verges,
## tree feet, boulders, banks. Needs a Vulkan driver (lavapipe is fine, slow):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . -s res://tools/ground_preview.gd -- <out_dir> [shot,names]

var _out := "user://ground_preview"
var _only := ""
var _forest: Node3D
var _cam: Camera3D
var _shots: Array = []
var _i := 0
var _t := 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_only = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1280, 720)
	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.near = 0.05
	_cam.far = 400.0
	root.add_child(_cam)
	_cam.make_current()
	_forest = load("res://world/forest/forest.tscn").instantiate()
	root.add_child(_forest)


func _plan() -> void:
	var t: ForestTerrain = _forest.terrain
	var s: ForestScatter = _forest.scatter
	# [name, eye xz, eye height above ground, target xz, target height]
	_shots = [
		["path_spawn", Vector2(-3.2, 25.0), 1.7, Vector2(-4.0, 12.0), 0.0],
		["path_verge", Vector2(-6.0, 1.5), 1.1, Vector2(-7.4, -6.0), 0.0],
		["path_top", Vector2(1.0, 13.0), 7.0, Vector2(-3.0, 8.0), 0.0],
		["meadow_rock", Vector2(8.2, 11.8), 1.4, Vector2(5.5, 9.0), 0.3],
		["ridge", Vector2(-3.0, -20.0), 2.2, Vector2(-9.0, -29.0), 0.5],
		["stream_bank", Vector2(21.5, 9.5), 1.5, Vector2(18.5, 2.0), 0.0],
		["pond_shore", Vector2(4.5, -12.5), 1.6, Vector2(10.0, -18.0), 0.0],
		["log_hollow", ForestLayout.HOLLOW + Vector2(-0.5, 7.5), 1.3, ForestLayout.HOLLOW + Vector2(-3.0, 4.0), 0.2],
		["meadow_wide", Vector2(-12.0, 14.0), 2.4, Vector2(0.0, 2.0), 0.0],
	]
	# The feet of a few real trees of different kinds, framed from close by.
	var wanted := ["common", "oak", "birch", "pine", "elder", "twisted"]
	for tr in s.trees:
		var k: String = tr.kind
		if not k in wanted:
			continue
		var p: Vector2 = tr.pos
		if maxf(absf(p.x), absf(p.y)) > 40.0:
			continue
		wanted.erase(k)
		# Look from the open side (towards the glade) at the foot of the trunk.
		var away := (ForestLayout.GLADE - p).normalized().rotated(0.35)
		var dist: float = 2.2 + tr.trunk * 3.5
		_shots.append(["tree_" + k, p + away * dist, 1.6, p, 0.2])
	if _only != "":
		_shots = _shots.filter(func(sh): return sh[0] in _only.split(","))
	for sh in _shots:
		print("shot ", sh[0], " at ", sh[1])


func _process(delta: float) -> bool:
	if _forest == null or not _forest.is_built:
		return false
	if _shots.is_empty():
		_plan()
		if _shots.is_empty():
			quit()
			return true
		_frame(_shots[0])
		return false
	_t += delta
	if _t < 1.5:
		return false
	_t = -1000.0
	_shot(_shots[_i][0])
	return false


func _frame(sh: Array) -> void:
	var t: ForestTerrain = _forest.terrain
	var e: Vector2 = sh[1]
	var g: Vector2 = sh[3]
	var eye := Vector3(e.x, t.height_at(e.x, e.y) + sh[2], e.y)
	var target := Vector3(g.x, t.height_at(g.x, g.y) + sh[4], g.y)
	_cam.global_position = eye
	_cam.look_at(target)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("preview: saved ", name)
	_i += 1
	if _i >= _shots.size():
		quit()
		return
	_frame(_shots[_i])
	_t = 0.0
