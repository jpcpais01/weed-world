class_name KelingMorph
extends Node3D
## A Keling turning into another one, played on the controller it changes.
##
##  0.00  the magic gathers: a circle of light opens on the ground, a column
##        of light rises round the body, glints and a rim glow spread over
##        it, and the Keling lifts off its feet and starts to whirl
##  0.45  the new Keling's model goes in (it was loading in the background
##        since the start; the gathering holds here until it is ready)
##  0.50  a glowing, ragged cut sweeps up from the feet to the crown: the old
##        Keling crumbles into its own petals (leaves, seeds, florets...)
##        above it while the new one is woven below it from a spiral of its
##        petals pouring in from the circle
##  1.32  the reveal: a flash, a burst of petals, a shockwave round the
##        circle, and the new Keling lands and cheers
##  2.10  the last sparkles settle and the spell is gone
##
## Everything is a handful of cheap meshes and two small MultiMeshes, so it
## costs next to nothing on a phone. The controller reads `spin` and `lift`
## for the body and keeps the player still until `revealed`.

signal revealed
signal finished

const GATHER := 0.45
const SWEEP := Vector2(0.5, 1.3)
const REVEAL := 1.32
const END := 2.1
const TURNS := 2.0
const SHED := 30     ## petals the old Keling sheds as the cut passes
const WEAVE := 30    ## petals spiralling in to weave the new one
const BURST := 26    ## petals bursting out at the reveal
const SHAPES := {"leaf": 0, "petal": 1, "seed": 2, "bloom": 3, "spore": 4}
const PETAL_SIZE := {"leaf": 0.075, "petal": 0.062, "seed": 0.08, "bloom": 0.05, "spore": 0.04}

const BODY_SHADER := preload("res://player/characters/morph/morph_body.gdshader")
const RING_SHADER := preload("res://player/characters/morph/morph_ring.gdshader")
const PILLAR_SHADER := preload("res://player/characters/morph/morph_pillar.gdshader")
const FLASH_SHADER := preload("res://player/characters/morph/morph_flash.gdshader")
const PETAL_SHADER := preload("res://player/characters/morph/morph_petal.gdshader")
const PILLAR_HEIGHT := 2.4

## Read by the controller every frame: extra yaw and lift of the body.
var spin := 0.0
var lift := 0.0

var keling: KelingController
var from_id := ""
var to_id := ""

var _t := 0.0
var _swapped := false
var _revealed := false
var _done := false
var _old_model: Node3D
var _old_body: KelingBody
var _new_body: KelingBody
var _old_info: Dictionary
var _new_info: Dictionary
var _old_dress: Array = []    # [MeshInstance3D, surface, previous override, morph material]
var _new_dress: Array = []
var _loading: Array[String] = []
var _loaded: Array[Resource] = []
var _ring: ShaderMaterial
var _pillar: ShaderMaterial
var _flash: ShaderMaterial
var _flash_mesh: MeshInstance3D
var _light: OmniLight3D
var _sparkles: CPUParticles3D
var _shed: MultiMesh
var _weave: MultiMesh
var _shed_seeds: Array = []
var _weave_seeds: Array = []
var _closeup := false


## Starts turning `k` into character `id`.
func begin(k: KelingController, id: String) -> void:
	keling = k
	from_id = k.character_id
	to_id = id
	_old_body = k.body
	_new_body = KelingCharacters.body(id)
	_old_info = KelingCharacters.get_info(from_id)
	_new_info = KelingCharacters.get_info(id)
	# Load the new model while the magic gathers, so nothing hitches.
	for path in [_new_info.scene, _new_info.animations]:
		if ResourceLoader.has_cached(path):
			_loaded.append(load(path))
		elif ResourceLoader.load_threaded_request(path) == OK:
			_loading.append(path)
	_build()
	_old_dress = _dress(k.model, true, _old_info)
	_play("morph_rise")
	if k.is_local and k.camera_rig:
		k.camera_rig.begin_closeup(k.facing)
		_closeup = true
	_animate()


## Ends the spell at once (the controller left, or another one started).
func finish_now() -> void:
	if _done:
		return
	_done = true
	_undress(_new_dress if _swapped else _old_dress)
	if _old_model and is_instance_valid(_old_model):
		_old_model.queue_free()
	if _closeup and is_instance_valid(keling) and keling.camera_rig:
		keling.camera_rig.end_closeup()
	spin = 0.0
	lift = 0.0
	if not _revealed:
		_revealed = true
		revealed.emit()
	finished.emit()
	queue_free()


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_timed(delta)
	PerfMeter.add(&"transformation", Time.get_ticks_usec() - t0)


func _process_timed(delta: float) -> void:
	if _done:
		return
	if _swapped:
		_t += delta
	else:
		_t = minf(_t + delta, GATHER)
		if _t >= GATHER and _resources_ready():
			_swap()
			if _done:
				return
	_animate()
	if not _revealed and _t >= REVEAL:
		_reveal()
	if _t >= END:
		finish_now()


func _resources_ready() -> bool:
	for path in _loading.duplicate():
		match ResourceLoader.load_threaded_get_status(path):
			ResourceLoader.THREAD_LOAD_LOADED:
				_loaded.append(ResourceLoader.load_threaded_get(path))
				_loading.erase(path)
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				pass
			_:
				# Couldn't load it in the background: the swap loads it now.
				_loading.erase(path)
	return _loading.is_empty()


func _swap() -> void:
	var old_lib := keling.animator.get_animation_library(&"")
	_old_model = keling.set_character(to_id)
	if _old_model == null:
		finish_now()
		return
	_swapped = true
	# The old Keling's last moment: a startled little pose as it crumbles.
	var ap := AnimationPlayer.new()
	ap.name = "MorphPose"
	_old_model.add_child(ap)
	ap.add_animation_library(&"", old_lib)
	if ap.has_animation(&"Surprise"):
		ap.play(&"Surprise")
	_new_dress = _dress(keling.model, false, _new_info)


func _reveal() -> void:
	_revealed = true
	if _old_model and is_instance_valid(_old_model):
		_old_model.queue_free()
	_old_model = null
	_play("morph_bloom")
	_sparkles.emitting = false
	keling.morph_landed()
	revealed.emit()


# ---------------------------------------------------------------------------
# Timeline

func _animate() -> void:
	var t := _t
	var height := maxf(_old_body.height, _new_body.height) + 0.2
	var sweep := smoothstep(SWEEP.x, SWEEP.y, t)
	var cut := lerpf(-0.15, height, sweep)
	spin = TAU * TURNS * smoothstep(0.15, REVEAL + 0.18, t)
	var hop := clampf((t - 0.2) / (REVEAL - 0.2), 0.0, 1.0)
	lift = 0.24 * pow(sin(PI * hop), 0.8)
	var magic := smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(REVEAL, END, t))
	var feet := keling.global_position.y + lift if is_instance_valid(keling) else 0.0
	if _old_model and is_instance_valid(_old_model):
		_old_model.position.y = lift

	for d in _old_dress:
		var m: ShaderMaterial = d[3]
		m.set_shader_parameter("cut", cut if _swapped else -1.0)
		m.set_shader_parameter("base_y", feet)
		m.set_shader_parameter("rim", smoothstep(0.0, GATHER, t))
	for d in _new_dress:
		var m: ShaderMaterial = d[3]
		m.set_shader_parameter("cut", cut)
		m.set_shader_parameter("base_y", feet)
		m.set_shader_parameter("rim", 1.0 - smoothstep(REVEAL, END - 0.25, t))

	var a: Color = _old_info.colors[0]
	var b: Color = _new_info.colors[0]
	var mix_c := a.lerp(b, sweep)
	_ring.set_shader_parameter("grow", ease(clampf(t / 0.5, 0.0, 1.0), 0.4))
	_ring.set_shader_parameter("intensity", magic * 1.3)
	_ring.set_shader_parameter("color_a", mix_c)
	_ring.set_shader_parameter("color_b", (_old_info.colors[1] as Color).lerp(_new_info.colors[1], sweep))
	_ring.set_shader_parameter("wave", (t - REVEAL) / 0.65 if t >= REVEAL and t < REVEAL + 0.65 else -1.0)
	_pillar.set_shader_parameter("intensity", smoothstep(0.1, 0.5, t) * (1.0 - smoothstep(REVEAL - 0.1, REVEAL + 0.3, t)) * 0.9)
	_pillar.set_shader_parameter("cut", (cut + lift) / PILLAR_HEIGHT)
	_pillar.set_shader_parameter("color_a", mix_c)
	_pillar.set_shader_parameter("color_b", (_old_info.colors[2] as Color).lerp(_new_info.colors[2], sweep))

	var flash := smoothstep(REVEAL - 0.06, REVEAL + 0.02, t) * exp(-maxf(t - REVEAL, 0.0) * 5.5)
	_flash.set_shader_parameter("intensity", flash * 1.6)
	_flash.set_shader_parameter("twist", t * 1.5)
	_flash.set_shader_parameter("color", (_new_info.colors[2] as Color).lerp(Color.WHITE, 0.3))
	_flash_mesh.scale = Vector3.ONE * (0.9 + 2.2 * clampf(t - REVEAL + 0.06, 0.0, 1.0))
	_flash_mesh.position.y = _new_body.height * 0.5 + lift
	_light.light_color = mix_c.lerp(Color.WHITE, 0.25)
	_light.light_energy = magic * 1.2 + flash * 5.0
	_light.position.y = 0.6 + cut * 0.4

	_sparkles.position.y = clampf(cut, 0.2, height) + lift
	_update_shed(t)
	_update_weave(t)


func _cut_at(t: float) -> float:
	var height := maxf(_old_body.height, _new_body.height) + 0.2
	return lerpf(-0.15, height, smoothstep(SWEEP.x, SWEEP.y, t))


func _lift_at(t: float) -> float:
	return 0.24 * pow(sin(PI * clampf((t - 0.2) / (REVEAL - 0.2), 0.0, 1.0)), 0.8)


## The old Keling coming apart: each petal breaks off where the cut passes
## and whirls away, up and out.
func _update_shed(t: float) -> void:
	for k in SHED:
		var s: Dictionary = _shed_seeds[k]
		var born: float = lerpf(SWEEP.x + 0.02, SWEEP.y - 0.05, s.order)
		var age: float = (t - born) / s.life
		if not _swapped or age <= 0.0 or age >= 1.0:
			_shed.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3.ZERO))
			continue
		var y0: float = clampf(_cut_at(born), 0.12, _old_body.height - 0.05)
		var r0: float = _old_body.half_width(y0) + 0.02
		var ang: float = s.angle + age * 3.6 + spin * 0.25
		var r: float = r0 + age * s.reach
		var y: float = y0 + _lift_at(born) + age * s.rise + sin(age * 7.0 + s.angle) * 0.04
		var size: float = s.size * smoothstep(0.0, 0.08, age) * (1.0 - age * age * age)
		var rot := Basis(s.axis, t * s.tumble + s.angle).scaled(Vector3.ONE * size)
		_shed.set_instance_transform(k, Transform3D(rot, Vector3(cos(ang) * r, y, sin(ang) * r)))


## The new Keling's petals: a spiral pouring in from the circle to where the
## cut is, then (the second set) a burst out of the body at the reveal.
func _update_weave(t: float) -> void:
	for k in WEAVE + BURST:
		var s: Dictionary = _weave_seeds[k]
		var xf := Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3.ZERO)
		if k < WEAVE:
			var arrive: float = lerpf(SWEEP.x + 0.06, SWEEP.y, s.order)
			var age: float = (t - (arrive - s.life)) / s.life
			if _swapped and age > 0.0 and age < 1.0:
				var e: float = age * age
				var ya: float = clampf(_cut_at(arrive), 0.1, _new_body.height - 0.05)
				var r: float = lerpf(1.15, _new_body.half_width(ya) + 0.02, e)
				var y: float = lerpf(0.04 + s.rise * 0.3, ya + _lift_at(arrive), e)
				var ang: float = s.angle - (1.0 - age) * 4.2
				var size: float = s.size * smoothstep(0.0, 0.15, age) * (1.0 - smoothstep(0.82, 1.0, age))
				xf = Transform3D(Basis(s.axis, t * s.tumble + s.angle).scaled(Vector3.ONE * size), Vector3(cos(ang) * r, y, sin(ang) * r))
		else:
			var tau: float = t - REVEAL - s.order * 0.06
			var age: float = tau / s.life
			if age > 0.0 and age < 1.0:
				var dir: Vector3 = Vector3(cos(s.angle), 0.25 + s.rise, sin(s.angle)).normalized()
				var p: Vector3 = Vector3(0.0, _new_body.height * 0.5, 0.0) + dir * (1.0 - exp(-tau * 4.0)) * s.reach * 1.6
				p.y -= 0.7 * tau * tau
				var size: float = s.size * (1.0 - age * age)
				xf = Transform3D(Basis(s.axis, t * s.tumble * 1.5 + s.angle).scaled(Vector3.ONE * size), p)
		_weave.set_instance_transform(k, xf)


# ---------------------------------------------------------------------------
# Building

## A ring of tiny specks wearing every material of the effect, for the
## loading screen's warm-up sweep to draw once, so the first transformation
## doesn't stop to compile shaders. The controller removes it as play starts.
static func make_warmup() -> Node3D:
	var root := Node3D.new()
	root.name = "MorphWarmup"
	var shaders := [BODY_SHADER, RING_SHADER, PILLAR_SHADER, FLASH_SHADER, PETAL_SHADER]
	for k in 12:
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.03, 0.03)
		mi.mesh = quad
		var m := ShaderMaterial.new()
		m.shader = shaders[k % shaders.size()]
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * k / 12.0
		mi.position = Vector3(sin(a) * 2.0, 1.6, cos(a) * 2.0)
		mi.rotation.y = a + PI
		root.add_child(mi)
	return root


func _build() -> void:
	# Ground circle.
	var ring := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.6, 2.6)
	ring.mesh = plane
	_ring = ShaderMaterial.new()
	_ring.shader = RING_SHADER
	ring.material_override = _ring
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.03
	add_child(ring)

	# Column of light.
	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.62
	cyl.bottom_radius = 0.5
	cyl.height = PILLAR_HEIGHT
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 28
	cyl.rings = 1
	pillar.mesh = cyl
	_pillar = ShaderMaterial.new()
	_pillar.shader = PILLAR_SHADER
	_pillar.set_shader_parameter("height", PILLAR_HEIGHT)
	pillar.material_override = _pillar
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pillar.position.y = PILLAR_HEIGHT * 0.5
	add_child(pillar)

	# The flash at the reveal.
	_flash_mesh = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)
	_flash_mesh.mesh = quad
	_flash = ShaderMaterial.new()
	_flash.shader = FLASH_SHADER
	_flash_mesh.material_override = _flash
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash_mesh)

	_light = OmniLight3D.new()
	_light.omni_range = 3.2
	_light.shadow_enabled = false
	_light.light_energy = 0.0
	add_child(_light)

	_sparkles = _make_sparkles()
	add_child(_sparkles)

	_shed = _make_petals(SHED, _old_info, _shed_seeds)
	_weave = _make_petals(WEAVE + BURST, _new_info, _weave_seeds)
	_set_petal_colors(_shed, _old_info)
	_set_petal_colors(_weave, _new_info)


func _make_petals(count: int, info: Dictionary, seeds: Array) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = PETAL_SHADER
	mat.set_shader_parameter("shape", SHAPES.get(info.petal, 0))
	quad.material = mat
	mm.mesh = quad
	mm.instance_count = count
	var size: float = PETAL_SIZE.get(info.petal, 0.06)
	for k in count:
		seeds.append({
			"order": (float(k % 30) + randf() * 0.7) / 30.0,
			"angle": float(k) * 2.39996 + randf() * 0.4,
			"life": randf_range(0.65, 0.95),
			"reach": randf_range(0.5, 1.0),
			"rise": randf_range(0.25, 0.8),
			"size": size * randf_range(0.75, 1.25),
			"tumble": randf_range(3.0, 8.0) * (1.0 if randf() < 0.5 else -1.0),
			"axis": Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized(),
		})
		mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3.ZERO))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.custom_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 5, 6))
	add_child(mi)
	return mm


func _set_petal_colors(mm: MultiMesh, info: Dictionary) -> void:
	var cols: Array = info.colors
	for k in mm.instance_count:
		var pick := randf()
		var c: Color = cols[0] if pick < 0.6 else (cols[1] if pick < 0.85 else cols[2])
		c = c.lerp(Color.WHITE, randf() * 0.15)
		var glow := 0.35 if info.petal == "spore" else randf_range(0.05, 0.3)
		mm.set_instance_custom_data(k, Color(c.r, c.g, c.b, glow))


func _make_sparkles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = false
	var tex := GradientTexture2D.new()
	tex.width = 32
	tex.height = 32
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	tex.gradient = g
	mat.albedo_texture = tex
	quad.material = mat
	p.mesh = quad
	p.amount = 40
	p.lifetime = 0.8
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.4
	p.emission_ring_inner_radius = 0.2
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP
	p.spread = 35.0
	p.gravity = Vector3(0, 1.2, 0)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.9
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var ramp := Gradient.new()
	var a: Color = _old_info.colors[2]
	var b: Color = _new_info.colors[2]
	ramp.colors = PackedColorArray([Color(a, 0.0), Color(a.lerp(b, 0.5), 1.0), Color(b, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	p.color_ramp = ramp
	p.emitting = true
	return p


## Puts the morph material on every surface of a model, keeping its look.
## Returns what to put back.
func _dress(model: Node3D, keep_above: bool, info: Dictionary) -> Array:
	var out := []
	var cols: Array = info.colors
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		# Only the character's own skinned meshes (not the props in its hands).
		if mi.mesh == null or mi.skin == null:
			continue
		for si in mi.mesh.get_surface_count():
			var prev := mi.get_surface_override_material(si)
			var src: Material = mi.mesh.surface_get_material(si)
			var m := ShaderMaterial.new()
			m.shader = BODY_SHADER
			m.set_shader_parameter("keep_above", 1.0 if keep_above else 0.0)
			m.set_shader_parameter("cut", -1.0 if keep_above else -10.0)
			m.set_shader_parameter("edge_color", cols[0])
			m.set_shader_parameter("core_color", (cols[2] as Color).lerp(Color.WHITE, 0.4))
			m.set_shader_parameter("rim_color", cols[0])
			var bm := src as BaseMaterial3D
			if prev is ShaderMaterial and src and src.resource_name == "Flower":
				# The crown flowers: vertex colours with this player's tint.
				m.set_shader_parameter("textured", false)
				m.set_shader_parameter("has_normal", false)
				m.set_shader_parameter("vertex_color", true)
				m.set_shader_parameter("roughness", 0.45)
				m.set_shader_parameter("hue_shift", (prev as ShaderMaterial).get_shader_parameter("hue_shift"))
				m.set_shader_parameter("saturation", (prev as ShaderMaterial).get_shader_parameter("saturation"))
			elif bm:
				# glTF models import as ORMMaterial3D (occlusion, roughness,
				# metallic in R, G, B), others as StandardMaterial3D.
				var orm := bm as ORMMaterial3D
				m.set_shader_parameter("albedo", bm.albedo_color)
				m.set_shader_parameter("textured", bm.albedo_texture != null)
				m.set_shader_parameter("albedo_tex", bm.albedo_texture)
				m.set_shader_parameter("rough_tex", orm.orm_texture if orm else (bm as StandardMaterial3D).roughness_texture)
				m.set_shader_parameter("roughness", bm.roughness)
				m.set_shader_parameter("metallic", bm.metallic)
				m.set_shader_parameter("has_normal", bm.normal_enabled and bm.normal_texture != null)
				m.set_shader_parameter("normal_tex", bm.normal_texture)
				m.set_shader_parameter("vertex_color", bm.vertex_color_use_as_albedo)
			mi.set_surface_override_material(si, m)
			out.append([mi, si, prev, m])
	return out


func _undress(dress: Array) -> void:
	for d in dress:
		var mi: MeshInstance3D = d[0]
		if is_instance_valid(mi):
			mi.set_surface_override_material(d[1], d[2])


func _play(clip: String) -> void:
	var path := "res://assets/audio/morph/%s.ogg" % clip
	if not ResourceLoader.exists(path):
		return
	var v := AudioStreamPlayer3D.new()
	v.bus = &"SFX"
	v.unit_size = 3.0
	v.max_distance = 30.0
	v.volume_db = -3.0
	v.position.y = 0.8
	v.stream = load(path)
	add_child(v)
	v.play()
