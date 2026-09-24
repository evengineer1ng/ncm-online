# NCM Vehicle Collection

> **STATUS: CURRENT** - authority for: *discovery and collection* - affirmed 2026-09-24
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

> **Terminology evolution (2026-09-23):** this authored discovery/roster design is preserved, but its player
> concept now expands into the [Machine Index](16_MACHINE_INDEX.md). “Vehicle Collection” remains the existing
> implementation seam; discovery is identity knowledge, not full specifications or ownership.

Generation 1 artwork sourcing and the canonical 27-slot visual mapping are preserved in
[15_GENERATION_1_VEHICLE_ARTWORK_MANIFEST.md](15_GENERATION_1_VEHICLE_ARTWORK_MANIFEST.md). It is a sourcing
manifest, not a replacement for the catalogue authority in `data.vehicle_catalogue`.

**Status:** discovery foundation implemented; broader Machine Index is foundation-only and not deployed.  
**Roster source:** [12_CANONICAL_VEHICLE_ROSTER.md](12_CANONICAL_VEHICLE_ROSTER.md), preserved unchanged.

## Product definition

The Vehicle Collection is the Driver's persistent discovery history across NCM's entire recognized automotive
world. It combines the emotional readability of a fighting-game roster with an automotive encyclopedia and a
Pokédex-like completion record, expressed in NCM's restrained technical/motorsport language.

It is not the garage. Four concepts remain independent:

| Concept | Question answered |
|---|---|
| Canonical Vehicle Library | Which machines currently exist in NCM's world? |
| Vehicle Collection | Which canonical machines has this Driver legitimately discovered? |
| Garage / ownership | Which individual machines does this Driver own or possess? |
| Active vehicle | Which available machine is selected/in use or requested for access? |

The Library covers supported native vehicles first and later canonical modded vehicles. Its consumers must not care
whether the underlying content is native or modded.

## Player experience

The primary surface is one large, filterable roster—not merely dropdowns:

```text
VEHICLE COLLECTION
47 / 126 DISCOVERED     12 OWNED

[CAR] [???] [CAR] [CAR] [???] [CAR]
[???] [CAR] [CAR] [???] [CAR] [CAR]
```

Unknown entries retain position and silhouette/technical presence while withholding identity. Discovered entries
open a hero view and factual dossier. The complete roster may also be documented publicly: `???` represents the
Driver's in-world history, not cryptographic secrecy. Looking up missing cars and deliberately hunting them is valid.

Relationships are facts, not XP levels:

```text
UNKNOWN → DISCOVERED
          ├ DRIVEN
          ├ OWNED
          ├ RACED
          └ historical facts (mileage, starts, wins, PBs, encounters…)
```

Discovery and ownership completion are different accomplishments. Full ownership may remain extraordinarily hard;
the economy must not be distorted to make it convenient.

## Stable identity boundary

### What exists

`data.vehicle_pool` currently treats the TweakDB `record` as identity. Eligibility, provisioning and performance
ceilings use it consistently. `owned_vehicle` is keyed by `(driver, server, record)`. `issued_vehicle` separately
records requested record, spawned record and ephemeral OPEN//77 `vehicle_id`.

This is a useful transport/spawn boundary, but it is not a durable Collection identity:

- `_player`, team-livery and appearance records can represent the same underlying model;
- one chassis may have multiple implementations or variants;
- a mod update could rename a TweakDB record without changing NCM's conceptual vehicle;
- ownership keyed by record permits only one row per record and cannot represent multiple physical examples;
- mod/native provenance, display names, manufacturers and catalogue generations are not first-class.

### Proposed boundary

Introduce an immutable NCM-owned `vehicleKey` slug, for example `makigai_maimai`, `quadra_type66`, or
`ncx_rb15`. A canonical definition maps one identity to its runtime records:

```text
vehicleKey
display/manufacturer/category/source
canonicalSinceGeneration / retiredAfterGeneration?
runtimeRecords[] { record, role: base|player|livery|variant, contentPackage? }
classes/tags/prestige
dossier/media references
```

`vehicleKey` is the join key for discovery, ownership, statistics and history. TweakDB `record` remains the exact
spawn/eligibility/performance key. OPEN//77 `vehicle_id` remains an ephemeral physical entity. These three identifiers
must never be collapsed.

Liveries normally map to one `vehicleKey`; materially different chassis/builds may receive distinct keys by authored
decision. Aliases preserve history across record renames. Once published, a `vehicleKey` is never reused.

Existing code can migrate incrementally: extend `data.vehicle_pool` definitions and `byRecord()` with `vehicleKey`,
then add catalogue lookup by key. Do not replace record-based sporting checks prematurely.

## Persistence shape (future)

Likely durable concepts:

- catalogue generation/version and immutable membership snapshot;
- per-driver discovery keyed by `(driver, server, vehicleKey)`, with first/last encounter, encounter count and method;
- independent relationship facts/aggregates (driven, raced, mileage, results);
- ownership assets keyed by a unique asset ID and referencing `vehicleKey` plus exact record/configuration;
- active/access selection referencing an owned/loaned asset, not merely a catalogue key;
- historical completion facts such as “completed generation 1 at 64/64.”

Adding catalogue entries changes current completion from 64/64 to 64/66 without erasing the generation-1 completion.
Retired vehicles remain valid historical identities even if no longer spawnable.

## Discovery contract

A Race Guide name, documentation page or installed asset does not discover a vehicle. A legitimate physical/world
encounter might be another player's vehicle, a dealer/showroom display, paddock machinery or an authored display.

The technical primitive is unresolved and must be tested. The most promising authoritative contract is:

1. server knows the player's routing bucket and position;
2. server knows a canonical OPEN//77 vehicle entity's id, position and exact record;
3. record resolves unambiguously to `vehicleKey`;
4. player and vehicle remain within a conservative encounter radius for a short dwell;
5. optional client evidence proves the vehicle is streamed, but never determines identity or awards discovery alone;
6. server performs an idempotent discovery grant.

This is proximity/encounter, not assumed visual line-of-sight. OPEN//77 exposes canonical `vehicles.all/get`, vehicle
snapshots and player/vehicle state, so a prototype is plausible; what is not yet proven is a robust authoritative
player-position-to-vehicle proximity query across stream boundaries and buckets.

### Required experiment

With two clients and two canonical cars, test server snapshots for record, position, bucket and stream state at
approach/leave/rejoin distances. Attempt false cases: different bucket, far away, unstreamed entity, self-spawned
development car, rapid drive-by and repeated encounter. Decide radius/dwell and whether client streamed evidence is
needed. Discovery must award once and survive reconnect/restart.

Do not scan arbitrary vanilla ambient traffic until NCM can distinguish a trustworthy canonical/registered entity;
otherwise normal traffic could complete large parts of the Collection accidentally and differently per client.

## Catalogue growth and roster implications

This system does not change the roster report's 45–65 initial expanded target or 80–110 growth envelope. It adds
**world/discovery distinctiveness** as a legitimate tie-breaker. A cheap, visually recognizable machine may add more
Collection and social value than another similar supercar. It does not justify admitting everything.

When new canonical vehicles arrive, unknown slots appear immediately. Updates may reveal their names openly or leave
the announcement broad; secrecy is optional. Rare ownership creates emergent encounter rarity without a loot-rarity
table: another player's unusual car becomes social content and may trigger restrained `NEW VEHICLE DISCOVERED` feedback.

## World/economy boundaries

- Dealership/showroom: exposes catalogue entries and may offer acquisition.
- Garage: stores/manages owned physical assets.
- Workshop: repairs/tunes/builds owned assets.
- Paddock: exposes competition machinery.
- Other players/street: social discovery surface.
- Collection: records and presents the Driver–machine relationship.

`/ncm car` remains an alpha provisioning convenience, not mature acquisition. Collection selection may later set an
active asset, request delivery or point to storage, but must not become magical teleportation. Exact acquisition and
access semantics remain part of Machine/economy design.

## Smallest future implementation slice

Using native cars only:

1. author stable `vehicleKey` definitions and record aliases;
2. persist idempotent per-driver discoveries;
3. build the large roster UI with `???` unknowns and a basic discovered dossier;
4. validate one reliable encounter primitive;
5. show restrained first-discovery feedback;
6. prove reconnect/restart persistence;
7. append one catalogue definition and prove clean expansion;
8. leave ownership, acquisition and delivery as separate follow-ups.

## Blockers and risks

- Current `record`-as-identity must gain an NCM key/alias layer before history becomes durable.
- Current ownership is one row per record, not a physical multi-asset garage model.
- Authoritative encounter proximity/stream evidence needs a two-client experiment.
- Ambient traffic is not automatically trustworthy or shared.
- Catalogue-generation snapshots and historical completion persistence do not exist.
- Vehicle dossier metadata/media are largely unauthored.
- Mod record stability, content delivery and rights remain unresolved—but do not block a native-first prototype.

None requires redesigning races today. The critical preventative step is to stop new long-lived systems from treating
TweakDB record strings or live entity ids as the permanent identity of a machine.

## Implementation status — 2026-09-22

The first vertical slice is built, not deployed or live-validated:

- `data.vehicle_catalogue` defines generation 1 with 27 authored identities: every distinct record in the existing
  supported vehicle pool (26 native machines plus the NCX RB15). Base and `_player` records resolve to one key; all
  current RB15 team-livery records resolve to `ncx_rb15`.
- Exact records remain the existing eligibility/provisioning key. OPEN//77 live ids exist only in the short-lived
  registered-entity map. Discovery rows persist only `vehicleKey` plus factual first/last/count/method fields.
- Migration 014 persists immutable generation membership and discoveries. Reusing a generation number with changed
  membership makes the Collection service refuse startup rather than silently rewriting history.
- The initial encounter candidate is server-authoritative: only an NCM-registered canonical vehicle, same bucket,
  exact snapshot record match, within 18 m for three consecutive one-second samples. Arbitrary ambient traffic is
  never scanned. A leave/reapproach can increment encounter count, but the primary key makes first discovery
  idempotent.
- F10 / `/ncm.collectionpage` opens a six-column roster wall. Unknown entries expose only `???`; discovered entries
  reveal their basic dossier and independently derived ownership state. The payload owns the replaceable working
  label `Vehicle Collection`.

The implementation deliberately does not claim the unresolved primitive is proven. [E27](archive/experiments/E27_2026-09-22_vehicle-collection-encounter.md)
is the required two-client experiment. In particular it must verify cross-resource canonical registration delivery,
the exact snapshot `record`/bucket fields, stream-distance behavior, dwell rejection and restart persistence before
this mechanic is marked validated.
