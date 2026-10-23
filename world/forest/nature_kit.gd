class_name NatureKit
extends RefCounted
## Loads Quaternius' Stylized Nature MegaKit models (CC0) and re-dresses every
## surface in the forest's own stylised shaders. Also owns the shared material
## state (wind, the meadow palette, Keling positions for parting grass).

const MODEL_PATH := "res://assets/nature/models/%s.gltf"
const TEX_PATH := "res://assets/nature/textures/%s.png"

const SH_CANOPY := preload("res://world/forest/shaders/canopy.gdshader")
const SH_BARK := preload("res://world/forest/shaders/bark.gdshader")
const SH_PLANT := preload("res://world/forest/shaders/plant.gdshader")
const SH_ROCK := preload("res://world/forest/shaders/rock.gdshader")
const SH_MUSHROOM := preload("res://world/forest/shaders/mushroom.gdshader")
const SH_TERRAIN := preload("res://world/forest/shaders/terrain.gdshader")
const SH_WATER := preload("res://world/forest/shaders/water.gdshader")
const SH_WATERFALL := preload("res://world/forest/shaders/waterfall.gdshader")
const CAUSTICS := preload("res://world/forest/textures/caustics.png")
const NOISE := preload("res://world/forest/textures/noise_rgba.png")
const WATER_NOISE := preload("res://world/forest/textures/noise_water.png")

## Leaf palettes: [low, high, magic low, magic high]. "Magic" is blended in per
## tree so groves can drift from summer green into blossom colours.
const PALETTES := {
	"common": [Color(0.07, 0.23, 0.10), Color(0.50, 0.76, 0.22), Color(0.48, 0.13, 0.33), Color(1.0, 0.63, 0.80)],
	"twisted": [Color(0.05, 0.20, 0.15), Color(0.34, 0.66, 0.34), Color(0.24, 0.10, 0.40), Color(0.78, 0.60, 1.0)],
	"pine": [Color(0.03, 0.14, 0.11), Color(0.22, 0.46, 0.24), Color(0.05, 0.20, 0.24), Color(0.40, 0.80, 0.78)],
	"bush": [Color(0.06, 0.22, 0.09), Color(0.42, 0.70, 0.20), Color(0.40, 0.12, 0.30), Color(0.95, 0.55, 0.72)],
	"blossom": [Color(0.42, 0.12, 0.30), Color(1.0, 0.66, 0.82), Color(0.30, 0.10, 0.42), Color(0.86, 0.68, 1.0)],
	"willow": [Color(0.06, 0.24, 0.20), Color(0.52, 0.84, 0.56), Color(0.12, 0.26, 0.24), Color(0.66, 0.86, 0.72)],
	"sentinel": [Color(0.10, 0.25, 0.08), Color(0.72, 0.80, 0.25), Color(0.40, 0.22, 0.05), Color(1.0, 0.72, 0.30)],
	"far": [Color(0.04, 0.16, 0.10), Color(0.26, 0.48, 0.22), Color(0.20, 0.10, 0.25), Color(0.62, 0.45, 0.70)],
	"oak": [Color(0.05, 0.19, 0.07), Color(0.44, 0.66, 0.18), Color(0.30, 0.20, 0.05), Color(0.95, 0.70, 0.25)],
	"birch": [Color(0.16, 0.30, 0.06), Color(0.86, 0.88, 0.32), Color(0.45, 0.30, 0.04), Color(1.0, 0.82, 0.30)],
	"sapling": [Color(0.08, 0.26, 0.08), Color(0.56, 0.82, 0.26), Color(0.42, 0.14, 0.32), Color(1.0, 0.64, 0.80)],
}

const BARK := {
	"Bark_NormalTree": ["Bark_NormalTree", "Bark_NormalTree_Normal", Color(0.95, 0.88, 0.82), 0.55],
	"Bark_TwistedTree": ["Bark_TwistedTree", "Bark_TwistedTree_Normal", Color(0.85, 0.82, 0.86), 0.6],
	"Bark_DeadTree": ["Bark_DeadTree", "Bark_DeadTree_Normal", Color(1.25, 1.22, 1.2), 0.2],
	"Bark_Pale": ["Bark_NormalTree", "Bark_NormalTree_Normal", Color(1.45, 1.38, 1.3), 0.35],
	"Bark_Birch": ["Bark_NormalTree", "Bark_NormalTree_Normal", Color(1.3, 1.3, 1.3), 0.15],
}

var wind_materials: Array[ShaderMaterial] = []
var interactive_materials: Array[ShaderMaterial] = []
var _meshes := {}
var _textures := {}
var _bark := {}
var _plain := {}


func texture(name: String) -> Texture2D:
	if not _textures.has(name):
		_textures[name] = load(TEX_PATH % name)
	return _textures[name]


## A kit mesh dressed in forest materials. `variant` picks alternate dressings
## of the same model, e.g. "glow" mushrooms.
func mesh(model: String, variant: String = "") -> ArrayMesh:
	var key := model + ":" + variant
	if _meshes.has(key):
		return _meshes[key]
	var scene: PackedScene = load(MODEL_PATH % model)
	var root := scene.instantiate()
	var mi := _find_mesh(root)
	var src: ArrayMesh = mi.mesh
	var m: ArrayMesh = src.duplicate()
	root.free()
	for s in m.get_surface_count():
		var mat := src.surface_get_material(s)
		var mat_name := mat.resource_name if mat else ""
		m.surface_set_material(s, _material_for(model, variant, mat_name, m, s))
	_meshes[key] = m
	return m


## A reshaped copy of a kit model: stretched, leaning, twisted, its crown
## puffed out or thinned, its limbs warped. A handful of source models grow
## into a forest of distinct silhouettes. LODs are rebuilt for the new shape.
## opts: scale (Vector3), bend (fraction of height the top drifts sideways),
## bend_dir (Vector2), twist (radians at the top), crown (scale of foliage
## about the crown centre), warp (metres of noise displacement), variant.
func reshaped(model: String, tag: String, opts: Dictionary) -> ArrayMesh:
	var key := model + "#" + tag
	if _meshes.has(key):
		return _meshes[key]
	var src := mesh(model, opts.get("variant", ""))
	var h := maxf(src.get_aabb().end.y, 0.01)
	var scale: Vector3 = opts.get("scale", Vector3.ONE)
	var bend: float = opts.get("bend", 0.0)
	var bdir: Vector2 = opts.get("bend_dir", Vector2.RIGHT)
	var twist: float = opts.get("twist", 0.0)
	var crown: float = opts.get("crown", 1.0)
	var warp: float = opts.get("warp", 0.0)
	var noise := FastNoiseLite.new()
	noise.seed = hash(key)
	noise.frequency = 0.3
	var im := ImporterMesh.new()
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var mat := src.surface_get_material(s)
		var leafy := mat is ShaderMaterial and (mat as ShaderMaterial).shader == SH_CANOPY
		var center := Vector3.ZERO
		if leafy:
			center = (mat as ShaderMaterial).get_shader_parameter("canopy_center")
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tans = arrays[Mesh.ARRAY_TANGENT]
		var has_tan: bool = tans is PackedFloat32Array and (tans as PackedFloat32Array).size() == verts.size() * 4
		for i in verts.size():
			var v := verts[i]
			var n := norms[i]
			if leafy and crown != 1.0:
				v = center + (v - center) * crown
			v *= scale
			n = (n / scale).normalized()
			var f := clampf(v.y / (h * scale.y), 0.0, 1.0)
			var a := twist * f
			if a != 0.0:
				v = v.rotated(Vector3.UP, a)
				n = n.rotated(Vector3.UP, a)
			if warp > 0.0:
				v += Vector3(noise.get_noise_3dv(v), noise.get_noise_3dv(v + Vector3(31.0, 0.0, 0.0)) * 0.4, noise.get_noise_3dv(v + Vector3(0.0, 0.0, 57.0))) * warp * f
			if bend != 0.0:
				v += Vector3(bdir.x, 0.0, bdir.y) * bend * h * scale.y * f * f
			verts[i] = v
			norms[i] = n
			if has_tan:
				var tg := Vector3(tans[i * 4], tans[i * 4 + 1], tans[i * 4 + 2]) * scale
				tg = tg.rotated(Vector3.UP, a).normalized() if a != 0.0 else tg.normalized()
				tans[i * 4] = tg.x
				tans[i * 4 + 1] = tg.y
				tans[i * 4 + 2] = tg.z
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		if has_tan:
			arrays[Mesh.ARRAY_TANGENT] = tans
		var out_mat := mat
		if leafy:
			var cm := (mat as ShaderMaterial).duplicate() as ShaderMaterial
			var c2 := center * scale
			var cf := clampf(c2.y / (h * scale.y), 0.0, 1.0)
			cm.set_shader_parameter("canopy_center", c2 + Vector3(bdir.x, 0.0, bdir.y) * bend * h * scale.y * cf * cf)
			cm.set_shader_parameter("canopy_radius", float(cm.get_shader_parameter("canopy_radius")) * crown * maxf(scale.x, scale.y))
			wind_materials.append(cm)
			out_mat = cm
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, out_mat)
	im.generate_lods(25.0, 60.0, [])
	var m := im.get_mesh()
	m.resource_name = key
	_meshes[key] = m
	return m


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r:
			return r
	return null


func _material_for(model: String, variant: String, mat_name: String, m: ArrayMesh, surface: int) -> Material:
	if mat_name.begins_with("Bark_"):
		return bark_material(mat_name if variant != "pale" else "Bark_Pale")
	match mat_name:
		"Leaves_NormalTree", "Leaves_TwistedTree", "Leaves_Pine", "Leaves_GiantPine":
			return _kit_canopy(model, mat_name, m, surface)
		"Leaves", "Flowers":
			if variant == "lotus":
				return _lotus_material()
			return _kit_plant(model, mat_name)
		"Grass":
			return grass_material(model, 0.5, false)
		"Mushrooms":
			return mushroom_material(variant == "glow")
		"PathRocks":
			return rock_material("PathRocks_Diffuse", 0.35)
		"Rocks":
			return rock_material("Rocks_Diffuse", 0.6)
	push_warning("NatureKit: unknown material %s on %s" % [mat_name, model])
	return StandardMaterial3D.new()


func _kit_canopy(model: String, mat_name: String, m: ArrayMesh, surface: int) -> ShaderMaterial:
	var arrays := m.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var aabb := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		aabb = aabb.expand(v)
	var center := aabb.get_center()
	var radius := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * 0.5
	var palette := "common"
	var tex := "Leaves_NormalTree"
	var stiff := 1.0
	if model.begins_with("Twisted"):
		palette = "twisted"
		tex = "Leaves_TwistedTree_C"
		stiff = 1.6
	elif model.begins_with("Pine"):
		palette = "pine"
		tex = "Leaf_Pine_C"
		stiff = 1.3
	elif model.begins_with("Bush"):
		palette = "bush"
		tex = "Leaves_TwistedTree_C" if mat_name == "Leaves_TwistedTree" else "Leaves_NormalTree"
		stiff = 0.35
	return canopy_material(palette, texture(tex), center, radius, stiff)


func canopy_material(palette: String, tex: Texture2D, center: Vector3, radius: float, stiffness: float = 1.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SH_CANOPY
	var p: Array = PALETTES[palette]
	mat.set_shader_parameter("leaf_tex", tex)
	mat.set_shader_parameter("color_low", p[0])
	mat.set_shader_parameter("color_high", p[1])
	mat.set_shader_parameter("alt_low", p[2])
	mat.set_shader_parameter("alt_high", p[3])
	mat.set_shader_parameter("canopy_center", center)
	mat.set_shader_parameter("canopy_radius", radius)
	mat.set_shader_parameter("stiffness", stiffness)
	wind_materials.append(mat)
	return mat


func bark_material(kind: String) -> ShaderMaterial:
	if _bark.has(kind):
		return _bark[kind]
	var b: Array = BARK[kind]
	var mat := ShaderMaterial.new()
	mat.shader = SH_BARK
	mat.set_shader_parameter("bark_tex", texture(b[0]))
	mat.set_shader_parameter("bark_normal", texture(b[1]))
	mat.set_shader_parameter("noise_tex", NOISE)
	mat.set_shader_parameter("tint", b[2])
	mat.set_shader_parameter("moss_amount", b[3])
	if kind == "Bark_TwistedTree":
		mat.set_shader_parameter("stiffness", 1.6)
	wind_materials.append(mat)
	_bark[kind] = mat
	return mat


func _kit_plant(model: String, mat_name: String) -> ShaderMaterial:
	var key := model + "/" + mat_name
	if _plain.has(key):
		return _plain[key]
	var mat := ShaderMaterial.new()
	mat.shader = SH_PLANT
	mat.set_shader_parameter("albedo_tex", texture(mat_name))
	_apply_ground(mat)
	var bend := 1.0
	var fade := Vector2(26.0, 36.0)
	var stiff := 1.0
	if model.begins_with("Fern"):
		bend = 2.2
		stiff = 1.4
		fade = Vector2(32.0, 44.0)
	elif model.begins_with("Plant_1"):
		bend = 1.6 if model.ends_with("Big") else 0.8
		fade = Vector2(30.0, 40.0)
	elif model.begins_with("Plant_7"):
		bend = 0.4
		stiff = 3.0
	elif model.begins_with("Flower"):
		bend = 1.7
		mat.set_shader_parameter("translucency", 0.7)
	elif model.begins_with("Clover"):
		bend = 1.0
	elif model.begins_with("Petal"):
		mat.set_shader_parameter("use_alpha", true)
	mat.set_shader_parameter("bend_height", bend)
	mat.set_shader_parameter("stiffness", stiff)
	mat.set_shader_parameter("fade_start", fade.x)
	mat.set_shader_parameter("fade_end", fade.y)
	mat.set_shader_parameter("up_normal", 0.35)
	wind_materials.append(mat)
	interactive_materials.append(mat)
	_plain[key] = mat
	return mat


func _lotus_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SH_PLANT
	mat.set_shader_parameter("albedo_tex", texture("Flowers"))
	mat.set_shader_parameter("tint", Color(1.0, 0.82, 0.92))
	mat.set_shader_parameter("stiffness", 60.0)
	mat.set_shader_parameter("glow", 0.9)
	mat.set_shader_parameter("glow_color", Color(1.0, 0.55, 0.85))
	mat.set_shader_parameter("hue_variation", 0.0)
	mat.set_shader_parameter("up_normal", 0.3)
	mat.set_shader_parameter("translucency", 1.0)
	mat.set_shader_parameter("fade_start", 60.0)
	mat.set_shader_parameter("fade_end", 70.0)
	return mat


func grass_material(key: String, bend: float, procedural: bool) -> ShaderMaterial:
	var k := "grass/" + key
	if _plain.has(k):
		return _plain[k]
	var mat := ShaderMaterial.new()
	mat.shader = SH_PLANT
	mat.set_shader_parameter("ground_tint", true)
	mat.set_shader_parameter("use_alpha", not procedural)
	mat.set_shader_parameter("albedo_tex", texture("Grass"))
	mat.set_shader_parameter("bend_height", bend)
	mat.set_shader_parameter("up_normal", 0.75)
	mat.set_shader_parameter("translucency", 0.55)
	mat.set_shader_parameter("fade_start", 20.0 if procedural else 26.0)
	mat.set_shader_parameter("fade_end", 28.0 if procedural else 36.0)
	_apply_ground(mat)
	wind_materials.append(mat)
	interactive_materials.append(mat)
	_plain[k] = mat
	return mat


func rock_material(tex: String, moss: float) -> ShaderMaterial:
	var k := "rock/" + tex
	if _plain.has(k):
		return _plain[k]
	var mat := ShaderMaterial.new()
	mat.shader = SH_ROCK
	mat.set_shader_parameter("albedo_tex", texture(tex))
	mat.set_shader_parameter("noise_tex", NOISE)
	mat.set_shader_parameter("moss_amount", moss)
	_plain[k] = mat
	return mat


func mushroom_material(glow: bool) -> ShaderMaterial:
	var k := "mushroom/%s" % glow
	if _plain.has(k):
		return _plain[k]
	var mat := ShaderMaterial.new()
	mat.shader = SH_MUSHROOM
	mat.set_shader_parameter("albedo_tex", texture("Mushrooms"))
	mat.set_shader_parameter("glow", 2.6 if glow else 0.0)
	_plain[k] = mat
	return mat


func terrain_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SH_TERRAIN
	mat.set_shader_parameter("rock_tex", texture("Rocks_Diffuse"))
	_apply_ground(mat)
	return mat


func water_material(flowing: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SH_WATER
	mat.set_shader_parameter("water_noise", WATER_NOISE)
	mat.set_shader_parameter("caustic_tex", CAUSTICS)
	mat.set_shader_parameter("flowing", flowing)
	mat.set_shader_parameter("ripples", not flowing)
	mat.set_shader_parameter("light_dir", ForestAtmosphere.light_direction())
	# Fewer reflection steps on phones; the march fades out gracefully.
	mat.set_shader_parameter("ssr_steps", 6 if OS.has_feature("mobile") else 10)
	if flowing:
		mat.set_shader_parameter("absorption", Vector3(0.5, 0.2, 0.16))
		mat.set_shader_parameter("scatter_color", Color(0.09, 0.26, 0.2))
	interactive_materials.append(mat)
	return mat


func waterfall_material() -> ShaderMaterial:
	if _plain.has("waterfall"):
		return _plain["waterfall"]
	var mat := ShaderMaterial.new()
	mat.shader = SH_WATERFALL
	mat.set_shader_parameter("water_noise", WATER_NOISE)
	_plain["waterfall"] = mat
	return mat


## Soft white puffs for spray and mist.
func mist_material() -> StandardMaterial3D:
	if _plain.has("mist"):
		return _plain["mist"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.albedo_color = Color(0.86, 0.9, 0.92, 0.7)
	m.disable_receive_shadows = true
	_plain["mist"] = m
	return m


func _apply_ground(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("ground_noise", NOISE)


func set_wind(direction: Vector3, strength: float) -> void:
	for m in wind_materials:
		m.set_shader_parameter("wind_direction", direction)
		m.set_shader_parameter("wind_strength", strength)


## Up to four Kelings part the grass as they walk through it.
func set_interactors(points: Array[Vector3]) -> void:
	for i in 4:
		var v := Vector4(0.0, -1000.0, 0.0, 0.9)
		if i < points.size():
			v = Vector4(points[i].x, points[i].y, points[i].z, 0.95)
		var pname := "interactor_%d" % i
		for m in interactive_materials:
			m.set_shader_parameter(pname, v)


# ----------------------------------------------------------------------------
# Procedural grass

## A tuft of curved, tapering blades. COLOR.r carries 0 at the root to 1 at the
## tip; the shader uses it for colour, wind and parting.
func grass_tuft(seed: int, blades: int, height: float, spread: float, kind: String = "tuft") -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for b in blades:
		var r := sqrt(rng.randf()) * spread
		var a := rng.randf() * TAU
		var base := Vector3(cos(a) * r, -0.04, sin(a) * r)
		var h := height * rng.randf_range(0.55, 1.15)
		var w := rng.randf_range(0.035, 0.06) * (height / 0.6)
		var face := rng.randf() * TAU
		var side := Vector3(cos(face), 0.0, sin(face))
		var lean := (Vector3(cos(a), 0.0, sin(a)) * 0.6 + Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1)) * 0.5)
		lean *= h * rng.randf_range(0.15, 0.4)
		var n := side.cross(Vector3.UP).normalized()
		var start := verts.size()
		var levels := 3
		for l in levels:
			var t := float(l) / levels
			var c := base + Vector3.UP * h * t + lean * t * t
			var hw := w * (1.0 - t * 0.55)
			verts.append(c - side * hw)
			verts.append(c + side * hw)
			for k in 2:
				norms.append(n)
				cols.append(Color(t, 0.0, 0.0))
			uvs.append(Vector2(0.0, 1.0 - t))
			uvs.append(Vector2(1.0, 1.0 - t))
		verts.append(base + Vector3.UP * h + lean)
		norms.append(n)
		cols.append(Color(1.0, 0.0, 0.0))
		uvs.append(Vector2(0.5, 0.0))
		for l in levels - 1:
			var i0 := start + l * 2
			idx.append_array([i0, i0 + 2, i0 + 1, i0 + 1, i0 + 2, i0 + 3])
		var top := start + (levels - 1) * 2
		idx.append_array([top, top + 2, top + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, grass_material(kind, height, true))
	return m
