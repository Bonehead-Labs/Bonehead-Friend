# Research — Market & Design Digest

Compiled 2026-08-28. Source research behind `game-design.md` and `economy.md`. Figures are as
of August 2026.

---

## Interactive Buddy (Shock Value, Newgrounds, 2005)

Four purchasable tabs — Explosives, God Powers, Objects, Hand — plus Modes and Skins. Free
starter kit: Open Hand, Tickle, Fist, Grenade.

**Price ladder (fan-wiki sourced, ~90% confidence on individual figures; the *shape* is the
point):** Wide Nozzle Hose $15 · Narrow Hose $20 · Gravity Vortex $30 · Fireballs, Bowling
Balls, Medieval Flail $40 · Molotov, Pistol, Explode-At-Mouse, Fire Hose $60 · Mines $80 · Stun
Gun $85 · Shotgun, Missiles, Flamethrower $100 · Machine Gun $140 · Gravity Shifter $240.
Modes: Low Gravity $20, NES Movement $20, Realistic Pyrotechnics $40, Blood and Gore $40,
Alternate Body Physics $40, Earthquake $40, Dynamic Camera $40, **Scripting Engine Access $400**.

**The key economic observation:** the entire game spans $15→$400 — a 27× range across ~25
one-time SKUs, with *no exponential curve at all*. A full playthrough is 45–90 minutes. **It has
no long tail.** That is the single biggest thing a 2026 paid product must change.

**How money was earned — the under-documented part.** Both channels paid:
- *Damage*: cash proportional to impact force. "The crazier the action, the more cash."
- *Pleasure*: the Buddy had a **mood meter**. Tickling, petting, hosing him down, and famously
  throwing **baseballs for him to catch without moving** produced steady income. The Fire Hose
  in a corner generated funds *while raising* happiness.
- *Proto-idle*: several tools kept firing after you clicked away from the Flash box — an AFK
  income exploit players used deliberately.

**Interactive Buddy already contained the seed of an idle game. Nobody harvested it.**

**Why it worked:** ragdoll unpredictability (novel in 2005, each hit readable and funny);
dual-valence interaction (cruelty *and* kindness both mechanically valid — the emotional hook
people still remember); toybox permission structure (no fail state, no timer); emergent
combinatorics (Gravity Shifter + mine + magic ball = player-invented content); and the $400
Scripting Engine as an in-game modding layer that spawned a fan-script ecosystem.

**Sequel:** Interactive Buddy 2 shipped on iOS in Dec 2012, delisted, now lost-media-adjacent.

## Kick the Buddy (Playgendary, 2017+) — the commercial descendant

**100M+ downloads.** 20+ categories, 150+ weapons: Firearms · Cold Weapons · Explosives ·
Objects · Music · Foods · Liquids · Appliances · Bio Weapons · Machines/Traps · Animals ·
Power of Gods · Horror · Tools · Plants · themed sets.

**The structural lift worth stealing:** tap → **damage meter fills** → meter full = Buddy
knocked down = **coin payout scaled to damage dealt** → meter resets. A *round structure*
Interactive Buddy never had, and it's what converts a sandbox into a progression game.

Also worth stealing: the category taxonomy, and cosmetics/decorations as the deep coin sink
(rooms cost 35,000–78,000 coins).

**Reject:** dual premium currency, gacha, rewarded-ad gates, VIP membership. A one-time-purchase
Steam title with free-to-play residue gets punished in reviews — and this game's vocabulary
(shops, currencies, unlocks) will already *look* free-to-play, so "no microtransactions, no ads"
needs saying explicitly on the store page.

---

## Idle/incremental maths

### Cost curves — `cost_next = base × r^owned`

| Game | r |
|---|---|
| AdVenture Capitalist | 1.07–1.15 (varies per business) |
| Clicker Heroes | 1.07 uniform |
| Cookie Clicker | 1.15 uniform |
| Idle Idol (postmortem) | 1.1–1.19 |

The 1.07–1.15 band is industry consensus — the same multipliers recurring across unrelated games
suggests that range is where the curve feels right. Lower r = many small purchases; higher r =
each purchase is an event.

Bulk purchase: `cost = b · rᵏ(rⁿ−1)/(r−1)`. Max affordable:
`⌊log_r(c(r−1)/(b·rᵏ) + 1)⌋`. Implement both from day one.

### Prestige formulas

| Game | Formula | Doubling requires |
|---|---|---|
| Realm Grinder | `(√(1 + 8c/10¹²) − 1)/2` | 4× |
| AdVenture Capitalist | `150√(c/10¹⁵)` | ~3–4× |
| **Cookie Clicker** | **`∛(c/10¹²)`, +1% CpS each** | **8×** ← chosen |
| Egg, Inc. | `(c/10⁶)^0.14`, run-based, +10% each | 128× |

Lifetime-based (Cookie Clicker, AdCap) pushes players to go further each run; run-based (Egg Inc)
rewards active play but needs a very flat exponent to resist exploitation.

### Pacing

- **0–30 min:** immediate gratification, generous, no friction. Progressive disclosure — grey out
  locked systems, don't show the skill tree at minute one.
- Target **~60% idle / 40% active** progress split.
- Offline earnings must exist and must be **capped** — the cap creates the "lost opportunity"
  feeling that drives return visits. Standard: 2h free → 8h → 24h purchased.
- First prestige after ~60–70% of first-run content; early resets 5–15 min, later 30–60 min.
- Stagger milestone thresholds (25/50/100/200/…) so progression is bumpy, and never let a new
  tier permanently obsolete an old one.
- Mobile retention benchmarks, directionally useful: D1 35–40%, D7 10–15%, D30 5–10%.

### Structural references

- **Melvor Idle — Mastery.** A second level track per *item* within a skill, plus a shared
  **Mastery Pool** whose checkpoint bonuses apply skill-wide, so spread-out mastery is never
  wasted. The original system was reworked because progression felt "sub-par". This is the direct
  model for per-weapon mastery.
- **Leaf Blower Revolution.** Each currency *type* unlocks its own upgrade tree; constant drip of
  new *features* rather than just bigger numbers; five years of QoL/automation updates is what
  retained the audience.
- **Cookie Clicker.** $4.99, 96% of 92,882 reviews. Achievements → milk → passive multiplier is a
  *third* progression axis parallel to prestige.
- **AdVenture Capitalist.** Managers-as-automation is the genre's most famous dopamine beat.
- **NGU Idle.** Aggressive diminishing returns on every stat, forcing breadth over depth.

---

## Rusty's Retirement (2024) — the direct precedent

The most relevant commercial data point in existence for this project: a desktop-overlay idle
farming game that sits at the edge of your screen while you work.

**Numbers:** $7, launched 26 Apr 2024, solo dev, originally a **two-week prototype**. ~140,000
wishlists at launch → **100k sales in 5 days**, ~330k by Aug 2024, **550k by July 2025**. Net
~$5/unit → ~$1.65M net at 330k. Supporter Pack DLC at $4 with **11% attach** (+$111k). Steam
**97% positive of 6,568**, 71 achievements, trading cards, cloud saves. Tail of ~300 units/day
four months post-launch with no promotion.

**Asia = 46% of sales** (China 26%, Japan 10%, Korea 6%, Taiwan 4%), with **11 languages at
launch.** This is the highest-leverage single lesson in the digest.

**Pricing rationale:** median idler $0–5, median farming sim $10–15 → chose $7 to sit between the
two genres. (Our analogue: median idler $0–5, median physics-comedy indie $10–15 → $6.99–8.99.)

**Design principles that worked:** core reduced to two verbs ("planting seeds, and placing things
which automate the farming process"); explicit dual audience ("cater to both the casual farming
sim player and the strategic idler fan who wants to min/max"); horizontal *and* vertical screen
modes as an option; **customisable input frequency** — how often the game demands attention is a
setting.

**Marketing:** Twitter + Instagram Reels cross-posted to TikTok. The desktop-overlay concept is
*itself* the visual hook — a clip of a game living on someone's real desktop is inherently
shareable. Launched 3 days ahead of Steam's Farming Fest.

**The streaming gotcha:** most Twitch streams were categorised **"Just Chatting"**, because
streamers were working with it on screen. Discovery attribution is invisible; Rusty's added Twitch
integration in response.

**Complaints — our pre-written bug backlog:**
- **DWM CPU spiking to ~20%**, occasionally driving 100% total. Transparent always-on-top windows
  are composited every frame. **The #1 technical risk of the genre.**
- High-resolution monitors hugely amplify resource use.
- **VSync on reduced CPU 2–3×.** They shipped a "Low Power Mode" button.
- Multi-monitor: wrong-monitor placement, zoom corruption after sleep/wake, finicky monitor
  dropdown.
- The existential one: *"having the game open while doing other tasks makes doing other things
  bogged down — which is problematic since the entire point is to have it open while doing other
  things."*

---

## Desktop pet / overlay market

| Game | Price | Reviews | Notes |
|---|---|---|---|
| Bongo Cat (2025) | Free | 97% of 109,585; **peak 194,500 CCU** | Gamified Pomodoro, reacts to input, tradable loot. **Dev says it makes essentially no money.** |
| VPet-Simulator (2023) | Free | 98% of 51,725 | Modding-heavy |
| **Rusty's Retirement** | **$7** | 97% of 6,568 | See above |
| Chillquarium (2023) | $5.99 | 93% of 5,259; 200k–500k owners | Idle aquarium |
| Ropuka's Idle Island (2025) | $3.99 | 95% of 3,965 | "A playable sticker for your desktop" |
| Tiny Pasture | $4.99 | 93% of 1,432 | Resizable desktop region |
| Weyrdlets 2.0 (2024) | ~$7 | — | Pomodoro + tasks; 5 DLC packs |
| Desktop Cat Cafe (2025) | **$9.99** | **76%** of 82 | The outlier: highest price, lowest score |

**Price band: $3.99–$7.99 is the genre's home; $9.99 is where scores start dropping.** Free
desktop pets are a marketing channel, not a business (see Bongo Cat).

**Steam tags to target:** Idler, Clicker, Incremental, Casual, Singleplayer, Physics, Sandbox,
Ragdoll, Comedy, 2D, Cute, Relaxing, Funny, Destruction, Automation, Pixel Graphics. "Desktop pet"
is not a tag — it's a description phrase, so put **"sits on your desktop while you work"** in the
first line of the short description.

**Praised:** low-maintenance presence, "visually engaging without demanding attention", art that
survives being stared at for 8 hours, productivity integration, achievements, genuinely low CPU.

**Complained about:** CPU/GPU cost, multi-monitor bugs, click-through gaps, fullscreen-game
conflicts, OBS capture confusion, taskbar behaviour (genre convention is hide-from-taskbar +
system tray).

**Shimeji / Desktop Goose — the mischief axis.** Shimeji mascots climb window edges, walk along
the bottom of the screen, grab and nudge browser windows, throw windows around, and multiply.
Desktop Goose drags images onto your desktop and steals your cursor. **Real OS windows as physics
colliders is the genre-defining mechanic neither Rusty's nor Chillquarium exploits** — the biggest
untapped idea available, and a perfect fit for a ragdoll.

---

## Juice, with overlay caveats

**Standard toolkit:** hit-stop 3–5 frames on impact (2 light, 6–8 heavy, 12+ on a kill); squash
and stretch with 60–100 ms recovery; particles erupting *along the strike vector*; damage numbers
white and small by default with colour coding by type and big-bold reserved for significant hits;
2–3 layered samples per impact with **±10–15% pitch randomisation**; anticipation before the swing.

**Overlay-specific — the novel part:**
- **You cannot screen-shake.** There is no screen; it's the user's spreadsheet. Shaking a
  transparent window is nauseating and makes its rect flicker against real windows. Substitutes:
  shake only the *contents* within a fixed window rect; reserve actual window-body shake for the
  rare maximal event (≤200 ms, ≤8 px, toggleable — it reads as "the game escaped the frame" and is
  genuinely novel *because* it's a real OS window); radial impact rings for spatial impact without
  motion.
- **Everything must read against an unknown background.** Dark particles vanish on dark IDEs.
  Every effect needs an outline or dual-tone. Test on pure white, pure black, and a busy photo.
- **Peripheral-vision rule.** The user is working; motion in peripheral vision is inherently
  distracting. An intensity slider (Off/Subtle/Normal/Chaos) framed as "Focus Mode" will be quoted
  in reviews as a feature.
- **Audio must be background-safe:** low default volume, limiter, voice cap ~8, mute-when-unfocused.
- **The kill beat.** A skeleton's knockout is a *collapse into a pile of bones* — gore-free,
  endlessly repeatable, great sound. This is the damage-meter round, free of tone problems.

**Rating:** Steam's Mature Content Survey asks you to *contextualise* violence; comedic/ragdoll
presentation rates lower than realistic depiction. Building gore-free is diegetically justified by
the protagonist being a skeleton, and buys an unrestricted rating, no regional storefront problems,
and a wider streaming audience.

---

## Release

**Wishlists:** Next Fest typically yields 1,000–15,000 wishlists, median 3,000–5,000 — roughly
**doubling what you already have**, so build the audience *before* the festival. Demo→wishlist
conversion is 10–20%, but **68–88% of wishlists come from people who never downloaded the demo** —
**capsule art quality correlates with conversion more than demo length or feature completeness.**
Wishlist→buyer runs 10–25% within three months.

**Scope for a realistic solo 1.0:** ~20–28 items (not 150 — Interactive Buddy shipped ~25 and is
beloved), ~8 friendly items as the differentiator, 3–4 augment nodes per weapon (~80–100 mostly-
numeric nodes, cheap content), one prestige layer at 1.0 with the second designed and shipped as
the month-3 update, 40–70 achievements, 10–15 cosmetic skins. **Cut for 1.0:** multiplayer,
Workshop/modding, scripting engine, macOS/Linux.

**Marketing hook:** a six-second vertical video of a skeleton getting launched across someone's
actual Windows desktop, bouncing off their Chrome window, landing in the taskbar. Record on a
realistic, messy, relatable desktop — not a clean one.

---

## Sources

Interactive Buddy: [Wikigrounds](https://newgrounds.miraheze.org/wiki/Interactive_Buddy) ·
[Flash Gaming Wiki](https://flashgaming.fandom.com/wiki/Interactive_Buddy) ·
[weapons/items](https://oofy.fandom.com/wiki/Interactive_Buddy_Wiki:Weapons_and_Items) ·
[modes](https://oofy.fandom.com/wiki/Modes) ·
[mechanics compendium](http://thehackerofgamesssssss.blogspot.com/p/interactive-buddy_5566.html) ·
[IB2 lost media](https://lostmediawiki.com/Interactive_Buddy_2_(found_iOS_sequel_to_%22Interactive_Buddy%22_simulation_game;_2012)) ·
[ragdoll retrospective](https://www.zleague.gg/theportal/gaming-news-remembering-interactive-buddy-and-its-revolutionary-ragdoll-physics/)

Kick the Buddy: [weapon list](https://kickthebuddy.fandom.com/wiki/List_of_Kick_The_Buddy_Weapons) ·
[categories](https://shapes.inc/fandom/kick-the-buddy/weapons-and-items) ·
[economy](https://www.crazygames.com/game/kick-the-buddy-yxa) ·
[Sensor Tower](https://sensortower.com/android/us/playgendary/app/kick-the-buddy/com.playgendary.kickthebuddy)

Idle maths: [Math of Idle Games I](https://www.gamedeveloper.com/design/the-math-of-idle-games-part-i) ·
[III — prestige](https://www.gamedeveloper.com/design/the-math-of-idle-games-part-iii) ·
[Numbers Getting Bigger](https://code.tutsplus.com/numbers-getting-bigger-the-design-and-math-of-incremental-games--cms-24023a) ·
[Cookie Clicker ascension](https://cookieclicker.wiki.gg/wiki/Ascension) ·
[Egg Inc prestige](https://egg-inc.fandom.com/wiki/Prestige) ·
[Melvor mastery](https://wiki.melvoridle.com/w/Mastery) ·
[Mind Studios](https://games.themindstudios.com/post/idle-clicker-game-design-and-monetization/) ·
[Machinations](https://machinations.io/articles/idle-games-and-how-to-design-them) ·
[Eric Guan](https://ericguan.substack.com/p/idle-game-design-principles)

Rusty's Retirement: [GameDiscoverCo](https://newsletter.gamediscover.co/p/how-rustys-retirement-idle-farmed) ·
[TechRaptor](https://techraptor.net/gaming/news/rustys-retirement-sales) ·
[Steam](https://store.steampowered.com/app/2666510/Rustys_Retirement/) ·
[CPU discussion](https://steamcommunity.com/app/2666510/discussions/0/4357871935587822053/) ·
[multi-monitor](https://steamcommunity.com/app/2666510/discussions/0/4357871761803208307/)

Market: [Steam250 incremental](https://steam250.com/tag/incremental) ·
[TheGamer desktop pets](https://www.thegamer.com/steam-best-desktop-pets/) ·
[Bongo Cat CCU](https://insider-gaming.com/what-is-bongo-cat-on-steam/) ·
[Bongo Cat revenue](https://www.gamespot.com/articles/viral-steam-hit-bongo-cat-doesnt-actually-make-any-money/1100-6532777/) ·
[Shimeji](https://shimejis.xyz/) · [Desktop Goose](https://samperson.itch.io/desktop-goose)

Godot overlay tech: [mouse passthrough](https://forum.godotengine.org/t/how-to-passthrough-mouse-to-desktop/66531) ·
[click-through tutorial](https://medium.com/@chewedgumah/godot-4-partially-clickthrough-window-with-transparent-background-3de637cdf95b) ·
[CTTW demo](https://atadenizoktay.itch.io/godot-cttw)

Juice & release: [damage numbers](https://www.gamejuice.co.uk/articles/damage-numbers-satisfying-feedback) ·
[juice in game design](https://www.bloodmooninteractive.com/articles/juice.html) ·
[Steamworks content survey](https://store.steampowered.com/news/group/4145017/view/3645136992391096608) ·
[ESRB guide](https://www.esrb.org/ratings-guide/) ·
[wishlist conversions](https://alineaanalytics.substack.com/p/wishlist-to-buyer-conversions-for) ·
[Next Fest analysis](https://alineaanalytics.substack.com/p/steam-next-fests-winners-and-why) ·
[wishlists to launch](https://presskit.gg/field-guides/how-many-wishlists-to-launch)
