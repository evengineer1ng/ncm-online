# 44 - The Paddock: Night City's living NPC motorsport world

> **STATUS: CURRENT** - authority for: *the NPC motorsport world (the Paddock)* - adopted 2026-09-29 (L225). Design authority for the build on the development server; **phases 1-2 and 4-5 are built and running on dev (L226, L227); phase 3 is skipped by owner ruling (L227)**. The Pace DLL (§15) is built as `ncm/pace` 0.1.0; P-PACE-2 stays open until its first live race.
> Authority map: [INDEX.md](INDEX.md). Governing decisions: L222, L223, L224, L225, L226, L227. Parent vision: [the PvE simulation stack](../research/open77/NCM_PVE_WORLD_VISION_AND_SIM_REVIEW.md) (PROPOSAL).

## 1. What the Paddock is

The Paddock is the **heartbeat** of NCM's PvE life sim (L222): a persistent world of NPC racing organizations, drivers, owners, principals, staff and sponsors. It races on its own calendar, keeps its own standings, makes its own news, hires and fires, grows and ages, whether or not any human is online. A solo player lives beside it. They can read it, bet on it through Billie, manage a team inside it, and later meet its people in the city's garages.

It descends from the owner's *From the Backmarker* (FTB1) management sim (`D:/dev/Radio-OS/plugins/ftb_game.py`, 35,634 lines) and its name and sponsor generators. Those are reimplemented as pure `ncm/core` Lua. The owner has granted verbatim reuse of their own code and data (L224); the Python originals serve as test oracles (L221).

**Design constraint (L223 addendum).** The dev server's population is the owner plus `ncmtester2`. The Paddock is judged by whether it makes a good world **for one player plus one test account**. Every rule that needs a crowd of humans to work (calibration minimums, market depth, human-managed rivals) has to degrade gracefully to two.

## 2. Governing decisions

| Decision | What it fixes here |
|---|---|
| **L224.1** | **Parallel circuit.** NPC organizations and series never share a grid, standing or result with humans. It will be reconsidered only when good NPC racing data and human data both exist. Amends L165, L177, doc 14's "NPC employees · AI Drivers" DO-NOT-BUILD line, and IDEA-158 |
| **L224.2** | Full scale: 4 tiers, ~60 organizations, ~150 drivers |
| **L224.3** | **Daily rhythm**: street racing at night, sanctioned racing by day, on US Eastern real time (§5) |
| **L224.4** | Billie takes positions on NPC races; amends L172 and doc 40's gambling non-goal (§9) |
| **L224.5** | Build order: sim-only season → display-only sightings → physical-authoritative races (§13) |
| **L224.6** | Paddock people get physical bodies; **garages are rented, shared workplaces** (§11) |
| **L224.7** | The owner's own FTB code and data may be reused verbatim |
| **L224.8** | One-Team Rule: a manager may not manage a second team. Street activity is free for everyone |
| **L224.9** | No hardcoded cap on how much one player can change; learn it from the sim |
| **L222** | Provenance is `physical` / `simulated` / `reported` and one never pretends to be another. Physical facts write back only from an explicit physical-authoritative activity that NCM corroborates. Weather is world state, never manufactured. Narrative has zero handling authority |
| **L223** | All Paddock work happens on the **development server**; Online stays frozen at Baseline 1 |
| **L69** | Nothing is done until a live PASS sits beside it in `wp/MASTER_TEST.md` §CH |

## 3. Reconciliation with the attached plan

The owner's plan (`C:/Users/eveng/.codex/attachments/5eddbe7c-1378-42f4-a779-fc98733fa5bd/Pasted text.txt`) is the source of this document. It reserved L210–L214, which were never written (L215 held them); **L225 releases them**, and its decisions are recorded in L224 instead. Where later rulings changed the plan, this document follows the rulings:

| Plan said | Now | Why |
|---|---|---|
| Rounds every 20–30 min per series, staggered, around the clock | Daily rhythm by tier, on Eastern time (§5) | L224.3 |
| "Physical outcomes never write back" | Projection mode never writes back; physical-authoritative mode does, when corroborated (§12) | L222 |
| Sightings are the end state of physical presence | Sightings are phase 3; bodies at garages and physical races follow (§13) | L224.5, L224.6 |
| Calibrate from human medians (min 8 samples, min 3 drivers) | Same, **plus** a declared seeded baseline that runs indefinitely at two humans (§7) | L223 addendum |
| Placing a slip requires having met Billie | Unchanged, and it makes **authoring Billie** part of phase 2: she is declared but unspeakable today (`graph.contacts`) | `contacts.lua` |
| Deploy and live-test on Windows dev, then Lightsail | **Dev only** until the freeze is thawed | L223 |
| KB-212 next free | KB-212 is now the SP Foreman phone lag; the Paddock takes KB numbers as they come | ledger |

Facts the plan listed as verified were re-checked against Baseline 1 (`online-baseline-1`) on 2026-09-29, and all hold:
- The next migration is **043**.
- `session_result` and `ledger` have foreign keys to `ncm_driver`, so NPC results need their own tables.
- `NcmEconomy.withBalanceLocks` exists.
- `ghost_lap.poses_json` exists.
- `SHELL_TABS` in `panel.html` has eight tabs.
- `Open77.tunables.declare` is per resource, and a second call replaces the first.
- `championships.lua` holds `POINTS_TABLES`.
- MASTER_TEST `§CH` is free.

## 4. The world

### 4.1 Tiers and scale (L224.2)

| Tier | Orgs | Series (first numbers) | Character | Rhythm |
|---|---|---|---|---|
| **Street** | 24 | 2 × 12 orgs | Unsanctioned, underground; the city's own scene | **Night** |
| **Regional** | 16 | 2 × 8 orgs | Sanctioned club and district racing | **Day**, into early evening |
| **Pro** | 12 | 1 × 12 orgs | Sanctioned professional series | **Day** |
| **Night City Premier** | 8 | 1 × 8 orgs | The top flight, the city's showcase | **Afternoon feature** |

About 60 organizations and 150 drivers (2–3 per org), 40 free agents, and owners, principals, managers, staff and sponsors. Promotion and relegation happen at the quarter rollover (§5.3).

### 4.2 People

Every person is a stable ID with a generated name, a nationality/region, an age and a role. The generator is the FTB name system (`ftb_names.py`, `ftb_sponsors.py`), with these changes:
- A region is picked first, weighted to Night City demographics.
- The real-driver blocks are dropped, and a `REAL_NAME_DENYLIST` is added.
- Indian, Middle Eastern and African surname regions are authored where FTB lacks them.
- Hashing is LuaJIT-safe FNV-1a.
- Names are unique, and everything is keyed by ID, never by name.

Canon Night City gangs and groups may appear (L222), but Paddock organizations themselves are invented.

### 4.3 Hidden attributes and earned tags

Drivers carry FTB1 stats: pace, consistency, racecraft, wet-weather skill, aggression, fitness and others. They also have FTB2's five-axis personality, and principals carry FTB1 principal traits. **Clients never receive a number.** What players see are **earned tags** from a closed vocabulary. A tag shows only when its stat predicate **and** its evidence predicate both hold ("Rain specialist" needs a high wet-weather skill *and* a record of wet results). Every payload is built by `paddock.projection`, which calls `assertNoHidden`.

### 4.4 Organizations and money

Each org has an owner, a principal (a personality that makes decisions), a manager, cash, sponsors and a car development level expressed in NCM Part terms. Wages, sponsorship, prize money and development spending move org cash. An org that runs dry **folds** and is replaced by a new one at the next Cup boundary. Titles, folds and retirements are kept forever.

## 5. Time: the daily rhythm (L224.3)

### 5.1 The clock

The Paddock keys to **US Eastern real time, `America/New_York`, with daylight saving** (L221/L222). The scheduler converts UTC to Eastern itself, in pure core (`world.clock.eastern(utc)`, applying the second-Sunday-of-March and first-Sunday-of-November rules). So it does not depend on the in-game clock service (IDEA-729), though both show the same hour once that service exists.

### 5.2 First schedule

These are **first numbers**, tunables with the volume computed rather than guessed:

| Tier | Window (ET) | Spacing | Races per day |
|---|---|---|---|
| Street, 2 series | 20:00–04:00 | every 40 min per series, staggered 20 min | 24 |
| Regional, 2 series | 12:00–20:00 | every 60 min per series, staggered 30 min | 16 |
| Pro | 10:00–18:00 | every 2 h | 4 |
| Premier | one feature race at 15:00 | daily | 1 |
| **Total** | | | **45 per day** |

**Multiplied by the cadence:** 45 races a day, 315 a week, about 4,100 a season. At roughly 10 entrants each that is about 41,000 result rows a season. That is modest, and it sets the pruning policy in §10. A player who plays at 9 PM lives mostly in the street scene; a lunchtime player sees sanctioned racing. That is the point (L222).

### 5.3 Weeks and seasons

- A **season is a UTC quarter** (L100) of **13 weekly Cups**. Each Cup keeps its own standings, and the season standings roll up from them.
- **Rollover:** promotion and relegation, contract expiries, retirements, and one "paddock year" of ageing.
- **Daily tick:** growth and decay run once per day. This fixes FTB1's per-tick bug.
- **Silly season:** transfers cluster at Cup boundaries and at rollover.

### 5.4 Weather

Each race reads its conditions from `NcmWeather`'s plan through `world.conditions.at(...)`: weather, road wetness, light. **The Paddock never sets weather** (L222). Rain on a street night changes the result because the sim models wet skill and wet pace, not because a story wanted rain.

## 6. The race sim

`paddock.sim` adapts FTB1's `_simulate_race_lap_by_lap` to segmented sprints over NCM's routes:
- Per-segment pace comes from the stats, the car's development level and the conditions: the wet scales with wet skill, night applies a light factor, and dirty air matters.
- Overtakes are gated by racecraft and the gap; incidents and DNFs are rolled from event-keyed randomness.
- The DNF rate is fixed at about 2.5% per race at stat 50 in the dry.
- Output: finishing order, per-segment splits and incidents, plus `SIM_VERSION`.
- Randomness is **event-keyed** (`vocabulary.hash.stream(seed, raceId)`), so a race replays identically.
- The result's seed commitment is stored **before** the race window opens. A running race never leaks its result (tested).

## 7. Calibration against human pace

Migration 043 stamps conditions on every human result: weather, road wetness, seconds of day, light, series, class and vehicle class. Calibration buckets are route × series/vehicle band × conditions, because class alone collapses: every street series is `street_open`. The base pace is the human median once a bucket has at least 8 samples from at least 3 drivers.

**At two humans that minimum will rarely be met.** So every bucket starts from a **declared seeded baseline** that is a first-class value, not a fallback that looks like an error. The baseline logs which buckets are human-calibrated, and the minimums are tunables. The sim must be good on the baseline alone; calibration refines it as data arrives.

## 8. Story: the tape, WIRE and spotlight

- **The tape.** Every consequential thing is an event: `{id, tick, kind, entities, causeRefs, effectRefs, facts, publicSummary, seed, salience, retain}`. It is the Paddock's contribution to the shared fact tape in the vision's Layer 3. Provenance is `simulated` in phases 1–3.
- **WIRE** is the F6 PADDOCK news feed. Headlines come from deterministic templates per event kind. A template is eligible only if every slot resolves from facts, and a no-repeat window of 8 applies. At full scale WIRE is busy by design, so **salience decides what surfaces**: Premier results, upsets, streaks, signings, firings, folds, retirements and title swings rank high; a mid-table street result ranks low and stays in RESULTS.
- **Pushes are rare.** At most a small daily number of Paddock items reach a player's Messages, and only when they relate to that player: a callout, their Billie slip, their org. Everything else waits in WIRE. Quest-graph §20 budgets still govern Messages.
- **Spotlight** scores human sanctioned results. It drives press mentions and NPC callouts. A callout becomes an arc plus an informational message (`actions=NULL`), resolved by the human's next *sanctioned* result.

## 9. Billie's board (L224.4)

Billie takes **win, podium and head-to-head** positions on NPC races:
- **Pricing.** Lines are priced by a Monte Carlo of the sim (1,000 runs, chunked across `Wait(0)` yields) with a 10% overround.
- **Line lifecycle.** A line is suspended and re-versioned whenever a tape event touches an entrant. Lines open at T−15 min and close when the race window opens.
- **Settlement** is idempotent, and a void race refunds.
- **Hard refusals** apply to everyone: no position on any driver of a **human-managed** org, and no manager in their own series. **Never a position on a human** (L172, unchanged).
- **Money** moves in capped eddies through the ledger: per slip, per day, and a maximum payout.
- **Access.** Everyone can read the board. Placing a slip requires a `player_contact` row with Billie, which requires **authoring Billie**. She is declared, not speakable, in `graph.contacts`, so her script and her Rico introduction ship with phase 2. Her copy is in her voice ("I take positions", "paper", no Cancel button, a refusal line for human-managed entrants).

## 10. Manager mode (L224.8)

- **Becoming a manager.** A human founds a Street org for a fee (wallet → treasury), or accepts an offer from a personality-driven NPC owner who can later fire them. A founder can't be fired, leaves if the org folds, and then waits out a one-season cooldown.
- **Controls:** roster and contracts, car development, staff and sponsors. **No per-race orders**; races stay simulated.
- **Timing.** Roster changes apply at the next Cup boundary.
- **One-Team Rule.** Managing is the human's one team affiliation, enforced by a unique database index (migration 046). Several humans may manage in the same series. **Street activity stays free** for managers.
- **Treasury.** Append-only, per org. Withdrawals are capped weekly and taxed; both are tunables.

## 11. Places and bodies: garages as rented workplaces (L224.6)

Paddock people are **persistent simulated people** who get physical bodies when it makes sense (phase 4). Organizations **rent** garages rather than owning them:
- A garage is a shared workplace rented by several teams, each on its own schedule.
- Teams mostly occupy a garage at different times of day, with some natural overlap, and stack two or three deep where garage density requires it.
- An org's **schedule** (which garage, which hours) is sim state. Where its people physically are right now follows from the Eastern clock, so a player can find a team's mechanic at the Kabuki garage on a weekday afternoon.
- The street tier's garage hours skew to the night, like its racing.

**Source of garages.** The game's own data gives 102 distinct garage, parking, workshop and Autofixer sites with X/Y/Z ([NIGHT_CITY_POI_EXTRACTION.md](../research/open77/NIGHT_CITY_POI_EXTRACTION.md), IDEA-736). A site enters the rental pool only after an in-engine check. A player's own garage use still goes through L203 and IDEA-698.

## 12. Provenance and write-back (L222)

| Mode | Where | Provenance | Writes back? |
|---|---|---|---|
| Sim-only race | Phases 1–2 | `simulated` | It *is* the result |
| Sighting | Phase 3: AI cars run the sim's splits near a player | projection | **Never.** A stalled or despawned car changes nothing |
| Physical-authoritative race | Phase 5: an explicitly declared activity | `physical` once NCM corroborates gates and timing | **Yes**, and it supersedes the sim for that race; slips already settled are never re-settled |
| Report | An NPC or a player says something happened | `reported` | Only as a report, never as a result |

## 13. Build order (L224.5)

| Phase | Delivers | Main work |
|---|---|---|
| **1. The season runs** | Genesis, the daily-rhythm calendar, sim, standings, tape, WIRE, RESULTS, DIRECTORY, calibration stamping | Core `vocabulary.hash`, `world.clock`, `world.conditions`, `paddock.{names_data,names,attributes,tags,world,season,sim,calibration,tape,news,projection}`; migrations 043, 045, 047, 048; `ncm_paddock` scheduler, races, news, views; F6 PADDOCK |
| **2. Billie and the manager** | Billie's board and slips; manager found/accept/fire; treasury; human sanctioned orgs (doc 14 schema, read-only DIRECTORY) | `paddock.{pricing,progression,contracts,finance,principal,manager,car,spotlight}`, `competition.affiliation`; migrations 044, 046, 049, 050; **Billie authored** in the quest graph |
| **3. Sightings** | **Skipped (L227)** except what 4-5 need. NPC races glimpsed in the city, display-only | `paddock.sighting`; `ncm_paddock/sightings.lua` (spawn 300–500 m upstream, ≤55 m/s, ≤64 route points from ghost poses, despawn past the player; caps per sighting and global) |
| **4. Bodies and garages** | Paddock people at rented garages on their schedules | The garage registry from IDEA-736, the rental schedule (IDEA-735), materialisation through `npcs.create`, native dialogue once IDEA-727 passes |
| **5. Physical races** | Declared physical-authoritative races that write back | The Pace DLL (§15), gate corroboration, provenance upgrade |

Later, per L222: NPCs buying parts and moving supply (IDEA-730), NCPD responding to sim actors (IDEA-731), and in-world screens as sourced projection surfaces (IDEA-732).

## 14. Architecture

```text
ncm/core (pure, deterministic, vendored)
  vocabulary.hash · world.clock · world.conditions · competition.affiliation ·
  paddock.{names_data, names, attributes, tags, world, season, sim, calibration, pricing, progression,
           contracts, finance, principal, manager, car, tape, news, spotlight, sighting, projection}
ncm_paddock (NEW server-only resource; own tunables; paddockEnabled kill switch)
  settings · schema_wait · stream (ncm:paddock) · wallet · players · store · world · scheduler · races ·
  calibration · progression · silly · news · spotlight · billie · manager · sightings · requests · views ·
  prune · admin · main
ncm_league   migrations 043–050 (+ allow-list); condition stamping in race.lua and ghost.lua
ncm_world    client/panel.lua relay + web/panel.html PADDOCK tab
ncm/pace     DLL spike (phase 5), no live wiring before then
```

- **Resources don't share memory.** `ncm_paddock` cannot call `NcmEconomy` or `NcmStream` directly. It mirrors the stream protocol and `withBalanceLocks` shape, and a lint catches cross-resource globals. `tools/ncm-stub.lua` loads every resource into one VM and would hide that mistake.
- **Tunables are declared once**, in `settings.lua`. That one call covers `serverId`, `paddockEnabled`, the rhythm windows and spacing, sighting caps, Billie caps and overround, calibration minimums, prune days, the manager fee, and the withdrawal cap and tax.
- **Quota.** OPEN//77 enforces an instruction quota per resource (`KB-211`). Pricing chunks across yields, and a performance canary holds one race's pricing under 1.5 s.
- **Payloads are windowed** (L193, IDEA-674), and the PADDOCK page gets a `guard()` and render-harness fixtures (IDEA-675).

### 14.1 Migrations (replay-safe)

| # | Content |
|---|---|
| 043 result_conditions | Condition columns on `session_result`, `practice_run`, `ghost_lap`, plus an index; stamping at every insert |
| 044 organizations | Human sanctioned orgs: `organization`, branding, ownership, `sporting_charter`, `settlement`; `entry` gains entry type, org and assigned asset |
| 045 paddock_world | `paddock_world`, `_series`, `_org`, `_person` (unique display name), `_contract` (one active per person), `_sponsor`, `_person_season` |
| 046 team_affiliation | Both circuits. The One-Team Rule as a unique index on a generated active column; the NPC circuit allows only the manager role |
| 047 paddock_racing | `paddock_race` (provenance, backend, conditions, seed commitment), `_result`, `_standing` (season, Cup), `_sighting` |
| 048 paddock_story | `paddock_event` (the tape), `_news`, `_arc`, `_spotlight`, `_cursor` |
| 049 billie | `paddock_line` (versioned), `paddock_slip` (idempotency key); ledger kinds for stake, payout and refund |
| 050 paddock_economy | `paddock_calibration`, `paddock_treasury` (append-only), `paddock_manager_offer` |

**Pruning:**

| Data | Kept |
|---|---|
| Race detail | 14 days |
| Results | Current and previous season, then summarised into `paddock_person_season` |
| Low-salience tape | 30 days |
| News | 90 days |
| Titles, folds and retirements | Forever |
| Slips, treasury and ledger | Forever, never pruned |

### 14.2 F6 PADDOCK

A ninth shell tab with sub-views **WIRE · STANDINGS · RESULTS (+PACE) · DIRECTORY · BILLIE'S BOARD · MY ORG**. Edits to `panel.html` and `panel.lua` are small and additive; re-read each file just before editing, because other sessions touch them. Only `paddock.projection` builds payloads.

## 15. Pace DLL spike (SPEC, phase 5)

`ncm/pace` is a separate RED4ext package, laid out like `ncm/vision`. It drives an AI car with the native `AIVehicleDriveToPointAutonomousCommand` through a loopback protocol: `hello` / `drive.start` / `drive.ack` / `gate` / `drive.end` / `drive.cancel`.
- **Redscript** has no `module` line (KB-182).
- **Launch safety.** It needs a hand launch before it can be a join requirement (IDEA-478). It ships as its own package and is never folded into Carrier (feedback: new features, new mods).
- **Probes.** P-PACE-1 maps an OPEN//77 vehicle ID to the game entity. P-PACE-2 checks whether a native command fights the platform's lease.
- **Physical provenance** counts only when the server corroborates the gate times.

## 16. Verification

- **Core tests** (Lua 5.4 and LuaJIT):
  - hash vectors; Eastern DST boundaries;
  - names: none denylisted, 5,000 unique, no surnames in first-name lists; world counts 24/16/12/8;
  - sim: a golden hash, a DNF rate of 1.5–3.5% over 2,000 races, a monotonic wet effect, and replay identity;
  - pricing overround within ±0.5%; refusals;
  - decay once per day; every news slot comes from facts; **projection never carries a hidden key**;
  - the daily schedule produces 45 races on a normal day and handles both DST transition days.
- **Oracle tests** (L221): for the sim and the name generator, the same seed and inputs through the Python original and the Lua port, compared within a stated tolerance.
- **Host harnesses:** genesis → schedule → price → close → resolve → settle; slip idempotency; the manager fee and withdrawal cap; the cross-resource lint; wallet lock parity; a running race never leaks; the pricing performance canary.
- **Migrations:** run twice against MariaDB 10.11.14 (replay-safe); a second active affiliation must fail.
- **Gate:** `tools/ncm-build.ps1 -Check`, then `tools/ncm-test.ps1`.
- **Live:** MASTER_TEST §CH on the **dev server** (L223), with two humans.

## 17. Open questions (closed by L226)

1. Series names: **generated**, every tier.
2. Routes: NPCs race **the same routes humans race**.
3. Head-to-head slips: **same race only**.
4. Push budget: **3 unsolicited per player per Eastern day**; solicited items exempt.

## 18. As built (phases 1-2, L226)

| Piece | Where |
|---|---|
| Pure core | `ncm/core/vocabulary/hash.lua`, `world/{clock,conditions}.lua`, `paddock/*.lua`, `competition/affiliation.lua` |
| Name data | `ncm/core/paddock/names_data.lua`, generated by `tools/paddock-names-port.py` (`--check` for drift) |
| Schema | `ncm_league/server/schema/043`-`050` |
| Runtime | `ncm/online/resources/ncm_paddock/` (server only; kill switch `paddockEnabled`; console `ncm.paddock.status`, `.resolve`, `.offer`, `.calibrate`) |
| F6 | PADDOCK tab in `ncm_world/web/panel.html`; relay in `ncm_world/client/panel.lua` |
| Billie | `graph.contacts` (authored) and `graph.opening` (`M.billie`); Rico's introduction opens her |
| Tests | `ncm/core/tests/test_paddock_*.lua`, `tools/test-paddock-host.lua` (incl. instruction metering), `tools/panel-render-check.js` (PADDOCK), `tools/test-paddock-migration.ps1` (needs `NCM_DB_ROOT`) |

Departures from the text above, all recorded in L226: every tier grids by a qualifying sim; the sprint overtake margin is 0.02-0.08 s; contracts are also tracked on the person row, with `paddock_contract` as history; a human-founded org is added to the Street division that has the fewest orgs, so its field grows by one.

## 19. As built (phases 4-5, L227)

**Owner ruling L227:** phase 3 is skipped except what phases 4-5 need, and MASTER_TEST is the 1.0 release bar rather than a gate on dev work.

| Piece | Where |
|---|---|
| Garage registry | `ncm/core/paddock/garages_data.lua`, generated by `tools/paddock-garages-port.py` from `references/world-pois/garage_sites.json` (`--check` for drift). 83 sites: garage, workshop, parking; Autofixers excluded |
| Rental and presence | `paddock.garages` (shifts by tier, assignment up to 3 deep with day/night pairing, who is present, where they stand); `ncm_paddock/server/garages.lua` (persisted rentals, the presence loop, bodies, talk, site checks) |
| Talk | `paddock.talk` (a line from public facts; first meetings are introductions); `ncm_paddock/client/presence.lua` (the `open77_interactions` prompt) |
| Live races | `paddock.live` (ghost path, checkpoints, grid, per-car speed plan, timing, corroboration, verdict); `ncm_paddock/server/live.lua` (declare, stage, go, sample, write back); `ncm_paddock/client/live.lua` (waypoint, the Pace transport) |
| NCM Pace | `ncm/pace` (DLL + `NcmPace.reds` + `NcmPaceNatives.reds`, no module); `tools/build-pace.ps1`; published to dev `requiredMods` as `ncm-pace` |
| Schema | `ncm_league/server/schema/051_paddock_live.lua` |
| Console | `ncm.paddock.garage <playerId|siteId> [good|bad]`, `ncm.paddock.live [playerId [raceId]]` |
| Tests | `ncm/core/tests/test_paddock_places.lua`, `test_paddock_live.lua`; `tools/test-paddock-host.lua` (a garage visit, three live races: physical, fallback, called off); `ncm/pace/tests/state_tests.cpp`; panel render fixtures |

**The live-race contract.** A live race is declared, never automatic. It runs in the race's own window, after the sim has sealed its result. The server's own gate times decide it. `physical` needs every classified finisher to cross every timing gate in order, at least half the field (and two cars) to finish, and, on the Pace backend, the plugin's times to agree within 1.5 s. Otherwise it is `fallback`, the sim's result stands, and `paddock_live.reason` says why. The close waits for the verdict; Billie settles once, after it.

**Departures:** sightings were not built (L227); a live grid's cars are catalogue cars by tier band, not org liveries (IDEA-745); talk is one notification line until native dialogue (IDEA-727); every extracted site starts in the rental pool and leaves it only when marked bad (the research note wanted an in-engine check first, which is IDEA-750).

## 20. Note (L305, 2026-10-04): the flag in simulated races; the human pace anchor

- **Simulated races are flagged like live ones.** After `Sim.simulate`, `paddock.mixed.flagEntrants(entrants, PaddockRaces.flagLength(route))` turns every car not home within `finishWindowSec` of the leader into `dnf/flagged`: no points, no purse, classified behind the finishers. Billie's pricing simulates the same rule.
- **The base pace is anchored on human Paddock laps.** `PaddockCalibration.humanPaddock` takes finished human results, backs out the human's car (`paddock.calibration.normaliseMs`), and takes each tier's median m/s as the stat-50 base. Attributes, car and fitted parts still spread the field via `paddock.sim`. Priority: `humanLearned` > `paceLearned` > seeds.
