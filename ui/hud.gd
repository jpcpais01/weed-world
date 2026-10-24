extends CanvasLayer
## In-game HUD: the minimap and world map, place-name banners, touch controls
## on phones, key-cap control hints on desktop / gamepad, an FPS / triangle
## counter (tap it, or press 0, for the debug readout) and a "What's new"
## scroll fed by PATCH_NOTES.md. Everything is built in code
## and laid out for a phone first: big touch targets, notch-safe margins.

const PATCH_NOTES := "res://PATCH_NOTES.md"
const SETTINGS := "user://hud.cfg"
const ARRIVE_DISTANCE := 2.6

var map_state := MapState.new()
var _root: Control
var _touch: TouchControls
var _brand: Control
var _hints: PanelContainer
var _hints_box: VBoxContainer
var _hints_chip: PanelContainer
var _debug: Label
var _stats: Button
var _stats_timer := 0.0
var _notes_btn: RoundIconButton
var _notes_panel: PanelContainer
var _notes_backdrop: ColorRect
var _minimap: Minimap
var _area_pill: PanelContainer
var _area_label: Label
var _banner: AreaBanner
var _world_map: WorldMap
var _beacon: WaypointBeacon
var _baker: MapBaker
var _forest: Forest
var _hint_timer := 14.0
var _hints_open := true
var _debug_on := false
var _area_tick := 0.0
var _current_place := ""
var _place_seen := {}            ## place id -> time it was last announced
var _clock := 0.0
var _notes_hash := ""


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = HudTheme.theme()
	add_child(_root)

	_touch = TouchControls.new()
	_root.add_child(_touch)

	_build_brand()
	_build_hints()

	_debug = Label.new()
	HudTheme.style_label(_debug, 15, Color(0.85, 1, 0.75, 0.95), HudTheme.body_font(700))
	_debug.visible = false
	_root.add_child(_debug)
	_build_stats()

	_banner = AreaBanner.new()
	_root.add_child(_banner)

	_build_minimap()
	_build_notes()

	_world_map = WorldMap.new(map_state)
	_world_map.opened.connect(_on_map_opened)
	_world_map.closed.connect(_on_map_closed)
	_root.add_child(_world_map)

	map_state.waypoint_changed.connect(_on_waypoint_changed)
	GameInput.input_method_changed.connect(func(_m): _refresh())
	_root.resized.connect(_layout)
	_refresh()
	_layout()
	_find_forest.call_deferred()


# ---------------------------------------------------------------------------
# Building blocks

func _build_brand() -> void:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", HudTheme.pill(Color(HudTheme.GLASS, 0.45)))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	chip.add_child(row)
	var leaf := Control.new()
	leaf.custom_minimum_size = Vector2(22, 26)
	leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	leaf.draw.connect(func():
		MapIcons.leaf(leaf, Vector2(4, 24), Vector2(0.45, -0.9).normalized(), 24.0, 13.0, HudTheme.LEAF)
		leaf.draw_line(Vector2(4, 24), Vector2(12, 9), Color(HudTheme.MOSS, 0.9), 1.6, true))
	row.add_child(leaf)
	var name := Label.new()
	name.text = "Weed World"
	HudTheme.style_label(name, 22, HudTheme.CREAM, HudTheme.title_font(600))
	row.add_child(name)
	var ver := Label.new()
	ver.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.1")
	HudTheme.style_label(ver, 14, Color(HudTheme.CREAM, 0.6), HudTheme.body_font(700), false)
	ver.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ver)
	_brand = chip
	_root.add_child(chip)


## Frame rate and triangles drawn, always on; tapping it toggles the debug
## readout.
func _build_stats() -> void:
	_stats = Button.new()
	_stats.flat = true
	_stats.focus_mode = Control.FOCUS_NONE
	_stats.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_stats.add_theme_font_override("font", HudTheme.body_font(750))
	_stats.add_theme_font_size_override("font_size", 13)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_stats.add_theme_color_override(st, Color(HudTheme.LEAF, 0.9))
	_stats.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	_stats.add_theme_constant_override("outline_size", 4)
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 10
	pad.content_margin_top = 2
	pad.content_margin_bottom = 2
	for st in ["normal", "hover", "pressed", "focus"]:
		_stats.add_theme_stylebox_override(st, pad)
	_stats.text = "-- FPS  ·  -- triangles"
	_stats.add_to_group("touch_blockers")
	_stats.pressed.connect(_toggle_debug)
	_root.add_child(_stats)


func _toggle_debug() -> void:
	_debug_on = not _debug_on
	_debug.visible = _debug_on


## 1234 -> "1234", 48210 -> "48.2k", 1250000 -> "1.25M"
static func _short(n: int) -> String:
	if n >= 1000000:
		return "%.2fM" % (n / 1000000.0)
	if n >= 10000:
		return "%.1fk" % (n / 1000.0)
	return str(n)


func _build_hints() -> void:
	_hints = PanelContainer.new()
	_hints.add_theme_stylebox_override("panel", HudTheme.glass(18, 0.5, 14.0))
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints_box = VBoxContainer.new()
	_hints_box.add_theme_constant_override("separation", 8)
	_hints.add_child(_hints_box)
	_root.add_child(_hints)

	_hints_chip = PanelContainer.new()
	_hints_chip.add_theme_stylebox_override("panel", HudTheme.pill(Color(HudTheme.GLASS, 0.4)))
	_hints_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_keycap("H"))
	var l := Label.new()
	l.text = "Controls"
	HudTheme.style_label(l, 15, Color(HudTheme.CREAM, 0.8), HudTheme.body_font(700))
	row.add_child(l)
	_hints_chip.add_child(row)
	_hints_chip.modulate.a = 0.0
	_root.add_child(_hints_chip)


func _build_minimap() -> void:
	_minimap = Minimap.new(map_state)
	_minimap.open_requested.connect(func(): _world_map.open())
	_minimap.visible = false
	_root.add_child(_minimap)

	_area_pill = PanelContainer.new()
	_area_pill.add_theme_stylebox_override("panel", HudTheme.pill(Color(HudTheme.GLASS, 0.55)))
	_area_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area_label = Label.new()
	HudTheme.style_label(_area_label, 16, HudTheme.CREAM, HudTheme.title_font(560))
	_area_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_area_pill.add_child(_area_label)
	_area_pill.visible = false
	_root.add_child(_area_pill)

	_notes_btn = RoundIconButton.new("notes", 50.0)
	_notes_btn.tooltip_text = "What's new"
	_notes_btn.pressed.connect(_toggle_notes)
	_root.add_child(_notes_btn)


func _keycap(text: String, gamepad := false) -> PanelContainer:
	var cap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var face := HudTheme.CREAM
	if gamepad:
		face = {"A": Color(0.55, 0.85, 0.45), "B": Color(1.0, 0.55, 0.5), "X": Color(0.5, 0.75, 1.0), "Y": Color(1.0, 0.85, 0.4)}.get(text, HudTheme.CREAM)
	sb.bg_color = face
	sb.set_corner_radius_all(14 if gamepad and text.length() == 1 else 7)
	sb.border_color = HudTheme.INK
	sb.set_border_width_all(2)
	sb.border_width_bottom = 4
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	sb.anti_aliasing = true
	cap.add_theme_stylebox_override("panel", sb)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	HudTheme.style_label(l, 15, HudTheme.INK, HudTheme.title_font(600), false)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 14
	cap.add_child(l)
	return cap


## One hint row: [[keys...], "what it does"] pairs laid out side by side.
func _hint_row(items: Array, gamepad: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for i in items.size():
		var item: Array = items[i]
		if i > 0:
			var gap := Control.new()
			gap.custom_minimum_size.x = 14
			row.add_child(gap)
		for key in item[0]:
			row.add_child(_keycap(key, gamepad))
		var l := Label.new()
		l.text = item[1]
		HudTheme.style_label(l, 16, Color(HudTheme.CREAM, 0.92), HudTheme.body_font(700))
		row.add_child(l)
	return row


func _build_notes() -> void:
	_notes_backdrop = ColorRect.new()
	_notes_backdrop.color = Color(0.02, 0.05, 0.03, 0.45)
	_notes_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_notes_backdrop.visible = false
	_notes_backdrop.add_to_group("touch_blockers")
	_notes_backdrop.gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
			_toggle_notes())
	_root.add_child(_notes_backdrop)

	_notes_panel = PanelContainer.new()
	_notes_panel.add_theme_stylebox_override("panel", HudTheme.glass(24, 0.9, 26.0))
	_notes_panel.visible = false
	_notes_panel.add_to_group("touch_blockers")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_notes_panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "What's new in the forest"
	HudTheme.style_label(title, 30, HudTheme.CREAM, HudTheme.title_font(600))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := RoundIconButton.new("close", 46.0, true)
	close.pressed.connect(_toggle_notes)
	head.add_child(close)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.scroll_active = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 17)
	text.add_theme_font_size_override("bold_font_size", 19)
	text.add_theme_constant_override("line_separation", 4)
	var md := _notes_text()
	_notes_hash = str(md.hash())
	text.text = _notes_bbcode(md)
	box.add_child(text)
	_root.add_child(_notes_panel)
	_notes_btn.dot = _setting("notes_seen", "") != _notes_hash and md != ""


func _notes_text() -> String:
	var f := FileAccess.open(PATCH_NOTES, FileAccess.READ)
	return f.get_as_text() if f else ""


func _notes_bbcode(md: String) -> String:
	if md == "":
		return "[b]No patch notes yet.[/b]"
	var out := PackedStringArray()
	for line in md.split("\n"):
		if line.begins_with("# "):
			continue
		elif line.begins_with("## "):
			out.append("\n[color=#ffd479][font_size=20][b]%s[/b][/font_size][/color]" % line.substr(3))
		elif line.begins_with("- "):
			var body := line.substr(2)
			# **Headline.** rest -> leafy bullet, bold cream headline.
			var parts := body.split("**")
			if parts.size() >= 3:
				body = "[b][color=#fff6df]%s[/color][/b]%s" % [parts[1], "**".join(parts.slice(2))]
			out.append("[color=#b8e588]•[/color]  " + body.replace("**", ""))
		elif not line.strip_edges().is_empty():
			out.append("[color=#cfd8cc]%s[/color]" % line)
	return "\n".join(out).strip_edges()


func _toggle_notes() -> void:
	_notes_panel.visible = not _notes_panel.visible
	_notes_backdrop.visible = _notes_panel.visible
	_touch.visible = GameInput.method == GameInput.Method.TOUCH and not _notes_panel.visible and not _world_map.is_open
	if _notes_panel.visible:
		_world_map.close()
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_notes_btn.dot = false
		_store_setting("notes_seen", _notes_hash)
	_layout()


# ---------------------------------------------------------------------------
# Layout

func _safe_insets() -> Vector4:
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0 or safe.size.x <= 0 or not OS.has_feature("mobile"):
		return Vector4.ZERO
	var k := _root.size.x / float(win.x)
	return Vector4(safe.position.x * k, safe.position.y * k, (win.x - safe.end.x) * k, (win.y - safe.end.y) * k)


func _layout() -> void:
	var s := _root.size
	var inset := _safe_insets()
	var left := 22.0 + inset.x
	var top := 18.0 + inset.y
	var right := 22.0 + inset.z
	var bottom := 22.0 + inset.w

	_brand.reset_size()
	_brand.position = Vector2(left, top)
	_stats.reset_size()
	_stats.position = Vector2(left, _brand.position.y + _brand.size.y + 4.0)
	_debug.position = Vector2(left + 8.0, _stats.position.y + _stats.size.y + 4.0)

	var mm := _minimap.size
	_minimap.position = Vector2(s.x - right - mm.x + 8.0, top - 8.0)
	_area_pill.reset_size()
	var pill_w := maxf(_area_pill.size.x, 120.0)
	_area_pill.size.x = pill_w
	_area_pill.position = Vector2(_minimap.position.x + mm.x * 0.5 - pill_w * 0.5, _minimap.position.y + mm.y - 4.0)
	var nb := _notes_btn.size
	if _minimap.visible:
		_notes_btn.position = _minimap.position + Vector2(-nb.x + 14.0, mm.y * 0.5 + 34.0)
	else:
		_notes_btn.position = Vector2(s.x - right - nb.x, top)

	_hints.reset_size()
	_hints.position = Vector2(left, s.y - bottom - _hints.size.y)
	_hints_chip.reset_size()
	_hints_chip.position = Vector2(left, s.y - bottom - _hints_chip.size.y)

	var nsize := Vector2(minf(720.0, s.x - 48.0), minf(560.0, s.y - 48.0))
	_notes_panel.size = nsize
	_notes_panel.position = (s - nsize) * 0.5


func _refresh() -> void:
	var touch := GameInput.method == GameInput.Method.TOUCH
	_touch.visible = touch and not _world_map.is_open and not _notes_panel.visible
	for c in _hints_box.get_children():
		c.queue_free()
	var rows: Array = []
	var pad := GameInput.method == GameInput.Method.GAMEPAD
	match GameInput.method:
		GameInput.Method.TOUCH:
			rows = []
		GameInput.Method.GAMEPAD:
			rows = [
				[[["L"], "move"], [["R"], "camera"], [["LB", "RB"], "zoom"]],
				[[["A"], "jump"], [["X"], "grab"], [["B"], "sprint"], [["Y"], "map"]],
				[[["D-pad"], "dance · cheer · sit · nod"], [["View"], "debug"]],
			]
		_:
			rows = [
				[[["W", "A", "S", "D"], "move"], [["Shift"], "sprint"], [["C"], "walk"]],
				[[["Space"], "jump"], [["E"], "grab"], [["M"], "map"], [["Esc"], "free mouse"]],
				[[["1", "2", "3", "4"], "dance · cheer · sit · nod"], [["0"], "debug"], [["F11"], "fullscreen"]],
			]
	for r in rows:
		_hints_box.add_child(_hint_row(r, pad))
	_hints_open = not rows.is_empty()
	_hint_timer = 14.0
	_hints.visible = _hints_open
	_hints.modulate.a = 1.0
	_hints_chip.modulate.a = 0.0
	_layout.call_deferred()


# ---------------------------------------------------------------------------
# Map wiring

func _find_forest() -> void:
	# The level owns both the forest and this HUD; fall back to the scene.
	for scene in [get_parent(), get_tree().current_scene]:
		if scene and _forest == null:
			_forest = _search_forest(scene, 3)
	if _forest == null:
		return
	map_state.places = MapLandmarks.all(_forest)
	_minimap.visible = true
	_area_pill.visible = true
	_baker = MapBaker.new()
	_baker.name = "MapBaker"
	add_child(_baker)
	_baker.baked.connect(map_state.set_texture)
	_baker.bake(_forest)
	_beacon = WaypointBeacon.new()
	_beacon.name = "WaypointBeacon"
	_forest.add_child(_beacon)
	_layout()
	# The opening title card.
	_place_seen["trailhead"] = 0.0
	_current_place = "trailhead"
	get_tree().create_timer(1.2).timeout.connect(func():
		_banner.show_place("The Whispering Glade", "Explore together · find new strains · share the view", HudTheme.LEAF, 3.6))


func _search_forest(n: Node, depth: int) -> Forest:
	if n is Forest:
		return n
	if depth <= 0:
		return null
	for c in n.get_children():
		var f := _search_forest(c, depth - 1)
		if f:
			return f
	return null


func _on_map_opened() -> void:
	_touch.visible = false
	_minimap.visible = false
	_area_pill.visible = false
	_hints.visible = false
	_hints_chip.visible = false
	_notes_btn.visible = false
	if _notes_panel.visible:
		_toggle_notes()


func _on_map_closed() -> void:
	_touch.visible = GameInput.method == GameInput.Method.TOUCH
	_minimap.visible = _forest != null
	_area_pill.visible = _forest != null
	_hints.visible = _hints_open
	_hints_chip.visible = true
	_notes_btn.visible = true


func _on_waypoint_changed() -> void:
	if _beacon == null:
		return
	if map_state.has_waypoint:
		var p := map_state.waypoint
		_beacon.show_at(Vector3(p.x, _forest.ground_height(p.x, p.y), p.y))
	else:
		_beacon.hide_beacon()


func _update_area() -> void:
	var me := MapState.local_player(get_tree())
	if me.is_empty():
		return
	var pos: Vector2 = me.pos
	# Hysteresis: stay "in" a place until you are well clear of it.
	var here := MapLandmarks.place_at(map_state.places, pos)
	if here.is_empty() and _current_place != "":
		for pl in map_state.places:
			if pl.id == _current_place and pos.distance_to(pl.pos) < pl.radius + 2.5:
				here = pl
	var id: String = here.get("id", "")
	if id != _current_place:
		_current_place = id
		if id != "" and _clock - (_place_seen.get(id, -999.0) as float) > 90.0:
			_place_seen[id] = _clock
			_banner.show_place(here.name, here.blurb)
	var label: String = here.name if id != "" else MapLandmarks.region_at(pos)
	if _area_label.text != label:
		_area_label.text = label
		_layout()
	if map_state.has_waypoint and pos.distance_to(map_state.waypoint) < ARRIVE_DISTANCE:
		var nm := map_state.waypoint_name
		map_state.clear_waypoint()
		Input.vibrate_handheld(30)
		_banner.show_place(nm if nm != "" else "You made it", "Waypoint reached", HudTheme.GOLD, 2.4)


# ---------------------------------------------------------------------------
# Settings

func _setting(key: String, default: Variant) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) != OK:
		return default
	return cfg.get_value("hud", key, default)


func _store_setting(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("hud", key, value)
	cfg.save(SETTINGS)


# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_toggle_debug()
	elif event.is_action_pressed("controls_help") and GameInput.method != GameInput.Method.TOUCH:
		_hints_open = not _hints_open
		_hint_timer = 14.0 if _hints_open else 0.0
		_hints.visible = _hints_open
		_hints.modulate.a = 1.0


func _process(delta: float) -> void:
	_clock += delta
	# Hints fade away once you have had a good look, leaving a small chip.
	if _hints_open:
		if _hint_timer > 0.0:
			_hint_timer -= delta
		else:
			_hints.modulate.a = move_toward(_hints.modulate.a, 0.0, delta * 1.2)
			if _hints.modulate.a <= 0.0:
				_hints_open = false
				_hints.visible = false
	var chip_target := 0.0 if _hints_open or GameInput.method == GameInput.Method.TOUCH else 1.0
	_hints_chip.modulate.a = move_toward(_hints_chip.modulate.a, chip_target, delta * 2.0)

	if _forest:
		_area_tick -= delta
		if _area_tick <= 0.0:
			_area_tick = 0.25
			_update_area()

	_stats_timer -= delta
	if _stats_timer <= 0.0:
		_stats_timer = 0.25
		var tris := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		_stats.text = "%d FPS  ·  %s triangles" % [Engine.get_frames_per_second(), _short(tris)]
	if _debug_on:
		var player := get_tree().get_first_node_in_group("player")
		if player and player.has_method("get_debug_text"):
			_debug.text = player.get_debug_text()
