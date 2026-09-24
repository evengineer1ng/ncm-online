# 07 — The node network as a first-class primitive (audit, 2026-09-22)

> **STATUS: CURRENT** - authority for: *nodes, routes, ordered chains* - affirmed 2026-09-24
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125)

**Status: audit only. Nothing implemented.** Written in answer to the owner's architecture brief. Read
`NOW.md` and `BACKLOG.md` first; this document is the reasoning behind IDEA-103, not a decision record — decisions
go in `DECISION_RECORD.md`.

---

## 1. Current-state findings

### The headline: the migration you are asking for has already happened

The brief assumes the 35 SP nodes are not in Online yet. **They are.** All of them, verbatim.

| Thing | Where | State |
|---|---|---|
| 35 curated nodes | `ncm/core/data/nodes.lua` (`data.nodes`) | **Complete.** Byte-identical rows to SP `data/nodes_curated.lua`, same ids, same headings. |
| 10 roots | `ncm/core/data/roots.lua` (`data.roots`) | **Complete.** Same ids and `displayName`s as SP `data/default_roots_pack.lua` v1.2.0. |
| Routes referencing nodes by id | `data.roots` rows carry `startNodeId` / `endNodeId` | **Already the design.** No root duplicates a coordinate. |
| Events referencing nodes by id | `organized.lua` writes `venue.nodeId` / `finish.nodeId` | **Already carried.** |
| Node table on the client | `shared_script "shared/core/data/nodes.lua"` in `ncm_world/open77.lua` | **Already there.** Every client has all 35 nodes in memory. |

So the Node/Route/Event separation the brief proposes is **not a refactor — it is the existing architecture.**
`course.routes.resolve(rootId, label)` takes a root, looks its two node ids up in `data.nodes`, and returns a
route whose `start` and `finish` *are the node records* (id, name, region, heading, coordinates). Nothing
downstream stores a coordinate that did not come from a node.

### What is actually missing

Exactly one thing, and it is data, not architecture:

```lua
-- ncm/online/resources/ncm_league/server/packs/street.lua
routes = {
    { rootId = "root_tip_1035_3652__to__trench_2899_2711", label = "Tip-to-Trench" },
    { rootId = "root_hill_abode_505_1229__to__downtown_2362_117", label = "Snake in the Grass" },
},
```

**The street series lists 2 of the 10 roots.** That is why the calendar only ever shows two. The cadence walks
`series.routes[(k % #series.routes) + 1]`, so adding the other eight is a data edit.

Two side effects worth knowing:

- **"Tip-to-Trench" is a pack override.** `resolve` does `name = label or root.displayName`, and the root's own
  `displayName` is already **"Ukulele"**. Deleting the `label` key is the whole rename.
- **B-line was never on the calendar.** `NcmOrganized.post` resolves by `routeByLabel`, which searches **all ten
  roots** — so the host kit can already post any of them on demand. That is how a third route appeared.

### The ad-hoc pipeline also already exists

`/ncm.ar` (`scenario.lua`) is a working authored-route recorder: start, drive, drop gates, finish/loop. It
persists to `custom_route` (migration 011) and on boot calls `registerCustom` → `Nodes.register()` +
`Roots.register()` with `custom = true`. `data.nodes` and `data.roots` both expose `register` **and
`unregister`** already.

**So "server creates a route at runtime, from nodes, with a lifetime" is not a new capability.** It exists, it is
host-only, and it is permanent rather than ephemeral.

### The finding that reframes the gate question

**None of the ten official roots has a single intermediate gate.** `data.roots` rows carry no `intermediate`
field; only `/ncm.ar`-authored routes do. `gates.build` produces a start line and a finish line, and
`gates.crossed` accepts either.

That means an official NCM race today is already *"get from node A to node B, by any road you like, fastest
corrected time wins."* Shortcutting is not prevented on Ukulele or Snake in the Grass either. **An ad-hoc A→B
race would therefore be exactly as rigorous as the official catalogue** — which removes the main technical
objection to shipping one, and raises a product question instead (below).

---

## 2. Proposed data model

The three-layer split is right. Stated against what exists:

**Node — permanent authored world infrastructure.** `data.nodes`. Stable id (the SP slug), `name`, `region`,
`x/y/z`, `heading`, and the booleans `road` / `urban` / `waypointable` / `raceLegal`. Runtime-registered nodes
carry `custom = true`.

Worth adding, because the SP format comment already documents them and the author may have the values:
`finishHeading`, `finishWidthM`, `finishArmDistM`. These are real finish-line geometry and `gates.build` would use
them directly — today every finish line is generated from the approach bearing with default width. **Do not add**
speculative fields (grid capacity, elevation class, "vibe" tags, difficulty) until something consumes them.

One genuine gap: nodes have no notion of **start suitability vs finish suitability**. `raceLegal` is a single
flag. If some of the 35 are good finishes but poor grid starts (no room for 20 cars), that is worth a field —
but the author should say which, rather than us inventing a heuristic.

**Route — a directed relationship between two nodes.** Today `data.roots`. The important clarification: a route
between two nodes **needs no stored row**. `resolve` derives everything (distance, region, venue, finish) from the
two node ids. A stored root exists to carry what cannot be derived: a curated `displayName`, a `description`, a
`recommendedMode`, `intermediate` gates, `laps`, `loop`.

So: **stored root = a route someone curated. Derived route = any ordered node pair.** Both produce the same shape
out of `resolve`.

**Event — an instance.** Unchanged; already references `routeId` plus a `venue.nodeId`.

---

## 3. Authority and lifecycle, in prose

The server is authoritative and already behaves correctly in the ways that matter, because **a client never
supplies a coordinate today** — it supplies an event id or an option id, and the server re-derives everything. Any
A→B feature must keep that property: the client sends **two node ids**, never two positions.

What the server must validate on an A→B request: both ids exist in `data.nodes`; both are `raceLegal`; they are
not the same node; the requester has an NCM driver; the requester is not already in a live session
(`NcmRace.busySession`, KB-37); and the pair is not absurd (a minimum separation, or Badlands↔Watson at 20 km
becomes a 20-minute commitment nobody reads).

Lifetime, as it would have to work: a request creates an **ephemeral root** (`Roots.register` with `custom = true`
and an `ephemeral = true` marker) plus an event that is **not published to the calendar**. It lives while it has a
live session or an entrant; it is unregistered on completion, abandonment, or the last participant disconnecting.
Nothing persists to `custom_route` — that table is for authored content. A janitor sweep is required, because
`Roots.register` mutates a shared core table and a leak here grows the route catalogue without bound.

Replication needs are small: the ephemeral event's own bag (the participants already receive `ncmVenue` /
`ncmSession`), and **nothing on the calendar**. The static node list needs no replication at all — the client
already has it.

---

## 4. Smallest useful first slice

The brief's guess was: *import nodes → catalogue → routes reference nodes → expose → ephemeral A→B.* **Steps one
to three are already done**, so the real first slice is much smaller than it looks:

1. **Put the other eight roots in the street series, and drop the `Tip-to-Trench` label override.** Two data edits
   in `street.lua`. This alone takes the calendar from 2 routes to 10 and renames Ukulele correctly.
2. **Add a core test that every node id referenced by every root resolves.** Today a typo in a `startNodeId` is
   discovered when the calendar tries to post. This is the guard that makes step 1 safe.
3. **Expose the node catalogue read-only** — a `/ncm.nodes [region]` list and a node picker in the existing F6
   panel. Zero replication work; the data is already client-side.

That is a real, shippable increment that makes the network visible without committing to any ad-hoc race design.
**Ephemeral A→B should be a second slice**, once the ten routes have actually been raced and we know whether
gate-less point-to-point racing is good.

### What would change

`packs/street.lua` (data), `ncm/core/tests/test_competition.lua` or a new `test_roots.lua` (the resolve guard),
and — for slice 3 only — `guide.lua` (a node payload) plus `panel.html` (a list). **No change to `data.nodes`,
`data.roots`, `course.routes`, `gates`, the calendar or the session kernels.** That is the sign the seam is right.

---

## 5. What SP data can be imported

Essentially none is left to import — it is already here and should not be re-authored. The remaining candidates:

- **`finishHeading` / `finishWidthM` / `finishArmDistM`**, if the author ever populated them. The SP file
  documents them in its format comment but every row in the pool omits them. Worth one grep of the SP save data
  and `user_nodes.json` before assuming they do not exist.
- **`ncm-localized/.../data/nodes.lua`** — the *legacy generated* pool that `nodes_curated.lua` replaced. Probably
  hundreds of auto-placed nodes of much lower quality. **Recommend not importing**; the curated 35 are curated for
  a reason.
- **`courier_nodes.lua`** and `user_nodes.json` — unexamined here; may contain player-placed nodes with the same
  schema.

---

## 6. Unresolved product decisions

- **Do drag routes belong in a street-sprint rotation?** `B-line` and `Hold Your Breath` carry
  `recommendedMode = "drag"`. Adding all ten to the sprint series runs them as sprints. Fine, or do they want a
  drag series of their own?
- **Ten routes at a 20-minute cadence means a given route returns every 3h20m.** Acceptable for a living calendar,
  slow for QA. `ncm.race.now <route>` already covers the QA case, so probably leave cadence alone — but say so
  deliberately.
- **Is gate-less point-to-point actually the product?** It is what ships today. Before building ad-hoc A→B it is
  worth deciding whether official routes should eventually get authored gates (making them meaningfully different
  from ad-hoc ones) or whether "any road you like" *is* NCM street racing.
- **Should ad-hoc results count?** Toward SR, licences, route records, the Fingerprint. This is the real design
  question behind the whole feature, and it is a values question, not a technical one.
- **Start suitability per node** — which of the 35 can hold a 20-car grid.

---

## 7. What having all 35 nodes visible unlocks

Not speculative — each of these has an existing consumer that is currently hardcoded or absent:

- **Race Guide browsing by region.** Nodes already carry `region`; the guide has no regional axis today.
- **Rendezvous / meetup points.** A named, headed, on-road, race-legal location list is exactly a meetup catalogue.
- **Dev and host tooling.** `ncm.tp` currently targets "venue"; it could target any node by name.
- **The chauffeur/pickup system** already searches `data.nodes` for the nearest on-road node (`pickup.lua`) — it is
  the one system that treats the network as a network, and it proves the primitive works.
- **Practice and navigation** between any two nodes, with no timing claims, is the cheapest possible version of
  "drive from any node to any node" and needs no session at all.
- **Telemetry and history** — "nodes visited", "routes discovered" become derivable once nodes are a browsable
  set rather than an implementation detail.
- **Route authoring** gets a starting vocabulary: `/ncm.ar` currently invents its own start/finish nodes; it could
  anchor to curated ones instead.

---

## 8. The one-line summary

**The node network is already a first-class primitive in the data model and is not exposed anywhere.** The work is
not migration or refactoring; it is (a) a two-line data edit to use the roots we already have, and (b) a decision
about whether player-initiated A→B races are a product we want. Those are independent and should not be bundled.

---

# Addendum A — chained routes (2026-09-22, owner follow-up)

## A1. SP already had this, and the Online port narrowed it

`ncm-localized/.../modules/roots.lua` is built on an **ordered node list**, not a pair:

```lua
normalized.nodeIds    = normalizeNodeIdList(normalized.nodeIds, startNodeId, endNodeId)
normalized.startNodeId = normalized.nodeIds[1]
normalized.endNodeId   = normalized.nodeIds[#normalized.nodeIds]
normalized.isLoop      = normalized.nodeCount > 2 and startNodeId == endNodeId
```

`pathDistance(nodes)` sums leg by leg; `resolveNodeList` resolves each id and reports *which index* failed;
consecutive duplicates are collapsed; a root needs "at least two ordered nodes" and "at least two distinct nodes".

**So `A → B` was already the two-node case of a chain in SP, and `startNodeId`/`endNodeId` were derived, not
stored.** The Online port kept only the derived pair and dropped `nodeIds`. That is the regression to undo — this
is restoring a capability, not inventing one.

## A2. Answers to the specific questions

**Should a route store an ordered node list?** Yes, and it is the only field that should exist.
`nodes = { "tip_-1035_3652", "trench_-2899_-2711" }`. `startNodeId` and `endNodeId` become derived accessors kept
only for compatibility with existing call sites. **Two-node routes are the smallest valid case of the same model**
— there must not be a second code path, and SP proves one path is sufficient.

**How do intermediate nodes differ from gates?** They are different kinds of thing and both are needed:

| | Node in the chain | Gate |
|---|---|---|
| Identity | A curated, named, permanent place with a stable id | An anonymous point on the ground |
| Purpose | *Where the route goes* — a waypoint a driver navigates to | *Which road* — proof you did not cut |
| Presentation | Named in the route ("via Gold Niwaki Plaza"), a GPS leg, a split time | Invisible; only its crossing matters |
| Authoring | Picked from the catalogue | Recorded by driving (`/ncm.ar gate`) |
| Reversal | Reverses with the chain | Does **not** reverse — approach bearings are direction-specific |

So yes to the owner's framing: **chain nodes are major waypoints; gates between them enforce the intended road.**
Today Online has gates-without-nodes (`intermediate` raw points on authored routes); SP had nodes-without-gates.
The full model wants both, with gates belonging *to a leg* rather than to the route as a flat list.

**Reverse routes.** Derivable by reversing `nodes`, and it is the right default for a node-only chain: distance is
identical and each node has its own heading. It is **not** safe to auto-reverse a route with authored gates,
because a gate is a directed line with an approach side (`gates.crossed` tests a sign flip from `before > 0` to
`after <= 0`). A reversed route with gates needs its gates re-authored or explicitly mirrored. Direction-specific
metadata stays per-direction: `The Cut` and `Reverse Cut` are already two separate roots in the catalogue with
their own names and descriptions, which is the precedent — derive the geometry, never the identity.

**Timing.** `telemetry.sectors(crossings, gatesTotal)` already computes times between consecutive crossings, and
every driver already stores `crossings[gateIndex]`. Legs fall out of this for free **once chain nodes are gates in
their own right** — which they should be: a node in the chain compiles to a gate, so reaching B is a crossing with
a timestamp. Expose total corrected time as the result (unchanged) and legs as splits. Leg times are presentation
and records; they must not affect classification, which stays on corrected total (L47).

**Records and PBs belong to the exact chain, not the endpoint pair.** `A→C` and `A→B→C` are different races over
different ground, and a route record that conflated them would be false. The record key should be the ordered node
list plus direction — and because `route_record` / `previousBestSec` already flow to B-089 race tags as
*supplied facts*, getting this key wrong would quietly corrupt personal bests. **Today's `routeId` is already
derived from the endpoints** (`root_<start>__to__<finish>`), so a chain needs an id derived from the whole
sequence. SP's `deriveRootId(startNodeId, finishNodeId, nodeIds)` already took `nodeIds` for exactly this reason.

**Promotion.** An ephemeral chain becomes an official route with **no change of abstraction**: same ordered node
list, same resolve path. Promotion is a provenance and curation change — give it a `displayName`, a description,
optionally author gates per leg, mark it non-ephemeral, persist it. That is the strongest argument for chain-first:
*the thing a player builds ad hoc and the thing we ship as official are the same object at different life stages.*

## A3. Server validation for a chain

Each of these is cheap and each prevents a real failure:

- every id exists in `data.nodes`; report **which index** failed (SP already did this);
- at least 2 entries after collapsing consecutive duplicates;
- at least 2 *distinct* nodes;
- no non-consecutive repeat **unless** it is first == last, which is a deliberate loop;
- a maximum chain length — suggest **8**, on the grounds that the longest official route is 6.6 km over 2 nodes
  and an 8-node chain is already a 30-minute commitment nobody will finish;
- a minimum leg length, so `A → A-adjacent → B` cannot be used to farm splits;
- total path distance within a sane ceiling;
- **node ids only, never coordinates**, which is the property NCM has today and must keep.

`North Tunnel → Gold Niwaki Plaza → Trench` passes all of these: three distinct real nodes, Watson → Westbrook →
Pacifica, roughly a cross-city marathon. It is exactly the shape the model should support.

## A4. What changes in the model

`data.roots` rows gain `nodes = { … }` as canonical; `startNodeId`/`endNodeId` stay as derived compatibility
fields so the ten existing roots and every current call site keep working unchanged (each becomes a two-entry
chain). `course.routes.resolve` returns `nodes` (resolved records) and `legs`, and computes `distanceM` as the sum
of legs. `gates.build` takes the chain and emits start + per-node gates + finish, with authored gates slotted into
their leg. **`session.race`, the calendar, progression and the guide need no change** — they already work from
`gatesTotal` and `crossings`.

---

# Addendum B — concurrency and the cadence (2026-09-22, owner)

> *"multiple races can and should be able to run concurrently, not just 1 every 20 mins. prioritize avoiding
> overlap of regions at the same time"*

## B1. The infrastructure is already there; the content is the limit

`calendar.lua` already loops `for _, s in ipairs(seriesList) do lists[#lists+1] = Cal.materialize(s, t, horizon) end`
— **multiple series already materialise concurrently.** There is one series defined, which is why one race runs.
So concurrency needs no new scheduler in the general case; it needs more series, or one series that emits several
events per slot.

Two things do need real work:

- **Event ids collide.** `eventId = seriesId .. "@" .. startsAt` is unique only while one event exists per slot.
  N concurrent events per slot need the route folded into the id.
- **Nothing coordinates regions across series.** Region-disjointness is a global property; `materialize` is
  per-series and pure. Either one scheduler emits the concurrent set, or a selection pass runs across series.

## B2. Disjoint by START region, not by corridor

Measured across the ten roots, by the regions each route touches:

| Region | Routes touching it |
|---|---|
| Heywood | 6 of 10 |
| Westbrook | 4 |
| City Center | 3 |
| Pacifica | 3 |
| Watson | 2 |

Requiring two concurrent races to share **no region at all** yields about **2 simultaneous events, occasionally
3** — Heywood appears in more than half the catalogue and starves everything.

Requiring only that they not share a **start region** yields **5**: the ten starts are Westbrook ×2, Heywood ×4,
City Center, Watson ×2, Pacifica. That is the better rule and it is also the truer one — **players converge at
the venue**, so the start is where overlap actually costs. Two races crossing the same district mid-route is
atmosphere, not a collision.

**Recommendation: disjoint start regions, with a soft preference for disjoint finish regions as a tiebreak.**

## B3. Drag is drag

Owner, 2026-09-22: *"the drag routes are drag, b line was being treated as a generic sprint. it is drag."*
`B-line` and `Hold Your Breath` both carry `recommendedMode = "drag"` in the roots data and both were about to be
swept into the street-sprint rotation by IDEA-104. They need a **drag series** with the `drag` discipline, not a
sprint slot. `data.roots.recommendedMode` is the field that already knows this — the series builder should read it
rather than have a human sort routes by hand.

That also means IDEA-104 splits: **8 sprint routes + 2 drag routes**, not 10 sprint routes.

## B4. Start suitability is answered

Owner: *"every node was handpicked for ai vehicles to spawn there as a start, so 20 real players should be
qualitatively easier."* **No new node field is needed.** `raceLegal` already means what we need it to mean, and
§2's speculative "start suitability" field is withdrawn.

---

# Addendum C — championships as the organizing principle (2026-09-22, owner)

## C0. Finish geometry: the answer to the outstanding question

**The fields exist in SP and carry real values, but not on nodes.**

- `data/nodes_curated.lua` documents `finishHeading`, `finishWidthM`, `finishArmDistM` in its format comment and
  **no curated row sets any of them**. So there is nothing to import at node level.
- `data/default_roots_pack.lua` sets `finishArmDistM = 180` and `finishLineWidthM = 35` (plus
  `genericRoadFinishLineWidthM = 45`) inside **per-root tuning blocks** on two roots.
- SP's `racing.lua` treats them as an override chain: `nodeB.finishWidthM or cfg.finishWidthM or …`, and when
  nothing is authored it **computes finish width from lane count** (`effectiveLaneCount * finishWidthPerLane`,
  floored by `dragMinFinishWidthM`).

**Conclusion: do not import these as node fields.** They were never node data; they are per-route tuning with a
sensible derived default. Online's `gates.build` already takes `halfWidthM` / `armM` / `captureM` through `opts`,
which is the same seam. The one number worth copying is SP's **arm distance of 180 m** against Online's current
default — worth comparing, since the arm is what decides how early a finish line starts accepting.

## C1. Current state: the championship primitive already exists and is called `series`

The brief's chain is `NODE(S) → ROUTE → CHAMPIONSHIP/SERIES → SCHEDULED EVENT → EVENT INSTANCE`. That is what is
implemented today, under different names:

| Brief's concept | Exists as | Owns |
|---|---|---|
| Node | `data.nodes` | geography |
| Route | `data.roots` | ordered node path, course info |
| **Championship** | **`series`** (in a pack) | `cadence`, `routes` pool, `disciplineId`, `formatId`, `classId`, `rulesetId`, `capacity`, `entryWindow`, `venueRadiusM` |
| Scheduled Event | a materialised slot | `eventId = seriesId@startsAt`, `routeId`, `startsAt`, entry window |
| Event Instance | a session `rec` | grid, telemetry, results |

**A series already owns exactly what the brief says a championship must own, and a route already owns only
geography.** No route carries cadence, eligibility or rules. The separation the brief asks for is not a refactor.

More importantly: **`Cal.materialize` is per-series and `Cal.merge(lists)` merges many**, and the server already
does `for _, s in ipairs(seriesList) do lists[#lists+1] = Cal.materialize(s, t, horizon) end`. Independent
championship schedules producing overlapping events is **the existing design**, not a new capability.

And the id scheme already survives it: `eventId = seriesId .. "@" .. startsAt`. City Cup and MaiMai Cup at 10:00
produce two distinct ids naturally. **Collisions only arise if one series emits several events per slot** — which
is an argument for doing concurrency the way the brief proposes (many championships) rather than the way Addendum
B floated (one series, N routes per slot). **Addendum B's region-disjoint scheduler is therefore withdrawn as the
primary mechanism**; independent cadences give concurrency for free, and the owner has since said overlap should
be soft anyway: *"if we have too much heywood its fine… just do our best to avoid each other while making sure the
calendar can breathe. should not be rigid."* Region spacing becomes a **tiebreak inside a championship's route
rotation**, not a global constraint.

## C2. Eligibility: declared, expressive, and never once called

`competition.class` has `M.eligible(classId, record)` with per-class `records = "any" | { ids }`.
**It has zero call sites in the whole codebase.** `enterPlayer` validates the entry window and your position; it
never looks at what you are driving.

This is the *second* case in this module family of a correct rule that nothing invokes — the first was the
performance ceiling (KB-30), where `performanceFor` also had no caller. Worth naming as a pattern: **core declares
the rule, the host forgets to ask.** A test that asserts "this rule has a caller" is not expressible in core, so
it has to be a review habit.

Today arbitrary machinery is prevented only *incidentally*, because `NcmGarage.issue` hands you a car from a pool
class. Nothing stops a player entering in whatever they drove up in.

**The data-driven catalogue the brief asks for already exists**: `data.vehicle_pool` groups records by
`CLASS_ORDER = { Muscle, Sport, Tech, Nomad, Bike, Formula }` with `prestige` 1–5 and free-form `tags`
(`budget`, `starter`, `street`, `sport`, `race`, `halo`, `iconic`, `executive`, `luxury`, `utility`, `classic`).
Mapped against the proposed catalogue:

| Championship | Expressible today as |
|---|---|
| NCM City Cup | `prestige <= 2` across Muscle/Sport/Tech |
| MaiMai Cup | one record: `Vehicle.v_standard2_makigai_maimai` (Tech, prestige 1) |
| Night City GT | `prestige >= 4` with tag `sport`/`race` |
| Badlands Rallycross | class `Nomad` |
| Hypercar | `prestige == 5` / tag `halo` |
| NCX World Championship | already `ncx_rb15` with an explicit record list |

**So no new vehicle metadata is needed** — with one gap: the brief names *manufacturer families* (Mizutani,
Quadra, Herrera, Porsche). Maker is embedded in the record id (`v_sport2_mizutani_shion`) and could be parsed, but
**a parsed id is not a catalogue**. Add an explicit `make` field rather than string-matching ids in eligibility
rules.

The real modelling question: today `classId` conflates **BoP ceiling** and **eligible records**. A championship
needs eligibility; a ceiling is a separate concern that several championships may share. They should be two
fields on the championship, not one id.

## C3. Concurrency blockers, audited

Most of the runtime is already multi-session: `sessions[sessionId]`, `plans[eventId]`, `byEvent[eventId]`,
`pickups[eventId]` are all keyed maps, and `tick()` loops every session. The blockers are few and specific:

| # | Blocker | Severity | Notes |
|---|---|---|---|
| 1 | **`GlobalState.ncmSession` is a single slot** — `publish()` does `GlobalState.ncmSession = v` for every session, last writer wins | **Hard blocker** | Two live races and every driver's HUD flickers between them. **A precedent fix already exists in the same file:** practice publishes to `GlobalState.ncmPractice` as a **map per event**, and the client's `pickView()` already scans it for the view the local driver is an entrant of. Converting races to `ncmSessions[sessionId]` and extending `pickView` is a small, proven change. |
| 2 | **Venue dressing is a singleton** — `ncm:venueDress` → `NcmVenue.dressUp(reason)` takes no venue id | Medium | Only `class == "organized"` events dress, so street championships are unaffected. Two sanctioned events at once would fight. |
| 3 | `publishCount = 3` | Trivial | Caps the Race Guide at 3 upcoming. With six championships this needs raising; it is a setting. |
| 4 | `pickView()` fallback `return g` | Design decision | A non-entrant currently sees whatever race is live. Under a map, "which race does a spectator see?" needs an answer. |
| 5 | Participant isolation | **Already correct** | `pickView` only returns a view the local driver is an entrant of; `NcmRace.busySession` (KB-37) already stops one driver joining two. |
| 6 | Settlement / results / ids | **Already correct** | Everything is keyed by `sessionId` / `eventId`; `complete()` and progression are per-rec. |
| 7 | Route reuse by several events | **Already correct** | Nothing locks a route. `byEvent` is event-keyed, `courseFor(e)` resolves per event. The same route can host City Cup and GT an hour apart, or simultaneously. |

## C4. Data model recommendation

Keep `series` and rename nothing yet. Add to it, as data:

- `championshipId` (today `seriesId`), `name`, `tier` (street / sanctioned, L58);
- `eligibility = { classes?, prestigeMin?, prestigeMax?, tags?, makes?, records? }` — a **predicate over
  `data.vehicle_pool`**, evaluated in core, so reclassifying a car is a data edit;
- `ceilingId` — the BoP profile, split out of `classId`;
- `schedule` — a tagged union, `{ kind = "interval", everyMinutes, offsetMinutes }` **or**
  `{ kind = "calendar", starts = { … } }`. This is the **only genuinely new primitive** in the brief;
  `validateSeries` currently hard-requires `cadence.everyMinutes >= 1`, so NCX cannot be expressed today.
- `routes` — unchanged, a pool the championship rotates through.

Routes gain nothing. Events gain nothing except that their `seriesId` now means "championship".

## C5. Smallest implementation slice

1. **`GlobalState.ncmSession` → `ncmSessions` map, and extend `pickView`.** One code change, one precedent to
   copy. **Everything else in the brief is blocked behind this**, and it is worth doing even if no championship
   ships, because it is the difference between "concurrency happens to work" and "concurrency is supported".
2. **Add the five interval championships as pack data**, each with its own cadence and route pool. No new code:
   `seriesList` already merges. This alone produces the irregular guide the brief wants.
3. **Wire `Class.eligible` (or its successor predicate) into `enterPlayer`**, refusing with a reason that names
   the championship. This is the point at which eligibility stops being decorative.
4. **Raise `publishCount`** and let the guide group by championship.

Deferred deliberately: explicit calendar scheduling for NCX (needs the tagged union), championship scoring/points,
and anything resembling seasons or standings.

## C6. Product decisions needed before coding

- ~~Do players bring their own car, or does NCM issue one?~~ **ANSWERED 2026-09-22 (L83): they bring their own,
  earned through progression, and a non-compliant entry is REFUSED, not substituted.** See §C7 for what that
  costs.
- ~~What happens to an ineligible entrant?~~ **Answered: refusal.** Substituting would make the eligibility rule
  meaningless and the earned car worthless.
- **Spectator view** when the local driver is in no race (blocker #4).
- **Does a championship imply a tier?** L58 says street and sanctioned are both first-class; City Cup and GT are
  presumably street and sanctioned respectively, which affects venue dressing and therefore blocker #2.
- **Are the six catalogues `classId`s, or is eligibility per-championship?** Recommend the latter — otherwise
  every new championship needs a new class, and classes are about BoP.

## C7. What "bring your own, or be refused" actually costs (L83)

Three consequences, in the order they bite.

**1. It is two checks, not one, and they fail differently.**

| Check | Question | Refusal should read |
|---|---|---|
| *Eligible* | Is this model allowed in this championship? | "MaiMai Cup is one-make — you need a Makigai MaiMai." |
| *Owned* | Does this driver own one? | "You don't own a Makigai MaiMai yet." |

Collapsing them into "you can't enter" throws away the only useful part: whether the fix is *switch cars* or
*go and earn one*. `competition.class.eligible` answers the first and **nothing answers the second.**

**2. The ownership ledger does not exist.** L55 describes `owned_vehicle` rows per driver; there is no
`owned_vehicle` table in any migration. The only garage table is `issued_vehicle` — and its `model` column is
already `ENUM('issued','loaner','owned','byo')`, of which **only `'issued'` is ever written**. So the vocabulary
for the end state was reserved and the ledger behind it was never built. Ownership is the real prerequisite here,
not eligibility; eligibility is ready and waiting.

**3. The testing exception is the dangerous part.** NCM spawning cars for QA is exactly the thing that would
satisfy an ownership check by accident, and then the rule rots unobserved — which is precisely what happened to
the performance ceiling (KB-30) and to `eligible` itself (§C2): *declared, correct, never asked.* Recommendation:
the QA spawn path writes `model = 'loaner'`, the ownership check accepts loaners **only** while a host-kit flag is
on, and it **logs every time it does**. A silent bypass is indistinguishable from no rule.

**Where the refusal belongs:** the venue option list (IDEA-095) already has the right shape for this.
`competition.venue_options` declines options and records *why* in `reasons`, and the design rule is already
**absent, not greyed**. So `ENTER RACE` simply should not appear for a driver who cannot comply — with the reason
carried for the host log, and the *fix* stated where the player will read it. That is a better home than a
refusal toast after a hold-E, and it needs no new surface.
