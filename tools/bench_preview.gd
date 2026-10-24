extends SceneTree
## Renders look-only previews of each scenic bench with a Keling sitting on
## it: the in-game framed view and a three-quarter shot of the bench.
##   xvfb-run godot --path . -s res://tools/bench_preview.gd -- <out_dir> [bench_index]

var _t := 0.0
var _k
var _benches: Array = []
var _i := 0
var _stage := 0
var _out := "user://"
var _only := -1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_only = int(args[1])
	root.size = Vector2i(1280, 720)
	root.add_child(load("res://world/forest/forest_level.tscn").instantiate())


func _process(delta: float) -> bool:
	_t += delta
	if _k == null:
		_k = root.find_child("Keling", true, false)
		if _k == null:
			return false
		_benches = get_nodes_in_group("bench")
		if _only >= 0:
			_i = _only
		_start()
		return false
	match _stage:
		0:
			if _t > 6.0 and _k.is_sitting():
				_shot("%s_view" % _benches[_i].site.id)
				_stage = 1
				_t = 0.0
		1:
			if _t > 0.5:
				# Swing the camera round to the front for a look at the bench.
				var b: Node3D = _benches[_i]
				var rig = _k.camera_rig
				rig.release_view()
				rig.yaw = b.facing_yaw() + 0.7
				rig.pitch = -0.22
				rig.zoom_by(0.6)
				_stage = 2
				_t = 0.0
		2:
			if _t > 1.0:
				_shot("%s_bench" % _benches[_i].site.id)
				_i += 1
				if _only >= 0 or _i >= _benches.size():
					quit()
					return true
				_k.stand_up()
				_stage = 3
				_t = 0.0
		3:
			if _t > 1.5:
				_start()
	return false


func _start() -> void:
	var b: Node3D = _benches[_i]
	_k.global_position = b.stand_point(0) + b.global_transform.basis.z * 0.3 + Vector3.UP * 0.05
	_k.reset_physics_interpolation()
	await create_timer(0.6).timeout
	_k.try_sit()
	_stage = 0
	_t = 0.0


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	print("preview: saved ", name)
