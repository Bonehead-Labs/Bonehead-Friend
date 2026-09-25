extends Node

## Global signal bus. Signals ONLY — no state, no logic.
##
## This exists so cross-scene communication never goes through absolute node paths.
## `get_node("/root/BaseLevel/_Gun")` shipped a crash in an exported build once already;
## signals fail loudly and locally instead. See docs/architecture.md.
##
## Within a single scene, prefer @export node references. Use this bus only across scenes.

# --- combat / interaction ---
signal damage_dealt(info: HitInfo)
signal kindness_given(source_id: StringName, value: float, world_pos: Vector2)
## Kindness paid at a rate rather than as an event: the sponge scrubbing, the boombox
## playing, and every Hearts generator after them. Same payout pipeline, but deliberately
## outside the combo multiplier — a combo is a reward for repeated *acts*, and a box left
## switched on would otherwise sit at the 3x ceiling forever (docs/economy.md).
signal kindness_sustained(source_id: StringName, value: float, world_pos: Vector2)
## `source_id` is the item that earned it (`&"automation"`, `&"acts"` for banked Dollars,
## `&""` for a grant with no source such as a contract claim) — so the tuning CSV can say
## which toy the money came from, which the Aug 31 log could not.
signal payout(currency: StringName, amount: float, world_pos: Vector2, source_id: StringName)
signal currency_changed(currency: StringName, balance: float)

# --- items ---
signal spawn_requested(item_id: StringName, at: Vector2)
signal item_spawned(item: Node2D)
signal item_despawned(item: Node2D)
signal cursor_power_changed(item_id: StringName)  ## &"" clears; powers self-deactivate on mismatch

# --- progression ---
signal item_purchased(item_id: StringName)
signal augment_purchased(node_id: StringName, level: int)
signal mastery_rank_up(item_id: StringName, rank: int)
## An automation capstone was switched on or off. Its income already follows from
## `Progression`; this exists so what is *on screen* can follow too — before M3.5-A a
## toggle changed a number and nothing else, so the device on the desk kept working after
## the player had switched it off.
signal automation_toggled(node_id: StringName, enabled: bool)
signal contract_event(key: StringName, count: int)
signal contract_completed(contract_id: StringName)          ## target reached, reward unclaimed
signal contract_claimed(contract_id: StringName, dollars: int)
## The board itself was replaced — a period rolled over, or a load repopulated it. Every
## row keyed to a contract id is stale. Emitted by `Progression` wherever `_active_contracts`
## is rewritten, so a panel never has to guess from its own visibility that this happened.
signal contract_board_changed()
signal prestige_performed(marrow_gained: float)

# --- buddy ---
signal mood_changed(value: float)  ## -100..+100
signal grime_changed(value: float)  ## 0..1; suppresses Bones income until sponged off
signal buddy_state_changed(state: StringName)
signal knockout_payout(total: float)
signal buddy_landed(world_pos: Vector2, speed: float)  ## his feet, and how fast he came down
## Something on the desk is about to hurt him, or just did. `kind` is `fuse` (a primed
## explosive: level 1 lit, 0 gone off), `windup` (an NPC's tell: 1 winding up, 0 swung) or
## `turret` (a shot: always 1). Presentation only — the buddy's expression reads it, nothing in
## the simulation may. One signal with three emitters, deliberately not six.
signal threat_changed(kind: StringName, world_pos: Vector2, level: float)
## A fidget toy did something he can react to (D57): `jack_popped`, `jack_laugh`,
## `answer_yes` / `answer_no` / `answer_maybe`, `spinning`. Presentation only — the expression
## brain maps each to a row, and nothing in the simulation may listen. The toy pays through
## `kindness_given` / `kindness_sustained` like everything else.
signal fidget_event(item_id: StringName, event: StringName, world_pos: Vector2)

# --- shell ---
signal ui_panel_changed(panel: StringName)  ## &"" = all closed
## Open the shop on one item: the HUD's "next up" row is a link, not a purchase.
signal ui_show_item(item_id: StringName)
## He put something on: a wardrobe slot changed (`bone` or `phones`) to a cosmetic id, or
## `&""` for as drawn. The art re-tints; nothing in the economy listens.
signal cosmetic_changed(slot: StringName, cosmetic_id: StringName)
## Open a page of the card by id. `&"prestige"` opens the Arcade scrolled to Reincarnation —
## the HUD's "Reincarnate for +N" row is a link to the biggest decision in the game.
signal ui_show_panel(panel: StringName)
## A purchase that actually went through, and the screen point the player pressed to make
## it happen — so the HUD can throw a coin from the tile into the purse. Presentation
## only: nothing in the simulation may listen to this, and nothing may infer a purchase
## from it, because a panel that fails to emit it must cost the player nothing.
signal ui_spend(currency: StringName, amount: float, screen_pos: Vector2)
signal interactive_shapes_dirty()           ## rebuild the mouse-passthrough polygon
signal focus_mode_changed(level: int)
## Whole-number UI zoom. Every CanvasLayer in the shell rescales itself and resizes its
## root Control; nothing else in the game cares.
signal ui_scale_changed(factor: float)
signal backdrop_changed(id: StringName)  ## what is painted behind him (D38)
signal save_requested()
