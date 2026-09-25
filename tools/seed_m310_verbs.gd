extends Node

## Teaches the everyday things their verbs (docs/decisions.md D67): writes each verb item's
## `controls` line from `tools/verb_table.gd` onto the `ItemData` that already exists.
##
##   Godot --headless --path <project> res://tools/seed_m310_verbs.tscn
##
## The seeders that own these items write `controls` when they create one, but they never
## rewrite an item that exists — its icon, its `requires` and its price may have been set by
## other tools since — so this loads each one, sets the line and saves it, and leaves every
## other field exactly as it was. The table is the authority: run it again after editing one.
##
## The **scenes** are not written here. They belong to the seeders that build them, which call
## `VerbTable.attach()` on every body: delete the scene and re-run its seeder without `--force`
## (`seed_friendly`, or `seed_m35_roster` for the hot tub), and it rewrites that file alone, with
## its zones and verbs (the route D62 used).

const VerbTable := preload("res://tools/verb_table.gd")
const ITEMS_DIR := "res://Data/Items"

func _ready() -> void:
	var written := 0
	for id in VerbTable.VERBS:
		var path := "%s/%s.tres" % [ITEMS_DIR, id]
		var item := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ItemData
		if item == null:
			push_error("seed_m310_verbs: no item at %s — check the exact on-disk case" % path)
			continue
		var line := VerbTable.controls(id)
		if item.controls == line:
			continue
		item.controls = line
		var err := ResourceSaver.save(item, path)
		if err != OK:
			push_error("seed_m310_verbs: failed to write %s (error %d)" % [path, err])
			continue
		written += 1
		print("  wrote %s" % path)
	print("seed_m310_verbs: %d written" % written)
	get_tree().quit()
