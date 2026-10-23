class_name ForestScatter
extends RefCounted
## Decides where every tree, rock, flower and blade of grass goes, then packs
## them into chunked MultiMeshes (few draw calls, per-chunk culling and
## distance cut-off) with per-instance colour/phase data for the shaders.
##
## INSTANCE_CUSTOM conventions:
##   trees/bushes: r hue jitter, g brightness, b wind phase, a magic tint
##   plants/grass: r canopy shade, g wetness, b random, a unused
##   rocks:        r moss bias, g brightness

const CHUNK := {"tree": 30.0, "far": 45.0, "rock": 30.0, "bush": 20.0, "plant": 12.0, "grass": 10.0, "small": 12.0}
const VIS_END := {"tree": 0.0, "far": 0.0, "rock": 0.0, "bush": 70.0, "plant": 50.0, "grass": 36.0, "small": 34.0}
const SHADOWS := {"tree": true, "far": false, "rock": true, "bush": true, "plant": false, "grass": false, "small": false}

var layout: ForestLayout
var terrain: ForestTerrain
var kit: NatureKit
var rng := RandomNumberGenerator.new()
var trees: Array[Dictionary] = []          # {pos: Vector2, r: float (spacing), trunk: float, canopy: float}
var colliders: Array[Dictionary] = []      # {shape: Shape3D, xform: Transform3D}
var hero := {}                             # named landmark data for FX (elder canopy etc.)
var _batches := {}
var _proc_pool := {}
var _patch := FastNoiseLite.new()
var _hash := {}                            # 8 m buckets of tree indices


func _init(p_layout: ForestLayout, p_terrain: ForestTerrain, p_kit: NatureKit) -> void:
	layout = p_layout
	terrain = p_terrain
	kit = p_kit
	rng.seed = ForestLayout.SEED * 31 + 7
	_patch.seed = ForestLayout.SEED + 99
	_patch.frequency = 0.09
	_patch.fractal_octaves = 2


# ----------------------------------------------------------------------------
# Public

func plan() -> void:
	_place_hero_trees()
	_place_forest()
	_place_outer_belt()
	for t in trees:
		terrain.paint_shade(t.pos, t.canopy, t.get("shade", 0.55))


## Everything that depends on the final shade map comes after the terrain mesh
## colours are baked, so call this second.
func populate() -> void:
	_place_rocks()
	_place_logs()
	_place_path_stones()
	_place_undergrowth()
	_place_grass()


func build(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Vegetation"
	parent.add_child(root)
	var keys := _batches.keys()
	keys.sort()
	for key in keys:
		var b: Dictionary = _batches[key]
		var data: PackedFloat32Array = b.data
		var count := data.size() / 16
		if count == 0:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = b.mesh
		mm.instance_count = count
		mm.buffer = data
		var mmi := MultiMeshInstance3D.new()
		mmi.name = key
		mmi.multimesh = mm
		var group: String = b.group
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if SHADOWS[group] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if VIS_END[group] > 0.0:
			mmi.visibility_range_end = VIS_END[group]
			mmi.visibility_range_end_margin = 4.0
		root.add_child(mmi)

	var body := StaticBody3D.new()
	body.name = "PropColliders"
	for c in colliders:
		var cs := CollisionShape3D.new()
		cs.shape = c.shape
		cs.transform = c.xform
		body.add_child(cs)
	parent.add_child(body)


# ----------------------------------------------------------------------------
# Instance batching

func add(mesh: Mesh, xform: Transform3D, custom: Color, group: String) -> void:
	var size: float = CHUNK[group]
	var cx := int(floor((xform.origin.x + 200.0) / size))
	var cz := int(floor((xform.origin.z + 200.0) / size))
	var key := "%s_%s_%d_%d" % [group, mesh.resource_name if mesh.resource_name != "" else str(mesh.get_instance_id()), cx, cz]
	if not _batches.has(key):
		_batches[key] = {"mesh": mesh, "group": group, "data": PackedFloat32Array()}
	var d: PackedFloat32Array = _batches[key].data
	var b := xform.basis
	var o := xform.origin
	d.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z,
		custom.r, custom.g, custom.b, custom.a])


func _named(model: String, variant: String = "") -> ArrayMesh:
	var m := kit.mesh(model, variant)
	if m.resource_name == "":
		m.resource_name = model + ("_" + variant if variant != "" else "")
	return m


func _ground_xform(x: float, z: float, scale: float, yaw: float, sink: float = 0.0, tilt: float = 0.0) -> Transform3D:
	var y := terrain.height_at(x, z) - sink * scale
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
	if tilt > 0.0:
		var n := terrain.normal_at(x, z)
		var axis := Vector3.UP.cross(n)
		if axis.length() > 0.001:
			basis = Basis(axis.normalized(), Vector3.UP.angle_to(n) * tilt) * basis
	return Transform3D(basis, Vector3(x, y, z))


# ----------------------------------------------------------------------------
# Trees

const KIT_TREES := {
	"common": ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5"],
	"pine": ["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"],
	"twisted": ["TwistedTree_1", "TwistedTree_2", "TwistedTree_3", "TwistedTree_4", "TwistedTree_5"],
}
# trunk radius, canopy radius, spacing radius (at scale 1)
const KIT_DIMS := {"common": [0.32, 2.6, 2.6], "pine": [0.3, 2.0, 2.2], "twisted": [0.7, 4.8, 5.5]}


func _proc_variant(style: ProcTree.Style, index: int) -> Dictionary:
	var key := "%d_%d" % [style, index]
	if _proc_pool.has(key):
		return _proc_pool[key]
	var t := ProcTree.grow(style, ForestLayout.SEED * 1000 + style * 100 + index)
	var mesh: ArrayMesh = t.mesh
	mesh.resource_name = "Proc_%s_%d" % [ProcTree.Style.keys()[style], index]
	var palette: String = ["blossom", "willow", "sentinel", "far"][style]
	var bark := "Bark_TwistedTree"
	if style == ProcTree.Style.SENTINEL:
		bark = "Bark_Pale"
	elif style == ProcTree.Style.FAR:
		bark = "Bark_NormalTree"
	mesh.surface_set_material(0, kit.bark_material(bark))
	var stiff := 0.8 if style == ProcTree.Style.WILLOW else 1.0
	var tex := kit.texture("Leaves_NormalTree")
	mesh.surface_set_material(1, kit.canopy_material(palette, tex, t.canopy_center, t.canopy_radius, stiff))
	_proc_pool[key] = t
	return t


func _tree_custom(magic: float) -> Color:
	return Color(rng.randf(), rng.randf(), rng.randf(), clampf(magic, 0.0, 1.0))


func _spot_free(p: Vector2, r: float) -> bool:
	var cx := int(floor(p.x / 8.0))
	var cz := int(floor(p.y / 8.0))
	for oz in range(-2, 3):
		for ox in range(-2, 3):
			var k := Vector2i(cx + ox, cz + oz)
			if not _hash.has(k):
				continue
			for i: int in _hash[k]:
				var t: Dictionary = trees[i]
				if p.distance_to(t.pos) < (r + t.r) * 0.62:
					return false
	return true


func _register(pos: Vector2, spacing: float, trunk: float, canopy: float, collide: bool, shade: float = 0.55) -> void:
	trees.append({"pos": pos, "r": spacing, "trunk": trunk, "canopy": canopy, "shade": shade})
	var k := Vector2i(int(floor(pos.x / 8.0)), int(floor(pos.y / 8.0)))
	if not _hash.has(k):
		_hash[k] = []
	_hash[k].append(trees.size() - 1)
	if collide and trunk > 0.0 and maxf(absf(pos.x), absf(pos.y)) < ForestLayout.HALF + 2.0:
		var shape := CylinderShape3D.new()
		shape.radius = trunk
		shape.height = 6.0
		var y := terrain.height_at(pos.x, pos.y)
		colliders.append({"shape": shape, "xform": Transform3D(Basis(), Vector3(pos.x, y + 2.5, pos.y))})


func plant_kit_tree(kind: String, model: String, pos: Vector2, scale: float, magic: float, yaw: float = NAN) -> void:
	var dims: Array = KIT_DIMS[kind]
	if is_nan(yaw):
		yaw = rng.randf() * TAU
	var xf := _ground_xform(pos.x, pos.y, scale, yaw, 0.05)
	# Gentle lean adds a lot of life to repeated models.
	xf.basis = Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.06)) * xf.basis
	add(_named(model), xf, _tree_custom(magic), "tree")
	_register(pos, dims[2] * scale, dims[0] * scale, dims[1] * scale, true)


func plant_proc_tree(style: ProcTree.Style, variant: int, pos: Vector2, scale: float, magic: float, group: String = "tree") -> Dictionary:
	var t := _proc_variant(style, variant)
	var xf := _ground_xform(pos.x, pos.y, scale, rng.randf() * TAU, 0.0)
	add(t.mesh, xf, _tree_custom(magic), group)
	var canopy: float = t.canopy_radius * scale
	_register(pos, canopy * 0.9, t.trunk_radius * scale * 1.2, canopy, group == "tree")
	return t


func _place_hero_trees() -> void:
	# The Elder: a vast twisted spirit tree, lilac-crowned, the heart of the glade.
	var e := ForestLayout.ELDER
	var elder_scale := 1.55
	var xf := _ground_xform(e.x, e.y, elder_scale, deg_to_rad(200.0), 0.05)
	add(_named("TwistedTree_3"), xf, Color(0.5, 0.75, 0.3, 0.82), "tree")
	_register(e, 7.0, 1.1, 8.5, true, 0.75)
	var crown := xf * Vector3(1.2, 10.5, -0.8)
	hero["elder_crown"] = crown
	hero["elder_base"] = xf.origin

	# Framing trees around the glade.
	plant_kit_tree("common", "CommonTree_2", Vector2(9.5, 19.0), 1.35, 0.0, 0.4)
	plant_kit_tree("common", "CommonTree_4", Vector2(-16.0, 15.0), 1.3, 0.1, 2.1)
	plant_kit_tree("common", "CommonTree_1", Vector2(13.5, 13.0), 1.2, 0.0, 1.3)
	plant_proc_tree(ProcTree.Style.BLOSSOM, 0, Vector2(-14.0, 3.0), 1.15, 0.0)
	plant_proc_tree(ProcTree.Style.BLOSSOM, 1, Vector2(10.0, 2.5), 1.0, 0.35)

	# Weeping willows trailing their curtains over the pond.
	plant_proc_tree(ProcTree.Style.WILLOW, 0, Vector2(4.2, -23.0), 1.25, 0.25)
	plant_proc_tree(ProcTree.Style.WILLOW, 1, Vector2(18.5, -19.5), 1.15, 0.6)
	plant_proc_tree(ProcTree.Style.WILLOW, 2, Vector2(20.5, -5.0), 1.0, 0.4)

	# Sentinels and the silver snag guarding the overlook.
	plant_proc_tree(ProcTree.Style.SENTINEL, 0, Vector2(-17.5, -40.0), 1.1, 0.0)
	plant_proc_tree(ProcTree.Style.SENTINEL, 1, Vector2(-4.5, -42.5), 1.0, 0.2)
	var d := ForestLayout.DEAD_TREE
	var dx := _ground_xform(d.x, d.y, 0.9, 0.7, 0.05)
	add(_named("DeadTree_1", "pale"), dx, Color(0.5, 0.5, 0.5, 0.0), "tree")
	_register(d, 4.5, 0.55, 2.0, true, 0.2)

	# A grandmother tree for the hollow, crown tinged with teal.
	plant_kit_tree("twisted", "TwistedTree_5", Vector2(38.0, -16.0), 1.15, 0.0, 1.0)
	plant_kit_tree("twisted", "TwistedTree_1", Vector2(-38.0, 8.0), 1.05, 0.0, 4.0)

	# Heart of the blossom grove.
	plant_proc_tree(ProcTree.Style.BLOSSOM, 2, ForestLayout.GROVE, 1.3, 0.0)
	plant_proc_tree(ProcTree.Style.BLOSSOM, 3, ForestLayout.GROVE + Vector2(6.5, -4.0), 1.1, 0.5)


func _clearance(p: Vector2) -> float:
	## 0 where trees must not grow, 1 where the forest is free to fill in.
	var c := 1.0
	c *= ForestLayout.sstep(ForestLayout.GLADE_RADIUS * 0.85, ForestLayout.GLADE_RADIUS * 1.55, p.distance_to(ForestLayout.GLADE))
	c *= ForestLayout.sstep(1.8, 3.6, terrain.path_distance(p.x, p.y))
	c *= ForestLayout.sstep(0.8, 3.0, terrain.water_distance(p.x, p.y))
	c *= ForestLayout.sstep(ForestLayout.OVERLOOK_RADIUS + 1.0, ForestLayout.OVERLOOK_RADIUS + 4.0, p.distance_to(ForestLayout.OVERLOOK))
	c *= ForestLayout.sstep(2.5, 6.0, p.distance_to(ForestLayout.SPAWN))
	# Keep the sight line from the spawn to the Elder open.
	c *= ForestLayout.sstep(2.0, 5.0, _seg_dist(p, ForestLayout.SPAWN, ForestLayout.ELDER))
	return c


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Is the point inside the overlook's sunset view, where tall trees would
## block the vista?
func _in_vista(p: Vector2) -> bool:
	var v := p - ForestLayout.OVERLOOK
	if v.length() > 46.0 or v.length() < 0.5:
		return false
	var sun := Vector2(ForestAtmosphere.SUN_TOWARDS.x, ForestAtmosphere.SUN_TOWARDS.z).normalized()
	return v.normalized().dot(sun.lerp(Vector2(0.0, 1.0), 0.35).normalized()) > 0.78


func _place_forest() -> void:
	var pts := _poisson(Rect2(-ForestLayout.HALF - 4.0, -ForestLayout.HALF - 4.0, ForestLayout.HALF * 2.0 + 8.0, ForestLayout.HALF * 2.0 + 8.0), 3.1)
	var counters := {"blossom": 4, "willow": 3, "sentinel": 2}
	for p in pts:
		var clear := _clearance(p)
		if clear <= 0.02:
			continue
		var ridge := ForestLayout.sstep(-20.0, -32.0, p.y)
		var hollow := 1.0 - ForestLayout.sstep(9.0, 20.0, p.distance_to(ForestLayout.HOLLOW))
		var grove := 1.0 - ForestLayout.sstep(8.0, 17.0, p.distance_to(ForestLayout.GROVE))
		var pond := 1.0 - ForestLayout.sstep(9.0, 14.0, p.distance_to(ForestLayout.POND))
		var edge := ForestLayout.sstep(36.0, 48.0, ForestLayout.square_dist(p.x, p.y))
		# Density: airy in the middle of the valley, thick towards the rim.
		var density := clear * lerpf(0.42, 0.95, maxf(edge, maxf(hollow * 0.9, ridge * 0.6)))
		density *= 0.7 + 0.6 * clampf(_patch.get_noise_2d(p.x * 0.4, p.y * 0.4) + 0.5, 0.0, 1.0)
		if rng.randf() > density:
			continue

		var w := {
			"common": 0.5, "twisted": 0.1, "pine": 0.16, "sentinel": 0.06, "blossom": 0.06,
		}
		w.pine += ridge * 0.6 + hollow * 0.7
		w.sentinel += ridge * 0.4
		w.common -= ridge * 0.25
		w.blossom += grove * 1.4 + pond * 0.15
		w.common += grove * 0.4
		w.twisted += hollow * 0.2 + edge * 0.1
		w["willow"] = pond * 0.8
		var kind := _pick(w)
		var vista := _in_vista(p)
		if vista and p.distance_to(ForestLayout.OVERLOOK) < 24.0:
			continue
		if vista and kind in ["twisted", "sentinel", "pine", "willow"]:
			kind = "common"

		var magic := grove * rng.randf_range(0.7, 1.0)
		if kind == "pine":
			magic = hollow * rng.randf_range(0.2, 0.7)
		elif kind == "twisted":
			magic = rng.randf_range(0.0, 0.25) + hollow * 0.3
		elif kind == "common":
			magic = maxf(magic, rng.randf_range(-0.6, 0.35))

		match kind:
			"blossom", "willow", "sentinel":
				var style: ProcTree.Style = {"blossom": ProcTree.Style.BLOSSOM, "willow": ProcTree.Style.WILLOW, "sentinel": ProcTree.Style.SENTINEL}[kind]
				var pool: int = {"blossom": 8, "willow": 4, "sentinel": 5}[kind]
				var idx := rng.randi() % pool
				var t := _proc_variant(style, idx)
				var s := rng.randf_range(0.85, 1.2)
				if not _spot_free(p, t.canopy_radius * s * 0.9):
					continue
				plant_proc_tree(style, idx, p, s, magic if kind != "blossom" else rng.randf_range(0.0, 0.6))
			_:
				var dims: Array = KIT_DIMS[kind]
				var s := rng.randf_range(0.9, 1.35)
				if kind == "twisted":
					s = rng.randf_range(0.75, 1.05)
				if vista:
					s *= 0.8
				if not _spot_free(p, dims[2] * s):
					continue
				var models: Array = KIT_TREES[kind]
				plant_kit_tree(kind, models[rng.randi() % models.size()], p, s, magic)
	counters.clear()


func _place_outer_belt() -> void:
	## A dense wall of trees beyond the playable edge so the valley feels
	## endless: kit trees close in, cheap procedural silhouettes further out.
	var pts := _poisson(Rect2(-95.0, -95.0, 190.0, 190.0), 3.6)
	for p in pts:
		var d := ForestLayout.square_dist(p.x, p.y)
		if d < ForestLayout.HALF + 1.0:
			continue
		if terrain.water_distance(p.x, p.y) < 2.5 or terrain.path_distance(p.x, p.y) < 2.0:
			continue
		if _in_vista(p) and d < 64.0:
			continue
		if d < 64.0:
			var kind := "pine" if rng.randf() < 0.45 else "common"
			var dims: Array = KIT_DIMS[kind]
			var s := rng.randf_range(1.0, 1.5)
			if not _spot_free(p, dims[2] * s):
				continue
			var models: Array = KIT_TREES[kind]
			plant_kit_tree(kind, models[rng.randi() % models.size()], p, s, rng.randf_range(-0.5, 0.3))
		elif rng.randf() < 0.85:
			var t := _proc_variant(ProcTree.Style.FAR, rng.randi() % 5)
			var s := rng.randf_range(1.0, 1.6)
			var xf := _ground_xform(p.x, p.y, s, rng.randf() * TAU, 0.0)
			add(t.mesh, xf, _tree_custom(rng.randf_range(0.0, 0.25)), "far")


func _pick(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += maxf(weights[k], 0.0)
	var r := rng.randf() * total
	for k in weights:
		r -= maxf(weights[k], 0.0)
		if r <= 0.0:
			return k
	return weights.keys()[0]


## Bridson Poisson-disk sampling: natural, evenly spread points.
func _poisson(rect: Rect2, r: float) -> PackedVector2Array:
	var cell := r / sqrt(2.0)
	var gw := int(ceil(rect.size.x / cell))
	var gh := int(ceil(rect.size.y / cell))
	var grid := PackedInt32Array()
	grid.resize(gw * gh)
	grid.fill(-1)
	var pts := PackedVector2Array()
	var active: Array[int] = []
	var first := rect.position + rect.size * Vector2(rng.randf(), rng.randf())
	pts.append(first)
	active.append(0)
	grid[int((first.y - rect.position.y) / cell) * gw + int((first.x - rect.position.x) / cell)] = 0
	while not active.is_empty():
		var ai := rng.randi() % active.size()
		var base := pts[active[ai]]
		var found := false
		for attempt in 20:
			var a := rng.randf() * TAU
			var d := r * (1.0 + rng.randf())
			var c := base + Vector2(cos(a), sin(a)) * d
			if not rect.has_point(c):
				continue
			var gx := int((c.x - rect.position.x) / cell)
			var gy := int((c.y - rect.position.y) / cell)
			var ok := true
			for oy in range(maxi(gy - 2, 0), mini(gy + 3, gh)):
				for ox in range(maxi(gx - 2, 0), mini(gx + 3, gw)):
					var j := grid[oy * gw + ox]
					if j >= 0 and pts[j].distance_squared_to(c) < r * r:
						ok = false
						break
				if not ok:
					break
			if ok:
				pts.append(c)
				active.append(pts.size() - 1)
				grid[gy * gw + gx] = pts.size() - 1
				found = true
				break
		if not found:
			active.remove_at(ai)
	return pts


# ----------------------------------------------------------------------------
# Rocks and props

func _rock(model: String, x: float, z: float, scale: float, sink: float, collide: bool, group: String = "rock") -> void:
	var yaw := rng.randf() * TAU
	var xf := _ground_xform(x, z, scale, yaw, sink, 0.6)
	xf.basis = Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.25)) * xf.basis
	var mesh := _named(model)
	add(mesh, xf, Color(rng.randf(), rng.randf(), 0.0, 0.0), group)
	if collide:
		colliders.append({"shape": _convex(mesh), "xform": xf})


var _convex_cache := {}


func _convex(mesh: ArrayMesh) -> Shape3D:
	if not _convex_cache.has(mesh):
		_convex_cache[mesh] = mesh.create_convex_shape(true, true)
	return _convex_cache[mesh]


func _place_rocks() -> void:
	var big := ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"]
	# Outcrops break through the steep ridge face.
	for i in 700:
		var x := rng.randf_range(-48.0, 48.0)
		var z := rng.randf_range(-48.0, -14.0)
		var slope := terrain.slope_at(x, z)
		if slope < 20.0 or terrain.path_distance(x, z) < 2.2 or terrain.water_distance(x, z) < 1.0:
			continue
		if rng.randf() > (slope - 18.0) / 30.0:
			continue
		if Vector2(x, z).distance_to(ForestLayout.OVERLOOK) < ForestLayout.OVERLOOK_RADIUS + 1.0:
			continue
		var s := rng.randf_range(0.8, 2.2) * (1.0 + (slope - 20.0) / 40.0)
		_rock(big[rng.randi() % 3], x, z, s, 0.35, true)
	# The overlook: a crescent of boulders behind the viewpoint to lean on.
	var o := ForestLayout.OVERLOOK
	for k in 7:
		var a := deg_to_rad(lerpf(-160.0, -20.0, k / 6.0)) + rng.randf_range(-0.1, 0.1)
		var r := ForestLayout.OVERLOOK_RADIUS + rng.randf_range(0.4, 1.6)
		_rock(big[rng.randi() % 3], o.x + cos(a) * r, o.y + sin(a) * r, rng.randf_range(0.9, 1.6), 0.3, true)
	# Boulders tumbling beside the creek cascade, a few right in the water.
	var creek := terrain.creek_points
	for k in range(0, creek.size(), 3):
		var p := creek[k]
		if p.distance_to(ForestLayout.POND) < ForestLayout.POND_RADIUS + 1.0:
			continue
		if maxf(absf(p.x), absf(p.y)) > 58.0:
			continue
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var dir := (creek[mini(k + 1, creek.size() - 1)] - creek[maxi(k - 1, 0)]).normalized()
		var perp := Vector2(-dir.y, dir.x) * side
		if rng.randf() < 0.75:
			var q := p + perp * rng.randf_range(1.0, 2.2)
			_rock(big[rng.randi() % 3], q.x, q.y, rng.randf_range(0.45, 0.95), 0.35, true)
		if rng.randf() < 0.3:
			var q := p + perp * rng.randf_range(0.0, 0.4)
			_rock(big[rng.randi() % 3], q.x, q.y, rng.randf_range(0.22, 0.38), 0.3, false)
	# Stones along the stream banks.
	var stream := terrain.stream_points
	for k in range(0, stream.size(), 4):
		if rng.randf() > 0.45:
			continue
		var p := stream[k]
		if maxf(absf(p.x), absf(p.y)) > 56.0:
			continue
		var dir := (stream[mini(k + 1, stream.size() - 1)] - stream[maxi(k - 1, 0)]).normalized()
		var perp := Vector2(-dir.y, dir.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var q := p + perp * rng.randf_range(1.3, 2.4)
		_rock(big[rng.randi() % 3], q.x, q.y, rng.randf_range(0.3, 0.7), 0.35, true)
	# Pond shore boulders.
	for k in 9:
		var a := TAU * k / 9.0 + rng.randf_range(-0.2, 0.2)
		var r := layout.pond_radius(a) + rng.randf_range(0.4, 1.4)
		var q := ForestLayout.POND + Vector2(cos(a), sin(a)) * r
		if terrain.path_distance(q.x, q.y) < 1.5 or terrain.water_distance(q.x, q.y) > 2.0 and rng.randf() < 0.5:
			continue
		_rock(big[rng.randi() % 3], q.x, q.y, rng.randf_range(0.35, 0.8), 0.35, true)
	# Lone meadow boulders: the sitting rock in the glade, and a few others.
	_rock("Rock_Medium_2", 5.5, 9.0, 1.15, 0.3, true)
	_rock("Rock_Medium_3", -9.5, -1.0, 0.8, 0.35, true)
	_rock("Rock_Medium_1", 24.0, 22.0, 1.3, 0.35, true)
	_rock("Rock_Medium_3", -27.0, -6.0, 1.6, 0.35, true)
	_rock("Rock_Medium_1", -33.0, 30.0, 1.1, 0.35, true)
	_rock("Rock_Medium_2", 29.0, -18.0, 1.4, 0.35, true)
	# Forest floor scatter.
	for i in 140:
		var x := rng.randf_range(-48.0, 48.0)
		var z := rng.randf_range(-48.0, 48.0)
		if terrain.path_distance(x, z) < 1.8 or terrain.water_distance(x, z) < 0.5 or _clearance(Vector2(x, z)) < 0.3:
			continue
		_rock(big[rng.randi() % 3], x, z, rng.randf_range(0.25, 0.7), 0.4, rng.randf() < 0.5)


func _place_logs() -> void:
	# Fallen trunks to sit on at the overlook, and an old mossy log in the hollow.
	var o := ForestLayout.OVERLOOK
	_log(o + Vector2(-2.2, 1.6), deg_to_rad(65.0), 3.2, 0.32)
	_log(o + Vector2(2.4, 1.2), deg_to_rad(-60.0), 2.8, 0.3)
	_log(ForestLayout.HOLLOW + Vector2(-3.0, 4.0), deg_to_rad(20.0), 6.5, 0.5)
	_log(ForestLayout.GROVE + Vector2(5.0, 5.0), deg_to_rad(-35.0), 4.5, 0.38)
	_log(Vector2(-24.0, -14.0), deg_to_rad(80.0), 5.0, 0.42)


var _log_mesh: ArrayMesh


func _log(p: Vector2, yaw: float, length: float, radius: float) -> void:
	if _log_mesh == null:
		_log_mesh = _make_log_mesh()
	var y := terrain.height_at(p.x, p.y)
	var dir := Vector3(cos(yaw), 0.0, sin(yaw))
	var a := Vector2(p.x, p.y) - Vector2(dir.x, dir.z) * length * 0.5
	var b := Vector2(p.x, p.y) + Vector2(dir.x, dir.z) * length * 0.5
	var ya := terrain.height_at(a.x, a.y)
	var yb := terrain.height_at(b.x, b.y)
	var along := Vector3(b.x - a.x, yb - ya, b.y - a.y).normalized()
	var side := along.cross(Vector3.UP).normalized()
	var up := side.cross(along).normalized()
	var basis := Basis(side * radius, up * radius, along * length)
	var origin := Vector3(p.x, (ya + yb) * 0.5 + radius * 0.65, p.y)
	add(_log_mesh, Transform3D(basis, origin), Color(rng.randf(), rng.randf(), 0.5, 0.0), "rock")
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = length
	colliders.append({"shape": shape, "xform": Transform3D(Basis(side, along, up).orthonormalized(), origin)})
	# Shelf fungi and mushrooms colonise the log.
	for k in rng.randi_range(2, 4):
		var t := rng.randf_range(-0.4, 0.4)
		var q := origin + along * length * t + side * radius * (1.0 if k % 2 == 0 else -1.0) * 0.9
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.4, 0.7)), q - Vector3.UP * radius * 0.4)
		add(_named("Mushroom_Laetiporus"), xf, Color(rng.randf(), rng.randf(), rng.randf(), 0.0), "small")


func _make_log_mesh() -> ArrayMesh:
	## Unit log along +Z (radius 1, length 1) with knobbly bark and pale ends.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 10
	var rings := 6
	for r in rings:
		for s in sides:
			for corner in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
				var ss: int = s + corner[0]
				var rr: int = r + corner[1]
				var a := TAU * ss / sides
				var z := float(rr) / rings - 0.5
				var bulge := 1.0 + 0.06 * sin(a * 3.0 + rr * 1.7)
				var n := Vector3(cos(a), sin(a), 0.0)
				st.set_normal(n)
				st.set_tangent(Plane(Vector3(-sin(a), cos(a), 0.0), 1.0))
				st.set_uv(Vector2(float(ss) / sides * 2.0, z * 3.0))
				st.set_color(Color(0.8, 0.8, 0.8))
				st.add_vertex(Vector3(n.x * bulge, n.y * bulge, z))
	var m := st.commit()
	m.surface_set_material(0, kit.bark_material("Bark_DeadTree"))
	m.resource_name = "FallenLog"
	return m


func _place_path_stones() -> void:
	var round := ["RockPath_Round_Small_1", "RockPath_Round_Small_2", "RockPath_Round_Small_3"]
	# Stepping stones across the stream where the hollow path fords it.
	var c := ForestLayout.STREAM_CROSSING
	var k := _nearest_index(terrain.stream_points, c)
	var p0 := terrain.stream_points[k]
	var dir := (terrain.stream_points[k + 1] - terrain.stream_points[k - 1]).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var surf := terrain.stream_surface[k]
	for i in 5:
		var t := lerpf(-1.9, 1.9, i / 4.0)
		var q := p0 + perp * t + dir * rng.randf_range(-0.15, 0.15)
		var s := rng.randf_range(0.75, 0.9)
		var y := maxf(terrain.height_at(q.x, q.y), surf + 0.06)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, 1.4, s)), Vector3(q.x, y - 0.05, q.y))
		var mesh := _named(round[i % 3])
		add(mesh, xf, Color(0.2, 0.5, 0, 0), "rock")
		var shape := CylinderShape3D.new()
		shape.radius = 0.5 * s
		shape.height = 0.6
		colliders.append({"shape": shape, "xform": Transform3D(Basis(), Vector3(q.x, y - 0.2, q.y))})
	# Flagstones on the overlook and along the last climb.
	var o := ForestLayout.OVERLOOK
	var sq := ["RockPath_Square_Small_1", "RockPath_Square_Small_2", "RockPath_Square_Small_3"]
	for i in 14:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 3.2
		var q := o + Vector2(cos(a), sin(a)) * r
		var xf := _ground_xform(q.x, q.y, rng.randf_range(0.8, 1.1), rng.randf() * TAU, 0.06, 1.0)
		add(_named(sq[rng.randi() % 3]), xf, Color(0.3, 0.5, 0, 0), "small")
	# Occasional stones set into the footpaths.
	for pts in terrain.path_points:
		for j in range(0, pts.size(), 3):
			if rng.randf() > 0.32:
				continue
			var q := pts[j] + Vector2(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.7, 0.7))
			if terrain.water_distance(q.x, q.y) < 0.3 or maxf(absf(q.x), absf(q.y)) > 52.0:
				continue
			var xf := _ground_xform(q.x, q.y, rng.randf_range(0.45, 0.75), rng.randf() * TAU, 0.05, 1.0)
			add(_named(round[rng.randi() % 3]), xf, Color(0.0, rng.randf(), 0, 0), "small")
			# Pebbles kicked to the path verge.
			if rng.randf() < 0.6:
				var e := pts[j] + Vector2(rng.randf_range(-1.6, 1.6), rng.randf_range(-1.6, 1.6))
				var peb := ["Pebble_Round_1", "Pebble_Round_2", "Pebble_Round_3", "Pebble_Square_1", "Pebble_Square_2"]
				add(_named(peb[rng.randi() % peb.size()]), _ground_xform(e.x, e.y, rng.randf_range(0.6, 1.3), rng.randf() * TAU, 0.02, 1.0), Color(rng.randf(), rng.randf(), 0, 0), "small")


static func _nearest_index(pts: PackedVector2Array, p: Vector2) -> int:
	var best := 1
	var bd := INF
	for i in range(1, pts.size() - 1):
		var d := pts[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


# ----------------------------------------------------------------------------
# Undergrowth

func _plant_custom(x: float, z: float) -> Color:
	var wet := 1.0 - ForestLayout.sstep(-0.2, 2.2, terrain.water_distance(x, z))
	return Color(terrain.shade_at(x, z), wet, rng.randf(), 0.0)


func _near_tree(p: Vector2, within: float) -> Dictionary:
	var cx := int(floor(p.x / 8.0))
	var cz := int(floor(p.y / 8.0))
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var k := Vector2i(cx + ox, cz + oz)
			if not _hash.has(k):
				continue
			for i: int in _hash[k]:
				var t: Dictionary = trees[i]
				if p.distance_to(t.pos) < t.trunk + within:
					return t
	return {}


func _place_undergrowth() -> void:
	var step := 0.9
	var n := int(ForestLayout.HALF * 2.0 / step) + 8
	for iz in n:
		for ix in n:
			var x := -ForestLayout.HALF - 3.0 + (ix + rng.randf()) * step
			var z := -ForestLayout.HALF - 3.0 + (iz + rng.randf()) * step
			var path := terrain.path_distance(x, z)
			var water := terrain.water_distance(x, z)
			if path < 1.0 or water < 0.15:
				continue
			var p := Vector2(x, z)
			var tree := _near_tree(p, 0.15)
			if not tree.is_empty():
				continue
			var shade := terrain.shade_at(x, z)
			var slope := terrain.slope_at(x, z)
			if slope > 34.0:
				continue
			var patch := _patch.get_noise_2d(x, z)
			var patch2 := _patch.get_noise_2d(x * 1.7 + 50.0, z * 1.7)
			var glade := 1.0 - ForestLayout.sstep(ForestLayout.GLADE_RADIUS * 0.6, ForestLayout.GLADE_RADIUS * 1.4, p.distance_to(ForestLayout.GLADE))
			var wet := 1.0 - ForestLayout.sstep(0.0, 3.0, water)
			var r := rng.randf()
			var custom := _plant_custom(x, z)

			# Flower drifts in sunny meadows, densest in the glade.
			if shade < 0.45 and patch > 0.3 - glade * 0.22 and r < 0.3:
				var fl := ["Flower_3_Single", "Flower_4_Single", "Flower_3_Group", "Flower_4_Group"]
				var pick := 0 if patch2 > 0.0 else 1
				if rng.randf() < 0.22:
					pick += 2
				add(_named(fl[pick]), _ground_xform(x, z, rng.randf_range(0.2, 0.32), rng.randf() * TAU, 0.0), custom, "plant")
				continue
			# Ferns love damp shade and the stream banks.
			if (shade > 0.35 or wet > 0.3) and patch2 > 0.05 and r < 0.16 + wet * 0.2:
				add(_named("Fern_1"), _ground_xform(x, z, rng.randf_range(0.18, 0.3), rng.randf() * TAU, 0.0, 0.5), custom, "plant")
				continue
			# Big-leafed plants at the water's edge.
			if wet > 0.4 and r < 0.12:
				var m := "Plant_1_Big" if rng.randf() < 0.4 else "Plant_1"
				add(_named(m), _ground_xform(x, z, rng.randf_range(0.35, 0.5) if m == "Plant_1_Big" else rng.randf_range(0.6, 0.9), rng.randf() * TAU, 0.0, 0.5), custom, "plant")
				continue
			# Clover carpets under the trees.
			if shade > 0.3 and patch < -0.1 and r < 0.4:
				var m := "Clover_1" if rng.randf() < 0.5 else "Clover_2"
				add(_named(m), _ground_xform(x, z, rng.randf_range(0.45, 0.7), rng.randf() * TAU, 0.0, 0.8), custom, "plant")
				continue
			# Low leafy rosettes anywhere.
			if r < 0.05:
				var m := "Plant_7" if rng.randf() < 0.6 else "Plant_7_Big"
				add(_named(m), _ground_xform(x, z, rng.randf_range(0.7, 1.1), rng.randf() * TAU, 0.0, 1.0), custom, "plant")
				continue
			# Bushes along the forest margins.
			if shade > 0.2 and shade < 0.75 and path > 2.2 and water > 1.2 and r < 0.035 and glade < 0.3:
				var grove := 1.0 - ForestLayout.sstep(10.0, 18.0, p.distance_to(ForestLayout.GROVE))
				var m := "Bush_Common_Flowers" if rng.randf() < 0.3 + grove * 0.5 else "Bush_Common"
				add(_named(m), _ground_xform(x, z, rng.randf_range(0.6, 1.05), rng.randf() * TAU, 0.08), _tree_custom(grove * 0.8), "bush")
				continue

	# Mushrooms gather at the feet of trees; in the hollow they glow.
	for t in trees:
		var tp: Vector2 = t.pos
		if maxf(absf(tp.x), absf(tp.y)) > ForestLayout.HALF:
			continue
		var hollow := 1.0 - ForestLayout.sstep(10.0, 22.0, tp.distance_to(ForestLayout.HOLLOW))
		var count := rng.randi_range(0, 2) + int(hollow * 4.0)
		for k in count:
			var a := rng.randf() * TAU
			var rr: float = t.trunk + rng.randf_range(0.3, 1.6)
			var q := tp + Vector2(cos(a), sin(a)) * rr
			if terrain.water_distance(q.x, q.y) < 0.2 or terrain.path_distance(q.x, q.y) < 0.8:
				continue
			var glow := rng.randf() < hollow * 0.85 + 0.05
			var model := "Mushroom_Common" if rng.randf() < 0.8 else "Mushroom_Laetiporus"
			if glow:
				model = "Mushroom_Common"
			var s := rng.randf_range(0.7, 1.3) if model == "Mushroom_Common" else rng.randf_range(0.4, 0.7)
			add(_named(model, "glow" if glow else ""), _ground_xform(q.x, q.y, s, rng.randf() * TAU, 0.02, 0.6), Color(rng.randf(), rng.randf(), rng.randf(), 0.0), "small")

	# The fairy ring around the Elder.
	var e := ForestLayout.ELDER
	var ring_r := 6.2
	var ring_n := 34
	hero["fairy_ring"] = []
	for k in ring_n:
		var a := TAU * k / ring_n + rng.randf_range(-0.05, 0.05)
		var q := e + Vector2(cos(a), sin(a)) * (ring_r + rng.randf_range(-0.25, 0.25))
		if terrain.path_distance(q.x, q.y) < 0.7:
			continue
		var s := rng.randf_range(0.8, 1.5)
		add(_named("Mushroom_Common", "glow"), _ground_xform(q.x, q.y, s, rng.randf() * TAU, 0.02, 0.6), Color(0.15 + rng.randf() * 0.3, rng.randf(), rng.randf(), 0.0), "small")
		hero["fairy_ring"].append(Vector3(q.x, terrain.height_at(q.x, q.y), q.y))


func _place_grass() -> void:
	var tufts: Array[ArrayMesh] = []
	for v in 4:
		var m := kit.grass_tuft(ForestLayout.SEED + v * 13, 9 + v, 0.55, 0.22)
		m.resource_name = "GrassTuft_%d" % v
		tufts.append(m)
	var tall := [_named("Grass_Wispy_Tall"), _named("Grass_Common_Tall"), _named("Grass_Wispy_Short")]
	var step := 0.42
	var lim := ForestLayout.HALF + 6.0
	var n := int(lim * 2.0 / step)
	for iz in n:
		for ix in n:
			var x := -lim + (ix + rng.randf()) * step
			var z := -lim + (iz + rng.randf()) * step
			var water := terrain.water_distance(x, z)
			if water < 0.25:
				continue
			var path := terrain.path_distance(x, z)
			var shade := terrain.shade_at(x, z)
			var density := (1.0 - shade * 0.72)
			density *= ForestLayout.sstep(0.55, 1.6, path)
			density *= 1.0 - ForestLayout.sstep(26.0, 40.0, terrain.slope_at(x, z))
			if Vector2(x, z).distance_to(ForestLayout.OVERLOOK) < 3.4:
				density *= 0.25
			var p := _patch.get_noise_2d(x * 0.7, z * 0.7)
			density *= 0.7 + 0.5 * clampf(p + 0.4, 0.0, 1.0)
			if rng.randf() > density:
				continue
			var custom := _plant_custom(x, z)
			var wet := custom.g
			# Tall wispy grass along the water and in sunny meadow patches.
			if (wet > 0.35 and rng.randf() < 0.18) or (p > 0.35 and shade < 0.3 and rng.randf() < 0.05):
				var m: ArrayMesh = tall[rng.randi() % tall.size()]
				add(m, _ground_xform(x, z, rng.randf_range(0.35, 0.55), rng.randf() * TAU, 0.0, 0.7), custom, "grass")
				continue
			var s := rng.randf_range(0.75, 1.25) * lerpf(1.0, 0.7, shade)
			add(tufts[rng.randi() % tufts.size()], _ground_xform(x, z, s, rng.randf() * TAU, 0.0, 0.8), custom, "grass")
