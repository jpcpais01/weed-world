class_name UpdateSprout
extends Control
## The update badge: a seedling pushing up out of a little mound of soil with
## a golden sparkle above it, on a round glass face. It sways while idle,
## wraps a growing ring round itself while a download runs, and swaps the
## sparkle for a tick when it is done.

## 0..1 ring progress, or < 0 for no ring.
var ring := -1.0
## Spins a short arc instead of a ring while waiting on something unmeasured.
var busy := false
var done := false
var _t := 0.0
var _shown_ring := 0.0


func _init(diameter := 48.0) -> void:
	custom_minimum_size = Vector2.ONE * diameter
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	if ring >= 0.0:
		_shown_ring = move_toward(_shown_ring, ring, delta * maxf(0.4, absf(ring - _shown_ring) * 4.0))
	else:
		_shown_ring = 0.0
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	draw_circle(c + Vector2(0, r * 0.06), r, Color(0, 0, 0, 0.22))
	draw_circle(c, r, Color(0.13, 0.24, 0.12, 0.95))
	draw_circle(c - Vector2(0, r * 0.08), r * 0.9, Color(0.2, 0.36, 0.17))
	draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(HudTheme.CREAM, 0.3), maxf(1.5, r * 0.05), true)

	# Soil mound.
	var base := c + Vector2(0, r * 0.52)
	var mound := PackedVector2Array()
	for k in 13:
		var u := float(k) / 12.0
		mound.append(base + Vector2(lerpf(-r * 0.52, r * 0.52, u), -sin(u * PI) * r * 0.2))
	draw_colored_polygon(mound, Color(0.42, 0.28, 0.16))
	draw_polyline(mound, Color(0.6, 0.42, 0.24), maxf(1.2, r * 0.05), true)

	# Stem and two leaves, swaying (and growing a touch with the ring).
	var grow := 0.85 + 0.15 * clampf(_shown_ring, 0.0, 1.0)
	var sway := sin(_t * 1.8) * 0.12
	var top := base + Vector2(sin(sway) * r * 0.3, -r * 0.82 * grow)
	var mid := base.lerp(top, 0.5) + Vector2(-r * 0.06, 0)
	var stem := PackedVector2Array()
	for k in 9:
		var u := float(k) / 8.0
		stem.append(base.lerp(mid, u).lerp(mid.lerp(top, u), u) + Vector2(0, -r * 0.12))
	draw_polyline(stem, Color(0.5, 0.78, 0.3), maxf(2.0, r * 0.11), true)
	var leaf_at := stem[6]
	_leaf(leaf_at, Vector2.from_angle(-PI * 0.82 + sway), r * 0.5 * grow, HudTheme.LEAF.darkened(0.12))
	_leaf(leaf_at, Vector2.from_angle(-PI * 0.18 + sway), r * 0.56 * grow, HudTheme.LEAF)

	# Sparkle (or tick) above.
	var sp := c + Vector2(r * 0.42, -r * 0.5)
	if done:
		var pts := PackedVector2Array([sp + Vector2(-0.16, 0.0) * r, sp + Vector2(-0.04, 0.13) * r, sp + Vector2(0.2, -0.16) * r])
		draw_polyline(pts, HudTheme.GOLD, maxf(2.0, r * 0.1), true)
	else:
		var tw := 0.75 + 0.25 * sin(_t * 3.4)
		_sparkle(sp, r * 0.22 * tw, HudTheme.GOLD)
		_sparkle(sp + Vector2(-r * 0.75, r * 0.12), r * 0.09 * (1.6 - tw), Color(HudTheme.CREAM, 0.8))

	# Progress ring or busy arc.
	var w := maxf(2.5, r * 0.12)
	if ring >= 0.0:
		draw_arc(c, r + w * 0.2, 0.0, TAU, 64, Color(0, 0, 0, 0.3), w, true)
		if _shown_ring > 0.001:
			draw_arc(c, r + w * 0.2, -PI * 0.5, -PI * 0.5 + TAU * _shown_ring, 64, HudTheme.GOLD, w, true)
	elif busy:
		var a := _t * 4.0
		draw_arc(c, r + w * 0.2, a, a + PI * 0.6, 24, HudTheme.GOLD, w, true)


func _leaf(at: Vector2, dir: Vector2, length: float, col: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	var poly := PackedVector2Array()
	for k in 11:
		var u := float(k) / 10.0
		poly.append(at + dir * length * u + side * sin(u * PI) * length * 0.34)
	for k in range(9, 0, -1):
		var u := float(k) / 10.0
		poly.append(at + dir * length * u - side * sin(u * PI) * length * 0.34)
	draw_colored_polygon(poly, col)
	draw_line(at, at + dir * length * 0.85, col.lightened(0.35), maxf(1.0, length * 0.06), true)


func _sparkle(p: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 8:
		var a := TAU * k / 8.0 - PI * 0.5
		pts.append(p + Vector2.from_angle(a) * (s if k % 2 == 0 else s * 0.32))
	draw_colored_polygon(pts, col)
