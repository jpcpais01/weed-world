extends Camera3D
## Free camera for previewing the forest without a player. Mouse/keyboard:
## right-drag to look, WASD to move, Q/E down/up, Shift to hurry. Touch: drag
## to look, hold with two fingers to glide forward. Left alone for a while it
## drifts on a slow sightseeing tour.

const TOUR: Array[Vector3] = [
	Vector3(-3, 1.7, 20), Vector3(-2, 2.2, 8), Vector3(-9, 2.0, -4), Vector3(-10, 2.4, -16),
	Vector3(-4, 4.2, -26), Vector3(-11, 9.8, -34), Vector3(-2, 3.0, -14), Vector3(6, 1.8, -12),
	Vector3(15, 1.8, -2), Vector3(24, 2.0, -4), Vector3(30, 2.2, -8), Vector3(19, 1.8, 6),
	Vector3(10, 1.8, 14), Vector3(-14, 1.8, 24), Vector3(-26, 2.2, 22), Vector3(-12, 2.0, 32),
]

var ground: Node
var speed := 6.0
var sensitivity := 0.004
var _yaw := 0.0
var _pitch := -0.08
var _idle := 0.0
var _tour_t := 0.0
var _touches := {}


func _ready() -> void:
	fov = 62.0
	near = 0.08
	far = 400.0
	_yaw = rotation.y


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_look(event.relative)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_look(event.relative * 1.4)
	if event is InputEventMouseMotion or event is InputEventKey or event is InputEventScreenTouch:
		_idle = 0.0


func _look(rel: Vector2) -> void:
	_yaw -= rel.x * sensitivity
	_pitch = clampf(_pitch - rel.y * sensitivity, -1.4, 1.4)
	_idle = 0.0


func _process(delta: float) -> void:
	_idle += delta
	if _idle > 20.0:
		_tour(delta)
		return
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): move.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S): move.z += 1.0
	if Input.is_physical_key_pressed(KEY_A): move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): move.x += 1.0
	if Input.is_physical_key_pressed(KEY_E): move.y += 1.0
	if Input.is_physical_key_pressed(KEY_Q): move.y -= 1.0
	if _touches.size() >= 2:
		move.z -= 1.0
	var fast := 3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	position += basis * move * speed * fast * delta
	_keep_above_ground()


func _tour(delta: float) -> void:
	_tour_t += delta * 0.045
	var n := TOUR.size()
	var i := int(_tour_t) % n
	var t := fmod(_tour_t, 1.0)
	var p := _catmull(TOUR[(i - 1 + n) % n], TOUR[i], TOUR[(i + 1) % n], TOUR[(i + 2) % n], t)
	var ahead := _catmull(TOUR[(i - 1 + n) % n], TOUR[i], TOUR[(i + 1) % n], TOUR[(i + 2) % n], minf(t + 0.08, 1.0))
	position = position.lerp(p, minf(delta * 2.0, 1.0))
	var dir := (ahead - p)
	if dir.length() > 0.01:
		var target := Basis.looking_at(dir.normalized() + Vector3(0, -0.05, 0), Vector3.UP)
		basis = basis.slerp(target, minf(delta * 1.5, 1.0)).orthonormalized()
		var e := basis.get_euler()
		_pitch = e.x
		_yaw = e.y
	_keep_above_ground()


func _keep_above_ground() -> void:
	if ground and ground.has_method("ground_height"):
		var h: float = ground.ground_height(position.x, position.z)
		position.y = maxf(position.y, h + 0.6)


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
