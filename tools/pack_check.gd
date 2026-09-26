extends SceneTree

## Does an export contain the game's art? The Windows twin of `tools/pack_check.py`, for the
## machine the builds are made on, which has no Python (the Store stub answers instead).
##
##   Godot --headless --path <project> -s res://tools/pack_check.gd -- <game.exe | pack.pck>
##
## Same rules as the Python: every `res://` literal in shipping code, every `.tres` under `Data/`,
## every sprite under `Assets/sprites/`, every `ext_resource` of a shipping scene — and, the case
## that shipped once, the *imported* file behind each source, which is a different path. Compared
## case-sensitively, because an exported build is (CLAUDE.md, hard rule 1).
##
## It also reads a pack **embedded in the exe**, which is what the preset builds
## (`binary_format/embed_pck`): the trailer is the pack's size and its magic, so the pack starts
## that many bytes before them. `tools/make_playtest_build.ps1` runs this on the exe it is about
## to zip, so a build that lost its art never reaches a tester.
##
## `--require=res://path` adds a path that must be there — the build script uses it for the
## build stamp, which is the one runtime file no script literal names while it is absent.

const MAGIC := 0x43504447  # "GDPC"

func _initialize() -> void:
	var target := ""
	var extra: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--require="):
			extra.append(arg.trim_prefix("--require="))
		elif not arg.begins_with("--"):
			target = arg
	if target == "":
		print("usage: -s res://tools/pack_check.gd -- <game.exe | pack.pck> [--require=res://...]")
		quit(2)
		return
	var packed := read_pack(target)
	if packed.is_empty():
		print("MISSING:  no readable pack in %s" % target)
		quit(1)
		return
	var want := required()
	for path in extra:
		want[path] = "asked for on the command line"

	var failures := {}
	for path in want:
		var absent := missing_forms(path, packed)
		if not absent.is_empty():
			failures[path] = [want[path], absent]

	print("pack:     %s" % target)
	print("files:    %d" % packed.size())
	print("required: %d" % want.size())
	if not failures.is_empty():
		print("MISSING:  %d" % failures.size())
		var keys := failures.keys()
		keys.sort()
		for path in keys:
			print("  %s  (%s)" % [path, failures[path][0]])
			for form in failures[path][1]:
				print("      no %s" % form)
		quit(1)
		return
	print("ok — every runtime resource is in the pack")
	quit(0)

## The pack's file table as a set of `res://` paths, from a `.pck` or from an exe that embeds one.
func read_pack(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var start := 0
	if f.get_32() != MAGIC:
		var length := f.get_length()
		if length < 16:
			return {}
		f.seek(length - 4)
		if f.get_32() != MAGIC:
			return {}
		f.seek(length - 12)
		var size := f.get_64()
		start = length - 12 - size
		if start < 0:
			return {}
		f.seek(start)
		if f.get_32() != MAGIC:
			return {}
	var version := f.get_32()
	if version < 2:
		print("pack format %d predates this checker" % version)
		return {}
	f.get_32()  # engine major
	f.get_32()  # minor
	f.get_32()  # patch
	var flags := f.get_32()
	if flags & 1:
		print("the pack's directory is encrypted; nothing to check")
		return {}
	var table := 0
	if version >= 4:
		# Format 4 keeps the directory at the end and its offset at 0x20, from the pack's start.
		f.seek(start + 0x20)
		table = start + f.get_64()
	else:
		table = start + 0x20 + 16 * 4
	f.seek(table)
	var count := f.get_32()
	if count <= 0 or count > 1_000_000:
		return {}
	var out := {}
	for i in count:
		var name_length := f.get_32()
		var raw := f.get_buffer(name_length)
		var name := raw.get_string_from_utf8().trim_prefix("res://")
		out["res://" + name] = true
		f.get_64()          # offset
		f.get_64()          # size
		f.get_buffer(16)    # md5
		f.get_32()          # flags
	f.close()
	return out

## {res:// path: why it has to be there}.
func required() -> Dictionary:
	var want := {}
	var literal := RegEx.create_from_string("\"(res://[^\"]+)\"")
	var ext := RegEx.create_from_string("path=\"(res://[^\"]+)\"")
	for gd in _walk("res://Scripts", ".gd"):
		for m in literal.search_all(FileAccess.get_file_as_string(gd)):
			_add(want, m.get_string(1), "named by %s" % gd)
	for tres in _walk("res://Data", ".tres"):
		_add(want, tres, "game content")
	for png in _walk("res://Assets/sprites", ".png"):
		_add(want, png, "art")
	var sources: Array[String] = _walk("res://Scenes", ".tscn")
	sources.append("res://main.tscn")
	sources.append_array(_walk("res://Data", ".tres"))
	for source in sources:
		if not FileAccess.file_exists(source):
			continue
		for m in ext.search_all(FileAccess.get_file_as_string(source)):
			_add(want, m.get_string(1), "ext_resource of %s" % source)
	return want

func _add(want: Dictionary, path: String, why: String) -> void:
	if FileAccess.file_exists(path) and not want.has(path):
		want[path] = why

## Why `path` is not reachable in this pack, or [] if it is. A script or scene is stored as a
## `.remap` to its binary form; an imported asset as its `.import` plus the generated file.
func missing_forms(path: String, packed: Dictionary) -> Array[String]:
	var absent: Array[String] = []
	if packed.has(path) or packed.has(path + ".remap"):
		return absent
	var generated := _imported_for(path)
	if generated.is_empty():
		absent.append(path)
		return absent
	for form in generated:
		if not packed.has(form):
			absent.append(form)
	if not packed.has(path + ".import"):
		absent.append(path + ".import")
	return absent

func _imported_for(path: String) -> Array[String]:
	var out: Array[String] = []
	var marker := path + ".import"
	if not FileAccess.file_exists(marker):
		return out
	var re := RegEx.create_from_string("(res://\\.godot/imported/[^\"\\n]+)")
	for m in re.search_all(FileAccess.get_file_as_string(marker)):
		if not out.has(m.get_string(1)):
			out.append(m.get_string(1))
	return out

func _walk(dir: String, suffix: String) -> Array[String]:
	var out: Array[String] = []
	var access := DirAccess.open(dir)
	if access == null:
		return out
	for name in access.get_files():
		if name.ends_with(suffix):
			out.append(dir.path_join(name))
	for sub in access.get_directories():
		out.append_array(_walk(dir.path_join(sub), suffix))
	out.sort()
	return out
