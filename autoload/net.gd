extends Node
## Co-op: up to four Kelings exploring the same forest together, on phones
## and PCs, across the internet, with no port forwarding.
##
## Drop-in: you are always in your own forest. "Host" opens it to friends
## and shows a six-letter code; a friend types the code and their Keling
## pops out of a leaf puff next to yours. Every device grows the exact same
## forest from the same seed, so nothing about the world needs sending, only
## the Kelings and what they do to it.
##
## Under the hood this is Godot's high-level multiplayer (peer ids, @rpc)
## over RelayPeer, which tunnels everything through a free public MQTT relay.
## The host is peer 1 and keeps the guest list; Kelings talk to each other
## directly through the relay. The room code picks the relay, the topic and
## the encryption key.
##
## For other systems:
##   Net.online / Net.is_host() / multiplayer.get_unique_id()
##   Net.send_world_event(kind, id, data) -> everyone else gets
##   world_event(kind, id, data, from_peer). world_sync_requested(peer) asks
##   the host to send a late joiner the state of the world.
##   Local Kelings emit net_event / activity_changed; Net replays them on the
##   friend's puppet (apply_net_event / play_remote_activity).

signal status_changed
signal roster_changed
signal player_joined(peer_id: int, display_name: String, slot: int)
signal player_left(peer_id: int, display_name: String, slot: int)
signal notice(text: String, color: Color)
signal world_event(kind: StringName, id: Variant, data: Dictionary, from_peer: int)
signal world_sync_requested(peer_id: int)

enum Status { OFFLINE, CONNECTING, HOSTING, JOINED }

## Public relays, best first. A room lives on one of them; the first letter
## of its code says which, so a guest knows where to knock.
const RELAYS := [
	"wss://broker.emqx.io:8084/mqtt",
	"wss://broker.hivemq.com:8884/mqtt",
	"wss://test.mosquitto.org:8081/mqtt",
	"wss://mqtt.eclipseprojects.io:443/mqtt",
]
## No 0/O, 1/I/L: codes get read out loud and typed on phones.
const CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 6
const SEND_RATE := 15.0
const PROFILE := "user://coop.cfg"
const KELING_SCENE := "res://player/keling.tscn"

const NAME_FIRST := ["Mossy", "Fern", "Pip", "Bramble", "Clover", "Sorrel", "Juniper", "Thistle",
	"Willow", "Hazel", "Puddle", "Sprout", "Nettle", "Bracken", "Tansy", "Rowan", "Mallow", "Basil"]
const NAME_LAST := ["Toes", "Bloom", "Puff", "Root", "Bud", "Leaf", "Wick", "Dew", "Pod", "Sprig",
	"Moss", "Nib", "Tuft", "Burrow", "Seed", "Breeze"]

var status: int = Status.OFFLINE
var online: bool:
	get:
		return status == Status.HOSTING or status == Status.JOINED
var room_code := ""
var last_error := ""
var player_name := ""
## ws://host:port/path to use instead of the public relays (tests, or
## `--relay=` on the command line).
var relay_override := ""
## How long to keep trying to get back into the forest after the connection
## drops (an app switch, a tunnel, a flaky Wi-Fi), in seconds.
const RESUME_FOR := 40.0
const RESUME_EVERY := 3.0

## Makes the transport (MqttLink by default; tests swap in LoopbackLink).
var link_factory: Callable = func(): return MqttLink.new()
## Where to look for the local Keling (defaults to the whole tree).
var world_root: Node

var _peer: RelayPeer
var _hosting := false
var _relay_index := 0
var _puppets := {}           # peer id -> KelingController
var _local: KelingController
var _send_acc := 0.0
var _arrived := true
var _activity: Array = []    # [name, data] of the local Keling's current activity
var _resume_code := ""        # room to get back into after a dropped connection
var _resume_host := false
var _resume_until := 0
var _resume_next := 0
var _resume_relay := 0
var _resuming := false


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_profile()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--relay="):
			relay_override = a.trim_prefix("--relay=")


func _ready() -> void:
	# The multiplayer API's own signals fire once a peer is admitted, so RPCs
	# to them work from inside the handlers.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	world_event.connect(_on_world_event)
	world_sync_requested.connect(_send_world_state)


func _load_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PROFILE)
	player_name = cfg.get_value("profile", "name", "")
	if player_name.strip_edges() == "":
		player_name = random_name()
		save_profile()


func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PROFILE)
	cfg.set_value("profile", "name", player_name)
	cfg.save(PROFILE)


func set_player_name(n: String) -> void:
	n = n.strip_edges().left(18)
	if n == "":
		return
	player_name = n
	save_profile()
	if _local:
		_local.player_name = n


static func random_name() -> String:
	return "%s %s" % [NAME_FIRST.pick_random(), NAME_LAST.pick_random()]


func is_host() -> bool:
	return status == Status.HOSTING


## While connecting: true if we are opening our own forest (not joining).
func is_opening_own() -> bool:
	return _hosting


## True while trying to get back into a forest after the connection dropped.
func is_reconnecting() -> bool:
	return _resume_code != ""


func is_busy() -> bool:
	return status != Status.OFFLINE


## Up to four players: [{id, name, slot, local, ping}] sorted by slot.
func players() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _peer == null or not online:
		out.append({"id": 1, "name": player_name, "slot": 0, "local": true, "ping": 0})
		return out
	var me := multiplayer.get_unique_id()
	out.append({"id": me, "name": player_name, "slot": _peer.slot_of(me), "local": true, "ping": _peer.rtt})
	for id in _peer.peer_ids():
		out.append({"id": id, "name": String(_peer.info_of(id).get("name", "Keling")), "slot": _peer.slot_of(id),
			"local": false, "ping": _peer.rtt_of(id)})
	out.sort_custom(func(a, b): return a.slot < b.slot)
	return out


# --- sessions -------------------------------------------------------------------

## Opens this forest to friends. Watch status_changed; room_code is set once open.
func host() -> void:
	if is_busy():
		return
	_stop_resume()
	_hosting = true
	_relay_index = 0
	last_error = ""
	_open_room()


## Knocks on a friend's forest by its code (any case, spaces and dashes ok).
func join(code: String) -> bool:
	if is_busy():
		return false
	if not _resuming:
		_stop_resume()
	code = normalize_code(code)
	if code.length() != CODE_LENGTH:
		last_error = "Codes are %d letters and numbers." % CODE_LENGTH
		status_changed.emit()
		return false
	_hosting = false
	last_error = ""
	room_code = code
	_relay_index = CODE_ALPHABET.find(code[0]) % RELAYS.size()
	var peer := RelayPeer.create_guest(link_factory.call(), code, _card())
	_begin(peer)
	return true


func leave() -> void:
	_stop_resume()
	if is_busy():
		_end("left")
	status_changed.emit()


static func normalize_code(code: String) -> String:
	var out := ""
	for ch in code.to_upper():
		if CODE_ALPHABET.contains(ch):
			out += ch
	return out.left(CODE_LENGTH)


## "K7M2QX" -> "K7M-2QX"
static func pretty_code(code: String) -> String:
	return code.left(3) + "-" + code.substr(3) if code.length() == CODE_LENGTH else code


func _open_room(code := "") -> void:
	room_code = code if code != "" else _new_code(_relay_index)
	var peer := RelayPeer.create_host(link_factory.call(), room_code, _card())
	_begin(peer)


func _new_code(relay: int) -> String:
	var code := ""
	while true:
		code = ""
		for i in CODE_LENGTH:
			code += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
		if CODE_ALPHABET.find(code[0]) % RELAYS.size() == relay:
			return code
	return code


func _card() -> Dictionary:
	return {"name": player_name, "ver": str(ProjectSettings.get_setting("application/config/version", "0"))}


func _relay_url() -> String:
	return relay_override if relay_override != "" else RELAYS[_relay_index]


func _begin(peer: RelayPeer) -> void:
	_peer = peer
	status = Status.CONNECTING
	peer.room_ready.connect(_on_room_ready)
	peer.room_failed.connect(_on_room_failed.bind(peer))
	peer.roster_changed.connect(_on_roster_changed)
	multiplayer.multiplayer_peer = peer
	var err := peer.start(_relay_url())
	status_changed.emit()
	if err != OK:
		_on_room_failed("Couldn't open a connection (%s)." % error_string(err), peer)


func _on_room_ready() -> void:
	status = Status.HOSTING if _hosting else Status.JOINED
	var resumed := _resume_code != ""
	_arrived = _hosting or resumed
	_stop_resume()
	_bind_local()
	if _local:
		_local.peer_id = multiplayer.get_unique_id()
		_local.set_player(_peer.slot_of(_local.peer_id), player_name)
	if resumed:
		notice.emit("Reconnected", HudTheme.LEAF)
	elif _hosting:
		notice.emit("Your forest is open · code %s" % pretty_code(room_code), HudTheme.LEAF)
	else:
		notice.emit("You joined %s's forest" % _host_name(), HudTheme.LEAF)
	status_changed.emit()
	roster_changed.emit()


func _on_room_failed(reason: String, peer: RelayPeer) -> void:
	if peer != _peer:
		return
	# A host can simply try the next relay with a fresh code (not while
	# reopening a room friends already know the code of).
	if _hosting and _resume_code == "" and relay_override == "" and _relay_index < RELAYS.size() - 1 and status == Status.CONNECTING:
		_relay_index += 1
		_detach()
		_open_room()
		return
	_end(reason)


func _on_roster_changed() -> void:
	if _peer and _local and online:
		var slot := _peer.slot_of(multiplayer.get_unique_id())
		if slot >= 0 and slot != _local.player_index:
			_local.set_player(slot, player_name)
	for id in _puppets:
		var p: KelingController = _puppets[id]
		var slot := _peer.slot_of(id) if _peer else -1
		var nm := String(_peer.info_of(id).get("name", p.player_name)) if _peer else p.player_name
		if slot >= 0 and (slot != p.player_index or nm != p.player_name):
			p.set_player(slot, nm)
	roster_changed.emit()


func _end(reason: String) -> void:
	var was_online := online
	var was_host := _hosting
	var code := room_code
	for id in _puppets.keys():
		_despawn(id, true)
	_detach()
	status = Status.OFFLINE
	room_code = ""
	_arrived = true
	if _local and is_instance_valid(_local):
		_local.peer_id = 1
		_local.set_player(0, player_name)
	# A dropped connection (not a goodbye): quietly keep trying to get back.
	var dropped := reason.begins_with("lost the relay") or reason == "host lost" or reason.begins_with("Couldn't reach")
	if _resume_code != "" and Time.get_ticks_msec() < _resume_until:
		status_changed.emit()
		return
	if dropped and was_online and code != "":
		_resume_code = code
		_resume_host = was_host
		_resume_relay = _relay_index
		_resume_until = Time.get_ticks_msec() + int(RESUME_FOR * 1000.0)
		_resume_next = Time.get_ticks_msec() + 1500
		notice.emit("Connection lost · reconnecting…", HudTheme.GOLD)
		status_changed.emit()
		roster_changed.emit()
		return
	if _resume_code != "":
		_stop_resume()
		reason = "Couldn't reconnect"
		was_online = true
		was_host = false
	if reason != "" and reason != "left":
		last_error = _friendly(reason)
		if was_online and not was_host:
			notice.emit("%s · back in your own forest" % last_error, HudTheme.BLOSSOM)
	elif was_online:
		notice.emit("Back in your own forest" if not was_host else "Your forest is closed to visitors", HudTheme.CREAM)
	status_changed.emit()
	roster_changed.emit()


func _stop_resume() -> void:
	_resume_code = ""
	_resume_until = 0


func _try_resume() -> void:
	if _resume_code == "" or is_busy() or Time.get_ticks_msec() < _resume_next:
		return
	if Time.get_ticks_msec() > _resume_until:
		_end("gave up")
		return
	_resume_next = Time.get_ticks_msec() + int(RESUME_EVERY * 1000.0)
	_resuming = true
	if _resume_host:
		_hosting = true
		_relay_index = _resume_relay
		_open_room(_resume_code)
	else:
		join(_resume_code)
	_resuming = false


func _detach() -> void:
	var peer := _peer
	_peer = null
	if peer:
		peer.room_ready.disconnect(_on_room_ready)
		peer.roster_changed.disconnect(_on_roster_changed)
		for c in peer.room_failed.get_connections():
			peer.room_failed.disconnect(c.callable)
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


static func _friendly(reason: String) -> String:
	if reason == "host left":
		return "The host headed home"
	if reason.begins_with("lost the relay"):
		return "Lost the connection"
	return reason


func _host_name() -> String:
	return String(_peer.info_of(1).get("name", "your friend")) if _peer else "your friend"


# --- Kelings ----------------------------------------------------------------------

func _bind_local() -> void:
	var found: KelingController = null
	for n in get_tree().get_nodes_in_group("local_player"):
		var k := n as KelingController
		if k and (world_root == null or world_root.is_ancestor_of(k)):
			found = k
			break
	if found == _local:
		return
	if _local and is_instance_valid(_local):
		for pair in _local_hooks():
			if _local.is_connected(pair[0], pair[1]):
				_local.disconnect(pair[0], pair[1])
	_local = found
	if _local == null:
		return
	_local.player_name = player_name
	for pair in _local_hooks():
		if _local.has_signal(pair[0]):
			_local.connect(pair[0], pair[1])


func _local_hooks() -> Array:
	return [
		[&"net_event", _on_local_event],
		[&"jumped", _on_local_jumped],
		[&"landed", _on_local_landed],
		[&"activity_changed", _on_local_activity],
	]


func _on_local_event(kind: StringName, args: Array) -> void:
	if online:
		_keling_event.rpc(kind, args)


func _on_local_jumped() -> void:
	_on_local_event(&"jump", [])


func _on_local_landed(impact: float, kind: StringName) -> void:
	_on_local_event(&"land", [impact, kind])


func _on_local_activity(activity: StringName, data: Dictionary) -> void:
	_activity = [] if activity == &"idle" or activity == &"" else [activity, data]
	_on_local_event(&"activity", [activity, data])


func _on_peer_connected(id: int) -> void:
	if _peer == null:
		return
	_bind_local()
	_spawn(id)
	var nm := String(_peer.info_of(id).get("name", "A Keling"))
	var slot := _peer.slot_of(id)
	# Catch the newcomer up on what we're doing right now.
	if _local:
		var bench := _local.current_bench_id()
		if bench != "":
			_keling_event.rpc_id(id, &"seat", [bench, _local.current_seat()])
		if not _activity.is_empty():
			_keling_event.rpc_id(id, &"activity", _activity)
		_state.rpc_id(id, KelingSync.pack(_local))
	if is_host():
		world_sync_requested.emit(id)
	if status != Status.CONNECTING:
		var them := String(_peer.info_of(id).get("ver", ""))
		var us := str(ProjectSettings.get_setting("application/config/version", ""))
		var extra := "" if them == us or them == "" else "  (on v%s)" % them
		notice.emit("%s joined the forest%s" % [nm, extra], HudTheme.PLAYER_COLORS[clampi(slot, 0, 3)])
	player_joined.emit(id, nm, slot)


func _on_peer_disconnected(id: int) -> void:
	var p: KelingController = _puppets.get(id)
	var nm := p.player_name if p else "A Keling"
	var slot := p.player_index if p else 0
	_despawn(id, false)
	# When the whole visit ends, _end() says so once instead.
	if _peer and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		notice.emit("%s headed home" % nm, Color(HudTheme.CREAM, 0.9))
	player_left.emit(id, nm, slot)


func _spawn(id: int) -> void:
	if _puppets.has(id) or _local == null or not is_instance_valid(_local):
		return
	var scene := load(KELING_SCENE) as PackedScene
	var k := scene.instantiate() as KelingController
	k.name = "Keling_%d" % id
	k.make_remote(id, _peer.slot_of(id), String(_peer.info_of(id).get("name", "Keling")))
	# Out of sight until the first snapshot puts it in place.
	k.position = _local.global_position + Vector3(0, -50, 0)
	k.visible = false
	_local.get_parent().add_child(k)
	_puppets[id] = k


func _despawn(id: int, quiet: bool) -> void:
	var k: KelingController = _puppets.get(id)
	_puppets.erase(id)
	if k == null or not is_instance_valid(k):
		return
	k.apply_net_event(&"unseat", [])
	if not quiet and k.visible:
		# Leave a little puff of leaves where they stood.
		var puff := k.leaf_puff
		if puff:
			puff.reparent(k.get_parent())
			puff.restart()
			puff.emitting = true
			get_tree().create_timer(2.0).timeout.connect(puff.queue_free)
	k.queue_free()


func puppet(id: int) -> KelingController:
	return _puppets.get(id)


func _physics_process(delta: float) -> void:
	_try_resume()
	if _peer and status != Status.CONNECTING and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_end(_peer.fail_reason if _peer.fail_reason != "" else "lost the relay")
		return
	if not online:
		return
	if _local == null or not is_instance_valid(_local):
		_local = null
		_bind_local()
		if _local == null:
			return
	_send_acc += delta
	if _send_acc >= 1.0 / SEND_RATE:
		_send_acc = fmod(_send_acc, 1.0 / SEND_RATE)
		_state.rpc(KelingSync.pack(_local))
	if not _arrived:
		_try_arrive()


## A guest's Keling hops over to the host as soon as we know where they are.
func _try_arrive() -> void:
	var host: KelingController = _puppets.get(1)
	if host == null or not host.remote.has_data():
		return
	_arrived = true
	var h: Dictionary = host.remote.latest()
	var hp: Vector3 = h.pos
	var angle: float = h.facing + PI * 0.5 + _local.player_index * 0.9
	var pos := hp + Vector3(sin(angle), 0.0, cos(angle)) * 1.4
	var forest := _find_forest()
	if forest:
		pos.y = maxf(forest.ground_height(pos.x, pos.z), hp.y - 1.0) + 0.05
	var to := hp - pos
	_local.arrive_at(pos, atan2(to.x, to.z))


func _find_forest() -> Node:
	var n := _local.get_parent() if _local else null
	while n:
		var f := n.get_node_or_null("Forest")
		if f and f.has_method("ground_height"):
			return f
		n = n.get_parent()
	return null


# --- the shared forest -----------------------------------------------------------

## What friends did to the forest, applied here: picked buds pop off their
## plants, Bloom Trail makes plants burst back into bud.
func _on_world_event(kind: StringName, id: Variant, data: Dictionary, _from: int) -> void:
	var forest := _find_forest()
	var weed = forest.get("weed") if forest else null
	if weed == null:
		return
	match kind:
		&"weed_picked":
			_remote_pick(weed, int(id))
		&"weed_ripened":
			var plant = weed.plant_by_index(int(id))
			if plant:
				plant.ripen_all()
		&"weed_state":
			for bid in data.get("picked", []):
				_remote_pick(weed, int(bid))


func _remote_pick(weed, id: int) -> void:
	var bud = weed.bud_by_id(id)
	if bud and bud.ripe:
		bud.apply_remote_pick()


## Host: tells a newcomer which buds have been picked lately.
func _send_world_state(peer_id: int) -> void:
	var forest := _find_forest()
	var weed = forest.get("weed") if forest else null
	if weed == null:
		return
	var picked: Array[int] = []
	for plant in weed.nodes:
		for bud in plant.buds:
			if not bud.ripe:
				picked.append(bud.net_id)
	if not picked.is_empty():
		send_world_event_to(peer_id, &"weed_state", 0, {"picked": picked})


# --- wire -------------------------------------------------------------------------

@rpc("any_peer", "unreliable_ordered", "call_remote", 1)
func _state(bytes: PackedByteArray) -> void:
	var k: KelingController = _puppets.get(multiplayer.get_remote_sender_id())
	if k == null:
		return
	k.remote.push(bytes)
	if not k.visible:
		k.visible = true
		k.apply_net_event(&"land", [6.0])  # pop in with a leaf puff


@rpc("any_peer", "reliable", "call_remote", 0)
func _keling_event(kind: StringName, args: Array) -> void:
	var k: KelingController = _puppets.get(multiplayer.get_remote_sender_id())
	if k == null:
		return
	if kind == &"activity":
		if k.has_method("play_remote_activity") and args.size() >= 2:
			k.play_remote_activity(args[0], args[1])
		return
	k.apply_net_event(kind, args)


## Tells everyone else something happened to the world (a bud picked...).
func send_world_event(kind: StringName, id: Variant, data := {}) -> void:
	if online:
		_world.rpc(kind, id, data)


## The same, to one player (the host catching up a late joiner).
func send_world_event_to(peer_id: int, kind: StringName, id: Variant, data := {}) -> void:
	if online and peer_id != multiplayer.get_unique_id():
		_world.rpc_id(peer_id, kind, id, data)


@rpc("any_peer", "reliable", "call_remote", 0)
func _world(kind: StringName, id: Variant, data: Dictionary) -> void:
	world_event.emit(kind, id, data, multiplayer.get_remote_sender_id())
