class_name CoopToasts
extends Control
## Little pills that drop in at the top of the screen when a friend joins or
## heads home, each with the player's colour. At most three at a time; each
## stays a few seconds, then floats up and fades.

const HOLD := 4.2
const MAX := 3

var top_margin := 18.0
var _toasts: Array = []   # [PanelContainer, age]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func push(text: String, color: Color) -> void:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", HudTheme.pill(Color(HudTheme.GLASS, 0.82), Color(color, 0.6), 20))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	pill.add_child(row)
	var dot := Control.new()
	dot.custom_minimum_size = Vector2(14, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.draw.connect(func():
		dot.draw_circle(Vector2(7, 7), 7.0, color)
		dot.draw_arc(Vector2(7, 7), 7.0, 0, TAU, 16, HudTheme.INK, 1.4, true))
	row.add_child(dot)
	var l := Label.new()
	l.text = text
	HudTheme.style_label(l, 18, HudTheme.CREAM, HudTheme.title_font(520))
	row.add_child(l)
	pill.modulate.a = 0.0
	add_child(pill)
	_toasts.push_front([pill, 0.0])
	while _toasts.size() > MAX:
		var old: Array = _toasts.pop_back()
		old[0].queue_free()


func _process(delta: float) -> void:
	var y := top_margin
	for i in range(_toasts.size() - 1, -1, -1):
		var t: Array = _toasts[i]
		t[1] += delta
		if t[1] > HOLD + 0.6:
			t[0].queue_free()
			_toasts.remove_at(i)
	for t in _toasts:
		var pill: PanelContainer = t[0]
		var age: float = t[1]
		var a_in := ease(clampf(age / 0.35, 0.0, 1.0), -2.2)
		var a_out := clampf((age - HOLD) / 0.6, 0.0, 1.0)
		pill.reset_size()
		var target := Vector2((size.x - pill.size.x) * 0.5, y - 14.0 * (1.0 - a_in) - 10.0 * a_out)
		pill.position = target if age < 0.02 else pill.position.lerp(target, 1.0 - exp(-14.0 * delta))
		pill.modulate.a = a_in * (1.0 - a_out)
		y += pill.size.y + 8.0
