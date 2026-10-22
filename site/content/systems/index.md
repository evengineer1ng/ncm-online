---
title: Systems
description: Every NCM Online system, what state it is in, and where it lives.
---

# Systems

NCM is many systems that share one Night City. Each page below says what the system does for a player, what it does
not do yet, and where it lives in the source. The label is the system's state on the public server today. A page can
carry more than one label when its parts are at different stages.

| System | Status | In one line |
|---|---|---|
| [Racing](racing.md) | {{status:live}} | Scheduled races across Night City, qualifying, grids, results, penalties, time trials, custom street races. |
| [NPC Racing & the Paddock](npc-racing.md) | {{status:live}} | A persistent NPC league that races whether or not anyone is online, and fills your grids. |
| [Race Week](race-week.md) | {{status:live}} {{status:experimental}} | Multi-day runs with championships, finales, a hall of champions and a reset. |
| [Cars & Machine Index](machines.md) | {{status:live}} | Serialized cars, calling your car, the Scanner and what you know about each machine. |
| [Engineering & Parts](engineering.md) | {{status:live}} {{status:experimental}} | Persistent damage, self and shop repair, workmanship, fitted parts, the Workshop. |
| [Manual Gearboxes](gearbox.md) | {{status:experimental}} | Our own manual transmission, fixed per car at manufacture. |
| [Fuel](fuel.md) | {{status:live}} | Fuel burn, stations, refuelling. |
| [Weather & Time](weather.md) | {{status:live}} | Shared sky, wet roads, Night City on US Eastern time. |
| [Economy, Markets & Betting](economy.md) | {{status:live}} {{status:experimental}} | One ledger, receipts, the Market, Autofixers, Exchange, Billie's board. |
| [Wheel & Rig Support](rig.md) | {{status:live}} | NCM Rig Bridge: DirectInput wheels, pedals and rigs, force feedback. |
| [Broadcast & Race Week Radio](broadcast.md) | {{status:live}} {{status:experimental}} | Timing tower, NPC car names, the Race Week Live station, the Observer. |
| [City Memory](city-memory.md) | {{status:planned}} | What places remember: designed, and partly shipped as road scars. |
| [Experimental Systems](experimental.md) | {{status:experimental}} | Flight, AVs and the strange branches. Not needed to race. |

## How the pieces fit

- **The server is the authority.** Money, ownership, results and condition live in the server's database. Your
  client draws them and asks for changes; the server decides.
- **Everything has provenance.** A result is *observed* or *simulated*, never passed off as the other. A fact about a
  machine is evidence you collected, not a guess.
- **One ledger.** Every eddie that moves is a ledger row with a reason. Balances are computed, never stored loose.
- **Machines are objects.** A car is one serialized asset with an owner, odometer, condition, gearbox and history.

Developers: the [Architecture](../developers/architecture.md) page explains how this maps onto the code.
