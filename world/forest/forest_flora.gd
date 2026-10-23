class_name ForestFlora
extends RefCounted
## Procedural plants and forest-floor clutter that the kit doesn't have:
## lush arching ferns, reeds and cattails for the water's edge, flower spikes,
## bluebell clumps, fallen leaves, twigs, stumps and moss cushions. Every mesh
## carries COLOR.r = 0 at the root to 1 at the tip for the wind shader.

var kit: NatureKit
var _mats := {}
var _white: ImageTexture


func _init(p_kit: NatureKit) -> void:
	kit = p_kit
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(img)


## Plant shader material with a flat colour (or a texture) instead of a kit atlas.
func material(key: String, tint: Color, opts := {}) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var mat := ShaderMaterial.new()
	mat.shader = NatureKit.SH_PLANT
	var tex: Texture2D = opts.get("texture", _white)
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("use_alpha", opts.has("texture"))
	mat.set_shader_parameter("ground_noise", NatureKit.NOISE)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("hue_variation", opts.get("hue", 0.05))
	mat.set_shader_parameter("bend_height", opts.get("bend", 1.0))
	mat.set_shader_parameter("stiffness", opts.get("stiffness", 1.0))
	mat.set_shader_parameter("translucency", opts.get("translucency", 0.6))
	mat.set_shader_parameter("up_normal", opts.get("up_normal", 0.4))
	mat.set_shader_parameter("fade_start", opts.get("fade_start", 26.0))
	mat.set_shader_parameter("fade_end", opts.get("fade_end", 36.0))
	if opts.has("glow"):
		mat.set_shader_parameter("glow", opts.glow)
		mat.set_shader_parameter("glow_color", opts.get("glow_color", tint))
	kit.wind_materials.append(mat)
	kit.interactive_materials.append(mat)
	_mats[key] = mat
	return mat


class Builder:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	func vert(p: Vector3, n: Vector3, w: float, uv := Vector2.ZERO) -> int:
		verts.append(p)
		norms.append(n)
		cols.append(Color(w, 0.0, 0.0))
		uvs.append(uv)
		return verts.size() - 1

	func tri(a: int, b: int, c: int) -> void:
		idx.append_array([a, b, c])

	func quad(a: int, b: int, c: int, d: int) -> void:
		idx.append_array([a, b, c, a, c, d])

	func empty() -> bool:
		return idx.is_empty()

	func add_to(m: ArrayMesh, mat: Material) -> void:
		if idx.is_empty():
			return
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(m.get_surface_count() - 1, mat)

	## A tapered stalk with `sides` faces along a polyline.
	func stalk(pts: Array, r0: float, r1: float, sides: int, h: float) -> void:
		var start := verts.size()
		for k in pts.size():
			var p: Vector3 = pts[k]
			var t := float(k) / (pts.size() - 1)
			var r := lerpf(r0, r1, t)
			for s in sides:
				var a := TAU * s / sides
				var n := Vector3(cos(a), 0.0, sin(a))
				vert(p + n * r, n, clampf(p.y / h, 0.0, 1.0))
		for k in pts.size() - 1:
			for s in sides:
				var i0 := start + k * sides + s
				var i1 := start + k * sides + (s + 1) % sides
				quad(i0, i0 + sides, i1 + sides, i1)


func _finish(name: String, builders: Array, mats: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	for i in builders.size():
		(builders[i] as Builder).add_to(m, mats[i])
	m.resource_name = name
	return m


# ----------------------------------------------------------------------------
# Ferns

## A lush fern: fronds spiral out of a crown, arch over and droop, each lined
## with leaflets that shrink towards the tip.
func fern(seed: int, kind := "lady") -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := Builder.new()
	var fronds := rng.randi_range(7, 10)
	var length := 0.9 if kind == "lady" else 1.25
	var arch := 0.55 if kind == "lady" else 0.35
	var pairs := 10
	for f in fronds:
		var yaw := TAU * f / fronds + rng.randf_range(-0.25, 0.25)
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-out.z, 0.0, out.x)
		var len_f := length * rng.randf_range(0.7, 1.15)
		var rise := rng.randf_range(0.8, 1.25)
		# Rachis as a quadratic arc: up and out, then drooping.
		var p0 := Vector3.ZERO
		var p1 := out * len_f * 0.35 + Vector3.UP * len_f * 0.75 * rise
		var p2 := out * len_f * 0.95 + Vector3.UP * len_f * (0.75 * rise - arch - 0.1)
		var prev := p0
		for k in pairs:
			var t := float(k + 1) / (pairs + 1)
			var q := p0 * (1.0 - t) * (1.0 - t) + p1 * 2.0 * t * (1.0 - t) + p2 * t * t
			var tan := (q - prev).normalized()
			prev = q
			var up := tan.cross(side).normalized()
			if up.y < 0.0:
				up = -up
			var leaf := len_f * 0.28 * sin(PI * minf(t * 1.15, 1.0)) * (1.0 - t * 0.45)
			var w := leaf * 0.28
			var hgt := q.y / (len_f * 0.9)
			for s: float in [-1.0, 1.0]:
				var dirl := (side * s + tan * 0.35 - up * 0.15).normalized()
				var tip := q + dirl * leaf
				var mid := q + dirl * leaf * 0.45
				var n := up
				var i0 := b.vert(q, n, hgt * 0.9)
				var i1 := b.vert(mid + tan * w, n, hgt)
				var i2 := b.vert(tip, n, hgt)
				var i3 := b.vert(mid - tan * w, n, hgt)
				b.quad(i0, i1, i2, i3)
		# The stalk itself.
		var s0 := b.vert(p0 - side * 0.012, Vector3.UP, 0.0)
		var s1 := b.vert(p0 + side * 0.012, Vector3.UP, 0.0)
		var s2 := b.vert(p2 + side * 0.004, Vector3.UP, 1.0)
		var s3 := b.vert(p2 - side * 0.004, Vector3.UP, 1.0)
		b.quad(s0, s1, s2, s3)
	var col := Color(0.42, 0.72, 0.24) if kind == "lady" else Color(0.34, 0.6, 0.2)
	var mat := material("fern_" + kind, col, {"bend": 0.9, "stiffness": 1.3, "translucency": 0.9, "up_normal": 0.35, "fade_start": 30.0, "fade_end": 40.0})
	return _finish("ProcFern_%s_%d" % [kind, seed], [b], [mat])


# ----------------------------------------------------------------------------
# Water's edge

## Reeds and rushes, a few topped with velvety cattail heads.
func reeds(seed: int, cattails: bool) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var blades := Builder.new()
	var heads := Builder.new()
	var count := rng.randi_range(10, 16)
	var h_max := 1.8
	for i in count:
		var r := sqrt(rng.randf()) * 0.32
		var a := rng.randf() * TAU
		var base := Vector3(cos(a) * r, -0.05, sin(a) * r)
		var h := rng.randf_range(0.9, h_max)
		var lean := Vector3(cos(a), 0.0, sin(a)) * h * rng.randf_range(0.04, 0.16) + Vector3(rng.randf_range(-0.06, 0.06), 0.0, rng.randf_range(-0.06, 0.06))
		var face := rng.randf() * TAU
		var sd := Vector3(cos(face), 0.0, sin(face))
		var n := sd.cross(Vector3.UP).normalized()
		var wid := rng.randf_range(0.018, 0.03)
		var levels := 4
		var prev_a := -1
		var prev_b := -1
		for l in levels + 1:
			var t := float(l) / levels
			var c := base + Vector3.UP * h * t + lean * t * t
			var hw := wid * (1.0 - t * 0.85)
			var ia := blades.vert(c - sd * hw, n, c.y / h_max)
			var ib := blades.vert(c + sd * hw, n, c.y / h_max)
			if prev_a >= 0:
				blades.quad(prev_a, prev_b, ib, ia)
			prev_a = ia
			prev_b = ib
		if cattails and rng.randf() < 0.45 and h > 1.2:
			var t0 := 0.68
			var t1 := 0.86
			var c0 := base + Vector3.UP * h * t0 + lean * t0 * t0
			var c1 := base + Vector3.UP * h * t1 + lean * t1 * t1
			var start := heads.verts.size()
			for k in 3:
				var c := c0.lerp(c1, k / 2.0)
				var rr := 0.032 if k == 1 else 0.026
				for s in 6:
					var aa := TAU * s / 6.0
					var nn := Vector3(cos(aa), 0.0, sin(aa))
					heads.vert(c + nn * rr, nn, c.y / h_max)
			for k in 2:
				for s in 6:
					var i0 := start + k * 6 + s
					var i1 := start + k * 6 + (s + 1) % 6
					heads.quad(i0, i1, i1 + 6, i0 + 6)
	var mats := [
		material("reed", Color(0.5, 0.66, 0.28), {"bend": 1.8, "translucency": 0.8, "up_normal": 0.5}),
		material("cattail", Color(0.36, 0.22, 0.12), {"bend": 1.8, "hue": 0.02, "translucency": 0.1}),
	]
	return _finish("Reeds_%d" % seed, [blades, heads], mats)


# ----------------------------------------------------------------------------
# Flowers

## Tall spikes of bells (foxglove-like) or upright florets (lupin-like).
func flower_spike(seed: int, kind: String) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var stems := Builder.new()
	var petals := Builder.new()
	var spikes := rng.randi_range(2, 4)
	var h_max := 1.1
	for i in spikes:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.0, 0.14)
		var h := rng.randf_range(0.65, h_max)
		var lean := Vector3(rng.randf_range(-0.08, 0.08), 0.0, rng.randf_range(-0.08, 0.08))
		var pts := []
		for k in 5:
			var t := k / 4.0
			pts.append(base + Vector3.UP * h * t + lean * t * t)
		stems.stalk(pts, 0.012, 0.005, 4, h_max)
		# Rosette of leaves at the foot.
		for k in 5:
			var la := a + TAU * k / 5.0
			var d := Vector3(cos(la), 0.0, sin(la))
			var sd := Vector3(-d.z, 0.0, d.x)
			var l := rng.randf_range(0.18, 0.28)
			var i0 := stems.vert(base, Vector3.UP, 0.0)
			var i1 := stems.vert(base + d * l * 0.5 + sd * 0.05 + Vector3.UP * 0.06, Vector3.UP, 0.05)
			var i2 := stems.vert(base + d * l + Vector3.UP * 0.02, Vector3.UP, 0.05)
			var i3 := stems.vert(base + d * l * 0.5 - sd * 0.05 + Vector3.UP * 0.06, Vector3.UP, 0.05)
			stems.quad(i0, i1, i2, i3)
		# Florets up the top half of the spike.
		var florets := 9
		for k in florets:
			var t := lerpf(0.45, 0.97, float(k) / (florets - 1))
			var c: Vector3 = base + Vector3.UP * h * t + lean * t * t
			var fa := k * 2.4 + rng.randf()
			var d := Vector3(cos(fa), 0.0, sin(fa))
			var s := lerpf(0.06, 0.03, float(k) / florets)
			var w := c.y / h_max
			if kind == "bells":
				# A drooping bell: a little cone hanging off the stem.
				var mouth := c + d * s * 1.1 - Vector3.UP * s * 0.9
				var start := petals.verts.size()
				var tip := petals.vert(c + d * 0.01, -d, w)
				for e in 5:
					var ea := TAU * e / 5.0
					var ring := (Vector3.UP.cross(d).normalized() * cos(ea) + (Vector3.UP - d).normalized() * sin(ea)) * s * 0.55
					petals.vert(mouth + ring, (ring + d * 0.3).normalized(), w)
				for e in 5:
					petals.tri(tip, start + 1 + e, start + 1 + (e + 1) % 5)
			else:
				var sd := Vector3(-d.z, 0.0, d.x)
				var i0 := petals.vert(c, Vector3.UP, w)
				var i1 := petals.vert(c + d * s + sd * s * 0.5 + Vector3.UP * s * 0.6, d, w)
				var i2 := petals.vert(c + d * s * 1.4 + Vector3.UP * s * 0.2, d, w)
				var i3 := petals.vert(c + d * s - sd * s * 0.5 + Vector3.UP * s * 0.6, d, w)
				petals.quad(i0, i1, i2, i3)
	var col := Color(0.86, 0.42, 0.78) if kind == "bells" else Color(0.5, 0.42, 0.95)
	var mats := [
		material("spike_stem", Color(0.32, 0.55, 0.2), {"bend": 1.3, "translucency": 0.5}),
		material("spike_" + kind, col, {"bend": 1.3, "hue": 0.1, "translucency": 1.0, "up_normal": 0.3}),
	]
	return _finish("FlowerSpike_%s_%d" % [kind, seed], [stems, petals], mats)


## A clump of arching stems hung with little nodding blue bells.
func bluebells(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var stems := Builder.new()
	var bells := Builder.new()
	var h_max := 0.4
	for i in rng.randi_range(5, 8):
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.0, 0.12)
		var h := rng.randf_range(0.22, h_max)
		var out := Vector3(cos(a), 0.0, sin(a))
		var pts := []
		for k in 5:
			var t := k / 4.0
			pts.append(base + Vector3.UP * h * sin(t * PI * 0.5) + out * h * 0.45 * t * t)
		stems.stalk(pts, 0.006, 0.003, 3, h_max)
		# Strap leaves.
		var sd := Vector3(-out.z, 0.0, out.x)
		var l0 := stems.vert(base - sd * 0.012, Vector3.UP, 0.0)
		var l1 := stems.vert(base + sd * 0.012, Vector3.UP, 0.0)
		var l2 := stems.vert(base + out * h * 0.8 + Vector3.UP * h * 0.25, Vector3.UP, 0.4)
		stems.tri(l0, l1, l2)
		for k in 4:
			var t := 0.55 + k * 0.13
			var c := base + Vector3.UP * h * sin(t * PI * 0.5) + out * h * 0.45 * t * t
			var hang := c - Vector3.UP * 0.035 + sd * (0.02 if k % 2 == 0 else -0.02)
			var start := bells.verts.size()
			var top := bells.vert(c, Vector3.UP, c.y / h_max)
			for e in 5:
				var ea := TAU * e / 5.0
				var ring := Vector3(cos(ea), 0.0, sin(ea)) * 0.016
				bells.vert(hang + ring, (ring + Vector3.DOWN * 0.01).normalized(), c.y / h_max)
			for e in 5:
				bells.tri(top, start + 1 + (e + 1) % 5, start + 1 + e)
	var mats := [
		material("bluebell_stem", Color(0.3, 0.52, 0.2), {"bend": 0.5, "translucency": 0.5}),
		material("bluebell", Color(0.36, 0.42, 1.0), {"bend": 0.5, "hue": 0.06, "translucency": 1.0, "glow": 0.08, "glow_color": Color(0.4, 0.5, 1.0)}),
	]
	return _finish("Bluebells_%d" % seed, [stems, bells], mats)


# ----------------------------------------------------------------------------
# Forest floor

## A scatter of fallen leaves lying flat on the ground, each a tiny bent card.
func leaf_litter(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := Builder.new()
	for i in 14:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.55
		var c := Vector3(cos(a) * r, 0.015 + rng.randf() * 0.02, sin(a) * r)
		var yaw := rng.randf() * TAU
		var d := Vector3(cos(yaw), 0.0, sin(yaw))
		var sd := Vector3(-d.z, 0.0, d.x)
		var s := rng.randf_range(0.05, 0.085)
		var curl := Vector3.UP * s * rng.randf_range(0.1, 0.5)
		var i0 := b.vert(c - d * s, Vector3.UP, 0.0, Vector2(0.0, 0.0))
		var i1 := b.vert(c + sd * s * 0.55 + curl, Vector3.UP, 0.0, Vector2(1.0, 0.0))
		var i2 := b.vert(c + d * s, Vector3.UP, 0.0, Vector2(1.0, 1.0))
		var i3 := b.vert(c - sd * s * 0.55 + curl, Vector3.UP, 0.0, Vector2(0.0, 1.0))
		b.quad(i0, i1, i2, i3)
	var mat := material("litter", Color(0.62, 0.36, 0.14), {"bend": 0.1, "stiffness": 50.0, "hue": 0.18, "translucency": 0.3, "up_normal": 0.9, "fade_start": 18.0, "fade_end": 26.0})
	return _finish("LeafLitter_%d" % seed, [b], [mat])


## A short broken stump: a fat tapered tube with a ragged top.
func stump(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 10
	var h := rng.randf_range(0.35, 0.8)
	var rings := 4
	var tops := []
	for s in sides:
		tops.append(h * rng.randf_range(0.7, 1.0) if rng.randf() < 0.6 else h)
	for r in rings:
		for s in sides:
			for corner in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
				var ss: int = (s + corner[0]) % sides
				var rr: int = r + corner[1]
				var a := TAU * float(s + int(corner[0])) / sides
				var t := float(rr) / rings
				var y: float = lerpf(-0.15, tops[ss], t)
				var flare := 1.0 + 0.6 * pow(1.0 - t, 3.0)
				var rad := 0.32 * flare * (1.0 + 0.08 * sin(a * 3.0 + seed))
				var n := Vector3(cos(a), 0.15, sin(a)).normalized()
				st.set_normal(n)
				st.set_tangent(Plane(Vector3(-sin(a), 0.0, cos(a)), 1.0))
				st.set_uv(Vector2((s + corner[0]) / float(sides) * 2.0, y * 1.5))
				st.set_color(Color(lerpf(0.5, 1.0, t), 0.0, 0.0))
				st.add_vertex(Vector3(cos(a) * rad, y, sin(a) * rad))
	# Pale cut face.
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		var rad := 0.32 * (1.0 + 0.08 * sin(a0 * 3.0 + seed))
		var rad1 := 0.32 * (1.0 + 0.08 * sin(a1 * 3.0 + seed))
		for v in [[0.0, 0.0, h * 0.85], [cos(a1) * rad1, sin(a1) * rad1, tops[(s + 1) % sides]], [cos(a0) * rad, sin(a0) * rad, tops[s]]]:
			st.set_normal(Vector3.UP)
			st.set_tangent(Plane(Vector3.RIGHT, 1.0))
			st.set_uv(Vector2(v[0], v[1]) * 2.0 + Vector2(0.5, 0.5))
			st.set_color(Color(1.0, 0.0, 0.0))
			st.add_vertex(Vector3(v[0], v[2], v[1]))
	var m := st.commit()
	m.surface_set_material(0, kit.bark_material("Bark_DeadTree"))
	m.resource_name = "Stump_%d" % seed
	return m


## A fallen twig with a couple of side shoots.
func twig(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := Builder.new()
	var length := rng.randf_range(0.6, 1.3)
	var dir := Vector3(1.0, 0.0, 0.0)
	var pts := []
	var p := Vector3(-length * 0.5, 0.03, 0.0)
	for k in 5:
		pts.append(p)
		dir = (dir + Vector3(0.0, 0.0, rng.randf_range(-0.3, 0.3))).normalized()
		p += dir * length / 4.0
	_twig_tube(b, pts, 0.025, 0.008)
	for k in 2:
		var at: Vector3 = pts[1 + k * 2]
		var sd := Vector3(rng.randf_range(0.3, 0.7), 0.0, 1.0 if k == 0 else -1.0).normalized()
		_twig_tube(b, [at, at + sd * length * 0.2 + Vector3.UP * 0.01, at + sd * length * 0.35], 0.012, 0.004)
	var mat := material("twig", Color(0.34, 0.26, 0.2), {"bend": 0.1, "stiffness": 60.0, "hue": 0.02, "translucency": 0.0, "up_normal": 0.2, "fade_start": 20.0, "fade_end": 28.0})
	return _finish("Twig_%d" % seed, [b], [mat])


func _twig_tube(b: Builder, pts: Array, r0: float, r1: float) -> void:
	var start := b.verts.size()
	var sides := 4
	for k in pts.size():
		var t := float(k) / (pts.size() - 1)
		var p: Vector3 = pts[k]
		var r := lerpf(r0, r1, t)
		for s in sides:
			var a := TAU * s / sides
			var n := Vector3(0.0, cos(a), sin(a))
			b.vert(p + n * r, n, 0.0)
	for k in pts.size() - 1:
		for s in sides:
			var i0 := start + k * sides + s
			var i1 := start + k * sides + (s + 1) % sides
			b.quad(i0, i1, i1 + sides, i0 + sides)


## A soft cushion of moss, a squashed lumpy dome.
func moss(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := Builder.new()
	var seg := 9
	var rings := 3
	var top := b.vert(Vector3(0.0, 0.16, 0.0), Vector3.UP, 0.0)
	var lumps := []
	for s in seg:
		lumps.append(rng.randf_range(0.75, 1.15))
	for r in range(1, rings + 1):
		var f := float(r) / rings
		for s in seg:
			var a := TAU * s / seg
			var rad: float = 0.5 * f * lumps[s]
			var y := 0.16 * cos(f * PI * 0.5) - 0.03 * f
			var n := Vector3(cos(a) * f, 1.0 - f * 0.6, sin(a) * f).normalized()
			b.vert(Vector3(cos(a) * rad, y, sin(a) * rad), n, 0.0)
	for s in seg:
		b.tri(top, 1 + (s + 1) % seg, 1 + s)
	for r in rings - 1:
		for s in seg:
			var i0 := 1 + r * seg + s
			var i1 := 1 + r * seg + (s + 1) % seg
			b.quad(i0, i1, i1 + seg, i0 + seg)
	var mat := material("moss", Color(0.36, 0.55, 0.16), {"bend": 0.1, "stiffness": 80.0, "hue": 0.05, "translucency": 0.3, "up_normal": 0.5, "fade_start": 28.0, "fade_end": 38.0})
	return _finish("Moss_%d" % seed, [b], [mat])
