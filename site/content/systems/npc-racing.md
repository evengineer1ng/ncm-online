---
title: NPC Racing & the Paddock
description: NCM's NPC league races on its own calendar whether or not anyone is online, fills human grids, and keeps teams, careers, money and news.
status: live
---

# NPC Racing & the Paddock

**A server showing 0 players does not mean nothing to do.** NCM's racing does not wait for another human to be online.

## What the Paddock is

The Paddock is a persistent world of NPC motorsport: teams, drivers, owners, managers and sponsors across several
tiers. In mid-October 2026 the Online Paddock held about 870 NPC drivers. It races on its own calendar, keeps its own
standings, signs and releases drivers, makes its own news and runs its own economy, whether or not any human is
online. You live beside it: race against it, read it, bet on it, or run a team inside it.

## Racing against NPCs

- **NPC racers fill empty grid places** around a race's start time, so a scheduled race has a field even when you are
  the only human.
- **Mixed grids are one field.** NPCs and humans qualify, grid and finish in the same order, under the same
  penalties.
- **NPC cars are real cars.** Each NPC race car is a serialized machine with an owner. It takes lasting damage, and
  its team has to fund repairs. A team that can't pay can miss a grid, and an independent driver who can't afford
  shop work is at a disadvantage.
- **NPC drivers drive physically** when a human is near. Near you, NPC cars are on the road, driven by the game's own
  racing AI along racing lines NCM bakes from the road network. Far from any player, the same race is resolved by
  the league's simulation, and that result is labelled *simulated*.
- **Pace is calibrated** against human times. PADDOCK → PACE DATA shows NPC times beside human ones.

## Watching and following it

F6 → **PADDOCK**:

| Tab | |
|---|---|
| TODAY | What's on now and what just happened |
| LIVE | Races on track right now |
| RACES | Upcoming races and results |
| STANDINGS | Season and Cup tables |
| TEAMS | Every team and where they work |
| NEWS | The Paddock wire |
| BILLIE'S BOARD | Positions on NPC races (see [Economy](economy.md)) |
| MY TEAM | Found or run a team |
| PACE DATA | NPC times against human times |

Every racer is on the map, `/ncm.names` labels NPC race cars, and `/ncm.tower` shows a timing tower for the Paddock
race you are near.

## Running a team

From **MY TEAM** you can found a team or take one on, sign drivers and make moves. You may manage only one team.
Scouting reports describe drivers in words, from their simulated careers, so a good signing is distinguishable from
a bad one. A manager can take a move back.

## Paddock people in the city

Paddock people work at rented, shared garages and keep daily routines around Night City. Walk up to one and **Talk**
for a line grounded in their real situation: their next race, their last result, the weather, their mood.

## Limits

- The NPC driver is the game's own racer AI on NCM-baked splines. It can be slower or clumsier than a good human in
  places, and some routes are withheld while their splines are rebuilt.
- A result resolved by simulation is marked as simulated; it was not driven.
- Talking to Paddock people gives one line, not a conversation. Spoken conversation is [planned](../roadmap.md).

## For developers

- Server: `ncm/online/resources/ncm_paddock/server/` (world, races, garages, days, Billie, markets, exchange, story).
- Pure model: `ncm/core/paddock/*` (world genesis, attributes, race sim, tape) and `ncm/core/life/*` (schedules,
  district climate, voice).
- The native race-pace helper: `ncm/pace/` (RED4ext).
- Authority: `docs/ncm-online/44_THE_PADDOCK.md` and DECISION_RECORD L224-L305.
