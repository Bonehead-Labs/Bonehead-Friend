class_name GrenadeLauncher
extends HeldGun

## A grenade launcher (docs/decisions.md D71). Right lobs a grenade: it arcs, it bounces off the
## desk, and it goes off when it touches him or when its fuse runs out — whichever is first.
##
## The only gun that hurts him by what it lands *near*. The blast is the explosives' own
## (`ExplosionUtil.point_blast`): every loose thing within reach is thrown, him included, and
## he is billed the impulse the blast handed him at the gun's shot multiplier (D7) — so a
## grenade that bounced once and went off at his feet hurts less than one that met him in the
## air, and one that went off beside the launcher throws the launcher too.
##
## It aims itself like every held gun, but at the arc (`HeldGun._lob_angle`): close in the
## barrel sits nearly flat; across the desk it tips up; out of reach it lobs at forty-five
## degrees and the bounce does the rest. Four in the drum, then a reload.

@export_group("Grenade")
@export var grenade_texture: Texture2D
## Seconds from the muzzle to the bang, if it has not met him first.
@export var fuse: float = 1.6
@export var blast_radius: float = 100.0
@export var grenade_bounce: float = 0.5

var _grenades: Array[WeakRef] = []

func _shoot(from: Vector2, dir: Vector2) -> void:
	var grenade := Grenade.new()
	grenade.name = "Grenade"
	grenade.source = item_id
	grenade.mult = shot_damage_mult()
	grenade.force = shot_force
	grenade.texture = grenade_texture
	grenade.radius = 4.0
	grenade.bounce = grenade_bounce
	grenade.lifetime = fuse
	grenade.blast_radius = blast_radius
	grenade.gravity_scale = projectile_gravity
	grenade.z_index = 20
	var host := get_parent() if get_parent() else self
	host.add_child(grenade)
	grenade.global_position = from
	grenade.linear_velocity = dir * projectile_speed
	_grenades.append(weakref(grenade))
	var fx := WorldFX.of(self)
	if fx:
		fx.shot(from, false, mini(juice_tier, 1))
		fx.puff(from, 3, WorldFX.SOOT, 50.0, 0.5)
	# It breaks open and the case comes out, a beat after the shot.
	if pump_delay > 0.0:
		get_tree().create_timer(pump_delay).timeout.connect(_pump)
	else:
		_eject()

func grenades_in_flight() -> int:
	var count := 0
	for ref in _grenades:
		var grenade := ref.get_ref() as Grenade
		if grenade and not grenade.is_queued_for_deletion():
			count += 1
	return count

## Binned with grenades in the air, they go with it: nothing a thrown-away thing fired may keep
## hurting him under its name.
func _exit_tree() -> void:
	super._exit_tree()
	for ref in _grenades:
		var grenade := ref.get_ref() as Node
		if grenade and is_instance_valid(grenade):
			grenade.queue_free()
	_grenades.clear()

## One grenade. Bounces off the world, goes off on him or on its fuse.
class Grenade extends GunProjectile:
	var blast_radius := 100.0
	var exploded := false

	func _on_him(_him: Buddy, at: Vector2, _heading: Vector2) -> void:
		explode(at)

	func _expire() -> void:
		explode(global_position)

	func explode(at: Vector2) -> void:
		if exploded:
			return
		exploded = true
		var space := get_world_2d().direct_space_state
		for hit in ExplosionUtil.point_blast(space, at, blast_radius, force):
			var body: Node = hit["body"]
			if body is Buddy:
				(body as Buddy).take_impulse(float(hit["impulse"]), source, mult, at)
		var fx := WorldFX.of(self)
		if fx:
			fx.boom(at, 0.7)
			fx.shake(3.0)
		AudioManager.play(&"explode_small", 0.1, -4.0, 1.15)
		queue_free()
