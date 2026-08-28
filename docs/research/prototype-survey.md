# Research — Prototype Survey

Snapshot of the codebase as of 2026-08-28, before the production rebuild. ~931 lines of GDScript
across 25 files, 41 commits, no addons, no tests, no docs. Recorded so the rebuild knows what it
inherited and why each decision was made.

## What's worth keeping

- **`BaseDraggable`'s drag technique** — a `PinJoint2D` between the dragged `RigidBody2D` and an
  invisible `StaticBody2D` "handle" that lerps toward the mouse each physics frame. This is the
  game feel. Keep it.
- **Component composition** via `@export`ed node references with `node_paths` in the scene
  (`HealthComponent`, `HitBoxComponent`, `AttackBox`, `EffectsPlayer`). The healthiest pattern in
  the project.
- **Scene inheritance** — `base_body.tscn` → `BaseballBat.tscn` / `_Mace.tscn`.
- Pixel-art import defaults: Nearest filter, lossless, no mipmaps, `fix_alpha_border`.

## What was missing entirely

Verified by exhaustive grep: no `FileAccess`, `ConfigFile`, `user://`, `ResourceSaver`, or any
save/currency/upgrade/persistence code anywhere. No audio files, no `AudioStreamPlayer`, no audio
buses (`SoundPlayer.gd` is a one-line empty stub). No fonts. No `Theme` beyond an inline
`default_font_size = 20`. No collision layer names. No settings.

**Overlay features were never implemented.** `DisplayServer.window_set_mouse_passthrough`,
`WINDOW_FLAG_ALWAYS_ON_TOP` and `WINDOW_FLAG_NO_FOCUS` appear nowhere. The window is a plain
bordered 1280×720 window that happens to have a transparent background because of two project
settings. `Main.gd` (199 lines, the only autoload) contained an elaborate OS/screen-detection and
window-setup system that is **dead code** — its entry point is commented out:

```gdscript
func _ready():
	detect_system_info()
	#setup_transparent_window()      # <-- disabled
	set_window_mode(WindowMode.WINDOWED)
```

Containment was faked with four hand-placed `StaticBody2D` borders around the 1280×720 box.

## The shipped export bug (commit `4d831ab`)

Worth understanding because it justifies two hard rules in `CLAUDE.md`:

1. **Case-sensitive paths.** `preload("res://Scenes/bodies/BaseballBat.tscn")` resolves fine on
   the Windows editor filesystem and fails inside the case-sensitive PCK — the real directory is
   `Scenes/Bodies/`. Nothing enforces casing, so the class of bug is still latent.
2. **A hardcoded `get_node` that crashed on load.** `get_node("Menus/ItemMenu")` where the node is
   actually named `item_menu`. The unfixed copy still exists in `backup_BaseLevel.gd`, which also
   still registers a conflicting `class_name BaseLevel`.

## Defects catalogued (all fixed or designed out in M0/M2)

**Damage model.** `WeaponClass.gd` computes `impact_strength` from
`_attackBody.linear_velocity.length()/1000 * mass`, where `_attackBody` is a bare `RigidBody2D`
nested *inside* the weapon's own rigid body **with no collision shape of its own**. It free-falls
under gravity, so its velocity is essentially *time since the last hit × 980* — not swing speed.
The `min/max_damage` clamp hides it, and commit `8fd347e` ("enhanced damage calculation to feel
more realistic") tuned around the artefact rather than fixing it. → `decisions.md` D7.

**Item menu.** Seven hand-copied tile `Control`s in the `.tscn`, seven hardcoded `preload`s, seven
separate `pressed` handlers, and cursor powers reached by absolute path
(`get_node_or_null("/root/BaseLevel/_Gun")`). `_on_fist_icon_pressed()` calls
`gun.make_inactive()` without the null guard its two siblings have — a guaranteed crash if the
tree changes. A generic `item.tscn` tile and an `ItemData` resource both exist and are **instanced
nowhere** — an abandoned data-driven attempt. → D8.

**Item counting.** `item_count` is incremented on spawn and **never decremented**; trashing or
exploding an item permanently burns one of the 10 slots, and `active_items` fills with freed
references.

**Trash bin.** `delete_bodies()` erases from the array it's iterating (skips every other element);
`delete_timer_active` is never reset and the timer isn't one-shot, so after the first body ever
enters, the bin fires forever on a 1.5 s loop; deletions aren't reconciled with `item_count`; the
whole thing polls in `_process` where a signal would do.

**Duck-typing.** `body.has_method("Character")` and `has_method("fist")` as type tests, backed by
no-op marker methods that exist purely to make `has_method` return true. Both are real
`class_name`s, so `is Character` would work. → D9 / collision-layer plan.

**Other.** Explosion VFX nodes are spawned into `current_scene` and **never freed** — every
explosion leaks a node. The identical explosion falloff-impulse loop is duplicated in
`ThrowableClass.gd` and `_missle.gd`. Three cursor powers implement `make_active`/`make_inactive`
three different ways across three different node types with no shared interface. The fist's
`_ready()` calls `make_inactive()` which disables `_physics_process`, so its off-screen parking
branch never runs — leaving an invisible collider stranded at `(234, 131)`. `Character._process`
checks `global_position.y < -2000` for "fell off the map" (wrong sign). `entity_damaged()` /
`entity_healed()` are `pass` with the flash effect commented out — **zero damage feedback exists**.
`IncreaseHealth` is never called.

**Hygiene.** ~25 `print()` statements in shipping paths, several per-frame. Mixed indentation
(two files use 4 spaces, the rest tabs). "Missle" misspelled throughout including a user-facing
label. Inconsistent naming: `PascalCase` members (`Health`, `Max_Health`, `Effects_Player`) mixed
with `snake_case`; `main_menu.gd` drives `pause_menu.tscn`.

## Assets inventory

Twelve PNGs, all 64×64 except `base-bonehead.png` (320×64 = five 64×64 idle frames at 7 fps).
The character, mace, bat, dynamite, grenade, missile, fist, trash bin, crosshairs, icon. **On-screen
scale is wildly inconsistent** — character 2×, bat and mace 4×, missile 3×, grenade/dynamite/fist
1×. No atlas, no animation beyond the character idle. Filenames contain spaces
(`baseball bat.png`, `Crosshair Basic.png`). The gun's three `cursor_type` variants all preload
the *same* crosshair texture.

## Dead weight removed in M0

`Scripts/Globals/backup_BaseLevel.gd`, `Scenes/Levels/backup_base_level.tscn`,
`Scenes/Levels/PROTOTYPE.tscn`, `Scenes/Bodies/test_body.tscn`,
`Scripts/Prototypes/PT-MainCharacter.gd`, `Resources/_Res_GunConfig.{gd,tres}`,
`Scripts/Components/SoundPlayer.gd`, `Scripts/Globals/Main.gd`. `PROTOTYPE.tscn` and
`test_body.tscn` also set `is_uniform`, a property that no longer exists on `BaseDraggable`, so
they emit orphan-property warnings on load.

## Settings that were already right

`default_texture_filter = 0` (Nearest), lossless compression, GL Compatibility renderer,
`window/size/transparent` + `per_pixel_transparency/allowed`. Settings that were wrong and change
in M0: VSync disabled, 120 physics ticks/second, `stretch/mode = "viewport"` with `expand`.
