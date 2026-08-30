# M3.7 — the desk you can clear, the kind half, and a buddy who plays

Three problems found in the first real session with the M3.6 sandbox, in the order they were
hit. All three are the same underlying shape: **the harm half of the game got built and the
kind half got listed.** The roster is 34 melee weapons, 14 explosives and 8 turrets against
7 kind items; the shop has categories on one side and a flat list on the other; and the one
system that would let him enjoy any of it was switched off by a bug.

M3.7-D is done. A, B and C are specified below and not started.

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

## A — no way to take anything off the desk

Both mechanisms already exist and **neither is findable**, which is why this reads as a
missing feature rather than a discoverability bug:

- Right-click despawns a spawned item (`BaseDraggable._unhandled_input`, gated on
  `drag_area.is_hovered` and `GROUP_SPAWNED`). Nothing in the game ever says so.
- `HUD._clear_button` clears the desk. It is a 26x22 ghost button carrying a bare `close`
  glyph, in a footer that only appears once `count > 0`.

And one real gap: `ThrowableBase` and `ProximityMine` override `right_click_is_mine()` to
prime a fuse, so **fourteen explosives cannot be right-clicked away at all**. Spawn a mine
you did not want and the only exit is the button you could not find.

**Build:** a universal gesture nothing may override (shift+right-click is the proposal, since
plain right-click is legitimately claimed), a labelled clear-desk control that is always
present rather than appearing with the first item, and a one-off toast naming both. Extend
`loop_check`'s existing `clearing the desk` suite to cover an explosive specifically — that
is the case the current suite misses.

## B — two-tile navigation, and a kind roster worth navigating

The shop cannot be fixed without the roster and the roster cannot be found without the shop,
so they ship together.

**Navigation:** a Harm tile and a Kind tile, each opening its own nested categories. Note that
the existing `category` enum cannot express this split — `Toy` currently holds the beach ball
*and* the gorilla. Either add a `side` field (cheap, mirrors how `is_autonomous` settled the
same argument in D) or re-file the NPCs into a category of their own and let Harm/Kind be
derived. **Whichever is chosen is a data change and needs a seed re-run with `--force`.**

**Roster:** ~20 leisure items — hammock, record player, fish tank, foot spa, paddling pool,
beanbag, jigsaw, birdfeeder. Built as different *shapes* of the existing `FriendlyBase`
switches rather than twenty classes. Every entry must state what he actually does with it,
because that is C's input, not decoration.

## C — he needs to be able to go and use them

He has no walk tag today, which is the real constraint: `IdleBrain` can already choose a toy
and travel to it, but there is nothing to draw while he does.

Plan animation as **families, not items** — "sits in" covers a beanbag, a paddling pool and a
hot tub; "bounces on" covers the trampoline and the bed. Twenty items should need perhaps six
families. Ship what needs no new art first (tilt into travel, bob keyed to speed, squash on
landing) behind an API `IdleBrain` calls, so the call sites do not change when real animation
lands.

**The suite that must exist:** stepped physics, a toy on the floor, assert he travelled
toward it and got paid. This broke silently once and should not be able to again.

---

*Sequence:* A is independent and smallest. B blocks C. Do A and B in parallel, C after B.
