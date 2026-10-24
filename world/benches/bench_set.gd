class_name BenchSet
extends RefCounted
## Places the scenic benches planned by BenchSites into the forest: dresses
## each one with flowers, ferns and pebbles (batched with the rest of the
## undergrowth) and builds the interactive Bench nodes.

var layout: ForestLayout
var terrain: ForestTerrain
var kit: NatureKit
var scatter: ForestScatter
var benches: Array[Bench] = []
var rng := RandomNumberGenerator.new()


func _init(p_layout: ForestLayout, p_terrain: ForestTerrain, p_kit: NatureKit, p_scatter: ForestScatter) -> void:
	layout = p_layout
	terrain = p_terrain
	kit = p_kit
	scatter = p_scatter
	rng.seed = ForestLayout.SEED + 77


## Must run before the scatter is built so the dressing joins its batches.
func decorate() -> void:
	var S := ForestLayout.SEED + 500
	var flowers := ["Flower_3_Group", "Flower_4_Group", "Flower_3_Single", "Flower_4_Single"]
	var petals := ["Petal_1", "Petal_4", "Petal_5"]
	var pebbles := ["Pebble_Round_1", "Pebble_Round_2", "Pebble_Round_3", "Pebble_Round_4", "Pebble_Round_5"]
	var ferns: Array[ArrayMesh] = [scatter.flora.fern(S, "lady"), scatter.flora.fern(S + 1, "bracken")]
	var reeds: Array[ArrayMesh] = [scatter.flora.reeds(S + 2, true), scatter.flora.reeds(S + 3, false)]
	var bells := scatter.flora.bluebells(S + 4)
	var moss := scatter.flora.moss(S + 5)
	for site in terrain.bench_sites:
		var half: float = site.length * 0.5
		var ends := [-half - 0.3, half + 0.3]
		match site.style:
			&"driftwood":
				for i in 8:
					_put(site, Vector2(rng.randf_range(-half - 0.6, half + 0.6), rng.randf_range(-0.9, -0.35)), _named(pebbles[i % 5]), rng.randf_range(0.6, 1.3), "small", 0.02)
				for x: float in [-half - 0.55, half + 0.75]:
					_put(site, Vector2(x, 1.1), reeds[rng.randi() % 2], rng.randf_range(0.7, 0.95), "plant")
				_put(site, Vector2(-half - 0.35, -0.2), ferns[0], 0.6, "plant")
			&"lotus":
				for x: float in ends:
					_put(site, Vector2(x, -0.1), _named(flowers[rng.randi() % 2]), rng.randf_range(0.3, 0.4), "plant", 0.0, rng.randf())
					_put(site, Vector2(x * 1.2, -0.55), bells, 0.9, "plant")
				for i in 4:
					_put(site, Vector2(rng.randf_range(-half, half), rng.randf_range(-0.9, -0.5)), _named(petals[i % 3]), 0.9, "plant", 0.0, rng.randf())
			&"stone":
				for x: float in ends:
					_put(site, Vector2(x, -0.25), ferns[rng.randi() % 2], rng.randf_range(0.65, 0.85), "plant")
					_put(site, Vector2(x * 0.8, -0.5), moss, rng.randf_range(0.8, 1.2), "small", 0.04)
				_put(site, Vector2(0.0, -0.75), ferns[0], 0.75, "plant")
			&"sunset":
				for x: float in ends:
					_put(site, Vector2(x, -0.35), _named(flowers[rng.randi() % 4]), rng.randf_range(0.28, 0.38), "plant", 0.0, rng.randf())
				for i in 5:
					_put(site, Vector2(rng.randf_range(-half, half), rng.randf_range(-0.9, -0.45)), _named(petals[i % 3]), 0.8, "plant", 0.0, rng.randf())
			&"living":
				# Flowers crowd round the roots, mushrooms at their feet.
				for i in 10:
					var side := -1.0 if i % 2 == 0 else 1.0
					var p := Vector2(side * (half + rng.randf_range(0.15, 0.6)), rng.randf_range(-0.5, 0.2))
					_put(site, p, _named(flowers[rng.randi() % 4]), rng.randf_range(0.25, 0.4), "plant", 0.0, rng.randf())
				for i in 6:
					_put(site, Vector2(rng.randf_range(-half, half), rng.randf_range(-0.85, -0.4)), _named(petals[i % 3]), 0.9, "plant", 0.0, rng.randf())
				for x: float in [-half + 0.1, half - 0.1]:
					_put(site, Vector2(x + 0.12, -0.32), _named("Mushroom_Common"), 0.35, "small")
					_put(site, Vector2(x - 0.1, 0.32), _named("Mushroom_Common"), 0.28, "small")


func build(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Benches"
	parent.add_child(root)
	var builder := BenchBuilder.new(kit)
	for site in terrain.bench_sites:
		var pos: Vector2 = site.pos
		var bench := Bench.new()
		var look: Vector2 = site.look
		var look_y: float = terrain.height_at(look.x, look.y) + site.look_y
		if site.id == &"falls":
			look_y = maxf(look_y, terrain.height_at(pos.x, pos.y) + 0.8)
		root.add_child(bench)
		bench.setup(site, builder, terrain.height_at(pos.x, pos.y), look_y)
		benches.append(bench)
	return root


func _named(model: String) -> ArrayMesh:
	return scatter._named(model)


## Drops a dressing instance at a bench-space spot (x along, z forward).
func _put(site: Dictionary, local: Vector2, mesh: Mesh, scale: float, group: String, sink := 0.0, hue := -1.0) -> void:
	var axis: Vector2 = site.axis
	var fwd: Vector2 = site.forward
	var p: Vector2 = (site.pos as Vector2) + axis * local.x + fwd * local.y
	if terrain.water_distance(p.x, p.y) < 0.25 and group != "plant":
		return
	var xf := scatter._ground_xform(p.x, p.y, scale, rng.randf() * TAU, sink, 1.0)
	var custom := scatter._plant_custom(p.x, p.y) if group == "plant" else Color(rng.randf(), rng.randf(), rng.randf(), 0.0)
	if hue >= 0.0:
		custom.a = scatter._flower_hue(p.x + hue * 40.0, p.y)
	scatter.add(mesh, xf, custom, group)
