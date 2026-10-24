class_name WaypointBeacon
extends Node3D
## A soft golden light pillar standing on the waypoint, so you can find it in
## the forest without staring at the map. Fades away as you arrive.

const HEIGHT := 36.0
const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.42, 1.0);
uniform float fade = 1.0;
uniform float height = 36.0;
varying float vh;
void vertex() {
	vh = VERTEX.y / height + 0.5;
}
void fragment() {
	float core = pow(abs(dot(NORMAL, VIEW)), 2.5);
	float a = core * pow(1.0 - vh, 1.6) * fade;
	a *= 0.7 + 0.3 * sin(TIME * 2.6 - vh * 26.0);
	ALBEDO = tint.rgb;
	ALPHA = clamp(a, 0.0, 1.0) * 0.8;
}
"""

var _mat: ShaderMaterial
var _beam: MeshInstance3D
var _ring: MeshInstance3D
var _strength := 0.0
var _target := 0.0


func _ready() -> void:
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_mat.set_shader_parameter("height", HEIGHT)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.42
	cyl.height = HEIGHT
	cyl.radial_segments = 12
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_beam = MeshInstance3D.new()
	_beam.mesh = cyl
	_beam.material_override = _mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position.y = HEIGHT * 0.5
	add_child(_beam)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.75
	torus.outer_radius = 0.9
	torus.rings = 32
	torus.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = _mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position.y = 0.08
	add_child(_ring)
	visible = false


func show_at(p: Vector3) -> void:
	global_position = p
	_target = 1.0
	visible = true


func hide_beacon() -> void:
	_target = 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	_strength = move_toward(_strength, _target, delta * 1.6)
	if _strength <= 0.0 and _target <= 0.0:
		visible = false
		return
	# Gentle as you get close, so it never blinds you on arrival.
	var near := 1.0
	var cam := get_viewport().get_camera_3d()
	if cam:
		var d := Vector2(cam.global_position.x - global_position.x, cam.global_position.z - global_position.z).length()
		near = clampf((d - 2.0) / 10.0, 0.15, 1.0)
	_mat.set_shader_parameter("fade", _strength * near)
	var pulse := 1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.004)
	_ring.scale = Vector3(pulse, 1.0, pulse)
