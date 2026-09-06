# The expressive buddy — a small mind, not a bigger animation set

Bonehead has nine body tags, ten faces, and **three triggers**. He reacts to a contact hit, to a
pet, and to his own mood band. Everything else the game does happens next to him: the sponge,
the purchase, the milestone, the toy landing on the desk, the player coming back after two
hours. `EventBus` already carries every one of those signals and nothing on the character is
connected to any of them.

This is not a new feature. D4 (`docs/decisions.md`) killed the ragdoll **in exchange for**
"bigger squash and stretch, a layered face, a wide expression set, scripted reaction states",
and `docs/architecture.md` names nine states of which `Sleep` and `Dance` were never built. The
debt is four months old. The interest is that the kind half of the game — twenty leisure items,
a whole currency — is invisible on his face, because `buddy.gd:72` connects `kindness_given` and
not `kindness_sustained`.

**The plan is a small mind, not a bigger animation set.** Give him four things he does not have
— what he is *looking at*, how *worked up* he is, whether the player has been *gone*, and a
single priority-arbitrated slot for the beat he is playing — and the ten faces and nine tags
already in the file produce about thirty distinguishable moments. Every tag added afterwards
multiplies through that rather than adding one row.

Phase 1 needs **no new art and no generation spend**.

---

## 1. The character

He is a soft, chunky, four-colour skeleton in teal headphones, 63 px tall inside a 96 px cell,
drawn at 2x on a transparent desktop. He is a **toy, not a target** (pillar 1). Gore was
rejected deliberately (`docs/ideas-backlog.md`), and the corollary for expression governs every
row in section 2: **no reaction may read as distress in earnest.** `crying` works at mood < −60
because he is a cartoon skeleton held at a distance; screaming, begging and pleading convert a
toy into a victim and cost the unrestricted rating for a joke that is not this game's joke.

Three things follow from the screen he lives on.

- **Posture carries; the face garnishes.** The face is four pixels at 2x and the player is
  working in another window — `buddy_art.gd:50-53` already states this as an engineering rule.
  Silhouette first, timing second, expression third. Faces are the cheap axis and therefore the
  tempting one.
- **He is expressive when looked at, quiet when not.** A character who acts in order to be
  looked at is Desktop Goose, which this design rejected by default when it made Focus Mode a
  pillar. D36 (section 3.5) is the rule that keeps it that way.
- **His body is currently lying about the central mechanic.** D15 records the failure: a player
  reads mood as a happiness meter, concludes the middle is fine, and earns 0.6x all session. At
  mood 0 he plays plain `idle` with `neutral` — he *looks* fine. The most valuable single row in
  this document is the mood-trough posture in 2H: at `|mood| < 15` he slows to `speed_scale 0.7`,
  slouches two degrees, and fidgets twice as often. That makes the U-curve legible from across
  the room without a number, and it is a posture, not a system.

What he should read as, one line each. **Hit** — surprised, never suffering. **Petted** —
uncomplicatedly delighted. **Held** — startled, then resigned, then annoyed. **Clean** —
sparkling, briefly smug. **Filthy** — sorry for himself. **Alone** — asleep. **Greeted** —
pleased you came back. **Bored** — visibly under-entertained, which is a wage negotiation.

---

## 2. The reaction table

This is the artefact that exists nowhere in the repo: signal → face → body tag → code motion →
sound → duration → priority → Focus gate, as data, in one file. It becomes a `const` dictionary
in `Scripts/Buddy/expression_brain.gd`, in the same shape as `BuddyArt.STATE_ANIMATION`
(`buddy_art.gd:25-33`), so a row is data and a missing tag is a row that keeps whatever is
playing.

**Priority ladder.** `AMBIENT 0` · `ATTENTION 10` · `REACTION 20` · `HEAVY 30` · `BEAT 40`.
Higher preempts. Equal preempts *except* under damping. `BEAT` is exclusive and reproduces
today's `_in_knockout` guard (`buddy.gd:256`) without leaking that flag into forty call sites.

**Duration** comes from `art.animation_length(tag)` when the tag exists and from the row's own
fallback when it does not — the pattern `_beat_time()` (`buddy.gd:328-333`) already uses for the
knockout and which `_react` never did. **Delete `REACTION_SECONDS := 0.45` (`buddy.gd:28`)
before generating any art**: `hurt` is 6 frames, `happy` is 8, and every new tag longer than
0.45 s would be cut off mid-play.

**Heat** is `clampf(info.amount / maxf(1.0, balance.hit_stop_full_damage), 0.0, 1.0)` — the
*same* linear quantity `world_fx.gd:69-70` computes for its chip count, so the chips, the
hit-stop and the flinch all agree about how hard that was. D30's `log10` grammar stays where D30
put it, on the payout *number*, where magnitude is unbounded; damage is clamped at
`max_hit_fraction`, so it is not.

**Amplitude** is `Settings.intensity_scale()` (`settings.gd:167` — 0.0 / 0.4 / 1.0 / 1.6) ×
personality `reaction_amplitude`. Every code-motion write multiplies by it, so Focus Off zeroes
motion arithmetically rather than through thirty scattered `if`s.

**Holds, not beats.** Rows marked *hold* set a face and a tag once, with a deadline the repeating
signal refreshes. `kindness_sustained` flushes twice a second (`friendly_base.gd:160`) and
`damage_dealt` arrives up to seven times a second (`buddy.gd:233-241`); a beat per event is a
strobe.

**Damping.** An identical beat arriving within **0.18 s** extends the deadline and does *not*
restart the animation; a heavier one escalates and does. Without this the player sees frames 1–3
of a six-frame `hurt` forever, which is the defect `hurt` already has.

Focus gate column: `R` reactive, allowed at Off as face and tag only with zero motion · `S`
Subtle and up · `N` Normal and up · `G` gaze, Normal and up only.

### A — being hit

| Moment | Source | Face | Body | Code motion | Sound | Duration | Pri | F |
|---|---|---|---|---|---|---|---|---|
| Light hit, heat < 0.25 | `buddy.gd:199-208`; `info.amount` **discarded today** | `shocked` | `flinch`¹ | squash 1.10 → overshoot; recoil away from `info.position` | material map (D35) | anim / 0.28 | 20 | R |
| Ordinary hit, 0.25–0.6 | same | per-category, below | `hurt` | squash 1.0 + 0.18·heat; recoil | material map | anim / 0.45 | 20 | R |
| Heavy hit, heat > 0.6 | same | `shocked` → `dizzy` tail | `hurt` → `dizzy`¹ | squash + lean away; head wobble ±5 px @ 3 Hz on the tail | material + `oof`² | anim + 0.8 | 30 | R |
| Fifth hit from one source in 3 s | `_cooldowns` keys | `angry` on the settle | — | — | — | 1.0 | 20 | R |
| Beam / cooking | `beam_power` ticks `take_impulse` at 4 Hz | `crying` | `hurt` held | shiver 12 Hz | — | *hold*, 0.4 s decay | 20 | R |
| Knockout beat | `health.knocked_out` | `dizzy` | `collapse`→`pile`→`reassemble` | frozen (existing) | `clatter` / `rattle` | anim | **40** | R |
| Meter reset after reassembly | `health.reset_meter()` (`buddy.gd:320`) | `neutral` | `happy` | two shake-offs | — | 0.5 | 20 | R |
| Meter above 80 % | `health.fill_fraction()` | — | `idle_sad` bias | slow tremble folded into idle | — | posture | 0 | S |

Per-category hurt face, keyed on `ItemDB.get_item(info.source_id).category` — **not on id**, so
ten entries cover the whole roster and every item added after it (D8): `CATEGORY_WEAPON` →
`shocked`; `CATEGORY_THROWABLE` → `shocked` + shiver; `CATEGORY_CURSOR_POWER` → `angry`;
`CATEGORY_TURRET` / `CATEGORY_CRITTER` → `angry`, one shiver, 0.3 s. `HitInfo.source_id` is
already in hand at `buddy.gd:207` and thrown away.

¹ new tag, section 4. Until it exists the row falls through to `hurt` — `_play_body`
(`buddy_art.gd:237-242`) already no-ops an unknown tag, which is what makes wiring-before-art
survivable. ² new synthesised voice, section 3.6.

### B — kindness

| Moment | Source | Face | Body | Code motion | Sound | Duration | Pri | F |
|---|---|---|---|---|---|---|---|---|
| Pet | `kindness_given` ✓ wired | `blissful` | `happy` | hop | `kindness` | anim / 0.45 | 20 | R |
| Pet combo ≥ 3 | `Economy._combo_count:49` — never leaves Economy | `blissful`, held | `happy` | hop × (1 + combo/6) | `kindness`, pitch stepped | anim | 20 | R |
| **Sponge / any sustained kindness** | `kindness_sustained` (`friendly_base.gd:160`) — **not connected in `buddy.gd` at all** | `happy` | `idle_happy` | slow side wiggle | — | *hold*, 0.6 s refresh | 20 | R |
| Grime reaches zero | `grime_component.gd:56-59` | `blissful` | `happy` | shake-off + `WorldFX.burst(pos, &"heart", …)` | `kindness`, pitched up | 0.8 | 30 | R |
| Eat | `hearts_per_contact` on a `CATEGORY_FOOD` item | `happy` | `eat`¹ | three nods | — | anim / 0.6 | 20 | R |
| Catch a thrown ball | `min_contact_speed` gate (`friendly_base.gd:110`) | `smug` | `catch`¹ | hop | `kindness` | anim / 0.7 | 20 | R |
| Soaking | `ROUTINE_SOAK` | `blissful` | `relax`¹ | `speed_scale 0.6`, deep slow bob | — | *hold* | 10 | S |
| Grime crosses a stage | `grime_changed` | `sad` | `idle_sad` bias | overlay stage swap | — | posture | 0 | R |

### C — the cursor and the player's hands

| Moment | Source | Face | Body | Code motion | Sound | Duration | Pri | F |
|---|---|---|---|---|---|---|---|---|
| Cursor over him | `DraggableArea.mouse_entered` (`draggable_area.gd:13`) — fires today, **emits nothing upward** | `neutral` | — | head lean ≤ 2 px toward the cursor | — | *hold* | 10 | **G** |
| Cursor leaves, or leaves the window | `mouse_exited`; `NOTIFICATION_WM_MOUSE_EXIT` (`hover_drawer.gd:99` pattern) | mood face | — | drop the gaze | — | — | 10 | G |
| Harm power equipped | `cursor_power_changed` | `shocked` | — | lean away | — | 0.5 | 10 | R |
| Open hand equipped | same | `happy` | `idle_happy` | — | — | 0.5 | 10 | R |
| Picked up | `_start_drag` (`buddy.gd:137`) | **`shocked`** — `STATE_FACE` has no `dragged` row (`buddy_art.gd:37-43`) | `dragged` | — | — | 0.3, then `neutral` | 20 | R |
| Held longer than 6 s | `dragging` | `angry` | `dragged` | kick, 3 s period | — | *hold* | 10 | N |
| Shaken while held | joint chase speed (`base_draggable.gd:147-149`) | `dizzy` | `dragged` | wobble | — | 0.6 | 20 | N |
| Landing after a drop | sign flip on downward velocity in `_integrate_forces`; the sub-threshold early-out discards these today | — | — | squash 1.2/0.8 → recover; dust burst | `impact_soft` | 0.25 | 20 | S |

### D — the world and threats

One new bus signal, `threat_changed(kind, world_pos, level)`, with three emitters. **Resist
adding six.**

| Moment | Source | Face | Body | Code motion | Sound | Duration | Pri | F |
|---|---|---|---|---|---|---|---|---|
| Fuse lit / mine armed nearby | `ThrowableBase.prime_explosion` starts a `modulate` tween and emits nothing; **new emit there** | `shocked` | `flinch`¹ | lean away; fidgets frozen | `gasp`² | *hold* while primed | 10 | R |
| Blast felt, no damage | new emit in `explode()` | `shocked` | `flinch`¹ | duck, then look toward `at` | — | 0.5 | 10 | R |
| Turret acquires, NPC winds up | `npc_base._set_state`, `TurretBase` firing | `shocked` | `flinch`¹ | face the threat | — | *hold* | 10 | N |
| Item lands beside him | `item_spawned` — `IdleBrain` uses it only to *stop* him | `neutral` | — | turn toward it | (`spawn` plays already) | 1.2 | 10 | N |
| Automation device appears | `automation_toggled` | — | — | look at the device | — | 0.4 | 0 | N |

### E — economy and progression

Every row here is one `connect`. `AudioManager:39-53` already plays a sound for all of them, and
he already does nothing.

| Moment | Signal | Face | Body | Code motion | Duration | Pri | F |
|---|---|---|---|---|---|---|---|
| Purchase | `item_purchased` | `happy` | `happy` | one hop, on the chime | 0.5 | 10 | R |
| Mastery rank up | `mastery_rank_up` | **`smug`** | `idle_happy` | chest puff (squash 0.92/1.08, held) | 0.9 | 10 | R |
| Milestone or contract claimed | `milestone_claimed`, `contract_claimed` | `blissful` | `happy` | two hops | 1.0 | 10 | R |
| Reincarnation | `prestige_performed` | the new personality's bias face | rides the existing `reassemble` | — | anim | 30 | R |
| Top-tier payout | `payout`, tiered as `FXLayer` already tiers it | `smug` | — | — | 0.4 | 10 | Chaos only |

### F — session and desktop

The genre's whole point, and entirely untouched today.

| Moment | Source | Face | Body | Code motion | Sound | Duration | Pri | F |
|---|---|---|---|---|---|---|---|---|
| App focus out | `NOTIFICATION_APPLICATION_FOCUS_OUT` — handled only in `audio_manager.gd:68` | `neutral` | — | arousal → 0; fidgets off | — | — | — | R |
| Unfocused longer than 90 s | derived | `asleep` | `sleep`¹ | `speed_scale 0.35`, slow deep bob | `yawn`² once | *hold* | 0 | S |
| **App focus in after > 60 s away** | `NOTIFICATION_APPLICATION_FOCUS_IN` (`audio_manager.gd:70`) | `shocked` → `happy` | wake (`sleep` reversed) | two hops, then look at the cursor | `greet`² | 1.2 | 20 | **R** |
| Player returns after a quiet spell | `IdleBrain._disturb()` (`:518`) already knows how long | `happy` | — | look at the cursor | — | 0.4 | 10 | N |
| Idle 25 s | `IDLE_SECONDS` (`idle_brain.gd:60`) | one yawn (`asleep`, 0.3 s) | — | — | `yawn`² | 0.3 | 0 | S |
| A panel opens over him | `ui_panel_changed` | — | — | look toward the card | — | 0.4 | 0 | N |

The reunion beat is the highest-value single trigger in this document: two `_notification` cases,
one already-drawn face and a code hop, in a game whose whole pitch is "keep it open all day" and
which currently does not acknowledge the player coming back at all.

### G — the idle brain, which nobody can see working

`IdleBrain` is a complete Shimeji layer — routines, dwell, wander, per-toy cooldown, stall
detection — and it is invisible because he plays `idle` the whole way there. Two new signals, no
logic change.

| Moment | Source | Face | Body | Duration | Pri | F |
|---|---|---|---|---|---|---|
| Walking | `art.travel()` from `idle_brain.gd:359` | mood face | `walk`¹ | continuous | — | already off at Off (`idle_brain.gd:276`) |
| Arrived at a toy | `_enter(PHASE_PLAYING)` (`:593`), new `phase_changed` | `happy` | routine tag, below | 0.4, then the routine | 10 | N |
| `ROUTINE_BOUNCE` (`:172`) | trampoline | `happy` | `happy` — free | *hold* | 10 | N |
| `ROUTINE_PLAY` (`:173`) | boombox and placed generators | `happy` | `dance`¹ | *hold* | 10 | N |
| `ROUTINE_SOAK` (`:174`) | hot tub, beanbag, recliner | `blissful` | `relax`¹ | *hold* | 10 | N |
| `ROUTINE_SCRUB` (`:175`) | sponge | `happy` | `fiddle`¹ | *hold* | 10 | N |
| `ROUTINE_NIBBLE` (`:176`) | food | `happy` | `eat`¹ | *hold* | 10 | N |
| Gave up climbing | `_stalled_seconds >= STALL_SECONDS` (`:87`) | `angry` | `fiddle`¹ | 0.8 | 10 | N |
| Toy despawns under him | `_on_item_despawned` | `shocked` | — | 0.5 | 10 | N |

The five `ROUTINE_*` constants map one-to-one onto the family plan in `uplift-m3.7.md`: **twenty
leisure items need six animations, not twenty**, and `_routine_for` (`:449`) already resolves
them from the item's switches rather than from its id.

### H — ambient and posture

All `AMBIENT`, all suppressed at Focus Off.

| Moment | Face | Body | Code motion | Period | Pri |
|---|---|---|---|---|---|
| Blink | `asleep` for 2 frames | — | — | 4–9 s, randomised | 0 |
| Fidget | mood face | — | shiver / weight shift (lean 3°) / look left-right | personality `fidget_period`, default 12 s | 0 |
| **Mood trough, mood within ±15** | `neutral` | `idle` | **`speed_scale 0.7`, slouch 2°, fidget period halved** | continuous | 0 |
| Mood band change | `MOOD_FACES` / `MOOD_IDLES` ✓ wired | ✓ | — | — | 0 |
| Airborne or spinning | — | — | stretch along velocity, tilt | per physics tick | 0 |

---

## 3. Architecture

### 3.1 The load-bearing rule: beats are not states

`Buddy.state` is a public contract. `_set_state` (`buddy.gd:335-339`) emits
`buddy_state_changed`, and off that: **Economy mints the knockout bonus**, `WorldFX` throws its
bone shower (`world_fx.gd:79-85`), `IdleBrain` stands down, and `BuddyArt` picks posture. Forty
new reactions must not become forty new states.

A fortieth state would also break mood **silently**: `_on_mood_changed`
(`buddy_art.gd:214-229`) overwrites the face by mood and then returns before `MOOD_IDLES` for any
state it does not recognise — so an unknown state loses its reaction face *and* freezes his
posture until something resets it.

Two channels, and only one of them is a state:

| Channel | Owner | What it is | On the bus |
|---|---|---|---|
| **State** | `buddy.gd`, unchanged | idle · dragged · hurt · happy · knockout · pile · reassemble | `buddy_state_changed` |
| **Beat** | new `ExpressionBrain` | a bounded presentation overlay: face + optional tag + code motion + sound + duration + priority | nothing |

`hurt` and `happy` stay states, because contracts and suites depend on them. Everything in
section 2 that is not already a state is a beat.

### 3.2 New file: `Scripts/Buddy/expression_brain.gd`

`class_name ExpressionBrain extends Node`. Sibling in spirit to `IdleBrain` — that one is what
he *does* when nobody is watching; this is what he *looks like he is feeling*. Built in
`Buddy._ensure_components()` (`buddy.gd:82-110`) as an `@export` slot, exactly as
`MoodComponent`, `GrimeComponent` and `BuddyArt` are, and for the stated reason: `buddy.tscn`
cannot be edited outside the editor, and the art pass promotes the slot with no code change.

State it owns, all derived — **no save schema change, no `SAVE_VERSION` bump, no migration, no
fixture**:

```
_beat       : {tag, face, priority, until_msec, hold, motion}   # one slot, arbitrated
_arousal    : float    # 0..1, decays; scales amplitude and shortens the fidget period
_attention  : {kind, point}   # cursor | toy | threat | none
_away_since : int      # msec at app focus out; the reunion beat reads it
_fidget_at  : int
```

Valence is **not** duplicated — it is `MoodComponent.value`, read off `mood_changed`.

`ExpressionBrain` is the **only** new place that connects to `EventBus`. That is deliberate:
CLAUDE.md's own scar is four `connect()` calls stranded after a `return` in `FXLayer._ready()` —
no parse error, no warning, and payout numbers silently gone. Keep the connects in a file whose
entire job is connects, and assert each one individually (section 6).

### 3.3 `BuddyArt` — the motion accumulator, and the trap under it

**A `Tween` on `body.position`, `face.position` or `body.scale` does not work.**
`_advance_travel` writes `body.position` unconditionally every frame (`buddy_art.gd:174`) and
`_process` writes `face.position` unconditionally every frame (`:142`). Anything tweened onto
either is overwritten on the next frame. Every code motion in section 2 must be an **accumulator
folded into those same two writes** — not a tween, not a second `_process`.

```
final_body_pos   = _body_home + Vector2(_recoil_x, _bob + _hop_y + _foot_fix)
final_body_scale = _base_scale * Vector2(_squash_x, _squash_y)
final_face_pos   = _face_home + offset * _base_scale
                 + Vector2(_look_x + _recoil_x, _bob + _hop_y + _nod_y + _foot_fix)
```

Three hazards inside that, each of which ships a visible bug if missed.

- **`_base_scale`, not `body.scale`.** `buddy_art.gd:137` multiplies the face offset by
  `body.scale`. The moment squash writes `body.scale`, a 0.85 squash drags his face 15 % down his
  skull — about 3 screen px at 2x, on every hit. Capture `_base_scale := body.scale` in
  `_ready()` and use it for the offsets. This is the one defect that would be visible in the
  first playtest.
- **Squash anchors at his feet.** `AnimatedSprite2D` is centre-pivoted, so squashing about the
  origin lifts him off the desk, which is the commonest way a squash reads as a glitch.
  `_foot_fix = (1.0 - _squash_y) * 31.5 * _base_scale.y` — half the 63 px figure inside the 96 px
  cell.
- **The mirror negates his home offset, not just the per-frame `dx`.** `buddy_art.gd:140-141`
  does `placed.x = -placed.x`, correct only while `_face_home.x == 0` — true today only because
  `buddy.gd:101` copies `sprite.position`. CLAUDE.md says the art pass opens `buddy.tscn` and
  authors `Face` properly; the first non-zero x sends his face off his head when he walks left.
  Fix it in phase 0, before head-turn work exists to trip it:

  ```gdscript
  var dx := float(entry[0]) * _base_scale.x
  if _facing < 0.0:
      dx = -dx
  placed.x = _face_home.x + dx + _look_x
  ```

Also fix `_state_of_body()` (`buddy_art.gd:231-233`), which does `get_parent() as Buddy`. The
same art pass wrapping the sprites in a `Rig: Node2D` makes it return `&"idle"` forever,
**silently**, so mood overwrites every reaction face. Make it `@export var buddy: Buddy` with a
group lookup as the fallback.

**New public surface on `BuddyArt`**, all shaped like `set_expression` — guarded, silently no-op
on an unknown name, so wiring can land before art:

```gdscript
func play_beat(tag: StringName, face: StringName, seconds: float, amplitude: float) -> void
func hold_face(face: StringName, until_msec: int) -> void
func clear_beat() -> void
func look(dx_px: float) -> void      ## head turn without the bob; travel() conflates the two
func set_squash(v: Vector2) -> void
func beat_active() -> bool
```

And connect `body.animation_finished`, which **nothing in the character connects today** — the
only `animation_finished` in `Scripts/` is `effects_player.gd:79` — so no beat can currently hold
until its animation ends.

### 3.4 How it stays cheap

The honest baseline: `Buddy._process` (`:112`) and `BuddyArt._process` (`:123`) both run
unconditionally every rendered frame for the life of the process, and neither ever calls
`set_process(false)`. `buddy_art.gd:127` allocates a `String` from a `StringName` and does a
`Dictionary`→`Array`→`Array` lookup **every frame, forever**. **This work should leave the
character cheaper than it found it.**

1. **`ExpressionBrain` has no `_process` and no `_physics_process`.** It is event-driven plus one
   re-armed `Timer` whose `wait_time` is recomputed on each tick: 0.1 s only while a beat with
   live code motion is running; 2–8 s while merely scheduling fidgets; `stop()` when arousal is
   zero, attention is none and nothing is pending. That is strictly cheaper than `IdleBrain`'s
   fixed 2 Hz think, which already passes the budget.
2. **Face placement moves to `body.frame_changed` and `body.animation_changed`.** The offsets
   table is indexed by *frame*, not by tick: `idle` at 10 fps needs 10 placements a second, not
   60. Both signals are needed — `frame_changed` does not fire when `play()` switches animation at
   frame 0.
3. **Cache the track.** `_offsets` becomes `Dictionary[StringName, PackedVector2Array]` plus a
   parallel visibility `PackedByteArray`, built once at load, with the current track cached on
   `animation_changed`. Zero allocation per frame, and the on-disk JSON shape does not change.
4. **`_process` runs only while something is moving** — `_travel > 0`, `_bob != 0`, a beat
   deadline pending, or any accumulator non-zero. `travel()`, `play_beat()`, `look()` and
   `set_squash()` re-enable it; it calls `set_process(false)` when all of them are quiet. This is
   asserted (section 6): the under-3 % claim is only true if a test says so.
5. **Move `Buddy._process`'s bounds check onto a 0.5 s timer.**
   `get_viewport().get_visible_rect().grow()` every frame for eight hours (`buddy.gd:112-122`) is
   a rescue failsafe, not a per-frame need.
6. **Every deadline is `Time.get_ticks_msec()`, never a frame count.** `Engine.max_fps` drops to
   20 at idle and in Low Power, so anything frame-counted plays three times too long. And no
   `SceneTreeTimer` per event — `buddy.gd:49-53` explains why, and it generalises.
7. **Velocity-derived motion rides the physics tick he already runs**, not `_process`.
8. **Gaze rides `InputEventMouseMotion` and `DraggableArea`'s existing signals — never
   `get_mouse_position()`.** A synthetic event cannot move the OS cursor, so anything built on it
   is untestable by construction. `ui_check` gets a source sweep for it.

Net at true idle: brain timer stopped, `BuddyArt` not processing, about ten `frame_changed`
callbacks a second. Fewer live callbacks than today.

### 3.5 Focus Mode — propose D36

`idle_brain.gd:276` and `npc_base.gd:64,70` each independently invented an answer for the
character and they agree; no document states it, so the third system will invent a third. The
next free number in `docs/decisions.md` is **D36** (D35 is "A hit sounds like what hit him").

> **D36 — At Focus Off he reacts; he does not initiate.** A beat caused by something the player
> just did still plays, because the player caused it and is looking at it — as a face and a tag
> change with **zero** procedural amplitude. Nothing initiates: no fidgets, no blinks, no gaze,
> no travel, no landing dust, no sleep, no attention-seeking. And nothing leaves his silhouette:
> body tag and face may change; `position`, `scale`, `rotation` and `skew` offsets may not.
> **Beats are not states** — the state machine is a public contract that Economy, WorldFX and the
> idle brain all read, and a reaction must never enter it.

Two helpers, and **reuse `Settings.intensity_scale()` verbatim** (`settings.gd:167`) rather than
inventing a third ladder; `ui_motion.gd` already invented a second one, and that is a warning
rather than a precedent.

```gdscript
func _amp() -> float:       # 0.0 / 0.4 / 1.0 / 1.6, times personality reaction_amplitude
func _initiates() -> bool:  # Settings.focus_intensity != Settings.Intensity.OFF
func _may_gaze() -> bool:   # >= Settings.Intensity.NORMAL
```

Gaze gets its own gate. Cursor tracking is the single most attention-grabbing thing a desktop
character can do and it is free CPU-wise, which is exactly why it is dangerous: Focus Mode is a
headline feature *because* this game refuses to be Desktop Goose by default. **He looks; he never
chases.** Chase stays where `ideas-backlog.md` #4 put it — an opt-in unlock.

Timings never scale with the setting, only amounts (D21). A reaction damped to nothing reads as a
hit that missed, which is why `world_fx.gd:97` halves the chip count at Subtle rather than
removing the burst. Do the same here.

### 3.6 Every file that changes

| File | Change |
|---|---|
| `Scripts/Buddy/expression_brain.gd` | **new** — the table, the beat slot, attention/arousal/memory, Focus gating, the fidget timer, the personality overlay |
| `Scripts/Buddy/buddy.gd` | delete `REACTION_SECONDS` (`:28`); `_react` / `_settle_reaction` become thin forwards; `_deal` passes the whole `HitInfo` (`:207` discards `amount`); `_on_kindness_given` passes `source_id` (`:250` names all three params `_`); build `ExpressionBrain` in `_ensure_components`; `_notification` for app focus in/out; landing detection off `_integrate_forces`; bounds check onto a timer |
| `Scripts/Buddy/buddy_art.gd` | accumulator; `_base_scale`; foot anchor; the `_facing` fix; `@export var buddy`; offsets cache; placement on `frame_changed` / `animation_changed`; the `set_process(false)` contract; six new methods; connect `animation_finished` |
| `Scripts/Bodies/draggable_area.gd` | `signal hover_changed(hovered: bool)` — four lines; `is_hovered` is already tracked (`:7-20`) and emitted to nobody |
| `Scripts/Buddy/idle_brain.gd` | `signal phase_changed(phase, routine, target_id)` in `_enter()` (`:593`); `func seconds_since_disturbance()` off `_disturb` (`:518`). No behaviour change |
| `Scripts/Bodies/throwable_base.gd` | emit `threat_changed` where the prime tween already starts, and again in `explode()` |
| `Scripts/World/npc_base.gd`, `turret_base.gd` | the same one signal, two more emitters |
| `Scripts/Autoload/event_bus.gd` | **one** new signal: `threat_changed(kind: StringName, world_pos: Vector2, level: float)` |
| `Scripts/Autoload/economy.gd` | `func kindness_combo() -> int: return _combo_count` (`:49`) — read-only, no balance change |
| `Scripts/Components/grime_component.gd` | grime becomes a masked shader uniform on **both** sprites, below; fix the stale docstring at `:13-16`, which still says the flash uses `self_modulate` |
| `Scripts/Components/effects_player.gd` | expose the shader material so grime can share it; **leave `sprite` pointed at `../Puppet`** |
| `Scripts/Data/personality_data.gd` | six presentation-only exports (section 5) |
| `Scripts/Autoload/audio_manager.gd` | four synthesised voices |

**Grime must reach the face; the flash must not.** These are opposite calls, and both are
deliberate.

- Grime today is `puppet.modulate` on the body sprite alone (`grime_component.gd:61-63`,
  `buddy.gd:92`), so a filthy skeleton has a **spotless white face** — and the lerp toward
  `Color(0.55, 0.50, 0.42)` also **browns the teal headphones**, the one prop
  `docs/art-direction.md` says never to compromise. Fold grime into the shader `EffectsPlayer`
  already installs (`effects_player.gd:22-30`) as a second uniform, masked to bone-white pixels
  so the teal and the outline are exempt, and apply the material to Puppet **and** Face. Retire
  the tint entirely when the three drawn overlay stages land.
- The white flash stays on `Puppet` alone (`buddy.tscn:103`). A one-frame white pop that erases
  the expression at the exact instant of peak attention is wrong; an unflashed face keeps the
  reaction readable through the hit.

**He has no voice.** Every sound attributed to him belongs to the object that hit him. Four
synthesised entries in `AudioManager._build_streams()`, in the existing helper style (D12 — all
audio is synthesised at boot, no assets): `oof` (`_impact_samples`, short and filtered), `greet`
(`_chime_samples`, rising two-tone), `yawn` (`_sweep_samples`, descending), `gasp`
(`_tick_samples`, rising).

### 3.7 Ordered steps

**Phase 0 — prerequisites. Nothing player-visible; everything after this depends on it.**

1. `buddy_art.gd`: capture `_base_scale` in `_ready()`; use it in the face placement at `:137`.
2. `buddy_art.gd`: replace the mirror at `:140-141` with the `dx`-only form above.
3. `buddy_art.gd`: `@export var buddy: Buddy`, filled by `_ensure_components`, used by
   `_state_of_body()`.
4. `buddy_art.gd`: build the offsets cache at load; place the face on `frame_changed` +
   `animation_changed`; add the `set_process(false)` contract.
5. `buddy.gd`: delete `REACTION_SECONDS`; every duration comes from `animation_length()` with a
   fallback.
6. `grime_component.gd` + `effects_player.gd`: masked grime uniform on both sprites; flash
   unchanged; stale docstring fixed.
7. Art tooling, **before any generation**: `postprocess.py --derive`, sub-range tags in the lua,
   `art/src/build_body.sh` (section 4).

**Phase 1 — the mind, no new art.**

8. `expression_brain.gd`: the beat slot, priority arbitration, damping, `_amp()` /
   `_initiates()`, the timer.
9. `buddy_art.gd`: the six new methods and the accumulator.
10. Wire tables A, B and E: pass `HitInfo` through, connect `kindness_sustained`, connect the six
    progression signals. `angry`, `smug` and `asleep` reach the screen for the first time.
11. Wire tables C and F: `hover_changed`, app focus in and out, the reunion beat, the drag ladder.
12. Wire tables D and G: `threat_changed` and its three emitters; `phase_changed` and the routine
    map.
13. Table H: blink, fidget, and **the mood-trough posture**.
14. Write D36 into `docs/decisions.md`.
15. The suites (section 6).

**Phase 2 — personality on the surface** (section 5). **Phase 3 — art** (section 4), arriving
into seams that already work.

---

## 4. The animation set

Rates from `docs/art-pipeline.md` § Cost model, measured 2026-08-29 with the free
`estimate_inference_cost`: **preset $0.14, `custom_action` $0.25, RD Pro still $0.18; frame count
free; reversal and held frames free.** Everything shipped so far cost $0.84.

Cell is 96×96, figure ~63 px, four colours exactly. Make them in this order — the walk first,
because it is the only thing standing between a fully built idle brain and anyone ever seeing it,
and the collapse re-roll early, because it is the beat the player already sees most.

| # | Tag | Frames | Route | Cost | Notes |
|---|---|---|---|---|---|
| 1 | side-view reference | still | RD Pro still, or hand-drawn from `bonehead_neutral_faceless_96.png` | $0.18 | **Every existing tag is front-on and near-symmetric**, which is why `body.flip_h` is invisible: `loop_check.gd:1458` asserts it flips during travel, passes, and the screen is identical. This is the first profile view in the character's whole set |
| 2 | `walk` | 8 | `walking` preset | $0.14 | **State the viewing angle in the prompt** — the clause `uplift-m3.7.md` added for the item batch and nobody applied to him. Budget two attempts. `travel()` is already the seam; no call site changes |
| 3 | `collapse` re-roll | 16 | `destroy` preset | $0.14 | The headphones detach and hang motionless in mid-air from frame 4 for thirteen frames while the body melts to a puddle — three seconds, every knockout, of the game's stated climax. `KEEPS_DETACHED_PIECES` (`postprocess.py:74`) is protecting a gag that does not land. Redraw, do not patch; `reassemble` and `pile` come free with it |
| 4 | `flinch` | 3–4 | `crouch` preset | $0.14 | Light hit and anticipation. Reversed = uncurl, free |
| 5 | `dizzy` | 4 | `subtle_motion` preset | $0.14 | Heavy-hit tail; the face already exists |
| 6 | `relax` | 6 | `subtle_motion` preset | $0.14 | `sit_in` = frames 1–2 as a sub-range; `lie_on` = first frame held. Both free. Covers all of `ROUTINE_SOAK` |
| 7 | `fiddle` | 6 | `subtle_motion` preset | $0.14 | Scrub, stall, idle fidget |
| 8 | `eat` | 4–6 | `attack` preset first, `custom_action` fallback | $0.14–0.25 | |
| 9 | `catch` | 3 | `attack` preset | $0.14 | The Interactive Buddy homage the design already promotes to a mechanic. Reversed = a present pose, free |
| 10 | `sleep` | 4 | `subtle_motion` preset | $0.14 | Reversed = `wake`, free |
| 11 | `idle_bored` | 8 | `idle` preset | $0.14 | Optional — the trough posture works as `speed_scale` + slouch on `idle`. Generate only if the code version reads as a stutter rather than a mood |
| 12 | `dance` | 8 | `custom_action` | $0.25 | "The screenshot animation — spend real time here" (`art-direction.md`), and `architecture.md`'s other missing state |
| — | `wave` | 4 | `custom_action` | $0.25 | Nice-to-have for the reunion beat; the code hop covers it until then |
| — | grime stages ×3, soot, sparkle, dust | — | **hand-drawn** | $0 | The generator will not hold a 4-colour speckle registered to his silhouette. `WorldFX.burst` is the pooled precedent for the puffs |
| — | `blink`, `bored`, `wince` faces | 1 each | **hand-drawn**, then rerun `_build_faces.lua` | $0 | A face never goes through the generator — the evidence is committed at `docs/images/face-degradation.png` |

**Generation total $1.55–$1.91; with a 30 % retry budget, under $2.50.** Money is not the
constraint. The constraint is roughly **45 minutes to two hours of hand-fixing per generated
tag**: 110–190 exposed outline pixels per animation to close (and any transform that moves pixels
reopens the outline, so rotate first and outline after), palette leaks, and specks that survive
`despeckle()` because it is 8-connected and they touch the headphone band diagonally — still
visible and still shipped in `art/preview/idle_sad_frames.png`, frames 2 and 6. **Re-baseline the
phase 4 estimate against that per-tag number before committing to a date.**

### Six artefacts per tag, or the suite goes red

`loop_check.gd:928-934` walks every animation and asserts it has a face-offsets row **whose
length equals its frame count**.

1. Generate into `art/raw/bonehead_<tag>_sheet.png`; record prompt, style, seed and task id in
   `art/prompts/`.
2. `python3 art/tools/postprocess.py art/raw/bonehead_<tag>_sheet.png <tag>` — snaps the palette,
   despeckles, closes the outline, writes `body_<tag>.png` and `face_<tag>.png`, and **merges the
   offsets row** into `Data/buddy_face_offsets.json`. Add a deliberately scattering tag to
   `KEEPS_DETACHED_PIECES` (`postprocess.py:74`) first, or the despeckler eats the pieces.
3. Rebuild the **whole** `.aseprite` in one `_build_body.lua` pass, with the full spec.
4. `ONE_SHOT` entry (`buddy_art.gd:48`) if it must not loop — the importer marks every tag as
   looping.
5. The table row in `expression_brain.gd`, or `STATE_ANIMATION` if it is a state.
6. `python3 art/tools/preview.py`, then the editor pass `--headless --editor --quit`. A new asset
   is invisible to `ResourceLoader.exists()` until it is imported.

**Skipping step 2 fails silently and badly.** `buddy_art.gd:128-130` early-outs on a short track:
the face **freezes in place, still visible, still flipped, while the body plays underneath it.**
Missing offsets detach the face; they do not hide it.

### Three tooling changes, all before the first generation

1. **`postprocess.py --derive <source_tag> --range a:b [--reverse]`.** `postprocess.py` writes an
   offsets row only for a generated sheet, which is why `dragged`, `pile` and `reassemble` have
   rows with **no `art/raw/face_*.png`** — they were hand-authored by a step nobody wrote down.
   Every free tag above (`wake`, `sit_in`, `lie_on`, the reversals) turns the suite red without
   this. About an hour; unblocks six tags.
2. **Sub-range tags in `_build_body.lua`.** It parses `tag:fps` only (`_build_body.lua:35-40`) and
   makes exactly one tag per sheet. Extend the spec to `tag:fps:from-to`. About an hour.
3. **Commit `art/src/build_body.sh` with the full spec.** The lua *must* be run with every tag
   every time: `Sprite:newFrame()` appends at the end and Aseprite silently extends any tag whose
   range ends at the last frame — the failure that once made all nine tags end at frame 74 and
   `idle` import as 74 frames (`_build_body.lua:11-18`). Going from nine tags to about eighteen is
   nine more chances to type a partial spec by hand.

`.godot/imported/bonehead.aseprite-*.res` is currently **older** than `art/src/bonehead.aseprite`.
Run the editor pass before believing anything about what the runtime is playing.

---

## 5. Personality on the surface

Twelve `.tres` files — diva, goth, gremlin, martyr, masochist, nervous, pendulum, showman,
stoic, stone, tyrant, zen — twelve `Curve`s, and the only place a player ever learns which one
they rolled is the prestige page, while `game-design.md` sells personality as half the reason to
Reincarnate.

D19 forbids a personality **touching numbers**: "the moment one of them touches prices or damage,
the five stop being one comparable axis and start being five balance problems." It says nothing
about presentation, and presentation fields stay inside D19 *by construction* — they multiply no
payout, so they cannot become balance problems, and a thirteenth personality stays a `.tres` with
no script edit (D8). `personality_data.gd:15-17` even instructs the author to describe how to
*play* him, "not what it does to a number — the player cannot see the curve."

Six optional exports on `PersonalityData`, all defaulted so the twelve existing files load
unchanged:

```gdscript
@export var hurt_face: StringName = &"shocked"
@export var celebration_face: StringName = &"happy"
@export var face_swaps: Dictionary = {}       ## {&"sad": &"neutral", &"blissful": &"shocked"}
@export var reaction_amplitude: float = 1.0   ## multiplies every code motion, never a payout
@export var fidget_period: float = 12.0       ## seconds; 0 disables
@export var flinches_early: bool = false      ## anticipation on an approaching item
```

Read once in `ExpressionBrain` off `Economy.personality` via `ItemDB.get_personality()`, and
re-read on `prestige_performed`.

| Personality | Curve | The visible tell, in the first minute |
|---|---|---|
| **Masochist** 2.8 / 1.1 | misery pays | `hurt_face = blissful`. **He grins while you hit him.** One field teaches the whole curve wordlessly |
| **Diva** 1.1 / 2.8 | bliss pays | `hurt_face = angry`, amplitude 1.4 — theatrical, sulks into `idle_sad` fast |
| **Showman** 0.9 / 3.0 | tallest, narrowest peak | amplitude 1.6, `celebration_face = smug`, shortest fidget period |
| **Goth** peak 2.2 at −50 | off-centre peak | `face_swaps = {sad: neutral, blissful: shocked}` — `sad` is his *contented* face and bliss reads as embarrassment. The one deliberately mismatched to mood |
| **Gremlin** 2.6 / 0.4 | purest seesaw | `fidget_period = 4` — never still |
| **Nervous** | flinches | `flinches_early = true`, amplitude 1.3. The only one who reacts *before* the bat lands |
| **Stone** flat 0.9–1.1 | mood is not a lever | amplitude 0.4, `fidget_period = 30`, `hurt_face = neutral`. Least motion in the set, cheapest CPU, and diegetically correct |
| **Zen** 1.0–1.4 | unbothered | amplitude 0.5, slow blink |
| **Pendulum** peaks at ±50 | pays in transit | `fidget_period = 3`; drifts between `idle_sad` and `idle_happy` |
| **Martyr · Tyrant · Stoic** | suffering · commitment · honest U | amplitude scaled by how far out on the curve he is. Martyr's "misery pays, but only just" wants a tell of its own — an owner call, section 8 |

**Edit the twelve `.tres` through a seed tool, not by hand** (CLAUDE.md rule 6). The existing
personality seeder is the precedent.

---

## 6. Tests

New `loop_check` suite `expression`, next to `_the_buddy_art_is_wired()` (`loop_check.gd:893`)
and in its shape. About 35 assertions.

1. **Table integrity.** Every row's face exists in `art.face.sprite_frames`; every row's body tag
   exists in `body.get_animation_names()` or is `&""`. Mirrors `:908-923`. A misspelled name
   silently no-ops through `set_expression`'s guard and he wears the last face forever.
2. **Every row that leaves `seconds` at 0 resolves to a real duration** —
   `animation_length(tag) > 0.05`.
3. **Every wire fires, asserted one signal at a time.** For each connected signal: emit it, then
   assert `art.body.animation` or `art.face.animation` changed — plus an explicit `is_connected`
   check per signal. The `FXLayer` scar was four `connect()` calls after a `return`: invisible, no
   warning, payout numbers silently gone.
4. **The sponge reacts.** Emit `kindness_sustained` through the real bus and assert a beat is
   live. This single assertion is the regression test for the bug that shipped M3.
5. **Priority.** Hit then pet → still `hurt`. Pet then hit → `hurt`. Any trigger during
   `_in_knockout` → still `collapse`.
6. **Escalation.** A 1-damage beat is strictly shorter than a `hit_stop_full_damage` beat, both
   greater than zero. **Read the multipliers before emitting** — autoloads connect to `EventBus`
   before scene nodes do, and three M3 assertions failed on exactly this.
7. **Damping.** Two identical hits 0.05 s apart: assert `body.frame` advanced rather than reset
   to 0.
8. **Focus Off is silent.** Pin `Settings.focus_intensity` on the suite's first line, set `OFF`,
   fire every trigger, then assert `body.scale == _base_scale`, `body.position == _body_home`,
   `face.position` equals the pure offsets-derived value, and an **ambient-start counter reads
   zero**. That counter must be a member or an `Array` element — a GDScript lambda captures locals
   by value, and a counter inside one reports a working mechanic as broken. Restore the setting
   and `save_settings()` before quitting.
9. **A reaction still plays at Off.** Emit `damage_dealt` at `OFF` and assert the face changed.
   D36 is two rules, and this is the second one.
10. **The face never detaches.** After every beat in the table plays and settles, `face.position`
    matches the offsets-derived position to within a pixel. This is what catches the `body.scale`
    trap in 3.3.
11. **Mirroring regression, written before the walk art exists.** Set
    `_face_home = Vector2(3, 0)`, `travel(-1, 1)`, step a frame, and assert the face x is `3 - dx`
    and not `-3 - dx`. `loop_check.gd:1458` passes today only because every tag is a symmetric
    front view; the bug is invisible until `walk` makes `flip_h` mean something.
12. **Nothing leaks.** After every beat: `body.speed_scale == 1.0`, squash back to `(1, 1)`,
    `_look_x == 0`.
13. **He goes quiet.** After settling with no travel and no live beat, `art.is_processing() ==
    false` **and** the brain's timer is stopped.
14. **Ambient never fires while dragging or in knockout.**
15. **The offsets cache is honest.** The cached `PackedVector2Array` length equals
    `get_frame_count()` for every animation, preserving what `:928-934` guarantees today after the
    representation changes. Add one explicit check that every *derived* tag has a row, so the
    failure names the missing tool rather than the tag.
16. **`art.buddy != null`** — guards the `_state_of_body()` wrapper breakage.
17. **Personality.** All twelve `validation_error()` empty; every `hurt_face`,
    `celebration_face` and `face_swaps` value resolves to a real face.

`ui_check` — headless, and there is no real DisplayServer focus event to raise:

18. Call `buddy._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)` and then `_IN` directly; assert
    the away clock and the reunion beat.
19. Motion over his grab rect sets hover and, at Normal, moves the gaze; motion away and
    `NOTIFICATION_WM_MOUSE_EXIT` both clear it. Send
    `notification(Viewport.NOTIFICATION_VP_MOUSE_ENTER)` by hand — physics picking is gated on it,
    and a bare `SubViewport` never learns the mouse is inside.
20. With a panel open (`ui_panel_changed`), gaze does not pull him under the card.
21. **Source sweep**: `expression_brain.gd` and `buddy_art.gd` contain no `get_mouse_position(`.
22. Clicking his rect still starts a drag — the regression guard for touching `draggable_area.gd`.

`pacing_sim`, `window_check` and the save fixtures are **untouched**. No `balance.tres` change,
no schema change, no migration.

An F3 overlay row — current beat, priority, arousal, attention, away clock — makes all of this
debuggable at all, and costs nothing.

---

## 7. Phasing

### One afternoon (~6 h): five wires and four drawn faces

Everything here is reachable today and every line survives into the final design. Do it before
`ExpressionBrain` exists, as its own commit, so there is something to look at while the
architecture lands.

1. Connect `EventBus.kindness_sustained` in `buddy.gd:72`. **The sponge, the boombox, the hot tub
   and all twenty M3.7 leisure items get a reaction for the first time.**
2. Stop discarding `info.amount` at `buddy.gd:207` and `source_id` at `:250` — a light hit and a
   mace stop looking identical, and per-category faces put `angry` on screen.
3. Replace `REACTION_SECONDS` with `animation_length()` plus a fallback; `happy` stops being cut
   off at 0.45 s.
4. `DraggableArea.hover_changed` → a gaze lean and `neutral`, Normal and above.
5. `NOTIFICATION_APPLICATION_FOCUS_IN` / `_OUT` in `buddy.gd` → `asleep` when he has been left,
   and a two-hop `happy` reunion when the player comes back.

`angry`, `smug`, `asleep` and idle `dizzy` are drawn, imported and reachable by nothing today.
This puts three of them on screen.

### Two days (~14 h): the afternoon, plus phase 0 and the beat slot

Add the phase 0 prerequisites (3.7, steps 1–6), the beat slot with priority and damping, D36
written down, and tables E and F wired. That is a character who reacts to the purchase, the rank
up, the milestone, the toy landing and being held too long — and a `BuddyArt` that is cheaper per
frame than it is today.

### The full set

| Phase | Work | Hours | $ |
|---|---|---|---|
| 0 | Prerequisites: `_base_scale`, foot anchor, the mirror fix, `@export buddy`, offsets cache + `frame_changed` + the process contract, duration from the art, grime shader mask, art tooling (`--derive`, sub-ranges, `build_body.sh`) | **7** | 0 |
| 1 | `ExpressionBrain` + accumulator + all eight tables wired + D36 + the mood-trough posture + four synthesised voices | **16** | 0 |
| 2 | Personality: six exports, seed tool, twelve `.tres`, reword two descriptions | **5** | 0 |
| 3 | Suites: `loop_check` ×17, `ui_check` ×5, the F3 row | **6** | 0 |
| 4 | Art: 10–12 generations, postprocess, one-pass rebuild, hand-fixing at the per-tag rate, grime stages, previews, editor passes | **22–28** | ~$2.50 |
| 5 | Tune against a real session: amplitudes, durations, fidget periods | **4** | 0 |
| | **Total** | **60–66 h** | **~$2.50** |

**Phases 0–3 are 34 hours, need no new art and no generation spend**, and pay off D4's four-month
debt. Phase 4 is a separate art session whose real content is the walk cycle and the collapse
re-roll, and it should not block any of the above.

---

## 8. Open decisions

1. **D36 as written?** "At Focus Off he reacts; he does not initiate", plus "beats are not
   states". Two systems have already invented compatible answers independently; this only writes
   down what they both do. Needs a yes before phase 1 — thirty ungated triggers would make Off
   louder than today's Normal, breaking the promise to a player in a meeting, and Focus Mode is
   the project's de-facto reduced-motion accessibility switch until M4.
2. **Gaze at all?** Recommended: look-only, ≤ 2 px lean, Normal and above, never chase. It is the
   cheapest life per CPU cycle in the whole plan and also the most attention-grabbing thing on the
   list. If in doubt, ship phase 1 without it and add it after the 30-minute playtest.
3. **Two personality descriptions promise behaviour a `Curve` cannot produce.** `nervous.tres`
   says it "pays hugely for the first blow of a swing and tails off" — a curve over mood has no
   memory of a swing. `pendulum.tres` says it "only pays while he is moving between moods" — the
   curve samples position, not velocity, so parked at −50 it pays 2.6 forever. Recommendation:
   **reword both**, and let `flinches_early` and a 3 s fidget period carry their identities
   visually, which costs nothing. The alternative is a second, non-monetary field on
   `PersonalityData` — which is where the presentation argument arrives from the other side.
4. **`martyr`, `tyrant` and `stoic` have no proposed tell yet.** Three lines of design, not
   engineering.
5. **`idle_bored` — generated tag or code posture?** The `speed_scale 0.7` + slouch version costs
   $0 and ships in phase 1. Generate the tag only if the code version reads as a stutter rather
   than a mood.
6. **Does the reunion beat suppress the offline toast, or land under it?** Recommendation: land
   under it, so the money and the greeting are one moment rather than two.
7. **How loud is Chaos?** Section 2E gives the top-tier payout row to Chaos only. If Chaos is
   meant to be more than "Normal with bigger numbers", it wants two or three rows of its own — an
   owner call about the setting, not about the character.
8. **The knockout has the highest seen-per-session-to-polish ratio in the game**, and its worst
   three seconds are a pair of headphones hanging in mid-air. Confirm the `collapse` re-roll is in
   scope for the same art session as the walk: it is $0.14, and it is the beat the player already
   sees most.
