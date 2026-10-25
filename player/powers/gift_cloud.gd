class_name GiftCloud
extends SmokeGift
## Cloud Ride: the Keling blows a long breath of smoke down at its feet, the
## smoke swirls and plumps up into a fluffy cloud, and up it goes, sitting
## cross-legged on top. Steer with the stick; hold jump to climb, let go to
## sink back to cruising height; sprint to zoom. It banks into turns, bobs,
## leaves a trail of wisps and the odd twinkle, and you can still roll and
## smoke up there. Grab (or the time running out) hops you off, and you
## drift down like a seed.
##
## The caster's controller hands its motion to `drive()` (gift_ride). On a
## friend's screen the same cloud is drawn under the puppet, which follows
## its snapshots and sits because its animation state says so.

const SPEED := 4.4
const SPRINT := 7.5
const CRUISE := 1.9          # above the ground (or water) under the cloud
const MIN_H := 1.15
const MAX_H := 15.0
const RISE := 2.6
const SINK := 1.2
const FORM_TIME := 0.85      # the smoke gathers this long before it lifts you
const MAX_WISPS := 56

static var _cloud_mat: ShaderMaterial
static var _wisp_mat: ShaderMaterial

var riding := false
var _offsets: Array[Vector3] = []
var _radii: Array[float] = []
var _born: Array[float] = []
var _puffs: MultiMeshInstance3D
var _wisps: MultiMeshInstance3D
var _w_pos := PackedVector3Array()
var _w_vel := PackedVector3Array()
var _w_age := PackedFloat32Array()
var _w_life := PackedFloat32Array()
var _w_s0 := PackedFloat32Array()
var _w_s1 := PackedFloat32Array()
var _w_rot := PackedFloat32Array()
var _w_alpha := PackedFloat32Array()
var _w_i := 0
var _w_acc := 0.0
var _twinkle: CPUParticles3D
var _vel_h := Vector3.ZERO
var _alt := 0.0
var _bank := 0.0
var _pitch := 0.0
var _last_facing := 0.0
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _size := 1.0
var _start_wait := 0.0
var _drift := false
var _wind: AudioStreamPlayer3D
var _t := 0.0


func _build() -> void:
	if _cloud_mat == null:
		var noise := preload("res://assets/fx/smoke_noise.png")
		_cloud_mat = ShaderMaterial.new()
		_cloud_mat.shader = preload("res://player/powers/cloud.gdshader")
		_cloud_mat.set_shader_parameter("noise", noise)
		_wisp_mat = ShaderMaterial.new()
		_wisp_mat.shader = preload("res://player/powers/soft_puff.gdshader")
		_wisp_mat.set_shader_parameter("noise", noise)
	_size = 1.0 + 0.2 * (boost - 1.0) / 0.5
	_lay_out()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 9
	_puffs = multimesh(sphere, _offsets.size(), _cloud_mat)
	_puffs.name = "Cloud"
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_wisps = multimesh(q, MAX_WISPS, _wisp_mat)
	_wisps.name = "Wisps"
	_w_pos.resize(MAX_WISPS)
	_w_vel.resize(MAX_WISPS)
	_w_age.resize(MAX_WISPS)
	_w_life.resize(MAX_WISPS)
	_w_s0.resize(MAX_WISPS)
	_w_s1.resize(MAX_WISPS)
	_w_rot.resize(MAX_WISPS)
	_w_alpha.resize(MAX_WISPS)
	_w_age.fill(1.0)
	_w_life.fill(1.0)
	_wisps.multimesh.visible_instance_count = MAX_WISPS
	_twinkle = WeedProps.stars(Color(1.0, 0.95, 0.85), 14, 0.06)
	_twinkle.name = "CloudTwinkles"
	_twinkle.one_shot = false
	_twinkle.explosiveness = 0.0
	_twinkle.lifetime = 1.6
	_twinkle.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_twinkle.emission_box_extents = Vector3(1.0, 0.3, 0.8) * _size
	_twinkle.gravity = Vector3(0, 0.1, 0)
	add_child(_twinkle)
	_wind = AudioStreamPlayer3D.new()
	_wind.bus = &"SFX"
	_wind.max_distance = 30.0
	_wind.unit_size = 3.0
	var path := "res://assets/audio/gifts/cloud_wind.ogg"
	if ResourceLoader.exists(path):
		_wind.stream = load(path)
		(_wind.stream as AudioStreamOggVorbis).loop = true
	add_child(_wind)


## The cloud's puffs: a fat core, a ring round it, a few on top to nestle
## into. Offsets from the feet, in the cloud's own frame (+Z forward).
func _lay_out() -> void:
	var add := func(o: Vector3, r: float) -> void:
		_offsets.append(o * _size)
		_radii.append(r * _size)
		_born.append(0.12 + _offsets.size() * 0.035 + rng.randf() * 0.05)
	for i in 6:
		var a := TAU * i / 6.0 + rng.randf_range(-0.2, 0.2)
		add.call(Vector3(cos(a) * 0.45, -0.38 + rng.randf_range(-0.05, 0.05), sin(a) * 0.38), rng.randf_range(0.46, 0.58))
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf_range(-0.15, 0.15)
		add.call(Vector3(cos(a) * 1.0, -0.42 + rng.randf_range(-0.08, 0.06), sin(a) * 0.78), rng.randf_range(0.3, 0.44))
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		add.call(Vector3(cos(a) * 0.62, -0.12, sin(a) * 0.5), rng.randf_range(0.24, 0.32))
	# A plump tail and nose.
	add.call(Vector3(0.0, -0.5, -1.25), 0.36)
	add.call(Vector3(0.0, -0.45, 1.15), 0.3)


func _start(_data: Dictionary) -> void:
	_last_facing = caster.facing
	_last_pos = caster.global_position
	_alt = caster.global_position.y
	_start_wait = FORM_TIME
	if local and caster.is_sitting():
		caster.stand_up()
		_start_wait = FORM_TIME + 0.6
	play("cloud_form", feet(), 0.0)
	_wind.play()


func _refreshed() -> void:
	play("cloud_form", feet(), -6.0, 1.15)
	for i in 10:
		_wisp(feet() + Vector3(rng.randf_range(-1, 1), -0.3, rng.randf_range(-1, 1)), Vector3(rng.randf_range(-0.5, 0.5), 0.4, rng.randf_range(-0.5, 0.5)), 0.3, 0.9, 1.2, 0.6)


func hop_off() -> void:
	end()


func _on_end() -> void:
	play("cloud_pop", feet(), -2.0)
	if local and riding:
		riding = false
		caster.gift_ride = null
		_drift = true
		caster.launch(2.4)
	riding = false
	for i in 18:
		var o := _offsets[rng.randi() % _offsets.size()]
		_wisp(_cloud_xf() * o, Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.3, 0.5), rng.randf_range(-0.8, 0.8)), 0.4, 1.2, 1.6, 0.8)


func fade_out() -> float:
	return 3.0


# ---------------------------------------------------------------------------
# Riding (caster): the controller calls this instead of its own modes.

func drive(k: KelingController, delta: float) -> void:
	var inp := k.move_input()
	var top := (SPRINT if k.sprinting() else SPEED) * sqrt(boost)
	_vel_h = _vel_h.lerp(inp * top, 1.0 - exp(-1.7 * delta))
	var p := k.global_position
	var fl := floor_at(p.x, p.z)
	var cruise := fl + CRUISE
	if k.jump_held():
		_alt = minf(_alt + RISE * delta, fl + MAX_H * sqrt(boost))
	elif _alt > cruise:
		_alt = maxf(_alt - SINK * delta, cruise)
	else:
		_alt = move_toward(_alt, cruise, SINK * 1.5 * delta)
	_alt = maxf(_alt, fl + MIN_H)
	var bob := sin(_t * 1.7) * 0.1 + sin(_t * 0.63) * 0.06
	var vy := clampf((_alt + bob - p.y) * 2.4, -4.0, 4.0)
	k.velocity = Vector3(_vel_h.x, vy, _vel_h.z)
	if _vel_h.length() > 0.25:
		k.facing = lerp_angle(k.facing, atan2(_vel_h.x, _vel_h.z), 1.0 - exp(-2.6 * delta))
	k.mode = KelingController.Mode.AIR


func _begin_ride() -> void:
	riding = true
	if not local:
		return
	if caster.weed and caster.weed.busy() and not caster.weed_act_allowed():
		caster.weed.interrupt()
	_alt = caster.global_position.y + 0.9
	_vel_h = Vector3(caster.velocity.x, 0.0, caster.velocity.z)
	caster.gift_ride = self
	caster.mode = KelingController.Mode.AIR
	caster.animator.travel(&"SitDown")


# ---------------------------------------------------------------------------

func _tick(dt: float, real: float) -> void:
	_t += real
	if not riding and not ending:
		_start_wait -= real
		if _start_wait <= 0.0:
			_begin_ride()
	if local and _drift:
		# Drifting down after hopping off, like a seed.
		caster.gravity_mod = 0.35 if not caster.is_on_floor() and out_t < 4.0 else 1.0
	var p := feet()
	var moved := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length() / maxf(real, 0.001)
	_last_pos = p
	_speed = lerpf(_speed, minf(moved, 12.0), 1.0 - exp(-4.0 * real))
	var yaw_rate := wrapf(caster.facing - _last_facing, -PI, PI) / maxf(real, 0.001)
	_last_facing = caster.facing
	_bank = lerpf(_bank, clampf(-yaw_rate * _speed * 0.05, -0.32, 0.32), 1.0 - exp(-3.0 * real))
	_pitch = lerpf(_pitch, clampf(_speed * 0.018, 0.0, 0.14), 1.0 - exp(-2.0 * real))
	_update_puffs()
	_emit_wisps(dt, real, p)
	_update_wisps(dt)
	_twinkle.global_transform = _cloud_xf()
	_twinkle.emitting = age > 0.6 and not ending
	_wind.global_position = p
	_wind.volume_db = lerpf(-24.0, -6.0, clampf(_speed / SPRINT, 0.0, 1.0)) + (-30.0 * clampf(out_t, 0.0, 1.0) if ending else 0.0)
	_wind.pitch_scale = 0.8 + 0.4 * clampf(_speed / SPRINT, 0.0, 1.0)


func _cloud_xf() -> Transform3D:
	var b := Basis(Vector3.UP, caster.facing) * Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.BACK, _bank)
	return Transform3D(b, feet())


func _update_puffs() -> void:
	var xf := _cloud_xf()
	var mm := _puffs.multimesh
	mm.visible_instance_count = _offsets.size()
	for i in _offsets.size():
		var g := 0.0
		var a := age - _born[i]
		if a > 0.0:
			g = elastic_out(clampf(a / 0.7, 0.0, 1.0))
		if ending:
			var d := clampf((out_t - i * 0.04) / 1.2, 0.0, 1.0)
			g *= 1.0 - d * d
		var breathe := 1.0 + 0.05 * sin(_t * 1.3 + i * 1.7)
		var r := maxf(_radii[i] * g * breathe, 0.0005)
		var o := _offsets[i]
		# The puffs squash a little flatter when cruising fast.
		var s := Vector3(r * (1.0 + _speed * 0.012), r * (1.0 - _speed * 0.01), r * (1.0 + _speed * 0.02))
		mm.set_instance_transform(i, Transform3D(xf.basis.scaled_local(s), xf * o))
		mm.set_instance_color(i, Color(1, 1, 1, 1))
		mm.set_instance_custom_data(i, Color(float(i) * 0.137 + seed % 97 * 0.01, 0, 0, 0))


func _emit_wisps(dt: float, real: float, p: Vector3) -> void:
	if age < FORM_TIME:
		# The breath going down to the feet, curling round as it gathers.
		var m := mouth()
		_w_acc += real * 40.0
		while _w_acc >= 1.0:
			_w_acc -= 1.0
			var a := rng.randf() * TAU
			var out := Vector3(cos(a), 0, sin(a))
			var to_feet := (p + Vector3(0, -0.2, 0) - m.origin)
			_wisp(m.origin + m.basis.z * 0.03, to_feet * rng.randf_range(1.0, 1.6) + out * 0.9, 0.06, 0.45, 0.8, 0.85)
		return
	if ending:
		return
	# A trail streaming off the back, thicker the faster it goes.
	var rate := 3.0 + _speed * 4.0
	_w_acc += dt * rate
	var xf := _cloud_xf()
	while _w_acc >= 1.0:
		_w_acc -= 1.0
		var side := rng.randf_range(-0.8, 0.8) * _size
		var at := xf * Vector3(side, rng.randf_range(-0.6, -0.2), -1.0 * _size)
		var back := -xf.basis.z * (0.2 + _speed * 0.15)
		_wisp(at, back + Vector3(0, rng.randf_range(-0.1, 0.15), 0), 0.25 * _size, 0.7 * _size, rng.randf_range(0.9, 1.5), 0.55)


func _wisp(at: Vector3, vel: Vector3, s0: float, s1: float, life: float, alpha: float) -> void:
	var i := _w_i
	_w_i = (_w_i + 1) % MAX_WISPS
	_w_pos[i] = at
	_w_vel[i] = vel
	_w_age[i] = 0.0
	_w_life[i] = life
	_w_s0[i] = s0
	_w_s1[i] = s1
	_w_rot[i] = rng.randf() * TAU
	_w_alpha[i] = alpha


func _update_wisps(dt: float) -> void:
	var mm := _wisps.multimesh
	for i in MAX_WISPS:
		if _w_age[i] >= _w_life[i]:
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0, -1000, 0)))
			continue
		_w_age[i] += dt
		var k := clampf(_w_age[i] / _w_life[i], 0.0, 1.0)
		_w_vel[i] *= 1.0 - 1.8 * dt
		_w_pos[i] += _w_vel[i] * dt
		var s := lerpf(_w_s0[i], _w_s1[i], 1.0 - pow(1.0 - k, 2.0))
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), _w_pos[i]))
		var a := _w_alpha[i] * smoothstep(0.0, 0.12, k) * (1.0 - k)
		mm.set_instance_color(i, Color(1.0, 0.98, 1.0, a))
		mm.set_instance_custom_data(i, Color(0, _w_rot[i] + k * 0.6, float(i) * 0.31, 0))


func _cleanup() -> void:
	if local and caster and is_instance_valid(caster):
		if caster.gift_ride == self:
			caster.gift_ride = null
			if caster.is_inside_tree():
				caster.launch(1.0)
		caster.gravity_mod = 1.0
