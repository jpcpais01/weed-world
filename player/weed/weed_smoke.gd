class_name WeedSmoke
extends Node3D
## Joint smoke, simulated on the CPU and drawn in three draw calls at most:
##
## - two thin ribbons that rise off the ember: smooth and laminar for the
##   first hand's breadth, then turning over into lazy curls that widen,
##   thin out and drift away on the breeze, the way smoke off a joint does;
## - soft puffs (exhales, nose jets, the first puffs while lighting up) that
##   jet out, slow down, swell, rise a little and tear into wisps as they go.
##
## Everything lives in world space, so smoke stays where it was blown while
## the Keling walks on. Each strain names a smoke style in WeedStrains; for
## now they are all "normal". Rarer strains can add a style of their own.

const STYLES := {
	&"normal": {
		"color": Color(0.78, 0.79, 0.82),
		"ribbon_alpha": 0.4,
		"puff_alpha": 0.17,
		"turbulence": 1.0,
		"rise": 1.0,
	},
}

## The breeze (world space, m/s). The forest keeps it in step with the wind
## that sways the trees.
static var wind := Vector3(0.2, 0.0, 0.12)

const MAX_PUFFS := 64
const RIBBON_LIFE := 2.8
const RIBBON_STEP := 1.0 / 30.0
const RIBBON_MAX := 96

var style: Dictionary = STYLES[&"normal"]

var _noise: Texture2D = preload("res://assets/fx/smoke_noise.png")
var _t := 0.0
var _scale := 1.0

# Ribbons: [{pos, vel, birth (PackedFloat32Array), age, seed, mesh, alpha}]
var _ribbons: Array[Dictionary] = []
var _ribbon_acc := 0.0
var _ember_on := false
var _ember_pos := Vector3.ZERO
var _ember_rate := 0.0

# Puffs, as parallel arrays.
var _p_pos := PackedVector3Array()
var _p_vel := PackedVector3Array()
var _p_age := PackedFloat32Array()
var _p_life := PackedFloat32Array()
var _p_s0 := PackedFloat32Array()
var _p_s1 := PackedFloat32Array()
var _p_rot := PackedFloat32Array()
var _p_spin := PackedFloat32Array()
var _p_seed := PackedFloat32Array()
var _p_alpha := PackedFloat32Array()
var _p_drag := PackedFloat32Array()
var _alive := 0
var _streams := {}
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _buf := PackedFloat32Array()


func _init() -> void:
	_p_pos.resize(MAX_PUFFS)
	_p_vel.resize(MAX_PUFFS)
	for arr: PackedFloat32Array in [_p_age, _p_life, _p_s0, _p_s1, _p_rot, _p_spin, _p_seed, _p_alpha, _p_drag]:
		arr.resize(MAX_PUFFS)
	_p_age.fill(1.0)
	_buf.resize(MAX_PUFFS * 20)


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://player/weed/smoke_puff.gdshader")
	mat.set_shader_parameter("noise", _noise)
	mat.render_priority = 1
	q.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = q
	_mm.instance_count = MAX_PUFFS
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Puffs"
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	for k in 2:
		var rmat := ShaderMaterial.new()
		rmat.shader = preload("res://player/weed/smoke_ribbon.gdshader")
		rmat.set_shader_parameter("noise", _noise)
		rmat.set_shader_parameter("seed", 0.37 * k)
		var mesh := ImmediateMesh.new()
		var mi := MeshInstance3D.new()
		mi.name = "Ribbon%d" % k
		mi.mesh = mesh
		mi.material_override = rmat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_ribbons.append({
			"pos": PackedVector3Array(), "vel": PackedVector3Array(),
			"birth": PackedFloat32Array(), "age": PackedFloat32Array(), "str": PackedFloat32Array(),
			"seed": 1.7 + 4.1 * k, "mesh": mesh, "node": mi,
			# The second strand is fainter and peels away from the first.
			"alpha": 1.0 if k == 0 else 0.45, "kick": 0.0 if k == 0 else 1.0,
		})


func set_style(id: StringName) -> void:
	style = STYLES.get(id, STYLES[&"normal"])


## How big the smoker is (the Keling's visual scale), so smoke scales with it.
func set_scale_hint(s: float) -> void:
	_scale = s


## Feeds the ember every frame: where the tip is and how much it smokes
## (0 stops the stream, so the last of it breaks off and floats away).
func ember(world_pos: Vector3, rate: float) -> void:
	_ember_pos = world_pos
	_ember_rate = rate
	_ember_on = rate > 0.01


## One puff of smoke.
func puff(at: Vector3, vel: Vector3, size0: float, size1: float, life: float, alpha := 1.0, drag := 2.2) -> void:
	var i := _free_slot()
	_p_pos[i] = at
	_p_vel[i] = vel
	_p_age[i] = 0.0
	_p_life[i] = life * randf_range(0.85, 1.15)
	_p_s0[i] = size0 * _scale * randf_range(0.8, 1.2)
	_p_s1[i] = size1 * _scale * randf_range(0.8, 1.2)
	_p_rot[i] = randf() * TAU
	_p_spin[i] = randf_range(-0.5, 0.5)
	_p_seed[i] = randf()
	_p_alpha[i] = alpha
	_p_drag[i] = drag


## A steady stream of puffs while it's called each frame: `rate` per second,
## leaving `at` along `dir` at `speed` (m/s), with a little spread.
func stream(key: StringName, at: Vector3, dir: Vector3, rate: float, speed: float, size0: float, size1: float, life: float, alpha := 1.0, spread := 0.18, delta := 1.0 / 60.0, drag := 2.2) -> void:
	var acc: float = _streams.get(key, randf()) + rate * delta
	while acc >= 1.0:
		acc -= 1.0
		var d := (dir.normalized() + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
		puff(at + d * 0.01 * _scale, d * speed * _scale * randf_range(0.8, 1.15), size0, size1, life, alpha, drag)
	_streams[key] = acc


func has_smoke() -> bool:
	if _alive > 0 or _ember_on:
		return true
	for r in _ribbons:
		if not (r.pos as PackedVector3Array).is_empty():
			return true
	return false


func _free_slot() -> int:
	var best := 0
	var best_left := INF
	for i in MAX_PUFFS:
		var left := _p_life[i] - _p_age[i]
		if left <= 0.0:
			return i
		if left < best_left:
			best_left = left
			best = i
	return best


## A cheap swirling flow: overlapping sines, so neighbouring bits of smoke
## move alike and curl together instead of jittering apart.
static func flow(p: Vector3, t: float, s: float) -> Vector3:
	return Vector3(
		sin(p.y * 9.0 + t * 1.7 + s) + 0.5 * sin(p.z * 17.0 - t * 2.3 + s * 2.0),
		0.35 * sin(p.x * 11.0 + p.z * 7.0 + t * 1.1 + s),
		sin(p.y * 8.0 - t * 1.4 + s * 3.0) + 0.5 * sin(p.x * 15.0 + t * 2.9 - s))


func _process(delta: float) -> void:
	if not has_smoke():
		if _mm.visible_instance_count != 0:
			_mm.visible_instance_count = 0
		return
	var t0 := Time.get_ticks_usec()
	delta = minf(delta, 0.05)
	_t += delta
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3(0, 2, 5)
	_update_ribbons(delta, eye)
	_update_puffs(delta, eye)
	PerfMeter.add(&"weed smoke", Time.get_ticks_usec() - t0)


func _update_ribbons(delta: float, eye: Vector3) -> void:
	var turb: float = style.turbulence
	var rise: float = style.rise
	var col: Color = style.color
	var base_a: float = style.ribbon_alpha
	var wk := 1.0 - exp(-delta * 1.1)
	_ribbon_acc += delta
	var spawn := _ember_on and _ribbon_acc >= RIBBON_STEP
	if spawn:
		_ribbon_acc = 0.0
	for r in _ribbons:
		var pos: PackedVector3Array = r.pos
		var vel: PackedVector3Array = r.vel
		var birth: PackedFloat32Array = r.birth
		var age: PackedFloat32Array = r.age
		var strength: PackedFloat32Array = r.str
		var s: float = r.seed
		var kick: float = r.kick
		# Age and move what's already in the air.
		var n := pos.size()
		for i in n:
			var a := age[i] + delta
			age[i] = a
			var v := vel[i]
			v.y = minf(v.y + 0.3 * rise * delta, 0.2 * rise * _scale)
			var churn := smoothstep(0.2, 1.3, a) * 0.42 * turb + kick * 0.12 * smoothstep(0.1, 0.6, a)
			v += flow(pos[i] * (1.0 / _scale), _t, s) * churn * delta * 3.0
			var wf := wk * (0.35 + 0.65 * smoothstep(0.0, 1.0, a))
			v.x += (wind.x - v.x) * wf
			v.z += (wind.z - v.z) * wf
			vel[i] = v
			pos[i] += v * delta
		# Drop what has dissipated (oldest at the end).
		while not age.is_empty() and age[age.size() - 1] >= RIBBON_LIFE:
			var last := age.size() - 1
			pos.remove_at(last)
			vel.remove_at(last)
			birth.remove_at(last)
			age.remove_at(last)
			strength.remove_at(last)
		if spawn and pos.size() < RIBBON_MAX:
			pos.insert(0, _ember_pos)
			vel.insert(0, Vector3(0.0, 0.04 * _scale, 0.0))
			birth.insert(0, _t)
			age.insert(0, 0.0)
			strength.insert(0, minf(_ember_rate, 1.0))
		elif _ember_on and not pos.is_empty():
			# Keep the base of the stream glued to the ember between spawns.
			pos[0] = _ember_pos
		r.pos = pos
		r.vel = vel
		r.birth = birth
		r.age = age
		r.str = strength
		_draw_ribbon(r, eye, col, base_a * float(r.alpha))


func _draw_ribbon(r: Dictionary, eye: Vector3, col: Color, alpha: float) -> void:
	var mesh: ImmediateMesh = r.mesh
	mesh.clear_surfaces()
	var pos: PackedVector3Array = r.pos
	var n := pos.size()
	if n < 2:
		return
	var age: PackedFloat32Array = r.age
	var birth: PackedFloat32Array = r.birth
	var strength: PackedFloat32Array = r.str
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n:
		var p := pos[i]
		var tan := pos[mini(i + 1, n - 1)] - pos[maxi(i - 1, 0)]
		var side := tan.cross(eye - p)
		if side.length_squared() < 1e-12:
			side = Vector3.RIGHT
		side = side.normalized()
		var a01 := age[i] / RIBBON_LIFE
		var w := (0.003 + 0.05 * pow(a01, 1.25)) * _scale
		# Thin smoke is dense; as it spreads out it thins away. Smoke strung
		# out by a quick swing of the joint is thinner still.
		var k := clampf(0.01 * _scale / (w + 0.005 * _scale), 0.18, 1.0)
		var seg := (pos[mini(i + 1, n - 1)] - pos[maxi(i - 1, 0)]).length() * 0.5
		k *= clampf(0.007 * _scale / maxf(seg, 0.0001), 0.12, 1.0)
		# Right at the ember it is barely there; it shows a finger's width up.
		var a := alpha * strength[i] * k * smoothstep(0.0, 0.25, age[i]) * pow(1.0 - a01, 1.3)
		if i == 0 or i == n - 1:
			a = 0.0
		var c := Color(col, a)
		var v := birth[i] * 0.9
		mesh.surface_set_color(c)
		mesh.surface_set_uv(Vector2(0.0, v))
		mesh.surface_set_uv2(Vector2(a01, 0.0))
		mesh.surface_add_vertex(p - side * w)
		mesh.surface_set_color(c)
		mesh.surface_set_uv(Vector2(1.0, v))
		mesh.surface_set_uv2(Vector2(a01, 0.0))
		mesh.surface_add_vertex(p + side * w)
	mesh.surface_end()


func _update_puffs(delta: float, eye: Vector3) -> void:
	var turb: float = style.turbulence
	var rise: float = style.rise
	var col: Color = style.color
	var base_a: float = style.puff_alpha
	var order: Array[int] = []
	var dist := {}
	for i in MAX_PUFFS:
		var life := _p_life[i]
		var a := _p_age[i]
		if a >= life:
			continue
		a += delta
		_p_age[i] = a
		if a >= life:
			continue
		var v := _p_vel[i] * exp(-_p_drag[i] * delta)
		v.y += 0.1 * rise * _scale * delta
		var settle := minf(a, 1.0)
		v += flow(_p_pos[i] * (0.6 / _scale), _t, _p_seed[i] * 9.0) * 0.1 * turb * settle * _scale * delta
		var wf := (1.0 - exp(-delta * 0.9)) * settle
		v.x += (wind.x - v.x) * wf
		v.z += (wind.z - v.z) * wf
		_p_vel[i] = v
		_p_pos[i] += v * delta
		_p_rot[i] += _p_spin[i] * delta
		order.append(i)
		dist[i] = _p_pos[i].distance_squared_to(eye)
	_alive = order.size()
	# Far to near, so the soft edges blend over each other properly.
	order.sort_custom(func(x: int, y: int) -> bool: return dist[x] > dist[y])
	var o := 0
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for i in order:
		var a01 := _p_age[i] / _p_life[i]
		# Puffs widen as they travel, so a breath leaves the lips as a jet
		# and opens into a cloud.
		var size := lerpf(_p_s0[i], _p_s1[i], 1.0 - exp(-_p_age[i] * 1.2))
		# A fresh puff is a small, thin jet; it gathers body as it spreads.
		var alpha := base_a * _p_alpha[i] * smoothstep(0.0, 0.35, _p_age[i]) * pow(1.0 - a01, 1.5)
		var p := _p_pos[i]
		lo = lo.min(p - Vector3.ONE * size)
		hi = hi.max(p + Vector3.ONE * size)
		_buf[o] = size; _buf[o + 1] = 0.0; _buf[o + 2] = 0.0; _buf[o + 3] = p.x
		_buf[o + 4] = 0.0; _buf[o + 5] = size; _buf[o + 6] = 0.0; _buf[o + 7] = p.y
		_buf[o + 8] = 0.0; _buf[o + 9] = 0.0; _buf[o + 10] = size; _buf[o + 11] = p.z
		_buf[o + 12] = col.r; _buf[o + 13] = col.g; _buf[o + 14] = col.b; _buf[o + 15] = 1.0
		_buf[o + 16] = a01; _buf[o + 17] = _p_seed[i]; _buf[o + 18] = _p_rot[i]; _buf[o + 19] = alpha
		o += 20
	# Park the unused instances out of sight; only the live ones are drawn.
	for j in range(o, _buf.size()):
		_buf[j] = 0.0
	_mm.buffer = _buf
	_mm.visible_instance_count = _alive
	if _alive > 0:
		_mmi.custom_aabb = AABB(lo, hi - lo)
