class_name SmokeGifts
extends RefCounted
## The smoke gifts: every strain carries one. Smoke a joint of it and each
## puff gives a charge of its gift; while the high lasts, the Gift button
## (V / RB / the touch button) breathes one charge out as a power.
##
##   fireflies · Firefly Swarm   twilight falls and a swarm of fireflies lights
##                               the forest, then leads you to the rarest ripe
##                               plant around
##   cloud     · Cloud Ride      your smoke gathers into a fluffy cloud; sit on
##                               it and fly across the valley
##   bloom     · Bloom Burst     a smoke ring rolls out over the ground and
##                               gigantic glowing flora erupt in its wake:
##                               bouncy titan mushrooms, starlilies, lantern
##                               bells, fiddlehead ferns, lotus on the water
##   slowtime  · Slow Time       the whole world slows to a dream around you
##                               (but not you): leaves hang in the air
##   moonjump  · Moon Jump       a pale moon rises; gravity lets go, every
##                               landing bounces and scatters stardust
##
## Smoked at a bench whose view matches the gift's element, it comes out
## stronger and lasts longer.

const GIFTS := {
	&"fireflies": {
		"name": "Firefly Swarm", "icon": "firefly", "element": &"spirit",
		"text": "Twilight falls, the fireflies wake and lead you to rare buds",
		"color": Color(0.85, 1.0, 0.45), "time": 40.0,
	},
	&"cloud": {
		"name": "Cloud Ride", "icon": "cloud", "element": &"air",
		"text": "Your smoke becomes a cloud: hop on and fly",
		"color": Color(0.88, 0.92, 1.0), "time": 32.0,
	},
	&"bloom": {
		"name": "Bloom Burst", "icon": "bloom", "element": &"life",
		"text": "Giant glowing flora burst out of the ground around you",
		"color": Color(1.0, 0.55, 0.85), "time": 48.0,
	},
	&"slowtime": {
		"name": "Slow Time", "icon": "hourglass", "element": &"water",
		"text": "The world slows to a dream around you, but you don't",
		"color": Color(0.55, 0.75, 1.0), "time": 22.0,
	},
	&"moonjump": {
		"name": "Moon Jump", "icon": "moon", "element": &"earth",
		"text": "A pale moon rises and gravity lets go",
		"color": Color(0.8, 0.84, 1.0), "time": 36.0,
	},
}

const ORDER: Array[StringName] = [&"fireflies", &"cloud", &"bloom", &"slowtime", &"moonjump"]
## How much more a matching bench view gives (time and strength).
const BOOST := 1.5
const MAX_CHARGES := 3

## The wild strains' gifts (a strain's own "gift" key wins over this).
const WILD := {&"ember": &"fireflies", &"starlit": &"moonjump", &"verdant": &"bloom"}


static func info(id: StringName) -> Dictionary:
	return GIFTS.get(id, GIFTS[&"fireflies"])


static func valid(id: StringName) -> bool:
	return GIFTS.has(id)


## The gift a strain carries: its own "gift" key, else the wild table, else a
## stable pick from its name (the same on every device).
static func of_strain(strain: StringName) -> StringName:
	var s: Dictionary = WeedStrains.STRAINS.get(strain, {})
	var own := StringName(s.get("gift", &""))
	if valid(own):
		return own
	if WILD.has(strain):
		return WILD[strain]
	if strain == &"":
		return &""
	return ORDER[absi(hash(String(strain))) % ORDER.size()]


## Real seconds per game second right now, for things that must keep real
## time while Slow Time stretches the world (gift timers, the HUD).
static func real(delta: float) -> float:
	return delta / maxf(Engine.time_scale, 0.01)


static func script_for(id: StringName) -> Script:
	match id:
		&"fireflies":
			return load("res://player/powers/gift_fireflies.gd")
		&"cloud":
			return load("res://player/powers/gift_cloud.gd")
		&"bloom":
			return load("res://player/powers/gift_bloom.gd")
		&"slowtime":
			return load("res://player/powers/gift_slow_time.gd")
		&"moonjump":
			return load("res://player/powers/gift_moon_jump.gd")
	return null
