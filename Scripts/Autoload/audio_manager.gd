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
	EventBus.item_purchased.connect(func(_id: StringName) -> void: play(&"purchase"))
	EventBus.knockout_payout.connect(func(_total: float) -> void: play(&"knockout"))

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
