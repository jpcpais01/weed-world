class_name Herb
extends Node3D
## A pickable herb for the grab test: a leafy stem with a glowing bud on top.
## The Keling grabs it at `grab_point()`; it then shrinks away and regrows.

@export var height := 0.42
@export var regrow_time := 8.0
@export var hanging := false  ## grows down from its node (a vine) instead of up

var _visual: Node3D
var _grown := 1.0
var _picked := false
var _timer := 0.0


func _ready() -> void:
	add_to_group("grabbable")
	_visual = build(height, hanging)
	add_child(_visual)


func grab_point() -> Vector3:
	return global_position + Vector3(0, -height * 0.85 if hanging else height * 0.85, 0)


func can_grab() -> bool:
	return not _picked


func on_grabbed() -> void:
	_picked = true
	_timer = regrow_time


func _process(delta: float) -> void:
	if _picked:
		_grown = move_toward(_grown, 0.0, delta * 5.0)
		_timer -= delta
		if _timer <= 0.0:
			_picked = false
	else:
		_grown = move_toward(_grown, 1.0, delta * 0.8)
	var s := ease(_grown, -2.0)
	_visual.scale = Vector3.ONE * maxf(s, 0.001)
	_visual.visible = _grown > 0.01


## Builds the herb geometry (also used for the sprig held in the hand).
static func build(h: float, hang := false) -> Node3D:
	var root := Node3D.new()
	var dir := -1.0 if hang else 1.0
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.32, 0.55, 0.2)
	stem_mat.roughness = 0.7
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.36, 0.68, 0.22)
	leaf_mat.roughness = 0.6
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf_mat.backlight_enabled = true
	leaf_mat.backlight = Color(0.35, 0.5, 0.1)
	var bud_mat := StandardMaterial3D.new()
	bud_mat.albedo_color = Color(0.85, 1.0, 0.55)
	bud_mat.emission_enabled = true
	bud_mat.emission = Color(0.55, 1.0, 0.35)
	bud_mat.emission_energy_multiplier = 1.4

	var stem := CylinderMesh.new()
	stem.top_radius = 0.008
	stem.bottom_radius = 0.014
	stem.height = h
	stem.radial_segments = 6
	stem.rings = 1
	stem.material = stem_mat
	var stem_mi := MeshInstance3D.new()
	stem_mi.mesh = stem
	stem_mi.position.y = h * 0.5 * dir
	root.add_child(stem_mi)

	var leaf := QuadMesh.new()
	leaf.size = Vector2(0.07, 0.13)
	leaf.center_offset = Vector3(0, 0.065, 0)
	leaf.material = leaf_mat
	for i in 6:
		var mi := MeshInstance3D.new()
		mi.mesh = leaf
		var t := 0.25 + 0.12 * i
		mi.position.y = h * t * dir
		mi.rotation = Vector3(deg_to_rad(55.0 + 8.0 * i) * dir, i * 2.4, 0.0)
		mi.scale = Vector3.ONE * (1.1 - 0.1 * i)
		root.add_child(mi)

	var bud := SphereMesh.new()
	bud.radius = 0.03
	bud.height = 0.07
	bud.radial_segments = 10
	bud.rings = 5
	bud.material = bud_mat
	var bud_mi := MeshInstance3D.new()
	bud_mi.mesh = bud
	bud_mi.position.y = h * dir
	root.add_child(bud_mi)
	return root
