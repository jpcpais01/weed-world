class_name GiantFlora
extends RefCounted
## The giant flora Bloom Burst raises, built here from nothing but code.
## Every mesh carries a little rig in its vertices (see giant_flora.gdshader)
## so a single shader grows it out of the ground, unfurls its petals, opens
## its cap or unrolls its fronds, sways it and finally wilts it.
##
##   glowcap    a titan mushroom: a bulb-footed stem with a skirt, a broad
##              spotted dome, glowing gills underneath (bouncy!)
##   springcap  a squat little one, knee high: the first step up
##   starlily   a nodding star lily on a tall stem, six long curling petals,
##              glowing stamens, two sword leaves at its foot
##   bellvine   a crook-necked stalk hung with lantern bells that glow inside
##   fern       a ring of fronds that unroll like fiddleheads, pinnae opening
##   lotus      a water lotus three layers deep with a glowing heart, on
##              giant floating pads (you can stand on them)
##   puffball   a dandelion clock as tall as a tree, seeds tipped with light
##
## Meshes are built once per kind and variant and shared; each plant is one
## MeshInstance3D with its own colours and growth in instance uniforms.

const KINDS: Array[StringName] = [&"glowcap", &"springcap", &"starlily", &"bellvine", &"fern", &"lotus", &"puffball"]
const VARIANTS := 2

## Colour sets per kind: [col_a, col_b, glow, stem].
const PALETTES := {
	&"glowcap": [
		[Color(0.86, 0.22, 0.62), Color(1.0, 0.62, 0.9), Color(0.35, 1.0, 0.95), Color(0.9, 0.88, 0.8)],
		[Color(0.12, 0.55, 0.68), Color(0.6, 1.0, 0.85), Color(1.0, 0.82, 0.3), Color(0.86, 0.9, 0.84)],
		[Color(0.95, 0.36, 0.14), Color(1.0, 0.78, 0.55), Color(1.0, 0.95, 0.6), Color(0.94, 0.88, 0.78)],
		[Color(0.42, 0.24, 0.9), Color(0.65, 0.75, 1.0), Color(1.0, 0.5, 0.85), Color(0.86, 0.84, 0.92)],
	],
	&"starlily": [
		[Color(1.0, 0.97, 0.95), Color(1.0, 0.45, 0.7), Color(1.0, 0.8, 0.3), Color(0.5, 0.75, 0.4)],
		[Color(1.0, 0.82, 0.25), Color(1.0, 0.42, 0.15), Color(1.0, 0.35, 0.2), Color(0.45, 0.72, 0.35)],
		[Color(0.75, 0.92, 1.0), Color(0.6, 0.4, 1.0), Color(0.4, 1.0, 1.0), Color(0.45, 0.7, 0.55)],
		[Color(0.85, 1.0, 0.6), Color(1.0, 1.0, 0.95), Color(0.8, 0.45, 1.0), Color(0.45, 0.75, 0.35)],
	],
	&"bellvine": [
		[Color(0.55, 0.12, 0.35), Color(0.95, 0.4, 0.55), Color(1.0, 0.75, 0.3), Color(0.4, 0.55, 0.3)],
		[Color(0.2, 0.3, 0.85), Color(0.55, 0.75, 1.0), Color(0.45, 1.0, 1.0), Color(0.38, 0.55, 0.38)],
		[Color(0.95, 0.5, 0.75), Color(1.0, 0.85, 0.9), Color(1.0, 0.9, 0.55), Color(0.42, 0.6, 0.32)],
	],
	&"fern": [
		[Color(0.2, 0.6, 0.25), Color(0.65, 1.0, 0.4), Color(0.75, 1.0, 0.35), Color(0.45, 0.62, 0.32)],
		[Color(0.12, 0.5, 0.55), Color(0.5, 0.95, 1.0), Color(0.4, 0.95, 1.0), Color(0.35, 0.6, 0.55)],
		[Color(0.5, 0.25, 0.45), Color(1.0, 0.55, 0.75), Color(1.0, 0.45, 0.8), Color(0.55, 0.45, 0.4)],
	],
	&"lotus": [
		[Color(1.0, 0.95, 0.97), Color(1.0, 0.5, 0.75), Color(1.0, 0.85, 0.35), Color(0.4, 0.7, 0.35)],
		[Color(0.8, 0.9, 1.0), Color(1.0, 1.0, 1.0), Color(0.45, 1.0, 1.0), Color(0.35, 0.65, 0.45)],
		[Color(0.65, 0.4, 0.95), Color(1.0, 0.6, 0.8), Color(1.0, 0.5, 0.9), Color(0.38, 0.62, 0.4)],
	],
	&"puffball": [
		[Color(0.98, 0.98, 0.95), Color(1.0, 1.0, 1.0), Color(1.0, 0.85, 0.4), Color(0.5, 0.72, 0.38)],
		[Color(0.95, 0.97, 1.0), Color(0.85, 0.95, 1.0), Color(0.45, 0.95, 1.0), Color(0.45, 0.68, 0.45)],
		[Color(1.0, 0.95, 0.98), Color(1.0, 0.9, 0.97), Color(1.0, 0.5, 0.85), Color(0.5, 0.7, 0.4)],
	],
}

const Z_STEM := 0.0
const Z_CAP := 0.2
const Z_GILL := 0.4
const Z_PETAL := 0.6
const Z_GLOW := 0.8
const Z_LEAF := 1.0

static var _cache := {}
static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://player/powers/giant_flora.gdshader")
	return _material


static func palette(kind: StringName, pick: int) -> Array:
	var sets: Array = PALETTES.get(kind, PALETTES[&"glowcap"]) if kind != &"springcap" else PALETTES[&"glowcap"]
	return sets[pick % sets.size()]


## {mesh, info} for a kind and variant (built on first use, then shared).
## info: height, and per kind cap_r / cap_top / cap_h / stem_r (caps),
## pads [[centre, radius]] (lotus), light (a point to hang a light at).
static func get_flora(kind: StringName, variant: int) -> Dictionary:
	var key := "%s_%d" % [kind, variant % VARIANTS]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var b := Builder.new()
	var info := {}
	match kind:
		&"glowcap":
			info = _mushroom(b, rng, 3.0, 1.75, 0.17, true)
		&"springcap":
			info = _mushroom(b, rng, 0.42, 0.52, 0.12, false)
		&"starlily":
			info = _starlily(b, rng)
		&"bellvine":
			info = _bellvine(b, rng)
		&"fern":
			info = _fern(b, rng)
		&"lotus":
			info = _lotus(b, rng)
		_:
			info = _puffball(b, rng)
	var out := {"mesh": b.commit(), "info": info}
	_cache[key] = out
	return out


# ---------------------------------------------------------------------------
# Kinds

static func _mushroom(b: Builder, rng: RandomNumberGenerator, h: float, r: float, rs: float, skirt: bool) -> Dictionary:
	var bend := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * h * rng.randf_range(0.04, 0.1)
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var n := 11
	for i in n:
		var t := float(i) / (n - 1)
		path.append(Vector3(0, h * t, 0) + bend * sin(t * PI * 0.9))
		radii.append(rs * (1.0 + 0.75 * exp(-t * 7.0)) * (1.0 - 0.22 * t))
	b.tube(path, radii, 14, Z_STEM, 0.0, 0.25, h)
	var top := path[n - 1]
	if skirt:
		var at := path[int(n * 0.72)]
		var sr := rs * 0.95
		var prof: Array[Vector2] = [Vector2(sr, 0.02), Vector2(sr * 1.6, -0.06), Vector2(sr * 2.2, -0.2), Vector2(sr * 2.45, -0.34)]
		b.lathe(at, prof, 18, Z_GILL, 0.3, 0.2, h, at, -0.6)
	var ch := r * 0.5
	var top_prof: Array[Vector2] = [Vector2(0.0, ch), Vector2(r * 0.3, ch * 0.95), Vector2(r * 0.58, ch * 0.75),
		Vector2(r * 0.8, ch * 0.42), Vector2(r * 0.95, ch * 0.1), Vector2(r * 1.02, -r * 0.05)]
	var under_prof: Array[Vector2] = [Vector2(r * 1.02, -r * 0.05), Vector2(r * 0.93, -r * 0.1), Vector2(r * 0.7, -r * 0.075),
		Vector2(r * 0.42, -r * 0.04), Vector2(rs * 1.1, -r * 0.02)]
	b.lathe(top, top_prof, 28, Z_CAP, 0.22, 0.3, h, top, -1.2, r)
	b.lathe(top, under_prof, 28, Z_GILL, 0.22, 0.3, h, top, -1.2, r, true)
	return {"height": h, "cap_r": r * 1.02, "cap_top": top.y + ch, "cap_h": ch, "cap_center": top, "stem_r": rs * 1.5,
		"light": top + Vector3(0, -r * 0.15, 0), "glows": true}


static func _starlily(b: Builder, rng: RandomNumberGenerator) -> Dictionary:
	var h := 4.0
	var nod := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var n := 16
	for i in n:
		var t := float(i) / (n - 1)
		path.append(Vector3(0, h * t, 0) + nod * (0.35 * t * t + 0.45 * pow(t, 6.0)))
		radii.append(0.075 * (1.0 - 0.35 * t) + 0.02 * exp(-t * 9.0))
	b.tube(path, radii, 8, Z_STEM, 0.0, 0.9, h)
	# Two sword leaves at the foot.
	for k in 2:
		var a := rng.randf() * TAU if k == 0 else 0.0
		if k == 1:
			a = atan2(nod.z, nod.x) + PI + rng.randf_range(-0.5, 0.5)
		var d := Vector3(cos(a), 0, sin(a))
		_leaf(b, Vector3(0, 0.05, 0), d, 1.7, 0.3, 70.0, 20.0, 0.08, h)
	# The flower, facing along the end of the stem.
	var c := path[n - 1]
	var up := (path[n - 1] - path[n - 3]).normalized()
	var right := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var fwd := right.cross(up).normalized()
	for layer in 2:
		var count := 3
		for i in count:
			var a := TAU * (float(i) + 0.5 * layer) / count + rng.randf_range(-0.08, 0.08)
			var dir_h := (right * cos(a) + fwd * sin(a)).normalized()
			var length := 1.35 if layer == 0 else 1.15
			b.petal(c, up, dir_h, length, 0.36 if layer == 0 else 0.3, 58.0, -32.0, 0.12, Z_PETAL, 0.45 + 0.08 * layer, 0.15, h, 1.25)
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		var dir_h := (right * cos(a) + fwd * sin(a)).normalized()
		var fil := PackedVector3Array()
		var fr := PackedFloat32Array()
		for s in 5:
			var t := float(s) / 4.0
			fil.append(c + up * (0.62 * t) + dir_h * (0.22 * t * t))
			fr.append(0.012)
		b.tube(fil, fr, 4, Z_GLOW, 0.6, 0.15, h, c)
		b.ball(fil[4], 0.045, Z_GLOW, 0.65, c)
	b.ball(c + up * 0.12, 0.09, Z_GLOW, 0.5, c)
	return {"height": h + 0.6, "light": c + up * 0.3, "glows": true, "flower": c}


static func _bellvine(b: Builder, rng: RandomNumberGenerator) -> Dictionary:
	var ctrl := PackedVector3Array([Vector3(0, 0, 0), Vector3(0.05, 0.9, 0), Vector3(0.12, 1.8, 0), Vector3(0.28, 2.6, 0),
		Vector3(0.5, 3.15, 0), Vector3(0.85, 3.45, 0), Vector3(1.25, 3.42, 0), Vector3(1.6, 3.2, 0), Vector3(1.85, 2.85, 0)])
	var path := _catmull(ctrl, 4)
	var radii := PackedFloat32Array()
	for i in path.size():
		var t := float(i) / (path.size() - 1)
		radii.append(0.1 * (1.0 - 0.62 * t) + 0.03 * exp(-t * 10.0))
	b.tube(path, radii, 8, Z_STEM, 0.0, 0.7, 3.5)
	for k in 2:
		_leaf(b, Vector3(0, 0.05, 0), Vector3(cos(k * 2.6 + 0.6), 0, sin(k * 2.6 + 0.6)), 1.3, 0.34, 60.0, 15.0, 0.06, 3.5)
	var bells := 5
	var light := Vector3.ZERO
	for k in bells:
		var t := 0.5 + 0.48 * float(k) / (bells - 1)
		var at := path[int(t * (path.size() - 1))]
		var drop := rng.randf_range(0.18, 0.45)
		var stem := PackedVector3Array([at, at + Vector3(0.05, -drop * 0.5, 0.04), at + Vector3(0.06, -drop, 0.05)])
		b.tube(stem, PackedFloat32Array([0.018, 0.014, 0.012]), 4, Z_STEM, 0.3 + 0.08 * k, 1.2, 3.5, at)
		var top := stem[2]
		var s := rng.randf_range(0.85, 1.15)
		var outer: Array[Vector2] = [Vector2(0.03, 0.0), Vector2(0.17, -0.05), Vector2(0.23, -0.2), Vector2(0.25, -0.38), Vector2(0.34, -0.5), Vector2(0.38, -0.47)]
		var inner: Array[Vector2] = [Vector2(0.36, -0.47), Vector2(0.31, -0.48), Vector2(0.22, -0.36), Vector2(0.2, -0.2), Vector2(0.14, -0.07), Vector2(0.02, -0.03)]
		for i in outer.size():
			outer[i] *= s
			inner[i] *= s
		b.lathe(top, outer, 16, Z_PETAL, 0.35 + 0.08 * k, 1.3, 3.5, at, 0.0, 0.38 * s)
		b.lathe(top, inner, 16, Z_GLOW, 0.35 + 0.08 * k, 1.3, 3.5, at, 0.0, 0.38 * s, true)
		b.ball(top + Vector3(0, -0.36 * s, 0), 0.05 * s, Z_GLOW, 0.4 + 0.08 * k, at, 1.3, 3.5)
		light += top
	return {"height": 3.6, "light": light / bells + Vector3(0, -0.3, 0), "glows": true}


static func _fern(b: Builder, rng: RandomNumberGenerator) -> Dictionary:
	var fronds := 7
	for f in fronds:
		var a := TAU * f / fronds + rng.randf_range(-0.2, 0.2)
		var d := Vector3(cos(a), 0, sin(a))
		var length := rng.randf_range(2.6, 3.4)
		var rise := rng.randf_range(0.5, 0.7)
		var axis := d.cross(Vector3.UP)
		var spine := PackedVector3Array()
		var steps := 22
		for i in steps:
			var t := float(i) / (steps - 1)
			spine.append(Vector3(0, 0.05, 0) + d * (length * 0.8 * t) + Vector3.UP * (length * rise * sin(t * PI * 0.72)))
		var curl_at := spine[int((steps - 1) * 0.5)]
		var delay := 0.08 * f
		# The rachis, then pairs of pinnae down its length.
		b.frond_strip(spine, 0.06, 0.02, axis, Z_LEAF, delay, 2.8, curl_at, 0.5, 5.2)
		var pairs := 13
		for k in pairs:
			var t := 0.12 + 0.86 * float(k) / pairs
			var i := int(t * (steps - 1))
			var p := spine[i]
			var tan := (spine[mini(i + 1, steps - 1)] - spine[maxi(i - 1, 0)]).normalized()
			var side := tan.cross(Vector3.UP).normalized()
			var lp := 0.62 * pow(sin(PI * clampf(t * 1.05, 0.0, 1.0)), 0.8) + 0.08
			for sgn: float in [-1.0, 1.0]:
				var dir := (side * sgn + tan * 0.55).normalized()
				b.pinna(p, dir, lp, 0.1, axis, Z_LEAF, delay + 0.2, 2.8, curl_at, t, 0.5, 5.2)
	return {"height": 2.0, "light": Vector3(0, 1.2, 0), "glows": false}


static func _lotus(b: Builder, rng: RandomNumberGenerator) -> Dictionary:
	var pads: Array = []
	var pad_count := 3
	for k in pad_count:
		var a := TAU * k / pad_count + rng.randf_range(-0.4, 0.4)
		var r := rng.randf_range(1.0, 1.35)
		var c := Vector3(cos(a), 0, sin(a)) * rng.randf_range(1.3, 1.75)
		c.y = 0.03
		b.pad(c, r, rng.randf() * TAU, Z_LEAF, 0.05 + 0.1 * k)
		pads.append([c, r])
	var c := Vector3(0, 0.06, 0)
	var layers := [[9, 1.05, 0.44, 18.0, 52.0], [8, 0.86, 0.38, 42.0, 72.0], [6, 0.62, 0.32, 62.0, 84.0]]
	for li in layers.size():
		var l: Array = layers[li]
		for i in int(l[0]):
			var a := TAU * (float(i) + 0.5 * li) / float(l[0])
			var d := Vector3(cos(a), 0, sin(a))
			b.petal(c, Vector3.UP, d, l[1], l[2], l[3], l[4], 0.22, Z_PETAL, 0.3 + 0.12 * li, 0.05, 1.0, 0.95)
	var core: Array[Vector2] = [Vector2(0.0, 0.2), Vector2(0.17, 0.19), Vector2(0.2, 0.1), Vector2(0.16, 0.0)]
	b.lathe(c, core, 12, Z_GLOW, 0.65, 0.05, 1.0, c, 0.0, 0.2)
	return {"height": 1.0, "pads": pads, "light": c + Vector3(0, 0.5, 0), "glows": true}


static func _puffball(b: Builder, rng: RandomNumberGenerator) -> Dictionary:
	var h := 3.6
	var bend := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * 0.3
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 12:
		var t := float(i) / 11.0
		path.append(Vector3(0, h * t, 0) + bend * sin(t * PI * 0.8))
		radii.append(0.05 * (1.0 - 0.3 * t) + 0.02 * exp(-t * 8.0))
	b.tube(path, radii, 7, Z_STEM, 0.0, 0.9, h)
	_leaf(b, Vector3(0, 0.05, 0), Vector3(1, 0, 0.3).normalized(), 1.1, 0.24, 65.0, 25.0, 0.05, h)
	var c := path[11]
	b.ball(c, 0.13, Z_STEM, 0.35, c, 0.9, h)
	var seeds := 72
	for i in seeds:
		# Fibonacci sphere: evenly spread seeds.
		var y := 1.0 - 2.0 * (float(i) + 0.5) / seeds
		var rr := sqrt(1.0 - y * y)
		var phi := float(i) * 2.39996
		var d := Vector3(cos(phi) * rr, y, sin(phi) * rr)
		var length := rng.randf_range(0.72, 0.88)
		var delay := 0.4 + 0.3 * rng.randf()
		b.tube(PackedVector3Array([c + d * 0.1, c + d * length]), PackedFloat32Array([0.008, 0.005]), 3, Z_PETAL, delay, 0.9, h, c)
		b.star(c + d * length, d, 0.07, Z_GLOW, delay + 0.1, c, 0.9, h)
	return {"height": h + 0.9, "light": c, "glows": true, "head": c, "head_r": 0.85}


static func _leaf(b: Builder, base: Vector3, d: Vector3, length: float, width: float, e0: float, e1: float, cup: float, h: float) -> void:
	b.petal(base, Vector3.UP, d, length, width, e0, e1, cup, Z_LEAF, 0.1, 0.4, h, 0.7)


static func _catmull(ctrl: PackedVector3Array, sub: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in ctrl.size() - 1:
		var p0 := ctrl[maxi(i - 1, 0)]
		var p1 := ctrl[i]
		var p2 := ctrl[i + 1]
		var p3 := ctrl[mini(i + 2, ctrl.size() - 1)]
		for s in sub:
			var t := float(s) / sub
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	out.append(ctrl[ctrl.size() - 1])
	return out


# ---------------------------------------------------------------------------

## Writes the rigged vertices (see the shader for what each channel means).
class Builder:
	var st := SurfaceTool.new()
	var count := 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
		st.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)

	func commit() -> ArrayMesh:
		return st.commit()

	func vert(p: Vector3, n: Vector3, uv: Vector2, zone: float, along: float, delay: float, sway: float, anchor: Vector3, axis: Vector3, fold: float) -> int:
		st.set_normal(n.normalized() if n.length_squared() > 0.0 else Vector3.UP)
		st.set_uv(uv)
		st.set_color(Color(zone, clampf(along, 0.0, 1.0), delay, sway))
		st.set_custom(0, Color(anchor.x, anchor.y, anchor.z, 0.0))
		st.set_custom(1, Color(axis.x, axis.y, axis.z, fold))
		st.add_vertex(p)
		count += 1
		return count - 1

	func quad(a: int, b: int, c: int, d: int) -> void:
		st.add_index(a)
		st.add_index(b)
		st.add_index(c)
		st.add_index(a)
		st.add_index(c)
		st.add_index(d)

	static func sway_of(p: Vector3, scale: float, h: float) -> float:
		var k := clampf(p.y / maxf(h, 0.01), 0.0, 1.5)
		return k * k * scale

	## A tube down a path (parallel-transported frames).
	func tube(path: PackedVector3Array, radii: PackedFloat32Array, sides: int, zone: float, delay: float, sway: float, h: float, anchor := Vector3.ZERO) -> void:
		var n := path.size()
		var t0 := (path[1] - path[0]).normalized()
		var nrm := t0.cross(Vector3.UP if absf(t0.y) < 0.95 else Vector3.RIGHT).normalized()
		var total := 0.0
		var arc := PackedFloat32Array([0.0])
		for i in range(1, n):
			total += path[i].distance_to(path[i - 1])
			arc.append(total)
		var base := count
		for i in n:
			var tan := (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
			nrm = (nrm - tan * nrm.dot(tan)).normalized()
			var bin := tan.cross(nrm)
			var along := arc[i] / maxf(total, 0.0001)
			for j in sides + 1:
				var a := TAU * j / sides
				var dir := nrm * cos(a) + bin * sin(a)
				var p := path[i] + dir * radii[i]
				vert(p, dir, Vector2(float(j) / sides, along), zone, along, delay, sway_of(p, sway, h), anchor, Vector3.ZERO, 0.0)
		for i in n - 1:
			for j in sides:
				var a := base + i * (sides + 1) + j
				var b := a + sides + 1
				quad(a, b, b + 1, a + 1)

	## A surface of revolution round the vertical through `c`: profile
	## points are (radius, height). Parts fold round their tangent at `hinge`.
	func lathe(c: Vector3, prof: Array[Vector2], segs: int, zone: float, delay: float, sway: float, h: float, hinge: Vector3, fold: float, along_r := 0.0, flip := false) -> void:
		var base := count
		var m := prof.size()
		for k in m:
			var pr := prof[k]
			var d: Vector2 = prof[mini(k + 1, m - 1)] - prof[maxi(k - 1, 0)]
			var n2 := Vector2(-d.y, d.x).normalized()
			if flip:
				n2 = -n2
			var along := pr.x / along_r if along_r > 0.0 else float(k) / (m - 1)
			for j in segs + 1:
				var a := TAU * j / segs
				var dir := Vector3(cos(a), 0.0, sin(a))
				var p := c + dir * pr.x + Vector3.UP * pr.y
				var n := dir * n2.x + Vector3.UP * n2.y
				var axis := dir.cross(Vector3.UP) if fold != 0.0 else Vector3.ZERO
				vert(p, n, Vector2(float(j) / segs, along), zone, along, delay, sway_of(p, sway, h), hinge, axis, fold * clampf(along, 0.0, 1.0))
		for k in m - 1:
			for j in segs:
				var a := base + k * (segs + 1) + j
				var b := a + segs + 1
				quad(a, b, b + 1, a + 1)

	## A curved blade (petal or leaf) growing out of `c` along `dir_h`: it
	## rises at `e0` degrees and bends to `e1` at its tip, `cup` curls the
	## sides up. Folds closed round its base by `fold` radians.
	func petal(c: Vector3, up: Vector3, dir_h: Vector3, length: float, width: float, e0: float, e1: float, cup: float, zone: float, delay: float, sway: float, h: float, fold: float) -> void:
		var rows := 9
		var cols := 4
		var side := dir_h.cross(up).normalized()
		var spine := PackedVector3Array()
		var p := c
		for i in rows:
			var t := float(i) / (rows - 1)
			spine.append(p)
			var e := deg_to_rad(lerpf(e0, e1, pow(t, 1.4)))
			p += (dir_h * cos(e) + up * sin(e)) * (length / (rows - 1))
		var base := count
		for i in rows:
			var t := float(i) / (rows - 1)
			var tan := (spine[mini(i + 1, rows - 1)] - spine[maxi(i - 1, 0)]).normalized()
			var nrm := side.cross(tan).normalized()
			if nrm.dot(up) < 0.0:
				nrm = -nrm
			var w := width * pow(sin(PI * minf(t * 0.92 + 0.08, 1.0)), 0.75) * (1.0 - 0.25 * t)
			for j in cols + 1:
				var u := float(j) / cols * 2.0 - 1.0
				var q := spine[i] + side * (u * w) + nrm * (u * u * cup * w * 2.0)
				vert(q, nrm - side * u * 0.4, Vector2(t, float(j) / cols), zone, t, delay, sway_of(q, sway, h), c, side, fold)
		for i in rows - 1:
			for j in cols:
				var a := base + i * (cols + 1) + j
				var b := a + cols + 1
				quad(a, a + 1, b + 1, b)

	## A fern's rachis: a thin strip down `spine` whose outer part coils up
	## (fold grows from 0 at `curl_from` to `curl` at the tip) round `curl_at`.
	func frond_strip(spine: PackedVector3Array, w0: float, w1: float, axis: Vector3, zone: float, delay: float, h: float, curl_at: Vector3, curl_from: float, curl: float) -> void:
		var n := spine.size()
		var base := count
		for i in n:
			var t := float(i) / (n - 1)
			var tan := (spine[mini(i + 1, n - 1)] - spine[maxi(i - 1, 0)]).normalized()
			var side := tan.cross(Vector3.UP).normalized()
			var nrm := side.cross(tan).normalized()
			var w := lerpf(w0, w1, t)
			var f := curl * clampf((t - curl_from) / (1.0 - curl_from), 0.0, 1.0)
			var anchor := curl_at if t > curl_from else Vector3.ZERO
			for s: float in [-1.0, 1.0]:
				var q := spine[i] + side * (w * s)
				vert(q, nrm, Vector2(t, 0.5 + 0.5 * s), zone, t * 0.6, delay, sway_of(q, 0.6, h), anchor, axis if t > curl_from else Vector3.ZERO, f)
		for i in n - 1:
			var a := base + i * 2
			quad(a, a + 1, a + 3, a + 2)

	## One fern leaflet off the rachis at fraction `t`, coiling with it.
	func pinna(p: Vector3, dir: Vector3, length: float, width: float, axis: Vector3, zone: float, delay: float, h: float, curl_at: Vector3, t: float, curl_from: float, curl: float) -> void:
		var rows := 4
		var base := count
		var nrm := dir.cross(axis).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		var side := nrm.cross(dir).normalized()
		var f := curl * clampf((t - curl_from) / (1.0 - curl_from), 0.0, 1.0)
		var anchor := curl_at if t > curl_from else Vector3.ZERO
		var ax := axis if t > curl_from else Vector3.ZERO
		for i in rows:
			var k := float(i) / (rows - 1)
			var w := width * sin(PI * minf(k * 0.85 + 0.15, 1.0))
			var q0 := p + dir * (length * k) + Vector3.DOWN * (k * k * length * 0.15)
			for s: float in [-1.0, 1.0]:
				var q := q0 + side * (w * s)
				vert(q, nrm, Vector2(k, 0.5 + 0.5 * s), zone, 0.55 + 0.45 * t, delay, sway_of(q, 0.7, h), anchor, ax, f)
		for i in rows - 1:
			var a := base + i * 2
			quad(a, a + 1, a + 3, a + 2)

	## A floating pad: a flat disc with a notch, rim turned up a little.
	func pad(c: Vector3, r: float, notch_at: float, zone: float, delay: float) -> void:
		var segs := 24
		var rings := 4
		var base := count
		for k in rings + 1:
			var rr := r * float(k) / rings
			for j in segs + 1:
				var a := notch_at + 0.25 + (TAU - 0.5) * j / segs
				var p := c + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
				p.y += pow(float(k) / rings, 4.0) * 0.08
				vert(p, Vector3.UP, Vector2(float(j) / segs, 0.5 + 0.5 * cos(a * 7.0)), zone, float(k) / rings, delay, 0.05, c, Vector3.ZERO, 0.0)
		for k in rings:
			for j in segs:
				var a := base + k * (segs + 1) + j
				var b := a + segs + 1
				quad(a, a + 1, b + 1, b)

	## A low-poly ball.
	func ball(c: Vector3, r: float, zone: float, delay: float, anchor: Vector3, sway := 0.0, h := 1.0) -> void:
		var prof: Array[Vector2] = []
		for k in 6:
			var a := PI * 0.5 - PI * k / 5.0
			prof.append(Vector2(cos(a) * r, sin(a) * r))
		var base := count
		var segs := 8
		for k in prof.size():
			var pr := prof[k]
			for j in segs + 1:
				var a := TAU * j / segs
				var dir := Vector3(cos(a), 0, sin(a))
				var n := dir * pr.x + Vector3.UP * pr.y
				var p := c + n
				vert(p, n, Vector2(float(j) / segs, float(k) / 5.0), zone, float(k) / 5.0, delay, sway_of(p, sway, h), anchor, Vector3.ZERO, 0.0)
		for k in prof.size() - 1:
			for j in segs:
				var a := base + k * (segs + 1) + j
				var b := a + segs + 1
				quad(a, b, b + 1, a + 1)

	## A glowing four-point star on the tip of a seed.
	func star(c: Vector3, d: Vector3, s: float, zone: float, delay: float, anchor: Vector3, sway: float, h: float) -> void:
		var u := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
		var v := d.cross(u).normalized()
		for pair in [[u, v], [v, u]]:
			var a: Vector3 = pair[0]
			var base := count
			vert(c - a * s, d, Vector2(0, 0.5), zone, 0.5, delay, sway_of(c, sway, h), anchor, Vector3.ZERO, 0.0)
			vert(c + d * s * 0.6, d, Vector2(0.5, 1), zone, 1.0, delay, sway_of(c, sway, h), anchor, Vector3.ZERO, 0.0)
			vert(c + a * s, d, Vector2(1, 0.5), zone, 0.5, delay, sway_of(c, sway, h), anchor, Vector3.ZERO, 0.0)
			vert(c - d * s * 0.6, d, Vector2(0.5, 0), zone, 1.0, delay, sway_of(c, sway, h), anchor, Vector3.ZERO, 0.0)
			quad(base, base + 1, base + 2, base + 3)
