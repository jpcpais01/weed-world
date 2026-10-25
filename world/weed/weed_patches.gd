class_name WeedPatches
extends RefCounted
## Where the wild weed grows in the Whispering Glade: little patches of one
## strain each, tucked beside the paths near the places worth exploring. The
## first one grows right by the spawn so new players find it straight away.
## Rarer strains grow in fewer, smaller patches in special places: Moonfeather
## weeps over the pond's far shore, Lantern Light glows in the shroom hollow,
## Cloud Bonsai clings to the sunset ridge, and the one Moonlit Lotus hides by
## the silver snag on the ridge shoulder.
##
## plan() runs after the trees are placed and before the undergrowth, so each
## plant gets a bed of soft soil (a ground stamp) that ferns and flowers keep
## clear of. build() then grows the interactive WeedPlant nodes.

## Hand-placed anchors; each patch settles on the nearest good spot to it.
## `n` is how many plants grow there.
const ANCHORS := [
	{"id": &"spawn", "strain": &"ember", "pos": Vector2(0.6, 16.4), "n": 3},
	{"id": &"glade", "strain": &"ember", "pos": Vector2(7.5, 2.5), "n": 4},
	{"id": &"ridge", "strain": &"ember", "pos": Vector2(-5.5, -32.5), "n": 4},
	{"id": &"elder", "strain": &"starlit", "pos": Vector2(-21.0, -5.0), "n": 4},
	{"id": &"hollow", "strain": &"starlit", "pos": Vector2(27.0, -11.0), "n": 4},
	{"id": &"pond", "strain": &"verdant", "pos": Vector2(2.5, -19.5), "n": 4},
	{"id": &"grove", "strain": &"verdant", "pos": Vector2(-23.0, 21.0), "n": 4},
	{"id": &"crossing", "strain": &"verdant", "pos": Vector2(14.5, -0.5), "n": 3},
	# Forged strains. Commons in two patches, uncommons off the beaten track,
	# rares and the legendary each in one special spot.
	{"id": &"glade_west", "strain": &"corkscrew", "pos": Vector2(-10.5, 12.5), "n": 3},
	{"id": &"streamside", "strain": &"corkscrew", "pos": Vector2(21.0, -13.5), "n": 3},
	{"id": &"south_path", "strain": &"mossy_mound", "pos": Vector2(-13.0, 31.0), "n": 3},
	{"id": &"elder_west", "strain": &"mossy_mound", "pos": Vector2(-27.0, -16.0), "n": 3},
	{"id": &"crossing_east", "strain": &"starfish", "pos": Vector2(24.5, 8.5), "n": 3},
	{"id": &"ridge_path", "strain": &"starfish", "pos": Vector2(-9.5, -21.5), "n": 3},
	{"id": &"west_woods", "strain": &"sky_spire", "pos": Vector2(-35.0, 8.0), "n": 3},
	{"id": &"east_woods", "strain": &"sky_spire", "pos": Vector2(37.0, 19.0), "n": 2},
	{"id": &"blossom_edge", "strain": &"bubblegum", "pos": Vector2(-33.0, 31.0), "n": 3},
	{"id": &"south_meadow", "strain": &"bubblegum", "pos": Vector2(7.0, 35.0), "n": 2},
	{"id": &"far_shore", "strain": &"moonfeather", "pos": Vector2(18.5, -20.5), "n": 2},
	{"id": &"lantern_hollow", "strain": &"lantern", "pos": Vector2(35.5, -3.5), "n": 3},
	{"id": &"sunset_ridge", "strain": &"cloud_bonsai", "pos": Vector2(-16.5, -40.0), "n": 2},
	{"id": &"falls_path", "strain": &"sunset_braid", "pos": Vector2(4.5, -31.5), "n": 2},
	{"id": &"silver_snag", "strain": &"moonlit_lotus", "pos": Vector2(-33.5, -24.0), "n": 1},
]
const SPACING := 0.75
## Highest a bud may grow (metres above the root) so a Keling can reach it.
const BUD_REACH := 1.1
## How much plants of each rarity vary in size.
const SIZE_SPREAD := {&"common": Vector2(0.88, 1.1), &"uncommon": Vector2(0.94, 1.06),
	&"rare": Vector2(0.96, 1.04), &"legendary": Vector2(1.0, 1.0)}
const SEARCH := 9.0

var terrain: ForestTerrain
var scatter: ForestScatter
var kit: NatureKit
## Planned plants: {pos: Vector2, strain, height, yaw, patch}
var plants: Array[Dictionary] = []
## Patch centres for the map and Spirit Sight: {id, strain, pos: Vector2}
var patches: Array[Dictionary] = []
var nodes: Array[WeedPlant] = []
var rng := RandomNumberGenerator.new()


func _init(p_terrain: ForestTerrain, p_scatter: ForestScatter, p_kit: NatureKit) -> void:
	terrain = p_terrain
	scatter = p_scatter
	kit = p_kit
	rng.seed = ForestLayout.SEED + 420


func plan() -> void:
	for a in ANCHORS:
		var centre := _settle(a.pos)
		if centre == Vector2.INF:
			continue
		var info := WeedStrains.info(a.strain)
		# Wide plants (Starfish, Mossy Mound...) need more elbow room.
		var spread := WeedKit.plant_spread(a.strain)
		var spacing := maxf(SPACING, spread * 1.7)
		patches.append({"id": a.id, "strain": a.strain, "pos": centre, "rarity": info.get("rarity", &"common")})
		scatter.keep_clear.append(Vector3(centre.x, centre.y, 2.2 + spread))
		var sizes: Vector2 = SIZE_SPREAD[info.get("rarity", &"common")]
		var top_bud := 0.0
		for b in WeedKit.bud_anchors(a.strain):
			top_bud = maxf(top_bud, b.y)
		var model_h := WeedKit.plant_model_height(a.strain)
		var placed: Array[Vector2] = []
		var tries := 0
		while placed.size() < a.n and tries < 60:
			tries += 1
			var r := 0.0 if placed.is_empty() else rng.randf_range(spacing * 0.85, spacing * 2.0)
			var ang := rng.randf() * TAU
			var p: Vector2 = centre + Vector2(cos(ang), sin(ang)) * r
			if not _good(p, 0.35 + spread * 0.5):
				continue
			var ok := true
			for q in placed:
				if p.distance_to(q) < spacing:
					ok = false
					break
			if not ok:
				continue
			placed.append(p)
			var h: float = info.height * rng.randf_range(sizes.x, sizes.y)
			# Never grow the buds out of reach.
			h = minf(h, BUD_REACH / maxf(top_bud / maxf(model_h, 0.01), 0.01))
			plants.append({"pos": p, "strain": a.strain, "height": h, "yaw": rng.randf() * TAU, "patch": a.id})
			# A bed of dark soil and moss at its foot that the undergrowth leaves clear.
			# Low, sprawling strains get a wide bed without the lush collar of tall
			# grass a rock stamp grows, so the grass never swallows them.
			if model_h < 0.9:
				scatter.ground.stamp(ForestGround.Foot.STONE, p, spread * 0.8 + 0.2)
			else:
				scatter.ground.stamp(ForestGround.Foot.ROCK, p, 0.32 + spread * 0.35)


func build(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "WeedPatches"
	parent.add_child(root)
	for d in plants:
		var plant := WeedPlant.new()
		var p: Vector2 = d.pos
		plant.position = Vector3(p.x, terrain.height_at(p.x, p.y) - 0.02, p.y)
		plant.setup(d.strain, d.height, d.yaw, kit)
		plant.net_index = nodes.size()
		for i in plant.buds.size():
			plant.buds[i].net_id = plant.net_index * 3 + i
		root.add_child(plant)
		nodes.append(plant)
	return root


## Co-op: every bud and plant has a stable id from the deterministic layout,
## identical on every device.
func bud_by_id(id: int) -> WeedBud:
	var plant := plant_by_index(id / 3)
	if plant == null or id % 3 >= plant.buds.size():
		return null
	return plant.buds[id % 3]


func plant_by_index(i: int) -> WeedPlant:
	return nodes[i] if i >= 0 and i < nodes.size() else null


## Spiral out from an anchor to the first spot with room for a patch.
func _settle(anchor: Vector2) -> Vector2:
	var step := 0.5
	var r := 0.0
	var a := 0.0
	while r <= SEARCH:
		var p := anchor + Vector2(cos(a), sin(a)) * r
		if _good(p, 1.1):
			return p
		a += step / maxf(r, step) * 1.3
		r += 0.035
	return Vector2.INF


func _good(p: Vector2, room: float) -> bool:
	if maxf(absf(p.x), absf(p.y)) > ForestLayout.HALF - 3.0:
		return false
	if terrain.water_distance(p.x, p.y) < 1.0 + room:
		return false
	if scatter.ground.path_edge(p.x, p.y) < 0.35 + room * 0.5:
		return false
	if terrain.slope_at(p.x, p.y) > 24.0:
		return false
	if scatter._near_bench(p, 2.2 + room):
		return false
	if not scatter._near_tree(p, 0.45 + room * 0.4).is_empty():
		return false
	return true
