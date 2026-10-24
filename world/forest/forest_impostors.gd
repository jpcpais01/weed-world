class_name ForestImpostors
extends RefCounted
## Distant trees drawn as impostors: a camera-facing card that shows the tree
## photographed from the nearest of FRAMES directions around it (blended with
## the next one), lit by baked normals and recoloured per tree exactly the
## way the canopy shader colours real crowns. Every impostor in the valley
## goes into a handful of MultiMeshes, so the whole far forest costs a few
## draw calls and two triangles a tree.
##
## The atlas is baked offline by tools/bake_impostors.gd. Each entry records
## a signature of the mesh it was baked from: if a tree's generator changes,
## that tree simply keeps its real mesh (and render_budget warns) until the
## atlas is baked again.

const DIR := "res://world/forest/impostors/"
const ALBEDO := DIR + "impostor_albedo.png"
const NORMAL := DIR + "impostor_normal.png"
const INDEX := DIR + "impostors.json"
const SHADER := preload("res://world/forest/shaders/impostor.gdshader")

const FRAMES := 8
## Bake resolution: about what a tree covers on a 1080p screen at FROM.
const PX_PER_M := 12.0
## Trees switch to impostors this far from the camera...
const FROM := 60.0
## ...and cast their shadow as one from here. A card's shadow can't shade
## the real crown it stands for, but out in the far shadow split that self
## shading is a soft blur anyway (side-by-side renders matched), and each
## real tree's casters cost a draw call: desktop switches at 40 m, phones at
## 30 m.
const SHADOW_FROM_DESKTOP := 40.0
const SHADOW_FROM_MOBILE := 30.0
static var shadow_from := SHADOW_FROM_MOBILE if OS.has_feature("mobile") else SHADOW_FROM_DESKTOP
## Rows of the type table: frame rect, quad size, then the crown palette.
const TABLE_W := 6

var types := {}          # mesh signature -> type index
var names: Array[String] = []
var material: ShaderMaterial
var quad: ArrayMesh
var stale: Array[String] = []
var _entries: Array = []


static func signature(mesh: Mesh) -> String:
	var verts := 0
	for s in mesh.get_surface_count():
		verts += mesh.surface_get_array_len(s)
	var b := mesh.get_aabb()
	return "%s|%d|%d|%.3f,%.3f,%.3f,%.3f,%.3f,%.3f" % [mesh.resource_name, mesh.get_surface_count(), verts,
			b.position.x, b.position.y, b.position.z, b.size.x, b.size.y, b.size.z]


## Loads the baked atlas, or returns null when there is none.
static func load_baked() -> ForestImpostors:
	if not FileAccess.file_exists(INDEX) or not ResourceLoader.exists(ALBEDO) or not ResourceLoader.exists(NORMAL):
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	if not (data is Dictionary) or int(data.get("frames", 0)) != FRAMES:
		return null
	var imp := ForestImpostors.new()
	imp._entries = data.types
	imp._atlas_size = Vector2(data.width, data.height)
	imp._albedo = load(ALBEDO)
	imp._normal = load(NORMAL)
	for i in imp._entries.size():
		imp.names.append(imp._entries[i].name)
	return imp


var _atlas_size := Vector2.ONE
var _albedo: Texture2D
var _normal: Texture2D
var _by_sig := {}


## The impostor type for this mesh, or -1. `canopy` is the mesh's crown
## material (for its palette), if it has one.
func type_for(mesh: Mesh) -> int:
	var sig := signature(mesh)
	if _by_sig.is_empty():
		for i in _entries.size():
			_by_sig[_entries[i].sig] = i
	if _by_sig.has(sig):
		types[sig] = _by_sig[sig]
		return _by_sig[sig]
	for i in _entries.size():
		if _entries[i].name == mesh.resource_name:
			stale.append(mesh.resource_name)
			break
	return -1


## Builds the shared material once every tree has been matched: the type
## table carries each type's frame strip, card size and crown palette.
func finish(meshes: Dictionary) -> void:
	var img := Image.create(TABLE_W, maxi(_entries.size(), 1), false, Image.FORMAT_RGBAF)
	for i in _entries.size():
		var e: Dictionary = _entries[i]
		var f: Array = e.frame
		img.set_pixel(0, i, Color(f[0] / _atlas_size.x, f[1] / _atlas_size.y, f[2] / _atlas_size.x, f[3] / _atlas_size.y))
		var q: Array = e.quad
		img.set_pixel(1, i, Color(q[0], q[1], q[2], e.radius))
		var pal := [Color(0.1, 0.28, 0.12), Color(0.55, 0.78, 0.22), Color(0.45, 0.14, 0.38), Color(1.0, 0.62, 0.78)]
		var mesh: Mesh = meshes.get(i)
		var stiffness := 1.0
		if mesh:
			for s in mesh.get_surface_count():
				var m := mesh.surface_get_material(s)
				if m is ShaderMaterial and (m as ShaderMaterial).shader == NatureKit.SH_CANOPY:
					var sm := m as ShaderMaterial
					pal = [sm.get_shader_parameter("color_low"), sm.get_shader_parameter("color_high"),
							sm.get_shader_parameter("alt_low"), sm.get_shader_parameter("alt_high")]
					stiffness = float(sm.get_shader_parameter("stiffness"))
					break
		for k in 4:
			var c: Color = (pal[k] as Color).srgb_to_linear()
			c.a = stiffness
			img.set_pixel(2 + k, i, c)
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("albedo_atlas", _albedo)
	material.set_shader_parameter("normal_atlas", _normal)
	material.set_shader_parameter("type_table", ImageTexture.create_from_image(img))
	material.set_shader_parameter("frames", float(FRAMES))
	quad = _quad()
	quad.surface_set_material(0, material)


## A unit card standing on its foot: x -0.5..0.5, y 0..1, UV top-left 0.
static func _quad() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.resource_name = "Impostor"
	# The card turns to face the camera in the shader; give culling the
	# whole space it can swing through.
	m.custom_aabb = AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1))
	return m
