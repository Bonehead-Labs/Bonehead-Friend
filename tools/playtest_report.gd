extends Node

## Reads a folder of returned feedback bundles — any number of testers, any number of sends each —
## and writes one markdown report (docs/playtest-plan.md, "Reading what comes back").
##
##   Godot --headless --path <project> res://tools/playtest_report.tscn -- --in=<folder> --out=<report.md>
##   ... -- --in=<folder> --out=<report.md> --dead=5    a dead stretch is 5+ minutes (the default)
##   ... -- --demo --in=<folder> --out=<report.md>      write three synthetic testers first, then report
##
## `--in` holds the zips exactly as testers sent them (`BoneheadFriend-feedback-*.zip`), or folders
## they were unzipped into — both are read, at any depth. A tester who sent twice sent a superset,
## so sessions and notes are de-duplicated by file name; the fuller copy of a session wins. Note
## pictures are copied out beside the report (`<report>_shots/`) and linked from it.
##
## The arithmetic is `tools/playtest_report_math.gd`, which the unit runner checks on fixtures.

const Math := preload("res://tools/playtest_report_math.gd")
const Fmt := preload("res://Scripts/Playtest/playtest_format.gd")

func _ready() -> void:
	# Nothing here writes preferences, and nothing ever should (D51).
	Settings.config_path = "user://settings_playtest_report.cfg"
	var args := _args()
	var folder := String(args.get("in", ""))
	var out_path := String(args.get("out", ""))
	if folder == "" or out_path == "":
		print("usage: res://tools/playtest_report.tscn -- --in=<folder of bundles> --out=<report.md> [--dead=5] [--demo]")
		get_tree().quit(2)
		return
	if args.has("demo"):
		var made := write_demo(folder)
		print("demo: wrote %d synthetic bundles to %s" % [made, folder])
	var result := build_report(folder, out_path, float(args.get("dead", "5")))
	print("report: %d testers, %d sessions, %d notes -> %s" % [result["testers"], result["sessions"],
		result["notes"], out_path])
	get_tree().quit(0 if bool(result["ok"]) else 1)

func _args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var eq := arg.find("=")
		if eq < 0:
			out[arg.substr(2)] = true
		else:
			out[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	return out

## Reads, reduces and writes. Returns counts and `ok`.
func build_report(folder: String, out_path: String, dead_minutes: float = 5.0) -> Dictionary:
	var by_tester := read_bundles(folder)
	var testers: Array = []
	var shots := {}
	var shot_dir := out_path.get_basename() + "_shots"
	var sessions := 0
	var notes := 0
	var ids := by_tester.keys()
	ids.sort()
	for id in ids:
		var entry: Dictionary = by_tester[id]
		testers.append(Math.summarize_tester(id, entry["sessions"].values(), entry["notes"].values(),
			dead_minutes))
		sessions += (entry["sessions"] as Dictionary).size()
		notes += (entry["notes"] as Dictionary).size()
		for note_id in entry["shots"]:
			var bytes: PackedByteArray = entry["shots"][note_id]
			if bytes.is_empty():
				continue
			DirAccess.make_dir_recursive_absolute(shot_dir)
			var file := FileAccess.open(shot_dir.path_join("%s.png" % note_id), FileAccess.WRITE)
			if file:
				file.store_buffer(bytes)
				file.close()
				shots[note_id] = "%s/%s.png" % [shot_dir.get_file(), note_id]
	var text := Math.render(testers, {"dead_minutes": dead_minutes, "shots": shots,
		"made_at": Time.get_datetime_string_from_system(false, true)})
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var out := FileAccess.open(out_path, FileAccess.WRITE)
	if out == null:
		push_error("playtest_report: cannot write %s" % out_path)
		return {"ok": false, "testers": testers.size(), "sessions": sessions, "notes": notes, "text": text}
	out.store_string(text)
	out.close()
	return {"ok": true, "testers": testers.size(), "sessions": sessions, "notes": notes, "text": text}

## tester id -> {"sessions": {name: summary}, "notes": {id: note}, "shots": {note id: png bytes}}.
func read_bundles(folder: String) -> Dictionary:
	var out := {}
	for path in _walk(folder):
		if path.ends_with(".zip"):
			_read_zip(path, out)
		elif path.get_file() == "manifest.json":
			_read_folder(path.get_base_dir(), out)
	return out

func _read_zip(path: String, out: Dictionary) -> void:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		push_warning("playtest_report: cannot open %s" % path)
		return
	var files := zip.get_files()
	var manifest := {}
	if files.has("manifest.json"):
		var parsed = JSON.parse_string(zip.read_file("manifest.json").get_string_from_utf8())
		if typeof(parsed) == TYPE_DICTIONARY:
			manifest = parsed
	var tester := String(manifest.get("tester", path.get_file().get_basename()))
	for name in files:
		_take(out, tester, name, zip.read_file(name))
	zip.close()

func _read_folder(dir: String, out: Dictionary) -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("manifest.json")))
	var tester := String((manifest as Dictionary).get("tester", dir.get_file())) \
		if typeof(manifest) == TYPE_DICTIONARY else dir.get_file()
	for sub in ["sessions", "feedback"]:
		var at := dir.path_join(sub)
		if not DirAccess.dir_exists_absolute(at):
			continue
		for name in DirAccess.get_files_at(at):
			_take(out, tester, "%s/%s" % [sub, name], FileAccess.get_file_as_bytes(at.path_join(name)))

func _take(out: Dictionary, tester: String, name: String, bytes: PackedByteArray) -> void:
	if not out.has(tester):
		out[tester] = {"sessions": {}, "notes": {}, "shots": {}}
	var entry: Dictionary = out[tester]
	if name.begins_with("sessions/") and name.ends_with(".jsonl"):
		var stem := name.get_file().get_basename()
		var summary := Math.summarize_session(stem, bytes.get_string_from_utf8())
		var held: Dictionary = entry["sessions"].get(stem, {})
		if held.is_empty() or int(summary["rows"]) > int(held["rows"]):
			entry["sessions"][stem] = summary
	elif name.begins_with("feedback/") and name.ends_with(".json"):
		var parsed = JSON.parse_string(bytes.get_string_from_utf8())
		if typeof(parsed) == TYPE_DICTIONARY:
			entry["notes"][String((parsed as Dictionary).get("id", name.get_file().get_basename()))] = parsed
	elif name.begins_with("feedback/") and name.ends_with(".png"):
		entry["shots"][name.get_file().get_basename()] = bytes

func _walk(dir: String) -> Array[String]:
	var out: Array[String] = []
	var access := DirAccess.open(dir)
	if access == null:
		return out
	for name in access.get_files():
		out.append(dir.path_join(name))
	for sub in access.get_directories():
		out.append_array(_walk(dir.path_join(sub)))
	return out

# --- synthetic testers ------------------------------------------------------------------------

## Three made-up testers, written as real bundles are: one who took to it, one who got stuck and
## crashed, one who never found the shop. For seeing what a report looks like before anyone has
## played, and for checking the tool end to end. Returns how many bundles it wrote.
func write_demo(folder: String) -> int:
	DirAccess.make_dir_recursive_absolute(folder)
	var picture := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	picture.fill(Color(0.99, 0.99, 0.93))
	var png := picture.save_png_to_buffer()
	var made := 0

	var ann_1 := [
		Fmt.row(0.0, "start", {"build": "2026-09-27-demo", "tester": "demo-ann", "mode": "play",
			"window": [1180, 760], "screens": [[2560, 1440]], "own": 4, "pc": 0, "lb": 0}),
		Fmt.row(20.0, "first", {"what": "item", "id": "baseball_bat", "ever": true}),
		Fmt.row(25.0, "first", {"what": "hit", "id": "baseball_bat", "ever": true}),
		Fmt.row(70.0, "first", {"what": "kind", "id": "open_hand", "ever": true}),
		Fmt.row(150.0, "buy", {"id": "tennis_ball", "cur": "bones", "p": 40}),
		Fmt.row(160.0, "page", {"id": "shop"}),
		Fmt.row(400.0, "aug", {"id": "bat_damage", "lvl": 1, "cur": "bones", "p": 60}),
		Fmt.row(600.0, "ko", {"bonus": 120, "n": 1, "s": 90}),
		Fmt.row(700.0, "first", {"what": "ability", "id": "baseball_bat", "ev": "home_run", "ever": true}),
		Fmt.row(1000.0, "gap", {"s": 420, "away": false}),
		Fmt.row(1100.0, "note", {"id": "note_demo_ann_1", "mood": "good"}),
		Fmt.row(1500.0, "end", {"why": "quit", "min": 25.0, "errs": 0}),
	]
	var ann_2 := [
		Fmt.row(0.0, "start", {"build": "2026-09-27-demo", "tester": "demo-ann", "mode": "overlay",
			"window": [2560, 1400], "own": 6, "pc": 0, "lb": 5200}),
		Fmt.row(60.0, "tick", {"aff": 1, "acts": 12, "own": 6, "lb": 5400}),
		Fmt.row(300.0, "job", {"id": "daily_hits", "d": 5}),
		Fmt.row(780.0, "end", {"why": "quit", "min": 13.0, "errs": 0}),
	]
	made += _demo_bundle(folder, "demo-ann", {"20260927-090000_demo_0001": ann_1,
		"20260928-090000_demo_0002": ann_2}, {
		"note_demo_ann_1": {"mood": "good", "text": "The home run is great. Wanted to do it again straight away.",
			"trying": "hit him over the tent", "saved_at": "2026-09-27T09:18:20", "session_minutes": 18.3,
			"context": {"page": "", "desk": ["baseball_bat", "tennis_ball"], "power": ""}},
	}, png)

	var ben := [
		Fmt.row(0.0, "start", {"build": "2026-09-27-demo", "tester": "demo-ben", "mode": "play",
			"window": [1180, 760], "own": 4}),
		Fmt.row(30.0, "first", {"what": "hit", "id": "fist", "ever": true}),
		Fmt.row(60.0, "tick", {"aff": 0, "acts": 20, "own": 4}),
		Fmt.row(120.0, "tick", {"aff": 0, "acts": 15, "own": 4}),
		Fmt.row(180.0, "tick", {"aff": 0, "acts": 9, "own": 4}),
		Fmt.row(240.0, "tick", {"aff": 0, "acts": 11, "own": 4}),
		Fmt.row(300.0, "tick", {"aff": 0, "acts": 6, "own": 4}),
		Fmt.row(330.0, "err", {"k": "error", "m": "Invalid call. Nonexistent function 'pop' in base 'Nil'.",
			"at": "bubble_wrap.gd:88"}),
		Fmt.row(360.0, "tick", {"aff": 0, "acts": 4, "own": 4}),
		Fmt.row(540.0, "buy", {"id": "tennis_ball", "cur": "bones", "p": 40}),
		Fmt.row(560.0, "note", {"id": "note_demo_ben_1", "mood": "meh"}),
		Fmt.row(700.0, "tick", {"aff": 0, "acts": 3, "own": 5}),
	]
	made += _demo_bundle(folder, "demo-ben", {"20260927-100000_demo_0003": ben}, {
		"note_demo_ben_1": {"mood": "meh", "text": "Took ages to afford anything. What are Hearts for?",
			"trying": "buy the tennis ball", "saved_at": "2026-09-27T10:09:20", "session_minutes": 9.3,
			"context": {"page": "shop", "desk": ["fist"], "power": ""}},
	}, png)

	var cat_rows := func(t_end: float, at: String) -> Array:
		return [
			Fmt.row(0.0, "start", {"build": "2026-09-26-demo", "tester": "demo-cat", "mode": "overlay",
				"window": [3440, 1400], "own": 4}),
			Fmt.row(15.0, "first", {"what": "hit", "id": "fist", "ever": at == "a"}),
			Fmt.row(40.0, "err", {"k": "error", "m": "Invalid call. Nonexistent function 'pop' in base 'Nil'.",
				"at": "bubble_wrap.gd:88"}),
			Fmt.row(t_end, "end", {"why": "quit", "errs": 1}),
		]
	made += _demo_bundle(folder, "demo-cat", {
		"20260926-200000_demo_0004": cat_rows.call(240.0, "a"),
		"20260927-200000_demo_0005": cat_rows.call(180.0, "b"),
		"20260928-200000_demo_0006": cat_rows.call(300.0, "c"),
	}, {
		"note_demo_cat_1": {"mood": "bad", "text": "I don't know where the shop is. Is there more than punching?",
			"trying": "", "saved_at": "2026-09-28T20:04:00", "session_minutes": 4.0,
			"context": {"page": "", "desk": [], "power": ""}},
	}, png)
	return made

func _demo_bundle(folder: String, tester: String, sessions: Dictionary, notes: Dictionary,
		png: PackedByteArray) -> int:
	var zip := ZIPPacker.new()
	if zip.open(folder.path_join("BoneheadFriend-feedback-%s-demo.zip" % tester)) != OK:
		return 0
	for name in sessions:
		zip.start_file("sessions/%s.jsonl" % name)
		zip.write_file(("\n".join(PackedStringArray(sessions[name])) + "\n").to_utf8_buffer())
		zip.close_file()
	for id in notes:
		var note: Dictionary = notes[id]
		note["id"] = id
		note["tester"] = tester
		note["build"] = "2026-09-27-demo"
		note["screenshot"] = "%s.png" % id
		zip.start_file("feedback/%s.json" % id)
		zip.write_file(JSON.stringify(note, "\t").to_utf8_buffer())
		zip.close_file()
		zip.start_file("feedback/%s.png" % id)
		zip.write_file(png)
		zip.close_file()
	zip.start_file("manifest.json")
	zip.write_file(JSON.stringify({"format": Fmt.FORMAT, "tester": tester, "build": "demo"}).to_utf8_buffer())
	zip.close_file()
	zip.close()
	return 1
