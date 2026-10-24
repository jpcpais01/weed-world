class_name LoopbackLink
extends RefCounted
## An in-memory stand-in for MqttLink: every LoopbackLink in the process
## shares one pretend broker. Used by tools/net_check.gd to run a host and
## its guests inside a single headless Godot, with no network at all.

signal opened
signal message(topic: String, payload: PackedByteArray)
signal closed(reason: String)

static var _clients: Array = []

var state: int = MqttLink.State.IDLE
var _subs: Array[String] = []
var _inbox: Array = []
var _will_topic := ""
var _will := PackedByteArray()
var _pending_open := false


func open(_url: String, _client_id: String, will_topic := "", will := PackedByteArray()) -> Error:
	_will_topic = will_topic
	_will = will
	state = MqttLink.State.HANDSHAKE
	_pending_open = true
	_clients.append(self)
	return OK


func is_ready() -> bool:
	return state == MqttLink.State.READY


func subscribe(topic: String) -> void:
	if not _subs.has(topic):
		_subs.append(topic)


func publish(topic: String, payload: PackedByteArray) -> void:
	if state == MqttLink.State.READY:
		_route(topic, payload)


func close() -> void:
	_clients.erase(self)
	_finish("closed")


## Drops off the "network" the rude way: the broker sends our last will.
func kill() -> void:
	_clients.erase(self)
	if _will_topic != "" and state == MqttLink.State.READY:
		_route(_will_topic, _will)
	_finish("killed")


func poll() -> void:
	if _pending_open:
		_pending_open = false
		state = MqttLink.State.READY
		opened.emit()
	var batch := _inbox
	_inbox = []
	for m in batch:
		if state != MqttLink.State.READY:
			return
		message.emit(m[0], m[1])


func _finish(reason: String) -> void:
	if state == MqttLink.State.CLOSED:
		return
	state = MqttLink.State.CLOSED
	closed.emit(reason)


static func _route(topic: String, payload: PackedByteArray) -> void:
	for c in _clients:
		if c._subs.has(topic):
			c._inbox.append([topic, payload])
