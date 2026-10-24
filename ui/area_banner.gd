class_name AreaBanner
extends Control
## "You have found…" title card that drifts in at the top of the screen when
## your Keling wanders into a named place.

var _title: Label
var _sub: Label
var _t := -1.0
var _hold := 3.2
var _accent := HudTheme.GOLD

const IN := 0.7
const OUT := 1.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -450.0
	offset_right = 450.0
	offset_top = 84.0
	offset_bottom = 214.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = Label.new()
	HudTheme.style_label(_title, 46, HudTheme.CREAM, HudTheme.title_font(600))
	_title.add_theme_color_override("font_outline_color", Color(HudTheme.INK, 0.55))
	_title.add_theme_constant_override("outline_size", 8)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size = Vector2(900, 60)
	_title.position = Vector2(0, 22)
	add_child(_title)
	_sub = Label.new()
	HudTheme.style_label(_sub, 19, Color(HudTheme.CREAM, 0.9), HudTheme.body_font(650))
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.size = Vector2(900, 28)
	_sub.position = Vector2(0, 86)
	add_child(_sub)
	modulate.a = 0.0


func show_place(title: String, subtitle: String, accent := HudTheme.GOLD, hold := 3.2) -> void:
	_title.text = title
	_sub.text = subtitle
	_accent = accent
	_hold = hold
	_t = 0.0


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_timed(delta)
	PerfMeter.add(&"area banner", Time.get_ticks_usec() - t0)


func _process_timed(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	var a := 0.0
	if _t < IN:
		a = ForestLayout.sstep(0.0, 1.0, _t / IN)
	elif _t < IN + _hold:
		a = 1.0
	elif _t < IN + _hold + OUT:
		a = 1.0 - ForestLayout.sstep(0.0, 1.0, (_t - IN - _hold) / OUT)
	else:
		_t = -1.0
	modulate.a = a
	_title.position.y = 22.0 + (1.0 - a) * -10.0
	queue_redraw()


func _draw() -> void:
	if _t < 0.0:
		return
	var grow := ForestLayout.sstep(0.1, 1.0, _t / (IN * 1.4))
	var cx := size.x * 0.5
	var font := HudTheme.title_font(600)
	var tw := font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
	var half := (tw * 0.5 + 40.0) * grow
	# Soft dark wash behind the text so it reads over bright meadow.
	for k in 6:
		var r := Vector2(half + 80.0 - k * 10.0, 58.0 - k * 6.0)
		_ellipse(Vector2(cx, 70), r, Color(0.0, 0.04, 0.02, 0.05))
	# Ornament: a vine line with a bud on each end and a little star on top.
	var y := 16.0
	draw_line(Vector2(cx - half, y), Vector2(cx - 18.0, y), Color(_accent, 0.85), 2.0, true)
	draw_line(Vector2(cx + 18.0, y), Vector2(cx + half, y), Color(_accent, 0.85), 2.0, true)
	MapIcons.star(self, Vector2(cx, y), 9.0, _accent, Color(HudTheme.INK, 0.6))
	for s in [-1.0, 1.0]:
		var e := Vector2(cx + s * half, y)
		MapIcons.leaf(self, e, Vector2(s, -0.5).normalized(), 16.0, 8.0, Color(HudTheme.LEAF, 0.9))
		draw_circle(e, 3.5, _accent)
	var y2 := 120.0
	draw_line(Vector2(cx - half * 0.55, y2), Vector2(cx + half * 0.55, y2), Color(_accent, 0.45), 1.5, true)


func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 32:
		var a := TAU * k / 32.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)
