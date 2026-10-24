extends SceneTree
## Headless check of the pause menu and settings in the real forest: presets,
## custom values, save and load, key rebinding with swaps, the audio buses,
## grass density and tree detail reaching ForestLod, every settings tab
## building, and pausing (solo freezes the world, co-op never does and tells
## friends you're away). Exits non-zero on failure.
##   godot --headless --path . -s res://tools/settings_check.gd

# Untyped on purpose: -s scripts compile before the autoloads exist.
var _settings
var _net
var _hud
var _k
var _lod: ForestLod
var _t := 0.0
var _step := 0
var _fails: Array[String] = []
var _away := []


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	root.add_child(load("res://world/forest/forest_level.tscn").instantiate())


func _check(ok: bool, what: String) -> void:
	print("settings_check: %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


func _process(delta: float) -> bool:
	_t += delta
	if _t > 240.0:
		_check(false, "timed out at step %d" % _step)
		return _finish()
	match _step:
		0:
			_settings = root.get_node_or_null("Settings")
			_net = root.get_node_or_null("Net")
			_hud = root.find_child("HUD", true, false)
			_k = root.find_child("Keling", true, false)
			_lod = root.find_child("Vegetation", true, false) as ForestLod
			if _settings and _hud and _k and _lod and _t > 1.0:
				_step = 1
		1:
			_check_values()
			_check_save_load()
			_check_bindings()
			_check_buses()
			_step = 2
		2:
			_check_density()
			_check_detail()
			_step = 3
		3:
			_check_pause()
			_check_tabs()
			return _finish()
	return false


func _finish() -> bool:
	if _settings:
		_settings.reset_section("graphics")
		_settings.reset_section("audio")
		_settings.reset_section("controls")
		_settings.save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	if _fails.is_empty():
		print("settings_check: PASS")
		quit(0)
	else:
		print("settings_check: FAILED %s" % ", ".join(_fails))
		quit(1)
	return true


func _check_values() -> void:
	_check(_settings.get_value("preset") == "high", "starts on the High preset (today's look)")
	_settings.apply_preset("low")
	_check(_settings.get_value("shadows") == 1 and is_equal_approx(_settings.get_value("render_scale"), 0.67), "Low preset sets its values")
	_settings.set_value("grass", 0.9)
	_check(_settings.get_value("preset") == "custom", "editing a value makes the preset Custom")
	_settings.set_value("grass", 0.45)
	_check(_settings.get_value("preset") == "low", "putting it back finds the preset again")
	_settings.apply_preset("high")
	_check(is_equal_approx(ForestLod.detail, 1.0) and is_equal_approx(ForestLod.density, 1.0), "High preset gives ForestLod full detail")


func _check_save_load() -> void:
	_settings.set_value("music", 0.3)
	_settings.set_value("invert_y", true)
	_settings.save()
	var fresh = load("res://autoload/settings.gd").new()
	fresh.values = fresh.DEFAULTS.duplicate()
	fresh._load()
	_check(is_equal_approx(fresh.values.music, 0.3) and fresh.values.invert_y == true, "settings survive a save and load")
	fresh.free()
	var cam = root.find_child("CameraRig", true, false)
	_check(cam != null and cam.invert_y == true, "the camera picks up invert Y")
	_settings.set_value("invert_y", false)


func _keys(action: String) -> Array:
	var out := []
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			out.append(e.physical_keycode)
	return out


func _check_bindings() -> void:
	var jump: int = _settings.key_of("jump")
	var grab: int = _settings.key_of("grab")
	var swapped: String = _settings.bind_key("jump", grab)
	_check(swapped == "grab", "binding a taken key swaps it")
	_check(_keys("jump")[0] == grab and _keys("grab")[0] == jump, "InputMap follows the swap")
	_check(not _settings.bind_key("jump", KEY_ESCAPE) and _keys("jump")[0] == grab, "Esc can't be bound")
	var fwd_alts := _keys("move_forward")
	_settings.bind_key("move_forward", KEY_I)
	_check(_keys("move_forward")[0] == KEY_I and KEY_UP in _keys("move_forward") and not KEY_W in _keys("move_forward"),
			"rebinding keeps the arrow-key alternate")
	_check(InputMap.action_get_events("jump").size() > _keys("jump").size(), "gamepad buttons stay bound")
	_settings.reset_section("controls")
	_check(_keys("jump")[0] == jump and _keys("move_forward") == fwd_alts, "reset brings the default keys back")


func _check_buses() -> void:
	for b in ["Music", "Ambience", "SFX", "World", "UI"]:
		_check(AudioServer.get_bus_index(b) >= 0, "audio bus %s exists" % b)
	var sound = root.find_child("Soundscape", true, false)
	var on_ambience := sound != null
	if sound:
		for c in sound.get_children():
			if (c is AudioStreamPlayer or c is AudioStreamPlayer3D) and c.bus != &"Ambience":
				on_ambience = false
	_check(on_ambience, "forest sounds play on the Ambience bus")
	_settings.set_value("master", 0.5)
	_check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.5)) < 0.1, "master volume reaches the Master bus")
	_settings.set_value("master", 1.0)


## Visible instances of every band of one scatter group.
func _drawn(group: String) -> int:
	var n := 0
	for c in _lod.get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi and mmi.visible and String(mmi.name).begins_with(group + "_") and mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			n += mmi.multimesh.visible_instance_count
	return n


func _check_density() -> void:
	var eye := Vector3(ForestLayout.SPAWN.x, 2.0, ForestLayout.SPAWN.y)
	_lod.update_now(eye)
	var before := _drawn("grass")
	_settings.set_value("grass", 0.5)
	_lod.update_now(eye)
	var after := _drawn("grass")
	var ratio := after / float(maxi(before, 1))
	print("settings_check:   grass drawn %d -> %d (%.2f)" % [before, after, ratio])
	_check(before > 0 and ratio > 0.4 and ratio < 0.6, "grass density 50% draws about half the blades")
	_settings.set_value("grass", 1.0)
	_lod.update_now(eye)
	_check(_drawn("grass") == before, "grass density 100% draws them all again")


## Sub-cells of tree batches on their full-detail band.
func _full_detail() -> int:
	var n := 0
	for b in _lod.batches:
		if b.key.begins_with("tree_"):
			for s in b.state:
				if s == 0:
					n += 1
	return n


func _check_detail() -> void:
	var eye := Vector3(ForestLayout.SPAWN.x, 2.0, ForestLayout.SPAWN.y)
	_lod.update_now(eye)
	var high := _full_detail()
	_settings.set_value("trees", 0)
	_lod.update_now(eye)
	var low := _full_detail()
	_settings.set_value("trees", 3)
	_lod.update_now(eye)
	var ultra := _full_detail()
	print("settings_check:   tree sub-cells at full detail low %d, high %d, ultra %d" % [low, high, ultra])
	_check(low < high and high < ultra, "tree detail moves the LOD switch distances")
	_settings.set_value("trees", 2)


func _check_pause() -> void:
	var menu = _hud.get("_pause")
	_check(menu != null, "the HUD has a pause menu")
	if menu == null:
		return
	menu.open()
	_check(paused and menu.is_open, "solo: opening the menu pauses the world")
	_check(root.get_node("GameInput").ui_locked, "the Keling ignores input under the menu")
	menu.close()
	_check(not paused and not root.get_node("GameInput").ui_locked, "closing it resumes")
	# Co-op: pretend we're hosting.
	_k.net_event.connect(func(kind, args):
		if kind == &"away":
			_away.append(args[0]))
	_net.status = 2
	menu.open()
	_check(not paused, "co-op: the menu never freezes the world")
	_check(_away == [true], "co-op: friends hear we're taking a break")
	menu.close()
	_check(_away == [true, false], "co-op: and that we're back")
	_net.status = 0
	_k.apply_net_event(&"away", [true])
	_check(_k.get_node_or_null("AwayTag") != null, "a friend's Keling shows the break tag")
	_k.apply_net_event(&"away", [false])


func _check_tabs() -> void:
	var menu = _hud.get("_pause")
	menu.open()
	menu.open_settings()
	var panel = menu.get("_settings")
	var counts := []
	for i in 4:
		panel.show_tab(i, false)
		counts.append(panel.get("_list").get_child_count())
	_check(counts.min() > 1, "every settings tab has rows %s" % str(counts))
	menu.close()
