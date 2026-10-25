extends SceneTree
## Screenshots of each smoke gift a few seconds after it is breathed out
## (Moon Jump, Slow Time, Cloud Ride, Firefly Swarm, Bloom Burst). Looks only:
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . -s res://tools/gift_preview.gd -- <out_dir>

const SHOTS := [
	[&"moonjump", 3.0, Vector3(0, 2.2, -5.5)],
	[&"slowtime", 3.0, Vector3(0, 2.0, -5.0)],
	[&"cloud", 4.0, Vector3(2.5, 2.4, -5.0)],
	[&"fireflies", 5.0, Vector3(0, 2.4, -6.0)],
	[&"bloom", 6.0, Vector3(4.0, 5.5, -11.0)],
]

var _out := "user://gift_preview"
var _k
var _cam: Camera3D
var _t := 0.0
var _i := -1
var _step_t := 0.0
var _cast := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.add_child(load("res://world/forest/forest_level.tscn").instantiate())


func _process(delta: float) -> bool:
	var real := delta / maxf(Engine.time_scale, 0.01)
	_t += real
	_step_t += real
	if _k == null:
		_k = root.find_child("Keling", true, false)
		return false
	if _i < 0:
		if _t < 8.0 or not _k.is_on_floor():
			return false
		_cam = Camera3D.new()
		root.add_child(_cam)
		_i = 0
		_step_t = 0.0
	if _i >= SHOTS.size():
		quit(0)
		return true
	var shot: Array = SHOTS[_i]
	if not _cast:
		_k.weed.gifts.ready_gift = shot[0]
		_k.weed.gifts.charges = 1
		_k.weed.gifts.cast()
		_cast = true
		_step_t = 0.0
	_film(shot[2])
	if _step_t >= shot[1]:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/%d_%s.png" % [_out, _i, shot[0]])
		print("gift_preview: saved ", shot[0])
		_k.weed.gifts.end_gift(shot[0])
		_i += 1
		_cast = false
		_step_t = -2.0
	return false


## Films the Keling from `offset` (x right, y up, z ahead in its facing frame).
func _film(offset: Vector3) -> void:
	var f: float = _k.facing
	var fwd := Vector3(sin(f), 0, cos(f))
	var right := Vector3(-fwd.z, 0, fwd.x)
	var p: Vector3 = _k.global_position
	_cam.global_position = p + right * offset.x + Vector3.UP * offset.y + fwd * offset.z
	_cam.look_at(p + Vector3.UP * 0.8 + fwd * 2.0)
	_cam.make_current()
