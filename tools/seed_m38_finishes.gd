extends Node

## The wardrobe's first rail: six bone finishes and three sets of headphones, plus the two he came in.
##
##   Godot --headless --path <project> res://tools/seed_m38_finishes.tscn
##
## Dollars had a slot, a currency and no store (docs/assessment-2026-09.md §4): the human
## session ended with fifteen thousand of them and nothing to spend them on but spins. Hats
## need art; a finish is a colour, so it can ship now on the shader he already wears.
##
## Prices are attention, not power (D31): Dollars never inflate, so a finish costs the same
## afternoon on day one and day ninety. The cheapest is under an hour of play; the golden one
## is a week's worth of milestones. Rewrites every time — this table is the authority.

const CosmeticDataScript := preload("res://Scripts/Data/cosmetic_data.gd")
const DIR := "res://Data/Cosmetics"

## [id, name, description, slot, price, tint, sort]
const FINISHES := [
	[&"ivory", "Ivory", "As he came. Free, and always yours.",
		&"bone", 0, Color(1.0, 1.0, 1.0), 0],
	[&"bleached", "Bleached", "Left in the sun. A whiter white than a skeleton has any right to.",
		&"bone", 600, Color(1.10, 1.10, 1.12), 10],
	[&"rose", "Rose Quartz", "Faintly pink, like he has been told something nice.",
		&"bone", 900, Color(1.0, 0.80, 0.88), 20],
	[&"cobalt", "Cobalt", "A cool blue-white. Reads as expensive, which it is.",
		&"bone", 1200, Color(0.74, 0.84, 1.0), 30],
	[&"lavender", "Lavender", "Dusk-coloured. He looks like he has opinions about tea.",
		&"bone", 1500, Color(0.88, 0.80, 1.0), 40],
	[&"neon", "Neon", "Toxic-waste green. Do not ask where he has been.",
		&"bone", 2000, Color(0.72, 1.0, 0.60), 50],
	[&"golden", "Golden Bonehead", "Solid gold, apparently. The most expensive skeleton on any desk.",
		&"bone", 3500, Color(1.0, 0.84, 0.42), 60],
	[&"teal_cans", "Teal Cans", "As he came. Free, and always his to go back to.",
		&"phones", 0, Color(1.0, 1.0, 1.0), 100],
	[&"studio_cans", "Studio Whites", "Crisp white headphones. He hears things you do not.",
		&"phones", 800, Color(0.93, 0.93, 0.92), 110],
	[&"pink_cans", "Pink Cans", "Bubblegum pink headphones. Entirely his choice.",
		&"phones", 1000, Color(0.96, 0.45, 0.64), 120],
	[&"gold_cans", "Gold Cans", "Gold-plated headphones, for a skeleton who has made it.",
		&"phones", 2500, Color(0.95, 0.82, 0.42), 130],
]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var written := 0
	for row in FINISHES:
		var res := CosmeticDataScript.new()
		res.id = row[0]
		res.display_name = row[1]
		res.description = row[2]
		res.slot = row[3]
		res.price_dollars = row[4]
		res.tint = row[5]
		res.sort_order = row[6]
		var path := "%s/%s.tres" % [DIR, row[0]]
		var err := ResourceSaver.save(res, path)
		if err != OK:
			push_error("seed_m38_finishes: failed to write %s (error %d)" % [path, err])
			continue
		written += 1
		print("  wrote %s" % path)
	print("seed_m38_finishes: %d written" % written)
	get_tree().quit()
