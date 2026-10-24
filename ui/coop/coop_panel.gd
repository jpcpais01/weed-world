class_name CoopPanel
extends Control
## "Play together": open your forest to up to three friends, or join one by
## their six-letter code. Shows the code big enough to read out across a
## room, who's in (in their map colours, with their connection), and lets you
## pick the name that floats over your Keling. Works the same with touch,
## mouse and keyboard; P opens it on desktop.

signal opened
signal closed

const CARD_WIDTH := 560.0

var is_open := false

var _net: Node
var _backdrop: ColorRect
var _card: PanelContainer
var _name_edit: LineEdit
var _dice: RoundIconButton
var _offline: VBoxContainer
var _busy: VBoxContainer
var _busy_label: Label
var _room: VBoxContainer
var _code_label: Label
var _code_caption: Label
var _copy: RoundIconButton
var _copied: Label
var _roster: VBoxContainer
var _leave: Button
var _code_edit: LineEdit
var _join: Button
var _host: Button
var _error: Label
var _hint: Label
var _pop := 0.0
var _t := 0.0
var _copied_t := 0.0
var _prev_lock := false
var _art: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_net = get_node_or_null("/root/Net")
	_build()
	if _net:
		_net.status_changed.connect(_sync)
		_net.roster_changed.connect(_sync)
	resized.connect(_layout)
	_sync()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	_pop = 0.0
	_prev_lock = GameInput.ui_locked
	GameInput.ui_locked = true
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync()
	_layout()
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	GameInput.ui_locked = _prev_lock
	get_viewport().gui_release_focus()
	closed.emit()


# ---------------------------------------------------------------------------
# Building

func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.02, 0.05, 0.03, 0.5)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.add_to_group("touch_blockers")
	_backdrop.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(_backdrop)

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", HudTheme.glass(26, 0.92, 26.0))
	_card.add_to_group("touch_blockers")
	_card.pivot_offset = Vector2(CARD_WIDTH * 0.5, 200)
	add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	_card.add_child(box)

	# Title row.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	box.add_child(head)
	var art := Control.new()
	art.custom_minimum_size = Vector2(64, 56)
	art.draw.connect(_draw_art.bind(art))
	head.add_child(art)
	_art = art
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var title := Label.new()
	title.text = "Play together"
	HudTheme.style_label(title, 32, HudTheme.CREAM, HudTheme.title_font(600))
	titles.add_child(title)
	var sub := Label.new()
	sub.text = "Up to four Kelings in one forest · phone or PC"
	HudTheme.style_label(sub, 16, Color(HudTheme.CREAM, 0.7), HudTheme.body_font(650), false)
	titles.add_child(sub)
	var x := RoundIconButton.new("close", 46.0, true)
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	x.pressed.connect(close)
	head.add_child(x)

	# Your name.
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	box.add_child(name_row)
	var you := Label.new()
	you.text = "Your name"
	HudTheme.style_label(you, 17, Color(HudTheme.CREAM, 0.8), HudTheme.body_font(750), false)
	you.custom_minimum_size.x = 104
	you.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(you)
	_name_edit = _line_edit("Your Keling's name", 18)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_t): _commit_name(); get_viewport().gui_release_focus())
	_name_edit.focus_exited.connect(_commit_name)
	name_row.add_child(_name_edit)
	_dice = RoundIconButton.new("dice", 46.0)
	_dice.tooltip_text = "Pick a random name"
	_dice.pressed.connect(func():
		if _net:
			_name_edit.text = _net.random_name()
			_commit_name())
	name_row.add_child(_dice)

	# Offline: host or join.
	_offline = VBoxContainer.new()
	_offline.add_theme_constant_override("separation", 12)
	box.add_child(_offline)
	_host = _big_button("Open my forest", HudTheme.LEAF)
	_host.pressed.connect(func():
		if _net:
			_net.host())
	_offline.add_child(_host)
	var cap := Label.new()
	cap.text = "You'll get a code to send your friends."
	HudTheme.style_label(cap, 15, Color(HudTheme.CREAM, 0.6), HudTheme.body_font(650), false)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offline.add_child(cap)
	_offline.add_child(_divider("or join a friend"))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	_offline.add_child(join_row)
	_code_edit = _line_edit("Their code, like K7M-2QX", 9)
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.add_theme_font_override("font", HudTheme.title_font(600))
	_code_edit.add_theme_font_size_override("font_size", 24)
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_code_edit.text_changed.connect(_on_code_typed)
	_code_edit.text_submitted.connect(func(_t): _do_join())
	join_row.add_child(_code_edit)
	_join = _big_button("Join", HudTheme.WATER)
	_join.custom_minimum_size.x = 120
	_join.pressed.connect(_do_join)
	join_row.add_child(_join)

	# Connecting.
	_busy = VBoxContainer.new()
	_busy.add_theme_constant_override("separation", 14)
	box.add_child(_busy)
	_busy_label = Label.new()
	HudTheme.style_label(_busy_label, 22, HudTheme.CREAM, HudTheme.title_font(500))
	_busy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_busy_label.custom_minimum_size.y = 64
	_busy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_busy.add_child(_busy_label)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.custom_minimum_size = Vector2(160, 48)
	cancel.pressed.connect(func():
		if _net:
			_net.leave())
	_busy.add_child(cancel)

	# In a room: the code and who's here.
	_room = VBoxContainer.new()
	_room.add_theme_constant_override("separation", 12)
	box.add_child(_room)
	var code_box := PanelContainer.new()
	var sb := HudTheme.glass(20, 0.5, 16.0)
	sb.bg_color = Color(0.02, 0.05, 0.03, 0.45)
	code_box.add_theme_stylebox_override("panel", sb)
	_room.add_child(code_box)
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 12)
	code_box.add_child(code_row)
	var code_col := VBoxContainer.new()
	code_col.add_theme_constant_override("separation", -4)
	code_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(code_col)
	_code_caption = Label.new()
	HudTheme.style_label(_code_caption, 15, Color(HudTheme.CREAM, 0.65), HudTheme.body_font(750), false)
	code_col.add_child(_code_caption)
	_code_label = Label.new()
	HudTheme.style_label(_code_label, 52, HudTheme.GOLD, HudTheme.title_font(600))
	_code_label.add_theme_constant_override("shadow_offset_y", 3)
	code_col.add_child(_code_label)
	var copy_col := VBoxContainer.new()
	copy_col.alignment = BoxContainer.ALIGNMENT_CENTER
	code_row.add_child(copy_col)
	_copy = RoundIconButton.new("copy", 54.0, true)
	_copy.tooltip_text = "Copy the code"
	_copy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_copy.pressed.connect(_copy_code)
	copy_col.add_child(_copy)
	_copied = Label.new()
	_copied.text = "Copied!"
	HudTheme.style_label(_copied, 13, HudTheme.LEAF, HudTheme.body_font(800), false)
	_copied.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_copied.modulate.a = 0.0
	copy_col.add_child(_copied)

	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 6)
	_room.add_child(_roster)
	for i in 4:
		_roster.add_child(CoopRosterRow.new(i))

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	_room.add_child(foot)
	_hint = Label.new()
	HudTheme.style_label(_hint, 15, Color(HudTheme.CREAM, 0.6), HudTheme.body_font(650), false)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_hint)
	_leave = Button.new()
	_leave.focus_mode = Control.FOCUS_NONE
	_leave.custom_minimum_size = Vector2(150, 48)
	_leave.pressed.connect(func():
		if _net:
			_net.leave())
	foot.add_child(_leave)

	_error = Label.new()
	HudTheme.style_label(_error, 16, HudTheme.BLOSSOM, HudTheme.body_font(750), false)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_error)


func _line_edit(placeholder: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size.y = 50
	e.add_theme_font_override("font", HudTheme.body_font(750))
	e.add_theme_font_size_override("font_size", 19)
	e.add_theme_color_override("font_color", HudTheme.CREAM)
	e.add_theme_color_override("font_placeholder_color", Color(HudTheme.CREAM, 0.38))
	e.add_theme_color_override("caret_color", HudTheme.LEAF)
	e.add_theme_color_override("selection_color", Color(HudTheme.LEAF, 0.35))
	var n := HudTheme.pill(Color(0.02, 0.05, 0.03, 0.5), Color(HudTheme.CREAM, 0.2), 16)
	var f := HudTheme.pill(Color(0.03, 0.07, 0.04, 0.7), Color(HudTheme.LEAF, 0.7), 16)
	e.add_theme_stylebox_override("normal", n)
	e.add_theme_stylebox_override("focus", f)
	e.add_theme_stylebox_override("read_only", n)
	e.add_to_group("touch_blockers")
	return e


func _big_button(text: String, tint: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 56
	b.add_theme_font_size_override("font_size", 21)
	b.add_theme_color_override("font_color", HudTheme.INK)
	b.add_theme_color_override("font_hover_color", HudTheme.INK)
	b.add_theme_color_override("font_pressed_color", HudTheme.INK)
	b.add_theme_color_override("font_disabled_color", Color(HudTheme.INK, 0.5))
	b.add_theme_stylebox_override("normal", HudTheme.pill(tint, Color(1, 1, 1, 0.35), 18))
	b.add_theme_stylebox_override("hover", HudTheme.pill(tint.lightened(0.15), Color(1, 1, 1, 0.6), 18))
	b.add_theme_stylebox_override("pressed", HudTheme.pill(tint.darkened(0.12), Color(1, 1, 1, 0.5), 18))
	b.add_theme_stylebox_override("disabled", HudTheme.pill(Color(tint, 0.45), Color(1, 1, 1, 0.15), 18))
	b.add_to_group("touch_blockers")
	return b


func _divider(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for i in 3:
		if i == 1:
			var l := Label.new()
			l.text = text
			HudTheme.style_label(l, 15, Color(HudTheme.CREAM, 0.55), HudTheme.body_font(750), false)
			row.add_child(l)
			continue
		var line := ColorRect.new()
		line.color = Color(HudTheme.CREAM, 0.16)
		line.custom_minimum_size.y = 2
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(line)
	return row


## Two little Kelings with leafy crowns, one in each of the first two colours.
func _draw_art(c: Control) -> void:
	var bob := sin(_t * 2.2) * 1.5
	for k in 2:
		var col: Color = HudTheme.PLAYER_COLORS[k]
		var base := Vector2(20 + k * 26, 50)
		var h := 30.0 + k * 3.0
		var body := Rect2(base - Vector2(11, h - (bob if k == 0 else -bob)), Vector2(22, h))
		c.draw_rect(Rect2(body.position + Vector2(0, 3), body.size), Color(0, 0, 0, 0.25))
		c.draw_circle(body.position + Vector2(11, 11), 11.0, Color(0.42, 0.62, 0.34))
		c.draw_rect(Rect2(body.position + Vector2(0, 11), Vector2(22, h - 11)), Color(0.42, 0.62, 0.34))
		c.draw_circle(body.position + Vector2(7, 12), 2.2, HudTheme.INK)
		c.draw_circle(body.position + Vector2(15, 12), 2.2, HudTheme.INK)
		MapIcons.leaf(c, body.position + Vector2(11, 1), Vector2(-0.5, -0.86), 13.0, 7.0, HudTheme.LEAF)
		MapIcons.leaf(c, body.position + Vector2(11, 1), Vector2(0.6, -0.8), 12.0, 7.0, HudTheme.MOSS.lightened(0.2))
		c.draw_circle(body.position + Vector2(5, 0), 3.6, col)
		c.draw_circle(body.position + Vector2(17, -1), 3.0, col)


# ---------------------------------------------------------------------------
# State

func _sync() -> void:
	if _net == null:
		_offline.visible = false
		_busy.visible = false
		_room.visible = false
		_error.text = "Co-op isn't available here."
		return
	var st: int = _net.status
	var again: bool = _net.is_reconnecting() and st <= 1
	_offline.visible = st == 0 and not again
	_busy.visible = st == 1 or again
	_room.visible = st >= 2
	_name_edit.editable = st == 0
	_dice.disabled = st != 0
	_dice.modulate.a = 1.0 if st == 0 else 0.4
	if not _name_edit.has_focus():
		_name_edit.text = _net.player_name
	_error.text = _net.last_error if st == 0 and not again else ""
	_error.visible = _error.text != ""
	if again:
		_busy_label.text = "Reconnecting"
	elif st == 1:
		_busy_label.text = "Opening your forest" if _net.is_opening_own() else "Looking for %s" % _net.pretty_code(_net.room_code)
	if st >= 2:
		var hosting: bool = st == 2
		_code_caption.text = "Your forest code" if hosting else "You're visiting"
		_code_label.text = _net.pretty_code(_net.room_code)
		_leave.text = "Close forest" if hosting else "Head home"
		var players: Array = _net.players()
		var by_slot := {}
		for p in players:
			by_slot[int(p.slot)] = p
		for i in 4:
			(_roster.get_child(i) as CoopRosterRow).show_player(by_slot.get(i, {}), hosting)
		var free := 4 - players.size()
		if hosting:
			_hint.text = "Friends open Play together and type this code. %s" % (
				"%d more can join." % free if free > 0 else "The forest is full!")
		else:
			_hint.text = "Everyone sees the same forest. Find a bench together!"
	_layout.call_deferred()


func _commit_name() -> void:
	if _net and _net.status == 0:
		_net.set_player_name(_name_edit.text)
		_name_edit.text = _net.player_name


func _on_code_typed(text: String) -> void:
	# Keep it tidy as you type: capitals, the dash in the middle.
	var raw: String = _net.normalize_code(text) if _net else text.to_upper()
	var pretty: String = raw if raw.length() <= 3 else raw.left(3) + "-" + raw.substr(3)
	if pretty != text:
		var caret := _code_edit.caret_column
		_code_edit.text = pretty
		_code_edit.caret_column = mini(caret + (pretty.length() - text.length()), pretty.length())
	_join.disabled = raw.length() != 6


func _do_join() -> void:
	if _net == null:
		return
	_commit_name()
	get_viewport().gui_release_focus()
	_net.join(_code_edit.text)


func _copy_code() -> void:
	if _net == null:
		return
	DisplayServer.clipboard_set(_net.pretty_code(_net.room_code))
	_copied_t = 1.6
	Input.vibrate_handheld(12)


func _unhandled_input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_mouse")):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_timed(delta)
	PerfMeter.add(&"co-op panel", Time.get_ticks_usec() - t0)


func _process_timed(delta: float) -> void:
	if not is_open:
		return
	_t += delta
	_pop = move_toward(_pop, 1.0, delta * 5.0)
	var e := ease(_pop, -2.4)
	_card.scale = Vector2.ONE * lerpf(0.94, 1.0, e)
	_card.modulate.a = e
	_copied_t = maxf(_copied_t - delta, 0.0)
	_copied.modulate.a = clampf(_copied_t * 2.0, 0.0, 1.0)
	if _busy.visible:
		var dots := int(_t * 3.0) % 4
		var base := _busy_label.text.rstrip(".")
		_busy_label.text = base + ".".repeat(dots)
	for row in _roster.get_children():
		row.queue_redraw()
	_art.queue_redraw()
	# Pings tick over while you look.
	if _room.visible and int(_t * 2.0) != int((_t - delta) * 2.0):
		_sync()


func _layout() -> void:
	if not is_inside_tree():
		return
	var s := size
	var w := minf(CARD_WIDTH, s.x - 32.0)
	_card.custom_minimum_size.x = w
	_card.reset_size()
	_card.size.x = w
	_card.position = Vector2((s.x - w) * 0.5, maxf((s.y - _card.size.y) * 0.42, 12.0))
	_card.pivot_offset = _card.size * 0.5
