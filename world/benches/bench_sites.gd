class_name BenchSites
extends RefCounted
## The five scenic benches of the Whispering Glade: where they stand, which way
## they look, and what kind of view each one frames.
##
## The view tags are data for the weed superpowers to come: smoking a bowl on a
## bench will grant a buff themed by what you are gazing at (a river view leans
## on water, the mountains on earth, and so on). Nothing reads them yet except
## the seated caption.
##
## Planning runs inside ForestTerrain.build(), before the footpaths are traced,
## so every bench gets a little level terrace and a trodden spur trail out to it
## that the scatter then keeps clear of trees and undergrowth.

## Seat spacing along a bench and its overall length per seat count.
const SEAT_SPACING := 0.68
const END_MARGIN := 0.2

## Hand-authored sites. `pos` is the bench centre, `look` the point the seated
## Keling gazes at (XZ; height from `look_y` metres above the ground there or
## an absolute `look_h`), `trail` waypoints from the nearest footpath (may be
## empty). The rest is flavour and the view tag.
const SITES := [
	{
		"id": &"brookside", "title": "Brookside Bench", "style": &"driftwood", "seats": 2,
		"view": &"river", "element": &"water",
		"caption": "The stream chatters past, cool and quick.",
		"pos": Vector2(17.55, 12.85), "look": Vector2(23.2, 16.4), "look_y": 0.2,
		"trail": [Vector2(12.0, 7.4)],
	},
	{
		"id": &"lotus", "title": "Lotus Pond Bench", "style": &"lotus", "seats": 2,
		"view": &"pond", "element": &"spirit",
		"caption": "Koi drift beneath the glowing lotus.",
		"pos": Vector2(6.35, -11.6), "look": Vector2(11.0, -18.0), "look_y": 0.1,
		"trail": [],
	},
	{
		"id": &"falls", "title": "Misty Falls Bench", "style": &"stone", "seats": 2,
		"view": &"waterfall", "element": &"air",
		"caption": "Spray drifts down the tumbling falls.",
		"pos": Vector2(9.9, -28.7), "look": Vector2(15.2, -32.0), "look_y": 0.9,
		"trail": [Vector2(-2.5, -25.5), Vector2(3.5, -27.3)],
	},
	{
		"id": &"sunset", "title": "Sunset Ridge Bench", "style": &"sunset", "seats": 4,
		"view": &"mountains", "element": &"earth",
		"caption": "The far mountains blush gold at sundown.",
		# Placed from the overlook and the vista direction in plan().
		"pos": Vector2.ZERO, "look": Vector2.ZERO, "look_y": 2.5,
		"trail": [],
	},
	{
		"id": &"meadow", "title": "Elder's Meadow Bench", "style": &"living", "seats": 2,
		"view": &"forest", "element": &"life",
		"caption": "The Elder tree hums over the meadow.",
		"pos": Vector2(-10.6, -3.9), "look": Vector2(-15.0, -11.0), "look_y": 5.5,
		"trail": [],
	},
]


static func length_for(seats: int) -> float:
	return seats * SEAT_SPACING + END_MARGIN * 2.0


## Resolves every site into placement data and sculpts its terrace into the
## terrain heights. Returns one Dictionary per bench (the SITES entry plus
## yaw, forward, axis, length, trails).
static func plan(terrain: ForestTerrain) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for src in SITES:
		var s: Dictionary = src.duplicate(true)
		if s.id == &"sunset":
			var v := ForestLayout.vista_dir()
			var perp := Vector2(-v.y, v.x)
			s.pos = ForestLayout.OVERLOOK + v * 3.7 - perp * 0.6
			s.look = ForestLayout.OVERLOOK + v * 60.0
		var pos: Vector2 = s.pos
		var fwd: Vector2 = ((s.look as Vector2) - pos).normalized()
		s.forward = fwd
		s.axis = Vector2(fwd.y, -fwd.x)  # bench-space +X in the world
		s.yaw = atan2(fwd.x, fwd.y)
		s.length = length_for(s.seats)
		s.ground = terrain.height_at(pos.x, pos.y)
		# Pad of trodden earth under the bench.
		var half: float = s.length * 0.5
		var trails: Array[PackedVector2Array] = [PackedVector2Array([pos - s.axis * half, pos + s.axis * half])]
		# A spur trail from the nearest footpath, if one is authored.
		var way: Array = s.trail
		if not way.is_empty():
			var ctrl: Array[Vector2] = []
			for w in way:
				ctrl.append(w)
			ctrl.append(pos + fwd * 1.0)
			trails.append(ForestLayout.resample(ctrl, 0.5))
		s.trails = trails
		out.append(s)
	_sculpt(terrain, out)
	return out


## Levels a terrace under each bench so the seat sits true even on the ridge,
## easing back into the natural slope a couple of metres out.
static func _sculpt(terrain: ForestTerrain, sites: Array[Dictionary]) -> void:
	var n := ForestTerrain.N
	for s in sites:
		var pos: Vector2 = s.pos
		var axis: Vector2 = s.axis
		var half: float = s.length * 0.5
		var level: float = s.ground
		var reach := half + 3.5
		var i0 := maxi(0, int((pos.x - reach + ForestTerrain.EXTENT) / ForestTerrain.STEP))
		var i1 := mini(n - 1, int((pos.x + reach + ForestTerrain.EXTENT) / ForestTerrain.STEP) + 1)
		var j0 := maxi(0, int((pos.y - reach + ForestTerrain.EXTENT) / ForestTerrain.STEP))
		var j1 := mini(n - 1, int((pos.y + reach + ForestTerrain.EXTENT) / ForestTerrain.STEP) + 1)
		for gz in range(j0, j1 + 1):
			for gx in range(i0, i1 + 1):
				var p := Vector2(ForestTerrain._gx(gx), ForestTerrain._gx(gz))
				var rel := p - pos
				var t := clampf(rel.dot(axis), -half, half)
				var d := rel.distance_to(axis * t)
				var w := 1.0 - ForestLayout.sstep(1.1, 3.2, d)
				if w <= 0.0:
					continue
				var i := gz * n + gx
				if terrain.water_dist[i] < 1.0:
					continue
				terrain.heights[i] = lerpf(terrain.heights[i], level, w)
