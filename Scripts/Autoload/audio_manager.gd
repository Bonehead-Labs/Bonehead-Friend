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

func _ready() -> void:
	_ensure_bus()
	_build_streams()
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

func play(id: StringName, pitch_spread: float = 0.12, volume_db: float = 0.0) -> void:
	if _muted or Settings.focus_intensity == Settings.Intensity.OFF:
		return
	var stream := _streams.get(id) as AudioStream
	if stream == null:
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	# Pitch randomisation is what stops repeated impacts sounding like a machine gun.
	player.pitch_scale = randf_range(1.0 - pitch_spread, 1.0 + pitch_spread)
	player.volume_db = volume_db
	player.play()

func _on_damage_dealt(info: HitInfo) -> void:
	# Louder for bigger hits, so the audio carries the same information the numbers do.
	var t := clampf(info.amount / 120.0, 0.0, 1.0)
	play(&"impact", 0.18, lerpf(-12.0, 0.0, t))

## Petting fires several times a second, so this is quiet and wide-spread on purpose —
## the same sample at the same pitch four times a second is a fire alarm, not affection.
func _on_kindness_given(_source_id: StringName, _value: float, _world_pos: Vector2) -> void:
	play(&"kindness", 0.25, -14.0)

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
