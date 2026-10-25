class_name GiftOwl
extends SmokeGift
## Owl Flight: the Keling breathes a long plume of smoke up into the air, the
## smoke spirals into a vortex and a giant spirit owl gathers out of it,
## burning into being from the chest out to the wingtips. It hoots, swoops
## down, scoops the Keling onto its back as it hops up, and soars off over
## the forest with it. The player steers (the stick turns it, hold jump to
## climb, sprint to fold the wings and dive, grab to land); when the gift runs
## out it glides down, the Keling hops off, and the owl climbs away and melts
## back into smoke and drifting feathers.
##
## The owl is a ghost: translucent, glowing, its feather edges and plumes
## fraying into smoke, trailing ribbons of light from its wingtips and tail
## and shedding wisps and the odd feather as it flies (owl_spirit.gdshader,
## owl_wisp, owl_feather, owl_trail). Its wings are flapped in the shader;
## `flap_point` is the same maths on the CPU for the trails and the smoke.
##
## The ride uses the gift ride hook: the caster's controller calls `drive()`
## instead of its own modes. The owl's pose comes from the body's motion
## (where it is, how fast, how it turns), so a co-op friend's owl simply
## follows their puppet on every other screen; the summon and the swoop run
## on the same clock everywhere from the cast's position and heading.

enum Phase { SUMMON, SWOOP, HOP, RIDE, GONE }

const MESH_PATH := "res://assets/fx/owl/spirit_owl.glb"
const META_PATH := "res://assets/fx/owl/spirit_owl.json"
const FEATHER_TEX := "res://assets/fx/owl/ghost_feather.png"

# The summon, in seconds from the cast (stretched while the Keling gets up).
const T_GATHER := 0.15      # smoke starts pouring up from the lips
const T_FORM0 := 0.55       # the owl starts burning into being
const T_FORM1 := 2.0
const T_HOOT := 1.75
const T_SWOOP := 2.35       # it dives at the Keling...
const T_HOP := 2.8          # ...who hops up...
const T_CATCH := 3.2        # ...onto its back
const HOP_SPEED := 7.4      # up onto its back (the owl is big)
const HOVER_AHEAD := 4.2
const HOVER_UP := 3.8

# Flight.
const SPEED := 9.0
const BOOST := 15.0
const CRUISE := 17.0        # height over the ground it settles to (m)
const MIN_CLEAR := 9.0
const MAX_CLEAR := 32.0
const CEILING := 46.0       # the edge walls stop at 50 m
const EDGE := 34.0          # turns back towards the valley past this
const TURN_RATE := 1.35     # rad/s
const SEAT_DROP := 0.32     # body origin under the seat (Kelings' legs are short)
const LAND_CLEAR := 1.9     # seat height over the ground when the Keling hops off
const LAND_MAX := 6.0       # never takes longer than this to come down

const MAX_WISPS := 120
const MAX_FEATHERS := 40
const MAX_MOTES := 48
const TRAIL_POINTS := 26
const TRAIL_STEP := 0.45

const GHOST := Color(0.45, 0.72, 1.0)
const MOON := Color(0.7, 0.88, 1.0)

static var _mesh: Mesh
static var _albedo: Texture2D
static var _meta: Dictionary
static var _owl_shader: Shader = preload("res://player/powers/owl_spirit.gdshader")
static var _wisp_shader: Shader = preload("res://player/powers/owl_wisp.gdshader")
static var _feather_shader: Shader = preload("res://player/powers/owl_feather.gdshader")
static var _trail_shader: Shader = preload("res://player/powers/owl_trail.gdshader")
static var _noise: Texture2D = preload("res://assets/fx/smoke_noise.png")
static var _wisp_mat: ShaderMaterial
static var _feather_mat: ShaderMaterial
static var _trail_mat: ShaderMaterial
static var _quad: QuadMesh
static var _feather_quad: QuadMesh

var phase: int = Phase.SUMMON
var owl_xform := Transform3D.IDENTITY   ## the seat on the owl's back, world space

var _owl: MeshInstance3D
var _mat: ShaderMaterial
var _light: OmniLight3D
var _wind: AudioStreamPlayer3D
var _trails: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _wisps: MultiMeshInstance3D
var _feathers: MultiMeshInstance3D
var _motes: MultiMeshInstance3D

var _origin := Vector3.ZERO     # where the cast was breathed out
var _yaw0 := 0.0
var _hover := Vector3.ZERO
var _clock := 0.0               # summon time (pauses while the Keling stands up)
var _form := 0.0
var _hoot_done := false
var _hopped := false            # the rider is off (or never got on)
var _off_t := 0.0               # out_t when the rider got off
var _riding := false
var _ride_t := 0.0
var _sit_k := 0.0
var _cam_on := false

# The flight (caster) and the pose (everyone).
var _yaw := 0.0
var _speed := SPEED
var _vy := 0.0
var _hop_v := 0.0
var _pitch := 0.0
var _bank := 0.0
var _head_yaw := 0.0
var _prev_facing := 0.0
var _yaw_rate := 0.0
var _vel := Vector3.ZERO
var _prev_pos := Vector3.INF
var _solo_vel := Vector3.ZERO   # the owl's own flight once the rider is off

# The wing beat (mirrored in owl_spirit.gdshader).
var _phase := 0.0
var _amp := 0.5
var _wamp := 0.35
var _fold := 0.0
var _burst := 0.0
var _next_burst := 3.0
var _prev_sin := 0.0
var _shoulder := Vector3(0.9, -0.333, 0.312)
var _wrist_x := 2.7
var _droop := 0.9

# Particles (world space).
var _w_pos := PackedVector3Array()
var _w_vel := PackedVector3Array()
var _w_from := PackedVector3Array()
var _w_pt := PackedInt32Array()      # >= 0: gathering into this owl point
var _w_age := PackedFloat32Array()
var _w_life := PackedFloat32Array()
var _w_size := PackedFloat32Array()
var _w_seed := PackedFloat32Array()
var _w_alpha := PackedFloat32Array()
var _f_pos := PackedVector3Array()
var _f_vel := PackedVector3Array()
var _f_axis := PackedVector3Array()
var _f_rot := PackedFloat32Array()
var _f_age := PackedFloat32Array()
var _f_life := PackedFloat32Array()
var _f_size := PackedFloat32Array()
var _m_pos := PackedVector3Array()
var _m_vel := PackedVector3Array()
var _m_age := PackedFloat32Array()
var _m_life := PackedFloat32Array()
var _trail_pts: Array[PackedVector3Array] = []
var _trail_src: Array = []           # [owl-space point, wing, span, chord, tail, width]
var _points: Array = []              # owl-space surface points [p, wing, tail, span, chord]
var _edge_points: PackedInt32Array = PackedInt32Array()
var _shed_acc := 0.0
var _feather_acc := 0.0
var _mote_acc := 0.0
var _gather_acc := 0.0


static func _load_shared() -> void:
	if _mesh != null:
		return
	var scene := load(MESH_PATH) as PackedScene
	var inst := scene.instantiate()
	var mi := inst.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	_mesh = mi.mesh
	var m := _mesh.surface_get_material(0)
	if m is BaseMaterial3D:
		_albedo = (m as BaseMaterial3D).albedo_texture
	inst.free()
	_meta = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	_quad = QuadMesh.new()
	_feather_quad = QuadMesh.new()
	_feather_quad.size = Vector2(0.4, 1.0)
	_wisp_mat = ShaderMaterial.new()
	_wisp_mat.shader = _wisp_shader
	_wisp_mat.set_shader_parameter("noise", _noise)
	_feather_mat = ShaderMaterial.new()
	_feather_mat.shader = _feather_shader
	_feather_mat.set_shader_parameter("feather", load(FEATHER_TEX))
	_trail_mat = ShaderMaterial.new()
	_trail_mat.shader = _trail_shader
	_trail_mat.set_shader_parameter("noise", _noise)


func _build() -> void:
	_load_shared()
	process_priority = -10   # before the skeleton poses the rider this frame
	_shoulder = _v3(_meta.get("shoulder", [0.9, -0.333, 0.312]))
	_wrist_x = float(_meta.get("wrist_x", 2.7))
	for p in _meta.get("points", []):
		_points.append([Vector3(p[0], p[1], p[2]), p[3], p[4], p[5], p[6]])
		if p[4] > 0.5 or (p[3] > 0.5 and p[6] > 0.55):
			_edge_points.append(_points.size() - 1)

	_mat = ShaderMaterial.new()
	_mat.shader = _owl_shader
	_mat.set_shader_parameter("albedo_tex", _albedo)
	_mat.set_shader_parameter("noise", _noise)
	_mat.set_shader_parameter("shoulder", _shoulder)
	_mat.set_shader_parameter("wrist_x", _wrist_x)
	_mat.set_shader_parameter("plume_droop", _droop)
	_mat.set_shader_parameter("form_origin", _v3(_meta.get("chest", [0, -0.9, -0.7])))
	_owl = MeshInstance3D.new()
	_owl.mesh = _mesh
	_owl.material_override = _mat
	_owl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_owl.custom_aabb = AABB(Vector3(-6.5, -5.0, -7.0), Vector3(13.0, 10.0, 11.0))
	_owl.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_owl.visible = false
	add_child(_owl)

	_light = OmniLight3D.new()
	_light.light_color = Color(0.55, 0.85, 1.0)
	_light.omni_range = 11.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_light)

	_trail_mesh = ImmediateMesh.new()
	_trails = MeshInstance3D.new()
	_trails.mesh = _trail_mesh
	_trails.material_override = _trail_mat
	_trails.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trails.extra_cull_margin = 16384.0
	_trails.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_trails)
	var tips: Array = _meta.get("wing_tips", [])
	var tails: Array = _meta.get("tail_tips", [])
	for t in tips:
		_trail_src.append([_v3(t), 1.0, 1.0, 0.3, 0.0, 0.24])
	for t in tails:
		_trail_src.append([_v3(t), 0.0, 0.0, 0.0, 1.0, 0.2])
	for i in _trail_src.size():
		_trail_pts.append(PackedVector3Array())

	_wisps = multimesh(_quad, MAX_WISPS, _wisp_mat)
	_feathers = multimesh(_feather_quad, MAX_FEATHERS, _feather_mat)
	var dot := QuadMesh.new()
	dot.size = Vector2(0.22, 0.22)
	_motes = multimesh(dot, MAX_MOTES, glow_material(MOON), false, true)

	_wind = AudioStreamPlayer3D.new()
	_wind.bus = &"SFX"
	_wind.max_distance = 60.0
	_wind.unit_size = 6.0
	_wind.volume_db = -80.0
	add_child(_wind)


func plan() -> Dictionary:
	return {}


func _start(data: Dictionary) -> void:
	_origin = data.get("pos", caster.global_position)
	_yaw0 = float(data.get("yaw", caster.facing))
	var fwd := Vector3(sin(_yaw0), 0.0, cos(_yaw0))
	_hover = _origin + fwd * HOVER_AHEAD + Vector3.UP * HOVER_UP
	_hover.y = maxf(_hover.y, floor_at(_hover.x, _hover.z) + 3.2)
	_yaw = _yaw0 + PI
	_prev_facing = caster.facing
	_place_owl(_hover, _yaw, 0.0, 0.0)
	_owl.visible = true
	if local and caster.is_sitting():
		caster.stand_up()
	play("owl_gather", mouth().origin, -2.0)


func _refreshed() -> void:
	# A fresh breath while flying: a hoot and a gust of feathers.
	if _riding:
		play("owl_hoot", owl_xform.origin, -3.0, 1.06)
		for i in 10:
			_spawn_feather(_surface_world(rng.randi() % _points.size()), _vel * 0.3 + _rand_dir() * 2.0)


func fade_out() -> float:
	# Land first (however long that takes), then melt away.
	return _off_t + 2.6 if _hopped else 99.0


func _on_end() -> void:
	# Ended before it ever carried anyone: it just melts away.
	if phase < Phase.RIDE:
		_let_go()


# --- the ride hook (caster only: KelingController calls this) -------------

func drive(k: KelingController, delta: float) -> void:
	if phase == Phase.HOP:
		_hop_v -= k.gravity * delta
		k.velocity = Vector3(0.0, _hop_v, 0.0)
		return
	if phase != Phase.RIDE:
		k.velocity = Vector3.ZERO
		return
	# (GameInput by path: this script compiles before the autoloads exist.)
	var gi := k.get_node_or_null("/root/GameInput")
	if not (gi and gi.ui_locked) and Input.is_action_just_pressed("grab") and not ending:
		end()
	var seat := k.global_position + Vector3.UP * SEAT_DROP
	var ground := floor_at(seat.x, seat.z)
	var fwd := Vector3(sin(_yaw), 0.0, cos(_yaw))

	# Steering: towards the stick (camera-relative), at most TURN_RATE.
	var turn := 0.0
	var input := k.move_input()
	if input.length() > 0.12 and not ending:
		var want := atan2(input.x, input.z)
		turn = clampf(wrapf(want - _yaw, -PI, PI) * 1.8, -TURN_RATE, TURN_RATE) * clampf(input.length() * 1.4, 0.0, 1.0)
	# Past the edge of the valley it banks round towards the middle.
	var out := maxf(absf(seat.x), absf(seat.z))
	if out > EDGE:
		var home := atan2(-seat.x, -seat.z)
		var urge := clampf((out - EDGE) / 8.0, 0.0, 1.0)
		var dh := wrapf(home - _yaw, -PI, PI)
		if absf(dh) > 0.35:
			turn = lerpf(turn, signf(dh) * TURN_RATE, urge)
	_yaw = wrapf(_yaw + turn * delta, -PI, PI)

	# Speed and height.
	var dive := k.sprinting() and not ending
	var climb := k.jump_held() and not ending
	var look := maxf(floor_at(seat.x + fwd.x * _speed, seat.z + fwd.z * _speed),
			floor_at(seat.x + fwd.x * _speed * 2.0, seat.z + fwd.z * _speed * 2.0))
	look = maxf(look, ground)
	var target_speed := BOOST if dive else (SPEED * 0.8 if climb else SPEED)
	var target_vy := 0.0
	if ending:
		target_speed = lerpf(SPEED, 5.0, clampf(out_t / 2.5, 0.0, 1.0))
		target_vy = clampf((ground + LAND_CLEAR - seat.y) * 1.4, -9.0, 1.5)
		if seat.y - ground < LAND_CLEAR + 0.25 or out_t > LAND_MAX:
			_hop_off(k)
			return
	else:
		if climb:
			target_vy = 5.0
		elif dive:
			target_vy = -4.5
		else:
			target_vy = clampf((ground + CRUISE - seat.y) * 0.5, -2.2, 2.6)
		# Never into the ground or the trees, never off the top of the world.
		var floor_y := look + MIN_CLEAR
		if seat.y < floor_y:
			target_vy = maxf(target_vy, (floor_y - seat.y) * 1.6)
		var top := minf(ground + MAX_CLEAR, CEILING)
		if seat.y > top:
			target_vy = minf(target_vy, (top - seat.y) * 1.2)
		# Something in the way (the Elder tree, a cliff): pull up hard.
		var space := k.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(seat, seat + fwd * (_speed * 1.3 + 2.0), 1, [k.get_rid()])
		if not space.intersect_ray(q).is_empty():
			target_vy = maxf(target_vy, 7.0)
	_speed = move_toward(_speed, target_speed, (6.0 if target_speed > _speed else 4.0) * delta)
	_vy = move_toward(_vy, target_vy, 7.0 * delta)
	fwd = Vector3(sin(_yaw), 0.0, cos(_yaw))
	k.velocity = fwd * _speed + Vector3.UP * _vy
	k.facing = _yaw


func _hop_off(k: KelingController) -> void:
	k.gift_ride = null
	k.mode = KelingController.Mode.AIR
	var fwd := Vector3(sin(_yaw), 0.0, cos(_yaw))
	k.launch(4.6, fwd * 2.5)
	_let_go()


# --- every device ----------------------------------------------------------

func _tick(dt: float, real: float) -> void:
	_clock_step(real)
	match phase:
		Phase.SUMMON:
			_summon(real)
		Phase.SWOOP, Phase.HOP:
			_swoop(real)
		Phase.RIDE:
			_ride(real)
		Phase.GONE:
			_solo(real)
	_update_form(real)
	_update_wings(real)
	_update_rider(real)
	_emit(real)
	_update_wisps(dt)
	_update_feathers(dt)
	_update_motes(dt)
	_update_trails()
	_light.global_position = owl_xform * Vector3(0.0, -0.6, 0.2)
	_light.light_energy = 1.4 * _form
	if _wind.playing:
		_wind.global_position = owl_xform.origin
		var want := -6.0 + clampf((_vel.length() - 6.0) / 9.0, 0.0, 1.0) * 6.0 if _riding else -40.0
		_wind.volume_db = lerpf(_wind.volume_db, want, 1.0 - exp(-2.0 * real))
	elif _riding:
		_start_wind()
	_owl.visible = _form > 0.001
	# Something else took the body over (another ride): let go.
	if local and phase == Phase.RIDE and caster.gift_ride != self and not _hopped:
		_let_go()


func _clock_step(real: float) -> void:
	# The summon waits (the owl hovering) while the Keling gets off a bench.
	var busy := caster.mode == KelingController.Mode.SIT or caster.mode == KelingController.Mode.MORPH
	if phase == Phase.SUMMON and _clock >= T_SWOOP - 0.05 and busy and age < T_SWOOP + 4.0:
		if local and caster.mode == KelingController.Mode.SIT:
			caster.stand_up()
		return
	_clock += real


func _summon(real: float) -> void:
	var bob := Vector3.UP * sin(_clock * 2.1) * 0.25
	_yaw = lerp_angle(_yaw, _face_caster(), 1.0 - exp(-2.0 * real))
	_place_owl(_hover + bob, _yaw, -0.12, sin(_clock * 1.3) * 0.08)
	_head_yaw = lerpf(_head_yaw, sin(_clock * 0.9) * 0.3, 1.0 - exp(-3.0 * real))
	if not _hoot_done and _clock >= T_HOOT:
		_hoot_done = true
		play("owl_hoot", _hover, 0.0)
	if _clock >= T_SWOOP and not ending:
		phase = Phase.SWOOP


func _face_caster() -> float:
	var to := caster.global_position - _hover
	return atan2(to.x, to.z) if Vector2(to.x, to.z).length() > 0.5 else _yaw0 + PI


## Dives from the hover down under the Keling (who hops up onto its back).
func _swoop(real: float) -> void:
	var t := clampf((_clock - T_SWOOP) / (T_CATCH - T_SWOOP), 0.0, 1.0)
	if phase == Phase.SWOOP and _clock >= T_HOP:
		phase = Phase.HOP
		_hop_v = HOP_SPEED
		if local:
			caster.gift_ride = self
			caster._enter_air(true)
		play("owl_flap", _hover, -1.0, 0.9)
	var d := Vector3(sin(_face_caster()), 0.0, cos(_face_caster()))
	var catch := caster.global_position + Vector3.UP * SEAT_DROP
	if phase == Phase.SWOOP:
		# Aim where the Keling will be at the top of its hop.
		catch.y += HOP_SPEED * HOP_SPEED / (2.0 * caster.gravity) * 0.8
	var p0 := _hover
	var p1 := _hover + d * 2.0 - Vector3.UP * 1.5
	var p3 := catch
	var p2 := catch - d * 3.5
	var e := t * t * (3.0 - 2.0 * t)
	var p := _bezier(p0, p1, p2, p3, e)
	# Skim the meadow, never through it (its belly hangs 1.4 m under the seat).
	p.y = maxf(p.y, floor_at(p.x, p.z) + 1.6)
	var tan := _bezier(p0, p1, p2, p3, minf(e + 0.02, 1.0)) - _bezier(p0, p1, p2, p3, maxf(e - 0.02, 0.0))
	var yaw := atan2(tan.x, tan.z) if Vector2(tan.x, tan.z).length() > 0.001 else _yaw
	_yaw = lerp_angle(_yaw, yaw, 1.0 - exp(-10.0 * real))
	var pitch := clampf(atan2(tan.y, Vector2(tan.x, tan.z).length()), -0.6, 0.4) * (1.0 - t)
	_place_owl(p, _yaw, pitch, 0.0)
	if _clock >= T_CATCH and not ending:
		_begin_ride()


func _begin_ride() -> void:
	phase = Phase.RIDE
	_riding = true
	_ride_t = 0.0
	_speed = 7.0
	_vy = 3.5
	_prev_pos = Vector3.INF
	caster.animator.travel(&"SitIdle")
	play("owl_hoot", owl_xform.origin, 1.0, 1.04)
	for i in 14:
		_spawn_feather(_surface_world(rng.randi() % _points.size()), _rand_dir() * 2.5 + Vector3.UP)
	if local:
		caster.facing = _yaw
		caster.weed.note.emit("Steer to fly · hold jump to climb · sprint to dive · grab to land")
		var cam := _camera()
		if cam and cam.has_method("begin_ride"):
			cam.begin_ride(10.5)
			_cam_on = true


## Riding: the owl is wherever the body is, posed from how it moves.
func _ride(real: float) -> void:
	_ride_t += real
	var seat := caster.global_position + Vector3.UP * SEAT_DROP
	if _prev_pos != Vector3.INF and real > 0.0:
		_vel = _vel.lerp((seat - _prev_pos) / real, 1.0 - exp(-10.0 * real))
	_prev_pos = seat
	if not local and caster.velocity.length() > 0.1:
		_vel = _vel.lerp(caster.velocity, 0.5)
	var yaw := caster.facing
	var yr := wrapf(yaw - _prev_facing, -PI, PI) / maxf(real, 0.001)
	_prev_facing = yaw
	_yaw_rate = lerpf(_yaw_rate, yr, 1.0 - exp(-6.0 * real))
	_yaw = lerp_angle(_yaw, yaw, 1.0 - exp(-12.0 * real)) if not local else yaw
	var flat := Vector2(_vel.x, _vel.z).length()
	var pitch := clampf(atan2(_vel.y, maxf(flat, 3.0)), -0.55, 0.5)
	_pitch = lerpf(_pitch, pitch, 1.0 - exp(-4.0 * real))
	_bank = lerpf(_bank, clampf(-_yaw_rate * 0.55, -0.75, 0.75), 1.0 - exp(-4.0 * real))
	_head_yaw = lerpf(_head_yaw, clampf(_yaw_rate * 0.35, -0.5, 0.5), 1.0 - exp(-4.0 * real))
	# A puppet's ride ends when it comes down to hop off.
	if not local and ending and not _hopped:
		var ground := floor_at(seat.x, seat.z)
		if seat.y - ground < LAND_CLEAR + 0.35 or out_t > LAND_MAX:
			_let_go()
	_place_owl(seat, _yaw, _pitch, _bank)


## The rider is off (or never got on): the owl flies on alone and melts away.
func _let_go() -> void:
	if _hopped:
		return
	_hopped = true
	_off_t = out_t
	if local and caster.gift_ride == self:
		caster.gift_ride = null
		if caster.mode != KelingController.Mode.AIR and not caster.is_on_floor():
			caster._enter_air(false)
	var fwd := Vector3(sin(_yaw), 0.0, cos(_yaw))
	_solo_vel = fwd * maxf(_vel.length() * 0.8, 6.0) + Vector3.UP * 3.0
	_riding = false
	phase = Phase.GONE
	if not ending:
		end()
	_release_camera()
	play("owl_vanish", owl_xform.origin, 0.0)


func _solo(real: float) -> void:
	_solo_vel += Vector3.UP * 2.0 * real
	var p := owl_xform.origin + _solo_vel * real
	var flat := Vector2(_solo_vel.x, _solo_vel.z)
	_yaw = atan2(flat.x, flat.y) if flat.length() > 0.5 else _yaw
	_pitch = lerpf(_pitch, clampf(atan2(_solo_vel.y, flat.length()), -0.4, 0.5), 1.0 - exp(-3.0 * real))
	_bank = lerpf(_bank, 0.0, 1.0 - exp(-2.0 * real))
	_place_owl(p, _yaw, _pitch, _bank)


func _place_owl(seat: Vector3, yaw: float, pitch: float, bank: float) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch) * Basis(Vector3.BACK, bank)
	owl_xform = Transform3D(b, seat)
	_owl.global_transform = owl_xform


# --- look --------------------------------------------------------------------

func _update_form(real: float) -> void:
	var want: float
	if _hopped:
		want = 1.0 - clampf((out_t - _off_t - 0.35) / 1.9, 0.0, 1.0)
		_form = want
	else:
		want = clampf((_clock - T_FORM0) / (T_FORM1 - T_FORM0), 0.0, 1.0)
		_form = maxf(_form, want * want * (3.0 - 2.0 * want))
	_mat.set_shader_parameter("form", _form)
	_mat.set_shader_parameter("intensity", 0.6 + 0.4 * _form)


func _update_wings(real: float) -> void:
	var amp := 0.5
	var freq := 1.9
	var fold := 0.0
	match phase:
		Phase.SUMMON:
			amp = 0.55 if _clock > T_FORM0 else 0.15
			freq = 1.7
		Phase.SWOOP:
			amp = 0.15
			fold = 0.35
			freq = 1.5
		Phase.HOP:
			amp = 0.6
			freq = 2.4
		Phase.RIDE:
			var flat := Vector2(_vel.x, _vel.z).length()
			var up := clampf(_vel.y / 4.0, 0.0, 1.0)
			var slow := 1.0 - clampf((flat - 5.5) / 3.0, 0.0, 1.0)
			fold = clampf((flat - SPEED - 1.5) / 4.0, 0.0, 1.0) * (1.0 if _vel.y < 1.0 else 0.3)
			# Glides mostly, with a few strong beats every few seconds.
			_next_burst -= real
			if _next_burst <= 0.0:
				_next_burst = rng.randf_range(3.5, 6.5)
				_burst = 1.0
			_burst = maxf(_burst - real / 1.4, 0.0)
			var beat := maxf(maxf(up, slow), smoothstep(0.0, 0.3, _burst) * 0.75)
			amp = lerpf(0.07, 0.62, beat) * (1.0 - fold * 0.8)
			freq = lerpf(0.9, 2.3, beat)
			if ending:
				amp = maxf(amp, 0.45 * clampf(out_t / 1.5, 0.0, 1.0))
		Phase.GONE:
			amp = 0.62
			freq = 2.2
	_amp = lerpf(_amp, amp, 1.0 - exp(-3.0 * real))
	_fold = lerpf(_fold, fold, 1.0 - exp(-3.0 * real))
	_wamp = _amp * 0.75
	_phase = fmod(_phase + TAU * freq * real, TAU * 64.0)
	var s := sin(_phase)
	# A whoosh on every strong downstroke.
	if _prev_sin > 0.7 and s <= 0.7 and _amp > 0.3 and _form > 0.5:
		play("owl_flap", owl_xform * Vector3(0, 0, 0.5), -6.0 + _amp * 6.0, 1.0 + (1.0 - _amp) * 0.15)
	_prev_sin = s
	_mat.set_shader_parameter("flap_phase", _phase)
	_mat.set_shader_parameter("flap_amp", _amp)
	_mat.set_shader_parameter("wrist_amp", _wamp)
	_mat.set_shader_parameter("fold", _fold)
	_mat.set_shader_parameter("head_yaw", _head_yaw)
	_mat.set_shader_parameter("head_tilt", sin(age * 0.7) * 0.12)


## The same wing maths as owl_spirit.gdshader, for points the script needs.
func flap_point(p: Vector3, wing: float, span: float, chord: float, tail: float) -> Vector3:
	var side := -1.0 if p.x < 0.0 else 1.0
	var ax := absf(p.x)
	var y := p.y
	var z := p.z
	if wing > 0.001:
		var a1 := (sin(_phase) * _amp + 0.06) * (1.0 - _fold * 0.7)
		var a2 := sin(_phase - 0.9) * _wamp + _fold * 0.25
		var ww := wing * smoothstep(_wrist_x - 0.6, _wrist_x + 0.7, ax)
		var r := Vector2(ax - _wrist_x, y - _shoulder.y).rotated(a2 * ww)
		ax = r.x + _wrist_x
		y = r.y + _shoulder.y
		var ws := wing * smoothstep(_shoulder.x - 0.25, _shoulder.x + 0.7, absf(p.x))
		r = Vector2(ax - _shoulder.x, y - _shoulder.y).rotated(a1 * ws)
		ax = r.x + _shoulder.x
		y = r.y + _shoulder.y
		y += -cos(_phase) * _amp * 0.55 * chord * (0.3 + span) * wing
		var q := Vector2(ax - _shoulder.x, z - _shoulder.z).rotated(-_fold * 0.95 * ws)
		ax = q.x + _shoulder.x
		z = q.y + _shoulder.z
	var x := side * ax
	if tail > 0.001:
		var t := fmod(Time.get_ticks_msec() / 1000.0, 3600.0)
		y -= tail * _droop
		y += sin(t * 2.6 - tail * 3.2 + side * 0.8) * 0.32 * tail * tail
		x += sin(t * 1.9 - tail * 2.6 + side) * 0.2 * tail * tail
	return Vector3(x, y, z)


func _surface_world(i: int) -> Vector3:
	var pt: Array = _points[i]
	return owl_xform * flap_point(pt[0], pt[1], pt[3], pt[4], pt[2])


# --- the rider -----------------------------------------------------------------

func _update_rider(real: float) -> void:
	var sit = caster.sit
	if sit == null:
		return
	var on := phase == Phase.RIDE and not _hopped
	var catching := phase == Phase.HOP and _clock > T_CATCH - 0.15
	_sit_k = move_toward(_sit_k, 1.0 if (on or catching) else 0.0, real * (4.0 if on or catching else 5.0))
	if _sit_k <= 0.0 and not on:
		if sit.straddle > 0.0:
			sit.amount = 0.0
			sit.legs = 0.0
			sit.straddle = 0.0
			sit.reins = 0.0
			sit.cheer = 0.0
			if caster.visual:
				caster.visual.rotation.x = 0.0
				caster.visual.rotation.z = 0.0
		return
	sit.amount = _sit_k
	sit.legs = _sit_k
	sit.hop = 0.0
	sit.straddle = _sit_k
	sit.hip_world = owl_xform * Vector3(0.0, 0.06, 0.0)
	# Hands in the neck feathers; flung up for joy in a dive or a climb.
	var thrill := clampf(maxf(_fold, _vel.y / 5.0), 0.0, 1.0) if on else 0.0
	sit.cheer = lerpf(sit.cheer, thrill, 1.0 - exp(-3.0 * real))
	sit.reins = 1.0 - sit.cheer
	if caster.visual:
		caster.visual.rotation.x = -_pitch * _sit_k
		caster.visual.rotation.z = _bank * 0.8 * _sit_k
	if caster.animator.current_state() != &"SitIdle" and on:
		caster.animator.travel(&"SitIdle")


func _camera() -> Node:
	return caster.get("camera_rig") if caster else null


func _release_camera() -> void:
	if _cam_on:
		_cam_on = false
		var cam := _camera()
		if cam and cam.has_method("end_ride"):
			cam.end_ride()


func _start_wind() -> void:
	if not _clips.has("owl_wind"):
		var path := "res://assets/audio/gifts/owl_wind.ogg"
		_clips["owl_wind"] = load(path) if ResourceLoader.exists(path) else null
	if _clips["owl_wind"] == null:
		return
	var stream: AudioStream = _clips["owl_wind"]
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_wind.stream = stream
	_wind.volume_db = -40.0
	_wind.play()


# --- smoke, feathers, motes, trails ------------------------------------------------

func _emit(real: float) -> void:
	# The breath: a plume pours up from the lips and spirals into the owl.
	if phase == Phase.SUMMON and _clock > T_GATHER and _clock < T_FORM1 - 0.2:
		_gather_acc += real * 34.0
		while _gather_acc >= 1.0:
			_gather_acc -= 1.0
			_spawn_gather()
	if _form > 0.05 and _form < 0.98 and not _hopped:
		_feather_acc += real * 10.0
	if phase == Phase.RIDE or phase == Phase.SWOOP or (phase == Phase.SUMMON and _form > 0.6):
		# Smoke pours off the frayed edges and streams behind.
		var speed := _vel.length() if phase == Phase.RIDE else 4.0
		_shed_acc += real * (10.0 + speed * 1.6)
		_feather_acc += real * (0.8 + _amp * 1.6)
		_mote_acc += real * 16.0
	while _shed_acc >= 1.0:
		_shed_acc -= 1.0
		if _edge_points.size() > 0:
			var i := _edge_points[rng.randi() % _edge_points.size()]
			var p := _surface_world(i)
			_spawn_wisp(p, _vel * 0.12 + _rand_dir() * 0.4 + Vector3.UP * 0.3, rng.randf_range(0.9, 1.8), rng.randf_range(1.1, 1.8), 0.55)
	while _feather_acc >= 1.0:
		_feather_acc -= 1.0
		var i := _edge_points[rng.randi() % _edge_points.size()] if _edge_points.size() > 0 else 0
		_spawn_feather(_surface_world(i), _vel * 0.25 + _rand_dir() * 0.8)
	while _mote_acc >= 1.0:
		_mote_acc -= 1.0
		var p := _surface_world(rng.randi() % _points.size())
		_spawn_mote(p, _vel * 0.3 + _rand_dir() * 0.6)
	# Melting away: one last burst of smoke and feathers.
	if _hopped and out_t - _off_t > 0.3 and out_t - _off_t < 2.0:
		var n := int(real * 70.0 + rng.randf())
		for k in n:
			var p := _surface_world(rng.randi() % _points.size())
			_spawn_wisp(p, _solo_vel * 0.3 + _rand_dir() * 1.4, rng.randf_range(1.2, 2.2), rng.randf_range(1.4, 2.4), 0.6)
		if rng.randf() < real * 18.0:
			_spawn_feather(_surface_world(rng.randi() % _points.size()), _rand_dir() * 2.0 + Vector3.UP * 0.5)


func _spawn_gather() -> void:
	if _points.is_empty():
		return
	var m := mouth()
	var start := m.origin + m.basis.z * 0.12
	var i := rng.randi() % _points.size()
	_add_wisp(start, Vector3.ZERO, rng.randf_range(1.0, 1.5), rng.randf_range(0.5, 0.9), 0.7, i, start)


func _spawn_wisp(p: Vector3, v: Vector3, life: float, size: float, alpha: float) -> void:
	_add_wisp(p, v, life, size, alpha, -1, p)


func _add_wisp(p: Vector3, v: Vector3, life: float, size: float, alpha: float, pt: int, from: Vector3) -> void:
	if _w_pos.size() >= MAX_WISPS:
		var oldest := 0
		for k in _w_age.size():
			if _w_age[k] / _w_life[k] > _w_age[oldest] / _w_life[oldest]:
				oldest = k
		_remove_wisp(oldest)
	_w_pos.append(p)
	_w_vel.append(v)
	_w_from.append(from)
	_w_pt.append(pt)
	_w_age.append(0.0)
	_w_life.append(life)
	_w_size.append(size)
	_w_seed.append(rng.randf())
	_w_alpha.append(alpha)


func _remove_wisp(k: int) -> void:
	_w_pos.remove_at(k)
	_w_vel.remove_at(k)
	_w_from.remove_at(k)
	_w_pt.remove_at(k)
	_w_age.remove_at(k)
	_w_life.remove_at(k)
	_w_size.remove_at(k)
	_w_seed.remove_at(k)
	_w_alpha.remove_at(k)


func _update_wisps(dt: float) -> void:
	var k := 0
	while k < _w_pos.size():
		_w_age[k] += dt
		if _w_age[k] >= _w_life[k]:
			_remove_wisp(k)
			continue
		var t := _w_age[k] / _w_life[k]
		if _w_pt[k] >= 0:
			# Spiral up from the lips and into its place in the owl.
			var to := _surface_world(_w_pt[k])
			var from := _w_from[k]
			var mid := from.lerp(_hover, 0.55) + Vector3.UP * 1.2
			var e := t * t * (3.0 - 2.0 * t)
			var p := _bezier(from, mid, mid.lerp(to, 0.5), to, e)
			var swirl := (1.0 - e) * e * 3.0 * 1.4
			var ang := _w_seed[k] * TAU + age * 4.0
			p += Vector3(cos(ang), 0.0, sin(ang)) * swirl
			_w_pos[k] = p
		else:
			var v := _w_vel[k]
			v = v * exp(-1.6 * dt) + Vector3.UP * 0.4 * dt
			_w_vel[k] = v
			_w_pos[k] += v * dt
		k += 1
	var mm := _wisps.multimesh
	mm.visible_instance_count = _w_pos.size()
	for i in _w_pos.size():
		var t := _w_age[i] / _w_life[i]
		var grow := 0.45 + 0.75 * t if _w_pt[i] < 0 else lerpf(1.0, 0.5, t)
		var s := _w_size[i] * grow
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), _w_pos[i]))
		var fade := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.55, 1.0, t))
		mm.set_instance_color(i, GHOST.lerp(MOON, _w_seed[i] * 0.6))
		mm.set_instance_custom_data(i, Color(t, _w_seed[i], _w_seed[i] * TAU + t * 1.5, _w_alpha[i] * fade))


func _spawn_feather(p: Vector3, v: Vector3) -> void:
	if _f_pos.size() >= MAX_FEATHERS:
		_f_pos.remove_at(0)
		_f_vel.remove_at(0)
		_f_axis.remove_at(0)
		_f_rot.remove_at(0)
		_f_age.remove_at(0)
		_f_life.remove_at(0)
		_f_size.remove_at(0)
	_f_pos.append(p)
	_f_vel.append(v)
	_f_axis.append(_rand_dir())
	_f_rot.append(rng.randf() * TAU)
	_f_age.append(0.0)
	_f_life.append(rng.randf_range(2.2, 3.6))
	_f_size.append(rng.randf_range(0.5, 0.95))


func _update_feathers(dt: float) -> void:
	var k := 0
	var t_now := age
	while k < _f_pos.size():
		_f_age[k] += dt
		if _f_age[k] >= _f_life[k]:
			_f_pos.remove_at(k)
			_f_vel.remove_at(k)
			_f_axis.remove_at(k)
			_f_rot.remove_at(k)
			_f_age.remove_at(k)
			_f_life.remove_at(k)
			_f_size.remove_at(k)
			continue
		# Drift down, rocking side to side like a real feather.
		var v := _f_vel[k] * exp(-1.8 * dt)
		v.y = lerpf(v.y, -0.7, 1.0 - exp(-1.2 * dt))
		var sway := sin(t_now * 2.4 + k * 1.7) * 0.9
		_f_vel[k] = v
		_f_pos[k] += (v + Vector3(sway, 0.0, cos(t_now * 1.9 + k) * 0.6)) * dt
		_f_rot[k] += dt * 2.2
		k += 1
	var mm := _feathers.multimesh
	mm.visible_instance_count = _f_pos.size()
	for i in _f_pos.size():
		var t := _f_age[i] / _f_life[i]
		var b := Basis(_f_axis[i], _f_rot[i]) * Basis(Vector3.FORWARD, sin(t_now * 3.0 + i) * 0.6)
		mm.set_instance_transform(i, Transform3D(b.scaled(Vector3.ONE * _f_size[i]), _f_pos[i]))
		mm.set_instance_color(i, MOON.lerp(GHOST, fmod(i * 0.37, 1.0)))
		mm.set_instance_custom_data(i, Color(t, fmod(i * 0.618, 1.0), 0.0, smoothstep(0.0, 0.1, t) * 0.85))


func _spawn_mote(p: Vector3, v: Vector3) -> void:
	if _m_pos.size() >= MAX_MOTES:
		_m_pos.remove_at(0)
		_m_vel.remove_at(0)
		_m_age.remove_at(0)
		_m_life.remove_at(0)
	_m_pos.append(p)
	_m_vel.append(v)
	_m_age.append(0.0)
	_m_life.append(rng.randf_range(0.8, 1.6))


func _update_motes(dt: float) -> void:
	var k := 0
	while k < _m_pos.size():
		_m_age[k] += dt
		if _m_age[k] >= _m_life[k]:
			_m_pos.remove_at(k)
			_m_vel.remove_at(k)
			_m_age.remove_at(k)
			_m_life.remove_at(k)
			continue
		_m_vel[k] = _m_vel[k] * exp(-1.0 * dt) + Vector3.UP * 0.3 * dt
		_m_pos[k] += _m_vel[k] * dt
		k += 1
	var mm := _motes.multimesh
	mm.visible_instance_count = _m_pos.size()
	for i in _m_pos.size():
		var t := _m_age[i] / _m_life[i]
		var tw := 0.6 + 0.4 * sin(age * 13.0 + i * 2.3)
		var s := (1.0 - t) * tw
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * maxf(s, 0.01)), _m_pos[i]))
		mm.set_instance_color(i, Color(MOON.r, MOON.g, MOON.b, (1.0 - t) * tw))


## Ribbons of light from the wingtips and the plume tips.
func _update_trails() -> void:
	_trail_mesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null or _form < 0.02:
		return
	var strength := _form * (1.0 if not _hopped else clampf(1.0 - (out_t - _off_t) / 2.0, 0.0, 1.0))
	if phase == Phase.SUMMON:
		strength *= 0.5
	var eye := cam.global_position
	var began := false
	for i in _trail_src.size():
		var src: Array = _trail_src[i]
		# Mostly the gliding wing's tip, a little of the beat: a ribbon that
		# swings gently instead of zigzagging with every stroke.
		var rest: Vector3 = src[0]
		if src[4] > 0.5:
			rest.y -= _droop
		var tip := owl_xform * rest.lerp(flap_point(src[0], src[1], src[2], src[3], src[4]), 0.35)
		var pts := _trail_pts[i]
		if pts.is_empty() or pts[0].distance_to(tip) > 30.0:
			pts = PackedVector3Array([tip, tip])
		elif pts.size() > 1 and pts[1].distance_to(tip) < TRAIL_STEP:
			pts[0] = tip
		else:
			pts.insert(0, tip)
			if pts.size() > TRAIL_POINTS:
				pts.resize(TRAIL_POINTS)
		_trail_pts[i] = pts
		if pts.size() < 2:
			continue
		if not began:
			_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			began = true
		var w: float = src[5]
		var n := pts.size()
		var col := Color(GHOST.r, GHOST.g, GHOST.b, strength * (0.6 if src[4] < 0.5 else 0.5))
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for j in n:
			var p := pts[j]
			var dir := (pts[mini(j + 1, n - 1)] - pts[maxi(j - 1, 0)])
			var side := dir.cross(eye - p).normalized() * w * (1.0 - 0.6 * float(j) / float(n - 1))
			var l := p - side
			var r := p + side
			if j > 0:
				var u0 := float(j - 1) / float(n - 1)
				var u1 := float(j) / float(n - 1)
				_tri(prev_l, prev_r, r, Vector2(u0, 0), Vector2(u0, 1), Vector2(u1, 1), col)
				_tri(prev_l, r, l, Vector2(u0, 0), Vector2(u1, 1), Vector2(u1, 0), col)
			prev_l = l
			prev_r = r
	if began:
		_trail_mesh.surface_end()


func _tri(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, col: Color) -> void:
	for v in [[a, ua], [b, ub], [c, uc]]:
		_trail_mesh.surface_set_color(col)
		_trail_mesh.surface_set_uv(v[1])
		_trail_mesh.surface_add_vertex(v[0])


func _cleanup() -> void:
	if caster and is_instance_valid(caster):
		if caster.gift_ride == self:
			caster.gift_ride = null
		var sit = caster.sit
		if sit and sit.straddle > 0.0:
			sit.amount = 0.0
			sit.legs = 0.0
			sit.straddle = 0.0
			sit.reins = 0.0
			sit.cheer = 0.0
		if caster.visual:
			caster.visual.rotation.x = 0.0
			caster.visual.rotation.z = 0.0
	_release_camera()


# --- helpers -----------------------------------------------------------------

static func _v3(a) -> Vector3:
	return Vector3(a[0], a[1], a[2]) if a is Array and a.size() >= 3 else Vector3.ZERO


static func _bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t


func _rand_dir() -> Vector3:
	return Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()


## A whole owl drawn once behind the loading curtain, so its shaders are
## compiled before anyone summons one.
static func warm_up(parent: Node3D) -> Node3D:
	_load_shared()
	var root := Node3D.new()
	root.name = "OwlWarmUp"
	parent.add_child(root)
	var at := parent.global_position - parent.global_basis.z * 6.0
	var owl := MeshInstance3D.new()
	owl.mesh = _mesh
	var m := ShaderMaterial.new()
	m.shader = _owl_shader
	m.set_shader_parameter("albedo_tex", _albedo)
	m.set_shader_parameter("noise", _noise)
	m.set_shader_parameter("form", 0.7)
	owl.material_override = m
	owl.scale = Vector3.ONE * 0.2
	root.add_child(owl)
	owl.global_position = at
	for mat in [_wisp_mat, _feather_mat]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _quad if mat == _wisp_mat else _feather_quad
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D(Basis(), at))
		mm.set_instance_custom_data(0, Color(0.3, 0.5, 0.0, 0.5))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		root.add_child(mmi)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(0, 0, 0), Vector3(0.3, 0, 0), Vector3(0, 0.3, 0)]:
		im.surface_set_color(Color(1, 1, 1, 0.5))
		im.surface_set_uv(Vector2(0.5, 0.5))
		im.surface_add_vertex(at + v)
	im.surface_end()
	var tr := MeshInstance3D.new()
	tr.mesh = im
	tr.material_override = _trail_mat
	root.add_child(tr)
	return root
