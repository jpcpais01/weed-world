class_name MenuRow
extends Control
## One line of the pause menu, drawn by hand in the HUD's look: a big menu
## button, a slider, a "‹ High ›" choice, an on/off switch, a key binding or
## a plain line of info. Works the same with touch, mouse, keyboard and
## gamepad: tap or drag the control, or select the row and use left / right
## and accept. Rows sit in a ScrollContainer, so a drag that starts on a
## row's label scrolls the list instead.

signal value_changed(value: Variant)
signal activated

enum Kind { BUTTON, SLIDER, CHOICE, TOGGLE, KEY, INFO }

var kind := Kind.BUTTON
var title := ""
var subtitle := ""
var icon := ""
var accent := HudTheme.LEAF
var value: Variant
var min_value := 0.0
var max_value := 1.0
var step := 0.05
var format := Callable()        ## value -> String, for sliders
var options: Array = []         ## choice labels
var choice_values: Array = []
var other_label := "Custom"     ## shown when the value isn't one of the choices
var keycap := ""
var listening := false
var danger := false

var _hl := 0.0                  ## hover / selection glow
var _press := 0.0
var _knob := 0.0                ## switch position
var _bump := 0.0                ## a value just changed
var _bump_dir := 0
var _dragging := false
var _hover := false
var _t := 0.0

static var _quiet := false


static func make_button(p_title: String, p_icon: String, p_accent := HudTheme.LEAF) -> MenuRow:
	var r := MenuRow.new()
	r.kind = Kind.BUTTON
	r.title = p_title
	r.icon = p_icon
	r.accent = p_accent
	r.custom_minimum_size.y = 60
	return r


static func make_slider(p_title: String, p_sub: String, lo: float, hi: float, p_step: float, fmt: Callable) -> MenuRow:
	var r := _setting(Kind.SLIDER, p_title, p_sub)
	r.min_value = lo
	r.max_value = hi
	r.step = p_step
	r.format = fmt
	r.value = lo
	return r


static func make_choice(p_title: String, p_sub: String, labels: Array, vals: Array) -> MenuRow:
	var r := _setting(Kind.CHOICE, p_title, p_sub)
	r.options = labels
	r.choice_values = vals
	r.value = vals[0]
	return r


static func make_toggle(p_title: String, p_sub: String) -> MenuRow:
	var r := _setting(Kind.TOGGLE, p_title, p_sub)
	r.value = false
	return r


static func make_key(p_title: String, p_keycap: String) -> MenuRow:
	var r := _setting(Kind.KEY, p_title, "")
	r.keycap = p_keycap
	r.custom_minimum_size.y = 50
	return r


static func make_info(p_title: String, p_text: String) -> MenuRow:
	var r := _setting(Kind.INFO, p_title, "")
	r.keycap = p_text
	r.custom_minimum_size.y = 44
	r.focus_mode = Control.FOCUS_NONE
	return r


static func _setting(k: Kind, p_title: String, p_sub: String) -> MenuRow:
	var r := MenuRow.new()
	r.kind = k
	r.title = p_title
	r.subtitle = p_sub
	r.custom_minimum_size.y = 64 if p_sub != "" else 54
	return r


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	if kind == Kind.TOGGLE:
		_knob = 1.0 if value else 0.0
	add_to_group("touch_blockers")
	focus_entered.connect(func():
		if not _quiet:
			UiSound.play("move")
		queue_redraw())
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(func(): _hover = true)
	mouse_exited.connect(func(): _hover = false)


## Selects a row without the selection tick (when a menu opens).
static func quiet_focus(row: Control) -> void:
	_quiet = true
	row.grab_focus()
	_quiet = false


## Shows a value without emitting value_changed (the setting changed elsewhere).
func show_value(v: Variant) -> void:
	value = v
	queue_redraw()


func _change(v: Variant, dir := 0) -> void:
	if kind == Kind.SLIDER:
		v = clampf(snappedf(float(v), step), min_value, max_value)
		if is_equal_approx(float(v), float(value)):
			return
	elif v == value:
		return
	value = v
	_bump = 1.0
	_bump_dir = dir
	value_changed.emit(value)
	match kind:
		Kind.TOGGLE:
			UiSound.play("toggle", 1.08 if value else 0.92)
		Kind.SLIDER:
			UiSound.play("change", 0.85 + 0.35 * inverse_lerp(min_value, max_value, float(value)))
		_:
			UiSound.play("change")
	queue_redraw()


## Left / right on a keyboard or gamepad (and the choice arrows).
func nudge(dir: int) -> void:
	match kind:
		Kind.SLIDER:
			_change(float(value) + step * dir, dir)
		Kind.CHOICE:
			var i := choice_values.find(value)
			if i < 0:
				i = 0 if dir > 0 else choice_values.size() - 1
			else:
				i = clampi(i + dir, 0, choice_values.size() - 1)
			if choice_values[i] != value:
				_change(choice_values[i], dir)
		Kind.TOGGLE:
			_change(dir > 0, dir)


func activate() -> void:
	match kind:
		Kind.BUTTON, Kind.KEY:
			_press = 1.0
			UiSound.play("confirm" if kind == Kind.BUTTON else "change")
			activated.emit()
		Kind.TOGGLE:
			_change(not value)
		Kind.CHOICE:
			var i := choice_values.find(value)
			_change(choice_values[(i + 1) % choice_values.size()], 1)
	queue_redraw()


# ---------------------------------------------------------------------------
# Input

func _gui_input(event: InputEvent) -> void:
	if kind == Kind.INFO:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if focus_mode != Control.FOCUS_NONE and not has_focus():
				grab_focus()
			var r := _ctrl_rect()
			match kind:
				Kind.BUTTON, Kind.KEY:
					_press = 1.0
					if kind == Kind.KEY and r.has_point(mb.position):
						accept_event()
				Kind.SLIDER:
					if r.grow(8).has_point(mb.position):
						_dragging = true
						_slide_to(mb.position.x)
						accept_event()
				Kind.CHOICE:
					if r.has_point(mb.position):
						nudge(-1 if mb.position.x < r.get_center().x else 1)
						accept_event()
				Kind.TOGGLE:
					if r.has_point(mb.position) or not _in_scroll():
						activate()
						accept_event()
		else:
			if _dragging:
				_dragging = false
				accept_event()
			elif (kind == Kind.BUTTON or kind == Kind.KEY) and Rect2(Vector2.ZERO, size).has_point(mb.position) and _press > 0.5:
				activate()
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_slide_to((event as InputEventMouseMotion).position.x)
		accept_event()
	elif event.is_action_pressed("ui_left", true):
		nudge(-1)
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		nudge(1)
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		activate()
		accept_event()


func _in_scroll() -> bool:
	var p := get_parent()
	while p:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _slide_to(x: float) -> void:
	var tr := _track()
	var f := clampf(inverse_lerp(tr.x, tr.y, x), 0.0, 1.0)
	_change(lerpf(min_value, max_value, f))


# ---------------------------------------------------------------------------
# Drawing

func _ctrl_rect() -> Rect2:
	var x := size.x * (0.5 if kind != Kind.KEY else 0.62)
	return Rect2(x, 6.0, size.x - x - 14.0, size.y - 12.0)


## Slider track ends (x).
func _track() -> Vector2:
	var r := _ctrl_rect()
	return Vector2(r.position.x + 14.0, r.end.x - 78.0)


func _process(delta: float) -> void:
	_t += delta
	var target := 1.0 if (has_focus() or _hover or _dragging) else 0.0
	var before := _hl + _press + _knob + _bump
	_hl = move_toward(_hl, target, delta * 8.0)
	_press = move_toward(_press, 0.0, delta * 5.0)
	_bump = move_toward(_bump, 0.0, delta * 6.0)
	if kind == Kind.TOGGLE:
		_knob = lerpf(_knob, 1.0 if value else 0.0, 1.0 - exp(-16.0 * delta))
	if not is_equal_approx(before, _hl + _press + _knob + _bump) or listening or (has_focus() and kind == Kind.BUTTON):
		queue_redraw()


func _draw() -> void:
	if kind == Kind.BUTTON:
		_draw_button()
		return
	var sel := ease(_hl, -2.0)
	var focused := has_focus()
	if sel > 0.01 or focused:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(HudTheme.CREAM, 0.035 + 0.05 * sel)
		sb.set_corner_radius_all(16)
		sb.border_color = Color(accent, 0.55 if focused else 0.0)
		sb.set_border_width_all(2 if focused else 0)
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
	if focused:
		MapIcons.leaf(self, Vector2(14, size.y * 0.5 + 6), Vector2(0.5, -0.86), 15.0, 8.0, accent)
	var tx := 32.0
	var tf := HudTheme.title_font(560)
	var ty := size.y * 0.5 + (-2.0 if subtitle != "" else 7.0)
	draw_string(tf, Vector2(tx, ty), title, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.48 - tx, 20, Color(HudTheme.CREAM, 0.95))
	if subtitle != "":
		draw_string(HudTheme.body_font(650), Vector2(tx, ty + 20), subtitle, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.48 - tx,
				14, Color(HudTheme.CREAM, 0.55))
	match kind:
		Kind.SLIDER:
			_draw_slider()
		Kind.CHOICE:
			_draw_choice()
		Kind.TOGGLE:
			_draw_toggle()
		Kind.KEY:
			_draw_key()
		Kind.INFO:
			var f := HudTheme.body_font(750)
			var r := _ctrl_rect()
			draw_string(f, Vector2(r.position.x, r.get_center().y + 6), keycap, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x, 16,
					Color(HudTheme.CREAM, 0.75))


func _draw_button() -> void:
	var sel := ease(_hl, -2.0)
	var squish := 1.0 - 0.03 * _press
	var r := Rect2(Vector2(6.0 * sel, 0), size)
	r = r.grow_individual(-size.x * (1.0 - squish) * 0.5, -size.y * (1.0 - squish) * 0.5, -size.x * (1.0 - squish) * 0.5, -size.y * (1.0 - squish) * 0.5)
	var sb := HudTheme.pill(Color(HudTheme.GLASS, 0.35 + 0.25 * sel), Color(accent, 0.15 + 0.6 * sel), 22)
	if danger and sel > 0.0:
		sb.bg_color = Color(0.32, 0.12, 0.12, 0.35 + 0.3 * sel)
	sb.shadow_size = int(4 + 6 * sel)
	draw_style_box(sb, r)
	var c := Vector2(r.position.x + 32.0, r.get_center().y)
	draw_circle(c, 19.0, Color(accent, 0.18 + 0.5 * sel))
	var glow := accent if sel > 0.5 else HudTheme.CREAM
	var ink := HudTheme.INK if sel > 0.5 else Color(HudTheme.CREAM, 0.9)
	if sel > 0.5:
		draw_circle(c, 19.0, glow)
	MenuIcons.glyph(self, icon, c, 8.5, ink)
	var f := HudTheme.title_font(600)
	draw_string(f, Vector2(r.position.x + 64.0, r.get_center().y + 8.5), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 24,
			HudTheme.CREAM if sel < 0.5 else Color.WHITE)
	if subtitle != "":
		var sf := HudTheme.body_font(700)
		var w := sf.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(sf, Vector2(r.end.x - w - 22.0, r.get_center().y + 5.5), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(HudTheme.CREAM, 0.5 + 0.2 * sel))
	if has_focus():
		# a little breathing chevron
		var x := r.end.x - 20.0 + sin(_t * 5.0) * 2.0
		if subtitle == "":
			draw_line(Vector2(x - 5, c.y - 7), Vector2(x, c.y), Color(accent, 0.9), 3.0, true)
			draw_line(Vector2(x - 5, c.y + 7), Vector2(x, c.y), Color(accent, 0.9), 3.0, true)


func _draw_slider() -> void:
	var r := _ctrl_rect()
	var tr := _track()
	var y := r.get_center().y
	var f := clampf(inverse_lerp(min_value, max_value, float(value)), 0.0, 1.0)
	var xf := lerpf(tr.x, tr.y, f)
	var h := 10.0
	_capsule(Vector2(tr.x, y), Vector2(tr.y, y), h, Color(0, 0, 0, 0.32))
	if xf > tr.x + 0.5:
		_capsule(Vector2(tr.x, y), Vector2(xf, y), h, accent.darkened(0.15))
		_capsule(Vector2(tr.x, y - 1.5), Vector2(xf, y - 1.5), h * 0.4, Color(accent.lightened(0.35), 0.6))
	var gr := 12.0 + 3.0 * ease(_hl, -2.0) + 2.0 * _bump
	draw_circle(Vector2(xf, y + 2.5), gr, Color(0, 0, 0, 0.3))
	draw_circle(Vector2(xf, y), gr, HudTheme.CREAM)
	draw_arc(Vector2(xf, y), gr, 0.0, TAU, 32, HudTheme.INK, 2.4, true)
	draw_circle(Vector2(xf, y), gr * 0.38, accent.darkened(0.1))
	var text: String = format.call(value) if format.is_valid() else str(value)
	var tf := HudTheme.title_font(600)
	draw_string(tf, Vector2(tr.y + 18.0, y + 7.5), text, HORIZONTAL_ALIGNMENT_LEFT, 70, 19, HudTheme.CREAM)


func _capsule(a: Vector2, b: Vector2, h: float, col: Color) -> void:
	draw_line(a, b, col, h, true)
	draw_circle(a, h * 0.5, col)
	draw_circle(b, h * 0.5, col)


func _draw_choice() -> void:
	var r := _ctrl_rect()
	var y := r.get_center().y - 3.0
	var i := choice_values.find(value)
	var label: String = options[i] if i >= 0 else other_label
	var sel := ease(_hl, -2.0)
	var bg := HudTheme.pill(Color(0.02, 0.05, 0.03, 0.35 + 0.15 * sel), Color(HudTheme.CREAM, 0.12 + 0.2 * sel), 18)
	draw_style_box(bg, Rect2(r.position + Vector2(0, 2), r.size - Vector2(0, 4)))
	var col := Color(HudTheme.CREAM, 0.8 + 0.2 * sel)
	for side in [-1, 1]:
		var can := i < 0 or (i > 0 if side < 0 else i < choice_values.size() - 1)
		var cx: float = r.position.x + 22.0 if side < 0 else r.end.x - 22.0
		var a := Color(col, 1.0 if can else 0.22)
		var push: float = side * _bump * 3.0 if side == _bump_dir else 0.0
		draw_line(Vector2(cx + push + 4 * side * -1, y - 7), Vector2(cx + push + 4 * side, y), a, 3.0, true)
		draw_line(Vector2(cx + push + 4 * side * -1, y + 7), Vector2(cx + push + 4 * side, y), a, 3.0, true)
	var tf := HudTheme.title_font(600)
	var w := tf.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	var off := -_bump_dir * _bump * 10.0
	draw_string(tf, Vector2(r.get_center().x - w * 0.5 + off, y + 6.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 19,
			Color(HudTheme.GOLD if i < 0 else Color.WHITE, 1.0 - _bump * 0.5))
	# One pip per choice, the current one a little leaf-green pill.
	var n := choice_values.size()
	var gap := 11.0
	var x0 := r.get_center().x - (n - 1) * gap * 0.5
	for k in n:
		var p := Vector2(x0 + k * gap, r.end.y - 9.0)
		if k == i:
			_capsule(p - Vector2(3, 0), p + Vector2(3, 0), 5.0, accent)
		else:
			draw_circle(p, 2.2, Color(HudTheme.CREAM, 0.3))


func _draw_toggle() -> void:
	var r := _ctrl_rect()
	var pw := 64.0
	var ph := 34.0
	var p := Rect2(Vector2(r.end.x - pw, r.get_center().y - ph * 0.5), Vector2(pw, ph))
	var on := _knob
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.35).lerp(accent.darkened(0.1), on)
	sb.set_corner_radius_all(int(ph * 0.5))
	sb.border_color = Color(HudTheme.CREAM, 0.2 + 0.25 * ease(_hl, -2.0))
	sb.set_border_width_all(2)
	sb.anti_aliasing = true
	draw_style_box(sb, p)
	var kx := lerpf(p.position.x + ph * 0.5, p.end.x - ph * 0.5, on)
	var kc := Vector2(kx, p.get_center().y)
	draw_circle(kc + Vector2(0, 2), ph * 0.5 - 4.0, Color(0, 0, 0, 0.3))
	draw_circle(kc, ph * 0.5 - 4.0, HudTheme.CREAM)
	if on > 0.5:
		MapIcons.leaf(self, kc + Vector2(-3, 5), Vector2(0.5, -0.86), 11.0, 6.0, Color(accent.darkened(0.2), (on - 0.5) * 2.0))
	var lf := HudTheme.body_font(800)
	var text := "On" if value else "Off"
	var w := lf.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(lf, Vector2(p.position.x - w - 12.0, p.get_center().y + 5.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(HudTheme.CREAM, 0.45 + 0.35 * on))


func _draw_key() -> void:
	var r := _ctrl_rect()
	var tf := HudTheme.title_font(600)
	var text := "Press a key…" if listening else keycap
	var w := maxf(tf.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 26.0, 44.0)
	var cap := Rect2(Vector2(r.end.x - w, r.get_center().y - 16.0), Vector2(w, 32.0))
	var sb := StyleBoxFlat.new()
	var pulse := 0.5 + 0.5 * sin(_t * 6.0)
	sb.bg_color = HudTheme.GOLD.lerp(HudTheme.CREAM, pulse * 0.4) if listening else HudTheme.CREAM
	sb.set_corner_radius_all(8)
	sb.border_color = HudTheme.INK
	sb.set_border_width_all(2)
	sb.border_width_bottom = 4
	sb.anti_aliasing = true
	draw_style_box(sb, cap)
	draw_string(tf, Vector2(cap.position.x + (w - tf.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x) * 0.5, cap.get_center().y + 5.0),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, HudTheme.INK)
