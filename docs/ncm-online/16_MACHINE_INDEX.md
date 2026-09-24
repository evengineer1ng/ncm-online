# Machine Index — knowledge foundation

> **STATUS: CURRENT** - authority for: *player-scoped machine knowledge* - affirmed 2026-09-24
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

**Status:** foundation implemented locally; migration 016 and live behavior are not deployed or validated.  
**Working display name:** Machine Index. This name is not a persistence identifier and may change.

The Machine Index records what the player has learned about the automotive world. It expands the Vehicle
Collection without erasing that feature's authored roster, discovery behavior, or historical rows.

## Invariants

- Discovery is not omniscience.
- The canonical library is server knowledge, not player knowledge.
- The market participates in discovery; it does not bypass discovery.
- Passive encounter establishes identity. Active observation develops knowledge.
- Unknown is valid data.
- Model knowledge and asset knowledge are different things.
- Ownership substantially clears the fog, but does not automatically reveal the entire future universe of possible modifications.
- Discovery can celebrate. Research should generally be quiet.

`vehicleKey` identifies a conceptual model. `assetId` identifies one persistent physical example. A live OPEN//77
vehicle/entity id identifies only a streamed runtime object and must never be persisted as either.

## Foundation now

The existing `vehicle_discovery` table remains the compact first-identity-reveal projection. It preserves first
time/source, encounter recency/count and Discoveries Inspired provenance. Migration 016 adds
`vehicle_knowledge_evidence`, an append-only, player-scoped evidence table with model identity, optional persistent
asset identity, explicit knowledge/source/epistemic kinds, occurrence time, optional JSON evidence and a unique
caller-authored idempotency key.

Existing discovery rows backfill to one `identity_reveal` item without upgrading them into performance knowledge.
The compatibility projection permits zero physical encounters: primary-market publication is a real identity
reveal but is not an encounter.

`NcmCollection.revealIdentity` is the trusted server seam for future player-facing surfaces. Sources begin with
`world_encounter`, `primary_market`, `secondary_listing`, `ownership`, `authored_display` and
`manufacturer_publication`. Only `world_encounter` may nominate another Driver for Discoveries Inspired.

The current F10 panel remains structurally unchanged. Its payload label and discovery toast use the working
Machine Index name; unknown slots remain `???`.

## Market contract

Market architecture is governed in [17_MARKET_NETWORK.md](17_MARKET_NETWORK.md). “Market” below means a
particular stable `marketId` visible through the player's known/available market set, not a universal shop.

1. Render actual available stock, never the full canonical library.
2. Rendering identifiable stock calls the trusted identity-reveal seam for that viewer.
3. Primary-market and listing reveals have no human source credit.
4. A model absent from stock is absent from Market and may remain `???`.
5. Canonical existence alone creates no player knowledge.
6. Knowledge survives stock removal and listing expiry.
7. Purchase transfers a real `assetId`; it does not mint a phantom asset on Buy.
8. Owned-now and owned-ever remain separate; owned-ever derives from immutable acquisition/transfer history.

Current conflict: `vehicle_asset` records current title only. Once resale exists, updating its owner would make
owned-ever and prior ownership unreconstructable. Market must add immutable transfer/acquisition history before
the first sale. That requirement is not implemented here.

## Probe

Build `2.31.13+op77.87` provides enough for a bounded Scanner experiment, not enough to promise the final UX:

- input plus WebUI/effect/audio surfaces can supply an action and modest feedback;
- `Open77.inspector.target().engineId` exposes the engine's LOS-tested look-at target;
- `Open77.world.raycast` returns bounded static/dynamic geometry hits, but not target identity;
- vehicle snapshots expose live id/entity, record, position/bucket, speed, RPM, controls, occupants and physics authority;
- no documented general engine-entity-to-network-vehicle mapping was found. Matching inspector `engineId` to a
  vehicle snapshot's `entity` is a hypothesis to test, not an assumption.

Probe a non-pausing scan action that acquires a target client-side, sends only a candidate live vehicle id, and
has the server revalidate registration, record, bucket, range and any corroborable evidence. Owner identity stays
unresolved: replication owner/occupant is not proof of legal title.

Authoritatively observable now: canonical record for NCM-registered vehicles, server position/bucket/proximity,
and replicated instantaneous motion telemetry. Observed 156 km/h supports “at least 156,” never a stock top-speed
claim. Stock specifications, installed parts, tuning, condition and asset configuration do not exist today and
remain unknown until their own systems provide facts.

## Later

- Ownership transfer history and owned-ever derivation.
- Scanner experiment, then separately reviewed interaction/presentation work.
- Asset-scoped dynamic observations and explicit estimates derived from evidence.
- Component/configuration knowledge once parts exist.
- F6 tab integration, richer dossiers and personal observation summaries.

## Do not build yet

No complete Scanner UI/effects, inference, randomized estimates, parts observation, prevalence analytics,
privacy/registration rules, manufacturer service, parked-versus-moving simulation, rewards, achievements,
knowledge leaderboard, XP or skill tree. This is not a universal ledger and does not authorize omniscient payloads.

## 2026-09-23 follow-up: owned-asset access (L106)

The foundation is deployed (live Market/report rows independently read); this access follow-up is built locally
and awaits live QA 2.17 / §AB. Existing Collection UI is reused as MACHINE INDEX in the shared F6 shell, after
Market and before Help; F10 stays available. Model discovery remains separate from the per-model `assets[]`
list, which contains one entry per owned persistent assetId. A discovered but unowned model has no CALL action.

CALL sends assetId only. ncm_world's access adapter reads fresh authoritative title under the authenticated
Driver/server, requests a bounded client geometry probe and rechecks title/context before creating the exact
stored record. Runtime assetId→vehicleId mappings prevent repeated calls creating duplicates. No persistent
asset, stock, title, purchase or ledger mutations occur. The first conservative envelope supports the three
Base Market records; unsupported models and unsafe/unknown geometry refuse cleanly. Existing called vehicles
remain in the world across disconnect and are removed on resource stop; lifecycle needs live verification.

Migration 017 now supplies immutable acquisition/transfer history, superseding the earlier "not implemented"
foundation note above. F6 integration is built; Scanner, richer dossiers and expanded model placement remain later.

2026-09-23 14:40 UTC deployment update: IDEA-199/L106 shipped to staging at the user's request. Clean boot and storage restart verified; live CALL/UI/geometry QA remains pending (MASTER_TEST 2.17).
