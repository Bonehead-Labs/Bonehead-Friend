class_name BubbleWrap
extends FidgetToy

## A sheet of bubble wrap: eight bubbles, each its own zone (D57).
##
## - **Left-tap a bubble** and it pops. Left-press-and-drag anywhere still lifts the sheet —
##   the bubbles claim only the tap — and a popped bubble claims nothing at all.
## - **Right-drag across the sheet** pops a run: every intact bubble the cursor passes over,
##   sampled along the whole stroke so a fast swipe cannot skip one. The film itself claims
##   the right button, so a stroke that starts between two bubbles is still a stroke and never
##   bins the sheet (Shift+right does, as it does everything).
## - **He pops them by coming down on it**: a landing on top of the sheet pops the bubble under
##   his feet. Left alone, he walks over, climbs on and hops.
##
## Each pop is a small kindness, a pop and a puff. Bubbles grow back one at a time, slowly —
## the sheet is a burst of fun and then a trickle, which is right for the cheapest toy on the
## shelf.

## Kindness value of one pop, before the item's own value node.
@export var pop_value: float = 2.0
## Seconds for one popped bubble to grow back, before the "time between uses" node.
@export var regrow_seconds: float = 4.0
## Holds one bubble sprite per slot, in slot order. Wired by the seed tool.
@export var bubble_layer: Node2D

## A hop onto the sheet: how high above its top edge he aims to clear. Enough that the
## brain's lean has the time in the air to carry him over the edge.
const HOP_CLEARANCE := 26.0
## How close to the sheet's top face his feet must be for a landing to count as on it.
const ON_TOP_SLACK := 6.0

var _popped: Array[bool] = []
var _regrow: Timer

func _ready() -> void:
	super._ready()
	_popped.resize(bubble_count())
	_popped.fill(false)
	_regrow = Timer.new()
	_regrow.name = "RegrowTimer"
	_regrow.one_shot = true
	_regrow.timeout.connect(_on_regrow)
	add_child(_regrow)
	body_entered.connect(_on_body_entered)
	EventBus.buddy_landed.connect(_on_buddy_landed)

func bubble_count() -> int:
	return bubble_layer.get_child_count() if bubble_layer else 0

func intact_count() -> int:
	return _popped.count(false)

func is_popped(slot: int) -> bool:
	return slot >= 0 and slot < _popped.size() and _popped[slot]

static func zone_of(slot: int) -> StringName:
	return StringName("b%d" % slot)

static func slot_of(zone: StringName) -> int:
	var name_ := String(zone)
	if not name_.begins_with("b") or not name_.substr(1).is_valid_int():
		return -1
	return int(name_.substr(1))

func _on_gesture(g: GestureZones.Gesture) -> void:
	var slot := slot_of(g.zone)
	if slot < 0:
		return
	match g.kind:
		GestureZones.TAP:
			if g.button == MOUSE_BUTTON_LEFT:
				pop(slot, true)
		GestureZones.PRESS, GestureZones.CROSS:
			if g.button == MOUSE_BUTTON_RIGHT:
				pop(slot, true)

## Pops one bubble. `by_player` decides how it pays: an act, or a trickle he earned himself.
func pop(slot: int, by_player: bool) -> bool:
	if slot < 0 or slot >= _popped.size() or _popped[slot]:
		return false
	_popped[slot] = true
	var bubble := bubble_layer.get_child(slot) as CanvasItem
	bubble.visible = false
	if gestures:
		gestures.set_zone_enabled(zone_of(slot), false)
	var at := gestures.zone_world(zone_of(slot)) if gestures else global_position
	AudioManager.play(&"pop", 0.2, -7.0)
	var fx := WorldFX.of(self)
	if fx:
		fx.puff(at, 5, Color.WHITE, 70.0, 0.3)
	if by_player:
		pay_act(pop_value, at)
	else:
		pay_sustained(pop_value, at)
	if _regrow.is_stopped():
		_regrow.start(_regrow_gap())
	return true

func _regrow_gap() -> float:
	return maxf(0.5, regrow_seconds * upgrade(&"cooldown_mult"))

## One bubble back, oldest slot first, and the timer re-armed only while any are still flat:
## a full sheet costs nothing.
func _on_regrow() -> void:
	var slot := _popped.find(true)
	if slot < 0:
		return
	_popped[slot] = false
	var bubble := bubble_layer.get_child(slot) as Node2D
	bubble.visible = true
	if gestures:
		gestures.set_zone_enabled(zone_of(slot), true)
	if animating():
		bubble.scale = Vector2(0.3, 0.3)
		create_tween().tween_property(bubble, "scale", Vector2.ONE, 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _popped.has(true):
		_regrow.start(_regrow_gap())

# --- him ------------------------------------------------------------------------

## He came down on it, two ways, because either alone misses one. `buddy_landed` is a fall
## that stopped, which is every landing — including a hop from beside the sheet, where he
## never lost touch with its edge and so no new contact begins. `body_entered` is a new
## contact, which is being set down on it gently, too slowly to count as a landing. Both are
## deferred: the first arrives from inside his `_integrate_forces`, and a pop runs the whole
## payout pipeline, which must not happen mid-solve.
func _on_buddy_landed(feet: Vector2, _speed: float) -> void:
	_came_down.call_deferred(feet)

func _on_body_entered(other: Node) -> void:
	var him := other as Buddy
	if him == null:
		return
	var rect := him.get_interaction_rect()
	_came_down.call_deferred(Vector2(rect.get_center().x, rect.end.y))

## One landing, one bubble: the two signals above often both fire for the same one.
const LANDING_GAP_MSEC := 250
var _next_landing_msec := 0

## Only from above — walking into its edge is not sitting on it — and the bubble that goes is
## the one under his feet, or the nearest intact one to it.
func _came_down(feet: Vector2) -> void:
	if intact_count() == 0 or gestures == null or not is_inside_tree():
		return
	if not _is_on_top(feet):
		return
	var now := Time.get_ticks_msec()
	if now < _next_landing_msec:
		return
	_next_landing_msec = now + LANDING_GAP_MSEC
	pop(_nearest_intact(feet), not _he_is_playing_with_me())

## His feet on top of it: across its width (with a little grace either side — he is wider
## than a bubble) and at its top edge, in the world. Whatever way up the sheet is lying, "on
## it" is "standing on the top of what is there".
func _is_on_top(feet_world: Vector2) -> bool:
	var box := _world_box()
	var slack := ON_TOP_SLACK * GestureZones.ART_SCALE
	return feet_world.x >= box.position.x - FOOT_GRACE and feet_world.x <= box.end.x + FOOT_GRACE \
		and absf(feet_world.y - box.position.y) <= slack

## World px either side of the sheet that still counts as on it.
const FOOT_GRACE := 24.0

## The collider's box in the world, rotation and all — `get_interaction_rect` is not.
func _world_box() -> Rect2:
	if collider and collider.shape:
		return collider.global_transform * collider.shape.get_rect()
	return Rect2(global_position - Vector2(40, 20), Vector2(80, 40))

func _nearest_intact(world: Vector2) -> int:
	var best := -1
	var best_d := INF
	for slot in _popped.size():
		if _popped[slot]:
			continue
		var d := gestures.zone_world(zone_of(slot)).distance_squared_to(world)
		if d < best_d:
			best_d = d
			best = slot
	return best

## Whether the idle brain has him here on his own time. A landing the player caused — they
## dropped him on it — is the player's act; one he hopped into himself is his.
func _he_is_playing_with_me() -> bool:
	var brain := get_tree().get_first_node_in_group(IdleBrain.GROUP_IDLE_BRAIN) as IdleBrain
	return brain != null and brain.phase_name() == IdleBrain.PHASE_PLAYING \
		and brain.target_id() == item_id

func idle_appeal() -> float:
	# One pop per think tick, and nothing at all once the sheet is flat — which is how a
	# popped-out sheet stops being somewhere worth walking to, with no special case.
	return pop_value / IdleBrain.THINK_SECONDS if intact_count() > 0 else 0.0

## A hop, straight up: from beside the sheet it clears the edge and the brain's lean carries
## him over onto it; from on top of it he comes straight back down on it. The landing does the
## popping. Straight up on purpose — the first version threw him sideways at the sheet, and a
## skeleton moving sideways against a sheet of plastic shoves it across the desk ahead of him
## every time (measured: three hops, three misses, the sheet 490 px further on). At Focus Off
## he is simply there (D21) and the bubble goes without the hop.
func idle_use(him: Buddy) -> void:
	if intact_count() == 0:
		return
	if not animating():
		pop(_nearest_intact(him.global_position), false)
		return
	if not him.is_grounded():
		return
	var gravity := float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	var feet := him.get_interaction_rect().end.y
	var rise := maxf(feet - _world_box().position.y, 0.0) + HOP_CLEARANCE
	var up := sqrt(2.0 * gravity * rise)
	him.apply_central_impulse(Vector2(0.0, -up - minf(him.linear_velocity.y, 0.0)) * him.mass)
