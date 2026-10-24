class_name BenchCaption
extends CanvasLayer
## A gentle title card while your Keling sits on a bench: the bench's name,
## a line about the view, and the view tag in its element's colour. It fades
## in as you settle, lingers, and drifts away (or leaves at once when you
## stand up).

const HOLD := 6.0

var _root: Control
var _title: Label
var _line: Label
var _tag: Label
var _hint: Label
var _tween: Tween


## Shows the card for a bench, creating the overlay on first use.
static func show_for(tree: SceneTree, bench: Bench) -> void:
	_instance(tree).present(bench)


static func dismiss(tree: SceneTree) -> void:
	var c := tree.root.get_node_or_null("BenchCaption") as BenchCaption
	if c:
		c.fade_out(0.45)


static func _instance(tree: SceneTree) -> BenchCaption:
	var c := tree.root.get_node_or_null("BenchCaption") as BenchCaption
	if c == null:
		c = BenchCaption.new()
		c.name = "BenchCaption"
		tree.root.add_child(c)
	return c


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.modulate.a = 0.0
	add_child(_root)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.offset_top = 70.0
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_tag = _label(15, Color(1, 1, 1, 0.9))
	_title = _label(36, Color(1.0, 0.97, 0.88))
	_line = _label(19, Color(1, 1, 1, 0.82))
	_hint = _label(14, Color(1, 1, 1, 0.55))
	for l in [_tag, _title, _line, _hint]:
		box.add_child(l)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	box.move_child(spacer, 3)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func present(bench: Bench) -> void:
	var site := bench.site
	var glow: Color = BenchBuilder.ELEMENT_GLOW.get(site.element, Color.WHITE)
	_tag.text = "·  %s  ·" % bench.view_name().to_upper()
	_tag.add_theme_color_override("font_color", glow.lerp(Color.WHITE, 0.25))
	_title.text = site.title
	_line.text = site.caption
	_hint.text = _stand_hint()
	if _tween:
		_tween.kill()
	_root.position.y = 14.0
	_tween = create_tween().set_parallel()
	_tween.tween_property(_root, "modulate:a", 1.0, 1.1).set_delay(0.5).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_root, "position:y", 0.0, 1.4).set_delay(0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_property(_root, "modulate:a", 0.0, 1.6).set_delay(HOLD).set_trans(Tween.TRANS_SINE)


func fade_out(time: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 0.0, time)


static func _stand_hint() -> String:
	match Bench.input_method():
		1:
			return "Move or press X to stand up"
		2:
			return "Move or tap the hand to stand up"
	return "Move or press E to stand up"
