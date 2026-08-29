extends Node

## Thin bootstrapper. Loads the save, applies offline earnings, builds the UI layers and
## wires them to the world — then gets out of the way.
##
## There is no main-menu scene: the game boots straight to the buddy (docs/decisions.md
## D6). The shell is the HUD dock plus the panel suite, on CanvasLayers inside the one
## transparent window.

## Where the trash bin sits, as a fraction of the window, so it lands somewhere sensible
## in a 480x360 play area as well as on a 4K overlay.
const BIN_ANCHOR := Vector2(0.06, 0.86)

@export var world: Node2D
@export var buddy: Buddy
@export var spawner: ItemSpawner
@export var trash_bin: Node2D

var _hud: HUD
var _panels: PanelLayer
var _esc: EscMenu
var _fx: FXLayer

func _ready() -> void:
	# Load before building UI: the shop reads what the player owns, and Progression grants
	# the free starters as part of from_save.
	var save := SaveManager.load_game()
	Economy.apply_offline_earnings(int(save.get("last_played_unix", 0)))

	spawner.world = world
	spawner.add_to_group(&"item_spawner")

	_build_ui()
	_place_trash_bin()
	get_viewport().size_changed.connect(_place_trash_bin)

	# A tree purchase has to reach weapons already lying on the desktop, or the upgrade
	# the player just bought does nothing until they bin the bat and spawn a new one.
	EventBus.augment_purchased.connect(func(_id: StringName, _l: int) -> void:
		spawner.refresh_augments())

func _build_ui() -> void:
	_fx = FXLayer.new()
	add_child(_fx)

	_panels = PanelLayer.new()
	add_child(_panels)

	_hud = HUD.new()
	add_child(_hud)
	_hud.panel_requested.connect(_panels.toggle)
	if buddy and buddy.health:
		_hud.bind_health(buddy.health)
	_hud.bind_spawner(spawner)

	_esc = EscMenu.new()
	_esc.world = world
	add_child(_esc)

func _place_trash_bin() -> void:
	if trash_bin == null:
		return
	trash_bin.global_position = get_viewport().get_visible_rect().size * BIN_ANCHOR
