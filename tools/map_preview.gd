extends SceneTree
## Screenshots of the HUD, the minimap and the world map, plus the painted map
## texture itself. Needs a rendering driver (looks only, not for perf):
##   xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-method gl_compatibility \
##       -s res://tools/map_preview.gd -- <out_dir>

var _t := 0.0
var _out := "user://map_preview"
var _step := 0
var _hud: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.add_child(load("res://world/forest/forest_level.tscn").instantiate())


func _process(delta: float) -> bool:
	_t += delta
	if _hud == null:
		_hud = root.find_child("HUD", true, false)
		return false
	match _step:
		0:
			if _t > 4.0:
				_shot("hud")
				var tex: Texture2D = _hud.map_state.texture
				if tex:
					tex.get_image().save_png(_out + "/map_texture.png")
				_hud._world_map.open()
				_step += 1
		1:
			if _t > 5.5:
				_shot("world_map")
				var pond: Dictionary = _hud.map_state.places[2]
				_hud._world_map._selected = pond
				_hud.map_state.set_waypoint(pond.pos, pond.name)
				_hud._world_map._refresh_card()
				_hud._world_map._zoom_at(_hud._world_map._sheet_center(), 2.0)
				_step += 1
		2:
			if _t > 7.0:
				_shot("world_map_zoom")
				_hud._world_map.close()
				_step += 1
		3:
			if _t > 8.0:
				_shot("hud_waypoint")
				quit(0)
	return false


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("map_preview: saved ", name)
