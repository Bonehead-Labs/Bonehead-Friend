class_name SpellPower
extends CursorPowerBase

## What the seven supernatural powers share (docs/decisions.md D72): telekinesis, time stop, the
## meteor shower and smite on the harm side; the blessing, levitation and the rainbow on the kind.
##
## Every one of them is a verb the Cursor tab did not have — a grip from anywhere, a pause, a
## barrage, a telegraphed strike, a spell left on him, a lift, a ride — and every one of them is
## held to the same four rules as the powers before them:
##
## * **D47.** The base class decides the click: over a toy it declines and you pick the toy up,
##   Shift gives you your plain hands, Esc holsters. Nothing here takes a left press any other
##   way, and the one right-click a spell takes (telekinesis's crush) it takes only while it is
##   holding him, when a right-click could not have meant anything else.
## * **D7.** He measures his own damage. A spell that hurts him hands him an impulse through
##   `Buddy.take_impulse`, the way lightning and the missile do, or moves him and claims the
##   impacts that follow (`Buddy.claim_impacts`, D65). Kindness goes through `kindness_given` for
##   an act and `kindness_sustained` for a rate. Nothing here mints a number.
## * **The budget.** No per-frame work while it is put away or idle. A spell processes only while
##   an effect is live — a grip, a bubble, a meteor in the air — and switches itself off the frame
##   that effect ends. `_input` is off too, except while the spell is equipped or live.
## * **His face is a row.** A spell says what happened through `EventBus.fidget_event` and the
##   expression brain maps it to a row (`ExpressionBrain.FIDGET_ROWS`), exactly as a toy does. No
##   spell calls the brain, and none plays an animation on him itself.
##
## Everything drawn is either the world's shared vocabulary (`WorldFX`) or a node the spell owns
## and parks — a tether, a bubble, a pillar, a halo, a rainbow — built on first use and kept for
## the life of the power, so casting a thousand times allocates nothing after the first.

## The palette the spells share, from the locked palette's roles (docs/art-direction.md): a
## ghost's green for the hand that is not there, ice for time stood still, gold for the holy,
## and the palest sky for air.
const SPECTRAL := Color("9febc4")
const SPECTRAL_CORE := Color("effff6")
const AIR := Color("e6f6ff")
const ICE := Color("9fe8ff")
const ICE_TINT := Color(0.70, 0.86, 1.0)
const HOLY := Color("fff1b8")

## Where the cursor is, in world space, from motion events — never polled, so a pushed event
## can drive every spell (CLAUDE.md: `get_mouse_position()` reads the OS cursor).
var _aim := Vector2.ZERO
## The left button is down on a press this spell claimed. Released wherever the release lands,
## including over a panel, which is why it is watched in `_input` and not `_unhandled_input`.
var _held := false

func _ready() -> void:
	super._ready()
	set_process(false)
	set_physics_process(false)
	_update_input()

func _on_activated() -> void:
	_update_input()
	_spell_activated()

func _on_deactivated() -> void:
	var was_held := _held
	_held = false
	_spell_deactivated(was_held)
	_update_input()

## **Losing the focus is letting go** (D70). Alt-tab with the button down and its release goes to
## the other window, so a held spell went on holding at a desk nobody was at: the meteor shower
## kept calling rocks and paying Bones, telekinesis kept its grip and levitation kept him up,
## all until the next click. The release lands where the cursor was last seen.
func release_hold() -> void:
	if not _held:
		return
	_held = false
	_hold_lost()
	_update_input()

## The focus went with the button still down. A release where the cursor was last seen, unless
## a spell's release is a cast — that one cancels, as a cancelled gesture never fires a toy.
func _hold_lost() -> void:
	_released(_aim)

## Whether an effect is still running — a meteor in the air, a ride down a rainbow. A live spell
## keeps its input and its processing until it ends, and not a frame after.
func is_live() -> bool:
	return false

## Input only while it can matter. Every other power listens to every event for the whole
## session once it has been equipped; seven more of those is seven more calls per mouse move.
func _update_input() -> void:
	set_process_input(active or is_live())

func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion:
		_aim = _to_world(motion.position)
		_moved(_aim)
		return
	var button := event as InputEventMouseButton
	if button == null:
		return
	if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed and _held:
		_held = false
		_released(_to_world(button.position))
	elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed and active \
			and not button.shift_pressed:
		if _right_pressed(_to_world(button.position)):
			get_viewport().set_input_as_handled()

## The base class hands `fire()` the world position; this keeps `_aim` in step with it.
func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and active and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		_aim = _to_world(button.position)
	super._unhandled_input(event)

func _to_world(screen: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen

# --- subclass hooks --------------------------------------------------------

func _spell_activated() -> void:
	pass

## `was_held` is whether the button was down on a press this spell had claimed.
func _spell_deactivated(_was_held: bool) -> void:
	pass

func _moved(_at: Vector2) -> void:
	pass

func _released(_at: Vector2) -> void:
	pass

## Return true to take the right-click. Only ever while the spell is doing something to him.
func _right_pressed(_at: Vector2) -> bool:
	return false

# --- shared ----------------------------------------------------------------

## By group, never by path (D9).
func _buddy() -> Buddy:
	if not is_inside_tree():
		return null
	var buddy := get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy
	return buddy if is_instance_valid(buddy) else null

## Whether he is somewhere a spell can reach him: there, not in the knockout, not held.
func _reachable(buddy: Buddy) -> bool:
	return buddy != null and not buddy.dragging and buddy.health != null \
		and not buddy.health.down and not ExpressionBrain.KNOCKOUT_STATES.has(buddy.state)

func _on_him(at: Vector2, padding: float) -> bool:
	var buddy := _buddy()
	return buddy != null and buddy.get_interaction_rect().grow(padding).has_point(at)

func _fx() -> WorldFX:
	return WorldFX.of(self)

func _tier() -> int:
	return Progression.juice_tier(item_id)

func _effects_on() -> bool:
	return Settings.focus_intensity != Settings.Intensity.OFF

## His face, through the brain's table (see the class note).
func _face(event: StringName, at: Vector2 = Vector2.INF) -> void:
	var buddy := _buddy()
	if buddy == null:
		return
	EventBus.fidget_event.emit(item_id, event, buddy.global_position if at == Vector2.INF else at)

## A spell holding him up is the player at the desk, the way a hand on him is: whatever
## routine he was in ends, and his own steering lets go of him.
func _notice_player() -> void:
	var idle := get_tree().get_first_node_in_group(IdleBrain.GROUP_IDLE_BRAIN) as IdleBrain
	if idle:
		idle.notice_player()

func _use() -> void:
	EventBus.contract_event.emit(&"use:%s" % item_id, 1)

func _gravity(body: RigidBody2D) -> Vector2:
	var g := float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	var v: Vector2 = ProjectSettings.get_setting("physics/2d/default_gravity_vector", Vector2.DOWN)
	return v * g * body.gravity_scale

## Steers him toward a velocity, the change per step bounded by `accel`, with this step's
## gravity paid for when `hold_up` is set.
##
## An impulse, not a write: a velocity assignment erases whatever else was applied to him this
## frame (D54). And it lands before `Buddy.StepStart` reads the step's starting velocity, so the
## ledger sees the steer as where the step began and never bills it as a contact (D64). The
## bound matters twice: it is what makes a spell's grip feel soft, and it keeps the push of
## holding him against a wall under the damage floor, so pinning him there earns nothing.
func _steer(buddy: Buddy, want: Vector2, accel: float, delta: float, hold_up: bool = true) -> void:
	var dv := (want - buddy.linear_velocity).limit_length(accel * delta)
	if hold_up:
		dv -= _gravity(buddy) * delta
	buddy.apply_central_impulse(dv * buddy.mass)

## Rights him, gently. Rotation is free while nothing drives him, and a skeleton carried upside
## down by his ankle reads as a physics bug rather than a spell.
func _upright(buddy: Buddy, stiffness: float = 6.0) -> void:
	var lean := wrapf(buddy.rotation, -PI, PI)
	buddy.angular_velocity = lerpf(buddy.angular_velocity, -lean * stiffness, 0.25)

## A continuous emitter the spell owns, with its own recipe. For the effects whose shape the
## world's pool has no word for: hearts that rain rather than rise, an updraft, sleep.
func _emitter(node_name: String, texture: Texture2D, colour: Color, amount: int,
		lifetime: float, gravity_y: float, speed: float, box: Vector2, scale_min: float,
		scale_max: float, spins: bool = false) -> GPUParticles2D:
	var emitter := GPUParticles2D.new()
	emitter.name = node_name
	emitter.one_shot = false
	emitter.emitting = false
	emitter.local_coords = false
	emitter.z_index = 32
	emitter.texture = texture
	emitter.modulate = colour
	emitter.amount = maxi(1, amount)
	emitter.lifetime = lifetime
	# Every frame, not the default 30 a second: an emitter that moves (a meteor, him) otherwise
	# drops its particles in clumps a frame apart, a dotted line where a trail should be.
	emitter.fixed_fps = 0
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 30.0
	mat.initial_velocity_min = speed * 0.5
	mat.initial_velocity_max = speed
	mat.gravity = Vector3(0, gravity_y, 0)
	mat.scale_min = scale_min
	mat.scale_max = scale_max
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(box.x, box.y, 1.0)
	if spins:
		mat.angular_velocity_min = -180.0
		mat.angular_velocity_max = 180.0
	# Shrinks to nothing rather than fading, like every chip in `WorldFX`.
	var curve := CurveTexture.new()
	var shape := Curve.new()
	shape.add_point(Vector2(0.0, 1.0))
	shape.add_point(Vector2(0.75, 0.9))
	shape.add_point(Vector2(1.0, 0.0))
	curve.curve = shape
	mat.scale_curve = curve
	emitter.process_material = mat
	add_child(emitter)
	return emitter

var _chip_texture: Texture2D

## The 4px square every chip in the world is, plotted rather than imported, as `WorldFX` does.
## Per instance, not static: a static holding a Resource outlives the engine and reads as a leak.
func _chip() -> Texture2D:
	if _chip_texture == null:
		var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_chip_texture = ImageTexture.create_from_image(image)
	return _chip_texture

func _emitting(emitter: GPUParticles2D, on: bool) -> void:
	if emitter and is_instance_valid(emitter):
		emitter.emitting = on and _effects_on()

## A small ring and a tick: the spell heard the click and is not ready yet. A refused click
## that shows nothing reads as a click that was lost.
func _fizzle(at: Vector2, colour: Color) -> void:
	var fx := _fx()
	if fx:
		fx.ring(at, 18.0, colour, 0.18, 1.0)
	AudioManager.play(&"wheel_tick", 0.05, -14.0, 0.7)
