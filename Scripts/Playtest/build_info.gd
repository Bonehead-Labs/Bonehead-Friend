class_name BuildInfo
extends RefCounted

## Which build this is, read from a stamp the build script writes (tools/make_playtest_build.ps1).
##
## A playtest is only worth its notes if every note says which build it came from: "the shop
## scrolled off the card" means one thing on Tuesday's build and nothing on Friday's. So the
## script writes `res://Data/build_stamp.txt` before it exports and deletes it after, and the
## export carries it because `Data/*.txt` is already on the preset's include list (the Dream
## Journal rides the same way). A checkout never has one — it is gitignored — so a run from the
## editor or a suite is `dev`, and says so.
##
## Pure: no autoloads, so the unit runner can reach it and an autoload can use it at boot.

const STAMP_PATH := "res://Data/build_stamp.txt"

## Set by the stamp. `playtest` turns the session log on by default (the tester can still
## switch it off in Settings); anything else — a demo, a release — leaves it off.
const CHANNEL_PLAYTEST := "playtest"

static var _loaded := false
static var _fields: Dictionary = {}

## `2026-09-27-e76d64f`, `2026-09-27-e76d64f-dirty`, or `dev` for a checkout.
static func id() -> String:
	return String(_stamp().get("build_id", "dev"))

static func channel() -> String:
	return String(_stamp().get("channel", "dev"))

static func commit() -> String:
	return String(_stamp().get("commit", ""))

static func is_stamped() -> bool:
	return _stamp().has("build_id")

## A build handed to a tester, or a developer run that asked to behave like one
## (`-- --playtest`, so the session log can be tried without making a build).
static func is_playtest() -> bool:
	if channel() == CHANNEL_PLAYTEST:
		return true
	for arg in OS.get_cmdline_user_args():
		if String(arg) == "--playtest":
			return true
	return false

## `key=value` lines; blank lines and `#` comments ignored. Parsed once and cached.
static func parse(text: String) -> Dictionary:
	var out := {}
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var eq := line.find("=")
		if eq <= 0:
			continue
		out[line.substr(0, eq).strip_edges()] = line.substr(eq + 1).strip_edges()
	return out

static func _stamp() -> Dictionary:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(STAMP_PATH):
			_fields = parse(FileAccess.get_file_as_string(STAMP_PATH))
	return _fields
