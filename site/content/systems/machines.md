---
title: Cars & Machine Index
description: Serialized machines, buying and calling a car, the Scanner, and the Machine Index of what you own and know.
status: live
---

# Cars & Machine Index

## Machines are objects

Every car in NCM is a **machine**: one serialized asset with its own number, owner, odometer, condition, gearbox and
history. Two Galenas are two different objects. The Market sells real stock, so a car that sells is gone.

## Getting and using a car

- **Buy** in F6 → MARKET. Start with a base car and build from there.
- **Call** an owned car from Machine Index (F6 or <kbd>F10</kbd>) with **CALL VEHICLE**. It appears in a clear space
  near you. Calling a car is separate from buying it.
- **Get in** by holding <kbd>E</kbd> at your car.
- **Your car keeps its state**: fuel, damage and odometer are stored on the server and restored when the car next
  appears.

## Machine Index

Machine Index is your record of **observation**: the cars you own, and the machines you have discovered.

- It keeps the **evidence** behind each fact. What you have not measured stays unknown; no number is guessed.
- **Discovering** a machine takes the **Scanner**: <kbd>Tab</kbd> or <kbd>Caps Lock</kbd>, held on a car within 60 m.
  Driving past a car does not add it. {{status:experimental}} The reticle and scan-to-discover are still being proven.
- **Driving** a machine records measured facts about it. There is no estimator or confidence rating yet.
- Servicing, parts and their actions are **not** here; they are in [Engineering (F9)](engineering.md).
- On Online, Machine Index is also where you choose the one car you **anchor** through the
  [Race Week](race-week.md) reset.

## Limits

- Wings, spoilers and splitters cannot be attached yet; the platform's attachable catalogue has none.
- Flying machines appear in the Index but are never street cars.

## For developers

- Assets, ownership, provenance: `ncm_league/server/` (`market.lua`, `provenance.lua`) and the `vehicle_asset`
  family of tables (see `ncm_league/server/schema/`).
- Calling, presence and materialisation: `ncm_world/server/` and `ncm_world/client/`.
- Scanner: `ncm/online/resources/ncm_scanner/` plus the native `ncm/vision` reticle.
- Authority: `docs/ncm-online/16_MACHINE_INDEX.md`, `13_VEHICLE_COLLECTION.md`, `12_CANONICAL_VEHICLE_ROSTER.md`.
