class_name GiftFireflies
extends SmokeGift
## Firefly Swarm: the Keling breathes out a cloud of fireflies. On the
## caster's screen the golden afternoon sinks into a velvet twilight, and the
## swarm lights the forest around it, blinking each to its own rhythm. Then
## part of the swarm streams away in a glowing river, leading to the rarest
## ripe plant nearby (a strain you've never found beats a rare one, a rare
## one beats a common one, nearer beats further). The river waits for you
## when you fall behind. At the plant the fireflies circle it like fairy
## lights until you pick it, then go looking for the next.
##
## The caster's game picks the plant (by net index) and tells the others when
## it changes, so friends see the same river. Only the caster's sky darkens.

const COUNT := 64
const GUIDE_SHARE := 0.42
const LEAD := 6.5           # the river's head stays this far ahead of you
const WAIT := 10.0          # ...and waits once you're this far behind
const LEAD_SPEED := 3.6
const ARRIVE := 3.4
const SEARCH := 140.0
const GLOW := Color(0.78, 1.0, 0.42)
const RARITY := {&"common": 0, &"uncommon": 1, &"rare": 2, &"legendary": 3}

static var _fly_mat: ShaderMaterial

var target_index := -1
var _target: Node3D
var _arrived := false
var _found_told := false
var _n := COUNT
var _flies: MultiMeshInstance3D
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _guide := PackedByteArray()
var _orbit := PackedFloat32Array()   # radius, height, speed, phase per fly (x4)
var _fade := PackedFloat32Array()
var _lead := Vector3.ZERO
var _lights: Array[OmniLight3D] = []
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _base := {}
var _loop: AudioStreamPlayer3D
var _t := 0.0
var _retarget_t := 0.0


func _build() -> void:
	if _fly_mat == null:
		_fly_mat = ShaderMaterial.new()
		_fly_mat.shader = preload("res://player/powers/firefly.gdshader")
	_n = int(COUNT * boost)
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.16
	_flies = multimesh(q, _n, _fly_mat)
	_flies.name = "Fireflies"
	_pos.resize(_n)
	_vel.resize(_n)
	_guide.resize(_n)
	_orbit.resize(_n * 4)
	_fade.resize(_n)
	for i in 3:
		var l := OmniLight3D.new()
		l.light_color = Color(0.82, 1.0, 0.5)
		l.light_energy = 0.0
		l.omni_range = 4.5 if i == 0 else 3.6
		l.omni_attenuation = 1.6
		l.shadow_enabled = false
		l.light_specular = 0.2
		add_child(l)
		_lights.append(l)
	_loop = AudioStreamPlayer3D.new()
	_loop.bus = &"SFX"
	_loop.max_distance = 25.0
	_loop.unit_size = 4.0
	var path := "res://assets/audio/gifts/fireflies_loop.ogg"
	if ResourceLoader.exists(path):
		_loop.stream = load(path)
		(_loop.stream as AudioStreamOggVorbis).loop = true
	add_child(_loop)


## Caster: the rarest ripe plant around.
func plan() -> Dictionary:
	return {"target": _pick_target()}


func _pick_target() -> int:
	var tree := get_tree()
	if tree == null:
		return -1
	var me := caster.global_position
	var weed = caster.get("weed")
	var best := -1
	var best_score := -INF
	for n in tree.get_nodes_in_group("weed_plant"):
		var plant := n as WeedPlant
		if plant == null or not plant.has_ripe_bud():
			continue
		var d := plant.global_position.distance_to(me)
		if d > SEARCH or d < 1.5:
			continue
		var info := WeedStrains.info(plant.strain)
		var score := float(RARITY.get(StringName(info.get("rarity", &"common")), 0)) * 40.0
		if weed and plant.strain not in weed.discovered:
			score += 140.0
		score -= d
		if score > best_score:
			best_score = score
			best = plant.net_index
	return best


func _start(data: Dictionary) -> void:
	_set_target(int(data.get("target", -1)))
	var m := mouth()
	for i in _n:
		_pos[i] = m.origin + Vector3(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03))
		var out := (m.basis.z + Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.1, 0.9), rng.randf_range(-0.7, 0.7))).normalized()
		_vel[i] = out * rng.randf_range(1.5, 4.0)
		_guide[i] = 1 if rng.randf() < GUIDE_SHARE else 0
		_orbit[i * 4] = rng.randf_range(0.9, 3.4)
		_orbit[i * 4 + 1] = rng.randf_range(0.3, 2.6)
		_orbit[i * 4 + 2] = rng.randf_range(0.25, 0.8) * (1.0 if rng.randf() < 0.5 else -1.0)
		_orbit[i * 4 + 3] = rng.randf() * TAU
		_fade[i] = 0.0
		_flies.multimesh.set_instance_custom_data(i, Color(rng.randf(), rng.randf_range(1.2, 2.6), rng.randf_range(0.12, 0.35), 0))
	_flies.multimesh.visible_instance_count = _n
	_lead = feet() + Vector3.UP
	play("fireflies_cast", m.origin, 0.0)
	_loop.play()
	if local:
		_grab_lighting()
		if target_index < 0:
			caster.weed.note.emit("No ripe buds nearby: the fireflies light your way")
		else:
			caster.weed.note.emit("The fireflies know where the %s grows. Follow them!" % WeedStrains.display_name((_target as WeedPlant).strain))


func _refreshed() -> void:
	play("fireflies_cast", mouth().origin, -4.0)
	var m := mouth()
	for i in range(0, _n, 3):
		_pos[i] = m.origin
		_vel[i] = (m.basis.z + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0, 0.8), rng.randf_range(-0.6, 0.6))) * 3.0
	if local and (_target == null or _arrived):
		_retarget()


func remote_update(data: Dictionary) -> void:
	_set_target(int(data.get("target", -1)))


func _set_target(index: int) -> void:
	target_index = index
	_target = null
	_arrived = false
	_found_told = false
	if index < 0 or not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("weed_plant"):
		var plant := n as WeedPlant
		if plant and plant.net_index == index:
			_target = plant
			return


func _retarget() -> void:
	var was := target_index
	if _target and is_instance_valid(_target):
		(_target as WeedPlant).set_glow(0.0)
	_set_target(_pick_target())
	if target_index != was:
		caster.weed.gifts.send_update(gift, {"target": target_index})
		if _target:
			caster.weed.note.emit("Off to the next one!")


func fade_out() -> float:
	return 3.2


func _on_end() -> void:
	if _target and is_instance_valid(_target):
		(_target as WeedPlant).set_glow(0.0)


func _tick(dt: float, real: float) -> void:
	_t += dt
	var k := envelope(1.6)
	var c := feet() + Vector3(0, 0.7, 0)
	_update_lead(dt, c)
	if local:
		_update_lighting(k)
		_retarget_t -= real
		if _arrived and _target and is_instance_valid(_target) and not (_target as WeedPlant).has_ripe_bud() and _retarget_t <= 0.0:
			_retarget_t = 1.0
			_retarget()
		elif _target == null and _retarget_t <= 0.0 and not ending:
			_retarget_t = 4.0
			_retarget()
	_simulate(dt, c, k)
	_place_lights(k, c)
	_loop.global_position = c
	_loop.volume_db = lerpf(-40.0, -10.0, k)


## The head of the river: runs ahead to the plant, but not too far ahead.
func _update_lead(dt: float, c: Vector3) -> void:
	if _target == null or not is_instance_valid(_target):
		_lead = _lead.lerp(c + Vector3(0, 0.6, 0), 1.0 - exp(-2.0 * dt))
		return
	var goal := _target.global_position + Vector3(0, 1.0, 0)
	var flat_me := Vector2(c.x, c.z)
	if not _arrived and flat_me.distance_to(Vector2(goal.x, goal.z)) < ARRIVE:
		_arrived = true
		_on_arrived()
	var to := goal - _lead
	var behind := Vector2(_lead.x, _lead.z).distance_to(flat_me)
	var speed := LEAD_SPEED
	if behind > WAIT:
		# Wait up: drift back towards the Keling a little.
		_lead = _lead.lerp(c + (goal - c).normalized() * LEAD, 1.0 - exp(-0.8 * dt))
		return
	if behind > LEAD and Vector2(to.x, to.z).length() > 1.0:
		speed = 0.0
	if to.length() > 0.05:
		_lead += to.normalized() * minf(speed * dt, to.length())
	var fl := floor_at(_lead.x, _lead.z)
	_lead.y = lerpf(_lead.y, maxf(fl + 1.3, goal.y - 0.2 if _arrived else fl + 1.3), 1.0 - exp(-3.0 * dt))


func _on_arrived() -> void:
	var at := _target.global_position + Vector3(0, 0.9, 0)
	play("fireflies_found", at, 0.0)
	if local:
		(_target as WeedPlant).set_glow(1.0)
		if not _found_told:
			_found_told = true
			caster.weed.note.emit("The fireflies found ripe %s!" % WeedStrains.display_name((_target as WeedPlant).strain))


func _simulate(dt: float, c: Vector3, k: float) -> void:
	var mm := _flies.multimesh
	var has_target := _target != null and is_instance_valid(_target)
	var plant_at := _target.global_position if has_target else Vector3.ZERO
	var path := _lead - c
	var side := Vector3(-path.z, 0, path.x).normalized() if Vector2(path.x, path.z).length() > 0.01 else Vector3.RIGHT
	for i in _n:
		var o := i * 4
		var r := _orbit[o]
		var h := _orbit[o + 1]
		var sp := _orbit[o + 2]
		var ph := _orbit[o + 3] + _t * sp
		var goal: Vector3
		if ending:
			goal = _pos[i] + Vector3(sin(ph) * 0.5, 2.0, cos(ph) * 0.5)
		elif _guide[i] == 1 and has_target and _arrived:
			# Fairy lights round the plant.
			var rr := 0.45 + r * 0.25
			goal = plant_at + Vector3(cos(ph * 1.6) * rr, 0.25 + h * 0.5, sin(ph * 1.6) * rr)
		elif _guide[i] == 1 and has_target:
			# A river from the Keling to the head, waving as it goes.
			var u := fmod(float(i) * 0.6180339 + _t * 0.08, 1.0) * 0.85 + 0.15
			var p := c.lerp(_lead, u)
			var wave := sin(u * 11.0 - _t * 2.6 + i) * 0.45 * u
			goal = p + side * wave + Vector3(0, sin(ph * 2.0) * 0.25 + 0.2, 0)
		else:
			goal = c + Vector3(cos(ph) * r, h - 0.4 + sin(ph * 1.7) * 0.3, sin(ph) * r)
		var v := _vel[i]
		var wander := Vector3(sin(_t * 1.3 + i * 2.1), sin(_t * 1.1 + i * 1.3) * 0.6, cos(_t * 1.7 + i * 0.7)) * 0.9
		v += ((goal - _pos[i]) * 2.2 + wander - v * 1.6) * dt
		_vel[i] = v
		_pos[i] += v * dt
		_fade[i] = minf(_fade[i] + dt * 0.8, 1.0)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * (1.0 + 0.3 * boost - 0.3)), _pos[i]))
		var a := _fade[i] * k
		mm.set_instance_color(i, Color(GLOW.r, GLOW.g, GLOW.b, a))


func _place_lights(k: float, c: Vector3) -> void:
	_lights[0].global_position = c + Vector3(0, 0.6, 0)
	_lights[0].light_energy = 1.3 * k
	var has_target := _target != null and is_instance_valid(_target)
	if has_target and _arrived:
		_lights[1].global_position = _target.global_position + Vector3(0, 0.8, 0)
		_lights[2].global_position = _target.global_position + Vector3(0.6 * sin(_t), 1.3, 0.6 * cos(_t))
	elif has_target:
		_lights[1].global_position = c.lerp(_lead, 0.55)
		_lights[2].global_position = _lead
	else:
		_lights[1].global_position = c + Vector3(sin(_t * 0.7) * 2.2, 1.0, cos(_t * 0.7) * 2.2)
		_lights[2].global_position = c + Vector3(sin(_t * 0.5 + 2.0) * 2.6, 1.4, cos(_t * 0.5 + 2.0) * 2.6)
	for i in range(1, 3):
		_lights[i].light_energy = 1.0 * k * (0.8 + 0.2 * sin(_t * 3.0 + i))


# ---------------------------------------------------------------------------
# Twilight (caster only): the sun sinks, the exposure drops, glow rises.

func _grab_lighting() -> void:
	var forest := _find_forest(get_tree().root, 5)
	var atmo = forest.get("atmosphere") if forest else null
	if atmo:
		_sun = atmo.get("sun")
		_fill = atmo.get("fill")
		_env = atmo.get("environment")
	if _env == null:
		var w := get_viewport().find_world_3d()
		_env = w.environment if w else null
	if _sun:
		_base.sun = _sun.light_energy
	if _fill:
		_base.fill = _fill.light_energy
	if _env:
		_base.exposure = _env.tonemap_exposure
		_base.glow = _env.glow_bloom


func _find_forest(n: Node, depth: int) -> Node:
	if n.get("atmosphere") != null:
		return n
	if depth <= 0:
		return null
	for ch in n.get_children():
		var f := _find_forest(ch, depth - 1)
		if f:
			return f
	return null


func _update_lighting(k: float) -> void:
	var d := k * k * (3.0 - 2.0 * k)
	if _sun and _base.has("sun"):
		_sun.light_energy = _base.sun * lerpf(1.0, 0.22, d)
	if _fill and _base.has("fill"):
		_fill.light_energy = _base.fill * lerpf(1.0, 0.6, d)
	if _env and _base.has("exposure"):
		_env.tonemap_exposure = _base.exposure * lerpf(1.0, 0.58, d)
		_env.glow_bloom = _base.glow + 0.08 * d


func _cleanup() -> void:
	if _sun and is_instance_valid(_sun) and _base.has("sun"):
		_sun.light_energy = _base.sun
	if _fill and is_instance_valid(_fill) and _base.has("fill"):
		_fill.light_energy = _base.fill
	if _env and _base.has("exposure"):
		_env.tonemap_exposure = _base.exposure
		_env.glow_bloom = _base.glow
	_base.clear()
	if local and _target and is_instance_valid(_target):
		(_target as WeedPlant).set_glow(0.0)
