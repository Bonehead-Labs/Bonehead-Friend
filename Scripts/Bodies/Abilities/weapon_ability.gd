class_name WeaponAbility
extends Node

## What a weapon does with the right button while it is in your hand (docs/decisions.md D74).
##
## The owner, after swinging the melee drawer: "other than their sprite they didn't feel
## unique". A bat and a mace were one verb with two pictures. So every held weapon gets one
## thing only it does — a home run, a cut straight through him, a BONG — on the button D56 and
## D57 already gave to "the item's action": **right while holding**.
##
## ## The grammar, unchanged
##
## - Left carries. Right while holding is the ability: press, hold, let go.
## - Right on a weapon you are *not* holding still bins it, and Shift+right bins it anywhere,
##   held or not. Nothing here claims Shift (`BaseDraggable.click_would_bin`).
## - A press during the cooldown is claimed and refused — a dull tick, and the pip flashes —
##   never passed through: mashing right on a cooling bat must not throw the bat away.
##
## ## How a weapon gets one
##
## A row in `AbilityTable.ABILITIES`, keyed by item id, naming an **archetype** (`charge`,
## `dash`, `stun`, `sustain`, `shockwave`, `projectile`, `spin`, `throw`) and its numbers.
## `BaseDraggable._ready` asks the table and adds the archetype's script as a child (D78: any held
## thing with a row, not only a weapon). Each archetype is a subclass of this that overrides the
## hooks below and nothing else; a weapon that needs behaviour its archetype lacks names a subclass
## of that archetype in the row's `script`. A kind row (`kind`) pays with `give`, never `strike`.
##
## ## Damage is still his to measure (D7, D64)
##
## An ability never mints anything. It does one of three things, and he bills each:
##   - moves a body — the weapon, or him — so that a contact happens his ledger bills;
##   - scales the weapon's own contact multiplier for a hit (`hit_multiplier`), which he reads
##     when he attributes the hit, exactly as he reads the damage augment;
##   - hands him an impulse through `Buddy.take_impulse`, the gunshot's path, at the weapon's
##     multiplier.
## Anything it applies to *him* directly is applied from `_physics_process`, which runs before
## `Buddy.StepStart` reads the step's starting velocity, so his ledger never mistakes a launch
## for a contact and bills it a second time.
##
## ## Cost
##
## Nothing runs while the weapon lies on the desk or the ability is idle: no `_process`, no
## `_physics_process`, no `_input`. Each is switched on for exactly as long as it is needed — the
## physics tick while an effect runs, the input hook while right is down, the frame tick while
## the pip is being drawn — and off again. The cooldown is a stopped `Timer` the rest of the time.

## One activation began, and one landed on him. For the suites and the capture tool; nothing in
## the simulation listens.
signal used(ability: StringName)
signal paid_off(event: StringName)

## One art pixel is this many world pixels — the 2x every sprite is drawn at.
const ART_SCALE := 2.0
## The layers a sweep looks for him on, and for the world on.
const BUDDY_LAYER := 2
const WORLD_LAYER := 1
## He knows a wind-up is aimed at him inside this range, like a gun's aim (D56).
const THREAT_REACH := 360.0
const THREAT_REFRESH_MSEC := 500

## The row, as `AbilityTable` holds it. See the table's comment for the fields.
var row: Dictionary = {}
## The thing in the hand. A `WeaponBase` for every D74 row; since D78 any `BaseDraggable` the table
## has a row for — a ball, a sponge, a sticky bomb — which is why nothing here reads a weapon's own
## fields except through `base_mult`. The class keeps its name: every archetype extends it.
var body: BaseDraggable

## Activations started, presses refused, and times the effect landed on him — for the suites.
## Never read by the simulation.
var uses := 0
var denied := 0
var payoffs := 0
## The multiplier each of the weapon's last hits was billed at on top of its own — through
## `hit_multiplier`, or through `strike` — and the impulse each hit it handed him itself carried.
var billed: Array[float] = []
var struck: Array[float] = []

var _active := false
var _right_held := false
var _pressed_usec := 0
var _cooldown_seconds := 0.0
var _ready_timer: Timer
var _pip: Pip
var _buddy: Buddy
var _threatening := false
var _threat_refresh_msec := 0
var _chip: Texture2D

func _ready() -> void:
	# After the body's own chase in the same physics frame, so a hand offset written here is
	# the last word on where the handle is before the step.
	process_physics_priority = 1
	set_physics_process(false)
	set_process(false)
	set_process_input(false)
	_ready_timer = Timer.new()
	_ready_timer.name = "Cooldown"
	_ready_timer.one_shot = true
	_ready_timer.timeout.connect(_on_cooled)
	add_child(_ready_timer)
	paid_off.connect(_on_paid_off_fx)

func _exit_tree() -> void:
	if _active:
		_on_stop()
	_active = false
	_threaten(false)
	# Nothing of it stays on him once the weapon has gone (D77).
	AbilityFX.clear_states(buddy(), self)

# --- reading it -------------------------------------------------------------------

func ability_id() -> StringName:
	return StringName(row.get("id", &""))

func ability_name() -> String:
	return String(row.get("name", ""))

func archetype() -> StringName:
	return StringName(row.get("archetype", &""))

## Ready to use: not running and not cooling down.
func is_ready() -> bool:
	return not _active and (_ready_timer == null or _ready_timer.is_stopped())

func is_active() -> bool:
	return _active

func is_cooling() -> bool:
	return _ready_timer != null and not _ready_timer.is_stopped()

func cooldown_left() -> float:
	return _ready_timer.time_left if is_cooling() else 0.0

## Seconds right has been held, 0 when it is not.
func held_seconds() -> float:
	if not _right_held:
		return 0.0
	return float(Time.get_ticks_usec() - _pressed_usec) / 1_000_000.0

func right_held() -> bool:
	return _right_held

## Whether anything here runs a frame, for the budget assertions.
func is_busy() -> bool:
	return is_physics_processing() or is_processing() or is_processing_input()

## What a hit from the weapon is multiplied by right now, on top of its own multiplier and its
## damage augment. One outside a charged hit, a daze, a throw.
func hit_multiplier() -> float:
	return 1.0

## Every multiplier the weapon's recent hits were billed at through this — one, and whatever a
## charge, a daze or a throw armed them with. For a suite that checks each hit's number against
## the data: a hit at any other multiplier is a bug.
func multipliers() -> Array[float]:
	var out: Array[float] = [1.0]
	for m in billed:
		if not out.has(m):
			out.append(m)
	return out

# --- input, from BaseDraggable ----------------------------------------------------------

## Every event on the weapon, before its own grab and bin logic. True claims it.
func take(event: InputEvent) -> bool:
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_RIGHT:
		return false
	if click.pressed:
		# Shift+right is the bin and never ours.
		if click.shift_pressed or body == null:
			return false
		# A second action while the effect runs, in the hand or on the thing where it lies — a
		# sticky bomb on the clicker, set off by clicking it (D78). Nothing in D74 takes one.
		if _active and (body.dragging or (body.drag_area and body.drag_area.is_hovered)) \
				and _press_again():
			return true
		if body.dragging:
			# Not ours yet: a charge's first right press lights its fuse, as it always did (D78).
			if not _wants_press():
				return false
			press()
			return true
		# Out of the hand but still mid-effect — an axe in the air — a right-click on it is a second
		# press, refused, not the bin: the same rule as mashing right on a cooling bat.
		if _active and body.drag_area and body.drag_area.is_hovered:
			denied += 1
			_refuse()
			return true
		# Right on a weapon nobody holds bins it, as it always did.
		return false
	if _right_held:
		release()
		return true
	return false

## Every release, not only the unhandled ones: a release over a panel is the panel's, and an
## ability that only let go on an unhandled release would charge forever (HeldGun learned this
## first). Only listened for while right is down.
func _input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.button_index == MOUSE_BUTTON_RIGHT and not click.pressed:
		release()

func press() -> void:
	if _right_held or body == null:
		return
	if not is_ready() or not _can_start():
		denied += 1
		_refuse()
		return
	_right_held = true
	_pressed_usec = Time.get_ticks_usec()
	set_process_input(true)
	_active = true
	uses += 1
	used.emit(ability_id())
	_in_press = true
	_on_press()
	_in_press = false
	_fx_activated()

func release() -> void:
	if not _right_held:
		return
	var seconds := held_seconds()
	_right_held = false
	set_process_input(false)
	if _active:
		_on_release(seconds)

## The weapon left the hand. An effect that needs the hand ends here; one that does not — an
## axe in the air — says so in `_on_dropped`.
func on_dropped() -> void:
	if _right_held:
		_right_held = false
		set_process_input(false)
	if _active:
		_on_dropped()
	_update_pip()
	_fx_glint(false)

## The weapon landed a hit he billed (`WeaponBase.register_use`, from his attribution step).
## Inside his `_integrate_forces`: record it here, act on it in `_physics_process`.
func note_hit() -> void:
	# What this hit is about to be billed at: he reads `hit_multiplier` on the next line of his
	# attribution step, and `_on_hit` must not change it before he does.
	billed.append(hit_multiplier())
	if billed.size() > 16:
		billed.pop_front()
	# Where the contact touched him, while he still knows (`Buddy.hit_at`, set only for the length of
	# his attribution): a payoff for this hit a tick later is drawn there, not at his middle (D77).
	var him := buddy()
	if him and him.hit_at != Vector2.INF:
		_strike_at = him.hit_at
		_strike_frame = Engine.get_physics_frames()
	if _active:
		_on_hit()

## The weapon was picked up: the pip comes back if it is still cooling, and the glint if it is not.
func on_picked_up() -> void:
	_update_pip()
	_fx_glint(true)

# --- the archetype's hooks --------------------------------------------------------------

## Whether it may start at all right now — a golf club with nobody to drive at, say.
func _can_start() -> bool:
	return true

## Whether a right press in the hand is this ability's at all. False hands the press on untouched,
## where `_can_start` would claim and refuse it: a charge's first right press is its fuse (D78).
func _wants_press() -> bool:
	return true

## A right press on the thing while its effect is still running — held, or hovered where it lies.
## True takes it as a second action; false leaves the D74 rule, a refusal.
func _press_again() -> bool:
	return false

## The window lost the focus with right still held: the release will never arrive (D70 — an
## alt-tab mid-draw used to fire the slingshot). True if the ability let go of what it was doing,
## as a cancel and never as the release it did not get; false, the default, changes nothing.
func _on_focus_lost() -> bool:
	return false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _right_held and _active and _on_focus_lost():
		_right_held = false
		set_process_input(false)
		_update_pip()

func _on_press() -> void:
	pass

func _on_release(_seconds: float) -> void:
	pass

func _on_tick(_delta: float) -> void:
	pass

func _on_hit() -> void:
	pass

## Default: an effect that needs the hand is over when the hand lets go.
func _on_dropped() -> void:
	finish()

## Undo anything the effect changed on another body: an exception, a buddy's emitter.
func _on_stop() -> void:
	pass

## 0..1 while something is filling (a charge, a rev), or -1 for nothing to show.
func pip_fill() -> float:
	return -1.0

# --- running and finishing -------------------------------------------------------------

## The physics tick, on for exactly as long as the effect needs it.
func run(on: bool) -> void:
	set_physics_process(on)

func _physics_process(delta: float) -> void:
	# Not while the hit-stop has physics switched off (D54): a torque or an offset applied to a
	# stopped world is all handed over at once when it resumes.
	if BaseDraggable.physics_frozen:
		return
	_on_tick(delta)
	if _threatening and Time.get_ticks_msec() >= _threat_refresh_msec:
		_threaten(true)

## The effect is over: stop it, and start the cooldown (the row's own, or `seconds`).
func finish(seconds: float = -1.0) -> void:
	if not _active:
		return
	_active = false
	_cue_state = false
	run(false)
	_threaten(false)
	_on_stop()
	var gap := seconds if seconds >= 0.0 else float(row.get("cooldown", 3.0))
	if body and body.item_id != &"":
		gap *= Progression.get_modifier(body.item_id, &"cooldown_mult")
	_cooldown_seconds = maxf(gap, 0.05)
	_ready_timer.start(_cooldown_seconds)
	_update_pip()
	_fx_glint(false)

func _on_cooled() -> void:
	_update_pip()
	if body and body.dragging:
		fx_readied += 1
	_fx_glint(true)
	if body and body.dragging:
		# Ready again: a small ring off the hand and a tick, so the player need not watch the pip.
		var fx := fx()
		if fx:
			fx.ring(hand_world(), 22.0, tier_colour(), 0.2, 2.0)
		sound(&"plink", -16.0, 1.6)

## A press refused: a dull tick and the pip flashes.
func _refuse() -> void:
	sound(&"ui_denied", -16.0, 1.4)
	if _pip:
		_pip.flash()

# --- the pip -----------------------------------------------------------------------------
#
# A ring by the hand: filling while something charges, emptying clockwise while it cools. Drawn
# only while the weapon is held and there is something to show, and redrawn only then.

func _update_pip() -> void:
	var show := body != null and body.dragging and (is_cooling() or pip_fill() >= 0.0)
	if show and _pip == null:
		_pip = Pip.new()
		_pip.name = "AbilityPip"
		_pip.top_level = true
		_pip.z_index = 40
		add_child(_pip)
	if _pip:
		_pip.visible = show
	set_process(show)
	if show:
		_draw_pip()

func _process(_delta: float) -> void:
	if body == null or not body.dragging:
		_update_pip()
		return
	_draw_pip()

func _draw_pip() -> void:
	if _pip == null:
		return
	_pip.global_position = (hand_world() + Vector2(16, -16)).round()
	var fill := pip_fill()
	if fill >= 0.0:
		_pip.show_fill(fill, tier_colour(), true)
	elif is_cooling():
		_pip.show_fill(1.0 - _ready_timer.time_left / maxf(_cooldown_seconds, 0.01), tier_colour(), false)

## The ring. Eight pixels across, a dark track and the tier colour over it.
class Pip extends Node2D:
	const RADIUS := 6.0
	const TRACK := Color("1a1714")
	var fill := 0.0
	var colour := Color.WHITE
	var charging := false
	var _flash_until := 0

	func show_fill(value: float, tint: Color, is_charge: bool) -> void:
		var v := clampf(value, 0.0, 1.0)
		if is_equal_approx(v, fill) and tint == colour and is_charge == charging \
				and Time.get_ticks_msec() > _flash_until:
			return
		fill = v
		colour = tint
		charging = is_charge
		queue_redraw()

	func flash() -> void:
		_flash_until = Time.get_ticks_msec() + 180
		queue_redraw()

	func _draw() -> void:
		var flashing := Time.get_ticks_msec() <= _flash_until
		draw_circle(Vector2.ZERO, RADIUS + 2.0, TRACK)
		draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 20, Color("4a433a"), 3.0, false)
		if fill > 0.0:
			var tint := Color.WHITE if flashing else (colour.lightened(0.35) if charging else colour)
			draw_arc(Vector2.ZERO, RADIUS, -PI * 0.5, -PI * 0.5 + TAU * fill,
				maxi(4, int(20.0 * fill)), tint, 3.0, false)
		elif flashing:
			draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 20, Color.WHITE, 3.0, false)

# --- helpers for the archetypes ------------------------------------------------------------

func buddy() -> Buddy:
	if not is_instance_valid(_buddy) and is_inside_tree():
		_buddy = get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy
	return _buddy

func fx() -> WorldFX:
	return WorldFX.of(body) if body else null

func sound(id: StringName, volume_db: float = -8.0, pitch: float = 1.0, spread: float = 0.05) -> void:
	AudioManager.play(id, spread, volume_db, pitch)

## A number from the row, or a default.
func num(key: String, fallback: float) -> float:
	return float(row.get(key, fallback))

func tier_colour() -> Color:
	return WorldFX.harm_colour(body.juice_tier if body else 0)

## His centre of mass in the world, or INF with nobody there.
func him_world() -> Vector2:
	var him := buddy()
	if him == null:
		return Vector2.INF
	return him.global_transform * him.center_of_mass

## Where the hand is: the handle the drag joint pins to, or the grip when nothing holds it.
func hand_world() -> Vector2:
	if body and body.dragging and body.handle:
		return body.handle.global_position
	return grip_world()

func grip_world() -> Vector2:
	return body.to_global(body.grip_offset)

func com_world() -> Vector2:
	return body.global_transform * body.center_of_mass

## The end of the weapon furthest from the hand: the barrel of a bat, the blade's point.
func tip_world() -> Vector2:
	return body.to_global(body._find_tip())

## Moment of inertia about the grip: the body's own about its centre of mass, plus m r² — the
## held gun's arithmetic (D56).
func pivot_inertia() -> float:
	var arm := com_world() - grip_world()
	var inertia := body.mass * 400.0
	var state := PhysicsServer2D.body_get_direct_state(body.get_rid())
	if state and state.inverse_inertia > 0.0:
		inertia = 1.0 / state.inverse_inertia
	return inertia + body.mass * arm.length_squared()

## +1 if turning clockwise (as drawn, y down) swings the weapon's head toward him, -1 if the
## other way. Clockwise when he is on the head's right as seen from the hand.
func swing_sign() -> float:
	var him := him_world()
	if him == Vector2.INF:
		return 1.0
	var grip := grip_world()
	var lever := com_world() - grip
	var to_him := him - grip
	var cross := lever.cross(to_him)
	return 1.0 if cross >= 0.0 else -1.0

## Spins the weapon about the hand by `omega` rad/s more, the way a wrist does it: a push on the
## centre of mass across the lever, which the drag joint at the grip turns into a swing. A
## torque about the centre of mass would spin it about the wrong point and yank the joint.
func whip(omega: float) -> void:
	var grip := grip_world()
	var com := com_world()
	var lever := com - grip
	if lever.length_squared() < 1.0:
		body.apply_torque_impulse(omega * pivot_inertia())
		return
	# The clockwise tangent (y down): a lever pointing right moves down when turned clockwise.
	var tangent := Vector2(-lever.y, lever.x).normalized() * signf(omega)
	body.apply_impulse(tangent * body.mass * absf(omega) * lever.length(), com - body.global_position)

## Tells his face something happened (D74 `ability_event`). Deferred, so that the hit this
## frame has already been dealt and the ability's own row takes the slot after it — the hit's
## row would otherwise overwrite a daze or a launch the instant it began.
func tell(event: StringName, at: Vector2) -> void:
	_tell_now.call_deferred(event, at)
	show_state(event)

func _tell_now(event: StringName, at: Vector2) -> void:
	if is_inside_tree() and body:
		EventBus.ability_event.emit(body.item_id, event, at)

## He sees a wind-up aimed at him: D56's edges and half-second refresh, on the `windup` kind
## the NPCs' tells already use, so the Nervous one flinches at a bat being cocked too.
func threaten(on: bool) -> void:
	if on:
		var him := him_world()
		on = him != Vector2.INF and hand_world().distance_to(him) <= THREAT_REACH
	_threaten(on)

func _threaten(on: bool) -> void:
	var now := Time.get_ticks_msec()
	if on == _threatening and (not on or now < _threat_refresh_msec):
		return
	_threatening = on
	_threat_refresh_msec = now + THREAT_REFRESH_MSEC
	if is_inside_tree() and body:
		EventBus.threat_changed.emit(&"windup", body.global_position, 1.0 if on else 0.0)

func is_threatening() -> bool:
	return _threatening

## The sprite the weapon is drawn with — wired, or found by what it is (the frying pan's scene
## never wired one).
func sprite() -> Sprite2D:
	if body == null:
		return null
	if body.sprite is Sprite2D:
		return body.sprite as Sprite2D
	for child in body.get_children():
		if child is Sprite2D:
			return child
	return null

## A GPU emitter riding on the weapon, built on first use and kept: charge sparks at a bat's
## barrel, exhaust off a chainsaw. `at` is body-local; `local` keeps the chips in its frame.
func emitter(key: String, glyph: StringName, colour: Color, amount: int, at: Vector2,
		velocity: Vector2, spread: float, lifetime: float, gravity: Vector2 = Vector2.ZERO,
		local: bool = false, target: Node2D = null) -> GPUParticles2D:
	var host: Node2D = target if target else body
	var name_ := "Ability%s" % key.to_pascal_case()
	var known := host.get_node_or_null(name_) as GPUParticles2D
	if known:
		return known
	var em := GPUParticles2D.new()
	em.name = name_
	em.one_shot = false
	em.emitting = false
	em.local_coords = local
	em.z_index = 31
	em.amount = maxi(1, amount)
	em.lifetime = lifetime
	em.texture = _chip_texture() if glyph == &"chip" else UIStyle.glyph(glyph)
	em.modulate = colour
	em.position = at
	var mat := ParticleProcessMaterial.new()
	var speed := velocity.length()
	mat.direction = Vector3(velocity.x, velocity.y, 0.0).normalized() if speed > 0.0 else Vector3(0, -1, 0)
	mat.spread = spread
	mat.initial_velocity_min = speed * 0.6
	mat.initial_velocity_max = speed
	mat.gravity = Vector3(gravity.x, gravity.y, 0.0)
	mat.scale_min = 1.0
	mat.scale_max = 2.0
	if glyph != &"chip":
		mat.angular_velocity_min = -360.0
		mat.angular_velocity_max = 360.0
	var curve := CurveTexture.new()
	var shape := Curve.new()
	shape.add_point(Vector2(0.0, 1.0))
	shape.add_point(Vector2(0.7, 0.9))
	shape.add_point(Vector2(1.0, 0.0))
	curve.curve = shape
	mat.scale_curve = curve
	em.process_material = mat
	host.add_child(em)
	return em

## Starts or stops an emitter, gated on Focus Mode like every moving thing (D21).
func emit_from(em: GPUParticles2D, on: bool) -> void:
	if em == null or not is_instance_valid(em):
		return
	var moving := Settings.focus_intensity != Settings.Intensity.OFF
	if on and moving and not em.emitting:
		em.emitting = true
		em.restart()
	elif not (on and moving):
		em.emitting = false

func _chip_texture() -> Texture2D:
	if _chip == null:
		var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_chip = ImageTexture.create_from_image(image)
	return _chip

## Any of the weapon's own shapes inside him right now — the question to ask before a collision
## exception with him comes off, because a body let go of while inside him is thrown out of him by
## the solver (D61: a teleport must clear the colliders; so must a pass-through).
func overlaps_him() -> bool:
	var him := buddy()
	if him == null or not body.is_inside_tree():
		return false
	var space := body.get_world_2d().direct_space_state
	for child in body.get_children():
		var cs := child as CollisionShape2D
		if cs == null or cs.shape == null or cs.disabled:
			continue
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = cs.shape
		query.transform = cs.global_transform
		query.collision_mask = BUDDY_LAYER
		query.collide_with_areas = false
		for result in space.intersect_shape(query, 4):
			if result.get("collider") == him:
				return true
	return false

## Whether a world point is inside him, by his real collider grown a little.
func touches_him(point: Vector2, margin: float = 0.0) -> bool:
	var him := buddy()
	return him != null and him.get_interaction_rect().grow(margin).has_point(point)

## Bills him for an impulse the ability handed him, the gunshot's way (D7): the shove is
## applied here and the same number is what he measures. `mult` is the multiplier on top of the
## weapon's own.
func strike(impulse: float, direction: Vector2, at: Vector2, mult: float = 1.0,
		shove: float = 1.0) -> void:
	var him := buddy()
	if him == null or impulse <= 0.0:
		return
	him.apply_central_impulse(direction.normalized() * impulse * shove)
	him.take_impulse(impulse, body.item_id, base_mult() * mult, at)
	_strike_at = at
	_strike_frame = Engine.get_physics_frames()
	struck.append(impulse)
	if struck.size() > 32:
		struck.pop_front()
	billed.append(mult)
	if billed.size() > 16:
		billed.pop_front()
	payoffs += 1

## The weapon's own multiplier with its damage augment, without anything this adds. Read off the
## body by name, because since D78 it may be a charge (which has one) or a ball (which does not,
## and is x1 before its augment).
func base_mult() -> float:
	var own = body.get(&"damage_mult")
	return Progression.damage_mult_for(body.item_id, float(own) if own != null else 1.0)

# --- how it reads (D77) ---------------------------------------------------------------------
#
# Four stages, the same for every ability, drawn by `AbilityFX` from the ability's row in
# `AbilityLooks` (or its defaults): the READY glint on the held weapon, the ACTIVATION flare and
# its name called out, a STATE badge on him for as long as each thing it `tell`s him lasts, and
# the PAYOFF where each `paid_off` lands. An archetype or a hook calls nothing here to get them.
# One with a moment the four do not cover calls `callout`, `show_state` or `fx_land` itself, and
# D78's abilities speak it through `AbilityCues` (their three moments, pointed here).

## For the suites and the capture tool; nothing in the simulation reads them. The words it asked
## to be called out (drawn or not — the suites' desks have no FX layer), the states it put on him,
## the payoffs it drew, and the times its glint came back in the hand.
var fx_said: Array[String] = []
var fx_states: Array[StringName] = []
var fx_landed := 0
var fx_readied := 0
## Where the next payoff is, if not where the ability last struck him: set by a hook just before its
## `paid_off` (a slam's wave on the desk, not him).
var fx_at := Vector2.INF
## The word for the next payoff, if the ability says it itself (`AbilityCues.payoff`, D78).
var fx_word := ""
## Every payoff drawn, by event: an array, so a suite that holds it can still read it after a charge
## has gone with its blast and taken the ability with it.
var fx_paid: Array[StringName] = []

var _look: Dictionary = {}
var _ready_glint: AbilityFX.ReadyGlint
var _strike_at := Vector2.INF
var _strike_frame := -100
var _paid_this_use := {}
var _paid_msec := {}
var _in_press := false
var _cue_at := Vector2.INF
var _cue_state := false

## How it reads, from `AbilityLooks`: every field filled.
func look() -> Dictionary:
	if _look.is_empty():
		_look = AbilityLooks.look_for(ability_id(), ability_name())
	return _look

## Its accent colour: the flare, the rings, the badge and the words.
func accent() -> Color:
	return look()["colour"]

func ready_glint() -> AbilityFX.ReadyGlint:
	return _ready_glint

## Where its glint sits, in the body's frame: along the weapon from the hand to the far end.
func glint_local() -> Vector2:
	var at: Vector2 = look()["glint_at"]
	if at != Vector2.INF:
		return at
	return body.grip_offset.lerp(body._find_tip(), clampf(float(look()["glint"]), 0.0, 1.0))

func glint_world() -> Vector2:
	return body.to_global(glint_local()) if body else Vector2.ZERO

## Over his skull, where a payoff's word and a badge go. The weapon's glint with nobody there.
func head_world() -> Vector2:
	var him := buddy()
	if him == null:
		return glint_world()
	var rect := him.get_interaction_rect()
	return Vector2(rect.get_center().x, rect.position.y)

## READY: the glint is on while it is held and can be used, and pops when it has just become so.
func _fx_glint(pop: bool) -> void:
	if body == null or not is_inside_tree():
		return
	var on := body.dragging and is_ready()
	if _ready_glint == null or not is_instance_valid(_ready_glint):
		if not on:
			return
		_ready_glint = AbilityFX.glint(sprite(), glint_local(), tier_colour(), AbilityFX.of(body))
		if _ready_glint == null:
			return
	elif on:
		_ready_glint.tint(tier_colour(), AbilityFX.of(body))
	_ready_glint.show_ready(on, pop)

## ACTIVATION: the glint flares off the weapon, its burst, and its name.
func _fx_activated() -> void:
	AbilityFX.note_use(ability_id())
	_paid_this_use.clear()
	_fx_glint(false)
	if body == null or not body.is_inside_tree():
		return
	# Where the ability said it started (`AbilityCues.activation` inside the press: a cake's wicks),
	# or the glint.
	var at := _cue_at if _cue_at.is_finite() else glint_world()
	_cue_at = Vector2.INF
	var afx := AbilityFX.of(body)
	if afx:
		afx.activate(at, accent(), StringName(look()["burst"]))
	callout(String(look()["call"]), at + Vector2(0.0, -34.0), false)

## `AbilityCues.activation` (D78): inside the press, only where the flare goes; anywhere else, the
## flare and the name there.
func fx_cue_activation(at: Vector2) -> void:
	if _in_press:
		_cue_at = at
		return
	if body == null or not body.is_inside_tree() or not at.is_finite():
		return
	var afx := AbilityFX.of(body)
	if afx:
		afx.activate(at, accent(), StringName(look()["burst"]))
	callout(String(look()["call"]), at + Vector2(0.0, -34.0), false)

## `AbilityCues.state` (D78): the ability's badge for its own id, up while it says so. Over him, or
## over the thing itself if the look says `over: weapon` (a charge on the clicker).
func fx_cue_state(on: bool) -> void:
	_cue_state = on
	if not on or body == null or not body.is_inside_tree():
		return
	var spec := AbilityLooks.cue_spec(look(), row)
	if spec.is_empty():
		return
	var over_it := String(spec.get("over", "")) == "weapon"
	var target: Node2D = body if over_it else buddy()
	if target == null:
		return
	var kind := StringName("%s_on" % ability_id())
	if not fx_states.has(kind):
		fx_states.append(kind)
	AbilityFX.state(target, kind, spec, self, AbilityFX.of(body))

## Whether the state `AbilityCues` last put up is still on: what a cue state's badge lasts for.
func cue_state_on() -> bool:
	return _cue_state and _active

## The moment it is let go, for an ability that has one (a drive's "FORE!"): its word and a flare.
func fx_go() -> void:
	var words := String(look()["go"])
	if words.is_empty() or body == null or not body.is_inside_tree():
		return
	var at := glint_world()
	var afx := AbilityFX.of(body)
	if afx:
		afx.activate(at, accent(), StringName(look()["burst"]), 3)
	callout(words, at + Vector2(0.0, -34.0), false, AbilityFX.weight_for(ability_id(), true))

## Calls out `text` at `at` in its colour, through FXLayer. `weight` <0 picks it by how new the
## ability still is (`AbilityFX.weight_for`).
func callout(text: String, at: Vector2, landing: bool, weight: float = -1.0) -> void:
	if text.is_empty() or body == null:
		return
	fx_said.append(text)
	if fx_said.size() > 16:
		fx_said.pop_front()
	var w := weight if weight >= 0.0 else AbilityFX.weight_for(ability_id(), landing)
	AbilityFX.callout(body, text, at, accent(), StringName("ability:%s" % ability_id()), w)

## STATE: the badge for `event` over his head, or a bump of the one there. Every `tell` shows one;
## an ability with a state it does not tell him about calls this itself.
func show_state(event: StringName) -> void:
	var him := buddy()
	if him == null or body == null:
		return
	var spec := AbilityLooks.state_spec(look(), event, row)
	if spec.is_empty():
		return
	if not fx_states.has(event):
		fx_states.append(event)
	AbilityFX.state(him, event, spec, self, AbilityFX.of(body))

## A badge over the weapon itself rather than him: something the player has to do with it (a
## letter opener waiting to be fetched). Its owner takes it off (`AbilityFX.clear_states(body, self)`).
func show_weapon_state(event: StringName) -> AbilityFX.StateMark:
	if body == null or not body.is_inside_tree():
		return null
	var spec := AbilityLooks.state_spec(look(), event, row)
	if spec.is_empty():
		return null
	if not fx_states.has(event):
		fx_states.append(event)
	return AbilityFX.state(body, event, spec, self, AbilityFX.of(body))

## PAYOFF: every `paid_off` is drawn where it landed, sized by the look. A repeated event (a grind,
## a burn, a staple) is drawn no more than five times a second, half size after its first.
func _on_paid_off_fx(event: StringName) -> void:
	fx_land(event)

## Draws a payoff for `event` at `at` (by default where the ability last struck him, or his middle),
## and calls out its word. For a moment that is not a `paid_off` (the monitor's reboot).
func fx_land(event: StringName, at: Vector2 = Vector2.INF) -> void:
	if body == null or not body.is_inside_tree():
		return
	var spec := AbilityLooks.pay_spec(look(), event)
	var where := at if at != Vector2.INF else fx_at
	fx_at = Vector2.INF
	if where == Vector2.INF:
		if Engine.get_physics_frames() - _strike_frame <= 2 and _strike_at != Vector2.INF:
			where = _strike_at
		else:
			var him := buddy()
			where = him.get_interaction_rect().get_center() if him else glint_world()
	var first := not _paid_this_use.has(event)
	_paid_this_use[event] = int(_paid_this_use.get(event, 0)) + 1
	var size := float(spec.get("size", 0.35))
	var now := Time.get_ticks_msec()
	if not first:
		size *= 0.5
		if now - int(_paid_msec.get(event, -1000)) < 200:
			size = 0.0
	fx_landed += 1
	fx_paid.append(event)
	if fx_paid.size() > 32:
		fx_paid.pop_front()
	if size > 0.0:
		_paid_msec[event] = now
		var afx := AbilityFX.of(body)
		if afx and spec.has("shape"):
			afx.payoff_shaped(StringName(spec["shape"]), where, size, accent(), self)
		elif afx:
			afx.payoff(where, size, accent())
	# The word: the look's own for this event if it names one, else what the ability said with it
	# (`AbilityCues.payoff`), else the look's landing word.
	var said := fx_word
	fx_word = ""
	var words := AbilityLooks.pay_words(look(), spec, first, said)
	if not words.is_empty():
		callout(words, head_world() + Vector2(0.0, -58.0), true)

# --- the kind side (D78) ----------------------------------------------------------------------
#
# A ball, a sponge, a duster, a towel, a box of donuts: their abilities are acts of kindness, and
# they pay the way their item already pays — a value on the bus, which Economy alone turns into
# Hearts with the combo, his mood, the augments and prestige (docs/economy.md, one pipeline). Never
# Hearts directly, and never a hit: a kind ability that billed him would be the one hole in D2.

## Kindness value an ability paid, before the item's value multiplier — "pets" — and the part of it
## the item would not have paid without the ability, which is what the row's `worth` states and
## `pacing_sim` prices. For the suites; nothing in the simulation reads them.
var given := 0.0
var given_extra := 0.0

## What `AbilityCues` last heard from this ability, for the suites (D78's three readability hooks).
var cue_count := 0
var last_cue: StringName = &""
var last_cue_at := Vector2.INF
var last_word := ""

func is_kind() -> bool:
	return bool(row.get("kind", false))

## The item's kindness-value multiplier: `FriendlyBase.value_multiplier`, which on this side of the
## economy is what `damage_mult` means.
func kind_value() -> float:
	if body == null or body.item_id == &"":
		return 1.0
	return Progression.get_modifier(body.item_id, &"damage_mult")

## One act of kindness: the combo, the contract board and the per-act Dollars see it, as they see a
## pet. `own` is the part of `value` the item would have paid anyway and the ability only delivered —
## a donut from the box is still the box's helping — and is not the ability's `worth`.
func give(value: float, at: Vector2, own: float = 0.0) -> void:
	if value <= 0.0 or body == null:
		return
	paying = true
	EventBus.kindness_given.emit(body.item_id, value * kind_value(), at)
	paying = false
	given += value
	given_extra += maxf(value - own, 0.0)
	payoffs += 1

## Kindness paid as a rate, banked by the caller: no combo, no contract count, the way a soak pays.
func give_sustained(value: float, at: Vector2, own: float = 0.0) -> void:
	if value <= 0.0 or body == null:
		return
	paying = true
	EventBus.kindness_sustained.emit(body.item_id, value * kind_value(), at)
	paying = false
	given += value
	given_extra += maxf(value - own, 0.0)

## True while an ability's own kindness is on the bus — `ItemVerbs.paying`'s twin (D67): his face
## for it is the ability's row, told a frame later, so the brain skips the generic one. Everything
## else the item pays is judged as it always was, controls line or not.
static var paying := false

## Moving him or holding him without a hit or a pet is the player at the desk, the way a spell is
## (D72): whatever routine he was in ends and his own steering lets go of him.
func notice_player() -> void:
	if not is_inside_tree():
		return
	var idle := get_tree().get_first_node_in_group(IdleBrain.GROUP_IDLE_BRAIN) as IdleBrain
	if idle:
		idle.notice_player()
