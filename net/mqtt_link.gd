class_name MqttLink
extends RefCounted
## A tiny MQTT 3.1.1 client over (secure) WebSockets: just enough to open a
## connection to a public broker, subscribe to one room topic, publish to it
## and hear everyone else on it. QoS 0 only: it all rides one TCP stream, so
## messages from one sender arrive in order and none go missing while the
## socket lives. A "last will" lets the broker say goodbye for us if the app
## is killed or the phone loses signal. Co-op runs on top (see RelayPeer).

signal opened
signal message(topic: String, payload: PackedByteArray)
signal closed(reason: String)

enum State { IDLE, SOCKET, HANDSHAKE, READY, CLOSED }

const KEEPALIVE := 20          ## seconds; the broker drops us after 1.5x silence
const OPEN_TIMEOUT := 7.0      ## seconds to get from nothing to CONNACK

var url := ""
var state: int = State.IDLE

var _ws := WebSocketPeer.new()
var _buf := PackedByteArray()
var _client_id := ""
var _will_topic := ""
var _will := PackedByteArray()
var _subs: Array[String] = []
var _next_packet_id := 1
var _opened_at := 0
var _last_send := 0
var _last_recv := 0


## Starts connecting. `will` is published to `will_topic` by the broker if we
## vanish without a clean close.
func open(p_url: String, client_id: String, will_topic := "", will := PackedByteArray()) -> Error:
	url = p_url
	_client_id = client_id
	_will_topic = will_topic
	_will = will
	_ws.supported_protocols = PackedStringArray(["mqtt"])
	_ws.inbound_buffer_size = 1 << 18
	_ws.outbound_buffer_size = 1 << 18
	_ws.max_queued_packets = 4096
	var tls: TLSOptions = TLSOptions.client() if url.begins_with("wss") else null
	var err := _ws.connect_to_url(url, tls)
	if err != OK:
		state = State.CLOSED
		return err
	state = State.SOCKET
	_opened_at = Time.get_ticks_msec()
	return OK


func is_ready() -> bool:
	return state == State.READY


func subscribe(topic: String) -> void:
	if not _subs.has(topic):
		_subs.append(topic)
	if state == State.READY:
		_send_subscribe(topic)


func publish(topic: String, payload: PackedByteArray) -> void:
	if state != State.READY:
		return
	var body := _str(topic)
	body.append_array(payload)
	_send(0x30, body)


## Clean goodbye: the broker discards the last will.
func close() -> void:
	if state == State.READY:
		_send(0xE0, PackedByteArray())
	if state != State.CLOSED and state != State.IDLE:
		_ws.close(1000, "bye")
	_finish("closed")


## Drops the connection without a goodbye, as if the app were killed: the
## broker publishes our last will. (Used by tools/net_check.gd.)
func kill() -> void:
	if state != State.CLOSED and state != State.IDLE:
		_ws.close()
	_finish("killed")


func poll() -> void:
	if state == State.IDLE or state == State.CLOSED:
		return
	_ws.poll()
	var now := Time.get_ticks_msec()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if state == State.SOCKET:
				_send_connect()
				state = State.HANDSHAKE
			while _ws.get_available_packet_count() > 0:
				_buf.append_array(_ws.get_packet())
				_last_recv = now
			_parse()
		WebSocketPeer.STATE_CLOSED:
			var why := _ws.get_close_reason()
			_finish("socket closed (%d%s)" % [_ws.get_close_code(), (": " + why) if why != "" else ""])
			return
	if state != State.READY and now - _opened_at > OPEN_TIMEOUT * 1000.0:
		_ws.close()
		_finish("timed out")
		return
	if state == State.READY:
		if now - _last_send > KEEPALIVE * 500:
			_send(0xC0, PackedByteArray())
		if now - _last_recv > KEEPALIVE * 2000:
			_ws.close()
			_finish("broker went quiet")


func _finish(reason: String) -> void:
	if state == State.CLOSED:
		return
	state = State.CLOSED
	closed.emit(reason)


# --- wire format ------------------------------------------------------------

func _send_connect() -> void:
	var body := _str("MQTT")
	body.append(4)  # protocol level 3.1.1
	var flags := 0x02  # clean session
	if _will_topic != "":
		flags |= 0x04
	body.append(flags)
	body.append(KEEPALIVE >> 8)
	body.append(KEEPALIVE & 0xFF)
	body.append_array(_str(_client_id))
	if _will_topic != "":
		body.append_array(_str(_will_topic))
		body.append(_will.size() >> 8)
		body.append(_will.size() & 0xFF)
		body.append_array(_will)
	_send(0x10, body)


func _send_subscribe(topic: String) -> void:
	var body := PackedByteArray([_next_packet_id >> 8, _next_packet_id & 0xFF])
	_next_packet_id = _next_packet_id % 65535 + 1
	body.append_array(_str(topic))
	body.append(0)  # QoS 0
	_send(0x82, body)


func _send(header: int, body: PackedByteArray) -> void:
	var pkt := PackedByteArray([header])
	var n := body.size()
	while true:
		var b := n & 0x7F
		n >>= 7
		pkt.append(b | (0x80 if n > 0 else 0))
		if n == 0:
			break
	pkt.append_array(body)
	_ws.send(pkt, WebSocketPeer.WRITE_MODE_BINARY)
	_last_send = Time.get_ticks_msec()


## Splits the byte stream into MQTT packets (a WebSocket frame may hold
## several, or half of one).
func _parse() -> void:
	var at := 0
	while _buf.size() - at >= 2:
		var header := _buf[at]
		var length := 0
		var mul := 1
		var i := at + 1
		var complete := false
		while i < _buf.size() and i < at + 5:
			var b := _buf[i]
			length += (b & 0x7F) * mul
			mul *= 128
			i += 1
			if b & 0x80 == 0:
				complete = true
				break
		if not complete or _buf.size() - i < length:
			break
		_handle(header, _buf.slice(i, i + length))
		at = i + length
		if state == State.CLOSED:
			return
	if at > 0:
		_buf = _buf.slice(at)


func _handle(header: int, body: PackedByteArray) -> void:
	match header >> 4:
		2:  # CONNACK
			if body.size() >= 2 and body[1] == 0:
				state = State.READY
				for t in _subs:
					_send_subscribe(t)
				opened.emit()
			else:
				_ws.close()
				_finish("broker refused (%d)" % (body[1] if body.size() >= 2 else -1))
		3:  # PUBLISH
			if body.size() < 2:
				return
			var tlen := (body[0] << 8) | body[1]
			var start := 2 + tlen
			if (header >> 1) & 0x03 > 0:
				start += 2  # packet id (we only ask for QoS 0, but be safe)
			if start > body.size():
				return
			message.emit(body.slice(2, 2 + tlen).get_string_from_utf8(), body.slice(start))
		9, 13:  # SUBACK, PINGRESP
			pass


static func _str(s: String) -> PackedByteArray:
	var b := s.to_utf8_buffer()
	var out := PackedByteArray([b.size() >> 8, b.size() & 0xFF])
	out.append_array(b)
	return out
