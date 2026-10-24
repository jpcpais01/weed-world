class_name WeedHigh
extends Node3D
## The high after a puff. Off a bench it is the Glade Glow: the forest turns
## dreamy and saturated and rainbow motes drift round the Keling. On a bench,
## the view grants a superpower themed by its element (BenchSites tags):
##
##   water  · Brook Stride    faster on your feet, ripples bloom at every step
##   spirit · Spirit Sight    every ripe bud in the forest shines through it all
##   air    · Featherfall     jump twice as high and drift down like a seed
##   earth  · Mountain Might  grow big, land with a ground-shaking thump
##   life   · Bloom Trail     flowers spring up in your footsteps, and wild
##                            plants near you ripen their buds
##
## Each puff deepens the high and adds time; it fades out gently at the end.

signal started(element: StringName)
signal ended

const PUFF_TIME := 35.0
const MAX_TIME := 110.0
const FADE_TIME := 8.0
const STEP_LENGTH := 0.42

var keling: KelingController
var weed: KelingWeed
var element: StringName = &"none"
var strain: StringName = &"ember"
var level := 0.0          ## how deep, 0..1 (grows with each puff)
var shown := 0.0          ## eased strength actually applied, 0..1
var time_left := 0.0

var _base := {}
var _applied := {}
var _env: Environment
var _env_base := {}
var _aura: CPUParticles3D
var _burst: CPUParticles3D
var _ripples: Array[MeshInstance3D] = []
var _ripple_age: Array[float] = []
var _ripple_next := 0
var _ripple_mat: ShaderMaterial
var _flowers: Array[MeshInstance3D] = []
var _flower_age: Array[float] = []
var _flower_next := 0
var _beacons: Array[MeshInstance3D] = []
var _beacon_mat: StandardMaterial3D
var _step_dist := 0.0
var _step_side := 1.0
var _last_pos := Vector3.ZERO
var _tick := 0.0
var _aura_element: StringName = &""
var _aura_tint := Color.WHITE


func setup(p_keling: KelingController, p_weed: KelingWeed) -> void:
	keling = p_keling
	weed = p_weed
	_base = {
		"walk": keling.walk_speed, "jog": keling.jog_speed, "sprint": keling.sprint_speed,
		"jump": keling.jump_height, "fall": keling.fall_gravity_scale, "max_fall": keling.max_fall_speed,
	}
	_applied = {"speed": 1.0, "jump": 1.0, "float": 0.0, "size": 1.0}
	keling.landed.connect(_on_landed)


func _ready() -> void:
	_build_aura()
	_build_ripples()
	_build_flowers()
	_last_pos = keling.global_position


func active() -> bool:
	return shown > 0.002 or time_left > 0.0


func power_info() -> Dictionary:
	return WeedStrains.power(element)


## A puff was exhaled: deepen the high (and switch power if the view changed).
func add_puff(p_element: StringName, p_strain: StringName) -> void:
	var fresh := time_left <= 0.0 or p_element != element
	if p_element != element and shown > 0.05:
		# Swapping powers: let the old one go before the new one rises.
		_set_power_gameplay(0.0)
		shown = 0.0
		level = 0.0
	element = p_element
	strain = p_strain
	level = minf(level + 0.4, 1.0)
	time_left = minf(time_left + PUFF_TIME, MAX_TIME)
	_restyle_aura()
	_burst_at(keling.global_position + Vector3(0, 0.9, 0), power_info().color, 24)
	if fresh:
		started.emit(element)


func remaining_fraction() -> float:
	return clampf(time_left / MAX_TIME, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_physics_process_timed(delta)
	PerfMeter.add(&"weed high", Time.get_ticks_usec() - t0)


func _physics_process_timed(delta: float) -> void:
	if keling == null:
		return
	if time_left > 0.0:
		time_left = maxf(time_left - delta, 0.0)
		if time_left <= 0.0:
			ended.emit()
	var target := level * clampf(time_left / FADE_TIME, 0.0, 1.0)
	if time_left <= 0.0:
		level = 0.0
	shown = move_toward(shown, target, delta * (0.45 if target > shown else 0.25))
	_set_power_gameplay(shown)
	_update_env(shown)
	_update_aura(shown)
	_update_steps(delta)
	_update_ripples(delta)
	_update_flowers(delta)
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		_slow_tick()


# ---------------------------------------------------------------------------
# Gameplay

func _set_power_gameplay(p: float) -> void:
	var speed := 1.0 + (0.42 * p if element == &"water" else 0.0) + (0.12 * p if element == &"earth" else 0.0)
	var jump := 1.0 + (1.25 * p if element == &"air" else 0.0)
	var flt := p if element == &"air" else 0.0
	var size := 1.0 + (0.45 * p if element == &"earth" else 0.0)
	if absf(speed - _applied.speed) > 0.004:
		_applied.speed = speed
		keling.walk_speed = _base.walk * speed
		keling.jog_speed = _base.jog * speed
		keling.sprint_speed = _base.sprint * speed
		keling.animator.configure_speeds(keling.walk_speed, keling.jog_speed, keling.sprint_speed)
	if absf(jump - _applied.jump) > 0.002:
		_applied.jump = jump
		keling.jump_height = _base.jump * jump
	if absf(flt - _applied.float) > 0.002:
		_applied.float = flt
		keling.fall_gravity_scale = lerpf(_base.fall, 0.22, flt)
		keling.max_fall_speed = lerpf(_base.max_fall, 2.6, flt)
	if absf(size - _applied.size) > 0.002:
		_applied.size = size
		keling.visual.scale = Vector3.ONE * size


func _on_landed(impact: float, _kind: StringName) -> void:
	if shown < 0.15:
		return
	var feet := keling.global_position
	match element:
		&"earth":
			# Mountain Might: every landing is a stomp.
			var s := clampf(impact / 8.0, 0.35, 1.0) * shown
			_ripple(feet, Color(1.0, 0.72, 0.35), 1.6 + 1.6 * s, s)
			_burst_at(feet + Vector3(0, 0.05, 0), Color(0.85, 0.65, 0.4), int(14 + 20 * s))
			keling.camera_rig.shake(0.18 * s)
			Input.vibrate_handheld(int(20 + 30 * s))
		&"air":
			_burst_at(feet + Vector3(0, 0.1, 0), Color(0.9, 0.97, 1.0), 12)
		&"water":
			_ripple(feet, Color(0.45, 0.85, 1.0), 1.4, shown)


func _slow_tick() -> void:
	var tree := keling.get_tree()
	if tree == null:
		return
	if not weed.local:
		return
	match element:
		&"spirit":
			_update_beacons(tree, shown)
		&"life":
			if shown > 0.2:
				for n in tree.get_nodes_in_group("weed_plant"):
					var plant := n as WeedPlant
					if plant and plant.global_position.distance_to(keling.global_position) < 6.5:
						if plant.ripen_all():
							weed.net_event(&"weed_ripened", plant.net_index)
							_burst_at(plant.global_position + Vector3(0, 0.8, 0), Color(0.6, 1.0, 0.45), 18)
							weed.note.emit("The %s plants burst into bud!" % WeedStrains.display_name(plant.strain))
	if element != &"spirit" and not _beacons.is_empty():
		_update_beacons(tree, 0.0)


# ---------------------------------------------------------------------------
# The world turns dreamy

func _update_env(p: float) -> void:
	if not weed.local and _env_base.is_empty():
		return  # a co-op puppet's high doesn't tint our screen
	if _env == null:
		var w := keling.get_viewport().find_world_3d() if keling.is_inside_tree() else null
		if w == null or w.environment == null:
			return
		_env = w.environment
	if p <= 0.0005:
		if not _env_base.is_empty():
			_env.adjustment_saturation = _env_base.sat
			_env.glow_intensity = _env_base.glow
			_env.adjustment_brightness = _env_base.bright
			_env_base.clear()
		return
	if _env_base.is_empty():
		_env_base = {"sat": _env.adjustment_saturation, "glow": _env.glow_intensity, "bright": _env.adjustment_brightness}
	var dream := 1.0 if element == &"none" else 0.45
	var wave := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0011)
	_env.adjustment_saturation = _env_base.sat * (1.0 + p * (0.22 + 0.2 * dream + 0.06 * wave * dream))
	_env.glow_intensity = _env_base.glow + p * (0.35 + 0.35 * dream)
	_env.adjustment_brightness = _env_base.bright * (1.0 + p * 0.04 * dream)


func _exit_tree() -> void:
	_update_env(0.0)


# ---------------------------------------------------------------------------
# Aura and bursts

func _build_aura() -> void:
	_aura = WeedProps.sparkles(Color.WHITE, 26, 0.035)
	_aura.name = "Aura"
	_aura.one_shot = false
	_aura.explosiveness = 0.0
	_aura.lifetime = 2.6
	_aura.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_aura.emission_ring_axis = Vector3.UP
	_aura.emission_ring_radius = 0.55
	_aura.emission_ring_inner_radius = 0.25
	_aura.emission_ring_height = 0.9
	_aura.position = Vector3(0, 0.6, 0)
	_aura.emitting = false
	add_child(_aura)
	_burst = WeedProps.sparkles(Color.WHITE, 24, 0.04)
	_burst.name = "PowerBurst"
	_burst.lifetime = 1.4
	add_child(_burst)


func _restyle_aura() -> void:
	if _aura_element == element:
		return
	_aura_element = element
	var info := power_info()
	_aura.color = Color.WHITE
	_aura.color_initial_ramp = null
	_aura.direction = Vector3.UP
	_aura.spread = 25.0
	_aura.gravity = Vector3(0, 0.05, 0)
	_aura.tangential_accel_min = 0.0
	_aura.tangential_accel_max = 0.0
	_aura.initial_velocity_min = 0.05
	_aura.initial_velocity_max = 0.2
	var tint: Color = info.color
	match element:
		&"none":
			var rainbow := Gradient.new()
			rainbow.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
			rainbow.colors = PackedColorArray([Color(1, 0.5, 0.5), Color(1, 0.85, 0.4), Color(0.6, 1, 0.5), Color(0.45, 0.85, 1), Color(0.75, 0.55, 1), Color(1, 0.55, 0.9)])
			_aura.color_initial_ramp = rainbow
			tint = Color.WHITE
		&"water":
			_aura.tangential_accel_min = 0.6
			_aura.tangential_accel_max = 1.0
			_aura.gravity = Vector3(0, -0.15, 0)
		&"spirit":
			_aura.initial_velocity_max = 0.1
			_aura.gravity = Vector3(0, 0.12, 0)
		&"air":
			_aura.tangential_accel_min = 1.6
			_aura.tangential_accel_max = 2.4
			_aura.initial_velocity_min = 0.3
			_aura.initial_velocity_max = 0.6
		&"earth":
			_aura.emission_ring_height = 0.1
			_aura.position = Vector3(0, 0.1, 0)
			_aura.gravity = Vector3(0, 0.3, 0)
		&"life":
			_aura.gravity = Vector3(0, -0.05, 0)
			_aura.tangential_accel_min = 0.2
			_aura.tangential_accel_max = 0.4
	if element != &"earth":
		_aura.emission_ring_height = 0.9
		_aura.position = Vector3(0, 0.6, 0)
	_aura_tint = tint * 1.5


func _update_aura(p: float) -> void:
	var on := p > 0.05
	if _aura.emitting != on:
		_aura.emitting = on
	# Bigger Kelings carry a bigger halo.
	_aura.scale = Vector3.ONE * keling.visual.scale.x
	if on:
		var tint := _aura_tint
		tint.a = clampf(p * 1.3, 0.1, 1.0)
		(_aura.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color = tint


func _burst_at(at: Vector3, color: Color, amount: int) -> void:
	if _burst == null:
		return
	_burst.global_position = at
	_burst.amount = amount
	(_burst.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color = color * 1.7
	_burst.restart()
	_burst.emitting = true


# ---------------------------------------------------------------------------
# Footsteps: ripples (water), dust (earth), flowers (life)

func _update_steps(_delta: float) -> void:
	var pos := keling.global_position
	var moved := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
	_last_pos = pos
	if shown < 0.1 or not keling.is_on_floor() or moved > 1.0:
		return
	_step_dist += moved
	var stride := STEP_LENGTH * keling.visual.scale.x
	if _step_dist < stride:
		return
	_step_dist = 0.0
	_step_side = -_step_side
	var side := Vector3(cos(keling.facing), 0.0, -sin(keling.facing)) * 0.1 * _step_side
	var foot := pos + side
	match element:
		&"water":
			_ripple(foot, Color(0.45, 0.85, 1.0), 0.9, shown)
		&"earth":
			_ripple(foot, Color(1.0, 0.7, 0.35), 0.7, shown * 0.6)
		&"life":
			_flower(foot + Vector3(randf_range(-0.12, 0.12), 0, randf_range(-0.12, 0.12)))
			if randf() < 0.5:
				_flower(foot + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)))
		&"none":
			if randf() < 0.35:
				_burst_at(foot + Vector3(0, 0.05, 0), Color.from_hsv(randf(), 0.5, 1.0), 4)


func _build_ripples() -> void:
	_ripple_mat = ShaderMaterial.new()
	_ripple_mat.shader = preload("res://player/weed/ripple.gdshader")
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	for i in 10:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = _ripple_mat.duplicate()
		mi.top_level = true
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_ripples.append(mi)
		_ripple_age.append(1.0)


func _ripple(at: Vector3, color: Color, size: float, strength: float) -> void:
	var mi := _ripples[_ripple_next]
	_ripple_age[_ripple_next] = 0.0
	_ripple_next = (_ripple_next + 1) % _ripples.size()
	mi.global_transform = Transform3D(Basis.from_scale(Vector3(size, 1.0, size)), at + Vector3(0, 0.03, 0))
	(mi.material_override as ShaderMaterial).set_shader_parameter("color", color)
	mi.set_instance_shader_parameter("strength", clampf(strength * 1.2, 0.0, 1.0))
	mi.visible = true


func _update_ripples(delta: float) -> void:
	for i in _ripples.size():
		if _ripple_age[i] >= 1.0:
			continue
		_ripple_age[i] = minf(_ripple_age[i] + delta / 1.3, 1.0)
		_ripples[i].set_instance_shader_parameter("age", _ripple_age[i])
		if _ripple_age[i] >= 1.0:
			_ripples[i].visible = false


func _build_flowers() -> void:
	var mesh := _flower_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://player/weed/bloom_flower.gdshader")
	for i in 28:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.top_level = true
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_flowers.append(mi)
		_flower_age.append(1.0)


## Five round petals on a short stem; COLOR.r runs heart -> tip, COLOR.g is
## the heart.
static func _flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.11
	# Stem: a thin green blade (COLOR.b marks it).
	for v in [Vector3(-0.004, 0, 0), Vector3(0.004, 0, 0), Vector3(0.0, h, 0.0)]:
		st.set_color(Color(0.0, 0.0, 1.0))
		st.add_vertex(v)
	var petals := 5
	for i in petals:
		var a := TAU * i / petals
		var d := Vector3(cos(a), 0.18, sin(a))
		var side := Vector3(-sin(a), 0, cos(a))
		var c := Vector3(0, h, 0)
		var tip := c + d * 0.05
		for v in [c, c + d * 0.025 + side * 0.022, tip]:
			st.set_color(Color((v - c).length() / 0.05, 0.0, 0.0))
			st.add_vertex(v)
		for v in [c, tip, c + d * 0.025 - side * 0.022]:
			st.set_color(Color((v - c).length() / 0.05, 0.0, 0.0))
			st.add_vertex(v)
	# Heart.
	for i in 6:
		var a0 := TAU * i / 6.0
		var a1 := TAU * (i + 1) / 6.0
		var c := Vector3(0, h + 0.008, 0)
		st.set_color(Color(0, 1, 0))
		st.add_vertex(c)
		st.add_vertex(c + Vector3(cos(a0), -0.4, sin(a0)) * 0.012)
		st.add_vertex(c + Vector3(cos(a1), -0.4, sin(a1)) * 0.012)
	st.generate_normals()
	return st.commit()


func _flower(at: Vector3) -> void:
	var mi := _flowers[_flower_next]
	_flower_age[_flower_next] = 0.0
	_flower_next = (_flower_next + 1) % _flowers.size()
	var y := at.y
	var space := keling.get_world_3d().direct_space_state if keling.is_inside_tree() else null
	if space:
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.5, 0), at - Vector3(0, 0.8, 0), 1)
		var hit := space.intersect_ray(q)
		if hit:
			y = hit.position.y
	mi.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU), Vector3(at.x, y, at.z))
	mi.set_instance_shader_parameter("petal", Color.from_hsv(randf_range(0.0, 1.0), randf_range(0.35, 0.7), 1.0))
	mi.scale = Vector3.ONE * 0.001
	mi.visible = true


func _update_flowers(delta: float) -> void:
	for i in _flowers.size():
		if _flower_age[i] >= 1.0:
			continue
		_flower_age[i] = minf(_flower_age[i] + delta / 7.0, 1.0)
		var a := _flower_age[i]
		var grow := elastic_out(clampf(a * 7.0 / 0.6, 0.0, 1.0))
		var shrink := 1.0 - smoothstep(0.82, 1.0, a)
		var s := maxf(grow * shrink, 0.001) * 1.25
		var mi := _flowers[i]
		mi.scale = Vector3.ONE * s
		mi.set_instance_shader_parameter("fresh", 1.0 - a)
		if a >= 1.0:
			mi.visible = false


static func elastic_out(t: float) -> float:
	if t <= 0.0 or t >= 1.0:
		return clampf(t, 0.0, 1.0)
	return pow(2.0, -10.0 * t) * sin((t * 10.0 - 0.75) * (TAU / 3.0)) + 1.0


# ---------------------------------------------------------------------------
# Spirit Sight: beacons over every plant with a ripe bud, seen through walls

func _update_beacons(tree: SceneTree, p: float) -> void:
	var plants := tree.get_nodes_in_group("weed_plant")
	if p <= 0.02:
		for b in _beacons:
			b.visible = false
		for n in plants:
			(n as WeedPlant).set_glow(0.0)
		if p <= 0.0:
			for b in _beacons:
				b.queue_free()
			_beacons.clear()
		return
	if _beacon_mat == null:
		_beacon_mat = StandardMaterial3D.new()
		_beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beacon_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_beacon_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		_beacon_mat.no_depth_test = true
		_beacon_mat.albedo_texture = WeedProps.soft_dot()
		_beacon_mat.disable_receive_shadows = true
	var i := 0
	for n in plants:
		var plant := n as WeedPlant
		var ripe := plant.has_ripe_bud()
		plant.set_glow(p if ripe else 0.0)
		if not ripe:
			continue
		if i >= _beacons.size():
			var mi := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.7, 3.4)
			q.center_offset = Vector3(0, 1.1, 0)
			mi.mesh = q
			mi.top_level = true
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var m := _beacon_mat.duplicate() as StandardMaterial3D
			mi.material_override = m
			add_child(mi)
			_beacons.append(mi)
		var b := _beacons[i]
		b.global_position = plant.global_position
		b.visible = true
		(b.material_override as StandardMaterial3D).albedo_color = Color(WeedStrains.info(plant.strain).glow, 0.85 * p)
		i += 1
	for k in range(i, _beacons.size()):
		_beacons[k].visible = false
