class_name DragonBreath
extends Node3D
## Dragon Breath: hold the puff and the Keling draws deep, blue light and
## mist gathering at its lips, rears back and blasts it out. The breath roars
## forward as a jet of glowing blue mist, and out of the front of it a water
## dragon unspools: head first, then the whole long body pouring out of the
## mist after it. It swims away through the air in great S-curves, skimming
## the ground, its body glassy water with the forest bent through it, raining
## drops that ring the ground where they land. Then it rears up and plunges
## into the earth (or the first tree in its way) in a burst of spray, a rain
## shower and a rainbow, leaving a puddle behind.
##
## The rain is real water: every wild weed plant it passes over, and every one
## round the splash, ripens its buds; and any Keling it rains on shakes off
## like a wet puppy.
##
## The dragon is tools/dragon_asset.py's unbent Meshy dragon, laid along its
## own flight path by water_dragon.gdshader: every frame this samples SPINE
## points down the trail behind the head, so the body follows the head
## exactly. The path is planned once at release from (origin, yaw, seed), so a
## co-op puppet's dragon (same seed) flies the same way on every screen; only
## the caster's own game ripens plants and tells the others.
##
## One node per breath, under the caster but in world space; it frees itself
## once the last drop has landed and the rainbow has faded.

signal released

enum Phase { CHARGE, FLY, AFTER, DONE }

const MESH_PATH := "res://assets/fx/dragon/water_dragon.glb"
const META_PATH := "res://assets/fx/dragon/water_dragon.json"
const SPINE := 48                 # spine points sent to the shader (matches it)
const BODY_SCALE := 1.15          # ~7.3 m of dragon
const PATH_STEP := 0.25
const FLIGHT := 24.0              # how far it swims before diving (m)
const CRUISE := 1.75              # height over the ground while swimming
const FINALE := 8.0               # the rear-up and dive at the end (m)
const BANK := 0.35
const LAUNCH_SPEED := 15.0
const SWIM_SPEED := 8.5
const DIVE_SPEED := 12.0
const DRIP_RATE := 70.0
const RAIN_TIME := 1.8
const RAINBOW_TIME := 7.5
const PUDDLE_TIME := 26.0
const MAX_MIST := 128
const MAX_DROPS := 240
const MAX_RINGS := 28
const WATER_TINT := Color(0.36, 0.7, 1.0)
const GLOW_TINT := Color(0.45, 0.9, 1.0)

static var _mesh: Mesh
static var _meta: Dictionary
static var _dragon_shader: Shader = preload("res://player/powers/water_dragon.gdshader")
static var _mist_mat: ShaderMaterial
static var _drop_mat: ShaderMaterial
static var _ring_mat: ShaderMaterial
static var _rainbow_mesh: ArrayMesh
static var _rainbow_shader: Shader = preload("res://player/powers/rainbow.gdshader")
static var _puddle_tex: Array[Texture2D] = []
static var _orb_mat: StandardMaterial3D
static var _noise: Texture2D = preload("res://assets/fx/smoke_noise.png")
static var _clips := {}

var caster: Node3D
var local := true
var phase: int = Phase.CHARGE
var yaw := 0.0
var seed := 0
var impact_point := Vector3.ZERO
var ripened := 0

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _fly_t := 0.0
var _charge := 0.0
var _mouth := Transform3D.IDENTITY
var _body_len := 6.3
var _girth := PackedFloat32Array()
var _seg := 0.1

# The flight path: points PATH_STEP apart, and the body's up along it.
var _pts := PackedVector3Array()
var _ups := PackedVector3Array()
var _len := 0.0
var _dir0 := Vector3.FORWARD
var _dir1 := Vector3.DOWN
var _head := 0.0
var _speed := LAUNCH_SPEED
var _impacted := false
var _impact_t := 0.0
var _jet_t := -1.0
var _spine := PackedVector4Array()
var _spine_up := PackedVector4Array()

var _dragon: MeshInstance3D
var _dragon_mat: ShaderMaterial
var _light: OmniLight3D
var _orb: MeshInstance3D

# Mist puffs, drops and rings, as parallel arrays drawn by one MultiMesh each.
var _m_pos := PackedVector3Array()
var _m_vel := PackedVector3Array()
var _m_age := PackedFloat32Array()
var _m_life := PackedFloat32Array()
var _m_s0 := PackedFloat32Array()
var _m_s1 := PackedFloat32Array()
var _m_rot := PackedFloat32Array()
var _m_spin := PackedFloat32Array()
var _m_seed := PackedFloat32Array()
var _m_alpha := PackedFloat32Array()
var _m_drag := PackedFloat32Array()
var _m_col := PackedColorArray()
var _m_alive := 0
var _m_acc := {}
var _mist_mm: MultiMesh
var _mist_mmi: MultiMeshInstance3D
var _mist_buf := PackedFloat32Array()

var _d_pos := PackedVector3Array()
var _d_vel := PackedVector3Array()
var _d_age := PackedFloat32Array()
var _d_life := PackedFloat32Array()
var _d_size := PackedFloat32Array()
var _d_floor := PackedFloat32Array()
var _d_kind := PackedByteArray()     # 0 drip (rings when it lands), 1 spray bead
var _d_alive := 0
var _d_next := 0
var _drop_mm: MultiMesh
var _drop_mmi: MultiMeshInstance3D
var _drop_buf := PackedFloat32Array()
var _drip_acc := 0.0
var _rain_acc := 0.0

var _r_pos := PackedVector3Array()
var _r_size := PackedFloat32Array()
var _r_age := PackedFloat32Array()
var _r_life := PackedFloat32Array()
var _r_str := PackedFloat32Array()
var _r_seed := PackedFloat32Array()
var _r_next := 0
var _ring_mm: MultiMesh
var _ring_mmi: MultiMeshInstance3D
var _ring_buf := PackedFloat32Array()

var _rainbow: MeshInstance3D
var _rainbow_mat: ShaderMaterial
var _puddle: Decal

var _plants: Array = []     # [[u along the path, plant], ...] still to water
var _soaked := {}           # Kelings already rained on
var _soak_tick := 0.0
var _voice_mouth: AudioStreamPlayer3D
var _voice_head: AudioStreamPlayer3D
var _voice_splash: AudioStreamPlayer3D
var _ripple_budget := 0.0


# ---------------------------------------------------------------------------
# Life cycle

func setup(p_caster: Node3D, p_local: bool, p_yaw: float, p_seed: int) -> void:
	caster = p_caster
	local = p_local
	yaw = p_yaw
	seed = p_seed
	_rng.seed = p_seed


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_load_shared()
	_body_len = float(_meta.get("length", 6.3))
	for g in _meta.get("girth", []):
		_girth.append(float(g))
	if _girth.size() != SPINE:
		_girth.resize(SPINE)
		_girth.fill(0.14)
	_seg = _body_len * BODY_SCALE / float(SPINE - 1)
	_spine.resize(SPINE)
	_spine_up.resize(SPINE)
	_build_dragon()
	_build_mist()
	_build_drops()
	_build_rings()
	_build_glow()
	_build_voices()


## The breath is being drawn in: blue mist spirals into the lips and a light
## gathers there. `mouth` is the mouth in world space (looking out of it),
## `k` how far the draw has come (0..1).
func charge(mouth: Transform3D, k: float) -> void:
	_mouth = mouth
	_charge = k


## Blast it out: the jet leaves the mouth and the dragon flies `yaw`.
func release(mouth: Transform3D, p_yaw: float) -> void:
	if phase != Phase.CHARGE:
		return
	_mouth = mouth
	yaw = p_yaw
	phase = Phase.FLY
	_jet_t = 0.0
	_fly_t = 0.0
	_head = -0.35
	_plan(mouth.origin)
	_dragon.visible = true
	_play(_voice_mouth, "roar", 1.0, 2.0)
	_play(_voice_head, "rush", 1.0, -4.0)
	released.emit()


## The draw was cut short (walked off): the gathered mist just drifts away.
func fizzle() -> void:
	if phase == Phase.CHARGE:
		phase = Phase.AFTER
		_charge = 0.0
		for i in 6:
			_mist_puff(_mouth.origin + _jitter(0.06), _jitter(0.4) + Vector3.UP * 0.2, 0.08, 0.3, 1.1, 0.5, 2.0)


func is_flying() -> bool:
	return phase == Phase.FLY


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_timed(minf(delta, 0.05))
	PerfMeter.add(&"dragon breath", Time.get_ticks_usec() - t0)


func _process_timed(delta: float) -> void:
	_t += delta
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3(0, 2, 5)
	match phase:
		Phase.CHARGE:
			_update_charge(delta)
		Phase.FLY:
			_update_flight(delta)
	_update_glow(delta)
	if _jet_t >= 0.0:
		_update_jet(delta)
	_update_mist(delta, eye)
	_update_drops(delta)
	_update_rings(delta)
	_update_after(delta)
	if phase == Phase.AFTER and _m_alive == 0 and _d_alive == 0 and _rings_alive() == 0 and _rainbow_done() \
			and (_puddle == null or not _puddle.visible):
		phase = Phase.DONE
		queue_free()


# ---------------------------------------------------------------------------
# The draw

func _update_charge(delta: float) -> void:
	var m := _mouth.origin
	var k := _charge
	# Wisps spiral in from around the head and vanish into the lips.
	var rate := 26.0 * k
	var acc: float = _m_acc.get(&"charge", 0.0) + rate * delta
	while acc >= 1.0:
		acc -= 1.0
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 1.0), _rng.randf_range(-1, 1)).normalized()
		var from := m + dir * _rng.randf_range(0.35, 0.65)
		var tangent := dir.cross(Vector3.UP).normalized() * 0.5
		_mist_puff(from, (m - from) * 2.1 + tangent, 0.07, 0.015, 0.5, 0.55 * k, 0.0, GLOW_TINT)
	_m_acc[&"charge"] = acc


func _update_glow(delta: float) -> void:
	var want := 0.0
	var at := _mouth.origin
	var range_m := 1.6
	if phase == Phase.CHARGE:
		want = _charge
	elif phase == Phase.FLY:
		at = _pos_at(_head - _seg * 3.0)
		want = clampf(_fly_t * 3.0, 0.0, 1.0) * (1.0 - clampf((_head - _len) / 3.0, 0.0, 1.0))
		range_m = 5.5
	_light.visible = want > 0.01
	if _light.visible:
		_light.global_position = at
		_light.light_energy = lerpf(_light.light_energy, want * (1.6 if phase == Phase.CHARGE else 2.4), 1.0 - exp(-delta * 10.0))
		_light.omni_range = range_m
	var orb := _charge if phase == Phase.CHARGE else maxf(0.0, 1.0 - _jet_t * 4.0) if _jet_t >= 0.0 else 0.0
	_orb.visible = orb > 0.01
	if _orb.visible:
		_orb.global_position = _mouth.origin + _mouth.basis.z * 0.03
		var pulse := 1.0 + 0.12 * sin(_t * 23.0)
		_orb.scale = Vector3.ONE * maxf(orb * pulse, 0.001)


# ---------------------------------------------------------------------------
# The flight

## Lays out the whole flight from where the breath leaves the lips: out and
## up to cruising height, weaving left and right and bobbing, terrain
## hugging, then the rear-up and the dive. It stops early where it would hit
## something solid: that is where the water lands.
func _plan(origin: Vector3) -> void:
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var side := Vector3(cos(yaw), 0.0, -sin(yaw))
	var start := origin + fwd * 0.55 + Vector3.UP * 0.15
	var amp := _rng.randf_range(1.1, 1.7) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var wave := _rng.randf_range(9.0, 12.0)
	var bob := _rng.randf_range(6.0, 8.5)
	var bob_phase := _rng.randf() * TAU
	var step := 0.5
	var n := int(FLIGHT / step) + 1
	var xz: Array[Vector3] = []
	var ground := PackedFloat32Array()
	for i in n:
		var d := i * step
		var lat := amp * sin(d / wave * TAU) * smoothstep(1.0, 7.0, d)
		var p := start + fwd * d + side * lat
		xz.append(p)
		ground.append(_floor_at(p.x, p.z))
	# The ground it skims, eased (it flies over a bump, not into each one).
	var eased := PackedFloat32Array()
	eased.resize(n)
	for i in n:
		var g := -INF
		for j in range(maxi(i - 3, 0), mini(i + 4, n)):
			g = maxf(g, ground[j])
		eased[i] = g
	for _pass in 2:
		var copy := eased.duplicate()
		for i in range(1, n - 1):
			eased[i] = maxf((copy[i - 1] + copy[i] + copy[i + 1]) / 3.0, ground[i] + 0.6)
	var raw := PackedVector3Array()
	for i in n:
		var d := i * step
		var g := eased[i]
		var cruise := g + CRUISE + 0.45 * sin(d / bob * TAU + bob_phase)
		var y := lerpf(start.y, cruise, smoothstep(0.0, 4.0, d))
		var k := (d - (FLIGHT - FINALE)) / FINALE
		if k > 0.0:
			if k < 0.5:
				y += 2.8 * sin(k * PI)
			else:
				var f := (k - 0.5) / 0.5
				y = lerpf(cruise + 2.8, ground[i] - 0.7, f * f)
		raw.append(Vector3(xz[i].x, y, xz[i].z))
	# Anything solid in the way (a tree, a rock, a cliff) is where it lands.
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space:
		for i in range(4, n):
			var q := PhysicsRayQueryParameters3D.create(raw[i - 1], raw[i], 1)
			var hit := space.intersect_ray(q)
			if hit:
				raw.resize(i)
				raw.append(hit.position)
				break
	_resample(raw)
	_dir0 = (_pts[1] - _pts[0]).normalized()
	_dir1 = (_pts[_pts.size() - 1] - _pts[_pts.size() - 2]).normalized()
	impact_point = _pts[_pts.size() - 1]
	_bank_ups()
	_find_plants()


func _resample(raw: PackedVector3Array) -> void:
	_pts.clear()
	_pts.append(raw[0])
	var carry := 0.0
	for i in range(1, raw.size()):
		var a := raw[i - 1]
		var b := raw[i]
		var l := a.distance_to(b)
		var d := PATH_STEP - carry
		while d <= l:
			_pts.append(a.lerp(b, d / l))
			d += PATH_STEP
		carry = l - (d - PATH_STEP)
	if _pts.size() < 3:
		_pts.append(raw[raw.size() - 1] + Vector3(0, 0, 0.01))
		_pts.append(raw[raw.size() - 1] + Vector3(0, 0, 0.02))
	_len = (_pts.size() - 1) * PATH_STEP


## The body's up along the path, leaning into each turn like a swimmer.
func _bank_ups() -> void:
	var n := _pts.size()
	_ups.resize(n)
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	for i in n:
		var a := _pts[maxi(i - 4, 0)]
		var b := _pts[i]
		var c := _pts[mini(i + 4, n - 1)]
		var t := (c - a).normalized()
		var bend := (a + c - 2.0 * b) / (PATH_STEP * PATH_STEP * 16.0)
		var lateral := bend - t * bend.dot(t)
		var up := Vector3.UP + lateral * BANK * 4.0
		if absf(t.dot(Vector3.UP)) > 0.97:
			up = -fwd if t.y > 0.0 else fwd
		up = (up - t * up.dot(t)).normalized()
		_ups[i] = up
	for _pass in 3:
		var copy := _ups.duplicate()
		for i in range(1, n - 1):
			_ups[i] = (copy[i - 1] + copy[i] * 2.0 + copy[i + 1]).normalized()


func _pos_at(u: float) -> Vector3:
	if u <= 0.0:
		return _pts[0] + _dir0 * u
	if u >= _len:
		return _pts[_pts.size() - 1] + _dir1 * (u - _len)
	var f := u / PATH_STEP
	var i := int(f)
	return _pts[i].lerp(_pts[mini(i + 1, _pts.size() - 1)], f - i)


func _up_at(u: float) -> Vector3:
	var f := clampf(u / PATH_STEP, 0.0, _ups.size() - 1.001)
	var i := int(f)
	return _ups[i].lerp(_ups[mini(i + 1, _ups.size() - 1)], f - i)


func _update_flight(delta: float) -> void:
	_fly_t += delta
	if _fly_t < 0.12:
		_speed = 0.0     # the jet leads; the head forms in it a beat later
	else:
		var target := lerpf(LAUNCH_SPEED, SWIM_SPEED, smoothstep(0.12, 0.9, _fly_t))
		if _head > _len - FINALE * 0.5:
			target = lerpf(target, DIVE_SPEED, smoothstep(_len - FINALE * 0.5, _len - 1.0, _head))
		_speed = target
	_head += _speed * delta
	var tail_u := _head - _body_len * BODY_SCALE
	# Lay the body down the trail behind the head.
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for k in SPINE:
		var u := _head - k * _seg
		var p := _pos_at(u)
		var up := _up_at(u)
		var swell := 1.0 + 0.07 * sin(_t * 5.0 - k * 0.45)
		_spine[k] = Vector4(p.x, p.y, p.z, swell)
		_spine_up[k] = Vector4(up.x, up.y, up.z, 0.0)
		lo = lo.min(p)
		hi = hi.max(p)
	_dragon_mat.set_shader_parameter("spine", _spine)
	_dragon_mat.set_shader_parameter("spine_up", _spine_up)
	_dragon_mat.set_shader_parameter("head_dist", _head)
	_dragon_mat.set_shader_parameter("swim_phase", _t * 7.0)
	_dragon.custom_aabb = AABB(lo - Vector3.ONE * 2.0, hi - lo + Vector3.ONE * 4.0)
	_voice_head.global_position = _pos_at(minf(_head, _len))

	# Still pouring out of the mist where it left the jet.
	if tail_u < 0.5:
		var dir := _dir0
		_mist_stream(&"emerge", _pts[0], dir, 46.0, 3.0, 0.3, 1.0, 0.9, 0.55, 0.35, delta)
	elif _head < _len:
		# A trail of mist off the tail tip.
		var tip := _pos_at(tail_u)
		_mist_stream(&"trail", tip, _dir0 * -0.2 + Vector3.UP * 0.1, 16.0, 0.6, 0.25, 0.8, 1.3, 0.32, 0.8, delta)
	_drip(delta)
	if _head >= _len and not _impacted:
		_impact()
	if _impacted:
		# The body pours into the splash: spray where it goes in.
		var sinking := clampf((_head - _len) / (_body_len * BODY_SCALE), 0.0, 1.0)
		if sinking < 1.0:
			var acc: float = _m_acc.get(&"pour", 0.0) + 55.0 * delta
			while acc >= 1.0:
				acc -= 1.0
				_fountain_drop(1.0 - sinking * 0.6)
			_m_acc[&"pour"] = acc
	_water_plants(minf(_head, _len))
	_soak_tick -= delta
	if _soak_tick <= 0.0:
		_soak_tick = 0.15
		_soak_kelings(tail_u)
	if tail_u > _len + 0.4:
		_dragon.visible = false
		_voice_head.stop()
		phase = Phase.AFTER


## Drops fall from the belly of every part of the body that's out in the air.
func _drip(delta: float) -> void:
	_drip_acc += DRIP_RATE * delta
	while _drip_acc >= 1.0:
		_drip_acc -= 1.0
		var k := _rng.randi_range(4, SPINE - 3)
		var u := _head - k * _seg
		if u < 0.3 or u > _len - 0.3:
			continue
		var p := _pos_at(u)
		var up := _up_at(u)
		var t := (_pos_at(u + 0.2) - p).normalized()
		var left := up.cross(t).normalized()
		var r := _girth[k] * BODY_SCALE
		var a := _rng.randf_range(-1.2, 1.2)
		var at := p - up * r * cos(a) * 0.9 + left * r * sin(a)
		var vel := t * _speed * 0.3 + Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-1.4, -0.4), _rng.randf_range(-0.5, 0.5))
		_drop(at, vel, _rng.randf_range(0.022, 0.042), 3.0, 0)


func _impact() -> void:
	_impacted = true
	_impact_t = 0.0
	# The dive ends just under the ground; a tree or a rock keeps its height.
	var floor_y := _floor_at(impact_point.x, impact_point.z)
	impact_point.y = maxf(impact_point.y, floor_y)
	var p := impact_point
	var below := Vector3(p.x, floor_y, p.z)
	for i in 70:
		_fountain_drop(1.0)
	for i in 3:
		_ring(below, 1.6 + i * 1.3, 1.1 + i * 0.35, 1.0 - i * 0.2)
	for i in 20:
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.3, 1.2), _rng.randf_range(-1, 1)).normalized()
		_mist_puff(p + dir * 0.3, dir * _rng.randf_range(1.5, 3.8), 0.4, 1.7, 1.6, 0.5, 1.6, WATER_TINT.lightened(0.3))
	if WaterLevel.surface_at(p.x, p.z) > WaterLevel.ground_at(p.x, p.z) + 0.05:
		WaterFX.ripple(p, 1.5, 3.2)
		WaterFX.ripple(p + Vector3(0.6, 0, 0.3), 1.0, 2.6)
	else:
		_place_puddle(below)
	_place_rainbow(below)
	_voice_splash.global_position = p
	_play(_voice_splash, "splash", 1.0, 3.0)
	_shake_cameras(p)
	if local:
		var n := _ripen_near(p, 5.5)
		if n > 0 and caster and caster.get("weed"):
			caster.weed.note.emit("The dragon's rain ripened %d plant%s!" % [n, "" if n == 1 else "s"])


func _fountain_drop(power: float) -> void:
	var p := impact_point + Vector3(_rng.randf_range(-0.3, 0.3), 0.05, _rng.randf_range(-0.3, 0.3))
	var out := Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)).normalized()
	var vel := out * _rng.randf_range(0.6, 3.6) * power + Vector3.UP * _rng.randf_range(2.5, 7.0) * power
	_drop(p, vel, _rng.randf_range(0.025, 0.05), 3.0, 0 if _rng.randf() < 0.45 else 1)


func _shake_cameras(p: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := cam.global_position.distance_to(p)
	var tree := get_tree()
	if tree == null:
		return
	var me := tree.get_first_node_in_group("local_player")
	if me and me.get("camera_rig") and d < 22.0:
		me.camera_rig.shake(0.22 * (1.0 - d / 22.0))


# ---------------------------------------------------------------------------
# Watering the forest

func _find_plants() -> void:
	_plants.clear()
	if not local or not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("weed_plant"):
		var plant := n as Node3D
		if plant == null or not plant.has_method("ripen_all"):
			continue
		var pp := plant.global_position
		var best := INF
		var best_u := 0.0
		for i in range(0, _pts.size(), 2):
			var q := _pts[i]
			var d := Vector2(q.x - pp.x, q.z - pp.z).length()
			if d < best:
				best = d
				best_u = i * PATH_STEP
		if best < 2.6:
			# Watered by the drips once the middle of the body passes over.
			_plants.append([best_u + _body_len * BODY_SCALE * 0.35, plant])


func _water_plants(head_u: float) -> void:
	if _plants.is_empty():
		return
	var keep: Array = []
	var n := 0
	for e in _plants:
		if head_u >= float(e[0]):
			var plant = e[1]
			if is_instance_valid(plant) and _ripen(plant):
				n += 1
		else:
			keep.append(e)
	_plants = keep
	if n > 0 and caster and caster.get("weed"):
		caster.weed.note.emit("Dragon rain! %d plant%s burst into bud" % [n, "" if n == 1 else "s"])


func _ripen_near(p: Vector3, radius: float) -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("weed_plant"):
		var plant := node as Node3D
		if plant and plant.has_method("ripen_all") and plant.global_position.distance_to(p) < radius:
			if _ripen(plant):
				n += 1
	return n


func _ripen(plant: Node3D) -> bool:
	if not plant.ripen_all():
		return false
	ripened += 1
	var weed = caster.get("weed") if caster else null
	if weed:
		weed.net_event(&"weed_ripened", plant.get("net_index"))
	for i in 10:
		_drop(plant.global_position + Vector3(_rng.randf_range(-0.3, 0.3), 1.2, _rng.randf_range(-0.3, 0.3)),
				Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(0.5, 1.6), _rng.randf_range(-0.6, 0.6)), 0.03, 2.0, 1)
	return true


## Any Keling the dragon rains on (or splashes) shakes off like a wet puppy.
func _soak_kelings(tail_u: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("player"):
		var k := node as Node3D
		if k == null or k == caster or _soaked.has(k) or not k.has_method("shake_off"):
			continue
		var kp := k.global_position
		var wet := false
		if _impacted and kp.distance_to(impact_point) < 4.0:
			wet = true
		else:
			for i in range(0, SPINE, 4):
				var u := _head - i * _seg
				if u < 0.0 or u > _len or u > tail_u + _body_len * BODY_SCALE:
					continue
				var p := _pos_at(u)
				if p.y > kp.y and Vector2(p.x - kp.x, p.z - kp.z).length() < 1.3:
					wet = true
					break
		if wet:
			_soaked[k] = true
			get_tree().create_timer(_rng.randf_range(0.7, 1.1)).timeout.connect(func():
				if is_instance_valid(k):
					k.shake_off())


# ---------------------------------------------------------------------------
# The jet of breath

func _update_jet(delta: float) -> void:
	_jet_t += delta
	if _jet_t > 0.6:
		return
	var k := _jet_t / 0.6
	var dir := Vector3(sin(yaw), 0.0, cos(yaw))
	dir = (dir + Vector3.UP * 0.06).normalized()
	var o := _mouth.origin + _mouth.basis.z * 0.02
	_mist_stream(&"jet", o, dir, 120.0 * (1.0 - k * 0.6), lerpf(15.0, 9.0, k), 0.07, 1.15, 1.25, lerpf(0.85, 0.5, k), 0.12, delta, 2.3)


# ---------------------------------------------------------------------------
# After the splash: rain, the rainbow, the puddle drying

func _update_after(delta: float) -> void:
	if not _impacted:
		return
	_impact_t += delta
	if _impact_t < RAIN_TIME:
		# A short shower over the splash.
		var fade := 1.0 - _impact_t / RAIN_TIME
		_rain_acc += 95.0 * fade * delta
		while _rain_acc >= 1.0:
			_rain_acc -= 1.0
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * 3.6
			var p := impact_point + Vector3(cos(a) * r, _rng.randf_range(3.2, 4.6), sin(a) * r)
			_drop(p, Vector3(WeedSmoke.wind.x, -_rng.randf_range(5.5, 7.5), WeedSmoke.wind.z), _rng.randf_range(0.018, 0.028), 2.0, 0)
	if _rainbow:
		var s := smoothstep(0.6, 1.8, _impact_t) * (1.0 - smoothstep(RAINBOW_TIME - 2.5, RAINBOW_TIME, _impact_t))
		_rainbow_mat.set_shader_parameter("strength", s)
		_rainbow.visible = s > 0.001
	if _puddle:
		var f := 1.0 - smoothstep(PUDDLE_TIME * 0.5, PUDDLE_TIME, _impact_t)
		_puddle.modulate = Color(1, 1, 1, f * smoothstep(0.0, 0.4, _impact_t))
		_puddle.visible = f > 0.001


func _rainbow_done() -> bool:
	return _rainbow == null or not _impacted or _impact_t > RAINBOW_TIME


func _place_rainbow(p: Vector3) -> void:
	if _rainbow_mesh == null:
		_rainbow_mesh = _make_rainbow_mesh()
	_rainbow_mat = ShaderMaterial.new()
	_rainbow_mat.shader = _rainbow_shader
	_rainbow = MeshInstance3D.new()
	_rainbow.name = "Rainbow"
	_rainbow.mesh = _rainbow_mesh
	_rainbow.material_override = _rainbow_mat
	_rainbow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rainbow.visible = false
	add_child(_rainbow)
	# Arched over the splash, square on to whoever is watching.
	var cam := get_viewport().get_camera_3d()
	var from := cam.global_position if cam else p - Vector3(sin(yaw), 0, cos(yaw)) * 8.0
	var to := Vector3(p.x - from.x, 0.0, p.z - from.z)
	var face := atan2(to.x, to.z) if to.length() > 0.1 else yaw
	_rainbow.global_transform = Transform3D(Basis(Vector3.UP, face), p + Vector3(0.0, -0.6, 0.0) + to.normalized() * 1.5)


static func _make_rainbow_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r0 := 3.4
	var w := 0.6
	var seg := 40
	for i in seg:
		var a0 := PI * i / seg
		var a1 := PI * (i + 1) / seg
		var quad := [[a0, 0.0], [a1, 0.0], [a1, 1.0], [a0, 0.0], [a1, 1.0], [a0, 1.0]]
		for q in quad:
			var a: float = q[0]
			var across: float = q[1]
			var r := r0 + w * across
			st.set_uv(Vector2(a / PI, across))
			st.add_vertex(Vector3(cos(a) * r, sin(a) * r, 0.0))
	return st.commit()


func _place_puddle(p: Vector3) -> void:
	if _puddle_tex.is_empty():
		_puddle_tex = _make_puddle_textures()
	_puddle = Decal.new()
	_puddle.name = "Puddle"
	_puddle.size = Vector3(4.2, 2.0, 4.2)
	_puddle.texture_albedo = _puddle_tex[0]
	_puddle.texture_orm = _puddle_tex[1]
	_puddle.albedo_mix = 1.0
	_puddle.upper_fade = 0.3
	_puddle.lower_fade = 0.3
	_puddle.cull_mask = 1
	add_child(_puddle)
	_puddle.global_transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p)
	_puddle.modulate = Color(1, 1, 1, 0)


## A dark, glossy wet patch with ragged edges and a few droplet spots round it.
static func _make_puddle_textures() -> Array[Texture2D]:
	var n := 128
	var alb := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var orm := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.05
	var spots := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.55, 0.95)
		spots.append([Vector2(cos(a), sin(a)) * r, rng.randf_range(0.03, 0.07)])
	for y in n:
		for x in n:
			var p := Vector2(x, y) / (n - 1) * 2.0 - Vector2.ONE
			var r := p.length() + noise.get_noise_2d(x, y) * 0.28
			var wet := 1.0 - smoothstep(0.42, 0.62, r)
			for s in spots:
				wet = maxf(wet, 1.0 - smoothstep(float(s[1]) * 0.6, float(s[1]), p.distance_to(s[0])))
			alb.set_pixel(x, y, Color(0.06, 0.09, 0.12, wet * 0.55))
			orm.set_pixel(x, y, Color(1.0, lerpf(0.7, 0.06, wet), 0.0, wet))
	return [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(orm)]


# ---------------------------------------------------------------------------
# Mist

func _mist_puff(at: Vector3, vel: Vector3, s0: float, s1: float, life: float, alpha := 1.0, drag := 2.2, col := WATER_TINT) -> void:
	var i := _free_mist()
	_m_pos[i] = at
	_m_vel[i] = vel
	_m_age[i] = 0.0
	_m_life[i] = life * _rng.randf_range(0.85, 1.15)
	_m_s0[i] = s0 * _rng.randf_range(0.8, 1.2)
	_m_s1[i] = s1 * _rng.randf_range(0.8, 1.2)
	_m_rot[i] = _rng.randf() * TAU
	_m_spin[i] = _rng.randf_range(-0.9, 0.9)
	_m_seed[i] = _rng.randf()
	_m_alpha[i] = alpha
	_m_drag[i] = drag
	_m_col[i] = col.lerp(GLOW_TINT, _rng.randf() * 0.4)


func _mist_stream(key: StringName, at: Vector3, dir: Vector3, rate: float, speed: float, s0: float, s1: float, life: float, alpha: float, spread: float, delta: float, drag := 2.2) -> void:
	var acc: float = _m_acc.get(key, _rng.randf()) + rate * delta
	while acc >= 1.0:
		acc -= 1.0
		var d := (dir.normalized() + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * spread).normalized()
		_mist_puff(at + d * 0.02, d * speed * _rng.randf_range(0.8, 1.15), s0, s1, life, alpha, drag)
	_m_acc[key] = acc


func _free_mist() -> int:
	var best := 0
	var best_left := INF
	for i in MAX_MIST:
		var left := _m_life[i] - _m_age[i]
		if left <= 0.0:
			return i
		if left < best_left:
			best_left = left
			best = i
	return best


func _update_mist(delta: float, eye: Vector3) -> void:
	var order: Array[int] = []
	var dist := {}
	for i in MAX_MIST:
		var a := _m_age[i]
		if a >= _m_life[i]:
			continue
		a += delta
		_m_age[i] = a
		if a >= _m_life[i]:
			continue
		var v := _m_vel[i] * exp(-_m_drag[i] * delta)
		v.y += 0.12 * delta
		v += WeedSmoke.flow(_m_pos[i] * 0.5, _t, _m_seed[i] * 9.0) * 0.25 * minf(a, 1.0) * delta
		_m_vel[i] = v
		_m_pos[i] += v * delta
		_m_rot[i] += _m_spin[i] * delta
		order.append(i)
		dist[i] = _m_pos[i].distance_squared_to(eye)
	_m_alive = order.size()
	if _m_alive == 0:
		if _mist_mm.visible_instance_count != 0:
			_mist_mm.visible_instance_count = 0
		return
	order.sort_custom(func(x: int, y: int) -> bool: return dist[x] > dist[y])
	var o := 0
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for i in order:
		var a01 := _m_age[i] / _m_life[i]
		var size := lerpf(_m_s0[i], _m_s1[i], 1.0 - exp(-_m_age[i] * 2.2))
		var alpha := 0.5 * _m_alpha[i] * smoothstep(0.0, 0.12, _m_age[i]) * pow(1.0 - a01, 1.4)
		var p := _m_pos[i]
		var c := _m_col[i]
		lo = lo.min(p - Vector3.ONE * size)
		hi = hi.max(p + Vector3.ONE * size)
		_mist_buf[o] = size; _mist_buf[o + 1] = 0.0; _mist_buf[o + 2] = 0.0; _mist_buf[o + 3] = p.x
		_mist_buf[o + 4] = 0.0; _mist_buf[o + 5] = size; _mist_buf[o + 6] = 0.0; _mist_buf[o + 7] = p.y
		_mist_buf[o + 8] = 0.0; _mist_buf[o + 9] = 0.0; _mist_buf[o + 10] = size; _mist_buf[o + 11] = p.z
		_mist_buf[o + 12] = c.r; _mist_buf[o + 13] = c.g; _mist_buf[o + 14] = c.b; _mist_buf[o + 15] = 1.0
		_mist_buf[o + 16] = a01; _mist_buf[o + 17] = _m_seed[i]; _mist_buf[o + 18] = _m_rot[i]; _mist_buf[o + 19] = alpha
		o += 20
	for j in range(o, _mist_buf.size()):
		_mist_buf[j] = 0.0
	_mist_mm.buffer = _mist_buf
	_mist_mm.visible_instance_count = _m_alive
	_mist_mmi.custom_aabb = AABB(lo, hi - lo)


# ---------------------------------------------------------------------------
# Drops

func _drop(at: Vector3, vel: Vector3, size: float, life: float, kind: int) -> void:
	var i := _d_next
	_d_next = (_d_next + 1) % MAX_DROPS
	_d_pos[i] = at
	_d_vel[i] = vel
	_d_age[i] = 0.0
	_d_life[i] = life
	_d_size[i] = size
	_d_floor[i] = _floor_at(at.x, at.z)
	_d_kind[i] = kind


func _update_drops(delta: float) -> void:
	var o := 0
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	_ripple_budget = minf(_ripple_budget + delta * 3.0, 2.0)
	for i in MAX_DROPS:
		if _d_age[i] >= _d_life[i]:
			continue
		_d_age[i] += delta
		var v := _d_vel[i]
		v.y -= 9.8 * delta
		v *= 1.0 - 0.25 * delta
		var p := _d_pos[i] + v * delta
		_d_vel[i] = v
		if v.y < 0.0 and p.y < _d_floor[i] + 0.4:
			var f := _floor_at(p.x, p.z)
			_d_floor[i] = f
			if p.y <= f:
				_land(Vector3(p.x, f, p.z), i)
				_d_age[i] = _d_life[i]
				continue
		_d_pos[i] = p
		var alpha := 0.85 * (1.0 - smoothstep(0.75, 1.0, _d_age[i] / _d_life[i]))
		lo = lo.min(p)
		hi = hi.max(p)
		_drop_buf[o] = 1.0; _drop_buf[o + 1] = 0.0; _drop_buf[o + 2] = 0.0; _drop_buf[o + 3] = p.x
		_drop_buf[o + 4] = 0.0; _drop_buf[o + 5] = 1.0; _drop_buf[o + 6] = 0.0; _drop_buf[o + 7] = p.y
		_drop_buf[o + 8] = 0.0; _drop_buf[o + 9] = 0.0; _drop_buf[o + 10] = 1.0; _drop_buf[o + 11] = p.z
		_drop_buf[o + 12] = 1.0; _drop_buf[o + 13] = 1.0; _drop_buf[o + 14] = 1.0; _drop_buf[o + 15] = _d_size[i]
		_drop_buf[o + 16] = v.x; _drop_buf[o + 17] = v.y; _drop_buf[o + 18] = v.z; _drop_buf[o + 19] = alpha
		o += 20
	_d_alive = o / 20
	if _d_alive == 0:
		if _drop_mm.visible_instance_count != 0:
			_drop_mm.visible_instance_count = 0
		return
	for j in range(o, _drop_buf.size()):
		_drop_buf[j] = 0.0
	_drop_mm.buffer = _drop_buf
	_drop_mm.visible_instance_count = _d_alive
	_drop_mmi.custom_aabb = AABB(lo - Vector3.ONE, hi - lo + Vector3.ONE * 2.0)


func _land(p: Vector3, i: int) -> void:
	var size := _d_size[i]
	var on_water := WaterLevel.surface_at(p.x, p.z) > WaterLevel.ground_at(p.x, p.z) + 0.03
	if on_water:
		if _ripple_budget >= 1.0 and _rng.randf() < 0.3:
			_ripple_budget -= 1.0
			WaterFX.ripple(p, 0.35, 1.4)
		_ring(p, _rng.randf_range(0.25, 0.45), 0.8, 0.8)
		return
	if _d_kind[i] == 0 and _rng.randf() < 0.4:
		_ring(p, _rng.randf_range(0.22, 0.5), _rng.randf_range(0.5, 0.8), 0.75)
	if size > 0.024 and _rng.randf() < 0.35:
		for k in 2:
			var out := Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)).normalized()
			_drop(p + Vector3.UP * 0.02, out * _rng.randf_range(0.3, 0.8) + Vector3.UP * _rng.randf_range(0.9, 1.7), size * 0.45, 0.6, 1)


func _rings_alive() -> int:
	var n := 0
	for i in MAX_RINGS:
		if _r_age[i] < _r_life[i]:
			n += 1
	return n


func _ring(at: Vector3, size: float, life: float, strength: float) -> void:
	var i := _r_next
	_r_next = (_r_next + 1) % MAX_RINGS
	_r_pos[i] = at + Vector3.UP * 0.03
	_r_size[i] = size
	_r_age[i] = 0.0
	_r_life[i] = life
	_r_str[i] = strength
	_r_seed[i] = _rng.randf()


func _update_rings(delta: float) -> void:
	var o := 0
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for i in MAX_RINGS:
		if _r_age[i] >= _r_life[i]:
			continue
		_r_age[i] += delta
		if _r_age[i] >= _r_life[i]:
			continue
		var p := _r_pos[i]
		var s := _r_size[i] * 2.0
		lo = lo.min(p - Vector3(s, 0.1, s))
		hi = hi.max(p + Vector3(s, 0.1, s))
		_ring_buf[o] = s; _ring_buf[o + 1] = 0.0; _ring_buf[o + 2] = 0.0; _ring_buf[o + 3] = p.x
		_ring_buf[o + 4] = 0.0; _ring_buf[o + 5] = 1.0; _ring_buf[o + 6] = 0.0; _ring_buf[o + 7] = p.y
		_ring_buf[o + 8] = 0.0; _ring_buf[o + 9] = 0.0; _ring_buf[o + 10] = s; _ring_buf[o + 11] = p.z
		_ring_buf[o + 12] = _r_age[i] / _r_life[i]; _ring_buf[o + 13] = _r_str[i]; _ring_buf[o + 14] = _r_seed[i]; _ring_buf[o + 15] = 0.0
		o += 16
	var alive := o / 16
	if alive == 0:
		if _ring_mm.visible_instance_count != 0:
			_ring_mm.visible_instance_count = 0
		return
	for j in range(o, _ring_buf.size()):
		_ring_buf[j] = 0.0
	_ring_mm.buffer = _ring_buf
	_ring_mm.visible_instance_count = alive
	_ring_mmi.custom_aabb = AABB(lo, hi - lo)


# ---------------------------------------------------------------------------
# Building

static func _load_shared() -> void:
	if _mesh == null:
		var scene := load(MESH_PATH) as PackedScene
		if scene:
			var inst := scene.instantiate()
			for mi in inst.find_children("*", "MeshInstance3D", true, false):
				_mesh = (mi as MeshInstance3D).mesh
				break
			inst.free()
		if _mesh == null:
			_mesh = CapsuleMesh.new()
	if _meta.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(META_PATH)) if FileAccess.file_exists(META_PATH) else null
		_meta = data if data is Dictionary else {"length": 6.3}
	if _mist_mat == null:
		_mist_mat = ShaderMaterial.new()
		_mist_mat.shader = preload("res://player/powers/dragon_mist.gdshader")
		_mist_mat.set_shader_parameter("noise", _noise)
		_mist_mat.render_priority = 1
		_drop_mat = ShaderMaterial.new()
		_drop_mat.shader = preload("res://player/powers/water_drop.gdshader")
		_drop_mat.render_priority = 2
		_ring_mat = ShaderMaterial.new()
		_ring_mat.shader = preload("res://player/powers/splash_ring.gdshader")
		_ring_mat.set_shader_parameter("noise", _noise)
		_orb_mat = StandardMaterial3D.new()
		_orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_orb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_orb_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_orb_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_orb_mat.albedo_texture = WeedProps.soft_dot()
		_orb_mat.albedo_color = Color(0.4, 0.82, 1.0, 0.85) * 1.25
		_orb_mat.disable_receive_shadows = true


func _build_dragon() -> void:
	_dragon_mat = ShaderMaterial.new()
	_dragon_mat.shader = _dragon_shader
	_dragon_mat.set_shader_parameter("body_len", _body_len)
	_dragon_mat.set_shader_parameter("body_scale", BODY_SCALE)
	_dragon_mat.set_shader_parameter("noise", _noise)
	var src := _mesh.surface_get_material(0) as BaseMaterial3D if _mesh.get_surface_count() > 0 else null
	if src:
		_dragon_mat.set_shader_parameter("albedo_tex", src.albedo_texture)
		_dragon_mat.set_shader_parameter("normal_tex", src.normal_texture)
	_dragon_mat.set_shader_parameter("end_dist", 1000.0)
	_dragon_mat.set_shader_parameter("head_dist", -1.0)
	_dragon_mat.set_shader_parameter("fallback_fwd", Vector3(sin(yaw), 0.0, cos(yaw)))
	_dragon = MeshInstance3D.new()
	_dragon.name = "WaterDragon"
	_dragon.mesh = _mesh
	_dragon.material_override = _dragon_mat
	_dragon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dragon.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_dragon.visible = false
	add_child(_dragon)


func _multimesh(mesh: Mesh, count: int, custom: bool, mat: Material, name_: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom
	(mesh as PrimitiveMesh).material = mat
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name_
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(mmi)
	return mmi


func _build_mist() -> void:
	# (Packed arrays are values: each one is resized by name.)
	_m_age.resize(MAX_MIST)
	_m_life.resize(MAX_MIST)
	_m_s0.resize(MAX_MIST)
	_m_s1.resize(MAX_MIST)
	_m_rot.resize(MAX_MIST)
	_m_spin.resize(MAX_MIST)
	_m_seed.resize(MAX_MIST)
	_m_alpha.resize(MAX_MIST)
	_m_drag.resize(MAX_MIST)
	_m_pos.resize(MAX_MIST)
	_m_vel.resize(MAX_MIST)
	_m_col.resize(MAX_MIST)
	_m_age.fill(1.0)
	_m_life.fill(0.0)
	_mist_buf.resize(MAX_MIST * 20)
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_mist_mmi = _multimesh(q, MAX_MIST, true, _mist_mat, "Mist")
	_mist_mm = _mist_mmi.multimesh


func _build_drops() -> void:
	_d_age.resize(MAX_DROPS)
	_d_life.resize(MAX_DROPS)
	_d_size.resize(MAX_DROPS)
	_d_floor.resize(MAX_DROPS)
	_d_pos.resize(MAX_DROPS)
	_d_vel.resize(MAX_DROPS)
	_d_kind.resize(MAX_DROPS)
	_d_age.fill(1.0)
	_d_life.fill(0.0)
	_drop_buf.resize(MAX_DROPS * 20)
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	_drop_mmi = _multimesh(q, MAX_DROPS, true, _drop_mat, "Drops")
	_drop_mm = _drop_mmi.multimesh


func _build_rings() -> void:
	_r_size.resize(MAX_RINGS)
	_r_age.resize(MAX_RINGS)
	_r_life.resize(MAX_RINGS)
	_r_str.resize(MAX_RINGS)
	_r_seed.resize(MAX_RINGS)
	_r_pos.resize(MAX_RINGS)
	_r_age.fill(1.0)
	_r_life.fill(0.0)
	_ring_buf.resize(MAX_RINGS * 16)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var mm_mi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	plane.material = _ring_mat
	mm.mesh = plane
	mm.instance_count = MAX_RINGS
	mm.visible_instance_count = 0
	mm_mi.name = "Rings"
	mm_mi.multimesh = mm
	mm_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mm_mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(mm_mi)
	_ring_mmi = mm_mi
	_ring_mm = mm


func _build_glow() -> void:
	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_color = Color(0.4, 0.85, 1.0)
	_light.light_energy = 0.0
	_light.omni_range = 1.6
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)
	_orb = MeshInstance3D.new()
	_orb.name = "MouthGlow"
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.13
	_orb.mesh = q
	_orb.material_override = _orb_mat
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_orb.visible = false
	add_child(_orb)


func _build_voices() -> void:
	_voice_mouth = _voice(18.0, 1.6)
	_voice_head = _voice(30.0, 2.4)
	_voice_splash = _voice(45.0, 3.0)


func _voice(max_d: float, unit: float) -> AudioStreamPlayer3D:
	var v := AudioStreamPlayer3D.new()
	v.bus = &"SFX"
	v.max_distance = max_d
	v.unit_size = unit
	v.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(v)
	return v


func _play(v: AudioStreamPlayer3D, clip: String, pitch := 1.0, db := 0.0) -> void:
	if not _clips.has(clip):
		var path := "res://assets/audio/dragon/%s.ogg" % clip
		_clips[clip] = load(path) if ResourceLoader.exists(path) else null
	var stream: AudioStream = _clips[clip]
	if stream == null or not v.is_inside_tree():
		return
	if v == _voice_mouth:
		v.global_position = _mouth.origin
	v.stream = stream
	v.volume_db = db
	v.pitch_scale = pitch * _rng.randf_range(0.96, 1.04)
	v.play()


## The gathering sound while the breath is drawn in (KelingWeed starts it).
func play_charge() -> void:
	_play(_voice_mouth, "charge", 1.0, -1.0)


# ---------------------------------------------------------------------------
# Helpers

static func _floor_at(x: float, z: float) -> float:
	return maxf(WaterLevel.ground_at(x, z), WaterLevel.surface_at(x, z))


func _jitter(r: float) -> Vector3:
	return Vector3(_rng.randf_range(-r, r), _rng.randf_range(-r, r), _rng.randf_range(-r, r))


## For the loading screen's warm-up sweep: one of everything this effect
## draws, posed in front of `parent` (the warm-up camera), so no pipeline
## compiles the first time a dragon is breathed.
static func warm_up(parent: Node3D) -> Node3D:
	var b := DragonBreath.new()
	b.setup(null, false, 0.0, 1)
	b.name = "DragonBreathWarmUp"
	parent.add_child(b)
	b._warm_pose(parent)
	return b


func _warm_pose(cam: Node3D) -> void:
	var at := cam.global_position - cam.global_basis.z * 4.0
	var fwd := cam.global_basis.x
	for k in SPINE:
		var p := at + fwd * (1.5 - k * _seg * 0.5)
		_spine[k] = Vector4(p.x, p.y, p.z, 1.0)
		_spine_up[k] = Vector4(0, 1, 0, 0)
	_dragon_mat.set_shader_parameter("spine", _spine)
	_dragon_mat.set_shader_parameter("spine_up", _spine_up)
	_dragon_mat.set_shader_parameter("head_dist", 40.0)
	_dragon.custom_aabb = AABB(at - Vector3.ONE * 8.0, Vector3.ONE * 16.0)
	_dragon.visible = true
	for i in 4:
		_mist_puff(at + _jitter(0.5), Vector3.ZERO, 0.4, 0.5, 30.0, 0.3, 1.0)
		_drop(at + _jitter(0.5) + Vector3.UP, Vector3.ZERO, 0.03, 30.0, 1)
		_ring(at + _jitter(0.5), 0.5, 30.0, 0.5)
	_place_rainbow(at)
	_rainbow.visible = true
	_rainbow_mat.set_shader_parameter("strength", 0.05)
	_orb.visible = true
	_orb.global_position = at
	phase = Phase.CHARGE
	set_process(false)
	# Draw the pools once (they normally update in _process).
	_update_mist(0.0, cam.global_position)
	_update_drops(0.0)
	_update_rings(0.0)
	_place_puddle(at)
	_puddle.modulate = Color(1, 1, 1, 0.5)
