extends SceneTree
## Headless check of the smoke gifts in the real forest. Puffs of a joint must
## charge its strain's gift (three at most, boosted by a matching bench view,
## swapped by another strain, gone when the high ends), and the Gift button
## must breathe each of the five gifts out: Moon Jump lightens the body, Slow
## Time slows the world (and puts it back), Cloud Ride lifts the Keling onto a
## cloud and lets it hop off, the fireflies pick a plant, Bloom Burst grows
## giant flora. Every cast tells co-op friends, a puppet replaying it plays
## its own, and every gift tidies itself away. Exits non-zero on failure.
##   godot --headless --path . -s res://tools/gift_check.gd

# Untyped on purpose: -s scripts compile before the autoloads exist.
const ORDER := [&"moonjump", &"slowtime", &"cloud", &"fireflies", &"bloom"]
const FLORA := [&"glowcap", &"springcap", &"starlily", &"bellvine", &"fern", &"lotus", &"puffball"]

var _k
var _forest
var _t := 0.0
var _step := 0
var _step_t := 0.0
var _fails: Array[String] = []
var _events := []
var _gi := 0
var _gift
var _puppet
var SG     # SmokeGifts, GiantFlora, SmokeGift and WeedStrains, loaded once the autoloads exist
var GF
var SGN
var WS


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://weed.cfg"))
	root.add_child(load("res://world/forest/forest_level.tscn").instantiate())


func _check(ok: bool, what: String) -> void:
	print("gift_check: %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


func _next() -> void:
	_step += 1
	_step_t = 0.0


func _gifts():
	return _k.weed.gifts


func _physics_process(delta: float) -> bool:
	_t += delta / maxf(Engine.time_scale, 0.01)
	_step_t += delta / maxf(Engine.time_scale, 0.01)
	if _k == null:
		_k = root.find_child("Keling", true, false)
		SG = load("res://player/powers/smoke_gifts.gd")
		GF = load("res://player/powers/giant_flora.gd")
		SGN = load("res://player/powers/smoke_gift.gd")
		WS = load("res://world/weed/weed_strains.gd")
		_forest = root.find_child("Forest", true, false)
		return false
	if _t > 240.0:
		_check(false, "timed out at step %d (gift %d)" % [_step, _gi])
		return _finish()
	match _step:
		0:
			if _step_t < 1.0 or not _k.is_on_floor() or _gifts() == null:
				return false
			# The table: every wild strain carries a gift, every gift has a script.
			for s in WS.STRAINS:
				_check(SG.valid(SG.of_strain(s)), "%s carries a gift (%s)" % [s, SG.of_strain(s)])
			for g in SG.ORDER:
				_check(SG.script_for(g) != null, "%s has a script" % g)
			for kind in FLORA:
				var f = GF.get_flora(kind, 0)
				_check(f.mesh != null and f.mesh.get_surface_count() > 0 and f.info.height > 0.3, "giant %s builds (%.1f m)" % [kind, f.info.height])
			_k.net_event.connect(func(kind, args): _events.append([kind, args]))
			# Puffs of an ember joint at a spirit view: boosted firefly charges.
			_k.weed.joint_strain = &"ember"
			_k.weed.puffed.emit(&"spirit", 2)
			_check(_gifts().ready_gift == &"fireflies" and _gifts().charges == 1, "a puff charges the strain's gift")
			_check(_gifts().boosted, "a matching bench view boosts it")
			for i in 4:
				_k.weed.puffed.emit(&"none", 1)
			_check(_gifts().charges == SG.MAX_CHARGES, "charges stop at %d" % SG.MAX_CHARGES)
			_k.weed.joint_strain = &"verdant"
			_k.weed.puffed.emit(&"none", 1)
			_check(_gifts().ready_gift == &"bloom" and _gifts().charges == 1 and not _gifts().boosted, "another strain swaps the gift")
			_gifts()._on_high_ended()
			_check(_gifts().charges == 0, "charges go when the high ends")
			_check(not _gifts().cast(), "no charge, no gift")
			_next()
		1:
			# Cast the next gift.
			if _gi >= ORDER.size():
				_step = 10
				return false
			if _step_t < 0.5:
				return false
			var id = ORDER[_gi]
			_gifts().ready_gift = id
			_gifts().charges = 1
			_gifts().boosted = false
			_events.clear()
			_check(_gifts().cast(), "%s casts" % id)
			_gift = _gifts().active.get(id)
			_check(_gift != null and is_instance_valid(_gift), "%s is breathed out" % id)
			_check(_gifts().charges == 0, "%s costs a charge" % id)
			var told := false
			for e in _events:
				if e[0] == &"gift" and e[1][0].get("gift") == id and e[1][0].has("seed"):
					told = true
			_check(told, "%s tells co-op friends" % id)
			if _gift == null:
				_gi += 1
				return false
			_next()
		2:
			# Let it play a while, then see that it does its thing.
			var id = ORDER[_gi]
			if _step_t < (2.5 if id != &"bloom" else 5.0):
				return false
			match id:
				&"moonjump":
					_check(_k.gravity_mod < 0.6 and _k.jump_mod > 1.5, "the moon lets gravity go (x%.2f)" % _k.gravity_mod)
				&"slowtime":
					_check(Engine.time_scale < 0.5, "the world slows (x%.2f)" % Engine.time_scale)
					_check(_k.time_dilation > 1.5, "but not the Keling (x%.2f)" % _k.time_dilation)
				&"cloud":
					_check(_gift.riding and _k.gift_ride == _gift, "the Keling rides the cloud")
					var h = _k.global_position.y - SGN.floor_at(_k.global_position.x, _k.global_position.z)
					_check(h > 0.8, "the cloud lifts it %.1f m up" % h)
				&"fireflies":
					_check(_gift.target_index >= 0, "the fireflies pick a plant to lead to (#%d)" % _gift.target_index)
				&"bloom":
					_check(_gift._plants.size() >= 6, "giant flora erupt (%d)" % _gift._plants.size())
					var grown := 0
					for p in _gift._plants:
						if p.get("born", false):
							grown += 1
					_check(grown >= 3, "and grow (%d up)" % grown)
			# A puppet replays the same cast.
			if _puppet == null:
				_puppet = load("res://player/keling.tscn").instantiate()
				_puppet.make_remote(7, 1, "Friend")
				_puppet.name = "Puppet"
				_forest.get_parent().add_child(_puppet)
				_puppet.global_position = _k.global_position + Vector3(2, 0.2, 0)
			for e in _events:
				if e[0] == &"gift":
					_puppet.apply_net_event(&"gift", e[1])
			_next()
		3:
			if _step_t < 0.3:
				return false
			var id = ORDER[_gi]
			var pg = _puppet.weed.gifts.active.get(id) if _puppet.weed and _puppet.weed.gifts else null
			_check(pg != null and is_instance_valid(pg), "a puppet replays %s" % id)
			if id == &"slowtime":
				_check(Engine.time_scale < 0.5, "a friend's Slow Time doesn't touch our clock twice")
			# End it early (hop off / the gift runs out).
			_events.clear()
			if id == &"cloud":
				_gift.hop_off()
			else:
				_gifts().end_gift(id)
			_puppet.apply_net_event(&"gift_end", [id])
			_next()
		4:
			var id = ORDER[_gi]
			if is_instance_valid(_gift) and _step_t < 15.0:
				return false
			_check(not is_instance_valid(_gift), "%s tidies itself away" % id)
			_check(not _gifts().is_active(id), "%s is over" % id)
			var told := false
			for e in _events:
				if e[0] == &"gift_end" and e[1][0] == id:
					told = true
			_check(told, "ending %s early tells friends" % id)
			match id:
				&"moonjump":
					_check(is_equal_approx(_k.gravity_mod, 1.0) and is_equal_approx(_k.jump_mod, 1.0), "gravity comes back")
				&"slowtime":
					_check(is_equal_approx(Engine.time_scale, 1.0), "the world's clock is back (x%.2f)" % Engine.time_scale)
					_check(is_equal_approx(_k.time_dilation, 1.0), "and the Keling's")
					_check(is_equal_approx(AudioServer.playback_speed_scale, 1.0), "and the sound's")
				&"cloud":
					_check(_k.gift_ride == null, "the Keling is off the cloud")
			_gi += 1
			_step = 1
			_step_t = 0.0
		10:
			# Wait for the puppet's gifts to finish too; nothing may be left over.
			var left := 0
			for g in _puppet.weed.gifts.active.values():
				if is_instance_valid(g):
					left += 1
			if left > 0 and _step_t < 20.0:
				return false
			_check(left == 0, "the puppet's gifts tidy away too")
			_check(is_equal_approx(Engine.time_scale, 1.0), "time runs normally at the end")
			return _finish()
	return false


func _finish() -> bool:
	Engine.time_scale = 1.0
	if _fails.is_empty():
		print("gift_check: PASS")
		quit(0)
	else:
		print("gift_check: FAILED (%d): %s" % [_fails.size(), ", ".join(_fails)])
		quit(1)
	return true
