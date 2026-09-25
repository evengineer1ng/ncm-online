# 32 — Parts / Engineering re-entry audit and reconstruction feasibility

> **STATUS: PROPOSAL** - an evidence-backed reconnaissance and recommendation with **no authority until ruled on**. Covers: *existing Parts / Engineering / R&D implementation status, product lineages, design-specific knowledge, reconstruction signatures, fabrication ceremony and five-lane implications*
> Authority map: [INDEX.md](INDEX.md) - added 2026-09-25; no runtime implementation authorised.

**2026-09-25.** This report answers the Parts / Engineering re-entry brief and its player-facing follow-up.
It changes no runtime behaviour, schema, persistent data, Development server or Online server.

The governing sources are, in descending order:

1. locked decisions in `DECISION_RECORD.md`, especially **L120**;
2. CURRENT authority in `24_FOUNDATION_RECONCILIATION.md`, `17_MARKET_NETWORK.md` and `08_ECONOMY.md`;
3. owner-intent SPEC documents `18_PARTS_ECOSYSTEM.md`, `19_ENGINEERING.md` and `20_WEAR_LIFECYCLE.md`;
4. accepted architecture as recorded by L120 from proposals `21` and `22`;
5. the current code and schema, which are authority for what is actually built;
6. this report's recommendations, which remain proposals.

No claim below turns an unbuilt design into an implementation fact.

---

## 1. Executive verdict

The proposed direction is **compatible with the accepted Parts / Engineering architecture**, but only if it is
implemented as an additive refinement of four things that already exist in the design:

1. component **design** versus physical component **asset**;
2. bounded Engineer **competency** versus growing design-specific **knowledge**;
3. design potential versus manufacturing/fabrication **realisation**;
4. persistent, attributed operations and provenance.

The smallest clean extension is:

```
product lineage
  -> immutable design revision
      -> bounded server-owned process dimensions
          -> manufacturing run / fabrication project
              -> physical component asset
```

with a separate ancestry graph for manufacturer successors, reconstructions and player-derived designs.

The opaque player-facing value should **not** be the actual PRNG seed, a hash of stats, or a partly revealed
hexadecimal number. It should be a high-entropy, server-issued **knowledge token** that refers to one design or
process fact. The actual generator seed, resolver inputs and full outcome truth remain server-only. Partial
knowledge is best represented as independently verifiable facts or fragments, not textual proximity inside one
number.

Unknown process dimensions can cleanly return to the normal procedural distribution. A known token selects a
previously established result for that dimension; an unknown dimension is resolved afresh from the ordinary
design-conditioned distribution when the project is committed. No interpolation exists, and no “guessing
penalty” is needed.

The proposal has one hard platform constraint and three major product risks:

- **Hard constraint:** OPEN//77 exposes no native vehicle component objects, and its one per-vehicle
  `setPerformance` profile is already claimed by class ceilings. NCM can build the data, economy, history and
  simulation honestly, but it must not promise physical handling effects until one composed server-owned effect
  path is proven. `31_CAPABILITY_AUDIT.md` is decisive here.
- **Information risk:** a human-shareable deterministic token will eventually be copied into Discords, wikis and
  databases. That is not an exploit if social sharing is intended; it means informational scarcity is temporary,
  and long-term scarcity must also come from capability, capital, time, capacity, specimens and supply.
- **Economy risk:** money + time make experimentation costly, but do not secure a small or predictable search
  space. Cryptographic unguessability and a non-oracular server boundary are still required.
- **Complexity risk:** one process field per visible stat becomes spreadsheet crafting; arbitrary player-added
  fields become slot spam. The design grammar must own a small bounded set of meaningful dimensions.

Nothing should be implemented from the new briefs yet. The immediate next action is an owner ruling on the
decision gates in section 18.

---

## 2. The two existing Parts lineages must not be conflated

There are two materially different systems in this workspace.

### 2.1 Released single-player NCM Parts — implemented

The public CET payload under `ncm-localized/` contains a working career garage and parts system:

- `data/parts.lua` is a 30-design authored catalogue across six slots: engine, drivetrain, brakes, handling,
  stability and anti-crawl.
- Every design has a stable id, authored name, slot, family, price, rarity, description and fixed modifier/
  additive vector.
- `modules/parts.lua` creates persistent part instances in the career JSON store. An instance has an id,
  `partId`, acquisition time, condition, source and installation location.
- A part moves between inventory and a vehicle loadout; installing does not mint it and removing does not
  destroy it.
- Vehicle slot counts are deterministically generated from authored templates, prestige, vehicle identity and
  career seed by `data/vehicle_slot_profiles.lua`.
- Shop stock, offers, race rewards and rival builds are deterministically selected from the authored catalogue.
- Installed effects compose into the existing tuning and AI-performance layers, with stacking attenuation and
  condition scaling.
- The garage UI charges Cyberpunk eddies for ordinary shop purchases and priced offers. Starter inventory,
  contact offers, promotion crates and race-linked offers are separate acquisition paths.
- The whole state lives inside `careers.json`; there is no relational provenance ledger or shared-world
  conservation authority.

What this released system does **not** contain:

- procedural creation of new product designs;
- manufacturers as persistent economic actors;
- product lineages or generations;
- manufacturing runs;
- Engineer competency or five-lane progression;
- asynchronous engineering projects;
- fabrication or crafting;
- destructive reverse engineering;
- design-specific knowledge;
- wear accrual, repair or service history;
- authoritative multiplayer trading or supply conservation.

Its “procedural” behaviour is selection and composition from a fixed 30-design catalogue, not autonomous R&D.

### 2.2 NCM Online Parts / Engineering — designed, not implemented

Online has a much deeper accepted design, but **zero component assets and zero Engineer gameplay**. The current
schema ends at migration 030 and contains no component, engineering, workshop, knowledge-token, fabrication,
wear or service table. Searches of `ncm/core` and the Online hosts confirm the absence.

The implemented Online foundations are real and valuable:

- persistent machine assets with stable `assetId`, `vehicleKey`, owner principal and lifecycle;
- deterministic factory paint and authoritative odometer;
- three immutable production ordinals: global NCM, manufacturer and model;
- production-run claims with nonce/idempotency protection;
- finite shelf stock, ceilings, batches and committed cadence;
- deterministic manufacturer supply personalities responding to recorded market history;
- market offerings, inventory, discovery/access knowledge and atomic single-asset purchase;
- an idempotent ledger and derived balances;
- player-scoped machine knowledge/evidence with epistemic source and observation provenance;
- owner-principal columns for Drivers and Organizations.

Those are reusable foundations. They are not hidden implementations of components, R&D, Engineering or
fabrication.

### 2.3 The rarity conflict is real, but it is not permission to rewrite SP

The released SP system explicitly uses `Common / Street / Pro / Elite` rarity and colour presentation. The
Online Parts spec explicitly rejects rarity tiers, and the re-entry brief reinforces that rejection.

The clean interpretation is product-boundary-specific:

- preserve the released SP behaviour and solo roadmap unless separately authorised;
- do not import its rarity ontology into Online;
- do not claim the two systems already share a canonical component catalogue;
- if convergence is later wanted, treat it as an explicit migration/product decision, not a silent cleanup.

---

## 3. Existing intended Online architecture, reconstructed

### 3.1 Component ontology

`18_PARTS_ECOSYSTEM.md` separates four layers:

1. **mechanical ontology** — twelve component families;
2. **compatibility** — machine architecture versus design constraints;
3. **R&D** — creates new component designs;
4. **manufacturing / supply** — creates physical assets from a design.

R&D must be bounded, deterministic, auditable and allowed to produce nothing. It may create content only inside
an authored grammar. Manufacturer R&D personality is explicitly separate from manufacturer supply personality.

The design/asset distinction is already clear:

- a component **design** is a product specification;
- a component **asset** is one manufactured physical example;
- installation changes custody, not identity;
- removal changes custody, not identity;
- transfer preserves history;
- physical destruction must not delete historical design truth.

### 3.2 Seven layers of component state

The accepted specs require these to remain distinct:

1. design characteristics;
2. manufacturing/fabrication realisation;
3. accumulated exposure;
4. derived condition;
5. installation workmanship;
6. repair/service workmanship;
7. provenance and attributed history.

The new process-knowledge proposal belongs primarily between layers 1 and 2. It must not become a replacement
for condition, installation quality or repair quality.

### 3.3 Engineering progression

L120 locks the core storage distinction:

- **competency** is bounded capability — at most 15 skills + 12 mechanical families under the currently
  provisionally accepted ontology;
- **knowledge** is unbounded, design-specific state — one Driver/principal may know different facts about
  different designs;
- performing an operation requires the relevant combination of both;
- neither substitutes for the other.

The five lanes remain:

1. Diagnostics / Inspection;
2. Maintenance / Repair;
3. Installation / Integration;
4. Fabrication / Crafting;
5. Design / Manufacturing.

Time regime belongs to the **operation**, not the lane. Inspection may be an immediate bench operation while
destructive reverse engineering is a persistent project, even though both sit under Diagnostics.

### 3.4 Reverse engineering

The established design is not a generic blueprint unlock:

```
physical component is legitimately controlled by the actor
  -> one atomic commit marks it consumed, never DELETEs it
  -> analysis project commits inputs, competency snapshot and seed
  -> elapsed authoritative time passes
  -> resolution yields design-specific knowledge according to capability and sophistication
  -> destruction and knowledge provenance remain forever
```

It is NCM's first intentional physical-asset sink. Its output is knowledge, never generic salvage materials.
Money buys the specimen/opportunity; it does not buy understanding.

### 3.5 Fabrication and manufacturing

The accepted design distinguishes:

- design potential;
- one asset's manufacturing/fabrication realisation;
- repeatable production capability.

Poor fabrication is explicitly intended to create a poor but legitimate physical component. A lucky outcome
does not make a beginner a master, does not improve the underlying design and does not retroactively improve
older assets. Manufacturing is the ability to repeat and sustain; fabrication is making one.

### 3.6 Wear

Wear is accepted as a pure deterministic derivation from authored profile + component identity + accumulated
exposure + append-only service relief. It is not a periodic random roll. Exposure is monotonic; condition and
severity are derived. The Engineering/ wear interface is one persisted `relief_m` value per repair operation.

The new reconstruction signatures must not be reused as lifecycle seeds. Design/process repeatability and
wear individuality are different authorities.

---

## 4. Implementation-status matrix

| Concern | Released SP | Online code now | Authoritative Online intent |
|---|---|---|---|
| authored part designs | **built** — 30 | none | twelve-family procedural ontology |
| physical part instances | **built** in career JSON | none | persistent component assets |
| install/remove | **built** | none | custody-preserving operations |
| compatibility | six slot categories + generated slot counts | none | derived machine architecture profile; proposal 25 unruled |
| part effects | **built** through CET tuning/AI composition | none; no native components | effect audit constraint; class ceiling already uses `setPerformance` |
| shop/market | **built** SP shop/offers | **built for vehicles** | extend market network to component supply/distribution |
| finite manufacture/supply | no conservation authority | **built for vehicles** | reuse principles, not blindly the tables |
| manufacturer supply personality | none | **built for vehicles** | reusable philosophy |
| manufacturer R&D personality | none | none | specified, separate from supply personality |
| autonomous procedural design R&D | none | none | specified, novelty-gated, may yield nothing |
| product lineage/revision | none | none | named in spec, not modelled |
| Engineer competency | none | none | accepted architecture, unbuilt |
| design-specific knowledge | none | machine-knowledge precedent only | accepted broad ladder; per-dimension refinement is new |
| engineering projects/time | none | production-run claim precedent only | accepted architecture, unbuilt |
| reverse engineering | none | none | destructive, timed, skill-dependent, provenance-preserving |
| fabrication | none | none | seeded bounded outcome vector, poor parts persist |
| repeat manufacturing | none | vehicle primary production only | player manufacturing horizon, unbuilt |
| component wear/exposure | static birth condition only | vehicle odometer only | component exposure + pure derived wear, unbuilt |
| attributed engineering operations | none | none | foundation primitive P5, unbuilt |
| heterogeneous barter | none | single-vehicle purchase/transfer only | transfer envelope P4, unbuilt |

---

## 5. Existing probability and deterministic models — what actually exists

### 5.1 SP

The SP system has explicit weighted tables for rarity selection by career tier, offer kind and rival tier. A
local LCG drives deterministic shuffles, shop stock, offers, rewards, rival loadouts, slot counts and initial
condition. Outcomes are chosen from 30 authored designs; individual designs do not procedurally acquire new
characteristics.

There is no fabrication success/failure model, no neutral process result, no knowledge-controlled dimension,
no product-generation dice and no manufacturing run.

### 5.2 Online implementation

Online vehicle production has deterministic scheduling and bounded supply decisions, but no component outcome
roll. A production tick may mint zero because the shelf is full; that is not a fabrication failure or neutral
engineering result.

### 5.3 Online accepted design

The accepted Engineering proposal specifies only the shape:

- server-owned, seeded and committed at project start;
- competency affects range, expected outcome and variance/control;
- an outcome vector, not one quality number;
- correlated dimensions rather than an independent casino roll per stat;
- poor outcomes remain real physical components;
- learning is not purely stochastic;
- exact distributions, dimensions, percentages and thresholds are deliberately undefined.

Therefore there is **no existing numeric probability model to recover**. Any report that supplies percentages
would be inventing them.

Neutral/no-meaningful-effect space does not exist in implemented Online code and is not quantified in the
accepted design. Adding it is compatible and advisable, but is a new distribution requirement.

---

## 6. Where deterministic identity belongs

The clean answer is “at several levels, for different reasons,” not one seed per thing.

| Level | Owns | Must not own |
|---|---|---|
| lineage | durable product-family identity and naming continuity | stats, physical provenance |
| design revision | authored/generated architecture and potential; process-dimension set; generator version | physical manufacture, current condition |
| process dimension | one bounded controllable source of variation within that revision | a player-visible stat label by default |
| manufacturing run | who executed which repeatable process, when, and at what scale | original designer/manufacturer attribution if reconstructed elsewhere |
| fabrication project | committed known facts, unresolved dimensions, costs, competency snapshot and private resolution nonce | mutable “reroll” state |
| physical asset | immutable realised outcome, maker/run, serial, lifecycle seed and provenance | future skill/knowledge changes |
| wear derivation | asset-specific lifecycle trajectory | design/process knowledge |

A manufacturer producing 100 units from one mature run may create functionally very similar assets, with
bounded manufacturing realisation differences. A one-off experiment may create a unique realised combination.
Neither requires 100 unrelated design secrets.

The current Online precedents map well:

- `vehicleKey` demonstrates design/model identity;
- `market_production_run` demonstrates one claimed manufacturing event;
- `assetId` + three ordinals demonstrate physical identity and provenance;
- deterministic paint demonstrates immutable instance state;
- asset-id-derived wear was proposed for lifecycle individuality.

The actual process resolver should be versioned, and resolved outputs should be stored immutably with the
asset/run. Determinism is an audit property, not permission to depend forever on recomputing old history through
whatever generator code happens to be current.

---

## 7. Product lineages and technological ancestry

Lineage is a small, natural extension because `18_PARTS_ECOSYSTEM.md` already says designs carry lineage and
revision; it simply never proposed the table shape.

### Recommended model

```
component_lineage
  lineage_id
  world/server scope
  originating principal / manufacturer identity
  family_id
  stable key
  naming policy reference
  introduced_at

component_design
  design_id
  lineage_id nullable                 -- new family may establish one
  family_id
  revision_label                     -- presentation only; never power
  generator_version
  production_specification
  introduced_by_operation_id
  introduced_at / discontinued_at

component_design_ancestry
  child_design_id
  parent_design_id
  relation_kind                      -- successor / reconstructed_from / derived_from
  ordinal                            -- stable display order, not merit
```

Use a many-to-many ancestry table rather than a single `parent_design_id`. A derived design may legitimately
combine knowledge from Mk II, Mk III and an unrelated process. The core validator must reject cycles.

Revision labels such as “Mk IV” are presentation. Nothing in the resolver may convert revision order into a
bonus. New-family creation and lineage iteration are separate allowed R&D outcomes. The novelty gate may choose:

- no worthwhile design;
- a successor in an existing lineage;
- a genuinely new lineage.

Physical extinction never deletes these rows. Production runs, consumed assets and attributed operations point
back to them with restrictive foreign-key behaviour or archival lifecycle states, never cascading deletion.

---

## 8. Design-specific knowledge and opaque reproducibility

### 8.1 What naturally corresponds to a process dimension

The best existing concept is the future **bounded outcome vector** attached to design potential and fabrication
realisation. A process dimension is not necessarily “power” or “thermal.” It is one server-defined, meaningful,
controllable degree of the design's production process which influences one or more validated outcome
dimensions, potentially with correlations.

Examples may be presented as `PROCESS 01`, `PROCESS 02` or manufacturer-flavoured operation names. The server
may know which mechanical outcomes they influence while a novice does not. Diagnostics and accumulated evidence
can progressively reveal relationships without making the pre-fabrication screen an arbitrary stat editor.

### 8.2 Base design and process knowledge should be separate

Represent at least these fact kinds:

- `design_basis` — enough knowledge to attempt the underlying design;
- `process_fact` — control over one process dimension or one part of it;
- `production_method` — tooling/repeatability knowledge needed for sustained runs.

They are not one ladder with a single top. Capability checks compose them with Engineer competency and facility
requirements.

### 8.3 Do not expose the actual generator seed

The actual resolver should use server-private state, for example a versioned secret-backed derivation over:

```
world + design revision + process dimension + project/run identity + committed inputs
```

The player-facing code is a randomly assigned, high-entropy lookup/capability token. It does not encode stats,
is not the input domain of the generator and has no useful neighbouring value. The server maps a valid token to
an authoritative knowledge fact. Invalid codes reveal only invalidity; they never reveal “close,” “three chunks
correct,” a candidate stat or a partial outcome.

Why not expose the true seed:

- copied server code or a reconstructed generator becomes an offline optimizer;
- version changes can silently reinterpret historical strings;
- a predictable seed domain makes length cosmetic;
- logs, WebUI payloads and modified clients would receive more authority than they need.

### 8.4 Partial knowledge should be facts, not missing hexadecimal characters

Literal strings with question marks are attractive presentation and poor state:

- “how many characters are known?” becomes an accidental progression scale;
- positional fragments create an online correctness oracle;
- partial collisions and versioning become ugly;
- players optimize string acquisition rather than engineering evidence;
- it implies textual proximity where the design explicitly rejects it.

Recommended representation:

```
engineering_knowledge_fact
  fact_id
  owner_principal_kind / owner_principal_id
  design_id
  process_dimension_id nullable      -- null for base-design facts
  fact_kind
  fragment_id nullable
  source_operation_id
  learned_at
  idem_key
```

Completeness is derived from the set of required facts for the versioned design/dimension. Individual facts may
have independently random, human-shareable codes. Pooling three codes can therefore pool three facts, without
pretending they are adjacent slices of a number. The same fact imported twice collides idempotently.

The smallest simpler alternative is to make **only complete process knowledge shareable** and keep partial
progress as private evidence. That loses partial social pooling but avoids a great deal of code-gameplay
machinery. It should be the default unless partial pooling proves central in play.

### 8.5 The unavoidable social consequence

If a code can be told to one human, it can be published to every human. NCM cannot simultaneously promise:

- plain-text, out-of-game social sharing; and
- permanent scarcity of the shared information.

World-specific tokens and enormous search spaces stop guessing; they do not stop copying. Once a community
catalogues a process, the remaining differentiation is the intended one: skill, time, capital, facilities,
capacity, access, specimens, reputation and execution.

---

## 9. Unknown dimensions, known dimensions and experimentation

At project commit:

1. validate the actor controls the base-design knowledge required to attempt the design;
2. validate each supplied process token, server-side;
3. freeze the actor's competency, facility/capacity, economic inputs and known fact set;
4. assign a private project resolution nonce/seed;
5. debit money and commit any consumed inputs in the same transaction;
6. set `ready_at` and release no result information early.

At resolution:

- a controlled dimension resolves to the authoritative outcome referenced by its complete known process fact;
- an unresolved dimension samples the **normal design-conditioned distribution** using the private project
  state;
- a wrong/invalid token is not “almost right”; it is not a valid controlled fact and the dimension is unresolved;
- correlated dimensions resolve through the design's joint model, not independent bonus slots;
- the immutable realised vector is stored on the resulting asset/operation.

Knowledge turns uncertainty into control. Competency still affects whether the process is executable, its
failure floor, waste, time, attainable manufacturing realisation and repeatability. A master without the fact
does not approach the missing historical outcome. A novice with the fact may still fail to execute it.

### Neutral and failure outcomes

Neutral/no-meaningful-effect space should be explicit in the eventual distribution. Otherwise adding process
complexity tends to add buffs. Exact mass remains unchosen.

The follow-up brief introduces “fabrication failure,” while the accepted spec says fabrication is not pass/fail
and poor work produces a real poor component. This needs a ruling, not a silent merge. The clean distinction is:

- **serviceable but poor/neutral/detrimental result:** a real component asset exists;
- **execution failed before serviceable hardware existed:** money/time/inputs are consumed, an attributed
  operation exists, but no component asset is born.

Whether the second category exists at all is open. It should not be introduced merely to create punishment.

### Lucky discovery does not imply understanding

A lucky experimental asset stores what happened, not why the Engineer can reproduce it. The completed project
earns normal competency practice and creates diagnostic evidence. It should not automatically grant a complete
process fact.

The asset may then be inspected or destructively analysed, including by its own maker. That supports:

```
experiment -> unusual specimen -> inspection -> destructive analysis
           -> process knowledge -> repeatability
```

Repeated experimentation may add bounded evidence or familiarity, but must not return a direction, partial
correctness score or hidden stat oracle. Knowledge extraction belongs primarily to Diagnostics / Reverse
Engineering, preserving the lane distinction.

---

## 10. Process complexity

Players must not add process slots. Complexity comes from the design grammar.

Natural inputs already present in the intended architecture are:

- mechanical family and subfamily;
- the machine interface/architecture the design targets;
- design sophistication;
- the bounded validated mechanical vocabulary;
- correlations and trade-offs selected by R&D;
- the number of genuinely controllable production decisions the generated design contains.

The unruled machine-profile proposal (`25_MACHINE_ARCHITECTURE_PROFILE.md`) can constrain fitment and demand,
but should not by itself become a “complexity stat.” The R&D grammar can derive a small bounded process-dimension
set from the design's real structure. Store the generated dimensions; do not recompute their count from later
code.

More dimensions mean more potential and more burden, not more power. Costs may scale from authored/derived work
units such as setup effort, process sophistication, tooling requirement and diagnostic burden. The UI boxes are
a rendering of those facts; the price must never be `box_count * €$500`.

---

## 11. Player-facing fabrication and inspection ceremony

### Before FABRICATE

Show:

- design/product identity and whether it is original, reconstructed or derived;
- the actor who will actually manufacture it;
- base-design knowledge state;
- a bounded list of design-owned process domains;
- for each domain: controlled / partly understood / unresolved, without a guaranteed result label;
- facility/capability refusals and required competency in plain language;
- committed money, elapsed time, capacity use and consumed specimen/input consequences;
- what provenance the result will carry;
- an honest observable opportunity envelope only where Diagnostics/knowledge justifies it.

Do not show:

- a RANDOMIZE/REROLL control;
- selectable target stats;
- the hidden distribution or thresholds;
- actual private generator seeds;
- complete authoritative effects the Engineer has no way to know.

Initiating an experiment with unknown dimensions is simply pressing **FABRICATE** with those domains marked
unresolved. The server commits ordinary uncertainty; the player is not asked to invent a fake string.

### After completion

Show the physical result first:

- component serial/asset identity;
- actual maker and manufacturing/fabrication operation;
- source design and ancestry;
- immediately observable fit/function;
- diagnostic findings at the actor's current breadth/precision/depth;
- unknown or unresolved observations honestly labelled;
- project cost/time and whether serviceable hardware was produced.

Do not automatically reveal the complete outcome vector. The server owns the truth; the player owns only what
their observation, documentation and analysis justify. A spectacular component may be visibly spectacular and
still have an unexplained cause.

Diagnostics therefore affects observability, not the component itself. It can reveal additional facts,
precision and causal confidence. It must not buff the part.

### Unlabelled must not mean unreadable

Pure opaque strings will feel like password entry, not engineering. A reasonable graduated presentation is:

- novice: Process A / B / C; controlled or unresolved; broad observed result;
- competent diagnostician: relationships and confidence (“A appears tied to thermal consistency”);
- deep knowledge: exact reproducibility token and validated outcome envelope;
- authoritative server: complete mapping, never sent wholesale to clients.

---

## 12. Costs and economic resistance

### What the existing design already says

For destructive reverse engineering, the existing costs are explicit:

1. **capital** — acquire the specimen;
2. **opportunity** — permanently remove a tradable physical asset;
3. **time** — complete the analysis project;
4. possibly **capacity** later.

For fabrication/manufacturing, time, committed inputs and capacity are intended, but no exact recipe economy is
defined. The released SP shop uses eddies and instant delivery; that is not Online fabrication authority. Online
vehicle manufacturing currently uses cadence, batch, shelf ceiling and market history, not a raw-material
simulation.

### Recommendation

Use **money + elapsed time** as the root fabrication abstraction for the first implementation, plus the existing
non-monetary costs that are already designed:

- workshop/project capacity;
- consumed reverse-engineering specimen where applicable;
- opportunity cost of occupied capacity;
- knowledge and capability requirements;
- market/access cost of obtaining source hardware;
- failed or low-value output occupying real supply and storage.

Do not introduce a general ore/electronics/chemical inventory now. Add a specific consumable only when a real
mechanic cannot be expressed honestly by money, time and a named component input.

### Is money + time sufficient?

It is sufficient for economic weight only if:

- costs are committed before the result is known;
- cancellation cannot refund the attempt into a reroll;
- concurrent capacity is bounded at the workshop/principal level, not merely per character;
- mediocre output cannot always be sold back for at least its marginal cost;
- market demand and storage prevent infinite bad-part externalisation;
- alternate accounts cannot multiply free starter capital/capacity without consequence.

It is **not** sufficient as brute-force security. A small predictable token space remains breakable offline at
zero fabrication cost. Server-private derivation and high-entropy tokens solve that different problem.

No arbitrary daily attempt limit is needed if time, capital, capacity, supply and resale are real. Rate limiting
invalid token submissions is still appropriate network abuse protection, not a gameplay guessing penalty.

---

## 13. Provenance, extinction and reconstruction

Physical extinction and informational retention fit the existing model cleanly:

- a component asset may reach `consumed_by_analysis`, `destroyed` or another terminal lifecycle state;
- the asset row and attributed terminal operation remain;
- the manufacturing run remains;
- the immutable design and lineage remain;
- aggregate physical population may legitimately become zero;
- no “last specimen” protection exists.

A reconstruction creates new provenance:

```
historical design by Manufacturer A
  -> knowledge extracted by Engineer(s)
      -> derived/reconstructed design attributed to Principal B
          -> B manufacturing run
              -> new B-made component asset
```

Functional equivalence never rewrites `made_by`, manufacturing run, serial or origin. An ancestry edge records
what B learned from A; it does not impersonate A.

An experiment that changes an uncontrolled negative dimension is not automatically a new persistent design.
Creating a design row for every attempt would produce database exhaust. Treat the result as a prototype asset
with an experimental process record. Promotion to a repeatable derived design occurs only after sufficient
knowledge/tooling and an explicit Design/Manufacturing operation.

---

## 14. Five-lane interaction

The common grammar can be:

```
knowledge + competency + legitimate operation + committed inputs
  -> bounded domain-specific uncertainty
      -> attributed persistent outcome
```

The lanes must remain mechanically different.

| Lane | Uses process-token representation? | Role in this loop |
|---|---|---|
| Diagnostics / Inspection | **reads/reveals, does not fabricate** | determines observable facts, precision, confidence and causal clues; destructive RE can recover knowledge after elapsed time |
| Maintenance / Repair | **no** | acts on known conditions; resolves workmanship into `relief_m`; preserves exposure/history |
| Installation / Integration | **no** | validates fit and resolves installation workmanship; no “installation seed” |
| Fabrication / Crafting | **yes, as committed known/unresolved process facts** | makes one physical component; unknown dimensions use normal uncertainty |
| Design / Manufacturing | **yes, deepest use** | turns prototypes/knowledge into stable designs, tooling, repeatability and production runs |

Useful interdependence should emerge from facts, not party requirements. One player may eventually develop all
lanes. Different specialists can contribute because Diagnostics exposes facts, Fabrication executes them,
Manufacturing stabilises them, Integration fits them and Repair sustains them. No operation should demand five
human players merely to force cooperation.

---

## 15. Security and brute-force threat analysis

### Threats

1. **Offline generator clone.** If client code contains the resolver and token is its seed, candidates are free.
2. **Small-domain hash reversal.** `HASH(stats)` hides nothing if the input domain is enumerable.
3. **Validation oracle.** “Two fragments correct” lets scripts solve the code incrementally.
4. **Early-result leakage.** Project rows, WebUI payloads, logs or APIs reveal outcomes before time/cost settles.
5. **Modified-client enumeration.** Any callable endpoint accepting arbitrary candidates can be scripted.
6. **Replay/cancel reroll.** Starting, peeking, cancelling or reconnecting changes a result without full cost.
7. **Parallel-account throughput.** Per-character limits are multiplied by alts.
8. **Public code archive.** Valid human-shareable codes become permanent community knowledge.
9. **Version drift.** A generator update changes what an old token means.
10. **API overexposure.** A broad Market/component JSON response leaks private R&D state or player knowledge.

### Required boundary

- resolver and authoritative process mappings run server-side only;
- actual PRNG/KDF inputs remain private;
- player tokens are random references, not generator seeds;
- token validation returns valid/invalid only and is rate-limited;
- project identity, inputs, capability snapshot, private nonce, cost and ready time commit atomically;
- resolution is idempotent and nonce-claimed;
- raw project/result secrets never enter global state bags, broad WebUI payloads, logs or public APIs;
- every design and outcome carries a resolver/generator version;
- resolved historical outputs are stored, not reinterpreted by new code;
- knowledge payloads are scoped to the requesting principal;
- public product history and private process truth are separate read models.

These measures prevent guessing and save-scumming. They intentionally do not prevent a knowledgeable player
from publishing a valid share code.

---

## 16. Migration implications for existing Machines

The world is not empty. Existing machine assets, ownership, odometers and provenance must remain untouched.

The accepted direction already says component assets and exposure accrual ship together. The re-entry brief adds
the correct historical premise: existing Machines already possess their canonical factory components even if
those rows were not materialised at purchase.

Recommended backfill after the component model is approved:

1. define one versioned factory configuration per `vehicleKey`;
2. for every existing machine asset, create one immutable configuration snapshot and the required factory
   component assets with deterministic idempotency keys such as `factory:<assetId>:<position>`;
3. attribute only what is known: vehicle model/factory specification and the migration event; do not invent a
   historical human installer, precise batch or timestamp that was never recorded;
4. seed each original factory component's distance exposure from the machine's existing odometer, as already
   proposed in foundation M8;
5. preserve the machine's `assetId`, ownership, paint, ordinals, odometer, results and transfer history;
6. retain old columns/tables until Development migration, restart, idempotent replay and rollback verification
   pass;
7. promote code/migrations only—never a Development database.

This assumes the established statement that current components are the original factory set. If evidence later
shows an existing machine changed hardware before materialisation, unknown history stays unknown; do not invent a
replacement story.

---

## 17. Exact schema, code and documentation changes proposed

These are proposed shapes, not migration numbers. Numbering them before approval would make an unruled model look
committed.

### 17.1 Schema

Add, in dependency order:

1. **Physical-asset/custody foundation** from `24_FOUNDATION_RECONCILIATION.md` P2/P3, extending the already-built
   owner principal without replacing machine assets.
2. `component_lineage`, `component_design`, `component_design_ancestry` and `component_process_dimension`.
3. `component_manufacturing_run` and immutable `component_asset` realisation/provenance fields.
4. `attributed_operation` with operation kind, actor principal, target/source assets, committed input snapshot,
   outcome snapshot, resolver version and unique idempotency key.
5. `engineer_skill` and `engineer_family` for the bounded 27-value competency state.
6. append-only `engineering_knowledge_fact`, with optional dimension/fragment and source operation.
7. `engineering_project`, following the production-run nonce claim: committed inputs, competency snapshot,
   private resolution reference, `started_at`, `ready_at`, `resolved_at`, state and claim nonce.
8. process-token registry mapping a high-entropy public code/hash to one versioned knowledge fact while keeping
   generator secrets separate.
9. installation/configuration snapshot, component exposure and service records in the same release as physical
   component assets.
10. distribution/offering relations at manufacturer, family, lineage and design scope before component stock
    reaches more than Base Market.

Required invariants:

- immutable designs/history are never cascade-deleted by asset extinction;
- ancestry graph is acyclic;
- a consumed asset cannot re-enter custody or supply;
- a physical asset has exactly one current custody state;
- a fabrication/manufacturing outcome is written once;
- a token never exposes or doubles as a generator seed;
- a project resolves at most once;
- old rows retain unknowns as null/unknown, never plausible backfill.

### 17.2 Core code

Proposed pure modules:

- `data.component_families` — the twelve-family closed vocabulary;
- `data.machine_architecture` + `components.compatibility` after proposal 25 is ruled;
- `components.lineage` — ancestry validation and presentation-neutral revision ordering;
- `components.process` — versioned design-conditioned dimensions, correlation and known/unknown resolution;
- `engineering.competency` — pure progression reducer;
- `engineering.knowledge` — fact validation and completeness derivation;
- `engineering.projects` — commit/resolve state rules without database or clock;
- `components.wear` — the already accepted pure condition derivation.

Do not extend SP `modules/parts.lua` into the Online authority. Reuse lessons and vocabulary deliberately; do not
share mutable persistence or rarity assumptions.

### 17.3 Host code

- a narrow Engineering host for persistence, project claims and principal-scoped payloads;
- atomic consume-and-project creation for destructive analysis;
- atomic debit/input commit/project creation for fabrication;
- idempotent resolution that mints at most one physical asset;
- component manufacturing/supply adapter reusing the vehicle production principles;
- custody/install/remove/trade operations through one transfer envelope;
- odometer checkpoint integration so machine distance and installed-component exposure commit together;
- Market projection that exposes public offerings without process secrets.

### 17.4 Documentation

After owner rulings:

- amend L120 or add one new locked decision covering lineage, process knowledge and the visibility/security
  boundary;
- amend `18_PARTS_ECOSYSTEM.md` with lineage/ancestry and extinction retention;
- amend `19_ENGINEERING.md` with base versus process knowledge, lucky prototypes and the chosen failure policy;
- amend `21_ENGINEERING_PROPOSAL.md` or supersede its relevant sections with the approved project/token model;
- reconcile `IDEA-277` roll ceremony with the new preference for unlabeled process domains;
- approve/reject `25_MACHINE_ARCHITECTURE_PROFILE.md` before authoring component fitment;
- keep this report PROPOSAL or archive it as historical evidence after its decisions move into the record.

---

## 18. What to implement now, what to reserve, and decision gates

### No implementation in this session

The brief explicitly asks for evaluation first, and AGENTS.md forbids major OPEN//77 implementation before the
reconnaissance is reviewed.

### First implementation slice after approval

Preserve the accepted order rather than jumping straight to the attractive fabrication UI:

1. rule on proposal 25 and the effect-carrier boundary;
2. implement the L120 Diagnostics/Inspection competency substrate against existing machine assets;
3. implement immutable component lineage/design history **before the first component design row exists**;
4. implement component assets + custody + factory configuration backfill + exposure accrual together in
   Development;
5. prove migration replay, odometer/exposure atomicity and the existing AG gates;
6. then implement destructive reverse engineering and one fabrication project path with money, time and fixed
   capacity;
7. only then add process tokens/partial knowledge and the player-facing ceremony.

This order validates the profession, physical conservation and history before building a secret-code UI on top.

### Reserve for later

- autonomous manufacturer design R&D and novelty tuning;
- multiple manufacturer naming grammars;
- partial share-code fragments rather than complete fact sharing;
- production-scale player workshops and market admission;
- heterogeneous asynchronous trade/escrow;
- raw-material economies;
- family-tree visualisation;
- public technological-history APIs;
- mechanical effects not proven compatible with the one `setPerformance` authority;
- elaborate archaeology quests (explicitly unwanted).

### Owner rulings required

1. Is the public human-shareable token model accepted despite inevitable community cataloguing?
2. Are only complete process facts shareable initially, or must partial facts also be communicable?
3. Does a fabrication execution failure with no asset exist, or does every completed attempt yield some real
   serviceable/poor asset?
4. Is the pre-commit ceremony allowed to show effect-labelled ranges when Diagnostics knows them, or should it
   always stay process-labelled?
5. Is proposal 25's machine architecture representation accepted?
6. May class ceiling + component/wear effects ever be composed into one server-owned `setPerformance` profile,
   or do component effects remain simulation/eligibility-only until a new platform primitive exists?
7. Does a one-off experimental success remain only an asset until an explicit Design/Manufacturing promotion
   operation creates a descendant design? This report recommends yes.
8. Is money + time + capacity the first fabrication cost model, with materials deferred? This report recommends
   yes.
9. Is the first shareable representation an opaque token/reference rather than literal seed fragments? This
   report recommends yes.

---

## 19. Direct answers to the follow-up's 30 questions

| # | Answer |
|---:|---|
| 1 | Yes. The bounded outcome-vector design supports known versus unknown dimensions; no implementation exists. |
| 2 | A process dimension most naturally corresponds to a server-defined controllable dimension of design potential / fabrication realisation, potentially influencing several correlated mechanical outcomes. |
| 3 | Not yet. The intended ontology and unruled architecture profile provide natural inputs, but no process-complexity model exists. |
| 4 | Store a bounded design-owned dimension set generated from family, architecture and sophistication; never let players add slots. |
| 5 | Yes. Known facts select established outcomes; unknown facts use the ordinary design-conditioned distribution. |
| 6 | Yes. Expose process state and diagnostic knowledge, not target-stat selection. |
| 7 | Yes. Unknown is a committed fabrication choice, not a RANDOMIZE control. |
| 8 | Select a known base design, optionally supply known process facts, accept unresolved domains, commit money/time/capacity, then wait for resolution. |
| 9 | Identity, ancestry, knowledge state, unresolved domains, requirements, cost, time, capacity, provenance and only honestly knowable ranges. |
| 10 | A real asset or explicit execution failure, serial/provenance, immediately observable behaviour, diagnostic findings and unresolved facts. |
| 11 | Only what is directly observable/documented plus what the Engineer's Diagnostics can justify; not the full server vector. |
| 12 | Diagnostics controls breadth, precision and causal confidence of information. It never changes the part. |
| 13 | No current fabrication exists. The accepted design already separates lucky outcome from mastery; it does not define automatic process knowledge. |
| 14 | It should not imply understanding. At most it creates practice and evidence. |
| 15 | Yes; that is compatible and desirable. |
| 16 | Yes, including by its maker, with normal destructive-analysis consequences. |
| 17 | Yes for first economic weight if capacity and resale are controlled; no as cryptographic security. |
| 18 | Specimen acquisition, permanent opportunity loss, project/workshop capacity, access, committed inputs and low-value inventory/storage pressure. |
| 19 | Scale from design sophistication, tooling/setup effort, process work units and facility burden—not visible UI field count. |
| 20 | Only the design grammar creates dimensions; the UI has no “add slot.” |
| 21 | None is defined numerically today. SP has fixed authored parts; Online has no fabrication distribution. |
| 22 | Yes, as an explicit eventual outcome region, without inventing percentages now. |
| 23 | Diagnostics reveals; Repair services; Installation integrates; Fabrication makes one; Design/Manufacturing stabilises and scales. |
| 24 | Repair and Installation should not use reconstruction signatures. Ordinary inspection may reveal them but should not look like fabrication. |
| 25 | Shared: competency ceilings, design knowledge, committed operations, bounded uncertainty, server authority, attributed outcomes and practice-on-completion. Different domain functions remain. |
| 26 | Literal long seeds, character fragments, one field per stat, automatic design creation per prototype and early partial-code pooling are overengineered. |
| 27 | Validation oracles, offline generator clones, cancellation rerolls, alt capacity, resale-funded attempts, public token databases and result leakage. |
| 28 | No fundamental architecture conflict. Open conflicts are fabrication failure versus “poor part exists,” effect-labelled ceremony versus unlabeled process preference, and the absent physical effect carrier. |
| 29 | Discrete server-owned knowledge facts plus an optional shareable opaque dossier/token preserve the experience with less machinery than fragmented hexadecimal strings. |
| 30 | Now after approval: competency/inspection, lineage/design history, components/custody/exposure and one project path. Later: autonomous R&D, partial tokens, manufacturing scale, complex UI and public history. |

---

## 20. Poking holes in the complete proposal

### What players will automate

- submitting candidate codes if any endpoint accepts them cheaply;
- recording every public code and resolved outcome in a community database;
- optimizing money-per-attempt and time-per-slot;
- parallelizing across accounts/workshops;
- dumping low-quality output into any market that buys indiscriminately;
- comparing diagnostic outputs to infer hidden mappings.

Automation is not prevented by hiding percentages. The model must remain sound when players document it.

### What does not scale

- one database row per visible character in a giant signature;
- one process dimension per possible stat;
- creating a new design revision for every failed prototype;
- sending complete process truth to every client that can view a product card;
- synchronous ancestry traversal without cycle/index discipline;
- updating every historical component when generator code changes;
- per-kilometre rolls or per-instance unrelated design genomes for mass-produced stock.

### What undermines the economy

- refundable cancellation after a result can be inferred;
- unlimited concurrent projects;
- guaranteed resale near or above marginal cost;
- free starter money/capacity multiplied by alts;
- process knowledge that automatically removes all execution waste;
- exceptional positives that are common enough for brute-force fabrication to dominate OEM supply;
- a Base Market that absorbs or sells every component.

### What is elegant conceptually but ugly technically

- partially revealed hex strings: evocative, but they create fragment indexing, correctness-oracle and versioning
  problems while teaching players that adjacency matters;
- one cryptographic code per characteristic: clean diagram, but tends to expose stat-labelled optimization and
  ignores correlations;
- perfect deterministic recomputation forever: elegant until resolver versions change; store the historical
  result too;
- a universal project table for every operation: accepted only for project-regime work; bench repair and social
  service must remain immediate;
- one shared roll formula for all five lanes: aesthetically tidy and semantically false.

### The simplest mechanism that preserves the desired experience

Start with:

- one known/unknown **base design** fact;
- a small design-owned set of opaque **process facts**;
- complete facts represented by random shareable tokens;
- partial state represented as accumulated evidence, not token substrings;
- unresolved facts sampled normally on project commit;
- money + time + one capacity limit;
- poor/neutral/detrimental results as persistent assets;
- Diagnostics required to understand the result;
- explicit later promotion of an exceptional prototype into a derived design.

That is enough to produce technological archaeology without constructing a cryptographic puzzle game.

---

## 21. Final recommendation

Adopt the principles, not the illustrative strings:

- **knowledge progressively turns uncertainty into control**;
- **skill improves execution; knowledge supplies missing design facts**;
- **unknown is an ordinary draw, never an almost-correct interpolation**;
- **complexity is generated by the design and creates burden as well as opportunity**;
- **a lucky asset can precede understanding**;
- **functional reproduction never rewrites provenance**;
- **history survives extinction**;
- **money + time + capacity are the first economic abstraction, not the security boundary**;
- **player-facing tokens refer to knowledge; they are not generator seeds**;
- **the five lanes share principles, not one minigame**.

The machinery can tell the desired story. The implementation should begin only after the nine rulings in
section 18, and it should begin with the accepted substrate and physical history—not the code-entry ceremony.
