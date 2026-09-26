class_name AbilityLooks
extends RefCounted

## What each ability looks like at each of D77's four stages, keyed by the ability's id (the key its
## sounds and his rows already use). The sibling of `AbilityTable`: that table is what an ability
## *does*, this one is how it *reads*, and neither needs the other to change. `AbilityFX` draws it;
## `WeaponAbility` calls it at its press, its `tell`s and its `paid_off`s.
##
## **A row is optional.** An ability with none gets the defaults: its glint, its name called out in
## gold, a generic badge on him for anything it tells him, and a middling payoff for anything it
## pays off. So a new ability reads as one of the family the day it lands, and gets a row when it
## deserves a colour and a word of its own.
##
## ## A row
##
##   colour   its accent: the flare, the rings, the badge's ring and its words' outline. Saturated
##            and not green — a green outline is keyed out with the chroma backdrop (D38)
##   call     the word it calls out as it starts (its name, by default)
##   go       a word for the moment it is let go, for an ability that has one (a drive's "FORE!")
##   land     the word for its payoff
##   burst    what its activation throws off the weapon: an `AbilityFX.ICONS` icon or a UI glyph
##   glint    where the ready glint sits, 0 at the hand to 1 at the far end (0.8 by default);
##            or `glint_at`, a point in the body's frame, for a weapon whose business end is not
##            its far end (the pan's face)
##   states   {event: spec}: the badge each thing it tells him puts over his head. `none` for an
##            event that shows nothing; see `AbilityFX.state` for the rest of a spec. `seconds` may
##            name a number in the ability's own row (`claim_seconds`), so the two cannot disagree
##   pay      {event: spec}: each `paid_off` event's payoff — `size` 0..1, and `land` (true for the
##            row's word the first time in a use, `every` for every time, or a word of its own)

const DEFAULT_COLOUR := Color("ffc247")
const DEFAULT_STATE := {"icon": &"pow", "seconds": 1.0}
const DEFAULT_PAY := {"size": 0.35}
const RED := "ff4d2e"

const LOOKS := {
	# --- the first eight ---------------------------------------------------------------------
	&"home_run": {
		"colour": "ffc247", "call": "HOME RUN!", "land": "CRACK!", "burst": &"star", "glint": 0.85,
		"states": {&"home_run": {"icon": &"arrow", "seconds": "claim_seconds",
			"aura": {"glyph": &"star", "colour": "ffc247", "amount": 6, "rise": 20.0}}},
		"pay": {&"home_run": {"size": 0.9, "land": true}},
	},
	&"iaido": {
		"colour": "6fa8ff", "call": "IAIDO", "land": "SLASH!", "burst": &"glint", "glint": 0.9,
		"states": {&"sliced": {"icon": &"slash", "seconds": "delay"}},
		"pay": {&"iaido": {"size": 0.85, "land": true}},
	},
	&"bong": {
		"colour": "ffc247", "call": "DING!", "land": "BONG!", "burst": &"star",
		"glint_at": Vector2(-12, -2),
		"states": {&"dazed": {"icon": &"star", "while": &"is_dazed", "left": &"pip_fill"}},
		"pay": {&"bong": {"size": 1.0, "land": true}},
	},
	&"rev": {
		"colour": "ff8c1a", "call": "REV!", "land": "VRRRM!", "burst": &"chip", "glint": 0.75,
		"states": {&"grinding": {"icon": &"saw", "while": &"is_active", "left": &"pip_fill",
			"aura": {"glyph": &"chip", "colour": "fff1b8", "amount": 10, "rise": 120.0}}},
		"pay": {&"grind": {"size": 0.2, "land": true}},
	},
	&"ground_pound": {
		"colour": "d98a3a", "call": "GROUND POUND", "land": "BOOM!", "burst": &"chip", "glint": 0.9,
		"states": {&"quaked": {"icon": &"quake", "seconds": "claim_seconds"}},
		"pay": {&"ground_pound": {"size": 1.0, "land": true}},
	},
	&"drive": {
		"colour": "3aa0ff", "call": "DRIVE", "go": "FORE!", "land": "HOLE IN ONE!", "burst": &"star",
		"glint": 0.95,
		"states": {&"fore": {"icon": &"target", "seconds": 0.9}},
		"pay": {&"drive": {"size": 0.65, "land": true}},
	},
	&"whirlwind": {
		"colour": "ff4d2e", "call": "WHIRLWIND", "land": "WHAP!", "burst": &"pow", "glint": 0.9,
		"states": {&"whirled": {"icon": &"pow", "while": &"is_active", "left": &"pip_fill",
			"count": &"spin_hits"}},
		"pay": {&"whirl": {"size": 0.45, "land": true}},
	},
	&"tomahawk": {
		"colour": "ff5a2e", "call": "TOMAHAWK", "land": "CHOP!", "burst": &"pow", "glint": 0.85,
		"states": {&"incoming": {"icon": &"bang", "colour": RED, "seconds": 0.7}},
		"pay": {&"tomahawk": {"size": 0.75, "land": true}},
	},

	# --- transform, tether, clamp ----------------------------------------------------------------
	&"lead_heart": {
		"colour": "d8402e", "call": "LEAD HEART", "land": "CRUNCH!", "burst": &"heart", "glint": 0.85,
		"states": {&"crushed": {"icon": &"heart", "seconds": 1.1, "refresh": true}},
		"pay": {&"lead_heart": {"size": 0.7, "land": "every"}},
	},
	&"ignite": {
		"colour": "3ad0ff", "call": "IGNITE", "land": "SIZZLE!", "burst": &"flame", "glint": 0.8,
		"states": {&"scorched": {"icon": &"flame", "colour": "ff8c1a", "seconds": 0.9, "refresh": true,
			"aura": {"glyph": &"flame", "colour": "ff8c1a", "amount": 6, "rise": 90.0}}},
		"pay": {&"ignite": {"size": 0.25, "land": true}},
	},
	&"wrap": {
		"colour": "8f9bb8", "call": "WRAP", "land": "FLING!", "burst": &"chain", "glint": 0.9,
		"states": {&"wrapped": {"icon": &"chain", "while": &"is_holding", "left": &"pip_fill"},
			&"flung": {"icon": &"arrow", "seconds": "claim_seconds"}},
		"pay": {&"catch": {"size": 0.5, "land": "GOTCHA!"}, &"fling": {"size": 0.8, "land": true}},
	},
	&"hook_and_spike": {
		"colour": "7f9cc8", "call": "HOOK AND SPIKE", "land": "SKEWERED!", "burst": &"hook", "glint": 0.95,
		"states": {&"hooked": {"icon": &"hook", "while": &"is_holding", "left": &"pip_fill"},
			&"spiked": {"icon": &"arrow", "seconds": "claim_seconds"}},
		"pay": {&"catch": {"size": 0.4, "land": "HOOKED!"}, &"spike": {"size": 0.9, "land": true}},
	},
	&"pry": {
		"colour": "d94a3a", "call": "PRY", "land": "POP!", "burst": &"lever", "glint": 0.9,
		"states": {&"pried": {"icon": &"lever", "while": &"is_holding", "left": &"pip_fill"},
			&"flung": {"icon": &"arrow", "seconds": "claim_seconds"}},
		"pay": {&"catch": {"size": 0.3}, &"pry": {"size": 0.8, "land": true}},
	},
	&"punch": {
		"colour": "ff5f9e", "call": "PUNCH", "land": "CHUNK!", "burst": &"hole", "glint": 0.6,
		"states": {&"punched": {"icon": &"hole", "seconds": "hole_seconds"}, &"bitten": {"none": true}},
		"pay": {&"punch": {"size": 0.7, "land": true}},
	},
	&"snip": {
		"colour": "4fb8ff", "call": "SNIP", "land": "SNIP SNIP!", "burst": &"slash", "glint": 0.9,
		"states": {&"snipped": {"icon": &"phones", "colour": "2eb8b3", "seconds": "phones_seconds"},
			&"bitten": {"icon": &"slash", "seconds": 0.7}},
		"pay": {&"snip": {"size": 0.5, "land": true}},
	},
	&"crank": {
		"colour": "ff8c1a", "call": "CRANK", "land": "CREAK!", "burst": &"crank", "glint": 0.9,
		"states": {&"cranked": {"icon": &"crank", "while": &"is_clamped", "left": &"pip_fill",
			"count": &"cranks"}, &"bitten": {"none": true}},
		"pay": {&"crank": {"size": 0.45, "land": "every"}},
	},

	# --- the blades --------------------------------------------------------------------------------
	&"momentum": {
		"colour": "a0b0ff", "call": "MOMENTUM", "land": "CLEAVE!", "burst": &"pow", "glint": 0.85,
		"states": {&"momentum": {"icon": &"sword", "while": &"is_active", "left": &"pip_fill",
			"count": &"chain"}},
		"pay": {&"momentum": {"size": 0.55, "land": true}},
	},
	&"embed": {
		"colour": "6fa8ff", "call": "EMBED", "land": "THUNK!", "burst": &"blade", "glint": 0.8,
		"states": {&"incoming": {"icon": &"bang", "colour": RED, "seconds": 0.7},
			&"skewered": {"icon": &"blade", "while": &"is_lodged", "left": &"lodge_left", "count": &"ticks"}},
		"pay": {&"embed": {"size": 0.75, "land": true}},
	},
	&"brush_clear": {
		"colour": "d9b83a", "call": "BRUSH CLEAR", "land": "SWOOSH!", "burst": &"leaf", "glint": 0.8,
		"states": {&"swept": {"icon": &"leaf", "colour": "c8a83a", "seconds": "claim_seconds",
			"aura": {"glyph": &"leaf", "colour": "c8a83a", "amount": 5, "rise": 40.0}}},
		"pay": {&"brush_clear": {"size": 0.75, "land": true}},
	},
	&"reap": {
		"colour": "e0a030", "call": "REAP", "land": "TRIP!", "burst": &"flip", "glint": 0.9,
		"states": {&"upended": {"icon": &"flip", "seconds": "claim_seconds"}},
		"pay": {&"reap": {"size": 0.75, "land": true}},
	},
	&"soul_reap": {
		"colour": "b48cff", "call": "SOUL REAP", "land": "WOOOO!", "burst": &"ghost", "glint": 0.85,
		"states": {&"soul_reaped": {"icon": &"ghost", "colour": "bff6ea", "seconds": 1.4,
			"aura": {"glyph": &"ecto", "colour": "bff6ea", "amount": 6, "rise": 70.0}}},
		"pay": {&"soul_reap": {"size": 0.75, "land": true}},
	},
	&"en_garde": {
		"colour": "ffd84a", "call": "EN GARDE", "land": "TOUCHE!", "burst": &"glint", "glint": 0.95,
		"states": {&"en_garde": {"icon": &"sword", "while": &"is_active", "left": &"pip_fill",
			"count": &"thrusts"}},
		"pay": {&"thrust": {"size": 0.65, "land": "every"}},
	},
	&"flurry": {
		"colour": "ff8c1a", "call": "FLURRY", "land": "RATATAT!", "burst": &"pow", "glint": 0.9,
		"states": {&"flurry": {"icon": &"pow", "while": &"is_active", "left": &"pip_fill",
			"count": &"jabs_landed"}},
		"pay": {&"flurry": {"size": 0.45, "land": true}},
	},
	&"snap": {
		"colour": "ffd23a", "call": "SNAP", "land": "TING!", "burst": &"spike", "glint": 0.95,
		"states": {&"snapped": {"icon": &"spike", "seconds": 1.2, "refresh": true, "count": &"tips_hit"}},
		"pay": {&"snap": {"size": 0.45, "land": true}},
	},
	&"special_delivery": {
		"colour": "e0463a", "call": "SPECIAL DELIVERY", "land": "DELIVERED!", "burst": &"envelope",
		"glint": 0.9,
		"states": {&"delivered": {"icon": &"envelope", "seconds": 1.6},
			&"fetch": {"icon": &"fetch", "static": true}},
		"pay": {&"special_delivery": {"size": 0.75, "land": true}},
	},

	# --- the blunt and desk nine ---------------------------------------------------------------------
	&"bristle": {
		"colour": "9aa4c8", "call": "BRISTLE", "land": "SPIKES!", "burst": &"spike", "glint": 0.9,
		"states": {&"incoming": {"icon": &"bang", "colour": RED, "seconds": 0.6},
			&"bristled": {"icon": &"spike", "seconds": 1.3, "refresh": true, "count": &"last_hits"}},
		"pay": {&"bristle": {"size": 0.35, "land": true}},
	},
	&"middle_it": {
		"colour": "ffc247", "call": "MIDDLE IT", "land": "SIX!", "burst": &"star", "glint": 0.55,
		"states": {&"six": {"icon": &"six", "seconds": "claim_seconds",
			"aura": {"glyph": &"star", "colour": "ffc247", "amount": 6, "rise": 20.0}}},
		"pay": {&"six": {"size": 1.0, "land": true}},
	},
	&"flatten": {
		"colour": "c98a4a", "call": "FLATTEN", "land": "SQUISH!", "burst": &"pancake", "glint": 0.8,
		"states": {&"flattened": {"icon": &"pancake", "seconds": 1.0, "refresh": true, "count": &"passes"}},
		"pay": {&"flatten": {"size": 0.6, "land": "every"}},
	},
	&"staple_gun": {
		"colour": "d8402e", "call": "STAPLE GUN", "land": "STAPLED!", "burst": &"staple", "glint": 0.9,
		"states": {&"stapled": {"icon": &"staple", "seconds": 1.4, "refresh": true, "count": &"landed"}},
		"pay": {&"staple": {"size": 0.3, "land": true}},
	},
	&"ricochet": {
		"colour": "ffb03a", "call": "RICOCHET", "land": "BANK SHOT!", "burst": &"bank", "glint": 0.85,
		"states": {&"incoming": {"icon": &"bank", "colour": RED, "seconds": 0.7, "refresh": true,
			"count": &"banks_done"}},
		"pay": {&"ricochet": {"size": 0.6, "land": "every"}},
	},
	&"pinpoint": {
		"colour": "ff4d2e", "call": "PINPOINT", "land": "BULLSEYE!", "burst": &"target", "glint": 0.95,
		"states": {&"targeted": {"icon": &"target", "while": &"is_locked_on"}},
		"pay": {&"pinpoint": {"size": 0.85, "land": true}},
	},
	&"keycap_barrage": {
		"colour": "e0a830", "call": "KEYCAP BARRAGE", "land": "CLACK!", "burst": &"key", "glint": 0.5,
		"states": {&"incoming": {"icon": &"key", "colour": RED, "seconds": 0.9},
			&"keyed": {"icon": &"key", "while": &"is_active", "count": &"hits"}},
		"pay": {&"keycap_barrage": {"size": 0.45, "land": true}},
	},
	&"blue_screen": {
		"colour": "2f6cf0", "call": "BLUE SCREEN", "land": "REBOOT!", "burst": &"pause", "glint": 0.5,
		"states": {&"frozen": {"icon": &"pause", "while": &"is_frozen", "left": &"pip_fill",
			"count": &"stored"}},
		"pay": {&"blue_screen": {"size": 0.35}, &"reboot": {"size": 0.9, "land": true}},
	},
	&"hot_coffee": {
		"colour": "c87a3a", "call": "HOT COFFEE", "land": "HOT!", "burst": &"drop", "glint": 0.5,
		"states": {&"incoming": {"icon": &"drop", "colour": RED, "seconds": 0.8},
			&"scalded": {"icon": &"drop", "colour": "ff8c1a", "while": &"is_steaming", "left": &"steam_left"}},
		"pay": {&"hot_coffee": {"size": 0.55, "land": true}},
	},

	# --- beyond the melee drawer (D78) ------------------------------------------------------------
	# The kind eight's states are care, not damage, and their icons say so:
	# a feather, a ball, a towel, a donut, a candle. Their words are the ones each ability gives
	# with its payoff (`AbilityCues.payoff`: "HEE!", "3!", "CAUGHT!"), in capitals like the rest.
	# `cue` is the badge `AbilityCues.state` puts up; `over: weapon` puts it over the thing itself.
	&"tickle": {
		"colour": "ff6fae", "call": "TICKLE", "burst": &"feather", "glint": 0.9,
		"cue": {"icon": &"feather", "left": &"pip_fill", "count": &"giggles",
			"aura": {"glyph": &"heart", "colour": "ff5f9e", "amount": 5, "rise": 50.0}},
		"states": {&"tickled": {"none": true}},
		"pay": {&"tickle": {"size": 0.25}},
	},
	&"keepy_uppy": {
		"colour": "ff9a2e", "call": "KEEPY-UPPY", "burst": &"ball", "glint": 0.5,
		"cue": {"icon": &"ball", "count": &"count"},
		"states": {&"lobbed": {"none": true}, &"header": {"none": true}},
		"pay": {&"header": {"size": 0.35, "shape": &"beach_header"}},
	},
	&"make_a_wish": {
		"colour": "ffd23a", "call": "MAKE A WISH", "burst": &"star", "glint": 0.85,
		"states": {&"wish": {"icon": &"cake", "seconds": 1.8,
			"aura": {"glyph": &"star", "colour": "ffd23a", "amount": 6, "rise": 40.0}}},
		"pay": {&"wish": {"size": 0.7, "land": "HAPPY BIRTHDAY!"}},
	},
	&"curveball": {
		"colour": "e04a4a", "call": "CURVEBALL", "burst": &"ball", "glint": 0.5,
		"states": {&"pitched": {"icon": &"target", "seconds": 0.8},
			&"caught_it": {"icon": &"ball", "seconds": 1.2}, &"threw_back": {"none": true}},
		"pay": {&"curveball": {"size": 0.45, "shape": &"catchers_mitt"}},
	},
	&"serve": {
		"colour": "e8b83a", "call": "SERVE", "burst": &"ball", "glint": 0.5,
		"states": {&"served": {"icon": &"target", "seconds": 0.8},
			&"volley": {"icon": &"ball", "seconds": 0.8}},
		"pay": {&"serve": {"size": 0.6, "shape": &"tennis_ace"}},
	},
	&"swaddle": {
		"colour": "ff8fbb", "call": "SWADDLE", "burst": &"heart", "glint": 0.6,
		"cue": {"icon": &"towel", "left": &"wrap_left",
			"aura": {"glyph": &"heart", "colour": "ff8fbb", "amount": 4, "rise": 40.0}},
		"states": {&"swaddled": {"none": true}},
		"pay": {&"swaddle": {"size": 0.4}},
	},
	&"strike": {
		"colour": "5a78ff", "call": "BOWL!", "burst": &"pin", "glint": 0.5,
		"states": {&"incoming": {"icon": &"pin", "colour": RED, "seconds": 0.9},
			&"bowled": {"icon": &"pin", "seconds": "claim_seconds"}},
		"pay": {&"strike": {"size": 0.95, "shape": &"bowling_pins"}},
	},
	&"wring": {
		"colour": "4fb8ff", "call": "WRING", "burst": &"drop", "glint": 0.5,
		"cue": {"icon": &"drop", "left": &"pip_fill"},
		"states": {&"showered": {"none": true}, &"shake_dry": {"icon": &"drop", "seconds": 1.0}},
		"pay": {&"wring": {"size": 0.4}},
	},
	&"donut_toss": {
		"colour": "ff6fae", "call": "DONUT TOSS", "burst": &"donut", "glint": 0.5,
		"states": {&"donut_incoming": {"icon": &"donut", "seconds": 0.9},
			&"fed": {"icon": &"donut", "seconds": 1.2,
				"aura": {"glyph": &"heart", "colour": "ff5f9e", "amount": 4, "rise": 40.0}}},
		"pay": {&"donut_toss": {"size": 0.5}},
	},
	&"airburst": {
		"colour": "ff8c1a", "call": "AIRBURST", "burst": &"bomb", "glint": 0.5,
		"cue": {"icon": &"bomb", "over": "weapon", "left": &"pip_fill"},
		"states": {&"airburst": {"icon": &"bomb", "colour": RED, "seconds": 1.0}},
		"pay": {&"airburst": {"size": 0.9, "land": "BOMBS AWAY!"}},
	},
	&"remote": {
		"colour": "ff4d2e", "call": "REMOTE", "burst": &"remote", "glint": 0.5,
		"cue": {"icon": &"remote", "over": "weapon", "left": &"pip_fill"},
		"states": {&"ticking": {"icon": &"bomb", "colour": RED, "seconds": 0.8, "refresh": true}},
		"pay": {&"remote": {"size": 0.6}},
	},
}

static func has_look(id: StringName) -> bool:
	return LOOKS.has(id)

## The look for an ability, every field filled: its row, or the defaults. Colours come back as
## `Color`; the rest as the row has them.
static func look_for(id: StringName, display_name: String) -> Dictionary:
	var row: Dictionary = LOOKS.get(id, {})
	return {
		"colour": colour_of(row.get("colour", DEFAULT_COLOUR)),
		"call": String(row.get("call", display_name.to_upper())),
		"go": String(row.get("go", "")),
		"land": String(row.get("land", "")),
		"burst": StringName(row.get("burst", &"star")),
		"glint": float(row.get("glint", 0.8)),
		"glint_at": row.get("glint_at", Vector2.INF),
		"states": row.get("states", {}),
		"cue": row.get("cue", {}),
		"pay": row.get("pay", {}),
	}

## The badge `AbilityCues.state` puts up for an ability (D78's abilities): the row's `cue`, lasting
## while the ability says its state is on (`cue_state_on`) unless the row says otherwise, and over
## him unless it says `over: weapon`. The generic badge for an ability with no row.
static func cue_spec(look: Dictionary, ability_row: Dictionary) -> Dictionary:
	var spec: Dictionary = (look.get("cue", {}) as Dictionary).duplicate()
	if bool(spec.get("none", false)):
		return {}
	if not spec.has("icon"):
		spec["icon"] = &"pow"
	if not spec.has("while") and not spec.has("seconds"):
		spec["while"] = &"cue_state_on"
	var states := {&"cue": spec}
	return state_spec({"colour": look.get("colour", DEFAULT_COLOUR), "states": states}, &"cue",
		ability_row)

## The badge for `event`, resolved against the ability's own row: its colour a `Color`, and a
## `seconds` that names a row key read from the row. Empty for an event the look says shows nothing.
static func state_spec(look: Dictionary, event: StringName, ability_row: Dictionary) -> Dictionary:
	var states: Dictionary = look.get("states", {})
	var spec: Dictionary = (states.get(event, DEFAULT_STATE) as Dictionary).duplicate()
	if bool(spec.get("none", false)):
		return {}
	spec["colour"] = colour_of(spec.get("colour", look.get("colour", DEFAULT_COLOUR)))
	var seconds = spec.get("seconds", 0.0 if spec.has("while") else 1.0)
	if seconds is String or seconds is StringName:
		seconds = float(ability_row.get(String(seconds), 1.5))
	spec["seconds"] = float(seconds)
	var aura: Dictionary = spec.get("aura", {})
	if not aura.is_empty():
		aura = aura.duplicate()
		aura["colour"] = colour_of(aura.get("colour", spec["colour"]))
		spec["aura"] = aura
	return spec

## The payoff for a `paid_off` event: its size, and the word to call, if any, given whether this is
## the event's first time in this use.
static func pay_spec(look: Dictionary, event: StringName) -> Dictionary:
	var pay: Dictionary = look.get("pay", {})
	return pay.get(event, DEFAULT_PAY)

## `said` is the word the ability gave with the payoff itself (D78's `AbilityCues.payoff`): it is
## called out every time, in capitals like every other word, unless the look names one of its own
## for the event.
static func pay_words(look: Dictionary, spec: Dictionary, first: bool, said: String = "") -> String:
	var land = spec.get("land", false)
	if not (land is bool) and String(land) != "every":
		return String(land) if first or not said.is_empty() else ""
	if not said.is_empty():
		return said.to_upper()
	if land is bool:
		return String(look.get("land", "")) if land and first else ""
	return String(look.get("land", ""))

static func colour_of(value) -> Color:
	if value is Color:
		return value
	return Color(String(value))
