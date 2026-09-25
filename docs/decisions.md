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

## D51 — A test writes its preferences somewhere disposable (2026-09-07)

**Decision.** `Settings.config_path` is a variable, not a constant. Every suite and capture
tool points it at its own file on the first line it runs, before it changes anything. The
in-memory capture-and-restore stays; the redirect is what makes it safe.

**Why.** Capture-and-restore only covers a run that reaches its last line. `ui_check` forces
Focus Mode Off, clicks real controls whose handlers call `save_settings()`, and puts the
developer's values back at the end — so a timeout, a parse error introduced mid-edit, or a
Ctrl-C leaves the file holding whatever the suite was using.

That is not hypothetical. It happened during this session: a killed run left `focus_intensity`
at Off in the owner's own `settings.cfg`, and because Focus Off deliberately silences the FX
layer, the next launch looked like **the payout numbers had stopped working**. The report was
"the text pop ups are no longer appearing", and the code was fine. A suite that can silently
reconfigure the game it is testing will eventually be believed over the game.

**The door was wider than it looked.** `loop_check` and `audit_shots` never call
`save_settings()` and still write the file, because a one-off hint marks itself seen and
saves — and both put items on the desk, which fires one. That is also how `hints_seen` got
polluted before anyone noticed.

*Consequence:* `tools/capture_window.gd` does the redirect in `_use_capture_slot()`, one level
up from the five tools that share it, next to the save-slot isolation it already did for
exactly the same reason. `ui_check` asserts on its first suite that the redirect is still in
place — circular-looking, but the failure it catches is somebody deleting that line, and the
cost of missing it is measured in an afternoon spent debugging the wrong thing.

## D52 — One grip moves the window, anywhere on the desktop (2026-09-07)

**Decision.** A 52x14 grip at the top centre of the window is the only place it can be picked
up, and a dragged window is left wherever it is put — including on another monitor, including
straddling a seam. Supersedes both load-bearing halves of **D49**.

**Why the background was wrong.** D49 armed the move from `_unhandled_input`, reasoning that
a press nothing else claimed is by definition the background. That is true and it was still
wrong: an overlay is mostly empty space, so "anywhere nothing claimed" is very nearly
everywhere. The owner went to click something in the play area, missed the thing, and moved
the window. A gesture that large cannot be a deliberate one.

Top centre because it is where a title bar lives on every other window on the desktop, and
because it is the one edge of the shell nothing else occupies — the HUD column is top-left and
the tab strip top-right. Either corner would have meant reserving a strip in both and
re-homing two auto-hide drawers.

**Why the snap was wrong, and why fixing the drag alone would not have helped.** The clamp
lived in three places, and the obvious one was the least important. `_commit_window_move`
clamped against `_validated_monitor()` — which is `Settings.monitor_id`, the *saved* monitor,
not the one the window is on. But even fixing that changes nothing visible, because
`WindowLayout.target_rect` re-clamped every FREE position to a single usable rect on **every
apply**, and `needs_revalidation` judged the saved rect against that same one screen. A size
step, a Focus Mode toggle or the next boot would each have hauled the window back. There was a
fourth: `set_play_area_size` cleared the saved rect outright, so pressing `+` teleported a
window the player had carefully dragged.

So the geometry moved into `WindowLayout` as pure, DisplayServer-free helpers —
`screen_for_rect`, `clamp_to_desktop`, `needs_revalidation_across` — and `monitor_id` now
follows the window rather than overruling it. Nothing is snapped: a window overlapping any
screen by `MIN_VISIBLE` is left exactly where it was put, and only one that has escaped every
screen is pulled back, to the nearest.

`MIN_VISIBLE` is sized to keep **the grip** reachable rather than to keep some pixels visible:
the grip is 14 UI px inset 2 at a shell scale of up to 3x (D50), so 90 vertical pixels is the
shallowest sliver that still contains it.

*Consequence:* the cursor position is an **argument** to `begin/update/end_window_drag`, not
read inside them. That is what makes the gesture testable at all — no synthetic event can move
a real cursor, so a gesture that reads `DisplayServer.mouse_get_position()` itself is
untestable by construction. `window_check` now drags the window for real, including onto a
second monitor when the machine has one, and the unit suite covers the pure geometry against
synthetic screen lists that include a monitor to the *left* of primary, whose usable rect has
a negative origin — the layout that is wrong on a common setup and right on the developer's.

*Found on the way:* `window_check` looked the HUD up as `"Hud"`, but the node is named `"HUD"`
and the lookup is case-sensitive. It had been silently null for the life of that suite, so the
"no part of the shell leaves the window" sweep had never measured the HUD at all. Fixing it
immediately reported eighteen escapes, every one of them the auto-hide drawer parked off the
left edge by design — so the sweep now pins both drawers first, since the question is about
the shell while it is on screen.

## D53 — The juice ladder spans the whole of mastery (2026-09-07)

**Decision.** Five juice tiers instead of three, at ranks **3 / 10 / 25 / 50 / 100** and
augment levels **1 / 10 / 20 / 35 / 55**. Rescales D41.

**Why.** The owner: "the augmentation to the appearance of items being levels 1 to 3 is stupid
because the mastery extends well beyond that". Measured against the pacing simulator, they
were understating it:

| | |
|---|---|
| Hands-on play to rank 3, the first tier | 41 seconds |
| Hands-on play to rank 25, the **top** tier | 10 min 22 s |
| Hands-on play to rank 100, the cap | 49 min 07 s |
| Share of the XP-to-cap spent at the old top tier | 10.9% |
| Items past rank 3 at the end of a first run | 91 of 91 |

So the last look arrived after a tenth of the grind and the remaining 89% changed nothing,
while the first tier was a milestone that literally nothing failed.

**There is a maximum, and the brief assumed there was not.** `MasteryMath.MAX_RANK` is 100 and
is clamped inside `rank_for_xp`. The 200 in `mastery_pool_thresholds` is the *shared pool* —
ranks summed across the whole roster, measured at 1,525 by hour 72 — not a rank any item can
hold. The top rung is therefore the cap itself.

**The rungs are the economy's own beats**, not new numbers: the Tier 2 branch at 10, the
automation capstone at 25, the personal payout bonus at 50, and the cap. The look changes on a
moment the player is already being told about. Effort between them is near-uniform because the
curve is `100 * r^1.6`, so doubling a rank always costs 3.03x — the steps are x4.3, x3.0, x3.0
and the measured gaps are 3:54, 6:28, 13:34, 25:11, each roughly double the last.

**The augment ladder had the identical defect.** A typical item has a *median of 60 buyable
levels*, so the old top of 15 stopped at 25% of maximum — the same quarter-way stop as rank 25.

*Consequence, and the trap this nearly shipped with:* `GLOW_STRENGTH` and `AURA_AMOUNT` are
indexed by tier and were four entries read **unclamped**, so a fifth tier is an out-of-range on
the item-spawn path — every item in the game. Both now cover the ladder and are read through a
clamp. Six effect gates spelled `tier >= 2` and `tier >= 3` meaning "well upgraded" and "the
top", and silently changed meaning when the ladder grew; they read `MasteryMath.JUICE_MID` and
`JUICE_TOP` now. `TRAIL_TIER_WIDTH` drops from 2.5 to 1.5 so the widest trail is the 15px it
always was rather than growing by two thirds because there are more steps to climb. No save
migration: the tier is presentation only and is never persisted.

## D54 — The hit-stop freezes physics instead of squeezing time (2026-09-07)

**Decision.** `FXLayer._hit_stop` calls `PhysicsServer2D.set_active(false)` for its handful of
frames instead of setting `Engine.time_scale = 0.05`. Four smaller force bugs are fixed
alongside it. This is the cause of the rebounding the owner reported.

**Why it rebounded.** Godot hands the 2D solver `physics_step * time_scale`, so `0.05` did not
slow the world so much as shrink the timestep from 1/60 s to 1/1200 s. A `PinJoint2D`'s
positional correction is `error * bias / step`, so the drag joint's authority went up
**twentyfold** for the duration — while `BaseDraggable._physics_process` went on chasing the
real cursor in real time, opening fresh error on every one of those frames. The joint turned
that error into velocity, and the body kept it when time returned to 1.0.

It was armed by the very contact it amplified, which makes it a positive feedback loop: a
bigger hit bought a longer stop, and a longer stop bought a bigger launch. Measured on a rig
carrying the shipped bat and buddy, an eight-frame stop threw him at **24,729 px/s**; freezing
instead of squeezing gives **2,056**.

**The joint parameters are not the problem and were not changed.** `joint_softness = 1.0`,
`joint_bias = 0.2`, `follow_lerp = 1.0` are byte-identical to the prototype the owner
remembers as near-perfect. One investigation proposed "restoring" 0.9 / 0.0 / 0.5; three
independent reviews checked the history and found that configuration never shipped in the
build being remembered. Raising `joint_bias` trades tracking lag for release violence one for
one, so tightening it would have made the reported symptom worse.

**Four more force bugs, all found by measurement:**

- **Every blast applied a torque.** `apply_impulse(dir * strength, Vector2.ZERO)` offsets from
  the body *origin*, not "no offset" — and the buddy's centre of mass is authored at (0, 10),
  so a 10,000 sideways impulse spun him at 16 rad/s, two and a half turns a second, at the
  same linear speed `apply_central_impulse` gives with zero spin. The same one-word mistake
  was in `npc_base.gd` twice, so a goose peck and a gorilla slam did it too. That was most of
  the "weird sudden movement".
- **Every turret shot fired straight up at full strength.** The blast was centred exactly on
  `target.global_position`, so `to_body` was the zero vector: the direction fell through to
  the `Vector2.UP` fallback *and* the falloff returned the undiminished `blast_force`. Six of
  the eight turrets fire a single pellet, so a running turret simply levitated him. The impact
  is now inset toward the muzzle. The `pellets > 1` gate on spread went with it — a nail gun
  fires one nail and declares a spread, and that spread was dead data.
- **The fist erased its own punch.** `_physics_process` assigned `linear_velocity` every frame,
  which both stopped an 11.5 kg body ever being slowed by what it hit and silently discarded
  the `punch_impulse` applied earlier in the same frame. It steers toward the wanted velocity
  now. This is the starter power, so its damage augment had been a placebo for every new player.
- **A cast-iron frying pan was 85% elastic** and a beach ball 95%. Both are weapons in the Play
  tab. 0.2 and 0.7.

*Consequence:* `BaseDraggable.physics_frozen` is a static flag set by `FXLayer`, because
`PhysicsServer2D.set_active` is write-only and there is no `is_active()` to ask. The handle
chase is guarded by it — `_physics_process` is still called during the freeze, and without the
guard the handle teleports to the cursor on every frozen frame and hands the joint all of that
error at once when physics resumes, which is the same bug through the other door. A
`max_drag_speed` / `max_drag_spin` backstop was added at 4500 / 40; at a fast 1200 px/s hand
the bat peaks near 1,600, so it never fires in play and exists for the next surprise. And
`_exit_tree` restores physics unconditionally: the resume sat after an `await`, so a layer
freed mid-stop left the whole game frozen.

*Not done, and measured rather than guessed:* the collision-shape audit found two systematic
faults and a list of individual offenders. `seed_friendly.gd` draws its sprites at 2x and
writes the collider extent unscaled while `seed_m35_roster.gd` multiplies by `ART_SCALE`, so 28
of 31 kind items have colliders at 0.33–0.86 of their art. Separately the nunchaku (2%
coverage), the monitor, keyboard, stapler, cricket bat, machete, cleaver, chainsaw and flail
overhang their art by 6–20 world px, and the greatsword, sickle, katar and rail gun were
authored against an orientation their sprite does not have. Seven scenes are also frozen
against sprites replaced in D45. None of that is a one-line fix and all of it changes how the
game plays, so it is left for the owner to direct rather than guessed at in a sweep. The
layers themselves are fine: 97 bodies on layer 4 / mask 7, the buddy on 2 / 5.

## D55 — The collider is the picture (2026-09-07)

**Decision.** A derived collider is the sprite's own opaque bounds at the sprite's scale, in
every seed tool, never a number somebody typed. `loop_check` asserts it for every body with a
single collider.

**Why.** The owner: "just simply make the collision of the items in the world match the shape
of the object." The fault was one line in two files. `seed_friendly.gd` and
`seed_m3_content.gd` drew their sprites at 2x and wrote a hand-typed art-pixel extent straight
into a world-pixel shape, while `item_body_builder.gd` and `seed_m35_roster.gd` multiplied by
`ART_SCALE`. So 28 of 31 kind items had a collider between a third and six-sevenths of what
you could see, and you could push a bat most of the way into a hot tub before anything
touched. A typed extent also goes stale when the art is regenerated and the scene is not,
which is what happened to seven scenes in the D45 art pass. Afterwards 35 of 36 Friendly and
Props colliders match their art on both axes. The trampoline's is deliberately the mat.

*Consequence:* the guard instantiates every item and checks the 43 single-collider bodies.
Nothing in 1,000 assertions had ever looked at a collision shape. The 42 bodies with several
colliders were left alone on purpose, because a bat is a capsule and a rect rather than a box
around both, and that geometry is D25. They became D61. The mine was corrected by hand with a
two-line size edit, because the seeder could only rewrite it with `--force`, which rewrites 63
files including augment data that later milestones refined. D61 added `--only` for that.

## D56 — Guns you hold: left carries, right fires, and the gun aims itself (2026-09-25)

**Decision.** A new kind of thing on the desk: a gun you pick up with the left button and
fire with the right, which points itself at him — `HeldGun`, built on `WeaponBase`, in a new
harm drawer, `ItemData.CATEGORY_GUN` ("Guns"). Five hurt him and cost Bones (revolver, SMG,
pump shotgun, hunting rifle, blunderbuss); two are kind, cost Hearts and sit under Care beside
the sponge (water pistol, bubble blaster). The cursor pistol, shotgun and minigun stay: they
are a mode the cursor becomes, and these are objects.

**The input grammar, shared by every stream that adds a toy:**

- **Left = hold / carry.** Unchanged.
- **Right while holding = the item's action** — fire, squirt, prime, pull, squeeze.
  Explosives already worked this way, so this names a rule rather than inventing one.
- **Shift+Right = bin**, never claimed by anything (`BaseDraggable.click_would_bin`).
- Every item with a non-default gesture fills `ItemData.controls` with one short line
  ("Hold · Right-click to fire", "Hold · Hold right to fire").

**Why.** The owner, after a session spent mostly on the cursor guns: "it would be cool to have
guns not only as cursor powers but actual weapons in the game, they would probably have to
always auto aim at the character, but be affected by recoil and be shot with right click when
held with left click, stabilised automatically but with physics a bit so it has weight". Each
clause is a mechanism:

- *Auto aim, with weight.* A PD controller on **torque** about the grip — never on `rotation`
  and never by overwriting `angular_velocity`, which is how D54's fist erased its own punch.
  The gains are scaled by the moment of inertia about the grip, so every gun has the natural
  frequency it was authored with whatever it weighs; the correction is capped at an authored
  angular acceleration, which is the weight — below the cap the aim is a spring, above it the
  gun swings and has to be caught. Gravity about the grip is cancelled on top. It lays the
  **barrel line** on his centre of mass, not the grip: the barrel sits above the hand.
- *Affected by recoil.* A shot fires along the barrel's **actual** direction, so a gun still
  swinging back onto him shoots where it points. The kick is an impulse backwards at the muzzle
  plus a climb; a full-auto burst also accumulates an aim offset, so a long one sprays and a
  tapped one stays on him.
- *Right click when held.* `right_click_is_mine()`; the release is read in `_input`, enabled
  only while the trigger is down, so a release a panel consumes still stops the stream.
- *Never upside down.* Aimed left it mirrors — about the **barrel's own axis through the
  grip**. Any other mirror moves either the joint's anchor (a yank, D54 again) or the barrel (a
  jump in the aim). The scenes are built with the body's origin *at* the grip, which makes the
  mirror a sign flip on every child's y.
- *He notices.* A harm gun on him emits `threat_changed(&"aim", ...)` on the edges and every
  half second while it holds; the expression brain's `aimed_at` row has him cower, shocked and
  shivering, until it comes off. A kind gun is no threat. The Nervous personality flinches once
  per aim, not once per refresh.

**Measured,** in the new `gun_check` suite on a stepped rig — settle from a quarter turn off /
kick of one shot / back on him:

| | settle | kick | back | |
|---|---|---|---|---|
| Revolver | 0.25 s | 22° | 0.27 s | semi, 0.42 s |
| SMG | 0.23 s | 2° | 0.07 s | 85 ms, a burst climbs to 23° |
| Pump shotgun | 0.30 s | 26° | 0.33 s | 6 pellets, pump at 0.4 s |
| Hunting rifle | 0.35 s | 33° | 0.42 s | flings him, bolt at 0.55 s |
| Blunderbuss | 0.35 s | 67° | 0.47 s | 9 pellets over 40° |
| Water pistol | 0.23 s | | | squirts, scrubs 0.12 grime/s |
| Bubble blaster | 0.25 s | | | a bubble every 0.4 s |

Every gun is back on him well inside its own fire interval, so a player who waits for the gun
hits, and one who does not shoots where the kick left it — which is the feature.

**What it turned up.** The first recoil measurement was **exactly 0.0°**. D54 added a
`max_drag_speed` / `max_drag_spin` backstop that wrote `linear_velocity` and `angular_velocity`
on every frame a body was held — and the getters return what the server reported after the
*previous* step, so the write replaced the body's real velocity with a stale copy and erased
any impulse applied since. A click runs before the frame's `_physics_process`, so every
semi-automatic shot's kick vanished, while a full-auto one fired after the backstop and
survived. It is the fist's bug arriving through the backstop added in the same commit, and it
also meant an explosion could not knock a bat out of your hand. The backstop now writes only
when the ceiling is exceeded, which it never is in play. Rule: **never write a physics body's
velocity back unconditionally; the getter is a copy from the last step.**

A second, smaller one: a stream that scheduled its next shot from the frame that fired rounded
every gap up to whole physics frames, so an 85 ms gun fired every 100 ms. It keeps its phase
now (next = last *due* + gap, within a frame so an idle trigger banks nothing).

**Kind guns pay no Bones.** A kind gun's contact multiplier is zero, so Bonehead's
`_queue_hit` drops the hit — a water pistol bounced off his skull is a toy landing on him. The
suite throws a revolver and a water pistol at him the same way: the first is a hit, the second
is not.

**The trees.** Damage, payout and fire rate (`cooldown_mult`) on all seven; the harm guns add
Weight (`mass_mult`, read by `WeaponBase`: a heavier gun is kicked less by the same impulse)
and Steady (`recoil_mult`, read by `HeldGun._recoil` and nowhere else). Both are measured
rather than trusted — ten levels of Steady take the revolver from 22.4° to 6.7° — because an
augment nothing reads has shipped here twice. Capstones by `seed_m35_engine`'s rules, in Hearts.

**Pacing,** 4/4 both ways. Against the same run without the guns: first automation 12:55 →
13:48 of play, worst purchase gap 1:29 → 1:30, first Reincarnation 9:16 → 9:46, worst ramp
1.2x → 1.0x. The half hour is structural — seven more things to spread play over — and leaves
fourteen minutes under the ten-hour ceiling. The next batch of items has to be run against it.

*Consequence:* a new gun is a row in `tools/seed_m39_guns.gd`, in the grid's own pixel
coordinates, and a text grid in `art/pixel/`. `HeldGun` does no per-frame work while it is on
the desk beyond the base class's trail; the aim runs only while it is held, and `_input` only
while the trigger is down. `gun_check` must stay green, and like every suite it takes two
arguments to `_check`.

*Not done:* the slingshot (the brief's stretch — plant the frame, draw the pouch, dotted
trajectory) is left for a later pass. Turning round is instant; a quick roll of the sprite
about the barrel would sell it and costs one tween. The two kind guns have no ambient life.

## D57 — Fidget toys: click zones, gestures, and one grammar for everything held (2026-09-25)

**Decision.** Toys get parts you can work, not just a body you can throw. A `GestureZones`
component on any body carries named zones authored in art pixels, turns the mouse into
gestures, and hands them to the toy's script. Five toys ship on it: bubble wrap, a fidget
spinner, a jack-in-the-box, a fortune ball and a stress ball.

**The owner's ask**, verbatim: "a lot more creative fidget style click and drag objects we can
do that utilise a combination of left and right click, utilise different click zones etc." A
second button and a second place to click are worth nothing if every toy spends them
differently, so the principle came first and is shared with the held guns being built beside
this:

- **Left = hold / carry.** Unchanged — the pin joint and the handle that chases the mouse.
- **Right while holding = the item's action**: squeeze, fire, prime. Explosives already did
  this; it is now the rule rather than their habit.
- **Right on a zone of an item you are not holding = that zone's action**: crank, flick, pop,
  read. A zone under the cursor still wins while the item is held, so a spinner can be spun
  in the hand rather than binned from it.
- **Left on a zone that claims it = that zone's action instead of a grab**, and a zone may
  claim only the *tap*: press a bubble and drag, and you have picked up the sheet.
- **Shift+Right = bin**, and nothing may claim it. D24's override, unchanged.
- **Hovering a zone shows the pointing hand**, and the rest of the toy the grab, driven from
  motion events and never from `get_mouse_position()`. A zone nobody can see is a zone nobody
  uses.

**The framework.** A component rather than a base class, because the fidget layer has to
compose with both halves of the roster: `FriendlyBase` owns the Hearts banking, juice and
ambient life, `WeaponBase` owns the damage multiplier, and a class both would need is a class
neither can have. `BaseDraggable` gained one field and three lines: the zones see every event
first and may claim a press. The gestures are tap, hold, drag, cross (entering another zone
mid-stroke, sampled along the segment so a fast swipe cannot skip a bubble), crank (angle
accumulated about a pivot), flick (release velocity), the held action, and carry (the body
moved in the hand). Zones live in the body's own frame, so they turn with it and flip with
`mirrored`; the suite clicks a crank on a box turned a quarter and mirrored. `FidgetToy` is the
kind side's convenience on top — `pay_act` for the player's hand (an act: combo, contracts,
Dollars), `pay_sustained` for his own play or a toy running on its own (a trickle, for exactly
the reasons `IdleBrain` gives), and the two idle hooks.

**He plays with them.** `IdleBrain.ROUTINE_FIDGET` is any toy with `idle_appeal()` and
`idle_use(buddy)`: the brain walks him there and the toy does the using on the think tick, so
the brain still pays for nothing it did not do. He hops on the bubble wrap, flicks the
spinner when it runs down, winds the jack a turn at a time, shakes and reads the ball, and
squeezes the stress ball. Every Play toy is still something he uses (`0f04aa5`). His face has
eight new rows — `fiddling`, `entranced`, `amused`, `startled`, `laugh` and three answers —
fed by one new bus signal, `fidget_event`, through `ExpressionBrain.FIDGET_ROWS`. A toy worked
by hand answers for itself: without that, the Play tab's generic reaction would have had him
celebrating a catch every time a bubble popped across the desk.

| Toy | The verb | His | Pays |
|---|---|---|---|
| Bubble wrap, 120 | tap a bubble; right-stroke a run | lands on it | 2 a pop, one back every 4 s |
| Stress ball, 450 | hold right to squeeze, let go | catches a throw | 5 by squeeze, 10 a catch |
| Fidget spinner, 1,200 | right-swipe an arm | stares, flicks it | 0.8/s at full spin, watched |
| Fortune ball, 2,400 | shake it, right-click to read | believes it | 14 for a yes |
| Jack-in-the-box, 6,000 | right-circle the crank; right-tap the lid | startles, laughs | 30, if he laughs |

Each has three tier-1 nodes and a capstone by the M3.5 rules, and every key is one its own
script reads — value, Hearts, and "time between uses" meaning whatever that is for the toy (a
bubble grows back sooner, a spinner runs down slower, the tune is shorter). Pacing with the
five in: first automation 14:40 of play (was 12:55), worst dead stretch 1:07 (was 1:29), first
Reincarnation 9:23 (was 9:16). All inside their targets.

**What it cost to find, measured.** A thrown ball is reported touching him one physics step
*after* the step that stopped it, so a one-frame speed memory read a 900 px/s throw as 36 and
nothing was ever caught; the stress ball keeps a decaying peak instead. His first hop at the
bubble wrap was aimed across it, and a skeleton moving sideways against a sheet of plastic
shoves it: three hops, three misses, the sheet 490 px further on. He hops straight up now and
the brain's lean carries him over — and the sheet cannot turn, because free to, it stood on its
edge the first time and "on top of it" stopped meaning anything.

**Budget.** Nothing per frame. `GestureZones` has no frame callback at all — the suite reads
its method list — and the hold timer runs only while a button is down. A toy runs `_process`
only while it is doing something (spinning, winding, showing an answer, being squeezed) and
turns it off itself; the suite asserts all five are silent at rest.

*Consequence:* a new fidget is a grid in `art/pixel/`, a row in `tools/seed_m39_fidgets.gd`
(zones included) and a script under `Scripts/Bodies/Fidgets/`; `GestureZones`' class comment is
the API. `ItemData.controls` is on the shop's detail pane (a `HowTo` strip) and taught once per
toy as a toast the first time it lands, so a new toy's gestures are never a secret. The next
five it is ready for:

- **Slinky** — hold one end; right plants it on the desk while the cursor stretches the other,
  and letting go walks it.
- **Newton's cradle** — right-drag an end ball back and let go; the far one answers.
- **Yo-yo** — carry it; right throws it down the string and back, a flick sends it round.
- **Pull-back car** — right-drag it backwards to wind it, let go and it drives at him.
- **Wind-up teeth** — crank the key; they chatter across the desk toward him.

## D58 — Every room of the Arcade is a cabinet, and 1.25x is uneven rather than soft (2026-09-25)

**Decision.** Each of the Arcade's five rooms is built by one class, `Cabinet`, as the same
four sections in the same order: a **marquee** (the room's name in the display face, lit in a
colour of its own, with the display the machine talks through set into it), the **stage** (the
game, at one height in every room), a **paytable** strip, and a **deck** (the stake stepper and
the one key that matters). One outer frame, and each section below the marquee owns a single
rule across its top — never a frame inside a frame. The room strip's keys are lit in their
room's colour, so the row reads as five machines with one switched on. The wardrobe and the
back room follow the same grammar. Relaxes D37's footer into the deck, and keeps its promise:
every stage is `Cabinet.STAGE` tall, so no key moves when the room changes.

**Why.** The owner: "less rounded boxes and more clear minigame sections". A room was a tile
holding a sunk well holding the machine — three nested frames of equal weight — so nothing read
as *the machine*; the bet and the key floated in a footer that belonged to no section, Three
Ghosts was three 96px windows in an empty well, and blackjack's Hit and Stand sat on the felt
while Deal sat outside it. Now the reels are one pane of glass at 192px divided by two rules,
the cards are 80x124 and fill the table's height, Hit, Stand and Deal are one row on the deck,
and the wardrobe's ten tall rows that scrolled off the card are two rails of swatches with the
chosen one on the deck.

**The marquee colours are identity, not meaning** — the one exception to Bonecard's "colour
only where it carries meaning", and fenced in accordingly. Five fills straight from the locked
palette (`art/src/bonehead.gpl`): bones gold for the wheel, ectoplasm for Three Ghosts, red dark
for blackjack, pink light for the wardrobe, grey dark for the back room. Each is paired with the
ink printed on it and graded by `loop_check`, and none is ever an ink on card stock — the light
three are as bright as the card. A new machine picks one of `UIStyle.MARQUEES` and touches no
theme code.

**The stake is a stepper**, x1 / x2 / x5 / x10 of a machine's price (`ArcadeGame.STAKES`), and
what it may change is decided: every Dollars prize scales with it and nothing else does. Each
table is written at the lowest stake, so its odds and its return per Dollar hold on every rung
(the wheel's 0.905, the slots' 0.88, blackjack's near-even), while a garnish and a boost stay
exactly their size — D32 caps both by acts and by minutes, never by the bet, so staking more can
only make them relatively worth less. It is refused while a play runs: the stake a hand was
dealt at is the stake it is paid at. `STAKES = [1]` hides it.

**1.25x, measured.** The owner plays at Menu size 1.25x (D50). The Arcade was captured at 1x,
1.25x and 2x and read pixel by pixel. Nothing in the shell is *soft* at 1.25x — a fractional
CanvasLayer scale with nearest filtering and no anti-aliasing lands every edge on a whole pixel —
with two exceptions, both removed: `StyleBoxFlat` switches anti-aliasing on only for a rounded
corner, so the wardrobe swatch's radius of 4 was the one blurred edge in the room, and the base
Button's disabled rule is a third of black, a grey edge on every key a hand spends disabled
(the deck's `DeckKey` keeps a solid one). The wardrobe went from 132 distinct colours at 1.25x
to 22 — every pixel now a flat fill. What 1.25x does do is make things **uneven**: a 3px rule
is 3.75 screen pixels and lands as 4 or 3 by position (894 and 218 of the Three Ghosts room's
horizontal rule samples), so a box can be heavier on top than underneath, and pixel type's stems
come out 2 or 3 wide (53 and 30 in the wheel's legend). Four ways to fix that, tried:

- **A 4px rule** lands as exactly 5 screen pixels at 1.25x — 740 of 740 samples — and as a whole
  number at every quarter step, since 4 x 0.25k = k; 3 is whole only at whole factors. The cheap
  real fix: rules 3 at whole factors and 4 at the others, with the theme rebuilt when the factor
  changes. Not done here — it is every page, and it makes 1.25x a little heavier than 1x scaled.
- **`Viewport.oversampling_override = factor`** rasterises type at its screen size: the legend's
  stems went from a 53/30 split to 108 of 110 at 3px. But it is per viewport, and the payout numbers
  draw on an unscaled layer of the same one — rasterised 1.25x too large and drawn at 0.8, their
  horizontal strokes broke into one-pixel slivers (12 against 1). Viable only if the shell gets
  a viewport of its own.
- **Snapping** is already on (`snap_2d_transforms_to_pixel`) and cannot help: the layer's scale
  is itself the fraction.
- **Integer-scaling the card and centring it** is D23 again, and takes away the rung the owner
  chose. Not recommended.

*Consequence:* the recommendation is the scale-aware rule width, for the owner to take or leave.
`ui_shots` shoots the Arcade at 1.25x as well as 1x and 2x on every run, and `-- --arcade`
shoots only the Arcade — at those three and in the 640x480 play area, the smallest card every
cabinet is laid out to fit without clipping: the reels step down 192, 160, 128 with the card
(`ArcadeGame.fit_stage`), and the paytable clips its last cell rather than widen the page. The
480x360 rung still clips a room, as the old wheel did. `ui_check` asserts the four sections
in order, one stage height and one deck line across all five rooms, every word in every room
legible where it sits, and the stepper's rules; `loop_check` asserts the new variations, every
marquee's ink, a solid disabled deck rule, and that no box in the theme has a rounded corner.

## D59 — Every item is used, one at a time, by a suite (2026-09-25)

**Decision.** `tests/integration/item_check.tscn` takes every `ItemData` in `ItemDB` —
enumerated, never listed — puts it on a desk of its own and uses it the way a player does, then
asserts what it claims. Twice: once as bought, once with one level of each augment key and
mastery 50. What it measures and D59 does not fix is a `KNOWN` table in the suite, one line per
check naming its finding; a known finding that stops reproducing fails the run. The per-item
table is written to `user://item_check_report.md`; the summary a person reads is
`docs/item-audit-2026-09.md`.

**Why.** The owner: "comprehensive isolated testing of each object and mechanic … and see if they
actually operate as expected". The history says they do not, and that it is found late: a shop
tab inert for weeks, every explosion forceless for a release, a placebo on the starter power, the
fist erasing its own punch. Each of those is a sentence of the form *this item does not do what
it says*, and that sentence can be asked of a hundred items in six minutes.

**How it is built, and the parts that cost time to get right.**

- **The stage is the game's**: `WorldBounds`, `ItemSpawner` and one buddy in a 1280x720
  `SubViewport`, so the walls, the rescue and a critter's exit are real (a headless root is 64x64).
  Input is `push_input` at real positions — the grab region, not the picture — which is why the
  SubViewport: in one with no container, `get_mouse_position()` is the last pushed event.
- **Drivers are chosen by exact script class**, not `is`. A `HeldGun` extending `WeaponBase` is a
  new toy; driving it as a bat would pass it. A class with no row fails by name.
- **The pipeline is checked inside the grant.** A probe on `EventBus.payout` reads
  `Economy.payout_for(1.0, id)` while Economy is paying — linear in its base, so that is the whole
  product of multipliers just applied — and the probe on the event that caused it (connected after
  the autoloads, before any buddy's components) checks the amount to 1e-6. Every payout of every
  item, not a sample.
- **Real-time physics, skewed clocks**: a fuse, a turret's interval, a critter's lifetime and a
  fountain's are wound on, never waited out, and the authored values go into the report. The RNG
  is seeded per item, or a shotgun's spread decides the verdict.
- **A `Logger`** (Godot 4.5+) catches every `push_error` and `push_warning` while an item runs.
  "A warning nobody read" is how the forceless explosions shipped.
- **Timing a gap on the item's own clock**, read against a timestamp taken *before* the press: the
  shot's own work runs between the clock being set and any read after it, which made the minigun's
  80 ms read as 75 in both phases and look like a placebo.

**What it found.** Seven fixed (the audit's X1–X7): a spent grenade left for half a second as an
invisible 6,878 px/s projectile; the three cluster charges never counted as a use and left his
fuse face on for good; seventeen items' mass nodes read by nothing; animals' body-checks billed at
×1.0 past the "Sharper Sting" the player bought; a mine he stood on went off for 0 damage; and two
test-side faults (the jobs badge asserting the calendar, the capture tools selecting items across
drawers). Open, and the audit's first three are high:

- **D7 has a hole.** `get_contact_impulse()` carries the previous step's impulse, zero on the frame
  two bodies first touch, so a collision that throws them apart within one step is never billed.
  Measured on the fist: it launched him at 1,653 px/s and billed nothing. Every melee weapon
  passes because the drag joint keeps it pressed on him for a second frame.

  ```
  f11  fist v(782,31)   him v(0,0)       contacts: floor 25, floor 25
  f12  fist v(891,-204) him v(405,-283)  contacts: FistBody 0
  f13  fist v(1102,-147) him v(1031,39)  contacts: FistBody 0
  f17  him v(1653,376)                   contacts: FistBody 0
  ```

- **D54's 18 px impact inset** put five of eight turrets' shots under the 350 damage floor. They fire
  and draw and shove, and have paid nothing since 2026-09-07.
- **The gorilla cannot walk** — its steering force is a third of the floor friction the NPC seeder
  gave it on purpose — and the raccoon crawls at 4 px/s.

*Consequence:* a new class is a new row in `DRIVERS`; a new item of an existing class is covered the
day it lands. The run takes about six and a half minutes; `-- --only=<ids>` and `-- --trace` (every
tenth frame, where he and it are and what has been billed) are for working on one. Run it before any
commit touching `Scripts/Bodies/`, `Scripts/World/npc_*`, `Buddy._integrate_forces` or `_attribute`,
or an item's scene. The table cannot rot: fix an F-finding and the suite fails until its `KNOWN`
lines go.

**Amended the same day: the held guns and the fidget toys.** D56 and D57 landed twelve items the
suite could only fail by name — seven "no driver for HeldGun" and one per toy class. Each now has a
driver, and a new toy is cheaper to cover than these were:

- **One `HeldGun` driver for all seven.** Picked up by the grab region, carried to a stand-off
  beside him, left to lay its own barrel on him (timed), then the right button: a tap, a second
  tap at once that the gap must refuse, then another shot or — full-auto — the trigger held for a
  stream that stops on the release. What a shot is (`bullet`, `water`, `bubble`) is read off the
  gun and the side it pays on off the item. The kind guns: never a threat, never a hit, the water
  pistol's pay exact to the squirt (the grime off him says how many landed), every bubble one act
  of exactly its value. The plain phase ends by throwing it into him — asked of his own contact
  list, so "a kind gun bills nothing" is never said of a throw that missed — and the upgraded one
  with Shift+right in the hand.
- **One driver per toy, built from shared helpers** that work a toy's zones with synthetic events
  at the zone's real place in the world: `_tap_zone`, `_stroke` (every motion carries its real
  velocity, which is what a flick is read from), `_crank_zone`, `_hold_right`, `_shake`. His face is
  part of a toy's claim: `_expect_face` reads the beat his brain chose for each `fidget_event`,
  through a watcher reconnected per stage so it runs *after* the new buddy's brain.
- **Which currency an item earns is `_pays_hearts`**: `HEARTS_CLASSES`, plus anything built on
  `FidgetToy`, plus a `HeldGun` filed on the kind side. **A hit's multiplier is `_hit_multiplier`**:
  a gun's shot is billed at `shot_mult` and is known by its impulse, which is exactly `shot_force`;
  the same gun bounced off him is billed at its contact `damage_mult`.
- **A key the suite's switches cannot see is measured by its driver** into `_gauges` and compared
  by `_gauge_verdict`. The first is Steady (`recoil_mult`), measured as the angular momentum one
  shot hands the gun: the change in spin over the step the shot lands in, less the change the aim
  was already making, times the mass. Mass-normalised on purpose — the Weight node bought in the
  same phase also takes the kick down, and read in degrees it passed for Steady. It reads x0.92 on
  all five, as sold (x0.89 on the SMG).
- **A toy that draws at random when it is made reseeds before a draw it can control.** The
  jack-in-the-box's first tune is spent differently in the two phases, so its "Shorter Tune" is
  measured on the *second*: the lid is right-tapped shut with the RNG reseeded immediately before
  the release, so both phases draw the same length and the node's x0.94 is the only difference.

What it found: **F10**, the fortune ball's "Looser Dice" is a placebo for its first four levels
(a shake is a whole reversal, and 4 x 0.94^n rounds back up to 4 until level 5); and none of the
five harm guns thrown into him from the hand is billed — each is in his contact list for exactly
one frame and gone, which is F1's signature, so they are filed `~F1` and neither fail nor go stale
when F1 is fixed. Every other claim of all twelve holds, and no item in the catalog is without a
driver: 118 items in about eight minutes (486 s), 0 failed.
## D60 — Every AI mechanic is tested on a desk of its own, by what can be seen (2026-09-25)

**Decision.** `tests/integration/brain_check.tscn` tests each thing that acts on its own — the
expression brain, the idle brain, his body, mood and grime, the personalities, the critters and
the turrets — one at a time, each on a 1280x720 SubViewport with the real `WorldBounds`, a spawner
and a fresh buddy. It fires every trigger through the signal the game fires it on and asserts
what can be seen: the face, the tag, the displacement, who paid, where he ended up. Every row,
routine toy, personality, critter and turret is enumerated from `ExpressionBrain.ROWS` and
`ItemDB`, never listed, so content added later arrives covered. The owner asked for it after
"spawn a ball and watch him play with it" had shipped showing nothing twice.

**Why a second suite, and why a SubViewport.** loop_check proves the wiring by calling handlers
directly, because emitting most signals on the real bus would pay money mid-economy — and so it
could not see a single one of the eleven faults below, every one of which sits *between* two
systems. And a headless root viewport is 64x64: every wall, home point, window edge and exit
derived from it is meaningless, which loop_check survives only by keeping its whole desk outside
the window. A SubViewport gives the game's own geometry for free.

**What it found, and fixed, one commit each:** one generator anywhere on the desk held him in
`cared_for` forever (`kindness_sustained` meant both "kind to him" and "income"); the idle brain's
routine looks were masked on 0 of 96 frames and ended by the first interruption; walker NPCs had
no friction feed-forward, so the gorilla never moved and nothing moved at Focus Off; five of eight
turrets have dealt no damage since D54 (damage read off an 18 px falloff); a generic category face
passed as an override locked out every personality's hurt face; a ball dropped from the shop onto
his head cancelled its own offer; the weapon-side balls were never chosen; the walk's push glued
him to the side of anything he hopped at; leaving animals walked into him for fourteen seconds;
the raccoon's throw spent itself on the raccoon; the reunion's tail face had no tail. Each is
written up with its root cause and numbers in `docs/ai-audit-2026-09.md`.

**Clocks are skewed, physics is real.** The expression brain's `_clock_skew` and its own timer,
backdated idle-brain timestamps and a hand-driven think tick replace waiting — but physics runs
in real time, because `--fixed-fps` would put the simulation ahead of every millisecond deadline
in the game. About six minutes; `-- --quick` takes one toy per routine, `-- --only idle.toys` one
section.

*Consequence:* a reaction row nobody asks for, a `connect()` in `ExpressionBrain._ready` no real
trigger drives, or a row no trigger produces is reported — a known one fails, a new one is a
note, so the next stream's rows are covered by the presentation pass until someone gives them a
trigger. `IdleBrain.paid_value` exists so a test can tell the brain's payment from the toy's; the
"never both" rule is otherwise unobservable. The design questions the audit could only measure —
Focus Off earning nothing from 26 of 33 routine toys, soaking against furniture rather than in it,
weapon balls that cannot pay, a 4,640 px/s gorilla slam, contact damage from animal bodies, a toy
outside the window — are in the audit for the owner.


## D61 — The authored colliders are the picture too (2026-09-25)

**Decision.** Every hand-authored body is re-authored against the sprite it actually has:
shapes, centre of mass and grip, in the seed tables' own art pixels. That is 36 of the 42
multi-collider weapons, turrets and charges. `loop_check` now asserts every authored body
against its picture. The bat, the mace and the katana are the reference feel and did not move.

**Why.** D54 measured the problem and D55 left it alone on purpose. Measured properly, it was
worse than a list of offenders:

| | |
|---|---|
| Nunchaku | shapes down the empty gap between two sticks drawn side by side: **2%** of its art |
| Tyre iron | a column where the bar is not, because the bar is drawn off to the right of its arm: 16% |
| Greatsword, sickle, katar, scythe | authored against a pose the sprite does not have; greatsword 46 degrees off its own axis, the sickle's grip 29 px in mid-air |
| Rail gun | a vertical stack against a gun drawn level, with its base 12 px below the art, so it stood in the air |
| Laser lattice | two posts in the empty middle of a frame, frozen against the art D45 replaced |
| Monitor, keyboard, stapler | 21, 15 and 13 px past their art |
| All authored bodies | **30 of 48** failed at least one bound below. After: none |

None of it was fixed in a sweep. Each row was measured, drawn over, re-authored and measured
again, and its centre of mass and grip were moved only where the art moved them. The
greatsword's weight sits a third of the way up the blade, as the row's comment always said.
The scythe's weight is mirrored to the side its blade is drawn on. The chainsaw's grip is
still 4 px from its engine, so it still bucks. The rows' comments were corrected where the
drawing contradicted them.

**How it is measured.** `ColliderAudit` (`tools/collider_audit.gd`) rasterises the scene the
game runs, with every sprite as the picture and every shape as the collider. It returns
coverage, the share of the collider that is air, the furthest a shape reaches past the art
(an exact distance transform), the principal axis of each, and whether the grip is on the
art. `tools/collider_report.tscn -- --tables --shots --runs` is now how a row is authored. It
builds the row in memory, draws the shapes over the sprite at 4x and prints the opaque pixels
per row. It is not written from a guess about the prompt. Run without `--tables`, it also
showed that no scene had drifted from its row. The guard's bounds come from the references:

| Bound | Why this number |
|---|---|
| coverage >= 0.65 | the katana covers 0.68, the lowest of the three references |
| air <= 0.30 | the katana is 0.25; the worst after D61 is a round bomb at 0.28 |
| overhang <= 8 px | one art pixel past the mace's 6.1 |
| grip <= 2 px from the art | one art pixel; a weapon is held by something |
| axis <= 10 degrees | only where both art and shapes are at least 2:1; worst after is 2.2 |

**Turrets.** Five turrets mirror their sprite to face him, and their colliders never mirror.
A flipping turret is therefore solid only where its picture is present in both facings. The
rail gun's stand and the nail gun's post are drawn off-centre and are not solid; each stands
on a centred foot that is. Mirroring the shapes in `TurretBase` instead would teleport them
under whatever touches the turret at the moment it turns, which is usually him. That is the
owner's call. The laser lattice's beams are light, and only its frame is solid.

**Feel, measured.** `tools/swing_rig.tscn` sweeps the game's own drag joint through him at
1200 px/s. The three references are bit-identical before and after. Across the 13 changed
weapons it swings, the momentum handed to him runs from 3,016 to 5,031, against 2,786 to 5,106
before; the references sit at 3,005 to 4,181. Peak weapon speed moved at most 5%, except the
nunchaku's +9%, whose weight is now in the far stick. Some
levers changed because the weapon on screen is a different length from the one its row
assumed: greatsword 32 -> 44 art px, halberd 50 -> 55, flail 41 -> 45, keyboard 33 -> 28,
nunchaku 32 -> 27. None of them became a plank or a rocket.

*Consequence:* the four seeders that own authored bodies take `--only id,id`. It rewrites
those scenes and nothing else, which is the way to re-seed one body. A weapon whose shapes do
not match its sprite now fails `loop_check`, which names the reason. The enumeration covers
future items and fails if it ever finds fewer than 42. Two things were left alone.
Turret barrels still lean up to 40 degrees over colliders that match the rest pose. And
`Buddy._cooldown_ready` runs on `Time.get_ticks_msec()`, so a headless run that steps faster
than real time bills slightly different hits from identical physics. The rig reports
momentum for that reason.

*Amended after the merge with D60.* `brain_check` reported the flamethrower's muzzle "on the far
side": it was lying on its side, rotated 117 degrees. The collider was not the cause. The
suite teleports each turret to 0.6 of its reach from him, which is 90 px for the flamethrower.
His collider reaches 44 px either side of his centre, and the flamethrower's reaches 54 now
that it is as wide as its drawn tank (26 before). So it was put 8 px inside him, and the
solver's shove at the end of the tank tipped it over. Standing on its own it is steadier than
before: its centre of mass is 8 px above an 18 px half-foot, against 12 above 20. The fix is
in the suite, which now keeps the gap clear of both bodies' colliders as well as inside
reach. No other turret was close enough to overlap. **A test that places a body by teleport
must clear the colliders.** Once those are the picture, a body is exactly as wide as it looks.

## D62 — The art polish is drawn, not generated: a walk, fourteen sprites, headphones that fall (2026-09-25)

**Decision.** Three pieces of art that had waited on a generator, or had come out of one
wrong, are drawn by hand from sources a person can read and diff. His **walk** is built from
his own neutral body (`art/tools/make_walk.py`) and plays while he travels. **Fourteen item
sprites** that did not say what they were are redrawn as text grids in `art/pixel/`. His
**headphones fall** onto the heap in the knockout instead of hanging where his head was
(`art/tools/drop_headphones.py`).

**Why the walk did not need Retro Diffusion.** It sat blocked on the walking preset for a
milestone (handoff B.1, D44, D45) while he slid to every toy on a 1.5 px bob. But he is a bone
wearing headphones, and the only things that move when he walks are the two knobs he stands
on — which the generated neutral body already draws. So each of the eight frames is that body
cut at the top of the knob flare and reassembled from a table: a foot lifts 2 then 4 pixels, the
upper body bobs one pixel at the passing frames and sways one over the planted foot. No pixel is
redrawn or recoloured, which is the only way to match a generated body's outline and shading
*exactly*, and the face offsets `postprocess.py` measures line up because the head is the same
head. Two details are not arbitrary:

- **The lift is eased column by column across the notch between his feet.** Lifting each half
  of the knob end as a block left the notch's walls four pixels apart, with a white tooth
  hanging in the gap. And lifts are even, because the body is drawn in two-pixel blocks.
- **Arm nubs were tried and dropped.** Cut from the `happy` hop, at 2x on a dark desk they read
  as two white dots floating off his sides — generator litter, the thing `postprocess.py`
  exists to remove. A walk without arms reads as a waddle; one with them reads as a defect.

`BuddyArt` plays `walk` while `travel()` is live and stands him back in his mood idle on
arrival; the drawn stride carries its own bob, so the code bob stays at zero under it and
survives only as the fallback for a body file with no `walk` tag. A tagged beat, a hurt or a
drag still take the body; a face-only beat does not stop his legs. `walk` is appended last in
`bonehead.aseprite`, so frames 1-74 keep their numbers and `_patch_frames.lua` still addresses
them — checked pixel-for-pixel against the file before.

**Why these fourteen.** Every item and icon was laid out at game scale against a dark and a
light desk beside the buddy, and ranked on the question `art-direction.md` already asks: can a
player tell what it is at 1x, in peripheral vision. The grenade was a clay jug, the dynamite a
fire extinguisher, the mine a spark, the nail bomb a ladybird, the demolition charge a block of
cheese, the foot spa a cooking pot, the tennis ball a coin, the wind chimes a grandfather clock
and the feather duster a 16x11 smear. The generator draws what a word looks like on average;
what makes an object legible at 26 pixels is the one part only it has — a spoon lever and a
pin, three sticks and a lit fuse, two seams, a hazard band on the only flat explosive. The grids
are the record, as D45 made the prompt the record for Codex: each file's header says what the
old sprite read as and what the new one leans on (`art/prompts/items.md` has the table).

**Colliders stay the picture (D55).** Eight redraws kept their exact size. The six that did
not were regenerated through their own seeders — scene deleted, seeder re-run without `--force`
— and each diff is two `size` lines and fresh `unique_id`s. D55 recorded that this route fails
because ItemDB cannot load the item while its scene is missing. ItemDB does log that, but
`seed_friendly`, `seed_bodies` and `seed_m36_explosives` do not need it to write a scene, and
all three rewrote exactly the one file asked for.

**Why the headphones.** The generated collapse left them in mid-air from its fourth frame, and
`pile` held them there: three seconds of every knockout that read as a rendering bug
(assessment §3, finding 8). The handoff filed it as a rigging problem; it is an art one. They
are found per frame as the detached piece with the most teal and lowered whole, outline and
all, on a `1.2 n^2` fall until they meet the heap as measured on that frame, then a two-pixel
bounce. `reassemble` is `collapse` reversed, as it always was, so they fly back onto his head.

*Consequence:* `loop_check` asserts the walk plays, that the code bob is zero under it, and
that arriving returns an idle and lets `BuddyArt` stop processing. Rebuilding the body file
needs every tag's sheet in `art/raw/`, which is gitignored: export them from the committed
`.aseprite` first (`art/prompts/bonehead_body_animations.md`). *Not redrawn:* the
multi-collider weapons, whose colliders are being re-authored against today's art — the hole
punch still reads as a floppy disk and the satchel charge as a sack of gold, and they should be
redrawn after that lands rather than before. The walk has not been watched by a person on a
real desk; frame strips and `art/preview/walk_*.gif` are what it was judged on.

## D63 — Floating text never overlaps; a number with no room is not drawn (2026-09-25)

**Decision.** Every rising line in `FXLayer` — payout, streak tag, rank, clean, knockout,
rebirth — reserves the space it will pass through for its whole life, and a new one is placed
where no live one will be at any moment of either's life. When there is no room within reach
of the hit (2.6 of its own lines, never under 100px), a higher-ranked line takes the spot and
puts the lesser ones away early; an equal or lesser one **is not drawn**. Headlines (rank ≥ 10)
only step around other headlines and clear anything lesser from where they land. Tags are keyed:
one streak tag, one combo tag, one rank line per item. The knockout's NEW BEST ROUND is a banner
over the headline rather than a line under it.

**Why.** `ui_shots` 16-juice printed "BASEBALE BATNRANK 43" — two rank-ups on one frame at one
point — and a streak tag on its own number, and twelve hits in one frame on one pixel. A game
that pays you in numbers cannot print them on top of each other. Dropping rather than queueing:
a queued number arrives late and a stream from a turret never drains, and a number that could
only be drawn over another one was never going to be read. The purse and the rate row count it
either way.

**How, and what it costs.** Checked against the *whole* life because the rise is an ease-out:
a young number rises faster than an old one and catches it up. With no sideways drift both
paths are closed-form, two quadratics differ by a quadratic, and "do they ever meet" is an
endpoint-and-vertex check, including the punch-in at its true `TRANS_BACK` peak. It runs once
per spawn and never per frame — about 0.1 ms in a debug build with a turret stream at one
point, nothing at rest.

*Consequence:* the fountain's coins stay outside the rule (a spray from one pixel cannot start
apart): they draw beneath the lines and are thrown no higher than the headline. `ui_check`'s
`numbers keep apart` suite checks every visible line's drawn rect pairwise, now and at four
points through its rise.

## D64 — The hits the engine never reports are billed from his own momentum (2026-09-25)

**Decision.** D7 stands: he measures his own damage. It now has two halves. The engine's contact
report is still billed as it was. What the engine never reports is read off his momentum: a
node that runs after every script (`Buddy.StepStart`) notes his velocity as each step begins,
and the callback after it holds the step as a ledger of what his contacts handed him (his
momentum change, less gravity and damping exactly as Godot applies them) and who was touching
him. One step later the engine has said all it will about that step. Whatever it reported is
subtracted, and the rest is billed to the colliders that were touching him and now report
nothing, through the same floor, per-source cooldown and attribution as any contact. Four more
item fixes from the audit (F6, F9 and the fist's double count) went in alongside it.

**Why D7 had a hole, measured.** A contact carries the impulse of the step *before* the one it
is listed in, and only if the solver recycled it. Godot's recycle radius is one pixel on both
bodies, so a contact that slides a pixel between steps is new every step and reports zero every
step. The fist pushed him for six frames and reported 0 on every one. And a body asleep when a
step begins is not called back for that step, even one woken inside it. He dozes whenever the
desk is quiet, so the commonest hit in the game (the first one on an idle buddy) was solved in
a step he never heard about. The ledger holds its span open across a sleep for that reason. The
engine's report is not always right when it does arrive. When two new contact points recycle
one old contact, each inherits its whole impulse, so a report can be exactly twice the blow.

**The model, and how it was chosen.** Two candidates were measured against the one number the
engine does report: a swung weapon's recycled contact. Each run was the reference bat, mace and
katana, swung on the game's own drag joint and thrown, at 600, 900, 1,200 and 1,500 px/s. At
each first contact the engine reported, both models were asked what they would have billed had
it not. Measured: 44 first contacts, 18 of them with him in the air.

| airborne, n = 18 | agrees with the engine | median ratio |
|---|---|---|
| ledger (his momentum) | exactly on 11; exactly half on 3, the engine's double count | 1.00 |
| closing speed, `(1+e) mu v` | within 20% on 6; the rest scatter from 0.4 to 1.9 | 1.11 |

On the floor (n = 26) the ledger reads 0.64 of the engine's number and the closing-speed model
0.54. The floor's friction takes part of the blow, and the ledger bills only what reached him.
Measured on a desk, a 14 kg ball thrown at a dozing buddy at 1,200 px/s is billed 5,301, and
the ball lost 5,418 along the blow. The engine reported 0. The ledger won on accuracy, and it
also cannot disagree about a thrown bat and a swung one: it never asks what hit him.

**Two limits keep it honest.** One unreported collider takes the whole residual only if it
could have delivered it. The blow has to push him away from that collider, and it has to sit
inside the friction cone, which is no wider than 45 degrees because his friction is 1.0. Several
colliders split it by their normals, solved non-negative. No share may exceed
`2 sqrt(2) x mass behind it x closing speed`. The mass behind a free body is its own. The mass
behind the world is his, because a floor gives back only what he brought. That cap removed a
9,521 "world" bill from a bat squeezing him into the floor, which the first version had made.
It cannot bill a step twice by construction. `loop_check` checks that with the per-source
cooldown switched off.

**What moved, item by item** (`item_check`, plain run):

| | before | after |
|---|---|---|
| fist (the starter power) | 0 hits, 0 Bones, launched him at 1,653 px/s | 3 hits, 19.3 Bones |
| bowling ball, dropped and thrown | 0 | 20.9 Bones |
| trampoline landing | unbilled; lands 722, leaves 303 | billed; lands 722, leaves 1,062 |
| beach ball | 0 (a 0.4 kg ball asked for the 1,500 fall floor) | a catch: 4.0 a time, 3.6 Hearts |
| fist, one level of Knuckle Duster | punch x1.15 and damage x1.15: x1.32 | punch 6,000 at every level: x1.15 |

- **F6, the trampoline.** The mat read his speed in `_physics_process`, after the landing had
  been solved, so every launch was the 320 minimum. It now reads the collider's velocity from
  its own contacts, which is the speed the solver started from. `max_launch` (1,080 px/s, 600
  px of lift, which keeps his head on a 720 px desk) stops x1.55 running away, and above the
  ceiling it gives back exactly what it was given, so nothing leaves slower than it arrived. The
  idle brain's restart hop now climbs 153, 320, 496, 769, 1,080 and stays there. The landing is
  billed at the mat's own multiplier, so "Tighter Springs" is read on the hit.
- **F9, the beach ball.** It is now what its description says: a `FriendlyBase` catch bought
  for 100 Hearts, paying 4 a catch above 200 px/s with a 0.5 s gap. He heads it at 270, so the
  keepy-uppies pay. Its tree was re-derived in Hearts by `seed_m35_trees -- --only beach_ball`.
  Its weight node ("Sand Filled", a placebo on a catch) became "Quicker Rallies", a rate, on the
  same id. "Beach Day" was re-derived on the Hearts line: 0.57 Hearts/s a level, where it was
  1.2 Bones/s.
- **The bowling ball stays a Bones toy in Play**, and so do the trampoline and the fan. They are
  bought with Bones and earn Bones. The receiver used to ask the drawer, so a thrown bowling
  ball faced the fall floor meant for a beanbag he climbed on to. It now asks the currency:
  kind *and* bought with Hearts means the fall floor. That rule also replaces the `Trampoline`
  special case.

*Consequence:* thrown things, the fist and the mat pay what they always claimed to, and the
landings he makes by being flung now bill the world as the reported ones always did. Two things
were measured and left alone. Godot's cast-ray CCD slows a fast body so that it arrives
"softly" the step before contact: a bowling ball thrown at 900 px/s reached him at 151. So a
throw still pays less than its speed suggests, and that is tunnelling protection. And the idle
brain's bouncing now really does pay the Bones its `KNOCKOUT_COOLDOWN` comment always said it
did: about 17.6 damage a second whatever the ceiling, because a landing's impulse and the flight
between landings both scale with speed. The dwell, the toy cooldown and the five-minute
knockout rest bound it. The pacing simulator models a player's hands and not the physics, so it
sees none of this. It moved only with the beach ball's price and capstone: the first
Reincarnation is 9:39:49, where it was 9:41:19, and four of four targets are met, so nothing
was rebalanced.

The seeders that own the beach ball take `--only id,id` now, as the body seeders have since
D61 (`seed_m3_content`, `seed_m35_trees`). Run `item_check` before any change to
`Buddy._integrate_forces`, the ledger or `_min_impulse_for`. Its F1, F6 and F9 lines are gone
from `KNOWN`.


## D65 — A node moves a number something reads, and a pull pulls him (2026-09-25)

**Decision.** Four of D59's findings and the donut box, closed together because they are one
sentence — *this node, or this description, promises something the item does not do*:

- **The three pulls are accelerations** (F4). The black hole charge, the implosion charge and the
  gravity vortex pull every body by its own mass times `pull_accel`, the way gravity does, instead
  of with one force for a 0.3 kg prop and a 3 kg skeleton. The vortex also falls off linearly and
  has drag inside its well; see below for why it needed both.
- **A field is billed for the world impacts it causes** (F5). While the vortex's pull or the fan's
  wind is on him, and for a moment after (2 s and 0.5 s), an impact with the floor or a wall is
  billed to that item instead of to `world` — `Buddy.claim_impacts`. The vortex and the fan now
  earn, rank and reach their mastery-25 capstones like everything else.
- **Ten nodes retargeted, ids unchanged** (F5, F7, F8). The fan's "Higher Setting" is wind
  strength (`wind_mult`); the vortex's "Faster Collapse" is its pull (`pull_mult`); the fist's
  "Faster Hands" is how fast it chases the cursor (`speed_mult`); and the third node of the seven
  consumables is how much a helping lifts his mood (`mood_mult`), renamed Comfort Food, Calming
  Blend, Sugar Rush, Extra Sprinkles, Family Recipe, Surprise Party and Best Day Ever.
- **A box of donuts is six donuts.** `FriendlyBase.servings`: one helping per contact,
  `contact_cooldown` apart, gone after the last. Six of 5 rather than one of 30, so a fresh combo
  totals 41 — still under the 400-Heart pizza's 45, the ordering `seed_friendly` was tuned to keep.

**Why.** Every one was measured by `item_check`, before and after:

| | before | after |
|---|---|---|
| black hole charge, him put down 126 px away | 126 → 126 px | 126 → 71, stopped against the charge |
| implosion charge, 129 px away | 129 → 129 | 132 → 68 |
| gravity vortex, the eye 197 px away | 197 → 197 | 197 → 11 |
| a 0.3 kg prop in the vortex | 155 → 106 px, peak 1,137 px/s | 155 → 42 px, peak 561 px/s |
| gravity vortex, Bones under its own name | 0, and no mastery | 10.5 plain, 46.6 upgraded, ranked |
| the fist's "Faster Hands" | placebo: a gap of 0 | ×1.06, 1,997 → 2,116 px/s |
| the vortex's "Faster Collapse" | placebo: a gap of 0 | ×1.10, 1,839 → 2,023 px/s² on a probe |
| the fan's "Higher Setting" | placebo: it never hits him | ×1.10, 2,250 → 2,475 px/s² on a probe |
| seven consumables' third node | placebo: gone before the gap | ×1.10 on his mood, exact to 1e-4 |
| a box of donuts | one contact, 30 | six contacts of 5, half a second apart |

**The design choice in F5, and the one it was chosen over.** The audit offered two: bill the
vortex for what it causes, or give both a capstone not gated on mastery. The second would have made
them the only items whose automation can be bought without ever being used, and left their payout
nodes placebos. The first is the audit's own model of the vortex ("its damage is the collisions it
causes") made true, and it has a clean boundary: **only who is billed changes, never whether.** A
prop the vortex throws into him is still billed to the prop — it is the collider, and D7 says the
collider is who hit him. Only a world impact, which had no author and was billed to `world`, is
reassigned. The floor it must clear is still the world's fall floor (1,500), not the swing floor,
so held still against the desk by a pull he is not billed, and nothing pays that did not pay before.
Picking him up clears the claim: from then on his energy is the player's.

**How, and what cost time.**

- **Why an acceleration and not a bigger force.** A force big enough to drag 3 kg against 2,940 of
  floor friction is more than 9,800 px/s² on a 0.3 kg prop. As an acceleration the pull is the
  same on him and on a pencil, and the numbers compare with gravity: the vortex is four g at the
  eye, the implosion charge ten, the black hole eleven.
- **The charges' ceiling is his squeeze.** Pressed against a frozen charge he takes
  `3 kg × pull × (1 − d/R)² / 60` of contact impulse every tick, and past the damage floor (350)
  being held still would bill him ten times a second. At the distance his body stops against
  theirs that is 330 (black hole) and 248 (implosion). Being dragged *into* the charge is billed,
  to the charge, and should be. The blast then meets him at close range: **6,478 px/s**, the fastest
  body in the game, still under item_check's 15,000 ceiling.
- **The vortex was a sling, not a knot.** Its swirl adds energy every frame and nothing took it
  out, so an orbit only widened until the body left the rim at speed. Drag inside the well bounds
  the spin at `pull × swirl / drag` (367 px/s). The first version dragged against the desk, and a
  moving eye lost him: carried up the desk in it, he fell out of the well from half the height the
  eye reached, too low for the landing to clear the fall floor. Measured against the *eye's*
  velocity instead, the knot travels with the cursor; the eye's speed is capped at 1,500 px/s so a
  cursor that jumps windows does not fling it. Linear falloff, not the blasts' square: a blast is
  an instant, a well is held, and under the square its outer half pulled at under a quarter of
  its strength.
- **The fan's end-to-end payout waits on F1.** The suite's drop lands him at 726 px/s and he parts
  from the floor inside the same step, so F1 bills that landing to nobody. The claim is checked
  directly instead — `Buddy.impacts_claimed_by()` at the landing — and three `~F1` lines carry the
  fan's earnings. The vortex is measured end to end because a slam keeps him pressed to the desk.
- **A new key is three edits, and the suite enforces the third.** The seeder's `EFFECT` table, the
  augment panel's `EFFECT_WORDS`, and an `item_check` verdict — a key it cannot measure fails as
  "unknown key". The field keys are read off a weightless, undamped probe's first step in the
  field (no friction, gravity or drag in the number); the fist's off its top speed chasing a cursor
  that jumped; the mood key off every act, read back after his `MoodComponent` by a handler
  connected per stage, from despair so a cake's 120 is not lost against the top rail.
- **Every new check fails without its fix.** Run against the old scripts with the new data and
  tests, the six items fail 19 checks between them, each naming its placebo ("Faster Collapse ...:
  it stayed at 2,198 px/s² on a free body", "Comfort Food ...: his mood went -99.43 to -70.66
  where the data says -67.78").
- **Faster Hands moved an F1 result.** Upgraded, the fist chases 6% faster, and in the full
  suite's order its punch is now still pressed on him a step later and billed. F1 is
  contact-geometry luck, so the upgraded fist's F1 lines are `~F1`; the plain run stays strict.

*Consequence:* `tools/seed_m35_trees.gd` takes `--only node_id,node_id`, the D61 pattern for
augments; it rewrote the ten nodes with their ids and every other field intact. The black hole
charge's scene carries `pull_accel` as a one-line change, not a re-seed: re-seeding either charge
also rewrites every unique id and the implosion charge's grab region, which has drifted from its
sprite since D61 and is not this decision's to settle. The pacing simulator moves only through the
fan, whose damage node is now wind: 4/4, first Reincarnation 9:41:19 → 9:40:45.

## D66 — The second five toys: a stretch, a swing, a wind, a string and a draw (2026-09-26)

**Decision.** Five more toys on D57's zones and gestures, each a verb the game did not have and
each something he does himself. Three are kind and two are harm. The grammar is unchanged:
left holds, right while holding is the item's action, right on a zone is that zone's action,
and Shift+right bins.

| Toy | Drawer, price | The verb | His | Pays |
|---|---|---|---|---|
| Slinky | Play, 350 Hearts | hold it and pull with right held, or right-drag it where it lies; let go and it boings. Throw it and it walks | plucks it | 6 a full boing (a quarter for a short one) as an act; 0.5 a step, trickled |
| Newton's cradle | Mood, 5,000 Hearts | right-drag an end ball out and let go | watches it, calmed; pulls one himself | 0.6 a full clack, trickled: about 4 for a 40 degree pull, over ~25 clacks |
| Pull-back car | Play, 3,000 Hearts | right-drag it backwards to wind it, eight notches, then let go | hops on for a ride; winds it and chases it | 24 a ride from a full wind, as an act |
| Yo-yo | Melee, 1,500 Bones, after the frying pan | hold it; right throws it out on its string, right held puts it to sleep | watches it sleep, impressed by a trick | a bonk: the collision's impulse x1.3, and x2.5 after a trick |
| Slingshot | Guns, 1,200 Bones, first in the drawer | hold it; hold right and pull the pouch back, let go | cowers while it is drawn at him | a pellet: 1,700 impulse at a full draw |

Each has three tier-1 nodes and a capstone by the M3.5 rules, currency by side. Every key is
read by the toy's own script: the value, the payout, and "time between uses", which here means
whatever each toy has instead of a gap in time. A full boing is a shorter pull ("Looser Coil").
A clack keeps more of the swing ("Harder Steel"). A full wind is a shorter pull ("Tighter
Spring"). A shorter sleep is a trick ("Ball Bearing"). A new pellet is in the pouch sooner
("Pellet Pouch"). `item_check` measures all fifteen (x0.94 each) rather than trusting them.

**The pull-back car is kind, not a ram.** The brief left the side open. A car that drives at
him and pays Bones is a melee weapon with a motor, and the harm side already has thirty of
those. It would also be billed by a contact solver that cannot see a hit that parts in one
physics step (D59's F1), and a small fast car bouncing off him is exactly that. A ride is a
verb nothing in the game had: he stands on a thing that moves. So the car sits in Play, costs
Hearts, and pays Hearts for the rides it gives. His own play with it is the idle brain's
steering doing what it already does. He winds it, lets it go away from him, and the brain walks
him after it.

**How each one works, and why that way.**

- *The slinky's coil* is twelve ring sprites, two of each colour, laid along a quadratic curve
  that sags more the more sideways it is pulled. Each ring stands across the curve, so a
  stretched slinky is its stack pulled apart. In the hand, the held end freezes where it is
  and the cursor has the other. Let go of right and the frozen end is released, the drag joint
  yanks it home, and the coil shrinks as it comes. That is the boing, and it is physics rather
  than a canned tween. On the desk, the far end comes home on an underdamped spring. A walk is
  end over end, one span a step, and only where `test_move` finds room.
- *The cradle is a clock, not a solver.* Five touching pendulums are hard to simulate and easy
  to animate: only the end balls move, one at a time, and what leaves one arrives at the other,
  less a tenth. The clacks form a geometric series, so `item_check` checks the whole swing's
  Hearts to 0.2%. The player's act is the pull, which the contract board counts. The clacks
  are the toy running on its own, so they trickle. Watching it holds him in a new `calmed` row,
  and the trickle lifts his mood like any kindness.
- *The ride.* The car stops, he hops, and he is welded to the roof by two pins a head apart,
  since one pin would let him spin. The car then drives frozen and kinematic under
  `move_and_collide`, so the car sets the pace rather than his weight, and a wall ends the ride
  instead of being driven through. **He and the car pass through each other from the hop to
  the end of the ride.** Measured first: a hop computed to rise 43 px topped out at 29 and turned
  him a radian, because a skeleton rising past the roof's corner catches on it. Nothing
  collides now, and the landing is the frame his feet cross the roof line coming down.
- *The yo-yo's string is a rope, not a joint.* In `_integrate_forces` the body is held within
  the string's length of the hand, and only the outward part of its velocity is removed. It is
  written there and only when taut, so it is always the current state and never a stale copy
  (D56). **A bonk on the string bills itself.** It uses `Buddy.take_impulse`, the gunshot's
  path, at the collision's own impulse: (1 + e) x reduced mass x the approach speed from the
  frames before the contact. While the yo-yo is out, his contact path bills it at zero, so a
  bonk is never billed twice. In the hand or loose, the yo-yo is an ordinary weapon. A trick
  pays through the next bonk, because Bones are minted only from damage and a trick is not
  damage.
- *The slingshot aims nothing for you.* It is the one gun in the drawer that does not aim
  itself. The frame plants upright and the pouch is the cursor, clamped to the bands' reach. A
  dotted arc shows the launch `loose` would give under the same gravity. While that arc runs
  through him, the held gun's `aim` threat is on and he cowers. The pellet collides with the
  world only and sweeps the segment it flew each step for him, so it bills exactly once however
  fast it goes. It bills at the slingshot's own `damage_mult`, so every hit carries the number
  the data says it does. A binned slingshot frees the pellets still flying.

**Budget.** Nothing per frame at rest, asserted for all five: `_process` runs only while a coil
is drawn, a cradle swings or a notch pip is shown, and each switches itself off. The yo-yo's
speed memory is a four-slot ring, not a queue.

**Pacing,** 4/4. Against a0934a5: first automation 15:33 -> 16:24 of play, worst dead stretch
1:10 -> 1:30, first Reincarnation 9:41 -> 9:49, worst ramp 1.0x. The simulator is order-
sensitive, not additive. Alone, the slinky, cradle and car added one to three minutes, the
yo-yo nothing, and the slingshot at 800 Bones took 27 minutes off. All five together at the
first prices landed at **10:06**, over the ceiling. The slingshot's price was the lever, not
the other four's: at 800 it was the first Bones purchase after the pistol, and anywhere from
1,000 to 2,500 lands at 9:48-9:49. It is 1,200: still the cheapest gun, and still before the
revolver. Eleven minutes of headroom is left, and the next batch has to be run against it.

**What else it turned up.** A drag that crosses a HUD panel is the panel's: the slingshot's
pouch stopped following the cursor over the "next up" row, because `GestureZones` hears only
unhandled events. A gesture is therefore confined to the desk, which is right for a click and
a limit for a long pull; nothing is done about it here. And at boot he is still dropping in
from his authored spawn point, so a toy put "beside him" in a suite's first second is put in
mid-air.

*Consequence:* `tools/seed_m39_toys2.gd` is the table (`--force`, `--only=id,id`), and each
grid in `art/pixel/` says which rows and columns are which part. `tests/integration/toys2_check.tscn`
(178 assertions, `-- --only=slinky,cradle,car,yoyo,slingshot,zones,bin,rest,him`) drives every
gesture with synthetic events at real positions. That includes an upside-down cradle, a
mirrored car and a slinky on its side. It checks payouts through the real pipeline, his routines
and rows, and the budget. `item_check` has a driver per class. `fidget_shots` stages the five
for a person to look at. Four `FIDGET_ROWS` are new (`boing`, `clacking`, `yoyo_trick`, `ride`),
three rows are new (`calmed`, `impressed`, `riding`), and there are six new synthesised voices
(`boing`, `clack`, `ratchet`, `zoom`, `twang`, `zip`). *Not done:* the wind-up teeth from D57's
list (the slingshot took its place). He does not play the yo-yo himself. And nothing here has
been seen on a real desk.

## D67 — Everyday things have verbs: the right button on what used to be only put down (2026-09-25)

**Decision.** Thirteen items that were "put it down and wait" get one thing to do with them in
your hands: squeeze the duck, change the boombox's track, stroke the wind chimes, feed the fish,
churn the lava lamp, water the plant, change the fairy lights, scratch the record, crank the
bubble machine, stir the tea, run the hot tub's jets, pull the party popper, aim the fan. Each
verb is a row in `tools/verb_table.gd` — zones, gesture, what it pays, what it looks and sounds
like, what his face does — on a new component, `ItemVerbs`, that rides beside D57's
`GestureZones` on the body the item already had. No item changed class and no item stopped
doing what it did.

**Why.** The owner: "a lot more creative fidget style click and drag objects we can do that
utilise a combination of left and right click, utilise different click zones etc." D57 built
the grammar and five new toys on it; the thirty kind items already on the shelf were still
furniture. His hour-long session log shows what he actually used: the beanbag, the sponge and
the open hand — the things you *do* something with.

**The grammar is D57's, unchanged.** Left carries. Right on a zone is that zone's verb; right in
the hand is the item's own action (the popper). Right anywhere else on the item still bins it —
the boombox's speakers, the tank's stand, the lamp's foot — and Shift+right bins it anywhere,
which matters for the duck, the lights and the chimes: they are zone from edge to edge.
Hovering a verb's zone shows the pointing hand. Each item teaches its line once, on first
landing, and the shop's HowTo strip shows it (`ItemData.controls`, written by
`tools/seed_m310_verbs.tscn`).

**A component, not a class, and a row, not a script** (D8). `ItemVerbs` reads its rows from the
scene; the two seeders that own these scenes call `VerbTable.attach()` on every body they build,
so a scene rebuilt from its seeder comes back with its verbs. A row names its zone and gesture
(tap, press, cross, crank every N radians, drag every N pixels, action), its payment (`value`,
`cooldown`, `once`, and the conditions `near` and `touching`), whether it `consume`s the item,
a `cycle` of states with a colour and a note each, sound, bursts, and a small vocabulary of
effects: `squash` and `swing` about an anchor in art pixels, `tint` and `tempo` on the sprite and
the ambient emitter, and `surge`, a GPU emitter in the item's own frame for a few seconds. The
one verb that needed code is the fan's, and it is one method on `WindSource` the row names
(`call: aim_at`). Staying `FriendlyBase` matters beyond tidiness: `item_check` picks its driver
by exact class, and every one of these items is still driven, and passes, as what it was.

**Ranked by delight per hour of work, and what was built.**

| Item | The verb | What you see | Pays (value / cooldown) | His face |
|---|---|---|---|---|
| Rubber duck | right-click it | squashes about its belly, squeaks, hearts | 2 / 1.5 s | amused |
| Boombox | right-click the buttons | next of four tracks: its notes change colour and tempo | 4 / 4 s | a new move, then dances on |
| Wind chimes | right-drag across the tubes | each tube it crosses rings its note; the chime rocks on its hook | 3 / 3 s, once a stroke | grooves |
| Party popper | hold it, right-click | a bang and confetti in four colours; it is used up | 45, once, only near him | laughs |
| Fish tank | right-click the lid | flakes drift down, the fish come up for them, the water bubbles | 12 / 15 s | watches |
| Lava lamp | right-click the glass | wax rises through the glass for five seconds; the lamp rocks | 8 / 8 s | watches |
| Houseplant | right-click the leaves | water falls on it, then it stands up a little taller | 6 / 20 s | amused |
| Fairy lights | right-click the lights | warm, rose, sky, mint — the bulbs and their twinkle | 3 / 4 s | watches |
| Record player | right-drag across the record | a scratch every 8 art px, higher pushed and lower pulled | 5 / 4 s | grooves |
| Bubble machine | right-drag circles on the fan | a tick a quarter turn, a flurry from the chimney a turn | 5 / 4 s | watches |
| Cup of tea | right-drag circles in the cup | a clink a half turn; two turns and it steams — a proper cup | 5, once a cup | amused |
| Hot tub | right-click the jets | the water boils with bubbles for five seconds | 10 / 8 s, only while he is in it | pampered |
| Desk fan | right-drag from its face | the wind turns to the cursor, level to 50° either side; a line shows where | nothing — the verb is the physics | — |

*Considered, and left for later:* the **birthday cake**'s candles (blow them out, relight them —
good, but it is food and is gone the moment he touches it); the **massage chair**'s programme
button (the hot tub's jets again, with nothing new to draw); the **beanbag** plumped (a squash
on the thing he already sinks into — the tell is him, not it); the **hammock** rocked (the sprite
can rock but he cannot rock in it, so it reads as broken); the **chocolate fountain** dipped
(there is nothing in the player's hand to dip).

*Rejected as busywork:* the **pizza, donuts, ice cream and noodles** (each lives a few seconds
before he eats it); the **foot spa, paddling pool and heated blanket** (a splash or a dial that
is the jets again, or invisible); the **jigsaw** (a piece placed needs a drawing per piece, and a
verb without a visible result is a click for money); the **kite**, **tennis ball** and
**baseball** (throwing already *is* the verb); the **sponge, towel and duster** (rubbing him
already is); the **trampoline** and **beach ball** (another stream's).

**What a verb pays, and why so little.** A verb is an act — the combo, the contract board and
the per-act Dollars see it, and the item's value node scales it — paid on the bus exactly as
`FidgetToy.pay_act` pays, so Economy is still the only thing that mints anything. It is sized
against petting, the kind side's hands-on baseline of one value a stroke at three or four
strokes a second: one act is a few seconds of petting, and **no verb pays faster than 1.5 value
a second however fast it is clicked** (value / cooldown; `verbs_check` asserts the ceiling on
every row), which is below each item's own rate — a rate that pays whether anyone is there or
not. A player going round the desk working one verb after another, a click every second or
two, earns about what stroking him would have, and stroking him is what `pacing_sim` models
for every second of kind play. The simulator reads nothing a verb changes and does not move:
first Reincarnation 9:41:19, first automation at 15:33 of play, worst dead stretch 1:10. It
would move if a verb were ever priced like a generator, which is what the ceiling is for.

No verb can make an item pay twice for one thing: a cooldown bounds each, the popper pulled is
the popper gone (and thrown, the same), the tea is stirred once a cup, and the jets pay only for
the soak they improve. A verb still plays during its cooldown — the lamp still churns, the
chimes still ring — it only does not pay.

**He notices, in three rows rather than thirteen.** `grooving` (a hop at a new track, a scratch,
a chime), `marvel` (a three-second hold, face toward it: wax, fish, lights, bubbles) and
`pampered` (the jets, only while he is in them); the popper uses the jack's `laugh`, and the
duck, the plant and the tea use `amused`. They arrive on `fidget_event`, which the brain already
listens to, through `FIDGET_ROWS`. Two changes to the brain made that honest:

- **A beat over one of his routines goes back to it.** A new track used to end his dance: the
  react took the one slot and nothing put the routine back. Now `_on_fidget_event` queues the
  routine's hold behind any fidget beat, so he does a new move and dances on. The kindness act
  the verb pays does not stand him down either — the idle brain already exempts the toy he is
  at — so `verbs_check` walks him to a boombox, changes the track and watches him keep dancing.
- **Only the verb's act is the hand's.** D57's `_worked_by_hand` read "has a `controls` line"
  as "every payment is a hand at work, so skip the generic face". Giving the tea a line would
  have stopped him looking pleased to drink it. `ItemVerbs.paying` is set while a verb's act is
  on the bus (the `Economy.paying_kind_act` idiom), and an item that carries verbs is otherwise
  judged as it always was: the tea is eaten, the duck caught, the boombox trickles to
  `cared_for`. Whether an item carries verbs is read from its scene, not kept in a list.
  `marvel` is at REACTION for the same reason: every one of these items trickles, and its next
  flush would have swapped the show for `cared_for` half a second in.

**Found on the way: `seed_friendly` never wired `sprite`.** Twenty-eight of the kind items — every
one it builds — left `BaseDraggable.sprite` empty, so none of them wore D41's glow, popped on
landing, or sat its ambient steam, bubbles or notes on its own top edge rather than on a guessed
32px square. Fixed in the seeder and all twenty-eight scenes rebuilt through it (D62's route:
delete, re-run without `--force`); each diff is the one `sprite` line and fresh ids, plus the
verbs where there are any.

**The fan.** Another stream owns the fan's augment tree; this touches only its verb — one method
on `WindSource`, which turns `blow_direction` and the wind area together — and its scene's zones.
Its `item_check` driver still passes: a fan fresh on the desk blows right, as it always did.

**Budget.** Nothing per frame. `ItemVerbs` has no frame callback and no input of its own; it runs
on a gesture. A squash or a swing is a tween that stops; an emitter is built the first time its
effect plays, emits for that effect's seconds and stops, and is timed so a second churn is not
cut short by the first one's timer. At Focus Off a verb still pays and his face still answers,
and nothing on the desk moves; a tint is a state, not a motion, so the lights still change.

*Consequence:* a new verb is a row in `tools/verb_table.gd` — zones read off the sprite with
`art/tools/zone_sheet.py`, which draws it at 8x on an art-pixel grid and the zones you wrote back
over it — then the scene rebuilt through its seeder and `seed_m310_verbs` run for its line. A
verb that needs behaviour the vocabulary lacks names a method on its body with `call`. Tests:
`tests/integration/verbs_check.tscn` drives every verb with synthetic events at its zone's real
position and asserts the act through the payout probe (never the balance: every one of these
trickles), his row, one payment per cooldown, the conditions, the grammar, Focus Off, and that
nothing runs at rest; it also fails if the scenes and the table ever disagree. **Not yet seen by
a person**, because no window may open on this machine while the owner is using it: every
effect's look on a real desk (`ui_shots`, `audit_shots`), the scratch sound, and whether the
wax, the fish and the flurry read at 1x.


## D68 — The shell at the sizes it is used at: even rules, keys that hold their size, words that fit, numbers that leave without a ghost (2026-09-26)

**Decision.** The shell is judged at the Menu sizes people actually play at — the owner's 1.25x
on a 1440x960 play area over the chroma backdrop, 2x, and both ends of the play-area ladder —
rather than at the 1x every suite ran at. Six things were right at 1x and wrong there, and each
is fixed at its source:

1. **Rules land on whole screen pixels at every Menu size.** D58's recommendation, taken. A
   rule is 3 at a whole factor and 4 at the quarter steps between (`UIStyle.rule_for`), because
   4 x k/4 is always whole: at 1.25x a 3px rule is 3.75 screen pixels and drew as 3 or 4 by
   position; a 4px rule is 5 wherever it sits. `UIScale.apply` hands every fit's factor to
   `UITheme.use_factor`, and only a change of *width* costs anything: the theme is rebuilt and
   merged into the Theme every layer already holds — one `changed`, fonts reused, nothing per
   frame. Whole factors keep today's widths exactly. What sizes or draws a rule outside the theme
   (`UIStyle.rule()`, the room lamps, the wheel, the cards, the tree's wires, the reel fit) reads
   `rule_width()` and re-reads it on `theme_changed`. The capstone's heavy rule is `rule x 2`
   (6, or 8 between) rather than `rule + 3`, which would have been 7 and uneven again; the
   fortune ball's bubble keeps 3, since the world is never scaled by the Menu size.
2. **A key is the same size in every state.** `_key_pressed` was written as though content
   margins stacked on a rule like CSS padding on a border; they are measured from the box's
   outer edge. So every pressed, toggled and disabled key was 4px taller than at rest, an open
   tab 5px taller than a shut one, a chosen list row's name stepped 3px left, and variations
   that left a state undefined took the base Button's margins for it — a price key 4px wider
   pressed, a quiet key 6px bigger disabled: 26 states in 13 variations. Godot sizes a Button
   from the state it is in (`align_to_largest_stylebox` is 0), so the arcade's deck grew 2px under
   every hand dealt — `Cabinet.KEY_HEIGHT` had been raised to cover it and fell 2 short. Now the
   pressed box is derived from the one at rest (`_pressed`) and every key defines all five
   states from one geometry (`_key_states`).
3. **A caption gives up its mark, then its word, and never its letters.** The page tabs read
   "Upgrad" and the Arcade's room keys "The Whee" at 2x: a tab's width is the card's shared out,
   the card is narrower at 2x, and the words are not. `UIStyle.fit_captions` shows mark and word
   if every key in the strip fits them, the word alone if that fits, and the mark alone with the
   word in its tooltip if not — the whole strip together, since two keys without their word
   beside four with it reads as broken. 2x on the default play area is words; 480x360 is marks.
4. **No page is wider than the card, and the shop is not taller.** Seven backdrop keys were 624px
   of row in a 533px card at 2x and Chroma — the owner's — was past its edge; the choice rows now
   wrap. The shop's detail pane scrolls inside itself with the buy key pinned under it (page
   455px tall at 2x in a 298px card; now 206). Every Arcade cabinet fits itself to its card
   (`Cabinet.fit`): the display gives width down to 120 from 240, deck keys down to what their
   captions need, the wheel is drawn smaller (262 down to 200), and a cabinet refits when its
   own content changes size. The 480x360 rung D58 left clipping a room now fits every room.
5. **The status card steps down under the page tabs when they would meet.** The strip is
   right-aligned and as wide as the card, so at 960x640 and at 2x on most windows its first tab
   sat on the purse, a layer above it. `PanelLayer` tells the HUD where its tabs are after every
   fit, by group; the tabs do not move.
6. **Floating numbers leave by shrinking, never by fading, and the fountain throws coins.**
   D63 kept a fade over each number's second half. Over a flat backdrop — the chroma green a
   streamer keys out — a half-transparent pale core in a half-transparent outline is a grey ghost
   of the number, on every hit. A number now holds full size while it is read and then draws in
   to its own centre, never larger than its settled size, so `_place`'s reservation still covers
   it. The fountain was ten labels each printing the same tenth of the headline beside the
   headline that states the total, and it took ten of the twenty-four number slots with it; it is
   now the currency's glyph plotted as a coin — pale core, outline in its colour, hard shadow,
   every pixel ink or nothing — from a pool of its own, shrinking out as the numbers do.

**Left as it was, and why.** The 1.6x headline punch overhanging the HUD for a fifth of a second
stays as D48 decided it: clearing the punch moved a centred headline ninety pixels off centre for
its whole life. Hairlines (a list row's rule, a dead tile's, a pip's) stay 1px and so are 1 or 2
screen pixels at a fractional size — the only width that is whole at every quarter step is 4, and
a hairline that heavy is not one. Pixel type's stems are still 2 or 3 wide at 1.25x; D58's
`oversampling_override` fix needs the shell in a viewport of its own. A number's drop shadow is
still 55% black and its face still the imported, antialiased one: both are constant rather than a
ghost, and changing either changes every number on every desktop, which wants eyes. The shop's
picture now sits inside the detail scroll, so its 1.35x spawn punch can lose a few pixels to the
scroll's edge for 0.15 s.

*Consequence:* `ui_check`'s `menu sizes` suite runs the real shell at 960x640 1x, 1440x960 1.25x
and 2x, 1180x760 2x, 960x640 1.75x and 480x360 1x, and asserts at each that every rule in the
theme is whole on screen and the shell draws with it, no page and no Arcade room is wider than
the card, every tab and room caption fits its key, the shop does not scroll the card, and the
tabs never sit on the status card — and that the theme is rebuilt only when the rule width
changes. The geometry suite presses, hovers and disables a real key of every Button variation
and asserts its rect; `loop_check` asserts every state of every variation is the size of its rest
state and the rule ladder over every quarter step; `no ghosts` watches a payout's whole life and
a whole fountain frame by frame and asserts nothing is drawn part-transparent and everything
leaves by drawing in. A new variation, a new tab or a new room is covered by the sweep the day
it lands.

## D69 — Eight pictures that said the wrong thing, and icons thicker than what they label (2026-09-26)

**Decision.** Eight item sprites are redrawn as grids in `art/pixel/`, the way D62 drew
fourteen: the three weapons D62 held back until their colliders were re-authored (hole punch,
satchel charge, letter opener) and the five that were the weakest left on a full contact sheet
(halberd, tesla coil, mortar, heated blanket, and the scythe, recoloured). Every long item
whose shop icon was a hairline gets an icon grid in `art/pixel/icons/` that is deliberately
*thicker than the item*. Where a redraw moved a picture, its physics row moved with it (D25,
D61), measured, and its scene was re-seeded alone with `--only`.

**Why these eight.** The roster was laid out at game scale beside him on a dark and a light
desk, and the same question asked as in D62: what does a player see in peripheral vision?

| Item | read as | the redraw leans on |
|---|---|---|
| hole punch | a floppy disk | from above and to one side: a red lever plate, two coiled plungers with daylight between them, a sheet with two holes in it |
| satchel charge | a sack of gold | green canvas, a leather strap arched over it, buckled straps, three red sticks out of the top, 3:00 chalked on the pocket |
| letter opener | a brown stick | brass all through: a slim lit blade, a bolster one pixel proud, a red grip, a pommel |
| halberd | a labrys on an invisible pole | one bearded axe, a hook, a spike, a wooden shaft that reads on a dark desk |
| tesla coil | an arcade joystick | a steel toroid, a copper-wound column, the primary's copper spiral, one spark |
| mortar | a telescope, dark end to end | short, fat and at seventy degrees: olive tube, flared muzzle, the bore, a bipod, a base plate |
| heated blanket | a raw steak | a pink quilt folded once, its stitch crossings glowing where the wire runs, a turned-back corner, the controller |
| scythe | an outline on a dark desk | the same pixels, recoloured: a steel blade with a white edge, a wooden snath |

Four things were learned by drawing them wrong first. **Straight on, a hole punch is a table**:
a lid on two legs with daylight between them, and every version drawn from the front read as a
bench or a toaster; from above and to one side, with the sheet it has just punched, it is a hole
punch. **A crossguard makes a sword**: the first letter opener was a gold dagger, and cutting the
guard back to a bolster is what made it a desk tool. **Two holes in a frame is a face**: the
punched sheet with its holes as dots in a white box smiled, until the holes became lenses; the
satchel's chalked 3:00 did the same at two thirds, which is why it has its own icon. **A folded
stack in red is dynamite**: the first blanket was three red folds and read as sticks.

**Why the icons are drawn thicker than the items.** Every icon was measured for its content.
Seven are under ten pixels on their short side (hunting rifle 6, pump shotgun 7, baseball bat 7,
cricket bat 8, rolling pin 9, blunderbuss 9, the shotgun cursor 10), and three more pass only
because a hairline is drawn at an angle (scythe, tyre iron and halberd, at about four pixels of
picture per pixel of length). Turning a long thing 45 degrees does not rescue it: a rectangle
L x T turned needs (L + T) / 1.41 of the square, so a 4:1 rifle drawn to scale grows by about an
eighth — four pixels longer, one pixel thicker. So the icon has to be a caricature:

- **The three long guns** are their own sprites with the barrel, stock, scope and fore-end rows
  doubled (and eight columns of the rifle's barrel taken out), laid on the 45-degree lattice:
  icon pixel (x, y) is sprite pixel (x - y, x + y), so a sprite row becomes an 8-connected
  diagonal and nothing is resampled by a fraction. Across their own axis they went 6 -> 12,
  7 -> 10 and 7 -> 11 px.
- **The halberd and the scythe** are their own shapes turned 45 degrees at about two thirds,
  with the pole shortened to what the corner leaves; **the tyre iron** is itself at full size
  with fourteen rows of bar cut out of the middle. Picture per pixel of length went from 4.4,
  3.6 and 4.3 to 9.0, 9.3 and 6.5.
- **Left alone:** the bats and the rolling pin (their short side is the object's real width,
  they are solid, and a diagonal gains under a pixel), and the shotgun cursor, whose pistol grip
  turned 45 degrees reads as a bent stick. The satchel, tesla coil and heated blanket also got
  icon grids, because stepped down their one telling detail — the time, the windings, the
  quilting — turned to noise.

**Colliders.** Six of the redraws are authored bodies and were re-authored against the new art
with `collider_report -- --tables --shots --runs` before their scenes were written; the scythe's
silhouette is byte-identical, so its D61 row stands, and the heated blanket kept its exact 42x30,
so its derived collider (D55) and its scene are untouched.

| Body | cover | air | overhang | what moved |
|---|---|---|---|---|
| hole punch | 97 % | 8 % | 6.2 px | two boxes became six that stop short of the parallelograms' empty corners |
| satchel charge | 98 % | 4 % | 5.3 px | the pin moves from the charge to the top of the strap, the same lever from the weight |
| letter opener | 93 % | 8 % | 0.0 px | blade, bolster, grip and pommel; grip and weight where they were |
| halberd | 96 % | 5 % | 3.5 px | axe, beard and hook for two circles; weight two pixels toward the axe |
| tesla coil | 97 % | 3 % | 1.8 px | toroid, column, spiral and base; the spark is light and not solid, and clear columns in the grid balance it so the coil stands, and shoots, on the centre line |
| mortar | 90 % | 3 % | 1.0 px | it flips, so only the base plate and the tube's foot are solid (D61); pin at the top of that column, muzzle at the new bore |

`swing_rig`, momentum handed to him, before -> after: hole punch 3,623 -> 3,760, letter opener
2,553 -> 3,335, halberd 5,031 -> 5,010; the three references did not move (3,005 / 4,181 /
3,224). The letter opener now sits inside the references' band rather than under it: it lands
in one clean contact where it used to land two glancing ones. Peak weapon speed moved at most
6 %. The halberd turns faster (4.8 -> 7.7 rad/s; the scythe below it is 6.9): Godot shares a
body's mass out by shape area, the new head is drawn bigger, so more of its 16 kg sits beside
the centre of mass and less along the shaft, and its inertia fell by a quarter.

*Consequence:* `make_icons.py` skips any id with an icon grid, instead of writing a downscale
over it — a full run would otherwise put the halberd's stick back (and would already have
overwritten bubble wrap's). `pixel_icon.py`'s docstring says how the long things were drawn;
each grid's header says what the old picture read as. A grid is centred by its width, clear
columns included, which is how the tesla coil keeps its column on the centre line beside a
spark: `brain_check` wants a turret that does not flip to shoot from within two pixels of its
middle, and the first version, shifted by the spark, failed it. The mortar is less solid than
it was, because what stands in both of its facings is now its base plate and the foot of its
tube: mirroring shapes with the sprite is still the owner's call from D61. *Not drawn:* the
hornet, which is small in the world; the swarm launcher, which reads as a speaker. *Not seen:*
this pass ran headless on a machine the owner was using, so everything was judged from rendered
previews at 1x, 2x and 8x on a dark and a light desk, never on a real one.

## D73 — Idle did not double: one run measured a busy machine, and the stage now says what it held (2026-09-26)

**Decision.** Nothing in the game changes for performance. The reading that started this —
idle at 14.30 % of one core (0.89 % of the machine) on `m3.9-toybox` @ 06d67fd, against D42's
6.7 % — did not reproduce, and M3.9 costs what D42 cost to within the noise. What changes is the
measurement, which could not tell a regression from a busy evening: the stage stops writing the
player's settings, its report says what frame cap it held, the tool repeats itself and says how
busy the rest of the machine was, and a `toybox` stage puts M3.9's things on the desk.

**Measured.** Same machine, same night, the owner's `settings.cfg` copied into a private user
folder (play area 1440x960, menu 1.25x, chroma backdrop, caps 30/60). Release builds of 5e6ac94
(D42) and of this branch (06d67fd plus the stage changes below, which touch nothing outside the
flag). `perf_measure -Repeat 3`, each run a minute or more after a 20 s warm-up. Share of one
core, minimum and range; the machine figure is that minimum over sixteen threads:

| stage | D42 build | M3.9 | machine, D42 → M3.9 |
|---|---|---|---|
| empty | 5.41 (5.41–6.00) | 5.68 (5.68–6.00) | 0.34 → 0.36 % |
| idle | 6.80 (6.80–7.36) | 7.06 (7.06–8.08) | 0.43 → 0.44 % |
| load | 14.07 (14.07–14.77) | 12.67 (12.67–14.15) | 0.88 → 0.79 % |
| toybox | — | 6.83 (6.83–8.19) | 0.43 % |

Through all of these the rest of the machine was 32–73 % busy (a Codex session, other agents'
suites), and the script now says so on every run. Earlier the same night, one-minute windows
with the old script: idle at 06d67fd 7.80–9.20 % over fifteen runs, D42's build 7.22–9.41 over
nine; empty 6.00–6.63 against 5.99–6.15. Nothing the same commit did tonight came within 5
points of 14.30, and D42's own build measured *load* at 14.07–14.77 — above the 12.26 that was
read for M3.9's load in the same breath as the idle figure.

**Why one run could say 14.** The process's CPU time is not independent of the machine: shared
cores and a contended driver make the same frame cost more of it. A sixteen-thread burner beside
the idle stage moved it from 6.95 and 7.95 to 8.76 and 9.16. The 02:15 run cannot be replayed,
and the tool could say neither how busy the machine was nor what the game was doing — and
twice the CPU with twice the GPU (4.0 % against ~2) is exactly what the 60 fps active cap looks
like from outside. The report now prints it: `idle_cap 73 of 85 s` is a desk that slept (the
bat falling on him, his walk to the tub and back are the rest); a number under half its window
is not an idle measurement.

**Where an idle frame goes**, read in-process from a scratch build (never committed), idle desk
at the 30 fps cap: every `_process` together 60–110 µs a frame; every `_physics_process` 35–60
µs a tick and the physics server 12–20 µs a step, in both builds — M3.9's `StepStart` ledger and
the rest add about 8 µs a tick, 0.05 % of one core; rendering about 0.55 ms of CPU a frame at
D42 and 0.65 at M3.9, the one difference that shows, about 0.3 % of one core. Switching
rendering off takes empty from 6 to 2.7–4.0; hiding the whole shell (44 of its 47 draw calls)
saved under half a point, and vsync off, the backdrop off or him hidden sat inside the noise.
Taking the hot tub off the idle desk saves 2 points in both builds: it pays a number every
second and steams, which is what it is for. The shell draws the same: 47 draw calls empty at
D42, 48 at M3.9 (D52's grip).

**Candidates cleared, each by looking at it running:** the `StepStart` ledger (above); the HUD
streak row's 20 Hz timer, which stops when the streak does and was never running at idle;
GestureZones and ItemVerbs, which are event-driven and have no per-frame hook; the walk cycle,
which plays only while he travels; the idle brain, one 2 s think timer with steering switched
off while he watches; FXLayer's placement, which runs once per number; the eighteen pooled
particle emitters, which draw nothing when idle (0 draw calls with all of them hidden); bodies
that never sleep — none on either desk (`awake_peak` 0 on the toybox, 2 on idle during the
bat's fall and his walk).

**The stage wrote the player's settings.** D42 said it never did. It did: a staged toy's
one-off controls tip marks itself seen, and `mark_hint_seen` saves — to the player's own file.
Measured in a private folder with the hot tub's tip unseen, one idle run and `settings.cfg` had
gained `controls:hot_tub`. The stage now reads the player's settings (window, menu size and caps
are what it measures) and writes to `user://settings_perf.cfg`, as D51 asks of every test, and
marks the staged items' tips seen first so a first run on a machine does not unroll a toast the
second does not.

**The toybox stage** is a fidget spinner, a Newton's cradle, bubble wrap, a boombox, a lava
lamp, a houseplant and a fish tank, worked by a one-second timer rather than the mouse — the
spinner flicked when it stops, the cradle pulled when it settles, a bubble a second, the next
track every six — because pushed input pins the active cap for the whole run. It sits at the
idle cap for its whole window with nothing awake, and costs what idle does. **A held gun is not
staged**: `HeldGun.fire()` refuses unless the gun is dragged, and a held body's handle follows
`get_global_mouse_position()`, which in the root viewport is the OS cursor, so a synthetic hand
would chase the real mouse. The load stage's pellet turret runs the same bullet, hit and payout
path.

**Working set: nothing grew.** Private bytes at idle were 335–424 MB for D42's build and
286–320 for M3.9; at load 405–425 against 378–405; empty 325–354 against 278–308. The working
set swings 50–100 MB between identical runs as Windows trims it, and the first run after an
export compiles shaders (418 MB for both builds in a fresh folder), so "364 against 320" was two
single readings. The script prints private bytes beside it now.

**Seen, not changed.** A toy that animates in `_process` — the spinner, the cradle — does not
lift the idle cap; only an awake body or input does. At 30 fps a spinner at full speed turns 73
degrees a frame, and with three arms that reads as turning backwards. Lifting the cap
while a toy animates costs what the active cap costs (compare idle and load above); that is the
owner's call, not a performance fix.

*Consequence:* a performance claim is the minimum of `perf_measure -Repeat 3` (or more),
read with its "everything else" line and its `idle_cap` line; D42's table stands as a single
run. `perf_measure` reads the report from the folder an `override.cfg` beside the exe names, so
a scratch build with its own folder is measured without touching the player's files — which is
how every number above was taken.


## D70 — The loose ends: his own play, Off still earns, in the beanbag, blasts with a ceiling, gestures that outlive a panel (2026-09-26)

**Decision.** What the item audit (D59), the AI audit (D60) and D64–D66 measured and left, closed
together, each with a check that fails without it. Thirteen fixes; one finding recorded rather
than changed.

**1. He goes back to the cradle and the car.** brain_check's two failures at 208a8d1. Both toys
quoted zero appeal while running — the cradle while it swung, the car while it drove — and zero is
the brain's "nothing to do here" (D57). His last tick at either set it going, so the moment he
looked round for a toy it was nothing. Every D57 toy quotes a steady appeal and lets `idle_use`
decline while busy; these two do the same now. A car carrying him on a ride still quotes zero.

**2. His own play is never a hit.** D64 billed the mat's landings, which is right for a player who
throws him on and wrong for his own bouncing: about 17.6 damage a second at an empty desk, a Bones
engine nobody bought, on top of the Hearts the brain pays for the same bounce. That broke both of
the brain's rules at once — the toy or the brain pays, never both; and what earns unattended is
automation, which D2 prices in Hearts. While the brain has him travelling to or playing at a toy,
`Buddy.begin_own_play(toy)` makes that toy and the world his own doing: not billed at all, not
billed to someone else, and before the per-source cooldown, in both the reported path and D64's
ledger. Anything else still is — a bat, a turret, an animal, a pellet. The player taking him or
arriving ends it at once; a routine that runs out ends it when he has been still on the ground for
half a second, because a trampoline goes on throwing him after the dwell. His own bounces no longer
count on "Bounce him 100 times". The bowling ball he bops onto his head stopped billing Bones too,
which settles audit C: played with for its own sake at any Focus.

**3. At Focus Off every routine toy still earns** (audit A). At Off he is simply there (D21, D36)
and every kind toy pays only for touch, so the soaks, scrubs, snacks and kind balls earned nothing
at Off — 21 of the 40 routine toys that pay Hearts, measured six hundred pixels from him. Of the
audit's two options this takes the first: the brain asks the toy to pay for his presence
(`FriendlyBase.pay_presence`), as itself and down its own roads — a touching rate as a trickle, the
sponge's grime, a helping at the contact cooldown as an act, eaten if it is food — never on top of
real contact, and nothing moves. The other option, choosing only brain-paid toys at Off, would have
made Off a different game. A jack he wound laughs out of earshot now, too: its laugh was gated on a
distance that at Off, with no walk, he was usually outside. 40 of 40.

**4. He gets in the beanbag** (audit B: 0 of 9 soak toys with him on or in them). A convex collider
cannot be sat in, so he is let in, the way the pull-back car lets him onto its roof:
`FriendlyBase.take_in(him)` hops him over its edge and across to its middle, the two passing
through each other, and when his feet come down through the seat line he is pinned there by two
joints a head apart, the toy frozen under him and drawn over his legs. The seat is `seat_depth`
(0.45) of its height below its top, never deeper than 0.4 of his own, so in a hot tub or a
recliner he sits with his head and shoulders over the side. Sitting in it is touching it
(`touches()`), so it pays as before, and the hot tub's jets still know he is in. He hops out over
the nearer side when the dwell ends; picked up, knocked down, or the toy moved or binned, he is let
go, and the two keep passing through each other until he is clear. 9 of 9, and `soak_shots` shows
each one reads as in it. One consequence is recorded rather than changed (audit I): sat in a
beanbag he is out of the goose's 78 px reach, so it waits beside it.

**5. No blast hands one body more than 7,500 px/s.** D54's drag backstop, for blasts. A blast's
push is `impulse / mass`: right for him at 3 kg, absurd for a light prop — a 0.3 kg prop the black
hole charge gathers was thrown at 56,462 px/s in one frame (74,608 upgraded), the implosion
charge's at 36,698. `ExplosionUtil.MAX_BLAST_SPEED` caps the push as a change of speed in both
blast functions; a caller may pass a smaller one. It sits above every launch a blast gives him (the
black hole's 6,478 is the fastest), so no explosion is smaller as he feels it: every explosive's
peak on him in item_check is what it was. The impulse billed to him is untouched.

**6. The gorilla's slam throws him no harder than the blunderbuss** (audit D). The slam's impulse
is sized for its damage and threw him at 4,640 px/s, past the drag's own 4,500 backstop. Its push
is capped at 2,500 (`slam_max_speed`, the blunderbuss's 2,536); its damage is not — 140.1 from
14,015, as before.

**7. A gesture outlives a panel, and not the focus.** Two faults in how a held gesture ends.
`GestureZones` heard only unhandled events, so a drag across the HUD's "next up" row lost the
motion to the panel and the slingshot's pouch froze at its edge (D66 measured it); a live press,
action or carry now listens in `_input` until it ends, exactly as the minigun's stream does, and
nothing listens at rest. And a gesture the game lost focus in was let go of: the RELEASE and
ACTION_END that `cancel()` sent on focus-out were a let-go's, so alt-tab mid-draw fired the
slingshot at him. They carry `cancelled` now, and every hold-to-act toy stands down instead — the
slingshot slackens, the car unwinds, the cradle's ball goes back, the slinky goes home without a
boing, the stress ball springs back unpaid, the yo-yo winds in without a trick, the spinner
settles. The held guns and the four held cursor powers never heard about the focus at all: alt-tab
mid-stream and the SMG or the minigun fired, and paid Bones, until the next click. They let go.

**8. The fortune ball fills as it is shaken** (F10). A shake was one whole reversal against
`4 x 0.94^n`, still four for levels 1–4. Each step of a stroke is now worth its share of a shake as
it happens, up to one 32 px stroke, and a straight drag is not a shake: 6% less shaking is 6% less
shaking. item_check measures the shaking itself — 112 px plain, 108 at level 1.

**9. The implosion charge's grab region is its sprite's** (D65's note): 88 x 76 drawn round an old
picture, 70 x 76 from its seeder now, re-seeded with `--only`.

**10. The smaller ones.** An animal's body faces the fall floor, so only its telegraphed blow hurts
him (audit E; a goose's grapple is its 8 shakes, not 16 hits). The Nervous one's threat holds wait
behind his early flinch instead of being refused (audit G). He eats only food; the rubber duck is
bopped (audit G). A toy outside the walls is not a destination (audit F): the brain asks
`WorldBounds.arena()`, found by group in its own viewport, rather than the window — which is why
the first attempt was reverted, and why loop_check's hand-built desk is untouched.

**Recorded, not changed: autonomous hits and Dollars** (audit H). By D31's letter a turret's hit
earns the flat per-hit Dollar like any other. By its point it should not: Dollars are earned by
being present, and automation pays them at `dollars_idle_efficiency`. A pellet turret banks about
3,270 an hour at an empty desk against an automation tick's 540; the toys he nibbles and bops pay
as acts, which the combo, the board and the Dollars all count. A balance call for the owner, with
the two-line fix written into the audit.

**Why these, and why together.** Each is a sentence of the form the audits exist to find — *this
does not do what it says*, or *this pays for something nobody did* — and most sit between two
systems: the brain and the toy, the blast and the body, the gesture and the panel. Every one was
measured before it was changed, and every check here was run against the code without its fix.

*Consequence:* `Buddy.is_own_play`, `FriendlyBase.take_in`/`let_out`/`touches`/`pay_presence`,
`ExplosionUtil.MAX_BLAST_SPEED`, `Gesture.cancelled` and `CursorPowerBase.release_hold()` are the
new seams: a new held toy honours `cancelled`, a new held power overrides `release_hold()`, a new
soak toy is sat in by default and tuned with `seat_depth`. brain_check takes `--toys id,id`, walks
every routine toy at Off, and fails an animal that throws him past the drag's backstop or hurts
him with its body; `tools/soak_shots.tscn` (windowed) shoots him in each soak toy. Three of the
suites' own timing flakes were found on the way and fixed at their cause: item_check counts touch
on every tick, brain_check holds his mood still across a reading and times a tell on the
engine's clock (docs/ai-audit-2026-09.md J). Pacing moves
nowhere — no price, rate or knob changed: 4/4, first Reincarnation 9:47:54. *Not seen by a
person:* the slingshot drawn across the real HUD, the goose waiting at the beanbag, the duck being
bopped.


## D74 — Every held weapon does one thing no other weapon does: the right button (2026-09-26)

**Decision.** Right while holding a melee weapon is its **ability**: a Home Run on the bat, an
iaido cut on the katana, a BONG on the frying pan. Each is a row in `AbilityTable`
(`Scripts/Bodies/Abilities/ability_table.gd`) naming one of eight **archetypes** — charge, dash,
stun, sustain, shockwave, projectile, spin, throw — with that weapon's numbers. `WeaponBase` reads
its row at `_ready` and adds the archetype as a child, `WeaponAbility`. Eight weapons have one:
the bat, katana, frying pan, chainsaw, sledgehammer, golf club, nunchaku and fire axe. The other
26 are on a design sheet below, and `loop_check` holds them on a list that may only shrink.

**Why.** The owner, verbatim: "I had a bit of a gripe with variability between items, I felt with
some melee weapons that they just felt similar to the previous, which of course they are supposed
to feel mostly similar, but other than their sprite they didn't feel unique. perhaps we can
leverage the left to hold right click to activate mechanic to give each weapon and item an ability
to activate that is totally unique." He had just played the held guns (D56) and called them
excellent, and they are the bar: a thing in the hand that does something when you ask it to, with
weight and a reason to aim. A bat and a mace were one verb with two pictures. Now each weapon has
a verb of its own, on the button D56 and D57 already gave to "the item's action".

**The grammar is D57's, unchanged.** Left carries. **Right while holding is the ability**: press,
hold, let go, as its line says. Right on a weapon lying on the desk still bins it, and
Shift+right bins it held or not. A press during the cooldown is claimed and refused (a dull tick,
and the pip flashes), never passed through: mashing right on a cooling bat must not throw the bat
away. The same holds while an ability is still at work out of the hand, as with an axe in the air.
Every weapon teaches its line on the shop's HowTo strip and on first landing,
`Hold · Right: <Name> — <what to do>`, written onto `ItemData.controls` from the table by
`tools/seed_m311_abilities.tscn`.

**Read at runtime, not seeded.** D67's verbs are seeded into their scenes, because a click zone is
geometry that sits beside the art. An ability is behaviour and tuning. Seeding it would mean
re-running four seeders that own the weapons' scenes for every number changed, one of which
(`seed_bodies`) has no `--only` and would rewrite the grenade, the dynamite, the mine and the
firework to reach the bat. So the table lives under `Scripts/`, which the export carries, not
beside `verb_table.gd` in `tools/`, which the export filter drops. No scene was touched.

**Damage is still his to measure (D7, D64).** An ability never mints anything. It does one of
three things, and he bills each one:

- it moves a body, the weapon or him, so that a contact happens and his ledger bills it (the
  whirl, a Home Run's swing);
- it scales the weapon's own contact multiplier for a hit (`hit_multiplier`), which he reads in
  `_attribute` exactly as he reads the damage augment. `register_use` tells the ability first and
  it only records, so the multiplier he reads on the next line is the one the hit was armed with;
- it hands him an impulse through `Buddy.take_impulse`, the gunshot's path, at the weapon's
  multiplier (the cut, the grind, the wave, the ball, the axe's chop).

Anything it applies to *him* directly — the Home Run's launch, the wave's lift — is applied from
the ability's `_physics_process`, which runs before `Buddy.StepStart` reads the step's starting
velocity. Applied later, from a deferred call or a timer, his ledger would read it as a contact
and bill it a second time. Where he lands after a launch is billed to the weapon for a moment
through D65's `claim_impacts`: only who is billed changes, never whether.

**The first eight**, measured in `ability_check` on a 1280x720 desk with the real stage.
"Worth" is what one use added, in ordinary hits of the same weapon on the same rig (the boost on a
multiplied hit, the whole of a hit the ability handed him itself, and a whirl's hits less the swing
they replace).

| Weapon | Ability | Archetype | What you do | Measured |
|---|---|---|---|---|
| Baseball bat | Home Run | charge | hold: the head cocks back over the shoulder, sparks gather, a ratchet climbs; let go: it whips round, and the next hit in 0.8 s is x2.5 and throws him | he leaves at 1,390 px/s; 1.4 hits' worth; his landing is the bat's for 2 s |
| Katana | Iaido | dash | tap: a glint, then the hand lunges 276 px through him, holds, returns. The blade passes *through* him and the cut lands 0.3 s later | blade 2,700 px/s; cut 3,640, billed once, 0 contacts on the way through; 2.4 |
| Frying pan | BONG | stun | tap to ring it; the next pan hit is x1.5 and dazes him for 3 s — stars circle his skull — and every pan hit in the daze is x1.3, a note higher each time | 10 to 12 hits a use against an aggressive hand; 3.7 to 4.3 |
| Chainsaw | Rev | sustain | hold on him: the engine climbs, it bucks, exhaust puffs, and the chain bites a hit every 0.13 s at 520 for 2.5 s of fuel, dragging him onto the bar | 7 grinds in the suite's second; about what swinging a 17 kg saw earns, without swinging it |
| Sledgehammer | Ground Pound | shockwave | tap: the hand lifts and drives the head into the desk; everything within 280 px is thrown up, 900 px/s at the impact | slammed 100 px from him: lifted at 770 px/s, 145 px into the air |
| Golf club | Drive | projectile | hold: a ball on the face, the power fills, a dotted low arc through him; let go and the ball flies. Underpowered, the arc falls short and the dots say so first | 1,300 px/s; the ball 2,200, billed once |
| Nunchaku | Whirlwind | spin | tap: 1.2 s whirling about the hand at 18 rad/s; each pass through him is a glancing hit, x0.6 | 15 rad/s peak, 2.4 turns, 4 hits with the hand following him; 3.1 |
| Fire axe | Tomahawk | throw | tap: thrown end over end on the low arc at him; it chops once and comes back to the hand if left is still held | the chop 2,497 at x1.3; home in 0.4 s from 250 px; caught |

He answers four of them with rows of his own (`launched`, `dazed`, `sliced`, `quaked`) and three
with rows that already say it: the grind is `cooking`, the golf ball `startled`, the thrown axe
`blast`. They arrive on a new bus signal, `ability_event`, mapped through
`ExpressionBrain.ABILITY_ROWS`, one `connect` in the brain's `_ready`. Each is told a frame after
the hit it belongs to, deferred, so the ability's row takes the slot from the hit's own. A
wind-up aimed at him (a bat cocked, a saw revved, a ball teed up) is D56's `windup` threat, so
he watches it coming and the Nervous one flinches at it. Seven voices are synthesised for them in
`AudioManager` (D12): whoosh, crack, bong, shing, rev, tock, quake.

The swing feel did not move. `swing_rig`'s deterministic columns (lever, inertia, the momentum
handed to him, peak spin and speed) are identical to the digit for all nine weapons it swings
with the ability idle, the three references included. Only its billed hit grouping differs, which
D61 already records as wall-clock-dependent.

**What cost time, measured.**

- **A throw pays a fraction of its speed.** The first Tomahawk was billed by his ledger like any
  thrown body, and measured a fifth of an ordinary axe swing: D64's "cast-ray CCD arrives
  softly" again. So for the flight he and the axe do not collide, the axe is swept for him (its
  own shapes, and the segment its centre flew), and the chop is billed once, sized by how fast it
  was going. The golf ball and the katana's cut work the same way.
- **The whirl jammed.** Spun toward him from still, the nunchaku started pressed into him and
  ground there at 7 rad/s, a fifth of a turn. It starts away from him now and comes round at
  speed. Each blow knocks him on, so a whirl is a thing you follow him with.
- **An impulse cannot aim a 24 kg head.** The first ground pound kicked the head down and whipped
  it toward the floor, and where it met the desk was wherever a heavy body on a soft joint
  happened to go. The hand drives it now, the katana's mechanism on end
  (`BaseDraggable.hand_offset`, the only line this adds to a shared class), so the head lands
  under the hand. A wave that fell off linearly lifted him 34 px from 150 px away and 96 px from
  100. It holds its strength near the impact now (`1 - (d / radius)²`) and lifts him 145 px.
- **The katana's blade lagged its own lunge.** The drag joint is soft (D54), so the blade was
  still leaving when the hand came back, and the frame at mid-lunge showed nothing. It holds
  at the far end for 0.12 s, zanshin, and the blade goes through him on screen.
- **Particles cannot draw a daze.** Orbiting chips fell inward and read as one star on his head.
  The halo is drawn: four star glyphs on an ellipse over his skull.
- **The chain shoved him off its own bar** inside a second, and a six-pixel golf ball was a
  speck. The chain now bites him onto the bar, and the ball is ten pixels with a streak.
- **A hit attributed in `_integrate_forces` is dealt on his next physics tick**, so a suite that
  checks the hit on the frame the ability heard of it finds nothing. And an ordinary swing with a
  heavy weapon can knock him out, so the next measurement lands in the knockout and bills nothing.
  The suites wait out both.

**Pacing.** Abilities that multiply damage add income, so the simulator now prices them. Each row
states its `worth` and its `busy` seconds. A player who uses a weapon's ability every time it is
ready deals `1 + worth / (hits_per_second x (cooldown + busy))` of what swinging it alone would,
at `REAL_HITS_PER_SECOND` = 1.5 in `pacing_sim`. That is a quick hand on a light weapon, and a lower
number prices every ability higher, which is the safe side of the six-hour floor. `ability_check`
fails any row whose measured worth runs past its stated worth by half again, so the table cannot
understate what it pays. The uplifts run from 1.12 (the sledgehammer) to 1.33 (the pan). Result,
4/4: the first Reincarnation 9:47:54 -> **9:11:08**, first automation 17:04 -> 16:57 of play, worst
dead stretch 1:13 -> 1:23, worst ramp 1.0x -> 1.3x. The half hour is income, and it buys back
headroom under the ten-hour ceiling that D66 had nearly used up.

**Budget.** Nothing runs while a weapon lies on the desk or its ability is idle: no `_process`,
no `_physics_process`, no `_input`. The physics tick runs while an effect runs, the input hook
while right is down, and the frame tick while the pip is drawn. The cooldown is a `Timer`.
`ability_check` asserts all three are off at rest, before and after every use.

**Seen, and tested.** `tools/ability_shots.tscn` stages every ability in the real game in a real
window and writes 24 frames and the shop's HowTo strip. Every frame was looked at, and five
abilities changed because of what they showed (the list above). `ability_check` is 314 assertions
over the eight. `loop_check` went 665 -> 747 with the every-melee-weapon suite and the brain's new
wire and rows. `item_check` drives every ability: 123 items, 0 failed. unit 242, ui 621, gun 103,
fidget 188, toys2 178 and verbs 265 are unchanged, and `brain_check` has its two known failures
from another stream and no new ones.

*Consequence:* **a new ability is a row**, plus a subclass of its archetype named in the row's
`script` only if it needs behaviour the archetype lacks:

1. Add the row to `AbilityTable.ABILITIES`: `id`, `name`, `archetype`, `controls`, `cooldown`,
   `busy`, `worth`, and the archetype's numbers (each archetype's class comment lists them).
2. Run `tools/seed_m311_abilities.tscn` to write its line onto the item.
3. Delete the weapon from `loop_check`'s `ABILITY_STILL_TO_DO`, which fails while it is listed.
4. Run `ability_check`. A row of an existing archetype is driven the day it lands. A new archetype
   fails by name until it has a driver there. Give it a stand-off in `item_check`'s
   `ABILITY_STANDOFF` too, or it is used from a default beside him.
5. Look at it: `tools/ability_shots.tscn` (`--fixed-fps 60`, not headless) stages each ability
   mid-effect in the real game and writes the frames to `user://ability_shots/`. A new archetype
   needs a staging branch there, and says so until it has one.
6. Run `pacing_sim`: it prices the new row by its `worth`.

`item_check` drives every ability through the same pipeline and multiplier checks as every other
hit in the catalog. A hit may carry the weapon's multiplier times any the ability billed it
through, and none other. `brain_check` reports the four new rows and the new wire as notes, as
its convention is for a stream's rows, because `ability_check` is what triggers them for real.
*Not done:* the tether, transform and clamp archetypes the sheet below needs are designed, not
built. Each lands with its first weapon. The capture tool lets the axe fall before it is caught,
because the catch re-grabs at the OS pointer, which the tool cannot move. Nothing here has been
used by a person yet. The frames were looked at, and the feel is the owner's to judge.

### The design sheet: one ability for each of the 26 still to do

No two do the same thing with the player's hand. **New** marks an archetype that does not exist
yet: *tether* (hook him and move him), *transform* (the weapon changes state for a while), and
*clamp* (a close-range bite that holds or pinches). *Hook* marks a subclass needed for a detail
its archetype lacks.

| Weapon | Ability | Archetype | The verb, in one line |
|---|---|---|---|
| Mace | Lead Heart | transform (new) | tap: for 4 s it weighs double and glows dull red; slow to swing, and every blow is x1.3 and shakes the desk |
| Morning star | Bristle | projectile, hook | tap: it fires its spikes in a fan of five at him and is bald until the cooldown grows them back |
| Flail | Wrap | tether (new) | tap: the next hit wraps the chain round him; for 2 s he is on the end of it and swings with your hand; let go of right to fling him |
| Halberd | Hook and Spike | tether (new) | tap: the hook reaches 200 px down the haft; if it catches him it yanks him back onto the spike, x1.5 |
| Greatsword | Momentum | sustain, hook | hold: the grip loosens and it carries its own weight in long arcs; each hit without it stopping adds x0.15, to x1.6 |
| Cleaver | Embed | throw, hook | tap: thrown end over end; if it hits him it lodges in him for 3 s, a light bleed tick every half second, then drops out |
| Machete | Brush Clear | shockwave, hook | tap: one wide chest-high swipe; everything in a 120-degree cone in front is thrown away from you, props off the desk, him with them |
| Sickle | Reap | dash, hook | tap: the hand sweeps a low arc along the desk; catch his feet and he is upended, head over heels |
| Scythe | Soul Reap | projectile, hook | swing with right held: a ghost of the blade flies on along the swing and passes through him, the iaido's cut at range |
| Rapier | En Garde | sustain, hook | hold: it points itself at him like a held gun (D56's aim); a thrust along the blade is x2, a swipe across it x0.5 |
| Katar | Flurry | sustain, hook | hold: the hand jabs at him six times a second, each a real contact; you steer the jabs |
| Boxcutter | Snap | projectile | tap: click-click-click, three snapped blade tips flicked at him dead straight, no arc |
| Letter opener | Special Delivery | throw, hook | tap: flies point-first in a straight line and sticks where it lands, x2 on the point; you go and fetch it |
| Crowbar | Pry | tether (new) | tap with it against him: it wedges under him and levers him up and over the bar |
| Cricket bat | Middle It | stun, hook | tap: the middle of the face glows for 1.5 s; a hit on the middle third is x2.5 and sends him straight up, a six; off the middle it is an ordinary hit |
| Rolling pin | Flatten | sustain, hook | hold: it rolls under the hand along the desk; roll it over him and he is flattened, squashed and x1.5 |
| Stapler | Staple Gun | projectile, hook | hold: staples at him five a second, straight; twenty to a strip, then the cooldown is the reload |
| Hole punch | Punch | clamp (new) | tap with his arm in the jaws: it bites once, sharply, x2, in a burst of paper confetti |
| Shears | Snip | clamp (new) | tap: the blades snap twice in quick succession on whatever is between them; a snip near his head takes his headphones off (D62) |
| Pipe wrench | Crank | clamp (new) | tap against him: the jaws clamp on for 2 s; right-drag circles and he is cranked round about them (D57's crank gesture) |
| Tyre iron | Ricochet | throw, hook | tap: thrown, it tumbles and each wall it hits redirects it at him, up to three banks |
| Energy sabre | Ignite | transform (new) | tap: for 4 s the blade is lit; it passes through him (no contact) and burns a tick every 0.2 s it spends inside him |
| War pick | Pinpoint | charge, hook | hold: a crosshair walks onto him; let go and the beak drives into that one spot, x2.5, and nowhere else |
| Mechanical keyboard | Keycap Barrage | projectile, hook | tap: eight keycaps pop off in a fountain and rain down on him in an arc, each a light hit, then clack back on |
| Monitor | Blue Screen | stun, hook | tap: the screen goes blue and he freezes, staring; the hits you land in the 1.5 s are stored and dump into him at once when he comes back |
| Office mug | Hot Coffee | projectile, hook | tap: a splash of coffee arcs out; it scalds (a light hit, his `cooking` face) and puts grime on him |

**Beyond melee, the same button.** Ideas for held things that are not melee weapons, left for the
owner:

- **Balls.** The baseball's *Curveball* (thrown from the hand with right, it breaks late toward
  him), the tennis ball's *Serve* (tossed up and struck, fast and flat), the bowling ball's *Strike*
  (bowled along the desk: it rolls at him and he goes over like a pin), the beach ball's *Spike*
  (a volleyball smash he tries to return).
- **Kind handhelds** pay Hearts, so theirs are acts. The sponge's *Wring* (squeezed over him, it
  rains clean water on a patch of grime), the feather duster's *Tickle Flurry* (a burst of
  feathers he cannot help giggling at, the `laugh` row), the warm towel's *Wrap* (thrown round his
  shoulders, a few seconds of warmth that lifts his mood), and the soft brush's *Polish* (a
  sparkle that makes the next pet worth more).
- The water pistol and the bubble blaster already use right for their shot (D56). They keep it.


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
