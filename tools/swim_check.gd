extends SceneTree
## Headless check of wading and swimming in the real forest: the Keling walks
## off the bank into the pond (slowing as it wades), starts swimming where it
## can't stand, floats with its chin at the waterline, paddles across and
## wades out the far side, shakes itself dry, cannonballs in from a height
## with a splash, hops back out with jump, and a friend's puppet fed its
## snapshots swims along with it. Exits non-zero on failure.
##   godot --headless --path . -s res://tools/swim_check.gd

# Untyped on purpose: -s scripts compile before the autoloads exist, and the
# controller names GameInput.
const MODE_GROUND := 0
const MODE_AIR := 1
const MODE_SWIM := 9

var _k
var _puppet
var _forest: Forest
var _t := 0.0
var _step := 0
var _step_t := 0.0
var _fails: Array[String] = []
var _target := Vector3.ZERO
var _min_wade_speed := INF
var _max_float_err := 0.0
var _swim_samples := 0
var _shook := false
var _ripples_seen := 0
var _sync: GDScript


func _initialize() -> void:
	_sync = load("res://player/keling_sync.gd")
	root.add_child(load("res://world/forest/forest_level.tscn").instantiate())


func _check(ok: bool, what: String) -> void:
	print("swim_check: %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


func _next() -> void:
	_step += 1
	_step_t = 0.0


## A point on the pond at `angle`, `f` of the way from the centre to the shore
## (beyond 1 is out on the bank).
func _pond_point(angle: float, f: float) -> Vector3:
	var c := ForestLayout.POND
	var r := _forest.layout.pond_radius(angle) * f
	var p := c + Vector2(cos(angle), sin(angle)) * r
	return Vector3(p.x, _forest.ground_height(p.x, p.y), p.y)


## Holds the stick towards `_target` (camera-relative, like a player would).
func _steer(strength := 1.0) -> void:
	var to: Vector3 = _target - _k.global_position
	to.y = 0.0
	if to.length() < 0.05:
		return
	var dir := to.normalized()
	_k.camera_rig.yaw = atan2(-dir.x, -dir.z)
	Input.action_press("move_forward", strength)


func _release() -> void:
	Input.action_release("move_forward")
	Input.action_release("jump")


func _place(at: Vector3, yaw: float) -> void:
	_k.global_position = at
	_k.velocity = Vector3.ZERO
	_k.facing = yaw
	_k.mode = MODE_GROUND
	_k.reset_physics_interpolation()


func _physics_process(delta: float) -> bool:
	_t += delta
	_step_t += delta
	if _k == null:
		_k = root.find_child("Keling", true, false)
		_forest = root.find_child("Forest", true, false) as Forest
		return false
	if _t > 150.0:
		_check(false, "timed out at step %d" % _step)
		return _finish()
	var fx = WaterFX._active
	if fx and not fx._ripples.is_empty():
		_ripples_seen = maxi(_ripples_seen, fx._ripples.size())
	match _step:
		0:
			if _step_t < 1.0:
				return false
			_check(WaterLevel.has_water(), "the forest publishes its water")
			var c := ForestLayout.POND
			var deep := WaterLevel.bed_depth_at(c.x, c.y)
			_check(deep > 1.0, "the pond is %.2f m deep in the middle" % deep)
			_check(WaterLevel.surface_at(ForestLayout.SPAWN.x, ForestLayout.SPAWN.y) == -INF, "no water at the spawn")
			# Start on the west bank, facing the pond, and walk in.
			var start := _pond_point(deg_to_rad(200.0), 1.35)
			_target = _pond_point(deg_to_rad(20.0), 1.4)
			_place(start + Vector3.UP * 0.05, atan2(_target.x - start.x, _target.z - start.z))
			_next()
		1:
			_steer()
			var w = _k.water
			if w.immersion > 0.45 and _k.mode == MODE_GROUND:
				_min_wade_speed = minf(_min_wade_speed, Vector2(_k.velocity.x, _k.velocity.z).length())
			if _k.mode == MODE_SWIM:
				_check(w.bed_depth >= 0.75, "starts swimming where the water is %.2f m deep" % w.bed_depth)
				_check(_min_wade_speed < _k.jog_speed * 0.8, "wading chest-deep slows it to %.2f m/s" % _min_wade_speed)
				_next()
			elif _step_t > 20.0:
				_check(false, "never started swimming (mode %d, depth %.2f)" % [_k.mode, w.bed_depth])
				return _finish()
		2:
			# Paddle across; the chin should ride the waterline.
			_steer()
			var w = _k.water
			if _k.mode == MODE_SWIM and _step_t > 1.5 and w.bed_depth > 1.0:
				var want: float = w.surface - w.float_depth(w.stroke_amount())
				_max_float_err = maxf(_max_float_err, absf(_k.global_position.y - want))
				_swim_samples += 1
				if _swim_samples == 30:
					_check(w.swim_amount() > 0.95, "the swim pose is fully on (%.2f)" % w.swim_amount())
					_check(_k.swim.amount > 0.9 and _k.swim.stroke > 0.5, "paddling at stroke %.2f" % _k.swim.stroke)
					var speed := Vector2(_k.velocity.x, _k.velocity.z).length()
					_check(speed > 0.6 and speed < _k.swim_sprint_speed * 1.4, "swims along at %.2f m/s" % speed)
					_check(not _k.procedural.ik_enabled, "foot IK is off while afloat")
					# Look up from below: the camera must stay out of the water.
					_k.camera_rig.pitch = 0.6
				if _swim_samples == 60:
					var cam_y: float = _k.camera_rig.camera.global_position.y
					_check(cam_y > w.surface + 0.05, "the camera skims %.2f m above the water" % (cam_y - w.surface))
			if _k.mode == MODE_GROUND and w.immersion < 0.3 and _swim_samples > 0:
				_check(_max_float_err < 0.15, "floats within %.2f m of the waterline" % _max_float_err)
				_check(_ripples_seen > 0, "strokes and steps ripple the water (%d at once)" % _ripples_seen)
				_next()
			elif _step_t > 30.0:
				_check(false, "never waded out (mode %d, at %s)" % [_k.mode, _k.global_position])
				return _finish()
		3:
			# Out onto the bank, stop, and shake dry.
			_steer()
			if _k.water.immersion < -0.05 or _step_t > 6.0:
				_release()
				_next()
		4:
			if _k._water_shake > 0.0:
				_shook = true
			if _shook or _step_t > 3.0:
				_check(_shook, "shakes itself dry after the swim")
				# Cannonball: drop in from 1.6 m over deep water.
				var p := _pond_point(deg_to_rad(110.0), 0.15)
				_place(Vector3(p.x, WaterLevel.surface_at(p.x, p.z) + 1.6, p.z), 0.0)
				_k._enter_air(false)
				_ripples_seen = 0
				_next()
		5:
			if _k.mode == MODE_SWIM:
				_check(_ripples_seen > 0, "the plunge splashes the surface")
				_check(_k.water._crown.emitting, "a crown of droplets flies up")
				_next()
			elif _step_t > 4.0:
				_check(false, "fell in but never swam (mode %d)" % _k.mode)
				return _finish()
		6:
			# Bob back up, then a friend's puppet follows our snapshots.
			if _step_t > 1.5 and _puppet == null:
				var w = _k.water
				var err: float = absf(_k.global_position.y - (w.surface - w.float_depth(w.stroke_amount())))
				_check(err < 0.12, "bobs back up to the waterline (%.2f m off)" % err)
				_puppet = load("res://player/keling.tscn").instantiate()
				_puppet.make_remote(2, 1, "Friend")
				_k.get_parent().add_child(_puppet)
			if _puppet:
				_puppet.remote.push(_sync.pack(_k))
			if _step_t > 3.5:
				_check(_puppet.mode == MODE_SWIM, "the puppet swims too")
				_check(_puppet.water.swim_amount() > 0.9, "the puppet's swim pose is on (%.2f)" % _puppet.water.swim_amount())
				_check(_puppet.global_position.distance_to(_k.global_position) < 0.5, "the puppet floats where we are")
				# Hop out with jump.
				Input.action_press("jump")
				_next()
		7:
			_puppet.remote.push(_sync.pack(_k))
			if _step_t > 0.1:
				Input.action_release("jump")
			if _k.mode == MODE_AIR and _k.velocity.y > 1.0:
				_check(true, "jump hops up out of the water")
				_next()
			elif _step_t > 2.0:
				_check(false, "jump did nothing in the water (mode %d)" % _k.mode)
				return _finish()
		8:
			_puppet.remote.push(_sync.pack(_k))
			if _k.mode == MODE_SWIM:
				_check(true, "drops back in and swims on")
				return _finish()
			elif _step_t > 4.0:
				_check(false, "never came back down into the water (mode %d)" % _k.mode)
				return _finish()
	return false


func _finish() -> bool:
	_release()
	if _fails.is_empty():
		print("swim_check: PASS")
	else:
		print("swim_check: %d FAILED" % _fails.size())
	quit(0 if _fails.is_empty() else 1)
	return true
