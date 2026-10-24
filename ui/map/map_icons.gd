class_name MapIcons
extends RefCounted
## Hand-drawn map glyphs, all vector so they stay crisp at any zoom on any
## screen: landmark badges, the Keling markers and the waypoint pin. Every
## function draws into the given CanvasItem from inside its _draw().

const INK := HudTheme.INK
const CREAM := HudTheme.CREAM


## A round cream badge with the landmark's glyph. `t` animates fire, glow and
## sparkle; `lift` (0..1) pops the badge up when hovered or selected.
static func badge(ci: CanvasItem, c: Vector2, r: float, icon: String, t: float, lift := 0.0) -> void:
	r *= 1.0 + 0.18 * lift
	c.y -= r * 0.25 * lift
	ci.draw_circle(c + Vector2(0, r * 0.2 + r * 0.25 * lift), r * 1.04, Color(0, 0, 0, 0.28 + 0.1 * lift))
	ci.draw_circle(c, r, CREAM)
	ci.draw_circle(c + Vector2(0, r * 0.12), r * 0.86, Color(0.93, 0.87, 0.74))
	ci.draw_circle(c - Vector2(0, r * 0.05), r * 0.82, Color(1.0, 0.98, 0.92))
	ci.draw_arc(c, r, 0.0, TAU, 40, Color(INK, 0.85), maxf(r * 0.13, 1.5), true)
	glyph(ci, c, r * 0.62, icon, t)


static func glyph(ci: CanvasItem, c: Vector2, s: float, icon: String, t: float) -> void:
	match icon:
		"elder":
			ci.draw_line(c + Vector2(0, 0.1) * s, c + Vector2(0, 0.95) * s, Color(0.45, 0.3, 0.22), s * 0.28, true)
			ci.draw_line(c + Vector2(0, 0.5) * s, c + Vector2(-0.35, 0.95) * s, Color(0.45, 0.3, 0.22), s * 0.16, true)
			var lil := Color(0.66, 0.5, 0.92)
			ci.draw_circle(c + Vector2(-0.45, -0.05) * s, s * 0.42, lil.darkened(0.15))
			ci.draw_circle(c + Vector2(0.45, -0.05) * s, s * 0.42, lil.darkened(0.15))
			ci.draw_circle(c + Vector2(0, -0.35) * s, s * 0.55, lil)
			ci.draw_circle(c + Vector2(-0.18, -0.55) * s, s * 0.2, lil.lightened(0.35))
			_sparkle(ci, c + Vector2(0.62, -0.78) * s, s * (0.22 + 0.08 * sin(t * 3.0)), HudTheme.GOLD)
		"pond":
			var w := Color(0.3, 0.62, 0.8)
			ci.draw_arc(c + Vector2(0, 0.55) * s, s * 0.85, deg_to_rad(200), deg_to_rad(340), 16, w, s * 0.14, true)
			for k in 5:
				var a := deg_to_rad(-90.0 + (k - 2) * 34.0)
				var dir := Vector2(cos(a), sin(a))
				leaf(ci, c + Vector2(0, 0.3) * s, dir, s * (0.95 if k == 2 else 0.8), s * 0.38, HudTheme.BLOSSOM.darkened(0.08 if k % 2 == 0 else 0.0))
			ci.draw_circle(c + Vector2(0, 0.22) * s, s * 0.14, HudTheme.GOLD)
		"overlook":
			var wood := Color(0.48, 0.3, 0.2)
			ci.draw_line(c + Vector2(-0.7, 0.75) * s, c + Vector2(0.7, 0.45) * s, wood, s * 0.22, true)
			ci.draw_line(c + Vector2(0.7, 0.75) * s, c + Vector2(-0.7, 0.45) * s, wood, s * 0.22, true)
			var f := 1.0 + 0.08 * sin(t * 11.0) + 0.05 * sin(t * 17.0)
			flame(ci, c + Vector2(0, 0.45) * s, s * 1.15 * f, Color(1.0, 0.48, 0.2))
			flame(ci, c + Vector2(0, 0.45) * s, s * 0.7 * f, Color(1.0, 0.82, 0.3))
		"hollow":
			var glow := 0.5 + 0.5 * sin(t * 2.2)
			ci.draw_circle(c + Vector2(0, -0.15) * s, s * (0.95 + 0.1 * glow), Color(0.4, 1.0, 0.85, 0.16 + 0.1 * glow))
			ci.draw_rect(Rect2(c + Vector2(-0.2, -0.05) * s, Vector2(0.4, 0.9) * s), Color(0.96, 0.92, 0.8))
			var cap := PackedVector2Array()
			for k in 17:
				var a := PI + PI * k / 16.0
				cap.append(c + Vector2(cos(a) * 0.85, sin(a) * 0.75 - 0.05) * s)
			ci.draw_colored_polygon(cap, Color(0.25, 0.75, 0.68))
			ci.draw_circle(c + Vector2(-0.35, -0.38) * s, s * 0.12, Color(0.9, 1.0, 0.95))
			ci.draw_circle(c + Vector2(0.25, -0.55) * s, s * 0.1, Color(0.9, 1.0, 0.95))
			ci.draw_circle(c + Vector2(0.45, -0.2) * s, s * 0.08, Color(0.9, 1.0, 0.95))
		"grove":
			for k in 5:
				var a := TAU * k / 5.0 - PI * 0.5 + t * 0.15
				leaf(ci, c, Vector2(cos(a), sin(a)), s * 0.95, s * 0.62, HudTheme.BLOSSOM)
			ci.draw_circle(c, s * 0.24, HudTheme.GOLD)
		"snag":
			var g := Color(0.55, 0.55, 0.58)
			ci.draw_line(c + Vector2(0, 0.95) * s, c + Vector2(0, -0.2) * s, g, s * 0.24, true)
			ci.draw_line(c + Vector2(0, 0.1) * s, c + Vector2(-0.6, -0.6) * s, g, s * 0.16, true)
			ci.draw_line(c + Vector2(0, -0.1) * s, c + Vector2(0.55, -0.8) * s, g, s * 0.16, true)
			ci.draw_line(c + Vector2(0.3, -0.45) * s, c + Vector2(0.75, -0.35) * s, g, s * 0.1, true)
		"stones":
			ci.draw_arc(c + Vector2(0, 1.05) * s, s * 1.1, deg_to_rad(235), deg_to_rad(305), 12, Color(0.3, 0.62, 0.8), s * 0.16, true)
			for k in 3:
				_ellipse(ci, c + Vector2(-0.55 + k * 0.55, 0.15 - (k % 2) * 0.3) * s, Vector2(0.3, 0.22) * s, Color(0.5, 0.52, 0.5))
				_ellipse(ci, c + Vector2(-0.6 + k * 0.55, 0.08 - (k % 2) * 0.3) * s, Vector2(0.16, 0.1) * s, Color(0.75, 0.76, 0.72))
		"falls":
			var w := Color(0.3, 0.62, 0.85)
			for k in 3:
				var x := (k - 1) * 0.42
				var pts := PackedVector2Array()
				for j in 7:
					var y := -0.8 + j * 0.25
					pts.append(c + Vector2(x + sin(y * 5.0 + t * 6.0 + k) * 0.07, y) * s)
				ci.draw_polyline(pts, w, s * 0.17, true)
			_ellipse(ci, c + Vector2(0, 0.85) * s, Vector2(0.75, 0.18) * s, Color(0.85, 0.95, 1.0))
		"bench":
			# A little garden bench with a glowing emblem on its back.
			var wood := Color(0.62, 0.38, 0.22)
			ci.draw_line(c + Vector2(-0.8, 0.2) * s, c + Vector2(0.8, 0.2) * s, wood, s * 0.24, true)
			ci.draw_line(c + Vector2(-0.72, -0.5) * s, c + Vector2(0.72, -0.5) * s, wood, s * 0.2, true)
			for x in [-0.62, 0.62]:
				ci.draw_line(c + Vector2(x, -0.62) * s, c + Vector2(x, 0.85) * s, wood.darkened(0.25), s * 0.16, true)
			ci.draw_circle(c + Vector2(0, -0.5) * s, s * (0.2 + 0.04 * sin(t * 2.5)), HudTheme.GOLD)
		"trailhead":
			var g := Color(0.35, 0.65, 0.3)
			ci.draw_line(c + Vector2(0, 0.9) * s, c + Vector2(0, -0.1) * s, g.darkened(0.2), s * 0.18, true)
			leaf(ci, c + Vector2(0, 0.05) * s, Vector2(-0.8, -0.6).normalized(), s * 0.85, s * 0.5, g)
			leaf(ci, c + Vector2(0, -0.1) * s, Vector2(0.75, -0.66).normalized(), s * 0.95, s * 0.55, g.lightened(0.15))
		"glade":
			var sun := Color(1.0, 0.75, 0.25)
			for k in 8:
				var a := TAU * k / 8.0 + t * 0.2
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(c + d * s * 0.62, c + d * s * 0.92, sun, s * 0.15, true)
			ci.draw_circle(c, s * 0.48, sun)
			ci.draw_circle(c + Vector2(-0.12, -0.12) * s, s * 0.22, Color(1.0, 0.9, 0.6))
		_:
			ci.draw_circle(c, s * 0.4, INK)


## A small Keling marker: soft halo, a rounded arrowhead in the player's
## colour, ink outline. `angle` is the screen heading (0 = up, clockwise).
static func player(ci: CanvasItem, c: Vector2, angle: float, col: Color, size: float, t: float, local := true) -> void:
	var pulse := 0.5 + 0.5 * sin(t * 3.0)
	if local:
		ci.draw_circle(c, size * (1.75 + 0.25 * pulse), Color(col, 0.18 + 0.08 * pulse))
	var pts := PackedVector2Array([Vector2(0, -1.3), Vector2(0.95, 0.85), Vector2(0, 0.42), Vector2(-0.95, 0.85)])
	var outline := PackedVector2Array()
	for p in pts:
		outline.append(c + (p * size).rotated(angle))
	var shadow := PackedVector2Array()
	for p in outline:
		shadow.append(p + Vector2(0, size * 0.22))
	ci.draw_colored_polygon(shadow, Color(0, 0, 0, 0.3))
	ci.draw_colored_polygon(outline, col)
	outline.append(outline[0])
	ci.draw_polyline(outline, INK, maxf(size * 0.22, 1.5), true)
	ci.draw_circle(c + (Vector2(0, -0.15) * size).rotated(angle), size * 0.2, Color(1, 1, 1, 0.85))


## Waypoint: a golden star on a stalk with a soft pulsing ground ring.
static func pin(ci: CanvasItem, c: Vector2, size: float, t: float) -> void:
	var bob := sin(t * 3.0) * size * 0.12
	var ring := fmod(t * 0.8, 1.0)
	ci.draw_arc(c, size * (0.4 + ring * 1.2), 0.0, TAU, 32, Color(HudTheme.GOLD, 0.6 * (1.0 - ring)), maxf(size * 0.12, 1.5), true)
	_ellipse(ci, c, Vector2(0.45, 0.2) * size, Color(0, 0, 0, 0.3))
	var top := c + Vector2(0, -size * 1.25 + bob)
	ci.draw_line(c, top, INK, maxf(size * 0.16, 1.5), true)
	star(ci, top, size * 0.62, HudTheme.GOLD, INK)


static func star(ci: CanvasItem, c: Vector2, r: float, fill: Color, edge: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI * 0.5 + PI * k / 5.0
		var rr := r if k % 2 == 0 else r * 0.48
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	ci.draw_polyline(pts, edge, maxf(r * 0.16, 1.2), true)


## A pointed leaf / petal from `base` along `dir`.
static func leaf(ci: CanvasItem, base: Vector2, dir: Vector2, length: float, width: float, col: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array()
	for k in 9:
		var u := k / 8.0
		pts.append(base + dir * length * u + side * width * 0.5 * sin(u * PI) * (1.0 - u * 0.25))
	for k in range(7, 0, -1):
		var u := k / 8.0
		pts.append(base + dir * length * u - side * width * 0.5 * sin(u * PI) * (1.0 - u * 0.25))
	ci.draw_colored_polygon(pts, col)


static func flame(ci: CanvasItem, base: Vector2, h: float, col: Color) -> void:
	# Teardrop: a round belly sitting on `base`, tapering to a tip above it.
	var r := h * 0.34
	var mid := base - Vector2(0, r)
	var pts := PackedVector2Array()
	for k in 13:
		var a := PI * k / 12.0
		pts.append(mid + Vector2(cos(a), sin(a)) * r)
	pts.append(base + Vector2(-r * 0.55, -h * 0.62))
	pts.append(base + Vector2(0, -h))
	pts.append(base + Vector2(r * 0.55, -h * 0.62))
	ci.draw_colored_polygon(pts, col)


static func _sparkle(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 8:
		var a := PI * k / 4.0
		var rr := r if k % 2 == 0 else r * 0.3
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, col)


static func _ellipse(ci: CanvasItem, c: Vector2, radii: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 20:
		var a := TAU * k / 20.0
		pts.append(c + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	ci.draw_colored_polygon(pts, col)
