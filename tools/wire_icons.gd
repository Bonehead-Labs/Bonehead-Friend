extends Node

## Points every ItemData at its generated shop icon.
##
##   Godot --headless --path <project> res://tools/wire_icons.tscn
##
## Separate from the seed tools because icons arrive *after* the items do — the icon is
## downscaled from the sprite, which is generated later — and because re-running a seed with
## --force would rewrite tuning alongside it. This only ever sets `icon`, so it is safe to
## run again as more art lands.

const ITEMS_DIR := "res://Data/Items"
const ICONS_DIR := "res://Assets/sprites/icons"

func _ready() -> void:
	var wired := 0
	var missing := 0
	for file in DirAccess.get_files_at(ITEMS_DIR):
		var name := file
		if name.ends_with(".remap") or name.ends_with(".import"):
			name = name.get_basename()
		if not (name.ends_with(".tres") or name.ends_with(".res")):
			continue
		var path := ITEMS_DIR.path_join(name)
		var item := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ItemData
		if item == null:
			continue

		var icon_path := "%s/%s.png" % [ICONS_DIR, item.id]
		if not ResourceLoader.exists(icon_path):
			missing += 1
			continue
		var icon := ResourceLoader.load(icon_path) as Texture2D
		if icon == null or item.icon == icon:
			continue
		item.icon = icon
		var err := ResourceSaver.save(item, path)
		if err != OK:
			push_error("wire_icons: failed to write %s (error %d)" % [path, err])
			continue
		wired += 1
		print("  %s -> %s" % [item.id, icon_path])

	print("wire_icons: %d wired, %d still without art" % [wired, missing])
	get_tree().quit()
