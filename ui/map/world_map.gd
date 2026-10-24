class_name WorldMap
extends Control
## The big map. Opens with M, a click or a tap on the minimap, and swoops
## out from your Keling to the whole valley. Drag to pan, wheel or pinch to
## zoom, tap a place (or anywhere) to set a waypoint; tap the waypoint again
## to clear it. Gamepad: left stick pans, LB/RB zoom, A marks the centre,
## X finds you, B closes. The world keeps running while it is open (it's
## co-op), but your Keling stays put.

signal opened
signal closed

const FIT_SPAN := 106.0          ## metres shown across the short side at "fit"
const ZOOM_MAX := 4.5
const TAP_SLOP := 14.0
const LABEL_SIZE := 17

var state: MapState
var is_open := false
var _open := 0.0                 ## 0..1 open animation
var _sheet: Panel
var _canvas: Control
var _frame: Panel
var _title: Label
var _hint: Label
var _card: PanelContainer
var _card_title: Label
var _card_text: Label
var _card_meta: Label
var _buttons: Array[Control] = []
var _zoom := 8.0
var _zoom_target := 8.0
var _center := Vector2.ZERO
var _center_target := Vector2.ZERO
var _t := 0.0
var _hover_place := -1
var _selected := {}              ## the place (or custom pin) shown in the card
var _touches := {}               ## index -> position
var _press_pos := {}             ## index -> where the touch began
var _pinch := 0.0
var _mouse_drag := false
var _mouse_down_at := Vector2.ZERO


func _init(p_state: MapState) -> void:
	state = p_state


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_sheet = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.83, 0.87, 0.77)
	sb.set_corner_radius_all(26)
	sb.anti_aliasing = true
	_sheet.add_theme_stylebox_override("panel", sb)
	_sheet.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sheet)

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_canvas.draw.connect(_draw_map)
	_canvas.gui_input.connect(_canvas_input)
	_canvas.mouse_exited.connect(func(): _hover_place = -1)
	_sheet.add_child(_canvas)

	_frame = Panel.new()
	var fb := StyleBoxFlat.new()
	fb.draw_center = false
	fb.set_corner_radius_all(26)
	fb.border_color = HudTheme.INK
	fb.set_border_width_all(7)
	fb.shadow_color = Color(0, 0, 0, 0.35)
	fb.shadow_size = 24
	fb.anti_aliasing = true
	_frame.add_theme_stylebox_override("panel", fb)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.draw.connect(_draw_frame_details)
	add_child(_frame)

	_title = Label.new()
	_title.text = "The Whispering Glade"
	HudTheme.style_label(_title, 30, HudTheme.CREAM, HudTheme.title_font(600))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)

	_hint = Label.new()
	HudTheme.style_label(_hint, 15, Color(HudTheme.CREAM, 0.85), HudTheme.body_font(700))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)

	_add_button("close", 56.0, close)
	_add_button("plus", 52.0, func(): _zoom_at(_sheet_center(), 1.5))
	_add_button("minus", 52.0, func(): _zoom_at(_sheet_center(), 1.0 / 1.5))
	_add_button("center", 52.0, _find_me)

	_build_card()
	resized.connect(_layout)
	GameInput.input_method_changed.connect(func(_m): _refresh_hint())
	state.waypoint_changed.connect(func(): _canvas.queue_redraw())
	_layout()
	_refresh_hint()


func _add_button(glyph: String, d: float, cb: Callable) -> void:
	var b := RoundIconButton.new(glyph, d, true)
	b.pressed.connect(cb)
	add_child(b)
	_buttons.append(b)


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", HudTheme.glass(20, 0.82, 16.0))
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.add_to_group("touch_blockers")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_card.add_child(box)
	_card_title = Label.new()
	HudTheme.style_label(_card_title, 24, HudTheme.CREAM, HudTheme.title_font(600))
	box.add_child(_card_title)
	_card_text = Label.new()
	HudTheme.style_label(_card_text, 16, Color(HudTheme.CREAM, 0.85), HudTheme.body_font(600))
	_card_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_text.custom_minimum_size.x = 300
	box.add_child(_card_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_card_meta = Label.new()
	HudTheme.style_label(_card_meta, 16, HudTheme.GOLD, HudTheme.title_font(560))
	_card_meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_meta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_card_meta)
	var clear := Button.new()
	clear.text = "Clear"
	clear.focus_mode = Control.FOCUS_NONE
	clear.theme = HudTheme.theme()
	clear.pressed.connect(func():
		state.clear_waypoint()
		_selected = {}
		_refresh_card())
	row.add_child(clear)
	_card.visible = false
	add_child(_card)


func _layout() -> void:
	# Hidden controls don't follow their anchors, so size to the screen here.
	var screen := get_parent_area_size()
	if screen.x > 0.0 and size != screen:
		position = Vector2.ZERO
		size = screen
	var safe := _safe_margins()
	var m := Vector2(maxf(26.0, safe.x), maxf(64.0, safe.y))
	var rect := Rect2(Vector2(m.x, m.y), size - Vector2(m.x * 2.0, m.y + maxf(52.0, safe.w)))
	_sheet.position = rect.position
	_sheet.size = rect.size
	_sheet.pivot_offset = rect.size * 0.5
	_frame.position = rect.position
	_frame.size = rect.size
	_frame.pivot_offset = rect.size * 0.5
	_title.size = Vector2(size.x, 44)
	_title.position = Vector2(0, rect.position.y - 50)
	_hint.size = Vector2(size.x, 24)
	_hint.position = Vector2(0, rect.end.y + 14)
	var close_b := _buttons[0]
	close_b.position = Vector2(rect.end.x - close_b.size.x * 0.6, rect.position.y - close_b.size.y * 0.4)
	for i in range(1, _buttons.size()):
		var b := _buttons[i]
		b.position = Vector2(rect.end.x - b.size.x - 18.0, rect.position.y + rect.size.y * 0.5 - 92.0 + (i - 1) * 64.0)
	_card.position = Vector2(rect.position.x + 20.0, rect.end.y - 20.0 - _card.size.y)
	_zoom = clampf(_zoom, _fit_zoom() * 0.9, _fit_zoom() * ZOOM_MAX)


## Left, top, right, bottom insets for notches and rounded corners.
func _safe_margins() -> Vector4:
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0 or safe.size.x <= 0 or not OS.has_feature("mobile"):
		return Vector4.ZERO
	var k := size.x / float(win.x)
	return Vector4(safe.position.x * k, safe.position.y * k, (win.x - safe.end.x) * k, (win.y - safe.end.y) * k)


func _refresh_hint() -> void:
	match GameInput.method:
		GameInput.Method.TOUCH:
			_hint.text = "Drag to look around  ·  Pinch to zoom  ·  Tap a place to set a waypoint"
		GameInput.Method.GAMEPAD:
			_hint.text = "Left stick  pan   ·   LB / RB  zoom   ·   A  mark   ·   X  find me   ·   B  close"
		_:
			_hint.text = "Drag to pan  ·  Wheel to zoom  ·  Click a place to set a waypoint  ·  E  find me  ·  M  close"


# ---------------------------------------------------------------------------
# Open / close

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
	GameInput.ui_locked = true
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_layout()
	var me := MapState.local_player(get_tree())
	var at: Vector2 = me.pos if not me.is_empty() else Vector2.ZERO
	# Swoop out: start close on your Keling, settle on the valley.
	_zoom = _fit_zoom() * 2.6
	_center = at
	_zoom_target = _fit_zoom() * 1.12
	_center_target = at.lerp(Vector2.ZERO, 0.45)
	_clamp_center()
	_touches.clear()
	_press_pos.clear()
	_refresh_card()
	opened.emit()
	Input.vibrate_handheld(12)


func close() -> void:
	if not is_open:
		return
	is_open = false
	GameInput.ui_locked = false
	_touches.clear()
	_mouse_drag = false
	closed.emit()


# ---------------------------------------------------------------------------
# View maths

func _fit_zoom() -> float:
	var s := _sheet.size if _sheet else size
	return maxf(minf(s.x, s.y), 100.0) / FIT_SPAN


func _sheet_center() -> Vector2:
	return _sheet.size * 0.5


func _to_screen(p: Vector2) -> Vector2:
	return _sheet_center() + (p - _center) * _zoom


func _to_world(s: Vector2) -> Vector2:
	return _center + (s - _sheet_center()) / _zoom


func _zoom_at(screen_p: Vector2, factor: float) -> void:
	var fit := _fit_zoom()
	var w := _center_target + (screen_p - _sheet_center()) / _zoom_target
	_zoom_target = clampf(_zoom_target * factor, fit * 0.9, fit * ZOOM_MAX)
	_center_target = w - (screen_p - _sheet_center()) / _zoom_target
	_clamp_center()


func _pan_pixels(d: Vector2) -> void:
	_center_target -= d / _zoom_target
	_center = _center_target if _touches.size() > 0 or _mouse_drag else _center
	_clamp_center()


func _clamp_center() -> void:
	var half := _sheet.size * 0.5 / _zoom_target
	var lim := MapState.EXTENT - 4.0
	var room := Vector2(maxf(lim - half.x, 0.0), maxf(lim - half.y, 0.0))
	_center_target = _center_target.clamp(-room, room)


func _find_me() -> void:
	var me := MapState.local_player(get_tree())
	if not me.is_empty():
		_center_target = me.pos
		_zoom_target = maxf(_zoom_target, _fit_zoom() * 2.0)
		_clamp_center()


# ---------------------------------------------------------------------------
# Input

func _input(event: InputEvent) -> void:
	if not is_open:
		if event.is_action_pressed("map") and not event.is_echo():
			open()
			get_viewport().set_input_as_handled()
		return
	var close_key: bool = event.is_action_pressed("map") or event.is_action_pressed("toggle_mouse") \
			or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B)
	if close_key and not event.is_echo():
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed:
		match event.physical_keycode:
			KEY_EQUAL, KEY_KP_ADD, KEY_Q:
				_zoom_at(_sheet_center(), 1.4)
			KEY_MINUS, KEY_KP_SUBTRACT, KEY_Z:
				_zoom_at(_sheet_center(), 1.0 / 1.4)
	if event.is_action_pressed("grab"):
		_find_me()
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A:
		_tap(_sheet_center())


## Tapping the dimmed world around the map closes it.
func _gui_input(event: InputEvent) -> void:
	if is_open and event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
		accept_event()


func _canvas_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			_press_pos[event.index] = event.position
			_pinch = 0.0
		else:
			if _press_pos.has(event.index) and _touches.size() == 1 \
					and (event.position as Vector2).distance_to(_press_pos[event.index]) < TAP_SLOP:
				_tap(event.position)
			_touches.erase(event.index)
			_press_pos.erase(event.index)
			_pinch = 0.0
		_canvas.accept_event()
	elif event is InputEventScreenDrag:
		if not _touches.has(event.index):
			return
		if _touches.size() >= 2:
			_touches[event.index] = event.position
			var keys := _touches.keys()
			var a: Vector2 = _touches[keys[0]]
			var b: Vector2 = _touches[keys[1]]
			var d := a.distance_to(b)
			if _pinch > 0.0:
				_zoom_at((a + b) * 0.5, d / _pinch)
				_zoom = _zoom_target
				_center = _center_target
			_pinch = d
			for k in _press_pos.keys():
				_press_pos[k] = Vector2.INF
		else:
			_touches[event.index] = event.position
			if (event.position as Vector2).distance_to(_press_pos.get(event.index, event.position)) > TAP_SLOP:
				_pan_pixels(event.relative)
		_canvas.accept_event()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(event.position, 1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(event.position, 1.0 / 1.15)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_mouse_drag = true
					_mouse_down_at = event.position
				else:
					if _mouse_drag and event.button_index == MOUSE_BUTTON_LEFT and event.position.distance_to(_mouse_down_at) < TAP_SLOP:
						_tap(event.position)
					_mouse_drag = false
		_canvas.accept_event()
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if _mouse_drag and event.position.distance_to(_mouse_down_at) > TAP_SLOP * 0.5:
			_pan_pixels(event.relative)
		_hover_place = _place_under(event.position)
		_canvas.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _hover_place >= 0 else Control.CURSOR_DRAG
		_canvas.accept_event()


func _place_under(p: Vector2) -> int:
	var best := -1
	var best_d := 26.0
	for i in state.places.size():
		var d := p.distance_to(_to_screen(state.places[i].pos))
		if d < best_d:
			best = i
			best_d = d
	return best


func _tap(p: Vector2) -> void:
	# Tapping the waypoint again lifts it.
	if state.has_waypoint and p.distance_to(_to_screen(state.waypoint) + Vector2(0, -14)) < 28.0:
		state.clear_waypoint()
		_selected = {}
		_refresh_card()
		Input.vibrate_handheld(8)
		return
	var i := _place_under(p)
	if i >= 0:
		var pl: Dictionary = state.places[i]
		_selected = pl
		state.set_waypoint(pl.pos, pl.name)
	else:
		var w := _to_world(p)
		if maxf(absf(w.x), absf(w.y)) > ForestLayout.HALF:
			return
		_selected = {"name": "Marked spot", "blurb": "Your own little waypoint. Tap it again to lift it.", "pos": w}
		state.set_waypoint(w, "Marked spot")
	_refresh_card()
	Input.vibrate_handheld(14)


func _refresh_card() -> void:
	_card.visible = not _selected.is_empty() and state.has_waypoint
	if not _card.visible:
		return
	_card_title.text = _selected.name
	_card_text.text = _selected.blurb
	_card.reset_size()
	_layout()


# ---------------------------------------------------------------------------
# Frame loop and drawing

func _process(delta: float) -> void:
	_t += delta
	var target := 1.0 if is_open else 0.0
	_open = move_toward(_open, target, delta / 0.28)
	if _open <= 0.0 and not is_open:
		visible = false
		return
	var e := _ease_out_back(_open) if is_open else _open * _open
	modulate.a = clampf(_open * 1.6, 0.0, 1.0)
	var s := lerpf(0.9, 1.0, e)
	_sheet.scale = Vector2.ONE * s
	_frame.scale = _sheet.scale

	if is_open:
		var pad := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if pad.length() > 0.05:
			_center_target += pad * delta * 900.0 / _zoom_target
			_clamp_center()
		if Input.is_action_pressed("zoom_in"):
			_zoom_at(_sheet_center(), 1.0 + delta * 1.6)
		if Input.is_action_pressed("zoom_out"):
			_zoom_at(_sheet_center(), 1.0 / (1.0 + delta * 1.6))
	var k := 1.0 - exp(-9.0 * delta)
	_zoom = lerpf(_zoom, _zoom_target, k)
	_center = _center.lerp(_center_target, k)
	if _card.visible and not _selected.is_empty():
		var me := MapState.local_player(get_tree())
		if not me.is_empty():
			_card_meta.text = "Waypoint set  ·  %d m away" % roundi((me.pos as Vector2).distance_to(_selected.pos))
	_canvas.queue_redraw()
	queue_redraw()


static func _ease_out_back(x: float) -> float:
	var c1 := 1.4
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


func _draw() -> void:
	# Dim the world behind the map, darker at the edges.
	var a := clampf(_open, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.05, 0.03, 0.55 * a))


func _draw_map() -> void:
	var font := HudTheme.title_font(600)
	var cs := _canvas.size
	# The painted valley.
	if state.texture:
		var tl := _to_screen(Vector2(-MapState.EXTENT, -MapState.EXTENT))
		var br := _to_screen(Vector2(MapState.EXTENT, MapState.EXTENT))
		_canvas.draw_texture_rect(state.texture, Rect2(tl, br - tl), false)
	else:
		var msg := "The map is being painted…"
		var tw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		_canvas.draw_string(font, cs * 0.5 - Vector2(tw * 0.5, 0), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, HudTheme.INK)

	# A dotted border where the explorable valley ends.
	var h := ForestLayout.HALF
	var corners := [Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]
	for i in 4:
		var a := _to_screen(corners[i])
		var b := _to_screen(corners[(i + 1) % 4])
		_canvas.draw_dashed_line(a, b, Color(HudTheme.INK, 0.28), 2.0, 10.0, true, true)

	var zoom_k := clampf(_zoom / _fit_zoom(), 1.0, 3.0)
	var badge_r := 12.0 + 3.0 * (zoom_k - 1.0)

	# Places and their names.
	for i in state.places.size():
		var pl: Dictionary = state.places[i]
		var s := _to_screen(pl.pos)
		var lift := 1.0 if i == _hover_place or (not _selected.is_empty() and _selected.get("id", "") == pl.id) else 0.0
		MapIcons.badge(_canvas, s, badge_r, pl.icon, _t, lift)
		var fs := LABEL_SIZE + (2 if lift > 0.0 else 0)
		var tw := font.get_string_size(pl.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lp := s + Vector2(-tw * 0.5, badge_r + fs + 3.0)
		_canvas.draw_string_outline(font, lp, pl.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(1.0, 0.97, 0.88, 0.92))
		_canvas.draw_string(font, lp, pl.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudTheme.INK)

	if state.has_waypoint:
		var me := MapState.local_player(get_tree())
		var ws := _to_screen(state.waypoint)
		if not me.is_empty():
			_canvas.draw_dashed_line(_to_screen(me.pos), ws, Color(HudTheme.GOLD, 0.9), 3.0, 9.0, true, true)
		MapIcons.pin(_canvas, ws, 17.0, _t)

	for p in MapState.players(get_tree()):
		var s := _to_screen(p.pos)
		MapIcons.player(_canvas, s, p.heading, p.color, 11.0 if p.local else 9.0, _t, p.local)
		var nm: String = p.name
		var tw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var lp := s + Vector2(-tw * 0.5, -24.0)
		_canvas.draw_string_outline(font, lp, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 6, HudTheme.INK)
		_canvas.draw_string(font, lp, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, p.color.lightened(0.2))

	if GameInput.method == GameInput.Method.GAMEPAD:
		var c := _sheet_center()
		_canvas.draw_arc(c, 14.0, 0.0, TAU, 32, Color(HudTheme.INK, 0.7), 2.5, true)
		_canvas.draw_circle(c, 2.5, HudTheme.INK)

	_draw_compass(Vector2(cs.x - 70.0, cs.y - 70.0), 44.0, font)
	_draw_scale_bar(Vector2(cs.x - 160.0 - 120.0, cs.y - 34.0), font)


func _draw_compass(c: Vector2, r: float, font: Font) -> void:
	_canvas.draw_circle(c, r * 1.08, Color(1.0, 0.97, 0.88, 0.55))
	_canvas.draw_arc(c, r * 1.08, 0.0, TAU, 48, Color(HudTheme.INK, 0.5), 2.0, true)
	for k in 8:
		var a := -PI * 0.5 + TAU * k / 8.0
		var d := Vector2(cos(a), sin(a))
		var side := Vector2(-d.y, d.x)
		var len := r * (0.92 if k % 2 == 0 else 0.55)
		var w := r * (0.2 if k % 2 == 0 else 0.13)
		var col := Color(0.75, 0.25, 0.2) if k == 0 else (HudTheme.INK if k % 2 == 0 else Color(HudTheme.INK, 0.6))
		_canvas.draw_colored_polygon(PackedVector2Array([c + d * len, c + side * w, c - side * w]), col)
		_canvas.draw_colored_polygon(PackedVector2Array([c + d * len, c + side * w, c]), col.lightened(0.35))
	_canvas.draw_circle(c, r * 0.12, HudTheme.CREAM)
	var nw := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var np := c + Vector2(-nw * 0.5, -r * 1.12)
	_canvas.draw_string_outline(font, np, "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, HudTheme.CREAM)
	_canvas.draw_string(font, np, "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.75, 0.25, 0.2))


func _draw_scale_bar(at: Vector2, font: Font) -> void:
	var metres := 10.0
	for m in [5.0, 10.0, 20.0]:
		if m * _zoom >= 70.0:
			metres = m
			break
	var w := metres * _zoom
	var y := at.y
	var x0 := at.x + 120.0 - w
	_canvas.draw_rect(Rect2(x0 - 8, y - 22, w + 16, 34), Color(1.0, 0.97, 0.88, 0.55))
	for k in 2:
		_canvas.draw_rect(Rect2(x0 + w * 0.5 * k, y, w * 0.5, 6), HudTheme.INK if k == 0 else HudTheme.CREAM)
	_canvas.draw_rect(Rect2(x0, y, w, 6), HudTheme.INK, false, 1.5)
	var label := "%d m" % metres
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	_canvas.draw_string(font, Vector2(x0 + w * 0.5 - tw * 0.5, y - 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, HudTheme.INK)


func _draw_frame_details() -> void:
	# Leafy sprigs on two corners of the frame.
	var s := _frame.size
	for corner in [Vector2(0, 0), Vector2(s.x, s.y)]:
		var inward := Vector2(1, 1) if corner == Vector2.ZERO else Vector2(-1, -1)
		var base: Vector2 = corner + inward * 10.0
		MapIcons.leaf(_frame, base, Vector2(inward.x, inward.y * 0.25).normalized(), 46.0, 20.0, Color(0.34, 0.6, 0.3))
		MapIcons.leaf(_frame, base, Vector2(inward.x * 0.25, inward.y).normalized(), 40.0, 18.0, Color(0.46, 0.72, 0.36))
		MapIcons.leaf(_frame, base, inward.normalized(), 34.0, 16.0, Color(0.4, 0.66, 0.33))
		_frame.draw_circle(base + inward * 6.0, 7.0, HudTheme.BLOSSOM)
		_frame.draw_circle(base + inward * 6.0, 2.8, HudTheme.GOLD)
