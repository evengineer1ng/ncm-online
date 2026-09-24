# NCM Team Organizations, Economic Roles and Human Motorsport

> **STATUS: CURRENT** - authority for: *organisations, team ownership, governance, grid slots* - affirmed 2026-09-24 (L92, L93; reaffirmed L123)
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

**Status:** architecture assessment and shaped design. **Nothing in this document is implemented.**
**Source:** owner design pass, 2026-09-22 (spec 3 of 3, with the OEM/parts postscript).
**Companions:** [08_ECONOMY.md](08_ECONOMY.md) · [13_VEHICLE_COLLECTION.md](13_VEHICLE_COLLECTION.md) ·
[05_DATA_MODEL.md](archive/05_DATA_MODEL.md). Ideas live in `BACKLOG.md`; decisions in `DECISION_RECORD.md`.

This is the constitution for formal human-run motorsport organizations. It is deliberately not a build order.

---

## 1. Architecture assessment — what already exists

The audit found more of this design already standing than expected, and one specific thing blocking all of it.

### What is already right

**Historical results already preserve team-at-time-of-entry (§13, question 7).** `entry` carries `team_id`,
`seat_index` and `car_number` (schema 005/006), written when the entry is made. Nothing derives a historical
result from a driver's current membership, because *there is no current membership to derive from*. The invariant
"Season 2 results remain Team X results forever" is already structurally true and needs only to be protected.

**A working bilateral offer primitive exists (§14, question 11).** The `message` table (schema 006) has
`from_kind ENUM('team','system','race_control')`, `actions JSON`, `expires_at`, and
`state ENUM('unread','read','accepted','declined','expired')`. `NcmOrganized.invite` offers a seat, the driver
answers `/ncm.accept` or `/ncm.decline`, and the state transition is persisted. Contracts do not need a new
offer/acceptance mechanism invented — they need this one generalised beyond seats.

**The ledger is already the single source of economic truth (§31, question 8).** Schema 004 built `ledger`
(`kind`, `amount`, `currency`, `ref`, `note`) from the first race, deliberately at zero amounts (L21). L84 already
rules that **balance is derived from the ledger, never a second mutable truth** — which is exactly the
conservation discipline §31 asks for, decided weeks before §31 was written.

**Idempotent settlement is already a scheduled hold, not a new requirement (§11, §30, question 12).** L85 hold #1:
*"the `idem_key` migration lands before any amount is non-zero. Duplicate charge, duplicate settlement and
restart/retry are gate tests, not nice-to-haves."* §30's invariant `settlement retry → does not duplicate money`
is already the project's own position.

**Driver identity carries no team field (question 4).** `ncm_driver` is `(ncm_driver_id, created_at, origin)` and
nothing else. Affiliation therefore has nowhere to accidentally live, and can be introduced as its own table with
its own lifecycle — which is what §2 and §30 require.

**Street and sanctioned structures are already separable (question 14).** The street pack is five cadence-driven
championships with venue registration; organized events are a different path (`invitation`, `registration
ENUM('venue','advance')`, `seats_total`, `pack_id`). §19's "do not reskin the corporate hierarchy into street
crews" costs nothing to honour because the two paths already diverge in the schema.

### What exists but means something different

**`team` is an authored competition team and must become a player organization (questions 1 and 2).** The
`team` table (schema 005) is `(server_id, team_id)` with `pack_id`, name, short, colour, livery, seats. Its ten
rows are the NCX pack's constructors, seeded from `core/competition/teams.lua`, where `teamId` deliberately
equals the RB15 livery key so the two cannot drift. There is **no owner, no manager, no treasury, no lifecycle
and no history**.

> **Owner ruling, L92.** These are *not* immutable authored constructors outside the player system. The NCX ten
> use the same organization substrate as every other sanctioned team and must ultimately be ownable and operable
> by players — motorsport ownership of the racing organization, never ownership of the wider Cyberpunk brand.
> They are the **founding NCX grid, not the permanent complete grid**. NCX becomes a highly governed, prestigious
> *use* of the ordinary substrate, with championship rules layered above it — **not a parallel implementation**.

This reverses the assessment's first recommendation, and it exposes a coupling that must be undone.
`teams.lua` sets `teamId == livery` key *"so the two never drift"*, and `liveryRecord()` builds
`Vehicle.v_sport1_rb15_f1_<livery>` from the team id. That coupling is a sound safeguard for authored content and
an obstacle for a governed rebrand (L94), where the livery can change while the organization must not.

**Identity must therefore be decoupled from livery.** `organization_id` becomes stable and opaque; name, short,
colour and livery become **effective-dated branding versions** carrying an approval reference, so
*"Yorinobu, 2027–2031"* stays true after a rebrand. This is the same dated-relationship discipline as ownership,
applied to identity.

**`seat` is event-scoped, not an affiliation (question 5).** `seat` is keyed `(event_id, team_id, seat_index)`.
It answers "who drove car 2 for Herrera in *this event*", which is exactly right for §13 and exactly wrong as a
membership record. Persistent affiliation is a genuinely missing concept, not a rename of this one.

**`team_car` is keyed by record, not by asset (question 9).** `(server_id, team_id, car_index) → vehicle_def`.
Like `owned_vehicle`, it cannot represent two physical examples of the same machine, and it has no provenance.
It needs the same `assetId` migration as driver ownership (spec 2, IDEA-157) and for the same reason.

### The one thing blocking everything

**The ledger is keyed `ncm_driver_id CHAR(36)` with a foreign key to `ncm_driver`.**

An organization is not a driver. As written, a team treasury cannot hold a single ledger row. Every other part of
§10 and §11 — capitalisation, revenue, payroll settlement, retained earnings, owner distribution — is downstream
of that one column.

This is question 10, and the answer is yes: **generalise the ledger from a driver to a principal.**

```text
ledger.ncm_driver_id            →   ledger.principal_kind ENUM('driver','organization')
                                    ledger.principal_id   CHAR(36)
```

One generalisation pays for three separate requirements:

| Requirement | Served by the principal |
|---|---|
| §10 team treasury, separate from the Owner's wallet | an organization principal holds ledger rows |
| §15 `ownerPrincipal` = Driver **or** Organization | the same vocabulary for asset title |
| §11 settlement recipients | a settlement credits principals, not driver ids |

**The timing is the important part.** Every ledger row today has `amount = 0` (L21). L85 already schedules an
`idem_key` migration that must land *before any amount is non-zero*. That is precisely the same moment the
principal generalisation must land, and for the same reason: after real money exists, both become migrations over
meaningful value rather than over zeroes.

**Recommendation: fold the principal generalisation into the already-planned `idem_key` migration.** One
migration, at the last moment when it is free, serving the economy slice and the organization spine at once.

---

## 2. Conflicts and assumptions this design exposes

| # | Conflict | Consequence | Resolution |
|---|---|---|---|
| 1 | `ledger` FK-bound to `ncm_driver` | no team treasury is possible | generalise to principal, inside the L85 `idem_key` migration |
| 2 | `team` means "authored constructor", but L92 requires the NCX ten to become player-ownable organizations | they need owners, treasuries, lifecycle and history they do not have | migrate the ten into `organization` rows on the ordinary substrate; NCX governance layers above, it does not fork |
| 2b | `teamId == livery` key, coupled on purpose *"so the two never drift"* | a governed rebrand (L94) changes livery while the organization must not change | decouple: opaque `organization_id`, livery moves into dated branding |
| 2c | no concept of a grid slot separate from the team | an NCX organization folding would take its grid presence with it, which L93 forbids | `sporting_charter`, held by governance and returned on a fold |
| 3 | `team_car` keyed by record | cannot express two examples, no provenance | same `assetId` migration as `owned_vehicle` (IDEA-157) |
| 4 | `entry` has `team_id` but no `entry_type` | privateer is *implied* by `team_id IS NULL`, which §3 forbids | explicit `entry_type ENUM('team','privateer')` |
| 5 | `seat` is the only team↔driver link and it is per-event | no affiliation to enforce the One-Team Rule against | separate `team_affiliation` table with effective dates |
| 6 | `ncm.grant` mints ownership from nothing | violates §31 and spec 2 §13 conservation | becomes an authored supply channel (IDEA-149) |
| 7 | `competition.teams.SEATS_PER_TEAM = 2` is a module constant | §12 forbids one universal seats-per-team | seats move to series/championship rules; the NCX pack keeps 2 as *its* rule |
| 8 | no economy is implemented at all | every §8–§11 number is unavailable | correct, and it must stay that way — L85 hold #2 |

Assumption worth stating plainly: **§8's economic personalities cannot be validated offline.** Whether Drivers
are genuinely high-variance and Owners genuinely exposed is an observed property of a running economy, not a
property of a schema. The architecture must be able to *express* those outcomes; it cannot guarantee them, and no
test will prove them.

---

## 3. Recommended persistent identity model

Conceptual, not final DDL. It follows the existing conventions (`server_id` scoping, CHAR(36) ids, effective-dated
history rather than mutation).

```text
organization
  organization_id      CHAR(36)          -- persistent, opaque; survives ownership change AND rebrand
  server_id
  lifecycle_state      ENUM('active','inactive','dormant','folded')   -- §18: never deleted
  founded_at
  -- NO owner column: ownership is a dated relationship, not a property
  -- NO name/livery columns either (L94): branding is dated, below

organization_branding                     -- L94: a rebrand is governed, and history survives it
  organization_id, name, short, colour, livery
  effective_from, effective_to?
  approved_by, approval_ref               -- a real rebrand, not a text-field edit

organization_ownership                    -- §16 "ownership changes, identity persists"
  organization_id, owner_principal, effective_from, effective_to?
  acquired_via ENUM('founded','purchased','transferred','governance_reallocation')   -- L93

sporting_charter                          -- L93: the grid slot, held by governance, NOT by the organization
  charter_id, series_id
  held_by_organization_id  NULL           -- NULL = vacant, awaiting reallocation
  effective_from, effective_to?
  -- an organization folding RETURNS its charter; it cannot destroy the grid slot

team_affiliation                          -- §2 the One-Team Rule lives here
  ncm_driver_id, organization_id
  role ENUM('owner','manager','driver')
  effective_from, effective_to?
  UNIQUE (ncm_driver_id) WHERE effective_to IS NULL   -- at most one ACTIVE affiliation

series/championship config  (extend existing, in the pack)
  entry_model ENUM('team','privateer','mixed')        -- L97: the SERIES decides, never the organization

entry  (extend existing)
  entry_type ENUM('team','privateer') NOT NULL        -- §3: a status, not a hidden one-person team
  organization_id  NULL                               -- snapshot at entry time
  assigned_asset_id NULL                              -- §15 access, not title

ledger (generalise existing)
  principal_kind ENUM('driver','organization'), principal_id
  idem_key  UNIQUE                                    -- L85 hold #1

settlement                                            -- §11
  settlement_id, event_id, organization_id?
  inputs (authoritative results reference)
  status, idem_key UNIQUE
  -- produces ledger rows; never mutates them
```

Four notes on why it is shaped this way.

**The One-Team Rule is a database constraint, not application logic (§2, §30).** A partial unique index on
"affiliation with no end date" makes a second active affiliation *impossible to write*, rather than something
three call sites must each remember to check. On MySQL this is expressed as a generated column holding
`ncm_driver_id` when `effective_to IS NULL` and NULL otherwise, with a unique index over it. The same discipline
the Vehicle Collection's primary key gave us for anti-farm credit (IDEA-137).

**Ownership is a dated relationship, never a column on the organization (§16).** An `owner_id` column would make
"Owner A sold to Owner B in 2032" unrepresentable without destroying the earlier fact. Ownership *transfer* is
then an insert plus an end-date, not an update — and organizational history survives by construction.

**Nothing is ever deleted (§18).** `lifecycle_state` includes `folded`, and a folded organization that won a
championship keeps its results, because results reference `organization_id` and organizations are never removed.

**Settlement produces ledger rows and never edits them.** The ledger stays append-only; a correction is a
compensating entry. This is what makes §11's "money must not duplicate or disappear because of retries" testable
rather than aspirational.

### The invariants, and where each is enforced

| Invariant (§30) | Enforced by |
|---|---|
| one identity → at most one active affiliation | unique index on active affiliation |
| Owner cannot occupy a team Driver seat | role check at seat assignment + One-Team Rule |
| Owner cannot service own team's machinery | capability check at service time (§21) |
| privateer entry does not alter affiliation | `entry_type` is on `entry`, affiliation on its own table — no shared column |
| historical result does not mutate after a team change | `entry.organization_id` is a snapshot; results never join to current affiliation |
| team ownership transfer does not create a new team identity | `organization_id` is never reissued; ownership is dated |
| vehicle access does not imply ownership | assignment references `asset_id`; title lives on the asset's `owner_principal` |
| settlement retry does not duplicate money | `idem_key UNIQUE` on both settlement and ledger |
| **Owner is never also Manager or Driver** (L95) | the same unique active-affiliation index — role lives on that one row |
| **folding an organization cannot destroy a grid slot** (L93) | the charter is held by governance; folding sets `held_by = NULL` |
| **a rebrand preserves history** (L94) | branding is dated; `organization_id` never changes |
| **an organization cannot admit or veto a privateer** (L97) | `entry_model` is series config, unreadable/unwritable by the organization |

---

## 4. NOW / FOUNDATION / LATER / DO NOT BUILD

### NOW (nothing to build; one thing to decide)

**Fold the ledger principal generalisation into the planned `idem_key` migration.** Both must land before any
amount is non-zero. This is a sequencing decision, not an implementation, and it is the only part of spec 3 that
is time-critical — because it gets strictly more expensive the moment money becomes real.

Everything else in spec 3 is correctly blocked behind L85 hold #2: the economy does not begin until Deploy 11 is
validated. Spec 3 is a larger economy than the one that hold was written about, so the hold applies more, not less.

### FOUNDATION (the smallest safe slice, when the hold lifts)

In dependency order. Each step is independently useful and independently testable.

1. **Ledger principal + `idem_key`** — one migration, amounts still zero.
2. **`assetId` and `owner_principal`** — spec 2's asset spine, which team assets and driver ownership share. This
   is the same work as IDEA-157 and is not additional cost to spec 3.
3. **`organization` + `organization_ownership` + `team_affiliation`** — identity and the One-Team Rule, with no
   economics attached. An organization can be founded, owned, affiliated with, and transferred. It cannot yet pay
   anyone, which is fine: §16 and §18 are about identity surviving, and they can be proven without money.
4. **`entry.entry_type` + `entry.organization_id`** — privateer becomes explicit, and entries snapshot their
   organization. Cheap, and it protects the §13 invariant before there is history worth protecting.
5. **Settlement skeleton at zero** — the same trick L21 used for the ledger: build the settlement path, run it on
   every race, produce zero-amount rows, and prove idempotency under restart before a single eddie is real.

Step 5 is the one worth insisting on. Every economic defect this project will have is a settlement defect, and
settling zero is the only way to find them without cost.

### LATER (shaped, unscheduled)

Contract lifecycle beyond a simple offer; roster and reserve management; series entry structures (§12) and
team-only grids; Manager permission granularity; treasury policy and owner distribution; organization acquisition
pricing; engineering capability; the parts economy and OEM/aftermarket compatibility; dealerships as discovery
surfaces.

### DO NOT BUILD (§28, restated so it survives this document)

Complete contracts · team economy balancing · invented salary numbers · transfer windows · team-management WebUI ·
corporate acquisitions · bankruptcy · sponsorship simulation · factory teams · exclusive mechanic employment ·
engineering progression or skill trees · parts catalogue, production or trading · repairs · tuning · physical
garage businesses · mechanic minigames · team headquarters · pitwall systems · street crews · NPC employees ·
AI Drivers · remote vehicle teleportation.

---

## 5. Required OPEN//77 / runtime probes

Only three questions in this design are empirical. Everything else is schema and rules, which the offline gate
can settle without a server.

**P-A · Can a vehicle be authoritatively assigned to a driver who does not own it?** §15 requires access without
title: a Driver sits in a team car, drives it, and leaves the team without taking it. NCM already spawns team
cars at grid slots (M7-lite), so the spawn half is proven; what is not proven is whether access can be granted
and revoked while the vehicle persists, rather than by despawning and respawning it. *Bearing:* §15 and the
player-facing fiction of §5 in spec 1 (cars stay where they are, title moves).

**P-B · Does anything in the platform assume a vehicle's operator is its owner?** Before ownership is generalised
to principals, confirm no platform path infers permission from occupancy. *Bearing:* the
`vehicle access ≠ ownership` invariant.

**P-C · Physical service interaction (§26).** Whether "car present, engineer present, capability present, work
occurs" is expressible at all — proximity, dwell and a persistent state change. **This is the same primitive the
Vehicle Collection needs** (`13_VEHICLE_COLLECTION.md`, discovery contract), so the probe should be run once and
its result used twice. Note that KB-53 showed our first attempt at that primitive called a platform function that
does not exist, so the probe must be run against real snapshots, not assumed.

Nothing here should be claimed feasible before these are run.

---

## 6. Tests and invariants required before any part is considered valid

Per L69, code plus offline proof is `built`; only a live PASS in `wp/MASTER_TEST.md` is `validated`.

**Offline gate — the invariant table in §3 is the test list.** Each one gets a test that *can fail*, verified by
mutation (the lesson of KB-57):

- a second active affiliation is rejected — at the database, with the application check disabled
- an Owner is refused a team Driver seat, and refused for the *right reason* (`owner_cannot_drive`, distinct from
  `no_seat_available` — the refusal-reason discipline of L83 and `eligibility.lua`)
- a privateer entry leaves affiliation unchanged, and an affiliated driver's privateer entry is not recorded as a
  team entry
- a result written under Team X still reads as Team X after the driver joins Team Y
- an ownership transfer preserves `organization_id`, its results and its history
- **settlement is idempotent**: the same settlement applied twice produces one set of ledger rows; a settlement
  interrupted mid-write and retried produces one set; the ledger sums identically either way
- the ledger never mutates — a correction is a new row
- conservation: for any settlement, credits equal debits and no principal is created or destroyed

**Live gate.** Nothing in this design may be marked validated on the strength of green tests. The economic
personalities of §8 in particular are observed, not proven.

---

## 7. Architectural decisions that would prevent the later engineering/parts economy

Recorded because each is cheap to avoid now and expensive to reverse later.

1. **Treating team upgrades as a menu.** §22 and §25: if teams ever gain performance through an "upgrade" that
   consumes nothing, the parts economy has no demand side and cannot be retrofitted. Any future team improvement
   must consume a physical component from authored supply.
2. **Engineering as a team role.** §20: adding a fourth role under Driver would bind capability to employment and
   make Driver-Engineer and Manager-Engineer unrepresentable. Capability belongs to the *player*, orthogonal to
   affiliation — which is why §32 keeps role, affiliation, profession and event representation as four separate
   facts rather than one `playerType`.
3. **Parts as rows on a vehicle.** §25 and the postscript §G: a part must be a persistent object with its own
   origin and supplier that *survives trading* and is *consumed* by installation. Modelled as a column on the
   vehicle, provenance is destroyed at install and parts can never be traded.
4. **Compatibility as `part.manufacturer == vehicle.manufacturer`.** Postscript §B and §E: this forecloses the
   entire aftermarket. Compatibility must be an authored property of a component family, and *who made a part* and
   *what it fits* must stay two separate facts.
5. **Rarity tiers.** Spec 2 §1 and postscript §J: a COMMON/RARE/EPIC/LEGENDARY ladder substitutes a label for an
   economy, and once players learn the ladder it cannot be removed. Value must emerge from supply, compatibility,
   capability and demand.
6. **Remote service.** §26: if technical work is ever performed from a menu, the physical-presence requirement
   cannot be reintroduced without removing a capability players already have.
7. **Collapsing the four identifiers.** `vehicleKey` · runtime record · live `vehicle_id` · `assetId` — spec 1 §G,
   spec 2 §14. Every system that touches a vehicle must keep all four distinct.

---

## 8. Owner rulings, 2026-09-22 (L92–L97)

All four questions are answered; the rulings are recorded in `DECISION_RECORD.md` and folded into the sections
above rather than appended as errata.

| Question | Ruling |
|---|---|
| Do the NCX ten become organizations? | **Yes — same substrate, governed above.** Founding grid, not permanent grid. (L92) |
| Can an Owner also be Manager? | **No.** Owner, Manager and Team Driver are mutually exclusive; an Owner must appoint another human. (L95) |
| What happens to affiliation when an organization folds? | **Affiliations end, people go free, nothing historical is deleted.** No penalty state for the former Owner. (L96) |
| Privateer entry: series rule or organization discretion? | **Series rule, always.** (L97) |

Two rulings added structure the assessment did not have:

**The sporting charter (L93).** The assessment modelled two things — organization and dated ownership. Preserving
an NCX grid slot through a collapse needs a third: a charter held by governance and allocated to an organization,
which a fold *returns* rather than destroys. Ownership transfer consequently needs a governance-initiated path
(`governance_reallocation`), not only an owner-initiated one.

**Dated branding (L94).** A governed rebrand means name, short, colour and livery cannot be columns on the
organization. They become effective-dated versions carrying an approval reference, which is also what makes
*"Yorinobu, 2027–2031"* remain a true statement afterwards.

One ruling turned out to cost nothing. **L95 is already enforced by the One-Team Rule**: role is a column on the
single active affiliation row, and the unique index permits exactly one such row per identity — so an Owner
structurally cannot hold a Manager or Driver affiliation anywhere, including in their own organization. The rule
the owner wanted and the constraint already proposed are the same constraint.

### Still explicitly undesigned

Bankruptcy and liquidation mechanics (L96), the governance review and rebranding system (L94), and charter
auction/reallocation procedure (L93). Each is named so the data model does not foreclose it. **None is to be
invented now.**
