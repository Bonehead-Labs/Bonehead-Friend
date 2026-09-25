class_name FriendlyBase
extends BaseDraggable

## Everything on the kindness side of the toy box, as one class with three switches.
##
## The friendly catalog has three shapes and only three (docs/economy.md): a burst on
## touch (pizza), sustained payment while something is true (sponge scrubbing, boombox
## playing), and a consumable that leaves when used. Each is an exported number here, so a
## new friendly item is a `.tres` plus a scene with different values in it — never a script
## (docs/decisions.md D8). One class also means the combo window, the mood nudge and the
## Hearts payout behave identically across the whole friendly roster, which matters
## because Economy applies the same pipeline to all of them.

## One-off Hearts when he first touches this, then nothing until `contact_cooldown` has
## passed. Pizza. Zero disables.
@export var hearts_per_contact: float = 0.0
@export var contact_cooldown: float = 1.0

## Hearts per second while he is touching it. Zero disables.
@export var hearts_per_second_touching: float = 0.0

## Hearts per second simply for existing in the world — the boombox and the rest of the
## Hearts generators. This is the shape every automation capstone will take, which is why
## it is a plain rate on a spawned object rather than anything cleverer.
@export var hearts_per_second_placed: float = 0.0

## Grime removed per second of contact. The sponge, and only the sponge. Payment is on
## grime *actually removed*, so scrubbing a clean skeleton earns nothing.
@export var cleans_grime: bool = false

## Vanishes once it has paid out. Food.
@export var consume_on_use: bool = false

## How many helpings a consumable is: one per contact, `contact_cooldown` apart, and gone after
## the last. A box of donuts is six, and says so (D65) — it was eaten whole on the first touch.
## Ignored unless `consume_on_use`.
@export var servings: int = 1
var _eaten := 0

## Minimum closing speed for `hearts_per_contact` to pay. The baseball's catch mechanic:
## he catches a *throw*, so resting a ball against him — or dropping it from one pixel up —
## must be worth nothing. Zero disables the check, which is what the pizza wants.
@export var min_contact_speed: float = 0.0

## How long the item sits in the world before it stops paying its placed rate. Zero means
## forever. Nothing uses it yet; it exists so a consumable generator does not need a new
## class when one appears.
@export var lifetime_seconds: float = 0.0

## The player holds this against him; it is not something he goes and uses himself. The
## feather duster pays `hearts_per_second_touching` exactly as a beanbag does, and without
## this flag `IdleBrain` would read that switch, walk him over and try to sit in a duster.
## The switches say what a thing *pays for*; this says whose hands it belongs in.
@export var handheld: bool = false

## What it sounds like when he first gets into it: `splash` for anything with water in it,
## `impact_soft` for a chair. Empty is silent. Played once per entry, not per frame.
@export var entry_sound: StringName = &""
var _was_touching := false

## Sustained kindness is banked and flushed on this interval rather than emitted every
## physics frame. Sixty payouts a second would put sixty floating numbers a second through
## the FX pool and sixty signals a second on the bus, for a rate the player experiences as
## one smooth trickle.
const FLUSH_SECONDS := 0.5

var _next_contact_msec := 0
var _age := 0.0
var _banked := 0.0
var _bank_position := Vector2.ZERO
var _since_flush := 0.0

## Speed on the previous tick. The contact that matters has already been solved by the time
## _physics_process runs, so the ball is *slower* than it was when it hit him — reading only
## the current speed would reject exactly the hardest throws, which are the ones that lose
## the most speed on impact.
var _previous_speed := 0.0

func _ready() -> void:
	super._ready()
	# get_colliding_bodies() is only populated when the body is reporting contacts. A few is
	# plenty: we only ever ask whether one specific body is in the list.
	contact_monitor = true
	max_contacts_reported = maxi(max_contacts_reported, 4)
	_build_ambient()
	EventBus.focus_mode_changed.connect(func(_level: int) -> void: _gate_ambient())

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_age += delta
	if lifetime_seconds > 0.0 and _age > lifetime_seconds:
		_despawn()
		return

	var value := value_multiplier()
	if hearts_per_second_placed > 0.0:
		_bank(hearts_per_second_placed * value * delta, global_position)

	# Nothing to ask the physics server when nothing here pays for touching him and there is
	# no entry sound to play: twenty ambience items polling `get_colliding_bodies()` every
	# tick for eight hours was a cost with no reader.
	var cares := hearts_per_second_touching > 0.0 or cleans_grime or hearts_per_contact > 0.0 \
		or entry_sound != &""
	var buddy := _touching_buddy() if cares else null
	var touching := buddy != null
	if touching and not _was_touching and entry_sound != &"":
		AudioManager.play(entry_sound, 0.10, -8.0)
	# He got in: a burst of hearts off him, more for an upgraded item (D41).
	if touching and not _was_touching and (hearts_per_second_touching > 0.0 or hearts_per_contact > 0.0):
		var fx := WorldFX.of(self)
		if fx:
			fx.burst(buddy.global_position, &"heart", trail_colour(), 5 + 3 * juice_tier, 130.0)
	_was_touching = touching
	if buddy != null:
		if hearts_per_second_touching > 0.0:
			_bank(hearts_per_second_touching * value * delta, buddy.global_position)

		if cleans_grime and buddy.grime:
			var removed := buddy.grime.clean(ItemDB.balance.sponge_clean_rate * delta)
			if removed > 0.0:
				# The *pay* scales, not the scrubbing. Scrubbing faster would be a nerf
				# dressed as an upgrade: grime is finite, so a sponge that removes it twice
				# as fast earns the same Hearts in half the time and then has nothing left
				# to clean.
				_bank(removed * ItemDB.balance.hearts_per_grime_cleaned * value,
					buddy.global_position)

		if hearts_per_contact > 0.0 and _approach_speed() >= min_contact_speed:
			var now := Time.get_ticks_msec()
			if now >= _next_contact_msec:
				var gap := contact_cooldown * Progression.get_modifier(item_id, &"cooldown_mult")
				_next_contact_msec = now + int(gap * 1000.0)
				_pay_event(hearts_per_contact * value, buddy.global_position)
				if consume_on_use:
					_eaten += 1
					if _eaten >= servings:
						_flush()
						_despawn()
						return

	_previous_speed = linear_velocity.length()
	_since_flush += delta
	if _since_flush >= FLUSH_SECONDS:
		_flush()

## The kindness-value multiplier, which on this side of the economy is what `damage_mult`
## means (docs/economy.md).
##
## It scales the *value* emitted rather than the Hearts paid, so it is a different node from
## the flat payout multiplier beside it in the tree: MoodComponent nudges his mood by the
## same number, so a better-loved item buys mood as well as Hearts. Without this every
## friendly item's damage node was a placebo — which two of them shipped as in M3, and is
## half the reason M3.5 exists.
func value_multiplier() -> float:
	if item_id == &"":
		return 1.0
	return Progression.get_modifier(item_id, &"damage_mult")

## Kindness goes on the bus as a *value*, not as Hearts. Economy is the only thing allowed
## to mint currency, and it is what applies the combo, the mood curve, the augments and
## prestige — exactly as it does for damage (docs/economy.md, one pipeline).
func _approach_speed() -> float:
	return maxf(linear_velocity.length(), _previous_speed)

func _pay_event(value: float, at: Vector2) -> void:
	if value <= 0.0:
		return
	EventBus.kindness_given.emit(item_id, value, at)

func _bank(value: float, at: Vector2) -> void:
	if value <= 0.0:
		return
	_banked += value
	_bank_position = at

func _flush() -> void:
	_since_flush = 0.0
	if _banked <= 0.0:
		return
	EventBus.kindness_sustained.emit(item_id, _banked, _bank_position)
	_banked = 0.0

func _touching_buddy() -> Buddy:
	for body in get_colliding_bodies():
		if body is Buddy:
			return body as Buddy
	return null

func _despawn() -> void:
	EventBus.item_despawned.emit(self)
	queue_free()

## Banked kindness is paid on the way out, whatever the exit. A sponge binned mid-scrub, or
## evicted by the item limit, otherwise silently swallows up to FLUSH_SECONDS of Hearts —
## and the trash bin and the spawner both free items without going through _despawn().
func _exit_tree() -> void:
	_flush()

## A kind item leaves a rose trail, not a gold one, and its aura is hearts.
func trail_colour() -> Color:
	return WorldFX.kind_colour(juice_tier)

func aura_glyph() -> StringName:
	return &"heart"

## An upgraded kind item has more life on it: the ambient emitter grows with the tier.
func apply_juice() -> void:
	super.apply_juice()
	if _ambient and _ambient_base_amount > 0:
		_ambient.amount = int(round(_ambient_base_amount * (1.0 + 0.5 * juice_tier)))

# --- ambient life -------------------------------------------------------------
#
# Steam off anything hot, bubbles off anything wet, a twinkle on anything that glows, notes
# off anything that plays (docs/decisions.md D39). A few GPU chips a second on a continuous
# emitter parented to the item, so it goes where the item goes and costs the CPU nothing per
# frame. Keyed by item id here rather than by a field on the scene, so a new item joins the
# table without a scene rebuild. Off at Focus Off like every other moving thing.

const AMBIENT := {
	&"hot_tub": &"steam", &"foot_spa": &"steam", &"cup_of_tea": &"steam",
	&"noodle_bowl": &"steam", &"pizza": &"steam", &"chocolate_fountain": &"steam",
	&"bubble_machine": &"bubbles", &"fish_tank": &"bubbles", &"paddling_pool": &"bubbles",
	&"fairy_lights": &"twinkle", &"lava_lamp": &"twinkle", &"birthday_cake": &"twinkle",
	&"wind_chimes": &"twinkle", &"boombox": &"notes", &"record_player": &"notes",
}
const STEAM := Color("e8e4d6")
const BUBBLE := Color("bfe6ff")
const TWINKLE := Color("ffc247")
const NOTE := Color("2fb5b0")

static var _ambient_materials: Dictionary = {}
static var _ambient_chip: Texture2D
var _ambient: GPUParticles2D
var _ambient_base_amount := 0

func ambient_kind() -> StringName:
	return AMBIENT.get(item_id, &"")

func _build_ambient() -> void:
	var kind := ambient_kind()
	if kind == &"" or _ambient != null:
		return
	var extent := _sprite_extent()
	_ambient = GPUParticles2D.new()
	_ambient.name = "Ambient"
	_ambient.one_shot = false
	_ambient.local_coords = false
	_ambient.z_index = 1
	match kind:
		&"steam":
			_ambient.texture = _chip()
			_ambient.modulate = STEAM
			_ambient.amount = 9
			_ambient.lifetime = 1.6
			_ambient.position = Vector2(0, -extent.y)
			_ambient.process_material = _ambient_material(kind, 30.0, -25.0, 1.4, 2.4,
				Vector2(extent.x * 0.35, 2.0), false)
		&"bubbles":
			_ambient.texture = _chip()
			_ambient.modulate = BUBBLE
			_ambient.amount = 6
			_ambient.lifetime = 1.4
			_ambient.position = Vector2(0, -extent.y * 0.6)
			_ambient.process_material = _ambient_material(kind, 50.0, -60.0, 0.8, 1.4,
				Vector2(extent.x * 0.3, 4.0), false)
		&"twinkle":
			_ambient.texture = UIStyle.glyph(&"star")
			_ambient.modulate = TWINKLE
			_ambient.amount = 5
			_ambient.lifetime = 0.8
			_ambient.position = Vector2.ZERO
			_ambient.process_material = _ambient_material(kind, 0.0, 0.0, 0.4, 0.7,
				Vector2(extent.x * 0.45, extent.y * 0.45), true)
		&"notes":
			_ambient.texture = _chip()
			_ambient.modulate = NOTE
			_ambient.amount = 4
			_ambient.lifetime = 1.2
			_ambient.position = Vector2(0, -extent.y)
			_ambient.process_material = _ambient_material(kind, 45.0, -40.0, 1.2, 1.8,
				Vector2(extent.x * 0.3, 2.0), false)
	_ambient_base_amount = _ambient.amount
	add_child(_ambient)
	_gate_ambient()

func _gate_ambient() -> void:
	if _ambient:
		_ambient.emitting = Settings.focus_intensity != Settings.Intensity.OFF

## Half the drawn size of the sprite, so an emitter can sit on the item's top edge and a
## twinkle can fill its face. A 32px square if there is no texture to measure.
func _sprite_extent() -> Vector2:
	var s := sprite as Sprite2D
	if s and s.texture:
		return s.texture.get_size() * s.scale.abs() * 0.5
	return Vector2(16, 16)

static func _chip() -> Texture2D:
	if _ambient_chip == null:
		var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_ambient_chip = ImageTexture.create_from_image(image)
	return _ambient_chip

## One recipe per kind and size, shared by every item of that kind for the life of the process.
static func _ambient_material(kind: StringName, speed: float, gravity_y: float, scale_min: float,
		scale_max: float, box: Vector2, pulse: bool) -> ParticleProcessMaterial:
	var key := "%s|%d|%d" % [kind, int(box.x), int(box.y)]
	if _ambient_materials.has(key):
		return _ambient_materials[key]
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 20.0
	mat.initial_velocity_min = speed * 0.6
	mat.initial_velocity_max = speed
	mat.gravity = Vector3(0, gravity_y, 0)
	mat.scale_min = scale_min
	mat.scale_max = scale_max
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(maxf(box.x, 1.0), maxf(box.y, 1.0), 1.0)
	var curve := CurveTexture.new()
	var shape := Curve.new()
	if pulse:
		# A twinkle appears, peaks and is gone.
		shape.add_point(Vector2(0.0, 0.0))
		shape.add_point(Vector2(0.5, 1.0))
		shape.add_point(Vector2(1.0, 0.0))
	else:
		shape.add_point(Vector2(0.0, 1.0))
		shape.add_point(Vector2(0.6, 0.9))
		shape.add_point(Vector2(1.0, 0.0))
	curve.curve = shape
	mat.scale_curve = curve
	_ambient_materials[key] = mat
	return mat
