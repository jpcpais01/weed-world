@tool
class_name Forest
extends Node3D
## The Whispering Glade: a 100 x 100 m magical forest. Everything is grown at
## load time from ForestLayout's deterministic seed, so the scene file stays
## tiny and every co-op client gets the identical world.
##
## Drop a player in by instancing it and calling get_spawn_transform(), or add
## any node to the "player" group: up to four of them part the grass.

signal built

@export var build_in_editor := true
@export_range(0.0, 2.0) var wind_strength := 0.6:
	set(v):
		wind_strength = v
		if kit:
			kit.set_wind(wind_direction, wind_strength)
## Spawn a free-fly camera when no player is present (standalone preview).
@export var preview_camera_when_alone := true

var wind_direction := Vector3(0.86, 0.0, 0.5).normalized()
var layout: ForestLayout
var terrain: ForestTerrain
var kit: NatureKit
var scatter: ForestScatter
var water: ForestWater
var atmosphere: ForestAtmosphere
var fx: ForestFX
var life: ForestLife
var sound: ForestSound
var _generated: Node3D
var _interactors: Array[Vector3] = []
var _wind_timer := 0.0


func _ready() -> void:
	if Engine.is_editor_hint() and not build_in_editor:
		return
	build()
	if not Engine.is_editor_hint() and preview_camera_when_alone:
		_spawn_preview_camera.call_deferred()


func build() -> void:
	var t0 := Time.get_ticks_msec()
	if _generated:
		_generated.queue_free()
	_generated = Node3D.new()
	_generated.name = "Generated"
	add_child(_generated)

	layout = ForestLayout.new()
	terrain = ForestTerrain.new(layout)
	terrain.build()
	kit = NatureKit.new()
	var laps := ["terrain %d" % (Time.get_ticks_msec() - t0)]

	# Trees first: they paint canopy shade into the terrain, which the ground
	# colour, the grass tint and the undergrowth all read.
	scatter = ForestScatter.new(layout, terrain, kit)
	scatter.plan()
	laps.append("trees %d" % (Time.get_ticks_msec() - t0))

	var ground := Node3D.new()
	ground.name = "Terrain"
	_generated.add_child(ground)
	var tmat := kit.terrain_material()
	for chunk in terrain.build_meshes(tmat):
		ground.add_child(chunk)
	ground.add_child(terrain.build_outer_mesh(tmat))
	ground.add_child(terrain.build_collision())

	laps.append("ground %d" % (Time.get_ticks_msec() - t0))
	scatter.populate()
	laps.append("undergrowth %d" % (Time.get_ticks_msec() - t0))
	scatter.build(_generated)
	laps.append("batches %d" % (Time.get_ticks_msec() - t0))

	water = ForestWater.new(layout, terrain, kit)
	water.build(_generated)

	atmosphere = ForestAtmosphere.new()
	atmosphere.build(_generated)
	atmosphere.build_distant_ranges(_generated)

	fx = ForestFX.new(layout, terrain, kit, scatter, water)
	fx.build(_generated)

	life = ForestLife.new(layout, terrain, kit)
	life.build(_generated)

	if not Engine.is_editor_hint():
		sound = ForestSound.new()
		_generated.add_child(sound)
		sound.setup(self)

	kit.set_wind(wind_direction, wind_strength)
	_place_spawn()
	print("Forest grown in %d ms (%s) instances %s" % [Time.get_ticks_msec() - t0, ", ".join(laps), scatter.counts])
	built.emit()


func _place_spawn() -> void:
	var spawn := get_node_or_null("PlayerSpawn") as Marker3D
	if spawn == null:
		spawn = Marker3D.new()
		spawn.name = "PlayerSpawn"
		add_child(spawn)
	spawn.transform = get_spawn_transform(0)


## Spawn points for up to four players in a small arc on the path, all facing
## north across the glade towards the Elder tree.
func get_spawn_transform(index: int) -> Transform3D:
	var offsets := [Vector2(0, 0), Vector2(-1.6, 0.6), Vector2(1.6, 0.6), Vector2(0, 1.8)]
	var p: Vector2 = ForestLayout.SPAWN + offsets[index % 4]
	var y := terrain.height_at(p.x, p.y) if terrain else 0.0
	var look := ForestLayout.ELDER - p
	var basis := Basis(Vector3.UP, atan2(-look.x, -look.y))
	return Transform3D(basis, Vector3(p.x, y + 0.1, p.y))


## Height of the forest floor, for anything that needs to stand on it.
func ground_height(x: float, z: float) -> float:
	return terrain.height_at(x, z) if terrain else 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or kit == null:
		return
	_interactors.clear()
	for n in get_tree().get_nodes_in_group("player"):
		if n is Node3D and _interactors.size() < 4:
			_interactors.append((n as Node3D).global_position)
	kit.set_interactors(_interactors)
	var t := Time.get_ticks_msec() / 1000.0
	if fx:
		fx.flicker(t)
	# The breeze breathes: a slow swell and lull on top of the gusts the
	# shaders roll across the valley.
	_wind_timer -= delta
	if _wind_timer <= 0.0:
		_wind_timer = 0.2
		var swell := 0.85 + 0.3 * sin(t * 0.13) * sin(t * 0.071 + 1.0)
		kit.set_wind(wind_direction, wind_strength * swell)


func _spawn_preview_camera() -> void:
	if not get_tree().get_nodes_in_group("player").is_empty():
		return
	if get_viewport().get_camera_3d() != null:
		return
	var cam := preload("res://world/forest/fly_camera.gd").new()
	cam.name = "PreviewCamera"
	add_child(cam)
	var t := get_spawn_transform(0)
	cam.global_transform = Transform3D(t.basis, t.origin + Vector3.UP * 1.6)
	cam.ground = self
	cam.make_current()
