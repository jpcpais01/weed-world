class_name ProcTree
extends RefCounted
## Grows a one-of-a-kind tree from a seed: a curving trunk that forks into
## limbs, recursive branches that reach for the light (or weep towards the
## water), tapered bark tubes with proper tangents for normal mapping, and leaf
## clusters on every twig. Same seed, same tree, on every client.

enum Style { BLOSSOM, WILLOW, SENTINEL, FAR }

const GOLDEN_ANGLE := 2.39996

var rng := RandomNumberGenerator.new()
var style: Style
var cfg := {}

var _bv := PackedVector3Array()
var _bn := PackedVector3Array()
var _bt := PackedFloat32Array()
var _buv := PackedVector2Array()
var _bc := PackedColorArray()
var _bi := PackedInt32Array()
var _lv := PackedVector3Array()
var _ln := PackedVector3Array()
var _luv := PackedVector2Array()
var _li := PackedInt32Array()
var _leaf_points := PackedVector3Array()


## Returns { mesh, canopy_center, canopy_radius, height, trunk_radius }.
## The mesh has two surfaces: 0 = bark, 1 = leaves (materials left empty).
static func grow(p_style: Style, seed: int) -> Dictionary:
	var t := ProcTree.new()
	t.style = p_style
	t.rng.seed = seed
	t.cfg = t._config()
	return t._build()


func _config() -> Dictionary:
	match style:
		Style.BLOSSOM:
			return {
				"height": rng.randf_range(4.2, 5.6), "trunk_r": rng.randf_range(0.26, 0.34),
				"depth": 3, "children": [3, 3, 3], "spread": [38.0, 42.0, 46.0],
				"ratio": [0.62, 0.62, 0.58], "tropism": [0.06, 0.08, 0.04], "wiggle": 0.22,
				"sides": [8, 6, 5, 4], "seg": 0.55, "leaf": 0.8, "leaves": 7, "split_at": 0.95,
				"weep": false, "trunk_lean": 0.18,
			}
		Style.WILLOW:
			return {
				"height": rng.randf_range(3.6, 4.4), "trunk_r": rng.randf_range(0.32, 0.4),
				"depth": 3, "children": [4, 3, 3], "spread": [48.0, 40.0, 30.0],
				"ratio": [0.7, 0.62, 0.55], "tropism": [0.14, -0.02, -0.5], "wiggle": 0.2,
				"sides": [8, 6, 4, 4], "seg": 0.5, "leaf": 0.75, "leaves": 2, "split_at": 0.9,
				"weep": true, "trunk_lean": 0.25,
			}
		Style.SENTINEL:
			return {
				"height": rng.randf_range(9.0, 12.0), "trunk_r": rng.randf_range(0.2, 0.26),
				"depth": 2, "children": [7, 3], "spread": [62.0, 40.0],
				"ratio": [0.32, 0.55], "tropism": [0.12, 0.2], "wiggle": 0.12,
				"sides": [7, 5, 4], "seg": 0.7, "leaf": 0.85, "leaves": 7, "split_at": 0.4,
				"weep": false, "trunk_lean": 0.08, "leader": true,
			}
		_:
			return {
				"height": rng.randf_range(7.0, 10.0), "trunk_r": rng.randf_range(0.28, 0.4),
				"depth": 2, "children": [4, 3], "spread": [36.0, 40.0],
				"ratio": [0.6, 0.6], "tropism": [0.12, 0.1], "wiggle": 0.15,
				"sides": [5, 4, 3], "seg": 1.2, "leaf": 2.2, "leaves": 5, "split_at": 0.55,
				"weep": false, "trunk_lean": 0.1,
			}


func _build() -> Dictionary:
	var lean_dir := rng.randf() * TAU
	var lean: float = cfg.trunk_lean
	var dir := Vector3(cos(lean_dir) * lean, 1.0, sin(lean_dir) * lean).normalized()
	var trunk_len: float = cfg.height * (cfg.split_at if not cfg.get("leader", false) else 1.0)
	_branch(Vector3(0.0, -0.3, 0.0), dir, trunk_len, cfg.trunk_r, 0)
	# Root flare: a few short, fat tubes diving into the soil.
	for k in 4:
		var a := k * TAU / 4.0 + rng.randf_range(-0.4, 0.4)
		var out := Vector3(cos(a), -0.5, sin(a)).normalized()
		var pts := [Vector3(0.0, 0.5, 0.0), Vector3(cos(a) * 0.35, 0.05, sin(a) * 0.35), Vector3(cos(a) * 0.65, -0.25, sin(a) * 0.65) + out * 0.1]
		_tube(pts, [cfg.trunk_r * 0.7, cfg.trunk_r * 0.45, cfg.trunk_r * 0.12], 5)

	var center := Vector3.ZERO
	for p in _leaf_points:
		center += p
	center /= maxf(_leaf_points.size(), 1.0)
	var radius := 0.5
	for p in _leaf_points:
		radius = maxf(radius, p.distance_to(center))

	var mesh := ArrayMesh.new()
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = _bv
	a[Mesh.ARRAY_NORMAL] = _bn
	a[Mesh.ARRAY_TANGENT] = _bt
	a[Mesh.ARRAY_TEX_UV] = _buv
	a[Mesh.ARRAY_COLOR] = _bc
	a[Mesh.ARRAY_INDEX] = _bi
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var l := []
	l.resize(Mesh.ARRAY_MAX)
	l[Mesh.ARRAY_VERTEX] = _lv
	l[Mesh.ARRAY_NORMAL] = _ln
	l[Mesh.ARRAY_TEX_UV] = _luv
	l[Mesh.ARRAY_INDEX] = _li
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, l)
	return {
		"mesh": mesh, "canopy_center": center, "canopy_radius": radius * 0.85,
		"height": center.y + radius, "trunk_radius": cfg.trunk_r,
	}


func _branch(pos: Vector3, dir: Vector3, length: float, radius: float, depth: int) -> void:
	var max_depth: int = cfg.depth
	var segs := maxi(2, int(ceil(length / cfg.seg)))
	var pts := [pos]
	var radii := [radius]
	var dirs := [dir]
	var cur := pos
	var d := dir
	var tip_r := radius * (0.62 if depth < max_depth else 0.25)
	var trop: float = cfg.tropism[mini(depth, cfg.tropism.size() - 1)]
	var wig: float = cfg.wiggle
	for s in segs:
		var t := float(s + 1) / segs
		var w := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.4, 0.4), rng.randf_range(-1.0, 1.0)) * wig
		var pull := trop
		if cfg.weep and depth >= 1:
			pull = lerpf(trop * 0.2, trop * 1.6, t)
		d = (d + w + Vector3.UP * pull).normalized()
		cur += d * (length / segs)
		pts.append(cur)
		radii.append(lerpf(radius, tip_r, t))
		dirs.append(d)
	var sides: Array = cfg.sides
	_tube(pts, radii, sides[mini(depth, sides.size() - 1)])

	if depth >= max_depth:
		_leaf_cluster(cur, d, cfg.leaves)
		if segs > 2:
			_leaf_cluster(pts[segs - 1], dirs[segs - 1], maxi(1, cfg.leaves / 2))
		return

	var n: int = cfg.children[depth]
	var spread: float = cfg.spread[depth]
	var ratio: float = cfg.ratio[depth]
	var phase := rng.randf() * TAU
	var leader: bool = cfg.get("leader", false) and depth == 0
	for c in n:
		var t: float
		if leader:
			t = lerpf(0.38, 0.95, (c + rng.randf_range(0.2, 0.8)) / n)
		else:
			t = lerpf(0.7, 1.0, (c + 0.5) / n) if n > 1 else 1.0
		var k := clampi(int(round(t * segs)), 1, segs)
		var base: Vector3 = pts[k]
		var pd: Vector3 = dirs[k]
		var ang := deg_to_rad(spread * rng.randf_range(0.75, 1.25))
		var around := phase + c * GOLDEN_ANGLE + rng.randf_range(-0.3, 0.3)
		var cd := _rotate_away(pd, ang, around)
		var clen := length * ratio * rng.randf_range(0.85, 1.15)
		if leader:
			# Whorled branches get shorter towards the crown tip.
			clen = cfg.height * ratio * lerpf(1.2, 0.45, t)
		var cr: float = radii[k] * rng.randf_range(0.55, 0.7)
		_branch(base - pd * 0.05, cd, clen, cr, depth + 1)
	if leader:
		_leaf_cluster(cur, d, cfg.leaves + 2)


func _rotate_away(d: Vector3, angle: float, around: float) -> Vector3:
	var ref := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	var a := d.cross(ref).normalized()
	var b := d.cross(a)
	var perp := a * cos(around) + b * sin(around)
	return (d * cos(angle) + perp * sin(angle)).normalized()


## Tapered tube along a polyline using parallel-transported frames.
func _tube(pts: Array, radii: Array, sides: int) -> void:
	var start := _bv.size()
	var count := pts.size()
	var t0: Vector3 = (pts[1] - pts[0]).normalized()
	var ref := Vector3.UP if absf(t0.y) < 0.95 else Vector3.RIGHT
	var normal := t0.cross(ref).normalized()
	var v := 0.0
	var wraps := maxf(1.0, round(TAU * float(radii[0]) / 0.9))
	for k in count:
		var p: Vector3 = pts[k]
		var tan: Vector3
		if k == 0:
			tan = (pts[1] - pts[0]).normalized()
		elif k == count - 1:
			tan = (pts[k] - pts[k - 1]).normalized()
		else:
			tan = (pts[k + 1] - pts[k - 1]).normalized()
		normal = (normal - tan * normal.dot(tan)).normalized()
		var bin := tan.cross(normal)
		if k > 0:
			v += p.distance_to(pts[k - 1]) / 1.6
		var r: float = radii[k]
		var ao := clampf(0.45 + p.y * 0.35, 0.45, 1.0)
		for s in sides + 1:
			var a := TAU * s / sides
			var off := normal * cos(a) + bin * sin(a)
			_bv.append(p + off * r)
			_bn.append(off)
			var tg := -normal * sin(a) + bin * cos(a)
			_bt.append_array([tg.x, tg.y, tg.z, 1.0])
			_buv.append(Vector2(float(s) / sides * wraps, v))
			_bc.append(Color(ao, ao, ao))
	var ring := sides + 1
	for k in count - 1:
		for s in sides:
			var i0 := start + k * ring + s
			var i1 := i0 + ring
			_bi.append_array([i0, i1, i0 + 1, i0 + 1, i1, i1 + 1])


func _leaf_cluster(pos: Vector3, dir: Vector3, count: int) -> void:
	var size: float = cfg.leaf
	if cfg.weep:
		_weeping_strand(pos, size)
		_weeping_strand(pos + Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3)), size * 0.8)
		return
	for i in count:
		var c := pos + dir * size * 0.25 + _rand_in_sphere() * size * 0.55
		var s := size * rng.randf_range(0.8, 1.25)
		var n := (dir * 0.6 + _rand_in_sphere() + Vector3.UP * 0.5).normalized()
		_card(c, n, s, s, rng.randf() * TAU)
		_leaf_points.append(c)


## Curtains of leaves hanging from willow twigs, stacked cards that twist a
## little as they fall.
func _weeping_strand(top: Vector3, size: float) -> void:
	var drops := rng.randi_range(3, 5)
	var p := top
	var yaw := rng.randf() * TAU
	for k in drops:
		var s := size * lerpf(1.0, 0.7, float(k) / drops)
		p += Vector3(rng.randf_range(-0.15, 0.15), -s * 0.55, rng.randf_range(-0.15, 0.15))
		if p.y < 0.6:
			break
		yaw += rng.randf_range(0.6, 1.2)
		var n := Vector3(cos(yaw), 0.15, sin(yaw)).normalized()
		_card(p, n, s * 0.8, s * 1.1, rng.randf_range(-0.2, 0.2))
		_card(p, n.rotated(Vector3.UP, PI * 0.5), s * 0.8, s * 1.1, rng.randf_range(-0.2, 0.2))
		_leaf_points.append(p)


func _card(c: Vector3, n: Vector3, w: float, h: float, roll: float) -> void:
	var ref := Vector3.UP if absf(n.y) < 0.9 else Vector3.FORWARD
	var right := ref.cross(n).normalized().rotated(n, roll)
	var up := n.cross(right).normalized()
	var start := _lv.size()
	var corners := [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
	for k in 4:
		var q: Vector2 = corners[k]
		_lv.append(c + right * q.x * w + up * q.y * h)
		_ln.append(n)
		_luv.append(Vector2(q.x + 0.5, 0.5 - q.y))
	_li.append_array([start, start + 1, start + 2, start, start + 2, start + 3])


func _rand_in_sphere() -> Vector3:
	while true:
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if v.length_squared() <= 1.0:
			return v
	return Vector3.ZERO
