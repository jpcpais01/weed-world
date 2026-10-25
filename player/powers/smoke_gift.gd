class_name SmokeGift
extends Node3D
## One cast of a smoke gift (SmokeGifts), the base every gift builds on.
##
## The node lives under the caster but draws in world space. Its clock runs
## in real seconds (`age`), so Slow Time can't stretch a gift out; visuals
## that should feel the slow-down get the game delta as well. `plan()` runs
## on the caster's game only and returns anything the other players need to
## play the same cast (a target, a path); `launch()` starts it everywhere.
## When the time is up (or `end()` is called) the gift fades for
## `fade_out()` seconds and frees itself.

signal finished

static var _clips := {}
static var _glow_mat: StandardMaterial3D

var caster: KelingController
var local := true
var gift: StringName = &""
var seed := 0
var boost := 1.0
var duration := 30.0
var age := 0.0
var ending := false
var ended_early := false
var out_t := 0.0
var rng := RandomNumberGenerator.new()

var _voices: Array[AudioStreamPlayer3D] = []
var _voice_i := 0


func setup(p_caster: KelingController, p_local: bool, p_gift: StringName, p_seed: int, p_boost: float) -> void:
	caster = p_caster
	local = p_local
	gift = p_gift
	seed = p_seed
	boost = p_boost
	rng.seed = p_seed
	duration = float(SmokeGifts.info(gift).get("time", 30.0)) * p_boost


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for i in 3:
		var v := AudioStreamPlayer3D.new()
		v.bus = &"SFX"
		v.max_distance = 40.0
		v.unit_size = 3.0
		v.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(v)
		_voices.append(v)
	_build()


## Caster only: work out what the others need to know. Override.
func plan() -> Dictionary:
	return {}


## Start the show (every device). Override `_start`.
func launch(data: Dictionary) -> void:
	_start(data)


## Cast again while it's still going: more time and a fresh burst.
func refresh(p_boost: float) -> void:
	boost = maxf(boost, p_boost)
	duration = maxf(duration, age + float(SmokeGifts.info(gift).get("time", 30.0)) * p_boost)
	_refreshed()


func end() -> void:
	if ending:
		return
	ending = true
	ended_early = age < duration - 0.05
	out_t = 0.0
	_on_end()


func remaining() -> float:
	return maxf(duration - age, 0.0)


func remaining_fraction() -> float:
	return clampf(remaining() / maxf(duration, 0.01), 0.0, 1.0)


## 0..1: rises over the first `rise` seconds, falls over the fade-out.
func envelope(rise := 1.2) -> float:
	var k := clampf(age / rise, 0.0, 1.0)
	if ending:
		k *= 1.0 - clampf(out_t / maxf(fade_out(), 0.01), 0.0, 1.0)
	return k


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var dt := minf(SmokeGifts.real(delta), 0.1)
	age += dt
	if ending:
		out_t += dt
	elif age >= duration:
		end()
	if caster == null or not is_instance_valid(caster):
		queue_free()
		return
	_tick(minf(delta, 0.1), dt)
	if ending and out_t >= fade_out():
		_done()
	PerfMeter.add(&"smoke gifts", Time.get_ticks_usec() - t0)


func _done() -> void:
	if is_queued_for_deletion():
		return
	_cleanup()
	finished.emit()
	queue_free()


# --- for the gifts to override ---------------------------------------------

func _build() -> void:
	pass


func _start(_data: Dictionary) -> void:
	pass


func _refreshed() -> void:
	pass


## Co-op: the caster sent a change of plan (KelingGifts.send_update).
func remote_update(_data: Dictionary) -> void:
	pass


func _on_end() -> void:
	pass


## Seconds the gift takes to fade once it ends.
func fade_out() -> float:
	return 2.0


## `dt` is game time (slowed by Slow Time), `real` is real time.
func _tick(_dt: float, _real: float) -> void:
	pass


## Undo anything done to the world or the caster (runs on free too).
func _cleanup() -> void:
	pass


func _exit_tree() -> void:
	_cleanup()


# --- helpers ---------------------------------------------------------------

## The caster's mouth in world space, looking out of it.
func mouth() -> Transform3D:
	var w = caster.get("weed") if caster else null
	if w and w.has_method("mouth_world"):
		return w.mouth_world()
	var p := caster.global_position + Vector3(0, 0.85, 0)
	return Transform3D(Basis(Vector3.UP, caster.facing), p)


## Where the caster stands, as drawn this frame (physics-interpolated), so
## effects that follow it don't jitter.
func feet() -> Vector3:
	return caster.get_global_transform_interpolated().origin


func forward() -> Vector3:
	return Vector3(sin(caster.facing), 0.0, cos(caster.facing))


static func floor_at(x: float, z: float) -> float:
	return maxf(WaterLevel.ground_at(x, z), WaterLevel.surface_at(x, z))


func play(clip: String, at: Vector3, db := 0.0, pitch := 1.0) -> AudioStreamPlayer3D:
	if not _clips.has(clip):
		var path := "res://assets/audio/gifts/%s.ogg" % clip
		_clips[clip] = load(path) if ResourceLoader.exists(path) else null
	var stream: AudioStream = _clips[clip]
	if stream == null or _voices.is_empty():
		return null
	var v := _voices[_voice_i]
	_voice_i = (_voice_i + 1) % _voices.size()
	if not v.is_inside_tree():
		return null
	v.global_position = at
	v.stream = stream
	v.volume_db = db
	v.pitch_scale = pitch * rng.randf_range(0.96, 1.04)
	v.play()
	return v


## An additive soft dot, for billboards that glow.
static func glow_material(color: Color) -> StandardMaterial3D:
	if _glow_mat == null:
		_glow_mat = StandardMaterial3D.new()
		_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_glow_mat.albedo_texture = WeedProps.soft_dot()
		_glow_mat.disable_receive_shadows = true
		_glow_mat.vertex_color_use_as_albedo = true
	var m := _glow_mat.duplicate() as StandardMaterial3D
	m.albedo_color = color
	return m


## A MultiMesh of glowing points/quads, world space, never shadowed.
func multimesh(mesh: Mesh, count: int, mat: Material, custom := true, colors := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mmi.extra_cull_margin = 16.0
	add_child(mmi)
	return mmi


## The local player's Keling (the one this screen follows), or null.
func local_player() -> KelingController:
	var tree := get_tree()
	return tree.get_first_node_in_group("local_player") as KelingController if tree else null


static func elastic_out(t: float) -> float:
	if t <= 0.0 or t >= 1.0:
		return clampf(t, 0.0, 1.0)
	return pow(2.0, -10.0 * t) * sin((t * 10.0 - 0.75) * (TAU / 3.0)) + 1.0


static func back_out(t: float, s := 1.7) -> float:
	t = clampf(t, 0.0, 1.0) - 1.0
	return t * t * ((s + 1.0) * t + s) + 1.0
