---
title: NCM Online
description: NCM Online turns Night City into a persistent motorsports world on OPEN//77 for Cyberpunk 2077: scheduled races, NPC rivals, real machines, engineering and a living league.
---

<div class="hero" markdown="0">
  <picture>
    <source srcset="{{root}}img/race-week-hero.webp" type="image/webp">
    <img src="{{root}}img/race-week-hero.jpg" width="1600" height="513" alt="NCM Race Week billboard: the words RACE WEEK in yellow brush lettering over a neon Night City skyline, with NIGHT CITY MOTORSPORTS and the NCM logo beneath and a sports car in the corner.">
  </picture>
  <div class="hero-copy">
    <h1>NCM ONLINE</h1>
    <p class="tag">Motorsports in Night City</p>
    <p>A multiplayer racing server for Cyberpunk 2077 on OPEN//77. Night City becomes a persistent motorsports world: scheduled races across the whole city, NPC rival drivers with careers and teams, serialized cars you own, an engineering bench, fuel, weather and an economy that keeps a receipt for every eddie.</p>
    <div class="cta">
      <a class="btn btn-primary" href="{{root}}getting-started.html">How to Play</a>
      <a class="btn btn-ghost" href="{{root}}systems/index.html">Explore NCM</a>
      <a class="btn btn-ghost" href="https://github.com/evengineer1ng/ncm-online">View Source</a>
    </div>
  </div>
</div>

**Status: alpha, under active development.** NCM Online has run since September 2026. Systems change quickly, and
progression is temporary: money, machines, parts and records reset for NCM 1.0, and may reset before then. Every
system on this site carries a [status label](status.md): {{status:live}} {{status:experimental}}
{{status:in-development}} {{status:planned}} {{status:historical}}.

## What is NCM Online?

NCM (Night City Motorsports) began as a single-player racing mod. NCM Online is its multiplayer branch: a dedicated
[OPEN//77](https://open2077.net) server where the racing happens in a shared, persistent Night City.

- **You race across the city.** Races run on a schedule through Night City's streets, highways and authored ovals,
  with routes, fields, entry fees and payouts that differ from event to event.
- **You are never waiting for a lobby.** A league of NPC teams and drivers, the Paddock, races on its own calendar
  whether anyone is online or not. NPC racers fill empty grid places around start time, so a quiet server still has
  races. [More on NPC racing](systems/npc-racing.md).
- **Your car is a real object.** Every machine is serialized: one specific car with an owner, an odometer, damage
  and a history. The Market sells real stock, so when a car is sold it is gone.
- **Engineering matters.** Damage persists, repair is a job with materials and workmanship, parts have fitment rules,
  and manual gearboxes are fixed at the factory per car.
- **The city has weather and time.** Night City runs on US Eastern real time, the session's sky is shared, and wet
  roads cost grip until they dry.
- **Race Week.** The server runs in multi-day Race Weeks with championships crowned at the end and a hall of
  champions that survives the reset.
- **Wheels welcome.** NCM Rig Bridge brings wheel, pedal and custom-rig input with force feedback. A controller or
  keyboard works too.

<div class="cards" markdown="1">
<div class="card" markdown="1">
### New here?
Install OPEN//77, find NCM Online, and run your first race.

[Getting Started](getting-started.md){.more}
</div>
<div class="card" markdown="1">
### Already playing?
Entering races, qualifying, repairs, fuel, money and the Paddock in depth.

[How to Play](how-to-play.md){.more}
</div>
<div class="card" markdown="1">
### Curious what's inside?
Every system, what state it is in, and how it works.

[Systems](systems/index.md){.more}
</div>
<div class="card" markdown="1">
### A developer?
Architecture, a map of a very large repository, and how to build on it. MIT licensed.

[Developers](developers/index.md){.more}
</div>
</div>

## What works today

This table comes straight from the in-game landing panel, so it says exactly what the game itself tells
players. "Experimental" here is the game's own *partial* state, and it always names its limit.

{{generated:capabilities}}

Since that panel was last updated, more has shipped to the server: the Paddock NPC league, Race Week, persistent
damage, the F9 Engineering panel and Workshop, manual gearboxes and the Race Week Live radio station. Some of these
are still waiting for a full live sign-off, so check each system's label. See the [changelog](changelog.md).

## The strange branches

NCM is a motorsports project first. But the simulation has grown some unusual branches, including flight and some
physics that reach well beyond a street race. None of it is needed to race, and it is all labelled. See
[Experimental Systems](systems/experimental.md).

## Open source

The whole server is public: the Lua resources, the native mods, the tests, and the design record of every decision.
It is released under the [MIT License](https://github.com/evengineer1ng/ncm-online/blob/main/LICENSE). It is a real,
actively developed server codebase, not a polished framework, but you are welcome to read it, fork it and build on it.
[Start here](developers/index.md).
