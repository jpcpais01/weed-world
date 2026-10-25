@tool
class_name WeedPlant
extends Node3D
## A wild weed plant with a few buds on its stem. Buds are picked with the
## regular grab (they are in the "grabbable" group); a picked bud pops off with
## a puff of leaves and slowly grows back.

signal bud_picked(bud: WeedBud)

const REGROW_TIME := 75.0
## Rarer strains take longer to grow their buds back.
const RARITY_REGROW := {&"common": 1.0, &"uncommon": 1.25, &"rare": 1.6, &"legendary": 2.2}

var strain: StringName = &"ember"
var net_index := -1   ## index in Forest.weed.nodes (same on every device)
var buds: Array[WeedBud] = []
var plant_mesh: MeshInstance3D
var _shake := 0.0
var _glow := 0.0
var _glow_target := 0.0
var _puff: CPUParticles3D


## Builds the plant (safe off the main thread, before entering the tree).
func setup(p_strain: StringName, height: float, yaw: float, kit: NatureKit = null) -> void:
	strain = p_strain
	name = "WeedPlant"
	add_to_group("weed_plant")
	var model_h := WeedKit.plant_model_height(strain)
	var s := height / maxf(model_h, 0.01)
	plant_mesh = MeshInstance3D.new()
	plant_mesh.name = "Plant"
	plant_mesh.mesh = WeedKit.plant_mesh(strain)
	plant_mesh.material_override = WeedKit.plant_material(strain, kit)
	plant_mesh.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3.ZERO)
	plant_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	plant_mesh.visibility_range_end = 46.0
	plant_mesh.visibility_range_end_margin = 4.0
	plant_mesh.set_instance_shader_parameter("phase", randf())
	add_child(plant_mesh)
	var dirs := WeedKit.bud_directions(strain)
	var i := 0
	for a in WeedKit.bud_anchors(strain):
		var bud := WeedBud.new()
		bud.plant = self
		bud.position = plant_mesh.transform * a
		# Point the bud the way it grows (some lean out, Moonfeather's hang).
		var d: Vector3 = (plant_mesh.basis * dirs[i]).normalized()
		if d.dot(Vector3.UP) < 0.999:
			var axis := Vector3.UP.cross(d)
			bud.basis = Basis(axis.normalized(), Vector3.UP.angle_to(d)) if axis.length() > 0.001 else Basis(Vector3.RIGHT, PI)
		bud.size = 1.0 if i == 0 else 0.8
		add_child(bud)
		bud.build()
		buds.append(bud)
		i += 1
	var rarity: StringName = WeedStrains.info(strain).get("rarity", &"common")
	if rarity == &"rare" or rarity == &"legendary":
		_add_motes(height, rarity == &"legendary")


## How long a picked bud takes to grow back on this plant.
func regrow_time() -> float:
	return REGROW_TIME * RARITY_REGROW.get(WeedStrains.info(strain).get("rarity", &"common"), 1.0)


## Rare strains are wrapped in a few drifting motes of their glow, so a
## lucky explorer spots them from across a clearing (more for the legendary).
func _add_motes(height: float, legendary: bool) -> void:
	var info := WeedStrains.info(strain)
	var motes := GPUParticles3D.new()
	motes.name = "Motes"
	motes.amount = 14 if legendary else 7
	motes.lifetime = 4.5
	motes.preprocess = 4.5
	motes.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3.0, height + 1.5, 3.0))
	motes.visibility_range_end = 34.0
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = WeedKit.plant_spread(strain) + 0.25
	pm.direction = Vector3.UP
	pm.spread = 40.0
	pm.initial_velocity_min = 0.03
	pm.initial_velocity_max = 0.12
	pm.gravity = Vector3(0, 0.03, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 1.5
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	motes.process_material = pm
	motes.position = Vector3(0, height * 0.55, 0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = info.glow.lightened(0.3)
	mat.albedo_texture = _mote_texture()
	quad.material = mat
	motes.draw_pass_1 = quad
	add_child(motes)


static var _mote_tex: GradientTexture2D


static func _mote_texture() -> Texture2D:
	if _mote_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
		_mote_tex = GradientTexture2D.new()
		_mote_tex.gradient = g
		_mote_tex.fill = GradientTexture2D.FILL_RADIAL
		_mote_tex.fill_from = Vector2(0.5, 0.5)
		_mote_tex.fill_to = Vector2(0.5, 0.0)
		_mote_tex.width = 32
		_mote_tex.height = 32
	return _mote_tex


func _ready() -> void:
	set_process(false)


## The bud was plucked: the plant shudders and sheds a few leaves.
func on_bud_picked(bud: WeedBud) -> void:
	_shake = 1.0
	set_process(true)
	_leaf_puff(bud.global_position)
	bud_picked.emit(bud)


## Every picked bud on this plant grows back at once (Bloom Trail).
func ripen_all() -> bool:
	var any := false
	for b in buds:
		if not b.ripe:
			b.ripen()
			any = true
	if any:
		_shake = 0.6
		set_process(true)
	return any


## Inner light for Spirit Sight (0..1), eased.
func set_glow(amount: float) -> void:
	if is_equal_approx(amount, _glow_target):
		return
	_glow_target = amount
	set_process(true)


func has_ripe_bud() -> bool:
	for b in buds:
		if b.ripe:
			return true
	return false


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_timed(delta)
	PerfMeter.add(&"weed plants", Time.get_ticks_usec() - t0)


func _process_timed(delta: float) -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	_shake = move_toward(_shake, 0.0, delta * 1.4)
	_glow = move_toward(_glow, _glow_target, delta * 1.5)
	plant_mesh.set_instance_shader_parameter("shake", _shake * _shake)
	plant_mesh.set_instance_shader_parameter("glow", _glow)
	if _shake <= 0.0 and is_equal_approx(_glow, _glow_target):
		set_process(false)


func _leaf_puff(at: Vector3) -> void:
	if _puff == null:
		_puff = CPUParticles3D.new()
		_puff.emitting = false
		_puff.one_shot = true
		_puff.amount = 10
		_puff.lifetime = 1.3
		_puff.explosiveness = 0.95
		_puff.direction = Vector3.UP
		_puff.spread = 70.0
		_puff.initial_velocity_min = 0.3
		_puff.initial_velocity_max = 0.8
		_puff.gravity = Vector3(0, -0.9, 0)
		_puff.damping_min = 1.0
		_puff.damping_max = 2.0
		_puff.angular_velocity_min = -180.0
		_puff.angular_velocity_max = 180.0
		_puff.scale_amount_min = 0.6
		_puff.scale_amount_max = 1.2
		var quad := QuadMesh.new()
		quad.size = Vector2(0.05, 0.03)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = WeedStrains.info(strain).glow.lerp(Color(0.35, 0.65, 0.25), 0.6)
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = WeedStrains.info(strain).glow * 0.4
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		quad.material = mat
		_puff.mesh = quad
		var fade := Gradient.new()
		fade.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
		fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
		_puff.color_ramp = fade
		add_child(_puff)
	_puff.global_position = at
	_puff.restart()
	_puff.emitting = true
