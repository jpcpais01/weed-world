class_name WaterFX
extends Node
## Rings and wakes on the water. Splashes, footsteps in the shallows and
## paddle strokes drop expanding ripple rings (with a burst of foam for the
## big ones), and every Keling swimming or wading draws a V-shaped wake that
## fans out behind it. All of it is drawn by the water shader itself, so the
## rings bend the reflections and the refraction like real ones and cost no
## extra geometry: this node only keeps a small table of live ripples and
## hands it to the water materials each frame.

## Ripple slots shared by everyone (matches `splashes[]` in water.gdshader).
const SLOTS := 10

static var _active: WaterFX

var materials: Array[ShaderMaterial] = []
var _ripples: Array[Dictionary] = []
var _dirty := false
var _wakes_live := false


func _init(water_materials: Array[ShaderMaterial] = []) -> void:
	name = "WaterFX"
	materials = water_materials


func _enter_tree() -> void:
	_active = self


func _exit_tree() -> void:
	if _active == self:
		_active = null


## Drops a ripple ring on the water at `pos` (its y is ignored). Strength 0..1:
## a toe dip is ~0.15, a running step 0.35, a cannonball 1. `life` seconds.
static func ripple(pos: Vector3, strength: float, life := 1.8) -> void:
	if _active == null or strength <= 0.01:
		return
	_active._add(Vector2(pos.x, pos.z), clampf(strength, 0.0, 1.5), life)


func _add(p: Vector2, strength: float, life: float) -> void:
	if _ripples.size() >= SLOTS:
		# Make room by retiring the ripple with the least left to give.
		var worst := 0
		var worst_score := INF
		for i in _ripples.size():
			var r := _ripples[i]
			var score: float = r.strength * (1.0 - r.age / r.life)
			if score < worst_score:
				worst_score = score
				worst = i
		if worst_score > strength:
			return
		_ripples.remove_at(worst)
	_ripples.append({"p": p, "age": 0.0, "life": life, "strength": strength})


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_timed(delta)
	PerfMeter.add(&"water fx", Time.get_ticks_usec() - t0)


func _process_timed(delta: float) -> void:
	if materials.is_empty():
		return
	if not _ripples.is_empty() or _dirty:
		var arr := PackedVector4Array()
		arr.resize(SLOTS)
		var i := 0
		while i < _ripples.size():
			var r := _ripples[i]
			r.age += delta
			if r.age >= r.life:
				_ripples.remove_at(i)
				continue
			# Strength fades over the ripple's life; the shader spreads the ring.
			var fade: float = 1.0 - r.age / r.life
			arr[i] = Vector4(r.p.x, r.p.y, r.age, r.strength * fade * fade)
			i += 1
		for m in materials:
			m.set_shader_parameter("splashes", arr)
		_dirty = not _ripples.is_empty()

	# Wakes: every Keling in the water, by player slot order.
	var pos := PackedVector4Array()
	var vel := PackedVector4Array()
	pos.resize(4)
	vel.resize(4)
	var n := 0
	for k in get_tree().get_nodes_in_group("player"):
		if n >= 4:
			break
		var w = k.get("water")
		if w == null:
			continue
		var strength: float = w.wake_strength()
		if strength <= 0.001:
			continue
		var p: Vector3 = (k as Node3D).global_position
		var v: Vector3 = k.velocity
		pos[n] = Vector4(p.x, w.surface, p.z, strength)
		vel[n] = Vector4(v.x, v.z, w.swim_amount(), 0.0)
		n += 1
	if n > 0 or _wakes_live:
		for m in materials:
			m.set_shader_parameter("wake_pos", pos)
			m.set_shader_parameter("wake_vel", vel)
	_wakes_live = n > 0

