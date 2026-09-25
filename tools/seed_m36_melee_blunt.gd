extends Node

## Fifteen blunt melee weapons: ten built to hit things, and five that were on the desk
## already.
##
##   Godot --headless --path <project> res://tools/seed_m36_melee_blunt.tscn [-- --force | --only id,id]
##
## M3.5 closed with four melee weapons — bat, pan, mace, katana — and the owner wants
## thirty. These are everything that hurts by **mass** rather than by edge; the blades are
## a separate tool and a separate ladder, and the two never touch the same id.
##
## The second family is the one the game is actually about. This is a toy that lives on a
## work machine, and until now nothing in the shop knew that: a stapler, a mug, a hole
## punch, a keyboard and the monitor in front of you are all within reach of the mouse
## already, and "beaten with a stapler" is the joke the overlay premise has been setting up
## since M1.
##
## Everything here comes out of tables. Scenes are packed by `ItemBodyBuilder`, items,
## trees and capstones are `ItemData` / `AugmentNode` written from script, and nothing is
## hand-edited — a sixteenth weapon is a row, not a script change (docs/decisions.md D8).
## Only files that do not already exist are written.

const ItemDataScript := preload("res://Scripts/Data/item_data.gd")
const AugmentNodeScript := preload("res://Scripts/Data/augment_node.gd")
const WeaponBaseScript := preload("res://Scripts/Bodies/weapon_base.gd")

const BODIES_DIR := "res://Scenes/Bodies"
const ITEMS_DIR := "res://Data/Items"
const AUGMENTS_DIR := "res://Data/Augments"
const ICONS_DIR := "res://Assets/sprites/icons"

# --- physics ---------------------------------------------------------------

## Authored feel, one entry per weapon, in **art pixels** — the same space as the scale
## table in `docs/art-direction.md`. `ItemBodyBuilder` multiplies it by ART_SCALE exactly
## as it does the sprite.
##
## D25 is why this table exists at all: rebuilding the prototype's bat from its sprite
## produced a box around the picture, pinned and balanced at its centre, which is a plank
## on a string. The four things a sprite cannot tell you are `shapes` (a head and a haft,
## not one box), `com` (weight where the steel is), `grip` (where the drag joint pins, so
## it pivots around your hand) and `grab` (the click target, over the handle). `rot` is in
## degrees, for anything drawn on a diagonal.
##
## Vertical, head up and handle down, is the house pose — it is what the bat and mace
## tables assume and what the art prompts ask for. The golf club is the exception and says
## why in place.
##
## The art does not always keep the pose — the crowbar leans, the tyre iron's bar hangs off
## the right of its arm, the nunchaku's sticks lie side by side — so every row is authored
## against the sprite as drawn (D61). Read shapes off
## `tools/collider_report.tscn -- --tables --shots --runs`, never off a guess about the prompt.
const PHYSICS := {
	# Two turned handles and a barrel between them. The weight is spread down the whole
	# cylinder rather than gathered in a head, which is what makes a rolling pin the
	# gentlest thing in this tool despite being solid hardwood.
	&"rolling_pin": {
		"shapes": [
			{"rect": Vector2(5, 9), "at": Vector2(0, -19)},
			{"capsule": Vector2(16, 26), "at": Vector2(0, -1)},
			{"rect": Vector2(5, 9), "at": Vector2(0, 16)},
		],
		"com": Vector2(0, -2),
		"grip": Vector2(0, 19),
		"grab": {"size": Vector2(14, 18), "at": Vector2(0, 14)},
	},
	# Steel end to end, so the balance sits only a little forward of centre. That is the
	# difference between a crowbar and a hammer, and it is the whole reason to own both.
	&"crowbar": {
		"shapes": [
			{"capsule": Vector2(6, 40.5), "at": Vector2(4.5, 4.75), "rot": -24.0},
			{"capsule": Vector2(8, 25), "at": Vector2(-5, -17.25), "rot": 68.0},
		],
		"com": Vector2(0, -6),
		"grip": Vector2(11, 19),
		"grab": {"size": Vector2(14, 26), "at": Vector2(8, 13)},
	},
	# A wide flat willow face on a long cane handle: the biggest contact patch in the tool
	# on one of the lightest bodies in it.
	&"cricket_bat": {
		"shapes": [
			{"rect": Vector2(13, 33), "at": Vector2(-0.5, -12.5)},
			{"capsule": Vector2(7, 19), "at": Vector2(-0.5, 14.5)},
			{"rect": Vector2(11, 6), "at": Vector2(-0.5, 26)},
		],
		"com": Vector2(0, -12),
		"grip": Vector2(0, 26),
		"grab": {"size": Vector2(14, 24), "at": Vector2(0, 18)},
	},
	# The socket arm is off to one side, so it is deliberately not symmetrical: it tumbles
	# rather than spins, which is what an L-shaped bar in the boot of a car actually does.
	&"tyre_iron": {
		"shapes": [
			{"capsule": Vector2(6, 46), "at": Vector2(10, 1)},
			{"rect": Vector2(22, 6), "at": Vector2(-2, -19)},
			{"rect": Vector2(8, 9), "at": Vector2(-8, -19.5)},
		],
		"com": Vector2(8, -12),
		"grip": Vector2(10, 21),
		"grab": {"size": Vector2(12, 26), "at": Vector2(10, 11)},
	},
	&"sledgehammer": {
		"shapes": [
			{"rect": Vector2(29, 12), "at": Vector2(-1, -21)},
			{"capsule": Vector2(10, 40), "at": Vector2(-0.5, 7)},
		],
		# Almost in the head. A sledgehammer is a wooden stick with a block on the end and
		# it should hang, swing and land like one.
		"com": Vector2(0, -18),
		"grip": Vector2(0, 24),
		"grab": {"size": Vector2(14, 30), "at": Vector2(0, 13)},
	},
	&"pipe_wrench": {
		"shapes": [
			{"rect": Vector2(14, 11), "at": Vector2(-3, -19.5)},
			{"rect": Vector2(6, 11), "at": Vector2(7, -15.5)},
			{"capsule": Vector2(9, 38), "at": Vector2(-3, 5.5), "rot": 7.7},
		],
		"com": Vector2(0, -14),
		"grip": Vector2(-5, 21),
		"grab": {"size": Vector2(14, 28), "at": Vector2(-3, 13)},
	},
	# The one item here drawn corner to corner, and the one whose grip is at the *top* of
	# the picture. A club hangs head-down from your hands, so pinning at the butt of the
	# grip and putting the mass in the head makes the body settle into its own address
	# position with no code at all — everything else in this table hangs head-down for the
	# same reason, just the other way up.
	&"golf_club": {
		"shapes": [
			{"capsule": Vector2(5.5, 54), "at": Vector2(10.1, -7.6), "rot": 43.0},
			{"rect": Vector2(20, 9), "at": Vector2(-19.5, 17.5)},
			{"rect": Vector2(11, 6), "at": Vector2(-21.5, 25)},
			{"rect": Vector2(7, 16), "at": Vector2(23.2, -21.6), "rot": 43.0},
		],
		"com": Vector2(-19, 19),
		"grip": Vector2(23, -23),
		"grab": {"size": Vector2(20, 20), "at": Vector2(20, -20)},
	},
	# Two sticks and a chain, approximated as one body — see the note on the flail below.
	# They are drawn side by side with the chain across the middle, so the pin is at the end
	# of one stick and the weight is in the other: the flail's approximation again. The gap
	# between the sticks is real geometry, so the near stick can pass a corner the far one
	# catches on.
	&"nunchaku": {
		"shapes": [
			{"capsule": Vector2(7, 44), "at": Vector2(-10, 0)},
			{"rect": Vector2(12, 4), "at": Vector2(-1, 2)},
			{"capsule": Vector2(7, 44), "at": Vector2(9, 0)},
		],
		"com": Vector2(9, 0),
		"grip": Vector2(-10, 19),
		"grab": {"size": Vector2(14, 20), "at": Vector2(-10, 14)},
	},
	# Rigid by definition — a morning star is a spiked head on a haft, and the flail below
	# is the one on a chain. That distinction is the only reason to own both.
	&"morning_star": {
		"shapes": [
			{"circle": 10.5, "at": Vector2(-0.5, -14)},
			{"rect": Vector2(27, 3), "at": Vector2(-1, -14.5)},
			{"rect": Vector2(5, 4), "at": Vector2(-1, -24)},
			{"capsule": Vector2(7, 30), "at": Vector2(-0.5, 10.5)},
		],
		"com": Vector2(0, -13),
		"grip": Vector2(0, 22),
		"grab": {"size": Vector2(14, 24), "at": Vector2(0, 15)},
	},
	# **The flail is one rigid body, and that is a decision rather than a shortcut.**
	#
	# A head pinned to a handle with a second RigidBody2D and a PinJoint2D is the physically
	# honest build and it fails on two things this tool cannot reach. `Buddy._attribute`
	# bills a hit to the *contacting collider object*, so a head that is not itself a
	# `WeaponBase` bills every swing to &"world" — no damage_mult, no payout attribution
	# and, worst, no mastery XP, which is the gate on the weapon's own automation capstone.
	# And the picture is one sprite: a head that swings free of a chain welded to the
	# handle reads as broken art, not as weight, and fixing that needs a second sprite plus
	# a Line2D rebuilt every frame.
	#
	# So it is approximated, and the approximation is the same one the bat uses, pushed as
	# far as it goes: the head is a ball 19 art pixels out, the mass is entirely inside it,
	# and the pin is at the very butt of the handle. That is a 45-pixel lever arm against
	# the bat's 30, and the drag joint's own softness supplies the lag.
	&"flail": {
		"shapes": [
			{"circle": 10.0, "at": Vector2(-0.5, -19)},
			{"capsule": Vector2(8, 22), "at": Vector2(-0.5, -0.5)},
			{"rect": Vector2(11, 18), "at": Vector2(-0.5, 19)},
		],
		"com": Vector2(0, -19),
		"grip": Vector2(0, 26),
		"grab": {"size": Vector2(14, 22), "at": Vector2(0, 17)},
	},

	# --- the desk ---
	#
	# All five are low, wide and pinned at the top rather than at an end: you pick a
	# stapler up, you do not hold it by a handle. The grab regions are correspondingly
	# generous, because none of these is a 14-pixel-wide stick that the eye can aim at.
	&"stapler": {
		"shapes": [
			{"rect": Vector2(29, 7), "at": Vector2(-1.5, -3.5)},
			{"rect": Vector2(13, 2), "at": Vector2(-8.5, -8)},
			{"rect": Vector2(31, 9), "at": Vector2(-0.5, 4.5)},
		],
		# The spring and the anvil are in the base, which is why a dropped stapler lands
		# on its bottom and stays there.
		"com": Vector2(0, 2),
		"grip": Vector2(0, -6),
		"grab": {"size": Vector2(32, 20), "at": Vector2(-1, 0)},
	},
	# Pinned by the handle, so it swings from a point outside its own silhouette. That is
	# the closest thing in this tool to an actual flail, and it came free with the shape.
	&"office_mug": {
		"shapes": [
			{"rect": Vector2(22, 24), "at": Vector2(-4, -1)},
			{"rect": Vector2(6, 14), "at": Vector2(11, -1)},
		],
		"com": Vector2(-4, 5),
		"grip": Vector2(11, -4),
		"grab": {"size": Vector2(28, 28), "at": Vector2(0, 0)},
	},
	# Drawn from above and to one side (D69), so its lever and its base are parallelograms:
	# each is a stack of boxes that stops short of the empty corners, and the daylight
	# between the two plungers stays open.
	&"hole_punch": {
		"shapes": [
			{"rect": Vector2(27, 7), "at": Vector2(0.5, -7.5)},
			{"rect": Vector2(7, 4), "at": Vector2(-5.5, -1.5)},
			{"rect": Vector2(7, 4), "at": Vector2(4.5, -1.5)},
			{"rect": Vector2(24, 4), "at": Vector2(1, 2)},
			{"rect": Vector2(27, 4), "at": Vector2(-0.5, 6)},
			{"rect": Vector2(25, 3), "at": Vector2(-2.5, 9.5)},
		],
		"com": Vector2(0, 2),
		"grip": Vector2(0, -8),
		"grab": {"size": Vector2(32, 26), "at": Vector2(-0.5, 0)},
	},
	# Gripped at one end, because a keyboard swung by its corner is a plank on a string and
	# in this one case that is exactly the joke.
	&"mechanical_keyboard": {
		"shapes": [
			{"rect": Vector2(57, 28), "at": Vector2(-0.5, 0)},
		],
		# Under the keys, not in them: the weight of a mechanical board is its steel plate.
		"com": Vector2(0, 6),
		"grip": Vector2(-27, 0),
		"grab": {"size": Vector2(60, 30), "at": Vector2(-0.5, 0)},
	},
	# Panel, neck and foot as three shapes, so it can land on the foot and stand up. Held
	# by the foot, which is how a monitor comes off a desk in a hurry.
	&"monitor": {
		"shapes": [
			{"rect": Vector2(52, 33), "at": Vector2(-0.5, -9.5)},
			{"rect": Vector2(10, 13), "at": Vector2(-0.5, 13.5)},
			{"rect": Vector2(28, 6), "at": Vector2(-0.5, 23)},
		],
		"com": Vector2(0, -8),
		"grip": Vector2(0, 23),
		"grab": {"size": Vector2(54, 36), "at": Vector2(0, -9)},
	},
}

# --- the roster ------------------------------------------------------------

## Two ladders, one row each.
##
## **Prices.** The melee ladder ran 0 / 250 / 900 / 3,500 and stopped. These continue it
## geometrically at about x1.45 a rung, from 1,200 to 250,000 — which is what puts a real
## purchase inside every five minutes of income for the whole of the mid-game rather than
## for the first hour of it (docs/economy.md, "no purchase more than ~5 minutes away").
##
## **`requires`.** Each rung is gated behind the rung below it in its *own* ladder, and the
## two ladders hang off different existing items: the blunt weapons off the `mace`, the
## desk objects off the `frying_pan`, which is already the catalogue's household object
## pressed into service. A player can chase either without being made to buy the other, and
## the Weapon page never opens showing fifteen unaffordable rows.
##
## **`mass` and `damage`.** Damage is contact impulse and impulse is mass x velocity (D7) —
## but the drag joint imparts a roughly fixed *velocity*, so a heavier body also swings
## slower and the two partly cancel. Mass is therefore character and `damage_mult` is the
## power knob: the ladder is ordered by multiplier, and mass says whether a rung feels like
## a sledgehammer or a golf club.
##
## The desk objects are the deliberate exception, and it is the funny one: they are light —
## a stapler is 2.5 against the sledgehammer's 24 — and they carry a high multiplier to
## make up for it. A stapler that weighs nothing and does nothing is not a joke, it is a
## dead shop row. Light and vicious is both the gag and a real play difference, because a
## light body reaches him faster and recovers faster between swings.
##
## **`sort`.** 40-54 is claimed by this tool so a second melee tool running in the same
## milestone cannot collide with it; within the band the order is by price, so the two
## ladders interleave into one sensible page.
const ROSTER := [
	{"id": &"rolling_pin", "node": "_RollingPin", "name": "Rolling Pin", "cost": 1200,
		"sort": 40, "mass": 7.0, "damage": 1.10, "requires": [&"mace"],
		"text": "Kitchen issue. It does not look like a weapon right up until it is one."},
	{"id": &"stapler", "node": "_Stapler", "name": "Stapler", "cost": 1750,
		"sort": 41, "mass": 2.5, "damage": 1.35, "requires": [&"frying_pan"],
		"text": "It weighs nothing and it hurts enormously. Nobody has explained this."},
	{"id": &"crowbar", "node": "_Crowbar", "name": "Crowbar", "cost": 2600,
		"sort": 42, "mass": 11.0, "damage": 1.30, "requires": [&"rolling_pin"],
		"text": "Opens crates, opens doors, opens him."},
	{"id": &"office_mug", "node": "_OfficeMug", "name": "Office Mug", "cost": 3800,
		"sort": 43, "mass": 4.0, "damage": 1.50, "requires": [&"stapler"],
		"text": "Glazed, chipped and still full. Half a kilo of somebody else's coffee."},
	{"id": &"cricket_bat", "node": "_CricketBat", "name": "Cricket Bat", "cost": 5500,
		"sort": 44, "mass": 6.0, "damage": 1.45, "requires": [&"crowbar"],
		"text": "A flat willow face the size of his whole ribcage. Middle it."},
	{"id": &"tyre_iron", "node": "_TyreIron", "name": "Tyre Iron", "cost": 8000,
		"sort": 45, "mass": 9.0, "damage": 1.55, "requires": [&"cricket_bat"],
		"text": "Kept in the boot for emergencies. This counts."},
	{"id": &"hole_punch", "node": "_HolePunch", "name": "Hole Punch", "cost": 11500,
		"sort": 46, "mass": 6.0, "damage": 1.70, "requires": [&"office_mug"],
		"text": "A block of cast steel that exists to make confetti. It moonlights."},
	{"id": &"sledgehammer", "node": "_Sledgehammer", "name": "Sledgehammer", "cost": 17000,
		"sort": 47, "mass": 24.0, "damage": 1.65, "requires": [&"tyre_iron"],
		"text": "Twelve pounds of steel on a long stick. The swing takes a while and it is worth the wait."},
	{"id": &"pipe_wrench", "node": "_PipeWrench", "name": "Pipe Wrench", "cost": 25000,
		"sort": 48, "mass": 16.0, "damage": 1.75, "requires": [&"sledgehammer"],
		"text": "Cast iron, adjustable, and far heavier than anything a plumber needs."},
	{"id": &"mechanical_keyboard", "node": "_MechanicalKeyboard", "name": "Mechanical Keyboard",
		"cost": 36000, "sort": 49, "mass": 8.0, "damage": 1.95, "requires": [&"hole_punch"],
		"text": "Eighty-seven switches on a brass plate. It sounds incredible when it lands."},
	{"id": &"golf_club", "node": "_GolfClub", "name": "Golf Club", "cost": 52000,
		"sort": 50, "mass": 4.0, "damage": 1.90, "requires": [&"pipe_wrench"],
		"text": "Long shaft, small head, enormous head speed. Keep your eye on him."},
	{"id": &"nunchaku", "node": "_Nunchaku", "name": "Nunchaku", "cost": 76000,
		"sort": 51, "mass": 5.0, "damage": 2.05, "requires": [&"golf_club"],
		"text": "Mostly you hit yourself. Occasionally you hit him, and it is spectacular."},
	{"id": &"monitor", "node": "_Monitor", "name": "Monitor", "cost": 110000,
		"sort": 52, "mass": 14.0, "damage": 2.30, "requires": [&"mechanical_keyboard"],
		"text": "Twenty-seven inches, one VESA mount and one careless swing. There goes the deposit."},
	{"id": &"morning_star", "node": "_MorningStar", "name": "Morning Star", "cost": 165000,
		"sort": 53, "mass": 19.0, "damage": 2.25, "requires": [&"nunchaku"],
		"text": "The mace, after it took up a hobby."},
	{"id": &"flail", "node": "_Flail", "name": "Flail", "cost": 250000,
		"sort": 54, "mass": 22.0, "damage": 2.45, "requires": [&"morning_star"],
		"text": "A ball of iron on a chain. Neither you nor it knows where it is going."},
]

# --- augments --------------------------------------------------------------

## cost = FLOOR + item cost x SLOPE for the damage node; the other two are fractions of it.
## The same rule `seed_m35_trees.gd` uses, so a tree written here and a tree written there
## sit in the same page without a visible seam.
const COST_FLOOR := 50.0
const COST_SLOPE := 0.045
const PAYOUT_FRACTION := 0.78
const THIRD_FRACTION := 0.61

## `item id: [damage name, payout name, third name]`. Hand-written, because
## "Sledgehammer +15% damage" is a spreadsheet row and "Demolition Fee" is a joke about
## what the player is doing.
const TREES := {
	&"rolling_pin": ["Hardwood Core", "Baker's Cut", "Marble Fill"],
	&"crowbar": ["Longer Bar", "Prybar Levy", "Forged Solid"],
	&"cricket_bat": ["Sweet Spot", "Boundary Bonus", "Denser Willow"],
	&"tyre_iron": ["Better Leverage", "Roadside Rates", "Drop-Forged"],
	&"sledgehammer": ["Bigger Head", "Demolition Fee", "Cast Steel Head"],
	&"pipe_wrench": ["Wider Jaw", "Call-Out Fee", "Cast Handle"],
	&"golf_club": ["Better Follow-Through", "Green Fees", "Tungsten Sole"],
	&"nunchaku": ["Wrist Snap", "Dojo Rates", "Oak Handles"],
	&"morning_star": ["Longer Spikes", "Tournament Purse", "Denser Head"],
	&"flail": ["Wicked Spikes", "Chain of Custody", "Lead-Filled Head"],
	&"stapler": ["Heavy-Duty Staples", "Stationery Budget", "Full Strip Loaded"],
	&"office_mug": ["Kiln-Fired Twice", "Break Room Rates", "Full of Cold Coffee"],
	&"hole_punch": ["Twelve-Sheet Capacity", "Confetti Rights", "Cast Steel Base"],
	&"mechanical_keyboard": ["Heavier Switches", "Productivity Bonus", "Brass Weight"],
	&"monitor": ["Higher Refresh Rate", "Depreciation Claim", "Steel Backplate"],
}

## Capstone numbers, derived from the item's own price by the rule in
## `tools/seed_m35_engine.gd`. Every weapon here is a Bones item, so only that tool's Bones
## line appears — the Hearts line has nothing to price in this roster.
const MAX_LEVELS := 30
const COST_GROWTH := 1.10
const BASE_RATE := 1.0
const RATE_SLOPE := 1.0 / 500.0
const PRICE_FLOOR := 800.0
const PRICE_SLOPE := 0.4

## `item id: [augment id, device name, description]`. The rule sets the numbers; the
## fiction is hand-authored, because a device on the desk is a thing the player looks at.
const DEVICES := {
	&"rolling_pin": [&"rolling_pin_bakery", "Bakery Line",
		"A pin on rails, flattening whatever is on the bench. He is on the bench."],
	&"crowbar": [&"crowbar_jimmy", "The Jimmy",
		"A pry bar on a cam that opens things. He counts as a thing."],
	&"cricket_bat": [&"cricket_bat_nets", "The Nets",
		"A bowling machine, a bat on a spring, and one skeleton at silly point."],
	&"tyre_iron": [&"tyre_iron_pit_crew", "Pit Crew",
		"Four seconds, every four seconds. Nobody is changing a tyre."],
	&"sledgehammer": [&"sledgehammer_demolition", "Demolition Rig",
		"A hammer on a counterweight, dropping on the hour and every minute in between."],
	&"pipe_wrench": [&"pipe_wrench_plumber", "The Plumber",
		"Called out, arrives, tightens something. It was never loose."],
	&"golf_club": [&"golf_club_range", "Driving Range",
		"A tee, a swing arm and a bucket that never empties."],
	&"nunchaku": [&"nunchaku_dojo", "The Dojo",
		"Two sticks, one motor and absolutely no supervision."],
	&"morning_star": [&"morning_star_gantry", "Siege Gantry",
		"It was built to bring down a gate. There is no gate."],
	&"flail": [&"flail_wrecking_yard", "Wrecking Yard",
		"A crane, a chain and a very heavy ball, swinging over one desk."],
	&"stapler": [&"stapler_collator", "The Collator",
		"An office stapler on a timer, working through a stack that is not paper."],
	&"office_mug": [&"office_mug_hot_desk", "Hot Desk",
		"The mug returns to its coaster. The coaster is on a rail, and the rail points at him."],
	&"hole_punch": [&"hole_punch_filing", "Filing System",
		"Everything gets two holes. Everything."],
	&"mechanical_keyboard": [&"keyboard_autotype", "Autotype",
		"It is typing something. It is typing it very hard."],
	&"monitor": [&"monitor_second_screen", "Second Screen",
		"You did not need two. He definitely did not."],
}

## Half the weapon's own price. A branch is bought once and it changes what the weapon *is*,
## so it should cost about what half a new toy does — well above a tier-1 level and well
## below starting the ladder again.
const BRANCH_FRACTION := 0.5

## Tier-2 exclusive branches, for the two weapons that have a genuine three-way identity
## rather than a preference. Everything else in this tool is one idea done well, and giving
## fifteen weapons a pick-one tier would make the choice mean nothing fifteen times.
##
## `[augment id, name, description, effect key, effect]` — max one level, pick one per
## (item, group), gated on Mastery 10 like `bat_slugger` and friends. The third option in
## each is the pillow-bat move: a *worse* weapon that is funnier, which is the reason the
## exclusive tier exists at all.
const BRANCHES := {
	&"sledgehammer": [
		[&"sledgehammer_dead_blow", "Dead Blow",
			"It does not bounce. Whatever it lands on absorbs the lot.", &"damage_mult", 1.6],
		[&"sledgehammer_scrap", "Scrap Merchant",
			"Every swing is billed by the kilo.", &"payout_mult", 1.8],
		[&"sledgehammer_mallet", "Rubber Mallet",
			"Twelve pounds of soft rubber. Enormously loud, entirely harmless.",
			&"damage_mult", 0.35],
	],
	&"monitor": [
		[&"monitor_ultrawide", "Ultrawide",
			"More screen. More of it lands.", &"damage_mult", 1.6],
		[&"monitor_warranty", "Warranty Claim",
			"Accidental damage is covered. It is not accidental.", &"payout_mult", 1.8],
		[&"monitor_screensaver", "Screensaver",
			"You turn it towards him instead. He watches the pipes for hours.",
			&"damage_mult", 0.35],
	],
}

var _force := false
## `--only id,id`: rewrite those ids' scenes and nothing else (D61). The way to re-seed a body
## after its physics row changes — `--force` would also rewrite every item and augment this tool
## owns, including the ones later milestones refined; D55 tried that and the suite caught it.
var _only := PackedStringArray()
var _written := 0
var _skipped := 0

func _ready() -> void:
	_force = OS.get_cmdline_user_args().has("--force")
	var only_at := OS.get_cmdline_user_args().find("--only")
	if only_at >= 0 and only_at + 1 < OS.get_cmdline_user_args().size():
		_only = OS.get_cmdline_user_args()[only_at + 1].split(",", false)
	for dir in [BODIES_DIR, ITEMS_DIR, AUGMENTS_DIR]:
		DirAccess.make_dir_recursive_absolute(dir)

	# Scenes first and in full, so no ItemData is ever written pointing at a scene this run
	# has not produced yet.
	for entry in ROSTER:
		_scene_for(entry)
	for entry in ROSTER:
		_item_for(entry)
		_tree_for(entry)
		_capstone_for(entry)
		_branch_for(entry)

	print("seed_m36_melee_blunt: %d written, %d already present" % [_written, _skipped])
	get_tree().quit()

# --- scenes ----------------------------------------------------------------

func _scene_for(entry: Dictionary) -> void:
	var id: StringName = entry["id"]
	var path := "%s/%s.tscn" % [BODIES_DIR, id]
	if not _should_write(path):
		return
	var physics: Dictionary = PHYSICS[id]
	var root := ItemBodyBuilder.build({
		"name": entry["node"],
		"id": id,
		"script": WeaponBaseScript,
		"mass": entry["mass"],
		"properties": {"damage_mult": entry["damage"]},
		"shapes": physics["shapes"],
		"com": physics["com"],
		"grip": physics["grip"],
		"grab": physics["grab"],
	})
	if root == null:
		return
	if ItemBodyBuilder.save_scene(root, path):
		_written += 1
		print("  wrote %s" % path)

# --- items -----------------------------------------------------------------

func _item_for(entry: Dictionary) -> void:
	var id: StringName = entry["id"]
	var path := "%s/%s.tres" % [ITEMS_DIR, id]
	if not _should_write(path):
		return
	var item := ItemDataScript.new()
	item.id = id
	item.display_name = entry["name"]
	item.description = entry["text"]
	item.category = ItemDataScript.CATEGORY_WEAPON
	item.cost = entry["cost"]
	item.currency = ItemDataScript.CURRENCY_BONES
	item.scene = _require("%s/%s.tscn" % [BODIES_DIR, id])
	item.sort_order = entry["sort"]
	var gate: Array[StringName] = []
	gate.assign(entry["requires"])
	item.requires = gate
	var icon := "%s/%s.png" % [ICONS_DIR, id]
	if ResourceLoader.exists(icon):
		item.icon = ResourceLoader.load(icon)
	_save(item, path)

# --- trees -----------------------------------------------------------------

func _tree_for(entry: Dictionary) -> void:
	var id: StringName = entry["id"]
	var names: Array = TREES[id]
	var base := COST_FLOOR + float(entry["cost"]) * COST_SLOPE
	_tier_one("%s_damage" % id, id, names[0], &"damage_mult", 1.15,
		int(round(base)), 1.12, 0)
	_tier_one("%s_payout" % id, id, names[1], &"payout_mult", 1.12,
		int(round(base * PAYOUT_FRACTION)), 1.10, 1)
	# Weight, on every one of them: these are all physical bodies swung by hand, so the
	# third lever is mass — which is impulse, and therefore felt in the swing rather than
	# only in the number over his head.
	_tier_one("%s_third" % id, id, names[2], &"mass_mult", 1.08,
		int(round(base * THIRD_FRACTION)), 1.09, 2)

func _tier_one(node_id: String, item_id: StringName, display_name: String,
		effect_key: StringName, effect_per_level: float, cost_base: int,
		cost_growth: float, sort_order: int) -> void:
	var path := "%s/%s.tres" % [AUGMENTS_DIR, node_id]
	if not _should_write(path):
		return
	var node := AugmentNodeScript.new()
	node.id = StringName(node_id)
	node.item_id = item_id
	node.display_name = display_name
	node.effect_key = effect_key
	node.effect_per_level = effect_per_level
	node.max_levels = 10
	node.cost_base = cost_base
	node.cost_growth = cost_growth
	node.currency = AugmentNodeScript.CURRENCY_BONES
	node.sort_order = sort_order
	_save(node, path)

# --- capstones -------------------------------------------------------------

func _capstone_for(entry: Dictionary) -> void:
	var device: Array = DEVICES[entry["id"]]
	var path := "%s/%s.tres" % [AUGMENTS_DIR, device[0]]
	if not _should_write(path):
		return
	var node := AugmentNodeScript.new()
	node.id = device[0]
	node.item_id = entry["id"]
	node.display_name = device[1]
	node.description = device[2]
	node.tier = 3
	# A capstone's effect is its rate, not a multiplier, so effect_key is inert here and
	# effect_per_level stays 1.0 — see AugmentNode.automation_rate.
	node.effect_key = &"payout_mult"
	node.effect_per_level = 1.0
	node.max_levels = MAX_LEVELS
	node.cost_base = int(round(PRICE_FLOOR + float(entry["cost"]) * PRICE_SLOPE))
	node.cost_growth = COST_GROWTH
	# Hearts, whatever it automates. That is D2's spine: you cannot stop working for your
	# money without having been kind to him first.
	node.currency = AugmentNodeScript.CURRENCY_HEARTS
	node.is_automation = true
	# round(x * 100) / 100, not snappedf: snapping 2.8 returns the double one ulp above it,
	# which serialises as 2.8000000000000003. These files are read by people.
	var rate := BASE_RATE + float(entry["cost"]) * RATE_SLOPE
	node.automation_rate = round(rate * 100.0) / 100.0
	node.requires_mastery = ItemDB.balance.mastery_automation_rank
	# Every weapon in this tool stands on a tripod; the pedestal and the claw arm belong to
	# the kind things and the cursor powers.
	node.device_mount = &"tripod"
	_save(node, path)

# --- exclusive branches ----------------------------------------------------

func _branch_for(entry: Dictionary) -> void:
	var id: StringName = entry["id"]
	if not BRANCHES.has(id):
		return
	var cost := int(round(float(entry["cost"]) * BRANCH_FRACTION))
	var rows: Array = BRANCHES[id]
	for i in rows.size():
		var row: Array = rows[i]
		var path := "%s/%s.tres" % [AUGMENTS_DIR, row[0]]
		if not _should_write(path):
			continue
		var node := AugmentNodeScript.new()
		node.id = row[0]
		node.item_id = id
		node.display_name = row[1]
		node.description = row[2]
		node.tier = 2
		node.effect_key = row[3]
		node.effect_per_level = row[4]
		node.max_levels = 1
		node.cost_base = cost
		# Growth is meaningless at one level, and 1.0 is what the M3 branches carry.
		node.cost_growth = 1.0
		node.currency = AugmentNodeScript.CURRENCY_BONES
		node.exclusive_group = &"flavour"
		node.requires_mastery = 10
		node.sort_order = i
		_save(node, path)

# --- io --------------------------------------------------------------------

func _should_write(path: String) -> bool:
	if not _only.is_empty():
		if path.get_extension() == "tscn" and _only.has(path.get_file().get_basename()):
			return true
		_skipped += 1
		return false
	if _force or not ResourceLoader.exists(path):
		return true
	_skipped += 1
	return false

func _require(path: String) -> Resource:
	var res := ResourceLoader.load(path)
	if res == null:
		push_error("seed_m36_melee_blunt: cannot load %s — check the exact on-disk case" % path)
	return res

func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("seed_m36_melee_blunt: failed to write %s (error %d)" % [path, err])
		return
	_written += 1
	print("  wrote %s" % path)
