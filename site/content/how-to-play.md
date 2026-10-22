---
title: How to Play
description: The player's guide to NCM Online: races, the Paddock, cars, engineering, fuel, money, trading, betting and controls.
status: live
---

# How to Play

New to NCM? Start with [Getting Started](getting-started.md). This page goes deeper. Each section links to the full
system page.

[TOC]

## The NCM Menu (F6)

Almost everything is in the NCM Menu: <kbd>F6</kbd>, or <kbd>Start</kbd> on a controller. Its tabs:

| Tab | What it is for |
|---|---|
| **DRIVER FILE** | Your licence, safety rating, reputation, balance and achievements. |
| **RACE GUIDE** | Tonight's races: route, start time, weather, regulations, entry fee, payout and whether you can enter. |
| **PADDOCK** | The NPC league: what's on today, races live on track, results, standings, teams, news, Billie's betting board, your own team and pace data. |
| **MARKET** | Serialized cars and parts for sale, from the Base Market and Autofixer terminals. |
| **EXCHANGE** | Direct trades with another online driver. |
| **MACHINE INDEX** | Cars you own and machines you have discovered, with the evidence behind each fact. |
| **DEVICES** | Wheel, pedals, force feedback and gamepad settings. |
| **MESSAGES** | Conversations, invitations and notices addressed to you. |
| **HELP** | Controls, what works today, and **report a problem**. |

Engineering has its own panel on <kbd>F9</kbd>, docked to the right so you can keep driving.

## Racing

**Find a race** in the Race Guide or the Paddock's RACES tab. Routes, fields, entry fees, payouts and eligibility
differ from event to event, so browse before you travel. Marking a race **Interested** tracks it and points your GPS
at the venue; it does not reserve a place.

**Enter at the venue.** Drive there, enter (the entry fee is charged then), and join the grid before it closes.
<kbd>F7</kbd> at the grid snaps you to your exact starting spot. You can correct your position until green. A driver
not on the grid at green is a DNS.

**Qualifying** starts at the venue and helps set the grid order. Practice and qualifying pay nothing.

**During the race**, <kbd>F8</kbd> toggles the live race graph. The running order on screen is the real order.
Penalties are applied in a ceremony after the flag, and NPCs are penalised by the same rules.

**Leaving.** Before the start, **Withdraw** at the venue. After the start, **Forfeit** (`/ncm.forfeit`, asked twice)
retires you as a DNF.

**After the flag** you get a result and, for paid events, an itemised settlement. Race Tags are awarded from the facts
of your run, and clean driving earns a capped bounty.

**Results say how they were made.** A race can be *observed* (driven by the cars on the road) or *simulated* (resolved
by the league's simulation when nobody was there to watch). Result details say which.

**Other ways to race:**

- **Time trials:** a field of one against the clock.
- **Custom street races** (<kbd>F5</kbd>): you set a start, a finish and a start time, and anyone can enter at the
  line. They are informal: no entry fee, no prize. One call per driver every 15 minutes, two open at once.
- **Your own ghost:** in practice and time trials, your personal-best lap replays beside you as a car that can't be
  hit. Ghosts never appear in contested races.

More: [Racing](systems/racing.md) · [NPC Racing & the Paddock](systems/npc-racing.md) · [Race Week](systems/race-week.md)

## Cars

- **Buy** in the Market. Each listing is one serialized machine, and sold stock is gone. Start with a base car.
- **Call** a car you own from Machine Index with **CALL VEHICLE**; it appears in a clear space nearby. Hold
  <kbd>E</kbd> at it to get in.
- **Discover** machines with the Scanner (<kbd>Tab</kbd> or <kbd>Caps Lock</kbd>): hold it on a car within 60 m.
  Driving past a car does not add it. Seeing a car in the Index does not mean you own it.
- **Learn** about a machine by driving it. Measured facts accumulate, and unknown details stay unknown.
- Some cars are **manual**. The gearbox is fixed when the car is made, so two cars of the same model can drive
  differently. See [Manual Gearboxes](systems/gearbox.md).

More: [Cars & Machine Index](systems/machines.md)

## Damage, repair and parts (F9)

Damage stays on your car for the Race Week. A crash costs condition, and condition costs money or work.

- **F9 Engineering** shows your car's condition by area before you choose how to service it.
- **Doing it yourself** costs materials only. A **workshop** quote includes labour; **Route Me There** navigates to
  the suggested shop.
- **Workmanship rolls per section** (grip, drive, brakes, drag). A job can improve or cost each one, and your
  restoration skill moves the odds. The result is a job sheet; read it.
- **Parts** are serialized components with fitment rules. A part that doesn't fit says so before you buy it.
- **The Workshop** (F9) covers tear-downs, fabrication, promoting a design and small production runs.

More: [Engineering & Parts](systems/engineering.md)

## Fuel

Your car burns fuel as you drive; the level is under the odometer. Park at a pump in your car and use
`/ncm.refuel` (€$2 a litre). `/ncm.fuel` sets your GPS to the nearest station. More: [Fuel](systems/fuel.md)

## Money

- You receive a **starting balance** once.
- **Scheduled races** charge entry and pay on completion and placement. Every settlement is an itemised receipt, and
  nothing is paid twice. An aborted event refunds.
- **Practice, qualifying and custom street races mint nothing.**
- `/ncm.balance` prints your balance in chat; the Driver File and Market show it too.

More: [Economy, Markets & Betting](systems/economy.md)

## Markets, trading and betting

- **Autofixer terminals** around the city are markets of their own. Stand at one and press <kbd>E</kbd> (pad
  <kbd>X</kbd>) to connect, then browse its stock from F6 Market from anywhere.
- **Exchange** (F6): build one exact offer from machines, stored parts and eddies. Both drivers confirm the same
  version before anything moves, and both must be online.
- **Billie's Board** (F6 → PADDOCK): Billie takes positions on NPC races. Anyone can read the board; writing paper
  needs an introduction, and Rico knows a book. Prices lock when you sign, and there is no cancel.

## Teams and the Paddock

The Paddock is a league of NPC teams and drivers that races, signs, fires and makes news on its own. In F6 →
PADDOCK → **MY TEAM** you can found or run one team. Paddock people can stand at garages and other places in the
city, and you can talk to them.

More: [NPC Racing & the Paddock](systems/npc-racing.md)

## Weather and time

Night City runs on **US Eastern real time**. The sky is shared by everyone in the session. Rain soaks the road: less
grip, longer braking, and a car that gets loose under heavy throttle. It dries over a few minutes. More:
[Weather & Time](systems/weather.md)

## Wheels and controllers

A controller, keyboard or wheel all work. For wheels, pedals and custom rigs, NCM Rig Bridge reads DirectInput
devices and drives force feedback, which starts **disarmed**. Set it up in F6 → DEVICES. More:
[Wheel & Rig Support](systems/rig.md)

## Watching a race

`/ncm.tower` toggles a timing tower for your race or the Paddock race you are near. `/ncm.names` toggles names over
NPC race cars. The **Race Week Live** station is in the game's own radio list. More:
[Broadcast & Race Week Radio](systems/broadcast.md)

## Getting help

F6 → **HELP** lists the controls and lets you **report a problem** from inside the game. See also
[Known Issues](known-issues.md) and the [FAQ](faq.md).
