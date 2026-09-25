class_name AbilityTable
extends RefCounted

## Every held weapon's ability, one row per item (docs/decisions.md D74). The sibling of
## `tools/verb_table.gd` (D67): a row, not a script, for everything the archetype already does.
##
## **Read at runtime, not seeded into scenes.** `WeaponBase._ready` asks `attach()` for its row and
## adds the archetype as a child. The verbs are seeded because their zones are geometry that sits
## beside the art; an ability is behaviour and tuning, and seeding it would mean re-running four
## seeders that own the weapons' scenes — one of which (`seed_bodies`) has no `--only` and would
## rewrite the grenade, the dynamite, the mine and the firework to reach the bat — for every number
## changed here. So it lives under `Scripts/`, which the export carries (`tools/` is excluded
## from it), and a scene never has to be touched to give its weapon an ability.
##
## ## A row
##
##   id         the ability's own name, `snake_case` — the key its sounds and his rows use
##   name       what the shop calls it
##   archetype  `charge`, `dash`, `stun`, `sustain`, `shockwave`, `projectile`, `spin`, `throw`,
##              `transform`, `tether`, `clamp`
##   script     optional: a subclass of the archetype, for a weapon whose ability needs a hook
##              its archetype lacks. The row still names the archetype it builds on
##   controls   the line `ItemData.controls` carries — written onto the item by
##              `tools/seed_m311_abilities.tscn`, which reads this table
##   cooldown   seconds after the effect ends before it can be used again
##   busy       seconds one use takes, press to done — for `pacing_sim`
##   worth      extra ordinary hits' worth of damage one use adds — for `pacing_sim`, which
##              prices every ability by it; `ability_check` measures each and fails a row that
##              understates what it pays by more than half
##   ...        the archetype's own numbers: see the class comment of each archetype script
##
## ## The rules every row keeps
##
## - **It never mints.** An ability moves bodies, scales the weapon's own multiplier for a hit, or
##   hands him an impulse through `take_impulse`; he bills all of it (D7, D64).
## - **It feels like nothing else.** Two weapons on one archetype must differ in what the player
##   *does*, not only in a number: the design sheet in D74 gives every melee weapon one.
## - **Its line teaches it.** `Hold · Right: <Name> — <what to do>`, one line.
## - **It costs nothing at rest** — the archetypes guarantee it, and `ability_check` asserts it.

const ARCHETYPES := {
	&"charge": "res://Scripts/Bodies/Abilities/charge_ability.gd",
	&"dash": "res://Scripts/Bodies/Abilities/dash_ability.gd",
	&"stun": "res://Scripts/Bodies/Abilities/stun_ability.gd",
	&"sustain": "res://Scripts/Bodies/Abilities/sustain_ability.gd",
	&"shockwave": "res://Scripts/Bodies/Abilities/shockwave_ability.gd",
	&"projectile": "res://Scripts/Bodies/Abilities/projectile_ability.gd",
	&"spin": "res://Scripts/Bodies/Abilities/spin_ability.gd",
	&"throw": "res://Scripts/Bodies/Abilities/throw_ability.gd",
	&"transform": "res://Scripts/Bodies/Abilities/transform_ability.gd",
	&"tether": "res://Scripts/Bodies/Abilities/tether_ability.gd",
	&"clamp": "res://Scripts/Bodies/Abilities/clamp_ability.gd",
}

const ABILITIES := {
	# --- the three archetypes the design sheet needed: transform, tether, clamp ---
	#
	# Four seconds of a mace twice as heavy, with a heart of lead beating in it: slower to bring
	# round, every blow x1.2 and the desk jolts under him. The weight is the body's own mass, so most
	# of the extra is in the swing, not the number: a blow measured 2.4 ordinary mace hits, five of
	# them a use. Hence the long cooldown.
	&"mace": {
		"id": &"lead_heart", "name": "Lead Heart", "archetype": &"transform",
		"controls": "Hold · Right: Lead Heart — for 4 s it weighs double and hits harder",
		"cooldown": 10.0, "busy": 4.0, "worth": 6.0,
		"seconds": 4.0, "mass_mult": 2.0, "hit_mult": 1.2, "quake": 7.0,
		"tint": "ff5a2e", "shade": "ff9c86", "glow": 0.7, "pulse": 0.7, "embers": "ff9a3c", "ember_at": 0.9,
		"ember_gravity": -70.0, "sound_on": &"heartbeat", "hum": &"heartbeat", "hum_seconds": 0.7,
		"tell": &"crushed",
	},
	# Four seconds lit: the blade goes through him without touching him, and every fifth of a second
	# of it inside him burns — a light hit that hops him, so the blade chases him round the desk.
	# Drawn through him for the four seconds, twelve burns: 3.5 ordinary sabre hits.
	&"energy_sabre": {
		"id": &"ignite", "name": "Ignite", "archetype": &"transform",
		"controls": "Hold · Right: Ignite — lit for 4 s, it passes through him and burns",
		"cooldown": 6.0, "busy": 4.0, "worth": 3.5,
		"seconds": 4.0, "phase": true, "burn_seconds": 0.2, "burn_force": 700.0, "burn_mult": 0.8,
		"shove": 0.3, "tint": "8ff8ff", "glow": 0.75, "embers": "d8fdff", "ember_at": 0.65,
		"ember_gravity": -40.0, "sound_on": &"ignite", "sound_off": &"hum", "hum": &"hum",
		"hum_seconds": 0.3, "tell": &"scorched",
	},
	# Hit him with right held and the chain wraps round him; while right stays down he is the ball
	# on 70 px of chain — he hangs from it, and whirls at 2,400 px/s when the hand goes round — and
	# letting go flings him the way he was going. The payoff is what he is swung into and where he
	# lands, which are the flail's: 1.8 to 2.4 ordinary flail hits a use.
	&"flail": {
		"id": &"wrap", "name": "Wrap", "archetype": &"tether",
		"controls": "Hold · Right: Wrap — hit him with it held, swing him, let go to fling",
		"cooldown": 6.0, "busy": 2.5, "worth": 2.4,
		"armed_seconds": 1.5, "catch_mult": 1.0, "hold_seconds": 2.5, "rope": 70.0, "stiffness": 14.0,
		"max_accel": 40000.0, "leash": 420.0, "reaction": 0.5, "fling_mult": 1.8, "fling_min": 800.0,
		"fling_max": 1800.0, "slam_mult": 1.0, "claim_seconds": 2.0,
		"tell": &"wrapped",
	},
	# A tap and the hook flies from the spike at him, up to 220 px; it catches and reels him in at
	# 900 px/s, and the spike meets him at x1.5 and throws him back off it. Reach, not swing. The
	# spike and the landing it throws him into measured 1.6 to 3.7 ordinary halberd hits.
	&"halberd": {
		"id": &"hook_and_spike", "name": "Hook and Spike", "archetype": &"tether",
		"script": "res://Scripts/Bodies/Abilities/hook_tether.gd",
		"controls": "Hold · Right: Hook and Spike — hook him from afar, onto the spike",
		"cooldown": 5.0, "busy": 0.8, "worth": 2.5,
		"reach": 220.0, "hook_speed": 1400.0, "reel_speed": 900.0, "reel_seconds": 0.8,
		"max_accel": 12000.0, "reaction": 0.4, "leash": 400.0, "spike_force": 2400.0,
		"spike_mult": 1.5, "shove": 0.8, "claim_seconds": 1.5,
	},
	# The claw against him, right held, and the hand pulled *down* levers him *up*: 1.2 px a pixel,
	# to 90 px, tipping him away from the bar. Let go and he pops up and over, spinning. The pry at
	# x1.3 and where he lands: 1.6 to 2.3 ordinary crowbar hits.
	&"crowbar": {
		"id": &"pry", "name": "Pry", "archetype": &"tether",
		"script": "res://Scripts/Bodies/Abilities/pry_tether.gd",
		"controls": "Hold · Right: Pry — claw against him, pull the hand down to lever",
		"cooldown": 5.0, "busy": 1.2, "worth": 2.3,
		"reach": 40.0, "lever_ratio": 1.2, "max_lift": 90.0, "lift_speed": 260.0, "tilt_degrees": 30.0,
		"hold_seconds": 2.5, "stiffness": 16.0, "max_accel": 9000.0, "reaction": 0.3,
		"pop": 950.0, "spin": 9.0, "pry_force": 2000.0, "pry_mult": 1.3, "claim_seconds": 2.0,
	},
	# Get him between the jaws and tap: one bite, x2, a burst of paper and a hole in him for three
	# seconds. A precise little verb: the jaws have to be on him, and then it always lands. One bite
	# measured 2.1 ordinary hole-punch hits.
	&"hole_punch": {
		"id": &"punch", "name": "Punch", "archetype": &"clamp",
		"controls": "Hold · Right: Punch — with him in the jaws: one hole, x2",
		"cooldown": 5.0, "busy": 0.2, "worth": 2.1,
		"jaw": Vector2(0, 4), "reach": 36.0, "touch": true, "bites": 1, "bite_gap": 0.1, "bite_force": 1200.0,
		"bite_mult": 2.0, "shove": 0.3, "snap": Vector2(1.0, 0.72), "bite_sound": &"chunk",
		"confetti": true, "hole_seconds": 3.0, "tell": &"punched",
	},
	# Two snips a seventh of a second apart on whatever is between the blades. At his head, the
	# first one takes his headphones off: they fall to the desk and he is bare-headed and cross for
	# four seconds, until they fly back on. Both snips on him: 2.0 ordinary shears hits.
	&"shears": {
		"id": &"snip", "name": "Snip", "archetype": &"clamp",
		"controls": "Hold · Right: Snip — two snips; at his head, off come the headphones",
		"cooldown": 4.0, "busy": 0.3, "worth": 2.0,
		"jaw": Vector2(0, -24), "reach": 18.0, "touch": true, "bites": 2, "bite_gap": 0.14, "bite_force": 800.0,
		"bite_mult": 1.0, "shove": 0.05, "snap": Vector2(0.55, 1.0), "bite_sound": &"snip",
		"snip_head": true, "head_band": 0.45, "head_reach": 60.0, "phones_seconds": 4.0,
	},
	# A tap with the jaws on him and they clamp on for two seconds: he is hoisted clear of the desk
	# on the wrench, and the hand going round him turns him like a nut, every half turn a creak. A turn and a third in the two
	# seconds, two cranks: 1.4 ordinary wrench hits.
	&"pipe_wrench": {
		"id": &"crank", "name": "Crank", "archetype": &"clamp",
		"controls": "Hold · Right: Crank — clamp it on him, then circle to turn him",
		"cooldown": 5.0, "busy": 2.2, "worth": 1.4,
		"jaw": Vector2(-14, -40), "reach": 22.0, "touch": true, "bites": 1, "bite_force": 900.0,
		"bite_mult": 1.0,
		"shove": 0.0, "snap": Vector2(0.85, 1.0), "bite_sound": &"clack", "hold_seconds": 2.0,
		"crank_lift": 96.0, "crank_rate": 14.0, "crank_force": 2400.0, "crank_mult": 1.0,
		"crank_hits": 4,
	},
	# The starter. A full wind-up is 0.9 s; the hit it arms is x2.5 and adds 850 px/s at 38 degrees
	# — he leaves at about 1,400 with the swing, a home run and not a launch into orbit. Where he
	# lands is the bat's for two seconds. One use measured at 1.4 ordinary bat hits' worth.
	&"baseball_bat": {
		"id": &"home_run", "name": "Home Run", "archetype": &"charge",
		"controls": "Hold · Right: Home Run — hold to wind up, let go to swing",
		"cooldown": 5.0, "busy": 1.7, "worth": 1.5,
		"charge_seconds": 0.9, "min_charge": 0.25, "hit_mult": 2.5, "window": 0.8,
		"whip": 12.0, "cock_degrees": 50.0, "cock_frequency": 14.0, "cock_accel": 260.0,
		"launch": 850.0, "launch_degrees": 38.0, "claim_seconds": 2.0,
	},
	# The draw, a lunge of up to 280 px through him, a held beat past him, and the cut lands 0.3 s
	# after the blade crossed him. It passes *through* him, so it is the one melee ability that never
	# touches him with the blade at all: the cut is billed from the blade's speed as it went through,
	# like a gunshot. The blade peaks near 2,800 px/s; the cut measured 3,640, 2.4 ordinary hits.
	&"katana": {
		"id": &"iaido", "name": "Iaido", "archetype": &"dash",
		"controls": "Hold · Right: Iaido — one draw, one cut, straight through him",
		"cooldown": 4.0, "busy": 0.9, "worth": 2.4,
		"draw_seconds": 0.12, "reach": 280.0, "overshoot": 70.0, "dash_seconds": 0.1,
		"hold_seconds": 0.12, "return_seconds": 0.22, "kick": 900.0, "delay": 0.3,
		"cut_force": 2600.0, "cut_speed": 1500.0, "cut_mult": 1.0, "shove": 0.6, "settle_seconds": 1.0,
	},
	# Ring it, then hit him: the BONG is x1.5 and dazes him for three seconds, in which every pan
	# hit is x1.3 and a note higher. A flurry, not a haymaker — the bat's opposite. x1.4 measured
	# 5.3 to 7.7 ordinary hits a use against an aggressive hand; x1.3 measures 3.7 to 4.3.
	&"frying_pan": {
		"id": &"bong", "name": "BONG", "archetype": &"stun",
		"controls": "Hold · Right: BONG — ring it, then hit him to daze him",
		"cooldown": 6.0, "busy": 4.0, "worth": 5.0,
		"armed_seconds": 2.0, "daze_seconds": 3.0, "bong_mult": 1.5, "bonus_mult": 1.3,
	},
	# Hold it on him: a grind every 0.13 s at 520, a light hit at the saw's own x2.9, for 2.5 s of
	# fuel, and the chain drags him onto the bar so it stays on him. About what swinging a 17 kg saw
	# earns for the same seconds, without having to swing it: the ability that pays for staying still.
	&"chainsaw": {
		"id": &"rev", "name": "Rev", "archetype": &"sustain",
		"controls": "Hold · Right: Rev — hold it down and the running chain grinds him",
		"cooldown": 5.0, "busy": 2.5, "worth": 3.0,
		"fuel_seconds": 2.5, "spin_up": 0.3, "tick_seconds": 0.13, "grind_force": 520.0,
		"shove": 0.35, "kick": 40.0, "rattle": 60.0, "reach": 6.0,
	},
	# Drive the head into the desk and the desk throws everything within 280 px up, 900 px/s at the
	# impact. The only ability that hits him without the weapon going near him: slammed 100 px from
	# him it threw him 145 px into the air, at x1.5 of the hammer's multiplier.
	&"sledgehammer": {
		"id": &"ground_pound", "name": "Ground Pound", "archetype": &"shockwave",
		"controls": "Hold · Right: Ground Pound — slam the desk and he goes up",
		"cooldown": 5.0, "busy": 0.6, "worth": 1.0,
		"raise_px": 50.0, "raise_seconds": 0.1, "plunge_seconds": 0.09, "recover_seconds": 0.25,
		"reach": 220.0, "slam_speed": 500.0, "radius": 280.0, "pop": 900.0, "lift_degrees": 25.0,
		"wave_mult": 1.5, "claim_seconds": 1.5,
	},
	# Tee up, fill the power, let go: a ball on the low arc through his middle, 2,200 at full power.
	# Too little power and the arc cannot reach him — the dots show it falling short.
	&"golf_club": {
		"id": &"drive", "name": "Drive", "archetype": &"projectile",
		"controls": "Hold · Right: Drive — hold to tee up, let go to drive a ball at him",
		"cooldown": 3.0, "busy": 1.0, "worth": 1.6,
		"charge_seconds": 0.8, "min_speed": 520.0, "max_speed": 1300.0, "ball_force": 2200.0,
		"ball_mult": 1.0, "shove": 0.5, "whip": 10.0,
	},
	# 1.2 s at 18 rad/s about the hand: every pass through him is a glancing hit (x0.6), as fast as the
	# per-source cooldown lets them land — four a use when the hand follows him, 2.5 turns.
	&"nunchaku": {
		"id": &"whirlwind", "name": "Whirlwind", "archetype": &"spin",
		"controls": "Hold · Right: Whirlwind — they spin about your hand",
		"cooldown": 6.0, "busy": 1.2, "worth": 3.5,
		"spin_seconds": 1.2, "spin_rate": 18.0, "spin_accel": 700.0, "spin_frequency": 20.0,
		"spin_mult": 0.6,
	},
	# Thrown at 1,100 px/s, spinning at 16 rad/s; the chop is 2,400 at that speed and x1.3, billed
	# once; and it comes back to the hand in about 0.4 s from a throw of 250 px.
	&"fire_axe": {
		"id": &"tomahawk", "name": "Tomahawk", "archetype": &"throw",
		"controls": "Hold · Right: Tomahawk — throw it; keep holding left and it comes back",
		"cooldown": 2.5, "busy": 1.2, "worth": 1.3,
		"throw_speed": 1100.0, "spin": 16.0, "hit_force": 2400.0, "throw_mult": 1.3, "shove": 0.5,
		"out_seconds": 0.55, "return_speed": 1200.0, "return_accel": 5000.0, "catch_radius": 48.0,
		"give_up_seconds": 3.0,
	},
}

static func has(item_id: StringName) -> bool:
	return ABILITIES.has(item_id)

## The row for an item, with its `archetype` resolved; empty for an item with none.
static func row_for(item_id: StringName) -> Dictionary:
	return ABILITIES.get(item_id, {})

## The line an item is taught by, or "" for one with no ability here.
static func controls(item_id: StringName) -> String:
	return String(row_for(item_id).get("controls", ""))

static func item_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ABILITIES:
		out.append(id)
	return out

## Gives a weapon its ability, if this table has one for it. Called by every `WeaponBase` on
## `_ready`; does nothing to the rest. Returns the ability, or null.
static func attach(weapon: Node) -> WeaponAbility:
	var item_id: StringName = weapon.get(&"item_id")
	if item_id == &"" or not ABILITIES.has(item_id):
		return null
	var row: Dictionary = ABILITIES[item_id]
	var script := _script_for(row)
	if script == null:
		push_error("AbilityTable: %s names no archetype this table knows (%s)"
			% [item_id, row.get("archetype", "")])
		return null
	var ability := script.new() as WeaponAbility
	if ability == null:
		push_error("AbilityTable: %s's script is not a WeaponAbility" % item_id)
		return null
	ability.name = "Ability"
	ability.row = row
	ability.body = weapon as WeaponBase
	weapon.add_child(ability)
	return ability

## Paths, not preloads: every archetype refers back to `WeaponBase`, which refers to this, and a
## preload cycle is a parse error that takes the whole autoload chain down with it (CLAUDE.md).
## Not cached here either — `ResourceLoader` already does, and a static holding a Resource keeps it
## alive past shutdown, where it reads as a leak (ExplosionUtil's note).
static func _script_for(row: Dictionary) -> Script:
	var path := String(row.get("script", ARCHETYPES.get(StringName(row.get("archetype", &"")), "")))
	if path.is_empty():
		return null
	return load(path) as Script

## How much a player's damage with this weapon goes up if they use its ability every time it is
## ready, given how many ordinary hits a second they land. `pacing_sim` multiplies the weapon's
## share of damage by it. One for a weapon with no ability.
static func damage_uplift(item_id: StringName, hits_per_second: float) -> float:
	var row := row_for(item_id)
	if row.is_empty() or hits_per_second <= 0.0:
		return 1.0
	var cycle := maxf(float(row.get("cooldown", 3.0)) + float(row.get("busy", 1.0)), 0.5)
	return 1.0 + float(row.get("worth", 0.0)) / (hits_per_second * cycle)
