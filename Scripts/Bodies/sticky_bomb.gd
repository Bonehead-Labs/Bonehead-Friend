class_name StickyBomb
extends ThrowableBase

## The charge that does not bounce off him. It latches where it lands and the fuse runs from
## there, so the blast happens at zero distance — which is the whole of the item. Every other
## explosive on the desk is a question of aim against a quadratic falloff; this one is a
## question of connecting once.
##
## Sticking is a PinJoint2D, the same joint the drag handle is built on. Reparenting it onto
## him would put an item scene inside the buddy's and make his transform its parent, and the
## joint costs nothing the drag code has not already paid for.

## The fuse the landing starts, which is shorter than `throwable_delay`: a charge already
## attached to him needs no travel time.
@export var contact_delay: float = 1.2

## How hard it holds. Soft enough that a big enough shove can shake it off him, which is the
## only counterplay there is to a bomb that is already on you.
@export var stick_softness: float = 0.2
@export var stick_bias: float = 0.9

var _joint: PinJoint2D
var _sticking := false

func _ready() -> void:
	super._ready()
	# `contact_monitor` and `max_contacts_reported` are set by the body factory. Without
	# both, this signal never fires and the item is an ordinary grenade with a tacky picture.
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _sticking or not (body is Buddy):
		return
	_sticking = true
	# Deferred, because `body_entered` arrives while the physics server is flushing and
	# adding a joint from inside that flush is the "Can't change this state while flushing
	# queries" error rather than a stuck bomb.
	_stick_to.call_deferred(body)

func _stick_to(target: PhysicsBody2D) -> void:
	if not is_instance_valid(target) or not is_inside_tree():
		return
	_joint = PinJoint2D.new()
	_joint.name = "StuckJoint"
	_joint.node_a = get_path()
	_joint.node_b = target.get_path()
	_joint.softness = stick_softness
	_joint.bias = stick_bias
	add_child(_joint)
	if is_primed:
		return
	# Landing on him *is* the pin. The fuse a right-click would have started is replaced by
	# the shorter one rather than added to it.
	throwable_delay = contact_delay
	prime_explosion()

func explode() -> void:
	# Let go before the blast. An invisible casing still pinned to a skeleton it has just
	# thrown across the desk drags him back, and the half second the base class waits before
	# freeing itself is long enough to watch it happen.
	if _joint:
		_joint.queue_free()
		_joint = null
	super.explode()
