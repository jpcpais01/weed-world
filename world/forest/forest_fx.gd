class_name ForestFX
extends RefCounted
## The magic: sun shafts through the canopy, fireflies, drifting pollen,
## blossom petals in the grove, spirit wisps around the Elder, glow lights in
## the hollow and a crackling campfire at the overlook.

const SH_GODRAY := preload("res://world/forest/shaders/godray.gdshader")
const SH_WISP := preload("res://world/forest/shaders/wisp.gdshader")

var layout: ForestLayout
var terrain: ForestTerrain
var kit: NatureKit
var scatter: ForestScatter
var water: ForestWater
var rng := RandomNumberGenerator.new()
var flicker_lights: Array[OmniLight3D] = []
var _glow_tex: Texture2D


func _init(p_layout: ForestLayout, p_terrain: ForestTerrain, p_kit: NatureKit, p_scatter: ForestScatter, p_water: ForestWater) -> void:
	layout = p_layout
	terrain = p_terrain
	kit = p_kit
	scatter = p_scatter
	water = p_water
	rng.seed = ForestLayout.SEED + 77


func build(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Magic"
	parent.add_child(root)
	_godrays(root)
	_fireflies(root)
	_pollen(root)
	_petals(root)
	_seeds(root)
	_mist(root)
	_wisps(root)
	_lights(root)
	_campfire(root)


func _ground(p: Vector2, lift: float = 0.0) -> Vector3:
	return Vector3(p.x, terrain.height_at(p.x, p.y) + lift, p.y)


func glow_texture() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.25, Color(1, 1, 1, 0.55))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_glow_tex = t
	return _glow_tex


func _spark_material(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = glow_texture()
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, 1.0)
	m.disable_receive_shadows = true
	m.disable_fog = false
	return m


# ----------------------------------------------------------------------------
# Light shafts

func _godrays(root: Node3D) -> void:
	var dir := ForestAtmosphere.light_direction()
	var spots: Array[Vector4] = []   # x, z, width, length
	# Through the western treeline into the glade, where the sun rakes in.
	for k in 7:
		var a := deg_to_rad(lerpf(130.0, 230.0, k / 6.0))
		var p := ForestLayout.GLADE + Vector2(cos(a), sin(a)) * rng.randf_range(9.0, 14.0)
		spots.append(Vector4(p.x, p.y, rng.randf_range(0.5, 0.9), rng.randf_range(0.6, 0.85)))
	# Around the Elder's crown.
	for k in 5:
		var p := ForestLayout.ELDER + Vector2(rng.randf_range(-7, 7), rng.randf_range(-7, 7))
		spots.append(Vector4(p.x, p.y, rng.randf_range(0.4, 0.8), rng.randf_range(0.7, 0.95)))
	# Over the pond and in the blossom grove.
	for k in 4:
		var p := ForestLayout.POND + Vector2(rng.randf_range(-8, 6), rng.randf_range(-6, 6))
		spots.append(Vector4(p.x, p.y, rng.randf_range(0.4, 0.7), rng.randf_range(0.55, 0.8)))
	for k in 5:
		var p := ForestLayout.GROVE + Vector2(rng.randf_range(-9, 9), rng.randf_range(-9, 9))
		spots.append(Vector4(p.x, p.y, rng.randf_range(0.4, 0.8), rng.randf_range(0.55, 0.8)))
	# Scattered through the deeper forest.
	for k in 14:
		var p := Vector2(rng.randf_range(-44, 44), rng.randf_range(-44, 44))
		if terrain.shade_at(p.x, p.y) < 0.25:
			continue
		spots.append(Vector4(p.x, p.y, rng.randf_range(0.3, 0.6), rng.randf_range(0.5, 0.8)))

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := ShaderMaterial.new()
	mat.shader = SH_GODRAY
	mat.set_shader_parameter("light_dir", dir)
	mat.set_shader_parameter("noise_tex", NatureKit.NOISE)
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = spots.size()
	for i in spots.size():
		var s := spots[i]
		var length := s.w * 30.0
		var ground := _ground(Vector2(s.x, s.y))
		# Anchor the top of the shaft up in the canopy, back along the light.
		var top := ground - dir * length * 0.8
		mm.set_instance_transform(i, Transform3D(Basis(), top))
		mm.set_instance_custom_data(i, Color(s.z, s.w, rng.randf(), rng.randf_range(0.6, 1.0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "SunShafts"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-80, -20, -80), Vector3(160, 60, 160))
	root.add_child(mmi)


# ----------------------------------------------------------------------------
# Particles

func _emitter(name: String, center: Vector3, extents: Vector3, amount: int, lifetime: float,
		color: Color, energy: float, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = name
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.randomness = 0.6
	p.visibility_aabb = AABB(-extents - Vector3.ONE * 2.0, extents * 2.0 + Vector3.ONE * 4.0)
	p.position = center
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.gravity = Vector3.ZERO
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 3.5
	pm.turbulence_noise_speed_random = 0.4
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.15, Color(1, 1, 1, 1))
	ramp.add_point(0.35, Color(1, 1, 1, 0.25))
	ramp.add_point(0.5, Color(1, 1, 1, 1))
	ramp.add_point(0.75, Color(1, 1, 1, 0.4))
	ramp.add_point(0.88, Color(1, 1, 1, 0.9))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _spark_material(color, energy)
	p.draw_pass_1 = q
	return p


func _fireflies(root: Node3D) -> void:
	var zones := [
		[ForestLayout.HOLLOW, Vector3(12, 1.6, 12), 90],
		[ForestLayout.ELDER, Vector3(8, 2.0, 8), 60],
		[ForestLayout.POND, Vector3(9, 1.2, 9), 50],
		[Vector2(24.0, 18.0), Vector3(6, 1.2, 10), 40],
		[ForestLayout.GROVE, Vector3(10, 1.5, 10), 40],
		[ForestLayout.GLADE + Vector2(-12, 0), Vector3(5, 1.2, 9), 30],
	]
	for z in zones:
		var c: Vector2 = z[0]
		var e: Vector3 = z[1]
		var p := _emitter("Fireflies", _ground(c, e.y + 0.4), e, z[2], 9.0, Color(0.75, 1.0, 0.35), 5.0, 0.07)
		root.add_child(p)


func _pollen(root: Node3D) -> void:
	# Warm dust motes hanging in the sunlit air of the glade and the pond.
	for c in [ForestLayout.GLADE, ForestLayout.POND, ForestLayout.OVERLOOK]:
		var p := _emitter("Pollen", _ground(c, 2.4), Vector3(11, 2.2, 11), 60, 12.0, Color(1.0, 0.85, 0.6), 0.55, 0.025)
		var pm: ParticleProcessMaterial = p.process_material
		pm.turbulence_noise_strength = 0.6
		pm.initial_velocity_max = 0.12
		root.add_child(p)


func _petals(root: Node3D) -> void:
	var p := GPUParticles3D.new()
	p.name = "BlossomPetals"
	p.amount = 70
	p.lifetime = 10.0
	p.preprocess = 10.0
	p.position = _ground(ForestLayout.GROVE, 6.0)
	p.visibility_aabb = AABB(Vector3(-16, -9, -16), Vector3(32, 14, 32))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(12, 1.5, 12)
	pm.gravity = Vector3(0.25, -0.45, 0.12)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.2
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	pm.particle_flag_rotate_y = true
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.0
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.25
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.06)
	var m := StandardMaterial3D.new()
	m.albedo_texture = glow_texture()
	m.albedo_color = Color(1.0, 0.68, 0.84)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.backlight_enabled = true
	m.backlight = Color(0.9, 0.5, 0.6)
	m.emission_enabled = true
	m.emission = Color(0.5, 0.2, 0.3)
	q.material = m
	p.draw_pass_1 = q
	root.add_child(p)


## Dandelion and thistle down floating on the breeze across the meadow.
func _seeds(root: Node3D) -> void:
	for c in [ForestLayout.GLADE, ForestLayout.GLADE + Vector2(-10, 14), ForestLayout.OVERLOOK]:
		var p := _emitter("Thistledown", _ground(c, 1.6), Vector3(10, 1.4, 10), 26, 16.0, Color(1.0, 0.97, 0.9), 0.9, 0.05)
		var pm: ParticleProcessMaterial = p.process_material
		pm.gravity = Vector3(0.12, 0.015, 0.07)
		pm.turbulence_noise_strength = 0.9
		pm.turbulence_influence_max = 0.08
		var q: QuadMesh = p.draw_pass_1
		var m: StandardMaterial3D = q.material
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		root.add_child(p)


## Low banks of mist breathing over the pond, the stream and the hollow.
func _mist(root: Node3D) -> void:
	var spots := [
		[_ground(ForestLayout.POND, 0.0) * Vector3(1, 0, 1) + Vector3(0, terrain.pond_level + 0.5, 0), Vector3(5, 0.25, 5), 9],
		[_ground(ForestLayout.HOLLOW, 0.6), Vector3(9, 0.3, 9), 10],
		[_ground(ForestLayout.STREAM_CROSSING + Vector2(4, 12), 0.5), Vector3(4, 0.2, 9), 7],
	]
	for sp in spots:
		var p := GPUParticles3D.new()
		p.name = "Mist"
		p.position = sp[0]
		p.amount = sp[2]
		p.lifetime = 14.0
		p.preprocess = 14.0
		var e: Vector3 = sp[1]
		p.visibility_aabb = AABB(-e - Vector3(4, 2, 4), e * 2.0 + Vector3(8, 5, 8))
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.sorting_offset = -2.0
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = e
		pm.gravity = Vector3(0.06, 0.0, 0.035)
		pm.initial_velocity_min = 0.0
		pm.initial_velocity_max = 0.08
		pm.scale_min = 0.8
		pm.scale_max = 1.4
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 0))
		ramp.set_color(1, Color(1, 1, 1, 0))
		ramp.add_point(0.5, Color(1, 1, 1, 0.16))
		var rt := GradientTexture1D.new()
		rt.gradient = ramp
		pm.color_ramp = rt
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(3.2, 1.6)
		q.material = kit.mist_material()
		p.draw_pass_1 = q
		root.add_child(p)


func _wisps(root: Node3D) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 10
	sphere.rings = 6
	var mat := ShaderMaterial.new()
	mat.shader = SH_WISP
	sphere.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = sphere
	var xf: Array[Transform3D] = []
	var cd: Array[Color] = []
	var crown: Vector3 = scatter.hero.get("elder_crown", _ground(ForestLayout.ELDER, 10.0))
	for k in 34:
		var a := rng.randf() * TAU
		var r := rng.randf_range(2.0, 9.0)
		var h := rng.randf_range(-7.0, 4.0)
		var pos := crown + Vector3(cos(a) * r, h, sin(a) * r)
		pos.y = maxf(pos.y, terrain.height_at(pos.x, pos.z) + 0.8)
		var s := rng.randf_range(0.07, 0.16)
		xf.append(Transform3D(Basis().scaled(Vector3.ONE * s), pos))
		cd.append(Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	# More hover low over the fairy ring.
	for p: Vector3 in scatter.hero.get("fairy_ring", []):
		if rng.randf() < 0.45:
			xf.append(Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.05, 0.09)), p + Vector3(0, rng.randf_range(0.6, 1.4), 0)))
			cd.append(Color(rng.randf() * 0.4, rng.randf(), rng.randf(), rng.randf() * 0.4))
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_custom_data(i, cd[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "ElderWisps"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	mmi.custom_aabb = AABB(crown - Vector3(14, 16, 14), Vector3(28, 26, 28))


func _omni(root: Node3D, pos: Vector3, color: Color, energy: float, range: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range
	l.omni_attenuation = 1.6
	l.shadow_enabled = false
	l.light_specular = 0.2
	root.add_child(l)
	return l


func _lights(root: Node3D) -> void:
	var e: Vector3 = scatter.hero.get("elder_base", _ground(ForestLayout.ELDER))
	_omni(root, e + Vector3(0, 1.2, 0), Color(0.45, 0.95, 0.95), 2.2, 10.0).name = "FairyRingGlow"
	_omni(root, _ground(ForestLayout.HOLLOW + Vector2(-2, 3), 1.0), Color(0.35, 0.9, 1.0), 1.6, 9.0).name = "HollowGlowA"
	_omni(root, _ground(ForestLayout.HOLLOW + Vector2(5, -6), 1.0), Color(0.75, 0.45, 1.0), 1.4, 8.0).name = "HollowGlowB"
	if not water.lotus_points.is_empty():
		var c := Vector3.ZERO
		for p in water.lotus_points:
			c += p
		c /= water.lotus_points.size()
		_omni(root, c + Vector3(0, 0.5, 0), Color(1.0, 0.5, 0.8), 0.9, 6.0).name = "LotusGlow"


func _campfire(root: Node3D) -> void:
	var o := ForestLayout.OVERLOOK + ForestLayout.vista_dir() * 0.5
	var base := _ground(o)
	var fire := Node3D.new()
	fire.name = "Campfire"
	fire.position = base
	root.add_child(fire)
	# Ring of stones.
	var peb := ["Pebble_Round_1", "Pebble_Round_2", "Pebble_Round_3"]
	for k in 10:
		var a := TAU * k / 10.0
		var mi := MeshInstance3D.new()
		mi.mesh = kit.mesh(peb[k % 3])
		mi.position = Vector3(cos(a) * 0.62, -0.03, sin(a) * 0.62)
		mi.rotation.y = rng.randf() * TAU
		mi.scale = Vector3.ONE * rng.randf_range(1.3, 1.8)
		fire.add_child(mi)
	# Crossed firewood.
	var wood := CylinderMesh.new()
	wood.top_radius = 0.06
	wood.bottom_radius = 0.07
	wood.height = 0.75
	wood.radial_segments = 6
	wood.material = kit.bark_material("Bark_DeadTree")
	for k in 4:
		var mi := MeshInstance3D.new()
		mi.mesh = wood
		mi.rotation = Vector3(deg_to_rad(68.0), TAU * k / 4.0 + 0.3, 0.0)
		mi.position = Vector3(0, 0.18, 0)
		fire.add_child(mi)
	# Flames: additive licks rising and shrinking.
	var flames := GPUParticles3D.new()
	flames.name = "Flames"
	flames.amount = 26
	flames.lifetime = 0.9
	flames.position = Vector3(0, 0.15, 0)
	flames.visibility_aabb = AABB(Vector3(-1, -0.5, -1), Vector3(2, 3, 2))
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fpm := ParticleProcessMaterial.new()
	fpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fpm.emission_sphere_radius = 0.18
	fpm.direction = Vector3.UP
	fpm.spread = 12.0
	fpm.gravity = Vector3(0, 1.2, 0)
	fpm.initial_velocity_min = 0.3
	fpm.initial_velocity_max = 0.7
	fpm.scale_min = 0.7
	fpm.scale_max = 1.2
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.6))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1.0, 0.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	fpm.scale_curve = sct
	var fr := Gradient.new()
	fr.set_color(0, Color(1.0, 0.9, 0.5, 1.0))
	fr.set_color(1, Color(0.9, 0.15, 0.02, 0.0))
	fr.add_point(0.45, Color(1.0, 0.45, 0.08, 0.8))
	var frt := GradientTexture1D.new()
	frt.gradient = fr
	fpm.color_ramp = frt
	flames.process_material = fpm
	var fq := QuadMesh.new()
	fq.size = Vector2(0.45, 0.55)
	fq.material = _spark_material(Color(1.0, 0.6, 0.25), 3.5)
	flames.draw_pass_1 = fq
	fire.add_child(flames)
	# Embers spiralling up into the dusk.
	var embers := _emitter("Embers", Vector3(0, 1.4, 0), Vector3(0.25, 1.2, 0.25), 18, 2.5, Color(1.0, 0.5, 0.15), 6.0, 0.035)
	var epm: ParticleProcessMaterial = embers.process_material
	epm.gravity = Vector3(0, 0.5, 0)
	epm.turbulence_noise_strength = 2.5
	embers.position = Vector3(0, 0.6, 0)
	fire.add_child(embers)
	var light := _omni(fire, Vector3(0, 0.7, 0), Color(1.0, 0.55, 0.22), 2.4, 7.0)
	light.name = "FireLight"
	flicker_lights.append(light)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.75
	cyl.height = 0.4
	cs.shape = cyl
	cs.position = Vector3(0, 0.1, 0)
	body.add_child(cs)
	fire.add_child(body)


func flicker(time: float) -> void:
	for l in flicker_lights:
		var f := 0.75 + 0.15 * sin(time * 11.0) + 0.1 * sin(time * 23.0 + 1.3) + 0.08 * sin(time * 4.3)
		l.light_energy = 2.4 * f
