class_name MenuIcons
extends RefCounted
## Little hand-drawn glyphs for the pause menu (and the round HUD buttons):
## pause, play, gear, door, speaker, eye, gamepad, sliders, sparkle, the
## "What's new" scroll and two friendly Kelings.

static func glyph(ci: CanvasItem, name: String, c: Vector2, s: float, col: Color) -> bool:
	var w := maxf(s * 0.24, 2.4)
	match name:
		"pause":
			for dx in [-0.42, 0.42]:
				var x: float = c.x + dx * s
				ci.draw_line(Vector2(x, c.y - s * 0.72), Vector2(x, c.y + s * 0.72), col, w * 1.35, true)
				ci.draw_circle(Vector2(x, c.y - s * 0.72), w * 0.67, col)
				ci.draw_circle(Vector2(x, c.y + s * 0.72), w * 0.67, col)
		"play":
			var pts := PackedVector2Array([c + Vector2(-0.55, -0.85) * s, c + Vector2(0.95, 0.0) * s, c + Vector2(-0.55, 0.85) * s])
			ci.draw_colored_polygon(pts, col)
			pts.append(pts[0])
			ci.draw_polyline(pts, col, w * 0.6, true)
		"gear":
			var teeth := 8
			var pts := PackedVector2Array()
			for i in teeth * 4:
				var a := TAU * i / float(teeth * 4)
				var r := s * (1.0 if (i % 4) < 2 else 0.74)
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			pts.append(pts[0])
			ci.draw_polyline(pts, col, w * 0.7, true)
			ci.draw_circle(c, s * 0.3, col, false, w * 0.75, true)
		"door":
			var r := Rect2(c + Vector2(-0.62, -0.95) * s, Vector2(1.05, 1.9) * s)
			ci.draw_rect(r, col, false, w * 0.75, true)
			ci.draw_circle(c + Vector2(0.18, 0.05) * s, s * 0.11, col)
			# a little arrow walking out
			ci.draw_line(c + Vector2(0.55, 0.0) * s, c + Vector2(1.15, 0.0) * s, col, w * 0.75, true)
			ci.draw_line(c + Vector2(0.9, -0.25) * s, c + Vector2(1.15, 0.0) * s, col, w * 0.75, true)
			ci.draw_line(c + Vector2(0.9, 0.25) * s, c + Vector2(1.15, 0.0) * s, col, w * 0.75, true)
		"speaker":
			var body := PackedVector2Array([c + Vector2(-1.0, -0.35) * s, c + Vector2(-0.55, -0.35) * s, c + Vector2(0.0, -0.85) * s,
					c + Vector2(0.0, 0.85) * s, c + Vector2(-0.55, 0.35) * s, c + Vector2(-1.0, 0.35) * s])
			ci.draw_colored_polygon(body, col)
			ci.draw_arc(c + Vector2(0.05, 0) * s, s * 0.5, -0.8, 0.8, 12, col, w * 0.7, true)
			ci.draw_arc(c + Vector2(0.05, 0) * s, s * 0.9, -0.8, 0.8, 16, Color(col, 0.7), w * 0.7, true)
		"eye":
			var pts := PackedVector2Array()
			for i in 25:
				var t := i / 24.0
				pts.append(c + Vector2(lerpf(-1.0, 1.0, t), -sin(t * PI) * 0.62) * s)
			for i in range(1, 24):
				var t := 1.0 - i / 24.0
				pts.append(c + Vector2(lerpf(-1.0, 1.0, t), sin(t * PI) * 0.62) * s)
			pts.append(pts[0])
			ci.draw_polyline(pts, col, w * 0.7, true)
			ci.draw_circle(c, s * 0.3, col)
		"gamepad":
			var r := Rect2(c + Vector2(-1.0, -0.55) * s, Vector2(2.0, 1.1) * s)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = col
			sb.set_border_width_all(int(maxf(w * 0.7, 2.0)))
			sb.set_corner_radius_all(int(s * 0.5))
			sb.anti_aliasing = true
			ci.draw_style_box(sb, r)
			ci.draw_line(c + Vector2(-0.62, 0) * s, c + Vector2(-0.22, 0) * s, col, w * 0.6, true)
			ci.draw_line(c + Vector2(-0.42, -0.2) * s, c + Vector2(-0.42, 0.2) * s, col, w * 0.6, true)
			ci.draw_circle(c + Vector2(0.38, -0.12) * s, s * 0.11, col)
			ci.draw_circle(c + Vector2(0.62, 0.12) * s, s * 0.11, col)
		"sliders":
			for k in 3:
				var y := c.y + (k - 1) * s * 0.62
				ci.draw_line(Vector2(c.x - s, y), Vector2(c.x + s, y), Color(col, 0.6), w * 0.55, true)
				var x: float = c.x + [0.35, -0.45, 0.1][k] * s
				ci.draw_circle(Vector2(x, y), s * 0.2, col)
		"sparkle":
			for k in 4:
				var a := k * PI * 0.5
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(c + d * s * 0.18, c + d * s * 1.0, col, w * 0.7, true)
			for k in 4:
				var a := k * PI * 0.5 + PI * 0.25
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(c + d * s * 0.2, c + d * s * 0.5, Color(col, 0.7), w * 0.55, true)
		"notes":
			# A rolled scroll.
			var r := Rect2(c + Vector2(-0.75, -0.85) * s, Vector2(1.5, 1.7) * s)
			ci.draw_rect(r, col, false, w * 0.8, true)
			for k in 3:
				var y := -0.4 + k * 0.4
				ci.draw_line(c + Vector2(-0.42, y) * s, c + Vector2(0.42 - (0.3 if k == 2 else 0.0), y) * s, col, w * 0.6, true)
			ci.draw_line(c + Vector2(-1.0, -0.85) * s, c + Vector2(1.0, -0.85) * s, col, w * 1.1, true)
			ci.draw_line(c + Vector2(-1.0, 0.85) * s, c + Vector2(1.0, 0.85) * s, col, w * 1.1, true)
		"friends":
			# Two Kelings side by side, the nearer one with a little sprout.
			var a := c + Vector2(-0.42, 0.05) * s
			var b := c + Vector2(0.4, -0.08) * s
			ci.draw_arc(a + Vector2(0, 0.95) * s, s * 0.62, PI * 1.12, PI * 1.88, 16, Color(col, 0.75), w * 0.8, true)
			ci.draw_circle(a, s * 0.36, Color(col, 0.75), false, w * 0.8, true)
			ci.draw_arc(b + Vector2(0, 1.05) * s, s * 0.7, PI * 1.12, PI * 1.88, 16, col, w * 0.9, true)
			ci.draw_circle(b, s * 0.42, col, false, w * 0.9, true)
			MapIcons.leaf(ci, b + Vector2(0, -0.42) * s, Vector2(0.5, -0.86), s * 0.55, s * 0.3, HudTheme.LEAF)
		"swap":
			# Two arrows chasing round a little leaf: change Keling.
			ci.draw_arc(c, s * 0.95, deg_to_rad(200), deg_to_rad(330), 16, col, w * 0.8, true)
			ci.draw_arc(c, s * 0.95, deg_to_rad(20), deg_to_rad(150), 16, col, w * 0.8, true)
			for a: float in [deg_to_rad(330), deg_to_rad(150)]:
				var out := Vector2(cos(a), sin(a))
				var tip := c + out * s * 0.95
				var tang := Vector2(-out.y, out.x)
				ci.draw_colored_polygon(PackedVector2Array([tip + tang * s * 0.4, tip + out * s * 0.32, tip - out * s * 0.32]), col)
			MapIcons.leaf(ci, c + Vector2(-0.22, 0.3) * s, Vector2(0.5, -0.86), s * 0.75, s * 0.4, HudTheme.LEAF)
		"back":
			ci.draw_line(c + Vector2(0.8, 0) * s, c + Vector2(-0.8, 0) * s, col, w, true)
			ci.draw_line(c + Vector2(-0.8, 0) * s, c + Vector2(-0.2, -0.6) * s, col, w, true)
			ci.draw_line(c + Vector2(-0.8, 0) * s, c + Vector2(-0.2, 0.6) * s, col, w, true)
		_:
			return false
	return true
