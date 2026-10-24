class_name WaterLevel
extends RefCounted
## Where the water is, for anything that wades, swims or splashes: the surface
## height and how deep it stands over the bed anywhere in the forest. The
## forest publishes its terrain here once it has grown; with no forest (the
## test grounds) there simply is no water.

static var _terrain: ForestTerrain


static func publish(terrain: ForestTerrain) -> void:
	_terrain = terrain


static func withdraw(terrain: ForestTerrain) -> void:
	if _terrain == terrain:
		_terrain = null


static func has_water() -> bool:
	return _terrain != null


## Height of the water surface over (x, z), or -INF where there is none. Near
## a waterfall the nearest grid cell decides, so the pool below a ledge never
## borrows the surface of the pool above it.
static func surface_at(x: float, z: float) -> float:
	var t := _terrain
	if t == null:
		return -INF
	var e := ForestTerrain.EXTENT
	if absf(x) >= e - ForestTerrain.STEP or absf(z) >= e - ForestTerrain.STEP:
		return -INF
	var n := ForestTerrain.N
	var fx := (x + e) / ForestTerrain.STEP
	var fz := (z + e) / ForestTerrain.STEP
	var level := t.water_level[clampi(roundi(fz), 0, n - 1) * n + clampi(roundi(fx), 0, n - 1)]
	if level > -1.0e5:
		return level
	# Right on the rim of the wet cells: take the highest neighbour.
	var gx := int(fx)
	var gz := int(fz)
	for dz in 2:
		for dx in 2:
			level = maxf(level, t.water_level[clampi(gz + dz, 0, n - 1) * n + clampi(gx + dx, 0, n - 1)])
	return level if level > -1.0e5 else -INF


## How deep the water stands over the terrain bed here (<= 0 on dry land).
static func bed_depth_at(x: float, z: float) -> float:
	var s := surface_at(x, z)
	if s == -INF:
		return -1.0
	return s - _terrain.height_at(x, z)


## Height of the ground (the bed, under water) at (x, z).
static func ground_at(x: float, z: float) -> float:
	return _terrain.height_at(x, z) if _terrain else 0.0
