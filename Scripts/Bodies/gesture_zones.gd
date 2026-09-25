class_name GestureZones
extends Node

## Click zones and gestures for a toy you work with your hands (docs/decisions.md D57).
##
## A child of any `BaseDraggable` — kind or harm, `FriendlyBase` or `WeaponBase` — so the
## fidget layer is a component the toy owns rather than a base class both halves of the roster
## would need. The body hands it every input event before its own grab and bin logic runs
## (`BaseDraggable.gesture_zones`), and it may claim a press: a bubble pops instead of the
## sheet lifting, a crank turns instead of the box being binned.
##
## ## The grammar — one for every held thing in the game
##
## - **Left = hold / carry.** Unchanged: `BaseDraggable` pins a joint to a handle that chases
##   the mouse. Anywhere on the toy that no zone claims still grabs.
## - **Right while holding = the item's action** (squeeze, fire, prime): `ACTION` and
##   `ACTION_END`, when the toy has one (`action_enabled`). A zone under the cursor that claims
##   the right button still comes first — a spinner can be flicked in the hand — and a toy with
##   neither lets the press fall through exactly as before.
## - **Right on a zone of an item you are not holding = that zone's action** (crank, flick,
##   pop, read).
## - **Left on a zone that claims it = that zone's action instead of a grab.** A zone may
##   claim only the *tap*: a left press on it that turns into a drag is still a grab.
## - **Shift+Right is the bin, and nothing claims it** (`BaseDraggable.click_would_bin`).
## - **Hovering a zone shows the pointing hand**; the rest of the toy shows the grab cursor.
##   A zone nobody can see is a zone nobody uses. Hover is driven from the motion events the
##   body forwards, never from `get_mouse_position()`, so a test can drive it.
##
## ## Using it from a new toy
##
## 1. **Author the zones in the seed table, in art pixels**, with the origin at the sprite's
##    centre and y down — the same space as the scale table and D25's physics table:
##
##        {"id": &"crank", "circle": 4.5, "at": Vector2(12, 1), "right": "claim"}
##        {"id": &"lid", "rect": Vector2(24, 8), "at": Vector2(0, -12), "right": "tap"}
##
##    `left` / `right` are `""` (not claimed — the default), `"claim"` (press, drag, crank and
##    flick belong to the zone) or `"tap"` (only a tap does; a drag falls through to a grab on
##    the left button and to nothing on the right). `pivot` (art px) is what a crank turns
##    about, the zone's centre if omitted. The first enabled zone containing the point that
##    claims the button wins, so list small zones before the large ones they sit on.
##    `"backing": true` marks a zone that is the toy rather than a button on it — a gesture
##    may start there (a right-drag across the bubble sheet begins on the film), but hovering
##    it shows the grab cursor, not the pointing hand.
##    The seed tool also sets `action_enabled` for a toy with a verb of its own in the hand.
## 2. **In the toy's script**: `@export var gestures: GestureZones` (the seed tool wires it),
##    then `gestures.gesture.connect(_on_gesture)` in `_ready`, and `match g.kind:`. A kind toy
##    extends `FidgetToy`, which does that wiring and adds the two ways to pay.
## 3. **At runtime**: `set_zone_enabled(id, on)` — a popped bubble stops claiming, so the sheet
##    under it grabs — and `mirrored = true` when the toy flips its art to face the other way.
##    `zone_world(id)` is where a zone is right now, for effects and for tests.
## 4. **He uses it too** if the toy has `idle_appeal() -> float` and `idle_use(buddy)`:
##    `IdleBrain` files it as `ROUTINE_FIDGET`, walks him over, and calls `idle_use` on its
##    think tick. The toy pays for what he does itself, as a sustained trickle, never an act.
## 5. **His face** answers `EventBus.fidget_event(item_id, event, at)`: add the event to
##    `ExpressionBrain.FIDGET_ROWS` and the row to its `ROWS`.
##
## ## What arrives (`Gesture.kind`)
##
##   PRESS       a claimed press landed on `zone`
##   TAP         released quickly and without moving
##   HOLD        still pressed after `hold_seconds` without moving; fires once
##   DRAG        moved while pressed: `delta` (art px), `world`, `velocity` (world px/s)
##   CROSS       the drag entered another enabled zone: `zone` is the one entered. Sampled
##               along the whole segment, so a fast swipe cannot skip a bubble
##   CRANK       moved while pressed: `angle` (radians this event about the zone's pivot,
##               clockwise as drawn is positive) and `total` (radians since the press)
##   FLICK       released while moving: `velocity` (world px/s)
##   RELEASE     every claimed press ends with exactly one: `seconds` held
##   ACTION      right pressed while the body is held
##   ACTION_END  right released, or the body let go of: `seconds` held
##   CARRY       the body moved while held: `delta` (world px) — a shake, a swing
##
## `at` and `delta` are art pixels in the toy's own frame — unrotated and unmirrored — so the
## zone table and the gesture agree whichever way up the body is lying.
##
## ## Cost
##
## Nothing per frame, ever. Everything here runs on an input event, and only on a zone toy;
## the hold timer runs only while a press is down. A toy at rest with nobody touching it costs
## what any other body costs.

signal gesture(g: Gesture)

const PRESS := &"press"
const TAP := &"tap"
const HOLD := &"hold"
const DRAG := &"drag"
const CROSS := &"cross"
const CRANK := &"crank"
const FLICK := &"flick"
const RELEASE := &"release"
const ACTION := &"action"
const ACTION_END := &"action_end"
const CARRY := &"carry"

## Claim modes, per button. Plain ints for the same reason `ItemData` uses them: an enum as a
## parameter type is a distinct type across script boundaries.
const CLAIM_NONE := 0
const CLAIM_TAP := 1
const CLAIM_ALL := 2

## One art pixel is this many world pixels — the 2x every sprite in the game is drawn at.
const ART_SCALE := 2.0
## A press that travels this far (world px) is a drag, not a tap.
const TAP_SLOP := 6.0
## A press held longer than this is not a tap, even if it never moved.
const TAP_SECONDS := 0.35
## A release moving at least this fast (world px/s), with the last motion this recent, is a
## flick. Slower, or after a pause, is a release.
const FLICK_SPEED := 120.0
const FLICK_FRESH_MSEC := 90
## How finely a drag is sampled for CROSS, in art px. Half a bubble.
const CROSS_STEP := 3.0

## One gesture. A plain object rather than a Dictionary, so a typo in a field name is a parse
## error in the toy rather than a silent null.
class Gesture extends RefCounted:
	var kind: StringName
	var zone: StringName = &""
	var button: int = 0
	var at := Vector2.ZERO
	var world := Vector2.ZERO
	var delta := Vector2.ZERO
	var velocity := Vector2.ZERO
	var angle := 0.0
	var total := 0.0
	var seconds := 0.0

## One zone, parsed from its table row. Rect or circle, in art px, centred on `centre`.
class Zone extends RefCounted:
	var id: StringName
	var centre := Vector2.ZERO
	var size := Vector2.ZERO
	var radius := 0.0
	var pivot := Vector2.ZERO
	var left := 0
	var right := 0
	var backing := false
	var enabled := true

	func has_point(p: Vector2) -> bool:
		if radius > 0.0:
			return p.distance_squared_to(centre) <= radius * radius
		return absf(p.x - centre.x) <= size.x * 0.5 and absf(p.y - centre.y) <= size.y * 0.5

	func claim(button: int) -> int:
		if button == MOUSE_BUTTON_LEFT:
			return left
		if button == MOUSE_BUTTON_RIGHT:
			return right
		return CLAIM_NONE

## The zone table, as the seed tool wrote it. See the class comment for the row format.
@export var zones: Array = []
## How long a still press takes to become a HOLD.
@export var hold_seconds: float = 0.5
## Whether right-while-holding is this toy's action. A toy with no held verb leaves it off,
## and a right press while holding it falls through as it always did.
@export var action_enabled: bool = false
## The art is drawn facing the other way. Zones, cranks and `at` all follow.
@export var mirrored: bool = false

var body: BaseDraggable

var _zones: Array[Zone] = []
var _by_id: Dictionary = {}
## How far from the body origin anything of this toy reaches, in art px — the hover test's
## early-out.
var _reach := 0.0

## The press in progress, if any: {button, zone, mode, started_usec, start_world, last_world,
## last_art, last_angle, total, moved, held, velocity, last_motion_msec}. Empty when none.
var _press: Dictionary = {}
## When right went down on the held body, in usec; 0 when no action is live.
var _action_since := 0
## Where the body was last seen while carried, for CARRY deltas.
var _carry_from := Vector2.INF
var _was_dragging := false

## What the cursor is over: the zone id (empty for none), and whether it is over the toy at
## all. Read by the cursor, and by tests.
var hover_zone: StringName = &""
var hover_body := false

var _hold_timer: Timer

## Whoever set the OS cursor last. One owner at a time, so two toys side by side cannot fight
## over it, and whoever sets it is the one that puts it back.
static var _cursor_owner: GestureZones = null
## What the OS cursor was last set to from here. Input has no getter for its default shape.
static var _applied_shape: int = Input.CURSOR_ARROW
## The shape this component last asked for — the headless DisplayServer always reports an
## arrow, so the suites read this instead.
var cursor_shape: int = Input.CURSOR_ARROW

func _enter_tree() -> void:
	# Found by what it is, never by name (CLAUDE.md): the body this rides on is its parent.
	body = get_parent() as BaseDraggable
	if body:
		body.gesture_zones = self

func _exit_tree() -> void:
	if body and body.gesture_zones == self:
		body.gesture_zones = null
	_release_cursor()

func _ready() -> void:
	if body and body.collider and body.collider.shape:
		_reach = (body.collider.shape.get_rect().size.length() * 0.5
			+ body.collider.position.length()) / ART_SCALE
	for row in zones:
		add_zone(row)
	_hold_timer = Timer.new()
	_hold_timer.name = "HoldTimer"
	_hold_timer.one_shot = true
	_hold_timer.timeout.connect(_on_hold_timeout)
	add_child(_hold_timer)

## Adds one zone from a table row. Public so a toy can lay out zones it computes — though a
## table in the seed tool is preferred, because it sits beside the art it describes.
func add_zone(row: Dictionary) -> void:
	var zone := Zone.new()
	zone.id = StringName(row.get("id", "zone%d" % _zones.size()))
	zone.centre = row.get("at", Vector2.ZERO)
	if row.has("circle"):
		zone.radius = float(row["circle"])
		zone.size = Vector2.ONE * zone.radius * 2.0
	else:
		zone.size = row.get("rect", Vector2(8, 8))
	zone.pivot = row.get("pivot", zone.centre)
	zone.left = _mode(String(row.get("left", "")))
	zone.right = _mode(String(row.get("right", "")))
	zone.backing = bool(row.get("backing", false))
	_reach = maxf(_reach, zone.centre.length() + zone.size.length() * 0.5)
	_zones.append(zone)
	_by_id[zone.id] = zone

static func _mode(word: String) -> int:
	match word:
		"claim":
			return CLAIM_ALL
		"tap":
			return CLAIM_TAP
	return CLAIM_NONE

func set_zone_enabled(id: StringName, on: bool) -> void:
	var zone: Zone = _by_id.get(id)
	if zone:
		zone.enabled = on

func zone_enabled(id: StringName) -> bool:
	var zone: Zone = _by_id.get(id)
	return zone != null and zone.enabled

func zone_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for zone in _zones:
		out.append(zone.id)
	return out

## Where a zone is in the world right now: its centre, through the body's rotation and the
## mirror. For a test that has to click it, and for a toy that throws a chip off it.
func zone_world(id: StringName) -> Vector2:
	var zone: Zone = _by_id.get(id)
	if zone == null or body == null:
		return Vector2.ZERO
	return art_to_world(zone.centre)

func art_to_world(art: Vector2) -> Vector2:
	var local := art * ART_SCALE
	if mirrored:
		local.x = -local.x
	return body.to_global(local)

func world_to_art(world: Vector2) -> Vector2:
	var local := body.to_local(world) / ART_SCALE
	if mirrored:
		local.x = -local.x
	return local

func is_pressed() -> bool:
	return not _press.is_empty()

func pressed_zone() -> StringName:
	return _press.get("zone", &"")

func action_live() -> bool:
	return _action_since > 0

## Seconds the action has been held, 0 when it is not.
func action_seconds() -> float:
	if _action_since <= 0:
		return 0.0
	return float(Time.get_ticks_usec() - _action_since) / 1_000_000.0

## The first enabled zone under `art` that claims `button` — or, with `button` 0, the first
## enabled zone under it at all.
func zone_at(art: Vector2, button: int = 0) -> Zone:
	for zone in _zones:
		if not zone.enabled or not zone.has_point(art):
			continue
		if button == 0 or zone.claim(button) != CLAIM_NONE:
			return zone
	return null

# --- the one entry point ------------------------------------------------------

## Every event on the body, before its own grab and bin logic. True claims it: the body does
## nothing further with it and marks it handled.
func take(event: InputEvent) -> bool:
	if body == null:
		return false
	var click := event as InputEventMouseButton
	if click:
		if click.button_index != MOUSE_BUTTON_LEFT and click.button_index != MOUSE_BUTTON_RIGHT:
			return false
		return _press_event(click) if click.pressed else _release_event(click)
	var motion := event as InputEventMouseMotion
	if motion:
		_motion_event(motion)
	return false

func _press_event(click: InputEventMouseButton) -> bool:
	var right := click.button_index == MOUSE_BUTTON_RIGHT
	# The bin. Never ours, on any zone, in any state.
	if right and click.shift_pressed:
		return false
	var world := _world_of(click.position)
	if body.dragging:
		# In the hand: a zone that claims the right button first, then the item's own verb,
		# then nothing — and nothing means the body's own right-click, as it always did.
		if not right or not _press.is_empty():
			return false
		if zone_at(world_to_art(world), MOUSE_BUTTON_RIGHT) == null:
			if not action_enabled or _action_since != 0:
				return false
			_action_since = Time.get_ticks_usec()
			_emit(ACTION, &"", MOUSE_BUTTON_RIGHT, world)
			_update_cursor()
			return true
	if not _press.is_empty():
		# A second button while one is down is ignored — and swallowed if it lands on a zone,
		# so a stray right-click mid-crank does not bin the box out from under the hand.
		return zone_at(world_to_art(world)) != null
	var art := world_to_art(world)
	var zone := zone_at(art, click.button_index)
	if zone == null:
		return false
	_press = {
		"button": click.button_index,
		"zone": zone.id,
		"mode": zone.claim(click.button_index),
		"started_usec": Time.get_ticks_usec(),
		"start_world": world,
		"last_world": world,
		"last_art": art,
		"last_angle": _angle_about(zone, world),
		"total": 0.0,
		"moved": false,
		"held": false,
		"velocity": Vector2.ZERO,
		"last_motion_msec": 0,
		"over": zone.id,
	}
	_hold_timer.start(hold_seconds)
	_emit(PRESS, zone.id, click.button_index, world, art)
	_update_cursor()
	return true

func _release_event(click: InputEventMouseButton) -> bool:
	var world := _world_of(click.position)
	if click.button_index == MOUSE_BUTTON_RIGHT and _action_since > 0:
		_end_action(world)
		return true
	# Letting go of the body ends its action too — you cannot squeeze what you have dropped —
	# but the release itself is the body's, which is what ends the drag.
	if click.button_index == MOUSE_BUTTON_LEFT and _action_since > 0:
		_end_action(world)
	if _press.is_empty() or int(_press["button"]) != click.button_index:
		return false
	_finish_press(world, true)
	return true

func _motion_event(motion: InputEventMouseMotion) -> void:
	var world := _world_of(motion.position)
	var art := world_to_art(world)
	_update_hover(art)
	# The body picks itself up and puts itself down; the cursor hears about it here.
	if body.dragging != _was_dragging:
		_was_dragging = body.dragging
		_update_cursor()
	if body.dragging:
		if _carry_from != Vector2.INF:
			var carried := world - _carry_from
			if carried.length_squared() > 0.0:
				var g := _make(CARRY, &"", MOUSE_BUTTON_LEFT, world, art)
				g.delta = carried
				g.velocity = _velocity_of(motion, carried)
				gesture.emit(g)
		_carry_from = world
	else:
		_carry_from = Vector2.INF
	if _press.is_empty():
		return
	var button := int(_press["button"])
	# The button came up somewhere this body never heard about — over a panel, outside the
	# window. End the press cleanly rather than leave a crank turning forever.
	var mask := MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	if motion.button_mask != 0 and (motion.button_mask & mask) == 0:
		_finish_press(world, false)
		return
	var step: Vector2 = world - _press["last_world"]
	if step.length_squared() <= 0.0:
		return
	if not _press["moved"] and world.distance_to(_press["start_world"]) >= TAP_SLOP:
		_press["moved"] = true
		_hold_timer.stop()
		# A tap-only zone lets go of a press that became a drag. On the left button the
		# body gets it back as the grab it always was.
		if int(_press["mode"]) == CLAIM_TAP:
			var was: Dictionary = _press
			_press = {}
			_emit_release(was, world)
			if button == MOUSE_BUTTON_LEFT:
				body._start_drag()
			_update_cursor()
			return
	var zone: Zone = _by_id.get(_press["zone"])
	var now := Time.get_ticks_msec()
	_press["velocity"] = _velocity_of(motion, step)
	_press["last_motion_msec"] = now
	var drag := _make(DRAG, _press["zone"], button, world, art)
	drag.delta = art - (_press["last_art"] as Vector2)
	drag.velocity = _press["velocity"]
	gesture.emit(drag)
	if zone:
		var angle := _angle_about(zone, world)
		var last := float(_press["last_angle"])
		var turn := 0.0
		if angle != INF and last != INF:
			turn = wrapf(angle - last, -PI, PI)
		if angle != INF:
			_press["last_angle"] = angle
		if not is_zero_approx(turn):
			_press["total"] = float(_press["total"]) + turn
			var crank := _make(CRANK, zone.id, button, world, art)
			crank.angle = turn
			crank.total = _press["total"]
			gesture.emit(crank)
	_sample_crossings(_press["last_art"], art, button)
	_press["last_world"] = world
	_press["last_art"] = art

## Every zone the segment passed into, in order — so a swipe that covers two bubbles between
## two motion events pops both, which is the difference between a run and a stutter.
func _sample_crossings(from: Vector2, to: Vector2, button: int) -> void:
	var length := from.distance_to(to)
	var steps := maxi(1, int(ceil(length / CROSS_STEP)))
	for i in range(1, steps + 1):
		var point := from.lerp(to, float(i) / float(steps))
		var zone := zone_at(point)
		var over: StringName = zone.id if zone else &""
		if over != _press.get("over", &""):
			_press["over"] = over
			if over != &"":
				gesture.emit(_make(CROSS, over, button, art_to_world(point), point))

func _finish_press(world: Vector2, released_here: bool) -> void:
	var was: Dictionary = _press
	_press = {}
	_hold_timer.stop()
	var seconds := float(Time.get_ticks_usec() - int(was["started_usec"])) / 1_000_000.0
	var art := world_to_art(world)
	if released_here:
		if not was["moved"] and not was["held"] and seconds <= TAP_SECONDS:
			_emit(TAP, was["zone"], was["button"], world, art)
		elif was["moved"] and Time.get_ticks_msec() - int(was["last_motion_msec"]) <= FLICK_FRESH_MSEC \
				and (was["velocity"] as Vector2).length() >= FLICK_SPEED:
			var flick := _make(FLICK, was["zone"], was["button"], world, art)
			flick.velocity = was["velocity"]
			gesture.emit(flick)
	_emit_release(was, world)
	_update_cursor()

func _emit_release(was: Dictionary, world: Vector2) -> void:
	var release := _make(RELEASE, was["zone"], was["button"], world, world_to_art(world))
	release.seconds = float(Time.get_ticks_usec() - int(was["started_usec"])) / 1_000_000.0
	gesture.emit(release)

func _end_action(world: Vector2) -> void:
	var g := _make(ACTION_END, &"", MOUSE_BUTTON_RIGHT, world, world_to_art(world))
	g.seconds = action_seconds()
	_action_since = 0
	gesture.emit(g)
	_update_cursor()

func _on_hold_timeout() -> void:
	if _press.is_empty() or _press["moved"]:
		return
	_press["held"] = true
	var world: Vector2 = _press["last_world"]
	var g := _make(HOLD, _press["zone"], _press["button"], world, world_to_art(world))
	g.seconds = hold_seconds
	gesture.emit(g)

## Everything a press or an action was doing, dropped — the app lost focus, the cursor left
## the window, the body was knocked out of the player's hand.
func cancel() -> void:
	if not _press.is_empty():
		var was: Dictionary = _press
		_press = {}
		_hold_timer.stop()
		_emit_release(was, was["last_world"])
	if _action_since > 0:
		_end_action(_carry_from if _carry_from != Vector2.INF else body.global_position)
	hover_zone = &""
	hover_body = false
	_carry_from = Vector2.INF
	_update_cursor()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			cancel()
		NOTIFICATION_WM_MOUSE_EXIT:
			if _press.is_empty() and _action_since == 0:
				hover_zone = &""
				hover_body = false
				_update_cursor()

# --- hover and the cursor -------------------------------------------------------

func _update_hover(art: Vector2) -> void:
	var zone_id: StringName = &""
	var over := false
	# Cheapest reject first: this runs for every zone toy on every mouse motion anywhere in the
	# window, and nearly all of them are nowhere near the cursor.
	if art.length() <= _reach + 4.0:
		var zone := _hover_zone_at(art)
		zone_id = zone.id if zone else &""
		over = zone != null or _over_body(art)
	if zone_id == hover_zone and over == hover_body:
		return
	hover_zone = zone_id
	hover_body = over
	_update_cursor()

## A zone only counts as a button if it claims something and is not the toy's backing.
func _hover_zone_at(art: Vector2) -> Zone:
	for zone in _zones:
		if zone.enabled and not zone.backing and zone.has_point(art) \
				and (zone.left != CLAIM_NONE or zone.right != CLAIM_NONE):
			return zone
	return null

## Over the toy's own collision shape, in its own frame — rotation included, which a world
## rect is not.
func _over_body(art: Vector2) -> bool:
	if body.collider == null or body.collider.shape == null:
		return false
	var local := art * ART_SCALE
	if mirrored:
		local.x = -local.x
	var in_shape := body.collider.transform.affine_inverse() * local
	return body.collider.shape.get_rect().has_point(in_shape)

func _update_cursor() -> void:
	var shape := Input.CURSOR_ARROW
	if not _press.is_empty() or _action_since > 0 or hover_zone != &"":
		shape = Input.CURSOR_POINTING_HAND
	elif body and body.dragging:
		shape = Input.CURSOR_DRAG
	elif hover_body:
		shape = Input.CURSOR_MOVE
	cursor_shape = shape
	if shape == Input.CURSOR_ARROW:
		_release_cursor()
		return
	if _cursor_owner != null and _cursor_owner != self and is_instance_valid(_cursor_owner) \
			and _cursor_owner.cursor_shape != Input.CURSOR_ARROW:
		return
	_cursor_owner = self
	_apply_shape(shape)

func _release_cursor() -> void:
	if _cursor_owner != self:
		return
	_cursor_owner = null
	_apply_shape(Input.CURSOR_ARROW)

## Only on a change. `set_default_cursor_shape` pushes a synthetic motion event through Input
## to make the new shape show at once, and that event comes back here as a hover update — a
## call on every motion would be a loop with a frame in it.
static func _apply_shape(shape: int) -> void:
	if _applied_shape == shape:
		return
	_applied_shape = shape
	Input.set_default_cursor_shape(shape)

# --- helpers -------------------------------------------------------------------

## Viewport coordinates to world, through the canvas transform — which carries the screen
## shake, so a click during a jolt still lands on the bubble under the cursor.
func _world_of(viewport_pos: Vector2) -> Vector2:
	return body.get_canvas_transform().affine_inverse() * viewport_pos

## INF with the cursor on the pivot itself, where no angle means anything.
func _angle_about(zone: Zone, world: Vector2) -> float:
	var pivot := art_to_world(zone.pivot)
	var offset := world - pivot
	if offset.length_squared() < 4.0:
		return INF
	# Measured in the toy's own frame, so "clockwise as drawn" survives the body's rotation
	# and a mirror flips it.
	var angle := offset.angle() - body.global_rotation
	return -angle if mirrored else angle

## World px/s. The event's own velocity where the platform supplies one (Windows does, for
## every real mouse), else the step over the time since the last motion.
func _velocity_of(motion: InputEventMouseMotion, step: Vector2) -> Vector2:
	if motion.velocity.length_squared() > 0.0:
		return body.get_canvas_transform().affine_inverse().basis_xform(motion.velocity)
	var now := Time.get_ticks_msec()
	var last := int(_press.get("last_motion_msec", 0)) if not _press.is_empty() else 0
	if last > 0 and now > last:
		return step / (float(now - last) / 1000.0)
	return Vector2.ZERO

func _make(kind: StringName, zone: StringName, button: int, world: Vector2,
		art: Vector2 = Vector2.INF) -> Gesture:
	var g := Gesture.new()
	g.kind = kind
	g.zone = zone
	g.button = button
	g.world = world
	g.at = art if art != Vector2.INF else world_to_art(world)
	if not _press.is_empty():
		g.total = float(_press.get("total", 0.0))
	return g

func _emit(kind: StringName, zone: StringName, button: int, world: Vector2,
		art: Vector2 = Vector2.INF) -> void:
	gesture.emit(_make(kind, zone, button, world, art))
