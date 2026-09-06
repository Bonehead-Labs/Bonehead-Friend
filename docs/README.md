# Bonehead Friend — Documentation

Production spec for **Bonehead Friend**, a Windows desktop-overlay idle game.

> **One-line pitch:** A skeleton lives on your desktop while you work. Hurt him for Bones,
> be kind to him for Hearts, and spend both on an ever-growing arsenal of toys that
> eventually run themselves.

## Index

| Doc | What's in it |
|---|---|
| [game-design.md](game-design.md) | Vision, pillars, core loop, all mechanics, full item catalog, cosmetics, post-1.0 shelf |
| [economy.md](economy.md) | Every formula: payouts, cost curves, mastery, prestige, offline earnings, tuning targets |
| [architecture.md](architecture.md) | Autoloads, EventBus contract, data model, scene tree, combat pipeline, buddy state machine |
| [overlay-tech.md](overlay-tech.md) | Window flags, click-through, multi-monitor, performance budget, DWM risk |
| [art-pipeline.md](art-pipeline.md) | Retro Diffusion → Aseprite → Godot workflow and setup |
| [art-direction.md](art-direction.md) | Style, palette, sprite sizing, animation inventory |
| [ideas-backlog.md](ideas-backlog.md) | Uncommitted idea pool: mechanics, ~100 item ideas, cosmetics, achievements, rejected ideas |
| [roadmap.md](roadmap.md) | Milestones M0–M5 with exit gates and per-milestone art needs |
| [uplift-m3.5.md](uplift-m3.5.md) | The M3.5 content & systems uplift: loop-depth findings, content budget, sub-milestones and gates |
| [assessment-2026-09.md](assessment-2026-09.md) | Holistic assessment after M3.7: code, balance, visuals, genre feel, ranked with a five-step sequence |
| [worklist-2026-09.md](worklist-2026-09.md) | **The working list.** Every M3.8 task with status, order, exact next steps, commit plan and owner decisions — start here in a new session |
| [plan-expressive-buddy.md](plan-expressive-buddy.md) | The reactive, expressive buddy: reaction tables, the expression brain, animation set, phasing (Phases 0–1 built; D36) |
| [test-matrix.md](test-matrix.md) | Manual overlay test matrix + automated test strategy |
| [decisions.md](decisions.md) | ADR-lite: what was decided, when, and why |
| [research/](research/) | Source research: prototype survey, market/design digest, pipeline findings |

## Status

**M3 — systems complete, art in progress.** The full loop runs: hit and be kind for two
currencies, mood on a U-curve, grime, a knockout beat, mastery and a shared pool, automation
capstones, a contract board and Reincarnation with five personalities, across a 16-item
roster. Bonehead is animated (nine body tags, ten expressions). 414 assertions across three
suites; save schema v3.

What is left in M3 is the rest of the art — item sprites and icons, the `Theme` and font,
VFX, real audio — and the two playtests that are its gate. See `roadmap.md`, which carries
the current handoff list.

## The thesis

Interactive Buddy (2005) already contained the seed of an idle game and nobody harvested it:
it paid you for **kindness as well as cruelty** (the happiness meter, the baseball-catch
trick), and several of its tools kept firing after you clicked away — an accidental AFK
income exploit players used on purpose. It had no long tail: ~25 items, a flat $15–$400 price
ladder, and a 45–90 minute lifespan.

Bonehead Friend is that game with twenty years of incremental-game design applied to it, and
a desktop it can actually live on.
