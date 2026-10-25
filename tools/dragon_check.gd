extends SceneTree
## Headless check of Dragon Breath in the real forest. The Keling stands a
## few metres from a weed patch with every bud picked, holds a lit joint and
## holds the puff: it must turn into Dragon Breath, cost one puff, fly a
## terrain-hugging path (over the ground, never through it), rain on the
## patch so its buds ripen, splash down, and tidy itself away. A second
## breath from the same seed, origin and heading must fly the same path (so
## co-op puppets see the same dragon), and a puppet replaying the "dragon"
## activity must breathe one too. Exits non-zero on failure.
##   godot --headless --path . -s res://tools/dragon_check.gd

# Untyped on purpose: -s scripts compile before the autoloads exist.
const ACT_NONE := 0
const ACT_HIT := 3
const ACT_DRAGON := 4
const HITS := 3

var _k
var _forest
var _t := 0.0
var _step := 0
var _step_t := 0.0
var _fails: Array[String] = []
var _plant
var _breath
var _activity := {}
var _min_clear := INF
var _peak_head := 0.0
var _impacted := false
var _puppet


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://weed.cfg"))
	root.add_child(load("res://world/forest/forest_level.tscn").instantiate())


func _check(ok: bool, what: String) -> void:
	print("dragon_check: %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


func _next() -> void:
	_step += 1
	_step_t = 0.0


func _physics_process(delta: float) -> bool:
	_t += delta
	_step_t += delta
	if _k == null:
		_k = root.find_child("Keling", true, false)
		_forest = root.find_child("Forest", true, false)
		return false
	if _t > 150.0:
		_check(false, "timed out at step %d" % _step)
		return _finish()
	match _step:
		0:
			if _step_t < 1.0 or not _k.is_on_floor():
				return false
			# Every bud on the first patch's first plant is picked...
			_plant = _forest.weed.nodes[0]
			for b in _plant.buds:
				if b.ripe:
					b.apply_remote_pick()
			_check(not _plant.has_ripe_bud(), "the test plant starts bare")
			# ...and the Keling stands 6 m off, facing it, with a lit joint.
			var pp: Vector3 = _plant.global_position
			var away := Vector3(1, 0, 0.35).normalized()
			var stand := pp + away * 6.0
			stand.y = _forest.ground_height(stand.x, stand.z) + 0.05
			_k.global_position = stand
			_k.velocity = Vector3.ZERO
			var to := pp - stand
			_k.facing = atan2(to.x, to.z)
			_k.camera_rig.set_yaw(_k.facing + PI)
			_k.weed.joint_strain = &"ember"
			_k.weed.joint_puffs = HITS
			_k.weed.lit = true
			_k.activity_changed.connect(func(a, d): _activity[a] = d)
			_next()
		1:
			if _step_t < 1.0:
				return false
			# Hold the puff (as the touch button does).
			_k.weed.dragon_held = true
			_k.weed.use()
			_check(_k.weed.act == ACT_HIT, "the press starts a puff")
			_next()
		2:
			if _step_t < 0.2:
				return false
			if _k.weed.act != ACT_DRAGON and _step_t < 1.2:
				return false
			_k.weed.dragon_held = false
			_check(_k.weed.act == ACT_DRAGON, "holding the puff turns it into Dragon Breath (%.2f s)" % _step_t)
			_check(_activity.has(&"dragon") and _activity[&"dragon"].has("seed") and _activity[&"dragon"].has("yaw"), "it tells co-op friends (with its seed and heading)")
			_breath = _k.find_child("DragonBreath", true, false)
			_check(_breath != null, "a dragon gathers at the lips")
			_next()
		3:
			if _breath == null:
				return _finish()
			if _breath.phase == 0:
				if _step_t > 4.0:
					_check(false, "the dragon never left the lips")
					return _finish()
				return false
			_check(_k.weed.joint_puffs == HITS - 1, "it costs one puff (%d left)" % _k.weed.joint_puffs)
			_check(_breath._len > 10.0, "it plans a %.1f m flight" % _breath._len)
			var to_plant: Vector3 = _plant.global_position - _k.global_position
			var aim := Vector3(sin(_breath.yaw), 0, cos(_breath.yaw))
			_check(aim.dot(Vector3(to_plant.x, 0, to_plant.z).normalized()) > 0.9, "it flies the way the camera looks")
			_next()
		4:
			# Fly: the head must stay over the ground until the dive.
			if is_instance_valid(_breath):
				var head: float = _breath._head
				_peak_head = maxf(_peak_head, head)
				if head > 0.5 and head < _breath._len - 5.0:
					var p: Vector3 = _breath._pos_at(head)
					_min_clear = minf(_min_clear, p.y - _forest.ground_height(p.x, p.z))
				if _breath._impacted:
					_impacted = true
				if _k.weed.act == ACT_NONE and _breath.phase >= 2:
					_next()
				elif _step_t > 12.0:
					_check(false, "the flight never ended")
					return _finish()
			else:
				_next()
		5:
			_check(_impacted, "the dragon splashes down")
			_check(_min_clear > 0.5, "it skims %.2f m or more over the ground" % _min_clear)
			_check(_plant.has_ripe_bud(), "its rain ripens the bare plant")
			_check(_k.weed.has_joint() and _k.weed.joint_puffs == HITS - 1, "the joint is back in hand")
			# Same seed, origin and heading: the same flight (what a puppet sees).
			var a = DragonBreath.new()
			var b = DragonBreath.new()
			a.setup(null, false, 0.7, 1234)
			b.setup(null, false, 0.7, 1234)
			_forest.add_child(a)
			_forest.add_child(b)
			var o: Vector3 = _k.global_position + Vector3.UP * 0.8
			# One screen drew the breath in for longer than the other.
			a.charge(Transform3D(Basis(), o), 1.0)
			for i in 12:
				a._update_charge(0.1)
			a.release(Transform3D(Basis(), o), 0.7)
			b.release(Transform3D(Basis(), o), 0.7)
			_check(a.impact_point.is_equal_approx(b.impact_point) and a._len == b._len, "the same seed flies the same path (however long each drew it in)")
			a.queue_free()
			b.queue_free()
			# A puppet replays the activity and breathes its own dragon.
			_puppet = load("res://player/keling.tscn").instantiate()
			_puppet.make_remote(7, 1, "Friend")
			_puppet.name = "Puppet"
			_forest.get_parent().add_child(_puppet)
			_puppet.global_position = _k.global_position + Vector3(2, 0.2, 0)
			_next()
		6:
			if _step_t < 0.5:
				return false
			_puppet.play_remote_activity(&"puff", {"strain": "ember", "element": "none"})
			_puppet.play_remote_activity(&"dragon", {"strain": "ember", "yaw": 0.3, "seed": 99, "element": "none"})
			_check(_puppet.weed.act == ACT_DRAGON, "a puppet replays Dragon Breath")
			_check(_puppet.find_child("DragonBreath", true, false) != null, "and breathes its own dragon")
			_next()
		7:
			# Let the first dragon's rainbow and puddle fade, then it must be gone.
			if _k.find_child("DragonBreath", true, false) != null and _step_t < 40.0:
				return false
			_check(_k.find_child("DragonBreath", true, false) == null, "the breath frees itself once its water has dried")
			return _finish()
	return false


func _finish() -> bool:
	if _fails.is_empty():
		print("dragon_check: PASS")
		quit(0)
	else:
		print("dragon_check: FAILED (%d): %s" % [_fails.size(), ", ".join(_fails)])
		quit(1)
	return true
