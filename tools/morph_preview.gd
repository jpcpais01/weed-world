extends SceneTree
## Look-only contact sheet of a Keling transforming into another in the real
## forest, through the game camera: ten moments of the effect.
## Needs a real renderer (xvfb + lavapipe in the cloud):
##   xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 -s res://tools/morph_preview.gd -- <out.png> <from> <to>

const TIMES := [0.12, 0.42, 0.62, 0.78, 0.92, 1.06, 1.2, 1.34, 1.5, 1.9]
const CELL := Vector2i(480, 270)

var _out := "user://morph.png"
var _from := "keling"
var _to := "blossom"
var _k
var _t := 0.0
var _started := false
var _shots: Array[Image] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_from = args[1]
	if args.size() > 2:
		_to = args[2]
	root.size = Vector2i(960, 540)
	KelingCharacters.save_id(_from)
	root.add_child(load("res://world/forest/forest_level.tscn").instantiate())


func _process(delta: float) -> bool:
	_t += delta
	if _k == null:
		_k = root.find_child("Keling", true, false)
		return false
	if not _started:
		if _t < 4.0:
			return false
		_started = _k.morph_to(_to)
		if not _started:
			print("morph_preview: could not start (mode %d)" % _k.mode)
			quit(1)
			return true
		return false
	var m = _k.morph
	var mt: float = m._t if m else 99.0
	while _shots.size() < TIMES.size() and mt >= TIMES[_shots.size()]:
		var img := root.get_texture().get_image()
		img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
		_shots.append(img)
	if _shots.size() < TIMES.size():
		return false
	var sheet := Image.create(CELL.x * 5, CELL.y * 2, false, _shots[0].get_format())
	for i in _shots.size():
		sheet.blit_rect(_shots[i], Rect2i(Vector2i.ZERO, CELL), Vector2i((i % 5) * CELL.x, (i / 5) * CELL.y))
	sheet.save_png(_out)
	print("morph_preview: saved ", _out)
	KelingCharacters.save_id(KelingCharacters.DEFAULT)
	quit()
	return true
