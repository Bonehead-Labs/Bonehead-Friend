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
signal payout(currency: StringName, amount: float, world_pos: Vector2)
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
signal contract_event(key: StringName, count: int)
signal prestige_performed(ectoplasm_gained: int)

# --- buddy ---
signal mood_changed(value: float)  ## -100..+100
signal buddy_state_changed(state: StringName)
signal knockout_payout(total: float)

# --- shell ---
signal ui_panel_changed(panel: StringName)  ## &"" = all closed
signal interactive_shapes_dirty()           ## rebuild the mouse-passthrough polygon
signal focus_mode_changed(level: int)
signal save_requested()
