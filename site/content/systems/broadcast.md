---
title: Broadcast & Race Week Radio
description: Names over NPC race cars, an opt-in timing tower, the Race Week Live radio station, and the Observer spectator mode.
---

# Broadcast & Race Week Radio

## NCM Broadcast {{status:live}}

Race presentation drawn natively by the **ncm-broadcast** plugin:

- **Names over NPC race cars**, so you can tell who is who. Toggle with `/ncm.names`.
- **An opt-in timing tower** for the race you are in, or the Paddock race you are near. Toggle with `/ncm.tower`.
- **The live race graph** (<kbd>F8</kbd>) while you drive.

## Race Week Live {{status:live}}

NCM's own **talk-radio station**, in the game's own radio list next to the vanilla stations. It talks about the
current [Race Week](race-week.md): the results, the drivers, the city.

- **Everything it says is real.** The show is authored, deterministic writing, aired from what actually happened in
  the simulation. No language model writes its lines.
- Its hosts are voiced with OmniVoice. The voice packs ship as NCM's own required mods (`ncm-radio` and
  `ncm-radio-voices-*`).
- It is on by default and never locked: switch stations like any other.

## NCM Observer {{status:in-development}}

A spectator mode: an invisible ghost camera that watches the races without taking part. It can't enter, earn, buy or
count, but the races around it still materialise. It only starts by an explicit act, and today it is restricted to
an allowlist.

## For developers

- Broadcast: `ncm/broadcast/` (native) and `ncm/online/resources/ncm_broadcast/`; DECISION_RECORD L235.
- Radio: `ncm/radio/` (corpus compiler, trigger map, voice render, native player) and
  `ncm/online/resources/ncm_radio/` (director); authority `docs/ncm-online/59_NCM_RADIO.md`.
- Observer: `ncm/online/resources/ncm_observer/`; `docs/ncm-online/46_NCM_OBSERVER.md`.
