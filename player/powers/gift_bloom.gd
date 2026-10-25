class_name GiftBloom
extends SmokeGift
## Bloom Burst: the Keling blows a rainbow smoke ring straight up. It hangs
## over its head for a heartbeat, then slams down and rolls out across the
## ground as a wave of pastel smoke, and wherever the wave passes the forest
## erupts: titan mushrooms taller than trees with glowing gills, nodding star
## lilies, lantern bellvines, ferns unrolling like fiddleheads, dandelion
## clocks with seeds of light, lotus flowers opening on the water, and a
## carpet of tiny glowing flowers between them all (GiantFlora builds them).
##
## The mushroom caps are trampolines. Right in front of you a knee-high
## springcap bounces you onto a bigger cap, which bounces you onto a titan,
## which flings you up over the canopy. The lotus pads hold your weight.
## Every wild weed plant the wave rolls over bursts into bud.
##
## When the time is up everything wilts back into the ground in a flurry of
## petals and drifting seeds. The layout comes from the cast's seed and the
## terrain, so friends see (and bounce on) the very same garden.

const RISE_TIME := 0.85      # the ring rises over the head
const SLAM_TIME := 0.2       # ...then drops to the ground
const WAVE_TIME := 2.3
const WAVE_R := 14.0
const GROW_TIME := 2.0
const RING_PUFFS := 44
const CARPET := 150
const MAX_LIGHTS := 4
const KIND_WEIGHTS := {&"glowcap": 30, &"starlily": 22, &"bellvine": 15, &"fern": 16, &"puffball": 17}
const FOOTPRINT := {&"glowcap": 1.6, &"springcap": 0.6, &"starlily": 0.9, &"bellvine": 1.4, &"fern": 2.0, &"lotus": 2.6, &"puffball": 0.9}
const OPEN_TIME := {&"fern": 4.2, &"lotus": 3.4, &"starlily": 2.6, &"glowcap": 1.6, &"springcap": 1.0, &"bellvine": 2.2, &"puffball": 2.0}

static var _carpet_mat: ShaderMaterial
static var _puff_mat: ShaderMaterial
static var _ring_mat: ShaderMaterial
static var _flower_mesh: Mesh

var _origin := Vector3.ZERO
var _yaw := 0.0
var _scale := 1.0
var _slam_t := -1.0          # seconds since the ring hit the ground
var _plants: Array[Dictionary] = []
var _chain: Array[int] = []
var _ring: MultiMeshInstance3D
var _ring_hue := 0.0
var _wave: MeshInstance3D
var _carpet: MultiMeshInstance3D
var _c_pos := PackedVector3Array()
var _c_born := PackedFloat32Array()
var _c_size := PackedFloat32Array()
var _c_yaw := PackedFloat32Array()
var _c_col := PackedColorArray()
var _lights: Array[OmniLight3D] = []
var _burst: CPUParticles3D
var _petals: CPUParticles3D
var _seeds: CPUParticles3D
var _ripened := false
var _prev_y := INF
var _boing_cool := 0.0


func _build() -> void:
	var noise := preload("res://assets/fx/smoke_noise.png")
	if _carpet_mat == null:
		_carpet_mat = ShaderMaterial.new()
		_carpet_mat.shader = preload("res://player/powers/bloom_carpet.gdshader")
		_puff_mat = ShaderMaterial.new()
		_puff_mat.shader = preload("res://player/powers/soft_puff.gdshader")
		_puff_mat.set_shader_parameter("noise", noise)
		_ring_mat = ShaderMaterial.new()
		_ring_mat.shader = preload("res://player/powers/dust_ring.gdshader")
		_ring_mat.set_shader_parameter("noise", noise)
		_flower_mesh = WeedHigh._flower_mesh()
	_scale = 1.0 + 0.4 * (boost - 1.0) / 0.5
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_ring = multimesh(q, RING_PUFFS, _puff_mat)
	_ring.name = "SmokeRing"
	_ring.multimesh.visible_instance_count = RING_PUFFS
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	_wave = MeshInstance3D.new()
	_wave.name = "BloomWave"
	_wave.mesh = plane
	_wave.material_override = _ring_mat
	_wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wave.visible = false
	add_child(_wave)
	_carpet = multimesh(_flower_mesh, CARPET, _carpet_mat, true, false)
	_carpet.name = "BloomCarpet"
	_burst = WeedProps.stars(Color(1.0, 0.9, 0.7), 30, 0.12)
	_burst.name = "PopStars"
	_burst.lifetime = 1.2
	_burst.initial_velocity_min = 1.0
	_burst.initial_velocity_max = 3.0
	_burst.gravity = Vector3(0, -0.8, 0)
	add_child(_burst)
	_petals = WeedProps.sparkles(Color.WHITE, 40, 0.09)
	_petals.name = "Petals"
	_petals.lifetime = 3.0
	_petals.explosiveness = 0.7
	_petals.initial_velocity_min = 0.4
	_petals.initial_velocity_max = 1.4
	_petals.gravity = Vector3(0, -0.35, 0)
	_petals.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_petals.emission_sphere_radius = 1.0
	add_child(_petals)
	_seeds = WeedProps.stars(Color(1.0, 0.95, 0.8), 50, 0.08)
	_seeds.name = "Seeds"
	_seeds.lifetime = 4.5
	_seeds.explosiveness = 0.6
	_seeds.direction = Vector3(0.3, 1, 0.2)
	_seeds.spread = 70.0
	_seeds.initial_velocity_min = 0.5
	_seeds.initial_velocity_max = 1.6
	_seeds.gravity = Vector3(0.25, 0.12, 0.1)
	_seeds.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_seeds.emission_sphere_radius = 0.8
	add_child(_seeds)


func _start(data: Dictionary) -> void:
	_origin = data.get("pos", feet())
	_yaw = float(data.get("yaw", caster.facing))
	_layout()
	_ring_hue = rng.randf()
	play("bloom_ring", mouth().origin, -2.0)


func _refreshed() -> void:
	# A second burst while the garden stands: everything blooms afresh.
	for p in _plants:
		if p.born:
			p.squash = -0.6
			p.flash_t = 0.0
	play("bloom_boom", _origin, -6.0, 1.2)
	_ripened = false
	_slam_t = 0.0 if _slam_t >= 0.0 else _slam_t


func fade_out() -> float:
	return 4.5


func _on_end() -> void:
	play("bloom_wilt", _origin + Vector3.UP, 0.0)
	for i in _plants.size():
		_plants[i].wilt_delay = rng.randf_range(0.0, 1.6)


# ---------------------------------------------------------------------------
# Laying out the garden (deterministic from the seed and the terrain)

func _layout() -> void:
	var fwd := Vector3(sin(_yaw), 0.0, cos(_yaw))
	# The bounce chain, straight ahead: little, middling, titan.
	var chain := [[&"springcap", 2.6, 1.0, 0.0], [&"glowcap", 4.9, 0.72, 0.25], [&"glowcap", 8.4, 1.5, -0.2]]
	for c in chain:
		var dir := fwd.rotated(Vector3.UP, float(c[3]) + rng.randf_range(-0.12, 0.12))
		var i := _try_place(c[0], _origin + dir * float(c[1]) * _scale, float(c[2]) * _scale * rng.randf_range(0.92, 1.08), false)
		if i >= 0:
			_chain.append(i)
	var count := int(round(14.0 * boost))
	var kinds: Array = KIND_WEIGHTS.keys()
	var total := 0
	for k in kinds:
		total += int(KIND_WEIGHTS[k])
	for n in count:
		var pick := rng.randi() % total
		var kind: StringName = kinds[0]
		for k in kinds:
			pick -= int(KIND_WEIGHTS[k])
			if pick < 0:
				kind = k
				break
		var dist := lerpf(3.6, WAVE_R * 0.92, pow((float(n) + rng.randf()) / count, 0.8)) * _scale
		for attempt in 4:
			var a := rng.randf() * TAU
			var dir := Vector3(cos(a), 0, sin(a))
			# Keep the bounce chain's lane clear.
			if dir.dot(fwd) > 0.9 and dist < 10.0 * _scale:
				continue
			var s := _scale * rng.randf_range(0.75, 1.35)
			if kind == &"glowcap":
				s *= rng.randf_range(0.8, 1.25)
			if _try_place(kind, _origin + dir * dist, s, true) >= 0:
				break
	_lay_carpet()


func _try_place(kind: StringName, at: Vector3, s: float, may_swap: bool) -> int:
	var ground := WaterLevel.ground_at(at.x, at.z)
	var water := WaterLevel.surface_at(at.x, at.z)
	var y := ground
	if water > ground + 0.35:
		if not may_swap:
			return -1
		kind = &"lotus"
		y = water
	elif kind == &"lotus":
		kind = &"fern"
	if not WaterLevel.has_water():
		y = _ray_floor(at, at.y)
	elif _blocked(at, ground):
		return -1
	var foot: float = FOOTPRINT[kind] * s
	for p in _plants:
		if Vector2(p.pos.x - at.x, p.pos.z - at.z).length() < (foot + float(p.foot)) * 0.62:
			return -1
	if Vector2(at.x - _origin.x, at.z - _origin.z).length() < 1.7:
		return -1
	var variant := rng.randi() % GiantFlora.VARIANTS
	var flora := GiantFlora.get_flora(kind, variant)
	var pal := GiantFlora.palette(kind, rng.randi())
	var dist := Vector2(at.x - _origin.x, at.z - _origin.z).length()
	var k := clampf(dist / WAVE_R, 0.0, 0.999)
	var plant := {
		"kind": kind, "pos": Vector3(at.x, y, at.z), "yaw": rng.randf() * TAU, "scale": s, "foot": foot,
		"mesh": flora.mesh, "info": flora.info, "palette": pal, "seed": rng.randf(),
		# The wave reaches it after this long (radius = R * (1 - (1 - k)^2.2)).
		"spawn": WAVE_TIME * (1.0 - pow(1.0 - k, 1.0 / 2.2)),
		"born": false, "age": 0.0, "squash": 0.0, "squash_v": 0.0, "flash_t": 0.0,
		"mi": null, "bodies": [], "light": null, "spores": null, "wilt_delay": 0.0, "burst_done": false,
	}
	_plants.append(plant)
	return _plants.size() - 1


## True if a tree, rock, bench or anything else stands here.
func _blocked(at: Vector3, ground: float) -> bool:
	if not is_inside_tree():
		return false
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, ground + 12.0, at.z), Vector3(at.x, ground - 1.0, at.z), 1)
	var hit := space.intersect_ray(q)
	return not hit.is_empty() and (hit.position as Vector3).y > ground + 0.5


func _ray_floor(at: Vector3, fallback: float) -> float:
	if not is_inside_tree():
		return fallback
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 3.0, 0), at - Vector3(0, 6.0, 0), 1)
	var hit := space.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else fallback


func _lay_carpet() -> void:
	_c_pos.resize(CARPET)
	_c_born.resize(CARPET)
	_c_size.resize(CARPET)
	_c_yaw.resize(CARPET)
	_c_col.resize(CARPET)
	var n := 0
	for i in CARPET:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * WAVE_R * 0.95 * _scale + 1.0
		var x := _origin.x + cos(a) * d
		var z := _origin.z + sin(a) * d
		var g := WaterLevel.ground_at(x, z) if WaterLevel.has_water() else _origin.y
		if WaterLevel.surface_at(x, z) > g + 0.05:
			continue
		_c_pos[n] = Vector3(x, g, z)
		var k := clampf(d / WAVE_R, 0.0, 0.999)
		_c_born[n] = WAVE_TIME * (1.0 - pow(1.0 - k, 1.0 / 2.2)) + rng.randf_range(0.0, 0.4)
		_c_size[n] = rng.randf_range(2.4, 4.6)
		_c_yaw[n] = rng.randf() * TAU
		_c_col[n] = Color.from_hsv(rng.randf(), rng.randf_range(0.35, 0.7), 1.0, rng.randf_range(0.4, 1.0))
		n += 1
	_carpet.multimesh.visible_instance_count = n


# ---------------------------------------------------------------------------

func _tick(dt: float, real: float) -> void:
	_boing_cool -= real
	_update_ring(dt)
	if _slam_t >= 0.0:
		_slam_t += dt
		_update_wave()
		for p in _plants:
			if not p.born and _slam_t >= float(p.spawn):
				_spawn(p)
		if not _ripened and _slam_t > WAVE_TIME and local:
			_ripened = true
			_ripen_plants()
	for p in _plants:
		if p.born:
			_update_plant(p, dt)
	_update_carpet()


## The smoke ring: up out of the mouth, a breath over the head, then down
## to the ground and out across it as the wave.
func _update_ring(dt: float) -> void:
	var mm := _ring.multimesh
	var t := age
	var centre: Vector3
	var radius: float
	var size: float
	var alpha: float
	var lift := 1.25 * caster.visual.scale.y
	if _slam_t < 0.0:
		var m := mouth().origin
		if t < RISE_TIME:
			var k := 1.0 - pow(1.0 - t / RISE_TIME, 2.0)
			centre = m + Vector3.UP * (lift * k)
			radius = lerpf(0.06, 0.62, k)
			size = lerpf(0.12, 0.42, k)
			alpha = clampf(t * 6.0, 0.0, 1.0) * 0.85
		else:
			var k := clampf((t - RISE_TIME) / SLAM_TIME, 0.0, 1.0)
			centre = (m + Vector3.UP * lift).lerp(Vector3(_origin.x, _origin.y + 0.15, _origin.z), k * k)
			radius = lerpf(0.62, 1.2, k)
			size = lerpf(0.42, 0.55, k)
			alpha = 0.85
			if k >= 1.0:
				_slam()
	else:
		var k := clampf(_slam_t / WAVE_TIME, 0.0, 1.0)
		centre = _origin
		radius = lerpf(1.2, WAVE_R * _scale, 1.0 - pow(1.0 - k, 2.2))
		size = lerpf(0.55, 1.9, k)
		alpha = 0.85 * (1.0 - k) * (1.0 - k)
	if alpha <= 0.002:
		_ring.visible = false
		return
	_ring.visible = true
	for i in RING_PUFFS:
		var a := TAU * i / RING_PUFFS + age * 0.6
		var p := centre + Vector3(cos(a), 0.0, sin(a)) * radius
		if _slam_t >= 0.0:
			p.y = floor_at(p.x, p.z) + 0.25 + size * 0.25
		var wob := 1.0 + 0.25 * sin(i * 2.3 + age * 3.0)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size * wob), p))
		var col := Color.from_hsv(fmod(_ring_hue + float(i) / RING_PUFFS, 1.0), 0.32, 1.0, alpha)
		mm.set_instance_color(i, col)
		mm.set_instance_custom_data(i, Color(0, a * 2.0, float(i) * 0.37, 0))


func _slam() -> void:
	_slam_t = 0.0
	_wave.visible = true
	_wave.set_instance_shader_parameter("seed", rng.randf() * 10.0)
	_wave.set_instance_shader_parameter("width", 0.08)
	play("bloom_boom", _origin, 2.0)
	var me := local_player()
	if me and me.camera_rig and me.global_position.distance_to(_origin) < 24.0:
		me.camera_rig.shake(0.22)
	if local:
		Input.vibrate_handheld(40)


func _update_wave() -> void:
	var k := clampf(_slam_t / WAVE_TIME, 0.0, 1.0)
	if k >= 1.0:
		_wave.visible = false
		return
	var d := WAVE_R * _scale * 2.1
	_wave.global_transform = Transform3D(Basis.from_scale(Vector3(d, 1.0, d)), _origin + Vector3(0, 0.12, 0))
	_wave.set_instance_shader_parameter("age", k)
	_wave.set_instance_shader_parameter("strength", 1.2)
	_wave.set_instance_shader_parameter("color", Color.from_hsv(fmod(_ring_hue + k * 0.4, 1.0), 0.35, 1.0))


func _spawn(p: Dictionary) -> void:
	p.born = true
	p.age = 0.0
	p.flash_t = 0.0
	var s: float = p.scale
	var info: Dictionary = p.info
	var mi := MeshInstance3D.new()
	mi.mesh = p.mesh
	mi.material_override = GiantFlora.material()
	mi.extra_cull_margin = 2.0 * s
	var tall := float(info.height) * s
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if tall > 2.4 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_transform = Transform3D(Basis(Vector3.UP, p.yaw).scaled(Vector3.ONE * s), p.pos)
	var pal: Array = p.palette
	mi.set_instance_shader_parameter("col_a", pal[0])
	mi.set_instance_shader_parameter("col_b", pal[1])
	mi.set_instance_shader_parameter("glow_col", pal[2])
	mi.set_instance_shader_parameter("stem_col", pal[3])
	mi.set_instance_shader_parameter("seed", p.seed)
	mi.set_instance_shader_parameter("grow", 0.0)
	p.mi = mi
	var xf: Transform3D = mi.global_transform
	if p.kind == &"glowcap" or p.kind == &"springcap":
		p.cap_center = xf * (info.cap_center as Vector3)
		p.cap_r = float(info.cap_r) * s
		p.cap_top = p.pos.y + float(info.cap_top) * s
		p.cap_h = float(info.cap_h) * s
		p.bounce = true
		_add_stem_collider(p, float(info.stem_r) * s, float(info.height) * s)
		if p.kind == &"glowcap":
			p.spores = _spore_emitter(p.cap_center + Vector3(0, -p.cap_r * 0.1, 0), p.cap_r, pal[2])
	elif p.kind == &"lotus":
		for pad in info.pads:
			_add_pad_collider(p, xf * (pad[0] as Vector3), float(pad[1]) * s)
	if info.get("glows", false) and _lights.size() < MAX_LIGHTS and tall > 1.8:
		var l := OmniLight3D.new()
		l.light_color = (pal[2] as Color).lerp(Color.WHITE, 0.2)
		l.light_energy = 0.0
		l.omni_range = 3.2 + 1.2 * s
		l.omni_attenuation = 1.5
		l.shadow_enabled = false
		l.light_specular = 0.1
		add_child(l)
		l.global_position = xf * (info.light as Vector3)
		_lights.append(l)
		p.light = l
	# Pop!
	_burst.global_position = p.pos + Vector3(0, 0.4, 0)
	_burst.amount = int(12 + 10 * s)
	_burst.restart()
	_burst.emitting = true
	var big := clampf(tall / 6.0, 0.0, 1.0)
	play("bloom_pop", p.pos + Vector3.UP, -4.0 + 4.0 * big, 1.25 - 0.45 * big)


func _add_stem_collider(p: Dictionary, r: float, h: float) -> void:
	# No collider if someone stands right where the stem comes up.
	for n in get_tree().get_nodes_in_group("player"):
		var k := n as Node3D
		if k and Vector2(k.global_position.x - p.pos.x, k.global_position.z - p.pos.z).length() < r + 0.5:
			return
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = maxf(r, 0.08)
	shape.height = maxf(h * 0.92, 0.2)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	body.global_position = p.pos + Vector3(0, shape.height * 0.5, 0)
	p.bodies.append(body)


func _add_pad_collider(p: Dictionary, at: Vector3, r: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r * 0.92
	shape.height = 0.14
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	body.global_position = at + Vector3(0, -0.03, 0)
	p.bodies.append(body)


func _spore_emitter(at: Vector3, r: float, col: Color) -> CPUParticles3D:
	var e := WeedProps.sparkles(col, 14, 0.06)
	e.name = "Spores"
	e.one_shot = false
	e.explosiveness = 0.0
	e.lifetime = 4.0
	e.direction = Vector3.DOWN
	e.spread = 30.0
	e.initial_velocity_min = 0.05
	e.initial_velocity_max = 0.2
	e.gravity = Vector3(0, -0.12, 0)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	e.emission_ring_axis = Vector3.UP
	e.emission_ring_radius = r * 0.7
	e.emission_ring_inner_radius = r * 0.2
	e.emission_ring_height = 0.05
	e.emitting = false
	add_child(e)
	e.global_position = at
	return e


func _update_plant(p: Dictionary, dt: float) -> void:
	p.age += dt
	p.flash_t += dt
	var mi: MeshInstance3D = p.mi
	var age_p: float = p.age
	var grow := clampf(age_p / GROW_TIME * 1.6, 0.0, 1.6)
	var open_time: float = OPEN_TIME.get(p.kind, 2.0)
	var o := clampf((age_p - 0.55) / open_time, 0.0, 1.0)
	o = o * o * (3.0 - 2.0 * o)
	p.squash_v += (-float(p.squash) * 140.0 - float(p.squash_v) * 9.0) * dt
	p.squash += float(p.squash_v) * dt
	var wilt := 0.0
	if ending:
		wilt = clampf((out_t - float(p.wilt_delay)) / 2.2, 0.0, 1.0)
		if wilt > 0.25 and not p.burst_done:
			p.burst_done = true
			_wilt_burst(p)
	mi.set_instance_shader_parameter("grow", grow)
	mi.set_instance_shader_parameter("open", o)
	mi.set_instance_shader_parameter("wilt", wilt)
	mi.set_instance_shader_parameter("squash", p.squash)
	mi.set_instance_shader_parameter("flash", exp(-float(p.flash_t) * 2.5))
	if p.light:
		(p.light as OmniLight3D).light_energy = 1.1 * clampf(grow, 0.0, 1.0) * o * (1.0 - wilt)
	if p.spores:
		(p.spores as CPUParticles3D).emitting = o > 0.6 and wilt <= 0.0
	if wilt > 0.6 and not p.bodies.is_empty():
		_free_bodies(p)
		p.bounce = false


func _wilt_burst(p: Dictionary) -> void:
	var info: Dictionary = p.info
	var s: float = p.scale
	var pal: Array = p.palette
	if p.kind == &"puffball":
		_seeds.global_position = (p.mi as Node3D).global_transform * (info.head as Vector3)
		_seeds.restart()
		_seeds.emitting = true
	else:
		_petals.global_position = p.pos + Vector3(0, float(info.height) * s * 0.7, 0)
		_petals.emission_sphere_radius = 0.5 * s
		(_petals.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color = (pal[0] as Color) * 1.4
		_petals.restart()
		_petals.emitting = true


func _update_carpet() -> void:
	var mm := _carpet.multimesh
	var n := mm.visible_instance_count
	for i in n:
		var a := _slam_t - _c_born[i] if _slam_t >= 0.0 else -1.0
		var g := 0.0
		if a > 0.0:
			g = elastic_out(clampf(a / 0.8, 0.0, 1.0))
		if ending:
			g *= 1.0 - clampf((out_t - fmod(float(i) * 0.37, 1.5)) / 1.5, 0.0, 1.0)
		var s := maxf(g * _c_size[i], 0.001)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, _c_yaw[i]).scaled(Vector3.ONE * s), _c_pos[i]))
		var c := _c_col[i]
		mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, c.a * g))


func _ripen_plants() -> void:
	var weed = caster.get("weed")
	var n := 0
	for node in get_tree().get_nodes_in_group("weed_plant"):
		var plant := node as WeedPlant
		if plant and Vector2(plant.global_position.x - _origin.x, plant.global_position.z - _origin.z).length() < WAVE_R * _scale:
			if plant.ripen_all():
				n += 1
				if weed:
					weed.net_event(&"weed_ripened", plant.net_index)
	if n > 0 and weed:
		weed.note.emit("The bloom wave woke %d weed plant%s!" % [n, "" if n == 1 else "s"])


# ---------------------------------------------------------------------------
# Bouncing: the caps are trampolines for whoever plays on this screen.

func _physics_process(_delta: float) -> void:
	var me := local_player()
	if me == null or _slam_t < 0.0:
		_prev_y = INF
		return
	var p := me.global_position
	var prev := _prev_y
	_prev_y = p.y
	if prev == INF or me.gift_ride != null:
		return
	if me.mode in [KelingController.Mode.SIT, KelingController.Mode.SWIM, KelingController.Mode.MORPH]:
		return
	if me.velocity.y > 0.5:
		return
	for i in _plants.size():
		var pl: Dictionary = _plants[i]
		if not pl.get("bounce", false) or float(pl.age) < GROW_TIME * 0.5:
			continue
		var cc: Vector3 = pl.cap_center
		var r: float = pl.cap_r
		var d := Vector2(p.x - cc.x, p.z - cc.z).length()
		if d > r * 0.95:
			continue
		var surf := float(pl.cap_top) - float(pl.cap_h) * pow(d / r, 2.0)
		if prev >= surf - 0.08 and p.y <= surf + 0.3:
			_bounce(me, i, surf)
			return


func _bounce(me: KelingController, i: int, surf: float) -> void:
	var pl: Dictionary = _plants[i]
	var rel := float(pl.cap_top) - float(pl.pos.y)
	var height := 2.6 + rel * 0.6
	var g := me.gravity * me.gravity_mod
	var vy := sqrt(2.0 * g * height)
	var push := Vector3.ZERO
	# Along the chain, a hop carries you on to the next cap up.
	var ci := _chain.find(i)
	if ci >= 0 and ci + 1 < _chain.size() and me.move_input().length() < 0.25:
		var nxt: Dictionary = _plants[_chain[ci + 1]]
		if nxt.born:
			var to: Vector3 = (nxt.cap_center as Vector3) - me.global_position
			to.y = 0.0
			var air := vy / g + sqrt(maxf(2.0 * (height - (float(nxt.cap_top) - surf) * 0.8), 0.2) / (g * me.fall_gravity_scale))
			push = to / maxf(air, 0.3)
			push.x -= me.velocity.x
			push.z -= me.velocity.z
	me.launch(vy, push)
	pl.squash = 1.0
	pl.squash_v = 0.0
	_burst.global_position = Vector3(me.global_position.x, surf + 0.1, me.global_position.z)
	_burst.amount = 18
	_burst.restart()
	_burst.emitting = true
	if _boing_cool <= 0.0:
		_boing_cool = 0.12
		play("bloom_boing", me.global_position, 0.0, 1.3 - 0.5 * clampf(rel / 7.0, 0.0, 1.0))
	Input.vibrate_handheld(25)


func _free_bodies(p: Dictionary) -> void:
	for b in p.bodies:
		if is_instance_valid(b):
			(b as Node).queue_free()
	p.bodies.clear()


func _cleanup() -> void:
	for p in _plants:
		_free_bodies(p)
