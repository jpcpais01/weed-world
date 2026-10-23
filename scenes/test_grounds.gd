extends Node3D
## Movement test grounds: an open meadow-tinted grid with a small obstacle
## course off to the side (jump blocks, ramps, a tower to drop from, a slalom
## and a bumpy slope for the foot IK). Built in code so it stays easy to tweak.

const GRID_SHADER := preload("res://scenes/materials/proto_grid.gdshader")

var _materials := {}
var _motes: GPUParticles3D


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_course()
	_build_motes()


func _material(key: String, base: Color, alt: Color, line: Color) -> ShaderMaterial:
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = GRID_SHADER
		m.set_shader_parameter("base_color", base)
		m.set_shader_parameter("alt_color", alt)
		m.set_shader_parameter("line_color", line)
		_materials[key] = m
	return _materials[key]


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.52, 0.78)
	sky_mat.sky_horizon_color = Color(0.78, 0.84, 0.82)
	sky_mat.ground_horizon_color = Color(0.62, 0.68, 0.6)
	sky_mat.ground_bottom_color = Color(0.2, 0.25, 0.2)
	sky_mat.sun_angle_max = 20.0
	sky_mat.sky_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.85
	env.ambient_light_energy = 1.05
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.8, 0.78)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)


func _build_ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(240, 240)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material("ground", Color(0.36, 0.47, 0.33), Color(0.33, 0.44, 0.31), Color(0.86, 0.96, 0.78))
	add_child(mi)
	_static_box(Vector3(240, 1, 240), Transform3D(Basis.IDENTITY, Vector3(0, -0.5, 0)))

	# Spawn ring.
	var ring := TorusMesh.new()
	ring.inner_radius = 1.15
	ring.outer_radius = 1.25
	ring.rings = 48
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.scale = Vector3(1, 0.05, 1)
	ring_mi.position.y = 0.005
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.85, 1.0, 0.7)
	glow.emission_enabled = true
	glow.emission = Color(0.6, 1.0, 0.45)
	glow.emission_energy_multiplier = 1.6
	ring_mi.material_override = glow
	add_child(ring_mi)


func _build_course() -> void:
	var stone := _material("stone", Color(0.6, 0.58, 0.52), Color(0.55, 0.53, 0.48), Color(0.95, 0.93, 0.85))
	var warm := _material("warm", Color(0.72, 0.55, 0.38), Color(0.67, 0.5, 0.35), Color(0.98, 0.9, 0.75))
	var moss := _material("moss", Color(0.42, 0.55, 0.36), Color(0.38, 0.5, 0.33), Color(0.9, 1.0, 0.8))

	# Jump blocks of rising height (the Keling clears ~0.8 m).
	var heights := [0.25, 0.45, 0.65, 0.85]
	for i in heights.size():
		var h: float = heights[i]
		_block(Vector3(1.6, h, 1.6), Vector3(7.0 + i * 2.4, h * 0.5, 6.0), warm)

	# Ramps up to two platforms, and a tower to drop from.
	_ramp(Vector3(-8.0, 0, 3.0), 6.0, 1.2, 2.4, stone)  # ~11 deg
	_block(Vector3(3.0, 1.2, 3.0), Vector3(-8.0, 0.6, 10.5), stone)
	_ramp(Vector3(-13.0, 0, 3.5), 5.0, 2.4, 2.4, stone)  # ~26 deg
	_block(Vector3(3.0, 2.4, 3.0), Vector3(-13.0, 1.2, 10.0), stone)
	_block(Vector3(2.0, 3.4, 2.0), Vector3(-13.0, 1.7, 12.5), warm)
	_block(Vector3(1.4, 0.6, 1.4), Vector3(-13.0, 2.7, 10.4), warm)  # step up to the tower top

	# Slalom posts for carving turns.
	for i in 7:
		var post := CylinderMesh.new()
		post.top_radius = 0.18
		post.bottom_radius = 0.22
		post.height = 1.4
		var x := 3.0 + i * 3.0
		var z := -9.0 + (1.2 if i % 2 == 0 else -1.2)
		var mi := MeshInstance3D.new()
		mi.mesh = post
		mi.material_override = moss
		mi.position = Vector3(x, 0.7, z)
		add_child(mi)
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.2
		cyl.height = 1.4
		shape.shape = cyl
		body.add_child(shape)
		body.position = mi.position
		add_child(body)

	# Bumpy slope: tilted slabs for the foot IK.
	for i in 6:
		var tilt := deg_to_rad(8.0 + i * 3.0) * (1 if i % 2 == 0 else -1)
		var b := Basis(Vector3.FORWARD, tilt)
		_block_basis(Vector3(2.2, 0.4, 2.2), Transform3D(b, Vector3(-6.0 - i * 2.6, 0.05, -8.0)), moss)

	# A low wall with a gap to run through, and a long beam to balance on.
	_block(Vector3(6.0, 0.9, 0.5), Vector3(16.0, 0.45, 14.0), stone)
	_block(Vector3(6.0, 0.9, 0.5), Vector3(24.0, 0.45, 14.0), stone)
	_block(Vector3(0.35, 0.35, 10.0), Vector3(0.0, 0.175, -18.0), warm)

	# Herb patch to practise grabbing: low tufts, a ledge, and a hanging vine.
	for p in [Vector3(2.4, 0, 2.6), Vector3(3.1, 0, 3.4), Vector3(2.2, 0, 3.9)]:
		var herb := Herb.new()
		herb.position = p
		add_child(herb)
	_block(Vector3(1.2, 0.3, 0.8), Vector3(4.6, 0.15, 2.4), stone)
	for x in [4.3, 4.9]:
		var herb := Herb.new()
		herb.height = 0.3
		herb.position = Vector3(x, 0.3, 2.1)
		add_child(herb)
	var post := CylinderMesh.new()
	post.top_radius = 0.06
	post.bottom_radius = 0.08
	post.height = 1.6
	var post_mi := MeshInstance3D.new()
	post_mi.mesh = post
	post_mi.material_override = warm
	post_mi.position = Vector3(6.2, 0.8, 3.6)
	add_child(post_mi)
	_block(Vector3(0.7, 0.08, 0.08), Vector3(5.95, 1.55, 3.6), warm)
	var vine := Herb.new()
	vine.hanging = true
	vine.height = 0.5
	vine.position = Vector3(5.75, 1.51, 3.6)
	add_child(vine)

	# Distance markers every 5 m along the open run.
	for i in range(1, 9):
		var m := BoxMesh.new()
		m.size = Vector3(0.08, 0.3, 0.08)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = stone
		mi.position = Vector3(-3.0, 0.15, -i * 5.0)
		add_child(mi)


func _block(size: Vector3, pos: Vector3, mat: Material) -> void:
	_block_basis(size, Transform3D(Basis.IDENTITY, pos), mat)


func _block_basis(size: Vector3, xform: Transform3D, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xform
	add_child(mi)
	_static_box(size, xform)


## A ramp rising along +Z from `start` (ground level) to `height` over `length`.
func _ramp(start: Vector3, length: float, height: float, width: float, mat: Material) -> void:
	var angle := atan2(height, length)
	var slope_len := sqrt(length * length + height * height)
	var thickness := 0.4
	var b := Basis(Vector3.RIGHT, -angle)
	var center := start + Vector3(0, height * 0.5, length * 0.5) + b * Vector3(0, -thickness * 0.5, 0)
	_block_basis(Vector3(width, thickness, slope_len), Transform3D(b, center), mat)


func _static_box(size: Vector3, xform: Transform3D) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.transform = xform
	add_child(body)


func _build_motes() -> void:
	# Drifting glowing motes around the player for a touch of magic.
	var motes := GPUParticles3D.new()
	motes.name = "Motes"
	motes.amount = 70
	motes.lifetime = 7.0
	motes.preprocess = 7.0
	motes.local_coords = false
	motes.visibility_aabb = AABB(Vector3(-14, -2, -14), Vector3(28, 10, 28))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(12, 2.5, 12)
	pm.gravity = Vector3(0, 0.04, 0)
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.12
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_speed_random = 0.4
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	motes.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.85, 1.0, 0.55) * 2.2
	quad.material = mat
	motes.draw_pass_1 = quad
	motes.position = Vector3(0, 1.5, 0)
	add_child(motes)
	_motes = motes


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if _motes and player:
		_motes.global_position = player.global_position + Vector3(0, 1.5, 0)
