@tool
class_name WeedPlant
extends Node3D
## A wild weed plant with a few buds on its stem. Buds are picked with the
## regular grab (they are in the "grabbable" group); a picked bud pops off with
## a puff of leaves and slowly grows back.

signal bud_picked(bud: WeedBud)

const REGROW_TIME := 75.0

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
	var i := 0
	for a in WeedKit.bud_anchors(strain):
		var bud := WeedBud.new()
		bud.plant = self
		bud.position = plant_mesh.transform * a
		bud.size = 1.0 if i == 0 else 0.8
		add_child(bud)
		bud.build()
		buds.append(bud)
		i += 1


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
