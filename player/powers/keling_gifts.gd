class_name KelingGifts
extends Node
## A Keling's smoke gifts (SmokeGifts): each puff of a joint gives a charge
## of its strain's gift, and the Gift button breathes one out. Charges last
## as long as the high; a puff of another strain swaps the gift over.
##
## Every cast is a SmokeGift node under the Keling. Casting a gift that is
## still going refreshes it (with a fresh burst) instead of stacking a second.
## The caster's game plans the cast (seed, target...) and tells the others,
## whose puppets play the same cast for show.

signal charged(gift: StringName, charges: int)
signal cast_gift(gift: StringName, boosted: bool)
signal gift_ended(gift: StringName)

var keling: KelingController
var weed: KelingWeed
var local := true
var ready_gift: StringName = &""
var charges := 0
var boosted := false      ## the charges came from a bench whose view matches
var active := {}          ## gift id -> SmokeGift


func setup(p_keling: KelingController, p_weed: KelingWeed) -> void:
	keling = p_keling
	weed = p_weed
	name = "Gifts"
	weed.puffed.connect(_on_puffed)


func _ready() -> void:
	local = weed.local
	if weed.high:
		weed.high.ended.connect(_on_high_ended)


func _process(_delta: float) -> void:
	if local:
		keling.gift_armed = charges > 0


## A puff went down: a charge of this joint's gift.
func _on_puffed(element: StringName, _left: int) -> void:
	if not local:
		return
	var gift := SmokeGifts.of_strain(weed.joint_strain)
	if gift == &"":
		return
	var match_view := element != &"none" and element == SmokeGifts.info(gift).element
	if gift != ready_gift:
		charges = 0
		boosted = false
	ready_gift = gift
	charges = mini(charges + 1, SmokeGifts.MAX_CHARGES)
	boosted = boosted or match_view
	charged.emit(gift, charges)


func _on_high_ended() -> void:
	if charges > 0:
		charges = 0
		charged.emit(ready_gift, 0)


## True while a gift can be breathed out right now.
func can_cast() -> bool:
	if charges <= 0 or ready_gift == &"":
		return false
	if keling.mode == KelingController.Mode.MORPH:
		return false
	if weed.act == KelingWeed.Act.ROLL:
		return false
	return true


## Why the button does nothing (for a toast), or "" when it works.
func cant_cast_reason() -> String:
	if charges <= 0:
		if weed.has_joint():
			return "Take a puff to charge its gift"
		return "Smoke a joint: every strain carries a gift"
	if keling.mode == KelingController.Mode.MORPH:
		return "Hold on, you're changing"
	if weed.act == KelingWeed.Act.ROLL:
		return "Finish rolling first"
	return ""


## The Gift button.
func cast() -> bool:
	if not local:
		return false
	if not can_cast():
		var why := cant_cast_reason()
		if why != "":
			weed.note.emit(why)
		return false
	var gift := ready_gift
	charges -= 1
	charged.emit(gift, charges)
	var data := {"gift": gift, "seed": randi(), "boost": boosted, "pos": keling.global_position, "yaw": keling.facing}
	var g := _begin(gift, data)
	if g:
		data.merge(g.plan(), true)
		g.launch(data)
	# Friends see it too (not replayed to late joiners: it's over soon).
	keling.net_event.emit(&"gift", [data])
	cast_gift.emit(gift, boosted)
	return true


## Co-op: a friend breathed a gift; play it on their puppet here.
func play_remote(data: Dictionary) -> void:
	var gift := StringName(data.get("gift", &""))
	if not SmokeGifts.valid(gift):
		return
	var g := _begin(gift, data)
	if g:
		g.launch(data)


## Co-op: a friend's gift ended early (hopped off the cloud...).
func end_remote(gift: StringName) -> void:
	var g: SmokeGift = active.get(gift)
	if g and is_instance_valid(g):
		g.end()


## Ends a running gift early (the local one tells the others).
func end_gift(gift: StringName) -> void:
	var g: SmokeGift = active.get(gift)
	if g and is_instance_valid(g):
		g.end()


func is_active(gift: StringName) -> bool:
	var g: SmokeGift = active.get(gift)
	return g != null and is_instance_valid(g) and not g.ending


## The running gift with the most time left (for the HUD), or null.
func current() -> SmokeGift:
	var best: SmokeGift = null
	for id in active:
		var g: SmokeGift = active[id]
		if g and is_instance_valid(g) and not g.ending and (best == null or g.remaining() > best.remaining()):
			best = g
	return best


func _begin(gift: StringName, data: Dictionary) -> SmokeGift:
	var boost := SmokeGifts.BOOST if bool(data.get("boost", false)) else 1.0
	var old: SmokeGift = active.get(gift)
	if old and is_instance_valid(old) and not old.ending:
		old.refresh(boost)
		return null
	# Riding and moon-jumping both own the body's motion: one at a time.
	for other in [&"cloud", &"moonjump"]:
		if gift != other and gift in [&"cloud", &"moonjump"] and is_active(other):
			(active[other] as SmokeGift).end()
	var script := SmokeGifts.script_for(gift)
	if script == null:
		return null
	var g: SmokeGift = script.new()
	g.name = "Gift_%s" % gift
	g.setup(keling, local, gift, int(data.get("seed", 0)), boost)
	g.finished.connect(_on_gift_finished.bind(gift, g))
	active[gift] = g
	keling.add_child(g)
	return g


func _on_gift_finished(gift: StringName, g: SmokeGift) -> void:
	if active.get(gift) == g:
		active.erase(gift)
	gift_ended.emit(gift)
	if local and g.ended_early:
		keling.net_event.emit(&"gift_end", [gift])


func _exit_tree() -> void:
	if local and keling:
		keling.gift_armed = false
