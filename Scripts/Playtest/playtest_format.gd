class_name PlaytestFormat
extends RefCounted

## The shape of what a playtest leaves behind, shared by the game that writes it and the report
## tool that reads it (`tools/playtest_report_math.gd`), so the two cannot drift.
##
## A session log is **JSON Lines**: one object per line, each with `t` (seconds since the session
## began) and `e` (what happened), plus whatever that event carries. One line per event rather
## than one document per session, because a session that crashes must still leave everything it
## flushed readable — a half-written JSON document is unreadable from its first byte.
##
## Pure: no autoloads, so `tests/run_tests.gd` can reach every function here.

## Bumped when a row changes meaning. The reader accepts anything at or below it.
const FORMAT := 1

## One row. Fields keep the order they were given in, so a log reads left to right the same way
## every time; `t` is rounded to a tenth, which is finer than anything a person does.
static func row(t: float, event: String, fields: Dictionary = {}) -> String:
	var out := {"t": snappedf(maxf(t, 0.0), 0.1), "e": event}
	for key in fields:
		out[key] = fields[key]
	# Unsorted, or `JSON.stringify` alphabetises and `t` and `e` land mid-row.
	return JSON.stringify(out, "", false)

## The row back, or `{}` for a line that is not one (a torn last line after a crash).
static func parse_row(line: String) -> Dictionary:
	var text := line.strip_edges()
	if text == "" or not text.begins_with("{"):
		return {}
	# An instance rather than `JSON.parse_string`, which prints an engine error for every torn
	# line it is handed — and a crashed session always ends in one.
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var parsed = json.data
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("e"):
		return {}
	return parsed

## Every row of a session file, skipping what does not parse.
static func parse_rows(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line in text.split("\n"):
		var parsed := parse_row(line)
		if not parsed.is_empty():
			out.append(parsed)
	return out

## Personal data out of free text the game did not write: an engine error that names a file names
## the folder it is in, and on Windows that folder is under the player's own name.
##
## `replacements` maps a known absolute path (the user data folder, the game's own folder) to what
## it should read as; it is applied in both slash directions, since Windows messages use either.
## Anything left that still looks like a home folder is cut to `~`.
static func scrub(text: String, replacements: Dictionary = {}) -> String:
	var out := text
	for key in replacements:
		var path := String(key)
		if path.length() < 4:
			continue
		out = out.replace(path, String(replacements[key]))
		out = out.replace(path.replace("/", "\\"), String(replacements[key]))
	return _home().sub(out, "~", true)

static var _home_re: RegEx = null

static func _home() -> RegEx:
	if _home_re == null:
		# A drive, a Users folder and the one path segment after it: `C:\Users\George`,
		# `c:/users/george`. The name ends at the next separator, quote or space.
		_home_re = RegEx.create_from_string("(?i)[a-z]:[\\\\/]+users[\\\\/]+[^\\\\/\"'\\s]+")
	return _home_re

## `20260927-140305`: sorts as it reads, and is safe in a file name on every OS.
static func file_stamp(datetime: Dictionary) -> String:
	return "%04d%02d%02d-%02d%02d%02d" % [int(datetime.get("year", 0)), int(datetime.get("month", 0)),
		int(datetime.get("day", 0)), int(datetime.get("hour", 0)), int(datetime.get("minute", 0)),
		int(datetime.get("second", 0))]

## Which of a folder's files to delete to bring it under a count and a size, oldest first.
##
## `entries` is `[{"name": String, "size": int}]`. Names begin with a `file_stamp`, so sorting by
## name is sorting by age; `keep` names a file that is never deleted (the session being written).
static func prune_plan(entries: Array, max_files: int, max_bytes: int, keep: String = "") -> PackedStringArray:
	var sorted := entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["name"]) < String(b["name"]))
	var count := sorted.size()
	var total := 0
	for entry in sorted:
		total += int(entry["size"])
	var out := PackedStringArray()
	for entry in sorted:
		if count <= max_files and total <= max_bytes:
			break
		if String(entry["name"]) == keep:
			continue
		out.append(String(entry["name"]))
		count -= 1
		total -= int(entry["size"])
	return out

## A multipart/form-data body: text fields, then one file. Built by hand because Godot's
## HTTPRequest takes a byte body and nothing else, and a webhook (Discord's, for one) wants a form.
static func multipart(boundary: String, fields: Dictionary, file_field: String, file_name: String,
		file_type: String, file_bytes: PackedByteArray) -> PackedByteArray:
	var body := PackedByteArray()
	for key in fields:
		body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n"
			% [boundary, key, String(fields[key])]).to_utf8_buffer())
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n"
		% [boundary, file_field, file_name, file_type]).to_utf8_buffer())
	body.append_array(file_bytes)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	return body
