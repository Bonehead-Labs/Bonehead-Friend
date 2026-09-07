# Decisions

ADR-lite. What was decided, when, and why — so a future session doesn't relitigate settled
questions or quietly violate a constraint it doesn't know about.

---

### D1 — Engine pinned to Godot 4.7.2-stable
**2026-08-28 · Decided**

The repo was ambiguous: the last commit declared feature tag `4.5`, the working tree had been
opened in 4.7, and `.vscode` pointed at 4.6.1. Three versions are installed on the machine.

Pinned to **4.7.2-stable** — the newest installed, and the version the working tree had already
migrated to. `.vscode/settings.json` updated to match.

*Consequence:* never open the project in another version; it rewrites `config/features` and can
change `.tscn` formats. Any addon must be verified against 4.7 (Aseprite Wizard's compatibility
is untested upstream).

---

### D2 — Dual currency: Bones and Hearts
**2026-08-28 · Decided**

Damage earns **Bones**; kindness earns **Hearts**. Weapons cost Bones. Friendly items **and
every automation capstone** cost Hearts.

Interactive Buddy's forgotten hook is that it paid for kindness as well as cruelty — the
happiness meter and the baseball-catch trick were real income sources, and nobody who cloned
the game kept them. Making Hearts gate automation turns that from flavour into the economy's
spine: you cannot stop working for your money without being nice to him. It's the strongest
differentiator against the Kick-the-Buddy lineage, and it produces the game's best joke.

*Alternative rejected:* single currency with a mood multiplier — simpler to balance, but
kindness would gate nothing and the identity would be weaker.

*Consequence:* more balancing work, two economies to tune. `Economy` stores balances in a
`StringName`-keyed dictionary and every cost carries its currency, so collapsing to one
currency later would be a data change rather than a refactor.

---

### D3 — Solid overlay basics at 1.0; OS-window colliders post-launch
**2026-08-28 · Decided**

1.0 ships bulletproof fundamentals: always-on-top, click-through, tray, multi-monitor, low-power
mode, taskbar-as-floor. Real OS windows as physics colliders becomes the flagship free
post-launch update.

Window enumeration needs Win32 (`EnumWindows`), which Godot doesn't expose — a GDExtension
workstream on the critical path, in a project whose genre already fails most often on technical
polish rather than content. The basics are what reviews are about; the window colliders are what
videos are about, and they're worth more as a launched-game update than as a launch risk.

*Consequence:* spike the Win32 work during M3 so the option stays open, and leave the seam in
the physics layer. Don't design any 1.0 mechanic that depends on it.

---

### D4 — Expressive single body, not a physics ragdoll
**2026-08-28 · Decided**

Bonehead stays a single `RigidBody2D`. The uplift is animation: bigger squash and stretch, a
layered face, a wide expression set, scripted reaction states. Knockout is an animated collapse
into a bone-pile sprite, not simulated dismemberment.

A jointed ragdoll with detachable limbs is the biggest single workstream in the project and the
one most likely to eat weeks in physics tuning (joint jitter, tunnelling, chaotic self-collision)
for a result that is *harder to make expressive*, not easier. Animation buys more character per
hour, and a single body is far cheaper for a game whose CPU budget is 3%.

*Consequence:* bone-scatter is a VFX/animation effect rather than a physics system; the
bone-collection mechanic is cut or reimplemented as collectible props. The buddy state machine,
`HealthComponent` and payout pipeline form a stable interface, so a ragdoll could slot in
post-1.0 without touching `Economy`, UI or saves.

---

### D5 — Stay on GL Compatibility
**2026-08-28 · Decided (inherited)**

The prototype's renderer choice is correct and stays: 2D-only game, lower idle GPU cost, best
track record with transparent windows. Revisit only if a shader requirement appears that GL
Compatibility can't serve.

---

### D6 — One window; UI as CanvasLayers, no separate main-menu scene
**2026-08-28 · Decided**

The game boots straight to the buddy. Shop, tree, contracts and settings are opaque
`PanelContainer`s on `CanvasLayer`s inside the single transparent window; the tray icon and Esc
menu are the shell.

Additional native `Window` nodes each complicate always-on-top ordering and the passthrough
polygon, for no benefit. Booting to a menu also wastes the genre's best first impression — the
character appearing on your actual desktop.

*Consequence:* the "beautiful main menu" requirement is delivered as a polished HUD dock plus
panel suite, which needs a real `Theme` and font (the prototype has neither).

---

### D7 — Receiver-side contact-impulse damage
**2026-08-28 · Decided**

Damage is measured on the buddy from `PhysicsDirectBodyState2D.get_contact_impulse()`, not by
the attacker measuring its own velocity.

The prototype read the velocity of a shapeless `RigidBody2D` nested inside the weapon, which
free-fell under gravity and therefore measured *time since the last hit* rather than swing
speed; the damage clamp hid it, and a later commit tuned around the artefact instead of fixing
it. Measuring on the receiver is physically correct, halves the code, and makes **any** rigid
body a weapon — a dropped bowling ball pays correctly with no special case.

*Consequence:* needs `contact_monitor` and a per-source cooldown (~0.1 s) so resting contact
can't farm damage.

---

### D8 — Content is data, never code
**2026-08-28 · Decided**

Items, augments, mastery tracks, contracts and all tuning live in typed `Resource` files under
`res://Data/`. Adding an item must never require editing a script.

The prototype needed three coordinated edits per item (a preload, a hand-copied UI tile, a
signal handler), which is why it stalled at seven items and why one of those edits shipped a
crash. Typed resources beat JSON here: inspector-editable, refactor-safe, validated on load.

---

### D9 — Cross-scene communication via EventBus and groups only
**2026-08-28 · Decided**

Absolute node paths (`/root/BaseLevel/_Gun`) are banned.

This is not a style preference: that exact pattern shipped a crash in the exported build
(commit `4d831ab`), because a node rename and a case-sensitive path both went undetected until
export. Signals and groups fail loudly and locally instead.

---

### D10 — Two window modes: fullscreen overlay and tucked play area
**2026-08-28 · Decided**

The overlay ships with two user-selectable modes:

- **Fullscreen overlay** (default) — fills the monitor's usable rect, taskbar becomes the
  floor. This is the intended way to play.
- **Play area** — a small window (960x640 by default) the player snaps into a screen corner
  or drags anywhere. 480x360 was the spike's placeholder and is unplayable: a single item
  sprite was two thirds of its height.

Play area was originally only the *fallback* if DWM compositing proved too expensive at 4K.
Promoting it to a first-class option is strictly better: some players want a quiet corner
pet rather than a screen-wide sandbox, it is the natural mode for a second monitor, and it
sidesteps the passthrough limitation entirely — a small window has very little area outside
the buddy for clicks to be wrongly captured in.

It also de-risks the milestone. If the 4K fullscreen numbers turn out bad, the fallback is
already shipped and tested rather than being an emergency redesign.

*Consequence:* `WindowLayout` owns mode/corner/clamping as pure functions;
`Settings` persists mode, corner, size and last-good rect; `WorldBounds` regenerates the
walls at runtime because the play area is resizable.

---

---

### D11 — `effect_per_level` is a multiplier, not an addend
**2026-08-28 · Decided**

An `AugmentNode`'s `effect_per_level` is the factor applied **per level**, and levels stack as
`pow(effect_per_level, levels)`. A damage node is `1.15`; a cooldown node is `0.95`.

The alternative — storing `+0.15` and summing, or storing a percentage and branching on whether
the effect is "good" — needs the sign of every effect encoded somewhere, and that somewhere is
always a script. One rule with no special case means a new effect key is a `.tres` field and
nothing else, and it makes the whole of `AugmentMath` four lines that the test runner can reach.

*Consequence:* effects compound rather than accumulate, so a ten-level damage node is ×4.0 and
not ×2.5. Cost growth is tuned against that, not against a linear ramp.

---

### D12 — Placeholder SFX are synthesised at boot, not committed
**2026-08-28 · Decided**

`AudioManager` generates its impact, purchase and knockout sounds procedurally in `_build_streams()`.

M2 needs "first impact sounds" and there is no audio pipeline yet. Committing binary stand-ins
invites someone to mistake them for the real thing (the art pipeline has explicit rules about
reproducibility for exactly this reason); generating them keeps the feedback loop complete,
costs nothing in repo size, and is obviously temporary at the call site. The pooled players,
voice cap, pitch randomisation and mute-when-unfocused around them are real and stay.

*Consequence:* the audio pass replaces one function. Nothing else changes.

---

### D13 — `main.tscn` is a thin scene; the UI is built in code
**2026-08-28 · Decided**

`main.tscn` holds the world, the buddy and the spawner. The HUD, panel suite, FX layer and Esc
menu are constructed by `main.gd` at boot rather than authored as scenes.

The shell is data-driven: shop tiles come from `ItemDB`, augment rows from an item's tree,
currency chips from `Economy`'s balance dictionary. An authored scene for any of those would be
a placeholder that has to be deleted the moment a second item exists — the exact mistake
`item_menu.tscn` made. Styling is centralised in `UIStyle` so the real `Theme` lands in one
file.

*Consequence:* the M2 art pass replaces `UIStyle` with a `Theme` resource and a font; the
layout code stays. UI changes are code review rather than scene diffs, which for generated
content is the right trade.

---

### D14 — Sustained kindness is a separate signal from event kindness
**2026-08-29 · Decided**

`EventBus` carries two kindness signals: `kindness_given` for discrete acts (a pet, a slice
of pizza, a caught baseball) and `kindness_sustained` for rates (the sponge scrubbing, the
boombox playing, and every Hearts generator after them). Both run the identical payout
pipeline; only `kindness_given` gets the combo multiplier.

The combo is a reward for repeated *acts*. A generator emits continuously, so on one signal
a boombox left switched on would sit permanently at the 3x combo ceiling — the exact
opposite of what a combo is for, and a large silent distortion to every idle Hearts rate.
Encoding the distinction as a second signal keeps `Economy` free of per-item special cases,
which is the property that lets a new friendly item be a `.tres` (D8).

*Consequence:* `FriendlyBase` banks its rate and flushes twice a second rather than emitting
per physics frame — sixty payouts a second would also mean sixty pooled floating numbers a
second for a trickle the player reads as continuous. Anything that emits kindness at a rate
must use the sustained signal.

---

### D15 — Mood and grime live on the buddy; Economy only mirrors them
**2026-08-29 · Decided**

`MoodComponent` and `GrimeComponent` own their values and announce them on the bus.
`Economy` keeps a plain mirror of each so the payout pipeline can multiply by them, and the
buddy is the save provider for the `buddy` block (save schema v2).

Economy is the only thing allowed to mint currency, so it must be able to read both without
holding a reference to a scene node; the buddy is the only thing that knows how he feels, so
he must be the one who owns them. Mirroring off the bus satisfies both without a path.

Two consequences that bit during implementation and are worth knowing before touching this:

- **Handler order is load-bearing.** `Economy` is an autoload and connects first, so it pays
  at the mood in force *when the event fired*; the components move it immediately afterwards.
  Any test that computes an expected payout must read the multiplier **before** emitting.
- **Mood is a multiplier on a U-curve, not a stat**, so the HUD prints the multiplier next to
  the bar. A player who reads it as a happiness meter concludes the middle is fine and
  quietly earns 0.6x all session.

*Alternative rejected:* mood as Economy state with the buddy as a view. Simpler wiring, but
then the save block, the decay timer and the animation trigger all live away from the thing
they describe, and the buddy has to ask an autoload how he feels.

---

### D16 — A minimal settings panel pulled forward from M4
**2026-08-29 · Decided**

Window mode, play-area size, corner, monitor, Focus Mode, Low Power and volumes ship now as
a third panel page. The rest of the M4 settings UI (streamer mode, hibernate, per-automation
rate sliders) stays in M4.

The M2 gate needs a non-developer to play for five minutes. Until this existed the only way
to resize the window was F9/F10 on the F3 developer overlay — and the window is borderless,
so it has no OS grab handle either. A playtester could not make the game fit on their desk,
which is not a fair test of whether the game is fun. Everything here writes through
`OverlayManager` and `Settings`, which already persisted and revalidated, so this is widgets
over working plumbing rather than new systems.

*Consequence:* the F3 hotkeys and the panel now change the same values, so the panel re-reads
`Settings` on every refresh rather than caching — two sources of truth is how a settings
screen ends up lying about the state of the window. Buttons rather than sliders and
`OptionButton`s throughout: popups over a transparent always-on-top window are awkward, and
`ui_check` can assert a `Button` is the control under the cursor in a way it cannot for a
popup.

---

### D17 — Automation capstones need Mastery, not Reincarnation
**2026-08-29 · Decided · amends economy.md**

`economy.md`'s tree diagram gates the automation capstone on **Mastery 25 + Reincarnation ≥ 1**.
The shipped capstones require Mastery 25 and **no prestige**.

The two halves of the spec disagreed and only one of them can be right. `economy.md`'s balance
targets say *"30 min — first automation running, understands why Hearts matter"* while its
pacing note puts the first Reincarnation at **6–10 hours**. Requiring prestige would therefore
put the game's central mechanic — the thing that makes Hearts matter and the thing the M3 gate
names — a full working day behind a wall, in a genre whose players quit at the first five-minute
dead end.

Mastery 25 on a single item is still a real gate: you must actively use a thing before you can
automate it, which is the difficulty ramp the design wanted from the requirement in the first
place. The prestige key is not thrown away — it stays available on `AugmentNode.requires_prestige`
and is the natural gate for a *second* tier of automation, post-1.0 content, or a capstone that
would be too strong on a first run.

*Consequence:* the gating gradient reads **Cash → Cash + Mastery → Cash + Mastery + Prestige**
across the whole game rather than within every tree. Update the diagram in `economy.md` if it is
ever regenerated.

---

### D18 — Contracts pay Ectoplasm, never a meaningful amount of Bones or Hearts
**2026-08-29 · Decided**

The contract board's reward is Ectoplasm. `ContractData` carries an optional currency
sweetener, and it is deliberately unused by every shipped contract.

A daily objective that pays spendable currency sets the pace of the shop ladder by the
calendar instead of by play: the optimal move becomes "log in, clear the board, log off", which
is precisely the free-to-play shape the design set out to avoid by replacing a login bonus with
a job board. Ectoplasm makes every *future* run richer without shortening this one, so a
contract is a reason to come back rather than a reason to stop playing.

*Consequence:* contracts are worth nothing to a player who never prestiges, which is fine —
they are the daily-return hook, and a player in their first six hours has better things to
chase. It also means the board can be generous without destabilising anything.

---

### D19 — A personality is one Curve and nothing else
**2026-08-29 · Decided**

`PersonalityData` holds an id, a name, a description and a **mood curve**. It does not modify
damage, prices, drop rates or anything else.

Five personalities from one field is the whole trick: the same roster and the same ectoplasm
number, but a different answer to "where is the money", so a run after a Reincarnation asks the
player to play *differently* rather than to play the same way faster. Masochist pays for cruelty,
Diva for kindness, Zen for neither, Goth for a mood nobody would otherwise sit at. Adding a sixth
is a `.tres` and no script edit (D8).

The temptation to give personalities extra stats should be resisted for as long as possible: the
moment one of them touches prices or damage, the five stop being one comparable axis and start
being five balance problems.

*Consequence:* `Economy.mood_multiplier()` reads the personality's curve rather than
`balance.tres`'s, falling back to it when a save names a personality that no longer exists — a
removed personality must degrade the tuning, not zero out every payout in the game.

### D20 — The shell is "Bonecard": a `Theme` built in code, and every figure in one face

Four skins were mocked up and shown side by side; Bonecard was chosen. It is printed card —
cream stock, hard black 3 px rules, no rounded corners, colour used only where it carries
meaning. It won on the constraint that actually matters here: the UI sits over an unknown
desktop, so it has to read as chrome rather than as part of the wallpaper.

Two structural parts of the decision, both of which could reasonably have gone the other way:

**The `Theme` is built in code (`UITheme`), not authored as a `.tres`.** Half of it is derived
— a pressed button's content margins are computed from its normal ones so the two states are
exactly the same height, which is what stops a row re-laying-out mid-press. A hand-edited theme
resource cannot hold that relationship; it holds the numbers after someone worked them out
once, and they drift. The cost is that the theme cannot be tweaked in the editor's theme
editor. That is the right trade for a UI that is itself built in code (D13).

**Every figure in the game is set in Silkscreen, never in the body face.** Pixelify Sans draws
`5` as a rounded form that reads as an `8` at 14 px. In a game read as columns of figures that
is not a stylistic quibble — it was caught in the first screenshot pass, where the bat's
"+15% damage" node was indistinguishable from "+18%". So the two faces are split by *job* and
not by taste: anything containing a number goes in the display face, and the body face carries
only prose. The Reincarnation page was rewritten around this, moving its numbers out of the
paragraph into figure chips.

*Consequence:* adding a UI string means asking whether it contains a digit. If it does, it is
`UIStyle.label`, not `UIStyle.body`. `art-direction.md` § UI carries the full token set.

### D21 — UI motion is a library, and Focus Mode Off means the menus stop moving too

All menu animation lives in `UIMotion` as static helpers, and every panel calls into it rather
than writing its own tweens. That is partly consistency and mostly three rules that have to be
enforced in one place:

1. Never animate `position` or `size` on a control inside a `Container` — the container owns
   both and rewrites them on the next layout pass, which happens on the same frame a refusal
   fires, because refreshing the row that refused you changes its text and therefore its
   minimum size. `scale`, `rotation`, `pivot_offset` and `modulate` are ours.
2. Never fade a card. The window is per-pixel transparent (D6).
3. One named tween slot per control per kind of motion, or a fast cursor leaves two scale
   tweens racing and the control settles wherever the loser stopped.

**Motion is off when Focus Mode is Off, and always off in headless.** The first is consistency:
Focus Mode Off already means the game stops shouting, and a player who set it because they are
in a meeting did not mean "except the menus". The second is load-bearing for the test suite —
a control caught mid-tween is at the wrong scale, so every hit test against it is a coin flip.
`tests/integration/loop_check.gd` asserts the headless case, because it is an invariant the
whole `ui_check` sweep leans on rather than a nicety.

*Consequence:* Focus Mode Off is the accessibility switch for reduced motion until M4 gives it
its own setting. Timings never scale with the setting — only amounts — because a slower UI is
not a calmer one.

### D22 — One tab strip, one card, one size

The first Bonecard build had two navigations: a five-button dock in one corner of the
desktop and an identical row of tabs on the card in the other. Five pages, ten buttons, the
same five words printed twice — and switching page meant a six-hundred-pixel trip from the
card you were reading back up to the dock.

**The strip owns the panel.** One row of five tabs, always on screen, never moving. Clicking
a tab unrolls the card directly beneath it; clicking the same tab rolls it back up. The strip
is exactly as wide as the card and its tabs share that width, so the open tab's cream bottom
edge runs into the card and the two read as one object rather than as a row of keys near a
panel.

**The card is one fixed size for every page.** It used to measure the page it was about to
show and resize to fit, so the panel changed shape under the cursor on every tab click. A
page that needs more room scrolls inside the card. Enforced by `ui_check`, which opens all
five pages and asserts the card's rect is identical — and structurally, because every page
scrolls with `SCROLL_MODE_SHOW_NEVER` rather than `SCROLL_MODE_DISABLED`: a disabled axis
folds the child's minimum size into the ScrollContainer's own, so one long unwrapped line on
one page silently widened the card for all of them.

**The shop is master/detail.** A thin list — picture, name, price — and one detail pane. The
list used to carry every item's description as two wrapped lines, which is thirteen
paragraphs stacked on one card: correct, and unreadable. The words now live in the detail
pane, one item at a time, set large enough to read.

*Consequence:* the card is generous (680x566 UI pixels) because it is a panel you open on
purpose. The previous 460px is what forced the type small enough to be the complaint that
started this.

### D23 — The UI scales in whole numbers, and only in whole numbers

The shell is pixel art at a fixed size, so on a 3440x1440 overlay it came out physically
tiny — making the play area bigger made the *game* bigger and left the menus exactly where
they were.

Each shell `CanvasLayer` is scaled by a whole number (`UIScale`), auto-picked from the window
height and overridable in Settings. Whole numbers because that is what pixel art wants: every
pixel becomes a clean 2x2 or 3x3 block, with no resampling and no reflow. Scaling the *font
sizes* instead would reflow every panel and put the type on fractional pixels.

*Consequence, and the trap:* a Control's `get_global_transform()` stops at its CanvasLayer, so
`get_global_rect()` is in canvas coordinates and is wrong by exactly the scale factor. Anything
comparing a control against a mouse position — the click tests, the coin thrown by a purchase —
goes through `UIScale.screen_centre` / `screen_rect` instead. A top-level Control also sizes
itself to the *viewport* and knows nothing about the layer above it, so each layer's root is
sized explicitly in UI pixels.

### D24 — No trash bin; right-click one thing, or clear the desk

The bin was a 36x45 catch area under a 64px sprite, anchored above the height at which a
dropped item comes to rest — so in practice nothing ever landed in it, and the only way to
clear the desk was to spawn past the item limit and let the oldest item get culled.

Two gestures replace it. **Right-click a spawned item** and it is gone; **the desk counter in
the HUD is a button** that clears all of them. Both go through `EventBus.item_despawned`, the
same path a prestige wipe uses, so the counter and the friendly items' banked kindness stay in
step.

Right-click is whitelisted on the `spawned_item` group, not blacklisted on the buddy. The
buddy is draggable too, and no gesture may ever delete him — `loop_check` asserts he is not in
that group, because the day someone adds him to it for an unrelated reason is the day
right-clicking him deletes the save's whole point.

### D25 — Item physics is authored; the sprite decides nothing but its own size

Rebuilding the prototype's hand-authored item scenes from their sprites produced, for every
weapon, a box around the picture pinned and balanced at its centre. That is a plank on a
string. The prototype bat had four things none of which are recoverable from a sprite:

- a **capsule** for the barrel and a small **rect** for the grip, not one box;
- its **centre of mass up in the barrel**, so it swings with weight in the head;
- the **drag joint pinned at the grip**, so it pivots around your hand;
- a **grab region over the handle**, so you pick it up by the handle.

`tools/seed_bodies.gd` now carries a `PHYSICS` table in the same art-pixel space as the
scale table. Anything not listed falls back to the derived box, which is right for a
grenade and a ball. Feel is authored data, in the same category as the scale table and for
the same reason: nothing enforces it, so nobody notices when it goes.

### D26 — Contrast is a test, not a judgement call

The palette was picked by eye and Bones came out at **2.97:1** on a sunk well — a price the
player cannot read — while disabled controls tinted their text at 55% alpha and landed near
2:1. Neither is visible to the person who picked the colour, on their monitor, with their
eyes. So it is not a judgement call any more.

`loop_check`'s `contrast` suite asserts every ink against every surface it is ever printed
on at **4.5:1**, plus the two inverted surfaces and the whole mood sweep. Every accent was
darkened until it cleared, and **no text is dimmed with alpha** — a disabled control uses
`UIStyle.DISABLED_INK` and says it is disabled with its *shape*.

*Consequence:* a new colour that looks fine fails a test rather than shipping. The floor is
4.5 and not 3.0 because nothing in this shell is "large text" — the biggest thing on a card
is a 26px pixel face.

### D27 — Every picture is exactly the size of the box that holds it

Not "at most". Exactly.

The box used to be a suggestion. A shop row asked for an icon and got whatever the PNG on
disk happened to be — the pistol pointed at a raw 64x64 crosshair, the fist at a raw 64x64,
the shotgun at nothing and fell back to a 16x16 glyph. A `Button` grows to fit its icon, so
one list held rows 74, 74, 42 and 38 pixels tall with the name starting at three different
x positions, in a list whose entire job is to be scanned. Nothing in the layout code was
wrong; the layout was faithfully rendering four different inputs.

The two obvious remedies are both wrong here. `Button.expand_icon` and the `icon_max_width`
theme constant resample to fit, and a 44 -> 32 resample of pixel art is a non-integer scale —
the thing `UIStyle.sprite()`'s `STRETCH_KEEP_CENTERED` exists to forbid. So instead,
`UIStyle.boxed()`:

- steps oversized art down by a **whole number** only (64 -> 32 is /2, exact under nearest);
- centres the result on a transparent canvas of exactly the box size, on whole-pixel offsets,
  so a glyph fallback and full-bleed item art occupy identical space;
- crops rather than overflows anything no whole number fits — a content bug is allowed to look
  wrong, never to move the layout.

`icon()`, `sprite()`, `set_sprite()` and `item_face(item, box)` all go through it. Writing
`rect.texture` or `button.icon` directly is the one way back to the old behaviour.

*Consequence:* **adding an item cannot move the UI.** Two assertions hold the line — `ui_check`'s
`geometry` suite measures every picture against its *declared* box (not its realised size: a
Button that grew to fit would otherwise pass the exact bug it was written for), and asserts every
row in a category is one height; `loop_check`'s `content` suite asserts every item icon is a 32px
canvas and prints the art backlog by name.

### D28 — A page that is not on screen does no work

`PanelPage` is the base every page of the card extends, and it exists for that one rule.

The bus is loud: `currency_changed` fires on every hit and again once a second per currency
from automation, forever. Five pages rebuilding themed rows on each of those, with the card
shut, is a permanent background cost in a game whose pitch is that it idles under your work
at under 3% CPU.

The guard cannot be `if visible:` — that was the original bug. A page's own `visible` flag is
written only when the card switches pages, so the page the player last had open stayed flagged
visible under a closed card and the guard passed forever. `is_visible_in_tree()` is the question
that was meant. `PanelLayer` now also hides the outgoing page with the card, so the two answers
can never disagree.

Deferred work is remembered, not dropped: `request_refresh()` / `request_rebuild()` mark the page
dirty and it catches up the moment it is shown. Pages that hold a transient mode drop it in
`_on_page_hidden()` — which is how the Rebirth page's armed confirm stopped surviving a close.

*Consequence:* `ui_check`'s `closed pages` suite asserts no page is flagged visible under a shut
card, that twenty currency events with the card shut cost zero refreshes, and that opening a page
pays what it deferred.

### D29 — Either half of the shell can hide behind an arrow

Opt-in, off by default, one switch each (Settings > Shell): **Hide status until hover** and
**Hide menu until hover**. Two switches rather than one because the two wants are genuinely
independent — someone who wants a clean desktop while they work often still wants the tabs
clickable, and a player who lives in the menus may not want a stat block over their document.

The panel parks against its own edge and leaves a small white arrow, outlined so it survives
an unknown desktop behind it. **The arrow points the way the panel will travel to reveal
itself** — right at the left edge, down at the top — and flips to point back at that edge once
the panel is out. That is the whole language; there is no label and no second thing to learn.

`HoverDrawer` is shared by both. Two constraints it exists to respect:

- It tracks the cursor from **motion events**, not `get_mouse_position()`. The polled position
  is the OS cursor, which no synthetic event can move — a drawer built on it works in the game
  and is untestable and unrecordable everywhere else.
- It animates `position` on a control that is a direct child of a plain `Control`, which is the
  only place in the shell where a control may own its own rect. Owning it means owning **both**
  halves: a child of a plain Control is never laid out, so it keeps its old *size* as well as
  its old position — that is what left a 697px tab strip inside a 480px window when the play
  area stepped down.

*Consequence:* `ui_check`'s `auto-hide` suite drives both drawers open and shut by pushed
motion, and asserts each half parks off screen, leaves an arrow that stays on screen, comes
back when that arrow is hovered, leaves again when it is not, and returns to the window when
the setting is switched off.

### D30 — A payout number escalates with its own magnitude

The floating numbers are the game's only reward for most of a session, so they are treated as
the reward rather than as a readout. Three rules, in `FXLayer`:

**Colour separates the two economies.** Bones and Hearts were both a pale cream differing only
in tint. They are now a gold and a rose at full saturation — and, as everywhere else here, the
colour reinforces rather than carries: the two are also different sizes and throw differently
coloured sparks, because about one player in twelve cannot use the hue. Both ramps stay
saturated at the top; running them to white was the obvious way to say "hotter" and would have
made the two economies identical at the tier a player works hardest to reach. The heat is
carried by the *core* instead, which goes white inside an outline that keeps its hue.

**The treatment escalates with `log10` of the amount**, not against a tuning constant. Size,
outline weight, rise distance, scatter and spark count all step up per digit, so a five-figure
payout is visibly a bigger event than a two-figure one — forever, with nothing to outgrow. That
is the appeal of the genre made visible, and it is why the ramp is logarithmic rather than a
table of thresholds.

**Tier 0 stays cheap.** It fires on every hit for eight hours. It throws no particles, uses the
smallest face, and a game that shouts at every tap stops being ignorable — which is the whole
premise (D6).

Numbers are drawn in the display face, loaded rather than themed: a `CanvasLayer` does not
inherit a `Theme`, so these had been quietly drawing in Godot's default sans while the rest of
the game was in Jersey.

*Consequence:* `ui_check`'s `payouts` suite asserts the layer is listening to all four of its
signals, that Focus Mode Off draws nothing and Focus Mode Normal draws something, and that the
two ramps stay distinguishable at every tier. `tools/fx_shots.tscn` renders the specimen sheet,
because whether a reward is satisfying cannot be reviewed from source.

### D31 — Dollars replace Ectoplasm

Decided 2026-08-30 by the owner, revising the same day's first version. **There is no
Ectoplasm.** Dollars are the game's third and last currency, and they take over everything
Ectoplasm was supposed to do.

Ectoplasm was a currency that could not be spent, and the pacing simulator found something
worse about it than that: because the threshold grows as a cube while the points grow as its
root, **every Reincarnation yields exactly one point, forever**. Five resets — fifty-eight
simulated hours — bought five points, worth five per cent. It was never going to be felt, and
no divisor fixes a shape like that.

**Dollars are earned by being present**, in three ways:

- **A flat amount per act.** Every damaging hit and every kind act pays the same Dollar
  amount whether it came from a starter bat or a lightning strike — *unmultiplied by mood,
  augments, mastery or anything else*. This is the property that makes a third currency safe
  to add: Bones and Hearts inflate by design and must, and Dollars cannot, so a veteran and a
  newcomer unlock cosmetics at the same rate. Cosmetics arrive on a schedule of attention
  rather than of power.
- **Milestones**, which is where most of them come from and which is the headline reward for
  playing broadly (D34).
- **Automation and offline pay them at `dollars_idle_efficiency`** — a fraction. The only
  place in the economy that is deliberately worse when idle, and the right place for it:
  Dollars buy the things you look at, so they should be earned while looking.

**Dollars buy** cosmetics, the arcade (D32), and Séance boons — permanent upgrades that make
every future run start stronger. The earlier rule, "Dollars never buy power", is **withdrawn**:
it was written to protect the shop ladder from a competing currency, and Dollars do not
compete with it — they cannot buy a toy or an upgrade. One narrower rule replaces it and is
the one that matters:

> **Nothing bought with Dollars may pay out Hearts at a rate that competes with being kind.**

Automation is Hearts-priced, everywhere, always (D2). That bargain — *you cannot stop working
for your money without being kind to him* — is the whole reason this is not simply Interactive
Buddy with a shop. A slot machine that pays a meaningful pile of Hearts lets a player gamble
their way past it, and the kindness half of the game becomes optional.

*Consequence:* save v4 drops `prestige.ectoplasm` for `currencies.dollars`, contracts pay
Dollars (D18 is amended: the reason contracts paid a prestige currency was so a daily could
not set the pace of the shop ladder, and Dollars satisfy that just as well since they buy
nothing in the shop).

### D32 — The arcade pays in Dollars, time and hats — not in income

Spin-the-wheel, a slot machine and blackjack, played with Dollars, filed as its own milestone
after 1.0 (M6). What a spin may pay, decided rather than left open:

- **Dollars** — gambling your own currency, which is the honest version and the main one.
- **A timed multiplier**, through the one shared `temp_mult` slot the Dream Journal and
  Overtime Pay also use. Minutes, never permanent.
- **Cosmetics**, including ones not otherwise purchasable.
- **Rarely, a permanent boon** — the same kind the Séance sells, won instead of bought.

**Bones and Hearts payouts stay small enough to be a garnish**, per D31's one rule. The
temptation is obvious and it is a trap: the moment a slot machine can pay a real pile of
Hearts, the optimal line becomes *farm Dollars, gamble for Hearts, skip the kindness half*.

Simulated gambling with no real money attached is storefront-legal but attracts content
descriptors on some ratings boards, which touches the gore-free unrestricted-rating position.
One game shipped well beats three shipped thin; the wheel is cheapest and reads fastest, so it
goes first and alone if the milestone is cut.

### D33 — Reincarnation is free, endless, and pays Marrow

Decided 2026-08-30. The owner's note on this is worth recording verbatim: *"it wasn't a
mechanic I asked for, it was something Claude came up with"* — the brief is an endless
incremental game that is rewarding on the way up and still rewarding once it is limitless, and
prestige is only justified if it serves that.

It does, but not in the shape it had. **A reset loop is the only structure that makes an idle
game genuinely unbounded**, and the reason is arithmetic: an upgrade ladder's costs grow
geometrically while a single device's output grows linearly, so *every* individual track
stalls eventually. What un-stalls it is a loop that resets the costs and keeps the multipliers.
Without one, "limitless" means "a very long ladder", and this design has already measured how
long that ladder is.

So the loop stays, and the three things wrong with it go:

- **No threshold.** You may Reincarnate at any moment. The Rebirth page states what you would
  gain right now, and that number climbs while you play; there is no locked door and no
  "not yet".
- **No cost in Dollars.** Considered and rejected: gating the endless engine behind the one
  currency that cannot inflate would cap progression on wall-clock attention, and a player
  with a huge run and no Dollars would be locked out of the only thing left to do. The cost of
  a Reincarnation is the run you give up. That is enough.
- **The reward scales with the run.** A reset grants **Marrow**: `(run earnings /
  marrow_divisor) ^ marrow_exponent`, added to a permanent total that multiplies all income as
  `1 + marrow`. One number, stated on the Rebirth page. Because each cycle multiplies income,
  the next run reaches further in the same wall-clock, which grants more Marrow, which reaches
  further again. That is the engine, and
  it is why cycle length stays roughly constant instead of growing eightfold each time as the
  cube-root threshold forced it to.

Marrow is a **stat, not a currency**: it is never spent, never displayed in the purse, and has
exactly one effect. It is named for the part of a bone nobody sees.

Reincarnation also rolls a new personality, which is the other half of why the loop is worth
taking: five mood curves (seven after M3.5-B) that each ask for a different rhythm.

*Consequence:* `prestige_divisor`, `prestige_exponent` and `prestige_income_per_point` are
replaced by `marrow_divisor` and `marrow_exponent`; `EconomyMath.ectoplasm_for_lifetime` and
`prestige_gain` become `marrow_for_run`. The pacing simulator's fourth target — each
Reincarnation within 2x the pacing of the last — stops being a hope and becomes the thing the
formula is built to deliver.

### D34 — Milestones come in two kinds, and one of them never runs out

Decided 2026-08-30. Milestones are the main source of Dollars, which creates a problem the
first version of the idea did not have an answer for: **there are only so many of them.** A
finite set that is mostly front-loaded ("earn your first 1M Bones", "own every toy") pays well
for a week and then stops, and the arcade goes dark exactly when a player has settled in.

So there are two kinds, and the split is the fix:

- **Named milestones**, roughly sixty at 1.0. Hand-written, memorable, each paying a Dollar
  lump and sometimes a hat. These carry the first week and are what a player screenshots.
- **Repeating milestones**, which are ladders rather than entries: every 10x of lifetime
  Bones, every hundred knockouts, every twenty-five levels on a device, every ten thousand
  kind acts. Each rung pays less than a named milestone and there is always another rung.

Both feed one compounding income bonus (x1.01 per milestone, D11's rule again), so the
milestone board is also the third income axis rather than only a Dollar tap.

*Consequence:* `MilestoneData` needs a `repeat_every` field and a claimed-count rather than a
claimed-flag, which is a save-shape decision and therefore belongs in the v4 bump with
everything else.

### D35 — A hit sounds like what hit him

Added 2026-08-30, with the roster going from four melee weapons to thirty-plus.

Every impact in the game played the same wooden clatter. That was right when the melee
category was a bat, a pan and a mace; it stops being right the moment it contains a
greatsword, a stapler and a tesla coil. **Material is what the ear is actually listening
for** — a player who is working in another window and not looking at the desk should still
be able to tell a sword from a keyboard.

Five voices, synthesised like everything else (D12): wood (the original), metal (inharmonic
partials, long decay — the difference between a bell and an organ pipe), soft (a low sine
with no transient, because the *absence* of a transient is what reads as padded), plastic
(short, dry, pitched above the wood so the two do not merge), and electric (noise through a
rising sweep). Plus blasts at two sizes, a turret's dry crack, a roar, and the arcade's
reel stop and wheel tick — which are the two sounds a casino actually runs on, both being
the moment *before* the outcome.

**Chosen by substring on the item id**, not by a table of every item. A per-item table
would need editing for every new toy, which is exactly the D8 violation this avoids; the
families are the ones the synthesiser has voices for, an unlisted item falls back by
category, and an unknown category falls back to wood — so a new toy is never silent. The
resolved voice is cached per source, because `_on_damage_dealt` runs on every contact for
eight hours and a substring sweep per hit is a substring sweep per hit.

*Consequence:* when the audio pass replaces synthesis with recorded assets, this becomes a
field on `ItemData` and the lookup goes away. It is written down here so that pass knows
the intent rather than inheriting a table it does not understand.

---

### D36 — At Focus Off he reacts; he does not initiate — and beats are not states
**2026-09-06 · Proposed** in `plan-expressive-buddy.md` §3.5 and implemented as written;
the owner's confirmation of the wording is still open (`worklist-2026-09.md` §4).

Two systems had already invented compatible answers to what the character may do at Focus
Off — `idle_brain.gd` skips the walk and is simply there, `npc_base.gd` stands its animals
down — and nothing wrote the rule down, so the third system would have invented a third.
The expressive buddy is that third system: some forty triggers, which ungated would make Off
louder than today's Normal and break the promise to a player in a meeting. Focus Mode is
also the project's de-facto reduced-motion switch until M4.

**At Focus Off he reacts; he does not initiate.** A beat caused by something the player just
did still plays, because the player caused it and is looking at it — as a face and a body tag
with **zero** procedural amplitude. Nothing initiates: no fidgets, no blinks, no gaze, no
travel, no landing dust, no sleep, no posture, no attention-seeking. And nothing leaves his
silhouette: tag and face may change; `position`, `scale`, `rotation` and `skew` offsets may
not. Amplitude is `Settings.intensity_scale()` (0.0 / 0.4 / 1.0 / 1.6), reused verbatim
rather than a third ladder, and every code motion multiplies by it — so Off zeroes motion
arithmetically rather than through forty scattered `if`s. Timings never scale with the
setting, only amounts (D21): a reaction damped to nothing reads as a hit that missed.

**Gaze has its own gate**, Normal and above. Looking at the cursor is the single most
attention-grabbing thing a desktop character can do and it is free, which is exactly why it is
dangerous — this game refuses to be Desktop Goose by default. He looks; he never chases.
Chase stays where the ideas backlog put it, as an opt-in unlock.

**Beats are not states.** `Buddy.state` is a public contract: Economy mints the knockout
bonus off `buddy_state_changed`, WorldFX throws its bone shower, the idle brain stands down,
the art picks posture. A reaction is a *beat* — a bounded presentation overlay owned by
`ExpressionBrain`, arbitrated in one slot by priority (ambient 0 · attention 10 · reaction
20 · pain 25 · heavy 30 · beat 40) — and never enters the state machine. `hurt` and `happy`
stay states because contracts and suites depend on them; everything else in the reaction
table is a beat. The knockout is the one thing in the other direction: while his real state
is inside collapse → pile → reassemble, nothing below `beat` plays.

*Consequence:* a new reaction is a row in `ExpressionBrain.ROWS`, not a state and not a
`connect()` somewhere else — every connect on the character lives in one `_ready`, and
`loop_check`'s `expression` suite asserts each by name. Any future system that wants to move
him at Off has to argue with this entry first.

### D37 — The Arcade is rooms, one on screen at a time — and the shell has particles

Three cabinets stacked in a 520px card gave each machine a 132px wheel, 32px reels and a
third room below the fold, in a game whose whole pitch is that the toys are worth looking at.
The Arcade page now has its own strip of `IconTab`s — The Wheel, Three Ghosts, Blackjack,
Wardrobe, Rebirth — and exactly one room below it. Every machine gets the same 270px stage
(`ArcadePanel.STAGE_WELL`), so switching rooms never moves the Play key under the cursor; the
wheel is 262px, the reels 96px (a 16px glyph boxed by six), the cards 60x92 with a hero-size
rank. Rooms stay built when hidden, so a spin in a room the player left still lands and still
pays. Everything above the stage was cut to one line each — page intro, machine rules — because
every line above the stage is a line taken from it. `show_room(id)` is the one entry point;
`EventBus.show_panel(&"prestige")` selects the Rebirth room through it.

`UIMotion.sparkle(control, colour, count, speed)` is the shell's own particle burst: a one-shot
`GPUParticles2D` of four-pixel chips, parented to the control so it rides the control's layer
and integer scale, shrinking to nothing rather than fading, freed when spent, and off wherever
`UIMotion` is off. It marks the moments the player made happen — an arcade win (a shower for a
jackpot or a boost), a deed claimed, a finish worn (with a star burst on him in the world), the
next toy becoming affordable, the rebirth row first appearing, a job coming good on the tab, a
record round's toast. `UIMotion.fill(bar, value)` tweens a `Range`'s value the same way.

*Consequence:* a new machine is a script in `ArcadePanel.MACHINES` and nothing else — it gets
its tab, its stage and its celebration for free. A new celebration is a `sparkle` call at the
moment of change, never on a refresh; anything that fires on every tick is a bug.

### D38 — What is behind him is a choice; the desktop stays the default

The transparent overlay is the game's pitch and stays the default, but it is not what everyone
wants behind a skeleton: a streamer needs a key colour, a player in a play-area window wants a
room, a player with a busy wallpaper wants a wall. `Backdrop` is a `CanvasLayer` under the world
that paints one of a fixed menu to the window's own rect — six flat colours (Slate, Charcoal,
Forest, Plum, Navy, Chroma) and five drawn scenes (Night sky, Dusk, Hills, Graph paper, Desk).

Scenes are **drawn, not pictured**: hard bands, stepped discs, ridge silhouettes sampled once
per block, a star field from a fixed seed with a count that follows the area. One block is
`floor(height / 240)` screen pixels, so a scene is as chunky in a 480px play area as on a
1440px monitor and nothing is ever stretched. Every backdrop is dark or mid-toned, because he is
white, the cards are cream and the inks are the palette's — a light backdrop would swallow all
three. The Desk puts its top at the bottom quarter of the window, which is where the generated
floor is, so he stands on it in every mode.

The choice is `Settings.backdrop`, machine-local like the rest of `settings.cfg`, set through
`OverlayManager.set_backdrop()` and announced on `EventBus.backdrop_changed`. "Desktop" hides the
layer outright, so the window is exactly as transparent as it was. Chroma is the colour
`streamer_bg_color` was reserved for; with auto-hide (D29) it closes what streamer mode owed.

*Consequence:* a new backdrop is a row in `Backdrop.CHOICES` — the settings page builds its
buttons from that table, and `ui_check`'s `backdrop` suite clicks every one. The canvas is a
full-rect Control on a CanvasLayer and MUST stay `MOUSE_FILTER_IGNORE` (CLAUDE.md).

## D39 — The world has juice: every physical event is drawn where it happened, and one
## particle system (2026-09-06)

**Decision.** `WorldFX` is the one pool for everything physical that is not a body, and every
event on the desk goes through it: a landing throws dust at his feet, a toy pops in and out
with a puff, an explosion is a shockwave ring, smoke, sparks and a jolt, a turret shot is a
tracer, the lightning is a jagged bolt from above, the sunbeam gives off heat, a trampoline
kicks dust, a missile trails smoke, a rank throws stars off him, a full clean throws white,
mood crossing into delighted or miserable sends hearts or a dark cloud off him, and a
Reincarnation is three rings, a shower of stars, a jolt and a headline. The hit chips run
hotter with the streak. `FXLayer` prints a rank, a rebirth and a clean over him in the payout
face, and shows what he earned offline as coins off him. The knockout meter glows once it is
nearly full. Every toast that is a score rather than a notice is chipped.

**Why.** The shell had motion everywhere (D37) and the world had almost none: a grenade was a
sprite that vanished and a number that appeared, the pistol was a click with no mark, a rank
was a toast in the corner, and the biggest decision in the game — Reincarnation — was one line
of text and a chime. The genre's whole feeling is that things *happen*, where they happen.

**What it turned up.** The world's pool was `CPUParticles2D` since D30, and in this project a
`CPUParticles2D` emits and never draws — the emitters sat "emitting" at the right place with the
right texture and the screen stayed empty, which only the shot tool could show. Every bone chip
off a hit and every heart off a pet had been invisible for the whole of M3. The pool is now
`GPUParticles2D`, like `FXLayer` and `UIMotion`, with one cached `ParticleProcessMaterial` per
recipe. Rule from it: **no `CPUParticles2D` anywhere; a particle effect is not done until a
shot shows it.**

**The shake** is the viewport's canvas transform, which is how a Camera2D would do it: rendering
only, so no body moves, the mouse still maps through it, and the shell on its own CanvasLayers
stays still. Normal and Chaos only, capped at nine pixels, 220 ms, whole pixels — a player
working beside the window must never find it rude.

*Consequence:* a new physical event is a call into `WorldFX` from the thing that happened, found
by group via `WorldFX.of(self)` and treated as optional. `ui_check`'s `juice` suite asserts the
pools are named, every listener is wired, nothing draws at Focus Off, and every ring, line and
jolt puts itself away. `ui_shots` catches the effects mid-flight in three frames (`16-juice`).

## D40 — The rhythm is on the card and the desk is alive (2026-09-06)

**Decision.** The HUD carries a streak row: the damage streak and the kindness combo as a
figure each, in the currency's colour heating toward orange, over a bar that drains toward the
moment the streak lapses — ticking twenty times a second only while one is alive. A streak of
ten puts embers on him; a blissful mood puts a slow gold sparkle on him; both are continuous
emitters parented to his body. Every body leaves a trail when it moves fast — gold for a
weapon, rose for a kind item, white for him — a world-space `Line2D` fed from the collision
shape's far corner and tapered from the tail, built on first use. The kind items have ambient
life by id: steam off anything hot, bubbles off anything wet, a twinkle on anything that glows,
notes off anything that plays. A heavy hit gets a ring at the contact. A deed claimed throws its
coin at the purse like a contract does.

**Why.** The streak and the combo are the whole feeling of momentum and they lived only as a
tag beside a payout number, in the world, for a second; "keep it going" needs a clock the
player can see. The kind side had numbers and no life — a hot tub was a picture of a hot tub.
A bat swung through the air with nothing behind it.

**Budget.** The streak timer and the trail are the two per-frame costs this pass added, and
both are bounded: the timer runs only while a streak is alive and stops itself; the trail is
one `length_squared` on a body that already ran a physics step, and allocates a node only the
first time that body moves fast. Ambient emitters are GPU, four to nine chips each, and every
one of them — embers, sparkle, trail, steam — is off at Focus Off and stays off.

*Consequence:* a new kind item joins `FriendlyBase.AMBIENT` by id — no scene rebuild. A body
that wants a different trail colour overrides `trail_colour()`. `ui_check`'s `juice` suite
asserts the row appears at three hits and lapses, embers and bliss obey Focus Mode, a trail is
world-space and hidden at rest, and a hot tub steams and stops.

## D41 — An upgraded item looks upgraded: the juice tier (2026-09-06)

**Decision.** Every item has a *juice tier*, 0..3, read from what the player has already earned
on it: `MasteryMath.juice_tier(rank, augment_levels)` reaches a tier by either ladder — rank
3 / 10 / 25 (the ranks the economy already treats as beats) or 1 / 6 / 15 augment levels (a
first buy, a committed build, a finished one). `Progression.juice_tier(item_id)` caches it and
drops the cache on a purchase, a rank, a reset or a load. The tier is presentation only; no
number in the economy reads it.

What the tier is worn as, on every body (`BaseDraggable.apply_juice`): a one-texel breathing
outline in the tier's colour (`ItemGlow`, a shader from the sprite's own alpha, so it fits
all hundred items with no second sprite), a wider and longer trail, and from tier 2 an aura of
chips (hearts on a kind item) rising off the thing. Harm runs gold → orange → red-orange →
white-hot; kind runs rose → magenta → lilac → white. Then per family: hit chips multiply and
take the tier's colour, every hit rings from tier 2 and throws white sparks at tier 3;
explosions grow (art and shockwave) and a primed charge sparks at its fuse; guns throw more
sparks and ring from tier 2; the sunbeam is a visible beam from above, wider by tier; the bolt
is wider and forks; the vortex has a swirl of chips orbiting the cursor; the fist sparks on a
punch; turrets' tracers thicken and take the colour, with a muzzle puff from tier 2; kind items
grow their ambient life by half per tier and throw hearts when he gets in; the trampoline rings.

**Why.** The owner's ask, and the genre's: a level-three bat has to *look* like a level-three
bat, or the upgrade tree is a spreadsheet. The art is one sprite per item and the generator is
blocked, so the upgrade is carried by light and motion instead — which also means every future
item gets it for free the day it is seeded.

**Budget.** The glow is a shader with `TIME` for its breath: zero CPU. Auras are GPU, four or
nine chips. The tier is read per hit from a cache. Focus Off stills the breath and every aura
and keeps the outline — the outline is information (which tier this is) and information stays.

*Consequence:* a body that wants its own colour ramp overrides `trail_colour()`; its aura glyph,
`aura_glyph()`. Anything that spawns bodies outside `ItemSpawner` must call `apply_juice()` when
upgrades land, or the look goes stale. Unit tests pin the ladders; `ui_check` spawns a rank-capped
bat and asserts the glow, the aura, and Focus Off stilling it.

## D42 — The budget is measured on a build, and the sounds that matter are recorded (2026-09-06)

**Decision, performance.** The performance budget (< 3% CPU idle, < 8% under load) is a claim
about an exported build, and it is now measured on one: `tools/perf_measure.ps1` runs the release
exe with the game's own staging flag (`-- --perf-stage=empty|idle|load`, in `main.gd`), reads the
process counters from outside for a minute after a warm-up, and prints the stage report the game
writes from inside (items on the desk, hits landed) — because the first cut placed the turret
seven hundred pixels from him on an ultrawide and measured furniture. The flag runs on its own
save slot and never writes settings; the exported build cannot run anything under `tools/`.

First measurement, 2026-09-06, Ryzen 7 7800X3D, release build, sixty-second windows:

| stage | one core | machine (16 threads) | GPU 3D | working set |
|---|---|---|---|---|
| empty (him alone) | 7.1 % | 0.44 % | 0.9 % | 420 MB |
| idle (hot tub steaming, rank-25 bat glowing) | 6.7 % | 0.42 % | 2.4 % | 310 MB |
| load (plus a pellet turret firing, 14 hits in 15 s) | 11.0 % | 0.69 % | 4.8 % | 324 MB |

The machine-wide figure is the one Task Manager shows and the one the budget means; all three
sit an order of magnitude under it. The working set is the number to watch next — three
hundred megabytes is a lot of desk toy — and every emitter, glow and trail added in D39–D41 is
inside these figures. Export templates for 4.7.2 are installed under the user's Godot folder;
`--export-release` needs them where `--export-pack` did not.

**Decision, sound.** Where a recorded sound is a clear win — a contact, a blast, a coin, a key, a
card, a landing — the game ships one: CC0 recordings from Kenney's packs, renamed to the id they
play as under `Assets/audio/<id>_<nnn>.ogg` (credits in `Assets/audio/CREDITS.txt`). Every file
found for an id is a variant and `play` picks one at random on top of the pitch spread. An id
with no files keeps its synthesised voice, so a missing import silences nothing. The chimes, his
breaths, the roar, the knockout clatter and the casino's wheel tick stay synthesised on purpose:
the owner likes them, and they are the game's own voice. Levels per id are in
`AudioManager.ASSET_GAIN_DB`, set once by ear from the code and **not yet heard by a person** —
that is the first thing to do with headphones on.

*Consequence:* D12 is amended, not replaced — synthesis is the fallback, not the placeholder.
A new recorded id is a row in `AudioManager.ASSETS` and files in the folder; nothing else.

## D43 — A turret looks at him and fires from its nozzle (2026-09-06)

**Decision.** Every turret carries a `muzzle` (the nozzle in its own texture pixels, read off
the art with a pixel probe), the way its art `faces`, and whether it `flips`. A gun mirrors to
face him and turns its barrel toward him within a per-turret cap — a gun swings, a mortar tips, a
coil, a lattice and a rack only lean — and the tracer, the muzzle sparks and the smoke leave from
`muzzle_position()`. Authored in `tools/seed_m36_turrets.gd`; the scenes are regenerated from it.

**Why.** The owner saw it: the sprite was static, never turned or mirrored, and the shot left
from the middle of the gun. A device that fires with no tell is the desk hurting him by itself.

*Consequence:* `ui_check` stands a pellet turret on each side of him and overhead and asserts the
mirror, the nozzle side and the cap. A new turret authors its three fields in the seed table.

## D44 — The art pass without a generator: plotted items, split turrets, pixel grime (2026-09-06)

**Decision.** With no image generator reachable from the session (no Retro Diffusion key in the
environment, no Codex tool exposed), the art pass shipped what can be drawn by hand in code and
deferred what cannot. Plotted, in the project palette with one texel of outline, at scale-table
size: the five hands-on kind items that had been placeholder polygons since M3.8 (feather duster,
tennis ball, party popper, warm towel, kite) and a bone-cream fist icon replacing the prototype
render (`art/tools/make_hands_on_items.py`). Cut, not drawn: four gun turrets' existing sprites
split into a base and a barrel along a per-turret line read off their pixels
(`art/tools/split_turret_barrels.py`), so the gun turns on its mount while the mount stays put —
the mortar and the three symmetric turrets keep one sprite. Shaded, not painted: grime is now a
per-texel hash of soot speckles that thicken with the value, over a deepening wash, in the same
shader as the flash and the wardrobe tints.

**Why.** The five items were the last placeholders a player could buy; a grey fist beside a
drawn hand looked like two games; a turret that only leaned was the owner's first complaint on
seeing one move; and grime as a flat tint read as a lighting bug rather than dirt.

**What still needs the generator** (worklist §3): the walk cycle and the other animation
families (`dance`, `relax`, `eat`, `catch`, `sleep`), and a proper two-part sprite for every
turret rather than a cut through the existing one. When it is back — Retro Diffusion via
`RD_API_KEY`, or the Codex plugin — the plotted five are the first things to replace; nothing
references their pixels.

> **Superseded in part by D45 (2026-09-07).** The premise of this entry is wrong: a generator
> *was* reachable from the session. Codex's native `imagegen` tool has since replaced the
> plotted five and the fist icon. What genuinely still needs Retro Diffusion is the animation
> work — Codex has no seed, no spritesheet return and none of the walking presets. The
> two-part turret art remains undone by choice rather than by blocking; D45 says why.

*Consequence:* `seed_friendly` picks a sprite up automatically when the PNG exists;
`seed_m36_turrets` hangs a Barrel when the split halves exist. Both tools are re-run, never
hand-edited, when art changes.

## D45 — The generator was reachable all along: Codex `imagegen` as the second art pipeline (2026-09-07)

**Decision.** D44 recorded that no image generator was exposed to an agent session and shipped
what could be plotted by hand instead. **That was wrong**, and it cost a session and left five
placeholder items in the shop. The Codex CLI installed on this machine carries a native
`imagegen` tool; `codex exec` drives it non-interactively, in its own fresh session, without
disturbing a Codex window the owner has open. The owner's own `~/.codex/generated_images`
already held eleven sessions' worth of output, which is the evidence that settled it.

The pipeline is now two-track. Retro Diffusion stays the primary route and is still the only
one that can do the animation work. Codex is the route that is *reachable from an agent
session*, and it covers still sprites:

    art/tools/codex_imagegen.sh <out.png> "<prompt>"     # one generation into art/raw/
    art/tools/keyout.py <raw> <out> --size 48            # the step remove_bg used to do
    art/tools/item_postprocess.py <keyed> <id> <height>  # unchanged

**What Codex cannot do**, and why the walk cycle is still blocked: there is no seed, so a
generation is not reproducible the way `art/prompts/items.md` requires — the prompt is the
whole record, which is why every prompt in that file is now written out in full rather than
summarised. There is no `remove_bg`, no `return_spritesheet`, and none of the
`rd_advanced_animation__*` presets. Getting a walk cycle out of it would mean prompting eight
frames and reconciling them by hand, which is a different and worse job than the one the
preset does.

**Two things in `keyout.py` are load-bearing.** The background is *sampled from the corners*
rather than assumed to be `#ff00ff` — the generator returns `#e30281`, `#f404cd`, `#c8287a`
and friends, and a hard-coded key would have kept every background in the batch. And alpha is
premultiplied before the reduction to 48px and unpremultiplied after, or the magenta sitting
in the transparent pixels averages back into the subject's rim as a pink fringe. That box
filter is the other half: `item_postprocess.py` resizes with NEAREST, which is right coming
from a 48px raw and returns noise coming from a 1254px one.

**Shipped under this decision**, all on `art/codex-imagegen-pass`:

| What | Where |
|---|---|
| The five hands-on kind items, generated, replacing D44's plots | `Assets/sprites/items/`, `art/prompts/items.md` |
| A fist icon that reads as a fist rather than a stack of bricks | `Assets/sprites/icons/fist.png` |
| Eight near-black items given the dual-tone treatment the spec asked for | assessment §3; mine, bowling ball, frying pan, gravity vortex, swarm launcher, tyre iron, laser lattice, implosion charge |
| Generator litter removed from three shipped buddy frames | `art/tools/clean_buddy_frames.py`, `art/src/_patch_frames.lua` |

**Why the dual-tone pass mattered most.** The game draws over whatever the player has behind
it. An item rendered in one dark material has no edge against a dark wallpaper and no internal
edge against itself, so it disappears twice over — and every one of those was bought from a
shop row the player could barely see. Each now carries a second bright material with real
area, on whichever part carries the silhouette, so it survives the downscale to a 28px row.

**Not done, deliberately: the two-part turret sprites** (handoff §B.4). Generating a base and a
barrel means re-deriving `barrel_pivot` and `muzzle` per turret, and only the pellet turret has
assertions in `ui_check`. The other three can be judged only by eye in a running game. Getting
them wrong makes shots leave from the wrong place, which trades a working feature for a nicer
picture. The existing halves are cut from one sprite and are therefore aligned by construction;
that is worth keeping until someone can watch a turret fire.

*Consequence:* `make_hands_on_items.py` now refuses to overwrite the generated sprites without
`--force` — it plotted the placeholders, and a habitual re-run would silently undo the pass.
D44's "no generator reachable" claim is superseded; do not plan around it.

## D46 — Grime is three patches of dirt, and never on his face (2026-09-07)

**Decision.** Grime is three fixed patches on his bones whose opacity rises with the value,
placed clear of his face, and the face sprite is no longer dirtied at all. It replaces D44's
per-texel soot speckle.

**Why it moved, which was the actual complaint.** D44 hashed `floor(UV / TEXTURE_PIXEL_SIZE)`
— the *atlas* texel. The Aseprite Wizard packs all 74 body frames into one 768x768 atlas, so
the speckle pattern was pinned to the atlas while the body walked across it a cell at a time.
Every frame change slid him onto different specks and the dirt crawled over him. That was
never a tuning problem: **anything positional in that shader has to be in frame-local
coordinates.** The shader now takes `grime_cell`, the frame's size in texels, and
`mod(texel, grime_cell)` is the position within the frame regardless of which cell the frame
occupies. `GrimeComponent` reads it off the SpriteFrames rather than hard-coding 96; left at
zero, which is every item in the game, the whole texture is the frame.

**Why the face is exempt now.** It was dirtied from M3 on the reasoning that a spotless face
on a filthy skeleton looks wrong. In practice the dirt obscured the one thing the expression
system exists to show — and his expression is how he asks to be cleaned, so the grime was
hiding the prompt to remove the grime.

**Two details that are not arbitrary.** The patches combine with `max`, not a sum: two
overlapping ellipses adding up produce a bright seam where they cross, which reads as a third
shape rather than two patches. And the falloff is quantised into three flat steps, because a
continuous gradient across a 96px frame is an airbrush, and an airbrushed smudge on a
hand-outlined skeleton reads as a rendering fault.

*Consequence:* placement was judged by simulating the shader in Python over four frames at
four grime levels — the mask, the frame-local UV and the quantisation are all cheap to
reproduce, and the loop is seconds rather than a launch. `loop_check` asserts the face stays
clean and that `grime_cell` is non-zero; at zero the patches crawl again and nothing else in
the suite would notice.

## D47 — A power aims at him; your hands still work on your toys (2026-09-07)

**Decision.** An equipped cursor power no longer swallows every left click. Three rules:

- Over a **spawned item**, the power declines and the click falls through, so you pick the
  thing up. Powers are for him, not for the props.
- Over **him** or over empty space, the power fires. He is not a spawned item, so nothing
  needs a special case to say he is the target.
- **Shift suspends the power** for that click, so he can still be dragged and thrown without
  holstering. Shift already means "ignore the special behaviour, do the plain thing" on the
  right button (`BaseDraggable.click_would_bin`), so this costs the player one idea.

Plus two ways out that are not a trip into the panel: **Escape** holsters before it opens the
pause menu — backing out of the innermost thing first — and the HUD grows an **armed chip**
naming what you are holding, which holsters in one click.

**Why.** The old code consumed every left click and its own comment called the question "a
real design question… left for the M2 playtest". The owner reached it first from the other
side: equipping and unequipping is annoying, and you cannot use anything else while armed.
Being armed silently changes what a left click does, which made it the one piece of hidden
state in the game a player could act on by accident.

**Then: none of it is visible.** The owner's second note on this was that the scheme "isn't
necessarily obvious to a new user", which is the right objection — a control scheme that has
to be discovered by experiment is one most players will conclude is broken. They will try to
drag him, shoot him instead, and stop equipping powers. So the rules are taught the same way
the removal gestures are (`HINT_REMOVAL`): a one-off toast the first time anything is
equipped, remembered in `Settings` so it survives the Reincarnation that wipes the save.

Which parts need teaching is not symmetric. *Clicking a toy picks it up* needs none — that is
what clicking a toy already did, so the rule is invisible in the good sense. *Esc* is written
on the chip itself rather than left in a tooltip, because a tooltip has to be found by
hovering something the player does not yet know is interactive, and that is the wrong place
for the one instruction they need in order to stop. *Shift* is the line that earns the toast:
nothing anywhere suggests that holding a key gives you your plain hands back.

*Consequence:* the Escape precedence lives in `EscMenu`, not in a second handler on the
spawner — two nodes racing for one key across a CanvasLayer and the world is decided by tree
order, which is not a thing to hang a control scheme on. `ItemSpawner.holster_power()` is the
one call behind both exits. The chip carries a 32px icon in a 32px box because the art size
contract (D27) forbids stepping it down into the 22px row the other footer buttons use, and
`ui_check` measures the chip against the HUD's column for **every** power in the roster:
"Magnifying Glass" comes to 257px of a 268px column, and a Button grows to fit rather than
clipping, so a longer name would silently widen the whole HUD.

*Also fixed on the way:* `ui_check` captured and restored six `Settings` fields but not
`hints_seen`, and the suite both puts an item on the desk and now equips a power — each of
which fires a one-off tip that marks itself seen and saves. A developer would have quietly
lost the tips they had not met yet and only found out by never being taught the controls. The
list is duplicated into `_restore`, not aliased.

## D48 — The big payout numbers step around the HUD (2026-09-07)

**Decision.** A floating number whose rise would cross the HUD's box is moved sideways past
it, and only downward when the play area is too narrow to step aside in.

**Why not the other two options.** Shrinking the HUD trades a permanent loss of readable state
for a transient collision. Drawing the numbers on top hides the purse and the meter at exactly
the moment the player is being paid, which is when those two are worth watching. Moving the
number keeps both, and it only fires on the small fraction of payouts that land in one corner.

Sideways rather than down because these rise as they live: pushing a number down puts it back
under the HUD a moment later.

*Consequence:* `HUD` joins a group and `FXLayer` reads `shell_rect()` through it — screen
pixels, not canvas pixels, since the shell is on a scaled CanvasLayer. The read is capped at
four a second rather than done per number: `hover_drawer.gd` records that drawers polling
`screen_rect()` every frame for eight hours was the largest idle cost in the shell, and
numbers can spawn many times a second. `ui_check` asserts against the HUD's own reported rect
rather than a constant, because a hard-coded rect passes at 1x and lies at 3x.

## D49 — The window moves, and floating on top is a setting (2026-09-07)

**Decision.** Drag the background to move the window. The play-area anchor defaults to *free*
rather than bottom-right, and the four corners become a one-click tidy-up instead of the only
places the game can sit. Always-on-top becomes a setting, still defaulting to on.

**Why.** The window is borderless, so it has no title bar and no OS grab handle — the four
corners the settings page offered were literally the only positions it could occupy. A
desktop toy that cannot be put where its owner wants it is in the way rather than in the
corner. Always-on-top was a fact of the build for the same kind of reason and not a
considered one: sharing a screen, recording, or wanting him behind the editor for ten
minutes are all reasonable, and the alternative was quitting the game.

**Three details that are load-bearing.**

*The gesture is `_unhandled_input`*, so a window drag is by definition a press nothing else
wanted — not the buddy, not a toy, not a panel, not an armed cursor power. That one choice is
what stops it fighting every other gesture in the game, and it is why the rule is short
enough to say: drag the *background*.

*It reads the OS cursor*, through `DisplayServer.mouse_get_position()`, which this project
otherwise forbids (`ui_check` cannot move a real cursor, so anything built on it cannot be
tested). Here it is correct and unavoidable: the window moves out from under the cursor as it
is dragged, so a motion event's own position is relative to a frame that is itself moving.
The consequence is that this gesture belongs to `docs/test-matrix.md` rather than to a suite,
which is already true of every other overlay behaviour.

*`Corner.FREE` now falls back to the bottom-right* rather than the top-left. That fallback is
only ever reached to invent a *first* home — a fresh install, or a saved rect that no longer
fits its monitor — because a free window otherwise uses the position it was dragged to.
Bottom-right because out of the way is the right first guess for something that lives on a
desktop while its owner works, and because the top-left is where most people keep the thing
they are actually doing.

*Consequence:* dragging clears the corner anchor, since putting the window somewhere by hand
is a statement about where it should be and leaving the anchor set would snap it back on the
next apply. Always-on-top is applied through `apply_window_configuration` like every other
window setting rather than by flipping the flag at the call site: that function is the one
place that knows about the borderless outer-size quirk, and a second writer of window flags
is how the two-pixel vibration bug got in.

## D50 — Menu size in quarter steps, with the cost stated (2026-09-07)

**Decision.** `Settings.ui_scale` becomes a float. Auto, or any quarter step between 1x and
3x. This relaxes **D23**, which said whole numbers only, and the reasoning behind D23 has not
changed — only who gets to weigh it.

**Why relax it.** D23 is right that 1.5x on a pixel face is a blurry pixel face: the shell is
drawn as pixel art, a fractional factor resamples it, and some texels come out a pixel wider
than their neighbours. But the ladder it left behind was too coarse to be a preference. On a
1440p monitor, 1x, 2x and 3x are "too small", "about right" and "enormous" — and where "about
right" falls depends on how far away somebody is sitting, which the game cannot measure. A
setting with three rungs, one of which is unusable, is not really a setting.

**What keeps the default sharp.** Auto only ever chooses a whole number, so nothing the game
picks on the player's behalf costs them a crisp shell. The in-between rungs exist to be asked
for, and the settings note says plainly that the whole numbers are the sharp ones rather than
hiding the trade.

**A quiet improvement that came with it.** `factor_for` steps a pinned factor down until the
shell fits — the guard from D23 that stops a 2x pin on the smallest play area putting the tab
strip off-screen. It used to give up a whole number at a time, which meant the only way down
from 2x was 1x. It now gives up a quarter at a time, so a window that cannot quite take 2x
gets 1.75x rather than half the size it asked for.

*Consequence:* the four scale buttons become a `−` / `+` / `Auto` stepper, matching the
volume and play-area rows. Stepping from Auto starts at the factor actually on screen, or
pressing `+` on an auto-2x shell would drop it to 1.25x and read as the button working
backwards. `Settings` clamps with literals rather than `UIScale.MIN/MAX/STEP`, because an
autoload that references a global class name before the class cache is warm fails to parse
and takes the game with it — the same rule the window enums already follow. Old settings
files hold an int here, which reads back as a float unchanged.

## Recommendations not yet decided

Carried in the spec, owner's call before they matter:

- **Price ~$7.99**, one-time purchase, no microtransactions or ads, with that stated explicitly
  on the store page (a game full of currencies reads as free-to-play otherwise). Genre band is
  $3.99–$7.99; the closest comparable sold ~550k units at $7.
- **Gore-free**, cartoon-violence positioning for an unrestricted rating.
- **Windows-first.** macOS transparent-window behaviour differs enough to be a separate project.
- **CJK localisation at launch** — the closest comparable took 46% of sales from Asia, and this
  game is nearly text-free.
- **Cosmetic supporter pack (~$4) post-launch**, no gated content (11% attach rate on the
  comparable).
