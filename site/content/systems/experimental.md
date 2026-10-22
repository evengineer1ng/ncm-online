---
title: Experimental Systems
description: NCM is a motorsports project first, but the simulation has grown some strange branches. Flight, aerodynamics, vehicle hacking and more, clearly labelled.
status: experimental
---

# Experimental Systems

**NCM is fundamentally a motorsports project, but the simulation has grown some strange branches.**

None of this is needed to enter a street race. It is here because the code is real, people find it, and hiding it
would be dishonest. Everything on this page is unstable, incomplete, or both.

## Slipstream {{status:experimental}}

Drafting is a physical effect: a car in another car's wake loses drag and gains a tow, including under power. Wake
quality is continuous, not an on/off bubble. Code: `ncm/online/resources/ncm_slipstream/`, `ncm/slipstream/`.

## NCM Chrome: vehicle quickhacks {{status:experimental}}

While the Scanner is up, NCM Chrome offers hacks against other vehicles: <kbd>X</kbd> and <kbd>Z</kbd> cycle hacks,
hold <kbd>G</kbd> to upload. The effects are vehicle-only. NPC racers have their own quickhack intelligence.
Uploads are recorded in a ledger the server keeps private. Design: DECISION_RECORD L343.

## Machines built from physical parts {{status:experimental}}

NCM's engineering does not stop at tuning. A machine is assembled from physical components on real mounting points,
such as the floor-pan underside and the rear, and **installed components decide what the machine can do**. Fit an
impulse actuator facing down and the car can **hop**. Fit a propulsor facing aft and it can **push**. Fit enough
lift and a flight computer and it can **fly**.

- On a pad: tap <kbd>Triangle</kbd> to hop, hold it to push forward, with the right parts fitted.
- Flight hardware comes from physical R&D and is spread across the Autofixer markets.
- The flight computer (FC-1) caps each engine's throttle to what the attitude parts can trim, and refuses with a
  reason when it can't hold the machine up.

Code: `ncm/core/engineering/*`, `ncm/online/resources/ncm_engineering/`, `ncm_build/`; authority docs 50 and 54,
DECISION_RECORD L321, L324, L342, L359.

## AVs {{status:experimental}}

The game's AVs (aerial vehicles) can be called and flown on NCM's own engineering: lift fans and a flight
computer. Flying machines are listed in the Machine Index but are **never street cars**. Expect rocking, odd speed
readouts and fuel surprises; see [Known Issues](../known-issues.md). DECISION_RECORD L368, KB-461..KB-478.

## Higher still

<details class="spoiler" markdown="1">
<summary>Spoiler: what is above Night City (open only if you want to know)</summary>

NCM treats this part as a secret to be found in play, not a menu item. Nothing teleports you there, nothing is gated,
and anyone who flies high enough finds it.

Above a seam high over the city, NCM takes over position from the game engine and runs **NCM Deep**, its own
universe: a real Solar System and a real star catalogue, multi-body gravity and frames of reference. Your actual
machine keeps flying on its own installed parts, drawn by a small native mod, **NCM Sky**. A propulsion laboratory
holds six experimental drives (impulse, fusion, warp, Alcubierre, jump and wormhole). They are lab-only toys with
no market, no progression and no balance.

It is the least stable thing in NCM. Thrust drop-outs, view problems and orbit drift are all recorded in the
[Known Issues](../known-issues.md). The [Race Week](race-week.md) reset applies there too.

Code: `ncm/core/space/*`, `ncm/sky/`, `ncm/online/resources/ncm_universe/`, `ncm_world/client/deep*.lua`;
authority `docs/ncm-online/60_ASTRONOMICAL_SUBSTRATE.md` and `61_EXPERIMENTAL_PROPULSION.md`.
</details>

## Not on the public server

These live in the repository but **do not run on NCM Online**:

| Branch | Status | What it is |
|---|---|---|
| NCM 3.0 single player (`ncm/host`, `ncm/host_native`) | {{status:in-development}} (on hold) | A native host that runs NCM's server resources inside single-player Cyberpunk over SQLite. See [The NCM Family](../about.md). |
| NCM Talk | {{status:planned}} | Spoken conversation with any NPC, grounded in NCM's real state. Plan only: `docs/ncm-online/62_NCM_TALK.md`. |
| Snowglobe, Los Santos (FiveM), Assetto Corsa and KSA bridges | {{status:historical}} | Development-server experiments in carrying one machine across games. Kept for the record, not shipped. |
| CITY_MEMORY ledgers and civil engineering | {{status:planned}} | See [City Memory](city-memory.md). |
