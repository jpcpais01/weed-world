class_name MapLandmarks
extends RefCounted
## The named places of the Whispering Glade, shared by the minimap, the world
## map and the "you have found" banner. Positions come straight from
## ForestLayout so the map can never drift from the world.

## Each place: id, name, blurb (one cozy line), pos (XZ metres), radius
## (where the banner triggers), icon (MapIcons glyph).
static func all(forest: Forest = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		_place("glade", "The Sunny Glade", "A warm meadow at the heart of the woods.", ForestLayout.GLADE, ForestLayout.GLADE_RADIUS * 0.85, "glade"),
		_place("elder", "The Elder Tree", "An ancient lilac spirit, ringed by fairy mushrooms.", ForestLayout.ELDER, 8.5, "elder"),
		_place("pond", "Lotus Pond", "Koi, lilies and glowing lotus blossoms.", ForestLayout.POND, ForestLayout.POND_RADIUS + 3.5, "pond"),
		_place("overlook", "Sunset Overlook", "A campfire, two benches and the best view in the valley.", ForestLayout.OVERLOOK, ForestLayout.OVERLOOK_RADIUS + 1.5, "overlook"),
		_place("hollow", "Glowshroom Hollow", "A dim, hushed dell lit by mushrooms and fireflies.", ForestLayout.HOLLOW, 10.0, "hollow"),
		_place("grove", "Blossom Grove", "Pink petals drift between the trees all day long.", ForestLayout.GROVE, 10.0, "grove"),
		_place("snag", "The Silver Snag", "A pale old tree keeping watch over the ridge.", ForestLayout.DEAD_TREE, 5.0, "snag"),
		_place("stones", "Stepping Stones", "Hop across the stream to the hollow.", ForestLayout.STREAM_CROSSING, 3.6, "stones"),
		_place("trailhead", "Mossy Trailhead", "Where every Keling wakes up.", ForestLayout.SPAWN, 3.5, "trailhead"),
	]
	var falls_at := Vector2(ForestLayout.CREEK[2])
	if forest and forest.terrain and not forest.terrain.falls.is_empty():
		var f: Dictionary = forest.terrain.falls[forest.terrain.falls.size() / 2]
		falls_at = Vector2(f.lip.x, f.lip.z)
	out.append(_place("falls", "Waterfall Stairs", "The creek tumbles down the ridge in little falls.", falls_at, 6.0, "falls"))
	return out


static func _place(id: String, name: String, blurb: String, pos: Vector2, radius: float, icon: String) -> Dictionary:
	return {"id": id, "name": name, "blurb": blurb, "pos": pos, "radius": radius, "icon": icon}


## The named place a point is in, or {} when out in the woods.
static func place_at(places: Array[Dictionary], p: Vector2, margin := 0.0) -> Dictionary:
	var best := {}
	var best_d := INF
	for pl in places:
		var d := p.distance_to(pl.pos) - (pl.radius as float) - margin
		if d < 0.0 and d < best_d:
			best = pl
			best_d = d
	return best


## A loose region name for anywhere that is not a named place.
static func region_at(p: Vector2) -> String:
	if p.y < -24.0:
		return "The Northern Ridge"
	if ForestLayout.square_dist(p.x, p.y) > 40.0:
		return "The Deep Woods"
	if p.x > 14.0 and p.y > 4.0:
		return "Streamside"
	return "Whispering Woods"
