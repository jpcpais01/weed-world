class_name CoopRosterRow
extends Control
## One of the four places in a co-op forest: the player's map colour, their
## name, "you" / "host" tags and how quick their connection is. An empty
## place waits with a gently pulsing outline.

var slot := 0
var _p := {}
var _viewer_hosts := false
var _t := 0.0


func _init(p_slot: int) -> void:
	slot = p_slot
	custom_minimum_size = Vector2(0, 46)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_player(p: Dictionary, viewer_hosts: bool) -> void:
	_p = p
	_viewer_hosts = viewer_hosts
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta


func _draw() -> void:
	var col: Color = HudTheme.PLAYER_COLORS[slot]
	var r := Rect2(Vector2.ZERO, size)
	var filled := not _p.is_empty()
	var bg := StyleBoxFlat.new()
	bg.set_corner_radius_all(14)
	bg.anti_aliasing = true
	if filled:
		bg.bg_color = Color(col.darkened(0.55), 0.55)
		bg.border_color = Color(col, 0.55 if _p.local else 0.3)
		bg.set_border_width_all(2)
	else:
		bg.bg_color = Color(0, 0, 0, 0.12)
		bg.border_color = Color(HudTheme.CREAM, 0.1 + 0.08 * (0.5 + 0.5 * sin(_t * 2.4 + slot)))
		bg.set_border_width_all(2)
	draw_style_box(bg, r)
	var cy := size.y * 0.5
	var font := HudTheme.title_font(560)
	var body := HudTheme.body_font(750)
	if not filled:
		draw_circle(Vector2(26, cy), 9.0, Color(col, 0.25), false, 2.0, true)
		draw_string(body, Vector2(48, cy + 6), "Waiting for a friend…", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(HudTheme.CREAM, 0.35))
		return
	# Their map dot: the same arrowhead the minimap uses, in their colour.
	draw_circle(Vector2(26, cy), 12.0, Color(col, 0.3))
	draw_circle(Vector2(26, cy), 8.0, col)
	draw_arc(Vector2(26, cy), 8.0, 0, TAU, 20, HudTheme.INK, 1.6, true)
	var x := 48.0
	var nm: String = _p.name
	draw_string(font, Vector2(x, cy + 7), nm, HORIZONTAL_ALIGNMENT_LEFT, size.x - 210, 20, HudTheme.CREAM)
	x += minf(font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x, size.x - 210) + 10.0
	var tags: Array[String] = []
	if _p.local:
		tags.append("you")
	if int(_p.id) == 1:
		tags.append("host")
	for tag in tags:
		var tw := body.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14.0
		var tr := Rect2(Vector2(x, cy - 11), Vector2(tw, 22))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col, 0.85) if tag == "you" else Color(HudTheme.CREAM, 0.16)
		sb.set_corner_radius_all(11)
		sb.anti_aliasing = true
		draw_style_box(sb, tr)
		draw_string(body, Vector2(x + 7, cy + 5), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HudTheme.INK if tag == "you" else HudTheme.CREAM)
		x += tw + 6.0
	# Connection: round trip through the relay.
	var ping := int(_p.ping)
	var bars := 3 if ping > 0 and ping < 160 else (2 if ping > 0 and ping < 320 else (1 if ping > 0 else 0))
	var bx := size.x - 22.0
	for i in 3:
		var h := 6.0 + i * 5.0
		var on := i < bars
		draw_rect(Rect2(Vector2(bx - (2 - i) * 7.0, cy + 8 - h), Vector2(4.5, h)),
			(HudTheme.LEAF if bars == 3 else (HudTheme.GOLD if bars == 2 else HudTheme.BLOSSOM)) if on else Color(HudTheme.CREAM, 0.15))
	var label := "%d ms" % ping if ping > 0 else "…"
	var lw := body.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(body, Vector2(bx - 26 - lw, cy + 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(HudTheme.CREAM, 0.6))
