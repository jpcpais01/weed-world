class_name WeedStrains
extends RefCounted
## The three strains growing wild in the Whispering Glade. Each has its own
## plant model, a bud tint, the colour of its smoke and the hue of the dreamy
## glow it leaves behind when smoked away from a bench.
##
## Buds keep their strain all the way from the plant to the joint, so the
## smoke you blow is the colour of what you picked.

const BUD_MESH := "res://assets/weed/bud.glb"

const STRAINS := {
	&"ember": {
		"name": "Ember Kush",
		"mesh": "res://assets/weed/plant_ember.glb",
		"height": 1.15,             # metres, a Keling is ~1.3
		"bud_tint": Color(1.0, 0.72, 0.42),
		"glow": Color(1.0, 0.55, 0.2),
		"smoke": Color(1.0, 0.86, 0.72),
		"dream": Color(1.0, 0.6, 0.3),
		"blurb": "Warm and toasty, with a crackle of orange sparks.",
	},
	&"starlit": {
		"name": "Starlit Haze",
		"mesh": "res://assets/weed/plant_starlit.glb",
		"height": 1.05,
		"bud_tint": Color(0.86, 0.68, 1.0),
		"glow": Color(0.72, 0.45, 1.0),
		"smoke": Color(0.88, 0.8, 1.0),
		"dream": Color(0.68, 0.48, 1.0),
		"blurb": "Violet and shimmering, like a sky full of stars.",
	},
	&"verdant": {
		"name": "Verdant Dream",
		"mesh": "res://assets/weed/plant_verdant.glb",
		"height": 1.0,
		"bud_tint": Color(0.68, 1.0, 0.7),
		"glow": Color(0.35, 1.0, 0.55),
		"smoke": Color(0.82, 1.0, 0.86),
		"dream": Color(0.35, 1.0, 0.6),
		"blurb": "Fresh as dew on a spring morning.",
	},
}

const ORDER: Array[StringName] = [&"ember", &"starlit", &"verdant"]


static func info(id: StringName) -> Dictionary:
	return STRAINS.get(id, STRAINS[&"ember"])


static func display_name(id: StringName) -> String:
	return info(id).name


## The bench powers: what you get for smoking while gazing at each kind of
## view (BenchSites element tags), plus the default dreamy glow anywhere else.
const POWERS := {
	&"none": {
		"name": "Glade Glow", "icon": "leaf",
		"text": "The forest blooms brighter and dreamier",
		"color": Color(0.85, 0.7, 1.0),
	},
	&"water": {
		"name": "Brook Stride", "icon": "drop",
		"text": "Quick as a stream: you run faster and ripple as you go",
		"color": Color(0.4, 0.8, 1.0),
	},
	&"spirit": {
		"name": "Spirit Sight", "icon": "eye",
		"text": "Ripe buds shine through the whole forest",
		"color": Color(0.95, 0.6, 1.0),
	},
	&"air": {
		"name": "Featherfall", "icon": "feather",
		"text": "Jump twice as high and drift down like a seed",
		"color": Color(0.85, 0.95, 1.0),
	},
	&"earth": {
		"name": "Mountain Might", "icon": "stone",
		"text": "You grow big and strong, and the ground shakes",
		"color": Color(1.0, 0.75, 0.38),
	},
	&"life": {
		"name": "Bloom Trail", "icon": "flower",
		"text": "Flowers spring up in your footsteps and plants ripen near you",
		"color": Color(0.55, 1.0, 0.45),
	},
}


static func power(element: StringName) -> Dictionary:
	return POWERS.get(element, POWERS[&"none"])
