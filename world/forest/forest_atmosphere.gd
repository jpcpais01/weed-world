class_name ForestAtmosphere
extends RefCounted
## Golden-hour lighting built for the Mobile renderer: a low warm sun with
## soft long shadows, a cool sky-bounce fill light that stands in for global
## illumination, a painted sky, sun-scattered aerial haze with valley mist,
## filmic tonemapping and bloom so glowing things really glow.

const SH_SKY := preload("res://world/forest/shaders/sky.gdshader")
const SH_DISTANT := preload("res://world/forest/shaders/distant.gdshader")

## Direction *towards* the sun: low in the west-south-west, so the glade gets
## raking side light and the overlook looks straight into the sunset.
const SUN_TOWARDS := Vector3(-0.83, 0.40, 0.39)

var sun: DirectionalLight3D
var fill: DirectionalLight3D
var environment: Environment


static func light_direction() -> Vector3:
	return -SUN_TOWARDS.normalized()


func build(parent: Node3D) -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.80, 0.58)
	sun.light_energy = 2.1
	sun.light_indirect_energy = 1.0
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.22
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 75.0
	sun.directional_shadow_fade_start = 0.85
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	parent.add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, light_direction(), Vector3.UP)

	# Cool bounce light from the opposite sky; keeps shadowed sides shaped and
	# blue instead of flat grey. No shadows, invisible in the sky.
	fill = DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.light_color = Color(0.55, 0.68, 1.0)
	fill.light_energy = 0.32
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	parent.add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, Vector3(SUN_TOWARDS.x, -0.6, SUN_TOWARDS.z).normalized(), Vector3.UP)

	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SH_SKY
	sky_mat.set_shader_parameter("cloud_noise", NatureKit.NOISE)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Mostly sky light, plus a constant cool floor so shade never goes inky.
	environment.ambient_light_color = Color(0.52, 0.6, 0.72)
	environment.ambient_light_sky_contribution = 0.8
	environment.ambient_light_energy = 0.85
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.92
	environment.tonemap_white = 6.0

	environment.glow_enabled = true
	environment.glow_normalized = false
	environment.glow_intensity = 0.75
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 0.95
	environment.glow_hdr_scale = 2.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	for i in 7:
		environment.set_glow_level(i, 1.0 if i in [1, 2, 3, 4] else 0.0)

	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_color = Color(0.70, 0.73, 0.78)
	environment.fog_light_energy = 0.9
	environment.fog_sun_scatter = 0.42
	environment.fog_density = 0.0085
	environment.fog_aerial_perspective = 0.55
	environment.fog_sky_affect = 0.12
	environment.fog_height = 0.2
	environment.fog_height_density = 0.07

	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.0
	environment.adjustment_contrast = 1.07
	environment.adjustment_saturation = 1.14

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = environment
	parent.add_child(we)


## Two rings of far ridges so the horizon is never empty: rolling forested
## hills, and taller blue ranges behind them seen through the western gap.
func build_distant_ranges(parent: Node3D) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = ForestLayout.SEED + 5
	noise.frequency = 1.0
	noise.fractal_octaves = 4
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var seg := 220
	for ring in 2:
		var r0 := 175.0 if ring == 0 else 280.0
		var depth := 40.0 if ring == 0 else 60.0
		var base_h := 12.0 if ring == 0 else 30.0
		var amp := 22.0 if ring == 0 else 55.0
		var start := verts.size()
		for s in seg + 1:
			var a := TAU * s / seg
			var dir := Vector3(cos(a), 0.0, sin(a))
			var n := noise.get_noise_2d(cos(a) * (2.0 + ring * 1.3), sin(a) * (2.0 + ring * 1.3)) * 0.5 + 0.5
			var peak := base_h + amp * pow(n, 1.6 - ring * 0.3)
			verts.append(dir * r0 + Vector3.DOWN * 20.0)
			verts.append(dir * (r0 + depth) + Vector3.UP * peak)
		for s in seg:
			var i := start + s * 2
			idx.append_array([i, i + 1, i + 3, i, i + 3, i + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = SH_DISTANT
	mat.set_shader_parameter("sun_towards", SUN_TOWARDS)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "DistantRanges"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
