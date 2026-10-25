extends SceneTree
## Headless check of Owl Flight in the real forest. The Keling breathes out
## an owl gift on the meadow: the owl must gather, swoop and take the Keling
## onto its back (the ride hook, an astride pose), fly it well clear of the
## ground and the trees while it is steered round, keep it inside the valley,
## then on ending glide down, let it hop off onto the ground, melt away and
## tidy up after itself (no ride, pose, tilt or camera left behind). A puppet
## replaying the "gift" event must fly its own owl and let it go too. Exits
## non-zero on failure.
##   godot --headless --path . -s res://tools/owl_check.gd

var _k
var _forest
var _t := 0.0
var _step := 0
var _step_t := 0.0
var _fails: Array[String] = []
var _gift
var _min_clear := INF
var _max_clear := 0.0
var _max_out := 0.0
var _yaw0 := 0.0
var _turned := 0.0
var _puppet
var _pgift


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://weed.cfg"))
	root.add_child(load("res://world/forest/forest_level.tscn").instantiate())


func _check(ok: bool, what: String) -> void:
	print("owl_check: %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


func _next() -> void:
	_step += 1
	_step_t = 0.0


func _ground(p: Vector3) -> float:
	return maxf(WaterLevel.ground_at(p.x, p.z), WaterLevel.surface_at(p.x, p.z))


func _physics_process(delta: float) -> bool:
	_t += delta
	_step_t += delta
	if _k == null:
		_k = root.find_child("Keling", true, false)
		_forest = root.find_child("Forest", true, false)
		return false
	if _t > 120.0:
		_check(false, "timed out at step %d" % _step)
		return _finish()
	match _step:
		0:
			if _step_t < 1.0 or not _k.is_on_floor() or _k.weed.gifts == null:
				return false
			var stand := Vector3(-2.0, 0.0, 12.0)
			stand.y = _forest.ground_height(stand.x, stand.z) + 0.05
			_k.global_position = stand
			_k.velocity = Vector3.ZERO
			_k.facing = PI
			_check(SmokeGifts.valid(&"owl") and SmokeGifts.script_for(&"owl") != null, "Owl Flight is a registered gift")
			_next()
		1:
			if _step_t < 1.0:
				return false
			_k.weed.gifts.ready_gift = &"owl"
			_k.weed.gifts.charges = 1
			_check(_k.weed.gifts.cast(), "the Gift button breathes out the owl")
			_gift = _k.find_child("Gift_owl", true, false)
			_check(_gift != null, "an owl gift node is made")
			if _gift == null:
				return _finish()
			_next()
		2:
			# Gather, swoop, hop on.
			if _gift.phase < 3:
				if _step_t > 8.0:
					_check(false, "the owl picks the Keling up")
					return _finish()
				return false
			_check(_k.gift_ride == _gift, "riding: the owl drives the Keling")
			_yaw0 = _k.facing
			_next()
		3:
			# Fly; steer left for a while.
			var seat: Vector3 = _k.global_position
			var clear: float = seat.y - _ground(seat)
			if _step_t > 3.0:
				_min_clear = minf(_min_clear, clear)
			_max_clear = maxf(_max_clear, clear)
			_max_out = maxf(_max_out, maxf(absf(seat.x), absf(seat.z)))
			if _step_t > 2.0 and _step_t < 7.0:
				Input.action_press("move_left", 1.0)
			else:
				Input.action_release("move_left")
			_turned = maxf(_turned, absf(wrapf(_k.facing - _yaw0, -PI, PI)))
			if _step_t > 1.0:
				_check_once("sit", _k.sit.straddle > 0.9 and _k.sit.amount > 0.9, "the Keling sits astride its back")
			if _step_t < 12.0:
				return false
			Input.action_release("move_left")
			_check(_max_clear > 12.0, "it climbs well above the forest (%.1f m)" % _max_clear)
			_check(_min_clear > 7.0, "it never skims the ground or the trees once up (lowest %.1f m)" % _min_clear)
			_check(_max_out < 48.0, "it stays inside the valley (furthest %.1f m)" % _max_out)
			_check(_turned > 1.0, "the stick turns it (%.2f rad)" % _turned)
			_gift.end()
			_next()
		4:
			# Glide down, hop off, land.
			if _k.gift_ride != null:
				if _step_t > 9.0:
					_check(false, "it comes down and lets the Keling off")
					return _finish()
				return false
			if not _k.is_on_floor():
				if _step_t > 14.0:
					_check(false, "the Keling lands after hopping off")
					return _finish()
				return false
			_check(true, "the Keling hops off and lands (%.1f s)" % _step_t)
			_next()
		5:
			if is_instance_valid(_gift):
				if _step_t > 6.0:
					_check(false, "the owl melts away and frees itself")
					return _finish()
				return false
			_check(true, "the owl melts away and frees itself")
			_check(_k.sit.amount == 0.0 and _k.sit.straddle == 0.0, "no riding pose left behind")
			_check(is_zero_approx(_k.visual.rotation.x) and is_zero_approx(_k.visual.rotation.z), "no tilt left on the Keling")
			_check(not _k.camera_rig._ride_on, "the camera stops following a mount")
			_next()
		6:
			# A friend's owl on their puppet.
			_puppet = load("res://player/keling.tscn").instantiate()
			_puppet.make_remote(7, 1, "Friend")
			_puppet.name = "Puppet"
			_forest.get_parent().add_child(_puppet)
			_puppet.global_position = _k.global_position + Vector3(3, 0.2, 0)
			_next()
		7:
			if _step_t < 0.5:
				return false
			var data := {"gift": &"owl", "seed": 5, "boost": false, "pos": _puppet.global_position, "yaw": 0.0}
			_puppet.apply_net_event(&"gift", [data])
			_pgift = _puppet.find_child("Gift_owl", true, false)
			_check(_pgift != null, "a friend's owl gift plays on their puppet")
			if _pgift == null:
				return _finish()
			_next()
		8:
			if _step_t < 5.0:
				return false
			_check(_pgift.phase == 3, "the puppet's owl takes them up")
			_puppet.apply_net_event(&"gift_end", [&"owl"])
			_next()
		9:
			if is_instance_valid(_pgift) and _step_t < 10.0:
				return false
			_check(not is_instance_valid(_pgift), "the puppet's owl lets go and melts away")
			return _finish()
	return false


var _once := {}


func _check_once(key: String, ok: bool, what: String) -> void:
	if _once.has(key):
		return
	_once[key] = true
	_check(ok, what)


func _finish() -> bool:
	Input.action_release("move_left")
	if _fails.is_empty():
		print("owl_check: PASS")
		quit(0)
	else:
		print("owl_check: %d failed" % _fails.size())
		quit(1)
	return true
