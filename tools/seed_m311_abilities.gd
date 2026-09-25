extends Node

## Teaches the held weapons their abilities (docs/decisions.md D74): writes each weapon's
## `controls` line from `AbilityTable` onto the `ItemData` that already exists.
##
##   Godot --headless --path <project> res://tools/seed_m311_abilities.tscn
##
## The seeders that own these items never rewrite an item that exists — its icon, its `requires`
## and its price may have been set by other tools since — so this loads each one, sets the line
## and saves it, and leaves every other field exactly as it was. The table is the authority: run
## it again after editing a row's line. The scenes are not touched at all; `WeaponBase` reads the
## table at runtime (see `AbilityTable`'s class comment for why).

const ITEMS_DIR := "res://Data/Items"

func _ready() -> void:
	var written := 0
	for id in AbilityTable.item_ids():
		var path := "%s/%s.tres" % [ITEMS_DIR, id]
		var item := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ItemData
		if item == null:
			push_error("seed_m311_abilities: no item at %s — check the exact on-disk case" % path)
			continue
		var line := AbilityTable.controls(id)
		if item.controls == line:
			continue
		item.controls = line
		var err := ResourceSaver.save(item, path)
		if err != OK:
			push_error("seed_m311_abilities: failed to write %s (error %d)" % [path, err])
			continue
		written += 1
		print("  wrote %s" % path)
	print("seed_m311_abilities: %d written" % written)
	get_tree().quit()
