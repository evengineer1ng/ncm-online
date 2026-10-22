---
title: Race Week
description: NCM Online runs in Race Weeks: multi-day runs with a social curve, speed limits, championships crowned at the end, a hall of champions and a reset.
---

# Race Week

{{status:live}} the Race Week clock, chapters, championships and rollover &nbsp; {{status:experimental}} the full
end-of-week reset of money and cars

Night City's racing comes in **Race Weeks**: runs that usually last about three days and then roll over into the next.
Each run is a season in miniature. You choose who to drive for, you race for a championship crowned at the end, the
names of the champions are kept permanently, and the city resets.

## The run

- **Length.** A run usually ends after about three days (72 hours). Its end can be pushed back by what happens during
  it, but never past Day 7. The boundary is 12:00 US Eastern time.
- **Chapters.** The HUD names the official chapter of the run (opening day, racing continues, the final day...). It
  never shows the city's mood directly.
- **The city reacts.** Underneath the chapters is a continuous social-pressure curve: a baseline that the run itself
  perturbs. A run with more crashes and more speeding than usual pushes the city's tolerance down sooner.
- **Advertised speed limits.** Race organisers post speed limits for everyone, NPCs included. They step up and down
  across the run. Police response is proportional to how far over the limit you are.

## Championships

- **The championship is the run.** Series such as the Badlands Cup, the MaiMai Cup, Night City Premier and GT
  are crowned at the end of the run.
- **Finales** before the end score double points.
- **The crown** can go to an NPC or a human, and the champions go into a permanent **hall of champions** that
  survives every reset.

## Damage through the week

Your car keeps its damage for the whole run, so crashes are costly. You can pay a shop or do the work yourself (see
[Engineering](engineering.md)). At the next run the surviving car comes back at full health.

## The rollover and the reset

At the end of a run, every player sees the **rewind**: a shared freeze, and the run collapses. Every machine goes
back to Night City, and the Paddock restarts from its historical seed, so the NPC league replays its history and
your choices are what change it.

The **reset of player property** is the part still being switched on. As designed for Online:

- **One car survives**: the one you anchor in Machine Index, or your most recently driven car if you choose none.
  Progression kept as physical property has to be fitted to that car or carried in its trunk. Second cars and loose
  possessions do not follow.
- **Wallets reopen at €$10,000.**
- **Knowledge and observations** you have collected generally persist. The hall of champions always does.

Until 2026-10-12 every reset ran as a **dry run**: it computed what it would close and changed nothing. The live reset
has been switched on, but its first real execution is waiting on a server maintenance step. Treat it as
{{status:experimental}} until the changelog says it has run.

Separately, **all alpha progression is temporary** and resets for NCM 1.0.

## On the radio

**Race Week Live** is an in-game station in the game's own radio list: a talk-radio show about the week, aired from
what actually happened. See [Broadcast & Race Week Radio](broadcast.md).

## For developers

- Clock, curve and verdicts: `ncm/core/week/*` (`week.clock`, `week.curve`, `week.collapse`), hosted by
  `ncm/online/resources/ncm_world/server/week.lua`.
- Championships, finales and the hall: `ncm_paddock/server/week.lua`. The collapse: `ncm_league/server/collapse.lua`.
- Design: `docs/ncm-online/45_RACING_WEEK.md` (proposal, with the owner's sixteen hard rules) and DECISION_RECORD
  L300-L310, L349, L362 and L369, which supersede parts of it. **Where the two disagree, the decision record and the
  code win.**
