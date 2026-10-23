class_name ForestWater
extends RefCounted
## Builds the pond, the cascading creek and the meandering stream as meshes
## that carry their own water depth and flow speed per vertex, plus lily pads
## and softly glowing lotus blossoms on the pond.

var layout: ForestLayout
var terrain: ForestTerrain
var kit: NatureKit
var lotus_points: Array[Vector3] = []


func _init(p_layout: ForestLayout, p_terrain: ForestTerrain, p_kit: NatureKit) -> void:
	layout = p_layout
	terrain = p_terrain
	kit = p_kit


func build(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Water"
	parent.add_child(root)
	root.add_child(_pond())
	root.add_child(_river("Creek", terrain.creek_points, terrain.creek_surface, 1.25, 0.9))
	root.add_child(_river("Stream", terrain.stream_points, terrain.stream_surface, 1.7, 0.35))
	root.add_child(_lilies())


func _pond() -> MeshInstance3D:
	var c := ForestLayout.POND
	var level := terrain.pond_level
	var seg := 56
	var rings := 12
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	# Centre vertex then concentric rings reaching under the banks.
	verts.append(Vector3(c.x, level, c.y))
	cols.append(Color(level - terrain.height_at(c.x, c.y), 0.0, 0.0))
	uvs.append(Vector2(0.5, 0.5))
	norms.append(Vector3.UP)
	for r in range(1, rings + 1):
		var f := float(r) / rings
		for s in seg:
			var a := TAU * s / seg
			var rad := (layout.pond_radius(a) + 1.6) * f
			var x := c.x + cos(a) * rad
			var z := c.y + sin(a) * rad
			verts.append(Vector3(x, level, z))
			cols.append(Color(maxf(level - terrain.height_at(x, z), 0.0), 0.0, 0.0))
			uvs.append(Vector2(x, z) * 0.1)
			norms.append(Vector3.UP)
	for s in seg:
		idx.append_array([0, 1 + s, 1 + (s + 1) % seg])
	for r in range(1, rings):
		var a0 := 1 + (r - 1) * seg
		var a1 := 1 + r * seg
		for s in seg:
			var s1 := (s + 1) % seg
			idx.append_array([a0 + s, a1 + s, a0 + s1, a1 + s, a1 + s1, a0 + s1])
	var mi := _mesh_instance("Pond", verts, norms, cols, uvs, idx, kit.water_material(false))
	return mi


func _river(name: String, pts: PackedVector2Array, surface: PackedFloat32Array, width: float, turbulence: float) -> MeshInstance3D:
	var across := 7
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var v := 0.0
	var rows := 0
	var first := -1
	var last := -1
	for k in pts.size():
		var p := pts[k]
		if terrain.is_in_pond(p.x, p.y, -0.8):
			continue
		if maxf(absf(p.x), absf(p.y)) > ForestTerrain.EXTENT - 1.0:
			continue
		if first < 0:
			first = k
		last = k
	if first < 0:
		return MeshInstance3D.new()
	for k in range(first, last + 1):
		var p := pts[k]
		var prev := pts[maxi(k - 1, 0)]
		var next := pts[mini(k + 1, pts.size() - 1)]
		var dir := (next - prev).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var drop := surface[maxi(k - 1, 0)] - surface[mini(k + 1, pts.size() - 1)]
		var grade := drop / maxf(prev.distance_to(next), 0.01)
		var speed := clampf(0.12 + grade * 2.2, 0.1, 1.0)
		var turb := clampf(grade * 3.0 * turbulence + 0.05, 0.0, 1.0)
		if k > first:
			v += p.distance_to(pts[k - 1])
		var w := width * (1.0 + 0.15 * sin(k * 0.37))
		for a in across:
			var t := float(a) / (across - 1) * 2.0 - 1.0
			var q := p + perp * t * w
			var y := surface[k]
			var depth := maxf(y - terrain.height_at(q.x, q.y), 0.0)
			verts.append(Vector3(q.x, y, q.y))
			norms.append(Vector3.UP)
			cols.append(Color(depth, turb, speed))
			uvs.append(Vector2((t * 0.5 + 0.5) * w * 2.0, v))
		rows += 1
	for r in rows - 1:
		for a in across - 1:
			var i0 := r * across + a
			var i1 := i0 + across
			idx.append_array([i0, i1, i0 + 1, i0 + 1, i1, i1 + 1])
	return _mesh_instance(name, verts, norms, cols, uvs, idx, kit.water_material(true))


func _mesh_instance(name: String, verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray,
		uvs: PackedVector2Array, idx: PackedInt32Array, mat: Material) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _lilies() -> Node3D:
	var root := Node3D.new()
	root.name = "Lilies"
	var rng := RandomNumberGenerator.new()
	rng.seed = ForestLayout.SEED + 5
	var pad := _pad_mesh()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = pad
	var xforms: Array[Transform3D] = []
	var c := ForestLayout.POND
	for i in 60:
		var a := rng.randf() * TAU
		var r := ForestLayout.POND_RADIUS * sqrt(rng.randf()) * 0.95
		var p := c + Vector2(cos(a), sin(a)) * r
		var depth := terrain.pond_level - terrain.height_at(p.x, p.y)
		if depth < 0.15 or not terrain.is_in_pond(p.x, p.y, -0.4):
			continue
		# Pads cluster towards the calm western shore.
		if p.x > c.x + 1.5 and rng.randf() < 0.7:
			continue
		var s := rng.randf_range(0.28, 0.5)
		var ok := true
		for x in xforms:
			if Vector2(x.origin.x, x.origin.z).distance_to(p) < (s + x.basis.get_scale().x) * 0.95:
				ok = false
				break
		if not ok:
			continue
		xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, terrain.pond_level + 0.015, p.y)))
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, Color(0.0, 0.3, rng.randf(), 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "LilyPads"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)

	# A few lotus blossoms that glow softly as the light fades.
	var petal := kit.mesh("Petal_3", "lotus")
	var lotus := MultiMesh.new()
	lotus.transform_format = MultiMesh.TRANSFORM_3D
	lotus.use_custom_data = true
	lotus.mesh = petal
	var lx: Array[Transform3D] = []
	var lc: Array[Color] = []
	var blooms := 0
	for x in xforms:
		if rng.randf() > 0.3 or blooms >= 7:
			continue
		blooms += 1
		var centre := x.origin + Vector3(0.0, 0.02, 0.0)
		lotus_points.append(centre)
		var petals := 7
		var phase := rng.randf() * TAU
		for k in petals:
			var a := phase + TAU * k / petals
			var open := deg_to_rad(rng.randf_range(35.0, 50.0))
			var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -open)
			lx.append(Transform3D(b.scaled(Vector3.ONE * 0.55), centre))
			lc.append(Color(0.0, 0.0, rng.randf(), 0.0))
		for k in 5:
			var a := phase + TAU * (k + 0.5) / 5
			var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -deg_to_rad(70.0))
			lx.append(Transform3D(b.scaled(Vector3.ONE * 0.4), centre + Vector3.UP * 0.02))
			lc.append(Color(0.0, 0.0, rng.randf(), 0.0))
	lotus.instance_count = lx.size()
	for i in lx.size():
		lotus.set_instance_transform(i, lx[i])
		lotus.set_instance_custom_data(i, lc[i])
	var lmi := MultiMeshInstance3D.new()
	lmi.name = "Lotus"
	lmi.multimesh = lotus
	lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(lmi)
	return root


func _pad_mesh() -> ArrayMesh:
	## A round pad with a notch, slightly cupped, radius 1.
	var verts := PackedVector3Array([Vector3(0.0, 0.02, 0.0)])
	var cols := PackedColorArray([Color(0.0, 0.0, 0.0)])
	var norms := PackedVector3Array([Vector3.UP])
	var uvs := PackedVector2Array([Vector2(0.5, 0.5)])
	var idx := PackedInt32Array()
	var seg := 18
	var notch := 0.35
	for s in seg + 1:
		var a := notch + (TAU - notch * 2.0) * s / seg
		verts.append(Vector3(cos(a), 0.035, sin(a)))
		cols.append(Color(0.0, 0.0, 0.0))
		norms.append(Vector3(cos(a) * 0.15, 1.0, sin(a) * 0.15).normalized())
		uvs.append(Vector2(cos(a), sin(a)) * 0.5 + Vector2(0.5, 0.5))
	for s in seg:
		idx.append_array([0, s + 2, s + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.42, 0.14)
	mat.roughness = 0.45
	mat.metallic_specular = 0.6
	mat.rim_enabled = true
	mat.rim = 0.4
	mat.backlight_enabled = true
	mat.backlight = Color(0.25, 0.4, 0.1)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.surface_set_material(0, mat)
	return m
