extends SceneTree
## Headless co-op check: a host and four guests in one process, each with its
## own Net, multiplayer API and Keling, talking through LoopbackLink (an
## in-memory relay). Walks through hosting, joining, puppets following,
## world events, the four-player cap, leaving, a dropped connection and the
## host closing up. Exits non-zero on failure.
##   godot --headless --path . -s res://tools/net_check.gd

# Loaded at run time: the Keling's scripts name autoloads, which only exist
# once the tree is up.
var NetScript: GDScript
var KELING: PackedScene
var _fails := 0
var _worlds: Array = []
var _events: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _world(tag: String, x: float) -> Dictionary:
	var branch := Node3D.new()
	branch.name = "World" + tag
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position.y = -0.5
	floor.add_child(shape)
	branch.add_child(floor)
	var keling = KELING.instantiate()
	keling.name = "Keling"
	keling.position = Vector3(x, 0.05, 0)
	branch.add_child(keling)
	var net = NetScript.new()
	net.name = "Net"
	net.world_root = branch
	net.link_factory = func(): return load("res://net/loopback_link.gd").new()
	branch.add_child(net)
	net.player_name = "Keling " + tag
	net.world_event.connect(func(kind, id, data, from): _events.append([tag, kind, id, data, from]))
	var w := {"tag": tag, "branch": branch, "net": net, "keling": keling}
	_worlds.append(w)
	return w


func _check(ok: bool, what: String) -> void:
	print("net_check: %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _until(cond: Callable, timeout := 5.0) -> bool:
	var start := Time.get_ticks_msec()
	while not cond.call():
		await process_frame
		if Time.get_ticks_msec() - start > timeout * 1000.0:
			return false
	return true


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


const S := {"OFFLINE": 0, "CONNECTING": 1, "HOSTING": 2, "JOINED": 3}


func _run() -> void:
	NetScript = load("res://autoload/net.gd")
	KELING = load("res://player/keling.tscn")
	var a := _world("A", 0.0)
	var b := _world("B", 20.0)
	var c := _world("C", -20.0)
	await _wait(0.3)

	# Host.
	a.net.host()
	_check(await _until(func(): return a.net.status == S.HOSTING), "host opens a room")
	var code: String = a.net.room_code
	_check(code.length() == 6 and NetScript.normalize_code(NetScript.pretty_code(code).to_lower()) == code, "room code %s round-trips" % NetScript.pretty_code(code))

	# Guest B joins and pops up next to the host.
	a.keling.global_position = Vector3(3, 0.05, 4)
	b.net.join(NetScript.pretty_code(code).to_lower())
	_check(await _until(func(): return b.net.status == S.JOINED), "guest joins by code")
	var a_id := 1
	var b_id: int = b.branch.multiplayer.get_unique_id()
	_check(await _until(func(): return a.net.puppet(b_id) != null and b.net.puppet(a_id) != null), "both sides spawn a puppet")
	_check(await _until(func(): return (b.keling.global_position as Vector3).distance_to(a.keling.global_position) < 2.5), "guest arrives beside the host")
	_check(b.keling.player_index == 1 and a.keling.player_index == 0, "colour slots host 0, guest 1")

	# Puppets follow.
	a.keling.global_position = Vector3(6, 0.05, -2)
	_check(await _until(func(): return (b.net.puppet(a_id).global_position as Vector3).distance_to(Vector3(6, 0, -2)) < 0.4), "guest sees the host move")
	var p = a.net.puppet(b_id)
	_check(p.visible and p.player_name == "Keling B" and not p.is_local and p.get_node_or_null("CameraRig") == null, "puppet has name, no camera")
	_check(load("res://ui/map/map_state.gd").players(self).size() >= 2, "map lists the Kelings")

	# Third guest.
	c.net.join(code)
	_check(await _until(func(): return c.net.status == S.JOINED), "second guest joins")
	var c_id: int = c.branch.multiplayer.get_unique_id()
	_check(await _until(func(): return b.net.puppet(c_id) != null and c.net.puppet(b_id) != null and c.net.puppet(a_id) != null), "guests see each other")
	var slots := {}
	for w in [a, b, c]:
		slots[w.keling.player_index] = true
	_check(slots.size() == 3, "three distinct colour slots")

	# Keling events and world events.
	var host_k = a.keling
	host_k.net_event.emit(&"grab", [host_k.global_position + Vector3(0, 0.5, 0.4), true, true])
	_check(await _until(func(): return b.net.puppet(a_id).grab.grabbing and c.net.puppet(a_id).grab.grabbing), "grab replays on every puppet")
	_events.clear()
	b.net.send_world_event(&"weed_picked", 42, {"strain": "test"})
	_check(await _until(func(): return _events.size() >= 2), "world event reaches everyone else")
	var good := true
	for e in _events:
		good = good and e[0] != "B" and e[1] == &"weed_picked" and e[2] == 42 and e[4] == b_id
	_check(good, "world event carries kind, id and sender")

	# Fourth player fits, fifth is turned away.
	var d := _world("D", 40.0)
	var e := _world("E", -40.0)
	await _wait(0.2)
	d.net.join(code)
	_check(await _until(func(): return d.net.status == S.JOINED), "fourth player joins")
	e.net.join(code)
	_check(await _until(func(): return e.net.status == S.OFFLINE and e.net.last_error.contains("full")), "fifth player is told it's full")
	_check(a.net.players().size() == 4, "host counts four players")

	# Leaving politely.
	c.net.leave()
	_check(await _until(func(): return a.net.puppet(c_id) == null and b.net.puppet(c_id) == null and d.net.puppet(c_id) == null), "a guest leaves and everyone drops them")

	# Dropping off the network (app killed): the relay's last will says goodbye.
	var d_id: int = d.branch.multiplayer.get_unique_id()
	d.net._peer.link.kill()
	_check(await _until(func(): return a.net.puppet(d_id) == null and b.net.puppet(d_id) == null), "a vanished guest is dropped")
	_check(await _until(func(): return d.net.status == S.OFFLINE), "the vanished guest goes back offline")

	# Wrong code: nobody answers.
	e.net.join("ZZZ-ZZZ")
	_check(await _until(func(): return e.net.status == S.OFFLINE and e.net.last_error != "", 14.0), "a wrong code times out kindly")

	# Host closes the forest.
	a.net.leave()
	_check(await _until(func(): return b.net.status == S.OFFLINE), "guests go home when the host leaves")
	_check(b.net.puppet(a_id) == null and b.keling.player_index == 0, "back to a solo forest")
	_check(a.net.status == S.OFFLINE, "host is offline")

	# Snapshot round trip.
	var Sync: GDScript = load("res://player/keling_sync.gd")
	var bytes: PackedByteArray = Sync.pack(host_k)
	var sync = Sync.new()
	sync.push(bytes)
	var s: Dictionary = sync.sample()
	_check(bytes.size() < 48 and (s.pos as Vector3).distance_to(host_k.global_position) < 0.01, "snapshot is %d bytes and decodes" % bytes.size())

	print("net_check: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	quit(0 if _fails == 0 else 1)
