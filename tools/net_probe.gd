extends SceneTree
## Tries every public relay co-op can use: opens a room on it, joins that
## room from a second connection and times the round trip. Informational
## (CI keeps going if a relay is down); always exits 0.
##   godot --headless --path . -s res://tools/net_probe.gd [-- --relay=wss://...]

const TIMEOUT := 15000


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var relays: Array = load("res://autoload/net.gd").RELAYS.duplicate()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--relay="):
			relays = [a.trim_prefix("--relay=")]
	var ok := 0
	for url in relays:
		var line := await _probe(url)
		print("net_probe: %s  %s" % [url, line])
		if line.begins_with("OK"):
			ok += 1
	print("net_probe: %d of %d relays work" % [ok, relays.size()])
	quit(0)


func _probe(url: String) -> String:
	var Peer: GDScript = load("res://net/relay_peer.gd")
	var Link: GDScript = load("res://net/mqtt_link.gd")
	var code := "PROBE%d" % (randi() % 10)
	var host = Peer.create_host(Link.new(), code + str(randi()), {"name": "probe host"})
	var guest = Peer.create_guest(Link.new(), host.code, {"name": "probe guest"})
	var t0 := Time.get_ticks_msec()
	host.start(url)
	while host.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING and Time.get_ticks_msec() - t0 < TIMEOUT:
		host.poll()
		await process_frame
	if host.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return "FAIL host: %s" % host.fail_reason
	var open_ms := Time.get_ticks_msec() - t0
	var t1 := Time.get_ticks_msec()
	guest.start(url)
	while guest.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING and Time.get_ticks_msec() - t1 < TIMEOUT:
		host.poll()
		guest.poll()
		await process_frame
	if guest.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		host.close()
		return "FAIL join: %s" % guest.fail_reason
	var join_ms := Time.get_ticks_msec() - t1
	# Let a few heartbeats echo back for the round trip.
	var t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 5000:
		host.poll()
		guest.poll()
		await process_frame
	var out := "OK  open %d ms, join %d ms, round trip host %d ms / guest %d ms" % [open_ms, join_ms, host.rtt, guest.rtt]
	guest.close()
	host.close()
	return out
