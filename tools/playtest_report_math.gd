extends RefCounted

## The arithmetic behind `tools/playtest_report.tscn`: session logs and feedback notes in, one
## markdown report out. Pure — no autoloads, no files — so `tests/run_tests.gd` checks it on
## fixtures, and the tool is only the part that opens zips.
##
## The rows are `PlaytestFormat`'s (`Scripts/Playtest/playtest_format.gd`); the words for them are
## here. Every figure in the report is derived from rows a session actually wrote, so a tester
## whose game crashed mid-session still counts up to the last flush.

const Fmt := preload("res://Scripts/Playtest/playtest_format.gd")

## The funnel, in the order a new player meets it. `key` is a field of a tester summary's
## `reach` (minutes of play when it first happened); `launched` is everyone with a session.
const FUNNEL := [
	["launched", "Started the game"],
	["first_hit", "Hit him"],
	["first_kind", "Was kind to him (pet, a kind toy)"],
	["first_buy", "Bought something"],
	["first_aug", "Bought an upgrade"],
	["first_ko", "Knocked him out"],
	["first_ability", "Used a weapon's ability"],
	["first_job", "Claimed a job"],
	["played_30", "Played 30 minutes"],
	["came_back", "Came back for a second session"],
	["first_rebirth", "Reincarnated"],
]

const MOODS := ["good", "meh", "bad"]

# --- one session -----------------------------------------------------------------------------

## What one session file says, as numbers. `t` in every list is seconds from that session's start.
static func summarize_session(name: String, text: String) -> Dictionary:
	var rows := Fmt.parse_rows(text)
	var out := {
		"name": name, "build": "", "at": "", "mode": "", "window": [], "screens": [],
		"minutes": 0.0, "ended": false, "why": "", "rows": rows.size(),
		"buys": [], "augs": 0, "firsts": [], "kos": 0, "rebirths": 0, "jobs": 0, "deeds": 0,
		"notes": 0, "gaps": [], "away_s": 0.0, "ticks": [], "errors": {}, "err_total": 0,
		"max_own": 0, "max_pc": 0, "max_lb": 0, "pages": {}, "first_t": {},
	}
	if rows.is_empty():
		return out
	var t0 := float(rows[0].get("t", 0.0))
	var last := t0
	var err_rows := 0
	for row in rows:
		var t := float(row.get("t", 0.0)) - t0
		last = maxf(last, float(row.get("t", 0.0)))
		match String(row.get("e", "")):
			"start":
				out["build"] = String(row.get("build", ""))
				out["at"] = String(row.get("at", ""))
				out["mode"] = String(row.get("mode", ""))
				out["window"] = row.get("window", [])
				out["screens"] = row.get("screens", [])
				out["max_own"] = maxi(int(out["max_own"]), int(row.get("own", 0)))
				out["max_pc"] = maxi(int(out["max_pc"]), int(row.get("pc", 0)))
				out["max_lb"] = maxi(int(out["max_lb"]), int(row.get("lb", 0)))
			"end":
				out["ended"] = true
				out["why"] = String(row.get("why", ""))
				out["err_total"] = int(row.get("errs", 0))
			"buy":
				if int(row.get("p", 0)) > 0:
					(out["buys"] as Array).append({"t": t, "id": String(row.get("id", "")),
						"cur": String(row.get("cur", "")), "p": int(row.get("p", 0))})
					_first_at(out, "first_buy", t)
			"aug":
				out["augs"] = int(out["augs"]) + 1
				_first_at(out, "first_aug", t)
			"first":
				var what := String(row.get("what", ""))
				(out["firsts"] as Array).append({"t": t, "what": what, "id": String(row.get("id", "")),
					"ev": String(row.get("ev", "")), "ever": bool(row.get("ever", false))})
				match what:
					"hit": _first_at(out, "first_hit", t)
					"kind": _first_at(out, "first_kind", t)
					"ability": _first_at(out, "first_ability", t)
			"ko":
				out["kos"] = int(out["kos"]) + 1
				_first_at(out, "first_ko", t)
			"rebirth":
				out["rebirths"] = int(out["rebirths"]) + 1
				out["max_pc"] = maxi(int(out["max_pc"]), int(row.get("pc", 0)))
				_first_at(out, "first_rebirth", t)
			"job":
				out["jobs"] = int(out["jobs"]) + 1
				_first_at(out, "first_job", t)
			"deed":
				out["deeds"] = int(out["deeds"]) + 1
			"note":
				out["notes"] = int(out["notes"]) + 1
			"gap":
				(out["gaps"] as Array).append({"t": t, "s": float(row.get("s", 0.0)),
					"away": bool(row.get("away", false))})
			"away":
				out["away_s"] = float(out["away_s"]) + float(row.get("s", 0.0))
			"tick":
				(out["ticks"] as Array).append({"t": t, "aff": int(row.get("aff", 0)),
					"acts": int(row.get("acts", 0)), "next": String(row.get("next", "")),
					"nr": float(row.get("nr", 0.0))})
				out["max_own"] = maxi(int(out["max_own"]), int(row.get("own", 0)))
				out["max_pc"] = maxi(int(out["max_pc"]), int(row.get("pc", 0)))
				out["max_lb"] = maxi(int(out["max_lb"]), int(row.get("lb", 0)))
			"err":
				err_rows += 1
				var message := String(row.get("m", ""))
				if not (out["errors"] as Dictionary).has(message):
					out["errors"][message] = {"k": String(row.get("k", "")), "at": String(row.get("at", ""))}
			"page":
				var page := String(row.get("id", ""))
				if page != "":
					out["pages"][page] = int((out["pages"] as Dictionary).get(page, 0)) + 1
	out["minutes"] = (last - t0) / 60.0
	# A session that never said goodbye still says how many errors it saw on the way.
	out["err_total"] = maxi(int(out["err_total"]), err_rows)
	return out

static func _first_at(out: Dictionary, key: String, t: float) -> void:
	if not (out["first_t"] as Dictionary).has(key):
		out["first_t"][key] = t

## The longest run of minute rows in which nothing was affordable **while the player was there**
## (clicked at least once that minute) — the M3 gate's dead end, in minutes. Also how many such
## runs reached `at_least` minutes.
static func dry_stretches(ticks: Array, at_least: float) -> Dictionary:
	var longest := 0
	var count := 0
	var run := 0
	for tick in ticks:
		if int(tick["aff"]) == 0 and int(tick["acts"]) > 0:
			run += 1
			longest = maxi(longest, run)
		else:
			if run >= at_least:
				count += 1
			run = 0
	if run >= at_least:
		count += 1
	return {"longest": longest, "count": count}

# --- one tester --------------------------------------------------------------------------------

## Every session of one tester, oldest first, as one story told in minutes of play.
static func summarize_tester(tester: String, sessions: Array, notes: Array, dead_minutes: float) -> Dictionary:
	var ordered := sessions.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["name"]) < String(b["name"]))
	var reach := {}
	var offset := 0.0
	var abilities := {}
	var powers := {}
	var items := {}
	var dead: Array = []
	var dry_longest := 0
	var dry_count := 0
	var errors := {}
	var builds := {}
	var crashes := 0
	var buys := 0
	var max_own := 0
	var max_pc := 0
	var max_lb := 0
	var windows := {}
	for i in ordered.size():
		var s: Dictionary = ordered[i]
		if s["build"] != "":
			builds[s["build"]] = true
		if s["mode"] != "":
			windows["%s %s" % [s["mode"], _size_text(s["window"])]] = true
		if i == 0:
			reach["launched"] = 0.0
		if i == 1:
			reach["came_back"] = offset
		for key in s["first_t"]:
			if not reach.has(key):
				reach[key] = offset + float(s["first_t"][key]) / 60.0
		for first in s["firsts"]:
			match String(first["what"]):
				"ability": abilities[first["id"]] = true
				"power": powers[first["id"]] = true
				"item": items[first["id"]] = true
		for gap in s["gaps"]:
			if not bool(gap["away"]) and float(gap["s"]) >= dead_minutes * 60.0:
				dead.append({"session": s["name"], "at_min": offset + float(gap["t"]) / 60.0,
					"minutes": float(gap["s"]) / 60.0})
		var dry := dry_stretches(s["ticks"], dead_minutes)
		dry_longest = maxi(dry_longest, int(dry["longest"]))
		dry_count += int(dry["count"])
		for message in s["errors"]:
			if not errors.has(message):
				errors[message] = {"k": s["errors"][message]["k"], "at": s["errors"][message]["at"], "sessions": 0}
			errors[message]["sessions"] = int(errors[message]["sessions"]) + 1
		if not bool(s["ended"]):
			crashes += 1
		buys += (s["buys"] as Array).size()
		max_own = maxi(max_own, int(s["max_own"]))
		max_pc = maxi(max_pc, int(s["max_pc"]))
		max_lb = maxi(max_lb, int(s["max_lb"]))
		offset += float(s["minutes"])
		if not reach.has("played_30") and offset >= 30.0:
			reach["played_30"] = 30.0
	var moods := {}
	for note in notes:
		var mood := String(note.get("mood", ""))
		moods[mood] = int(moods.get(mood, 0)) + 1
	return {
		"tester": tester, "sessions": ordered.size(), "minutes": offset, "reach": reach,
		"abilities": abilities.keys(), "powers": powers.keys(), "items": items.keys(),
		"dead": dead, "dry_longest": dry_longest, "dry_count": dry_count,
		"errors": errors, "builds": builds.keys(), "crashes": crashes, "buys": buys,
		"max_own": max_own, "max_pc": max_pc, "max_lb": max_lb, "notes": notes, "moods": moods,
		"windows": windows.keys(),
	}

static func _size_text(size) -> String:
	if typeof(size) == TYPE_ARRAY and (size as Array).size() == 2:
		return "%dx%d" % [int(size[0]), int(size[1])]
	return "?"

# --- across testers -----------------------------------------------------------------------------

## How many testers reached each step, and the median minutes of play it took them.
static func funnel(testers: Array) -> Array:
	var out: Array = []
	for step in FUNNEL:
		var times: Array = []
		for tester in testers:
			if (tester["reach"] as Dictionary).has(step[0]):
				times.append(float(tester["reach"][step[0]]))
		out.append({"key": step[0], "label": step[1], "reached": times.size(),
			"of": testers.size(), "median": median(times) if not times.is_empty() else -1.0})
	return out

## Errors by how many testers met them, then how many sessions.
static func common_errors(testers: Array) -> Array:
	var merged := {}
	for tester in testers:
		for message in tester["errors"]:
			var entry: Dictionary = tester["errors"][message]
			if not merged.has(message):
				merged[message] = {"message": message, "k": entry["k"], "at": entry["at"], "testers": 0, "sessions": 0}
			merged[message]["testers"] = int(merged[message]["testers"]) + 1
			merged[message]["sessions"] = int(merged[message]["sessions"]) + int(entry["sessions"])
	var out := merged.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["testers"]) != int(b["testers"]):
			return int(a["testers"]) > int(b["testers"])
		if int(a["sessions"]) != int(b["sessions"]):
			return int(a["sessions"]) > int(b["sessions"])
		return String(a["message"]) < String(b["message"]))
	return out

## Every note, grouped by the page that was open when it was written (`desk` when none was), each
## group with its moods counted. Newest first inside a group.
static func group_notes(testers: Array) -> Dictionary:
	var groups := {}
	for tester in testers:
		for note in tester["notes"]:
			var context: Dictionary = note.get("context", {})
			var page := String(context.get("page", ""))
			if page == "" or page == "feedback":
				page = "desk"
			if not groups.has(page):
				groups[page] = {"notes": [], "moods": {}}
			(groups[page]["notes"] as Array).append(note)
			var mood := String(note.get("mood", ""))
			groups[page]["moods"][mood] = int((groups[page]["moods"] as Dictionary).get(mood, 0)) + 1
	for page in groups:
		(groups[page]["notes"] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("saved_at", "")) > String(b.get("saved_at", "")))
	return groups

## Which items were in the player's hands or on the desk when notes were written, and in what mood.
static func notes_by_item(testers: Array) -> Dictionary:
	var out := {}
	for tester in testers:
		for note in tester["notes"]:
			var context: Dictionary = note.get("context", {})
			var seen := {}
			for id in context.get("desk", []):
				seen[String(id)] = true
			if String(context.get("power", "")) != "":
				seen[String(context["power"])] = true
			for id in seen:
				if not out.has(id):
					out[id] = {"notes": 0, "moods": {}}
				out[id]["notes"] = int(out[id]["notes"]) + 1
				var mood := String(note.get("mood", ""))
				out[id]["moods"][mood] = int((out[id]["moods"] as Dictionary).get(mood, 0)) + 1
	return out

static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var mid := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return float(sorted[mid])
	return (float(sorted[mid - 1]) + float(sorted[mid])) / 2.0

static func minutes_text(minutes: float) -> String:
	if minutes < 0.0:
		return "—"
	if minutes < 1.0:
		return "%d s" % roundi(minutes * 60.0)
	if minutes < 120.0:
		return "%.1f min" % minutes
	return "%.1f h" % (minutes / 60.0)

static func _moods_text(moods: Dictionary) -> String:
	var parts: Array[String] = []
	for mood in MOODS:
		if int(moods.get(mood, 0)) > 0:
			parts.append("%d %s" % [int(moods[mood]), mood])
	if int(moods.get("", 0)) > 0:
		parts.append("%d unrated" % int(moods[""]))
	return ", ".join(parts) if not parts.is_empty() else "—"

static func _cell(text: String) -> String:
	return text.replace("|", "\\|").replace("\r", " ").replace("\n", " ").strip_edges()

# --- the report ---------------------------------------------------------------------------------

## `options`: `title`, `dead_minutes`, `shots` (note id -> relative path of its picture), `made_at`.
static func render(testers: Array, options: Dictionary = {}) -> String:
	var dead_minutes := float(options.get("dead_minutes", 5.0))
	var shots: Dictionary = options.get("shots", {})
	var lines: Array[String] = []
	lines.append("# %s" % String(options.get("title", "Bonehead Friend — playtest report")))
	lines.append("")
	var total_sessions := 0
	var total_minutes := 0.0
	var total_notes := 0
	var builds := {}
	for tester in testers:
		total_sessions += int(tester["sessions"])
		total_minutes += float(tester["minutes"])
		total_notes += (tester["notes"] as Array).size()
		for build in tester["builds"]:
			builds[build] = true
	lines.append("%d testers · %d sessions · %s of play · %d notes · builds %s" % [testers.size(),
		total_sessions, minutes_text(total_minutes), total_notes,
		", ".join(PackedStringArray(builds.keys())) if not builds.is_empty() else "—"])
	if options.has("made_at"):
		lines.append("")
		lines.append("Made %s. A dead stretch is %d+ minutes with the window focused and no click; a dry stretch is %d+ minutes of play with nothing affordable." % [
			String(options["made_at"]), roundi(dead_minutes), roundi(dead_minutes)])
	lines.append("")

	lines.append("## The funnel")
	lines.append("")
	lines.append("| Step | Testers | Share | Median time to reach |")
	lines.append("|---|---:|---:|---:|")
	for row in funnel(testers):
		var share := 0.0 if int(row["of"]) == 0 else 100.0 * float(row["reached"]) / float(row["of"])
		lines.append("| %s | %d / %d | %d%% | %s |" % [row["label"], int(row["reached"]), int(row["of"]),
			roundi(share), minutes_text(float(row["median"])) if int(row["reached"]) > 0 else "—"])
	lines.append("")

	lines.append("## Per tester")
	lines.append("")
	lines.append("| Tester | Sessions | Played | Furthest | First purchase | Abilities found | Dead stretches | Longest dry | Errors | Crashes | Notes |")
	lines.append("|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---|")
	for tester in testers:
		var reach: Dictionary = tester["reach"]
		var longest_dead := 0.0
		for stretch in tester["dead"]:
			longest_dead = maxf(longest_dead, float(stretch["minutes"]))
		var dead_text := "0"
		if not (tester["dead"] as Array).is_empty():
			dead_text = "%d (longest %s)" % [(tester["dead"] as Array).size(), minutes_text(longest_dead)]
		lines.append("| %s | %d | %s | %d toys · %d rebirths · %s Bones | %s | %d | %s | %s | %d | %d | %s |" % [
			tester["tester"], int(tester["sessions"]), minutes_text(float(tester["minutes"])),
			int(tester["max_own"]), int(tester["max_pc"]), _big(int(tester["max_lb"])),
			minutes_text(float(reach.get("first_buy", -1.0))), (tester["abilities"] as Array).size(),
			dead_text, "%d min" % int(tester["dry_longest"]) if int(tester["dry_longest"]) > 0 else "0",
			(tester["errors"] as Dictionary).size(), int(tester["crashes"]),
			_moods_text(tester["moods"])])
	lines.append("")
	for tester in testers:
		lines.append("**%s** — builds %s; windows %s; abilities: %s; cursor powers: %s." % [
			tester["tester"], ", ".join(PackedStringArray(tester["builds"])),
			", ".join(PackedStringArray(tester["windows"])),
			", ".join(PackedStringArray(tester["abilities"])) if not (tester["abilities"] as Array).is_empty() else "none",
			", ".join(PackedStringArray(tester["powers"])) if not (tester["powers"] as Array).is_empty() else "none"])
		for stretch in tester["dead"]:
			lines.append("- dead stretch of %s at %s of play" % [minutes_text(float(stretch["minutes"])),
				minutes_text(float(stretch["at_min"]))])
		lines.append("")

	lines.append("## Feedback notes, by page")
	lines.append("")
	var groups := group_notes(testers)
	if groups.is_empty():
		lines.append("No notes yet.")
		lines.append("")
	var pages := groups.keys()
	pages.sort()
	for page in pages:
		var group: Dictionary = groups[page]
		var count := (group["notes"] as Array).size()
		lines.append("### %s — %d note%s (%s)" % [page, count, "" if count == 1 else "s",
			_moods_text(group["moods"])])
		lines.append("")
		for note in group["notes"]:
			var context: Dictionary = note.get("context", {})
			var mood := String(note.get("mood", ""))
			var text := _cell(String(note.get("text", "")))
			var head := "- **%s** %s" % [mood if mood != "" else "unrated", ("“%s”" % text) if text != "" else "(no words)"]
			lines.append(head)
			if String(note.get("trying", "")) != "":
				lines.append("  - trying to: %s" % _cell(String(note["trying"])))
			var desk: Array = context.get("desk", [])
			var power := String(context.get("power", ""))
			lines.append("  - %s · build %s · %s into the session · desk: %s%s" % [note.get("tester", "?"),
				note.get("build", "?"), minutes_text(float(note.get("session_minutes", 0.0))),
				", ".join(PackedStringArray(desk)) if not desk.is_empty() else "empty",
				(" · holding %s" % power) if power != "" else ""])
			var shot := String(shots.get(String(note.get("id", "")), ""))
			if shot != "":
				lines.append("  - [picture](%s)" % shot)
		lines.append("")

	var by_item := notes_by_item(testers)
	if not by_item.is_empty():
		lines.append("## Items on the desk when notes were written")
		lines.append("")
		lines.append("| Item | Notes | Moods |")
		lines.append("|---|---:|---|")
		var ids := by_item.keys()
		ids.sort_custom(func(a, b) -> bool:
			if int(by_item[a]["notes"]) != int(by_item[b]["notes"]):
				return int(by_item[a]["notes"]) > int(by_item[b]["notes"])
			return String(a) < String(b))
		for id in ids:
			lines.append("| %s | %d | %s |" % [id, int(by_item[id]["notes"]), _moods_text(by_item[id]["moods"])])
		lines.append("")

	lines.append("## Most common errors")
	lines.append("")
	var errors := common_errors(testers)
	if errors.is_empty():
		lines.append("None recorded.")
	else:
		lines.append("| Testers | Sessions | Kind | Where | Message |")
		lines.append("|---:|---:|---|---|---|")
		for entry in errors.slice(0, 15):
			lines.append("| %d | %d | %s | %s | %s |" % [int(entry["testers"]), int(entry["sessions"]),
				entry["k"], _cell(String(entry["at"])), _cell(String(entry["message"])).left(160)])
	lines.append("")
	return "\n".join(lines)

static func _big(value: int) -> String:
	if value >= 1_000_000_000:
		return "%.1fB" % (value / 1.0e9)
	if value >= 1_000_000:
		return "%.1fM" % (value / 1.0e6)
	if value >= 10_000:
		return "%.1fK" % (value / 1.0e3)
	return str(value)
