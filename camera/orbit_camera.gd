class_name OrbitCamera
extends Node3D
## Third-person orbit camera with smoothed follow, collision (SpringArm3D),
## mouse / touch / gamepad look, pinch and wheel zoom, gentle auto-recentre
## behind a moving character, sprint FOV kick and impact shake.
## Framing follows the rule of thirds: the camera sits a little high and tilts
## up off the arm so the character stands on the lower third of the screen,
## leaving the view ahead open.

@export var target_path: NodePath
@export var target_height := 0.7  ## orbit pivot above the feet (the Keling's middle)
## Where the pivot lands on screen, as a fraction of the height from the bottom.
@export_range(0.2, 0.5) var frame_height := 0.33
@export var distance := 3.4
@export var min_distance := 1.6
@export var max_distance := 7.0
@export var min_pitch := deg_to_rad(-70.0)
@export var max_pitch := deg_to_rad(35.0)
@export var mouse_sensitivity := 0.0032
@export var touch_sensitivity := 0.0055
@export var gamepad_speed := 2.8
@export var follow_lag := 12.0
@export var recentre_delay := 1.6
@export var base_fov := 60.0
## Player settings (autoload/settings.gd sets these and the sensitivities).
var invert_y := false
var invert_x := false
var auto_follow := true   ## drift back behind a moving character

@onready var arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var yaw := 0.0
var pitch := deg_to_rad(-22.0)
var _target: Node3D
var _focus := Vector3.ZERO
var _zoom := 3.4
var _since_manual := 99.0
var _shake := 0.0
var _shake_t := 0.0
# Scenic framing (benches): ease round to gaze at a view.
var _view_active := false
var _view_point := Vector3.ZERO
var _view_blend := 0.0
var _view_zoom := 0.0
var _saved_zoom := 0.0
var _view_excluded: Array[RID] = []
# Close-ups (rolling a joint): swing round to the front, close and low.
var _close_active := false
var _close_blend := 0.0
var _close_yaw := 0.0
var _close_fwd := Vector3.FORWARD
var _close_moved := false        # the player looked around during the close-up
var _close_saved := Vector3.ZERO # yaw, pitch, zoom to go back to
var _returning := false
const CLOSE_ZOOM := 1.2
const CLOSE_PITCH := -0.3
const CLOSE_HEIGHT := 0.74
const CLOSE_AHEAD := 0.3        # pivot this far in front of the character (its hands)       # pivot at the hands, not the belly
const CLOSE_FRAME := 0.5


func _ready() -> void:
	top_level = true
	# Moved every rendered frame from interpolated targets, so no physics interpolation.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_to_group("orbit_camera")
	_target = get_node_or_null(target_path)
	if _target == null:
		_target = get_parent() as Node3D
	_zoom = distance
	arm.spring_length = distance
	arm.margin = 0.15
	if _target is CollisionObject3D:
		arm.add_excluded_object((_target as CollisionObject3D).get_rid())
	camera.fov = base_fov
	_focus = _target.global_position + Vector3.UP * target_height
	global_position = _focus
	var settings := get_node_or_null("/root/Settings")
	if settings:
		settings.apply_camera(self)


func set_yaw(value: float) -> void:
	yaw = value


## Jumps straight to the target with no follow lag (after a teleport).
func snap() -> void:
	if _target == null:
		return
	_focus = _target.global_position + Vector3.UP * target_height
	global_position = _focus
	rotation = Vector3(pitch, yaw, 0.0)
	reset_physics_interpolation()


## Yaw-only basis used to make movement camera relative.
func get_flat_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func add_look_input(delta_radians: Vector2) -> void:
	yaw -= delta_radians.x * (-1.0 if invert_x else 1.0)
	pitch = clampf(pitch - delta_radians.y * (-1.0 if invert_y else 1.0), min_pitch, max_pitch)
	_since_manual = 0.0


## Touch drag in pixels (from the touch controls).
func add_touch_look(drag: Vector2) -> void:
	add_look_input(drag * touch_sensitivity)


func zoom_by(factor: float) -> void:
	_zoom = clampf(_zoom * factor, min_distance, max_distance)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Eases the camera round behind the character to frame a view, pulled back a
## little and a touch wider. Manual look still works; the camera drifts back
## to the view after a while. `exclude` lists bodies the arm may pass through
## (the bench it sits on).
func frame_view(point: Vector3, view_distance := 4.2, exclude: Array[RID] = []) -> void:
	if not _view_active:
		_saved_zoom = _zoom
	_view_active = true
	_view_point = point
	_view_zoom = view_distance
	_since_manual = 99.0
	for rid in _view_excluded:
		arm.remove_excluded_object(rid)
	_view_excluded = exclude.duplicate()
	for rid in _view_excluded:
		arm.add_excluded_object(rid)


## Swings round to a front three-quarter close-up of the character (who faces
## `facing`), for a good look at something in its hands. Manual look still
## works; end_closeup() glides back to where the camera was.
func begin_closeup(facing: float) -> void:
	if not _close_active:
		_close_saved = Vector3(yaw, pitch, _zoom)
	_close_active = true
	_returning = false
	_close_moved = false
	# In front, a little off to the character's right (the busy hand).
	_close_yaw = facing - 0.32
	_close_fwd = Vector3(sin(facing), 0.0, cos(facing))
	_since_manual = 99.0


func end_closeup() -> void:
	if not _close_active:
		return
	_close_active = false
	_returning = not _close_moved
	_zoom = _close_saved.z


func release_view() -> void:
	if not _view_active:
		return
	_view_active = false
	_zoom = _saved_zoom
	for rid in _view_excluded:
		arm.remove_excluded_object(rid)
	_view_excluded.clear()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		add_look_input(event.relative * mouse_sensitivity)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom_by(0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom_by(1.1)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if GameInput.method == GameInput.Method.KEYBOARD_MOUSE and not OS.has_feature("mobile"):
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_timed(delta)
	PerfMeter.add(&"camera", Time.get_ticks_usec() - t0)


func _process_timed(delta: float) -> void:
	if _target == null:
		return
	delta = minf(delta, 0.1)
	_since_manual += delta

	var pad := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if pad != Vector2.ZERO:
		add_look_input(pad * gamepad_speed * delta)
	if Input.is_action_pressed("zoom_in"):
		zoom_by(1.0 - delta)
	if Input.is_action_pressed("zoom_out"):
		zoom_by(1.0 + delta)

	var target_pos := _target.get_global_transform_interpolated().origin
	var vel := Vector3.ZERO
	if _target is CharacterBody3D:
		vel = (_target as CharacterBody3D).velocity
	var flat_speed := Vector2(vel.x, vel.z).length()

	# Drift behind the character once the player stops steering the camera.
	var facing = _target.get("facing")
	if auto_follow and _since_manual > recentre_delay and flat_speed > 0.4 and facing != null:
		var behind: float = facing + PI
		# Only when running away or across: running towards the camera must not
		# swing it around (that would steer the run into a circle).
		var off := absf(wrapf(behind - yaw, -PI, PI))
		var t := clampf(flat_speed / 3.0, 0.0, 1.0) * 1.1 * delta * smoothstep(deg_to_rad(115.0), deg_to_rad(60.0), off)
		yaw = lerp_angle(yaw, behind, t)
		pitch = lerpf(pitch, deg_to_rad(-20.0), t * 0.5)

	if _close_active:
		if _since_manual < 0.1:
			_close_moved = true
		_close_blend = move_toward(_close_blend, 1.0, delta * 1.4)
		var k := 1.0 - exp(-(2.6 if _since_manual > 2.5 else 0.0) * delta)
		yaw = lerp_angle(yaw, _close_yaw, k)
		pitch = lerpf(pitch, CLOSE_PITCH, k)
		_zoom = lerpf(_zoom, CLOSE_ZOOM, 1.0 - exp(-2.2 * delta))
	else:
		_close_blend = move_toward(_close_blend, 0.0, delta * 1.1)
		if _returning:
			if _since_manual < 0.1 or flat_speed > 0.4:
				_returning = false
			else:
				var k := 1.0 - exp(-2.4 * delta)
				yaw = lerp_angle(yaw, _close_saved.x, k)
				pitch = lerpf(pitch, _close_saved.y, k)
				if absf(wrapf(yaw - _close_saved.x, -PI, PI)) < 0.01:
					_returning = false
	if _view_active and not _close_active:
		_frame_view(delta)
	elif not _view_active:
		_view_blend = move_toward(_view_blend, 0.0, delta * 0.8)

	# Smooth follow: stiffer vertically when falling so we don't lose the player.
	var cb := smoothstep(0.0, 1.0, _close_blend)
	var focus_target := target_pos + Vector3.UP * lerpf(target_height, CLOSE_HEIGHT * _target_scale(), cb) + _close_fwd * CLOSE_AHEAD * _target_scale() * cb
	var k := 1.0 - exp(-follow_lag * delta)
	var ky := 1.0 - exp(-(follow_lag * (2.0 if vel.y < -6.0 else 0.6)) * delta)
	_focus.x = lerpf(_focus.x, focus_target.x, k)
	_focus.z = lerpf(_focus.z, focus_target.z, k)
	_focus.y = lerpf(_focus.y, focus_target.y, ky)

	arm.spring_length = lerpf(arm.spring_length, _zoom, 1.0 - exp(-8.0 * delta))
	global_position = _focus
	rotation = Vector3(pitch, yaw, 0.0)

	var sprinting := flat_speed > 2.0
	var fov_target := base_fov + (6.0 if sprinting else 0.0) + 5.0 * smoothstep(0.0, 1.0, _view_blend)
	camera.fov = lerpf(camera.fov, fov_target, 1.0 - exp(-(1.2 if _view_active else 3.0) * delta))
	camera.rotation.x = _frame_tilt(lerpf(frame_height, CLOSE_FRAME, cb))

	if _shake > 0.001:
		_shake_t += delta * 40.0
		camera.h_offset = sin(_shake_t * 1.3) * _shake * 0.08
		camera.v_offset = cos(_shake_t) * _shake * 0.1
		_shake = lerpf(_shake, 0.0, 1.0 - exp(-7.0 * delta))
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


## Upward tilt of the camera off the arm that puts the pivot at frame_height.
func _frame_tilt(at := -1.0) -> float:
	var fh := frame_height if at < 0.0 else at
	return atan((1.0 - 2.0 * fh) * tan(deg_to_rad(camera.fov) * 0.5))


## The character's visual scale (a giant Keling gets a higher close-up).
func _target_scale() -> float:
	var v = _target.get("visual") if _target else null
	return (v as Node3D).scale.y if v is Node3D else 1.0


func _frame_view(delta: float) -> void:
	_view_blend = move_toward(_view_blend, 1.0, delta * 0.6)
	# Swing round slowly and cinematically; hold off while the player looks
	# around, then drift back to the view.
	var to := _view_point - _focus
	var flat := Vector2(to.x, to.z)
	if flat.length() < 0.5:
		return
	var want_yaw := atan2(-to.x, -to.z)
	# The camera already tilts up by the framing angle, so the arm stays that much lower.
	var want_pitch := clampf(atan2(to.y, flat.length()) - deg_to_rad(9.0) - _frame_tilt(), deg_to_rad(-40.0), deg_to_rad(0.0))
	var rate := 1.5 if _since_manual > 3.5 else 0.0
	var k := 1.0 - exp(-rate * delta)
	yaw = lerp_angle(yaw, want_yaw, k)
	pitch = lerpf(pitch, want_pitch, k)
	_zoom = lerpf(_zoom, _view_zoom, 1.0 - exp(-0.9 * delta))
