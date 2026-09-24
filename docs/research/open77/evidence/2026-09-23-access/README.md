# Owned-asset access evidence — 2026-09-23

Completed: read-only staging database/package inspection, official build-pinned API queries, implementation
inspection and deterministic offline adapter tests. No deployment, restart, live geometry probe or driving test.

Staging package manifest reports **2.31.13+op77.87**. The official MCP was queried with that exact requested
build; [build.md](build.md) explicitly reports fallback to **.78**, with docs regenerated 2026-09-23. These
cards are documentation evidence, not proof that every field works on the deployed .87 runtime.

## Storage → payload → renderer

| Model | Authoritative asset_id | Current state |
|---|---|---|
| Makigai MaiMai | `10000000-0000-4000-8000-000000000001` | sold; Driver title; acquired_via purchase |
| Thorton Galena | `10000000-0000-4000-8000-000000000002` | available; no Driver title |
| Archer Hella | `10000000-0000-4000-8000-000000000003` | available; no Driver title |

Read `vehicle_asset`, `market_inventory`, purchase/grant ledger rows and `vehicle_asset_transfer` on staging.
One starter +10000, one MaiMai -2500, one primary_purchase history row, balance 7500 and two available offers.
No row was changed. `market.lua` selects `mi.asset_id` and assigns `assetId=row.asset_id` without conversion;
the old WebUI rendered `String(item.assetId).slice(0,8)`, collapsing every authored UUID to `10000000`.
The fix displays full IDs. This was a presentation defect; authoritative identity is distinct.
Read-only inspection of deployed `/opt/ncm/resources/ncm/ncm_league/server/market.lua:73` and
`ncm_world/web/panel.html:647` confirmed this same payload assignment and eight-character truncation on staging,
not just in the local source tree.

Read report `7a579673-e592-4d3c-8a6f-e02c67a01c62`, submitted 2026-09-23 14:03:21 UTC:
"bought a mai mai, it didnt appear anywhere but took my money". Its stored context reports one owned example,
one model, balance 7500, two offers and no eligibility refusal. Context corroborates the independent table reads;
it is not substituted for them. Existing Help submission PASS remains in MASTER_TEST 2.16.

## Supported contracts and limits

- [raycast.md](raycast.md): client static/dynamic ray, nearest hit position/normal; `world.query` permission.
  No road classification, vehicle sweep, ground snapping or native delivery behavior is assumed.
- [character.md](character.md): local grounded/alive/seated/movement snapshot, used to refuse invalid contexts.
- [player.md](player.md), [players-all.md](players-all.md): server player identity/context/freshness/enumeration.
- [create.md](create.md), [get.md](get.md), [all.md](all.md), [remove.md](remove.md): server runtime creation,
  lookup, enumeration and cleanup. An OPEN77 runtime ID is not the persistent NCM assetId.

Implementation: four candidates eight metres away; 3×6 m footprint ground samples every 0.75 m, normals ≥0.97,
height spread ≤0.2 m, vertical clearance to 2.5 m and horizontal cross-rays, plus player-to-candidate clearance.
No successful ray or missing API is treated as automatic permission to create: all checks must pass. Server
revalidates fresh title, request token/age, player movement/bucket, bounded pose, and nearby shared cars/players.
Creation uses only the exact owned record. First envelope supports MaiMai/Galena/Hella; others refuse.

This is conservative sampled geometry, **not a volumetric clearance proof**. Thin obstacles between rays,
changing traffic, client-reported geometry, actual record bounds, streaming readiness and lifetime cleanup
remain live risks to measure. There is no headless server geometry oracle claimed here. Unknown snapshot/API
fields cause refusal, not fallback offsets. Runtime records persist only as in-memory asset→runtime mappings;
no schema or acquisition semantics changed.

Next action: deploy the bounded resource changes under existing empty-server/Warden discipline, then execute
MASTER_TEST 2.17 §AB3–AB9. Record real .87 snapshot/raycast behavior first. If the probe cannot establish safe
space reliably, keep CALL refusing and revise the adapter; do not weaken ownership or create replacements.
