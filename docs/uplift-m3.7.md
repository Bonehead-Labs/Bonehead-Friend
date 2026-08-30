# M3.7 — the desk you can clear, the kind half, and a buddy who plays

Three problems found in the first real session with the M3.6 sandbox, in the order they were
hit. All three were the same underlying shape: **the harm half of the game got built and the
kind half got listed.** The roster was 34 melee weapons, 14 explosives and 8 turrets against
7 kind items; the shop had categories on one side and a flat list on the other; and the one
system that would have let him enjoy any of it was switched off by a bug.

All four parts are built. What remains is art: twenty leisure items and a walk cycle.

---

## D — the idle brain was dead (DONE, commit `5ba8934`)

`IdleBrain` stands him up whenever the player does something, and read every `damage_dealt`
as the player. Turrets and NPCs fire on their own schedule forever, so **one turret on the
desk reset his idle timer every couple of seconds for the rest of the session** and he never
reached the twenty-five seconds a routine needs. Nothing failed, because nothing watched it.

Fixed with `ItemData.is_autonomous`. It is data rather than a category test because the
gorilla, goose and hornet are filed as `Toy` beside the trampoline — that is where a player
looks for them — and shop placement is a different question from having a mind of one's own.

**The trap for anyone extending this:** both seed tools skip files that already exist. A run
without `-- --force` leaves the flag off and the feature silently dead again. `loop_check`'s
`idle brain` suite asserts the flag in both directions and sweeps turrets by category.

Second-order note for A and B: there is a subtler reason the feature looks broken even when
it works. Spawning an item counts as the player being present, so anyone testing by putting
things on the desk resets the clock every time. `tools/sandbox.gd` now stages a trampoline, a
boombox and a hot tub at boot and says so in its summary.

---

## A — taking things off the desk (DONE, `3469e2a`)

Both routes existed and neither could be found, which is why this was reported as a missing
feature by someone looking straight at the button for it. Right-click bins an item and the
game never said so; the clear-desk button was a 26x22 ghost carrying a bare cross, and a
cross means "close" everywhere else in this shell.

The real gap was explosives: fourteen of them claim plain right-click to prime a fuse, so a
sixth of the spawnable roster could not be removed one at a time by any gesture at all.

**Shift+right-click is now an override no subclass may take.** The rule lives in
`BaseDraggable.click_would_bin()` rather than inside an input handler, because a headless
suite cannot synthesise a click with a modifier held but it can ask the question. The button
says "Clear desk". A one-off toast names both gestures the first time anything is on the
desk, remembered in `Settings.hints_seen` — whether someone has read a tip belongs to the
person at the keyboard, has to survive the Reincarnation that wipes everything else, and
keeping it out of the save keeps it out of `SAVE_VERSION`.

`clear_desk` and the gesture were two copies of "emit and free" and are now one call.

## B — two front doors, and a kind half worth opening (DONE, `5b3c73a`)

The roster is now **68 harm to 32 kind**, up from 73 to 7.

**Critters got their own category**, which is what made the rest possible. While the gorilla,
the goose and the hornet sat under Props beside the beach ball, no rule over categories could
tell the two halves of the shop apart. With that fixed `ItemData.side()` is a plain lookup
and every system agrees by construction. The kind half then got drawers of its own: Care
keeps what you do with your hands, and comfort, food and ambience moved out of Friendly.

**Twenty leisure items**, each a `FriendlyBase` with different switches and no new script
(D8). They are grouped by *what he does with them* rather than by theme, because those
switches are also what the idle brain reads: things he gets into and stays (comfort), things
he has a bite of (food), things that pay while they sit there (ambience).

Two traps this sprang, both worth remembering:

- `IdleBrain._routine_for` filtered on `CATEGORY_FRIENDLY`. Splitting that category would
  have made every hot tub and plate of food invisible to him and landed all twenty new items
  dead on arrival. It asks `is_kind()` now.
- The tree seeder guessed an item's third upgrade from its category, and that guess started
  contradicting names already authored — the massage chair's "Shorter Cycle" would have been
  given mass. The eight weighted items are named outright. The names are the design.

## C — he goes and uses them (DONE, `5b3c73a` and this commit)

Movement was already built and correct. What was missing was that he played `idle` the whole
way there, and that nothing anywhere proved he moved at all.

**`BuddyArt.travel(direction, effort)`** is the seam. He has no walk tag — the nine body tags
are poses and beats, none of them a stride — so this ships the half that needs no new art:
which way he faces, and a bob keyed to how fast he is going. A real walk cycle replaces the
bob later and no call site changes.

It is applied to the body *and* the face together, as a shared offset with a mirrored x
rather than a rotation. The face is a sibling sprite re-placed every frame from a table of
per-frame offsets, so anything that moves one and not the other takes his face off.

`travel()` is a **heartbeat, not a switch**: it decays in between calls, so a caller that
simply stops calling — because he arrived, was picked up, was knocked out — fades out
correctly. There is no code path that can leave him bobbing on the spot forever.

### The suite, and what it cost to get right

`loop_check`'s `idle brain — he goes and plays` runs stepped physics against real geometry:
buy a beanbag, put it 260px to his left, make him idle, and watch. It asserts he closes the
distance, arrives, is **paid** for being in it, and faces the way he is walking — plus that a
turret shooting him does not end his soak while a bat does.

Four things had to be got right, each of which had silently made it prove nothing:

- **Focus Mode must be pinned and restored.** With it Off he is *designed* to skip the walk
  and simply be there (D21), so a run inheriting Off from the developer's own `settings.cfg`
  exercises the one path with no travel in it.
- **Spawning is gated on ownership** and silently does nothing otherwise, so the item has to
  be bought first — and it has to be one gated by price alone, or the test breaks whenever a
  requires chain is re-authored.
- **Facing is sampled during the walk, not after.** He slides a little past the beanbag and
  nudges back, so a snapshot at the end asks about the correction rather than the journey.
- **Distance closed, not a coordinate.** He can overshoot a target he is standing in.

### Animation families — the plan for the rest

Plan by **family, not by item**. Twenty items need about six animations, not twenty:

| Family | Reads as | Covers |
|---|---|---|
| `walk` | a stride, replacing the bob | every journey |
| `sit_in` | lowers himself and settles | beanbag, paddling pool, hot tub, foot spa, recliner |
| `lie_on` | flat out, slow sway | hammock, heated blanket |
| `nibble` | leans in, small repeated bite | every food item |
| `fiddle` | hands busy, head down | jigsaw, rubber duck, record player |
| `gaze` | still, head tracking something | fish tank, lava lamp, fairy lights, bubble machine |

The mapping belongs beside the routine in `IdleBrain._routine_for`, which already reads the
item's switches rather than its id — so a new item picks up its family from what it does, and
adding one stays a `.tres` plus a scene.

Two constraints from the existing pipeline, both already paid for once: the Aseprite importer
marks **every** animation as looping, so a one-shot needs `set_animation_loop(name, false)`;
and every new tag needs a matching row in `Data/buddy_face_offsets.json` or his face will not
follow it — `loop_check`'s `buddy art` suite asserts the frame counts match, which is what
catches a tag added without offsets.

---

*Still to do:* art for the twenty leisure items (they fall back to placeholder silhouettes,
which is designed for and playable), and the walk cycle plus the five families above.
