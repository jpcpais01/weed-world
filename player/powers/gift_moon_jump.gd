class_name GiftMoonJump
extends SmokeGift
## Moon Jump: a pale crescent moon rises in the sky where you're looking and
## gravity lets go. Jumps go four times as high and drift down slowly, the
## air steers like water, and every landing bounces you back up a little in
## a ring of moon dust and a spray of stars. Stardust trails off your feet
## while you're airborne.
##
## The caster's controller gets the gravity/jump/air-control multipliers;
## friends see the stardust and the landings on the puppet (its snapshots
## already carry the floaty arcs).

const GRAVITY := 0.3
const JUMP := 4.0          # x jump height
const AIR_CONTROL := 2.6
const BOUNCE := 0.46       # of the landing speed, back up
const MIN_BOUNCE := 3.0    # m/s landing speed below which it settles
const MOON_DIST := 300.0
const MOON_SIZE := 46.0
const STAR_TINT := Color(0.78, 0.86, 1.0)

static var _moon_mat: ShaderMaterial
static var _ring_mat: ShaderMaterial

var _moon: MeshInstance3D
var _moon_dir := Vector3.FORWARD
var _trail: CPUParticles3D
var _burst: CPUParticles3D
var _aura: CPUParticles3D
var _beam: MeshInstance3D
var _rings: Array[MeshInstance3D] = []
var _ring_age: Array[float] = []
var _ring_i := 0
var _was_floor := true
var _air_t := 0.0
var _last_y := 0.0
var _fall_v := 0.0


func _build() -> void:
	if _moon_mat == null:
		_moon_mat = ShaderMaterial.new()
		_moon_mat.shader = preload("res://player/powers/moon.gdshader")
		_moon_mat.set_shader_parameter("noise", preload("res://assets/fx/smoke_noise.png"))
		_ring_mat = ShaderMaterial.new()
		_ring_mat.shader = preload("res://player/powers/dust_ring.gdshader")
		_ring_mat.set_shader_parameter("noise", preload("res://assets/fx/smoke_noise.png"))
	_trail = WeedProps.stars(STAR_TINT, 40, 0.07)
	_trail.name = "Stardust"
	_trail.one_shot = false
	_trail.explosiveness = 0.0
	_trail.lifetime = 1.3
	_trail.gravity = Vector3(0, -0.25, 0)
	_trail.initial_velocity_min = 0.05
	_trail.initial_velocity_max = 0.25
	_trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_trail.emission_sphere_radius = 0.16
	add_child(_trail)
	_burst = WeedProps.stars(STAR_TINT, 36, 0.09)
	_burst.name = "LandingStars"
	_burst.lifetime = 1.1
	_burst.direction = Vector3.UP
	_burst.spread = 75.0
	_burst.initial_velocity_min = 1.0
	_burst.initial_velocity_max = 2.6
	_burst.gravity = Vector3(0, -1.2, 0)
	add_child(_burst)
	_aura = WeedProps.sparkles(Color(0.85, 0.9, 1.0), 18, 0.04)
	_aura.name = "MoonMotes"
	_aura.one_shot = false
	_aura.explosiveness = 0.0
	_aura.lifetime = 2.4
	_aura.local_coords = false
	_aura.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_aura.emission_ring_axis = Vector3.UP
	_aura.emission_ring_radius = 0.6
	_aura.emission_ring_inner_radius = 0.35
	_aura.emission_ring_height = 1.0
	_aura.gravity = Vector3(0, 0.12, 0)
	_aura.tangential_accel_min = 0.5
	_aura.tangential_accel_max = 0.9
	add_child(_aura)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	for i in 6:
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.material_override = _ring_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_rings.append(mi)
		_ring_age.append(1.0)
	# A column of moonlight at the cast.
	_beam = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 7.0)
	q.center_offset = Vector3(0, 3.5, 0)
	_beam.mesh = q
	var bm := glow_material(Color(0.7, 0.8, 1.0, 0.0))
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_beam.material_override = bm
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)


func _start(_data: Dictionary) -> void:
	_was_floor = true
	_last_y = feet().y
	_beam.global_position = feet()
	_burst_at(feet(), 1.2)
	_ring(feet(), 4.5, 1.0)
	play("moon_rise", feet() + Vector3.UP, 0.0)
	if local:
		caster.landed.connect(_on_landed)
		_build_moon()


func _refreshed() -> void:
	_burst_at(feet(), 1.0)
	_ring(feet(), 4.0, 0.9)
	play("moon_rise", feet() + Vector3.UP, -3.0)


func _build_moon() -> void:
	# The moon rises where the camera looks (so you see it come up).
	var cam := get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z if cam else forward()
	fwd.y = 0.0
	_moon_dir = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	_moon = MeshInstance3D.new()
	_moon.name = "Moon"
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_moon.mesh = q
	_moon.material_override = _moon_mat
	_moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_moon.extra_cull_margin = 400.0
	add_child(_moon)


func fade_out() -> float:
	return 2.2


func _tick(_dt: float, real: float) -> void:
	var k := envelope(1.4)
	var p := feet()
	if local:
		caster.gravity_mod = lerpf(1.0, GRAVITY / sqrt(boost), k)
		caster.jump_mod = lerpf(1.0, JUMP * boost, k)
		caster.air_control_mod = lerpf(1.0, AIR_CONTROL, k)
	# Airborne: trail stardust. Landing (puppets): work it out from motion.
	var on_floor := caster.is_on_floor() if local else bool(caster.get("_remote_floor"))
	if not local:
		var vy := (p.y - _last_y) / maxf(real, 0.001)
		if not on_floor:
			_fall_v = maxf(_fall_v, -vy)
		elif not _was_floor and _air_t > 0.15:
			_land_fx(_fall_v)
		if on_floor:
			_fall_v = 0.0
	_air_t = 0.0 if on_floor else _air_t + real
	_was_floor = on_floor
	_last_y = p.y
	_trail.emitting = not on_floor and _air_t > 0.08 and k > 0.2 and not ending
	_trail.global_position = p + Vector3(0, 0.1, 0)
	_aura.emitting = k > 0.3 and not ending
	_aura.global_position = p + Vector3(0, 0.55, 0)
	# The beam fades out over the first two seconds.
	var bk := clampf(1.0 - age / 2.0, 0.0, 1.0)
	_beam.visible = bk > 0.0
	if _beam.visible:
		(_beam.material_override as StandardMaterial3D).albedo_color = Color(0.7, 0.82, 1.0, 0.55 * bk * bk)
	_update_rings(real)
	_update_moon(k)


func _update_moon(k: float) -> void:
	if _moon == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Rises from the horizon over four seconds, sets as it ends.
	var rise := smoothstep(0.0, 4.0, age)
	var elev := deg_to_rad(lerpf(-3.0, 22.0, rise))
	if ending:
		elev -= deg_to_rad(10.0) * clampf(out_t / fade_out(), 0.0, 1.0)
	var dir := (_moon_dir * cos(elev) + Vector3.UP * sin(elev)).normalized()
	_moon.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * MOON_SIZE), cam.global_position + dir * MOON_DIST)
	_moon.set_instance_shader_parameter("alpha", k * (0.35 + 0.65 * rise))


func _on_landed(impact: float, _kind: StringName) -> void:
	if ending and out_t > 0.6:
		return
	_land_fx(impact)
	# Bounce: back up with part of the landing speed (a jump press wins).
	if impact > MIN_BOUNCE and caster.water.immersion < 0.05 and not caster.jump_held():
		var up := minf(impact * BOUNCE, 6.0)
		caster.launch.call_deferred(up)
		play("moon_bounce", feet(), -6.0, 0.9 + 0.25 * clampf(up / 6.0, 0.0, 1.0))


func _land_fx(impact: float) -> void:
	var s := clampf(impact / 8.0, 0.25, 1.0)
	var p := feet()
	_burst_at(p, s)
	_ring(p, 1.6 + 3.2 * s, 0.6 + 0.4 * s)
	play("moon_land", p, -4.0 + 4.0 * s, 1.15 - 0.25 * s)


func _burst_at(p: Vector3, s: float) -> void:
	_burst.global_position = p + Vector3(0, 0.08, 0)
	_burst.amount = int(14 + 26 * s)
	_burst.initial_velocity_max = 1.2 + 2.2 * s
	_burst.restart()
	_burst.emitting = true


func _ring(p: Vector3, size: float, strength: float) -> void:
	var mi := _rings[_ring_i]
	_ring_age[_ring_i] = 0.0
	_ring_i = (_ring_i + 1) % _rings.size()
	var y := floor_at(p.x, p.z)
	if absf(y - p.y) > 0.6:
		y = p.y
	mi.global_transform = Transform3D(Basis.from_scale(Vector3(size, 1.0, size)), Vector3(p.x, y + 0.04, p.z))
	mi.set_instance_shader_parameter("color", Color(0.72, 0.8, 1.0))
	mi.set_instance_shader_parameter("strength", strength)
	mi.set_instance_shader_parameter("width", 0.16)
	mi.set_instance_shader_parameter("seed", rng.randf() * 10.0)
	mi.visible = true


func _update_rings(real: float) -> void:
	for i in _rings.size():
		if _ring_age[i] >= 1.0:
			continue
		_ring_age[i] = minf(_ring_age[i] + real / 1.1, 1.0)
		_rings[i].set_instance_shader_parameter("age", _ring_age[i])
		if _ring_age[i] >= 1.0:
			_rings[i].visible = false


func _cleanup() -> void:
	if local and caster and is_instance_valid(caster):
		caster.gravity_mod = 1.0
		caster.jump_mod = 1.0
		caster.air_control_mod = 1.0
		if caster.landed.is_connected(_on_landed):
			caster.landed.disconnect(_on_landed)
