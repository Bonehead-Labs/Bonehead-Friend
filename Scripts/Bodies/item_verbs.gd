class_name ItemVerbs
extends Node

## The verbs of an everyday thing: what a player does *to* a boombox, a lava lamp or a fish
## tank with the right button, beyond putting it down and waiting (docs/decisions.md D67).
##
## A component, like the `GestureZones` it listens to and for the same reason (D57): it rides
## on a `FriendlyBase` generator, a comfort item, a food or the desk fan without any of them
## changing class. The body keeps everything it already does — its placed rate, its catch,
## the routine he has with it — and `item_check` still drives it as the class it always was.
##
## **A verb is a row, not a script** (D8). The seed table (`tools/verb_table.gd`) writes the
## rows into the scene beside the zones they fire on, and this reads them. One row:
##
##   id        the verb's name
##   zone      the zone it fires on — or `zones`, several, whose index picks the note
##   on        the gesture that fires it: "tap", "press", "cross", "crank", "drag", "hold",
##             "action" (right while held) — or several, as an Array
##   every     crank: radians per firing; drag: art px of travel per firing (0: every event)
##   button    "right" (the default) or "left"
##   value     kindness value of one act, before the item's own value node. 0 pays nothing
##   cooldown  seconds before it pays again. It still plays in between — the lamp still
##             churns, the chimes still ring — it only does not pay. The item's "time between
##             uses" node shortens it, as it shortens the item's own contact cooldown
##   once      pays once for the life of the item: a cup is stirred once
##   near      pays and reacts only with him within this many px
##   touching  pays and reacts only while he is touching it: the jets are for his soak
##   consume   the act uses the item up: a popper is pulled once
##   cycle     it steps through this many states (tracks, light patterns); the state picks
##             the colour and the note
##   colours   one per state (cycle) or per zone
##   sound     an `AudioManager` voice; `notes` are semitones per state or zone, `volume` dB,
##             `pitch` a multiplier. A drag plays higher forwards and lower back
##   bursts    [[glyph, colour, count, speed], ...] thrown off the zone; colour "cycle" is
##             the state's colour. `&"chip"` is the 4px square, anything else a UI glyph
##   effects   what it visibly does — see `_effect`
##   call      a method on the body, handed the gesture's world point (the fan's aim)
##   react     the fidget event his face answers (`ExpressionBrain.FIDGET_ROWS`)
##
## **Economy is the only thing that mints currency.** A verb pays a kindness *value* on the
## bus, as an act, exactly as `FidgetToy.pay_act` does — so the combo, the contract board and
## the per-act Dollars all see it, and the item's value node is felt. It never pays for what
## the item already pays for: a cooldown bounds every verb, a popper that pops is gone, and a
## jet pays for nothing but his soak.
##
## ## Cost
##
## Nothing per frame, ever: no `_process`, and nothing here runs but on a gesture. A tween runs
## while a squash or a swing plays and then stops; a particle emitter is built the first time
## its effect plays and emits only for that effect's seconds.

## One firing: which verb, and whether it paid. For the suites, and for anything that wants to
## know a thing was used.
signal fired(verb: StringName, paid: bool)

## Set while a verb's own act is on the bus, so his face can tell a hand at work from the
## item's ordinary payout: a boombox's trickle is his cared-for smile, a new track is a dance
## (`ExpressionBrain._worked_by_hand`). The same idiom as `Economy.paying_kind_act`.
static var paying := false

## One art pixel is this many world pixels — the 2x every sprite is drawn at.
const ART_SCALE := 2.0

## Which items carry verbs, read once from each item's scene.
static var _carries: Dictionary = {}
static var _chip: Texture2D
## One particle recipe per item and effect, for the life of the process.
static var _materials: Dictionary = {}

## The verb table, as the seed tool wrote it. See the class comment for the row format.
@export var verbs: Array = []

var body: BaseDraggable
var zones: GestureZones

## verb id -> msec before which it will not pay again; -1 for never again.
var _next_pay: Dictionary = {}
## verb id -> radians cranked or art px dragged since the last firing, this press.
var _accum: Dictionary = {}
## verb id -> the state a cycling verb is in.
var _state: Dictionary = {}
## effect key -> its emitter, and how many times it has been started (the latest run is the
## only one whose timer may stop it).
var _emitters: Dictionary = {}
var _runs: Dictionary = {}
var _tween: Tween
## The ambient emitter's own colour, before any tint, so a cycle can come back round to it.
var _ambient_colour := Color.WHITE
var _ambient_known := false

func _enter_tree() -> void:
	# Found by what it is, never by name (CLAUDE.md): the body this rides on is its parent.
	body = get_parent() as BaseDraggable

func _ready() -> void:
	# The zones announce themselves to the body on entering the tree, which every node has
	# done before any `_ready` runs.
	if body:
		zones = body.gesture_zones
	if zones:
		zones.gesture.connect(_on_gesture)

# --- reading it ------------------------------------------------------------------

func verb_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for r in verbs:
		out.append(StringName((r as Dictionary).get("id", &"")))
	return out

func row(verb: StringName) -> Dictionary:
	for r in verbs:
		if StringName((r as Dictionary).get("id", &"")) == verb:
			return r
	return {}

## The state a cycling verb is in: the track, the pattern.
func state_of(verb: StringName) -> int:
	return int(_state.get(verb, 0))

## Whether it would pay if fired now (conditions aside).
func can_pay(verb: StringName) -> bool:
	var next := int(_next_pay.get(verb, 0))
	return next >= 0 and Time.get_ticks_msec() >= next

## Anything still moving: a squash, a swing, an emitter emitting.
func is_busy() -> bool:
	if _tween and _tween.is_valid() and _tween.is_running():
		return true
	for key in _emitters:
		var emitter := _emitters[key] as GPUParticles2D
		if is_instance_valid(emitter) and emitter.emitting:
			return true
	return false

func emitter(key: String) -> GPUParticles2D:
	return _emitters.get(key) as GPUParticles2D

## Whether an item's scene carries verbs. Read from the scene's own nodes rather than kept as
## a list, so the answer cannot drift from the content — and cached, because his face asks on
## every kind payout in the game.
static func carried_by(item_id: StringName) -> bool:
	if _carries.has(item_id):
		return _carries[item_id]
	var found := false
	var item := ItemDB.get_item(item_id)
	if item and item.scene:
		var state := item.scene.get_state()
		for i in state.get_node_count():
			for p in state.get_node_property_count(i):
				if state.get_node_property_name(i, p) != &"script":
					continue
				var script := state.get_node_property_value(i, p) as Script
				if script and script.get_global_name() == &"ItemVerbs":
					found = true
	_carries[item_id] = found
	return found

# --- gestures ----------------------------------------------------------------------

const _ON := {
	GestureZones.TAP: "tap",
	GestureZones.PRESS: "press",
	GestureZones.CROSS: "cross",
	GestureZones.CRANK: "crank",
	GestureZones.DRAG: "drag",
	GestureZones.HOLD: "hold",
	GestureZones.FLICK: "flick",
	GestureZones.ACTION: "action",
}

func _on_gesture(g: GestureZones.Gesture) -> void:
	if body == null or not is_inside_tree():
		return
	for entry in verbs:
		var r := entry as Dictionary
		if not _button_matches(r, g) or not _zone_matches(r, g):
			continue
		var id := StringName(r.get("id", &""))
		# A press starts a fresh count; a release drops what was left of it.
		if g.kind == GestureZones.PRESS or g.kind == GestureZones.RELEASE:
			_accum[id] = 0.0
		var word: String = _ON.get(g.kind, "")
		if word.is_empty() or not _fires_on(r, word):
			continue
		match word:
			"crank":
				_count(r, id, absf(g.angle), g, 0.0)
			"drag":
				_count(r, id, g.delta.length(), g, signf(g.delta.x))
			_:
				_fire(r, g, 0.0)
		# A consumed item is gone; nothing further may fire on it.
		if not is_instance_valid(body) or body.is_queued_for_deletion():
			return

func _count(r: Dictionary, id: StringName, amount: float, g: GestureZones.Gesture,
		direction: float) -> void:
	var every := float(r.get("every", 0.0))
	if every <= 0.0:
		_fire(r, g, direction)
		return
	var total := float(_accum.get(id, 0.0)) + amount
	while total >= every:
		total -= every
		_fire(r, g, direction)
	_accum[id] = total

func _button_matches(r: Dictionary, g: GestureZones.Gesture) -> bool:
	var want := MOUSE_BUTTON_LEFT if String(r.get("button", "right")) == "left" else MOUSE_BUTTON_RIGHT
	return g.button == want

func _zone_matches(r: Dictionary, g: GestureZones.Gesture) -> bool:
	if g.kind == GestureZones.ACTION or g.kind == GestureZones.ACTION_END:
		return StringName(r.get("zone", &"")) == &"" and not r.has("zones")
	if r.has("zones"):
		return (r["zones"] as Array).has(g.zone)
	return StringName(r.get("zone", &"")) == g.zone

func _fires_on(r: Dictionary, word: String) -> bool:
	var on = r.get("on", "tap")
	if on is Array:
		return (on as Array).has(word)
	return String(on) == word

# --- one act ----------------------------------------------------------------------------

func _fire(r: Dictionary, g: GestureZones.Gesture, direction: float) -> void:
	var id := StringName(r.get("id", &""))
	var index := 0
	if r.has("zones"):
		index = maxi(0, (r["zones"] as Array).find(g.zone))
	if r.has("cycle"):
		index = (int(_state.get(id, 0)) + 1) % maxi(1, int(r["cycle"]))
		_state[id] = index
	var at := _where(g)
	var allowed := _conditions_hold(r)
	_present(r, index, at, direction)
	var method := StringName(r.get("call", &""))
	if method != &"" and body.has_method(method):
		body.call(method, g.world)
	var paid := allowed and _pay(r, id, at)
	var react := StringName(r.get("react", &""))
	if allowed and react != &"":
		# After the payment, as `FidgetToy.pay_act` does: the verb's act has been kept off his
		# generic reaction, so this is the only thing that answers it.
		EventBus.fidget_event.emit(body.item_id, react, at)
	fired.emit(id, paid)
	if bool(r.get("consume", false)):
		body.bin_myself()

## Where the act happened: the zone it happened on, or the item for a verb in the hand.
func _where(g: GestureZones.Gesture) -> Vector2:
	if g.zone != &"" and zones:
		return zones.zone_world(g.zone)
	return body.global_position

func _conditions_hold(r: Dictionary) -> bool:
	if not r.has("near") and not bool(r.get("touching", false)):
		return true
	var him := _buddy()
	if him == null:
		return false
	if r.has("near") and him.global_position.distance_to(body.global_position) > float(r["near"]):
		return false
	if bool(r.get("touching", false)) and not body.get_colliding_bodies().has(him):
		return false
	return true

func _pay(r: Dictionary, id: StringName, at: Vector2) -> bool:
	var value := float(r.get("value", 0.0))
	if value <= 0.0 or not can_pay(id):
		return false
	if bool(r.get("once", false)):
		_next_pay[id] = -1
	else:
		var gap := float(r.get("cooldown", 0.0)) * _modifier(&"cooldown_mult")
		_next_pay[id] = Time.get_ticks_msec() + int(gap * 1000.0)
	paying = true
	EventBus.kindness_given.emit(body.item_id, value * _modifier(&"damage_mult"), at)
	paying = false
	EventBus.contract_event.emit(&"use:%s" % body.item_id, 1)
	return true

func _modifier(key: StringName) -> float:
	return Progression.get_modifier(body.item_id, key) if body.item_id != &"" else 1.0

func _buddy() -> Buddy:
	return get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy

# --- what it looks and sounds like -------------------------------------------------------

func _present(r: Dictionary, index: int, at: Vector2, direction: float) -> void:
	var moving := Settings.focus_intensity != Settings.Intensity.OFF
	var sound := StringName(r.get("sound", &""))
	if sound != &"":
		var pitch := float(r.get("pitch", 1.0))
		var notes: Array = r.get("notes", [])
		if not notes.is_empty():
			pitch *= pow(2.0, float(notes[index % notes.size()]) / 12.0)
		if direction > 0.0:
			pitch *= 1.15
		elif direction < 0.0:
			pitch *= 0.8
		AudioManager.play(sound, float(r.get("spread", 0.06)), float(r.get("volume", -8.0)), pitch)
	var effects: Array = r.get("effects", [])
	for i in effects.size():
		_effect(effects[i], r, index, "%s%d" % [String(r.get("id", "")), i], moving)
	if not moving:
		return
	var fx := WorldFX.of(body)
	if fx == null:
		return
	for burst in r.get("bursts", []):
		var b := burst as Array
		var glyph := StringName(b[0])
		var colour := _colour(r, b[1], index)
		if glyph == &"chip":
			fx.chips(at, colour, int(b[2]), float(b[3]))
		else:
			fx.burst(at, glyph, colour, int(b[2]), float(b[3]))

## A colour from a row: a Color as written, or "cycle" for the state's own.
func _colour(r: Dictionary, value, index: int) -> Color:
	if value is Color:
		return value
	var colours: Array = r.get("colours", [])
	if colours.is_empty():
		return Color.WHITE
	return colours[index % colours.size()]

## One visible effect. Each is a Dictionary with a `kind`:
##
##   squash  {scale, anchor, seconds, delay}: the sprite squashes to `scale` and back, about
##           `anchor` (art px) — the pot's base, the duck's belly — so it does not float
##   swing   {degrees, pivot, seconds, swings}: the sprite rocks about `pivot` and settles —
##           chimes from their hook, a lamp on its foot
##   tint    {sprite, ambient}: the state's colour on the sprite, and on the ambient emitter,
##           "set" outright or "tint" over its own colour. State, so it holds at Focus Off
##   tempo   {speeds}: the ambient emitter's speed, per state — a faster track, faster notes
##   surge   {glyph, colour, at, box, velocity, spread, gravity, damping, lifetime, amount,
##           seconds, delay, scale}: particles in the item's own frame for `seconds`, all in
##           art px — wax rising in the glass, flakes falling on the water
##
## Everything but the tint is motion, and is skipped at Focus Off (D21): the verb still pays
## and he still answers it.
func _effect(e: Dictionary, r: Dictionary, index: int, key: String, moving: bool) -> void:
	match String(e.get("kind", "")):
		"tint":
			var colour := _colour(r, "cycle", index)
			if bool(e.get("sprite", false)) and body.sprite:
				body.sprite.modulate = colour
			var ambient := _ambient()
			if ambient and e.has("ambient"):
				if not _ambient_known:
					_ambient_colour = ambient.modulate
					_ambient_known = true
				ambient.modulate = colour if String(e["ambient"]) == "set" else _ambient_colour * colour
		"tempo":
			var ambient := _ambient()
			var speeds: Array = e.get("speeds", [])
			if ambient and not speeds.is_empty():
				ambient.speed_scale = float(speeds[index % speeds.size()])
		"squash":
			if moving:
				_squash(e)
		"swing":
			if moving:
				_swing(e)
		"surge":
			if moving:
				_surge(e, key, _colour(r, e.get("colour", Color.WHITE), index))

func _ambient() -> GPUParticles2D:
	if body.has_method(&"ambient_emitter"):
		return body.call(&"ambient_emitter") as GPUParticles2D
	return null

func _squash(e: Dictionary) -> void:
	var sprite := body.sprite
	if sprite == null:
		return
	_stop_tween()
	var peak: Vector2 = e.get("scale", Vector2(1.1, 0.9))
	var anchor: Vector2 = e.get("anchor", Vector2.ZERO)
	_tween = create_tween()
	if e.has("delay"):
		_tween.tween_interval(float(e["delay"]))
	_tween.tween_method(_squash_at.bind(sprite, peak, anchor), 0.0, 1.0, float(e.get("seconds", 0.25)))
	_tween.tween_callback(_rest_sprite)

## Out to `peak` and back, a little past rest on the way home. The position moves with the
## scale so that `anchor` stays where it was drawn.
func _squash_at(k: float, sprite: Node2D, peak: Vector2, anchor: Vector2) -> void:
	if not is_instance_valid(sprite):
		return
	var w := sin(PI * minf(k * 1.25, 1.0)) - 0.25 * sin(PI * clampf((k - 0.8) * 5.0, 0.0, 1.0))
	var s := Vector2.ONE.lerp(peak, w)
	sprite.scale = s * ART_SCALE
	sprite.position = anchor * ART_SCALE * (Vector2.ONE - s)

func _swing(e: Dictionary) -> void:
	var sprite := body.sprite
	if sprite == null:
		return
	_stop_tween()
	var degrees := float(e.get("degrees", 6.0))
	var pivot: Vector2 = e.get("pivot", Vector2.ZERO)
	var swings := float(e.get("swings", 2.5))
	_tween = create_tween()
	_tween.tween_method(_swing_at.bind(sprite, degrees, pivot, swings), 0.0, 1.0, float(e.get("seconds", 1.0)))
	_tween.tween_callback(_rest_sprite)

## A decaying rock about `pivot`: the position moves with the angle so the pivot stays put.
func _swing_at(k: float, sprite: Node2D, degrees: float, pivot: Vector2, swings: float) -> void:
	if not is_instance_valid(sprite):
		return
	var angle := deg_to_rad(degrees) * sin(TAU * swings * k) * (1.0 - k)
	var p := pivot * ART_SCALE
	sprite.rotation = angle
	sprite.position = p - p.rotated(angle)

func _stop_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
	_rest_sprite()

func _rest_sprite() -> void:
	var sprite := body.sprite if body else null
	if sprite == null or not is_instance_valid(sprite):
		return
	sprite.scale = Vector2.ONE * ART_SCALE
	sprite.position = Vector2.ZERO
	sprite.rotation = 0.0

func _surge(e: Dictionary, key: String, colour: Color) -> void:
	var emitter := _emitter_for(key, e, colour)
	if emitter == null:
		return
	var seconds := float(e.get("seconds", 1.0))
	var delay := float(e.get("delay", 0.0))
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(_start.bind(key, seconds))
	else:
		_start(key, seconds)

func _start(key: String, seconds: float) -> void:
	var emitter := _emitters.get(key) as GPUParticles2D
	if not is_instance_valid(emitter):
		return
	var run := int(_runs.get(key, 0)) + 1
	_runs[key] = run
	emitter.emitting = true
	emitter.restart()
	get_tree().create_timer(seconds).timeout.connect(_stop.bind(key, run))

## Stops an emitter when the run that started it is up — and only then, so a second churn
## started half way through the first is not cut short by the first one's timer. Counted by
## run rather than by clock: a timer's seconds are process time, which is not the wall clock,
## and a stop that compared the two could miss by a frame and leave it emitting for good.
func _stop(key: String, run: int) -> void:
	var emitter := _emitters.get(key) as GPUParticles2D
	if not is_instance_valid(emitter) or int(_runs.get(key, 0)) != run:
		return
	emitter.emitting = false

func _emitter_for(key: String, e: Dictionary, colour: Color) -> GPUParticles2D:
	var known := _emitters.get(key) as GPUParticles2D
	if is_instance_valid(known):
		return known
	var em := GPUParticles2D.new()
	em.name = "Verb%s" % key.to_pascal_case()
	em.one_shot = false
	em.emitting = false
	# The item's own frame: wax rises up the lamp however the lamp is lying, and goes where
	# the lamp goes.
	em.local_coords = true
	em.z_index = 1
	em.amount = maxi(1, int(e.get("amount", 8)))
	em.lifetime = float(e.get("lifetime", 1.0))
	var glyph := StringName(e.get("glyph", &"chip"))
	em.texture = _chip_texture() if glyph == &"chip" else UIStyle.glyph(glyph)
	em.modulate = colour
	var at: Vector2 = e.get("at", Vector2.ZERO)
	em.position = at * ART_SCALE
	em.process_material = _material("%s|%s" % [body.item_id, key], e)
	body.add_child(em)
	_emitters[key] = em
	return em

static func _material(cache_key: String, e: Dictionary) -> ParticleProcessMaterial:
	if _materials.has(cache_key):
		return _materials[cache_key]
	var mat := ParticleProcessMaterial.new()
	var velocity: Vector2 = e.get("velocity", Vector2(0, -20))
	velocity *= ART_SCALE
	var speed := velocity.length()
	mat.direction = Vector3(velocity.x, velocity.y, 0.0).normalized() if speed > 0.0 \
		else Vector3(0, -1, 0)
	mat.spread = float(e.get("spread", 15.0))
	mat.initial_velocity_min = speed * 0.7
	mat.initial_velocity_max = speed
	# Set outright: a ParticleProcessMaterial falls at 9.8 by default, which in pixels is a drift.
	var gravity: Vector2 = e.get("gravity", Vector2.ZERO)
	gravity *= ART_SCALE
	mat.gravity = Vector3(gravity.x, gravity.y, 0.0)
	var damping := float(e.get("damping", 0.0)) * ART_SCALE
	mat.damping_min = damping * 0.8
	mat.damping_max = damping
	var box: Vector2 = e.get("box", Vector2(2, 2))
	box *= ART_SCALE
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(maxf(box.x, 0.5), maxf(box.y, 0.5), 1.0)
	var scale: Vector2 = e.get("scale", Vector2(1.0, 1.6))
	mat.scale_min = scale.x
	mat.scale_max = scale.y
	# Shrinking to nothing rather than fading, like every other chip in the world (WorldFX).
	var curve := CurveTexture.new()
	var shape := Curve.new()
	shape.add_point(Vector2(0.0, 1.0))
	shape.add_point(Vector2(0.75, 0.9))
	shape.add_point(Vector2(1.0, 0.0))
	curve.curve = shape
	mat.scale_curve = curve
	_materials[cache_key] = mat
	return mat

static func _chip_texture() -> Texture2D:
	if _chip == null:
		var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_chip = ImageTexture.create_from_image(image)
	return _chip
