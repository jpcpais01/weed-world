class_name CharacterPicker
extends Control
## "Choose your Keling": a row of portrait cards, one per playable Keling.
## Pick one and press the big button (or pick it again) to transform into
## it. Touch, mouse, keyboard (arrows, Enter) and gamepad (d-pad, A) all
## work; T opens it on desktop.

signal opened
signal closed
## The player picked a new character.
signal chosen(id: String)

const PORTRAITS := "res://ui/character/portraits/%s.png"
const CARD_MAX := Vector2(150, 206)

var is_open := false
## Why transforming is not possible right now ("" if it is).
var blocked_reason: Callable

var _backdrop: ColorRect
var _panel: PanelContainer
var _row: HBoxContainer
var _cards: Array[Control] = []
var _tagline: Label
var _go: Button
var _current := KelingCharacters.DEFAULT
var _selected := 0
var _pop := 0.0
var _t := 0.0
var _prev_lock := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()
	resized.connect(_layout)


func toggle(current: String) -> void:
	if is_open:
		close()
	else:
		open(current)


func open(current: String) -> void:
	if is_open:
		return
	is_open = true
	visible = true
	_current = current
	_selected = maxi(KelingCharacters.IDS.find(current), 0)
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
	closed.emit()


func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.02, 0.05, 0.03, 0.45)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.add_to_group("touch_blockers")
	_backdrop.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", HudTheme.glass(26, 0.92, 22.0))
	_panel.add_to_group("touch_blockers")
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	box.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var title := Label.new()
	title.text = "Choose your Keling"
	HudTheme.style_label(title, 30, HudTheme.CREAM, HudTheme.title_font(600))
	titles.add_child(title)
	var sub := Label.new()
	sub.text = "Pick one and watch yourself transform"
	HudTheme.style_label(sub, 16, Color(HudTheme.CREAM, 0.7), HudTheme.body_font(650), false)
	titles.add_child(sub)
	var x := RoundIconButton.new("close", 46.0, true)
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	x.pressed.connect(close)
	head.add_child(x)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 10)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_row)
	for i in KelingCharacters.IDS.size():
		var card := _Card.new(self, i, KelingCharacters.IDS[i])
		_row.add_child(card)
		_cards.append(card)

	_tagline = Label.new()
	_tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudTheme.style_label(_tagline, 17, Color(HudTheme.CREAM, 0.85), HudTheme.body_font(700), false)
	box.add_child(_tagline)

	_go = Button.new()
	_go.focus_mode = Control.FOCUS_NONE
	_go.custom_minimum_size = Vector2(300, 56)
	_go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_go.add_theme_font_override("font", HudTheme.title_font(600))
	_go.add_theme_font_size_override("font_size", 22)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		_go.add_theme_color_override(k, HudTheme.INK)
	_go.add_theme_color_override("font_disabled_color", Color(HudTheme.CREAM, 0.7))
	_go.add_to_group("touch_blockers")
	_go.pressed.connect(_confirm)
	box.add_child(_go)


## A card was tapped: select it, or transform if it was already selected.
func _pick(i: int) -> void:
	if i == _selected:
		_confirm()
		return
	_selected = i
	_sync()


func _confirm() -> void:
	var id: String = KelingCharacters.IDS[_selected]
	if id == _current or _reason() != "":
		return
	close()
	chosen.emit(id)


func _reason() -> String:
	return String(blocked_reason.call()) if blocked_reason.is_valid() else ""


func _sync() -> void:
	var id: String = KelingCharacters.IDS[_selected]
	var info := KelingCharacters.get_info(id)
	_tagline.text = info.tagline
	var col: Color = info.colors[0]
	var reason := _reason()
	if id == _current:
		_go.text = "That's you!"
		_go.disabled = true
	elif reason != "":
		_go.text = reason
		_go.disabled = true
	else:
		_go.text = "Become %s" % info.name
		_go.disabled = false
	var tint := col.lerp(HudTheme.CREAM, 0.35)
	_go.add_theme_stylebox_override("normal", HudTheme.pill(tint, Color(1, 1, 1, 0.4), 20))
	_go.add_theme_stylebox_override("hover", HudTheme.pill(tint.lightened(0.15), Color(1, 1, 1, 0.65), 20))
	_go.add_theme_stylebox_override("pressed", HudTheme.pill(tint.darkened(0.12), Color(1, 1, 1, 0.5), 20))
	_go.add_theme_stylebox_override("disabled", HudTheme.pill(Color(0.02, 0.05, 0.03, 0.4), Color(HudTheme.CREAM, 0.15), 20))
	for c in _cards:
		c.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_mouse"):
		close()
	elif event.is_action_pressed("ui_left"):
		_selected = posmod(_selected - 1, _cards.size())
		_sync()
	elif event.is_action_pressed("ui_right"):
		_selected = posmod(_selected + 1, _cards.size())
		_sync()
	elif event.is_action_pressed("ui_accept") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A):
		_confirm()
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_open:
		return
	_t += delta
	_pop = move_toward(_pop, 1.0, delta * 5.0)
	var e := ease(_pop, -2.4)
	_panel.scale = Vector2.ONE * lerpf(0.94, 1.0, e)
	_panel.modulate.a = e
	for c in _cards:
		c.queue_redraw()
	# Whatever was in the way (a roll, a jump) may have finished.
	if int(_t * 4.0) != int((_t - delta) * 4.0):
		_sync()


func _layout() -> void:
	if not is_inside_tree():
		return
	var s := size
	var w := minf(s.x - 24.0, 5.0 * CARD_MAX.x + 4.0 * 10.0 + 44.0)
	var card_w := clampf((w - 44.0 - 40.0) / 5.0, 90.0, CARD_MAX.x)
	var card_h := minf(card_w * CARD_MAX.y / CARD_MAX.x, maxf(s.y - 250.0, 120.0))
	for c in _cards:
		c.custom_minimum_size = Vector2(card_w, card_h)
	_panel.custom_minimum_size.x = w
	_panel.reset_size()
	_panel.size.x = w
	_panel.position = Vector2((s.x - w) * 0.5, maxf((s.y - _panel.size.y) * 0.45, 8.0))
	_panel.pivot_offset = _panel.size * 0.5


## One portrait card.
class _Card extends Control:
	var picker: CharacterPicker
	var index := 0
	var id := ""
	var info: Dictionary
	var portrait: Texture2D
	var _hover := 0.0
	var _lift := 0.0

	func _init(p: CharacterPicker, i: int, p_id: String) -> void:
		picker = p
		index = i
		id = p_id
		info = KelingCharacters.get_info(p_id)
		var path := PORTRAITS % p_id
		portrait = load(path) if ResourceLoader.exists(path) else null
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		add_to_group("touch_blockers")
		tooltip_text = String(info.name)

	func _gui_input(event: InputEvent) -> void:
		# Touches arrive as emulated mouse clicks too.
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			picker._pick(index)
			accept_event()

	func _process(delta: float) -> void:
		if not picker.is_open:
			return
		var sel := picker._selected == index
		_hover = move_toward(_hover, 1.0 if get_global_rect().has_point(get_global_mouse_position()) else 0.0, delta * 8.0)
		_lift = move_toward(_lift, 1.0 if sel else 0.0, delta * 6.0)

	func _draw() -> void:
		var sel := picker._selected == index
		var you := picker._current == id
		var col: Color = info.colors[0]
		var r := Rect2(Vector2(0, (1.0 - _lift) * 8.0), size - Vector2(0, 8.0))
		var face := HudTheme.pill(Color(0.02, 0.05, 0.03, 0.55 - 0.15 * _lift), Color(col, 0.25 + 0.75 * _lift), 18)
		face.set_border_width_all(int(2 + 2 * _lift))
		draw_style_box(face, r)
		# A soft glow of the character's colour behind them, brighter when picked.
		var c := r.position + Vector2(r.size.x * 0.5, r.size.y * 0.5)
		for k in 6:
			var rad := r.size.x * (0.55 - k * 0.07)
			draw_circle(c, rad, Color(col, (0.04 + 0.05 * _lift + 0.02 * _hover)))
		if portrait:
			var bob := sin(picker._t * 3.0 + index) * 2.5 * _lift
			var ps := portrait.get_size()
			var h := r.size.y - 30.0
			var w := h * ps.x / ps.y
			if w > r.size.x - 4.0:
				w = r.size.x - 4.0
				h = w * ps.y / ps.x
			var pr := Rect2(Vector2(c.x - w * 0.5, r.position.y + 2.0 + bob), Vector2(w, h))
			draw_texture_rect(portrait, pr, false, Color(1, 1, 1, 0.75 + 0.25 * maxf(_lift, _hover)))
		var f := HudTheme.title_font(600)
		var fs := 17
		var name_s := String(info.name)
		var tw := f.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(c.x - tw * 0.5, r.end.y - 10.0), name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudTheme.CREAM if sel else Color(HudTheme.CREAM, 0.75))
		if you:
			var tag := "YOU"
			var tf := HudTheme.body_font(850)
			var tws := tf.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var tr := Rect2(Vector2(r.position.x + 8.0, r.position.y + 8.0), Vector2(tws + 14.0, 20.0))
			draw_style_box(HudTheme.pill(HudTheme.LEAF, Color(1, 1, 1, 0.4), 10), tr)
			draw_string(tf, tr.position + Vector2(7.0, 15.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HudTheme.INK)
