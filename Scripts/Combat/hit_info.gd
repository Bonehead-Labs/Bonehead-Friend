class_name HitInfo
extends RefCounted

## A single damage event, produced by the receiver from real contact impulses.
## See docs/architecture.md — damage is measured on the buddy, not by the attacker.

var amount: float          ## Damage after the source's damage_mult
var source_id: StringName  ## Item id that caused it, or &"" for anonymous world contact
var position: Vector2      ## Global position of the contact, for floating numbers and VFX
var raw_impulse: float     ## Unscaled contact impulse, used for detach/knockback thresholds
## Which part of him took it. `torso` until the multi-hitbox lands (docs/plan-movement-
## hitboxes.md §5); the seam exists now so the parts are additive when they arrive.
var part: StringName
## Nobody's hand is behind it, though an item's name is on it (D76 amended): a desk fan left
## blowing, which claims the wall it blows him into (D65). The id says whose; this says nobody
## was there, so Economy judges it as it judges the world and the idle brain does not take it for
## the player arriving. False for everything a hand swings, throws, fires or holds.
var by_itself := false

func _init(p_amount: float = 0.0, p_source_id: StringName = &"", p_position: Vector2 = Vector2.ZERO,
		p_raw_impulse: float = 0.0, p_part: StringName = &"torso") -> void:
	amount = p_amount
	source_id = p_source_id
	position = p_position
	raw_impulse = p_raw_impulse
	part = p_part
