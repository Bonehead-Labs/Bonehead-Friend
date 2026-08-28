# Game Design

## Vision

A skeleton lives in a transparent window on your desktop. He is there while you answer email.
You flick him, whack him with a bat, drop an anvil on him — and he pays you in **Bones**. You
also sponge him clean, feed him pizza and run him a hot tub — and he pays you in **Hearts**.
Bones buy weapons. Hearts buy kindness *and every piece of automation in the game*, so the
only way to stop working for your money is to be nice to him.

Over hours he accumulates an arsenal, a skill tree, a mood, a personality, and eventually the
ability to beat himself up while you're in a meeting.

## Pillars

1. **He is a toy, not a target.** No fail state, no timer, no score. Money is a pacing gate on
   new toys, exactly as in Interactive Buddy. Every purchase is a new *verb*, not a bigger number.
2. **Cruelty and kindness are both first-class.** The dual-valence loop is the emotional hook
   and the economic constraint. A player who only ever hits him hits a wall.
3. **It respects the desktop it lives on.** Under 3% CPU, click-through everywhere he isn't,
   a Focus Mode slider, mute-when-unfocused. The player is *working*; the game earns its place.
4. **Physics comedy over gore.** He is a skeleton: no blood, cartoon violence, clattering
   bones. Funny is the tone, and it keeps the store rating clean.
5. **Every session ends somewhere better than it started.** Offline earnings, contracts,
   milestone unlocks — closing the game is never a punishment.

## Core loop

```
     ┌─────────────────────────────────────────────────────────┐
     │                                                         │
  INTERACT ──► EARN (Bones / Hearts) ──► SPEND ──► NEW VERBS ──┘
     │              │                       │
     │              │                       ├─► Shop: one-time unlocks (toys)
     │              │                       ├─► Tree: augment levels (numbers)
     │              │                       └─► Capstones: AUTOMATION (idle income)
     │              │
     │              └─► MOOD swings ──► multiplies both payouts at the extremes
     │
     └─► damage meter fills ──► KNOCKOUT ──► payout fountain ──► reassemble
```

Long arc: `active play → automation → multipliers → soft wall → Reincarnation (prestige) →
content that only opens after prestige N`.

Target split is roughly **60% of progress from idle, 40% from active play** — the genre
consensus. Automation should always feel like it earns *well*, and active play like it earns
*better*.

## Currencies

| Currency | Earned by | Spends on |
|---|---|---|
| **Bones** 🦴 | Damage dealt (impact impulse), knockouts | Weapons, explosives, cursor powers, damage augments |
| **Hearts** 💗 | Kindness: petting, cleaning, feeding, music, spa, catching thrown baseballs | Friendly items, comfort furniture, **all automation capstones**, offline-cap upgrades |
| **Ectoplasm** 👻 | Prestige only (Reincarnation) | Permanent meta-upgrades, personality re-rolls, post-prestige content |

The Hearts-gates-automation rule is the design's spine. It forces every player through both
halves of the toy box, it makes the mood system matter mechanically rather than decoratively,
and it produces the game's best joke: *he is happy to hit himself for you.*

## Mechanics

### Mood seesaw

Bonehead has a mood from **−100 (despair)** to **+100 (bliss)**, decaying toward 0 over time.
Payout multiplier is a **U-curve**: highest at both extremes, worst in the middle.

- Consequence: optimal play *oscillates*. Beat him up, then comfort him, then beat him up again.
- It mechanises the comedy — the player's rhythm becomes the joke.
- Mood also drives his idle animation set (sobbing, neutral, dancing) so his state is readable
  at a glance from across the desktop.
- Curve is a `Curve` resource in `balance.tres` — tunable without code.

### Knockout round

Borrowed from Kick the Buddy, which converted the sandbox into a progression game by giving it
a *round structure* Interactive Buddy never had.

1. Damage fills a meter (visible as a subtle rib-cage fill, not a floating HP bar).
2. Meter full → **collapse**: he folds into a pile of bones with a clatter.
3. **Payout fountain** — coins burst out, scaled to total damage dealt that round, mood
   multiplier applied.
4. Pause, then **reassemble** with a rattle and a little shake-off animation.
5. Meter resets, escalating slightly (soft cap so knockout-farming isn't the only strategy).

Gore-free by construction. This is the game's climax beat and it is repeatable forever.

### Friendly interactions

The differentiator from every Kick-the-Buddy clone. Each has its own Hearts rate and mood curve:

- **Petting** (open hand) — small steady Hearts, big mood.
- **Sponge** — he gets visibly dirty over time (dust/soot from explosions); cleaning pays and
  resets the grime overlay. Grime also slightly reduces Bones income, so hygiene is economic.
- **Baseball catch** — throw one, he catches it without moving. A direct homage to Interactive
  Buddy's most-loved exploit, promoted to a real mechanic with a combo counter.
- **Pizza / snacks** — burst of Hearts, temporary happy buff.
- **Boombox** — passive Hearts while music plays; he dances (and dancing is his most
  screenshot-able animation).
- **Chocolate fountain / hot tub / massage chair** — furniture that generates Hearts on a timer
  once he's placed in it. These are the Hearts-side idle generators.

### Automation (capstones)

Automation is **not a shop tab**. Every weapon and every comfort item has an automation node at
the top of its own tree, bought with Hearts, unlocked by Mastery. Consequences:

- You must actively use a thing before you can automate it — a natural difficulty ramp.
- The idle-income curve grows organically with the roster.
- Each automation is a visible object on the desktop (a sentry bat on a tripod, a self-stirring
  chocolate fountain), so an idle desktop still looks alive.
- Every automation has an on/off toggle and a rate slider — required for the Focus Mode promise.

### Mastery

Per-item XP earned by *using* the item. Ranks 10/25/50 grant per-item bonuses **plus** points
into a shared **Mastery Pool** with checkpoint bonuses that apply across the whole roster —
Melvor's fix for "spreading mastery is wasted mastery". Answers the genre's oldest question:
*why would I ever use the shotgun once I own the rocket launcher?*

### Reincarnation (prestige)

Reset unlocks and currencies; keep **Ectoplasm** = ∛(lifetime earnings / 10¹²), each point
granting +1% to all income (Cookie Clicker's proven curve — doubling requires ~8× the run).

Each Reincarnation rolls Bonehead a new **personality** — Stoic, Masochist, Diva, Zen, Goth —
each with a different mood curve and a different optimal playstyle. Content variety out of a
single stat table, and a reason to prestige beyond the multiplier.

First prestige should land after roughly 60–70% of first-run content; early resets every
5–15 minutes, later ones 30–60.

### Contract board

A small desktop prop. Rotating daily/weekly objectives — "deal 10k damage with explosives",
"keep mood above 80 for 30 real minutes", "land 20 taskbar impacts", "catch 50 baseballs" —
paying Ectoplasm and cosmetics. This is the daily-return hook, replacing Kick the Buddy's
login bonus with something that doesn't smell like free-to-play.

### Offline earnings & the Dream Journal

Automation accrues while closed, **capped at 2 hours**, upgradeable with Hearts to 8h then 24h.
The cap is deliberate: uncapped offline income removes the reason to come back.

On return, a **Dream Journal** page shows what he dreamt about while you were gone — a
randomised absurd one-liner plus a small temporary buff. It turns the "collect your offline
money" screen into the day's first joke.

### Focus Mode

An intensity slider — **Off / Subtle / Normal / Chaos** — governing particle counts, flashes,
damage-number frequency and screen effects. Off makes him a quiet desktop pet that still earns.
This is a *feature*, not an accessibility afterthought: it's what makes an eight-hour session
possible, and it will get quoted in reviews.

## Item catalog (target ~24 at 1.0)

Prices are one-time and hand-authored — Interactive Buddy's flat $15→$400 ladder, not an
exponential curve. Exponential growth lives in the augment levels instead. Costs below are
first-draft ordering, to be tuned against `docs/economy.md`.

### Melee — Bones
| Item | Cost | Notes |
|---|---|---|
| Baseball Bat | free (starter) | The tutorial weapon |
| Frying Pan | 250 | Big flat *clang*, high knockback, low damage |
| Mace | 900 | Heavy, slow, satisfying |
| Katana | 3,500 | Fast, precise, multi-hit combo |

### Cursor powers — Bones
| Item | Cost | Notes |
|---|---|---|
| Fist | free (starter) | Punch at cursor |
| Pistol | 600 | Single shot |
| Shotgun | 2,200 | Spread; the exclusive-branch showcase (Buckshot / Slug / Beanbag) |
| Magnifying Glass | 4,000 | Sustained sunbeam, damage-over-time, sets him smoking |
| Minigun | 9,000 | Sustained fire, the "numbers go up" weapon |
| Gravity Vortex | 15,000 | Pulls him and every loose object into a spinning knot |
| Lightning | 40,000 | Strike at cursor; chains to nearby props |

### Explosives — Bones
| Item | Cost | Notes |
|---|---|---|
| Grenade | free (starter) | Timed throw |
| Dynamite | 800 | Bigger radius |
| Mine | 2,500 | Proximity trigger; combos with knockback weapons |
| Firework Rocket | 6,000 | Erratic flight, colourful, low damage, high comedy |

### Friendly — Hearts
| Item | Cost | Notes |
|---|---|---|
| Open Hand | free (starter) | Petting |
| Sponge | 40 | Cleans grime; grime suppresses Bones income |
| Baseball | 120 | Throw-and-catch, combo counter |
| Pizza | 400 | Instant Hearts + happy buff |
| Boombox | 1,200 | Passive Hearts while playing; he dances |
| Chocolate Fountain | 5,000 | Hearts generator on a timer |
| Hot Tub | 12,000 | Strong Hearts generator; he relaxes in it |
| Massage Chair | 30,000 | Top-tier Hearts generator |

### Toys & props — either currency
| Item | Cost | Notes |
|---|---|---|
| Beach Ball | 100 | Bouncy, he plays with it (Hearts) or you weaponise it |
| Bowling Ball | 700 | Heavy, rolls, knocks him flat |
| Trampoline | 1,800 | Launches him; enables trick payouts |
| Desk Fan | 3,000 | Constant wind — changes every projectile's arc |

Plus the existing **Trash Bin** (free, always present) for clearing spawned clutter, and the
**Contract Board** prop.

## Cosmetics

10–15 Bonehead skins and hats, bought with Hearts or earned from contracts: Party Hat, Hard
Hat, Top Hat, Cowboy, Chef, Golden Bonehead, Neon Bonehead, Cardboard-Box Disguise, Tiny Bow
Tie. Highest joy-per-development-hour in the whole design, and the natural content of a
post-launch supporter pack.

## Achievements

40–70 Steam achievements. Cheap retention, cheap store visibility. Mix of milestone
("earn 1M Bones"), stunt ("land him on the taskbar 100 times"), kindness ("keep mood above 90
for an hour") and joke ("leave the game open for a full 8-hour workday" — *Bring Your Buddy
To Work Day*).

## Post-1.0 shelf

Designed for now, built later. Seams are left in the architecture; none of it ships in 1.0.

1. **Occupational Hazard** — real OS window rectangles become physics colliders. He lands on
   your Chrome window, slides down your Slack sidebar, gets crushed when you snap two windows
   together. No competitor in the genre does this, and it is the single best marketing asset
   the game can have. Needs Win32 (`EnumWindows`) via GDExtension — spike early, ship as the
   flagship free update.
2. **Working Hours** — a multiplier that ramps while you're genuinely typing in *other* apps
   and decays when you stop, plus a Pomodoro layer where he celebrates at the end of a focus
   block. The strongest retention hook available to a game whose pitch is "keep it open".
3. **Twitch integration** — viewers spend channel points to drop an anvil on him. Solves the
   genre's discovery problem, where streams get categorised as "Just Chatting" because the
   game is background furniture.
4. **Bonehead's Workshop** — a visual node editor for player-built contraptions, plus Steam
   Workshop sharing. The homage to Interactive Buddy's $400 Scripting Engine, and the feature
   that gives the game a multi-year tail.
5. **Skeleton crew** — buy a second and third Bonehead; they collide with each other.

## Tone & rating

Cartoon violence, no blood, no gore. He's a skeleton, so bloodlessness is *diegetic* rather
than a compromise — the ideal protagonist for this genre. Target an unrestricted store rating
and a wide streaming audience. If a gore toggle is ever added it ships off by default,
declared in the Steamworks content survey, and is styled as obviously-fake confetti.

## Commercial shape (recommendation, revisit before store page)

One-time purchase around **$7.99**, no microtransactions, no ads, everything unlockable by
playing — and say so explicitly on the store page, because a game full of shops and currencies
will otherwise be mistaken for free-to-play. Optional cosmetic supporter pack (~$4) post-launch.
Windows-first. Ship with Simplified Chinese, Japanese and Korean: the closest comparable took
46% of its sales from Asia, and this game is nearly text-free, so localisation is cheap.
See `docs/research/market-and-design.md` for the comparables and the numbers behind this.
