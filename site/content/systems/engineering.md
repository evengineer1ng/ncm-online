---
title: Engineering & Parts
description: Persistent damage, self and shop repair with per-section workmanship, serialized parts with fitment rules, and the Workshop.
---

# Engineering & Parts

{{status:live}} damage, repair, parts and the F9 panel &nbsp; {{status:experimental}} the Workshop, competency and Build

Engineering is its own panel: <kbd>F9</kbd>, docked to the right side of the screen. It never goes full screen and
never takes your keyboard.

## Damage

Damage is persistent and **weighted by what it costs to put right**: chassis 60%, body 25%, glass 6%, lamps 4%,
tyres 3%, panels 2%. It is not the worst single dent. Damage survives a reconnect and lasts for the whole
[Race Week](race-week.md).

## Repair

- **SERVICE** in F9 shows condition by area before you choose a job.
- **Self repair costs materials only.** Your own hands don't charge labour.
- **A workshop** quotes materials and labour. *Route Me There* navigates to the suggested shop.
- **Workmanship rolls per section** (grip, drive, brakes, drag). Each can come out better or worse. Your restoration
  skill moves the odds, and a botch affects only that section. The result is written onto a **job sheet**, one
  section at a time, and stamped. Read it.
- NPC teams repair with the same model, and pay for it.

## Parts

Parts are **serialized components**: one physical part with an identity, bought from Market stock (the PARTS view)
and fitted to a machine you own.

- **Fitment rules are real.** A part that doesn't fit says so before you buy it.
- **Parts wear** with distance. Tyre compounds (hard/medium/soft) are not in yet.
- Fitted parts travel with the car; loose parts can be stored and traded on the Exchange.

## The Workshop {{status:experimental}}

The F9 **WORKSHOP** tab is one bench for four kinds of engineering, usable anywhere:

| Job | What it does |
|---|---|
| **Tear down** | Consumes a specimen part and reveals what it is, in stages, as far as your reverse-engineering skill reaches. The knowledge stays with you. |
| **Fabricate** | Builds a prototype from what you know. It can come out poor, neutral or junk, and junk is kept (and can't be mounted). |
| **Promote** | Turns a working prototype into your own immutable design. |
| **Run** | Builds one to three units of your design. Your production skill sets the reject rate. You can list a unit on the Base Market; the buyer pays you. |

Every bench job builds your **engineer competency**, shown in words from *Untrained* to *Master*, never as raw
numbers.

The F9 **BUILD** tab is reserved for player-built infrastructure and is not designed yet; on some clients it reports
that Build is not running.

## For developers

- Panel: `ncm/online/resources/ncm_engineering/` (client) with server logic in `ncm_world/server/engineering.lua`,
  `vehicle_condition.lua` and `ncm_workshop/`.
- Pure models: `ncm/core/engineering/*` (competency, lineage, fit, envelope, machine assembly), `ncm/core/parts/*`
  (wear, fitment).
- Native physics and parts application: NCM Carrier, `ncm/carrier/` (RED4ext C++).
- Authority: DECISION_RECORD L162-L163 (parts economy), L178 (wear), L314 (architecture), L349-L353 (damage and
  repair), L361 (Workshop); docs 50 and 54.
