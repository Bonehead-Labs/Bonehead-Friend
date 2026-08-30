#!/usr/bin/env python3
"""Assert an exported .pck actually contains the game's runtime content.

    Godot --headless --path <project> --export-pack "Windows Desktop" <out.pck>
    python3 tools/pack_check.py <out.pck>

Every build produced before M3.5-0 shipped without the buddy animation and the explosion:
`export_presets.cfg` excluded `art/*` while `buddy_art.gd` and `Explosion.tscn` load from
`res://art/src/`. Nothing caught it, because the editor resolves those paths perfectly and
the test suites all run against the project rather than against a pack.

So this reads the pack's own file table and checks for what the game loads at runtime:
every `res://` path a script names, every `.tres` under `Data/`, every sprite under
`Assets/sprites/`, and — the case that actually shipped — the *imported* resource behind
each `.aseprite` source, which is a different file in a different directory from the path
the script asks for.

Exits non-zero with the missing paths listed. Paths are compared case-sensitively on
purpose: `res://` lookups are case-sensitive in an exported build and are not in the
editor, which is the other half of the same bug (CLAUDE.md, hard rule 1).
"""

import re
import struct
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent


def read_pack(pck: Path) -> set[str]:
	"""File table of a Godot .pck, as `res://` paths.

	Pack format 4 (Godot 4.7) keeps the header at the front but the *directory* at the end,
	so the table is found through the offset at 0x20 rather than by reading on past the
	header — reading on lands on 64 bytes of reserved zeroes and reports an empty pack,
	which is indistinguishable from a build that shipped nothing.
	"""
	data = pck.read_bytes()
	if data[:4] != b"GDPC":
		raise SystemExit(f"{pck}: not a Godot pack (magic {data[:4]!r})")
	(version,) = struct.unpack_from("<I", data, 4)
	if version < 2:
		raise SystemExit(f"{pck}: pack format {version} predates this checker")
	(flags,) = struct.unpack_from("<I", data, 0x14)
	if flags & 1:
		raise SystemExit(f"{pck}: directory is encrypted; nothing to check")

	if version >= 4:
		(pos,) = struct.unpack_from("<Q", data, 0x20)
	else:
		pos = 0x20 + 16 * 4
	(count,) = struct.unpack_from("<I", data, pos); pos += 4

	paths: set[str] = set()
	for _ in range(count):
		(length,) = struct.unpack_from("<I", data, pos); pos += 4
		raw = data[pos:pos + length]; pos += length
		# Stored without the res:// prefix in format 4, with it before that.
		paths.add("res://" + raw.rstrip(b"\0").decode("utf-8").removeprefix("res://"))
		pos += 8 + 8 + 16  # offset, size, md5
		if version >= 2:
			pos += 4  # flags
	return paths


def imported_for(source: Path) -> list[str]:
	"""The generated resources a `.import` file points at.

	An `.aseprite` or a `.png` in the pack is inert on its own — what `load()` actually
	reaches is the `res://.godot/imported/<name>-<hash>.<ext>` its `.import` names.
	"""
	marker = source.with_suffix(source.suffix + ".import")
	if not marker.exists():
		return []
	found = re.findall(r'"?(res://\.godot/imported/[^"\n]+)"?', marker.read_text(encoding="utf-8"))
	return list(dict.fromkeys(found))


def missing_forms(path: str, packed: set[str]) -> list[str]:
	"""Why `path` is not reachable in this pack, or [] if it is.

	A source path is almost never stored verbatim. A `.tres`, `.tscn` or `.gd` becomes a
	`.remap` pointing at a binary conversion; an imported asset becomes its `.import` plus
	the generated file in `.godot/imported/`. Accepting only the literal path reports a
	perfectly good pack as empty, which is a check nobody would trust twice.
	"""
	if path in packed or path + ".remap" in packed:
		return []
	on_disk = PROJECT / path.removeprefix("res://")
	generated = imported_for(on_disk)
	if generated:
		absent = [g for g in generated if g not in packed]
		if path + ".import" not in packed:
			absent.append(path + ".import")
		return absent
	return [path]


def required() -> dict[str, str]:
	"""{res:// path: why it has to be there}. Directories are skipped — ItemDB scans them,
	but what has to survive the export is the content inside."""
	want: dict[str, str] = {}

	def add(path: str, why: str) -> None:
		on_disk = PROJECT / path.removeprefix("res://")
		if on_disk.is_file():
			want.setdefault(path, why)

	# Every res:// literal in shipping code.
	for gd in sorted((PROJECT / "Scripts").rglob("*.gd")):
		for path in re.findall(r'"(res://[^"]+)"', gd.read_text(encoding="utf-8")):
			add(path, f"named by {gd.relative_to(PROJECT)}")

	# Content is data (D8): a missing .tres is a missing item, augment or contract.
	for tres in sorted((PROJECT / "Data").rglob("*.tres")):
		add("res://" + tres.relative_to(PROJECT).as_posix(), "game content")

	# Art is referenced from .tres and .tscn rather than from code, so the sweep above
	# never sees it. The scenes' own sprites come with them; these are the loose ones.
	for png in sorted((PROJECT / "Assets" / "sprites").rglob("*.png")):
		add("res://" + png.relative_to(PROJECT).as_posix(), "art")

	# Every ext_resource a shipping scene or resource depends on. This is how the explosion
	# is caught: nothing in Scripts/ names `res://art/src/explosion.aseprite` — it is an
	# ext_resource of Explosion.tscn, and an export that drops it leaves the game with an
	# explosion that has no animation and no error until it goes off.
	scenes = list((PROJECT / "Scenes").rglob("*.tscn")) + [PROJECT / "main.tscn"]
	for source in sorted(scenes) + sorted((PROJECT / "Data").rglob("*.tres")):
		if not source.is_file():
			continue
		text = source.read_text(encoding="utf-8", errors="replace")
		for path in re.findall(r'path="(res://[^"]+)"', text):
			add(path, f"ext_resource of {source.relative_to(PROJECT)}")

	return want


def main() -> int:
	if len(sys.argv) != 2:
		print(__doc__)
		return 2
	pack = Path(sys.argv[1])
	packed = read_pack(pack)
	want = required()

	failures: dict[str, tuple[str, list[str]]] = {}
	for path, why in want.items():
		absent = missing_forms(path, packed)
		if absent:
			failures[path] = (why, absent)

	print(f"pack:     {pack}")
	print(f"files:    {len(packed)}")
	print(f"required: {len(want)}")
	if failures:
		print(f"MISSING:  {len(failures)}")
		for path, (why, absent) in sorted(failures.items()):
			print(f"  {path}  ({why})")
			for form in absent:
				print(f"      no {form}")
		return 1
	print("ok — every runtime resource is in the pack")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
