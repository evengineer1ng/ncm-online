# Procedural component / parts ecosystem — architecture + ontology spec

> **STATUS: SPEC** - owner intent, captured and **NOT authorised for implementation**. Do not build from it; do not contradict it. Covers: *the procedural component/parts ecosystem*
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

**Status: SPECIFICATION CAPTURED 2026-09-23. Nothing built, nothing authorised.** Spec 1 of a batch the owner
is sending; capture-only until they say otherwise. This document is the faithful record of the spec plus a
first pass at which existing NCM primitives it should reuse — written now, while the connections are fresh,
so the eventual implementation does not start by re-deriving them.

> Do not make the parts yet.
> Build the periodic table, the grammar, and the factory that can eventually make them.

---

## The governing asymmetry

**Cars are expensive authored, rendered objects. Parts are not.** A vehicle model must exist in
REDengine/Cyberpunk content before anyone can drive or see it. A component needs no 3D representation at all —
it can be authoritative NCM data with a lightweight 2D identity later (image, icon, glyph, product card).

That asymmetry is the whole reason this system can be far more procedural and expansive than the vehicle
catalogue. Plant the grammar once; let an industrial history emerge.

## Four layers, kept separate

| Layer | Does | Does not |
|---|---|---|
| **Mechanical ontology** | says what kinds of component can exist | say what they do mechanically |
| **Compatibility** | says which designs fit which vehicle architectures | enumerate per-model lists |
| **R&D** | introduces new component **designs** over server history | manufacture anything physical |
| **Manufacturing / supply** | creates physical component **assets** from an existing design | invent designs |

R&D does not manufacture. Manufacturing does not design.

## Explicitly out of scope for this pass

Performance effects of any kind — buffs, penalties, percentages, top speed, acceleration, handling, grip,
quickhack mappings, vehicle-effect mappings. Also: wear formulas and rates, failure conditions, repair
recipes, mechanical symptoms, diagnosis gameplay, terminal vehicle failure, component balance, rarity tiers,
loot tiers, quality colours, 3D component models, mechanic minigames.

**Effects come only after a separate audit of what Cyberpunk / OPEN//77 / NCM can actually manipulate.** Do
not speculate them into the schema. The point of this pass is to give those eventual effects a coherent
mechanical world to inhabit.

## The component periodic table

Twelve families, first pass. Room to refine if repo inspection gives a structural reason; **do not casually
collapse them**. Each family carries potential subfamilies, the architecture facets it may need to express,
the objects worth generating, and what it should normally abstract away.

| Family | Meaning | Normally abstracts away |
|---|---|---|
| **Power unit** | produces motive power | pistons, bearings, valves, seals, fasteners |
| **Cooling / thermal** | moves and rejects heat | hoses, clamps, coolant quantities, fittings |
| **Transmission** | converts/selects output before final drive | bearings, synchros, small internals |
| **Drivetrain** | carries torque to the driven wheels | joints, boots, bearings, fasteners |
| **Tires** | replaceable contact medium | tread blocks, microscopic simulation, pressure/temp detail |
| **Brakes** | controlled deceleration | lines, fluid, individual pistons |
| **Suspension** | controls wheel movement and body motion | bushings, ball joints, small mounting hardware |
| **Steering** | input to road-wheel direction | column bearings, small linkage hardware |
| **Electrical / control** | vehicle-wide power, sensing, computation | wires, fuses, connectors, relays |
| **Aerodynamics** | airflow for stability, drag, cooling, downforce | tiny appendages, fasteners |
| **Structure** | load-bearing physical integrity | welds, cosmetic panels, fatigue simulation |
| **Chassis** | the platform everything else attaches to | — see below |

**Chassis is deliberately unusual.** It is partly a family and partly *the root of the compatibility tree*.
The identity-bearing chassis of a persistent vehicle must not behave like a casually swappable part:
"replace chassis" cannot become equivalent to replacing brake pads. Keep three things apart — vehicle
identity, vehicle architecture, and replaceable chassis-related assemblies.

**On tires:** do not assume individually serialised physical tires. Find the cleanest abstraction (set? axle
pair? specification?) from the domain model.

## Compatibility is derived, not listed

Vehicle models expose a **mechanical architecture profile**; components declare **constraints against it**.
The resolver relates them.

The scaling requirement is explicit: when NCM adds vehicle model #83, nobody should have to edit thousands of
historical component definitions. The new vehicle states its architecture, existing components state their
requirements, and compatibility falls out. **Exact model-specific fitment must remain possible** for
components that genuinely need it.

Facets the profile may describe: propulsion architecture, power-unit family/interface, thermal architecture,
transmission interface/type, drivetrain layout, axle/wheel configuration, wheel/tire fitment classes, brake
interfaces, suspension architecture, steering architecture, electrical/control architecture, aero mounting
capability, structural architecture, chassis/platform identity.

## Design identity vs physical asset

A **component design** is analogous to a vehicle model — *"Makigai KX-17 Thermal Circulation Pump"* names a
specification, not one pump. A **component asset** is one manufactured example: KX-17 unit #000001, #000002…

Design carries: immutable identity, manufacturer, family, subfamily, lineage/revision, the R&D event that
introduced it, compatibility constraints, installation position/scope, OEM/third-party relationship,
production specification, deterministic generation provenance, product name, descriptive metadata.

Asset carries: componentAssetId, designId, manufacturer, production ordinal, manufacture event, batch
provenance, owner/custodian, storage state, installation state, installed vehicle assetId, component-local
lifecycle/exposure, service history.

> **INSTALLING A COMPONENT CHANGES WHERE IT IS. IT DOES NOT CREATE IT.**
> **REMOVING A COMPONENT CHANGES WHERE IT IS. IT DOES NOT DESTROY IT.**

A used component moved between compatible cars keeps its history. It does not reset.

## Procedural R&D

Manufacturers introduce new designs autonomously over server history. **Not** LLM generation, machine
learning, uncontrolled randomness, admin-authored weekly content, or stat soup. Bounded, deterministic,
auditable, reproducible, idempotent, constrained by the authored grammar.

> **The generator may create new content inside the mechanical grammar. It may not invent new game
> mechanics.** It cannot decide that a brake pad makes a vehicle invisible.

**R&D must be allowed to produce nothing.** A cycle may deterministically conclude *no worthwhile new design*.
New designs should be **events, not exhaust**. A novelty/distinctiveness gate is needed — architect for it now,
define it later, because distinctiveness depends on effects that are out of scope.

**Manufacturer R&D personality** reuses the philosophy of the supply profiles (L118) but is a *separate
authority*. Two manufacturers running the same mechanism should produce meaningfully different industrial
histories. Private parameters, never exposed to players.

## Procedural naming

First-class, deterministic, bounded — and deliberately **not one uniform voice**. A spectrum from dry factory
nomenclature (*MX-14 Thermal Pump*, *KX-17B Circulation Assembly*, *Series 6 Drive Controller*) to commercial
aftermarket flair (*Rocket Blaster X*, *Vortex RS*, *NightPulse 4*). Examples are flavour, not literal.

It must understand manufacturer naming personality, family/subfamily, lineage, revision/generation, OEM vs
aftermarket context, collision avoidance, and continuity between successors — a successor should read as a
successor, not an unrelated random name.

**Names are presentation. Store stable identity independently; never key the database on a name.**

## R&D vs manufacturing, and industrial history

A manufacturer does not invent a product because inventory is low. A new design does not imply stock. Old
designs do not vanish when successors appear. That permits: Design A introduced → manufactured → Design B
introduced → A continues → A becomes uncommon → old machines still need A or a compatible alternative.

Do not implement discontinuation/scarcity rules yet; preserve the architecture for them.

## Supply, storage, secondary market, barter

**Supply:** reuse NCM's authoritative principles where they fit — discrete batches, cadence, shelf capacity,
manufacturer behaviour, idempotent production, conservation, provenance, primary vs secondary. Do **not**
blindly duplicate the vehicle implementation if components need different abstractions. The economic truth is
the same: a physical component entering circulation has an authoritative origin, and nothing is created
because a UI needed one.

**Storage:** parts are ownable and storable independently of vehicles. Do **not** assume Cyberpunk's vanilla
item inventory. A dedicated NCM parts inventory is acceptable and may be preferable. What matters is
persistence, ownership, conservation, installation state, trading, listing, provenance, scalability. Do not
force game-inventory integration for immersion.

**Secondary market:** buy, own, store, list, sell, trade, install, remove, transfer with preserved history.
Transfer must never mint replacement supply.

**Generalised barter — the architecturally load-bearing one.** Trades must eventually span three
value-bearing categories: **money, vehicles, component assets**, in any combination (vehicle + components +
money for vehicle + components, many components for one valuable car, and so on). NCM does **not** judge
fairness — valuation belongs to players. NCM guarantees: each asset exists, the offerer controls it, it is
transferable, money exists, installation/storage state permits transfer, nothing duplicates, nothing
disappears, both sides consented to the exact final offer, atomicity, provenance updates, safe rollback, and
replay/retry cannot duplicate a transfer.

Money-for-money is not a barter case and needs no support.

## Visual identity

No 3D models. Lightweight product representation later: image, icon, glyph, manufacturer mark, family
imagery, product card. A component should be understandable as a **product** — what is it, who made it, what
family, what does it fit, where did it come from, new or used, what is its production identity.

**Do not build a Machine Profile for every component.** Cars are biographical centrepieces; parts need enough
identity to be ownable, tradable and serviceable without pretending every water pump is a protagonist.

## Relationship to future wear and repair

Not implemented here, but this is the direction that **replaces the struck odometer-to-car-death design**
(L119 amended): vehicle mileage and use will predispose installed components toward mechanical conditions,
which will eventually create tactile consequences using only effects verified to be supportable.

**Sporting incidents and mechanical wear stay separate systems.** Bad driving does not damage persistent
property in this pass; the sporting system judges racing behaviour, the lifecycle system represents machine
use and time. Do not connect collision penalties to component damage.

---

## First pass at existing primitives to reuse (not yet verified in depth)

The spec asks for repo inspection before coding. This is the head start, from systems built 2026-09-23:

| Spec concept | Existing NCM primitive | Note |
|---|---|---|
| manufacturer identity | `data.vehicle_catalogue` `MAKER_KEY` → `manufacturerKey` | already stable and authored, not a display string (L119). Components should key off the same identity, not a second one. |
| design vs physical instance | `vehicleKey` vs `assetId` (L119) | exactly the same distinction; the five-identity rule should extend rather than be re-derived. |
| production ordinals | `NcmProvenance` + `production_sequence` | three sequences, optimistic claim with holder nonce, three unique indexes. Components need their own scopes; the mechanism generalises. |
| discrete supply | `economy.production` + `market_production_run` | ceiling/batch/cadence, ceiling-seeking, tick claimed by index. |
| manufacturer behaviour | `economy.supply_profiles` (L118) | the personality mechanism to mirror for R&D — **separate authority**, same philosophy. |
| ownership + conservation | `vehicle_asset`, `market_inventory` | owner nullable = on the shelf; derive stock, never count. |
| transfer provenance | `vehicle_asset_transfer` (idem key) | see the conflict below. |
| money | `ledger` with `idem_key` | already idempotent. |
| forward-only migrations | `NcmSchema` | one transaction per version, `IF NOT EXISTS` convention. |

### Conflicts and decisions this spec will force

1. **Barter breaks the current transfer model.** `vehicle_asset_transfer` is per-asset with a per-asset idem
   key, and `NcmMarket.purchase` is a single-asset transaction. A multi-asset, two-sided, atomic barter needs
   a **trade envelope** — one consented offer id that every leg references — and each leg idempotent under
   that envelope. This is the single largest piece of new transaction architecture the spec implies, and it
   should be designed before parts exist rather than retrofitted after.
2. **Ordinals: shared or separate?** Vehicles use a global NCM production sequence. Components almost
   certainly want their own scopes (global-components, per-manufacturer, per-design) rather than sharing the
   vehicle sequence — otherwise a pump takes a number out of NCM's *vehicle* history. Needs an explicit
   decision.
3. **`origin` already exists on assets** (`production` vs `grant`, L119). Components should reuse that
   vocabulary rather than invent one, and the unresolved IDEA-233 question (should admin grants carry
   serials?) will recur identically.
4. **The architecture profile does not exist yet.** `data.vehicle_catalogue` carries `category`, `classes`
   and `tags` — nothing like propulsion/transmission/axle architecture. This is new authoring against 27
   existing catalogue entries, and it is the prerequisite for derived compatibility.
5. **Tires vs the serialisation rule.** The spec asks for the cleanest abstraction; a per-tire assetId is
   almost certainly wrong, but "a set" conflicts with the general rule that serviceable components have
   individual identity. Needs resolving in the ontology, not at implementation time.
6. **Inventory has no precedent.** NCM has no storage concept at all today — `vehicle_asset` with a null
   owner is shelf stock, and owned vehicles live in the garage view. A parts inventory is genuinely new.

---

# Addendum — markets, distribution, discovery and component access

Captured 2026-09-23 with the spec above; same status, **nothing built, nothing authorised**.

> **MARKETS ARE DISCOVERABLE WORLD KNOWLEDGE.**

## What actually shipped (checked, not assumed)

The addendum says the implementation may be incomplete and to inspect rather than assume. It is incomplete in
a specific and useful way: **the storage and the decision function both exist; the wiring does not.**

| Piece | State |
|---|---|
| `player_market_knowledge` table — driver, server, market, `first_known_at`, `source_kind`, `source_ref`, `access_state` | **exists** (migration 017) and **nothing reads or writes it**. Its only reference in the whole repo is its own `CREATE TABLE`. |
| `economy.markets.known(markets, grants)` — universally-known markets plus granted ids | **exists and is tested** (`test_markets.lua`) and **is never called by the host**. |
| `market.universally_known` | written at seed, and it is what `NcmMarket.payload` actually filters on (`WHERE m.universally_known = 1`). |
| `market.policy_json` | exists, unused. |
| Market rows | exactly one: `base_market`, universally known. |

So the substrate was laid for discoverable markets and then the Market shipped against the simpler
"universally known" path. `source_kind` / `source_ref` / `access_state` already anticipate multiple discovery
authorities — which is precisely what this addendum asks for. **Wiring that up is a smaller job than it
looks, and doing it before parts exist is much cheaper than after.**

## The rule the parts architecture must not violate

> **"If a component exists, every player can browse and buy it"** — must never be assumed.

## The pipeline, and where it must not be collapsed

```
R&D → MANUFACTURING → DISTRIBUTION → MARKET STATE → PLAYER MARKET KNOWLEDGE → EXPOSURE → ACQUISITION
```

Each arrow is a real boundary:

- A **design existing** does not mean a physical example exists.
- A **physical example existing** does not mean every market sells it.
- A **market selling it** does not mean every player knows that market.
- A **player knowing the market** does not mean the item is in stock.
- **Currently sold out** does not mean the product never existed. *(Already locked as L117 for vehicles —
  the offering survives its stock. The same rule now has to hold one level down.)*

## Base Market

It should eventually carry an introductory selection of components: nobody should have to discover a secret
specialist supplier just to meet the parts system at all. It is the **front door**.

But the existing principle holds unchanged: **the Base Market is a market, not THE market** (L117). It must
never become the universal catalogue of every component design in NCM.

## Discovery is content, not a lock

The purpose is not to withhold. It is that a large, continually evolving ecosystem gives reasons to explore,
specialise, progress, talk to other players, trade, revisit known suppliers and build sourcing
relationships.

> The feeling wanted: *"there is always another corner of the automotive world I haven't seen yet."*
> The feeling to avoid: *"the game arbitrarily hid the good shop until Level 30."*

Physical/world discovery is the important intended route: encounter something meaningful in Night City,
interact with it, the market becomes known, **and that knowledge persists** — so F6 becomes the durable
browser for what the player has legitimately learned, without ever needing to revisit the location.

Possible future discovery authorities — *possibilities, not commitments, and not to be hard-coded now*:
world/physical discovery, interacting with a location or access point, engineering progression,
relationships, achievements, motorsport accomplishments. No `Badge X unlocks Market Y` rules yet; just the
architecture for multiple authorities.

## Manufacturer ≠ market, and distribution has scopes

A **manufacturer** designs and builds. A **market** is a distribution surface. One manufacturer may sell
through many markets; one market may carry many manufacturers.

Distribution must be expressible at several scopes — market↔manufacturer, market↔manufacturer+family,
market↔product line/lineage, market↔specific design — so that two markets carrying the same manufacturer can
have meaningfully different catalogues (ordinary replacement line here, specialist line there, a narrow
subset somewhere else).

> **The schema must not make "affiliate manufacturer X with market Y" mean "every current and future X
> product is available at Y forever."**

This matters most because R&D is autonomous: a design that did not exist yesterday, authored by nobody, must
not appear in every storefront the moment it is created.

## Markets are economic entities, not loot tables

A market should have a coherent, learnable identity — stable enough that a player can think *"I know where to
look for Makigai cooling equipment"* or *"that supplier carries the ordinary line but not the specialist
products."* Not interchangeable vending machines whose theme rerolls daily.

Relationships need not be immutable forever (contracts, distribution rights and channels may move later), but
**for the initial substrate, stable authored relationships are preferable** and none of those dynamics should
be simulated merely because the architecture allows them.

## Knowledge, ownership and access are four different facts

Canonical server data is not player knowledge — the same philosophy already locked for vehicles and the
Machine Index. Procedural R&D creating a design must not populate every player's component encyclopaedia.

And for the secondary market, keep these apart:

- knowing a component exists
- owning a component
- knowing its originating market
- having access to that market
- being able to buy another one there

If Player A discovers a specialist supplier, buys a component and trades it to Player B, **B owns it without
gaining access to the market it came from.** That is what makes a specialist valuable — they know where to
source things, not because ownership is magically restricted.
