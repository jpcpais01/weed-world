extends CanvasLayer
## In-game HUD: touch controls on phones, control hints on desktop / gamepad,
## a debug readout (F3) and a "What's new" panel fed by PATCH_NOTES.md.

const PATCH_NOTES := "res://PATCH_NOTES.md"

var _touch: TouchControls
var _hints: Label
var _debug: Label
var _notes_panel: PanelContainer
var _hint_timer := 14.0
var _debug_on := false


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_touch = TouchControls.new()
	root.add_child(_touch)

	var title := Label.new()
	title.text = "Weed World  ·  v%s  ·  movement test" % ProjectSettings.get_setting("application/config/version", "0.1")
	title.position = Vector2(24, 18)
	_style_label(title, 18, Color(1, 1, 1, 0.75))
	root.add_child(title)

	_hints = Label.new()
	_style_label(_hints, 17, Color(1, 1, 1, 0.85))
	_hints.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hints.position = Vector2(24, -24)
	root.add_child(_hints)

	_debug = Label.new()
	_style_label(_debug, 15, Color(0.85, 1, 0.75, 0.95))
	_debug.position = Vector2(24, 48)
	_debug.visible = false
	root.add_child(_debug)

	var notes_btn := Button.new()
	notes_btn.text = "What's new"
	notes_btn.flat = false
	notes_btn.focus_mode = Control.FOCUS_NONE
	notes_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	notes_btn.position = Vector2(-160, 14)
	notes_btn.custom_minimum_size = Vector2(136, 40)
	notes_btn.add_theme_stylebox_override("normal", _pill(Color(0.06, 0.12, 0.06, 0.45)))
	notes_btn.add_theme_stylebox_override("hover", _pill(Color(0.12, 0.22, 0.1, 0.6)))
	notes_btn.add_theme_stylebox_override("pressed", _pill(Color(0.2, 0.35, 0.15, 0.7)))
	notes_btn.pressed.connect(_toggle_notes)
	root.add_child(notes_btn)

	_build_notes(root)
	GameInput.input_method_changed.connect(func(_m): _refresh())
	_refresh()


func _style_label(l: Label, size: int, color: Color) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _pill(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(20)
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(2)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	return sb


func _build_notes(root: Control) -> void:
	_notes_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.09, 0.05, 0.9)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(22)
	sb.border_color = Color(0.7, 1.0, 0.55, 0.4)
	sb.set_border_width_all(2)
	_notes_panel.add_theme_stylebox_override("panel", sb)
	_notes_panel.set_anchors_preset(Control.PRESET_CENTER)
	_notes_panel.custom_minimum_size = Vector2(640, 460)
	_notes_panel.position = -_notes_panel.custom_minimum_size * 0.5
	_notes_panel.visible = false
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.scroll_active = true
	text.custom_minimum_size = Vector2(596, 416)
	text.add_theme_font_size_override("normal_font_size", 17)
	text.add_theme_font_size_override("bold_font_size", 19)
	text.text = _notes_bbcode()
	text.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and e.double_click:
			_toggle_notes())
	_notes_panel.add_child(text)
	root.add_child(_notes_panel)


func _notes_bbcode() -> String:
	var f := FileAccess.open(PATCH_NOTES, FileAccess.READ)
	if f == null:
		return "[b]No patch notes yet.[/b]"
	var out := PackedStringArray()
	for line in f.get_as_text().split("\n"):
		if line.begins_with("# "):
			out.append("[font_size=26][b]%s[/b][/font_size]" % line.substr(2))
		elif line.begins_with("## "):
			out.append("\n[color=#bff59a][b]%s[/b][/color]" % line.substr(3))
		elif line.begins_with("- "):
			out.append("  •  " + line.substr(2).replace("**", ""))
		elif not line.strip_edges().is_empty():
			out.append("[color=#cfd8cc]%s[/color]" % line)
	return "\n".join(out)


func _toggle_notes() -> void:
	_notes_panel.visible = not _notes_panel.visible
	if _notes_panel.visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _refresh() -> void:
	var touch := GameInput.method == GameInput.Method.TOUCH
	_touch.visible = touch
	match GameInput.method:
		GameInput.Method.TOUCH:
			_hints.text = ""
		GameInput.Method.GAMEPAD:
			_hints.text = "Left stick  move (push gently to walk)\nRight stick  camera   ·   LB/RB  zoom\nA  jump (hold for higher)   ·   X  grab   ·   B / L3  sprint\nD-pad  dance · cheer · sit · nod"
		_:
			_hints.text = "WASD  move   ·   Shift  sprint   ·   C  walk toggle\nSpace  jump (hold for higher)   ·   E  grab\nClick  capture mouse to look   ·   Wheel  zoom   ·   Esc  release\n1 dance   2 cheer   3 sit   4 nod   ·   F3 debug   ·   F11 fullscreen"
	_hints.modulate.a = 1.0
	_hint_timer = 14.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_debug_on = not _debug_on
		_debug.visible = _debug_on


func _process(delta: float) -> void:
	if _hint_timer > 0.0:
		_hint_timer -= delta
	else:
		_hints.modulate.a = move_toward(_hints.modulate.a, 0.35, delta * 0.5)
	if _debug_on:
		var player := get_tree().get_first_node_in_group("player")
		var txt := "%d fps\n" % Engine.get_frames_per_second()
		if player and player.has_method("get_debug_text"):
			txt += player.get_debug_text()
		_debug.text = txt
