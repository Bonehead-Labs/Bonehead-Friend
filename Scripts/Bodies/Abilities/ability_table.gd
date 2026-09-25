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
##   archetype  `charge`, `dash`, `stun`, `sustain`, `shockwave`, `projectile`, `spin`, `throw`
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
}

const ABILITIES := {
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

	# --- the blades (D74, 2026-09-26) ---------------------------------------------------------
	# Nine edges, nine verbs: a flywheel, a lodged blade, a clearing swipe, a trip, a ghost, a
	# guard, a flurry, a burst and a dart. Each hooked row's script says what its archetype lacks.

	# Hold: the grip loosens, a heave starts it round and the wrist keeps it turning at 6 rad/s,
	# never braking it; each hit without it stopping adds x0.15, to x1.6. Notches count the chain.
	&"greatsword": {
		"id": &"momentum", "name": "Momentum", "archetype": &"sustain",
		"script": "res://Scripts/Bodies/Abilities/momentum_ability.gd",
		"controls": "Hold · Right: Momentum — keep it swinging; each hit that doesn't stop it hits harder",
		"cooldown": 6.0, "busy": 4.0, "worth": 1.2,
		"fuel_seconds": 4.0, "heave": 6.0, "carry_spin": 6.0, "carry_accel": 40.0, "keep_speed": 220.0,
		"stop_grace": 0.3, "step_mult": 0.15, "max_mult": 1.6,
	},
	# Thrown end over end; in him, it stays in him for 3 s and works in a light hit every half second,
	# then drops out at his feet.
	&"cleaver": {
		"id": &"embed", "name": "Embed", "archetype": &"throw",
		"script": "res://Scripts/Bodies/Abilities/embed_ability.gd",
		"controls": "Hold · Right: Embed — throw it; it sticks in him and keeps biting",
		"cooldown": 5.0, "busy": 3.6, "worth": 3.0,
		"throw_speed": 1000.0, "spin": 14.0, "hit_force": 1800.0, "throw_mult": 1.0, "shove": 0.4,
		"out_seconds": 0.7, "lodge_seconds": 3.0, "tick_seconds": 0.5, "tick_force": 600.0,
		"tick_mult": 1.0, "give_up_seconds": 3.0,
	},
	# One wide chest-high swipe: everything in the 120 degrees in front is thrown away from you.
	&"machete": {
		"id": &"brush_clear", "name": "Brush Clear", "archetype": &"shockwave",
		"script": "res://Scripts/Bodies/Abilities/brush_clear_ability.gd",
		"controls": "Hold · Right: Brush Clear — one wide swipe clears everything in front of you",
		"cooldown": 4.0, "busy": 0.5, "worth": 1.0,
		"wind_px": 40.0, "wind_seconds": 0.08, "swipe_px": 90.0, "swipe_seconds": 0.12,
		"recover_seconds": 0.2, "whip": 12.0, "radius": 260.0, "cone_degrees": 120.0, "pop": 950.0,
		"lift_degrees": 20.0, "wave_mult": 1.2, "claim_seconds": 1.5,
	},
	# The hand drops to the desk and sweeps a low arc under him and back: caught by the feet, he goes
	# head over heels toward you.
	&"sickle": {
		"id": &"reap", "name": "Reap", "archetype": &"dash",
		"script": "res://Scripts/Bodies/Abilities/reap_ability.gd",
		"controls": "Hold · Right: Reap — a low sweep that takes his feet out from under him",
		"cooldown": 4.0, "busy": 0.7, "worth": 1.2,
		"drop_seconds": 0.1, "sweep_seconds": 0.16, "pull_seconds": 0.12, "return_seconds": 0.2,
		"floor_gap": 14.0, "sweep_px": 240.0, "feet_share": 0.45, "reap_force": 1800.0,
		"reap_mult": 1.2, "pull": 260.0, "lift": 520.0, "flip": 13.0, "claim_seconds": 1.5,
		"settle_seconds": 1.0,
	},
	# Hold and flick: a ghost of the blade leaves it the way the hand went, at the hand's speed, and
	# passes through him. The one ranged ability the player aims.
	&"scythe": {
		"id": &"soul_reap", "name": "Soul Reap", "archetype": &"projectile",
		"script": "res://Scripts/Bodies/Abilities/soul_reap_ability.gd",
		"controls": "Hold · Right: Soul Reap — hold and swing; the blade's ghost flies on through him",
		"cooldown": 4.0, "busy": 1.0, "worth": 1.8,
		"arm_seconds": 2.0, "release_speed": 600.0, "ghost_min": 700.0, "ghost_max": 1300.0,
		"ghost_range": 620.0, "assist_degrees": 30.0, "reap_force": 2600.0, "reap_speed": 1000.0,
		"reap_mult": 1.0, "shove": 0.15,
	},
	# Hold: it points itself at him like a held gun (D56); a thrust along the blade is x2, a swipe
	# across it x0.5.
	&"rapier": {
		"id": &"en_garde", "name": "En Garde", "archetype": &"sustain",
		"script": "res://Scripts/Bodies/Abilities/en_garde_ability.gd",
		"controls": "Hold · Right: En Garde — it points at him; lunge for x2, a swipe is half",
		"cooldown": 5.0, "busy": 3.0, "worth": 1.5,
		"guard_seconds": 4.0, "aim_frequency": 18.0, "aim_damping": 0.8, "aim_accel": 260.0,
		"thrust_speed": 220.0, "thrust_mult": 2.0, "swipe_mult": 0.5,
	},
	# Hold near him: the hand jabs six times a second for two seconds, every jab a real contact.
	&"katar": {
		"id": &"flurry", "name": "Flurry", "archetype": &"sustain",
		"script": "res://Scripts/Bodies/Abilities/flurry_ability.gd",
		"controls": "Hold · Right: Flurry — hold it near him and it jabs six times a second",
		"cooldown": 5.0, "busy": 2.0, "worth": 1.8,
		"fuel_seconds": 2.0, "jab_rate": 6.0, "jab_px": 50.0, "jab_draw": 0.2, "jab_out": 0.3,
		"kick": 300.0, "reach": 150.0, "aim_frequency": 16.0, "aim_accel": 320.0,
	},
	# Tap: click-click-click, three snapped-off blade tips flicked at him dead straight.
	&"boxcutter": {
		"id": &"snap", "name": "Snap", "archetype": &"projectile",
		"script": "res://Scripts/Bodies/Abilities/snap_ability.gd",
		"controls": "Hold · Right: Snap — three blade tips, snapped off and flicked straight at him",
		"cooldown": 3.0, "busy": 0.4, "worth": 1.5,
		"shots": 3.0, "shot_gap": 0.12, "tip_speed": 1400.0, "tip_force": 1300.0, "tip_mult": 1.0,
		"shove": 0.4, "range": 700.0, "recoil": 60.0,
	},
	# Tap: point-first in a dead straight line, x2 on the point, and it sticks where it lands. The
	# cooldown starts when you fetch it, so `busy` counts the walk.
	&"letter_opener": {
		"id": &"special_delivery", "name": "Special Delivery", "archetype": &"throw",
		"script": "res://Scripts/Bodies/Abilities/delivery_ability.gd",
		"controls": "Hold · Right: Special Delivery — thrown point-first; go and fetch it",
		"cooldown": 1.0, "busy": 3.0, "worth": 1.3,
		"throw_speed": 1500.0, "point_force": 1600.0, "point_mult": 2.0, "shove": 0.5,
		"align_frequency": 30.0, "flight_seconds": 1.2, "quiver_seconds": 0.6, "give_up_seconds": 3.0,
	},

	# --- the blunt and desk nine (D74, second pass) -------------------------------------------
	# A tap: the five spikes facing him leave the head in a flat fan; the star is bald on that side
	# until the cooldown has grown them back, one pop at a time. Close in, the whole fan lands.
	&"morning_star": {
		"id": &"bristle", "name": "Bristle", "archetype": &"projectile",
		"script": "res://Scripts/Bodies/Abilities/bristle_ability.gd",
		"controls": "Hold · Right: Bristle — fire its spikes at him; they grow back",
		"cooldown": 5.0, "busy": 0.3, "worth": 1.7,
		"spikes": 5, "fan_degrees": 20.0, "spike_speed": 1500.0, "spike_force": 1400.0,
		"spike_mult": 1.0, "shove": 0.35,
	},
	# A tap lights the middle third of the face for 2 s; a hit with it on him is x2.5 and a six,
	# straight up. Off the edge it is an ordinary hit and the light stays on: it is aimed, not armed.
	# The middle meets him when the face comes through him; a fast flat sweep leads with the
	# handle, and a hand held high grazes his skull with the toe.
	&"cricket_bat": {
		"id": &"middle_it", "name": "Middle It", "archetype": &"stun",
		"script": "res://Scripts/Bodies/Abilities/middle_it_ability.gd",
		"controls": "Hold · Right: Middle It — then hit him off the glowing middle for six",
		"cooldown": 5.0, "busy": 1.5, "worth": 1.5,
		"armed_seconds": 2.0, "middle_band": 0.34, "middle_mult": 2.5, "six_speed": 950.0,
		"keep_sideways": 0.3, "claim_seconds": 2.5,
	},
	# Held: the pin goes down level on the desk and rolls where the hand takes it; each pass over
	# his middle flattens him (a squash on his sprite) and is billed once, x1.5.
	&"rolling_pin": {
		"id": &"flatten", "name": "Flatten", "archetype": &"sustain",
		"script": "res://Scripts/Bodies/Abilities/flatten_ability.gd",
		"controls": "Hold · Right: Flatten — hold it down and roll it over him",
		"cooldown": 5.0, "busy": 2.5, "worth": 2.5,
		"fuel_seconds": 2.5, "lay_frequency": 12.0, "lay_accel": 300.0, "ride_px": 16.0,
		"over_px": 34.0, "reach": 240.0, "roll_force": 1000.0, "roll_speed": 450.0,
		"flatten_mult": 1.5, "pass_gap": 0.35, "shove": 0.1,
	},
	# Held: five staples a second, dead straight at him, twenty to a strip; the strip running out
	# is the reload. The only melee ability you hold down to keep firing. A staple is x0.3 of the
	# stapler's own blow: at full weight one strip was fourteen ordinary hits.
	&"stapler": {
		"id": &"staple_gun", "name": "Staple Gun", "archetype": &"projectile",
		"script": "res://Scripts/Bodies/Abilities/staple_gun_ability.gd",
		"controls": "Hold · Right: Staple Gun — hold to staple him, twenty to a strip",
		"cooldown": 6.0, "busy": 4.0, "worth": 4.0,
		"rate": 5.0, "strip": 20, "staple_speed": 1400.0, "staple_force": 420.0,
		"staple_mult": 0.3, "shove": 0.15, "pause": 0.4,
	},
	# A tap throws it into the desk (or along a flick); every surface it meets banks it straight at
	# him, faster each time, and a hit after the nth bank is x(1 + 0.25n). Three banks, then it
	# falls where it falls and you go and get it.
	&"tyre_iron": {
		"id": &"ricochet", "name": "Ricochet", "archetype": &"throw",
		"script": "res://Scripts/Bodies/Abilities/ricochet_ability.gd",
		"controls": "Hold · Right: Ricochet — throw it at the desk and it banks into him",
		"cooldown": 3.0, "busy": 2.0, "worth": 2.4,
		"throw_speed": 1300.0, "flick_speed": 450.0, "skip_degrees": 55.0, "spin": 18.0,
		"banks": 3, "bank_speed": 1300.0, "bank_gain": 0.1, "hit_force": 2000.0,
		"bank_mult": 0.25, "shove": 0.5, "give_up_seconds": 3.5,
	},
	# Held: a crosshair walks from the beak onto his skull and locks; let go and the beak goes into
	# that one spot, x2.5 with almost no shove. Let go early and the spot is wherever it had got to.
	&"war_pick": {
		"id": &"pinpoint", "name": "Pinpoint", "archetype": &"charge",
		"script": "res://Scripts/Bodies/Abilities/pinpoint_ability.gd",
		"controls": "Hold · Right: Pinpoint — hold till it locks on him, let go to strike",
		"cooldown": 5.0, "busy": 1.4, "worth": 2.7,
		"charge_seconds": 0.8, "cock_degrees": 70.0, "cock_frequency": 12.0, "cock_accel": 220.0,
		"raise_px": 36.0, "drive_seconds": 0.09, "hold_seconds": 0.16, "return_seconds": 0.2,
		"reach": 260.0, "pin_radius": 32.0, "pick_force": 1800.0, "pick_speed": 1300.0,
		"pick_mult": 2.5, "shove": 0.15, "settle_seconds": 0.8,
	},
	# A tap: eight caps pop off in a fountain, come down on his head one after another, and fly
	# home to their keys with a clack. Light hits; the fun is the rain.
	&"mechanical_keyboard": {
		"id": &"keycap_barrage", "name": "Keycap Barrage", "archetype": &"projectile",
		"script": "res://Scripts/Bodies/Abilities/keycap_barrage_ability.gd",
		"controls": "Hold · Right: Keycap Barrage — tap and its keys rain down on him",
		"cooldown": 4.5, "busy": 1.8, "worth": 2.0,
		"caps": 8, "rain_seconds": 0.75, "stagger": 0.05, "spread": 40.0, "cap_force": 500.0,
		"cap_mult": 1.0, "shove": 0.25, "home_after": 0.45, "home_seconds": 2.4,
	},
	# A tap near him: the screen goes blue and he is a statue for 1.5 s; every swing that clangs off
	# him is stored, and all are dealt on one frame at x1.3 when he comes back, which throws him.
	&"monitor": {
		"id": &"blue_screen", "name": "Blue Screen", "archetype": &"stun",
		"script": "res://Scripts/Bodies/Abilities/blue_screen_ability.gd",
		"controls": "Hold · Right: Blue Screen — freeze him; your hits land when he's back",
		"cooldown": 6.0, "busy": 1.8, "worth": 2.0,
		"reach": 420.0, "freeze_seconds": 1.5, "min_speed": 300.0, "hit_force": 1300.0,
		"swing_speed": 1100.0, "dump_mult": 1.3, "dump_shove": 0.5, "dump_cap": 900.0,
		"claim_seconds": 1.5,
	},
	# A tap: the coffee arcs out in a spatter; the first drop on him scalds (a light hit), stains
	# him (grime) and he steams for 1.2 s, the steam biting twice more.
	&"office_mug": {
		"id": &"hot_coffee", "name": "Hot Coffee", "archetype": &"projectile",
		"script": "res://Scripts/Bodies/Abilities/hot_coffee_ability.gd",
		"controls": "Hold · Right: Hot Coffee — splash him; it scalds and it stains",
		"cooldown": 4.0, "busy": 1.4, "worth": 1.2,
		"drops": 7, "splash_speed": 620.0, "whip": 9.0, "scald_force": 900.0, "scald_mult": 1.0,
		"shove": 0.2, "grime": 0.04, "steam_seconds": 1.2, "steam_ticks": 2, "steam_force": 450.0,
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
