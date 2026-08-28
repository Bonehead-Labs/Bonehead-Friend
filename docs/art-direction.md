# Art Direction

## The character

Bonehead as drawn in the prototype (`Assets/base-bonehead.png`, 5 × 64×64 idle frames): a
small, rounded, cream-white chibi figure — big head, stubby limbs, two dot eyes, a simple
smile — wearing **teal over-ear headphones**.

Keep all of it. Two things about that design are load-bearing:

1. **He's soft, not scary.** Rounded silhouette, no visible ribs or grinning skull. That's what
   makes hitting him funny rather than grim, and it's what keeps the store rating clean.
2. **The headphones are the whole pitch in one prop.** He is already dressed for sitting on
   your desktop while you work. They make him readable at 64 px, they're the silhouette hook,
   and they're a free cosmetic slot (different headphones per skin). Never design him without
   them.

Uplift direction: more expressive, not more detailed. Bigger squash and stretch, a wider face
set, more anticipation before impacts. Resist adding rendering detail — he has to read clearly
at small size against an unknown background.

## Style rules

- **Pixel art, nearest-neighbour, no anti-aliasing** on sprite interiors.
- **64×64 cell grid** for characters and items; props and furniture may use 128×128. This is
  also the Retro Diffusion sweet spot.
- **Uniform on-screen scale.** The prototype is inconsistent — the character renders at 2×,
  bat and mace at 4×, missile 3×, grenade and fist at 1×. Standardise on **2× for everything**
  and author at the true pixel size instead of scaling up in-engine. Fix each asset as it's
  touched.
- **Dark outline on everything.** Not optional. The game renders over an unknown background —
  a white IDE, a black terminal, a photo wallpaper. Every sprite needs a 1 px dark outline (or
  a dual-tone bright-core/dark-edge treatment for effects) or it will vanish on someone's
  desktop.
- **Readable at a glance from across the room.** The player is working; they see this in
  peripheral vision. Silhouette and pose carry the information, never fine detail.

## Palette

Anchored on what already exists:

| Role | Use |
|---|---|
| Bone cream | The character's body — the brand colour |
| Teal / cyan | Headphones, UI accents, "friendly" affordances |
| Warm orange–red | Damage, explosions, Bones currency |
| Pink–magenta | Hearts, kindness feedback, mood-positive effects |
| Ghost green | Ectoplasm, prestige UI |
| Near-black | Outlines everywhere |

Lock the exact hex values into an Aseprite palette file (`art/src/bonehead.gpl`) once the first
production sprites exist, and run every generated asset through Retro Diffusion's palette
converter against it. That's what stops AI-generated assets drifting apart.

Currencies must be distinguishable by **shape as well as colour** (bone vs heart icons) for
colour-blind players — they're the two most-read symbols in the game.

## Animation inventory

Tag names must match the state names in `architecture.md` — Aseprite tags become Godot
animation names directly.

### Buddy — body (`art/src/bonehead_body.aseprite`)

| Tag | Frames | Notes |
|---|---|---|
| `idle` | 5 | Exists. Gentle bob |
| `idle_sad` | 4–6 | Low mood: slumped, slower |
| `idle_happy` | 4–6 | High mood: bouncy |
| `dragged` | 2–3 | Dangling from the cursor |
| `hurt` | 3–4 | Impact squash + recoil |
| `dizzy` | 4 | Post-heavy-hit stagger |
| `dance` | 8 | Boombox. The screenshot animation — spend real time here |
| `relax` | 4 | Hot tub, massage chair |
| `eat` | 4–6 | Pizza and snacks |
| `catch` | 3 | Baseball catch — the Interactive Buddy homage |
| `sleep` | 4 | Idle-too-long, and the hibernate state |
| `collapse` | 6–8 | Knockout: folds into the pile |
| `pile` | 2–3 | Bone-pile idle, faint settling |
| `reassemble` | 8–10 | Springs back together. Must feel *good* — it's seen constantly |

### Buddy — face (`bonehead_face.aseprite`, layered separately)

Neutral, happy, blissful, sad, crying, angry, shocked, dizzy (spiral eyes), asleep, smug.
Layering the face separately means mood reads independently of body pose, which multiplies the
expression set for very little work.

### Overlays

Grime/dirt (3 escalating stages, cleared by the sponge), soot after explosions, sparkle after
cleaning, a small mood aura.

### Items

Each: one 64×64 idle sprite, one 32×32 UI icon, plus per-item extras (muzzle flash, projectile,
impact). Generate the whole family from one reference image so they read as a set.

### VFX

Impact stars, bone chips, dust puffs, explosion (replacing the prototype's untextured
`CPUParticles2D`), sparkle, heart burst, coin/bone burst for the knockout fountain.

**All VFX must be visible on white, on black, and on a busy photo.** Test on all three before
accepting one — this is the single most common way an overlay game's effects fail.

## UI

- Chunky, tactile, high-contrast panels with clear borders — they sit over arbitrary desktop
  content and must read as *chrome*, not as part of the wallpaper.
- **Opaque panels**, not translucent. Legibility beats prettiness when the background is
  unknowable.
- 9-slice panel textures, pixel-perfect at 2×.
- A real pixel font (the prototype uses the engine default everywhere). Pick one that supports
  Simplified Chinese, Japanese and Korean, or plan a separate CJK fallback font in the `Theme` —
  those languages are planned for launch and the wrong font choice discovers that late.
- Every number that goes up needs a tween and a colour pop. In an incremental game the number
  *is* the feedback.
- Damage numbers: white and small by default (they appear constantly and must stay readable),
  colour-coded per damage type, big and bold only for genuinely significant hits. Cap the number
  on screen at once and merge rapid hits into a running combo total.

## Sound

No audio exists yet — this is greenfield, and it matters more here than in most games because
the game is *running all day*.

- Layer 2–3 samples per impact (transient + body + tail).
- **Randomise pitch ±10–15% on every play.** Non-negotiable: an unvaried sample heard a thousand
  times in one workday becomes torture.
- Material-specific impacts: bone, metal, wood, wet, soft.
- Voice cap ~8 simultaneous, with a limiter — an automation cascade must never machine-gun
  someone's headphones during a meeting.
- Default volume low. Ship **mute-when-unfocused** as a default-on option.
- Signature sounds worth getting right: the bone-pile clatter on collapse, the rattle on
  reassembly, and the coin fountain. Those three play more than anything else in the game.
