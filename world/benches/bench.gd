@tool
class_name Bench
extends Node3D
## A scenic bench with a seat for each Keling. Players walk up, press grab
## (E, X on gamepad, or the hand button) at the floating prompt and their
## Keling hops up to sit and take in the view. The carved emblem wakes up
## while anyone is sitting: it is the bench's view tag made visible, and where
## the weed superpowers will come from.
##
## Bench space: +Z is the way a seated Keling faces, X runs along the seat.

signal occupancy_changed

## How close (metres from a seat's stand point) a Keling must be to sit.
const REACH := 1.25
## Where a Keling stands in front of its seat before hopping up (bench space z).
const STAND_Z := 0.6

const VIEW_NAMES := {
	&"river": "River view", &"pond": "Pond view", &"waterfall": "Waterfall view",
	&"mountains": "Mountain view", &"forest": "Forest view",
}

var site: Dictionary
## Hip-joint spots in bench space, one per seat.
var seats := PackedVector3Array()
var occupants: Array = []
var body: StaticBody3D
var glyph_material: ShaderMaterial
var glyph_point := Vector3.ZERO
## World point the seated view is framed on.
var view_point := Vector3.ZERO

var _prompt: Label3D
var _sparkles: GPUParticles3D
var _active := 0.0
var _prompt_alpha := 0.0
var _prompt_seat := -1


## Assembles the bench from a planned site (see BenchSites.plan).
func setup(p_site: Dictionary, builder: BenchBuilder, ground_y: float, look_y: float) -> void:
	site = p_site
	name = String(site.id).to_pascal_case() + "Bench"
	add_to_group("bench")
	var pos: Vector2 = site.pos
	transform = Transform3D(Basis(Vector3.UP, site.yaw), Vector3(pos.x, ground_y, pos.y))
	var look: Vector2 = site.look
	view_point = Vector3(look.x, look_y, look.y)

	var model := builder.build(site)
	add_child(model)
	for e in builder.take_extras():
		var mi := MeshInstance3D.new()
		mi.mesh = e.mesh
		var aabb: AABB = (e.mesh as Mesh).get_aabb()
		var size: Vector3 = e.get("size", aabb.size)
		var s := Vector3(size.x / maxf(aabb.size.x, 0.001), size.y / maxf(aabb.size.y, 0.001), size.z / maxf(aabb.size.z, 0.001))
		var xf: Transform3D = e.xform
		mi.transform = Transform3D(xf.basis * Basis.from_scale(s), xf.origin - xf.basis * (aabb.position * s + Vector3(aabb.size.x * s.x * 0.5, 0.0, aabb.size.z * s.z * 0.5)))
		model.add_child(mi)
	glyph_material = builder.glyph_material
	glyph_point = builder.glyph_point
	seats = BenchBuilder.seat_points(site.seats)
	occupants.resize(seats.size())

	body = StaticBody3D.new()
	body.name = "Collision"
	for c in builder.colliders:
		var cs := CollisionShape3D.new()
		cs.shape = c.shape
		cs.transform = c.xform
		# Walls, not steps: a knee-high box is a ramp to a round capsule, so
		# every box reaches from the ground to above a Keling's jump.
		var box := c.shape as BoxShape3D
		if box:
			var top := maxf(cs.transform.origin.y + box.size.y * 0.5, 0.95)
			box.size.y = top + 0.05
			cs.transform.origin.y = top * 0.5 - 0.05
		body.add_child(cs)
	add_child(body)

	if builder.lantern_point != Vector3.INF:
		var lamp := OmniLight3D.new()
		lamp.name = "Lantern"
		lamp.position = builder.lantern_point
		lamp.light_color = Color(1.0, 0.72, 0.4)
		lamp.light_energy = 0.6
		lamp.omni_range = 2.2
		lamp.shadow_enabled = false
		add_child(lamp)

	_build_prompt()
	_build_sparkles(BenchBuilder.ELEMENT_GLOW.get(site.element, Color.WHITE))


## Nearest free seat to a world position within reach, over every bench.
## Returns {bench, seat, distance} or an empty Dictionary.
static func find_free_seat(tree: SceneTree, pos: Vector3, reach := REACH) -> Dictionary:
	var best := {}
	var best_d := reach
	for n in tree.get_nodes_in_group("bench"):
		var b := n as Bench
		if b == null:
			continue
		var i := b.nearest_seat(pos, true)
		if i < 0:
			continue
		var d := _flat(b.stand_point(i) - pos).length()
		if d < best_d:
			best_d = d
			best = {"bench": b, "seat": i, "distance": d}
	return best


func nearest_seat(pos: Vector3, free_only: bool) -> int:
	var best := -1
	var best_d := INF
	for i in seats.size():
		if free_only and occupants[i] != null:
			continue
		var d := _flat(stand_point(i) - pos).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


## Ground point in front of a seat where a Keling turns round to hop up.
func stand_point(i: int) -> Vector3:
	return to_global(Vector3(seats[i].x, 0.0, STAND_Z))


## World position of the seated hip joint.
func hip_point(i: int) -> Vector3:
	return to_global(seats[i])


## Yaw a seated Keling faces (Keling convention: 0 looks down +Z).
func facing_yaw() -> float:
	var f := global_transform.basis.z
	return atan2(f.x, f.z)


func claim(i: int, who: Node) -> bool:
	if i < 0 or i >= seats.size() or (occupants[i] != null and occupants[i] != who):
		return false
	occupants[i] = who
	occupancy_changed.emit()
	return true


func release(who: Node) -> void:
	for i in occupants.size():
		if occupants[i] == who:
			occupants[i] = null
	occupancy_changed.emit()


func is_occupied() -> bool:
	for o in occupants:
		if o != null and is_instance_valid(o):
			return true
	return false


func view_name() -> String:
	return VIEW_NAMES.get(site.get("view", &""), "Scenic view")


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# ----------------------------------------------------------------------------
# Presentation

func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.name = "Prompt"
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.fixed_size = false
	_prompt.pixel_size = 0.0018
	_prompt.font_size = 44
	_prompt.outline_size = 14
	_prompt.outline_modulate = Color(0.05, 0.09, 0.05, 0.0)
	_prompt.modulate = Color(1, 1, 1, 0)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.line_spacing = -6.0
	_prompt.render_priority = 10
	_prompt.visible = false
	add_child(_prompt)


func _build_sparkles(color: Color) -> void:
	_sparkles = GPUParticles3D.new()
	_sparkles.name = "Sparkles"
	_sparkles.position = glyph_point
	_sparkles.amount = 14
	_sparkles.lifetime = 2.6
	_sparkles.emitting = false
	_sparkles.visibility_aabb = AABB(Vector3(-1, -0.5, -1), Vector3(2, 2, 2))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.direction = Vector3.UP
	pm.spread = 35.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.16
	pm.gravity = Vector3(0, 0.06, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 2.0
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	_sparkles.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color * 1.6
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	dot.gradient = g
	dot.width = 32
	dot.height = 32
	mat.albedo_texture = dot
	quad.material = mat
	_sparkles.draw_pass_1 = quad
	add_child(_sparkles)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or seats.is_empty():
		return
	var occupied := is_occupied()
	_active = move_toward(_active, 1.0 if occupied else 0.0, delta * (0.7 if occupied else 0.5))
	if glyph_material:
		glyph_material.set_shader_parameter("active", smoothstep(0.0, 1.0, _active))
	if _sparkles.emitting != occupied:
		_sparkles.emitting = occupied
	_update_prompt(delta)


func _update_prompt(delta: float) -> void:
	# Offer a seat to the nearest Keling that is out walking.
	var want := false
	var seat := -1
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Node3D
		if p == null or (p.has_method("is_sitting") and p.is_sitting()):
			continue
		var i := nearest_seat(p.global_position, true)
		if i >= 0 and _flat(stand_point(i) - p.global_position).length() < REACH:
			want = true
			seat = i
			break
	if seat >= 0 and seat != _prompt_seat:
		_prompt_seat = seat
		_prompt.position = Vector3(seats[seat].x, 1.25, seats[seat].z + 0.1)
	_prompt_alpha = move_toward(_prompt_alpha, 1.0 if want else 0.0, delta * 4.0)
	_prompt.visible = _prompt_alpha > 0.01
	if _prompt.visible:
		_prompt.text = "%s\n%s" % [site.title, _sit_hint()]
		var bob := sin(Time.get_ticks_msec() * 0.003) * 0.015
		_prompt.position.y = 1.25 + bob + (1.0 - _prompt_alpha) * -0.08
		_prompt.modulate = Color(1.0, 0.97, 0.88, _prompt_alpha)
		_prompt.outline_modulate = Color(0.05, 0.09, 0.05, 0.75 * _prompt_alpha)


static func _sit_hint() -> String:
	match GameInput.method:
		GameInput.Method.GAMEPAD:
			return "X  ·  sit and enjoy the view"
		GameInput.Method.TOUCH:
			return "Tap the hand  ·  sit and enjoy the view"
	return "E  ·  sit and enjoy the view"
