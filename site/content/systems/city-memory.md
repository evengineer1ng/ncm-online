---
title: City Memory
description: City Memory is NCM's design for a Night City that remembers where crashes happened and changes its infrastructure in response. What exists today and what is designed.
---

# City Memory

{{status:live}} road scars from real incidents &nbsp; {{status:planned}} the campaign scar ledger, infrastructure
knowledge and civil engineering

**City Memory** is the idea that Night City should remember what happens on its roads. Places where cars keep
crashing accumulate history, the city responds, and that history becomes something players can read and use.

## What a player sees today

- **Incidents are recorded with positions.** When a car crashes or goes off during a race, the server records the
  kind of incident, its severity and where it happened.
- **Road scars.** Each run, recent incidents are drawn back into the world as scars, so the places that hurt people
  look like it.
- **Race Week reacts** to how the run is going: more incidents than usual pushes the city's tolerance down sooner.
  See [Race Week](race-week.md).

## What is designed but not built

The full design, written in October 2026 and explicitly not yet authorised for building:

- **A campaign scar ledger:** incidents clustered by road segment and radius into a burden that grows through levels
  1-4, physical incidents only, ending with the campaign.
- **An infrastructure knowledge ledger** that carries what the city learned across runs.
- **Civil engineering** as engineering pointed outward: a small snapping kit of barriers and pieces, built and
  dismantled by anyone for modest money, judged by the race.
- **An end-of-cycle Night City map** with a danger heatmap and infrastructure pins, chosen publicly at rollover.

None of this is a promise. It is recorded so the design is not lost. See the [Roadmap](../roadmap.md).

## For developers

- **Where it comes from:** the `incident` table (session, driver, kind, severity band, delta-v, x/y/z, time,
  evidence) written by `ncm_league`, and `ncm/online/resources/ncm_world/server/scars.lua`, which reads recent
  positioned incidents and redraws them each run.
- **Design authority:** `docs/ncm-online/49_CITY_MEMORY.md` (SPEC: owner intent, not authorised); DECISION_RECORD
  L312-L313.
