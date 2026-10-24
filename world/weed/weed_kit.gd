class_name WeedKit
extends RefCounted
## Meshes and materials for the weed plants and buds, loaded once and shared
## by every plant in the forest and every bud in a Keling's hand.

const SH_PLANT := preload("res://world/weed/weed_plant.gdshader")
const SH_BUD := preload("res://world/weed/weed_bud.gdshader")
## The bud model is ~0.95 units tall; this makes it a plump 11 cm bud.
const BUD_SCALE := 0.115

static var _meshes := {}
static var _plant_mats := {}
static var _bud_mats := {}
static var _anchors := {}
static var _mutex := Mutex.new()


static func _load_mesh(path: String) -> Dictionary:
	_mutex.lock()
	if _meshes.has(path):
		var cached: Dictionary = _meshes[path]
		_mutex.unlock()
		return cached
	_mutex.unlock()
	var out := {"mesh": null, "albedo": null, "normal": null}
	var scene := load(path) as PackedScene
	if scene:
		var root := scene.instantiate()
		var mi := root.find_children("*", "MeshInstance3D", true, false)
		if not mi.is_empty():
			var mesh: Mesh = (mi[0] as MeshInstance3D).mesh
			out.mesh = mesh
			var m := mesh.surface_get_material(0) as BaseMaterial3D
			if m:
				out.albedo = m.albedo_texture
				out.normal = m.normal_texture if m.normal_enabled else null
		root.free()
	_mutex.lock()
	_meshes[path] = out
	_mutex.unlock()
	return out


static func plant_mesh(strain: StringName) -> Mesh:
	return _load_mesh(WeedStrains.info(strain).mesh).mesh


static func bud_mesh() -> Mesh:
	return _load_mesh(WeedStrains.BUD_MESH).mesh


## Native height of a strain's plant model (it stands on its root at 0).
static func plant_model_height(strain: StringName) -> float:
	var m := plant_mesh(strain)
	return m.get_aabb().end.y if m else 1.0


static func plant_material(strain: StringName, kit: NatureKit = null) -> ShaderMaterial:
	_mutex.lock()
	var mat: ShaderMaterial = _plant_mats.get(strain)
	_mutex.unlock()
	if mat:
		return mat
	var info := WeedStrains.info(strain)
	mat = ShaderMaterial.new()
	mat.shader = SH_PLANT
	mat.set_shader_parameter("albedo_tex", _load_mesh(info.mesh).albedo)
	mat.set_shader_parameter("height", info.height)
	mat.set_shader_parameter("glow_color", info.glow)
	if kit:
		kit.wind_materials.append(mat)
		kit.interactive_materials.append(mat)
	_mutex.lock()
	_plant_mats[strain] = mat
	_mutex.unlock()
	return mat


static func bud_material(strain: StringName) -> ShaderMaterial:
	_mutex.lock()
	var mat: ShaderMaterial = _bud_mats.get(strain)
	_mutex.unlock()
	if mat:
		return mat
	var info := WeedStrains.info(strain)
	var src := _load_mesh(WeedStrains.BUD_MESH)
	mat = ShaderMaterial.new()
	mat.shader = SH_BUD
	mat.set_shader_parameter("albedo_tex", src.albedo)
	if src.normal:
		mat.set_shader_parameter("normal_tex", src.normal)
	mat.set_shader_parameter("tint", info.bud_tint)
	mat.set_shader_parameter("glow_color", info.glow)
	_mutex.lock()
	_bud_mats[strain] = mat
	_mutex.unlock()
	return mat


## A ready-to-use bud mesh instance (centred on the bud's middle).
static func make_bud(strain: StringName, size := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = bud_mesh()
	mi.material_override = bud_material(strain)
	mi.scale = Vector3.ONE * BUD_SCALE * size
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("phase", randf())
	return mi


## Where buds sit on a plant model (model units, before scaling): the crown
## cola and two side colas, found on the stem by averaging the vertices in a
## thin band at each height.
static func bud_anchors(strain: StringName) -> PackedVector3Array:
	_mutex.lock()
	if _anchors.has(strain):
		var cached: PackedVector3Array = _anchors[strain]
		_mutex.unlock()
		return cached
	_mutex.unlock()
	var out := PackedVector3Array()
	var mesh := plant_mesh(strain)
	if mesh:
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var top := mesh.get_aabb().end.y
		for band: float in [0.9, 0.7, 0.52]:
			var sum := Vector3.ZERO
			var n := 0
			for v in verts:
				if absf(v.y - top * band) < top * 0.05:
					sum += v
					n += 1
			if n > 0:
				var c := sum / n
				# Pull towards the stem so the bud never floats off a leaf tip.
				out.append(Vector3(c.x * 0.5, top * band, c.z * 0.5))
	if out.is_empty():
		out.append(Vector3(0, 0.9, 0))
	_mutex.lock()
	_anchors[strain] = out
	_mutex.unlock()
	return out
