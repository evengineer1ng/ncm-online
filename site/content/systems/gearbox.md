---
title: Manual Gearboxes
description: NCM Gearbox, our own manual transmission: fixed per car at manufacture, 4 to 8 gears, native engine audio.
status: experimental
---

# Manual Gearboxes

NCM has its own manual transmission, **NCM Gearbox**, written from scratch for NCM.

## For players

- **A gearbox is fixed when a car is made**, like its colour. A Galena automatic and a Galena manual are two
  different Galenas: one Machine Index entry, two configurations, and the difference shows wherever you buy.
- **Automatics are untouched.** A manual's edge is gearing trade-offs only: acceleration against top speed and
  overdrive. Manuals come with **4 to 8 gears** depending on the spec.
- **Cars that already existed** before the gearbox system stay automatic. Shelf stock and every new car are rolled
  from the model's factory mix.
- The engine's own gear and sound follow your box. Since version 0.4.0, each of your gears is carried across all
  seven of the game's native gears, which fixed the slow, bad-sounding manuals of 0.3.x.

## Limits

{{status:experimental}} Gear feel and audio are still being tuned from live driving. Clutch behaviour on a pedal
depends on your [rig setup](rig.md).

## For developers

- Native side: `ncm/gearbox/` (redscript HUD and natives; TweakDB clones `<model>_ncm_gbx_<spec>`).
- Asset fields: `vehicle_asset.gearbox_*` (schema 063).
- Authority: DECISION_RECORD L306 and L360.
- NCM does **not** ship the third-party "Manual Transmission" mod. NCM Gearbox replaces it.
