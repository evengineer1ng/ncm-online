# Individual Machine Profile — design specification

> **STATUS: SPEC** - owner intent, captured and **NOT authorised for implementation**. Do not build from it; do not contradict it. Covers: *the individual machine biography*
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

**Status: SPECIFICATION ONLY. Not implemented, and not authorised for implementation.** Recorded on
2026-09-23 from the owner's spec so it is not lost, and so the foundations built the same day are checked
against it. Promotion is a separate, explicit decision.

> THE MACHINE INDEX TELLS YOU ABOUT THE MODEL.
> THE ASSET LEDGER TELLS NCM WHAT ACTUALLY HAPPENED TO THE CAR.
> THE MACHINE PROFILE LETS THE OWNER SHOW YOU WHO THAT CAR HAS BECOME.

---

## Why this is recorded now rather than built

The spec depends on persistent asset identity, production provenance, authoritative mileage, ownership
history and race results. Four of those five landed on 2026-09-23 (L117, L118, L119). This document exists to
state what they are *for*, and to record which parts of the eventual feature are already possible.

The owner's own ordering is explicit: **do not let cosmetic profile work block foundational asset
persistence.**

## The three layers, which must not be conflated

| Layer | Answers | Owned by | Status today |
|---|---|---|---|
| **Machine Index** | "What do I know about this MODEL?" | discovery (`vehicle_discovery`, `machine_knowledge`) | **exists** |
| **Authoritative asset history** | "What is objectively true about THIS car?" | `vehicle_asset`, `vehicle_asset_transfer`, `session_result` | **mostly exists** (L119) |
| **Machine Profile** | "How is the current owner presenting this car?" | not built | **specification only** |

Model knowledge ≠ asset history ≠ owner-curated presentation.

## What already exists, and what a Phase 1 profile could compose today

`NcmProvenance.of(assetId)` already returns the spine of the profile card:

| Spec field | Source | State |
|---|---|---|
| manufacturer, model | `data.vehicle_catalogue` via `vehicle_key` | ready |
| model production ordinal | `vehicle_asset.model_ordinal` | ready (L119) |
| manufacturer production ordinal | `vehicle_asset.maker_ordinal` | ready (L119) |
| global NCM production ordinal | `vehicle_asset.production_ordinal` | ready (L119) |
| odometer | `vehicle_asset.odometer_m` | ready (L119) |
| production date | `vehicle_asset.produced_at` | ready (L119) |
| lifecycle state | `vehicle_asset.lifecycle` | ready (L119), terminal disabled |
| number of owners | `vehicle_asset_transfer` | derivable |
| race starts / wins / podiums | `session_result` | derivable, **but not yet per asset** — see the gap below |
| earned distinctions | — | not built |
| banner, featured distinctions, biography | — | not built |

**Phase 1 of the owner's own implementation order — a read-only profile composed from existing authoritative
data — is therefore largely possible now**, and is the natural first promotion.

## The one real gap in the foundations

**Race results are recorded against the DRIVER, not the machine.** `session_result` carries
`ncm_driver_id`; there is no `asset_id`. So "486 starts, 37 wins" for NCX #0042 — the spec's own example —
cannot be answered today, and no amount of profile UI will change that.

This is a small, cheap, forward-only addition (an `asset_id` column on `session_result`, written at entry or
settlement from the car the driver actually fielded) and it is **a prerequisite for the competition-history
half of the profile**. It is recorded as its own backlog item rather than folded into a later cosmetic pass,
because the value compounds with time: results not attributed to a machine from the start are results that
machine's biography will never contain.

## Rules the foundations already honour

- **The profile follows the car.** Ownership transfer preserves assetId, ordinals, provenance and mileage;
  L119 locks this and tests assert it.
- **Runtime reconstruction does not create a new machine.** A new `vehicleId` after a CALL is not a new car.
- **Facts cannot be edited by owners.** Nothing player-facing writes to `vehicle_asset`'s provenance or
  odometer columns.
- **The hidden terminal threshold is never exposed** — it does not exist yet, and when it does it stays
  server-side (L119).
- **Derive, don't duplicate.** The profile is a composed view; it must never become the canonical source of
  wins, mileage, ownership or production numbers.

## Rules that will need work when promoted

- **Historical accomplishment vs current status.** "Held the B-Line record in Season 4" is permanently true;
  "current record holder" is not. Distinctions must be append-only statements about things that happened.
- **Complete vs featured distinctions.** A car may earn many; the owner features a few. Changing the
  featured set must not touch the earned ledger.
- **Physical presence is the access model.** *The world is the browser.* Inspecting another player's machine
  should normally require being near it, through the future scanner, reusing canonical Machine Index
  discovery rather than duplicating it. Discovering that Enzos exist must not grant remote access to every
  individual Enzo's profile.
- **Owner-authored biography** needs the existing player-generated-content limits: length bound, escaping,
  overflow, and a moderation path. `player.help.cleanReport` is the established precedent in this codebase.
- **Privacy boundaries.** Stored ≠ public. Owner identities, transaction prices, administrative provenance,
  telemetry and any future lifespan are not automatically profile content.
- **No pay-to-prestige.** Cosmetic banners may have broad unlocks; accomplishments must originate from
  authoritative NCM events.

## Not authorised by this document

Global vehicle search, remote inspection of arbitrary cars, likes/follows/comments/ratings, price histories,
full telemetry history, museum/restoration/repair systems, terminal mechanical failure, prestige scores,
rarity tiers, automated "legendary car" classification, or a permanent archive of every biography edit.

Reputation should emerge from facts and from humans.

## Suggested promotion order (the owner's, preserved)

1. Read-only profile composed from existing authoritative asset data.
2. Owner-curated biography, banner and featured distinctions.
3. Scanner / physical-presence inspection of other players' machines.
4. Earned distinction catalogue and event integrations.
5. Onward, only as justified by actual play.

**Prerequisite for meaningful Phase 1 competition history: attribute race results to the asset (IDEA-236).**
