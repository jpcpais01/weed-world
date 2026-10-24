@tool
class_name WeedBud
extends Node3D
## One bud on a wild weed plant. It is "grabbable": walk up and press grab and
## the Keling reaches out and plucks it (KelingWeed puts it in the pouch).
## A picked bud shrinks away and grows back after a while.

var plant: WeedPlant
var net_id := -1   ## stable across co-op devices, see WeedPatches.bud_by_id()
var size := 1.0
var ripe := true
var mesh: MeshInstance3D
var _grow := 1.0
var _timer := 0.0
var _flash := 0.0


func build() -> void:
	add_to_group("grabbable")
	add_to_group("weed_bud")
	mesh = WeedKit.make_bud(plant.strain, size)
	mesh.rotation = Vector3(randf_range(-0.25, 0.25), randf() * TAU, randf_range(-0.2, 0.2))
	mesh.visibility_range_end = 30.0
	mesh.visibility_range_end_margin = 3.0
	add_child(mesh)
	set_process(false)


var strain: StringName:
	get:
		return plant.strain if plant else &"ember"


func grab_point() -> Vector3:
	return global_position


func can_grab() -> bool:
	return ripe


func on_grabbed() -> void:
	if not ripe:
		return
	ripe = false
	_timer = WeedPlant.REGROW_TIME * randf_range(0.85, 1.2)
	_flash = 1.0
	set_process(true)
	if plant:
		plant.on_bud_picked(self)


## Another player picked this bud: it pops off here too (no item for us).
func apply_remote_pick() -> void:
	on_grabbed()


## Grows back straight away (Bloom Trail).
func ripen() -> void:
	ripe = true
	_timer = 0.0
	_flash = 1.0
	set_process(true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	if not ripe:
		_timer -= delta
		_grow = move_toward(_grow, 0.0, delta * 6.0)
		if _timer <= 0.0:
			ripe = true
			_flash = 0.8
	else:
		_grow = move_toward(_grow, 1.0, delta * 0.7)
	_flash = move_toward(_flash, 0.0, delta * 1.6)
	var s := ease(_grow, -2.2)
	mesh.scale = Vector3.ONE * WeedKit.BUD_SCALE * size * maxf(s, 0.001)
	mesh.visible = _grow > 0.01
	mesh.set_instance_shader_parameter("ripe", 1.0 if ripe and _grow > 0.95 else 0.0)
	mesh.set_instance_shader_parameter("flash", _flash)
	if ripe and _grow >= 1.0 and _flash <= 0.0:
		set_process(false)
