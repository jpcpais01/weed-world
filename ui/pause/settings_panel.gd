class_name SettingsPanel
extends PanelContainer
## The settings card in the pause menu: Graphics, Audio, Controls and
## Interface tabs over one scrolling list of MenuRows. Everything applies
## live (autoload/settings.gd) and saves on its own. Bumpers or Q / E switch
## tabs; keyboard keys can be rebound from the Controls tab.

signal close_requested

const TABS := [
	["graphics", "Graphics", "sliders"],
	["audio", "Audio", "speaker"],
	["controls", "Controls", "gamepad"],
	["interface", "Interface", "eye"],
]
const GAMEPAD := [
	["Left stick", "Move"], ["Right stick", "Look around"], ["A", "Jump"], ["X", "Grab · pick · sit"], ["B", "Sprint"],
	["Y", "Map"], ["RT", "Roll · light · smoke"], ["LB / RB", "Zoom"], ["D-pad", "Dance · cheer · sit · nod"],
	["Start", "This menu"], ["View", "Frame-time readout"],
]

var _settings: Node
var _tab := 0
var _tab_row: HBoxContainer
var _tab_buttons: Array[Button] = []
var _pad_hints: Array[Control] = []
var _scroll: ScrollContainer
var _list: VBoxContainer
var _rows := {}               ## setting key -> MenuRow
var _key_rows := {}           ## action -> MenuRow
var _listening: MenuRow
var _listen_action := ""
var _hint: Label
var _reset: Button
var _hint_hold := 0.0
var _tick := 0.0


func _ready() -> void:
	_settings = get_node_or_null("/root/Settings")
	add_theme_stylebox_override("panel", HudTheme.glass(28, 0.9, 22.0))
	add_to_group("touch_blockers")
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	if _settings:
		_settings.changed.connect(_on_setting_changed)
		_settings.bindings_changed.connect(_refresh_keys)
	GameInput.input_method_changed.connect(func(_m): _refresh_pad_hints())
	show_tab(0, false)


func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	var title := Label.new()
	title.text = "Settings"
	HudTheme.style_label(title, 30, HudTheme.CREAM, HudTheme.title_font(600))
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size.x = 10
	head.add_child(gap)
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 6)
	_tab_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_tab_row)
	_tab_row.add_child(_pad_cap("LB"))
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i][1]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_size_override("font_size", 18)
		b.add_to_group("touch_blockers")
		b.pressed.connect(show_tab.bind(i))
		_tab_row.add_child(b)
		_tab_buttons.append(b)
	_tab_row.add_child(_pad_cap("RB"))
	var x := RoundIconButton.new("close", 44.0, true)
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	x.tooltip_text = "Back"
	x.pressed.connect(func(): close_requested.emit())
	head.add_child(x)

	var line := ColorRect.new()
	line.color = Color(HudTheme.CREAM, 0.12)
	line.custom_minimum_size.y = 2
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.add_to_group("touch_blockers")
	box.add_child(_scroll)
	# Room on the right for the scroll bar.
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 14)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(margin)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	margin.add_child(_list)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	box.add_child(foot)
	_hint = Label.new()
	HudTheme.style_label(_hint, 15, Color(HudTheme.CREAM, 0.6), HudTheme.body_font(700), false)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hint.clip_text = true
	foot.add_child(_hint)
	_reset = Button.new()
	_reset.text = "Reset tab"
	_reset.focus_mode = Control.FOCUS_NONE
	_reset.custom_minimum_size = Vector2(140, 44)
	_reset.add_to_group("touch_blockers")
	_reset.pressed.connect(_reset_tab)
	foot.add_child(_reset)
	_refresh_pad_hints()


func _pad_cap(text: String) -> Control:
	var cap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = HudTheme.CREAM
	sb.set_corner_radius_all(8)
	sb.border_color = HudTheme.INK
	sb.set_border_width_all(2)
	sb.border_width_bottom = 3
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.anti_aliasing = true
	cap.add_theme_stylebox_override("panel", sb)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	HudTheme.style_label(l, 13, HudTheme.INK, HudTheme.title_font(650), false)
	cap.add_child(l)
	_pad_hints.append(cap)
	return cap


func _refresh_pad_hints() -> void:
	var pad := GameInput.method == GameInput.Method.GAMEPAD
	for c in _pad_hints:
		c.visible = pad


# ---------------------------------------------------------------------------
# Tabs

func show_tab(i: int, focus := true) -> void:
	_cancel_listen()
	_tab = wrapi(i, 0, TABS.size())
	for k in _tab_buttons.size():
		var b := _tab_buttons[k]
		var on := k == _tab
		var fill := HudTheme.LEAF if on else Color(HudTheme.GLASS, 0.45)
		b.add_theme_stylebox_override("normal", HudTheme.pill(fill, Color(1, 1, 1, 0.3 if on else 0.12), 18))
		b.add_theme_stylebox_override("hover", HudTheme.pill(fill.lightened(0.1) if on else Color(0.14, 0.24, 0.13, 0.7), Color(1, 1, 1, 0.45), 18))
		b.add_theme_stylebox_override("pressed", HudTheme.pill(fill.darkened(0.1), Color(1, 1, 1, 0.45), 18))
		for st in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(st, HudTheme.INK if on else HudTheme.CREAM)
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	_key_rows.clear()
	match TABS[_tab][0]:
		"graphics":
			_build_graphics()
		"audio":
			_build_audio()
		"controls":
			_build_controls()
		"interface":
			_build_interface()
	_scroll.scroll_vertical = 0
	_hint_hold = 0.0
	_update_hint()
	if focus:
		focus_first()


## Selects the first row (for keyboard and gamepad players).
func focus_first() -> void:
	if GameInput.method == GameInput.Method.TOUCH:
		return
	for c in _list.get_children():
		if c is MenuRow and c.focus_mode != Control.FOCUS_NONE:
			MenuRow.quiet_focus(c)
			return


func _reset_tab() -> void:
	if _settings == null:
		return
	_settings.reset_section(TABS[_tab][0])
	UiSound.play("back")
	_flash("Back to the way it started.")
	_refresh_keys()


# ---------------------------------------------------------------------------
# Rows

static func _pct(v) -> String:
	return "%d%%" % roundi(float(v) * 100.0)


static func _times(v) -> String:
	return "×%.2f" % float(v) if float(v) < 1.0 else "×%.1f" % float(v)


static func _deg(v) -> String:
	return "%d°" % roundi(float(v))


func _section(text: String, note := "") -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var top := Control.new()
	top.custom_minimum_size.y = 10 if _list.get_child_count() > 0 else 0
	box.add_child(top)
	var l := Label.new()
	l.text = text.to_upper()
	HudTheme.style_label(l, 14, HudTheme.GOLD, HudTheme.title_font(650), false)
	l.add_theme_constant_override("line_spacing", 0)
	box.add_child(l)
	if note != "":
		var n := Label.new()
		n.text = note
		HudTheme.style_label(n, 14, Color(HudTheme.CREAM, 0.5), HudTheme.body_font(650), false)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(n)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_child(box)


func _bind(key: String, row: MenuRow) -> MenuRow:
	row.show_value(_value_of(key))
	if row.kind == MenuRow.Kind.TOGGLE:
		row._knob = 1.0 if row.value else 0.0
	row.value_changed.connect(func(v):
		if _settings:
			_settings.set_value(key, v))
	_rows[key] = row
	_list.add_child(row)
	return row


func _value_of(key: String) -> Variant:
	return _settings.get_value(key) if _settings else GameSettings.DEFAULTS.get(key)


func _slider(key: String, title: String, sub: String, lo: float, hi: float, step: float, fmt: Callable) -> MenuRow:
	return _bind(key, MenuRow.make_slider(title, sub, lo, hi, step, fmt))


func _choice(key: String, title: String, sub: String, labels: Array, vals: Array) -> MenuRow:
	return _bind(key, MenuRow.make_choice(title, sub, labels, vals))


func _toggle(key: String, title: String, sub: String) -> MenuRow:
	return _bind(key, MenuRow.make_toggle(title, sub))


func _build_graphics() -> void:
	var mobile := OS.has_feature("mobile")
	_section("Quality")
	var preset := _choice("preset", "Quality preset", "Sets everything below in one go",
			["Low", "Medium", "High", "Ultra"], ["low", "medium", "high", "ultra"])
	preset.accent = HudTheme.GOLD
	_slider("render_scale", "Resolution", "The biggest speed-up · sharpened with FSR", 0.5, 1.0, 0.05, _pct)
	_choice("shadows", "Shadows", "Long soft sun shadows cost the most", ["Off", "Low", "Medium", "High", "Ultra"], [0, 1, 2, 3, 4])
	_choice("trees", "Tree detail", "How far trees keep their full shape", ["Low", "Medium", "High", "Ultra"], [0, 1, 2, 3])
	_slider("grass", "Grass & flowers", "How thick the meadows grow", 0.25, 1.0, 0.05, _pct)
	_choice("aa", "Anti-aliasing", "Smooths jagged edges", ["Off", "FXAA", "MSAA 2×", "MSAA 4×"], [0, 1, 2, 3])
	_toggle("bloom", "Bloom", "Glow on fireflies, magic and sunlight")
	_section("Display")
	if not mobile:
		_toggle("vsync", "VSync", "Matches your screen, no tearing")
	_choice("fps_cap", "Frame rate cap", "Lower saves battery" if mobile else "Keeps laptops cool and quiet",
			["Unlimited", "30", "60", "90", "120", "144"], [0, 30, 60, 90, 120, 144])


func _build_audio() -> void:
	_section("Volume")
	var m := _slider("master", "Master", "Everything at once", 0.0, 1.0, 0.05, _pct)
	m.accent = HudTheme.GOLD
	_slider("music", "Music", "Gentle tunes that drift in now and then", 0.0, 1.0, 0.05, _pct)
	_slider("ambience", "Ambience", "Wind, water, birds and crickets", 0.0, 1.0, 0.05, _pct)
	_slider("sfx", "Effects", "Rolling, smoking and the menu", 0.0, 1.0, 0.05, _pct)
	if not OS.has_feature("mobile"):
		_section("Window")
		_toggle("mute_unfocused", "Mute in the background", "Goes quiet when you switch windows")


func _build_controls() -> void:
	var mobile := OS.has_feature("mobile")
	_section("Camera")
	if not mobile:
		_slider("mouse_sens", "Mouse sensitivity", "", 0.2, 3.0, 0.05, _times)
	if mobile or DisplayServer.is_touchscreen_available():
		_slider("touch_sens", "Touch look speed", "", 0.2, 3.0, 0.05, _times)
	_slider("pad_sens", "Gamepad look speed", "", 0.2, 3.0, 0.05, _times)
	_toggle("invert_y", "Invert up / down", "")
	_toggle("invert_x", "Invert left / right", "")
	_toggle("auto_camera", "Camera follows you", "Swings in behind your Keling as you run")
	_slider("fov", "Field of view", "Wider sees more of the forest", 50.0, 80.0, 1.0, _deg)
	if not mobile:
		_section("Keyboard", "Pick an action, then press its new key. Esc cancels. Taken keys swap over.")
		for pair in GameSettings.REBINDABLE:
			var row := MenuRow.make_key(pair[1], _settings.key_label(pair[0]) if _settings else "")
			row.activated.connect(_listen.bind(row, String(pair[0])))
			_key_rows[pair[0]] = row
			_list.add_child(row)
	_section("Gamepad")
	for pair in GAMEPAD:
		_list.add_child(MenuRow.make_info(pair[1], pair[0]))


func _build_interface() -> void:
	_section("On screen")
	_toggle("show_fps", "Frame-rate counter", "Tap it in game for the frame-time readout")
	if not OS.has_feature("mobile"):
		_toggle("show_hints", "Control hints", "The key and button reminders, bottom left")


func _on_setting_changed(key: String) -> void:
	var row: MenuRow = _rows.get(key)
	if row:
		row.show_value(_value_of(key))


# ---------------------------------------------------------------------------
# Key binding

func _listen(row: MenuRow, action: String) -> void:
	if _listening == row:
		_cancel_listen()
		return
	_cancel_listen()
	_listening = row
	_listen_action = action
	row.listening = true
	row.queue_redraw()
	_flash("Press the new key for %s…" % row.title, 30.0)


func _cancel_listen() -> void:
	if _listening and is_instance_valid(_listening):
		_listening.listening = false
		_listening.queue_redraw()
	_listening = null
	_listen_action = ""


func is_listening() -> bool:
	return _listening != null


func _refresh_keys() -> void:
	if _settings == null:
		return
	for a in _key_rows:
		var row: MenuRow = _key_rows[a]
		row.keycap = _settings.key_label(a)
		row.queue_redraw()


func _input(event: InputEvent) -> void:
	if _listening == null or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).physical_keycode
		if k == KEY_NONE:
			k = (event as InputEventKey).keycode
		get_viewport().set_input_as_handled()
		var action := _listen_action
		var row := _listening
		_cancel_listen()
		if k == KEY_ESCAPE:
			UiSound.play("back")
			_flash("")
			return
		if k in GameSettings.RESERVED:
			_flash("That key is taken by the game.")
			return
		var swapped: String = _settings.bind_key(action, k)
		_refresh_keys()
		UiSound.play("confirm")
		if swapped != "":
			_flash("%s is now %s · %s moved to %s" % [row.title, _settings.key_label(action), _label_of(swapped), _settings.key_label(swapped)], 4.0)
		else:
			_flash("%s is now %s" % [row.title, _settings.key_label(action)], 3.0)
	elif (event is InputEventMouseButton and event.pressed) or (event is InputEventJoypadButton and event.pressed):
		_cancel_listen()
		_flash("")


static func _label_of(action: String) -> String:
	for pair in GameSettings.REBINDABLE:
		if pair[0] == action:
			return pair[1]
	return action


# ---------------------------------------------------------------------------

func _flash(text: String, hold := 3.0) -> void:
	_hint.text = text
	_hint.add_theme_color_override("font_color", HudTheme.GOLD if text != "" else Color(HudTheme.CREAM, 0.6))
	_hint_hold = hold if text != "" else 0.0
	if text == "":
		_update_hint()


func _update_hint() -> void:
	_hint.add_theme_color_override("font_color", Color(HudTheme.CREAM, 0.6))
	match TABS[_tab][0]:
		"graphics":
			var vp := get_viewport()
			var px := Vector2(DisplayServer.window_get_size()) * vp.scaling_3d_scale if vp else Vector2.ZERO
			_hint.text = "%d FPS  ·  drawing %d × %d  ·  saved as you go" % [Engine.get_frames_per_second(), px.x, px.y]
		"audio":
			_hint.text = "Saved as you go"
		"controls":
			_hint.text = "LB / RB switch tabs  ·  B goes back" if GameInput.method == GameInput.Method.GAMEPAD else "Saved as you go"
		_:
			_hint.text = "Saved as you go"


## Q / E and the bumpers flip tabs.
func handle_tab_keys(event: InputEvent) -> bool:
	if _listening:
		return false
	var dir := 0
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			dir = -1
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			dir = 1
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_Q:
				dir = -1
			KEY_E:
				dir = 1
	if dir == 0:
		return false
	UiSound.play("move", 1.15)
	show_tab(_tab + dir)
	return true


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _hint_hold > 0.0:
		_hint_hold -= delta
		if _hint_hold <= 0.0:
			_update_hint()
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		_update_hint()
