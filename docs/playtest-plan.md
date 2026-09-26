# Playtest plan

How to get Bonehead Friend in front of people, in three rounds that use the same kit: first your
partner, then 5–10 friends, then 20–100 strangers. It closes the two open gates in
[roadmap.md](roadmap.md):

- **M2 — the five-minute cold start.** A non-developer plays five minutes with no instruction.
  Do they hit him, earn, and buy something without being told?
- **M3 — thirty minutes with no dead ends.** Never more than ~5 minutes from the next affordable
  thing; the knockout repeated on purpose; both currencies understood by a fresh player.

Everything below is written to be run by you, from this checkout, without an agent.

---

## The kit

| Step | Command or place | What happens |
|---|---|---|
| Make a build | `powershell -ExecutionPolicy Bypass -File tools\make_playtest_build.ps1` | Stamps a build id (`2026-09-27-e76d64f`, `-dirty` if uncommitted changes), exports release headless, checks the exe contains its art, zips it with `README-PLAYTEST.txt`. Prints the zip's path: `Desktop\Bonehead Friend playtest\BoneheadFriend-<id>.zip`. |
| Leave a note | **F1** anywhere, *Settings › Playtest › Leave a note*, or *Esc › Feedback* | Good / Meh / Bad, a free-text box, "what were you trying to do?". Attached by the game: build, session minutes, currencies, owned items, the desk, the open page, his mood, the last 40 events, errors, and a picture of the window taken before the card appeared. One JSON per note, its PNG beside it. |
| The session log | automatic in a playtest build | One compact JSON-lines file per session: start/end, window and monitor, purchases with price and time, first use of every item, power and ability, pages opened, knockouts, jobs, Reincarnation, idle gaps and time away, a minute-by-minute purse with "how many things are affordable", and every engine error. Flushed every 30 s, capped at 60 sessions / 8 MB. Switchable in *Settings › Playtest*. |
| Send it back | *Settings › Playtest › Send feedback* | One zip on the tester's Desktop, shown in Explorer. They send it however they like. With an uploader configured, it is posted instead, and retried next launch if it fails. |
| Read it | `"$GODOT" --headless --path "$PROJ" res://tools/playtest_report.tscn -- --in=<folder of zips> --out=<report.md>` | One markdown report: the funnel, a row per tester, every note grouped by page with its picture, items on the desk when notes were written, the most common errors. `-- --demo` first writes three made-up testers so you can see the format. |

The build id is on *Settings › Playtest › Build*, on the F3 overlay, and in every note and session.

**Each build keeps its own save.** The zip carries an `override.cfg` that puts saves, settings
and logs in `%APPDATA%\Bonehead Friend Playtest` — never your development save, which is where
the editor's copy lives. Pass `-UserDirName "Bonehead Friend Playtest - Anna"` to give two people
on one PC their own. To reset a machine for a fresh cold start, delete that folder.

---

## Round 0 — your partner

On **her** PC if she has one (the real test: a stranger's monitor, a stranger's desktop, the
SmartScreen warning). On yours, quit your own copy first so there is one skeleton on screen.

Make the build, copy the zip, unzip it, and **do not launch it** — the first launch is the test.

### A. The five-minute cold start (M2 gate)

Have: a phone timer, this page, and something to write on. Sit beside and slightly behind.

Say exactly this, then start the timer:

> "This is a game that lives on your desktop while you work. I'm testing the game, not you. Please
> think out loud — what you're looking at, what you expect to happen. For five minutes I won't
> answer anything; that's the test, not me being rude. Double-click it whenever you're ready."

Then **do not help, point, or nod.** If she asks, say "what would you try?". Write down, with the
time on the timer:

| Watch for | Write |
|---|---|
| First click on him; first hit; first Bones number | mm:ss each |
| First time the tab strip is opened, and which tab | mm:ss, tab |
| First purchase | mm:ss, what |
| First pet / first Hearts | mm:ss |
| Every pause over ~5 s | mm:ss, where the cursor was |
| Every "what does this do?" / "where's…?" | the words |
| Anything she tries that does nothing | what, where |

**Pass:** inside five minutes, unprompted, she hits him, sees Bones, *and* buys something. Her
session log says the same thing in seconds (`first` hit, first `buy`) — use it to check your
stopwatch, not to replace it.

Afterwards, three questions, in this order, before you explain anything:

1. "What do you think you're supposed to do?"
2. "What were the numbers going up?"
3. "Was there a moment you didn't know what to do? What were you looking at?"

### B. The free 30 minutes (M3 gate)

Straight on from A, same save. Say:

> "Now play however you like for half an hour. Whenever something's fun, confusing or broken, press
> F1 and leave a note — as many as you want, short is fine. I can answer questions now."

Go and do something else in the room. Every question she asks, write down with the time: each
one is a hole in the game.

**Pass:** the report's *Longest dry* for this session is ≤ 5 min (nothing affordable while she was
clicking); she knocks him out more than once and says or shows it was on purpose; she can answer
Q2 of the questionnaire correctly for both currencies.

Then the [questionnaire](#questionnaire), then *Settings › Playtest › Send feedback*.

### C. Take-home, a day or two

Leave it running on her machine while she works. Ask for two things only: an F1 note whenever it
annoys or delights her, and *Send feedback* at the end. Tell her closing it is fine — note whether
she opens it again, because the log will.

What you learn here and nowhere else: does it come back to life after sleep, does it get in the way
of work, does she return to it (sessions ≥ 2), how long the gaps are (`away` vs `gap`), crashes
(a session with no end), and what the minute rows say about the long game.

Debrief: the questionnaire again, plus "when did you last look at it, and why?".

---

## Round 1 — 5 to 10 friends

**Set up:** one build (`make_playtest_build.ps1`), the zip shared by Drive/Dropbox/a Discord
message. The README covers unzipping and SmartScreen ("More info › Run anyway"; the exe is not
signed). Optional: turn on the uploader (below) with a Discord webhook into a private channel, so
nobody has to email a zip.

**Ask each person for:** one sitting of about 30 minutes in their first day, leaving it running a
day or two after if they like, F1 notes, then *Send feedback* (or nothing, with the uploader).
Send the [questionnaire](#questionnaire) as a form afterwards.

**Collect:** every returned zip into one folder, e.g. `Desktop\playtest-round1\`, as they arrive —
duplicates and repeat sends are fine, the report de-duplicates. Run the report after each batch.

**Pass (both gates, at scale):**

| Gate | Pass |
|---|---|
| M2 | ≥ 80% reach *Bought something* with a median under 5 min; ≥ 80% reach *Hit him* in under 1 min |
| M3 | median *Longest dry* ≤ 5 min and nobody over 8; ≥ 60% reach *Knocked him out*; ≥ 60% reach *Was kind to him* without being told |
| Stability | no crash (session without an end) that you cannot explain; every error seen by 2+ testers triaged |

---

## Round 2 — 20 to 100 strangers

At this size people will not email zips: **use the uploader, with `-AutoUpload`** so each quit
queues the log and the next launch sends it. Say so on the download page and in the README (the
build script writes the README to match).

**Distribution — itch.io (now):** a *restricted* project (Visibility: Restricted, access by secret
URL or password), the zip uploaded as the Windows download, the README text pasted into the page.
No payment set-up needed. Recruit from a Discord, a subreddit that allows playtest calls, or a
mailing list; say "Windows 10/11, 30 minutes, desktop overlay".

**Distribution — Steam Playtest (once Steamworks exists):** needs the Steamworks partner account
and app fee, the app's store-page basics, a *Playtest* app created from the main app, a depot and a
SteamPipe upload of the build folder (the unzipped stage folder from the build script), and the
sign-up button enabled with a cap on testers. Steam handles distribution and updates; the uploader
still carries feedback, since Steam Playtest has no feedback channel of its own.

**Measure:** the funnel as percentages; *Came back for a second session* (the day-one return);
median minutes played; crash rate by GPU and Windows version (both are in every `start` row — open
the session files); the error table; notes by page.

---

## What to measure, by round

| | Round 0 | Round 1 | Round 2 |
|---|---|---|---|
| Watched in person | 5-min cold start, 30 min | — | — |
| Funnel & first-purchase time | from the log, checked against your notes | report | report |
| Dead / dry stretches | report | report | report |
| Notes by page / item | read every one | read every one | read by page, sample within |
| Errors & crashes | every one | every one | by frequency |
| Questionnaire | spoken | form | form (optional) |
| Decides | M2 gate, the obvious fixes | M2 + M3 gates | what to fix before M4 |

---

## Questionnaire

Ask what they did and felt, not whether they liked it. Seven questions; keep them in this order.

1. In one sentence: what do you do in this game?
2. What were Bones for, and what were Hearts for? ("Not sure" is a useful answer.)
3. What was the last thing you bought, and why that one?
4. Was there a moment you didn't know what to do next? What were you looking at?
5. What did you do most — and was that because you wanted to, or because nothing else was available?
6. While it was sitting on your desktop, when did you last look at it, and what made you look?
7. What made you stop playing (or, if you're still playing, what keeps you)?

---

## From reports to a triaged list

After each batch: run the report, then keep **one table** in `docs/playtest-triage.md` (one row
per problem, not per note):

| # | Problem, in the player's words | Evidence | Testers | Kind | Priority | Decision |
|---|---|---|---|---|---|---|
| 1 | "I don't know where the shop is" | notes n_…, n_…; funnel *Bought something* 5/8 | 3 | confusing | P1 | tab strip pinned for the first 10 min |

- **Kind:** crash · error · confusing · pacing · feel · wish.
- **P0** — a crash, save loss, or an error 2+ testers met. Fix before the next build.
- **P1** — a funnel step that loses more than a third of testers; a *Longest dry* over 5 min for
  the median tester (retune it with `pacing_sim`, then confirm on the next round); anything 3+
  testers wrote in different words.
- **P2** — one person, clearly real. **Backlog** — wishes; they go to
  [ideas-backlog.md](ideas-backlog.md), not the triage table.

Each P0/P1 is fixed, a new build made (the build id changes), and the next round's report is read
for the same row: the fix is done when the problem stops appearing, not when the code is merged.

---

## Privacy — what to tell testers

The README in every zip says this; say it again when you hand it over.

- **Recorded:** when the game starts and stops; what is bought, used and opened, and when; how long
  between clicks; time spent in other windows (as a number of seconds, nothing about them); the
  screen sizes, Windows version, graphics card and language; the game's own error messages.
- **Not recorded:** names, accounts, files, anything typed outside a note, anything from other
  programs. A note's picture is **only the game's own window** — a transparent window's
  screenshot contains the game, never the desktop behind it.
- **Paths are scrubbed:** the save folder and anything shaped like `C:\Users\<name>` are replaced
  before an error message is kept, in the log, in the engine logs the bundle includes, everywhere.
- **Identity:** a random 8-character tester id groups one person's sends; you know who is who
  only because you know who you sent it to.
- **Local until sent:** nothing leaves the PC until they press *Send feedback* (or, in a Round 2
  build, until they quit — and the page says so). *Settings › Playtest › Session log* switches the
  log off; *Open folder* shows everything written.
- **Deleting:** delete the game folder, and `%APPDATA%\Bonehead Friend Playtest`. If someone asks
  you to delete what they sent, delete their zips and any report built from them.
- Keep the zips and webhook channel private, delete them when the round's triage is done, and
  test with adults (or with a parent's OK).

---

## The optional uploader

Off unless a `playtest.cfg` sits beside the exe. The build script writes one when given
`-UploadUrl`; **never commit one** (`playtest.cfg` is gitignored, and the URL is in no file in the
repository or the pack). Anyone holding the zip holds the URL, so use a dedicated endpoint and
replace it after each round.

```ini
[upload]
url="https://..."
format="multipart"      ; or "json"
file_field="file"
header=""               ; one extra header, e.g. "Authorization: Bearer abc123"
auto_on_quit=false      ; true: every quit queues the log; the next launch sends it
```

A failed send stays in `…\playtest\outbox\` and is retried on the next launch.

**Discord webhook (Rounds 1–2, up to a few dozen testers).** In a private channel: *Edit Channel ›
Integrations › Webhooks › New Webhook › Copy Webhook URL*. Then:

```powershell
powershell -ExecutionPolicy Bypass -File tools\make_playtest_build.ps1 -UploadUrl "https://discord.com/api/webhooks/…"
```

Each send arrives as a message with the zip attached (multipart, field `file`, the summary in
`content`). Discord caps attachments (10 MB on an unboosted server); a bundle is usually well
under 1 MB, a few MB with many screenshots. Download the attachments into one folder for the report.

**Google Apps Script into a Drive folder (Round 2, any size).** New Apps Script project:

```js
function doPost(e) {
  var data = JSON.parse(e.postData.contents);
  var folder = DriveApp.getFolderById("PUT_THE_DRIVE_FOLDER_ID_HERE");
  folder.createFile(Utilities.newBlob(
    Utilities.base64Decode(data.zip_base64), "application/zip", data.name));
  return ContentService.createTextOutput("ok");
}
```

*Deploy › New deployment › Web app*, execute as you, access "Anyone"; copy the `/exec` URL, and
build with `-UploadUrl "<that URL>" -UploadFormat json`. The script answers with a redirect, which
the game counts as delivered. Sync the Drive folder to your PC and point the report at it.

**Any HTTPS endpoint.** A POST of `multipart/form-data` with a `content` text field and the zip as
`file` (or `-UploadField` to rename it), or `-UploadFormat json` for
`{build, tester, name, summary, zip_base64}`. Any 2xx (or a 302/303) counts as delivered.

---

## Known limits

- The dev hotkeys (F3–F10) are live in every build; F4–F10 move and resize the window. Tell a
  tester who reports "it jumped" that a function key does that.
- The exe is unsigned, so SmartScreen warns on first launch until a code-signing certificate is
  bought (an M4 question).
- The first launch's minute rows start at one minute: a five-minute cold start has at most five of
  them. Your stopwatch is the instrument for Round 0 A; the log is the witness.
