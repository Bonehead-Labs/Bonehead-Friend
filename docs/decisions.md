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
