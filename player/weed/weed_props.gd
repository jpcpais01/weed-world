class_name WeedProps
extends RefCounted
## Little hand-held props for rolling and smoking, all built in code: the
## rolling paper (a sheet that curls itself into a tube in its shader), the
## finished joint with its glowing ember, the soft smoke puffs, the crumbs
## that fall while the bud is broken up, and a fairy-spark lighter flame.

const PAPER_W := 0.085   ## across the sheet (becomes the joint's girth)
const PAPER_L := 0.115   ## along the joint
const JOINT_L := 0.12
const JOINT_R_TIP := 0.0115   ## the lit end
const JOINT_R_MOUTH := 0.0065

static var _soft_dot: GradientTexture2D


## A sheet of rolling paper. Its shader curls it round the X axis as `roll`
## goes 0 -> 1, and fills it with ground bud as `fill` rises.
static func paper(tint: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 12
	var nv := 3
	for j in nv + 1:
		for i in nu + 1:
			var u := float(i) / nu
			var v := float(j) / nv
			st.set_uv(Vector2(u, v))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3((v - 0.5) * PAPER_L, 0.0, (u - 0.5) * PAPER_W))
	for j in nv:
		for i in nu:
			var a := j * (nu + 1) + i
			var b := a + 1
			var c := a + nu + 1
			var d := c + 1
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://player/weed/rolling_paper.gdshader")
	mat.set_shader_parameter("width", PAPER_W)
	mat.set_shader_parameter("fill_color", tint)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 0.1
	return mi


## The rolled joint along +X: the twisted mouth end at the origin, the lit tip
## at +JOINT_L. Returns {root, ember: MeshInstance3D, ember_mat, body_mat}.
static func joint(tint: Color) -> Dictionary:
	var root := Node3D.new()
	root.name = "Joint"
	var body := CylinderMesh.new()
	body.top_radius = JOINT_R_TIP
	body.bottom_radius = JOINT_R_MOUTH
	body.height = JOINT_L
	body.radial_segments = 10
	body.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.97, 0.94, 0.86)
	mat.roughness = 0.8
	mat.backlight_enabled = true
	mat.backlight = tint * 0.5
	body.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = body
	mi.rotation.z = -PI * 0.5
	mi.position.x = JOINT_L * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# The twist at the tip, and the crutch at the mouth end.
	var twist := CylinderMesh.new()
	twist.top_radius = 0.0
	twist.bottom_radius = JOINT_R_TIP * 0.95
	twist.height = 0.016
	twist.radial_segments = 8
	twist.rings = 1
	twist.material = mat
	var tw := MeshInstance3D.new()
	tw.mesh = twist
	tw.name = "Twist"
	tw.rotation.z = -PI * 0.5
	tw.position.x = JOINT_L + 0.008
	tw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(tw)
	var crutch := CylinderMesh.new()
	crutch.top_radius = JOINT_R_MOUTH * 1.02
	crutch.bottom_radius = JOINT_R_MOUTH * 1.02
	crutch.height = 0.018
	crutch.radial_segments = 8
	crutch.rings = 1
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.86, 0.72, 0.5)
	cmat.roughness = 0.9
	crutch.material = cmat
	var cr := MeshInstance3D.new()
	cr.mesh = crutch
	cr.rotation.z = -PI * 0.5
	cr.position.x = 0.009
	cr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cr)
	# The ember: a glowing cap that brightens on every draw.
	var ember := SphereMesh.new()
	ember.radius = JOINT_R_TIP * 1.05
	ember.height = JOINT_R_TIP * 1.4
	ember.radial_segments = 10
	ember.rings = 4
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(0.25, 0.08, 0.04)
	emat.emission_enabled = true
	emat.emission = Color(1.0, 0.42, 0.12)
	emat.emission_energy_multiplier = 0.0
	ember.material = emat
	var em := MeshInstance3D.new()
	em.mesh = ember
	em.name = "Ember"
	em.position.x = JOINT_L
	em.visible = false
	em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(em)
	return {"root": root, "ember": em, "ember_mat": emat, "body_mat": mat, "twist": tw}


static func soft_dot() -> GradientTexture2D:
	if _soft_dot == null:
		_soft_dot = GradientTexture2D.new()
		_soft_dot.fill = GradientTexture2D.FILL_RADIAL
		_soft_dot.fill_from = Vector2(0.5, 0.5)
		_soft_dot.fill_to = Vector2(0.5, 0.0)
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
		_soft_dot.gradient = g
		_soft_dot.width = 64
		_soft_dot.height = 64
	return _soft_dot


static func _particle_material(color: Color, additive: bool, unshaded := true) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	mat.albedo_texture = soft_dot()
	mat.disable_receive_shadows = true
	return mat


static func _fade(peak := 0.2, alpha := 1.0) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, peak, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, alpha), Color(1, 1, 1, 0)])
	return g


static func _grow_curve(from: float, to: float) -> Curve:
	var c := Curve.new()
	c.max_value = maxf(from, to)
	c.add_point(Vector2(0.0, from))
	c.add_point(Vector2(1.0, to), 0.0, 0.0)
	return c


## A billowing exhale: soft puffs that drift out, swell and thin away.
static func smoke_puff(color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Exhale"
	p.emitting = false
	p.one_shot = true
	p.amount = 26
	p.lifetime = 3.2
	p.explosiveness = 0.0
	p.local_coords = false
	p.direction = Vector3(0, 0.2, 1)
	p.spread = 22.0
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.6
	p.gravity = Vector3(0, 0.12, 0)
	p.damping_min = 0.25
	p.damping_max = 0.45
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -25.0
	p.angular_velocity_max = 25.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	p.scale_amount_curve = _grow_curve(0.25, 1.0)
	p.color = Color(color, 0.5)
	p.color_ramp = _fade(0.12, 1.0)
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	var mat := _particle_material(Color.WHITE, false, false)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = mat
	p.mesh = q
	return p


## The thin curl that rises from the ember between draws.
static func ember_wisp(color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Wisp"
	p.emitting = false
	p.amount = 14
	p.lifetime = 2.4
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 6.0
	p.initial_velocity_min = 0.06
	p.initial_velocity_max = 0.12
	p.gravity = Vector3(0, 0.08, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	p.scale_amount_curve = _grow_curve(0.15, 1.0)
	p.color = Color(color, 0.32)
	p.color_ramp = _fade(0.15, 1.0)
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	q.material = _particle_material(Color.WHITE, false)
	p.mesh = q
	return p


## Green crumbs that rain onto the paper while the bud is broken up.
static func crumbs(color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Crumbs"
	p.emitting = false
	p.amount = 20
	p.lifetime = 0.45
	p.local_coords = false
	p.direction = Vector3.DOWN
	p.spread = 25.0
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.15
	p.gravity = Vector3(0, -2.2, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var q := BoxMesh.new()
	q.size = Vector3.ONE * 0.007
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.62, 0.25).lerp(color, 0.35)
	mat.roughness = 0.9
	q.material = mat
	p.mesh = q
	return p


## Sparkles: the lighter's fairy spark, the "joint ready" twinkle, the roach
## vanishing.
static func sparkles(color: Color, amount := 16, size := 0.03) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Sparkles"
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.9
	p.explosiveness = 0.85
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.5
	p.gravity = Vector3(0, -0.3, 0)
	p.damping_min = 0.8
	p.damping_max = 1.6
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	p.scale_amount_curve = _grow_curve(1.0, 0.0)
	p.color = color * 1.6
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	q.material = _particle_material(Color.WHITE, true)
	p.mesh = q
	return p


## A tiny magic flame that dances on a fingertip to light the joint.
static func flame() -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.055)
	q.center_offset = Vector3(0, 0.022, 0)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://player/weed/fairy_flame.gdshader")
	q.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.name = "Flame"
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
