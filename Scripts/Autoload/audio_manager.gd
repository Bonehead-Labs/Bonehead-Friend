extends Node

## Pooled, pitch-randomised SFX with a hard voice cap, and the mute-when-unfocused rule
## the overlay promise depends on.
##
## The sounds themselves are **placeholders synthesised at boot**, not assets. M2's art
## list calls for "first impact sounds" and there are none yet; generating them keeps the
## feedback loop complete without committing binary stand-ins that someone later mistakes
## for the real thing. Replace `_build_streams()` with loaded assets in the audio pass and
## nothing else changes.

## Eight simultaneous voices. A physics sandbox produces collision bursts, and an
## uncapped pool turns a pile-up into a wall of noise plus an audible frame hitch.
const VOICE_CAP := 8
const MIX_RATE := 22050

const SFX_BUS := "SFX"

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _streams: Dictionary = {}
var _muted := false
## Resolved impact voices, because `_on_damage_dealt` runs on every contact for eight hours
## and a substring sweep per hit is a substring sweep per hit.
var _voice_cache: Dictionary = {}

func _ready() -> void:
	_ensure_bus()
	_build_streams()
	_load_assets()
	for i in VOICE_CAP:
		var player := AudioStreamPlayer.new()
		player.bus = SFX_BUS
		add_child(player)
		_players.append(player)

	apply_volumes()
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.kindness_given.connect(_on_kindness_given)
	EventBus.item_purchased.connect(func(_id: StringName) -> void: play(&"purchase"))
	EventBus.knockout_payout.connect(func(_total: float) -> void: play(&"knockout"))
	EventBus.mastery_rank_up.connect(func(_id: StringName, _r: int) -> void: play(&"rank_up", 0.06, -6.0))
	EventBus.contract_claimed.connect(func(_id: StringName, _e: int) -> void: play(&"contract", 0.04))
	EventBus.prestige_performed.connect(func(_gained: int) -> void: play(&"prestige", 0.0))
	# The moments that were silent (assessment-2026-09). An augment level is a register
	# tick that climbs with the level, so buying ten in a row is a scale rather than one
	# note ten times; a milestone is its own figure because a $2,600 milestone and a rank-up
	# used to look and sound identical; a contract *finishing* is quieter than claiming it.
	EventBus.augment_purchased.connect(func(_id: StringName, level: int) -> void:
		play(&"upgrade", 0.02, -6.0, 1.0 + 0.035 * float(mini(level, 24))))
	EventBus.contract_completed.connect(func(_id: StringName) -> void: play(&"contract", 0.04, -8.0))
	EventBus.item_spawned.connect(func(_item: Node2D) -> void: play(&"spawn", 0.10, -12.0))
	# Landing: a padded thud, louder the harder he came down, and silent for a hop.
	EventBus.buddy_landed.connect(func(_at: Vector2, speed: float) -> void:
		var t := clampf((speed - 400.0) / 800.0, 0.0, 1.0)
		if t > 0.0:
			play(&"land", 0.12, lerpf(-18.0, -4.0, t)))
	Milestones.milestone_claimed.connect(func(_id: StringName, _rungs: int, _dollars: int) -> void:
		play(&"milestone", 0.02, -3.0))

## Autoloads outlive the scene tree, so the synthesised streams and any playback still in
## flight are still referenced when the engine runs its leak check and get reported as
## leaks. Dropping them here keeps that report meaningful for real leaks.
func _exit_tree() -> void:
	for player in _players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_streams.clear()

func _notification(what: int) -> void:
	# The player is working. A game that keeps talking while they are in a meeting gets
	# uninstalled, and this is one of the few genre complaints that is trivially fixable.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and Settings.mute_when_unfocused:
		_set_muted(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_set_muted(false)

func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(maxf(0.0001, Settings.volume_master)))
	var sfx := AudioServer.get_bus_index(SFX_BUS)
	if sfx >= 0:
		AudioServer.set_bus_volume_db(sfx, linear_to_db(maxf(0.0001, Settings.volume_sfx)))

func play(id: StringName, pitch_spread: float = 0.12, volume_db: float = 0.0,
		pitch: float = 1.0) -> void:
	if _muted or Settings.focus_intensity == Settings.Intensity.OFF:
		return
	var stream := _pick(id)
	if stream == null:
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	# Pitch randomisation is what stops repeated impacts sounding like a machine gun. A
	# deliberate `pitch` on top is how a streak or a level climbs.
	player.pitch_scale = pitch * randf_range(1.0 - pitch_spread, 1.0 + pitch_spread)
	player.volume_db = volume_db + _asset_gain(id)
	player.play()

func _on_damage_dealt(info: HitInfo) -> void:
	# Louder for bigger hits, so the audio carries the same information the numbers do — and
	# higher for each hit in a streak, so a run of swings climbs like a scale. Economy has
	# already counted this hit (autoloads connect in boot order), so the streak includes it.
	var t := clampf(info.amount / 120.0, 0.0, 1.0)
	var streak := Economy.damage_streak()
	var pitch := 1.0 + 0.03 * float(mini(maxi(streak - 1, 0), 16))
	play(impact_voice(info.source_id), 0.18, lerpf(-12.0, 0.0, t), pitch)

## What a hit from this thing sounds like.
##
## Everything in the game hit with the same wooden clatter, which was fine while the roster
## was a bat, a pan and a mace and stops being fine the moment it contains a greatsword, a
## stapler and a tesla coil. Material is the only thing the ear is actually listening for:
## a player who cannot see the desk should be able to tell a sword from a keyboard.
##
## Keyed on the item id, in this file, deliberately — every sound in the game is synthesised
## here rather than loaded (docs/decisions.md D12), so this is where a sound *is*. When the
## audio pass replaces synthesis with recorded assets, this table becomes a field on
## ItemData and the lookup goes away. Until then, an unlisted item falls back by category,
## and an unknown category falls back to wood, so a new toy is never silent.
const MATERIAL_VOICES := {
	&"metal": &"impact_metal",
	&"soft": &"impact_soft",
	&"plastic": &"impact_plastic",
	&"electric": &"impact_electric",
	&"wood": &"impact",
}

## Substrings, matched against the item id, longest-specific first. A table of every item
## would need editing for every new toy — which is the D8 violation this avoids — and the
## families here are the ones the synthesiser actually has voices for.
const MATERIAL_HINTS := [
	[&"electric", ["tesla", "laser", "energy", "rail", "lightning", "shock", "plasma", "taser"]],
	[&"metal", ["sword", "katana", "blade", "machete", "cleaver", "axe", "halberd", "scythe",
		"rapier", "sickle", "pick", "crowbar", "wrench", "hammer", "flail", "mace", "anvil",
		"pan", "skillet", "iron", "wrench", "scissors", "knife", "saw", "spanner", "girder"]],
	[&"plastic", ["keyboard", "stapler", "mouse", "monitor", "lamp", "tape", "punch", "mug",
		"ruler", "bottle", "toy", "ball"]],
	[&"soft", ["pillow", "cushion", "plush", "sponge", "glove", "boxing", "bag", "fish"]],
]

func impact_voice(source_id: StringName) -> StringName:
	if _voice_cache.has(source_id):
		return _voice_cache[source_id]
	var voice := _resolve_voice(source_id)
	_voice_cache[source_id] = voice
	return voice

func _resolve_voice(source_id: StringName) -> StringName:
	var id := String(source_id)
	for entry in MATERIAL_HINTS:
		for hint in entry[1]:
			if id.contains(hint):
				return MATERIAL_VOICES[entry[0]]
	var item := ItemDB.get_item(source_id)
	if item and item.category == ItemData.CATEGORY_THROWABLE:
		# The big voice was synthesised in M3.6 and nothing ever played it. The heavy end of
		# the explosives drawer is what it was made for.
		for hint in BIG_BANG_HINTS:
			if id.contains(hint):
				return &"explode_big"
		return &"explode_small"
	return &"impact"

const BIG_BANG_HINTS := ["demolition", "black_hole", "implosion", "mortar", "napalm",
	"cluster", "satchel", "oil_drum", "concussion", "nail_bomb", "missile"]

## Petting fires several times a second, so this is quiet and wide-spread on purpose —
## the same sample at the same pitch four times a second is a fire alarm, not affection.
func _on_kindness_given(_source_id: StringName, _value: float, _world_pos: Vector2) -> void:
	# Pitched up per act in the combo, so a petting streak climbs the way a hit streak does.
	play(&"kindness", 0.25, -14.0, 1.0 + 0.05 * float(mini(Economy.kindness_combo(), 10)))

func _set_muted(value: bool) -> void:
	_muted = value
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(master, value)

func _ensure_bus() -> void:
	if AudioServer.get_bus_index(SFX_BUS) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, SFX_BUS)
	AudioServer.set_bus_send(index, "Master")

# --- placeholder synthesis -------------------------------------------------

func _build_streams() -> void:
	_streams[&"impact"] = _wav(_impact_samples())
	_streams[&"purchase"] = _wav(_chime_samples([880.0, 1174.0], 0.18))
	_streams[&"knockout"] = _wav(_chime_samples([440.0, 330.0, 220.0], 0.45))
	# The knockout beat's two halves: bones hitting the floor, then bones finding each
	# other again. Same clatter body, played long and falling for the collapse and short
	# and rising for the reassemble, so the pair reads as one gag rather than two noises.
	_streams[&"clatter"] = _wav(_clatter_samples(0.42, -1.0))
	_streams[&"rattle"] = _wav(_clatter_samples(0.30, 1.0))
	_streams[&"kindness"] = _wav(_chime_samples([659.0, 988.0], 0.22))
	# Progression's three moments. Each is a rising figure, and each is longer than the last
	# — a rank up is a nod, a contract is a small event, a Reincarnation is the big one.
	_streams[&"rank_up"] = _wav(_chime_samples([784.0, 1046.0], 0.30))
	_streams[&"contract"] = _wav(_chime_samples([523.0, 659.0, 784.0], 0.50))
	_streams[&"prestige"] = _wav(_chime_samples([392.0, 523.0, 659.0, 784.0, 1046.0], 1.10))
	# An augment level: two quick notes, pitched up per level by the caller. A milestone:
	# a third figure between rank-up and contract. Coming back: a slow, warm three.
	_streams[&"upgrade"] = _wav(_chime_samples([660.0, 880.0], 0.14))
	_streams[&"milestone"] = _wav(_chime_samples([523.0, 784.0, 1046.0], 0.40))
	_streams[&"welcome"] = _wav(_chime_samples([392.0, 523.0, 659.0], 0.70))
	# A toy landing on the desk: a short soft knock, not a chime — it is furniture arriving.
	_streams[&"spawn"] = _wav(_tick_samples(0.06, 520.0, 0.7))

	# --- his voice ---
	#
	# He had none: every sound attributed to him belonged to the thing that hit him. Four
	# breaths for the expression brain (docs/plan-expressive-buddy.md §3.6), all the same
	# sweep-plus-breath body so they read as one throat. `oof` falls and is short; `gasp`
	# rises and is shorter; `yawn` falls slowly with almost no breath; `greet` is a rising
	# two-tone, because coming back after an hour deserves a note rather than a grunt.
	_streams[&"oof"] = _wav(_voice_samples(0.14, 260.0, 130.0, 0.5))
	_streams[&"gasp"] = _wav(_voice_samples(0.12, 300.0, 720.0, 0.6))
	_streams[&"yawn"] = _wav(_voice_samples(0.70, 420.0, 180.0, 0.15))
	_streams[&"greet"] = _wav(_chime_samples([523.0, 784.0], 0.25))

	# --- the shell ---
	#
	# The menus are keys and card stock, so they click and knock rather than chime. These
	# are much shorter and much quieter than anything above: a hover tick fires several
	# times a second as the cursor crosses a list, and at chime length and chime volume it
	# would be the loudest thing in the game.
	_streams[&"ui_hover"] = _wav(_tick_samples(0.018, 2600.0, 0.35))
	_streams[&"ui_click"] = _wav(_key_samples())
	_streams[&"ui_tab"] = _wav(_tick_samples(0.05, 900.0, 0.9))
	_streams[&"ui_denied"] = _wav(_denied_samples())
	_streams[&"ui_open"] = _wav(_sweep_samples(0.12, 320.0, 720.0))
	_streams[&"ui_close"] = _wav(_sweep_samples(0.10, 700.0, 300.0))

	# --- materials ---
	#
	# One voice per family the roster actually contains. See `impact_voice`: the ear is
	# listening for material, and a thirty-weapon melee category that all sounds like a
	# baseball bat is thirty weapons that feel like one.
	_streams[&"impact_metal"] = _wav(_ring_samples())
	_streams[&"impact_soft"] = _wav(_thud_samples())
	_streams[&"impact_plastic"] = _wav(_clack_samples())
	_streams[&"impact_electric"] = _wav(_zap_samples())

	# --- explosives, turrets and things that are alive ---
	_streams[&"explode_small"] = _wav(_boom_samples(0.45, 90.0))
	_streams[&"explode_big"] = _wav(_boom_samples(0.95, 55.0))
	_streams[&"turret_fire"] = _wav(_shot_samples())
	_streams[&"npc_roar"] = _wav(_roar_samples())
	_streams[&"npc_stomp"] = _wav(_boom_samples(0.22, 70.0))

	# --- the arcade ---
	#
	# A casino is mostly sound. The reel stop and the wheel tick are the two that do the
	# work: both are the moment *before* the outcome, which is the part a player is
	# actually there for.
	_streams[&"reel_stop"] = _wav(_tick_samples(0.07, 420.0, 0.8))
	_streams[&"wheel_tick"] = _wav(_tick_samples(0.02, 1800.0, 0.5))
	_streams[&"card_deal"] = _wav(_card_samples())
	_streams[&"jackpot"] = _wav(_chime_samples([523.0, 659.0, 784.0, 1046.0, 1318.0, 1568.0], 1.30))
	_streams[&"lose"] = _wav(_sweep_samples(0.28, 420.0, 140.0))

	# --- his own afternoon ---
	_streams[&"bounce"] = _wav(_bounce_samples())
	_streams[&"splash"] = _wav(_splash_samples())

## A woodblock tick: one decaying sine with a noise transient on the front. The transient
## is what makes it read as a physical contact rather than as a beep.
func _tick_samples(duration: float, pitch: float, noise: float) -> PackedFloat32Array:
	var count := int(MIX_RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260830
	for i in count:
		var t := float(i) / float(MIX_RATE)
		var envelope := exp(-t * 190.0)
		var transient := rng.randf_range(-1.0, 1.0) * exp(-t * 900.0) * noise
		out[i] = clampf((sin(TAU * pitch * t) * 0.7 + transient) * envelope, -1.0, 1.0)
	return out

## A key bottoming out and rebounding: the press knock, then a quieter, higher one a few
## milliseconds later. The gap is what the ear hears as travel.
func _key_samples() -> PackedFloat32Array:
	var down := _tick_samples(0.05, 620.0, 1.0)
	var up := _tick_samples(0.035, 1150.0, 0.5)
	var gap := int(MIX_RATE * 0.028)
	var out := PackedFloat32Array()
	out.resize(gap + up.size())
	for i in out.size():
		var value := down[i] if i < down.size() else 0.0
		if i >= gap:
			value += up[i - gap] * 0.45
		out[i] = clampf(value, -1.0, 1.0)
	return out

## Refusal. A low, slightly detuned square that stops abruptly — the one sound in the game
## that is deliberately unpleasant, because it is the only one that means "no".
func _denied_samples() -> PackedFloat32Array:
	var duration := 0.16
	var count := int(MIX_RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t := float(i) / float(MIX_RATE)
		var envelope := clampf(1.0 - t / duration, 0.0, 1.0)
		var a := signf(sin(TAU * 116.0 * t))
		var b := signf(sin(TAU * 123.0 * t))
		out[i] = clampf((a + b) * 0.22 * envelope, -1.0, 1.0)
	return out

## A panel arriving or leaving: a short glide between two pitches, filtered soft so it
## sits under the click rather than over it.
func _sweep_samples(duration: float, from_hz: float, to_hz: float) -> PackedFloat32Array:
	var count := int(MIX_RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(MIX_RATE)
		var progress := t / duration
		phase += TAU * lerpf(from_hz, to_hz, progress) / float(MIX_RATE)
		var envelope := sin(PI * clampf(progress, 0.0, 1.0))
		out[i] = clampf(sin(phase) * 0.30 * envelope, -1.0, 1.0)
	return out

## A breath with a pitch in it: a sine sweep under filtered noise, both inside one soft
## envelope. `breath` is how much noise rides the tone — a gasp is mostly air, a yawn mostly
## tone. Every one of his four voices is this with different numbers.
func _voice_samples(duration: float, from_hz: float, to_hz: float, breath: float) -> PackedFloat32Array:
	var count := int(MIX_RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260906
	var phase := 0.0
	var low := 0.0
	for i in count:
		var t := float(i) / float(MIX_RATE)
		var progress := t / duration
		phase += TAU * lerpf(from_hz, to_hz, progress) / float(MIX_RATE)
		# Quick in, slow out: a breath starts on the beat and trails off.
		var envelope := minf(progress * 8.0, 1.0) * (1.0 - progress) * (1.0 - progress)
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.25)
		out[i] = clampf((sin(phase) * 0.32 + low * 0.5 * breath) * envelope, -1.0, 1.0)
	return out

## Struck metal: partials that are not whole multiples of the fundamental, which is the
## entire difference between a bell and an organ pipe. Long decay, because metal rings.
func _ring_samples() -> PackedFloat32Array:
	var duration := 0.55
	var count := int(MIX_RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	# Ratios lifted from a struck bar rather than a harmonic series: 1 : 2.76 : 5.40 is what
	# stops it sounding like a note being played at him.
	var partials := [[520.0, 0.42, 7.0], [1435.0, 0.26, 11.0], [2808.0, 0.15, 16.0]]
	for i in count:
		var t := float(i) / float(MIX_RATE)
		var value := 0.0
		for partial in partials:
			value += sin(TAU * float(partial[0]) * t) * float(partial[1]) * exp(-t * float(partial[2]))
		out[i] = clampf(value, -1.0, 1.0)
	return out

## Something padded landing on something padded: a low sine with almost no noise on it and
## a fast decay. The absence of a transient is what makes it read as soft.
func _thud_samples() -> PackedFloat32Array:
	var count := int(MIX_RATE * 0.20)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t := float(i) / float(MIX_RATE)
		var envelope := exp(-t * 22.0)
		out[i] = clampf(sin(TAU * lerpf(120.0, 74.0, minf(t * 6.0, 1.0)) * t) * 0.75 * envelope,
			-1.0, 1.0)
	return out

## Hollow plastic — a keyboard, a stapler, a mug. Very short, dry, and pitched high enough
## to sit above the wooden clatter it is meant to be distinguished from.
func _clack_samples() -> PackedFloat32Array:
	var count := int(MIX_RATE * 0.07)
	var out := PackedFloat32Array()
	out.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260901
	for i in count:
		var t := float(i) / float(MIX_RATE)
		var envelope := exp(-t * 120.0)
		var body := sin(TAU * 940.0 * t) * 0.5 + sin(TAU * 1580.0 * t) * 0.25
		out[i] = clampf((body + rng.randf_range(-0.3, 0.3) * exp(-t * 700.0)) * envelope,
			-1.0, 1.0)
	return out

## A discharge: noise pushed through a fast rising sweep, so it cracks and then hisses.
func _zap_samples() -> PackedFloat32Array:
	var duration := 0.26
	var count := int(MIX_RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260902
	var phase := 0.0
	for i in count:
		var t := float(i) / float(MIX_RATE)
		var progress := t / duration
		phase += TAU * lerpf(180.0, 2400.0, progress * progress) / float(MIX_RATE)
		var envelope := exp(-t * 14.0)
		out[i] = clampf((sin(phase) * 0.45 + rng.randf_range(-0.5, 0.5)) * envelope, -1.0, 1.0)
	return out

## A blast: a noise burst over a falling low body, with a tail long enough to sound like
## the room. `pitch` sets how big the thing was.
func _boom_samples(duration: float, pitch: float) -> PackedFloat32Array:
	var count := int(MIX_RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260903
	var low := 0.0
	for i in count:
		var t := float(i) / float(MIX_RATE)
		# Two envelopes: a crack that is gone in a few milliseconds and a body that is not.
		var crack := exp(-t * 90.0)
		var body := exp(-t * (2.2 / duration))
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.25)
		var boom := sin(TAU * lerpf(pitch, pitch * 0.45, minf(t * 3.0, 1.0)) * t)
		out[i] = clampf(low * 0.55 * (crack * 0.6 + body * 0.5) + boom * 0.6 * body, -1.0, 1.0)
	return out

## A turret round: a crack with no ring on it. Deliberately dry — a turret fires several
## times a second for hours, and anything with a tail becomes a drone.
func _shot_samples() -> PackedFloat32Array:
	var count := int(MIX_RATE * 0.06)
	var out := PackedFloat32Array()
	out.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260904
	for i in count:
		var t := float(i) / float(MIX_RATE)
		var envelope := exp(-t * 160.0)
		out[i] = clampf((rng.randf_range(-1.0, 1.0) * 0.7 + sin(TAU * 210.0 * t) * 0.5)
			* envelope, -1.0, 1.0)
	return out

## Something large and annoyed. Low noise with a slow wobble on it, which is what turns a
## rumble into a voice.
func _roar_samples() -> PackedFloat32Array:
	var duration := 0.75
	var count := int(MIX_RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260905
	var low := 0.0
	for i in count:
		var t := float(i) / float(MIX_RATE)
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.12)
		var wobble := 0.75 + 0.25 * sin(TAU * 7.0 * t)
		var envelope := sin(PI * clampf(t / duration, 0.0, 1.0))
		var growl := sin(TAU * 88.0 * t) * 0.5 + sin(TAU * 131.0 * t) * 0.3
		out[i] = clampf((low * 0.7 + growl) * wobble * envelope * 0.8, -1.0, 1.0)
	return out

## A card off the top of the shoe: a very short band of noise and nothing else. Anything
## pitched makes it a whistle rather than paper.
func _card_samples() -> PackedFloat32Array:
	var count := int(MIX_RATE * 0.055)
	var out := PackedFloat32Array()
	out.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260906
	var high := 0.0
	var last := 0.0
	for i in count:
		var t := float(i) / float(MIX_RATE)
		var noise := rng.randf_range(-1.0, 1.0)
		# One-pole high pass: the paper is in the top of the band, and the low end of raw
		# noise reads as wind.
		high = noise - last + high * 0.86
		last = noise
		out[i] = clampf(high * 0.5 * sin(PI * clampf(t / 0.055, 0.0, 1.0)), -1.0, 1.0)
	return out

## A boing. Pitch rises hard on the compression and falls back as it leaves, which is the
## whole shape of a trampoline and is why this is a sweep rather than a note.
func _bounce_samples() -> PackedFloat32Array:
	var duration := 0.30
	var count := int(MIX_RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(MIX_RATE)
		var progress := t / duration
		var pitch := 180.0 + 520.0 * sin(PI * progress)
		phase += TAU * pitch / float(MIX_RATE)
		out[i] = clampf(sin(phase) * 0.55 * exp(-t * 6.5), -1.0, 1.0)
	return out

## Water. Filtered noise that opens and closes, with no pitch in it at all.
func _splash_samples() -> PackedFloat32Array:
	var duration := 0.35
	var count := int(MIX_RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260907
	var band := 0.0
	for i in count:
		var t := float(i) / float(MIX_RATE)
		band = lerpf(band, rng.randf_range(-1.0, 1.0), 0.55)
		var envelope := sin(PI * clampf(t / duration, 0.0, 1.0)) * exp(-t * 3.0)
		out[i] = clampf(band * envelope * 0.8, -1.0, 1.0)
	return out

## A clatter: filtered noise over a short low thump. Bones hitting a bat.
func _impact_samples() -> PackedFloat32Array:
	var count := int(MIX_RATE * 0.14)
	var out := PackedFloat32Array()
	out.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260828
	var low := 0.0
	for i in count:
		var t := float(i) / float(MIX_RATE)
		var envelope := exp(-t * 34.0)
		# One-pole low pass over white noise, so it reads as wood rather than static.
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.45)
		var thump := sin(TAU * 150.0 * t) * exp(-t * 60.0) * 0.6
		out[i] = clampf((low * 0.8 + thump) * envelope, -1.0, 1.0)
	return out

## A tumble of little wooden knocks. `direction` -1 falls in pitch (he is coming apart),
## +1 rises (he is putting himself back together).
func _clatter_samples(duration: float, direction: float) -> PackedFloat32Array:
	var count := int(MIX_RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260829
	var knocks := 9
	for n in knocks:
		var progress := float(n) / float(knocks - 1)
		var start := int(progress * duration * 0.8 * MIX_RATE)
		var pitch := 320.0 * pow(2.0, direction * (progress - 0.5) * 1.2)
		for i in range(start, mini(count, start + int(MIX_RATE * 0.09))):
			var t := float(i - start) / float(MIX_RATE)
			var envelope := exp(-t * 48.0)
			var body := sin(TAU * pitch * t) * 0.6 + rng.randf_range(-0.35, 0.35)
			out[i] = clampf(out[i] + body * envelope * 0.45, -1.0, 1.0)
	return out

## Stacked decaying sines, one per note, offset in time.
func _chime_samples(notes: Array, duration: float) -> PackedFloat32Array:
	var count := int(MIX_RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	var step := duration / float(maxi(1, notes.size())) * 0.5
	for n in notes.size():
		var start := int(step * float(n) * MIX_RATE)
		for i in range(start, count):
			var t := float(i - start) / float(MIX_RATE)
			var envelope := exp(-t * 12.0)
			out[i] = clampf(out[i] + sin(TAU * float(notes[n]) * t) * envelope * 0.35, -1.0, 1.0)
	return out

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	return stream

# --- recorded assets -----------------------------------------------------------
#
# The synthesised voices above were the placeholder (D12). Where a recorded sound is a clear
# win — a contact, a blast, a coin, a key, a card — the game now ships one (docs/decisions.md
# D42): CC0 recordings from Kenney's packs, renamed to the id they play as and kept under
# `res://Assets/audio/<id>_<nnn>.ogg`. Every file found for an id is a *variant*, and `play`
# picks one at random on top of the pitch spread, which is what stops twenty hits a second
# sounding like one sample on a loop. An id with no files keeps its synthesised voice, so a
# missing import never silences anything — and the chimes, his breaths, the roar and the
# knockout clatter are deliberately left synthesised: they are the game's own sound.
#
# Listed rather than discovered: in an exported build the .ogg is not in the pack — its
# import is — and `ResourceLoader` resolves the remap while a directory listing would not.
# Levels are set per id here, by ear; a recorded file peaks near full scale where the synth
# voices sat lower, so most of these pull the asset down to meet the old level.

const ASSET_DIR := "res://Assets/audio"
const ASSETS := {
	&"impact": 5, &"impact_metal": 5, &"impact_soft": 5, &"impact_plastic": 5,
	&"explode_small": 5, &"explode_big": 2, &"land": 5,
	&"purchase": 2, &"spawn": 4,
	&"ui_click": 5, &"ui_hover": 3, &"ui_tab": 3, &"ui_open": 4, &"ui_close": 4, &"ui_denied": 3,
	&"card_deal": 8, &"reel_stop": 3,
}
const ASSET_GAIN_DB := {
	&"impact": -6.0, &"impact_metal": -8.0, &"impact_soft": -4.0, &"impact_plastic": -7.0,
	&"explode_small": -4.0, &"explode_big": -2.0, &"land": -6.0,
	&"purchase": -6.0, &"spawn": -8.0,
	&"ui_click": -10.0, &"ui_hover": -14.0, &"ui_tab": -10.0, &"ui_open": -10.0, &"ui_close": -10.0,
	&"ui_denied": -8.0, &"card_deal": -6.0, &"reel_stop": -6.0,
}

var _variants: Dictionary = {}   ## id -> Array[AudioStream]

func _load_assets() -> void:
	for id in ASSETS:
		var found: Array[AudioStream] = []
		for n in int(ASSETS[id]):
			var path := "%s/%s_%03d.ogg" % [ASSET_DIR, id, n]
			if ResourceLoader.exists(path):
				var stream := load(path) as AudioStream
				if stream:
					found.append(stream)
		if not found.is_empty():
			_variants[id] = found

## Whether an id is playing a recording rather than its synthesised voice.
func is_recorded(id: StringName) -> bool:
	return _variants.has(id)

func _pick(id: StringName) -> AudioStream:
	if _variants.has(id):
		var options: Array = _variants[id]
		return options[randi() % options.size()]
	return _streams.get(id) as AudioStream

## The level a recorded id sits at relative to the synthesised voice it replaced.
func _asset_gain(id: StringName) -> float:
	return float(ASSET_GAIN_DB.get(id, 0.0)) if _variants.has(id) else 0.0
