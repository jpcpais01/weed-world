class_name VineProgress
extends Control
## The loading bar: a vine that grows across the screen, unfurling leaves and
## popping buttercups as it goes, with a firefly lighting its tip. Drawn by
## hand each frame (no shaders), so it costs nothing to warm up and keeps
## animating while the forest grows on a worker thread.

## 0..1, how far the vine has grown. Set it freely; the drawing eases towards it.
var value := 0.0
## How far the vine swings up and down, as a fraction of the control's height.
var wave := 0.22

const LEAVES := 22
const STEM_DARK := Color(0.16, 0.36, 0.13)
const STEM_LIGHT := Color(0.55, 0.82, 0.30)
const LEAF_A := Color(0.36, 0.66, 0.22)
const LEAF_B := Color(0.66, 0.90, 0.36)
const BUD := Color(1.0, 0.86, 0.28)
const GLOW := Color(1.0, 0.9, 0.55)

var _shown := 0.0
var _time := 0.0
var _born: PackedFloat32Array = []
var _glow_tex: Texture2D
var _sparks: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_born.resize(LEAVES)
	_born.fill(-1.0)
	_glow_tex = make_glow_texture()


static func make_glow_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _process(delta: float) -> void:
	_time += delta
	# Ease towards the target but never jump: the vine always grows smoothly.
	var target := clampf(value, 0.0, 1.0)
	if target > _shown:
		_shown = minf(target, _shown + maxf((target - _shown) * delta * 3.0, delta * 0.04))
	for i in LEAVES:
		if _born[i] < 0.0 and _shown >= _leaf_t(i):
			_born[i] = _time
	# Sparks shed by the firefly at the tip.
	if _shown > 0.001 and randf() < delta * 14.0:
		var tip := _point(_shown)
		_sparks.append({"p": tip, "v": Vector2(randf_range(-14, 6), randf_range(-26, -6)), "life": 0.0, "max": randf_range(0.6, 1.2)})
	for s in _sparks:
		s.life += delta
		s.p += s.v * delta
		s.v.y += 10.0 * delta
	_sparks = _sparks.filter(func(s): return s.life < s.max)
	queue_redraw()


## How far the vine has visibly grown, 0..1 (eases behind `value`).
func grown() -> float:
	return _shown


## Where along the vine a point at t (0..1) is, in this control's space.
func point_at(t: float) -> Vector2:
	return _point(t)


func _leaf_t(i: int) -> float:
	return (float(i) + 0.6) / float(LEAVES)


## A point along the vine at t in 0..1: a lazy wave that sways a touch.
func _point(t: float) -> Vector2:
	var w := size.x
	var h := size.y
	var x := t * w
	var y := h * 0.5 + sin(t * TAU * 1.5 + 0.6) * h * wave + sin(_time * 1.3 + t * 5.0) * h * 0.03
	return Vector2(x, y)


func _tangent(t: float) -> Vector2:
	return (_point(minf(t + 0.004, 1.0)) - _point(maxf(t - 0.004, 0.0))).normalized()


func _draw() -> void:
	var h := size.y
	# The path still to grow: a faint trail of dots.
	var n := 60
	for k in n + 1:
		var t := float(k) / n
		if t > _shown:
			draw_circle(_point(t), 1.6, Color(1, 1, 1, 0.16))

	if _shown <= 0.0005:
		_draw_tip(_point(0.0))
		return

	# Stem: a dark under-stroke and a bright top stroke, thickening with age.
	var pts := PackedVector2Array()
	var steps := maxi(2, int(_shown * 90.0))
	for k in steps + 1:
		pts.append(_point(_shown * float(k) / steps))
	draw_polyline(pts, STEM_DARK, h * 0.085, true)
	draw_polyline(pts, STEM_LIGHT.darkened(0.15), h * 0.05, true)
	var hi := PackedVector2Array()
	for p in pts:
		hi.append(p + Vector2(0, -h * 0.012))
	draw_polyline(hi, Color(STEM_LIGHT, 0.55), h * 0.018, true)

	# Leaves (and every fourth, a buttercup) pop out with a springy overshoot.
	for i in LEAVES:
		if _born[i] < 0.0:
			continue
		var age := _time - _born[i]
		var s := _spring(clampf(age / 0.55, 0.0, 1.0))
		var t := _leaf_t(i)
		var p := _point(t)
		var tan := _tangent(t)
		var nrm := Vector2(-tan.y, tan.x) * (1.0 if i % 2 == 0 else -1.0)
		var sway := sin(_time * 2.1 + i * 1.7) * 0.18
		var dir := nrm.rotated(sway + (0.5 if i % 2 == 0 else -0.5))
		if i % 4 == 3:
			_draw_bud(p + dir * h * 0.32 * s, h * 0.2 * s, i)
			draw_line(p, p + dir * h * 0.3 * s, STEM_LIGHT.darkened(0.1), h * 0.025, true)
		else:
			_draw_leaf(p, dir, h * 0.42 * s, i)

	for sp in _sparks:
		var a: float = 1.0 - sp.life / sp.max
		draw_texture_rect(_glow_tex, Rect2(sp.p - Vector2.ONE * 5, Vector2.ONE * 10), false, Color(GLOW, a * 0.9))
	_draw_tip(_point(_shown))


func _draw_leaf(base: Vector2, dir: Vector2, length: float, i: int) -> void:
	if length < 1.0:
		return
	var side := Vector2(-dir.y, dir.x)
	var tip := base + dir * length
	var poly := PackedVector2Array()
	var steps := 10
	for k in steps + 1:
		var u := float(k) / steps
		poly.append(base + dir * length * u + side * sin(u * PI) * length * 0.32)
	for k in range(steps - 1, 0, -1):
		var u := float(k) / steps
		poly.append(base + dir * length * u - side * sin(u * PI) * length * 0.32)
	var c := LEAF_A.lerp(LEAF_B, 0.5 + 0.5 * sin(i * 2.3))
	draw_colored_polygon(poly, c)
	draw_line(base, tip, c.lightened(0.3), maxf(1.0, length * 0.05), true)


func _draw_bud(center: Vector2, r: float, i: int) -> void:
	if r < 0.5:
		return
	var spin := _time * 0.4 + i
	for k in 5:
		var a := spin + TAU * k / 5.0
		draw_circle(center + Vector2.from_angle(a) * r * 0.55, r * 0.5, BUD)
	draw_circle(center, r * 0.38, Color(1.0, 0.7, 0.15))
	draw_texture_rect(_glow_tex, Rect2(center - Vector2.ONE * r * 2.2, Vector2.ONE * r * 4.4), false, Color(BUD, 0.25))


func _draw_tip(p: Vector2) -> void:
	var h := size.y
	var pulse := 0.75 + 0.25 * sin(_time * 5.0)
	var r := h * 0.95 * pulse
	draw_texture_rect(_glow_tex, Rect2(p - Vector2.ONE * r, Vector2.ONE * r * 2.0), false, Color(GLOW, 0.55))
	draw_texture_rect(_glow_tex, Rect2(p - Vector2.ONE * r * 0.35, Vector2.ONE * r * 0.7), false, Color(1, 1, 0.9, 1))


## Overshooting ease-out for the leaves' pop.
static func _spring(x: float) -> float:
	if x >= 1.0:
		return 1.0
	return 1.0 - exp(-6.0 * x) * cos(x * 9.0)
