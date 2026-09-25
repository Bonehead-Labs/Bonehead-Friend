extends CaptureWindow

## Him in the soak furniture (D70), as the player sees it: each of the soak toys on the desk,
## the idle brain sent to it, and a shot once the toy has him sitting in it — and one of him
## hopping out when the dwell is over. The thing a headless suite can only measure: whether
## "in it" reads as in it, with the toy drawn over his legs.
##
##   Godot --path <project> res://tools/soak_shots.tscn        (NOT --headless: it draws)
##
## Files land in `user://soak_shots/`. Its own save slot and settings file, through
## `CaptureWindow._use_capture_slot()`, like every capture tool.

const SIZE := Vector2i(1180, 760)
const OUT := "user://soak_shots"

var _main: Node
var _had := {}

func _ready() -> void:
	_use_capture_slot()
	_had = {"hud": Settings.hud_pinned, "tabs": Settings.tabs_pinned, "scale": Settings.ui_scale,
		"focus": Settings.focus_intensity}
	DirAccess.make_dir_recursive_absolute(OUT)
	Settings.focus_intensity = Settings.Intensity.NORMAL
	Settings.ui_scale = 0
	Settings.hud_pinned = false
	Settings.tabs_pinned = false
	_install_backdrop()

	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	await _idle(20)
	_show_window(SIZE, "soak furniture")
	await _idle(30)
	Economy.grant(Economy.HEARTS, 5.0e6)
	var buddy := get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Buddy
	var idle := get_tree().get_first_node_in_group(IdleBrain.GROUP_IDLE_BRAIN) as IdleBrain
	var spawner := get_tree().get_first_node_in_group(&"item_spawner") as ItemSpawner
	if buddy == null or idle == null or spawner == null:
		push_error("soak_shots: the game booted without a buddy, a brain or a spawner")
		get_tree().quit(1)
		return
	var floor_y := float(SIZE.y)
	var index := 0
	for item in ItemDB.all_items():
		if item.scene == null:
			continue
		# Instanced, then cast, then freed either way: a cursor power is not a body, and a null
		# cast used to leave all ten of them alive at exit (D75).
		var instance := item.scene.instantiate()
		var probe := instance as BaseDraggable
		var routine := IdleBrain.ROUTINE_NONE
		if probe:
			probe.item_id = item.id
			routine = idle._routine_for(probe)
		instance.free()
		if routine != IdleBrain.ROUTINE_SOAK:
			continue
		index += 1
		Progression._unlock(item.id)
		idle._disturb()
		spawner.clear_desk()
		await _idle(5)
		# Out of the way first, or the next toy is dropped on his head and that is billed.
		buddy.global_position = Vector2(float(SIZE.x) - 120.0, floor_y - 63.0)
		buddy.linear_velocity = Vector2.ZERO
		var toy_x := float(SIZE.x) * 0.5 - 60.0
		EventBus.spawn_requested.emit(item.id, Vector2(toy_x, floor_y - 200.0))
		var toy: FriendlyBase = null
		for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_SPAWNED):
			if (node as BaseDraggable).item_id == item.id:
				toy = node as FriendlyBase
		await _idle(60)
		if toy == null:
			continue
		buddy.global_position = Vector2(toy.global_position.x + toy.seat_rect().size.x * 0.5 + 110.0,
			floor_y - 63.0)
		buddy.global_rotation = 0.0
		buddy.linear_velocity = Vector2.ZERO
		await _idle(30)
		idle.pretend_idle()
		idle.think_now()
		var sat := false
		for f in 300:
			await get_tree().physics_frame
			if f % 60 == 59:
				idle.think_now()
			if toy.is_seated(buddy):
				sat = true
				break
		await _idle(40)
		await _shot("%02d-%s-%s" % [index, item.id, "in" if sat else "NOT-in"])
		# The dwell runs out and he hops out over the side.
		for i in 12:
			if idle.phase_name() != IdleBrain.PHASE_PLAYING:
				break
			idle.think_now()
		await _idle(14)
		await _shot("%02d-%s-out" % [index, item.id], 0)
		# Down and still before the next: disturbing him mid-hop would make his landing the
		# player's, and bill it.
		for f in 240:
			if buddy.is_grounded() and buddy.linear_velocity.length() < 30.0:
				break
			await get_tree().physics_frame

	idle._disturb()
	spawner.clear_desk()
	_clear_slot()
	print("soak_shots: wrote %s" % ProjectSettings.globalize_path(OUT))
	Settings.hud_pinned = _had["hud"]
	Settings.tabs_pinned = _had["tabs"]
	Settings.ui_scale = _had["scale"]
	Settings.focus_intensity = _had["focus"]
	Settings.save_settings()
	get_tree().quit()

## Headless draws nothing, so there a shot is only the staging.
func _shot(name: String, settle: int = 20) -> void:
	await _idle(settle)
	if DisplayServer.get_name() == "headless":
		print("  %s (staged; headless draws nothing)" % name)
		return
	await RenderingServer.frame_post_draw
	_grab().save_png("%s/%s.png" % [OUT, name])
	print("  %s" % name)
