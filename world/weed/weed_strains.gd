class_name WeedStrains
extends RefCounted
## The strains growing wild in the Whispering Glade. Each has its own plant
## model, a bud tint, a smoke style (WeedSmoke.STYLES) and the hue of the
## dreamy glow it leaves behind when smoked away from a bench.
##
## The first three are the common wild Meshy plants. The other ten are forged
## from them by tools/strain_forge.py: each has its own plant silhouette, its
## own bud shape ("bud_mesh") and palette, a rarity (rarer ones grow in fewer,
## more special places, see WeedPatches) and the smoke gift it grants.
##
## Buds keep their strain all the way from the plant to the joint. The wild
## strains all smoke "normal"; rarer strains can bring a style of their own.

const BUD_MESH := "res://assets/weed/bud.glb"

const STRAINS := {
	&"ember": {
		"name": "Ember Kush",
		"mesh": "res://assets/weed/plant_ember.glb",
		"height": 1.15,             # metres, a Keling is ~1.3
		"bud_tint": Color(1.0, 0.72, 0.42),
		"glow": Color(1.0, 0.55, 0.2),
		"smoke": &"normal",
		"dream": Color(1.0, 0.6, 0.3),
		"blurb": "Warm and toasty, with a crackle of orange sparks.",
	},
	&"starlit": {
		"name": "Starlit Haze",
		"mesh": "res://assets/weed/plant_starlit.glb",
		"height": 1.05,
		"bud_tint": Color(0.86, 0.68, 1.0),
		"glow": Color(0.72, 0.45, 1.0),
		"smoke": &"normal",
		"dream": Color(0.68, 0.48, 1.0),
		"blurb": "Violet and shimmering, like a sky full of stars.",
	},
	&"verdant": {
		"name": "Verdant Dream",
		"mesh": "res://assets/weed/plant_verdant.glb",
		"height": 1.0,
		"bud_tint": Color(0.68, 1.0, 0.7),
		"glow": Color(0.35, 1.0, 0.55),
		"smoke": &"normal",
		"dream": Color(0.35, 1.0, 0.6),
		"blurb": "Fresh as dew on a spring morning.",
	},
	# --- Forged strains (tools/strain_forge.py). Height is the model's own
	# (metres); bud shapes and anchors come from StrainShapes.
	&"corkscrew": {
		"name": "Corkscrew Kush",
		"mesh": "res://assets/weed/strains/corkscrew.glb",
		"bud_mesh": "res://assets/weed/strains/corkscrew_bud.glb",
		"height": 1.2, "rarity": &"common", "gift": &"moonjump",
		"bud_tint": Color(0.82, 1.0, 0.45),
		"glow": Color(0.75, 1.0, 0.3),
		"smoke": &"normal",
		"dream": Color(0.8, 1.0, 0.35),
		"blurb": "Wound up like a spring: its stem corkscrews skywards and its buds swirl like soft-serve.",
	},
	&"mossy_mound": {
		"name": "Mossy Mound",
		"mesh": "res://assets/weed/strains/mossy_mound.glb",
		"bud_mesh": "res://assets/weed/strains/mossy_mound_bud.glb",
		"height": 0.72, "rarity": &"common", "gift": &"bloom",
		"bud_tint": Color(0.6, 0.85, 0.42),
		"glow": Color(0.45, 0.95, 0.35),
		"smoke": &"normal",
		"dream": Color(0.5, 0.95, 0.4),
		"blurb": "A low, cosy dome of leaves hiding lumpy popcorn nugs. Smells like rain on moss.",
	},
	&"starfish": {
		"name": "Starfish Sprawl",
		"mesh": "res://assets/weed/strains/starfish.glb",
		"bud_mesh": "res://assets/weed/strains/starfish_bud.glb",
		"height": 0.56, "rarity": &"common", "gift": &"fireflies",
		"bud_tint": Color(1.0, 0.62, 0.5),
		"glow": Color(0.3, 0.95, 1.0),
		"smoke": &"normal",
		"dream": Color(0.35, 0.9, 1.0),
		"blurb": "Its arms sprawl flat along the ground and curl up at the tips. The buds are little stars.",
	},
	&"sky_spire": {
		"name": "Sky Spire Haze",
		"mesh": "res://assets/weed/strains/sky_spire.glb",
		"bud_mesh": "res://assets/weed/strains/sky_spire_bud.glb",
		"height": 2.45, "rarity": &"uncommon", "gift": &"moonjump",
		"bud_tint": Color(1.0, 0.94, 0.58),
		"glow": Color(1.0, 0.88, 0.4),
		"smoke": &"normal",
		"dream": Color(1.0, 0.9, 0.45),
		"blurb": "A towering sativa twice your height, with long foxtail colas you can still reach on tiptoe.",
	},
	&"bubblegum": {
		"name": "Bubblegum Pop",
		"mesh": "res://assets/weed/strains/bubblegum.glb",
		"bud_mesh": "res://assets/weed/strains/bubblegum_bud.glb",
		"height": 1.3, "rarity": &"uncommon", "gift": &"cloud",
		"bud_tint": Color(1.0, 0.6, 0.85),
		"glow": Color(1.0, 0.45, 0.8),
		"smoke": &"normal",
		"dream": Color(1.0, 0.55, 0.85),
		"blurb": "Grows into a perfect topiary lollipop. The buds are round as gumballs.",
	},
	&"moonfeather": {
		"name": "Moonfeather",
		"mesh": "res://assets/weed/strains/moonfeather.glb",
		"bud_mesh": "res://assets/weed/strains/moonfeather_bud.glb",
		"height": 1.5, "rarity": &"rare", "gift": &"owl",
		"bud_tint": Color(0.8, 0.9, 1.0),
		"glow": Color(0.6, 0.8, 1.0),
		"smoke": &"normal",
		"dream": Color(0.65, 0.8, 1.0),
		"aura": 0.22, "bud_rim": 1.5,
		"blurb": "A ghostly weeping willow by the water. Its feathery buds dangle from curtains of silver leaves.",
	},
	&"lantern": {
		"name": "Lantern Light",
		"mesh": "res://assets/weed/strains/lantern.glb",
		"bud_mesh": "res://assets/weed/strains/lantern_bud.glb",
		"height": 0.95, "rarity": &"rare", "gift": &"fireflies",
		"bud_tint": Color(1.0, 0.72, 0.32),
		"glow": Color(1.0, 0.62, 0.18),
		"smoke": &"normal",
		"dream": Color(1.0, 0.66, 0.25),
		"aura": 0.08, "bud_rim": 2.6,
		"blurb": "A candelabra of a plant that holds up glowing paper-lantern buds in the dark.",
	},
	&"cloud_bonsai": {
		"name": "Cloud Bonsai",
		"mesh": "res://assets/weed/strains/cloud_bonsai.glb",
		"bud_mesh": "res://assets/weed/strains/cloud_bonsai_bud.glb",
		"height": 1.2, "rarity": &"rare", "gift": &"cloud",
		"bud_tint": Color(1.0, 0.86, 0.94),
		"glow": Color(1.0, 0.7, 0.88),
		"smoke": &"normal",
		"dream": Color(1.0, 0.75, 0.9),
		"blurb": "An ancient little bonsai, pruned into pink clouds. Its buds are soft as cloud puffs.",
	},
	&"sunset_braid": {
		"name": "Sunset Braid",
		"mesh": "res://assets/weed/strains/sunset_braid.glb",
		"bud_mesh": "res://assets/weed/strains/sunset_braid_bud.glb",
		"height": 1.17, "rarity": &"rare", "gift": &"slowtime",
		"bud_tint": Color(1.0, 0.62, 0.72),
		"glow": Color(1.0, 0.5, 0.6),
		"smoke": &"normal",
		"dream": Color(1.0, 0.55, 0.7),
		"blurb": "Ember and Starlit, braided into one: two stems twist around each other into a sunset.",
	},
	&"moonlit_lotus": {
		"name": "Moonlit Lotus",
		"mesh": "res://assets/weed/strains/moonlit_lotus.glb",
		"bud_mesh": "res://assets/weed/strains/moonlit_lotus_bud.glb",
		"height": 1.18, "rarity": &"legendary", "gift": &"slowtime",
		"bud_tint": Color(0.88, 0.88, 1.0),
		"glow": Color(0.75, 0.7, 1.0),
		"smoke": &"normal",
		"dream": Color(0.8, 0.75, 1.0),
		"aura": 0.3, "bud_rim": 2.0,
		"blurb": "The legend of the glade: a silver lotus rosette crowned with a royal cola. Few have seen it.",
	},
}

const ORDER: Array[StringName] = [&"ember", &"starlit", &"verdant", &"corkscrew", &"mossy_mound", &"starfish",
	&"sky_spire", &"bubblegum", &"moonfeather", &"lantern", &"cloud_bonsai", &"sunset_braid", &"moonlit_lotus"]

## How rare each strain is: the label and colour the HUD shows when you find one.
const RARITY := {
	&"common": {"name": "Common", "color": Color(0.75, 0.95, 0.6), "stars": 1},
	&"uncommon": {"name": "Uncommon", "color": Color(0.45, 0.85, 1.0), "stars": 2},
	&"rare": {"name": "Rare", "color": Color(0.85, 0.55, 1.0), "stars": 3},
	&"legendary": {"name": "Legendary", "color": Color(1.0, 0.8, 0.3), "stars": 4},
}


static func info(id: StringName) -> Dictionary:
	return STRAINS.get(id, STRAINS[&"ember"])


static func display_name(id: StringName) -> String:
	return info(id).name


static func rarity(id: StringName) -> Dictionary:
	return RARITY[info(id).get("rarity", &"common")]


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
