extends SceneTree
## Screenshots of the pause menu over the real forest (looks only):
## the menu, each settings tab and the quit question.
##   xvfb-run -a godot --path . --rendering-method mobile -s res://tools/pause_preview.gd -- <out dir>
## Needs a Vulkan driver (lavapipe: apt install mesa-vulkan-drivers).

var _out := "user://pause_preview"
var _frame := 0
var _hud
var _shots := [
	[36, "hud", ""],
	[60, "menu", ""],
	[90, "graphics", "settings:0"],
	[120, "audio", "settings:1"],
	[150, "controls", "settings:2"],
	[180, "interface", "settings:3"],
	[210, "quit", "quit"],
]
var _i := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1600, 900)
	root.add_child(load("res://world/forest/forest_level.tscn").instantiate())


func _process(_delta: float) -> bool:
	_frame += 1
	if _hud == null:
		_hud = root.find_child("HUD", true, false)
		return false
	var menu = _hud.get("_pause")
	if _frame == 40:
		menu.open()
	if _i >= _shots.size():
		quit()
		return true
	var shot: Array = _shots[_i]
	if _frame == shot[0] - 20:
		var what: String = shot[2]
		if what.begins_with("settings:"):
			if not menu.get("_settings_open"):
				menu.open_settings()
			menu.get("_settings").show_tab(int(what.get_slice(":", 1)))
		elif what == "quit":
			menu.close_settings()
			menu.call("_ask_quit")
	if _frame == shot[0]:
		var img := root.get_texture().get_image()
		var path := _out.path_join("pause_%s.png" % shot[1])
		img.save_png(path)
		print("pause_preview: wrote ", path)
		_i += 1
	return false
