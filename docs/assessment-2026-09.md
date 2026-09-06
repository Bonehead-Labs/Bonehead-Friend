# Holistic assessment — 2026-09-02

Where the game stands after M3.7, graded against the owner's four priorities in order. Sources:
the four suites and the pacing simulator run today, the 30-minute human session logged on
2026-08-31 (`user://logs/session_2026-08-31_21-41-56.csv`), a read of every production script,
a scripted pass over all 100 item resources and scenes, and a look at every sprite, icon, buddy
frame and shell capture. Nothing was changed; this is the list to work from.

**Baseline today:** unit 206 / loop 379 / ui 196 / pacing 4 of 4 / boot clean. Save schema v4.
One live error and one live warning in every play session (§1). The pacing simulator now takes
about eight minutes, not "about a second".

The one-paragraph version: the engine is in better shape than the docs say and the code is
healthier than most solo projects. What is not finished is the *experience* — the kind half of
the game has almost nothing to do with your hands, the buddy has ten faces and three triggers,
the cursor and turret tabs draw nothing when they fire, and the HUD never tells the player what
to want next. None of the fixes below touch the save schema, and only a handful touch
`balance.tres`.

---

## 1. Clean code, mechanics as intended, performance

**Verdict: healthy.** CLAUDE.md's rules are actually followed — no `print`, no absolute paths,
signals over lookups, data in resources, pooled FX, cached audio. What remains is a short list
of "polls when it could listen" and a few string allocations in loops, plus one real bug.

### The live error, pinned

The 26 `Lambda capture at index 0 was freed` errors in the Aug 31 log come from
`Scripts/Components/effects_player.gd:57-66`, **not** the shop row I first blamed. Two lambdas
capture the `explosion` node: `animation_finished` frees it at about 0.5 s, then a redundant
2 s `create_timer` lambda validates its captures before running, finds the node dead, and prints
the error. Once per explosion, up to fifteen per cluster or napalm throw. `loop_check`
reproduces it after the missile-strike assertion. Fix: drop the timer, or connect the bound
method (`timeout.connect(explosion.queue_free)`), which auto-disconnects when the node dies.
`panel_layer.gd:305-307` has the same shape (captures the purse into a 0.41 s timer).

The `UIStyle.boxed: 128x128 into a 64 box` warning is content, not code: thirteen item sprites
are 128 px (`gorilla, greatsword, halberd, hammock, hot_tub, massage_chair, mechanical_keyboard,
monitor, paddling_pool, rail_gun, recliner, scythe, trampoline`) and skipped the size table in
`item_postprocess.py`. `boxed()` handles them correctly by halving, so in the shop hero well the
hot tub draws at 35 px beside a katana at 56 px — the one place toys are compared side by side
inverts their sizes. `ui_check` never opens a 128-cell item, which is why its `shrunk` assertion
passes.

The leaks printed at `loop_check` exit are the harness: `loop_check.gd:204,206` construct two
`RigidBody2D`s for a method check and never free them.

### Performance, ranked (budget is < 3 % idle on an export)

1. **`hover_drawer.gd:84,108-128`** — `set_process(true)` in `setup()` and never off. Both
   drawers run every frame for the whole session, parked or not. Sleep at target, wake on motion.
2. **`npc_base.gd:358-383` + `overlay_manager.gd:53-56`** — NPC steering applies force every
   physics frame, so the body never sleeps, so the frame governor sees active physics and pins
   60 fps. A permanent NPC (the Enclosure capstone) defeats the idle governor for good.
3. **`progression.gd:224`** — `get_modifier()` string-formats its cache key on every call, and it
   is the hottest lookup in the game (per friendly and per turret per physics frame, per payout).
4. **`milestones.gd:88-132`** — every `contract_event` walks the whole milestone board, and a hit
   emits three. A 20-shot-per-second turret is sixty board walks a second. Index by goal key.
5. **`panel_page.gd:57`** — `request_refresh` is synchronous and uncoalesced; with the card open
   the shop re-walks 100 items and re-themes every row up to 14 times a second. Defer to once
   per frame and every page inherits the fix.
6. **`friendly_base.gd:149`** — `get_colliding_bodies()` allocates every physics frame per
   friendly, including a boombox that has no touch behaviour.
7. **`economy.gd:242,254`** — a separate Dollars grant on every hit and pet doubles the bus
   traffic of the busiest event in the game. Bank Dollars into the automation tick.
8. Smaller: `hud.gd:75-93` polls the health meter every frame (it has signals);
   `buddy_art.gd:126` converts a StringName to String per frame; `ui_style.gd:315` formats a
   cache key per call; `device_layer.gd:145-152` does a GPU readback per device per rebuild.

### Correctness and rules

- **`throwable_base.gd:44`, `missile.gd:85`, `cluster_bomb.gd:88`, `npc_base.gd:417`,
  `buddy.gd:299`** — coroutines `await` a timer on a node that can be freed mid-wait, guarded by
  `is_instance_valid(self)` *after* the await. The engine never resumes a coroutine whose
  instance is gone, so those guards are dead and Shift+right-clicking a primed grenade logs an
  error in debug. Use a bound method or a child `Timer`.
- **`effects_player.gd:50`** — `get_node_or_null("_particleEffect")` is a name lookup across the
  Explosion scene boundary, the pattern that once disabled every explosion in the game.
- `Data/balance.tres` overrides only two values; nearly every knob in the docs "lives in
  balance.tres" as a script default in `balance_data.gd`. The tuning workflow in `economy.md`
  and CLAUDE.md is misleading about where to edit.
- The tuning CSV's `source` column is empty on every payout row: `EventBus.payout` carries no
  source id, so `tuning_log.gd:63` cannot attribute income per item. `economy.md § Tuning`
  promises exactly that attribution. Add the id to the signal.
- The pacing simulator's greedy buyer rescans all items and all open nodes several times per
  simulated second across 259,200 steps; at 100 items and 427 nodes that is eight minutes.
  Cache the affordable set per currency and invalidate on purchase.
- Low: `save_schema.gd:22` `playtime_sec` is written as zero and never read;
  `effective_damage_mult()` is copy-pasted five times; `world_bounds.gd:35` uses bare layer
  numbers; `open_hand_power.gd:48` and `fist_power.gd:52` poll the mouse per frame; nine call
  sites set `button.icon` directly; `trampoline.gd:412` keeps a dict that is never swept.

---

## 2. Balance and longevity

**Verdict: the kind half is too passive, not too expensive.** The owner's read is confirmed by
three independent sources, but the fix is verbs, not prices.

### What the human session showed (2026-08-31, 29.8 minutes, real save)

| | Bones | Hearts |
|---|---|---|
| First 5 minutes | 7,033 earned | ~20 earned (started at 112) |
| First purchase | pistol at 2:14 | sponge at 2:33 |
| Purchases in 30 min | 8 items, 4 augment levels | 3 items, 15 augment levels |
| Minutes 20–25 | 255 | 4,437 |

Three knockouts in the first 46 seconds paid 826, 1,051 and 1,249 Bones. A pet pays about one
Heart. The player hit him for 17 minutes, then switched sides entirely: 12,270 Bones sat unspent
from minute 18 to 26 while they saved for a boombox, and once beanbag plus boombox ran, mood
pinned at 95 and Hearts snowballed with no input. The two halves were played *in sequence*, not
interleaved — which is the opposite of what the mood seesaw is designed for.

The first kind item that does anything (beanbag, 600 H) came at seven minutes and emptied the
purse to 31. The second (boombox, 1,200 H) came at nineteen. Between them: one verb, the open
hand.

### The roster, counted

| | Harm | Kind |
|---|---|---|
| Items | 68 | 32 (28 priced in Hearts; 4 "toys" on the kind door cost Bones) |
| Player-wielded, repeatable | 56 | **4** (open hand, sponge, duck, baseball) |
| One act per spawn (food) | — | 6 |
| Placed / he uses it himself | 12 | 18 |

Every hands-on kind item sits at the bottom of the ladder (0 / 40 / 60 / 120 H). Nothing you do
with your hands appears again until the 3,000 H jigsaw, and that is a sit-in. After the
baseball, the kind side is furniture.

### Rates, from the scenes

- **Sponge (40 H) pays zero without grime**, and grime only comes from damage
  (`friendly_base.gd:74-80`). For the Hearts-first player the cheapest kind item is dead. The
  human used it four times in thirty minutes.
- **Rubber duck (60 H) held against him pays about 74 H/s** (`rubber_duck.tscn`:
  10 per contact, 0.8 s cooldown, no minimum speed, inside the combo window). That is four times
  petting and buys the 12,000 H hot tub in under three minutes. Either a bug or the template;
  decide which.
- **The top three comfort items are 59 % of all kind spending and earn less than the hot tub.**
  Paddling pool 55k, heated blanket 80k, recliner 120k pay 5 / 6.5 / 9 H/s; the 12k hot tub
  pays 9.8 and the 30k massage chair 35. Their only value is the capstone rate derived from
  their price.
- **Every ambience item at 900 H or more is beaten per slot by a comfort item at or below its
  price**, and comfort needs no attention because the idle brain walks him into it. Wind chimes
  are worse than the boombox, pizza worse than the donut box, jigsaw worse than the foot spa.
- Food dominates active kind income once owned (free unlimited spawns): a noodle bowl fed every
  four seconds is roughly double the massage chair.
- Ladder sinks: Bones 3.57 M over 54 rungs, Hearts 432 k over 27 rungs, while all 100 capstones
  are Hearts-priced (level 1 of the harm capstones alone is about 1.48 M H). Kindness is
  monotonically the better strategy at every attention split, and a harm-only player never
  automates.
- Harm side, by declared multiplier: 22 of 34 melee and 9 of 14 throwables carry a lower number
  than a cheaper item (frying pan 250 B is 0.75 against the free bat; chainsaw 250,000 B is 2.9
  against the 35,000 B energy sabre). Authored mass changes the real impulse, so this needs a CSV
  measurement, not a retune from source. The pistol may be a 9x step over the bat at 600 B.

### The simulator

The real run today passes 4 of 4, but read the lines, not the verdict:

| | M3.6 (80 items) | Today (100 items) | Target |
|---|---|---|---|
| First automation (play time) | 9:52 | 10:23 | ≤ 30:00 |
| First Reincarnation | 7:03 | **9:45:43** | 6–10 h |
| Worst purchase gap | 2:20 | 1:34 | ≤ 5:00 |

Twenty kind items moved the first reset two and three-quarter hours toward the ceiling. The
mechanism: the modelled player spreads kindness attention across every owned kind item, so with
29 of them none reaches the rank-25 capstone gate for hours. Idle income is a flat 60 Bones/s +
15 Hearts/s from hour 5 to hour 36, then cliffs to 9,000 H/s at hour 42 and 216,000 B/s at hour
54, after which everything is owned and nothing happens for 22 hours. The first three resets
each pay exactly +1.00 Marrow, the floor. At 72 h idle Bones outrun idle Hearts 24 to 1.

The sim also models no kind mechanics at all: every owned kind item is "a pet at 3 per second".
It cannot see the duck, the dead sponge, the dominated furniture or grime, and it models about
five times less Hearts than a player holding the pet button actually earns — while the human
earned twenty times *less* than the model because they did not pet. The instrument is right
about reachability and blind to the kind side.

### Contracts and gates

Nine of fifty contracts name a harm item and are drawn without an ownership check
(`progression.gd:456-470`); none names a kind item; the "catch 50 baseballs" contract in
`game-design.md` does not exist. Split 26 harm / 16 kind / 8 neutral. Critters gate behind desk
fan → trampoline → bowling ball, all Bones-priced but listed on the kind door because `Toy` maps
to `SIDE_KIND` (`item_data.gd:44-55`). The hot tub gates through chocolate fountain and boombox,
two items that are per-slot dominated.

### What to do, in order

1. **Data-only, this week:** give the sponge a touching trickle (or start him at grime 0.25);
   decide the duck (min contact speed ~250 or cooldown 2.0); swap pizza/donut prices; raise the
   top three comfort rates so per-slot rises with price (pool 14, blanket 22, recliner 45) and
   re-derive their capstones; multiply ambience by about 2.5. Move the four Bones toys to the
   harm door or price them in Hearts.
2. **Six hands-on kind items, each a `LEISURE` row plus a sprite (~$0.05 each):** feather duster
   90 H (held, 2 H/s touching), tennis ball 300 H (thrown catch, min speed 300), soft brush 500 H
   (open-hand clone at 1.6x, its own cursor), party popper 800 H (aimed burst, consumed), warm
   towel 1,500 H (held, cleans grime, 3 H/s), kite 4,500 H (mid-ladder catch). Hands-on kind
   items go from 4 to 10 with one at every rung below 5,000.
3. **Make the sim see the kind side:** model per-item kind mechanics from the scene switches
   (contact, touching, placed, feed), assert an active:idle ratio, cap kindness attention to the
   best N items rather than all owned, and make it fast again.
4. **Then** log two real sessions with the source column fixed and retune the harm ladder from
   measured impulse, not multipliers.

---

## 3. Visual quality

**Verdict: the still frame matches the spec; the moving picture does not.** CLAUDE.md's "no art
and no Theme" paragraph is stale — the Bonecard shell is finished to the letter of
`art-direction.md § UI`, the payout numbers are better than the spec asked for, and 98 of 100
sprites are on the 24-colour palette with closed outlines and a consistent side-on read. The
gaps are motion and feedback.

### Ranked

1. **No walk cycle.** He slides to every toy on a 1.5 px bob (`buddy_art.gd:76-82`). The most
   seen animation in the idle pillar does not exist. The family plan (walk, sit_in, lie_on,
   nibble, fiddle, gaze) is in `uplift-m3.7.md`; also missing against the spec: dizzy body,
   dance (the boombox's "most screenshot animation"), sleep, catch, per-weapon hit reactions.
2. **Two cards fade with alpha through the transparent window**, against the rule: `hud.gd:301`
   fades the toast, `ui_motion.gd:309` fades the whole card in `roll_up`. Caught on camera in
   `ui_shots/01-hud.png` and `11-upgrades-automation.png`.
3. **The fist icon is the prototype's anti-aliased render** (`icons/fist.png`, 267 off-palette
   colours, no item sprite). It is the first cursor power every player sees.
4. **Hit flash is a solid red silhouette** (`effects_player.gd:29-38`, `self_modulate = RED`).
   The face vanishes and it reads as an error state; the convention is a one-frame white flash.
5. **Cursor powers and turrets draw nothing when they fire.** `gun_power.gd`, `beam_power.gd`,
   `lightning_power.gd` apply blasts with no muzzle, bolt, beam or projectile; turrets are a
   still with a code lean. A lightning strike with no lightning is the most felt absence.
6. **Hero well halves the thirteen 128 px items** (see §1). Hot tub smaller than a katana.
7. **Gorilla walk sheet is off-palette, un-outlined and artefacted** (`npc/gorilla_walk.png`,
   frame 6), invisible on a dark wallpaper; and no NPC has an attack animation, so the
   gorilla's haymaker — the reason it is a subclass — plays nothing.
8. **Headphones hang motionless in mid-air through the whole knockout beat** (`collapse` frames
   4+, `pile`, `reassemble`; `audit/16_knockout_pile_s1.png`). About three seconds, every
   knockout, and it reads as a bug rather than a gag.
9. **The scale table covers half the roster and constrains height only.** 47 items have no
   entry; the two tables disagree on baseball, grenade, dynamite and sponge; the frying pan is
   30 px tall and 64 px wide, wider at 2x than the buddy is tall (`audit/07_play_s1.png`).
10. **Generator litter in shipped buddy frames:** `idle_sad` frames 2 and 6 have a stray mark
    above the head; `happy` frame 8 a smear on the face; `hurt` is barely distinguishable from
    idle except frame 4 — the spec asked for bigger squash and stretch.

Also: grime is a whole-sprite tint that browns the headphones (`grime_component.gd:19,63`);
ten near-black items (mine, bowling ball, frying pan, gravity vortex, sticky bomb, swarm
launcher, tyre iron, monitor, laser lattice, tripod) collapse to silhouettes on a dark desktop
and want the dual-tone treatment the spec describes; five sprites read wrong at 32 px
(demolition charge, black hole charge, implosion charge, laser lattice, mine); eight shop rows
truncate their names (`shop_panel.gd:122` `LIST_WIDTH`); the auto-hide pins are unbordered pink
teardrops; `ui_shots` still names a Rebirth page that is now Jobs.

VFX missing, by how often it would be seen: squash/stretch and landing dust on the buddy;
white hit flash; impact stars; muzzle/beam/bolt art; trails on thrown items; sparkle after
cleaning; grime as an overlay; scorch after explosions.

---

## 4. Addictive effects, genre feel

**Verdict: the engine is above the genre median; the experience is not yet sticky, and every
reason is in the last mile.** One payout pipeline, correct bulk-buy, a Melvor pool, AdCap
capstones, run-scaled prestige with the gain shown in advance, seeded dailies and a pacing
simulator — this is the simulation layer done right. What turns a loop into a habit is missing.

### What the genre expects and this build lacks

- **No goal on screen.** The HUD shows purse, meter and mood, never "next up". Affordable badges
  exist only inside the open shop (`shop_panel.gd:455-465`); the tab strip has none; both shell
  halves auto-hide by default (`settings.gd:40-41`). From the desktop, nothing ever says
  something became affordable. Cookie Clicker's store column and AdCap's progress-to-afford bars
  are the whole genre's answer to this.
- **No rate anywhere.** No Bones/s or Hearts/s on the HUD; the only rate in the game is one
  per-node line in the tree (`augment_panel.gd:811`).
- **No onboarding.** A fresh save boots to a skeleton and two 22 px arrows. `Settings.first_run`
  exists and is used by nothing (`settings.gd:64`); the only hint in the game is the removal
  gesture toast. A stranger must discover hover the arrow, Toys, Spawn, drag the bat. This is the
  single biggest risk to the outstanding M2 five-minute test.
- **Progression is silent.** Augment purchase has no sound (`ui_motion.gd:245-247`); milestone,
  contract completion, offline welcome, spawn, pickup, trampoline, hot tub, turret fire, NPC
  roar, device online — all silent. Seven synthesised voices have no caller: `explode_big`,
  `turret_fire`, `npc_roar`, `npc_stomp`, `bounce`, `splash`, `card_deal`. No music on a bus
  that has a volume slider.
- **Nothing changes on the desk when you buy.** The button flips to Spawn
  (`shop_panel.gd:521-531`); the toy appears on a second click, under the panel.
- **The combo is invisible.** The kindness combo (`economy.gd:245-256`, up to x3) is never
  drawn; there is no damage streak at all. The human session's payout rows show `mood_mult`
  swinging 0.6 to 2.0 and the player is never told.
- **He barely reacts to you.** Ten faces, and the triggers are hurt and happy for 0.45 s plus
  five mood faces (`buddy.gd:250-268`, `buddy_art.gd:428-441`). Nothing on purchase, a toy
  landing beside him, a near-miss, the sponge, being held, a milestone, or the player coming
  back. Interactive Buddy's whole charm was that he responded.
- **Meta has nowhere to go.** 62 milestones and no board; `Milestones.earned()` uncalled;
  `Economy.stats` never displayed; cosmetics have a slot and a currency and no store. The human
  ended the session with 15,050 Dollars and nothing to spend them on except spins.
- **Prestige is hidden** at the bottom of the Arcade tab (`arcade_panel.gd:19-22`). A player who
  never opens the Arcade never learns the game has one.
- **Offline is undersold.** One silent six-second toast (`main.gd:69-80`); the Dream Journal is
  unbuilt; the offline-cap upgrade the docs promise is read (`economy.gd:339`) and saved but sold
  nowhere. An open unattended game earns 0.6x (mood decays to neutral) against 0.5x closed — a
  20 % incentive where the docs imply 2x.
- No crits, random events, drops or jackpots outside the arcade; personality is shown only on
  the prestige page.

### Ten changes by impact per effort

1. "Next up" line in the HUD with a fill and a pulse on affordable, plus a tab badge.
2. Bones/s · Hearts/s on the HUD.
3. Onboarding minute 0–3: pin both drawers, spawn the bat beside him, three toasts through
   `Settings.hints_seen`.
4. A sound for every progression moment, and wire the seven orphaned voices at their emitters.
5. Draw the kindness combo; add a damage streak with pitch stepping up per hit.
6. Expression triggers on the signals that already exist: purchase, spawn nearby, rank up,
   milestone, prestige, held > 2 s, hover, the brain arriving at a toy.
7. Offline welcome as a beat, and sell the cap upgrade.
8. A milestone and stats page (a `PanelPage`).
9. Spawn on purchase (one line at `shop_panel.gd:440-446`).
10. Personality name on the mood row; a "Reincarnate for +N" line once pending Marrow ≥ 1.

### Decide deliberately

The design's instincts are good (one-time purchase, no timers, no FOMO) and the docs say so.
Three things still want an explicit call: the arcade is simulated gambling at 0.905 RTP with
near-miss ticks and it pays a five-minute x2 income boost — decide whether it ever pays buffs
and whether it is in the demo; the offline cap is a deliberate loss-aversion "sting" and should
be stated once in the welcome card; the mood U rewards not leaving him alone, which conflicts
with pillar 3 if a Working Hours layer ever lands — consider an idle mood floor so an open
desktop is never punished below the closed rate.

---

## Where the milestones actually are

The roadmap table is stale in two rows: M3.5 is listed as "0 and A built" while its body marks
B done and M3.6 and M3.7 sit below it; the CLAUDE.md "Current state" section predates the shell,
the roster and the sandbox. The 2026-08-31 session was the first real run of the M3 30-minute
test and its findings never reached the docs.

Suggested sequence, which is also the priority order above:

| Step | What | Touches |
|---|---|---|
| A | The one bug, the two fades, the harness leak, the drawers' `_process`, NPC sleep, coalesced refresh, string keys, the source column, the sim's speed | code only, an afternoon or two |
| B | Data-only kind fixes, six hands-on kind items, sim sees the kind side, a logged session | `.tres`, six sprites, `pacing_sim.gd` |
| C | Walk cycle plus the five families; fist, gorilla sheet, buddy frame litter, headphones; white flash; muzzle, beam, bolt | art |
| D | HUD next-up and rate, onboarding, sounds, streak, reactions, spawn-on-buy | shell and audio |
| E | The M2 five-minute stranger test, *after* D1, D3 and D9 | a person |
