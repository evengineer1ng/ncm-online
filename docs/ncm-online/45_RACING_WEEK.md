# 45 - Racing Week: the three-day reconstruction

> **STATUS: PROPOSAL** - a coder recommendation answering the owner's Racing Week spec (2026-10-03, L300). **No authority until ruled; no implementation authorised.** The owner's sixteen hard rules (§0) are SPEC: do not contradict them.
> **§0.5 and §0.6 are SUPERSEDED, and §0.1 is amended, by doc 47** (owner ruling, L309 addendum): Racing Week is seven advertised days, a run may survive past Day 3, and Day moods are the expected trajectory. The crown moves to every collapse. Since L310 the code implements doc 47 (recorded run ends, verdicts at each possible end, Moody); §N's carrier and §O's crown timing below are as amended there.
> Authority map: [INDEX.md](INDEX.md). Governing decision: L300. Ideas: IDEA-857 to IDEA-912.

The spec asked for an audit before any build, with sections A-K. This document is that return. Every claim about
existing code cites a file, and every proposal is marked as one. Nothing in the tree was changed except documentation.

---

## 0. The owner's invariants (SPEC, verbatim intent)

1. Day 1/2/3 emotional identities are fixed (Love / Conflict / Disgust). *Amended by doc 47 (L309): the expected trajectory, not fixed skins.*
2. Random conditions modify play, never the Day's identity.
3. The server shares one Day and one condition state.
4. 24 real hours = 24 game hours.
5. ~~Racing Week was advertised as seven days and ends after Day 3.~~ *Superseded by doc 47 (L309).*
6. ~~There is never a playable Day 4.~~ *Superseded by doc 47 (L309).*
7. Reputation comes only from recorded behaviour.
8. Joining late fabricates no history.
9. Fame and public sentiment are different axes.
10. A famous racer can be admired in a city that hates racers.
11. Every procedural event has provenance and explicit reset semantics.
12. Completed reconstructions stay inspectable.
13. The reset matters materially.
14. Meta-progression still permits deep and late-game play.
15. Progression is not solved by preserving everything.
16. Replayability is not solved by deleting everything.
17. NCM's simulation generates the stories, and authored content interprets them.

---

## The headline finding

**About 70% of this design already exists in NCM, under different names.** The Paddock was built as a life sim on
the same principles the spec asks for:

| Spec concept | Already in the tree | Where |
|---|---|---|
| Authoritative real-time clock, robust to downtime | Eastern real time, idempotent daily step, catches up after downtime | `core/world/clock.lua`, `ncm_paddock/server/days.lua` `PaddockDays.daily`, `ncm_paddock/server/clock.lua` (game time at rate 1.0 via NCM Clock) |
| Seeded, reproducible random roll with provenance | `Hash.stream(seed, namespace, key)`; a weighted per-season "city climate" draw; transitions written `INSERT IGNORE` with their causes | `core/life/climate.lua`, `paddock_climate_event` (053) |
| World mood that facts move | six district axes (order, grip, prosperity, cohesion, heat, scene), regimes and permanent scars | `core/life/climate.lua` |
| The player is part of the sim, hidden and multi-axis | `life.trajectory`: racer/street/wrench/broker/social + risk, buckets with an evidence floor, never sent to a client | `core/life/trajectory.lua`, `paddock_trajectory` (053) |
| Fame | Spotlight, earned only from sanctioned results, with 5%/day decay and callout arcs | `core/paddock/spotlight.lua` |
| Tag-selected dialogue with no combinatorial explosion | the voice bank: `[tags] text` lines, the truth rule (every slot must resolve from facts), `known/heard/famous` tags | `core/life/voice.lua`, `core/life/voice_bank*.lua` |
| NPC memory and earned labels | earned tags (stat + evidence), WIRE news, rivalry arcs | `core/paddock/tags.lua`, `news.lua`, `paddock_arc` (048) |
| Knowledge vs possession | "Model knowledge and asset knowledge are different things" is already a Machine Index invariant | [16_MACHINE_INDEX.md](16_MACHINE_INDEX.md), `vehicle_knowledge_evidence` (016) |
| Auditable money | an append-only `ledger` with `kind` and `ref`; settlements carry receipts | 004, `session_settlement` (035) |
| Kimiko | already an NCX team identity in the career | L18, L45 |

So Racing Week is **a lens and a reset boundary around the Paddock**, not a new simulation. The proof slice (§K) is
small because most of the parts are already there.

**What is missing:**
- **The trajectory hears almost nothing.** `PaddockDays.record` has two callers, talk and meet visits
  (`days.lua:291`, `:443`). Race results, incidents, chrome use and trades do not feed it yet.
- **There is no police/wanted signal anywhere server-side** (grep: nothing). Conduct currently has to come from
  `incident` (009: `car|object|person|...`, attributed) and `chrome_event` (041).
- **Nothing is run-scoped.** Every table keys on `server_id` alone.
- **There is no betting persistence for humans** beyond Billie's lines/slips (049).

---

## A. Architecture map

### Where RacingWeekState lives

**Recommendation: a new server resource, `ncm_week`, plus a pure core module `week.*`.** This follows the existing
split (pure deterministic core under `ncm/core/`, a thin host resource, vendored copies; see the vendoring memory).

```
ncm/core/week/clock.lua       pure: (epoch, now, dayLength) -> { runIndex, day 1..3, secondsIntoDay, phase }
ncm/core/week/conditions.lua  pure: condition table v1, roll(seed, runIndex, slot) -> resolved condition + params
ncm/core/week/character.lua   pure: run facts -> the four bands (§E)
ncm/core/week/archive.lua     pure: frozen record -> derived summaries (§H)
ncm_week/server/              state machine, DB, GlobalState publish, toasts, console commands
```

**The state is derived, not stored.** The current run and Day are a pure function of `(epoch, now)`, as
`Clock.eastern(t).dayIndex` already is. The database stores what *happened* (runs opened and closed, conditions
rolled, records frozen) and never "what day it is". That single choice makes most of §J trivial.

Published to clients through one read-only `GlobalState` key (`ncm.week`: run id, day, phase, active condition ids
with their expiry). It carries no player data. That matches the state-bag audience rules in doc 29.

### Which systems need Day or condition awareness

| System | Needs | How |
|---|---|---|
| `ncm_paddock` days/climate | Day as an input; reset at collapse (§D, Decision W-1) | Day lean on `heat`/`order` (Day 3 crackdown), similar to the season's `CITY_CLIMATES` lean |
| Voice bank / news / talk | Day + player bands as tags | new tags (§F); the truth rule is unchanged |
| Settlement (purses, fees) | condition multipliers | the receipt cites the condition id (`receipt_json`) |
| Markets / components | condition inventory | run-bound rows (§G) |
| Weather | conditions may request a front | `weather_plan` already plans |
| Chrome (Open77.hacking) | condition toggles | the server-authoritative gate already exists |
| Spotlight | run-scoped | reset or re-key at collapse |
| Broadcast / HUD | Day banner, condition toasts | client reads `ncm.week` |

### Which can stay untouched

The race engine and session kernel, Pace, restream, grid, flags and classification, incidents scoring, fuel physics,
wear physics, the Exchange mechanics, Carrier, Rig Bridge and Vision. They don't need to know what Day it is. They
only see different inputs (a fee, a part on a shelf, a car in a garage).

---

## B. Existing persistence map

All of the following is keyed by `server_id`, and nothing is run-scoped today.

| Domain | Tables | Nature |
|---|---|---|
| Identity | `ncm_driver`, `ncm_driver_binding`, `driver_profile`, `driver_presentation` | who you are |
| Licence and rating | `driver_licence`, `driver_rating`, `driver_sr`, `accomplishment` | earned standing |
| Money | `ledger` (append-only, kind/ref), `economy_balance_lock`, `session_settlement` | balance = sum |
| Cars | `vehicle_asset` (`acquired_via` grant/progression/prize/purchase/seed), `vehicle_asset_transfer`, `owned_vehicle`, `issued_vehicle`, `machine_fuel`, `production_sequence` | physical instances |
| Parts | `component_asset`, `component_asset_transfer`, `machine_configuration*`, `component_service`, `component_operation` | physical instances |
| R&D | `component_rnd_state/run`, `research_submission`, `component_design` | design knowledge plus capacity |
| Machine Index | `vehicle_discovery`, `vehicle_knowledge_evidence`, `vehicle_catalogue_*` | **player knowledge** |
| Markets | `market`, `market_inventory`, `market_supply_state`, `market_production_run`, `player_market_knowledge` | world stock plus player knowledge |
| Teams | `organization*`, `sporting_charter`, `team`, `seat`, `team_car`, `team_affiliation` | identity plus resources |
| Races | `event`, `entry`, `session`, `session_result`, `incident`, `ghost_lap`, `telemetry_chunk` | history |
| Contacts and story | `player_contact`, `player_behaviour_counter`, `player_graph_budget`, `message`, `lead`, `player_message_exposure` | relationships plus knowledge |
| Chrome | `chrome_event` | history |
| Weather | `weather_plan/transition/observation` | world |
| The Paddock (NPC world) | `paddock_world` (one **seed**), series, org, person, contract, sponsor, races, results, standings, news, arcs, spotlight, Billie's lines/slips, treasury, live, climate, trajectory, NPC money/cars/garage, exchange posts | the whole NPC world |

---

## C. Reset-boundary proposal

Classes: **RUN** (dies at collapse), **META** (persists), **ARCHIVE** (frozen into the record, then immutable),
**UNDECIDED** (needs a ruling). Nothing is deleted under any class: a reset is a new key or a compensating ledger
entry, never a `DELETE`. This keeps IDEA-194 (consequential state retains its facts).

| State | Class | Note |
|---|---|---|
| Identity, presentation, Driver Card | META | |
| Machine Index (discovery + evidence) | META | the Outer Wilds layer (§D-1) |
| Market knowledge, leads (closed), contacts *known* | META | knowing Rico survives; Rico's mood does not |
| Accomplishments, ghost laps, records | META + ARCHIVE | history is history |
| Licence tier, rating, SR | **UNDECIDED** (W-3) | the strongest candidate for "unlock rights persist" |
| Wallet (ledger balance) | RUN | one `reconstruction_collapse` ledger entry zeroes it. **This also kills condition boons by construction** (rule 11) |
| Cars and parts in your possession | RUN, except anchored (§D-2) | |
| Fuel, wear state | RUN (follows the car) | an anchored car keeps its wear: that's its biography |
| Spotlight (fame) | RUN | resets; the peak is archived |
| Trajectory (style) | split: lifetime META, run copy RUN | lifetime is "who you tend to be"; the run copy is "who you were this week" |
| Behaviour counters, graph budget | RUN | |
| Contact relationship state (warmth, threads) | RUN | Majora's Mask: they forget you; you remember them |
| Team identity (name, branding, charter, history) | META | §D-3 |
| Team finances, hires, contracts | RUN | |
| The Paddock NPC world | **UNDECIDED** (W-1) | the biggest call; see below |
| Chrome events, incidents, results | ARCHIVE | |
| Conditions | ARCHIVE | with provenance |
| Weather plan | RUN | conditions may perturb it |
| Markets' world stock and supply state | RUN (back to the run's genesis) | otherwise boons leak through stock |

### W-1, the biggest decision: does the NPC world reset?

The Paddock was built for long horizons. Seasons are UTC quarters (L100) with 13 weekly Cups; contracts span
seasons; orgs fold after `red_days`; climate scars are permanent; L298 just made NPC money and cars circulate. **A
72-hour reset breaks every one of those time constants.** Two coherent answers:

- **W-1a, the historical cast replays (recommended).** `paddock_world.seed` becomes the *historical* seed and is
  the same every reconstruction: the same 60 orgs, the same drivers, the same opening standings, the same Day 1.
  That's Majora's Mask: the same Clock Town every cycle. Divergence comes only from conditions and humans.
  Implementation: the Paddock's partition key becomes `<server>#R<n>` instead of `server_id`. One seam
  (`PaddockUtil.sid()`) plus the paddock tables that join player ids. Old reconstructions stay queryable under
  their own key for free, which also satisfies §11. Racing Week's championship becomes **the Cup that was never
  decided**: three days of a seven-day Cup, and the standings at collapse are its only result.
  *Cost:* NPC careers, contracts across seasons, folds and the scar mechanic only live inside 72 hours, so
  most of their long-horizon tuning goes dormant. Genesis is metered (KB-211), so the next run's world must be
  built under its new key **during Day 3**, then swapped atomically at collapse.
- **W-1b, the world persists and only players reset.** Cheaper and preserves L298. But Day 1 isn't the same
  Day 1 twice, and "same three historical days" weakens to a costume.

Recommendation: W-1a, built so W-1b stays available behind one setting.

---

## D. Meta-progression proposals

The owner's two references already describe two of the three models: **Outer Wilds** (only knowledge survives) and
**Majora's Mask** (the Song of Time keeps masks, songs and the bank; loses rupees, ammo and keys).

### D-1. "The Index remembers" (Outer Wilds: knowledge is the only inventory)

**Persists:** Machine Index (every model ever identified and the knowledge depth on it), market knowledge (where the
shops are, what they stock, when production runs), contacts *known*, leads, R&D *designs known* (not stock), licence
tier, records.
**Resets:** everything physical, and money.
**Late game:** a veteran starts Day 1 broke but knows exactly where the under-priced Sport-class seller is, which
fixer has prototype parts, and which route pays. Knowledge turns into capital quickly. Premier access comes from
licence + knowledge + a run's earnings.
**Exploits:** knowledge is wiki-able. IDEA-440 (the solved-wiki invariant: public knowledge removes ignorance but
grants no competency or capital) already guards this. Knowing a market exists is not the same as having
`player_market_knowledge` access to it.
**Economy:** the cleanest. No meta-money exists, so boons cannot leak.
**Risk:** 72 hours may be too short to rebuild to Premier every run, so late game becomes an every-run grind.

### D-2. Anchors (Majora's Mask: the Song of Time and the Clock Town bank)

**Persists:** D-1, plus **N anchored assets** (start N = 1), chosen at collapse. An anchored car keeps its
`asset_id`, odometer, wear, fitted parts and provenance, so it carries its whole biography (17_MACHINE_PROFILE).
Optionally a **bank** with a cap, depositable only from earned ledger kinds.
**The anti-exploit rule (recommended): the reconstruction only remembers what it witnessed.** A car is anchored *as
configured at the last sanctioned race it finished*. Parts fitted after that race are not anchored. This closes
the "convert all cash into parts at 05:59 on Day 3" exploit, and it reuses provenance NCM already records
(`machine_configuration` revisions + `session_result`).
**Boon cars:** ineligible by default (`acquired_via = 'grant'` + condition ref). The owner's "I saved that Galena
somehow" story suggests one exception worth considering: a boon car becomes anchor-eligible if it *won a sanctioned
race* during the run. It's earned, it's rare, it's bounded by N, and it makes the story real (W-4).
**Late game:** N grows with archived achievements (e.g. N=2 after a championship lead at collapse, N=3 after
Premier). A veteran walks into Day 1 with one real car and no money.
**Economy:** anchored value sits outside the run economy. Bounded by N and by the witnessed-configuration rule.
**Emotion:** the strongest of the three. The collapse ceremony becomes a choice: *which car do you save?*

### D-3. The team outlives the week (identity persists, resources reset)

**Persists:** D-1, plus your organization's identity: name, branding, charter, history and an archived **prestige**
across reconstructions.
**Resets:** team cash, hires, contracts, cars.
**Each run:** the team opens with a charter stipend scaled by persisted prestige, and the NPC talent pool (the
historical cast) is re-signed each run.
**Late game:** Premier grid access gated by team prestige (doc 14 grid slots), earned across many weeks. This is the
slow, deep axis that takes longer than one reconstruction.
**Exploit:** a stipend is money that persists in disguise. Cap it, and make it run-bound (it dies at collapse
like any wallet).

### D-4. Hybrid (recommended for ruling)

**D-1 always + D-2 with N = 1 to 3 + D-3 for team owners.** Each covers a different player:
- The explorer keeps what they learned.
- The driver keeps one car with a story.
- The owner keeps a name that means something.

No meta-money exists anywhere. That's what keeps rule 13 (the reset matters) and rule 11 (boons die) true at the
same time.

---

## E. Player-character model: four bands, not a spreadsheet

All four are derived from recorded facts, kept run-scoped, and sent to no client as numbers (the trajectory rule).
Each is a small set of bands, so dialogue can tag on them.

| Band | Values | Fed by (existing source) |
|---|---|---|
| **Renown** | `unknown`, `noticed`, `known`, `famous` | Spotlight (existing thresholds 10 / 25), plus street-race wins (new feed) |
| **Conduct** | `clean`, `rough`, `menace` | `incident` attributed `self`/`both` (kinds `person` and `car`), `chrome_event` as attacker; police once a signal exists (gap) |
| **Standing** | `none`, `contender`, `winner`, `leader` | `session_result` + Paddock standings for this run |
| **Style** | the trajectory bucket (charger, tactician, wildfire, engineer, dealer...) | `life.trajectory`, run copy, **after wiring the missing feeds** |

**Facts, not dimensions:** rival NPCs (top contact or encounter counts this run), the signature car (most raced), first
seen Day (`arrival: day1|day2|day3`), returning (has archived runs). These become slot facts and tags, not axes.

Four bands × three to five values is about 200 combinations. No line is written for a combination: lines are written
for one or two tags, and the selector (§F) combines them.

**Order of work:** wire the existing trajectory feeds (race finish/win/DNF, dirty drive, chrome, trade) first. That's
also useful before Racing Week exists.

---

## F. Reaction and dialogue architecture

**Extend the voice bank. Don't build a second system.** It already has the shape the spec asks for: tagged lines, a
truth rule, deterministic per-meeting selection and stable line ids. The additions:

1. **Day tags:** `day1 day2 day3`. Untagged lines stay valid on every Day.
2. **Player tags:** `renown_* conduct_* standing_* style_* arrival_* returning`.
3. **Speaker classes** with a **stance** toward Day. This is how disagreement comes out without an omniscient
   narrator:

| Speaker | Day sensitivity | Player sensitivity |
|---|---|---|
| Race Control | none (procedural on every Day) | standing, conduct (penalties) |
| Sponsor / commercial | none (relentlessly positive) | renown |
| Municipal PA | strong (welcome, then advisories, then curfew) | none |
| NCPD | escalating | conduct |
| Media / WIRE | moderate | renown, standing |
| Crowd / civilian | strong (follows the Day) | renown, conduct |
| Fan | weak | renown overrides the Day |
| Contacts (Dex, Rico, Billie...) | moderate, through their own voice | everything |

4. **Selection = filter, then specificity.** Filter: the line's tags must all hold (the existing rule). Score: prefer
   the line matching the most tags, with a per-line cooldown. Writers then cover the space bottom-up: a generic
   `day3` crowd line exists, a `day3 renown_famous` line beats it, and a `day3 renown_famous conduct_clean` line
   beats both. This is the Valve response-rules model (Ruskin, GDC 2012). It scales by *adding* lines, never by
   filling a matrix.
5. **Audio is keyed by line id** (`<move>#<n>`, already stable). Only lines with no slots, or with closed-vocabulary
   slots, get recorded. Slotted lines stay text. That decides which lines are VO candidates without a second
   catalogue.

The spec's Day-3 example becomes a single line:
`[crowd day3 renown_famous arrival_day3] Great. Another racer. And apparently this one's terrifyingly good.`

---

## G. Procedural-condition architecture

### Cadence: two slots a Day, six conditions a run

- **Dawn slot (06:00 ET):** changes the Day's economy.
- **Dusk slot (18:00 ET):** changes the street night.

These line up with the existing rhythm: sanctioned racing by day, street racing from 18:00 (L224.3).
Conditions last until the next slot by default. A few run-scoped ones last until collapse.

### The roll, deterministic and auditable

```
seed      = Hash.key(historicalSeed, "week", runIndex, slot)      -- slot = 1..6
condition = weighted(TABLE_v<n>, filtered by day + exclusions + already-rolled-this-run)
params    = Hash.stream(seed, condition.id)                        -- amounts, which car, which market
row       = racing_week_condition(run_id, slot) PRIMARY KEY        -- INSERT IGNORE: a second roll is a no-op
```

Stored per row: run id, Day, slot, table version, seed, roll value, condition id, params JSON, `activates_at`,
`expires_at`, `reset` semantics, and what it actually touched (refs). Because the roll is pure, re-rolling after a
crash gives the same answer, and the PK makes it impossible to record two.

### Reset semantics (each condition declares one or more)

| Semantics | Meaning |
|---|---|
| `expire` | a rule change that simply stops |
| `run_bound` | anything granted dies at collapse (assets carry the condition ref) |
| `knowledge_persists` | the Machine Index entry or market knowledge it caused survives |
| `anchor_ineligible` / `anchor_if_won` | per D-2 |
| `no_meta` | never contributes to meta-progression |

### Concrete conditions against systems that exist today

| Condition | System it perturbs | Reset |
|---|---|---|
| **Purse surge** ×1.5 sanctioned purses | settlement (`session_settlement`, receipt cites the condition) | `expire`; the money is run-bound via the wallet |
| **Fees waived** | Economy v1 entry fees | `expire` |
| **Prototype rubber**: a component design appears at one market | `component_market_inventory`, `component_design` | `run_bound`, `knowledge_persists` (the design is now *known*) |
| **The weird car**: every driver is granted one specific model | `vehicle_asset` `acquired_via='grant'` + condition ref | `run_bound`, `knowledge_persists`, `anchor_if_won` |
| **Dry pumps**: fuel price ×3 in two districts | `fuel` + `fuel_locations` | `expire` |
| **Chrome spread**: hacks enabled at a higher tier | chrome gate (Open77.hacking) | `expire` |
| **Front coming in**: forced rain through the night | `weather_plan` | `expire` |
| **Long odds**: Billie offers boosted lines on underdogs | `paddock_line` | `expire`; slips settle normally |
| **Fire sale**: one market dumps stock | `market_supply_state` | `expire`; bought cars are `run_bound` like all cars |
| **Kimiko anomaly** (cosmetic: ghosts of a previous reconstruction's best lap appear) | `ghost_lap` from the **archive** | `expire`; the first condition that reaches *between* runs |

**Not backed by any system yet, so not proposed for v1:** pink slips, insurance, crowd size.
That respects the spec's "no fake simulation".

### Day weighting

The table filters by Day without changing its identity. Windfalls are more likely on Day 1, scarcity and chrome
on Day 2, police pressure and fee hikes on Day 3. A Day-1 condition can still be harsh ("dry pumps on Day 1"), but
it never reads as anger.

---

## H. End-of-reconstruction schema

### Frozen per player (only those who appeared this run)

```
identity, first_seen {day, at}, last_seen
sporting   starts, wins, podiums, dnfs, best {race_id, pos, field}, cup position at collapse, penalties s
economic   earned (by kind), spent (by kind), peak wallet, cars acquired (by acquired_via), parts fitted, bets net
social     renown {start, peak, end, per-day}, contacts met, rivals [top 3 {person_id, encounters, h2h}]
conduct    band, incidents by kind (self-attributed), civilian contacts, chrome {used, received}
machine    signature car {asset_id, km}, km total, cars destroyed/scrapped, anchored [asset_id + witnessed config]
moments    top 5 salience-ranked facts (first win, biggest upset, worst incident, a condition-driven first...)
```

### Frozen per world

```
run id, historical seed, epoch, opened/closed (planned and actual), closure {clean | late | unwitnessed}
conditions[]  (full provenance rows)
cup           standings at collapse per series (the Cup that was never decided)
paddock       top 10 WIRE stories by salience, climate transitions + scars, folds, arcs resolved
population    humans seen, per-Day peak online, races run (physical vs sim, provenance kept)
```

### The two questions, kept separate

- **"Who were you?"** = style × conduct × renown arc × standing, plus the signature car and the top rival. It renders
  through the truth rule into an epithet: *"A clean charger who arrived on Day 2 and left famous. Lost three times to
  Okonkwo."* Template-filled from facts, never authored per player.
- **"What kind of Racing Week was this?"** = the conditions plus the world's top facts. The run is auto-titled by its
  highest-salience condition, so it can be named in conversation: *"Reconstruction 017: the Galena Week."*

**Storage:** one `racing_week_archive` row per run (world JSON) + one `racing_week_record` per player per run. Both are
written in one transaction before any reset (§J). Ribbon OS later reads only these, so the graphics never need live
tables.

---

## I. Join-in-progress walkthroughs

| Joins | Brand-new player | Returning player (D-4 hybrid) |
|---|---|---|
| **Day 1 morning** | renown `unknown`, arrival `day1`. The city is excited and the dawn condition is active. Sanctioned regional races run every 15 minutes, and the issued car / first car path works unchanged. | Same, but they know markets and cars (Index), have their anchored car in the garage and a team name with a stipend. Their contacts don't know them: "Have we met? You've got that look." |
| **Day 2 afternoon** | `arrival_day2`, no history. The Day-2 conflict lines fire generically, not at them. Four conditions may already have come and gone. They inherit the world's *state* (empty fire-sale shelves) but not its boons (the Day-1 grant car went only to drivers present). | Same choice, plus the knowledge to act fast. A Day-2 veteran start is the speedrun case: one day to make a mark. |
| **Day 3 evening** | `arrival_day3`. One big win produces "who the hell is this?" in Day-3 colour. Renown can still reach `famous`: thresholds are absolute, not per-Day. They get archived too: a one-evening record is a real record. | The interesting case: a known name arriving into a hostile city. Archived history (`returning`) can unlock contact lines ("Last week you...") even while this run's renown is zero. That's the Kimiko déjà vu. |

Rule 8 holds by construction: run counters start at zero and only facts move them. Should late joiners receive
missed boons? **No:** condition grants are given to drivers *present* when they fire (W-5). Presence is part of the story.

---

## J. Failure and recovery

The state is derived from `(epoch, now)`, so "what day is it" can never be wrong after a restart. What can go wrong
is the *transitions*, so each transition is an idempotent, keyed step, as in `PaddockDays.daily`.

| Failure | Behaviour |
|---|---|
| **Server restart / crash** | On boot: compute the expected run and slot. The DB's latest open run and rolled slots say what happened. Missing slots are rolled (same seed, same result); `INSERT IGNORE` means a double roll is impossible. |
| **Missed rollover (down across Day 3's end)** | Boot finds run *n* still open but the clock in *n+1*. It runs the collapse late (`closure = 'late'`, ceremony replayed on each player's next login), then opens *n+1* in its correct Day. Players never see a Day 4. |
| **Down longer than 72 h** | Skipped runs are archived as `unwitnessed` (no simulation is invented; zero players), so the run index stays truthful. |
| **Duplicate roll / duplicate collapse** | PKs on `(run_id, slot)` and `(run_id)`; the collapse is a state machine `open -> closing -> archived`, and every step checks state first. |
| **DB failure mid-collapse** | Freeze (archive + records) is one transaction. Resets happen only after it commits, and they are additive (a compensating ledger entry, a new Paddock key) so they replay safely. |
| **Archive keeps failing** | The run stays in `closing`. The world holds in a **"Day 4" static screen**: racing paused, a Ribbon-style "reconstruction failed to terminate" overlay, retries with backoff, operator alert. The failure mode is diegetic, and it never silently resets without a record. |
| **Rollback** | Mandatory DB backup (existing OPS backup) before each collapse. Since collapse never deletes, reverting a bad collapse means pointing the active key back plus a reversing ledger entry. |
| **Clock skew** | Server UTC only; clients never decide. |

**Boundary choice (W-2):** Day boundaries at **06:00 ET, not midnight**. The street night runs 18:00 to 06:00
across midnight (`season.lua`: "untilSec may pass 86400"), so midnight would cut a night in half. Day 3 then ends
at dawn: *the sun comes up on a Day 4 that never arrives.* Collapse at 06:00 ET means most US players are asleep and
Europe is at midday. **The ceremony must therefore work both live and replayed on first login after.**

**Cadence aliasing (multiply by the cadence):** a 72-hour cycle against a 7-day week means a player who plays only
every third day (e.g. Mon/Thu/Sun) **always sees the same Day**. Daily and weekly players rotate. Acceptable, but
worth knowing: it means the Day-of-first-join distribution is not uniform for habitual players.

---

## K. Implementation ladder

Each rung ships alone on **dev**, with a live PASS in MASTER_TEST before the next. Online stays untouched until
the owner rules.

| Rung | What | Proves | Changes production behaviour? |
|---|---|---|---|
| **0** | `week.clock` + `week.conditions` pure modules + tests (Lua 5.4/LuaJIT). A `weekDaySeconds` tunable so dev can run a **whole reconstruction in ~3 hours** (a real 72-hour test cycle is untestable) | determinism, boundaries, catch-up maths | no |
| **1** | Migration 059 (`racing_week_run`, `racing_week_condition`); `ncm_week` resource; `GlobalState ncm.week`; `ncm.week` console; Day banner on HUD | authoritative state, restart/catch-up, one shared Day | Day banner only |
| **2** | One condition end to end: **Purse surge** (settlement only), toast to all, receipt cites it, expires | provenance + expiry against a real system | yes, purses, behind a setting |
| **3** | Wire the trajectory's missing feeds + `racing_week_player` run counters → the four bands, console-readable | the character model from real facts | no (hidden) |
| **4** | Collapse: freeze archive + records → reset **Spotlight only** → open the next run | archive-before-reset, the state machine, late collapse | Spotlight resets |
| **5** | ~20 voice lines tagged `day*` / `renown_*` for two speaker classes (crowd, PA) | Day × player reactions with no explosion | dialogue only |

**What waits for rulings:** wallet/car resets, anchors, team stipends, Paddock re-keying (W-1) and Ribbon OS
presentation. Rung 4 deliberately resets only something cheap and non-economic, so the whole machine is proven
before anything valuable is put through it.

---

## L. Site population: a seeded jigsaw (added 2026-10-03, research)

Owner: "how do Minecraft villages get populated ... a seed system for day one, day two, and day three ... we're
just controlling state variables ... spawning different things, because they're all tagged ... let's look through
WolvenKit." Full research: [RACING_WEEK_SITE_POPULATION.md](../research/open77/RACING_WEEK_SITE_POPULATION.md).

- **Native Communities, phases and AISpots are baked and client-local.** They're not shared, they aren't seed-controllable from the server, and they have no OPEN//77 API. Use them as **data**, not as the controller.
- **The runtime population is server NPCs + workspots + props + effects + sound.** All are replicated, and the catalogues are already tagged (npc-templates: crowd/police/vendor, faction, risk).
- **WolvenKit harvest:** 1,542 vanilla AISpots within 90 m of the 35 race nodes (`tools/harvest-site-sockets.py`, evidence `site_sockets.json`). Seven sites are rich (100+), and seven have none.
- **3,106 vanilla workspots already contain the Day palette:** cheer, flares and crowd waves; Claire's big-race argue; police observing the crowd; protest signs; trauma team.
- **Design:** socket maps (harvested + walked) × Day palettes (the "biome") × tagged pools × Day processors on props, generated purely from `hash(runSeed, day, site, layer)` with one salt per layer, materialised only near players under a body budget, and pinned to a content version for reproducibility.
- **Experiments E1-E6 owed on dev** before anything is built.

## M. Advertised speed limits (owner idea + rulings 2026-10-03, L301; v1 BUILT ON DEV, no live PASS)

Owner: "advertised speed limits for racing for everyone including npcs that modulate ... day 1: low speed limit, event
organizers thought this would be friendly ... day 2: ok we will raise the speed limit ... please stop driving
dangerously; day 3: ok we have had enough of racing, back to sane driving limits, but the racers who actually are
still racing ... are pushing harder than ever ... police response can be proportional to how far over."
Rulings: build v1 now (NPC compliance after its probe), and **race costs are Day-dependent**.

**The limits already exist in the game.** Every cooked vehicle lane has `maxSpeed`: 19,432 lanes, 1,397 km, at 10 /
15 / 17 m/s (36 / 54 / 61 km/h). `tools/gen-lane-limits.py` -> `ncm_world/server/lane_limits_data.lua` (1.14 MB,
server only). **Advertised = posted x the Day, signed to 5 km/h:**

| Day | Factor | 10 / 15 / 17 m/s lanes | In a race | Police cap |
|---|---|---|---|---|
| 1 Friendly racing | x0.75 | 25 / 40 / 45 km/h | time: a `'speed'` incident, 1 s per 150 m*s over, in 5 s steps, max 30 s | 1 |
| 2 Raised limits | x1.6 | 60 / 85 / 100 | race-control warnings | 2 |
| 3 Back to sane | x1.0 | 35 / 55 / 60 | nothing: police only | 5 |

Grace is 5 km/h. **Excess** is metre-seconds over the sign, in a rolling 60 s window. The wanted level is
excess / 150, capped by the Day. The server never learns the engine's heat, so it clears the level itself after
45 s clean. Police are local to each player's game (the `setWanted` card).

**Built (dev):**
- `core/week/clock.lua`: the derived Day. 06:00 ET boundary; convars `ncm_week_epoch`, `ncm_week_day_seconds`, `ncm_week_day_override`; console `ncm.week <0..3>`; `GlobalState.ncmWeek`.
- `core/world/speed_limits.lua`: lane lookup with overpass separation and hysteresis, the sign, accounting, wanted, race dues; tests under Lua 5.4 and LuaJIT.
- `ncm_world/server/speed.lua`: fed by the odometer's 1 Hz sample of NCM machines.
- League `ncm:speed:excess` -> `kernel.incident{kind='speed'}`, with schema 059 widening the incident kind.
- HUD sign on the race HUD page; `speeding` trajectory signal through `ncm:life:record`.

**Known v1 limits:** only NCM machines (the odometer's watchlist) are measured. The HUD sign is only re-sent when it
changes. NPC compliance is not built.

**v2 (NPC compliance, after probe E7):**
- **One axis:** `restraint` from discipline vs aggression.
- **Mood:** a race incident makes the driver angrier; a rival over the limit gives them permission to push.
- **A per-run arc:** "I quit" (drop out of Day 2/3 races) or "all in" (push harder towards Day 3).
- **Physical cars:** racer records with `useSpeedLimit` + `speedLimitSafetyMargin`. Both fields exist natively on
  every driving profile (Pace TweakDB dump); E7 measures the margin's units and sign.
- **Sim pace:** per-point posted limits added to `roadlines_data`.

## N. The 72-hour curve (owner direction 2026-10-03, L302; BUILT ON DEV, no live PASS)

Owner: "static Day 1 / Day 2 / Day 3 states are now too coarse ... a continuous 72-hour social-pressure curve ... a
baseline trajectory, then let Racing Week itself perturb it ... the social simulation consumes outcomes regardless of
who produced them." The Days stay as official chapters (**OPENING DAY / RACING CONTINUES / FINAL DAY**); underneath,
`week.curve` holds one number, the city's **tolerance**:

    tolerance(h) = clamp(carrier(h) + deviation, 0, 1),   |deviation| <= band(h)

- **Carrier:** the owner's outline as keyframes, interpolated by a monotone cubic. There's no overshoot and no step at
  midnight: hour 12 is still 0.88, not "16.7% disgusted".

  | Hour | 0 | 10 | 16 | 24 | 30 | 36 | 48 | 60 | 70 | 72 |
  |---|---|---|---|---|---|---|---|---|---|---|
  | Tolerance | .95 | .90 | .80 | .62 | .58 | .52 | .35 | .18 | .08 | 0 |

- **Live signal:** a deviation that leaks back toward the carrier at 8% per run hour and is pushed by facts. The facts
  come from every resource through `ncm:week:fact`:

  | Fact | Impulse |
  |---|---|
  | speeding (per 1,000 m·s) | −0.010 |
  | civilian contact | −0.015 |
  | wreck | −0.008 |
  | race crash | −0.003 |
  | chrome impact | −0.004 |
  | clean race | +0.004 |

  These are human or NPC alike. Harm is absolute and measured against an **expected** cost per race. That expected
  cost is measured, not guessed: dev's Paddock had 325 crash DNFs in 655 races (0.50 per race). So an NPC-only week
  tracks the carrier (a test holds it within ±0.03), and twelve reckless humans drag the city down.
- **Band** (provisional ruling, L302): ±0.12 on opening day, widening to ±0.30 by the end. Opening day can sour but
  never turn angry; a clean week ends at "fine, but go home".
- **Institutions step, crowds drift.** The organisers announce four steps, each latched once per run and recorded as
  provenance:

  | Step | Limit | Race rule | Window (h) | Fires early below |
  |---|---|---|---|---|
  | `opening` | ×0.75 | penalty | 0 | — |
  | `we_hear_you` | ×1.6 | warning | 20–30 | 0.56 |
  | `back_to_sane` | ×1.0 | police | 44–54 | 0.24 |
  | `clampdown` | ×0.8 | police | 62–68 | 0.07 |

  A week no worse than history fires each step at the end of its window. A worse one crosses early; a test holds
  that. Each announcement is broadcast to every player as a PA line.
- **Police discretion is continuous:** the wanted cap is ceil((1 − tolerance) × 5), and the bar is 150 × (0.5 + tolerance) m·s per level.
- **Server:** `ncm_world/server/week.lua` steps once a minute. The run state persists in `racing_week_run`;
  announcements and one sample per run hour are written INSERT IGNORE to `racing_week_event` (schema 060).
  `GlobalState.ncmWeek` publishes the chapter, step, limit, rule, cap and `endsIn`, but not the tolerance: players
  see consequences, not a meter.
- **Console:** `ncm.week` (status) | `hour <h>` | `day <1..3>` (pins hours 6 / 36 / 60) | `clock` | `fact <kind> <n>`.
  A pinned hour runs on a scratch state, so testing never spends the real run's announcements.
- **First boot** (log `tools/open77/server/l307-restart-20261003.stdout.log`): `RUN 1 opened at hour 16.39`,
  `ANNOUNCE opening`, `carrier 0.792 tolerance 0.792 ... cap 2`.

**Not built (presentation):**
- the end-of-run countdown and rewind: `world.setTimeScale` freeze, `effects.screen`, rewind audio via `sound.broadcast`;
- sector-by-sector withdrawal of race authorisation in the final minutes;
- the Kimiko boot line for returning players;
- curve-driven crowd composition and PA tone (the probe's palettes).

The reset behind the rewind still needs W-1 and W-4.

## O. Championships crowned at hour 72; the hall of champions (L303; BUILT ON DEV, no live PASS)

Owner: "we schedule the championship aggressively around the winners being crowned hour 72 so it matters ... a name
to remember at shut down ... etched into the fabric of the lore ... decisions you make day 1 as far as who to drive
for or with can materially shape your championship run end to end." Lore (owner): "the in lore reason for spike in
racing is money is unusually high, people are thinking its a gold mine, but its more flash craze for racing."

- **The Cup is the run.** `paddock.season` takes a run provider (`Season.setWeek`, installed by
  `ncm_paddock/server/week.lua` from the shared `week.clock.config`), so every series' standings span one
  reconstruction: Cup id `<season>-RW<nnn>`. The fifteen named leagues are the championships (Badlands Cup, MaiMai
  Cup, Night City GT, the Hypercar Championship ...). Setting `racingWeek` (default on).
- **Finales.**
  - Regular slots stop 150 min before the end.
  - Every series then runs one finale, worth **double points**, in tier order: street from −165 min, regional
    from −120, pro from −85, and the Hypercar finale at −50.
  - A finale is never an oval, because an oval can run an hour.
  - The crown waits for the run's races to resolve, at most 20 min past the end.
- **The crown** is the existing Cup-boundary title code. It now crowns humans too (by `paddock_entry`, labelled Privateer).
  - Every crown is written to `racing_week_champion` (schema 061, server-keyed, never archived) and announced to everyone.
  - It fires `ncm:week:champions`.
  - Console: `ncm.week.hall`, `ncm.week.cup` (shows the finale schedule).
- **Spec series.** `Season.SPEC.regional_b` = MaiMai (`Vehicle.v_standard2_makigai_maimai`).
  - Physical NPCs spawn the MaiMai racer clone whatever they own.
  - The sim gives every entrant the same tier-base car.
  - Humans must enter in a MaiMai (`NcmCompetition.eligibilityFor`).
- **The legend.** A new voice move, `topic_champion` (16 tagged lines), with slots {champion} {championSeries}
  {championRun}. They are filled only from past runs in the hall, so NPCs can name past champions.
- **The money craze.** `week.curve` gains a money carrier: ×1.60 at the opening, ×1.80 at hour 8 (the gold rush),
  ×1.35 at 32, ×1.00 at 56, ×0.95 at the end. It moves ±0.5 × the live signal (a reckless week scares sponsors off),
  with a floor of ×0.80.
  - Published as `ncmWeek.money`.
  - Paddock NPC purses scale by it.
  - Human payouts get one auditable `craze_bonus` ledger line above ×1.

## P. The collapse and the ending (L303; BUILT ON DEV, DRY-RUN ONLY, no live PASS)

**A reconstruction is a server-id namespace.** At the collapse, everything run-local is re-keyed from `<server>` to
`<server>#R<nnn>`. Nothing is deleted, and a finished run stays queryable under its own key.

| Moves to the archive key (RUN) | Stays on the server key (META) |
|---|---|
| every `paddock_*` table except calibration, place checks and garage checks (what the Paddock learned about the physical world) | identity, licence, rating (W-3) |
| NPC-owned cars and parts; `npc_money`; the Exchange | Machine Index, market knowledge, contacts known, designs, leads |
| every player car not anchored, its fitted parts, and the player's loose parts | history: sessions, results, incidents, ghosts, the hall of champions |
| | anchored cars (W-4), team identity |

- **Wallet:** `reconstruction_collapse` (−balance) then `reconstruction_open` (+10,000, the new-player grant), both
  idempotent ledger lines.
- **SR** halves toward 5.0.
- **NPC team affiliations** end with reason `reconstruction`.
- **Anchors** (W-4):
  - **Slots:** 1, plus 1 after finishing a race in hours 48+, plus 1 after a Premier start (max 3).
  - **Choosing:** `/ncm.anchor` lists your cars, and `/ncm.anchor <n>` toggles one.
  - **Default:** if you mark nothing, your most-raced car is kept. That default is also every existing garage's
    founding anchor (W-6).
  - **Condition grants:** a car granted by a run condition needs a sanctioned win (`anchor_if_won`).
- **W-1:** the Paddock archives its world in one transaction and restarts (`Open77.resource.restart`, permission
  `resources.control`). Genesis then replays the historical seed (`racing_week_genesis`, schema 062): the same cast,
  the same Day 1.
- **Mode** (convar `ncm_week_collapse`): **`dryrun` by default** (the full plan logged and recorded in
  `racing_week_collapse`, nothing changed), `live`, or `off`.
  - `ncm.week.collapse plan` plans the current run now, as if it had ended.
  - Validated read-only against dev's data: 1 driver, 1 car (26 races, 10 wins: the default anchor), 746 NPC cars,
    8,791 NPC parts, SR 3.54 → 4.27.
- **The ending** (`ncm_world/server/week.lua`):
  - an hour-left toast;
  - a per-second countdown through the last two minutes;
  - at 00:00, a shared near-freeze (`world.setTimeScale(0, 0.05)`, 7 s) and the most glitch-like screen effect the
    platform lists;
  - then KIMIKO: "This braindance again? Really?" to anyone with a past `reconstruction_open` entry, and a clean
    boot line to everyone else;
  - called cars reclaimed on `ncm:week:collapsed`;
  - console `ncm.week rewind` to see the beat.
- **Not built:**
  - rewind audio (needs a shipped sound);
  - the full ceremony UI (champions board, "who were you", Ribbon OS);
  - the witnessed-configuration rule for anchors (parts fitted after the car's last sanctioned finish should not be
    saved; logged as owed);
  - team stipend (human teams hold no money yet);
  - market stock reset (undecided);
  - the collapse replay for players who missed it.

## Decisions owed (for L-lines when ruled)

- **W-1** Does the NPC Paddock replay from the historical seed each run (recommended), or persist?
- **W-2** Day boundary 06:00 ET (recommended) vs midnight; collapse at dawn on day 4.
- **W-3** Do licence tier / rating / SR persist (recommended: yes, as "unlock rights")?
- **W-4** Meta model: D-4 hybrid (recommended), the starting N, and whether `anchor_if_won` exists.
- **W-5** Condition grants only to drivers present (recommended) vs everyone who joins before expiry.
- **W-6** The Online rollout: a public server's first collapse wipes wallets and cars. That needs an announcement and
  probably a one-time "founding anchor" grandfathering for existing Online garages.
- **W-7** Is the condition cadence two slots a Day (recommended) right, or one?
