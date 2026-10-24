class_name RelayPeer
extends MultiplayerPeerExtension
## Godot's high-level multiplayer (RPCs, peer ids, peer_connected...) over a
## shared room on a pub/sub relay, so friends can play together across the
## internet from phones and PCs with no port forwarding and no server of our
## own. Everyone in a room publishes to and listens on one topic; the room
## code picks the topic and the key every frame is sealed with (AES-256), so
## the relay only ever sees noise.
##
## It behaves like a mesh: every Keling hears every other Keling directly
## through the relay, one hop. The host is peer 1 and keeps the guest list:
## guests knock (HELLO), the host answers with the roster (who is in, and
## which of the four colour slots each one has), and everyone adds or drops
## peers from the latest roster. A last will on the relay connection tells
## the room when someone vanishes; a heartbeat catches the rest.

signal room_ready
signal room_failed(reason: String)
signal roster_changed

const PROTOCOL := 1
const MAX_PLAYERS := 4
const PING_EVERY := 1500        ## ms of quiet before we send a heartbeat
const PEER_TIMEOUT := 9000      ## ms of silence before someone counts as gone
const HELLO_EVERY := 900
const JOIN_TIMEOUT := 10000
const MAX_FRAME := 12000        ## bytes of packets batched into one relay message
const EARLY_KEEP := 4000        ## ms to hold packets from someone the roster has not named yet

enum Kind { HELLO = 1, ROSTER = 2, DENY = 3, DATA = 4, BYE = 5, PING = 6 }

## The transport: MqttLink on devices, LoopbackLink in tests.
var link
var code := ""
var topic := ""
## Our own card: {"name", "ver", "proto"}.
var info := {}
var fail_reason := ""
## Round trip to the relay and back, in ms (our own heartbeats echo back).
var rtt := 0

var _host := false
var _id := 0
var _status: int = CONNECTION_CONNECTING
var _peers := {}        # id -> {"slot", "info", "seen", "rtt"}, everyone but us
var _slot := -1
var _key := PackedByteArray()
var _aes := AESContext.new()
var _crypto := Crypto.new()
var _incoming: Array = []
var _current: Array = [0, 0, TRANSFER_MODE_RELIABLE, PackedByteArray()]
var _pending: Array = []
var _pending_bytes := 0
var _early := {}        # id -> [[msec, entries]]
var _admitted := {}     # ids the multiplayer API has been told about
var _joins: Array = []  # ids to announce at the start of the next poll
var _target := 0
var _channel := 0
var _mode: int = TRANSFER_MODE_RELIABLE
var _refuse := false
var _last_sent := 0
var _hello_at := 0
var _started := 0
var _ping_seq := 0
var _ping_sent := {}    # seq -> msec


static func create_host(p_link, p_code: String, p_info: Dictionary) -> RelayPeer:
	var p := RelayPeer.new()
	p._host = true
	p._id = 1
	p._slot = 0
	p._setup(p_link, p_code, p_info)
	return p


static func create_guest(p_link, p_code: String, p_info: Dictionary) -> RelayPeer:
	var p := RelayPeer.new()
	p._id = 2 + (randi() % 0x7FFFFFF0)
	p._setup(p_link, p_code, p_info)
	return p


func _setup(p_link, p_code: String, p_info: Dictionary) -> void:
	link = p_link
	code = p_code
	info = p_info.duplicate()
	info["proto"] = PROTOCOL
	# Kept free of PROTOCOL so an old guest still reaches a new host and
	# hears why it can't come in.
	topic = "weedworld/v1/%s" % _sha("weedworld/room/" + code).slice(0, 12).hex_encode()
	_key = _sha("weedworld/key/%s" % code)
	link.opened.connect(_on_link_opened)
	link.message.connect(_on_link_message)
	link.closed.connect(_on_link_closed)


## Connects to the relay at `url` and opens (host) or knocks on (guest) the room.
func start(url: String) -> Error:
	_started = Time.get_ticks_msec()
	link.subscribe(topic)
	var client_id := "ww%s" % _crypto.generate_random_bytes(8).hex_encode()
	# The last will is a BYE marked "dropped", so friends know to wait for us.
	return link.open(url, client_id, topic, _frame(Kind.BYE, PackedByteArray([0])))


func is_host() -> bool:
	return _host


func slot_of(id: int) -> int:
	if id == _id:
		return _slot
	return _peers[id].slot if _peers.has(id) else -1


func info_of(id: int) -> Dictionary:
	if id == _id:
		return info
	return _peers[id].info if _peers.has(id) else {}


func rtt_of(id: int) -> int:
	if id == _id:
		return rtt
	return _peers[id].rtt if _peers.has(id) else 0


func peer_ids() -> Array:
	return _peers.keys()


func player_count() -> int:
	return _peers.size() + (1 if _status == CONNECTION_CONNECTED else 0)


# --- MultiplayerPeerExtension -------------------------------------------------

func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_max_packet_size() -> int:
	return MAX_FRAME


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	_current = _incoming.pop_front()
	return _current[3]


func _put_packet_script(p_buffer: PackedByteArray) -> Error:
	if _status != CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	# Always name the targets: "everyone" to us is not "everyone" to someone
	# who joined a moment ago and is still catching up.
	var targets: Array = []
	if _target > 0:
		targets = [_target]
	else:
		for id in _admitted:
			if id != -_target:
				targets.append(id)
	# Broadcasts arrive as one put per peer with the same bytes: fold them
	# back into one entry so the relay carries them once.
	if _target > 0 and not _pending.is_empty():
		var last: Array = _pending[-1]
		if not last[0].is_empty() and last[1] == _channel and last[2] == _mode and last[3] == p_buffer:
			last[0].append(_target)
			return OK
	_pending.append([targets, _channel, _mode, p_buffer])
	_pending_bytes += p_buffer.size() + 12
	if _pending_bytes > MAX_FRAME:
		_flush()
	return OK


# The multiplayer API asks who sent the next packet before it takes it, so
# these describe the packet at the front of the queue (like ENet does).
func _get_packet_channel() -> int:
	return _incoming[0][1] if not _incoming.is_empty() else _current[1]


func _get_packet_mode() -> TransferMode:
	return _incoming[0][2] if not _incoming.is_empty() else _current[2]


func _get_packet_peer() -> int:
	return _incoming[0][0] if not _incoming.is_empty() else _current[0]


func _set_transfer_channel(p_channel: int) -> void:
	_channel = p_channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(p_mode: TransferMode) -> void:
	_mode = p_mode


func _get_transfer_mode() -> TransferMode:
	return _mode


func _set_target_peer(p_peer: int) -> void:
	_target = p_peer


func _is_server() -> bool:
	return _host


func _is_server_relay_supported() -> bool:
	return false


func _get_unique_id() -> int:
	return _id


func _get_connection_status() -> ConnectionStatus:
	return _status


func _set_refuse_new_connections(p_enable: bool) -> void:
	_refuse = p_enable


func _is_refusing_new_connections() -> bool:
	return _refuse


func _disconnect_peer(p_peer: int, _p_force: bool) -> void:
	if not _host or not _peers.has(p_peer):
		return
	_publish(Kind.DENY, _deny_body(p_peer, "kicked"))
	_drop(p_peer)


func _close() -> void:
	if _status == CONNECTION_DISCONNECTED:
		return
	if _status == CONNECTION_CONNECTED:
		_flush()
		_publish(Kind.BYE, PackedByteArray([1]))
	_shutdown("left")


func _poll() -> void:
	if link == null:
		return
	# New peers are announced here, outside the relay callbacks, once the
	# multiplayer API has seen us connected; their packets wait until then.
	if not _joins.is_empty() and _status == CONNECTION_CONNECTED:
		var joins := _joins
		_joins = []
		for id in joins:
			if _peers.has(id) and not _admitted.has(id):
				_admitted[id] = true
				peer_connected.emit(id)
				_release_early(id)
	link.poll()
	if _status == CONNECTION_DISCONNECTED:
		return
	var now := Time.get_ticks_msec()
	if _status == CONNECTION_CONNECTING:
		if not _host and link.is_ready() and now - _hello_at > HELLO_EVERY:
			_hello_at = now
			var body := StreamPeerBuffer.new()
			body.put_var(info)
			_publish(Kind.HELLO, body.data_array)
		if now - _started > JOIN_TIMEOUT:
			_fail("No forest answered that code. Check it and try again." if not _host else "Couldn't reach the relay.")
		return
	_flush()
	if now - _last_sent > PING_EVERY:
		_ping_seq += 1
		_ping_sent[_ping_seq] = now
		var body := StreamPeerBuffer.new()
		body.put_u32(_ping_seq)
		body.put_u16(clampi(rtt, 0, 65535))
		_publish(Kind.PING, body.data_array)
	# Anyone gone quiet has left; a quiet host ends the visit.
	for id in _peers.keys():
		if now - (_peers[id].seen as int) > PEER_TIMEOUT:
			if id == 1 or _host:
				_drop(id, "quiet")
	for id in _early.keys():
		_early[id] = (_early[id] as Array).filter(func(e): return now - (e[0] as int) < EARLY_KEEP)
		if (_early[id] as Array).is_empty():
			_early.erase(id)


# --- relay events -------------------------------------------------------------

func _on_link_opened() -> void:
	if _host:
		_status = CONNECTION_CONNECTED
		room_ready.emit()
		roster_changed.emit()


func _on_link_closed(reason: String) -> void:
	if _status == CONNECTION_CONNECTING:
		_fail("Couldn't reach the relay (%s)." % reason)
	else:
		_shutdown("lost the relay: " + reason)


func _on_link_message(_topic: String, payload: PackedByteArray) -> void:
	var plain := _unseal(payload)
	if plain.size() < 8 or plain[0] != 0x57 or plain[1] != 0x57:
		return
	var kind := plain[3]
	var buf := StreamPeerBuffer.new()
	buf.data_array = plain
	buf.seek(4)
	var sender := buf.get_u32()
	if plain[2] != PROTOCOL:
		if _host and kind == Kind.HELLO:
			_publish(Kind.DENY, _deny_body(sender, "version"))
		return
	if sender == _id:
		if kind == Kind.PING:
			var seq := buf.get_u32()
			if _ping_sent.has(seq):
				var sample: int = Time.get_ticks_msec() - _ping_sent[seq]
				rtt = sample if rtt == 0 else int(lerpf(rtt, sample, 0.3))
				_ping_sent.erase(seq)
		return
	if _peers.has(sender):
		_peers[sender].seen = Time.get_ticks_msec()
	match kind:
		Kind.HELLO:
			if _host:
				_on_hello(sender, _var(buf))
		Kind.ROSTER:
			if not _host and sender == 1:
				_apply_roster(_var(buf))
		Kind.DENY:
			if not _host and sender == 1 and buf.get_u32() == _id:
				var why := buf.get_utf8_string()
				if _status == CONNECTION_CONNECTING:
					_fail(_deny_text(why))
				else:
					_shutdown(why)
		Kind.DATA:
			if _status == CONNECTION_CONNECTED:
				_on_data(sender, buf)
		Kind.BYE:
			if _peers.has(sender):
				var clean := buf.get_available_bytes() > 0 and buf.get_u8() == 1
				_drop(sender, "bye" if clean else "quiet")
		Kind.PING:
			buf.get_u32()
			if _peers.has(sender):
				_peers[sender].rtt = buf.get_u16()


func _on_hello(sender: int, card: Variant) -> void:
	if _peers.has(sender):
		_send_roster()
		return
	if typeof(card) != TYPE_DICTIONARY:
		return
	var why := ""
	if _refuse:
		why = "closed"
	elif int(card.get("proto", 0)) != PROTOCOL:
		why = "version"
	elif _peers.size() + 1 >= MAX_PLAYERS:
		why = "full"
	if why != "":
		_publish(Kind.DENY, _deny_body(sender, why))
		return
	var taken := [_slot]
	for id in _peers:
		taken.append(_peers[id].slot)
	var slot := 0
	while slot in taken:
		slot += 1
	_peers[sender] = {"slot": slot, "info": card, "seen": Time.get_ticks_msec(), "rtt": 0}
	_send_roster()
	_joins.append(sender)
	roster_changed.emit()


func _send_roster() -> void:
	var roster := {1: [_slot, info]}
	for id in _peers:
		roster[id] = [_peers[id].slot, _peers[id].info]
	var body := StreamPeerBuffer.new()
	body.put_var(roster)
	_publish(Kind.ROSTER, body.data_array)


func _apply_roster(roster: Variant) -> void:
	if typeof(roster) != TYPE_DICTIONARY or not roster.has(_id):
		return
	var now := Time.get_ticks_msec()
	var first := _status == CONNECTION_CONNECTING
	_slot = int(roster[_id][0])
	if first:
		_status = CONNECTION_CONNECTED
	var changed := first
	for id in _peers.keys():
		if not roster.has(id):
			_drop(id)
			changed = true
	for id in roster:
		var entry: Array = roster[id]
		if id == _id:
			continue
		if _peers.has(id):
			_peers[id].slot = int(entry[0])
			_peers[id].info = entry[1]
			continue
		_peers[id] = {"slot": int(entry[0]), "info": entry[1], "seen": now, "rtt": 0}
		_joins.append(id)
		changed = true
	if first:
		room_ready.emit()
	if changed:
		roster_changed.emit()


func _on_data(sender: int, buf: StreamPeerBuffer) -> void:
	var entries: Array = []
	var count := buf.get_u16()
	for i in count:
		var n := buf.get_u8()
		var mine := false
		for k in n:
			if buf.get_u32() == _id:
				mine = true
		var channel := buf.get_u8()
		var mode := buf.get_u8()
		var size := buf.get_u32()
		if size > buf.get_size() - buf.get_position():
			return
		var data := buf.data_array.slice(buf.get_position(), buf.get_position() + size)
		buf.seek(buf.get_position() + size)
		if mine:
			entries.append([sender, channel, mode, data])
	if entries.is_empty():
		return
	if not _admitted.has(sender):
		# The roster that names them is still on its way: hold on to these.
		if not _early.has(sender):
			_early[sender] = []
		_early[sender].append([Time.get_ticks_msec(), entries])
		return
	_incoming.append_array(entries)


func _release_early(id: int) -> void:
	if _early.has(id):
		for e in _early[id]:
			_incoming.append_array(e[1])
		_early.erase(id)


## `why`: "bye" (they said goodbye or the relay passed on their last will),
## "quiet" (timed out) or "roster" (the host's list no longer has them).
func _drop(id: int, why := "bye") -> void:
	if id == 1 and not _host:
		_shutdown("host left" if why == "bye" else "host lost")
		return
	if not _peers.has(id):
		return
	_peers.erase(id)
	_early.erase(id)
	_joins.erase(id)
	_incoming = _incoming.filter(func(e): return e[0] != id)
	if _admitted.has(id):
		_admitted.erase(id)
		peer_disconnected.emit(id)
	if _host:
		_send_roster()
	roster_changed.emit()


func _fail(reason: String) -> void:
	fail_reason = reason
	_shutdown(reason)
	room_failed.emit(reason)


func _shutdown(reason: String) -> void:
	if _status == CONNECTION_DISCONNECTED:
		return
	if fail_reason == "":
		fail_reason = reason
	var was := _status
	_status = CONNECTION_DISCONNECTED
	if was == CONNECTION_CONNECTED:
		for id in _admitted.keys():
			peer_disconnected.emit(id)
	_peers.clear()
	_admitted.clear()
	_joins.clear()
	_early.clear()
	_incoming.clear()
	_pending.clear()
	if link and link.state != MqttLink.State.CLOSED:
		link.close()
	roster_changed.emit()


static func _deny_text(why: String) -> String:
	match why:
		"full":
			return "That forest is full: four Kelings are already there."
		"version":
			return "Your friend is on a different version. Update the game and try again."
		"closed":
			return "That forest isn't taking visitors right now."
		"kicked":
			return "The host asked you to head home."
	return "The host said no (%s)." % why


# --- frames -------------------------------------------------------------------

func _flush() -> void:
	if _pending.is_empty():
		return
	var body := StreamPeerBuffer.new()
	body.put_u16(_pending.size())
	for p in _pending:
		var targets: Array = p[0]
		body.put_u8(targets.size())
		for t in targets:
			body.put_u32(t)
		body.put_u8(p[1])
		body.put_u8(p[2])
		body.put_u32((p[3] as PackedByteArray).size())
		body.put_data(p[3])
	_pending.clear()
	_pending_bytes = 0
	_publish(Kind.DATA, body.data_array)


func _publish(kind: int, body: PackedByteArray) -> void:
	if link == null or not link.is_ready():
		return
	link.publish(topic, _frame(kind, body))
	_last_sent = Time.get_ticks_msec()


func _frame(kind: int, body: PackedByteArray) -> PackedByteArray:
	var head := StreamPeerBuffer.new()
	head.put_data(PackedByteArray([0x57, 0x57, PROTOCOL, kind]))
	head.put_u32(_id)
	var plain := head.data_array
	plain.append_array(body)
	return _seal(plain)


func _deny_body(id: int, why: String) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(id)
	b.put_utf8_string(why)
	return b.data_array


func _seal(plain: PackedByteArray) -> PackedByteArray:
	var pad := 16 - plain.size() % 16
	for i in pad:
		plain.append(pad)
	var iv := _crypto.generate_random_bytes(16)
	_aes.start(AESContext.MODE_CBC_ENCRYPT, _key, iv)
	var out := iv
	out.append_array(_aes.update(plain))
	_aes.finish()
	return out


func _unseal(data: PackedByteArray) -> PackedByteArray:
	if data.size() < 32 or data.size() % 16 != 0:
		return PackedByteArray()
	_aes.start(AESContext.MODE_CBC_DECRYPT, _key, data.slice(0, 16))
	var plain := _aes.update(data.slice(16))
	_aes.finish()
	var pad := plain[plain.size() - 1]
	if pad < 1 or pad > 16:
		return PackedByteArray()
	return plain.slice(0, plain.size() - pad)


static func _var(buf: StreamPeerBuffer) -> Variant:
	return buf.get_var(false)


static func _sha(s: String) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(s.to_utf8_buffer())
	return ctx.finish()
