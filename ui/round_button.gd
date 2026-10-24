class_name RoundIconButton
extends Button
## A round, touch-sized HUD button with a hand-drawn glyph. Squishes when
## pressed, glows on hover, and can show a little "something new" dot.

var glyph := ""
var dot := false:
	set(v):
		dot = v
		queue_redraw()
var light := false   ## cream face with ink glyph instead of glass
var _hover := 0.0
var _press := 0.0
var _t := 0.0


func _init(p_glyph := "", diameter := 52.0, p_light := false) -> void:
	glyph = p_glyph
	light = p_light
	custom_minimum_size = Vector2.ONE * diameter
	size = custom_minimum_size
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_to_group("touch_blockers")
	button_down.connect(func(): _press = 1.0)


func _process(delta: float) -> void:
	_t += delta
	var h := 1.0 if is_hovered() else 0.0
	var before := _hover + _press
	_hover = move_toward(_hover, h, delta * 7.0)
	_press = move_toward(_press, 1.0 if button_pressed or get_draw_mode() == DRAW_PRESSED else 0.0, delta * 9.0)
	if not is_equal_approx(before, _hover + _press) or dot:
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 * (1.0 - 0.08 * _press)
	draw_circle(c + Vector2(0, 3), r, Color(0, 0, 0, 0.25))
	var face := HudTheme.CREAM if light else Color(HudTheme.GLASS, 0.62 + 0.15 * _hover)
	var ink := HudTheme.INK if light else HudTheme.CREAM
	draw_circle(c, r, face)
	if light:
		draw_circle(c + Vector2(0, r * 0.1), r * 0.84, Color(0.93, 0.87, 0.74))
		draw_circle(c - Vector2(0, r * 0.04), r * 0.82, Color(1.0, 0.98, 0.92))
	draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(HudTheme.INK, 0.85) if light else Color(HudTheme.CREAM, 0.25 + 0.35 * _hover), 2.4, true)
	_glyph(c, r * 0.42, ink)
	if dot:
		var dp := c + Vector2(r * 0.68, -r * 0.68)
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		draw_circle(dp, 7.5 + pulse * 1.5, Color(HudTheme.BLOSSOM, 0.35))
		draw_circle(dp, 6.0, HudTheme.BLOSSOM)
		draw_arc(dp, 6.0, 0.0, TAU, 20, HudTheme.INK, 1.6, true)


func _glyph(c: Vector2, s: float, col: Color) -> void:
	var w := maxf(s * 0.24, 2.4)
	match glyph:
		"plus":
			draw_line(c - Vector2(s, 0), c + Vector2(s, 0), col, w, true)
			draw_line(c - Vector2(0, s), c + Vector2(0, s), col, w, true)
		"minus":
			draw_line(c - Vector2(s, 0), c + Vector2(s, 0), col, w, true)
		"close":
			draw_line(c - Vector2(s, s) * 0.8, c + Vector2(s, s) * 0.8, col, w, true)
			draw_line(c + Vector2(-s, s) * 0.8, c + Vector2(s, -s) * 0.8, col, w, true)
		"center":
			draw_arc(c, s * 0.7, 0.0, TAU, 32, col, w * 0.8, true)
			draw_circle(c, s * 0.26, col)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + d * s * 0.75, c + d * s * 1.15, col, w * 0.8, true)
		"map":
			# A folded map with a little path on it.
			var pts := PackedVector2Array([c + Vector2(-1.0, -0.7) * s, c + Vector2(-0.35, -0.95) * s, c + Vector2(0.35, -0.7) * s,
					c + Vector2(1.0, -0.95) * s, c + Vector2(1.0, 0.75) * s, c + Vector2(0.35, 1.0) * s,
					c + Vector2(-0.35, 0.75) * s, c + Vector2(-1.0, 1.0) * s, c + Vector2(-1.0, -0.7) * s])
			draw_polyline(pts, col, w * 0.8, true)
			draw_line(c + Vector2(-0.35, -0.95) * s, c + Vector2(-0.35, 0.75) * s, Color(col, 0.6), w * 0.6, true)
			draw_line(c + Vector2(0.35, -0.7) * s, c + Vector2(0.35, 1.0) * s, Color(col, 0.6), w * 0.6, true)
			draw_circle(c + Vector2(0.62, -0.25) * s, s * 0.17, HudTheme.GOLD)
		"notes":
			# A rolled scroll.
			var r := Rect2(c + Vector2(-0.75, -0.85) * s, Vector2(1.5, 1.7) * s)
			draw_rect(r, col, false, w * 0.8, true)
			for k in 3:
				var y := -0.4 + k * 0.4
				draw_line(c + Vector2(-0.42, y) * s, c + Vector2(0.42 - (0.3 if k == 2 else 0.0), y) * s, col, w * 0.6, true)
			draw_line(c + Vector2(-1.0, -0.85) * s, c + Vector2(1.0, -0.85) * s, col, w * 1.1, true)
			draw_line(c + Vector2(-1.0, 0.85) * s, c + Vector2(1.0, 0.85) * s, col, w * 1.1, true)
		"friends":
			# Two Kelings side by side, the nearer one with a little sprout.
			var a := c + Vector2(-0.42, 0.05) * s
			var b := c + Vector2(0.4, -0.08) * s
			draw_arc(a + Vector2(0, 0.95) * s, s * 0.62, PI * 1.12, PI * 1.88, 16, Color(col, 0.75), w * 0.8, true)
			draw_circle(a, s * 0.36, Color(col, 0.75), false, w * 0.8, true)
			draw_arc(b + Vector2(0, 1.05) * s, s * 0.7, PI * 1.12, PI * 1.88, 16, col, w * 0.9, true)
			draw_circle(b, s * 0.42, col, false, w * 0.9, true)
			MapIcons.leaf(self, b + Vector2(0, -0.42) * s, Vector2(0.5, -0.86), s * 0.55, s * 0.3, HudTheme.LEAF)
		"dice":
			var r := Rect2(c - Vector2(s, s) * 0.85, Vector2(s, s) * 1.7)
			draw_rect(r, col, false, w * 0.8, true)
			for k in [-0.45, 0.0, 0.45]:
				draw_circle(c + Vector2(k, k) * s, s * 0.15, col)
		"copy":
			var back := Rect2(c + Vector2(-0.8, -0.8) * s, Vector2(1.15, 1.25) * s)
			var front := Rect2(c + Vector2(-0.3, -0.4) * s, Vector2(1.15, 1.25) * s)
			draw_rect(back, Color(col, 0.6), false, w * 0.7, true)
			draw_rect(front, Color(HudTheme.INK if light else HudTheme.GLASS, 1.0), true)
			draw_rect(front, col, false, w * 0.8, true)
		"pin_off":
			MapIcons.star(self, c, s * 0.95, Color(HudTheme.GOLD, 0.9), HudTheme.INK)
			draw_line(c - Vector2(s, s), c + Vector2(s, s), HudTheme.INK, w * 1.6, true)
			draw_line(c - Vector2(s, s), c + Vector2(s, s), col if light else HudTheme.BLOSSOM, w * 0.8, true)
