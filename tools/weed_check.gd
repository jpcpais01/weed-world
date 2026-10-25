extends SceneTree
## Headless check of the weed loop in the real forest: wild patches grow (one
## by the spawn), the Keling plucks a bud with the regular grab, rolls a joint
## in 10 s, lights it and takes a puff for the Glade Glow, walks off mid-roll
## (the bud comes back), then sits on the Brookside bench and smokes for its
## water power. Exits non-zero on failure.
##   godot --headless --path . -s res://tools/weed_check.gd

# Untyped on purpose: -s scripts compile before the autoloads exist, and the
# controller names GameInput.
const ROLL_TIME := 10.0
const LIGHT_TIME := 2.6
const HIT_TIME := 3.8
const HITS := 3
const ACT_NONE := 0
const ACT_ROLL := 1
const ACT_LIGHT := 2
const ACT_HIT := 3

var _k
var _forest: Forest
var _t := 0.0
var _step := 0
var _step_t := 0.0
var _fails: Array[String] = []
var _bud: WeedBud
var _bench: Bench


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://weed.cfg"))
	root.add_child(load("res://world/forest/forest_level.tscn").instantiate())


func _check(ok: bool, what: String) -> void:
	print("weed_check: %s %s" % ["ok  " if ok else "FAIL", what])
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
		_forest = root.find_child("Forest", true, false) as Forest
		return false
	if _t > 120.0:
		_check(false, "timed out at step %d" % _step)
		return _finish()
	match _step:
		0:
			if _step_t < 1.0:
				return false
			var w := _forest.weed
			_check(w.patches.size() >= 6, "%d weed patches grow in the forest" % w.patches.size())
			var buds := get_nodes_in_group("weed_bud").size()
			_check(buds >= 60, "%d buds on %d plants" % [buds, w.nodes.size()])
			var near := INF
			for p in w.patches:
				near = minf(near, (p.pos as Vector2).distance_to(ForestLayout.SPAWN))
			_check(near < 6.0, "a patch grows %.1f m from the spawn" % near)
			for n in w.nodes:
				var h := n.global_position.y - _forest.ground_height(n.global_position.x, n.global_position.z)
				if absf(h) > 0.1:
					_check(false, "plant floats %.2f m off the ground" % h)
					break
			# Every strain grows somewhere, and every bud is within a Keling's reach.
			var grown := {}
			var reach_ok := true
			for n in w.nodes:
				grown[n.strain] = true
				for b in n.buds:
					var up: float = b.global_position.y - n.global_position.y
					if up < 0.22 or up > 1.18:
						reach_ok = false
						_check(false, "a %s bud grows out of reach (%.2f m up)" % [n.strain, up])
						break
			for s in WeedStrains.ORDER:
				if not grown.has(s):
					_check(false, "strain %s grows nowhere" % s)
				_check(WeedKit.bud_mesh(s) != null, "strain %s has a bud model" % s)
			_check(grown.size() == WeedStrains.ORDER.size(), "all %d strains grow in the glade" % grown.size())
			_check(reach_ok, "every bud is within reach")
			# Stand in front of a plant and face its lowest bud.
			var plant: WeedPlant = w.nodes[0]
			_bud = plant.buds[plant.buds.size() - 1]
			var bp := _bud.global_position
			var stand := Vector3(bp.x, _forest.ground_height(bp.x, bp.z + 0.6), bp.z + 0.6)
			_k.global_position = stand + Vector3.UP * 0.05
			_k.velocity = Vector3.ZERO
			_k.facing = PI
			_next()
		1:
			if _step_t > 0.6 and _step_t - delta <= 0.6:
				_k.try_grab()
			if _step_t > 3.0:
				_check(_k.weed.bud_count() == 1, "the grab put a bud in the pouch (%d)" % _k.weed.bud_count())
				_check(not _bud.ripe or _k.weed.bud_count() > 0, "a bud was plucked off the plant")
				_check(_k.weed.discovered.size() == 1, "the strain is discovered")
				_k.weed.use()
				_check(_k.weed.act == ACT_ROLL, "the weed action starts rolling")
				_check(_k.weed.bud_count() == 0, "rolling uses the bud")
				_next()
		2:
			if _step_t > 9.0 and _step_t - delta <= 9.0:
				_check(not _k.weed.has_joint(), "the joint isn't ready before 10 s")
			if _step_t < ROLL_TIME + 0.2:
				return false
			_check(_k.weed.has_joint() and _k.weed.joint_puffs == HITS, "a joint is ready ~10 s after rolling starts")
			_check(_k.weed.act == ACT_NONE, "rolling finished")
			_k.weed.use()
			_check(_k.weed.act == ACT_LIGHT, "the first smoke lights the joint")
			_next()
		3:
			if _step_t < LIGHT_TIME + HIT_TIME + 0.3:
				return false
			_check(_k.weed.lit, "the joint is lit")
			_check(_k.weed.joint_puffs == HITS - 1, "one puff taken (%d left)" % _k.weed.joint_puffs)
			_check(_k.weed.high.element == &"none" and _k.weed.high.time_left > 0.0, "off a bench: the Glade Glow")
			# Walk off mid-roll: the bud goes back in the pouch.
			_k.weed.add_bud(&"starlit")
			_k.weed.use()
			_check(_k.weed.act == ACT_HIT, "smoking again takes a puff (joint first)")
			_next()
		4:
			if _step_t < HIT_TIME + 0.3:
				return false
			_k.weed.add_bud(&"starlit")
			_k.weed.joint_strain = &""
			_k.weed.joint_puffs = 0
			_k.weed.use()
			_check(_k.weed.act == ACT_ROLL, "rolling a second joint")
			_next()
		5:
			if _step_t < 1.5:
				return false
			Input.action_press("move_forward", 1.0)
			if _step_t < 1.8:
				return false
			Input.action_release("move_forward")
			_check(_k.weed.act == ACT_NONE, "walking off cancels the roll")
			_check(_k.weed.bud_count(&"starlit") == 2, "the bud came back to the pouch")
			# Hand over a joint and head for the Brookside bench.
			_k.weed.joint_strain = &"ember"
			_k.weed.joint_puffs = HITS
			_k.weed.lit = true
			for b in get_nodes_in_group("bench"):
				if (b as Bench).site.id == &"brookside":
					_bench = b
			_check(_bench != null, "found the Brookside bench")
			var sp := _bench.stand_point(0)
			_k.global_position = sp + Vector3.UP * 0.1
			_k.velocity = Vector3.ZERO
			_next()
		6:
			if _step_t > 0.6 and _step_t - delta <= 0.6:
				_k.try_grab()
			if _step_t < 4.0:
				return false
			_check(_k.current_bench() == _bench, "seated on the bench")
			_check(_k.weed_element() == &"water", "the bench's view is water")
			_k.weed.use()
			_check(_k.weed.act == ACT_HIT, "smoking on the bench")
			_next()
		7:
			if _step_t < HIT_TIME + 3.0:
				return false
			_check(_k.weed.high.element == &"water", "the bench grants its power (%s)" % _k.weed.high.element)
			_check(_k.walk_speed > 0.46, "Brook Stride speeds the Keling up (walk %.2f)" % _k.walk_speed)
			_check(_k.current_bench() == _bench, "still seated after smoking")
			return _finish()
	return false


func _finish() -> bool:
	Input.action_release("move_forward")
	print("weed_check: ", "PASS" if _fails.is_empty() else "FAIL (%s)" % ", ".join(_fails))
	quit(0 if _fails.is_empty() else 1)
	return true
