extends Node

## The collider audit as a table (docs/decisions.md D61): every authored item body measured
## against its own picture by `ColliderAudit`, one row each.
##
##   Godot --headless --path <project> res://tools/collider_report.tscn
##       [-- --all] [--only id,id] [--shots] [--runs] [--csv]
##
## `--all` adds the single-collider bodies D55 already guards; by default only bodies with
## several shapes are listed, because those are the ones authored by hand in a seed table.
## `--shots` writes an overlay per body to `user://collider_audit/<id>.png` — the sprite at 4x
## with the shapes tinted over it, green on the picture and red off it, grip in blue and centre
## of mass in yellow, on a grid every 4 art pixels. Read shape coordinates off that, not off the
## sprite alone: the grid's dark lines are the origin the seed tables measure from. `--runs`
## prints the picture as opaque runs per art-pixel row, which is where exact extents come from.
##
## Runs against the real ItemDB, so it measures the scenes that ship rather than the tables
## that were meant to produce them — a scene frozen against replaced art shows up here, and
## that is one of the things it exists to find.

const SHOTS_DIR := "user://collider_audit"

const SeedBodies := preload("res://tools/seed_bodies.gd")
const SeedBlades := preload("res://tools/seed_m36_melee_blades.gd")
const SeedBlunt := preload("res://tools/seed_m36_melee_blunt.gd")
const SeedTurrets := preload("res://tools/seed_m36_turrets.gd")
const SeedExplosives := preload("res://tools/seed_m36_explosives.gd")
const BaseDraggableScript := preload("res://Scripts/Bodies/base_draggable.gd")

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var everything := args.has("--all")
	var shots := args.has("--shots")
	var csv := args.has("--csv")
	# `--tables` builds every body from the seed tables in memory instead of loading the shipped
	# scene: the loop for authoring shapes without writing a file, and — run beside the default
	# — the check that a scene has not drifted from the table that is supposed to produce it.
	var tables := _table_specs() if args.has("--tables") else {}
	var only: Array[String] = []
	var at := args.find("--only")
	if at >= 0 and at + 1 < args.size():
		only.assign(args[at + 1].split(",", false))
	if shots:
		DirAccess.make_dir_recursive_absolute(SHOTS_DIR)

	var rows: Array = []
	for item in ItemDB.all_items():
		if item.scene == null:
			continue
		if not only.is_empty() and not only.has(String(item.id)):
			continue
		var root: Node = null
		if args.has("--tables"):
			if not tables.has(item.id):
				continue
			var spec: Dictionary = tables[item.id].duplicate()
			spec["id"] = item.id
			root = ItemBodyBuilder.build(spec)
			if root == null:
				continue
		else:
			root = item.scene.instantiate()
		var body := root as RigidBody2D
		if body == null or (not everything and not ColliderAudit.is_authored(body)):
			root.free()
			continue
		var m := ColliderAudit.measure(body)
		if not m.is_empty():
			m["id"] = item.id
			m["mass"] = body.mass
			rows.append(m)
			if shots:
				var image := ColliderAudit.overlay(body, 4)
				if image:
					image.save_png("%s/%s.png" % [SHOTS_DIR, item.id])
			if args.has("--runs"):
				print("%s  grip %s  com %s (art px)" % [item.id, m["grip"] * 0.5, m["com"] * 0.5])
				for line in ColliderAudit.runs(body):
					print("  " + line)
		root.free()

	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["id"]) < String(b["id"]))
	if csv:
		print("id,shapes,mass,coverage,excess,overhang,left,right,top,bottom,art_axis,art_long,"
			+ "shape_axis,shape_long,axis_gap,grip_off,com_off,grip_t,com_t,art_x,art_y,art_w,art_h")
	else:
		print("")
		print("%-20s %2s %5s %5s %5s %5s  %3s %3s %3s %3s  %5s %5s %4s  %4s %4s %5s %5s  %s" % [
			"id", "n", "mass", "cov%", "exc%", "over", "L", "R", "T", "B",
			"art°", "shp°", "gap", "grip", "com", "g_t", "c_t", "art rect (art px from centre)"])
	for m in rows:
		var sides: Dictionary = m["sides"]
		var art: Rect2 = m["art_rect"]
		var art_px := Rect2(art.position * 0.5, art.size * 0.5)
		if csv:
			print("%s,%d,%.1f,%.3f,%.3f,%.1f,%d,%d,%d,%d,%.1f,%.2f,%.1f,%.2f,%.1f,%.1f,%.1f,%.2f,%.2f,%.1f,%.1f,%.1f,%.1f" % [
				m["id"], m["shapes"], m["mass"], m["coverage"], m["excess"], m["overhang"],
				sides["left"], sides["right"], sides["top"], sides["bottom"],
				m["art_axis"], m["art_long"], m["shape_axis"], m["shape_long"], m["axis_gap"],
				m["grip_off"], m["com_off"], m["grip_t"], m["com_t"],
				art_px.position.x, art_px.position.y, art_px.size.x, art_px.size.y])
			continue
		print("%-20s %2d %5.1f %5.0f %5.0f %5.1f  %3d %3d %3d %3d  %5.0f %5.0f %4.0f  %4.1f %4.1f %5.2f %5.2f  (%.1f,%.1f %.1fx%.1f)" % [
			m["id"], m["shapes"], m["mass"], float(m["coverage"]) * 100.0,
			float(m["excess"]) * 100.0, m["overhang"],
			sides["left"], sides["right"], sides["top"], sides["bottom"],
			m["art_axis"], m["shape_axis"], m["axis_gap"],
			m["grip_off"], m["com_off"], m["grip_t"], m["com_t"],
			art_px.position.x, art_px.position.y, art_px.size.x, art_px.size.y])
	print("")
	print("%d bodies measured%s" % [rows.size(),
		(", overlays in %s" % ProjectSettings.globalize_path(SHOTS_DIR)) if shots else ""])
	get_tree().quit()

## Every authored body in every seed table, as the spec `ItemBodyBuilder.build` takes: shapes,
## centre of mass, grip and grab, keyed by id. Only entries with shapes of their own — a body
## the tables leave to the derived box is D55's to guard, not this report's.
func _table_specs() -> Dictionary:
	var out := {}
	for id in SeedBodies.PHYSICS:
		out[id] = SeedBodies.PHYSICS[id]
	for row in SeedBlades.BLADES:
		out[row["id"]] = row
	for id in SeedBlunt.PHYSICS:
		out[id] = SeedBlunt.PHYSICS[id]
	for id in SeedTurrets.TURRETS:
		# The turret's own numbers ride along, because `flips` changes what it is measured
		# against — and so does its script, which is the only thing that has that property.
		var turret: Dictionary = SeedTurrets.TURRETS[id]["body"].duplicate()
		turret["properties"] = SeedTurrets.TURRETS[id]["turret"]
		turret["script"] = SeedTurrets.TurretBaseScript
		out[id] = turret
	for row in SeedExplosives.EXPLOSIVES:
		if row.has("shapes"):
			out[row["id"]] = row
	var specs := {}
	for id in out:
		var row: Dictionary = out[id]
		var spec := {"script": BaseDraggableScript}
		for key in ["shapes", "com", "grip", "grab", "properties", "script"]:
			if row.has(key):
				spec[key] = row[key]
		specs[id] = spec
	return specs
