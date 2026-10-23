class_name ForestLife
extends RefCounted
## The forest's small inhabitants: butterflies over the meadow flowers, bees
## working the blossoms, dragonflies hunting over the water, koi turning slow
## circles in the pond, birds wheeling high above the canopy, and leaves
## spinning down wherever trees stand overhead. All of their motion runs in
## the critter and falling-leaf shaders, one draw call per species.

const SH_CRITTER := preload("res://world/forest/shaders/critter.gdshader")
const SH_LEAF := preload("res://world/forest/shaders/falling_leaf.gdshader")

enum Kind { BUTTERFLY, BEE, DRAGONFLY, BIRD, FISH }

var layout: ForestLayout
var terrain: ForestTerrain
var kit: NatureKit
var rng := RandomNumberGenerator.new()
## Where the bees and birds live, for the soundscape.
var bee_homes: Array[Vector3] = []
var bird_centres: Array[Vector3] = []


func _init(p_layout: ForestLayout, p_terrain: ForestTerrain, p_kit: NatureKit) -> void:
	layout = p_layout
	terrain = p_terrain
	kit = p_kit
	rng.seed = ForestLayout.SEED + 313


func build(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Life"
	parent.add_child(root)
	_butterflies(root)
	_bees(root)
	_dragonflies(root)
	_fish(root)
	_birds(root)
	_falling_leaves(root)


func _ground(p: Vector2, lift := 0.0) -> Vector3:
	return Vector3(p.x, terrain.height_at(p.x, p.y) + lift, p.y)


## A dry spot (not in water, not too steep) near `c`.
func _land_near(c: Vector2, spread: float) -> Vector2:
	for i in 12:
		var p := c + Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))
		if terrain.water_distance(p.x, p.y) > 0.8 and terrain.slope_at(p.x, p.y) < 30.0:
			return p
	return c


func _species(root: Node3D, name: String, kind: Kind, mesh: ArrayMesh, homes: Array, customs: Array, params: Dictionary) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SH_CRITTER
	mat.set_shader_parameter("kind", int(kind))
	for k in params:
		mat.set_shader_parameter(k, params[k])
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = homes.size()
	for i in homes.size():
		var h: Array = homes[i]
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * float(h[1])), h[0]))
		mm.set_instance_custom_data(i, customs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-140, -20, -140), Vector3(280, 90, 280))
	root.add_child(mmi)


# ----------------------------------------------------------------------------
# Meshes. Body along +Z, wings along +-X with COLOR.r = 1, fins COLOR.g = 1.

class Shape:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	func v(p: Vector3, n: Vector3, uv: Vector2, c := Color(0, 0, 0)) -> int:
		verts.append(p)
		norms.append(n)
		uvs.append(uv)
		cols.append(c)
		return verts.size() - 1

	func quad(a: int, b: int, c: int, d: int) -> void:
		idx.append_array([a, b, c, a, c, d])

	## A flat wing on each side, spanning `span` along X from the body.
	func wings(span: float, z0: float, z1: float, y := 0.0) -> void:
		for s: float in [-1.0, 1.0]:
			var a := v(Vector3(s * 0.004, y, z0), Vector3.UP, Vector2(0.0, 0.0), Color(1, 0, 0))
			var b := v(Vector3(s * span, y, z0), Vector3.UP, Vector2(1.0, 0.0), Color(1, 0, 0))
			var c := v(Vector3(s * span, y, z1), Vector3.UP, Vector2(1.0, 1.0), Color(1, 0, 0))
			var d := v(Vector3(s * 0.004, y, z1), Vector3.UP, Vector2(0.0, 1.0), Color(1, 0, 0))
			quad(a, b, c, d)

	## A tapered body: a diamond cross-section from tail (z0) to head (z1).
	func body(z0: float, z1: float, r: float, rings := 4, fin_tail := false) -> void:
		var start := verts.size()
		for k in rings + 1:
			var t := float(k) / rings
			var z := lerpf(z0, z1, t)
			var rr := r * sin(PI * clampf(t * 0.9 + 0.08, 0.0, 1.0))
			for s in 4:
				var a := TAU * s / 4.0 + PI * 0.25
				var n := Vector3(cos(a), sin(a), 0.0)
				v(Vector3(n.x * rr, n.y * rr * 0.9, z), n, Vector2(float(s) / 4.0, t), Color(0, 1.0 - t if fin_tail else 0.0, 0))
		for k in rings:
			for s in 4:
				var i0 := start + k * 4 + s
				var i1 := start + k * 4 + (s + 1) % 4
				quad(i0, i1, i1 + 4, i0 + 4)

	func mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m


# ----------------------------------------------------------------------------
# Species

func _butterflies(root: Node3D) -> void:
	var s := Shape.new()
	s.body(-0.03, 0.024, 0.006)
	s.wings(0.085, -0.058, 0.064)
	var homes := []
	var customs := []
	var spots := [
		[ForestLayout.GLADE, 9.0, 12], [ForestLayout.GROVE, 7.0, 6], [ForestLayout.POND + Vector2(-6, 4), 4.0, 3],
		[ForestLayout.SPAWN, 4.0, 3], [Vector2(24.0, 18.0), 5.0, 3], [ForestLayout.OVERLOOK + Vector2(4, 3), 4.0, 2],
	]
	for sp in spots:
		for i in int(sp[2]):
			var p := _land_near(sp[0], sp[1])
			homes.append([_ground(p), rng.randf_range(0.85, 1.2)])
			# Mostly warm oranges and yellows, a few blues and whites.
			var hue: float = [0.0, 0.0, 0.05, -0.06, 0.5, 0.42, 0.12][rng.randi() % 7]
			customs.append(Color(rng.randf(), rng.randf(), rng.randf_range(1.5, 3.5), hue))
	_species(root, "Butterflies", Kind.BUTTERFLY, s.mesh(), homes, customs,
			{"color_a": Color(1.0, 0.58, 0.12), "color_b": Color(0.07, 0.05, 0.04), "flap_rate": 10.0, "flap_angle": 1.15})


func _bees(root: Node3D) -> void:
	var s := Shape.new()
	s.body(-0.018, 0.016, 0.009)
	s.wings(0.018, -0.006, 0.008, 0.008)
	var homes := []
	var customs := []
	for c in [ForestLayout.GLADE, ForestLayout.GLADE + Vector2(-6, -3), ForestLayout.GLADE + Vector2(5, 4), ForestLayout.GROVE, ForestLayout.GROVE + Vector2(4, -5), Vector2(24.0, 18.0)]:
		var hub := _land_near(c, 3.0)
		bee_homes.append(_ground(hub, 0.4))
		for i in 4:
			var p := hub + Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))
			homes.append([_ground(p), rng.randf_range(0.9, 1.15)])
			customs.append(Color(rng.randf(), rng.randf(), rng.randf_range(0.6, 1.4), 0.0))
	_species(root, "Bees", Kind.BEE, s.mesh(), homes, customs,
			{"color_a": Color(0.95, 0.7, 0.12), "color_b": Color(0.08, 0.06, 0.03), "flap_rate": 60.0, "flap_angle": 0.6})


func _dragonflies(root: Node3D) -> void:
	var s := Shape.new()
	s.body(-0.07, 0.02, 0.006, 5)
	s.wings(0.06, -0.012, 0.004)
	s.wings(0.055, 0.006, 0.02)
	var homes := []
	var customs := []
	var level := terrain.pond_level
	for i in 7:
		var a := rng.randf() * TAU
		var p := ForestLayout.POND + Vector2(cos(a), sin(a)) * rng.randf_range(1.0, 4.0)
		homes.append([Vector3(p.x, level, p.y), 1.0])
		customs.append(Color(rng.randf(), rng.randf(), rng.randf_range(1.5, 3.0), [0.0, 0.0, 0.25, -0.15][rng.randi() % 4]))
	var pts := terrain.stream_points
	for i in 5:
		var p := pts[rng.randi_range(8, pts.size() - 20)]
		homes.append([Vector3(p.x, terrain.height_at(p.x, p.y) + 0.3, p.y), 1.0])
		customs.append(Color(rng.randf(), rng.randf(), rng.randf_range(1.0, 2.0), 0.0))
	_species(root, "Dragonflies", Kind.DRAGONFLY, s.mesh(), homes, customs,
			{"color_a": Color(0.15, 0.55, 0.85), "color_b": Color(0.05, 0.1, 0.12), "flap_rate": 38.0, "flap_angle": 0.45})


func _fish(root: Node3D) -> void:
	var s := Shape.new()
	s.body(-0.2, 0.17, 0.05, 6, true)
	# Tail fin, vertical, flagged as fin so it swishes hardest.
	var a := s.v(Vector3(0.0, 0.0, -0.18), Vector3.RIGHT, Vector2(0.5, 0.0), Color(0, 1, 0))
	var b := s.v(Vector3(0.0, 0.07, -0.3), Vector3.RIGHT, Vector2(0.5, 0.1), Color(0, 1, 0))
	var c := s.v(Vector3(0.0, -0.07, -0.3), Vector3.RIGHT, Vector2(0.5, 0.1), Color(0, 1, 0))
	s.idx.append_array([a, b, c])
	var homes := []
	var customs := []
	var level := terrain.pond_level
	for i in 9:
		homes.append([Vector3(ForestLayout.POND.x, level - rng.randf_range(0.3, 0.55), ForestLayout.POND.y), rng.randf_range(0.8, 1.25)])
		customs.append(Color(rng.randf(), rng.randf(), rng.randf_range(1.4, 3.6), [0.0, 0.0, 0.06, -0.04][rng.randi() % 4]))
	_species(root, "Koi", Kind.FISH, s.mesh(), homes, customs,
			{"color_a": Color(1.0, 0.42, 0.08), "color_b": Color(0.1, 0.1, 0.1)})


func _birds(root: Node3D) -> void:
	var s := Shape.new()
	s.body(-0.12, 0.1, 0.035)
	s.wings(0.28, -0.05, 0.06)
	var homes := []
	var customs := []
	for flock in 3:
		var centre := Vector3(rng.randf_range(-25, 25), rng.randf_range(24, 34), rng.randf_range(-30, 20))
		bird_centres.append(centre)
		var radius := rng.randf_range(22.0, 38.0)
		var phase := rng.randf()
		for i in rng.randi_range(4, 7):
			homes.append([centre + Vector3(rng.randf_range(-3, 3), rng.randf_range(-1.5, 1.5), rng.randf_range(-3, 3)), rng.randf_range(0.85, 1.1)])
			customs.append(Color(fposmod(phase + rng.randf_range(-0.025, 0.025), 1.0), 0.5 + rng.randf_range(-0.05, 0.05), radius + rng.randf_range(-2.0, 2.0), 0.0))
	_species(root, "Birds", Kind.BIRD, s.mesh(), homes, customs,
			{"color_a": Color(0.35, 0.3, 0.27), "color_b": Color(0.12, 0.1, 0.1), "flap_rate": 11.0, "flap_angle": 0.75})


# ----------------------------------------------------------------------------
# Falling leaves

func _falling_leaves(root: Node3D) -> void:
	var img := Image.create(ForestTerrain.N, ForestTerrain.N, false, Image.FORMAT_R8)
	for z in ForestTerrain.N:
		for x in ForestTerrain.N:
			img.set_pixel(x, z, Color(terrain.shade[z * ForestTerrain.N + x], 0, 0))
	var tex := ImageTexture.create_from_image(img)
	var mat := ShaderMaterial.new()
	mat.shader = SH_LEAF
	mat.set_shader_parameter("shade_map", tex)
	mat.set_shader_parameter("map_extent", ForestTerrain.EXTENT)
	kit.wind_materials.append(mat)
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.09)
	q.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = 150
	for i in mm.instance_count:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(rng.randf() * 26.0, rng.randf() * 11.0, rng.randf() * 26.0)))
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "FallingLeaves"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 150, 400))
	root.add_child(mmi)
