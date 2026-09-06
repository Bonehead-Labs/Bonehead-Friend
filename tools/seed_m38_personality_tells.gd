extends Node

## Personality on the surface: the tell each of the twelve personalities shows in the first
## minute (docs/plan-expressive-buddy.md §5). Updates the existing `.tres` files in place.
##
##   Godot --headless --path <project> res://tools/seed_m38_personality_tells.tscn
##
## The only place a player ever learned which personality they rolled was the Reincarnate
## page, while the design sells personality as half the reason to Reincarnate. These fields
## put it on his face and in his motion, and none of them touches a number (D19).
##
## Runs every time, unlike the roster seeders: the presentation fields are authored here and
## the file is the output, so re-running is how a tell gets retuned. The curve, name and
## description in each file are left exactly as they are.

const PERSONALITIES_DIR := "res://Data/Personalities"

## id -> {field: value}. Anything not listed keeps the class default, which is the honest
## baseline. Martyr, Tyrant and Stoic have no tell yet — an owner call (plan §8, item 4).
const TELLS := {
	&"masochist": {"hurt_face": &"blissful"},
	&"diva": {"hurt_face": &"angry", "reaction_amplitude": 1.4},
	&"showman": {"reaction_amplitude": 1.6, "celebration_face": &"smug", "fidget_period": 6.0},
	&"goth": {"face_swaps": {&"sad": &"neutral", &"blissful": &"shocked"}},
	&"gremlin": {"fidget_period": 4.0},
	&"nervous": {"flinches_early": true, "reaction_amplitude": 1.3},
	&"stone": {"reaction_amplitude": 0.4, "fidget_period": 30.0, "hurt_face": &"neutral"},
	&"zen": {"reaction_amplitude": 0.5, "fidget_period": 20.0},
	&"pendulum": {"fidget_period": 3.0},
}

func _ready() -> void:
	var written := 0
	for id in TELLS:
		var path := "%s/%s.tres" % [PERSONALITIES_DIR, id]
		var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PersonalityData
		if res == null:
			push_error("seed_m38_personality_tells: no personality at %s" % path)
			continue
		var tell: Dictionary = TELLS[id]
		for field in tell:
			res.set(field, tell[field])
		var err := ResourceSaver.save(res, path)
		if err != OK:
			push_error("seed_m38_personality_tells: failed to write %s (error %d)" % [path, err])
			continue
		written += 1
		print("  wrote %s" % path)
	print("seed_m38_personality_tells: %d updated" % written)
	get_tree().quit()
