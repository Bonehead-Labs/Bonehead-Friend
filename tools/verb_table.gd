extends RefCounted

## The verbs on everyday things (docs/decisions.md D67): what the right button does to a toy
## that used to be only put down. One row per item — its click zones, its verbs and the line
## the shop and the first-landing toast teach it by.
##
## Read by the seeders that own these scenes (`seed_friendly.gd`, `seed_m35_roster.gd`), which
## call `attach()` on every body they build, so a scene rebuilt from its seeder comes back with
## its verbs; and by `seed_m310_verbs.gd`, which writes `controls` onto items that already
## exist. A new verb is a row here, and — only if it needs one — a method on the body its
## `call` names. `ItemVerbs`' class comment is the row format; `GestureZones`' is the zones'.
##
## **Everything spatial is in art pixels**, origin at the sprite's centre, y down — the space
## of the scale table and the fidget seeder. Every zone here was read off its sprite with
## `art/tools/zone_sheet.py`, which draws it at 8x on an art-pixel grid with the zones over it.
##
## **What a verb pays, and why so little.** A verb is an act — the combo, the board and the
## Dollars see it — sized against petting, the kind side's hands-on baseline: 1 value a pet at
## three or four pets a second. So one act is worth a few seconds of petting, and no verb can
## pay faster than 1.5 value a second however fast it is clicked (value / cooldown), which is
## below the item's own rate for every item here — and that rate pays whether anyone is there
## or not. They are the reason to touch the thing, not a second income from it. `pacing_sim`
## models hands-on kindness as petting; a player going round the desk working one verb after
## another, a click every second or two, earns about what stroking him would have.

const GestureZonesScript := preload("res://Scripts/Bodies/gesture_zones.gd")
const ItemVerbsScript := preload("res://Scripts/Bodies/item_verbs.gd")

const KIND := Color("ff5f9e")
const NOTE := Color("2fb5b0")
const GOLD := Color("ffc247")
const LILAC := Color("d9a0ff")
const BUBBLE := Color("bfe6ff")
const WAX := Color("ff9a3d")
const FLAKE := Color("ffcf6b")
const FISH := Color("f28c28")
const WATER := Color("7fc8ff")
const STEAM := Color("e8e4d6")

const VERBS := {
	# --- Play -------------------------------------------------------------------------
	# The most obvious verb in the world. A squeeze squashes it about its belly and it squeaks;
	# at 2 a squeak every 1.5 s it is a fifth of what catching it pays.
	&"rubber_duck": {
		"controls": "Right-click it to squeak · Throw it to him",
		"zones": [{"id": &"duck", "circle": 10.0, "at": Vector2(0, 0), "right": "tap"}],
		"verbs": [{
			"id": &"squeak", "zone": &"duck", "on": "tap",
			"value": 2.0, "cooldown": 1.5,
			"sound": &"squeak", "spread": 0.15, "volume": -4.0,
			"bursts": [[&"heart", KIND, 3, 90.0]],
			"effects": [{"kind": "squash", "scale": Vector2(1.25, 0.72), "anchor": Vector2(0, 9),
				"seconds": 0.28}],
			"react": &"amused",
		}],
	},
	# Right while held is the item's action (D57). A popper is pulled once: the pull pays what
	# throwing it at him pays, and both routes use it up, so it can never pay twice. Pulled with
	# him out of earshot it is confetti for nobody and pays nothing.
	&"party_popper": {
		"controls": "Hold it near him and right-click to pull the string · Or throw it at him",
		"action": true,
		"zones": [],
		"verbs": [{
			"id": &"pull", "on": "action",
			"value": 45.0, "near": 360.0, "consume": true,
			"sound": &"pop", "pitch": 0.55, "volume": -2.0,
			"bursts": [[&"chip", KIND, 10, 300.0], [&"chip", GOLD, 10, 280.0],
				[&"chip", NOTE, 10, 320.0], [&"star", GOLD, 4, 220.0]],
			"react": &"confetti",
		}],
	},
	# A crank on the fan face: every full turn blows a flurry out of the chimney.
	&"bubble_machine": {
		"controls": "Right-drag circles on the fan to blow a flurry",
		"zones": [{"id": &"fan", "circle": 6.5, "at": Vector2(-2, 7.5), "right": "claim"}],
		"verbs": [
			{"id": &"wind", "zone": &"fan", "on": "crank", "every": PI * 0.5,
				"sound": &"whirr", "volume": -12.0},
			{"id": &"flurry", "zone": &"fan", "on": "crank", "every": TAU,
				"value": 5.0, "cooldown": 4.0,
				"sound": &"pop", "pitch": 1.3, "volume": -8.0,
				"effects": [{"kind": "surge", "colour": BUBBLE, "at": Vector2(8, -7),
					"box": Vector2(2, 1), "velocity": Vector2(6, -40), "spread": 35.0,
					"gravity": Vector2(0, 10), "lifetime": 1.6, "amount": 10, "seconds": 0.7,
					"scale": Vector2(1.2, 2.2)}],
				"react": &"show"},
		],
	},

	# --- Ambience ---------------------------------------------------------------------
	# The buttons across the top change the track: four of them, each its own colour of notes and
	# its own tempo, and he does a new move for each.
	&"boombox": {
		"controls": "Right-click the buttons for the next track",
		"zones": [{"id": &"deck", "rect": Vector2(40, 8), "at": Vector2(0, -6), "right": "tap"}],
		"verbs": [{
			"id": &"next_track", "zone": &"deck", "on": "tap", "cycle": 4,
			"value": 4.0, "cooldown": 4.0,
			"colours": [NOTE, KIND, GOLD, LILAC],
			"sound": &"plink", "notes": [0, 5, 7, 12], "volume": -6.0,
			"bursts": [[&"chip", "cycle", 8, 140.0]],
			"effects": [
				{"kind": "tint", "ambient": "set"},
				{"kind": "tempo", "speeds": [1.0, 1.6, 0.7, 1.3]},
				{"kind": "squash", "scale": Vector2(1.06, 0.94), "anchor": Vector2(0, 20),
					"seconds": 0.2},
			],
			"react": &"music",
		}],
	},
	# Three tubes, each a note. A stroke across them rings each one it passes — pressed on a
	# tube it rings that one at once — and the whole chime rocks on its hook. One act a stroke.
	&"wind_chimes": {
		"controls": "Right-drag across the chimes to ring them",
		"zones": [
			{"id": &"t0", "rect": Vector2(4, 20), "at": Vector2(-6, 1), "right": "claim"},
			{"id": &"t1", "rect": Vector2(4, 22), "at": Vector2(-1, 2), "right": "claim"},
			{"id": &"t2", "rect": Vector2(4, 16), "at": Vector2(4, -1), "right": "claim"},
			# The chime around them, last so the tubes win: a stroke may start between them.
			{"id": &"chimes", "rect": Vector2(18, 36), "at": Vector2(-1, 0), "right": "claim",
				"backing": true},
		],
		"verbs": [{
			"id": &"ring", "zones": [&"t0", &"t1", &"t2"], "on": ["press", "cross"],
			"value": 3.0, "cooldown": 3.0,
			"sound": &"plink", "notes": [0, 4, 7], "volume": -8.0,
			"bursts": [[&"star", GOLD, 2, 60.0]],
			"effects": [{"kind": "swing", "degrees": 7.0, "pivot": Vector2(0, -18), "seconds": 1.6}],
			"react": &"music",
		}],
	},
	# Four patterns: warm, rose, sky, mint — the bulbs and their twinkle together.
	&"fairy_lights": {
		"controls": "Right-click the lights to change the pattern",
		"zones": [{"id": &"lights", "rect": Vector2(60, 22), "at": Vector2(-1, 1), "right": "tap"}],
		"verbs": [{
			"id": &"pattern", "zone": &"lights", "on": "tap", "cycle": 4,
			"value": 3.0, "cooldown": 4.0,
			"colours": [Color.WHITE, Color("ffb3d9"), Color("9fd8ff"), Color("b8f5b0")],
			"sound": &"plink", "notes": [7, 11, 14, 19], "volume": -9.0,
			"bursts": [[&"star", "cycle", 5, 70.0]],
			"effects": [{"kind": "tint", "sprite": true, "ambient": "tint"}],
			"react": &"show",
		}],
	},
	# Wax rises through the glass for five seconds and the lamp rocks on its foot.
	&"lava_lamp": {
		"controls": "Right-click the glass to stir up the wax",
		"zones": [{"id": &"glass", "rect": Vector2(12, 24), "at": Vector2(-1, -4), "right": "tap"}],
		"verbs": [{
			"id": &"churn", "zone": &"glass", "on": "tap",
			"value": 8.0, "cooldown": 8.0,
			"sound": &"slosh", "pitch": 0.7, "volume": -10.0,
			"effects": [
				{"kind": "surge", "colour": WAX, "at": Vector2(-1, 3), "box": Vector2(3, 3),
					"velocity": Vector2(0, -8), "spread": 15.0, "lifetime": 1.6, "amount": 10,
					"seconds": 5.0, "scale": Vector2(1.4, 2.4)},
				{"kind": "swing", "degrees": 4.0, "pivot": Vector2(0, 19), "seconds": 0.7,
					"swings": 3.0},
			],
			"react": &"show",
		}],
	},
	# Scratch it: every 8 art px of stroke across the record is a scratch, up for a push and
	# down for a pull.
	&"record_player": {
		"controls": "Right-drag across the record to scratch it",
		"zones": [{"id": &"disc", "rect": Vector2(22, 10), "at": Vector2(-1, 1), "right": "claim"}],
		"verbs": [{
			"id": &"scratch", "zone": &"disc", "on": "drag", "every": 8.0,
			"value": 5.0, "cooldown": 4.0,
			"sound": &"scratch", "volume": -6.0,
			"bursts": [[&"chip", NOTE, 4, 110.0]],
			"effects": [{"kind": "squash", "scale": Vector2(1.03, 0.97), "anchor": Vector2(0, 18),
				"seconds": 0.12}],
			"react": &"music",
		}],
	},
	# Feed them: flakes drift down from the lid, the fish come up for them, the water bubbles.
	# Once every fifteen seconds is a meal; tapping sooner still sprinkles, and pays nothing.
	&"fish_tank": {
		"controls": "Right-click the lid to feed the fish",
		"zones": [{"id": &"lid", "rect": Vector2(40, 6), "at": Vector2(0, -19), "right": "tap"}],
		"verbs": [{
			"id": &"feed", "zone": &"lid", "on": "tap",
			"value": 12.0, "cooldown": 15.0,
			"sound": &"pop", "pitch": 1.6, "volume": -12.0,
			"effects": [
				{"kind": "surge", "colour": FLAKE, "at": Vector2(0, -16), "box": Vector2(14, 1),
					"velocity": Vector2(0, 10), "spread": 20.0, "gravity": Vector2(0, 4),
					"lifetime": 1.8, "amount": 10, "seconds": 0.6, "scale": Vector2(0.8, 1.2)},
				{"kind": "surge", "colour": FISH, "at": Vector2(0, -3), "box": Vector2(14, 3),
					"velocity": Vector2(0, -24), "spread": 8.0, "damping": 24.0,
					"lifetime": 1.0, "amount": 4, "seconds": 0.5, "delay": 0.3,
					"scale": Vector2(1.4, 1.8)},
				{"kind": "surge", "colour": BUBBLE, "at": Vector2(0, 0), "box": Vector2(16, 1),
					"velocity": Vector2(0, -14), "spread": 10.0, "lifetime": 1.3, "amount": 10,
					"seconds": 2.0, "scale": Vector2(0.8, 1.3)},
			],
			"react": &"show",
		}],
	},
	# Water it: drops fall on the leaves, and a moment later it stands up a little taller.
	&"houseplant": {
		"controls": "Right-click the leaves to water it",
		"zones": [{"id": &"leaves", "rect": Vector2(32, 22), "at": Vector2(0, -8), "right": "tap"}],
		"verbs": [{
			"id": &"water", "zone": &"leaves", "on": "tap",
			"value": 6.0, "cooldown": 20.0,
			"sound": &"slosh", "pitch": 1.4, "volume": -12.0,
			"effects": [
				{"kind": "surge", "colour": WATER, "at": Vector2(0, -24), "box": Vector2(9, 1),
					"velocity": Vector2(0, 40), "spread": 5.0, "gravity": Vector2(0, 60),
					"lifetime": 0.45, "amount": 8, "seconds": 0.4, "scale": Vector2(0.8, 1.1)},
				{"kind": "squash", "scale": Vector2(0.94, 1.12), "anchor": Vector2(0, 21),
					"seconds": 0.5, "delay": 0.35},
			],
			"react": &"amused",
		}],
	},

	# --- Food ---------------------------------------------------------------------------
	# Stir it: a clink every half turn, and two full turns make it a proper cup — once. It is
	# drunk the way it always was.
	&"cup_of_tea": {
		"controls": "Right-drag circles in the cup to stir it · He drinks it on contact",
		"zones": [{"id": &"tea", "circle": 7.0, "at": Vector2(0, -5), "right": "claim"}],
		"verbs": [
			{"id": &"clink", "zone": &"tea", "on": "crank", "every": PI,
				"sound": &"impact_metal", "pitch": 2.2, "volume": -16.0},
			{"id": &"stirred", "zone": &"tea", "on": "crank", "every": TAU * 2.0,
				"value": 5.0, "once": true,
				"bursts": [[&"heart", KIND, 3, 80.0]],
				"effects": [{"kind": "surge", "colour": STEAM, "at": Vector2(0, -8),
					"box": Vector2(5, 1), "velocity": Vector2(0, -20), "spread": 20.0,
					"lifetime": 1.2, "amount": 8, "seconds": 1.0, "scale": Vector2(1.0, 2.0)}],
				"react": &"amused"},
		],
	},

	# --- The fan -------------------------------------------------------------------------
	# Pointing it was always the interaction (WindSource's own comment), and the only way to
	# point it was to tip the whole fan over. Now a right-drag from its face aims the wind at
	# the cursor, level to 50 degrees either side. A Bones toy that pays nothing, so nothing
	# here pays: the verb is the physics.
	&"desk_fan": {
		"controls": "Right-drag from the fan's face to aim it",
		"zones": [{"id": &"face", "circle": 10.0, "at": Vector2(0, -6), "right": "claim"}],
		"verbs": [
			{"id": &"grab_face", "zone": &"face", "on": "press",
				"sound": &"whirr", "volume": -10.0},
			{"id": &"aim", "zone": &"face", "on": "drag", "call": &"aim_at"},
		],
	},

	# --- Comfort --------------------------------------------------------------------------
	# The jets are for him: they bubble whoever is in the tub, and pay only while he is.
	&"hot_tub": {
		"controls": "Right-click the jets while he soaks",
		"zones": [{"id": &"jets", "rect": Vector2(56, 8), "at": Vector2(0, 4), "right": "tap"}],
		"verbs": [{
			"id": &"jets", "zone": &"jets", "on": "tap",
			"value": 10.0, "cooldown": 8.0, "touching": true,
			"sound": &"slosh", "volume": -6.0,
			"effects": [{"kind": "surge", "colour": BUBBLE, "at": Vector2(0, -13),
				"box": Vector2(24, 6), "velocity": Vector2(0, -16), "spread": 25.0,
				"lifetime": 0.9, "amount": 18, "seconds": 5.0, "scale": Vector2(0.9, 1.6)}],
			"react": &"jets",
		}],
	},
}

## The line an item is taught by, or "" for one with no verbs here.
static func controls(item_id: StringName) -> String:
	var entry: Dictionary = VERBS.get(item_id, {})
	return String(entry.get("controls", ""))

## Gives a body built by a seeder its zones and its verbs, if this table has any for it. The
## seeders call it on every body; it does nothing to the rest.
static func attach(root: Node, item_id: StringName) -> void:
	if not VERBS.has(item_id):
		return
	var entry: Dictionary = VERBS[item_id]
	var zones := GestureZonesScript.new() as Node
	zones.name = "GestureZones"
	zones.set(&"zones", entry.get("zones", []))
	zones.set(&"action_enabled", bool(entry.get("action", false)))
	root.add_child(zones)
	var verbs := ItemVerbsScript.new() as Node
	verbs.name = "ItemVerbs"
	verbs.set(&"verbs", entry.get("verbs", []))
	root.add_child(verbs)
