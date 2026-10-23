extends Node3D
## The playable Whispering Glade: grows the forest, then drops a Keling at the
## spawn on the meadow path, facing the Elder tree.

const KELING := preload("res://player/keling.tscn")

@onready var forest: Forest = $Forest


func _ready() -> void:
	var spawn := forest.get_spawn_transform(0)
	var look := ForestLayout.ELDER - ForestLayout.SPAWN
	var keling := KELING.instantiate() as Node3D
	keling.name = "Keling"
	keling.position = spawn.origin + Vector3.UP * 0.05
	# Kelings face +Z at yaw 0.
	keling.rotation.y = atan2(look.x, look.y)
	add_child(keling)
