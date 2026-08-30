# Architecture

Target architecture for the production rebuild. The prototype in `Scripts/Globals/` predates
this and is being replaced; see `roadmap.md` for sequencing.

## Principles

- **Data over code.** Adding an item, augment or contract must be a `.tres` file, never a
  script edit. The prototype required editing three places to add one item; that's the specific
  failure this architecture exists to prevent.
- **Signals over paths.** Cross-scene communication goes through `EventBus` or node groups.
  Absolute paths like `/root/BaseLevel/_Gun` are banned — that coupling caused a shipped
  export bug.
- **Composition over inheritance**, except where inheritance is genuinely the shape (draggable
  bodies). Components (`HealthComponent`, `MoodComponent`, `HitBox`) attach via `@export` refs,
  the one pattern from the prototype worth keeping wholesale.
- **Lean.** Solo dev with AI assistance. Eight small autoloads, one bus, no framework.

## Autoloads

Registered in this order — boot order is load-bearing.

| # | Autoload | File | Responsibility |
|---|---|---|---|
| 1 | `EventBus` | `Scripts/Autoload/event_bus.gd` | Signal declarations only. Zero state, zero logic. |
| 2 | `Settings` | `settings.gd` | `user://settings.cfg` — monitor id/rect, Focus Mode, volumes, low-power, streamer mode. Machine-local, **never** cloud-synced. |
| 3 | `SaveManager` | `save_manager.gd` | Versioned JSON at `user://save/`, atomic writes, `.bak` fallback, migrations, debounced autosave. |
| 4 | `ItemDB` | `item_db.gd` | Scans `res://Data/` at boot. Read-only lookup of `ItemData` / `AugmentNode` / `ContractData` / `PersonalityData` by id, plus `balance` and the active mood curve. |
| 5 | `Economy` | `economy.gd` | Currency balances, the payout pipeline, lifetime totals, offline earnings, prestige. |
| 6 | `Progression` | `progression.gd` | Owned unlocks, augment levels, exclusive choices, mastery XP and pool, automation toggles, contract board. Answers `get_modifier()`, `mastery_multiplier()` and `automation_rate_per_second()`. |
| 7 | `OverlayManager` | `overlay_manager.gd` | Window flags, passthrough polygon, monitor persistence, FPS governor, hibernate. See `overlay-tech.md`. |
| 8 | `AudioManager` | `audio_manager.gd` | Bus setup, pooled players (voice cap 8), pitch-randomised layered impacts, mute-when-unfocused. |

`Economy` and `Progression` are split because they map 1:1 onto the Shop UI and the Tree UI.
If that ever feels like overhead, fold `Progression` into `Economy` — nothing else changes.

The prototype's `Main.gd` autoload is deleted in M0. Its screen/DPI detection was 170 lines of
unreachable code (the setup call was commented out); the useful observations are preserved in
`overlay-tech.md`.

## EventBus contract

This is the interface everything codes against. Adding a signal is cheap; changing one is not.

```gdscript
# Scripts/Autoload/event_bus.gd — signals only, no logic
extends Node

# --- combat / interaction ---
signal damage_dealt(info: HitInfo)                        # buddy -> Economy, contracts, FX
signal kindness_given(source_id: StringName, value: float, world_pos: Vector2)
signal kindness_sustained(source_id: StringName, value: float, world_pos: Vector2)  # rate-paid; no combo (D14)
signal payout(currency: StringName, amount: float, world_pos: Vector2)
signal currency_changed(currency: StringName, balance: float)

# --- items ---
signal spawn_requested(item_id: StringName, at: Vector2)  # shop tile -> ItemSpawner
signal item_spawned(item: Node2D)                         # -> passthrough, bin, counters
signal item_despawned(item: Node2D)
signal cursor_power_changed(item_id: StringName)          # &"" clears; powers self-deactivate

# --- progression ---
signal item_purchased(item_id: StringName)
signal augment_purchased(node_id: StringName, level: int)
signal mastery_rank_up(item_id: StringName, rank: int)
signal contract_event(key: StringName, count: int)        # &"deal_damage", &"pet", &"use:bat"
signal contract_completed(contract_id: StringName)       # target reached, reward unclaimed
signal contract_claimed(contract_id: StringName, ectoplasm: int)
signal prestige_performed(ectoplasm_gained: int)
signal automation_changed()                              # a capstone was bought or toggled

# --- buddy ---
signal mood_changed(value: float)                         # -100..+100
signal buddy_state_changed(state: StringName)
signal knockout_payout(total: float)

# --- shell ---
signal ui_panel_changed(panel: StringName)                # &"" = all closed
signal interactive_shapes_dirty()                         # rebuild passthrough polygon
signal focus_mode_changed(level: int)
signal save_requested()
```

**Rules:** payload types are `HitInfo` (RefCounted) or primitives — never pass node references
through the bus unless the receiver's only job is to hold them (`item_spawned`). Nothing
connects to a signal it doesn't act on.

## Data model

All content is typed `Resource` files under `res://Data/`. Typed resources beat JSON here:
inspector-editable, refactor-safe, and validated at load.

```gdscript
# Scripts/Data/item_data.gd
class_name ItemData extends Resource
@export var id: StringName                               # &"baseball_bat" — the universal join key
@export var display_name: String
@export_multiline var description: String
@export_enum("Weapon", "Throwable", "CursorPower", "Friendly", "Toy") var category: int
@export var cost: int
@export_enum("Bones", "Hearts") var currency: int
@export var scene: PackedScene
@export var icon: Texture2D
@export var requires: Array[StringName]                  # prerequisite item ids
@export var sort_order: int
```

```gdscript
# Scripts/Data/augment_node.gd
class_name AugmentNode extends Resource
@export var id: StringName
@export var item_id: StringName                          # owning item, or &"global"
@export var tier: int
@export var effect_key: StringName                       # &"damage_mult", &"payout_mult", ...
@export var effect_per_level: float
@export var max_levels: int = 10
@export var cost_base: int
@export var cost_growth: float = 1.10
@export_enum("Bones", "Hearts") var currency: int
@export var exclusive_group: StringName                  # non-empty = pick-one within (item_id, group)
@export var is_automation: bool                          # capstone; Hearts by convention
@export var requires: Array[StringName]
@export var requires_mastery: int
@export var requires_prestige: int
```

Also: `ContractData` (goal key, target, period, Ectoplasm reward), `PersonalityData` (a name
and **one mood `Curve`** — that is the whole of a personality, see D19), and **`balance.tres`** — one resource holding every global knob (mood `Curve`,
`bones_per_damage`, `min_damage_impulse`, knockout params, offline cap and efficiency, prestige
constants, item limit). `balance.tres` is the tuning spreadsheet; nothing else hard-codes a rate.

Currencies are `StringName`-keyed dictionaries throughout (`Economy._balances`), so collapsing
to a single currency — or adding a fourth — is a data change, not a refactor.

### Save schema (v3)

```json
{ "version": 1,
  "saved_at_unix": 0, "last_played_unix": 0, "playtime_sec": 0,
  "currencies": { "bones": 0, "hearts": 0 },
  "lifetime":   { "bones": 0, "hearts": 0 },
  "prestige":   { "ectoplasm": 0, "count": 0, "personality": "stoic" },
  "unlocks": [], "augments": {}, "exclusive_choices": {},
  "mastery_xp": {}, "mastery_pool": 0,
  "buddy": { "mood": 0.0, "grime": 0.0 },
  "automation_off": [],
  "offline_cap_level": 0,
  "contracts": { "active": [], "progress": {}, "claimed": [], "refreshed_at": 0 },
  "cosmetics": { "owned": [], "equipped": [] },
  "stats": { "damage_dealt": 0, "pets": 0, "knockouts": 0 } }
```

Each autoload implements `to_save() -> Dictionary` and `from_save(d: Dictionary)`;
`SaveManager` composes and decomposes. `SaveManager.slot_name` selects the file inside
`user://save/` — a variable rather than a constant so the headless loop check runs against its
own slot instead of overwriting the save of whoever is running the tests. Write path: serialise → `slot_1.json.tmp` → rename over
`slot_1.json`, previous copy kept as `.bak`. Load path: parse failure falls back to `.bak`.

`automation_off` lists the capstones the player has switched **off**, not the ones they have on.
Absence therefore means running, which is what a save written before automation existed should
mean — the inverse spelling would arrive from v2 with every future capstone disabled and no way
for the player to know why.

`Buddy` is itself a save provider for the `buddy` block — mood and grime are his state, and
`Economy` only mirrors them off the bus so the payout pipeline can multiply by them (D15).
The buddy registers in `_ready()` and unregisters in `_exit_tree()`, so a scene change does
not leave `SaveManager` holding a freed node.

Migrations are an ordered chain of `_migrate_1_to_2(d)` functions. Unknown keys are preserved.
**Every schema change needs: `SAVE_VERSION` bump + migration step + a fixture save in
`tests/fixtures/`.** Autosave is debounced 30 s after any `currency_changed`, and immediate on
purchase, knockout, prestige, hibernate and quit.

Steam Cloud syncs `user://save/` only. `settings.cfg` holds monitor rects and must stay local.

## Scene architecture

**Boot to buddy — no traditional main-menu scene.** One OS window. Extra `Window` nodes are
avoided: each one complicates always-on-top ordering and passthrough. UI is opaque
`PanelContainer`s on `CanvasLayer`s inside the overlay, which is also the genre norm.

```
main.tscn
Main (Node) ── main.gd  (thin bootstrapper)
├─ World (Node2D)
│  ├─ Bounds (StaticBody2D)      # generated at runtime from the screen's usable rect
│  ├─ ItemSpawner (Node)         # owns instancing + item limits; listens to spawn_requested
│  ├─ Buddy (buddy.tscn)
│  └─ Props (trash bin, contract board, automation devices)
├─ FXLayer   (CanvasLayer 5)     # floating numbers, impact sparks — Focus-Mode gated
├─ HUD       (CanvasLayer 10)    # currency chips, knockout + mood meters, toast, dock
├─ PanelLayer(CanvasLayer 20)    # Toys / Upgrades / Jobs / Rebirth / Settings — opaque panels
├─ EscMenu   (CanvasLayer 30)
└─ Tray (StatusIndicator)        # Show/Hide, Pause, Settings, Quit
```

The "beautiful main menu" requirement is met by the HUD dock plus the panel suite, themed with
a real `Theme` resource and a chosen font — the prototype has neither.

`main.tscn` holds only `World` (bounds, spawner, buddy, props). The four CanvasLayers are built
by `main.gd` at boot, because every widget on them is generated from data (docs/decisions.md
D13). `Scripts/UI/ui_style.gd` is the one place styling lives until the `Theme` exists.

`main.gd` also installs `TuningLog` — but only under `OS.is_debug_build()`. It writes every
payout and purchase to `user://logs/`, which is the instrument the M3 balance gate needs and a
performance bug in a shipped build.

The panel's scroll height is a function of the window and of the page being shown, not a
constant: a long shop scrolls, a short settings page is a short panel, and neither leaves dead
space on a 1440p overlay. A fixed height is wrong in both directions and the play area is
resizable at runtime.

`ItemSpawner` is a node, not an autoload, because it needs a parent to instance into. It tags
every spawned node into groups (`spawned_item`, `interactive`) which is how the trash bin, the
passthrough polygon builder and the item counter find things without paths.

**Pause semantics matter.** Never use `get_tree().paused` for hibernate — it would stop the
economy too. The Esc menu pauses only `World` via `process_mode`; hibernate is
`OverlayManager` dropping the frame cap and switching `Economy` to offline accrual.

## Combat pipeline

Damage is measured **on the receiver** from real contact impulses. This is the single most
important correction to the prototype, which read the velocity of a shapeless nested rigid
body — measuring, in effect, time since the last hit.

```gdscript
# Scripts/Buddy/buddy_body.gd — contact_monitor = true, max_contacts_reported = 4
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	for i in state.get_contact_count():
		var impulse := state.get_contact_impulse(i).length()
		if impulse < ItemDB.balance.min_damage_impulse:
			continue
		var src := state.get_contact_collider_object(i)
		if not _cooldown_ready(src):
			continue
		var mult: float = src.damage_mult if src is WeaponBase else 1.0
		_health.apply_hit(HitInfo.new(impulse * mult, _source_id(src),
			state.get_contact_local_position(i), impulse))
```

`HitInfo` is a `RefCounted` carrying `{amount, source_id, position, raw_impulse}`. A per-source
cooldown (~0.1 s) stops resting contact from farming damage.

Then: `HealthComponent.apply_hit()` → `EventBus.damage_dealt` → `Economy` applies mood, augment,
mastery and prestige multipliers → `EventBus.payout` → `FXLayer` spawns a pooled floating number
and applies hit-stop (2–8 frames scaled by magnitude, Focus-Mode gated) → `AudioManager` plays a
layered, pitch-randomised impact. Kindness uses the identical path via `kindness_given`.

### Class hierarchy

```
BaseDraggable (RigidBody2D)      # KEEP — pin-joint-to-invisible-handle drag IS the game feel
├─ WeaponBase                    # item_id, damage_mult, mastery hooks, auto-swing (capstone)
├─ ThrowableBase                 # prime()/explode() template; shared falloff impulse
└─ FriendlyBase                  # the whole kindness roster, as exported numbers

CursorPowerBase (Node2D)         # item_id, activate()/deactivate(), cursor texture, fire(pos)
├─ GunPower                      # pistol and shotgun: pellets + spread, same class
├─ MissilePower
└─ OpenHandPower                 # petting; declines clicks that miss him
```

`OpenHandPower` tracks a `_stroking` flag set by a press this power actually claimed, rather
than polling `Input.is_mouse_button_pressed`. Polling bypasses the whole `_unhandled_input`
chain that exists so UI can consume a click first: with a panel open over the buddy, holding
the button on a shop tile would pay Hearts at four a second with the cursor nowhere near him.

`FriendlyBase` is one class for every friendly item because the catalog has exactly three
shapes: a burst on touch (pizza), a rate while something is true (sponge scrubbing, boombox
playing), and a consumable that leaves when used. Each is an exported number, so a new
friendly item is a `.tres` plus a scene with different values in it (D8).

`CursorPowerBase.can_fire_at(pos)` lets a power decline a click. A declined click is left
unhandled, so the world still sees it — which is how the open hand can be a cursor power
without making everything outside his silhouette undraggable while it is equipped.

`CursorPowerBase` replaces three copy-pasted activation implementations. Each instance listens
to `cursor_power_changed` and deactivates itself when the id isn't its own — which deletes the
three-way `if` chain in the old `item_menu.gd` entirely.

Fixes required to `BaseDraggable` when it's promoted (both are latent bugs today):
- `_input` → `_unhandled_input`, so UI can consume clicks before draggables see them. Mandatory
  before shop panels overlap the world.
- `_start_drag` uses `event.position` (viewport space) while `_physics_process` uses
  `get_global_mouse_position()`. Pick global space for both.

### Collision layers

Named in Project Settings; never use bare numbers.

| # | Name | Notes |
|---|---|---|
| 1 | `world` | Bounds, static props |
| 2 | `buddy` | The buddy body |
| 3 | `item` | Spawned weapons, throwables, toys |
| 4 | `handle` | Invisible drag handles — collide with nothing |
| 5 | `pickup` | Collectibles |
| 6 | `sensor` | Area2D-only detection |

Type checks use `is Buddy` or groups — never the prototype's `has_method("Character")`
duck-typing markers.

## Buddy

Single rigid body with an expressive animated puppet (decision recorded in `decisions.md`).

```
buddy.tscn
Buddy (RigidBody2D) ── buddy.gd : StateMachine
│    states: Idle · Dragged · Hurt · Happy · Sleep · Dance · Knockout · Pile · Reassemble
├─ Puppet (AnimatedSprite2D)     # body animation set
├─ Face   (AnimatedSprite2D)     # expressions, layered so mood reads independently of pose
├─ Grime  (Sprite2D)             # dirt overlay, cleared by the sponge
├─ CollisionShape2D
├─ DraggableArea (Area2D)
├─ HealthComponent               # the knockout damage meter
├─ MoodComponent                 # -100..+100, decays toward 0, drives payouts and animation
├─ GrimeComponent                # 0..1, suppresses Bones income; only the sponge removes it
├─ HitBox (Area2D)
└─ EffectsPlayer
```

Knockout is a scripted beat, not simulated dismemberment: tip over → swap to a bone-pile sprite
→ payout fountain → reassemble tween. Cheap, gore-free, and repeatable forever. He is `freeze`d
for the whole beat, so the collapse is choreography rather than whatever the solver does with a
body full of accumulated impulse. States fire in order `knockout → pile → reassemble → idle`;
`Economy` pays the bonus off the first of those, because it is the only thing allowed to mint
currency, so the buddy announces rather than awards.

`MoodComponent` and `GrimeComponent` are `@export` slots that `buddy.gd` fills in at `_ready()`
if the scene has not authored them. That is a tooling accommodation, not a design: scene edits
must be made in the editor (CLAUDE.md), and the M3 art pass is the point at which `buddy.tscn`
is opened and both are authored properly alongside the grime sprite layer they will drive.

The state machine, `HealthComponent` and the payout pipeline form a stable interface. If a
jointed ragdoll is ever added post-1.0, it slots in behind that interface without touching
`Economy`, the UI, or the save format.

## What gets deleted

`Scripts/Globals/backup_BaseLevel.gd` (registers a conflicting `class_name BaseLevel` and still
contains the line that broke the export build), `Scenes/Levels/backup_base_level.tscn`,
`Scenes/Levels/PROTOTYPE.tscn`, `Scenes/Bodies/test_body.tscn`,
`Scripts/Prototypes/PT-MainCharacter.gd`, `Resources/_Res_GunConfig.{gd,tres}`,
`Scripts/Components/SoundPlayer.gd` (empty stub), `Scripts/Globals/Main.gd`.
