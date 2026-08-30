# Ideas Backlog

Unfiltered idea pool. Nothing here is committed — `game-design.md` holds what's actually planned.
Ideas graduate from this file into that one. Ranked roughly by "would this make a six-second
video", because in this genre that's the marketing engine.

---

## Mechanics only this game can do

These exploit the fact that it's a real OS window on a real desktop. Everything else in the idle
genre is a rectangle full of buttons; this is the moat.

1. **Window Collision Physics** ⭐ — enumerate real OS window rectangles and feed them to the
   physics world as static colliders. Bonehead lands on your Chrome window, slides down your Slack
   sidebar, gets crushed between two windows when you snap them. *No competitor does this.* Gate
   it behind a mid-game unlock ("Occupational Hazard") so it lands as a revelation rather than a
   default. Needs Win32 `EnumWindows` via GDExtension.
2. **Window Snap Guillotine** — detect a real window resize/snap happening across him and pay a
   huge "Workplace Accident" bonus. Turns your actual work into a weapon.
3. **Taskbar Slam** — the taskbar is the floor by default (free, via `screen_get_usable_rect`).
   A "Taskbar Piledriver" augment pays a multiplier on taskbar impacts. He can hang off its edge,
   be dragged along it, or launch off the Start button like a ramp.
4. **Cursor Chase / Union Rep** — he scampers toward your cursor when idle and gets in the way.
   The "Union Rep" augment pays passive Hearts proportional to your real typing speed, so he's
   *paid to be annoying*. Ties income to the work you're actually doing.
5. **Notification Interception** — when a Windows toast appears he can be thrown at it, stand on
   it, or (with an upgrade) eat it for cash. Visual mimicry is enough; no API hooks needed.
6. **Screen-Edge Cannon** — fling him off the left edge and he wraps in from the right at speed.
   Multi-monitor variant: he travels *between* monitors for a "Frequent Flyer" bonus.
7. **Wallpaper Sampling** — sample the user's wallpaper colours and tint particles to match. Also
   a camouflage cosmetic. Cheap, delightful, screenshot-friendly.
8. **Streamer Mode / Chat Buddy** — Twitch viewers spend channel points to drop an anvil on him.
   Solves the genre's "Just Chatting" attribution problem by giving streamers a reason to tag the
   game.
9. **Dual-monitor tug-of-war** — with two buddies on two monitors, they throw things at each other
   across the gap.
10. **Clipboard Gag** — he occasionally "reads" your clipboard and reacts with an expression. Purely
    local, never transmitted, and it should probably be off by default — but the *reaction* to
    copying a URL versus copying code is a great bit. Flag: privacy-sensitive, needs care.

## Working-life mechanics

11. **Working Hours bonus** — sustained keyboard/mouse activity in *other* apps ramps an "On The
    Clock" multiplier over 25 minutes and resets after 5 idle minutes. Explicitly rewards you for
    actually working. Add Pomodoro: he dances at the end of a focus block.
12. **Overtime Pay** — between 9am–5pm local time automation runs normally; after hours it pays
    1.5× "overtime" but his mood decays faster. Real-clock strategy for a genuinely idle game.
13. **Sleep Cycle & Dream Journal** — closing the game puts him to sleep; on return, an absurd
    randomised dream grants a small buff. Turns the offline-collection screen into a joke.
14. **Occlusion "hazard pay"** — when a fullscreen app covers him he hides, rendering stops (CPU
    saved) and income accrues at a reduced rate. A technical necessity dressed as a mechanic.
15. **Lunch Break** — leave him alone for a while and he makes himself a sandwich. Passive Hearts,
    zero interaction, purely charming.

## Economy & emotional mechanics

16. **Loyalty / Stockholm meter** — a slow long-term stat that rises only when you *alternate*
    cruelty and kindness. High loyalty unlocks the automation tier: "he now hits himself for you,
    and he's happy about it." The narrative justification for the entire automation layer.
17. **Grime economy** — explosions leave him sooty; grime suppresses Bones income until you sponge
    him. Makes hygiene mechanically load-bearing rather than decorative. *(Promoted to the spec.)*
18. **Bone collection** — heavy hits scatter bones across the desktop; collect them for a bonus or
    leave them and he limps at reduced income. Missing bones can be *replaced* with upgrade parts
    — steel femur, spring spine, rocket pelvis — a diegetic augment system. *(Deferred: needs the
    ragdoll that D4 cut. Could return as collectible props.)*
19. **Insurance Fraud** — after a knockout he files a claim. Small passive payout, escalating
    premiums, and eventually an investigator prop shows up.
20. **Mood contagion** — two buddies affect each other's mood. A happy one cheers up a sad one.

## Weapon & item brainstorm (beyond the committed catalog)

Categories borrowed from Kick the Buddy's taxonomy, which is proven at scale.

**Melee** — golf club, crowbar, tennis racket, rolling pin, rubber chicken (0 damage, huge
Hearts), fly swatter, boxing glove on a spring, wet noodle (joke tier-0), giant novelty hammer.

**Firearms & cursor powers** — nail gun, paintball gun (leaves colour, no damage — cosmetic
graffiti), potato cannon, T-shirt cannon, laser pointer (he chases it — Hearts, not damage),
freeze ray, shrink ray, tractor beam, disco ball.

**Explosives** — party popper, whoopee cushion (0 damage, all Hearts), C4 with a detonator prop,
barrel of pickles, cartoon bomb with a fuse you can pinch out, glitter bomb.

**Nature & weather** — lightning (committed), rain cloud that follows him, tiny tornado, swarm of
bees, a single very determined pigeon, snow (he builds a snowman), sunbeam.

**Appliances & office** — desk fan (committed), stapler, paper shredder, microwave, toaster,
office chair he can spin on, printer that jams and he has to fix, vending machine.

**Food** — pizza (committed), birthday cake, hot sauce, ice cream (melts, needs eating fast),
coffee (temporary speed buff — he vibrates), an entire watermelon.

**Comfort & spa** — hot tub, massage chair, chocolate fountain (all committed), plus: hammock,
weighted blanket, aromatherapy diffuser, tiny bed, a cat that sits on him, bubble machine,
a very good chair.

**Toys** — beach ball, bowling ball, trampoline (committed), plus: yo-yo, skateboard, pogo stick,
bubble wrap, a swing, roller skates, remote-control car, kite.

**Absurd tier (late game, high cost, high video-potential)** — anvil from off-screen, grand piano,
a whale, a small meteor, gravity inversion, a black hole, a second Bonehead, a mirror (he meets
himself), the cursor itself becomes a weapon, an actual Windows error dialog that falls on him.

**Automation devices** (capstone rewards, each a visible desktop object) — sentry bat on a tripod,
clockwork punching arm, self-stirring chocolate fountain, roomba that bumps him, a metronome that
paces the spa, a tiny conveyor belt, a wind-up masseur, an autonomous sponge on a stick.

## Cosmetics

Party hat, hard hat, top hat, cowboy hat, chef's hat, crown, halo, tiny bow tie, sunglasses,
monocle, scarf, cape, jetpack (cosmetic only), Golden Bonehead, Neon Bonehead, Glass Bonehead
(you can see through him), Cardboard-Box Disguise, seasonal skins, and — the obvious one, since
he already wears them — **alternate headphones**: gold, gaming-RGB, tiny earbuds, one broken side.

## Achievements worth writing now

*Bring Your Buddy To Work Day* (open 8 hours straight) · *Pacifist Run* (earn 10k Hearts before
your first Bone) · *Occupational Hazard* (100 taskbar impacts) · *Catch!* (50 consecutive baseball
catches) · *Emotionally Complex* (swing mood from −90 to +90 inside a minute) · *Do Not Disturb*
(complete a Pomodoro block without touching him) · *Spring Cleaning* (sponge him 100 times) ·
*It's Not You, It's Me* (first Reincarnation) · *Frequent Flyer* (send him to another monitor).

## The arcade (committed to a future milestone — docs/decisions.md D32)

Played with Dollars, the cosmetics currency, so a losing streak costs a hat and never a run.

- **Spin the wheel.** One spin, a ring of segments, a possible bonus. Cheapest of the three to
  build and the fastest to read; the one to ship first if only one ships.
- **Slot machine.** Three reels of item icons — a bat, a heart, a bone, an ectoplasm blob — with
  the roster's own art doing the work. Wants a lever he can be made to pull.
- **Blackjack.** The only one with real rules, and therefore the only one that is a *game* rather
  than a pull; also the only one whose UI is a full page of its own.

Open in D32: whether a prize may be a timed income buff (recommended, bounded, through the shared
temporary-multiplier slot) or must stay purely cosmetic.

Ideas that follow naturally once Dollars exist: a vending machine on the desk as the arcade's
front end; a daily free spin as a second return hook beside the contract board; **wagering a
cosmetic** rather than currency, which is the only version of "high stakes" this game can offer
without touching the income loop.

## Deliberately rejected

- **Gore / blood mode.** Rejected: costs the unrestricted rating and the streaming audience for a
  joke that isn't the game's joke. He's a skeleton; bloodlessness is free.
- **Free-to-play with ads or gacha.** Rejected: the genre's premium buyers punish it, and the
  comparable free desktop pet with 194k peak concurrent users makes essentially no money.
- **A traditional main menu.** Rejected in D6 — it wastes the best first impression the genre has.
- **Simulated dismemberment.** Deferred by D4 — weeks of physics tuning for a result that's harder
  to make expressive than animation.
