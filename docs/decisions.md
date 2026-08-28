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
- **Play area** — a small window (480x360 by default) the player snaps into a screen corner
  or drags anywhere.

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
