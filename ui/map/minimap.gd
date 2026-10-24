class_name Minimap
extends Control
## Round minimap in the corner. It turns with the camera, so "up" is always
## the way you are looking, and the little N bead on the rim keeps north in
## sight. Shows nearby places, your Keling and its view, the other Kelings in
## the session and the waypoint (pinned to the rim with its distance when it
## is out of range). Click or tap it, or press M, for the world map. The mouse
## wheel over it zooms.

signal open_requested

const DISK_RADIUS := 92.0
const MIN_RANGE := 16.0
const MAX_RANGE := 48.0

var state: MapState
var view_range := 28.0      ## metres from the centre to the rim
var _range_target := 28.0
var _disk: ColorRect
var _mat: ShaderMaterial
var _over: Control
var _hover := 0.0
var _hovered := false
var _t := 0.0
var _yaw := 0.0
var _center := Vector2.ZERO


func _init(p_state: MapState) -> void:
	state = p_state


func _ready() -> void:
	custom_minimum_size = Vector2.ONE * (DISK_RADIUS + 22.0) * 2.0
	size = custom_minimum_size
	pivot_offset = size * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = ""
	add_to_group("touch_blockers")

	_disk = ColorRect.new()
	_disk.size = Vector2.ONE * DISK_RADIUS * 2.0
	_disk.position = size * 0.5 - _disk.size * 0.5
	_disk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://ui/map/minimap.gdshader")
	_disk.material = _mat
	add_child(_disk)

	_over = Control.new()
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.draw.connect(_draw_overlay)
	add_child(_over)

	state.texture_ready.connect(_on_texture)
	if state.texture:
		_on_texture()
	mouse_entered.connect(func(): _hovered = true)
	mouse_exited.connect(func(): _hovered = false)


func _on_texture() -> void:
	_mat.set_shader_parameter("map_tex", state.texture)
	_mat.set_shader_parameter("has_map", true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if _in_disk(event.position):
					open_requested.emit()
					accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				_range_target = clampf(_range_target * 0.88, MIN_RANGE, MAX_RANGE)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				_range_target = clampf(_range_target * 1.12, MIN_RANGE, MAX_RANGE)
				accept_event()


func _in_disk(p: Vector2) -> bool:
	return p.distance_to(size * 0.5) < DISK_RADIUS + 18.0


func _has_point(point: Vector2) -> bool:
	return _in_disk(point)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_timed(delta)
	PerfMeter.add(&"minimap", Time.get_ticks_usec() - t0)


func _process_timed(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_hover = move_toward(_hover, 1.0 if _hovered else 0.0, delta * 6.0)
	scale = Vector2.ONE * (1.0 + 0.035 * _hover)
	view_range = lerpf(view_range, _range_target, 1.0 - exp(-10.0 * delta))
	var cam := get_tree().get_first_node_in_group("orbit_camera")
	if cam:
		_yaw = cam.yaw
	var me := MapState.local_player(get_tree())
	if not me.is_empty():
		_center = me.pos
	_mat.set_shader_parameter("center_uv", MapBaker.world_to_uv(_center))
	_mat.set_shader_parameter("view_uv", view_range / (MapState.EXTENT * 2.0))
	_mat.set_shader_parameter("rot", -_yaw)
	_over.queue_redraw()


## World XZ -> overlay pixels. Map offsets turn with the camera.
func _to_screen(p: Vector2) -> Vector2:
	var q := (p - _center) / view_range * DISK_RADIUS
	return size * 0.5 + q.rotated(_yaw)


func _draw_overlay() -> void:
	var c := size * 0.5
	var R := DISK_RADIUS
	var font := HudTheme.title_font(650)

	# Places within range.
	for pl in state.places:
		var d: float = (pl.pos as Vector2).distance_to(_center)
		if d > view_range * 0.9:
			continue
		var fade := 1.0 - ForestLayout.sstep(view_range * 0.75, view_range * 0.9, d)
		if fade < 0.15:
			continue
		MapIcons.badge(_over, _to_screen(pl.pos), 10.5 * fade, pl.icon, _t)

	# Waypoint: in the disk, or riding the rim with its distance.
	if state.has_waypoint:
		var wd := state.waypoint.distance_to(_center)
		var ws := _to_screen(state.waypoint)
		if (ws - c).length() < R - 12.0:
			MapIcons.pin(_over, ws, 13.0, _t)
		else:
			var dir := (ws - c).normalized()
			var at := c + dir * (R - 2.0)
			_rim_arrow(at, dir, HudTheme.GOLD)
			MapIcons.star(_over, at - dir * 13.0, 8.5, HudTheme.GOLD, HudTheme.INK)
			var label := "%d m" % roundi(wd)
			var lp := at - dir * 32.0
			var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_rect_rounded(Rect2(lp - Vector2(tw * 0.5 + 6, 10), Vector2(tw + 12, 19)), Color(HudTheme.INK, 0.72))
			_over.draw_string(font, lp + Vector2(-tw * 0.5, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HudTheme.GOLD)

	# Your view: a soft wedge pointing up, where the camera looks.
	var cone := PackedVector2Array([c])
	var cols := PackedColorArray([Color(1, 0.98, 0.85, 0.32)])
	for k in 13:
		var a := deg_to_rad(-90.0 - 36.0 + 72.0 * k / 12.0)
		cone.append(c + Vector2(cos(a), sin(a)) * R * 0.62)
		cols.append(Color(1, 0.98, 0.85, 0.0))
	_over.draw_polygon(cone, cols)

	# Kelings.
	for p in MapState.players(get_tree()):
		var s := _to_screen(p.pos)
		var ang: float = p.heading + _yaw
		if p.local:
			continue
		if (s - c).length() < R - 10.0:
			MapIcons.player(_over, s, ang, p.color, 7.0, _t, false)
		else:
			var dir := (s - c).normalized()
			var at := c + dir * (R - 2.0)
			_rim_arrow(at, dir, p.color)
			_over.draw_circle(at - dir * 11.0, 6.5, HudTheme.INK)
			_over.draw_circle(at - dir * 11.0, 4.8, p.color)
	var me := MapState.local_player(get_tree())
	if not me.is_empty():
		MapIcons.player(_over, c, me.heading + _yaw, me.color, 9.5, _t, true)

	_draw_frame(c, R, font)


func draw_rect_rounded(r: Rect2, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(r.size.y * 0.5))
	sb.anti_aliasing = true
	_over.draw_style_box(sb, r)


func _rim_arrow(at: Vector2, dir: Vector2, col: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	var tip := at + dir * 9.0
	var pts := PackedVector2Array([tip, at - side * 7.0, at + side * 7.0])
	_over.draw_colored_polygon(pts, HudTheme.INK)
	var inner := PackedVector2Array([at + dir * 6.0, at - side * 4.5 + dir * 0.5, at + side * 4.5 + dir * 0.5])
	_over.draw_colored_polygon(inner, col)


func _draw_frame(c: Vector2, R: float, font: Font) -> void:
	var glow := 0.35 + 0.4 * _hover
	_over.draw_arc(c, R + 6.5, 0.0, TAU, 96, Color(0, 0, 0, 0.25), 15.0, true)
	_over.draw_arc(c, R + 5.0, 0.0, TAU, 96, Color(HudTheme.INK, 0.88), 10.0, true)
	_over.draw_arc(c, R + 0.8, 0.0, TAU, 96, Color(HudTheme.CREAM, 0.85), 2.2, true)
	_over.draw_arc(c, R + 9.6, 0.0, TAU, 96, Color(HudTheme.CREAM, glow), 1.6, true)
	# Rim ticks every 30 degrees, turning with the map.
	for k in 12:
		var a := _yaw + TAU * k / 12.0 - PI * 0.5
		var d := Vector2(cos(a), sin(a))
		var big := k % 3 == 0
		_over.draw_line(c + d * (R + 2.5), c + d * (R + (7.5 if big else 5.0)), Color(HudTheme.CREAM, 0.7 if big else 0.4), 1.6, true)
	# Leafy sprigs tucked into the frame.
	for side in [-1.0, 1.0]:
		var base := c + Vector2(side * 0.62, 0.79) * (R + 5.0)
		MapIcons.leaf(_over, base, Vector2(side * 0.9, 0.42).normalized(), 24.0, 11.0, Color(0.34, 0.6, 0.3))
		MapIcons.leaf(_over, base, Vector2(side * 0.45, 0.9).normalized(), 19.0, 9.0, Color(0.46, 0.72, 0.36))
		_over.draw_circle(base + Vector2(side * 4.0, -2.0), 3.6, HudTheme.BLOSSOM)
		_over.draw_circle(base + Vector2(side * 4.0, -2.0), 1.4, HudTheme.GOLD)
	# North bead.
	var n := Vector2(0, -1).rotated(_yaw)
	var nb := c + n * (R + 5.0)
	_over.draw_circle(nb + Vector2(0, 2), 12.5, Color(0, 0, 0, 0.3))
	_over.draw_circle(nb, 12.0, HudTheme.CREAM)
	_over.draw_arc(nb, 12.0, 0.0, TAU, 32, HudTheme.INK, 2.4, true)
	var nw := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_over.draw_string(font, nb + Vector2(-nw * 0.5, 6.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.25, 0.2))
	# What opens the big map.
	var hint := "M" if GameInput.method == GameInput.Method.KEYBOARD_MOUSE else ""
	var hb := c + Vector2(0, R + 6.0)
	if hint != "":
		var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var box := Rect2(hb - Vector2(hw * 0.5 + 8.0, 10.0), Vector2(hw + 16.0, 20.0))
		var sb := StyleBoxFlat.new()
		sb.bg_color = HudTheme.CREAM
		sb.set_corner_radius_all(6)
		sb.border_color = HudTheme.INK
		sb.set_border_width_all(2)
		sb.border_width_bottom = 4
		sb.anti_aliasing = true
		_over.draw_style_box(sb, box)
		_over.draw_string(font, hb + Vector2(-hw * 0.5, 4.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HudTheme.INK)
	else:
		# Expand glyph: two little corner arrows.
		_over.draw_circle(hb, 12.0, HudTheme.CREAM)
		_over.draw_arc(hb, 12.0, 0.0, TAU, 32, HudTheme.INK, 2.2, true)
		for sgn in [-1.0, 1.0]:
			var o := hb + Vector2(sgn * 4.2, -sgn * 4.2)
			_over.draw_line(o, o + Vector2(-sgn * 4.0, 0), HudTheme.INK, 2.0, true)
			_over.draw_line(o, o + Vector2(0, sgn * 4.0), HudTheme.INK, 2.0, true)
			_over.draw_line(o, o - Vector2(sgn * 5.0, -sgn * 5.0) * 0.8, HudTheme.INK, 2.0, true)
