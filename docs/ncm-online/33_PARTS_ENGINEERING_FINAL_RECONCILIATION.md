# 33 — Parts / Engineering owner rulings and final reconciliation

> **STATUS: PROPOSAL** - reconciliation and implementation recommendation; owner rulings are authoritative only
> where recorded in `DECISION_RECORD.md` L134. Gate 5 awaits acceptance and Gate 6 awaits Development proof.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-25 (L125).

Date: **2026-09-25**. Scope: owner rulings on Report 32, the focused machine-architecture audit, the Chrome /
`setPerformance` history and a bounded Development proof plan, the solved-wiki test, junk assets, naming and
design promotion. **No Parts/Engineering code, schema, migration, database state, deployment or restart was
performed.**

---

## 1. Executive result

The nine rulings are coherent with the accepted Online architecture after one explicit amendment: the old
statement that fabrication is simply “not pass/fail” must be narrowed. A completed project always leaves an
attributed physical result, but that result may be **functional poor**, **functional neutral** or **nonfunctional
as built**. The third is a persistent component asset, not an installable component and not a vanished failure.

Gate 5 recommendation: **ACCEPT WITH AMENDMENTS.** Proposal 25 correctly separates machine architecture from
Engineering and correctly derives compatibility instead of enumerating vehicle-by-component pairs. It needs
four corrections before authoring begins:

1. separate physical compatibility from operational suitability;
2. represent stable installation interfaces/positions, not only one map entry per broad family;
3. allow platform inheritance plus model/variant overrides instead of requiring identical interface maps;
4. add a separate canonical factory-configuration blueprint for backfill.

Gate 6 result: **PARTIALLY VIABLE WITH SPECIFIC LIMITS; LIVE PROOF REQUIRED.** The Chrome work recovered the
right ownership pattern—one NCM composer, many factual inputs, one final write—but did not prove it in game.
The current NCM governor and current official API materially strengthen the hypothesis:

- NCM already publishes a record-wide profile and calls `setPerformanceClass` on each client;
- the platform now documents a server-side per-instance `setPerformance`, read-back through `getPerformance`,
  replication to all viewers, and instance-over-record precedence;
- the three writable dimensions are only `topSpeedKph`, `accelerationScale` and `taperKph`.

That last fact is the limit. The carrier can express ceilings and reductions, or restore deliberately withheld
headroom. It cannot add above-native torque, change braking, grip, tire friction, steering, suspension or gear
ratios. Parts may depend on this carrier only for effects honestly reducible to its three dimensions.

Two Development proofs are required:

1. one calculated profile visibly changes one actual vehicle and cleanly restores its prior state;
2. two independent NCM inputs are evaluated together by one owner into a third, expected final profile, with
   neither input writing the platform slot directly.

---

## 2. Status vocabulary used in this report

| Status | Meaning here |
|---|---|
| **IMPLEMENTED ONLINE** | Code/schema exists in the current Online payload; this does not imply every behavior has a live PASS. |
| **ACCEPTED ONLINE DESIGN** | Previously locked in `DECISION_RECORD.md`; not necessarily implemented. |
| **OWNER-RULED BY THIS FOLLOW-UP** | The owner explicitly decided it in the brief captured by L134. |
| **PROPOSED / RECOMMENDED** | This report's recommendation; not authority until accepted. |
| **SP-ONLY PRECEDENT** | Exists in the released single-player payload and is not automatically Online authority. |
| **UNRESOLVED / REQUIRES PROOF** | Needs a ruling or measured experiment before dependency. |

---

## 3. Final interpretation of Gates 1–9

| Gate | Final status | Interpretation |
|---|---|---|
| 1. Human-shareable knowledge | **OWNER-RULED BY THIS FOLLOW-UP** | Complete process facts may be represented by human-shareable opaque references. Public cataloguing is legitimate technological diffusion, not an exploit. Knowledge never grants competency, facilities, capacity, capital, specimens or execution reliability. |
| 2. Partial knowledge | **OWNER-RULED BY THIS FOLLOW-UP** | First implementation shares complete facts only. Partial understanding remains private evidence/design-specific knowledge state. No token substrings and no partial hexadecimal puzzle. |
| 3. Failure/junk | **OWNER-RULED BY THIS FOLLOW-UP**, representation recommended below | Fabrication can create a persistent, nonfunctional physical result. It is not installable merely because it has an asset row. No arbitrary copied-token failure tax; mastery plus complete mature knowledge approaches repeatability. |
| 4. Effect labels | **OWNER-RULED BY THIS FOLLOW-UP** | Display causal/effect information only to the precision justified by Diagnostics and evidence. The server owns truth; mystery is epistemic, not permanent cosmetic obfuscation. |
| 5. Machine architecture | **PROPOSED / RECOMMENDED: ACCEPT WITH AMENDMENTS** | The subsystem boundary and derived-fitment direction are right. Amend fit versus suitability, interface positions, variant inheritance and factory configuration before authoring. |
| 6. Physical effects | **UNRESOLVED / REQUIRES PROOF; PARTIALLY VIABLE WITH SPECIFIC LIMITS** | A sole composition owner is technically plausible for the three governor dimensions. It is not yet empirically proven and is not a general vehicle-physics modifier. |
| 7. Prototype promotion | **OWNER-RULED BY THIS FOLLOW-UP** | A one-off asset remains an asset. A new design is born only through explicit promotion after sufficient understanding/capability. Discovery is not understanding; understanding is not manufacturing. |
| 8. Costs | **OWNER-RULED BY THIS FOLLOW-UP** | Start with money + elapsed time + bounded capacity, plus already-legitimate specimens, knowledge, capability and access. Commit cost before outcome; cancellation cannot reroll freely. No general materials economy or daily attempt cap. |
| 9. Knowledge references | **OWNER-RULED BY THIS FOLLOW-UP** | Tokens are opaque high-entropy references to versioned server-owned facts. They are not seeds, stat hashes, proximity codes or correctness oracles. Historical resolutions are stored and never reinterpreted by resolver upgrades. |

### Compatibility with L120

Gates 1, 2, 4, 7, 8 and 9 reinforce L120's load-bearing distinction:

```
knowledge = what process/design facts the principal legitimately possesses
competency = what work the principal can execute
capability = competency + tooling/facility + capacity + access + committed inputs
```

A valid token may satisfy one knowledge predicate. It does not satisfy the capability predicate and must never
be smuggled into the competency reducer as practice, rank or guaranteed execution.

---

## 4. Contradictions and exact amendments

### C1 — “Fabrication is not pass/fail” is now too broad

`19_ENGINEERING.md` says poor fabrication always produces a poor but legitimate component. The ruling adds a
third outcome: a real physical assembly which is nonfunctional for its intended component role.

**Recommended amendment:** preserve the anti-casino intent and replace the absolute statement with:

> Fabrication never resolves as a disappearing `CRAFT FAILED` event. It produces an attributed physical output.
> A serviceable output may be poor, neutral or beneficial; an execution failure may instead produce a persistent
> nonfunctional-as-built asset. Complete knowledge controls process information, while competency and capability
> govern whether the process crosses the serviceability boundary. Mature known processes executed at mastery
> should approach reliable repeatability rather than retain an arbitrary failure floor.

This is a refinement, not rejection, of L120. L120 did not lock a fabrication outcome taxonomy.

### C2 — Proposal 25 calls adequacy “fitment”

Its `component.capability >= machine.demand` predicate answers “is this enough part for safe/expected service,”
not “does this physical component fit this interface.” Combining the questions would make a beautifully
manufactured under-rated brake “not fit,” while a nonfunctional junk brake could inherit its design's fit and
appear installable.

**Recommended amendment:** expose two predicates:

```
compatible(design, machine_interface) -> mechanical attachment / geometry / protocol
suitable(asset, machine, context)      -> compatibility + design rating + realised serviceability + condition
```

Installation requires both. Compatibility remains stable design/architecture truth. Suitability may change
with manufacturing realization, condition, ruleset and validated context.

### C3 — Same platform does not guarantee identical interfaces

Proposal 25 recommends identical interface maps for vehicle keys sharing a platform. Nomad, competition and
trim variants are exactly where suspension, tires, brakes, powertrain or cooling can differ while chassis roots
remain shared.

**Recommended amendment:** a platform supplies an inherited base profile; a vehicle model/variant may override
or add named interfaces. Validate overrides and show them in review. Do not silently copy or require equality.

### C4 — Proposal 25 cannot alone perform factory backfill

It answers what can fit, not what was factory-installed, how many positions exist or which design occupied each
position. That is the correct boundary, but Report 32's backfill requires another authored object.

**Recommended amendment:** add a versioned canonical factory-configuration blueprint:

```
vehicle model/variant -> interface position -> canonical factory component design
```

The migration materialises assets from that blueprint idempotently. The architecture profile is not overloaded
with historical asset creation.

### C5 — The older Chrome text overstates one reset hazard

`06_CHROME_ROSTER.md` correctly says repeated writes do not stack, but says clearing a LIMITER necessarily hands
the vehicle uncapped rated performance. Current official documentation describes precedence as **instance,
record class, default**; clearing an instance profile falls back to the record-class profile when one exists.

**Recommended amendment:** keep the single-owner rule, but update the rationale. Clearing is unsafe because the
correct fallback depends on all current NCM inputs and on which platform layer NCM uses—not because every clear
necessarily erases a record cap.

### C6 — IDEA-102's “no read-back” statement is stale for the server path

The current official server API exposes `getPerformance(id)` and `get(id).performance`. The current NCM client
record-class path still has no NCM-side authoritative read model, but a proposed server per-instance composer can
verify its canonical profile.

**Recommended amendment:** qualify IDEA-102 historically instead of deleting it: no useful read-back was
available to the original client record-class owner; current server per-instance profiles are readable.

No other owner ruling contradicts locked authority. The remaining differences are proposal refinements or proof
gates, not reversals of L119/L120/L125.

---

## 5. Focused audit of Proposal 25 — machine architecture

### 5.1 What it represents

Proposal 25 represents authored mechanical structure for a machine model:

- an immutable chassis/platform root;
- a sparse set of serviceable component interfaces;
- a closed physical mount vocabulary;
- coarse size/rating inputs;
- descriptive facts which do not participate in the resolver;
- a rare exact-model restriction for genuinely bespoke designs.

It deliberately does not represent a physical component instance, workmanship, wear, engineering knowledge,
market access or player capability.

### 5.2 Component family and subfamily attachment

The current proposal indexes one interface by broad `family` and lets a component design declare that family and
its fit constraints. This is directionally correct but too coarse for positions and multiple interfaces.

**Recommended minimum representation:**

```
machine architecture
  platform_id
  interface_id                 -- stable position/role, e.g. brakes.front
  family_id / subfamily_id
  mount_standard_id
  size_class
  required_rating              -- suitability input, not physical fit

component design
  family_id / subfamily_id
  compatible_mount_standard_ids
  supported_size_range
  design_rating
  optional exact-model restriction
```

This is still sparse. A machine declares only interfaces it possesses. It does not require arbitrary universal
slots, and it does not decide whether tires are individual, axle-pair or set assets. It merely provides named
positions capable of hosting the later asset abstraction.

### 5.3 Authored versus procedural

- Machine architecture is **authored and versioned with the vehicle catalogue**.
- Compatibility resolution is **deterministic code** over authored facts.
- Future component R&D may **procedurally create component designs within the authored grammar**.
- R&D may select existing mount/size/rating vocabulary; it may not invent a new interface standard or mechanic.
- Factory configuration is authored separately.

This is the right asymmetry. Cars are authored content. The procedural space is the component design history,
not silent mutation of what a shipped vehicle mechanically is.

### 5.4 Separation from Engineering

The owner's working hypothesis is confirmed with one refinement:

```
Machine architecture: what this machine mechanically is and what can attach/work at an interface.
Engineering: what a principal knows, can inspect, execute, fabricate, install, repair and manufacture.
```

The interaction is a capability check. Engineering cannot roll a physically incompatible component into
compatibility. Architecture does not decide whether an Engineer can perform the installation or whether this
particular fabricated asset is serviceable.

### 5.5 Complexity audit

Useful complexity:

- a platform root with constrained overrides;
- sparse named interfaces;
- closed mount standards;
- deterministic refusal reasons;
- rare exact-model constraints;
- separate compatibility and suitability answers.

Unnecessary or dangerous complexity:

- deriving precise physical dimensions from CDPR vehicle class tiers;
- treating descriptive facets as latent resolver inputs;
- a fourth/fifth generic ordinal before a real refusal needs it;
- a bespoke compatibility row for every vehicle/design pair;
- forcing every platform variant to have identical interfaces;
- encoding factory installed designs into the fitment resolver;
- letting procedural R&D invent mount standards.

The proposed 1–5 `size` ordinal is acceptable as an authored abstraction, but CDPR tier may only seed a review
draft; it is not evidence of physical size. `demand` should be renamed `required_rating` and moved into
suitability.

### 5.6 Factory-component backfill sufficiency

Proposal 25 **is necessary and insufficient**. Backfill additionally needs:

1. the canonical factory-configuration blueprint;
2. component design rows for each factory design;
3. stable interface positions/cardinality;
4. deterministic component IDs and idempotency keys;
5. an exposure allocation rule from the machine odometer;
6. explicit unknowns for manufacturer run, installer and historical timestamp.

Existing machine identity, ownership, paint, ordinals, odometer, results and transfer history stay untouched.
Development and Online remain separate universes; only code and forward migrations move downstream.

### 5.7 Gate 5 recommendation

**ACCEPT WITH AMENDMENTS.** Accept the subsystem boundary, authored direction, sparse profiles, platform root,
closed mounts, derived resolution, refusal reasons and rare exact-model escape hatch. Amend C2–C4 before any
profiles are authored. Do not author the proposed ~250 declarations until the owner accepts those amendments.

---

## 6. Gate 6 — recovered Chrome and performance-governor history

### 6.1 What Chrome previously concluded

The Chrome spec made four relevant claims:

1. performance writes do not automatically stack;
2. class ceilings, weather, LIMITER and POWER SURGE would compete for the same effective governor;
3. therefore one NCM authority must own the final profile and other systems must supply inputs, not write;
4. the composed owner must restore the still-valid base profile when a temporary influence ends.

This was an architectural deduction from API documentation. It was not a live composition proof.

### 6.2 What is implemented now

**IMPLEMENTED ONLINE:**

```
competition.class.recordCeilings()
  -> NcmCompetition.publishCeilings()
  -> GlobalState.ncmCeilings.records
  -> ncm_world/client/main.lua 10-second loop
  -> Open77.vehicles.setPerformanceClass(record, profile)
```

The only NCM call sites are:

- `ncm_world/client/main.lua:92` — `setPerformanceClass(record, prof)`;
- `ncm_world/client/main.lua:105` — `clearPerformanceClass(record)`.

The publisher is `ncm_league/server/competition.lua:166-171`. It publishes every enabled record-wide class
profile at service start. The pure data function is `ncm/core/competition/class.lua:47-65`.

This proves NCM has a working data-to-host-to-client path and that the current runtime exposes the expected
symbols. It does **not** prove the profile changes vehicle behavior. The existing D7 PASS measured the RB15
cliff and selected 355 km/h; the recorded retest still says to accelerate beyond 350 and confirm the governor
prevents the collapse. No live PASS in `MASTER_TEST.md` records that observation.

### 6.3 What owns the slot today

There is one NCM writer path today, but no general composition owner:

- class data owns the only input;
- `ncm_league` publishes a whole record map;
- `ncm_world` applies one record-class profile;
- there is no layer registry, per-vehicle input snapshot, contribution trace or recompute contract;
- the 10-second loop is reconciliation polling, not lifecycle ownership;
- the path cannot distinguish two physical assets sharing one TweakDB record;
- the code does not restore record caps on explicit client-resource stop.

The prior warning that `open77_admin` can write a competing governor remains architecturally relevant. A platform
precedence rule does not make two policy owners coherent.

### 6.4 Demonstrated platform capability versus assumption

| Claim | Classification |
|---|---|
| API symbols `setPerformanceClass` / `clearPerformanceClass` exist on the `.87` client | **IMPLEMENTED ONLINE evidence:** current NCM probes and calls them without the missing-API warning. |
| NCM publishes 11 record profiles at boot | **IMPLEMENTED ONLINE and boot-observed.** |
| Current class profile physically holds an RB15 at 355 and prevents the cliff | **UNRESOLVED / REQUIRES PROOF.** No player-observed PASS is recorded. |
| Server per-instance `setPerformance`, clear and read-back exist | **Documented current platform capability**, not yet exercised by NCM. See the official [vehicle guide](https://open2077.net/docs/vehicles) and [server API](https://open2077.net/docs/api/server/open77-vehicles). |
| Instance overrides record class, then falls back on clear | **Documented platform contract**, not yet exercised by NCM. See the official [client API](https://open2077.net/docs/api/client/open77-vehicles). |
| Multiple NCM influences can be calculated into one table | **Pure-software capability; trivially testable offline.** |
| One composed table yields the expected physical combined behavior | **UNRESOLVED / REQUIRES PROOF.** |
| Parts can change grip, brakes, suspension or steering through this carrier | **BLOCKED by known platform limits.** Those fields do not exist. |
| A “positive” part can exceed native power through this carrier | **BLOCKED.** `accelerationScale` is at most 1 and top speed is a ceiling. Positive effects can only restore withheld headroom or improve relative to another capped state. |

### 6.5 What has strengthened the hypothesis

- A server per-instance profile now exists and matches asset-specific Parts better than the current record-wide
  client path.
- The server exposes canonical read-back.
- The server profile replicates to every viewer and survives physics-owner changes.
- A projection that attaches later receives the intent.
- Platform precedence is explicitly documented.
- NCM already has persistent asset-to-runtime identity and class data to feed a composer.

### 6.6 What weakens or narrows it

- The current NCM writer is record-wide and client-local; it is not the proposed per-asset authority.
- No physical change/reset has a live PASS.
- The governor only withdraws throttle. It is not a writable drive model.
- Client-local instance writes can take precedence over the replicated server policy, so admin/dev tools remain
  capable of conflicting unless operational ownership is enforced.
- Despawn clears instance profiles. Persistent machine respawn therefore requires rehydration.
- The current loop has no explicit teardown restoration and no contribution trace.
- Record-wide profiles are context-insensitive. They cannot honestly represent installed component instances,
  wear or a race-only class rule by themselves.

### 6.7 Recommended one-owner architecture

One pure core service computes the desired profile from immutable/frozen inputs; one host adapter is the only
NCM caller of server `setPerformance`/`clearPerformance`:

```
authoritative facts
  class/ruleset hard ceiling
  + validated installed-component modifiers
  + derived condition/wear modifiers
  + environment modifier
  + temporary Chrome statuses
  -> performance.compose(snapshot)
  -> { topSpeedKph, accelerationScale, taperKph, contribution trace }
  -> one server setPerformance(runtimeVehicleId, finalProfile)
```

Other systems publish facts or request time-bounded modifiers. They never call the platform governor. The
composer stores the last requested profile and input revisions for idempotency/audit; platform read-back verifies
delivery but does not become the source of truth.

Exact production arithmetic is still a balance/design decision. Likely invariants are:

- immutable ruleset/homologation caps are hard maxima;
- no layer may raise `accelerationScale` above 1 or a hard cap;
- a temporary “boost” can release a prior soft restriction, never exceed native/hard authority;
- taper belongs to the effective winning ceiling rather than being averaged blindly;
- stacking must be bounded so adding more component families does not multiply a vehicle toward zero.

### 6.8 Recompute and restoration events

Recompute on:

- runtime vehicle creation/rehydration and late projection attach;
- asset-to-runtime binding change;
- install/remove or configuration-snapshot activation;
- a wear condition crossing a derived effect threshold;
- repair/service changing persisted relief;
- class/ruleset/session enter, green, retire or abort;
- weather state change, if that consumer is accepted;
- Chrome effect apply, expiry, purge or cancellation;
- resource/server restart and player reconnect.

Do not recompute on every odometer metre. Wear effects change at deterministic threshold crossings, so those
events invalidate the profile. A low-frequency reconciliation sweep may repair missed events, but it is not the
authority model.

On vehicle despawn, discard the runtime binding. On respawn, recompute from persistent machine/configuration
facts. On resource stop, restore the pre-test/pre-NCM profile for every active target or clear only profiles NCM
knows it created. Never call `clearAllPerformance` in a shared production resource.

---

## 7. Smallest safe Development proofs for Gate 6

### 7.1 Harness boundary

**PROPOSED / RECOMMENDED, not implemented:** a temporary Development-only resource or command set with:

- both an environment assertion and a console-only command assertion;
- one explicit canonical vehicle ID; never “nearest vehicle”;
- no schema, persistence, Parts rows, Chrome rows or production data;
- capture of the pre-test server profile through `getPerformance`;
- one active target maximum;
- a hard short TTL and automatic restoration;
- exact input/final-profile/read-back logging;
- restoration on normal completion, abort, player disconnect and resource stop;
- refusal when a baseline cannot be read or restored;
- no `clearAllPerformance` call.

Use an ordinary Development Hella or MaiMai on a straight, not the RB15 cliff case, so the first experiment does
not mix governor proof with the car's native failure. Use a server-spawned canonical vehicle, because server
`setPerformance` cannot address local traffic.

### 7.2 Proof 1 — one calculated profile changes one vehicle and restores

1. Record target ID, TweakDB record, current server profile and a short baseline full-throttle run. Baseline must
   exceed the proposed cap comfortably.
2. Feed one named Development input into the pure composer, for example:
   `diagnostic_limiter = {topSpeedKph=80, accelerationScale=0.50, taperKph=12}`.
3. Log the input and exact composed output, then make the single server `setPerformance` call.
4. Assert server `getPerformance` equals the requested profile.
5. Repeat the same straight/full-throttle run. PASS requires a clearly slower pickup and a stable plateau near
   80 km/h, without stutter/rubber-banding. Capture telemetry/log evidence, not only feel.
6. Restore the exact captured baseline: reapply it if non-null, otherwise clear the instance profile.
7. Assert read-back equals the baseline and repeat the run. PASS requires the vehicle to exceed 80 again and
   return to baseline pickup within ordinary run variance.
8. Stop/reload the harness and confirm no profile remains.

This proves:

```
NCM calculation -> final profile -> platform write -> intended physical effect -> clean restoration
```

It does not prove composition.

### 7.3 Proof 2 — two meaningful inputs compose without overwrite

Use the same car and a test-only deterministic composition law. The exact law is not production balancing; its
purpose is to make the combined result distinct and predictable.

| State | Input A: homologation | Input B: temporary limiter | Expected final profile |
|---|---|---|---|
| baseline | none | none | captured baseline / clear |
| A only | cap 120, accel 0.80, taper 15 | none | 120 / 0.80 / 15 |
| B only | none | cap 90, accel 0.90, taper 10 | 90 / 0.90 / 10 |
| A + B | cap 120, accel 0.80 | cap 90, accel 0.90 | cap 90; accel 0.72; taper 10 |

Run A-only, restore; B-only, restore; A+B, restore. For each state log both inputs, final output and server
read-back. The combined output must differ from both individual profiles. Physical PASS requires:

- A-only reaches approximately 120 with the larger pickup reduction;
- B-only reaches approximately 90 with the smaller pickup reduction;
- A+B reaches approximately 90 **and accelerates more slowly than B-only**;
- removing B while A remains recomputes A, not clear/native;
- removing A while B remains recomputes B;
- removing both restores the captured baseline.

This specifically detects last-writer behavior. If each input calls `setPerformance` independently, A+B will
equal whichever ran last and the matrix fails.

### 7.4 Follow-on cases after the two proofs

These are not required for the first viability ruling but should precede persistent Parts effects:

1. **Vehicle respawn:** profile disappears with runtime ID; new runtime ID is recomputed from the same machine.
2. **Ownership/seat transition:** exit/re-enter and a second driver retain the server policy.
3. **Late observer:** a second client streaming the target sees the same governed behavior/profile.
4. **Temporary expiry:** remove only the temporary input and prove the class input remains.
5. **Resource reload:** cleanup restores, restart rehydrates exactly once.
6. **Admin conflict probe:** deliberately apply a competing client instance profile in Development and document
   precedence/refusal/operational mitigation. Do not pretend one NCM owner controls non-NCM tools.
7. **Boundary values:** top-speed-only, acceleration-only, no-op profile, taper floor refusal and invalid input.

### 7.5 Gate 6 classification

Before Proof 1: **PARTIALLY VIABLE WITH SPECIFIC LIMITS — NEEDS TEST.**

After Proof 1 only: the carrier is proven, composition remains unproven.

After Proof 2: a single-owner compositor is proven for the three governor dimensions. That still does not prove
brake, grip, suspension, tire or other family-specific physical effects.

---

## 8. Six-month solved-wiki stress test

Scenario: veterans give a new player every publicly known complete process token for a popular lineage.

What the player legitimately receives:

- complete public process facts for those exact versioned designs/dimensions;
- the ability to avoid ignorance-driven uncertainty on those facts;
- social access to accumulated industrial knowledge.

What they do not receive:

- Engineering competency or family specialisation;
- diagnostic breadth, precision or depth;
- workshop/tooling eligibility or concurrent capacity;
- money, specimens, source hardware or restricted market access;
- elapsed project time;
- execution reliability or manufacturing repeatability;
- installation/integration workmanship;
- condition diagnosis, repair capability or service relief;
- access to undiscovered/private/new processes;
- authorship of a derived design or provenance on another principal's work.

Meaningful remaining gameplay:

1. qualify to execute sophisticated known work;
2. acquire and improve facilities/capacity;
3. finance and schedule projects;
4. source hardware and destructive-analysis specimens;
5. diagnose whether realised assets match known intent;
6. install, integrate, maintain and repair assets;
7. turn one-off outcomes into repeatable manufacturing capability;
8. participate in new R&D, new revisions and newly extinct/recovered lineages;
9. build a reputation from attributed successful work and supply reliability.

The architecture passes, with one real hole to watch: **a static world eventually makes the knowledge-discovery
game finite.** Public popular designs will become solved. The profession remains through execution, diagnosis,
service, manufacturing and supply, but the discovery frontier needs real new designs/process revisions and
historical reconstruction over time. Do not fake that frontier by invalidating correct tokens or making them
account-bound.

Two other anti-shortcut requirements are design quality, not anti-sharing rules:

- cheap repeated junk projects must not be the fastest universal competency grind;
- transferable money and purchasable facilities must not turn a funded alt into a master without demonstrated
  family-relevant work.

If those progression reducers are sound, a solved wiki changes **what is known**, not **who can do the work**.

---

## 9. Exact treatment of nonfunctional fabrication output

### 9.1 Representation

Do not create a separate “junk item” ontology. Create the ordinary component asset and record an immutable
as-built serviceability result:

```
component_asset
  component_asset_id
  attempted_design_id
  fabrication_operation_id
  manufacturing_run_id nullable
  realised_outcome
  as_built_serviceability = serviceable | nonfunctional
  owner/custody/provenance/serial
```

`functional poor`, `functional neutral` and `functional beneficial` all have `serviceable`. Their realised
characteristics differ. A failed execution has `nonfunctional`.

The install validator asks `suitable(asset, machine, context)`. A nonfunctional-as-built asset returns
`nonfunctional_as_built` before any configuration change. It remains a physical asset for custody, display,
trade with honest disclosure, inspection and legitimate reverse engineering.

### 9.2 Lifecycle

First implementation permits:

- store/transfer/list with explicit nonfunctional status;
- inspect/diagnose;
- consume through destructive reverse engineering;
- dispose through the ordinary provenance-preserving terminal lifecycle.

It grants no generic scrap/material currency, no automatic refund and no invisible deletion. Whether a future
repair/rework operation can cross the as-built serviceability boundary is deliberately deferred; do not encode
that promise now. A terminal analysis/disposal operation preserves the row and provenance.

### 9.3 Outcome probability

No numeric failure rate is selected. The resolver must use design/process requirements, frozen competency and
facility capability. Complete knowledge is not immunity for an incapable novice; mastery of a known mature
process should approach repeatability. There is no permanent casino tax and no extra failure penalty for using a
shared token.

---

## 10. Prototype -> understanding -> design promotion

The refined lifecycle is:

```
fabrication project committed
  -> physical experimental asset (serviceable or nonfunctional)
  -> use / inspection / diagnostic evidence
  -> optional destructive analysis
  -> design and process knowledge
  -> competency + facility/tooling + capacity threshold
  -> explicit design-promotion operation
  -> immutable new component design + ancestry edges
  -> optional manufacturing qualification/run
  -> physical production assets
```

The exceptional prototype remains exactly what it was born as. Promotion does not rewrite its design, stats,
maker, operation or serial. It creates a descendant design whose production specification is informed by the
prototype and other legitimate evidence. The prototype may cite the promoted design later for presentation, but
the direction of provenance remains historical; the child did not cause its ancestor.

Promotion is a major attributed event because it asserts reproducible understanding, not merely possession of a
lucky object. It should require an explicit idempotent operation and a novelty/validity decision; it must not be
an automatic threshold trigger.

---

## 11. Naming rights, identity and provenance

### 11.1 Minimal naming layers

Only three layers are needed initially:

1. **Immutable IDs and provenance** — `component_asset_id`, `design_id`, `lineage_id`, operation IDs, ancestry,
   maker and contributors. Never player-facing names as keys.
2. **Optional specimen nickname** — a mutable display annotation on one asset/prototype. It never names a design
   and never changes provenance.
3. **Canonical design name at promotion** — assigned when the design is created and stable as its historical
   designation. Later market/commercial labels are a separate optional presentation layer and may be deferred.

The experimental-asset and prototype-name layers therefore collapse: the prototype's informal/internal name is
simply its specimen nickname. No fourth “experimental product identity” is needed.

### 11.2 Who may name what

- A current asset owner may set/change its specimen nickname. The fabrication operation permanently records who
  made it; a later nickname does not claim creation.
- A newly promoted design is named by the **design-owning/commissioning principal recorded on the promotion
  operation**, not automatically by whichever individual clicked the last analysis button.
- The operation separately attributes performer/contributors. An organization can therefore own/name a product
  while several engineers retain historical credit for discovery, analysis and promotion.
- Manufacturer-created successors are named at their design-introduction event under the manufacturer's naming
  personality and lineage-continuity rules.
- A player/organization creating a genuinely new lineage names the lineage and its first design at the promotion
  event. Successor designs remain within that lineage unless a later promotion explicitly establishes a new one.

The owner must approve the proposed distinction between commissioning/design-owning principal and performing
principal before schema. It is the one genuine naming-rights policy choice not already forced by provenance.

### 11.3 Reconstruction versus derived design

No percentage-difference threshold decides this.

- **Reconstruction** is an explicit promotion intent whose target is faithful reproducibility of a named
  historical design. It creates a new design record attributed to the reconstructing principal, with
  `reconstructed_from` ancestry. Presentation must keep the source visible: “B reconstruction of A/X,” never
  “original X by B.”
- **Derived design** is an explicit promotion which authors a changed production specification, combines parents
  or deliberately pursues a different trade-off. It carries `derived_from` ancestry.
- **Successor revision** is a derived design kept in the same lineage by the design owner. Revision sequence does
  not imply improvement.
- **New lineage** is an explicit promotion outcome when the design is intended as a distinct technological
  family and passes the eventual novelty gate.

The distinction arises from the promoted production specification and declared relationship, not from the
accidental realised stats of one specimen.

### 11.4 Commercial naming

Stable `design_id` and ancestry are authority. A canonical historical design name is presentation attached to
that identity. A later market may advertise a commercial/product label independently without rewriting the
design's historical name or lineage. Initial implementation can defer commercial aliases entirely.

Renaming rules should be minimal:

- IDs, maker, ancestry and operation attribution never change;
- specimen nickname is owner-controlled display text;
- canonical design/lineage name is fixed at creation except an audited operator correction for error/abuse;
- market label, if later introduced, is mutable presentation scoped to an offering/distributor.

### 11.5 Contributor attribution

Do not collapse discovery, analysis, promotion and manufacture into “created by.” Each existing operation owns
its truthful role:

| Event | Attribution |
|---|---|
| experimental fabrication | maker/executing principal + commissioning principal if different |
| inspection/diagnosis | inspecting principal and evidence produced |
| destructive reverse engineering | analysing principal(s), consumed specimen and knowledge facts produced |
| design promotion | design-owning/commissioning principal, performer and contributing operation references |
| manufacturing run | actual manufacturing principal and run operator |
| individual asset | actual run/maker/serial, never the historical source manufacturer after reconstruction |

A generic operation-contributor relation with a small closed role vocabulary is enough. Do not invent patents,
royalties, employment law or contributor voting.

### 11.6 Validation now versus later

Validate now:

- Unicode-safe length bound, trimmed non-empty text and no control characters;
- uniqueness only where presentation genuinely requires it, scoped by maker/lineage rather than globally;
- collision-safe generated fallback name;
- names never become persistence keys or token inputs;
- UI renders them as text, never markup;
- operator correction is audited.

Defer:

- profanity policy beyond ordinary operator moderation;
- commercial aliases and regional branding;
- trademark/IP simulation, licensing, royalties and disputes;
- elaborate naming grammars for every manufacturer;
- public contributor-credit UI and family-tree visualisation.

---

## 12. Existing machines and migration

The accepted migration direction remains unchanged and no migration was executed.

For each existing machine asset, the future migration will:

1. resolve its authored architecture profile and canonical factory-configuration blueprint;
2. deterministically materialise one component asset per declared factory position;
3. attach each component to the existing machine without changing the machine's asset ID;
4. seed original-component exposure from the existing machine odometer where appropriate;
5. create a configuration snapshot identified as migration-derived factory materialisation;
6. leave installer, historical manufacturing batch and original installation time unknown;
7. be idempotent on replay and additive/forward-only.

It preserves ownership, paint, all three production ordinals, odometer, results, entry attribution, transfers and
provenance. It does not invent a replacement history. Development data never replaces Online data.

---

## 13. Smallest coherent implementation order

No elaborate Parts/Engineering implementation is authorised. After Gate 5 acceptance and Gate 6 proof:

1. **Run Gate 6 Proof 1 and Proof 2 in Development.** Record live PASS/FAIL in `MASTER_TEST.md`.
2. **Amend/accept Proposal 25.** Author the closed mount/interface vocabulary, platform inheritance rules and
   factory-configuration shape before vehicle profiles.
3. **Implement the already accepted L120 Inspection slice** against existing machines—competency, knowledge and
   attributed operations, no components needed.
4. **Implement immutable lineage/design/ancestry and design-promotion identity** before the first component
   design exists.
5. **Implement component assets + custody + serviceability + exposure + factory blueprint/backfill together** in
   Development. No mechanical effects yet.
6. **Prove migration replay, conservation, odometer/exposure atomicity and configuration attribution.**
7. **Implement one destructive reverse-engineering project and one fabrication project** using money, elapsed
   time and fixed capacity; complete facts only; junk remains physical.
8. **Add opaque complete-fact sharing and the player ceremony** after the security gate.
9. **Enable only Gate-6-validated physical effects**, through the sole composer, after condition/effect soak.
10. Add manufacturing runs/design promotion and broader markets only after one-off fabrication is sound.

This order establishes proof, knowledge/capability separation and physical history before expensive persistent
rows depend on them.

---

## 14. Deliberately deferred

- production numeric composition/balance laws beyond the proof arithmetic;
- mappings from component families to validated physical effect dimensions;
- grip, braking, suspension, tire and handling effects without a proven carrier;
- exact fabrication/neutral/nonfunctional probabilities;
- whether rework can make nonfunctional-as-built output serviceable;
- raw-material inventories and generic salvage currency;
- partial-fact social sharing;
- autonomous manufacturer R&D tuning and novelty thresholds;
- commercial aliases, rich manufacturer naming grammars and public ancestry UI;
- patents, licensing, royalties, courts, NDAs and other IP simulation;
- production-scale workshops, asynchronous trade/escrow and public technology APIs;
- online migration or deployment.

---

## 15. New owner decisions genuinely required

Only three decisions remain before the next bounded work:

1. **Gate 5:** accept the Proposal 25 amendments—compatibility versus suitability, named interfaces/positions,
   platform overrides and a separate factory blueprint?
2. **Naming:** when commissioning and performing principals differ, does the commissioning/design-owning
   principal control the formal design name while all contributors retain role-specific provenance?
3. **Gate 6 proof authorisation:** authorise a temporary Development-only harness and the two live tests above?

No decision is needed yet on exact effect magnitudes, junk probability, materials, commercial aliases or
manufacturer R&D balance. Those would be premature.

---

## 16. Final recommendation

Record Gates 1–4 and 7–9 as owner-ruled. Accept Gate 5 with the four amendments. Treat Gate 6 as promising but
partial: prove the carrier, then prove composition, then constrain Parts to the dimensions actually demonstrated.

The reconciled model preserves all five north stars:

- knowledge progressively turns randomness into control;
- knowledge tells you what, competency/capability determine execution;
- discovery is not understanding, and understanding is not manufacturing;
- a bad result can remain a real physical thing;
- reproduction and naming never rewrite technological ancestry.

