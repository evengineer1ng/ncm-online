# Market Network — supplier and commercial-knowledge architecture

> **STATUS: CURRENT** - authority for: *markets, market discovery* - affirmed 2026-09-24 (L106, L117)
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

**Status:** foundation built locally and offline-green; not deployed or live-validated. Migration 017, the host
purchase path and the F6 tab implement one universally known `base_market` with a small authored starter-vehicle
allocation. No dealership network, supplier discovery, component, map or progression content is built.

Current provisional alpha allocation: one MaiMai (€$2,500), one Galena (€$4,500), and one Hella (€$7,500),
against an idempotent €$10,000 starting grant. These are authored balancing values, not a permanent economy
decision. Each listing is one real `assetId`; when sold, it is gone from shared stock.

The Base Market is a market, not the market. NCM's economy may contain multiple stable commercial sources, and
the F6 Market surface represents the sources a particular player knows and can currently access. Physical/world
interaction may establish commercial knowledge; F6 remembers and operationalizes it.

## FOUNDATION NOW

Introduce a stable opaque `marketId` boundary before inventory or transactions exist. Do not use a manufacturer
name as identity: one manufacturer may operate several surfaces and one supplier may carry several manufacturers.

The smallest durable model is:

```text
market
  market_id                 stable opaque identity
  display_name              presentation, independently mutable
  kind                      primary supplier initially; classifieds remain a separate economic kind
  universally_known         policy, true only for Base Market initially
  discovery_policy          authored policy/reference, not one global level
  access_policy             optional future policy/reference; knowledge and access may diverge

market_inventory / allocation
  market_id                 which commercial surface makes this stock available
  asset_id                  one real physical example, never a catalogue row or per-viewer copy
  availability state/time   current market state over authored supply

player_market_knowledge     future-compatible even if Base Market is derived rather than stored initially
  ncm_driver_id, server_id, market_id
  first_known_at, source_kind, source_ref/context
  access state/reason       nullable until knowledge and access actually diverge
```

Exact table names are not mandated. `base_market` may be authored data and treated as universally known without
one redundant knowledge row per Driver. All query code must nevertheless accept a set of known/available
`marketId`s; it must never call a singleton `theShop` or query all stock without market scope.

Knowledge, access, stock, eligibility and affordability are separate questions:

```text
known market → currently accessible market → visible real stock → item-eligible → affordable
```

The UI may collapse successful stages, but authority and refusal reasons must not. Unknown markets are absent.
There is no total market count, completion percentage, locked `???` market roster or canonical market catalogue
disclosed to the client.

## IMPLICATIONS FOR STARTER MARKET

- Author `base_market` as the first stable market identity and universally known policy.
- Assign the three starter stock assets/allocation to `base_market`; do not make them unscoped global inventory.
- Query F6 through the player's known/available market context even while that set contains only Base Market.
- The first UI may display only **BASE MARKET**. Filters can remain trivial, but payload rows carry `marketId`.
- Stock is authoritative shared supply according to allocation policy. Opening F6 creates no asset and no
  per-player inventory copy.
- Buying atomically debits the idempotent ledger and transfers the existing `assetId`, or does neither.
- Purchase records market/allocation provenance and immutable ownership transfer history.
- Base Market contains only its authored starter allocation. It is not a fallback for every future product.
- Primary supply and player classifieds remain different transaction origins.

The conservation rule remains:

> SUPPLY CREATES → MARKET MAKES AVAILABLE → TRANSACTION MOVES OWNERSHIP → ENGINEERING APPLIES / INSTALLATION MAY CONSUME

Market discovery changes knowledge/access only. It never mints stock.

## MACHINE INDEX INTEGRATION

Market knowledge and vehicle knowledge are separate domains:

- knowing a vehicle never reveals a market;
- knowing a market never reveals products absent from its current inventory;
- rendering identifiable current stock may call `NcmCollection.revealIdentity(player, vehicleKey,
  { source = "primary_market", assetId = assetId })`;
- catalogue membership, allocation policy, or hidden stock not exposed to the viewer produces no discovery;
- primary-market exposure has no human source and no Discoveries Inspired credit;
- discovery remains after stock is sold or removed.

The integration point is the authoritative server response resolving visible inventory for that viewer—not the
browser merely opening and not client JavaScript. That response knows the market is known/accessible and which
real stock rows are disclosed. Replays are safe through the Machine Index identity evidence key.

## PROBES / OPEN QUESTIONS

- Physical discovery: which OPEN//77 interaction/zone/terminal primitive is reliable, and can an authored
  location become a durable map pin without custom map infrastructure?
- Access representation: when known-but-inaccessible first exists, derive access from domain facts or record a
  dated grant/revocation? Do not add mutable state before a real policy needs it.
- Market lifecycle: permanent closure, movement and suspended access are undesigned. Knowledge should survive
  ordinary empty inventory and downtime.
- Shared-stock concurrency: purchase must lock/claim one asset so two clients cannot buy the same `assetId`.
- Visibility timing: define “exposed” for pagination/filtering so an internal query does not discover every row.
- Organization/team supplier access, information sharing, and public owner identity remain unresolved.

## LATER

- Persistent player market-knowledge rows when the first non-universal market is authored.
- Physical dealership/showroom/terminal discovery and optional known-location map pins.
- Authored accomplishment, sporting, engineering, manufacturer or relationship access sources.
- F6 filtering across one, several or all currently known/available markets.
- OEM, aftermarket and specialist component suppliers over persistent component supply.
- Opt-in inventory watches, brokers, sourcing specialists and player information exchange.
- Secondary classifieds over real player-owned assets with their own lifecycle.

Supplier access may eventually be a meaningful reward. It is not universal Market XP, a profession class, or a
statistical buff. Manufacturer identity, supplier identity and component compatibility remain separate facts.

## DO NOT BUILD YET

No citywide dealership network, placeholder suppliers, OEM catalogue, parts economy, physical discovery flow,
map infrastructure, unlock quests, supplier reputation, rarity tiers, loyalty, fast travel, market completion,
undiscovered-market slots, global omniscient inventory, infinite shops, inventory notifications, brokers or
social professions. Preserve the seams; do not fabricate content.

## Architectural tests

- Base Market is a market, not the market.
- Players can know different markets.
- Unknown markets are absent and no total count is exposed.
- Market discovery and vehicle discovery are separate facts.
- A known market reveals only currently exposed real stock.
- Knowing a vehicle does not reveal where to buy it.
- Discovering a supplier creates no supply and no per-player copies.
- `marketId`, manufacturer identity, allocation identity, `vehicleKey` and `assetId` are never collapsed.
- Visible, eligible and affordable remain distinct.
- Exploration is one knowledge source, not the universal source.
- F6 remembers commercial knowledge; repeated commuting is not the browsing loop.

## 2026-09-23 first live purchase and access contract

The foundation has been deployed since the original status above. Live SQL confirms the MaiMai purchase:
asset `10000000-0000-4000-8000-000000000001` is sold and owned, balance €$7,500, Galena/Hella still available.
The three starter UUIDs share their first eight characters; the UI wrongly displayed only that prefix. The
payload already carried full distinct assetIds; this follow-up renders the full ID. No identity repair or
transaction rewrite was required.

Purchase and access are separate (L106). A success notification names the model and teaches Machine Index
(F6/F10) → owned asset → CALL. It does not navigate away or materialize a car at checkout. Physical access is
owned by the world runtime adapter, which never mutates Market stock or persistent ownership. Concise Help copy
explains the same loop. These UI/access changes are local, not yet live-validated; QA 2.17 / §AB is authoritative.

2026-09-23 14:40 UTC deployment update: IDEA-199/L106 shipped to staging at the user's request. Clean boot and storage restart verified; live CALL/UI/geometry QA remains pending (MASTER_TEST 2.17).
