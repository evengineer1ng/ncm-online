# Foundry — vehicle lineage and procedural Vehicle R&D architecture review

> **STATUS: PROPOSAL** — repo-aware architecture recommendation awaiting owner review. **Do not implement
> from this document.** The owner invariants are recorded in `DECISION_RECORD.md` L153; the representation,
> migrations and order proposed here have no authority until ruled on. `L155` now governs the narrower
> Machine-keyed Parts/runtime-binding boundary and derivative performance-channel rules; it does not authorise
> the Foundry schema proposed here.
>
> Date: **2026-09-26**. Scope: existing Cyberpunk vehicle substrates, NCM Parts technology, procedural
> Vehicle R&D, immutable factory specifications, authored appearance reservoirs, bounded manufacturing and
> persistent Machine history. The abandoned AI/generative-geometry Foundry is out of scope.

---

## 1. Executive result

The proposed Foundry fits NCM cleanly if it is treated as **one new product-design layer**, not a replacement
for Parts, manufacturing, Markets or Machine identity:

```text
validated human-controlled runtime substrate -> vehicle lineage
procedural Parts R&D                    -> immutable component designs

lineage + historical component-design snapshot + project collaborators
        + reserved authored appearance treatments
                                      -> deterministic Vehicle R&D project
                                      -> immutable Vehicle Design revision

Vehicle Design + existing batch/cadence/ceiling scheduler
                                      -> production run
                                      -> serialised stock Machine + factory configuration

Machine                              -> ownership, current Parts, wear, repair,
                                        repaint, trade, racing and history
```

Most of the lower half already exists. NCM already has permanent physical `assetId`s, exact runtime records,
stable catalogue keys, production ordinals, asset-keyed ownership, transfer history, an idempotent production
claim, bounded shelf replenishment and persistent supply schedules. Parts already has an ontology, a partial
architecture profile, a fail-closed compatibility resolver and three proven per-instance expression levers.
Those levers now express three component families directly and eight by declared approximation; steering is
the one refused family (`L154`).

The genuinely missing layer is the middle: **vehicle lineage, immutable Vehicle Design revision, persisted
Vehicle R&D project, factory BOM, design ancestry, authored appearance-reservoir allocation and design-keyed
market production.** None of those should be faked with paint names, `vehicleKey` suffixes or per-Machine Part
rerolls.

The safest identity decision is:

- keep `assetId` as the permanent physical Machine identity;
- keep the current `record -> vehicleKey` catalogue invariant;
- do **not** allocate a new `vehicleKey` to every Foundry derivative;
- add an explicit `lineage_id` and immutable `vehicle_design_id`;
- let a released design select a validated runtime substrate while many designs may share that substrate.

Appearance can make shared geometry legible, but it must never be used as the authoritative identity. A repaint
cannot turn one Vehicle Design into another.

No new Carrier primitive is required to model lineages, research, BOMs, production, serialisation or Markets.
The first release is nevertheless blocked on four things: owner approval of the remaining architecture; the
existing Parts Gate 5 decisions; immutable component designs/assets; and runtime proof of how two different
designs sharing one record behave concurrently. `L155` authorises only the prerequisite Machine-keyed
Parts/live-binding correction.

---

## 2. Evidence labels used in this review

| Label | Meaning |
|---|---|
| **KNOWN — CODE** | implemented in the current repository/schema |
| **DESIGNED — UNBUILT** | already present in an owner spec or accepted decision, but not implemented |
| **PROPOSED — FOUNDRY** | new representation recommended by this review; awaiting owner ruling |
| **EXPERIMENT** | a runtime fact that code/docs do not establish safely |

This distinction matters. A schema-shaped paragraph in a SPEC is not a table, and a documented platform
capability is not a live NCM PASS.

---

## 3. What already exists and must be reused

### 3.1 Machine and runtime identity

**KNOWN — CODE**

- `vehicle_asset.asset_id` is the permanent identity of one physical Machine. Ownership, transfer, mileage,
  lifecycle and race attribution attach to it.
- `vehicle_asset.record` is the exact spawn/runtime configuration.
- `vehicle_asset.vehicle_key` is a stored conceptual catalogue identity which survives an upstream record
  rename.
- `data.vehicle_catalogue` permits many runtime records to resolve to one `vehicleKey`, but deliberately
  refuses two conceptual catalogue entries claiming the same record.
- live `vehicleId` is ephemeral. `ncm_world/server/vehicle_access.lua` already keeps an active
  `assetId -> vehicleId/player/record` binding for summoned Machines.
- current production provenance allocates world-global, manufacturer and model ordinals without changing the
  `assetId`.

**Reuse:** Foundry extends this identity stack. It does not replace, reinterpret or fork the asset ledger.

### 3.2 Manufacturing and bounded supply

**KNOWN — CODE**

`economy.production` already implements the exact replenishment rule the owner described:

```text
mint = min(batch, max(0, ceiling - available))
```

It also separates batch from cadence, persists the next committed schedule, claims each tick idempotently,
records the forensic decision and manufactures individually identified assets. `allocation_id` and
`allocation_slot` already carry a batch identity and slot onto each Machine.

**Reuse:** generalise the product key from `vehicleKey` to `vehicle_design_id`; do not build a Foundry scheduler.
A production tick is already the natural vehicle production run.

### 3.3 Parts, compatibility and Engineering

**KNOWN — CODE**

- `parts.ontology` defines twelve component families and refuses effect claims on nonexistent channels.
- `parts.architecture` defines fourteen architecture facets with `derived`, `authored` or `unknown` provenance.
- `parts.compat` returns `fits`, `mismatch` or `unknown_facet`; unknown fails closed.
- `parts.handling` composes three direct and eight explicitly approximated component-family effects onto the
  three proven per-instance levers. Steering is refused. It does not invent inventory, and its first-pass
  approximation weights remain tuning data.

**DESIGNED — UNBUILT**

- component lineage -> immutable component design revision -> fabrication/manufacturing run -> component asset;
- deterministic, auditable Parts R&D which may produce no worthwhile design;
- physical component assets, custody, serviceability, installation, wear and component production;
- stable named installation interfaces/positions and cardinality;
- the distinction between physical compatibility and operational suitability;
- platform inheritance plus vehicle/variant overrides;
- a versioned canonical factory-configuration blueprint;
- persistent configuration snapshots referenced by the already-reserved `configuration_ref` columns.

These are Foundry dependencies, not Foundry reinventions. In particular, a factory vehicle BOM cannot be
correctly represented until the Gate 5 interface/position/cardinality decisions are accepted.

### 3.4 Appearance

**KNOWN — CODE**

- a manufactured Machine gets stable authored-range RGB at mint and stores primary/secondary paint;
- CALL reapplies that stored paint to the exact summoned asset;
- the capability audit identifies the full engine-visible surface as runtime record, entity appearance variant,
  primary RGB, secondary RGB and lights hue.

**DESIGNED — UNBUILT**

- factory appearance and current/repainted appearance are separate facts;
- production allocation, rather than a buyer colour picker, authors the exact factory appearance.

Current code stores only two paint columns and therefore conflates factory and current appearance. It does not
yet persist an appearance variant or lights hue.

---

## 4. The identity model

Do not collapse these layers:

| Layer | Meaning | Stable key | What it is not |
|---|---|---|---|
| Runtime substrate | a validated game-facing record/entity/appearance route | existing `vehicleKey` plus exact record/substrate revision | an NCM derivative |
| Vehicle lineage | the enduring NCM product family made possible by scarce geometry | `lineage_id` | a mechanical platform or paint colour |
| Vehicle Design revision | one immutable reproducible factory product/specification | `vehicle_design_id` | a physical car or a mutable trim loadout |
| Production run | one claimed manufacturing batch/tick of one design | `run_id` plus run slot | the design itself |
| Physical Machine | one permanent automobile | existing `assetId` | its live entity or current setup |
| Current configuration | installed component assets, condition, appearance and ownership now | immutable snapshot ID plus current installation state | the factory specification |
| Live projection | the entity currently materialised in the game | ephemeral `vehicleId` | durable identity |

### 4.1 `vehicleKey` must not become the Vehicle Design ID

The current catalogue uses `vehicleKey` to resolve a native conceptual vehicle from a runtime record. Discovery,
ownership views, production, model ordinals, palettes and compatibility all depend on that meaning. Giving each
Caliburn descendant a new `vehicleKey` while all claim the same record would violate a tested invariant and make
record resolution nondeterministic.

**PROPOSED — FOUNDRY:** leave `vehicleKey` in place as the legacy/native catalogue and substrate identity.
Introduce explicit lineages and map one or more validated catalogue substrates into each lineage. Initially,
one current `vehicleKey` may bootstrap one lineage; after the real mesh/entity audit, several existing native
variants may deliberately become founding designs within one lineage without rewriting their keys.

`parts.architecture.platform` also must not become lineage. Platform is a compatibility root: multiple product
lineages may share one platform, and one platform may have variant-specific interface overrides.

### 4.2 Minimum new identity state

The names below are conceptual, not authorised migration names.

```text
vehicle_lineage
  lineage_id
  canonical_name
  founding_manufacturer_key
  introduced_at
  naming_policy_ref

vehicle_lineage_substrate
  substrate_id
  lineage_id
  vehicle_key
  exact_record / entity-template / appearance provenance
  content_package + minimum-build facts
  validation revision and state

vehicle_design
  vehicle_design_id                    -- one immutable revision
  lineage_id
  substrate_id
  manufacturer_key
  canonical_name
  introduced_world_time
  vehicle_rnd_project_id
  architecture_profile_revision
  resolver_logic_version
  canonical_spec_hash
  factory_bom_completeness

vehicle_design_ancestry
  child_design_id
  parent_design_id
  relationship                         -- predecessor / derived_from / reconstructed_from
  ordinal
```

Released specification columns and referenced BOM/palette rows are immutable. Commercial state—announced,
offered, paused, discontinued, retired—is separate mutable market/lifecycle state. A product ceasing production
does not rewrite what it was.

The ancestry graph should permit multiple parents where provenance truly needs them, reject cycles and require
same-lineage parents for an ordinary successor. A single `predecessor` edge is enough for the common case; the
graph prevents a later collaboration/reconstruction feature from forcing a schema rewrite.

---

## 5. Immutable factory BOM and current Machine state

### 5.1 The factory specification

**PROPOSED — FOUNDRY:** represent the stock engineering specification as normalized immutable rows, not an
opaque per-asset JSON blob:

```text
vehicle_factory_bom_position
  vehicle_design_id
  interface_position_id                -- e.g. brakes.front, power_unit.primary
  component_design_id                  -- immutable component Design revision
  required_quantity / serialisation unit
  requirement_revision
```

This reuses the Parts design identity and the Gate 5 factory-blueprint idea. BOM rows reference component
**Designs**, not component assets and not floating names. `vehicle_asset.factory_json` may later retain a
canonical birth-certificate snapshot/hash for audit, but it must not be the only authority: JSON can drift,
cannot protect referential integrity and is awkward to query for restoration or originality.

Vehicle R&D selects this BOM once. Manufacturing never rerolls it.

### 5.2 Manufacturing materialisation

When component assets exist, one vehicle run should atomically or idempotently:

1. claim the production run and reserve all serial ranges;
2. create the Machine `assetId`;
3. create the required physical component assets from the BOM's component Design IDs;
4. install them at the named interface positions;
5. assign one allowed factory appearance treatment;
6. write an immutable factory configuration snapshot;
7. point current configuration at that starting snapshot;
8. list the Machine into the market if the transaction completes.

A failed retry must collide on run/slot/component idempotency keys rather than create a second engine or half a
car. No Machine should enter inventory until its required factory configuration is complete.

### 5.3 Current state

After manufacture, installation/removal, wear, repair and repaint change the Machine, not the Vehicle Design.
Use the already-reserved `configuration_ref` as a reference to an NCM-authored immutable configuration snapshot:

```text
machine_configuration_snapshot
  configuration_id
  asset_id
  basis / created_at / operation_ref

machine_configuration_position
  configuration_id
  interface_position_id
  component_asset_id
```

Factory appearance and current appearance need separate persisted values or snapshots. Restoration compares the
current component-asset/appearance state with the immutable factory BOM and factory appearance—not with today's
best available Parts and not by rerunning the old R&D resolver.

---

## 6. OEM, supplier and engineering-collaboration provenance

Do not build companies, contracts, employees, equity or royalty simulation.

**PROPOSED — FOUNDRY minimum:** reuse the stable manufacturer-key namespace already carried by the catalogue
and Machine provenance. If it is externalised later, make it a small industrial-actor registry, not a corporate
game system.

```text
vehicle_rnd_project_collaborator
  project_id
  actor_key
  role                                  -- OEM / engineering collaborator / commissioning actor

vehicle_design_contributor
  vehicle_design_id
  actor_key
  role
  source_project_or_operation
```

The BOM itself provides ordinary supplier provenance because each component Design knows its manufacturer. Do
not duplicate every component supplier into the design-contributor table. Add a contributor only when the actor
participated in the vehicle programme as a credited collaborator rather than merely supplying a purchasable Part.

Technology eligibility needs no general corporate-relationship simulator. At project commitment, a component
Design is eligible because it is:

- owned by the vehicle manufacturer;
- legitimately available as third-party production technology; or
- made available by an actor explicitly attached to that project.

Persist that reason with the candidate snapshot. If long-lived alliances later become real gameplay, they can
be an additional source of project collaborators without changing the Design/BOM model.

---

## 7. Deterministic Vehicle R&D over historical technology

Vehicle R&D should use the existing Engineering project philosophy: commit inputs and costs before resolution,
use authoritative elapsed world time, resolve once under a named logic version and store the result forever.

### 7.1 Project commitment

**PROPOSED — FOUNDRY:** a persisted `vehicle_rnd_project` commits at least:

- manufacturer/design owner and explicit collaborators;
- lineage and validated substrate;
- parent/predecessor Design IDs;
- project start and committed world time;
- exact eligible immutable component Design IDs and each eligibility reason;
- architecture/interface blueprint revision;
- compatibility/suitability resolver version;
- vehicle-R&D logic version and deterministic seed/private resolution reference;
- manufacturer objectives/personality and capability snapshots actually used;
- eligible/reserved appearance-treatment IDs;
- committed money, time, capacity and other already-legitimate inputs;
- ready/resolution time.

The exact candidate snapshot is more important than the seed. Re-running the same seed against ten years of new
Parts is not reproducibility; it is a different experiment wearing the old project's name.

### 7.2 Resolution

At resolution, deterministic code:

1. filters the committed technology snapshot through compatibility, suitability and access gates;
2. fills every required factory interface exactly according to its cardinality;
3. evaluates coherence and approved manufacturer objectives using only existing Part properties;
4. refuses combinations whose claimed effects cannot be expressed honestly;
5. compares the result with existing Designs in the lineage under a versioned novelty rule;
6. either records `no_viable_design` / `no_worthwhile_design`, or creates a reviewable candidate specification;
7. promotes the candidate explicitly into one immutable Vehicle Design and converts appearance reservations to
   allocations only after all gates pass.

Vehicle R&D is allowed to produce nothing. It must never keep rerolling until it produces content.

### 7.3 Eligibility and coherence gates

A component Design may enter a factory BOM only when all applicable checks pass:

- it existed and was released no later than the committed project snapshot;
- the project has a persisted legitimate access reason;
- its family/subfamily belongs at the named interface;
- physical mount/protocol/size compatibility passes;
- unknown architecture facts fail closed rather than becoming lucky fits;
- its design rating satisfies the interface's authored required rating;
- all mandatory positions are filled with correct cardinality and no illegal overlap;
- the component Design is repeatably manufacturable, not merely a one-off prototype asset;
- its effect declaration uses a proven record, instance or simulated channel;
- the overall specification stays inside whatever mass, thermal, electrical or other budgets the approved Parts
  grammar actually models—Foundry may not invent hidden stats to make a combination look coherent;
- a released derivative clears a meaningful novelty gate rather than differing only by paint.

At physical manufacture, each produced component asset must also be serviceable/suitable. Design compatibility
does not make a nonfunctional manufactured example safe to install.

---

## 8. Finite authored appearance reservoir

Appearance is a separately managed content resource. Do not place it inside Parts R&D and do not derive it from
the mesh count.

### 8.1 Reservoir item

**PROPOSED — FOUNDRY:** each lineage has versioned, validated renderable treatments:

```text
lineage_appearance_treatment
  treatment_id
  lineage_id / substrate_id
  exact runtime recipe                   -- record/appearance variant/RGB/lights hue as applicable
  authored source and content provenance
  validation build/revision
  state                                  -- available / reserved / allocated / withdrawn / invalid
  exclusivity policy
```

An appearance treatment is not a label such as `blue`. It is an exact recipe the installed game can render on
that substrate and which has passed a runtime validation matrix. The current RGB palettes are the smallest
existing form of this idea; appearance variants and lights hue are not yet wired.

### 8.2 Project reservation and Design palette

Vehicle R&D reserves a bounded subset so concurrent projects cannot spend the same scarce treatment. Failed or
cancelled projects release their reservations. Promotion converts them into immutable
`vehicle_design_appearance` allocations. Default policy should be exclusive allocation to preserve visual runway;
reuse, if ever allowed, must be explicit and auditable rather than automatic.

The Vehicle Design palette is not a set of new Designs. A production run chooses concrete treatment IDs only
from that palette, stores the run's distribution plan, and writes the selected factory treatment/snapshot onto
each Machine. Current repaint is separate state.

### 8.3 Monitoring state

The future dashboard needs only facts, not a dashboard design:

- total treatments authored for the lineage;
- validated and eligible for the current build/substrate;
- available/unallocated;
- reserved by active R&D projects;
- allocated to released Designs;
- withdrawn/invalid with reasons;
- authored low-water threshold and target palette size;
- projected Design runway, e.g. `available / target_palette_size`;
- the specific substrate/build/validation blockers.

`CALIBURN APPEARANCE RESERVOIR LOW` is then a read-model result, not manually maintained state.

---

## 9. Manufacturing, Markets and serialisation

### 9.1 Design release is not economy release

A promoted Vehicle Design may exist historically without being offered. Market/distribution state decides when,
where and at what schedule it enters the economy. This is the seam that permits owner-controlled drip feeding
and scheduled-maintenance content intake without corrupting autonomous Parts or Vehicle R&D history.

Likewise, adding a new validated substrate to the reservoir does not release a lineage; establishing a lineage
does not release every derivative; releasing a Design does not mint infinite Machines.

### 9.2 Extend the existing production vocabulary

**PROPOSED — FOUNDRY:** evolve the current production line, `market_supply_state` and
`market_production_run` from `vehicle_key` to `vehicle_design_id`, retaining `vehicle_key` as a historical/runtime
snapshot. Add a stable `run_id` and preserve the existing tick claim, batch, cadence, ceiling, schedule envelope,
signals and idempotency behavior.

The primary/unique keys must change before two Designs in one lineage can be offered: current
`(server, market, vehicle_key, tick_index)` rows would collide. This is a migration of the existing scheduler's
product identity, not a second scheduler.

One run contains one Vehicle Design and therefore one fixed stock BOM. Permitted variation is represented as
run output:

- planned and actual quantity;
- design ID and spec hash;
- deterministic appearance distribution over the Design's allowed palette;
- run slot for each Machine;
- component-manufacturing operation references;
- market/schedule/logic facts already recorded today.

### 9.3 Serial meanings

Preserve the current global, manufacturer and `vehicleKey` model ordinals. Do not silently reinterpret historical
`model_ordinal` after lineages are introduced.

Add only the two serial facts the new model actually needs:

- `design_ordinal`: this is the Nth Machine made under this exact Vehicle Design;
- `run_slot` / existing `allocation_slot`: this is slot N in this production run.

The `assetId` remains canonical. A Machine can simultaneously be global production #1204, maker #88, legacy
model #27, Design #001 and run slot #01 without any conflict. A lineage ID is an identity, not automatically
another displayed ordinal; add a lineage-wide serial only if a later product requirement proves it useful.

---

## 10. Generation-zero bootstrap

Bootstrapping must preserve unknown history rather than manufacture it.

**PROPOSED — FOUNDRY:**

1. Create deterministic lineage/substrate mappings for the current approved catalogue. Begin one lineage per
   current `vehicleKey` unless the substrate audit has positive evidence that several current keys are founding
   variants of one family.
2. Create one deterministic founding Vehicle Design per existing native conceptual entry. Multiple founding
   Designs may belong to one lineage after an evidence-backed merge.
3. Mark the imported factory BOM as `legacy_external_unknown` or equivalent until the canonical component
   blueprint is authored. Do not create fictional component Design IDs merely to make the table look complete.
4. Do not manufacture new stock from a founding Design whose required BOM is incomplete.
5. Backfill `vehicle_design_id` only where stored `vehicle_key`/record evidence maps unambiguously. Leave unknown
   rows unknown and log them for review.
6. Preserve every existing `assetId`, owner, paint, transfer, ordinal, odometer, result and lifecycle fact.
7. Preserve current `model_ordinal` semantics. Add design/run ordinals prospectively or through an explicit,
   evidence-ordered backfill.
8. Copy current paint into factory/current appearance only when mint-time evidence supports that claim. Where
   the origin is ambiguous, store the current visible value and leave factory appearance unknown.

This creates a historical root without pretending that NCM always had component-level knowledge.

---

## 11. Hard-coded assumptions which break with shared-substrate Designs

**KNOWN — CODE audit**

| Current assumption | Failure once several Designs share one substrate | Required direction |
|---|---|---|
| catalogue `record -> one vehicleKey` | breaks only if derivatives are incorrectly made new catalogue entries | keep it; add `vehicle_design_id` |
| production lines/state/runs keyed by `vehicleKey` | derivatives collide and stock is aggregated together | key offerings and schedules by Design |
| manufacturing chooses `entry.runtimeRecords[1]` | Design cannot choose an exact substrate/appearance recipe | resolve exact record from immutable Design |
| market available/sold counts group by `vehicle_key` | separate derivatives share one shelf count | group by `vehicle_design_id` |
| model ordinal is scoped by `vehicle_key` | cannot say Design #001 | preserve old ordinal; add design ordinal |
| Collection discovery is one row per driver/server/`vehicle_key` | seeing one derivative discovers the whole family | decide and store lineage discovery and Design discovery separately |
| machine knowledge requires `vehicleKey` | observations cannot distinguish derivatives | carry Design ID and asset/config references |
| palette is keyed by `vehicleKey` | every descendant consumes one undifferentiated range | lineage reservoir + Design palette |
| architecture profile is keyed by `vehicleKey` | variants cannot express Design-specific blueprint/requirements | lineage/platform base plus substrate/Design overrides where mechanical truth differs |
| garage model counts deduplicate runtime records | several Designs look like one model | count assets, lineages and Designs explicitly for the relevant UI |
| eligibility reads record/class | cannot distinguish factory homologation or current configuration | retain record for runtime class; add Design/config eligibility where rules require it |
| CALL supports three hard-coded records | most reservoir candidates cannot materialise | validate and add exact placement envelopes per substrate |
| record-wide performance projection | two same-record Designs cannot differ on one client | per-instance channel, distinct record clone, or explicit release constraint |
| `paint_primary/secondary` is both factory and current | repaint destroys restoration truth | split factory assignment from current appearance |

Collection should probably answer two different questions: “have I encountered this lineage?” and “do I know
this exact Design?” Do not overload the present collection slot without a product decision; its unique key can
only record one of those facts.

---

## 12. Runtime identity invariant and shared records

### 12.1 What is safe now

Server-side semantic identity does **not** require one runtime record per Vehicle Design. The server summons by
`assetId`, reads the exact asset row and keeps the active asset-to-entity binding. Persisting
`vehicle_design_id` on that asset is enough to distinguish two derivatives which happen to spawn the same record.
It is **not** enough to target live physics: `KB-146` found that Carrier selected the fastest plausible body rather
than proving the active Machine/entity/body chain. `L155` requires that positive binding and fail-inert behavior.

Appearance also does not need to be identity. It is a persisted property selected from the Design palette.

The current catalogue invariant should therefore remain:

```text
one runtime record resolves to at most one current catalogue vehicleKey
many runtime records may resolve to that vehicleKey
many Vehicle Designs may select a validated substrate under that key/lineage
one Machine asset references exactly one Vehicle Design at birth
```

### 12.2 Where one record is insufficient

The record expression channel is spawn-cached and shared by every instance of that record on one client. It
cannot represent two concurrent derivatives whose required engineering difference relies on different record
flats. The live instance channel can distinguish Machines once `KB-146` is closed; its three levers directly
express tires, power unit and brakes and coarsely express eight other families under `L154`. Simulated effects
remain legitimate server truth but must be labelled when they are not felt.

Therefore every promoted/released Design needs an **expression-feasibility result**:

- safe on a shared record because all differentiating effects are per-instance, simulated or cosmetic;
- requires a distinct runtime-record clone which still points at the same existing geometry; or
- remains legitimately distinct only in simulation/economy/history, with no false felt-performance claim.

A record clone is not new geometry and could still resolve to the same `vehicleKey`, but its feasibility and
delivery behavior are an experiment. A useful clone must include both the vehicle record and its referenced
drive-model record; cloning only the former preserves the shared handling flats. Clone-backed Designs are rare,
restart-bound content releases under `L155`, not ordinary repeat manufacturing. Do not assume them into the
schema or build speculative mesh-import tooling.

---

## 13. Smallest unresolved experiments

Five bounded experiments cover the remaining expensive runtime assumptions.

### E-F1 — two Designs, one record, two live configurations

Spawn two asset-backed Machines using one runtime record, bind different stored Design/configuration effects,
drive concurrently with two clients, transfer/leave/re-enter seats, reconnect and respawn. Verify the correct
per-instance grip/drive/brake profile follows the Machine and restores cleanly rather than following a recycled
player ID.

**Failure that matters:** any setup crosses assets, survives after unbinding, or cannot be restored from the
asset/config snapshot. That would require a binding change; only a proven missing engine surface would justify a
new Carrier capability.

### E-F2 — exact appearance-treatment matrix

For a small lineage, validate record + entity appearance variant + primary/secondary RGB + lights hue across
create, replication, late join, despawn/respawn and damage/repair. Record which dimensions are truly renderable
and whether an appearance variant changes seats, collision, damage or AI behavior.

**Failure that matters:** a recipe does not reproduce for every client or the appearance variant changes the
functional substrate. Such an item is invalid/withdrawn, not an eligible reservoir entry.

### E-F3 — distinct TweakDB records over one existing geometry substrate

Create two controlled vehicle-record clones pointing at one existing vehicle entity/mesh. Give each its own
cloned referenced drive-model record and observably different record-channel settings. Validate both can coexist,
spawn through OPEN//77, survive required-mod delivery/restart and retain independent record-flat behavior.

**Failure that matters:** settings alias, clients require unsafe manual installation, patches make the clone
unresolvable, or OPEN//77 cannot create it reliably. If E-F1 cannot express a required BOM difference and E-F3
fails, that derivative is not releasable—not a reason to falsify its engineering identity.

### E-F4 — usable substrate inventory

Inventory the installed game, not an internet vehicle count: record -> entity/template -> underlying geometry ->
appearance variants -> content package/build -> conceptual family. Then validate spawn, placement, driving,
doors/seats, damage, paint, AI racing and cleanup. This turns the human-controlled mesh reservoir into evidence.

The current 26 native NCM identities are an authored racing subset, not proof that the base Auto Fixer list is
fully represented or that every ownable/NPC record is a distinct usable mesh.

### E-F5 — OPEN//77 per-instance performance surface

In an isolated Development harness, apply `setPerformance(id)` to one of two same-record vehicles and verify
top-speed, acceleration-scale and taper behavior, replication/authority, ownership transfer, leave/re-enter,
despawn/respawn, reconnect and explicit teardown. Repeat with both instances assigned different values.

**Failure that matters:** settings cross instances, follow a recycled player/entity ID, cannot be restored or
cleared deterministically, or create split client authority. Carrier remains the proven force channel; this
surface is adopted only for the narrower effects it actually passes.

---

## 14. What is data/server-side today

Without a new Carrier capability, NCM can implement—after authorisation:

- lineage/substrate inventory and validation records;
- immutable Vehicle Design/ancestry/contributor identity;
- persisted Vehicle R&D projects and exact historical technology snapshots;
- deterministic candidate selection and audit/refusal output;
- factory BOM references to immutable component Designs;
- appearance reservoir/reservation/allocation state for already-proven RGB recipes;
- Design-keyed offerings, supply schedules, production claims and run serialisation;
- generation-zero mappings and idempotent migration rehearsal;
- market, collection, knowledge and provenance read models;
- current/factory appearance and configuration snapshot separation;
- simulated engineering/performance/valuation facts.

NCM cannot honestly ship full factory materialisation today because component Designs/assets, named interfaces,
installation/custody and canonical blueprints are unbuilt. It also cannot promise distinct felt behavior for
every component family. Those are dependency limits, not a reason to create a parallel Foundry parts model.

---

## 15. Dragons

1. **Record aliasing.** Two Designs can share semantic identity safely while still colliding on record-scoped
   physics. Never infer that a different asset/design ID makes the engine record channel per-instance.
2. **Identity collapse.** Lineage, native `vehicleKey`, mechanical platform, runtime record, appearance treatment,
   Design and Machine are related and not interchangeable.
3. **Mutable historical input.** A seed is useless if candidate Part Designs, architecture facts or resolver code
   are allowed to change underneath it. Persist exact snapshots and versions.
4. **Mutable component definitions.** Factory BOMs must reference immutable component Design revisions. Editing a
   Part Design in place rewrites every historical car built from it.
5. **Opaque `factory_json`.** Useful as an audit snapshot, dangerous as the sole BOM authority.
6. **Unknown compatibility.** Most architecture facets remain unauthored. Unknown must continue to fail closed.
7. **Interface/cardinality gap.** A family-level fit answer cannot say how many positions a car has or which Part
   occupies each one.
8. **Appearance fiction.** A database colour or livery name that the game cannot reproduce is not inventory.
9. **Appearance double-spend.** Concurrent R&D needs reservation semantics and a unique allocation rule.
10. **Factory/current conflation.** Repaint or modification must not erase restoration and originality truth.
11. **Production-key migration.** Existing `vehicle_key` primary keys and idempotency keys will collide when two
    Designs share a substrate. Rehearse the forward migration and its replay path before any Design stock exists.
12. **Serial reinterpretation.** Never rename historical model ordinals into lineage/design ordinals after the
    fact. Add explicit scopes.
13. **Release versus research.** R&D completion, Design promotion, market introduction and repeat production are
    four separate events. Collapsing them consumes the content reservoir immediately.
14. **Generation-zero false precision.** Existing Machines have no component-level recorded factory truth. Unknown
    is safer than a beautifully deterministic invented BOM.
15. **Discovery/knowledge collapse.** Current `vehicleKey`-scoped rows would make one derivative reveal every
    descendant unless lineage and Design knowledge are separated intentionally.
16. **Supported-record bottleneck.** CALL currently admits only three placement envelopes. A catalogue row alone
    does not make a substrate summonable.
17. **Patch drift.** Runtime record/entity/appearance recipes need build provenance and revalidation states.
18. **Procedural exhaust.** Autonomous Vehicle R&D must be allowed to produce nothing and release remains a
    separate controlled act, or one lineage will generate meaningless trim noise.
19. **Visual runway.** Engineering depth can grow faster than authored appearance depth. Low-reservoir warnings
    are a release constraint, not merely dashboard decoration.
20. **Corporate overbuild.** Project collaborators and BOM-derived suppliers are enough. Do not model a business
    conglomerate to explain one specialist-engineering credit.
21. **Effect-channel drift.** The authoritative fitted setup belongs to the Machine, while record flats,
    Carrier force levers and a possible OPEN//77 per-instance surface have different scopes and lifecycles. One
    composer must declare which channel owns each claim and restore every channel on unbind.
22. **Unsafe body inference.** `KB-146` proved that a plausible/fast body is not the player's Machine. No
    performance result is trustworthy until asset, live entity and physics body match positively.

---

## 16. Direct answers to the owner's twenty questions

| # | Answer |
|---|---|
| 1 | Asset identity, record/catalogue identity, bounded production, supply state, ordinals, RGB factory paint, Parts ontology/compatibility and a three-lever instance channel already exist. |
| 2 | Reuse `assetId`, stored record/`vehicleKey`, manufacturer keys, production claims/schedules, allocation run/slot, provenance sequences, owner principals, Parts design vocabulary and `configuration_ref`. |
| 3 | Add lineage/substrate mapping, immutable Vehicle Design/ancestry, Vehicle R&D project snapshots, normalized factory BOM, project/design contributors, finite appearance reservoir/allocation, Design-keyed market state and design/run serial facts. |
| 4 | Lineage is the enduring geometry-backed family; Vehicle Design is one immutable factory revision; Machine is the existing permanent `assetId`. Keep platform and `vehicleKey` separate. |
| 5 | BOM rows map stable named interface positions to immutable component Design IDs. Manufacturing materialises component assets once; later configuration snapshots describe installed physical assets. |
| 6 | Use stable actor/manufacturer keys, project collaborators and role-specific design contributors. Derive ordinary suppliers from the BOM; build no contracts/employees/equity simulator. |
| 7 | Commit exact eligible Part Design IDs, access reasons, time, lineage/parents, collaborators, architecture/resolver versions, objectives, seed and appearances; resolve once and persist the complete result/refusal. |
| 8 | Time/access, fail-closed architecture, named interfaces/cardinality, compatibility, rating/suitability, repeatable manufacture, honest expression channels, complete required positions and versioned novelty gates. |
| 9 | Store exact validated render recipes per lineage with available/reserved/allocated/withdrawn states, thresholds and runway counts. |
| 10 | The Design owns an allowed palette of treatment IDs; each run distributes those treatments and each Machine stores its exact factory assignment. Colour never creates a Design. |
| 11 | Generalise existing lines/state/runs to `vehicle_design_id`; keep `min(batch, ceiling-available)`, cadence, envelopes, idempotent tick claims and derived stock counts. |
| 12 | Preserve `assetId` and current ordinals; add immutable Design ID, stable run ID, design ordinal and run slot. Do not reinterpret `model_ordinal`. |
| 13 | Add deterministic founding Designs, backfill only unambiguous assets, preserve every current fact and mark unknown legacy BOM/appearance truth explicitly. Do not manufacture from an incomplete imported BOM. |
| 14 | Store an acyclic ancestry edge set with a normal predecessor relation and optional multiple parents for genuine derivation/collaboration. |
| 15 | Persist committed candidate snapshots, all logic/profile versions, seed/reference, resolution output and refusals, released BOM/palette rows, spec hash, run facts and per-asset factory snapshot. Never recompute history on boot. |
| 16 | Production, stock counts, supply state, runs, ordinals, Collection, knowledge, palettes, architecture, garage counting, eligibility and CALL all assume `vehicleKey`/record is the product. Section 11 enumerates the breaks. |
| 17 | One record per conceptual catalogue `vehicleKey` remains. Semantic derivatives can safely share a record because the asset stores Design ID; appearance is never identity. A record-only physical difference needs the exceptional E-F3 path: distinct vehicle and referenced drive-model records. Concurrent use is never barred merely because substrates are shared. |
| 18 | E-F1 same-record concurrent configs and positive Machine/body binding, E-F2 appearance recipes, E-F3 vehicle + drive-model clones over one mesh, E-F4 the actual game substrate inventory and E-F5 OPEN//77 per-instance performance. |
| 19 | All semantic/data/R&D/market/provenance work can be server-side. Full physical BOM materialisation waits on component assets/interfaces; broader felt behavior may require existing Carrier work, but Foundry itself does not. |
| 20 | Record aliasing, identity collapse, mutable historical inputs, incomplete compatibility, appearance fiction/double-spend, production-key migration, false legacy precision, release/research collapse, patch drift and visual runway are the main dragons. |

---

## 17. Recommended implementation order

Nothing below begins until the owner reviews this proposal.

1. **Close the authorised prerequisite.** Make fitted Parts Machine-keyed and prove the positive
   `assetId -> runtime entity -> physics body` binding required by `L155`/`KB-146`; do not run the old handling
   acceptance drive against the fastest-body heuristic.
2. **Rule the remaining architecture.** Decide the identity split, `vehicleKey` preservation,
   generation-zero unknowns, project-level collaboration model and exclusive appearance allocation.
3. **Close Parts Gate 5.** Accept/amend named interfaces/cardinality, compatibility vs suitability, platform
   inheritance/variant overrides and the canonical factory blueprint. Do not design a Vehicle BOM around the
   current fourteen-facet map alone.
4. **Run E-F1 through E-F5 as isolated evidence work.** In particular, inventory the game rather than adopting
   an internet vehicle count, and prove the same-record concurrency boundary before schema promises it.
5. **Build the immutable identity spine in pure/server code.** Lineage, substrate mapping, Vehicle Design,
   ancestry, contributor roles, validation and canonical hashing. No market or migration of existing assets yet.
6. **Finish the component Design/asset prerequisite.** Implement the already-designed Parts R&D promotion,
   component asset/custody/installation and configuration snapshot layers in their authorised order.
7. **Build Vehicle R&D as a pure deterministic resolver plus persisted project snapshots.** Exercise years of
   simulated history offline; prove restart/replay and `no worthwhile design` outcomes.
7. **Build the appearance reservoir.** Start with proven RGB recipes, add only E-F2-passing variant/hue recipes,
   then reservation, allocation and low-water read models.
8. **Rehearse generation zero.** Produce a dry-run mapping and ambiguity report; do not mutate production data.
   After approval, perform an idempotent additive backfill which preserves unknowns and all existing asset facts.
9. **Generalise the existing market/production product key.** Migrate offering/state/run uniqueness to Design ID,
   add run/design ordinals and deterministic appearance distribution, while retaining the current cap arithmetic
   and forensic schedule state.
10. **Bind factory/current configurations at materialisation.** Spawn by asset, resolve its Design and current
    configuration, publish the per-instance setup, and prove seat transfer/reconnect/respawn restoration.
11. **Release one Development-only descendant in one lineage.** Fixed BOM, small reserved palette, tiny capped
    production line. Pass R&D replay, batch idempotency, appearance, configuration, ownership, modification,
    restoration and two-client same-record tests.
12. **Only then schedule the first controlled economy release.** A new substrate/lineage is a rarer release event
    than a descendant Design; repeat production remains the ordinary batch/tick/Q process.

The architectural invariant at every step is simple: **Parts R&D creates technology; Vehicle R&D freezes a
reproducible factory product from the technology that existed then; manufacturing creates physical examples;
later Machine history changes the examples without rewriting the product that created them.**
