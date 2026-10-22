---
title: Racing
description: How races work on NCM Online: finding, entering, qualifying, grids, the race, penalties, results and money.
status: live
---

# Racing

## For players

**Where races come from.** Organised races on NCM Online are Paddock races: the NPC league's own calendar, with
places for humans on mixed grids. They run on a schedule through Night City's streets, highways and authored ovals.
Each race has a discipline (point-to-point, circuit or oval), a route, a field size, an entry fee, a payout,
regulations about which cars may enter, and the weather at its start.

**The flow of a race:**

1. **Browse** the Race Guide (F6) or PADDOCK → RACES. Mark one *Interested* to track it and route to the venue.
2. **Enter** at the venue. The entry fee is charged then. Entry is open until shortly before the start.
3. **Qualify** at the venue if the event has a session. Qualifying helps set the grid order. Entering without setting
   a time is still an entry.
4. **Grid up.** Your slot is assigned; <kbd>F7</kbd> snaps you to it. Corrections are allowed until green, and the
   snap checks there is clearance. A driver who is not on the grid at green is DNS.
5. **Race.** <kbd>F8</kbd> toggles the live race graph. The on-screen running order is the real one.
6. **The flag.** Penalties (jump starts, incidents, cuts) are applied in a ceremony after the flag. NPCs are judged by
   the same rules as humans.
7. **Settlement.** Paid events write an itemised receipt: solo completion, contested placement and field bonuses are
   separate figures. Race Tags and a capped clean-driving bounty come from the facts of your run.

**Leaving a race:** *Withdraw* at the venue before it starts; *Forfeit* (`/ncm.forfeit`, confirm twice) after it
starts, recorded as a DNF.

**Ineligible?** Regulations can restrict an event to a class or a specific model (a MaiMai cup admits MaiMais).
Flying machines are never street cars: no ground race admits one unless its rules ask for it. The Race Guide shows
whether your car can enter before you travel.

**Other formats:**

- **Time trials:** a field of one against the clock, even with nobody else on the road.
- **Custom street races (F5):** choose a start, a finish and a start time; anyone can join at the line. No fee, no
  prize; one call per driver every 15 minutes, at most two open at once.
- **Lap ghosts:** your personal-best lap replays as an unhittable car in practice and time trials only.

**Records.** Best times are kept per route. `/ncm.results` lists your last five results and `/ncm.best` your best per
route.

## Limits and known rough edges

- Some checkpointed routes have been withdrawn while their racing lines are rebuilt; the calendar only posts routes
  that pass its checks.
- The interaction card shows only the keyboard key; on a pad, hold X.
- See [Known Issues](../known-issues.md) for current race problems.

## For developers

- League, calendar, sessions, results, penalties and settlement: `ncm/online/resources/ncm_league/server/`
  (`calendar.lua`, `race.lua`, `guide.lua`, `economy.lua`, `records.lua`).
- The Paddock's races and the physical "bubble" that puts NPC cars on the road: `ncm/online/resources/ncm_paddock/`.
- Pure rules (scoring, eligibility, penalties) live in `ncm/core/` and are unit-tested under Lua 5.4 and LuaJIT.
- The race HUD, grid snap and venue panel: `ncm/online/resources/ncm_world/client/` and `ncm_world/web/race.html`,
  `venue.html`.
- Design record: `docs/ncm-online/DECISION_RECORD.md` L228-L296 (Paddock racing, grids, qualifying, ovals, the flag).
