# Bonehead Friend — M3.5: The Content & Systems Uplift

**What this is.** A plan for taking the game from a well-built demo to a game worth $7.99,
written to be handed to implementation sessions. Every claim below about the current build
was verified against the code and `.tres` files on 2026-08-30; file paths are given so the
implementing session does not have to re-survey.


---

## The one-page summary — what to build, in order

**The blunt findings first:**

1. **First prestige is unreachable by ~5 orders of magnitude.** `prestige_divisor` is 10¹²
   (BalanceData default; `balance.tres` overrides only the mood curve). A fully-built
   player earns ~400–800 Bones/s; 10¹² lifetime is ~40 years, not the 6–10 hours the spec
   targets. Deeper: the formula assumes Cookie-Clicker-style *exponential* income growth
   between resets, and this economy's growth is bounded (~10³ total multiplier). No divisor
   value fixes that — the game needs an exponential engine, and the genre answer is
   upgradeable automation.
2. **The entire shop is bought out in under two hours.** Total catalog spend is 9,810
   currency units; the most expensive item is 2,500 Bones. The committed catalog's top end
   (lightning 40k, massage chair 30k) was never seeded. Hours 2–8 are empty.
3. **Ectoplasm cannot be spent on anything.** It is excluded from `Economy._balances` and
   never passes `spend()`. Contracts — the daily-return hook — pay a currency that does
   nothing. Day 3 has no reason to exist.
4. **9 of 16 items have zero augments**, 2 of the 3 kindness-side augments are dead code,
   and the offline-cap upgrade the docs promise was never built (`offline_cap_level` is
   saved, read, and never incremented).

**The build order (full argument in Part 5):**

| Milestone | One line | Schema |
|---|---|---|
| **M3.5-0 — Prove the base** | The two playtests, the export check, retune pass 1, and the small confirmed defects. Blocking: rebalancing after a content expansion is strictly worse than before one. | none |
| **M3.5-A — The engine and the ladder** | Automation levels + a capstone per item (the exponential engine), augment coverage for all items, roster 16→~28, visible automation devices, a headless pacing simulator, divisor retuned to reality | none |
| **M3.5-B — The long game** | Ectoplasm meta-shop (deepen prestige axis one — NOT a second axis), milestones + stats page, Dream Journal, contract expansion to ~30, +2 personalities, prestige-gated automation tier 2, the hat layer | **v4, one bump** |
| **M3.5-C — Live on the desktop** | Taskbar mechanics, Overtime Pay, hibernate/hazard-pay, and the timeboxed Win32 spike → Working Hours if it lands. Occupational Hazard stays post-1.0. | none |

**Budget:** the full uplift's art is ~**$4.60** against the $8.43 balance — it fits with
~1.8× retry margin. What the balance does *not* buy is M4's capsule/key art and trailer.

**Scope push-backs (argued in place):** no second prestige currency, no fourth spendable
currency, no 150-item roster, no personality stat riders, no compound contract predicates,
and Occupational Hazard is not pulled into 1.0 — but its spike is, because it was already
scheduled ("during M3", D3) and has slipped.

---

## Part 1 — How deep the loop has to be

### The four horizons, before and after

| Horizon | Target experience | Current build | After uplift |
|---|---|---|---|
| **Hour 1** | Buy every 3–5 min; knockout beat lands; both currencies understood; first automation ~30 min | Probably holds — this is what the two playtests measure | Same, retuned from CSVs |
| **Hour 8** | First prestige lands mid-session; idle is ~60% of income; 2–3 trees deep; shop ladder still has visible rungs | **Breaks.** Shop empty by hour 2, idle income flat at 2.5 Bones/s forever, prestige mathematically unreachable | Ladder to 40k, automation levels compounding, first Reincarnation at 6–10h against a sane divisor |
| **Day 3** | 3–6 prestiges behind them; personalities have changed how they play; dailies worth claiming; something permanent to spend Ectoplasm on; a reason the morning open is a small event | **Breaks.** Ectoplasm is a number that only whispers +1%/point; the board pays into a void; Dream Journal unbuilt | Ecto meta-shop rows, Dream Journal beat, `use:`/`damage:` contracts that rotate real variety |
| **Week 2** | A second chase visibly waiting: prestige-gated automation tier, milestone completion, hats to earn, pool checkpoints at 100/200 | **Absent.** Nothing exists past the first prestige | Tier-2 automation via `requires_prestige` (implemented, unused — `progression.gd:134`), milestone board, cosmetic drip |

### Finding 1: the economy has no exponential engine (the load-bearing fix)

Verified numbers: a hit caps at 200 damage (`knockout_damage 400 × max_hit_fraction 0.5`)
= 100 Bones; a knockout round pays ~640 Bones and takes 30–60s of active play, so ~10–20
Bones/s baseline. Every multiplier in the game — augments ×4.05 damage × ×3.11 payout,
mood ×2, mastery ×1.65, pool ×1.10 — compounds to roughly ×40. Call peak income 800/s.
Lifetime after 8 hours: ~2×10⁷. `∛(2×10⁷/10¹²)` = 0. And because income growth per run is
bounded, each later prestige (8× lifetime per doubling) costs ~8× the *wall-clock* — the
spec's "early resets 5–15 min, later 30–60" cannot emerge at any divisor.

**Fix — make automation the engine (mostly data):**

- **Automation capstones become leveled.** `Progression._compute_automation_rate` already
  computes `automation_rate × level` (`progression.gd`, cached) — raising `max_levels`
  from 1 to 25–50 with `cost_growth ≈ 1.10` is a `.tres` edit. Linear rate × exponential
  cost is AdVenture Capitalist's business shape.
- **A capstone on every item**, not 2 of 16. Each pays its owning item's currency
  (weapon→Bones, friendly→Hearts — `Progression._automation_currency`, already resolved
  from the item). Idle income now grows with the roster, as `game-design.md` always said
  it should.
- **Price automation levels in Hearts.** Capstones already cost Hearts (D2's spine); levels
  costing Hearts makes kindness demand scale exponentially alongside Bones income, so the
  dual-currency premise *deepens* rather than dilutes as numbers grow.
- **A global upgrade tree — pure data today.** `item_id = &"global"` augment nodes apply to
  every payout (`progression.gd:209-212`, hook live, zero content exists). Three or four
  global `payout_mult` nodes (growth 1.12, priced steep) are the cross-run multiplier
  ladder that gives lifetime earnings real curvature.
- **Then retune the divisor** to land first prestige at 6–10h — expect ~10⁷–10⁸, set from
  the pacing simulator (Part 5), confirmed by CSV. Note: the +1%/Ectoplasm and the mastery
  exponent 1.6 are hard-coded in `EconomyMath`/`MasteryMath`, not `balance.tres` — move
  them into `BalanceData` while touching this.

One deliberate wrinkle to resolve while in there: **automation income pays as source
`&"automation"`, so per-item payout augments don't reach it** — only global nodes, pool,
mood and prestige do. That is probably the right balance lever (active play with a
levelled item beats its own automation, preserving the 60/40 split) — keep it, but write
it down in `economy.md` as a rule rather than an accident. Similarly, **offline income
bypasses `payout_for()` entirely** (`economy.gd:208` calls `grant()` directly), so mood,
augments, mastery and prestige all silently don't apply offline while online automation
gets all four. Decide it: recommendation is offline pays `rate × elapsed × efficiency ×
prestige × pool` — the stable multipliers, not the volatile ones — and `economy.md`
documents it.

### Finding 2: the run needs a middle (hours 2–8)

- **Roster 16 → ~28.** Seed the 12 committed-but-missing catalog items: katana 3.5k, mine
  2.5k, firework 6k, magnifying glass 4k, minigun 9k, gravity vortex 15k, lightning 40k
  (the Bones ladder's top), chocolate fountain 5k, hot tub 12k, massage chair 30k (the
  Hearts generators the friendly economy is missing), trampoline 1.8k, desk fan 3k. The
  unused `FriendlyBase` fields are free levers here: `hearts_per_second_touching` is the
  hot tub, `lifetime_seconds` is a consumable generator. All are `.tres` + scene; the
  five cursor powers need `CursorPowerBase` subclasses (magnifying glass = sustained DoT,
  vortex, lightning) — the one place roster growth costs code.
- **Augment coverage: every item gets the 3-node tier-1 pattern** (27 `.tres` at the
  established shape), plus 2–3 more exclusive branches on marquee items (shotgun's
  Buckshot/Slug/Beanbag is designed in `game-design.md` already). The tier system is
  emergent from data — tiers 4/5/N, prerequisite chains and prestige gates are all pure
  `.tres` (`augment_panel.gd:263-282` discovers tiers; one constraint: a tier must be
  homogeneous, don't mix an exclusive group and normal nodes in one tier).
- **Fix the dead kindness augments**: `open_hand_damage` and `open_hand_third` do nothing
  (`OpenHandPower` never reads `effective_damage()` or `cooldown_mult` —
  `open_hand_power.gd:63-65`). Two of the three augments a kindness-first player can buy
  are placebos; wire them or replace them.

### Finding 3: the long game needs a spine, not a second axis

**Ectoplasm gets a sink: the Séance shop** — permanent meta-upgrades priced in Ectoplasm
that survive Reincarnation. Rows in the spirit of: start-with-item-N unlocked, offline cap
rungs (the unbuilt 2h→8h→24h promise finally lands here), offline efficiency 0.5→0.75,
+base automation rate, a knockout-fountain multiplier, personality re-roll token. Build it
as **Ectoplasm-priced AugmentNodes** (extend the currency enum, teach
`Economy.spend()` the special case — Ectoplasm already lives outside `_balances` — and
carve meta nodes out of `Progression.reset_for_prestige()`'s wipe). Reusing AugmentNode
means the tree UI, gating, bulk-buy math and save shape all come free; the wipe carve-out
plus the Rebirth-page rows are the real work.

**Push-back: no second prestige axis in this uplift.** The research digest's own scope
note (one prestige layer at 1.0; the second *designed*, shipped month-3) is right, and the
survey confirms a second axis is the one genuinely-new-architecture item on the list (new
currency + save reshape + gating + panel). Nobody has prestiged even once yet; tuning a
second axis now is tuning in the dark. The Séance shop delivers the "permanent
meta-progression" feeling on the axis that exists.

**Milestones (in-game), the third axis.** Cookie Clicker's achievements→milk loop, built
honestly: an `AchievementData`/`MilestoneData` resource scanned by `ItemDB` (the
`OPTIONAL_DIRS` pattern at `item_db.gd:110` exists for this), a listener node on the bus
(`TuningLog` proves the shape costs nothing), each completed milestone compounding a small
global income bonus (×1.01 each, D11-style multiplier, never currency) and some paying
hats. ~40 at launch, mirrored to Steam at M5. The reserved-but-dead save surface gets
used: `stats` (written, read by nothing) grows counters and gets a page; `playtime_sec`
(never incremented) starts counting; `cosmetics {owned, equipped}` (reserved, untouched)
holds hats.

**Dream Journal** — designed in `game-design.md`, unbuilt. On return with offline
earnings: one absurd one-liner + a small timed buff. The buff needs a tiny
temporary-multiplier holder in `Economy` (one new factor in `payout_for` — the survey's
"shape 2" change, touches `EconomyMath.payout_for`'s signature and its unit tests once;
Dream buff, Overtime and any future timed effect share that one slot as a single
`temp_mult` product).

**Contracts get teeth.** Today: 6 templates on 5 keys. The highest-leverage 5-line change
in the codebase: emit `damage:<item_id>` from `Economy._on_damage_dealt` (`HitInfo`
already carries `source_id`) — the whole "deal N damage with X" class becomes data. Add
emit sites for `use:` beyond guns/missile (WeaponBase/ThrowableBase currently emit
nothing, so `use:baseball_bat` would never progress), a `catch` key on the baseball, and a
`minutes_at_extreme` counter ticked by `MoodComponent` (time-based goals as counting keys —
no predicate system needed; **push-back:** compound predicates like "keep mood above 80
while grime is 0" are real architecture for decoration-grade variety — don't). Then ~30
templates. Rewards stay Ectoplasm-only (D18) — which finally works, because Ectoplasm now
buys things.

**Automation tier 2, prestige-gated.** `requires_prestige` is implemented and unused. A
second capstone per marquee item (steeper rate, `requires_prestige: 1–3`) is pure data and
is the week-2 chase. This is exactly the seam D17 left on purpose.

**+2 personalities** (7 total), curves only — D19 holds, no stat riders. More than that
dilutes curve identity before anyone has met the first five.

**The hat layer.** `buddy_face_offsets.json` already tracks the head per frame — a hat
rides the same anchor data, so cosmetics are "new code on existing hooks", not a system.
Six hats in the uplift (contract/milestone rewards need something to pay); the full 10–15
set is M5.

---

## Part 2 — The content budget

Measured prices (art-pipeline.md, 2026-08-29): RD Fast still ~$0.017 batched, RD Pro still
$0.18, preset animation $0.14, custom $0.25, all post-processing free, icons derived free
from sprites. Measured actuals: 13 sprites + 13 icons + explosion = **$0.86**; the buddy's
9 tags + 10 faces = **$0.98**.

| Content | Current (verified) | Target | Est. cost |
|---|---|---|---|
| Items | 16 (15 icons — shotgun none; baseball scene still Polygon2D) | ~28 | 12 sprites+icons ≈ **$0.90** |
| Augment nodes | 23 (18 tier-1 on 6 items; 2 dead; 2 capstones) | ~120 incl. leveled capstones ×28, global tree, tier-2 | **$0** (UI generated) |
| Automation devices | 0 visible | 3 *mounts* (tripod / pedestal / gizmo arm) composited with item sprites — not 28 bespoke devices | **$0.25** |
| Buddy tags | 9 built; dizzy, dance, relax, eat, catch, sleep unbuilt | all 15 | 6 × $0.14–0.25 ≈ **$1.10** |
| VFX | explosion only; grime is a tint | impact stars, bone chips, heart burst, coin fountain, grime sprite layer | ≈ **$1.00** |
| Crosshairs/cursors | prototype ×3 | real, incl. new cursor powers | ≈ **$0.30** |
| Contracts | 6 templates, 5 keys | ~30 templates, ~9 keys | **$0** |
| Personalities | 5 | 7 | **$0** |
| Hats | 0 | 6 now (M5: 10–15) | ≈ **$0.30** |
| Milestones | 0 | ~40 | **$0** (hand-plotted glyphs) |
| Séance shop / stats page / Journal UI | — | — | **$0** (theme + glyphs exist) |

**Total ≈ $4.60 against $8.43 — fits, with ~1.8× margin for retries and hand-finishing
discoveries.** Two honest caveats: (1) the mount-composite trick for automation devices is
the difference between $0.25 and ~$2 — if composites look wrong, bespoke devices for the
six marquee items only; (2) **the balance does not cover M4's capsule, key art or trailer
assets** — large canvases, many iterations, and a quality bar where capsule art
demonstrably drives wishlists more than demo quality does. Budget real money or a human
pass there; do not bleed the API balance into it.

---

## Part 3 — Genre-staple audit: load-bearing vs decoration

| Staple | Status | Verdict |
|---|---|---|
| Exponential idle engine | **Missing** | **Load-bearing — Part 1, Finding 1** |
| Prestige currency sink | **Missing** | **Load-bearing — the Séance shop** |
| Milestone/achievement pressure | **Missing** (stats saved, read by nothing) | **Load-bearing — the third axis** |
| Daily return hook | Board built and rotating; pays into a void; Journal unbuilt | **Load-bearing** — fixed by sink + Journal, not by new board mechanics |
| Offline earnings, capped, upgradeable | Built except the upgrade (never purchasable) | Fix the rung; cap itself is load-bearing and stays (uncapped removes the return reason) |
| Buy ×10 / Buy Max | Built, closed-form, unit-tested | ✓ |
| Escalating reward feedback | Built (D30, log10 ramp — scales forever by design) | ✓ |
| Unlock gating / progressive disclosure | `ItemData.requires` exists, **empty on all 16 items** | Cheap and worth doing in the data pass — a 28-item shop on hour one is noise; gate the top of each ladder behind the rung below |
| Stats page | Save block exists, no UI | Cheap; feeds milestones; do |
| Synergies / set bonuses | Emergent physics only | Decoration — skip. The physics sandbox *is* the synergy system |
| Timed events / seasons | — | Decoration — skip at 1.0 |
| Multiple save slots | `SaveManager.slot_name` already a variable | Not player-facing at 1.0; skip |

---

## Part 4 — The desktop premise (the only real differentiator)

Verified: nothing in the codebase senses anything beyond its own window and screen
geometry (`OS.` usage outside tools/: exactly one call, `OS.is_debug_build()`). The
premise is currently "the taskbar is the floor," and even that is unexploited. Ranked by
cost against what each buys:

1. **Taskbar mechanics — pure Godot, now.** The floor already *is* the taskbar in overlay
   mode. A `taskbar_impact` contract key (emit on floor contact while
   `Settings.window_mode == overlay`) plus a "Taskbar Piledriver" global augment. Hours of
   work, and it makes the premise legible inside the loop for the first time.
2. **Overtime Pay — pure Godot, now.** `Time.get_datetime_dict_from_system()` + one factor
   in the shared `temp_mult` slot: after-hours automation pays 1.25×. Real-clock texture
   for a game that lives on a work desktop; trivially ignorable (constraint respected —
   it's passive income flavour, never a demand for attention).
3. **Hibernate / hazard pay — already M4 scope.** Focus-loss + input-silence heuristic →
   stop rendering, accrue at offline rate. A technical necessity (CPU budget) dressed as a
   mechanic. `Settings.hibernate_when_occluded` is already persisted and unimplemented.
4. **The Win32 GDExtension spike — timeboxed, this milestone.** D3 scheduled it "during
   M3 so the option stays open" and it slipped. One spike answers two features:
   `GetLastInputInfo` (system-wide idle time — a far smaller surface than window
   enumeration) unlocks **Working Hours**, and `EnumWindows` feasibility prices
   **Occupational Hazard** for post-1.0. If the spike lands cleanly, Working Hours — the
   "On The Clock" multiplier that ramps while you genuinely type in other apps — ships
   behind a setting as the uplift's flagship desktop feature; it is the strongest
   *retention* hook available to a game whose pitch is "keep it open while you work."
5. **Occupational Hazard — stays post-1.0. Push-back on pulling it forward.** D3's
   reasoning has not aged: the genre fails on technical polish, live window-rect→collider
   sync is the riskiest workstream in the project, and it is worth more as the flagship
   free update of a *launched* game (a marketing beat with an audience) than as a launch
   risk. What changed is only that the spike slipped; the correction is "do the spike,"
   not "move the feature." `WorldBounds` is the seam — it already rebuilds StaticBody2D
   walls at runtime, so feeding it more rects later is natural.

Not proposed: clipboard gags (privacy-sensitive, off-brand for a paid product's first
impression), notification interception (fragile mimicry), multi-monitor travel (window
architecture doesn't support it), wallpaper sampling (charming, decoration, post-1.0).
Click-through remains cut and is orthogonal to this uplift (overlay-tech.md documents the
viable all-or-nothing approach for whenever it is re-attempted).

---

## Part 5 — Sequencing

Milestone style follows `docs/roadmap.md`: sizes are estimates, **gates are commitments.**

### M3.5-0 — Prove the base *(~2–3 days of dev time + the human sessions; BLOCKING)*

The user's own framing is correct and this plan enforces it: the two playtests move
balance numbers, and rebalancing after a content expansion is far worse than before one.

- Run M2's five-minute non-developer playtest and M3's 30-minute no-dead-ends session;
  collect the TuningLog CSVs; retune pass 1 (`balance.tres` only).
- Verify the fixed `export_presets.cfg` in a real exported `.exe` — every build so far
  shipped without the buddy animation and explosion (they load from `res://art/src/`).
  Measure CPU on that export against the 3%/8% budget (the M4 "do first" item, pulled
  here because every later milestone builds on trusting the export).
- Fix the small confirmed defects that would pollute playtest reads: dead
  `open_hand_damage`/`open_hand_third`, shotgun icon + cursor art, `baseball.tscn`
  Polygon2D, the stale F9/F10 comment in `settings.gd:28`.

**Gate:** both playtests done and written up in `roadmap.md`; the exported build contains
its art and meets budget; retune 1 committed with its CSVs archived.
**Schema:** none.

### M3.5-A — The engine and the ladder *(~1.5–2 wk)*

- Automation levels (capstones → `max_levels` 25–50, `cost_growth` ~1.10, Hearts) and a
  capstone for every item (26 new `.tres`).
- Augment coverage: tier-1 trio for the 9 bare items; exclusive branches for shotgun (the
  designed Buckshot/Slug/Beanbag) and 1–2 more; the global tree (3–4 `&"global"` nodes).
- Roster 16→~28 per the committed catalog (Part 1, Finding 2); `ItemData.requires` gating
  up each ladder; new cursor-power subclasses where needed; scale-table + `PHYSICS`-table
  entries for every new body (D25 — a bat that swings like a plank is a known failure).
- Visible automation devices: optional `PackedScene` on `AugmentNode` + a small manager
  instancing/freeing on purchase and toggle (survey's shape: the device emits
  `damage_dealt`/`kindness_sustained` and thereby routes through the payout pipeline for
  free). Devices obey Focus Mode Off (stop moving, keep earning) and the FPS governor.
- Offline multiplier rule made deliberate (`prestige × pool`, documented in `economy.md`).
- **The pacing simulator**: `tests/` gains a headless sim over the pure math modules
  (EconomyMath/AugmentMath/MasteryMath are autoload-free by design — this is why) that
  plays a greedy-buyer strategy at speed and asserts the balance targets: first automation
  ≤ 30 min, no purchase gap > 5 min in hour 1–2, first prestige within 6–10 h, prestige N+1
  within 2× the pacing of N for the first five. Retune `prestige_divisor` (expect
  ~10⁷–10⁸) and move the hard-coded prestige/mastery constants into `BalanceData`.

**Gate:** pacing sim green on all targets; `loop_check` content suite green with the art
backlog empty of items (mounts allowed outstanding); a 30-minute human session against the
new ladder confirms the sim's hour-1 read; budget ledger in `art/prompts/` ≤ $1.50 spent.
**Schema:** none (`unlocks`/`augments` dictionaries absorb new ids by construction).

### M3.5-B — The long game *(~1.5–2 wk)*

- Séance shop: Ectoplasm-priced meta-AugmentNodes (currency enum + `spend()` special case
  + prestige-wipe carve-out + Rebirth-page rows), including the offline-cap rungs and
  offline-efficiency rung.
- Milestones: `MilestoneData` under `Data/Milestones/` (ItemDB `OPTIONAL_DIRS`), listener
  autoload/provider, ~40 milestones, compounding ×1.01 income each, several paying hats;
  stats block expansion + a stats page (`panel_layer.gd` takes a sixth tab by design —
  fold stats into the Jobs or Rebirth page if six tabs crowd the strip; decide on screen,
  not in this document).
- Dream Journal: one-liners table + timed buff via the shared `temp_mult` slot; the
  offline toast becomes the Journal card when earnings > 0.
- Contract expansion: `damage:<item_id>` emit, `use:` on WeaponBase/ThrowableBase,
  `catch`, `minutes_at_extreme`; ~30 templates; `KNOWN_KEYS` updated (the one const that
  gates contract variety, deliberately).
- +2 personalities (curves only); prestige-gated tier-2 automation capstones on marquee
  items; hat layer riding `buddy_face_offsets.json` + 6 hats.

**Gate:** save v3→v4 migration proven against a committed v3 fixture (and v1/v2 chain
still green); a simulated week-2 state (5 prestiges, sim-driven) shows a non-empty "next
thing" at every horizon: an affordable Séance row, an unclaimed milestone, an unbought
tier-2 capstone; contracts rotate with ≥3 distinct goal shapes on the board; all suites
green.
**Schema: v4 — ONE bump** covering milestones, journal state, stats expansion, and
`playtime_sec` finally counting. `cosmetics` needs no schema change (reserved since v1).
Bump + `_migrate_3_to_4` + fixture, per the CLAUDE.md rule — a schema change without a
migration is a data-loss bug.

### M3.5-C — Live on the desktop *(~1 wk + spike timebox)*

- Taskbar impact key + Piledriver augment; Overtime Pay; hibernate/hazard-pay (consumes
  the already-persisted `hibernate_when_occluded`).
- **Win32 GDExtension spike, timeboxed to 3 days**: `GetLastInputInfo` first (small
  surface), `EnumWindows` feasibility second. If idle-detection lands → Working Hours
  behind a Settings toggle. If the spike fails or overruns → cut cleanly; nothing else in
  the plan depends on it, and the finding prices Occupational Hazard honestly for the
  post-1.0 roadmap either way.

**Gate:** taskbar contract completable in a real overlay session; CPU budget re-measured
on an export with devices + effects live (the constraint that is a release gate, not a
preference); Working Hours demonstrably ramps only from *other-app* activity or is cut.
**Schema:** none (milestone keys ride v4's structures).

### Then M4 as re-scoped

M4 (demo, streamer mode, test matrix, store page) proceeds on top with its export check
already banked by M3.5-0. The M3.5 content set defines the demo cut naturally: through
first automation, prestige locked behind the demo boundary.

---

## Constraints honoured (the non-negotiables)

- **CPU 3%/8%**: devices and effects live under the FPS governor and Focus Mode; milestone
  listener is one bus node (TuningLog proves the cost); pacing sim is headless; every gate
  re-measures on an export.
- **Focus Mode Off still earns**: devices stop *moving*, never stop *earning* (same
  contract as capstone toggles); Overtime/Working Hours are passive multipliers.
- **Content is data**: every content row above is `.tres`; the code items are one-time
  system extensions (enum value, emit sites, device manager, milestone listener), after
  which their content is data too. The one known D8 violation — hard-coded shop category
  tabs in `shop_panel.gd:18` — stays untouched because no sixth category is added.
- **Two currencies with opposite sources**: nothing new spends or earns across the divide;
  Ectoplasm stays prestige-only; milestones pay multipliers and hats, never currency;
  automation stays Hearts-gated and deepens the spine (levels in Hearts).

## Verification (for the implementing sessions)

- Suites: `run_tests.gd` (sim + migration chain + new math), `loop_check` (content
  coverage, new signals), `ui_check` (new rows/pages clickable), `window_check` — all per
  the CLAUDE.md invocations; editor pass after any new `class_name`.
- The pacing simulator is the uplift's tuning instrument; human CSVs remain the ground
  truth it is calibrated against (M3.5-0 and the A-gate session).
- Budget ledger: every generation recorded in `art/prompts/` with cost; running total
  asserted ≤ $6.00 at C-gate (leaves margin for M4 store-asset experiments even though
  they shouldn't come from this balance).
- Save-schema discipline: exactly one bump (v4) in M3.5-B; fixtures for v1/v2/v3 all
  migrate green before and after.
