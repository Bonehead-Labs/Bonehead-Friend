class_name AbilityTable
extends RefCounted

## Every held weapon's ability, one row per item (docs/decisions.md D74) — and since D78 every
## other held thing's it is plausible for: the balls, the care items, a box of donuts, two charges.
## The sibling of `tools/verb_table.gd` (D67): a row, not a script, for everything the archetype
## already does.
##
## **Read at runtime, not seeded into scenes.** `BaseDraggable._ready` asks `attach()` for its row
## and adds the archetype as a child. The verbs are seeded because their zones are geometry that sits
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
##              `transform`, `tether`, `clamp`, `fuse` (D78: a lit charge's second press)
##   kind       optional, true for an act of kindness (D78): it pays with `give`, never bills him,
##              and its `worth` is kindness value in pets, priced by `kindness_uplift`
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
	# D78: a lit charge's second right press takes its fuse over.
	&"fuse": "res://Scripts/Bodies/Abilities/fuse_ability.gd",
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

	# --- D78: beyond the melee drawer ---
	#
	# The same button on everything else it is plausible for (the design sheet is in D78). A row
	# marked `kind` pays Hearts through the bus (`WeaponAbility.give`) and never bills him, and its
	# `worth` is kindness value, in pets, that one use adds on top of what the item pays anyway —
	# `pacing_sim` prices it against petting (`kindness_uplift`), and no kind row may pay faster
	# than D67's ceiling for a hand-worked act, 1.5 value a second over its cycle. The rest are
	# harm, billed by him, their `worth` in ordinary hits (a charge's in ordinary blasts).
	#
	# Bowled, not thrown: down onto the desk and rolling at him with its topspin; the strike is billed
	# once at x1.5 and he goes over like a pin, his landing the ball's.
	&"bowling_ball": {
		"id": &"strike", "name": "Strike", "archetype": &"throw",
		"script": "res://Scripts/Bodies/Abilities/strike_ability.gd",
		"controls": "Hold · Right: Strike — tap: bowled along the desk, he goes over",
		"cooldown": 5.0, "busy": 1.5, "worth": 1.5,
		"roll_speed": 900.0, "hit_force": 8000.0, "strike_mult": 1.5, "shove": 0.1, "topple": 11.0,
		"lift": 260.0, "claim_seconds": 2.0, "out_seconds": 2.5,
	},
	# Pitched high over his glove, it breaks late and hard down into his hands; he holds it a moment
	# and throws it back to you. A caught curveball is two ordinary catches.
	&"baseball": {
		"id": &"curveball", "name": "Curveball", "archetype": &"throw", "kind": true,
		"script": "res://Scripts/Bodies/Abilities/curveball_ability.gd",
		"controls": "Hold · Right: Curveball — tap: it breaks late into his hands",
		"cooldown": 3.0, "busy": 1.6, "worth": 6.0,
		"throw_speed": 820.0, "break_height": 70.0, "break_distance": 150.0, "break_accel": 5200.0,
		"spin": 26.0, "curve_mult": 2.0, "hold_seconds": 0.6, "out_seconds": 1.4,
		"return_speed": 900.0, "return_accel": 5000.0, "catch_radius": 48.0, "give_up_seconds": 3.0,
	},
	# Tossed up by the press, struck by the release: at the top of the toss it goes flat and fast,
	# an ace; he volleys it back to the hand. A good serve is his catch and a share of an ace.
	&"tennis_ball": {
		"id": &"serve", "name": "Serve", "archetype": &"throw", "kind": true,
		"script": "res://Scripts/Bodies/Abilities/serve_ability.gd",
		"controls": "Hold · Right: Serve — hold to toss it up, let go at the top: an ace",
		"cooldown": 2.5, "busy": 1.8, "worth": 6.0,
		"toss_speed": 520.0, "window": 0.25, "min_speed": 500.0, "max_speed": 1150.0, "ace": 0.8,
		"ace_value": 6.0, "out_seconds": 1.2, "return_speed": 1000.0, "return_accel": 5000.0,
		"catch_radius": 48.0, "give_up_seconds": 3.0,
	},
	# Lobbed onto his head; he heads it back up four times, a count over his head, and the last one
	# home to the hand. Each header is an act.
	&"beach_ball": {
		"id": &"keepy_uppy", "name": "Keepy-Uppy", "archetype": &"throw", "kind": true,
		"script": "res://Scripts/Bodies/Abilities/keepy_uppy_ability.gd",
		"controls": "Hold · Right: Keepy-Uppy — tap: lobbed onto his head, he heads it up",
		"cooldown": 5.0, "busy": 4.5, "worth": 12.0,
		"lob_height": 200.0, "bounce_height": 150.0, "window": 46.0, "headers": 4, "header_value": 3.0,
		"hop": 170.0, "out_seconds": 2.5, "return_speed": 900.0, "return_accel": 5000.0,
		"catch_radius": 56.0, "give_up_seconds": 3.0,
	},
	# Squeezed over him, it rains; every drop on him takes grime off, paid as the sponge pays for
	# it, and the first is a rinse. Quicker than scrubbing, never richer.
	&"sponge": {
		"id": &"wring", "name": "Wring", "archetype": &"sustain", "kind": true,
		"script": "res://Scripts/Bodies/Abilities/wring_ability.gd",
		"controls": "Hold · Right: Wring — hold it over him: it rains, grime runs off",
		"cooldown": 4.0, "busy": 2.5, "worth": 2.0,
		"fuel_seconds": 2.0, "spin_up": 0.2, "tick_seconds": 0.08, "clean": 0.03, "rinse_value": 2.0,
		"squeeze": 0.25,
	},
	# It flutters on him and he giggles, an act every 0.3 s, for 2.4 s of fluttering.
	&"feather_duster": {
		"id": &"tickle", "name": "Tickle", "archetype": &"sustain", "kind": true,
		"script": "res://Scripts/Bodies/Abilities/tickle_ability.gd",
		"controls": "Hold · Right: Tickle — hold it on him: he can't stop giggling",
		"cooldown": 3.5, "busy": 2.4, "worth": 6.4,
		"fuel_seconds": 2.4, "spin_up": 0.25, "tick_seconds": 0.3, "giggle_value": 0.8, "reach": 14.0,
		"flutter": 0.3,
	},
	# Thrown round his shoulders, it stays there five seconds keeping him warm, with the hand free.
	&"warm_towel": {
		"id": &"swaddle", "name": "Swaddle", "archetype": &"throw", "kind": true,
		"script": "res://Scripts/Bodies/Abilities/swaddle_ability.gd",
		"controls": "Hold · Right: Swaddle — tap near him: it wraps round him, warm",
		"cooldown": 8.0, "busy": 5.5, "worth": 18.0,
		"reach": 300.0, "throw_speed": 650.0, "wrap_seconds": 5.0, "wrap_value": 3.0, "warm_rate": 3.0,
		"drape": 1.25, "out_seconds": 1.2,
	},
	# One donut flipped out of the box into his mouth: a helping the box would have paid anyway, and
	# a little for being hand-fed.
	&"donut_box": {
		"id": &"donut_toss", "name": "Donut Toss", "archetype": &"projectile", "kind": true,
		"script": "res://Scripts/Bodies/Abilities/donut_toss_ability.gd",
		"controls": "Hold · Right: Donut Toss — tap: one flips out into his mouth",
		"cooldown": 1.2, "busy": 0.9, "worth": 1.0,
		"toss_speed": 480.0, "reach": 380.0, "fed_bonus": 1.0, "spin": 5.0,
	},
	# Held up to him, the candles burn brighter as the wish gathers; let go, and he shuts his eyes,
	# takes a breath and blows them out. The wish is an act; the cake is still his to eat.
	&"birthday_cake": {
		"id": &"make_a_wish", "name": "Make a Wish", "archetype": &"charge", "kind": true,
		"script": "res://Scripts/Bodies/Abilities/make_a_wish_ability.gd",
		"controls": "Hold · Right: Make a Wish — hold it near him, let go: he blows them out",
		"cooldown": 6.0, "busy": 1.7, "worth": 8.0,
		"reach": 260.0, "charge_seconds": 1.2, "min_charge": 0.6, "blow_delay": 0.45, "wish_value": 8.0,
		"flame_rows": Vector2i(16, 19), "wicks": [Vector2(27, 18), Vector2(32, 18), Vector2(37, 18)],
	},
	# Lit, right again: on the clicker. It goes when it is clicked, wherever it is — stuck to him,
	# most likely — or after ten seconds.
	&"sticky_bomb": {
		"id": &"remote", "name": "Remote", "archetype": &"fuse",
		"script": "res://Scripts/Bodies/Abilities/remote_fuse.gd",
		"controls": "Hold · Right: Remote — lit, right again: it goes when you click it",
		"cooldown": 0.0, "busy": 3.0, "worth": 0.2,
		"wait_seconds": 10.0, "blink": 0.2,
	},
	# Lit, right again: set to burst over him. Thrown over him, it opens overhead and its bomblets
	# land in a ring round his feet.
	&"cluster_bomb": {
		"id": &"airburst", "name": "Airburst", "archetype": &"fuse",
		"script": "res://Scripts/Bodies/Abilities/airburst_fuse.gd",
		"controls": "Hold · Right: Airburst — lit, right again, throw over him: it opens",
		"cooldown": 0.0, "busy": 2.0, "worth": 0.5,
		"wait_seconds": 4.0, "window": 90.0, "height": 60.0, "ring": 90.0,
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

## Gives a held thing its ability, if this table has one for it. Called by every `BaseDraggable` on
## `_ready` (a weapon since D74, anything since D78); does nothing to the rest. Returns the ability,
## or null.
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
	ability.body = weapon as BaseDraggable
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
## share of damage by it. One for a weapon with no ability, and for a kind row, which deals none.
static func damage_uplift(item_id: StringName, hits_per_second: float) -> float:
	var row := row_for(item_id)
	if row.is_empty() or hits_per_second <= 0.0 or bool(row.get("kind", false)):
		return 1.0
	# A charge is used once a throw, and its ability rides every throw it is used on: its `worth`
	# is in ordinary blasts of itself, so each throw deals `1 + worth` of one (D78).
	if StringName(row.get("archetype", &"")) == &"fuse":
		return 1.0 + float(row.get("worth", 0.0))
	return 1.0 + float(row.get("worth", 0.0)) / (hits_per_second * cycle_seconds(item_id))

## Whether an item's ability is an act of kindness (D78): it pays Hearts on the bus and bills
## nothing.
static func is_kind(item_id: StringName) -> bool:
	return bool(row_for(item_id).get("kind", false))

## One use and the wait after it: what a player who uses it every time it is ready spends per use.
static func cycle_seconds(item_id: StringName) -> float:
	var row := row_for(item_id)
	return maxf(float(row.get("cooldown", 3.0)) + float(row.get("busy", 1.0)), 0.5)

## D67's ceiling for anything worked by hand on the kind side, which D78 holds every kind row to:
## no faster than this much kindness value a second, however fast it is used.
const KIND_CEILING := 1.5

## Kindness value a second a kind row adds when it is used every time it is ready (D78).
static func kindness_rate(item_id: StringName) -> float:
	if not is_kind(item_id):
		return 0.0
	return float(row_for(item_id).get("worth", 0.0)) / cycle_seconds(item_id)

## How much a player's kindness with this item goes up if they use its ability every time it is
## ready, given how many pets a second the model credits the hand with: the kind side's
## `damage_uplift`, the row's `worth` being kindness value in pets. `pacing_sim` multiplies the
## item's share of kindness by it. One for anything with no kind row.
static func kindness_uplift(item_id: StringName, pets_per_second: float) -> float:
	if not is_kind(item_id) or pets_per_second <= 0.0:
		return 1.0
	return 1.0 + kindness_rate(item_id) / pets_per_second
