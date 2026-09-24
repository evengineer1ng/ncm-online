# Offline test queue — run solo, log as you go

> **STATUS: LEDGER** - living and append-only, current by construction. Covers: *offline test queue* (L69)
> Authority map: [INDEX.md](../INDEX.md) - classified 2026-09-24 (L125)

## Starter Market foundation — completed 2026-09-23

- **PASS:** `test_markets.lua` covers stable Base identity, the exact finite allocation, no unknown-market
  placeholders/total, and independent known/access/visible/available/eligible/affordable gates.
- **PASS:** a disposable MariaDB proof applied migration 017, deduplicated starter grant and purchase, preserved
  one title/transfer, and refused a competing buyer without charging them. The scratch schema was dropped.
- **PASS:** full gate is 189/189 under Lua 5.4 and LuaJIT; 120 resource Lua files parse; 3 inline scripts and
  33 panel-render assertions pass, including populated and sold-out Market states.
- **REVIEWED, unchanged:** `KNOWN_BUGS.md`. No deployed behavior changed and KB-66 remains open until live QA.
- Live migration, contention, purchase/ownership/eligibility, reveal and recovery checks remain in §AA/§Z.

## Machine Index foundation — completed 2026-09-23

- **PASS:** `test_machine_knowledge.lua` covers model/asset distinction, accepted Market sources, no human credit
  from Market/listings, explicit epistemic vocabulary, unknown-kind refusal and bounded mandatory retry keys.
- **PASS:** full repository gate is 186/186 under Lua 5.4 and LuaJIT; 116 resource Lua files parse; 3 inline
  scripts and 28 panel-render assertions pass.
- **REVIEWED, unchanged:** `KNOWN_BUGS.md`. This pass creates no observed defect and claims no live fix.
- Live migration/backfill/retry and encounter regression checks are queued in `MASTER_TEST.md`; Scanner remains a
  probe, not a built feature.

## Walk-in orientation anchor — completed 2026-09-22

- **PASS:** `ncm_world/server/main.lua` and `client/calendar.lua` pass the resource syntax gate.
- **PASS:** full repository gate remains 181/181 under Lua 5.4 and LuaJIT, 113 resource files, 3 inline scripts,
  and 28 panel-render assertions.
- Static contract: the persistent heartbeat contains the literal `/ncm help`; all subcommand and dotted aliases
  share one `showHelp` function, so their content cannot drift independently.
- Live presentation/private-delivery checks are queued in `MASTER_TEST.md` §W.

## Season identity foundation — completed 2026-09-22

- **PASS:** `test_seasons.lua` (8 cases), Lua 5.4 and LuaJIT: four quarter transitions, year rollover, leap day,
  interior dates, strict IDs, half-open bounds and UTC midnight authority.
- **PASS:** calendar materialization now asserts the occurrence's `seasonId`.
- **PASS:** discovery window tests remain the seasonal/all-time aggregation proof.
- Full gate: **181/181**, 113 resource Lua files syntax-clean, 3 inline scripts and 28 panel assertions green.
- Live host query is queued in `MASTER_TEST.md` §V2; closure/recovery is deliberately unbuilt (§V3).

One block per check, each with its **own Result and Notes**. Write into the block, not at the bottom of the file:
a note next to the thing it is about survives; a note at the end of a document does not.

**Result** is one of: `PASS` · `FAIL` · `PARTIAL` · `BLOCKED` · `NOT RUN`.
Leave `NOT RUN` alone if you skip it. **Notes** is free text — one line or ten, whatever you saw, in your words.
Partial credit is normal and useful; "worked but felt wrong" is a real result, so write it.

Then: anything that fails goes to `KNOWN_BUGS.md`, anything that is a new idea goes to `BACKLOG.md` (next free ID
at the top of that file). **Do not stop for small defects — record and move.**

**Deployed build = deploy 13**, live 2026-09-22 16:57 UTC: deploy 12 plus Guide championship labels and starter
clothing. Boot was clean — migration 012 current, five series, no resource/script errors.

## Run order

Ordered by **outstanding work**, not by how much has been filled in. A section stays in *Run next* while any item
is `NOT RUN`, `FAIL`, `PARTIAL` or `blocked` — **a FAIL that has since been fixed still needs re-running**, so a
filled-in result is not the same as finished work. Sections where every item is `PASS` drop to *Answered*.
Nothing is ever deleted.

### Run next

| § | What | Needs | Outstanding | Passed |
|---|---|---|---|---|
| **M** | The ownership ledger (IDEA-115) | solo, Warden | 9 | 0 / 9 |
| **O** | Championships (IDEA-111) | solo, Warden | 9 | 0 / 9 |
| **C** | Host kit and scenarios (2.2 / 2.3) — needs Warden | Warden | 8 | 0 / 8 |
| **N** | Eligibility at entry (IDEA-113, L83) | solo, Warden | 8 | 0 / 8 |
| **I** | The venue option list (IDEA-095) | solo | 7 | 5 / 12 |
| **J** | Race Guide v2 (IDEA-100) — built locally, not deployed | solo, visual | 7 | 0 / 7 |
| **L** | Concurrent sessions (IDEA-112) — two clients | **two clients** | 7 | 0 / 7 |
| **D** | Never tested at all | mixed | 6 | 1 / 7 |
| **K** | Routes and the drag series (IDEA-104) | solo | 6 | 0 / 6 |
| **B** | Finish 2.1 — the Race Guide doors | solo | 5 | 0 / 5 |
| **G** | The eight settlement fixes | solo | 5 | 3 / 8 |
| **H** | Two clients — what a solo run cannot prove | **two clients** | 5 | 0 / 5 |
| **Q** | Championship labels and apparel slice 1 | solo, visual | 5 | 0 / 5 |
| **A** | Deploy 8 fixes | solo | 3 | 4 / 7 |
| **F** | System glyph tranche 1 (IDEA-080) | solo, visual | 2 | 4 / 6 |
| **P** | Guide blocker and unsolicited calendar presentation | solo | 2 | 2 / 4 |

### Answered — kept for the record

| § | What | Needs | Outstanding | Passed |
|---|---|---|---|---|
| **E** | Free-driving observations | solo | 0 | 0 / 0 |

---

# Run next

## M. The ownership ledger (IDEA-115)

New table `owned_vehicle` (migration 012) and `ncm.grant` / `ncm.garage` / `ncm.revoke`. **Nothing refuses an
entry yet** — eligibility enforcement is the next slice (IDEA-113). This section proves the ledger is real and
survives a restart, which is what that slice will stand on.

There is **no testing bypass** by design (L83): the owner's garage gets seeded with real rows, so the real check
gets exercised when it lands.

### M1 · Migration 012 applies — IDEA-115

**Do:** Watch the deploy log at boot.

**Pass:** `migrations: 1 applied` (not 0), and `applied=[… 012:ownership]`. On the *second* boot it reads `no pending migrations` again. A table that re-creates every boot is a broken migration.

**Result:** `NOT RUN`

**Notes:** 

### M2 · An empty garage is empty — IDEA-115 — the honest baseline

**Do:** Before granting anything: `ncm.garage 1` from Warden.

**Pass:** `garage driver=… : 0 vehicle(s)`. If a fresh driver already owns something, something is granting by accident — which is exactly the failure mode L83 exists to prevent.

**Result:** `NOT RUN`

**Notes:** 

### M3 · Granting a whole class works — IDEA-115

**Do:** `ncm.grant 1 Sport`, then `ncm.garage 1`.

**Pass:** Every Sport record appears. The count matches the pool's Sport list. Chat tells the player `Garage: N vehicle(s) added.`

**Result:** `NOT RUN`

**Notes:** 

### M4 · Granting is idempotent — IDEA-115

**Do:** Run `ncm.grant 1 Sport` a second time, then `ncm.garage 1`.

**Pass:** The count does **not** double. The table's primary key is (driver, server, record), so a repeat grant is a no-op — the same mistake that produced KB-38's duplicate accomplishments must not be possible here.

**Result:** `NOT RUN`

**Notes:** 

### M5 · Seed the full garage — L83 — replaces the testing bypass

**Do:** `ncm.grant 1 all`, then `ncm.garage 1`.

**Pass:** Every pool record is listed. **This is the setup step for all future eligibility testing** — with a real garage there is no bypass flag to write and no bypass to accidentally ship.

**Result:** `NOT RUN`

**Notes:** 

### M6 · A multi-class car reads honestly — the model correction found while building this

**Do:** In `ncm.garage 1`, find `Vehicle.v_standard25_thorton_colby_pickup`.

**Pass:** Its class column reads **`Muscle/Nomad`**, not one of them. A record can belong to several classes on purpose; a listing that showed one would quietly disagree with what a championship accepts.

**Result:** `NOT RUN`

**Notes:** 

### M7 · Ownership survives a restart — IDEA-115 — the point of a ledger

**Do:** After M5, restart the server (no clients connected, KB-5), then `ncm.garage 1`.

**Pass:** The same vehicles are still owned. If the list is empty after a restart, the rows are not being written and only the in-memory cache was ever working.

**Result:** `NOT RUN`

**Notes:** 

### M8 · Revoke removes exactly one — IDEA-115

**Do:** `ncm.revoke 1 Vehicle.v_standard2_makigai_maimai`, then `ncm.garage 1`.

**Pass:** The MaiMai is gone; everything else remains. Count drops by exactly one.

**Result:** `NOT RUN`

**Notes:** 

### M9 · A second driver has their own garage — IDEA-115 — ledger scoping

**Do:** With two clients: grant to one, `ncm.garage` both.

**Pass:** Garages are per driver. Granting to player 1 must not appear for player 2 — the ledger keys on `ncm_driver_id`, and getting this wrong would hand everyone the host's cars.

**Result:** `NOT RUN`

**Notes:** 

## O. Championships (IDEA-111)

Five series with independent cadences, all consuming the same route pool. The calendar is no longer "a race every
20 minutes" — it is several championships on their own clocks, deliberately overlapping.

| Championship | Cadence | Admits | Routes |
|---|---|---|---|
| NCM City Cup | 20 min | 9 entry-level road cars | 8 |
| MaiMai Cup | 30 min | 1 (the MaiMai) | 4 |
| Night City GT | 60 min | 5 high-performance | 5 |
| Hypercar Championship | 180 min | 2 Rayfields | 3 |
| Street Drag | 30 min | 26 (every street class) | 2 |

**Badlands Rallycross is deliberately absent** — it needs an off-road route and the node bank has exactly one
Badlands node; a route needs two. **NCX World Championship is absent** — it needs explicit calendar scheduling
(IDEA-114). Neither is a bug; both are in the pack header with reasons.

### O1 · Five championships start — IDEA-111 — read this at boot

**Do:** Read the deploy log.

**Pass:** Five `series <id>: every N min, M route(s), K eligible vehicle(s)` lines — city_cup 20/8/9, maimai_cup 30/4/1, night_city_gt 60/5/5, hypercar 180/3/2, street_drag 30/2/26. **No `WARNING: series … admits 0 vehicles`** — that line means a spec is broken and every entry to it will be refused.

**Result:** `NOT RUN`

**Notes:** 

### O2 · The guide is irregular, not a metronome — IDEA-111 — the actual product goal

**Do:** Open F6 and read the upcoming list. Leave it and come back over an hour.

**Pass:** Several championships with **unrelated countdowns** — something in 7 minutes, another in 24, another in 51. If everything is a neat 20 minutes apart, the cadences have not taken effect. `publishCount` may need raising to see them all (setting, default 3).

**Result:** `NOT RUN`

**Notes:** 

### O3 · Two championships can be due at once — IDEA-111 — concurrency is intended

**Do:** Watch for a time when two championships post or start close together (City Cup and MaiMai coincide every hour; drag joins them).

**Pass:** Both appear and both run. **This is not a defect** — independent cadences overlapping is the design, and §L covers whether two live races actually behave.

**Result:** `NOT RUN`

**Notes:** 

### O4 · The same route hosts different championships — IDEA-111 — routes are a shared pool

**Do:** Over a few hours, note which championship runs Ukulele.

**Pass:** Ukulele is used by City Cup, GT and Hypercar at different times. A route is a venue, not a championship's property.

**Result:** `NOT RUN`

**Notes:** 

### O5 · MaiMai Cup is genuinely one-make — IDEA-111 + IDEA-113

**Do:** With a full garage, enter a MaiMai Cup event. Then `ncm.revoke <pid> Vehicle.v_standard2_makigai_maimai` and try again.

**Pass:** First: entry allowed. Second: **refused**, `admits=1`, and `ENTER RACE` absent from the venue list. This is the sharpest test of the whole eligibility seam because the field is exactly one car.

**Result:** `NOT RUN`

**Notes:** 

### O6 · Hypercar excludes the Formula car — IDEA-111 — caught in offline verification

**Do:** Own the RB15 (`ncm.grant <pid> Vehicle.v_sport1_rb15_f1`) and **nothing else**, then try to enter Hypercar and Street Drag.

**Pass:** **Both refuse.** The RB15 is prestige 5, so a naive `prestigeMin = 5` would have admitted it to Hypercar, and a bare open spec would have admitted it to street drag. Formula is entered through NCX and nowhere else. If either accepts it, the class filters have regressed.

**Result:** `NOT RUN`

**Notes:** 

### O7 · City Cup admits what a new driver would own — IDEA-111

**Do:** Own only `Vehicle.v_standard2_thorton_galena` (prestige 1) and try City Cup, then GT.

**Pass:** City Cup: **allowed**. GT: **refused** (`prestigeMin = 3`). A starter car must never be locked out of the accessible championship — that is the one that has to work for someone with nothing.

**Result:** `NOT RUN`

**Notes:** 

### O8 · Drag stays on drag routes — IDEA-104 + IDEA-111

**Do:** Watch which routes Street Drag uses.

**Pass:** Only B-line and Hold Your Breath. Neither ever appears in City Cup, GT or Hypercar, and the drag routes never run as sprints.

**Result:** `NOT RUN`

**Notes:** 

### O9 · Old events survive the series rename — IDEA-111 — `street_sprint` became `city_cup`

**Do:** After deploy, check the calendar and `ncm.results` for anything from before.

**Pass:** Historic rows still read correctly; the calendar posts the new ids. Event ids are `seriesId@startsAt`, so old `street_sprint@…` rows are untouched and new ones are `city_cup@…`. **Nothing should error on the old ids** — if results or leaderboards break, the rename needs a display-layer mapping.

**Result:** `NOT RUN`

**Notes:** 

---

**Next deploy — Guide transport and interest-only world guidance**  *(context note; the section headings below are authoritative)*

## C. Host kit and scenarios (2.2 / 2.3) — needs Warden

### C1 · Scenario post

**Do:** `ncm.scenario gt <route> in 2`.

**Pass:** Posts and auto-enters everyone connected.

**Result:** `NOT RUN`

**Notes:** 

### C2 · Scenario restart

**Do:** `ncm.scenario restart`.

**Pass:** Re-forms the same field without a resource restart.

**Result:** `NOT RUN`

**Notes:** 

### C3 · Scenario stop

**Do:** `ncm.scenario stop`.

**Pass:** Retires cleanly — cars returned, venue undressed.

**Result:** `NOT RUN`

**Notes:** 

### C4 · World reset

**Do:** `ncm.world reset`.

**Pass:** Cars returned, offers cleared, no leftovers.

**Result:** `NOT RUN`

**Notes:** 

### C5 · Every discipline

**Do:** A short run of each: gt / badlands / drift / drag / oval / ncx. Record which routes exist (`/ncm.ar list`).

**Pass:** Each one forms and runs. Note which routes are missing.

**Result:** `NOT RUN`

**Notes:** 

### C6 · Readable state under pressure

**Do:** `ncm.state` mid-race.

**Pass:** **Is it readable under time pressure?** That is the actual test (L63), not whether it prints.

**Result:** `NOT RUN`

**Notes:** 

### C7 · Incident injection

**Do:** `ncm.incident <pid> <band>`; `ncm.rules incidents off/on`.

**Pass:** Bands inject and the rule toggles.

**Result:** `NOT RUN`

**Notes:** 

### C8 · Client debug

**Do:** `/ncm.debug` on the client.

**Pass:** Phase, next gate, distance, gps target, telemetry health.

**Result:** `NOT RUN`

**Notes:** 

## N. Eligibility at entry (IDEA-113, L83)

A championship declares what it admits (`eligibility` spec on the series); a driver must **own** a car it admits;
if they do not, entry is **refused, never substituted**. Two places enforce it: the venue list stops offering
`ENTER RACE`, and `enterPlayer` refuses anyway because the server is the one that decides.

**Both street series are currently `eligibility = {}` — open, admitting the whole pool.** So N1–N2 are the
baseline (nothing should change for an ordinary entry) and N3 onward need a narrowed spec to test against.
**Run §M first**: without a seeded garage every entry refuses and you will be testing the refusal, not the rule.

### N1 · An open series still admits everyone — IDEA-113 — the regression that matters

**Do:** With a seeded garage (§M5), enter an ordinary Street Sprint.

**Pass:** Entry works exactly as before. `ENTER RACE` is offered at the venue and pressing it enters you. **If this fails, eligibility has broken normal racing** and nothing else in this section matters.

**Result:** `NOT RUN`

**Notes:** 

### N2 · An empty garage is refused, with a way out — L83

**Do:** `ncm.revoke` everything (or use a second driver who owns nothing), then stand in a venue ring.

**Pass:** `ENTER RACE` is **absent** from the option list — not greyed, not present-and-failing. `PRACTICE` and `HISTORY` are still offered: you can learn the route while you go and earn the car. The server log reads `enter refused … reason=no_eligible_car admits=N`.

**Result:** `NOT RUN`

**Notes:** 

### N3 · The refusal says what would fix it — L83 — a refusal a player can act on

**Do:** From Warden, force an entry for a driver with nothing eligible: `ncm.enter <pid>`.

**Pass:** Chat reads *"You don't own a car eligible for <series>. N car(s) qualify — earn or bring one of those."* **Not** a bare "you can't enter" — the useful half is whether to switch cars or go and earn one.

**Result:** `NOT RUN`

**Notes:** 

### N4 · A one-make series admits exactly one car — IDEA-113 — the MaiMai Cup shape

**Do:** Temporarily set a series' `eligibility = { records = { "Vehicle.v_standard2_makigai_maimai" } }` in `packs/street.lua`, redeploy, and try to enter owning everything.

**Pass:** Entry is allowed. Then `ncm.revoke <pid> Vehicle.v_standard2_makigai_maimai` and try again: refused, `admits=1`. This is the check the whole championship catalogue rests on.

**Result:** `NOT RUN`

**Notes:** 

### N5 · A class filter admits a multi-class car — the model correction

**Do:** Set `eligibility = { classes = { "Muscle" } }` and own only the Colby pickup.

**Pass:** **Entry is allowed.** The pickup is Muscle *and* Nomad; a championship naming either must accept it. If it refuses, the multi-class fix has regressed and trucks are silently Nomad-only again.

**Result:** `NOT RUN`

**Notes:** 

### N6 · A broken spec blames the operator, not the driver — IDEA-113

**Do:** Set `eligibility = { records = { "Vehicle.not_a_real_car" } }` and try to enter.

**Pass:** Chat reads *"This race is not accepting entries right now."* — **not** "you don't own". The log carries `reason=championship_admits_nothing (CHECK THE SERIES ELIGIBILITY SPEC)`. Telling a driver they lack a car when we wrote the spec wrong sends them shopping for a car that does not exist.

**Result:** `NOT RUN`

**Notes:** 

### N7 · The option list and the server agree — IDEA-113 — two enforcement points

**Do:** With nothing eligible, watch the venue list, then force `ncm.enter <pid>` from Warden anyway.

**Pass:** The list does not offer `ENTER RACE`, **and** the console entry is still refused. The list is presentation; the server decides. A stale client must not be able to enter.

**Result:** `NOT RUN`

**Notes:** 

### N8 · A database hiccup does not lock anyone out — L83 — "could not ask" is not "no"

**Do:** Hard to force deliberately. If MySQL ever drops while the server runs, try to enter.

**Pass:** Entry is **allowed**, not refused. `NcmOwnership.owns` returns nil on a failed read and the refusal path treats nil as "no objection". Refusing on a database wobble would look exactly like a progression bug and would be blamed on the wrong thing for hours.

**Result:** `NOT RUN`

**Notes:** 

## I. The venue option list (IDEA-095)

Built 2026-09-22, deployed, never run. **I1 decides whether anything else in this section is reachable.**

### I1 · The ring still exists — the assumption this section rests on

**Do:** Drive to a venue with an event posted. The marker now carries no label at all.

**Pass:** The cyan ring is on the ground where it always was. **If there is no ring, stop and say so** — the unlabelled-marker assumption was wrong, the label goes back, and I2–I12 are unreachable until it does.

**Result:** `PASS`

**Notes:** It's a yellow ring as it has always been, not cyan. it is visible though.

**Retest:** Noted: the ring is the platform's default yellow — the `color` parameter has never taken effect, before or after this change. Cosmetic, not a regression, logged as KB-45. Not chased.

### I2 · No competing E card — KB-16

**Do:** Stand in the ring.

**Pass:** The platform's own "E" prompt card does **not** appear. The only prompt is NCM's list.

**Result:** `PASS`

**Notes:** 

### I3 · The list appears and is short — IDEA-095

**Do:** Stand in the ring.

**Pass:** A panel bottom-centre: series, route, venue, then **at most four** rows, most likely first. Typical: `ENTER RACE` / `PRACTICE` / `HISTORY`.

**Result:** `PASS`

**Notes:** 

### I4 · Tap cycles, hold engages — IDEA-095

**Do:** Tap E a few times, then hold it.

**Pass:** Each tap moves the cyan highlight down one row and wraps at the bottom. Holding fills the bar under the list and fires at ~0.6 s. A tap must **never** engage anything.

**Result:** `FAIL`

**Notes:** tapping e moves to the second row of the list briefly, then back to the top without any user input. cant reach the 2nd and 3rd items of the list reliably

**Retest:** **Fixed for deploy 10.** The highlight was compared by table identity, so every republish of the `ncmVenue` bag (every few seconds, identical contents) reset it to row 1 — exactly the "back to the top without any user input" you saw. It now compares the list's contents and remembers the highlight by option id. Expect tap to cycle 1→2→3→1 and stay where you put it. **I6, I7 and I8 unblock with this.**

### I5 · ENTER RACE still enters — regression on replacing the facade prompt

**Do:** Highlight `ENTER RACE`, hold E.

**Pass:** Same as the old prompt: entered, toast, `ENTERED player=…` in the log. If only one thing in this section works, it has to be this one.

**Result:** `PASS`

**Notes:** 

### I6 · PRACTICE says how to start — KB-28, KB-31

**Do:** Highlight `PRACTICE`, hold E.

**Pass:** A panel reading *"Cross the start line to begin a run…"* and `Open until the race forms`. **No "entries close in mm:ss" wording anywhere** — that phrasing is the bug.

**Result:** `blocked`

**Notes:** cant run until e scroll works

**Retest:** Blocked on I4, which is fixed for deploy 10 — run it again.

### I7 · HISTORY shows both readings — owner, 2026-09-21

**Do:** Highlight `HISTORY`, hold E.

**Pass:** One panel with **your runs on this route** and **the route record board**. Empty states read as sentences ("You have not finished a run on this route yet."), not blank tables.

**Result:** `blocked`

**Notes:** cant run until e scroll works.

**Retest:** Blocked on I4, which is fixed for deploy 10 — run it again.

### I8 · A panel closes with the same key — IDEA-095

**Do:** With a panel open, tap E. Then try holding E.

**Pass:** Panel closes, list returns. Neither tap nor hold should engage an option underneath it.

**Result:** `blocked`

**Notes:** cant run until e scroll works

**Retest:** Blocked on I4, which is fixed for deploy 10 — run it again.

### I9 · Options are absent, not greyed — KB-32 — this is the design

> **SUPERSEDED by L108 (2026-09-23).** The rule reversed: options are now **always present**, greyed
> with a reason. The owner, standing on a start line offered nothing but HISTORY, could not tell a system
> that had decided against them from one that was broken — and that time it was broken (KB-75). This item is
> kept, not deleted: it is a true record of what was required and why it changed. Its replacement is
> MASTER_TEST §AC9.

**Do:** Enter the race, then stand in the ring again.

**Pass:** `ENTER RACE` is **gone**, replaced by `WITHDRAW`. Nothing appears greyed-out or struck through.

**Result:** `FAIL`

**Notes:** Entrance ring disappears upon race entry as far as i can tell, no options panel available to click

**Retest:** **Fixed for deploy 10.** The ring was taken down on entry by a rule written when the marker's only job was to enter the race. IDEA-095 made it the way to reach WITHDRAW / PRACTICE / HISTORY, which matter most *after* entry. Only invitation events hide it now. Expect the ring to persist and the list to read `WITHDRAW` in place of `ENTER RACE`.

### I10 · Stale options are refused — IDEA-095

**Do:** Hard to force — try holding E on `ENTER RACE` just as the grid forms.

**Pass:** Either it enters, or a "Not available" toast appears and the list refreshes. It must never half-act.

**Result:** `NOT RUN`

**Notes:** 

### I11 · It stays out of the race HUD's way — IDEA-095

**Do:** Start a race from the venue.

**Pass:** The venue list disappears the moment the race HUD takes over, and does not reappear underneath it.

**Result:** `PASS`

**Notes:** 

### I12 · Chat goes quiet — KB-31 — the point of the whole surface

**Do:** Watch chat through I3–I7.

**Pass:** The option list, practice board and history produce **no chat lines**. `/ncm.practice` etc. still work when typed — they are the KB-4 console twin now, not the display surface.

**Result:** `PARTIAL`

**Notes:** The point isn't so much to avoid using chat for anything, moreso avoid it for most things. some things are fine. some things still come thru chat but less than before i think. bigger issue is all chats tagged as global when most should be personal to the player

**Retest:** Scope corrected by your note (L82): the goal is *most* things off chat, not all. The open defect is the **Global tag** (KB-42), not chat usage. NCM already sends per-player and never broadcasts, so the labelling is the platform's — re-scoped, not re-fixed.

## J. Race Guide v2 (IDEA-100) — built locally, not deployed

The data contract, regional schedule grid and detail rail pass the offline gate. These checks begin only after the
next deploy; until then, the live server still has the prior Guide.

### J1 · Start-node region owns placement

**Do:** Open Schedule and compare several event cards with their routes' first nodes, including a Badlands route.

**Pass:** Each card appears in the region of its route's start node. Cross-region finishes do not move the card, and
no known route falls into `UNKNOWN`.

**Result:** `NOT RUN`

**Notes:** 

### J2 · Concurrent events do not collide

**Do:** Inspect a time slot containing two or more events in the same region, if the current calendar produces one.

**Pass:** Every event remains independently selectable; cards stack without overlap or lost click targets.

**Result:** `NOT RUN`

**Notes:** 

### J3 · Stable selection across refresh

**Do:** Select a non-first event, leave the Guide open through at least one live refresh, then switch tabs and back.

**Pass:** The same event ID remains selected while it still exists. If it disappears from the payload, selection
moves cleanly to the first visible event rather than showing stale details.

**Result:** `NOT RUN`

**Notes:** 

### J4 · Capacity and entry state agree

**Do:** Select open, joined, full and invite-only events when available; compare the card/detail counts and action.

**Pass:** Capacity is identical everywhere. The primary action truthfully reads express interest, leave list, full,
or by invitation and fires no more than once.

**Result:** `NOT RUN`

**Notes:** 

### J5 · Course facts are factual

**Do:** Inspect lap and point-to-point events and compare their detail rail with the server payload.

**Pass:** Adapter, route, region, start type, laps/distance, practice state and generated description use known data.
No invented weather, story copy, map preview or result appears.

**Result:** `NOT RUN`

**Notes:** 

### J6 · Future doors are honest

**Do:** Inspect Past Races, reminder and route-preview affordances.

**Pass:** Unsupported capabilities are visibly unavailable and cannot be activated. My Races works from real entry
state; the UI leaves deliberate room for the future capabilities without fabricating them.

**Result:** `NOT RUN`

**Notes:** 

### J7 · Guide remains usable at target resolution

**Do:** Inspect the full Guide at 1920×1080, including the busiest available schedule and the longest factual text.

**Pass:** Header, grid, event cards and detail rail fit without clipping; text remains readable; scrolling, if needed,
is contained inside the intended surface and does not hide the primary action.

**Result:** `NOT RUN`

**Notes:** 

## L. Concurrent sessions (IDEA-112) — two clients

The change: `GlobalState.ncmSession` (one slot, last writer wins) became `GlobalState.ncmSessions` (a map, one
view per live session), and the client picks the view it is an entrant of. Until this shipped, two live races
made both drivers' HUDs flicker between them.

### L1 · Two races run at once without interfering — IDEA-112 — the whole point

**Do:** Get two races live simultaneously: enter one driver in a sprint and the other in a drag event that overlaps, or use `ncm.race.now` on two different events from Warden.

**Pass:** **Each driver's HUD shows only their own race** for its whole length — their route name, their position, their gates. Neither HUD ever shows the other race's route or flickers between the two.

**Result:** `NOT RUN`

**Notes:** 

### L2 · Both races settle correctly — IDEA-112

**Do:** Let both finish.

**Pass:** Two separate results, correct entrants and times in each, two sets of progression lines in the log. Neither result contains the other race's drivers.

**Result:** `NOT RUN`

**Notes:** 

### L3 · Telemetry goes to the right session — IDEA-112

**Do:** During L1, run `ncm.telemetry` from Warden for each session.

**Pass:** Each session receives samples only from its own entrants, `refused=0`. A driver's samples must never be attributed to the race they are not in.

**Result:** `NOT RUN`

**Notes:** 

### L4 · A finished race clears while the other continues — IDEA-112 — view pruning

**Do:** During L1, let the shorter race finish first.

**Pass:** The finished driver's HUD goes through its result and clears. **The still-racing driver's HUD is undisturbed** — no flicker, no stolen result banner.

**Result:** `NOT RUN`

**Notes:** 

### L5 · Solo racing is unchanged — IDEA-112 — the regression check

**Do:** Run one ordinary solo race start to finish.

**Pass:** Identical to before: lights, HUD, gates, result, clean-up. **This is the regression test that matters most** — the change touched the publication path every race uses, and solo is the path we run constantly.

**Result:** `NOT RUN`

**Notes:** 

### L6 · A non-entrant sees nothing — IDEA-112 — deliberate behaviour change

**Do:** Stand around as a connected driver while somebody else races.

**Pass:** Your HUD shows **no race HUD at all**. Previously a non-entrant was handed whatever single race was live; with several live there is no defensible answer to *which one*, so spectators now see nothing until spectating is designed. **This is intended — record it if it feels wrong, do not file it as a bug.**

**Result:** `NOT RUN`

**Notes:** 

### L7 · The practice surface still works — IDEA-112 — practice shares this code path

**Do:** Open practice for an event and take a run while no race is live.

**Pass:** Practice HUD and board behave exactly as before. `pickView` prefers a live session over practice, so also check that entering a race while practice is open switches you cleanly to the race.

**Result:** `NOT RUN`

**Notes:** 

## D. Never tested at all

### D1 · Telemetry mid-race — never verified

**Do:** Warden `ncm.telemetry` while driving.

**Pass:** `last client` present and `refused=0`.

**Result:** `NOT RUN`

**Notes:** 

### D2 · Client telemetry field list — decides whether drivetrain data reaches us (E8)

**Do:** Client log prints `telemetry fields: …` once per session — paste the field list into Notes.

**Pass:** The list is captured here, whatever it says. This one is data collection, not pass/fail.

**Result:** `NOT RUN`

**Notes:** 

### D3 · Rolling start — built, never run live

**Do:** `ncm.scenario oval <ring> laps 2 in 2`.

**Pass:** Formation holds, green fires at the leader, formation faults are caught.

**Result:** `NOT RUN`

**Notes:** 

### D4 · Two-race format — L53

**Do:** `ncm.event.post <route> 4 tworace`.

**Pass:** Race 2's grid is reversed from race 1's result.

**Result:** `NOT RUN`

**Notes:** 

### D5 · Leave / rejoin mid-race — KB-5 risk: you may lose WebUI and need a full relaunch

**Do:** Quit to menu during a race, then come back.

**Pass:** `SUSPENDED → RESUMED`, car re-claimed.

**Result:** `NOT RUN`

**Notes:** 

### D6 · The round number — KB-23 — **now fixed in deploy 9; this is the confirmation**

**Do:** After every race, note the finish time.

**Pass:** Times no longer land on `.000`. Duplicate of G1 — log it in whichever you reach first and cross-reference.

**Result:** `SUPERSEDED BY G1`

**Notes:** 

### D7 · The RB15 cliff — KB-30 / L77 — decides where the class ceiling goes

**Do:** In a Formula car, accelerate past 350 and note the **exact** km/h where it collapses.

**Pass:** A number, written down. The ceiling then goes at or below 355 km/h through the IDEA-079 ceiling authority — never a direct `setPerformance` call.

**Result:** `PASS`

**Notes:** Please cap the car at 355 kph

**Retest:** **Done for deploy 10.** `ncx_rb15` ceiling 340 → **355**, and — the part that mattered — the ceiling is now actually applied. It was data with no caller: `performanceFor` was never called and `setPerformance` appeared nowhere in NCM (KB-30 suspected exactly this). Ceilings publish on GlobalState so every client and every joiner caps itself. **Re-run: accelerate past 350 and confirm it holds at ~355 instead of collapsing.**

## K. Routes and the drag series (IDEA-104)

### K1 · Ten routes are actually scheduled — IDEA-104

**Do:** Open the F6 Race Guide and watch the calendar over ~40 minutes, or read `ncm.calendar` from Warden.

**Pass:** Route names cycle through **eight** sprint routes rather than repeating two. Over a full rotation you should see Ukulele, Snake in the Grass, The Cut, Troll Pass, Sewer, Overbridge Curve, Reverse Cut and Hook.

**Result:** `NOT RUN`

**Notes:** 

### K2 · Ukulele is called Ukulele — IDEA-104 — the label override is gone

**Do:** Find the Tip → Trench event in the guide.

**Pass:** It reads **Ukulele**, never `Tip-to-Trench`. If the old name appears anywhere, a `label` has crept back into a pack — the roots pack owns route names.

**Result:** `NOT RUN`

**Notes:** 

### K3 · The drag series exists and runs as drag — IDEA-104 / owner 2026-09-22

**Do:** Wait for a `Street Drag` event (every 30 min, offset 10), or pull one forward with `ncm.race.now bline`.

**Pass:** The event's series reads **Street Drag** and the session forms with `disciplineId=drag`. Server log shows a lanes course, not a point-to-point one. B-line and Hold Your Breath must **never** appear in the sprint series.

**Result:** `NOT RUN`

**Notes:** 

### K4 · A drag race actually completes — IDEA-104 — lanes adapter, never run live

**Do:** Enter a Street Drag event and finish it.

**Pass:** Grid forms with lane assignments, the race runs and settles. The offline test proves the course *builds*; this is the first time the lanes adapter has been driven. **Record anything odd about lane placement.**

**Result:** `NOT RUN`

**Notes:** 

### K5 · A bad route id cannot reach the calendar — IDEA-104 — the guard

**Do:** Nothing to do in game — this is a note. `tools\ncm-test.ps1` now fails if any root references a missing node.

**Pass:** If someone edits a pack and the gate goes red with `start node exists for …`, that is the guard working, not a broken build.

**Result:** `NOT RUN`

**Notes:** 

### K6 · Every route is drivable end to end — IDEA-104 — six of these have never been raced

**Do:** Over time, race or practice each of the eight sprint routes at least once.

**Pass:** Each one forms, has a sane distance, and its finish is reachable by road. **Six of the eight have never been run in Online** — log anything that is undrivable, ends in a wall, or takes absurdly long.

**Result:** `NOT RUN`

**Notes:** 

## B. Finish 2.1 — the Race Guide doors

### B1 · Practice run — P48

**Do:** On the list for an event, drive to the start and cross the line.

**Pass:** A run starts and times. Crossing the finish records it. Multiple runs allowed.

**Result:** `NOT RUN`

**Notes:** 

### B2 · Practice leaderboard — KB-31 — now superseded by I6/I7

**Do:** However it currently surfaces.

**Pass:** It exists and is right. Note whether the **times** are correct — the surface itself was rebuilt in deploy 9, so judge the numbers here and the presentation in §I.

**Result:** `NOT RUN`

**Notes:** 

### B3 · Upgrade at the line — P52 / L48

**Do:** Wait for entries to open (T−15), hold E at the venue.

**Pass:** State goes `interested → checked_in` **keeping the same entry id** (server log). Not a second entry.

**Result:** `NOT RUN`

**Notes:** 

### B4 · Withdraw — P52

**Do:** Get on a list, then press the button again / `/ncm.withdraw`.

**Pass:** You leave the list cleanly; the HUD drops back to `NCM · NEXT RACE`; the venue marker behaves.

**Result:** `NOT RUN`

**Notes:** 

### B5 · Interest never forms a grid — L48 — interest is not entry

**Do:** Get on a list and then *do not* go to the venue.

**Pass:** At start time the event closes with no session and no race. You are not silently entered.

**Result:** `NOT RUN`

**Notes:** 

## G. The eight settlement fixes

Solo-verifiable. Four of the eight were found in the one two-human race we have ever run; those live in §H.

### G1 · Race time precision — KB-23

**Do:** Run any race or time trial and read the finish time. Run two and compare.

**Pass:** The time is **not** a round multiple of 100 ms. `0:40.000` was the tell; a real time looks like quali's `1:04.964`. Both landing on `.000` or `.x00` means the fix did not take.

**Result:** `PASS`

**Notes:** 

### G2 · Green is dated from startsAt — KB-23

**Do:** Check the server log at lights-out.

**Pass:** `GREEN at <t>` where `<t>` equals the event's scheduled start, not up to a second later. Race times should now be *shorter* than before by up to 1 s for the same driving.

**Result:** `NOT RUN`

**Notes:** 

### G3 · Solo HUD is a time trial throughout — KB-33 / your Finding 1

**Do:** Enter alone and watch the strip for the whole run, not just the finish.

**Pass:** Eyebrow `TIME TRIAL · <route>`, the **elapsed clock** as the big value, `gate n/m` in the middle. **No `P1` at any point**, including the first second after green.

**Result:** `PASS`

**Notes:** 

### G4 · Accomplishments granted once — KB-38 / your Finding 4

**Do:** `/ncm.profile`, race, `/ncm.profile` again. Do it twice. **Run the `DELETE` at the foot of `KNOWN_BUGS.md` first**, or the old duplicates will still show.

**Pass:** `first_finish` and `first_win` appear **once each, ever**. The log line reads `accomplishments +0` on a second finish.

**Result:** `PASS`

**Notes:** 

### G5 · `ncm.tp` log — KB-21 residual

**Do:** Any `ncm.tp`.

**Pass:** Line ends `ok=true` or `ok={…k=v…}`. **No `table: 0x…` anywhere.**

**Result:** `NOT RUN`

**Notes:** 

### G6 · Readiness watchdog — KB-39

**Do:** Hard to force. Watch for it opportunistically when anyone joins and stalls.

**Pass:** At 45 s a connected player with no position gets chat + a toast saying to reconnect, and the log carries `readiness: player=N … not gameplay-ready (KB-39)`. **A clean join must trigger nothing.**

**Result:** `NOT RUN`

**Notes:** 

### G7 · No false entry while racing — KB-37

**Do:** Mid-race, from Warden: `ncm.enter <pid>` for another event.

**Pass:** Refused: *"You're still out in a session."* Log: `enter refused … reason=in_live_session`.

**Result:** `NOT RUN`

**Notes:** 

### G8 · No phantom DNS — KB-37

**Do:** Start a race, and while it runs let the next cadence event's start time pass.

**Pass:** The next event does **not** form with you in it and does **not** classify you DNS. Log: `held back N entrant(s) already in a live session` — **once**, not once a second.

**Result:** `NOT RUN`

**Notes:** 

## H. Two clients — what a solo run cannot prove

The most important section in the file. H1–H3 are the only real proof that KB-34's fix works, and KB-34 was the
defect that invalidated every incident record captured so far.

### H1 · Car-to-car contact is attributed — KB-34 — the whole fix

**Do:** Deliberately drive into each other at a clear speed difference.

**Pass:** Server log: `kind=car` with **`other=<the other driver>` populated on both sides**. `kind=object, other=nil` means it did not take.

**Result:** `NOT RUN`

**Notes:** 

### H2 · Both sides carry it — KB-34

**Do:** Same contact.

**Pass:** Two incident rows, same band, one per driver, `attributed=both`. Both drivers' SR moves.

**Result:** `NOT RUN`

**Notes:** 

### H3 · Scenery is still scenery — KB-34 — regression risk from my own fix

**Do:** One driver alone hits a wall hard while the other is far away.

**Pass:** Still `kind=object`. The new neighbour-staleness guard must not have made object hits impossible — **if wall hits stop registering entirely, the guard is too strict and that is a regression.**

**Result:** `NOT RUN`

**Notes:** 

### H4 · Questionnaire is private — KB-41

**Do:** Client 2 joins fresh while client 1 is playing.

**Pass:** The Driver Profile questionnaire opens **only on client 2**. Client 1 sees nothing. It used to open on everyone.

**Result:** `NOT RUN`

**Notes:** 

### H5 · Chat visibility — KB-42, still open

**Do:** Client 1 finishes a run.

**Pass:** Does client 2 see `[NCM] Result:`? **Either answer is useful** — record which.

**Result:** `NOT RUN`

**Notes:** 

---

## Q. Championship labels and apparel slice 1

### Q1 · Every Guide card names its championship

**Do:** Open F6 with events from at least three championships and select several cards.

**Pass:** Each schedule card shows route and championship/series. The detail rail repeats the championship beneath
the route. No route is presented as though it were the event's only identity.

**Result:** `NOT RUN`

**Notes:** 

### Q2 · Empty presentation receives a complete starter outfit

**Do:** Join with an empty OPEN//77 equipment record.

**Pass:** Shirt, trousers and shoes appear; log says `starter clothing requested for empty slot(s)`; the character
is not left near-naked. No head, face, jacket, outfit or underwear choice is invented.

**Result:** `NOT RUN`

**Notes:** 

### Q3 · Existing clothing is never overwritten

**Do:** Save distinct clothing in the wardrobe, reconnect, and inspect all equipped slots.

**Pass:** Every saved item remains. Log says `saved clothing present; starter grant not needed`, or only genuinely
missing starter slots are requested.

**Result:** `NOT RUN`

**Notes:** 

### Q4 · Starter clothing persists

**Do:** After Q2, disconnect and reconnect without opening the wardrobe.

**Pass:** The same shirt, trousers and shoes return from OPEN//77 presentation persistence; NCM does not repeatedly
grant or visibly reattach them.

**Result:** `NOT RUN`

**Notes:** 

### Q5 · Another client sees the committed outfit

**Do:** Observe the Q2 driver from a second client before and after reconnect.

**Pass:** The observer sees the committed starter clothing. The two clients agree on all three slots.

**Result:** `NOT RUN`

**Notes:** 

## A. Deploy 8 fixes

A1–A4 were run 2026-09-21 and passed; the full narrative is in the appendix. A5 was partial and has since been
closed in deploy 9 (re-check as G5). A6 and A7 were never run.

### A1 · Solo race = time trial — IDEA-001 / L67

**Do:** Enter any event alone and finish it.

**Pass:** Result banner reads **TIME TRIAL** with your time as the big value, *not* `P1`.

**Result:** `PASS`

**Notes:** 2026-09-21, Tip → Trench, ~6.6 km, 1 entrant. Settlement read **Tip-to-Trench Time Trial**. See appendix. Adjacent findings 1–4 raised from the same run.

### A2 · No phantom win — IDEA-001

**Do:** `/ncm.profile` right after A1.

**Pass:** `first_win` does not increase; a new `first_time_trial` appears once; `rating —` stays absent.

**Result:** `PASS`

**Notes:** 2026-09-21. "Considered the first time trial, not a phantom win."

### A3 · Result banner lifetime — KB-22

**Do:** Watch the finish closely.

**Pass:** Banner and results board appear together and **disappear together**.

**Result:** `PASS`

**Notes:** 2026-09-21. "Result banner disappeared in time gracefully."

### A4 · No map flicker — L70

**Do:** Get on the list, drive to a venue, start a race.

**Pass:** The map **never** opens and closes by itself.

**Result:** `PASS`

**Notes:** 2026-09-21. "Map did not flicker."

### A5 · `ncm.tp` log — KB-21

**Do:** Run `ncm.tp 1 venue` from Warden, or check the log after any tp.

**Pass:** Line names the venue and event. No `table: 0x…`, no bare `nil`.

**Result:** `PARTIAL`

**Notes:** 2026-09-21 23:20 — venue and event named, but the line still ended `ok=table: 0x…`. **Residual fixed in deploy 9 — re-check as G5.**

### A6 · Counter honesty — KB-29

**Do:** Get on a list, then have `ncm.calendar` run.

**Pass:** The row reads `entrants=0 (+1 on the list)` — not `entrants=1`. The close line says `… (0 entrant(s), 1 on the list)`.

**Result:** `NOT RUN`

**Notes:** 

### A7 · Version banner — KB-24

**Do:** Boot log.

**Pass:** `ncm_world started v0.5.0`. **Known remaining:** `ncm_league` still reports `v0.1.0` while its manifest says 0.3.0 — same bug, unfixed. Note it and move on.

**Result:** `NOT RUN`

**Notes:** 

## F. System glyph tranche 1 (IDEA-080)

Built 2026-09-22 and deployed in deploy 9; browser syntax and the full offline gate pass, but no glyph has been
observed in OPEN//77 yet.

### F1 · Guide rows carry glyphs — IDEA-080

**Do:** Open the F6 Race Guide with street and sanctioned rows.

**Pass:** Every row has a legible route glyph and tier glyph at normal viewing distance; no broken-image boxes or missing rows. Street and sanctioned stay distinguishable without relying on colour alone.

**Result:** `partial`

**Notes:** 3verything is tagged with the same glyph so far but definitely there are new glyphs

**Retest:** Glyph mapping is incomplete rather than absent — logged as KB-44 for the glyph author.

### F2 · Sign-up button glyph — IDEA-080

**Do:** Click **GET ON THE LIST**, then leave it.

**Pass:** The button carries the sign-up/leave glyph without shifting, clipping or swallowing the label. The existing action still fires exactly once.

**Result:** `FAIL`

**Notes:** get on the list exists and i can click it, it registers me, but race guide does not show me on list or that i can leave list, nor does it show anyone interested in event.

**Retest:** **Not fixed, deliberately.** Your note says the button read `GET ON THE LIST`; the panel in the tree now reads `EXPRESS INTEREST` — Codex's Race Guide v2 (IDEA-100, §J) replaced this code after you tested. Fixing it would mean debugging code you never ran. **Re-run F2 once v2 deploys** (KB-43).

### F3 · Venue options carry distinct glyphs — IDEA-080 + IDEA-095

**Do:** Stand in a venue ring and cycle every available option.

**Pass:** ENTER, PRACTICE, WITHDRAW/LEAVE LIST and HISTORY use distinct 24-grid glyphs; the selected cyan styling comes from CSS and stays readable against the panel.

**Result:** `PASS`

**Notes:** 

### F4 · Race state glyphs track state — IDEA-080

**Do:** Run standing and rolling starts through a finish.

**Pass:** Grid/formation, live/green, incident or jump-start, result, and finish glyphs appear in the correct state. **No stale glyph survives a state transition.**

**Result:** `PASS`

**Notes:** Didnt do a rolling start none are available

**Retest:** Noted: no rolling-start route is configured, which is also why D3 is unrun. Logged as KB-46.

### F5 · Graph and result board glyphs — IDEA-080

**Do:** Watch the progress graph and result board.

**Pass:** Finish endpoint and result title glyphs are crisp, aligned, and do not overlap driver tags or timing columns.

**Result:** `PASS`

**Notes:** 

### F6 · Legible in motion, in daylight — IDEA-080

**Do:** Check at 1920×1080 in motion, including bright daylight.

**Pass:** Glyphs stay recognisable at their actual 18–34 px sizes; colour is supportive, never the only readable signal. **Record any symbol whose meaning is unclear without its label.**

**Result:** `PASS`

**Notes:** 

---

## P. Guide blocker and unsolicited calendar presentation

### P1 · F6 receives the live rows directly

**Do:** Open F6 with events posted and inspect the client log.

**Pass:** The Guide briefly says `Loading live schedule…`, then shows the events. Client log says
`guide payload received: N row(s)` with `N > 0`; it never settles on `Nothing posted right now` while
`/ncm.guide` lists rows.

**Result:** `PASS`

**Notes:** 2026-09-22 owner: “race guide is populated.” Direct payload fix proven live on deploy 12.

### P2 · Interest refreshes the open Guide

**Do:** Express interest from F6, leave the Guide open, then withdraw.

**Pass:** The selected event changes to on-list state and back without closing/reopening F6. Counts and the primary
action update with it. This is the KB-43 retest.

**Result:** `PASS`

**Notes:** 2026-09-22 owner: expressing interest works, leaving the list works, and My Races works.

### P3 · No named race or waypoint without interest

**Do:** Join with no live entry and wait through an event entering its registration window.

**Pass:** The only persistent NCM card is `NCM · RACE GUIDE` with an F6 prompt. It names no race, creates no venue
ring, and does not replace or create the player's waypoint.

**Result:** `NOT RUN`

**Notes:** 

### P4 · Interested guidance follows your event

**Do:** Express interest in an event that is not the soonest event on the calendar.

**Pass:** The card, venue ring and automatic route all point to the event you selected. An unrelated championship
starting sooner never takes over the card or GPS.

**Result:** `NOT RUN`

**Notes:** 

---

**Next deploy — Guide identity and starter clothing**  *(context note; the section headings below are authoritative)*

## R. Platform .87 upgrade — regressions and re-checks

Staging upgraded .84 -> .87 on 2026-09-22 and NCM was offline for ~1 hour (KB-51). These are the checks that
upgrade earned. **R1 is a standing step for every future upgrade, not a one-off.**

### R1 · The load-list guard runs clean — KB-51, every future upgrade

**Do:** After any OPEN//77 upgrade, before restarting: `scp tools\staging\check-load-list.py` then
`python3 /tmp/check-load-list.py`.

**Pass:** Exit 0, `load list OK: N resources, every dependency satisfied`. Non-zero means the server will abort
its **entire** automatic start set and NCM will not run — while still listening and registering with the master,
so every surface-level check still passes. That is exactly how .87 hid an hour of downtime.

**Result:** `PASS`

**Notes:** 2026-09-22 — verified clean on .87 after the fix: `load list OK: 38 resources, every dependency satisfied`.

### R2 · NCM boots clean on .87 — KB-51

**Do:** Read the boot log after any upgrade restart.

**Pass:** Five lines, in order: `migrations: N applied` · `ownership ledger ready` · `ncm_world started v…` ·
`class ceilings published: 11 record(s)` · `scheduler started: 5 series`. **If the series line is missing, NCM did
not start**, whatever else looks healthy.

**Result:** `PASS`

**Notes:** 2026-09-22 17:55 — all five present, migration 012 intact, 5 series with correct route and vehicle
counts, zero `[ERR]` since.

### R3 · `Open77.*` API drift on .87 — owner: "we'll check"

**Do:** Exercise each surface once and watch for silence: state bags (guide/venue/practice/history), `players.get`
position, `vehicles.setPerformanceClass` (the 355 cap), `input.isDown` (venue list tap/hold), notifications, chat,
blips/GPS, worldui ring, interactions, `time.unix`/`monotonic`.

**Pass:** Each behaves as on .84. **Most of these calls are `pcall`-wrapped, so a method that became nil fails
silently** — absence of errors is not evidence. The guide and venue publishes now log their own failures
(GUIDE/VENUE PUBLISH FAILED); the rest do not.

**Result:** `NOT RUN`

**Notes:** 

### R4 · KB-39 readiness latch in .87 — owner: "lets test kb 39"

**Do:** Read `open77_appearance/client/main.lua` `announce()` on the box. Then watch a join that stalls.

**Pass:** The function no longer opens `if announced or failed ~= nil then return end` — i.e. a failed appearance
restore can retry and `gameplayReady` can still fire. If the latch is gone, **NCM's watchdog should stop firing
entirely**; a clean join must still produce no warning. If the latch remains, KB-39 is unfixed upstream and the
watchdog stays earning its keep.

**Result:** `NOT RUN`

**Notes:** 

### R5 · Required mods on .87 — KB-8, owner: "important we need to try soon"

**Do:** `set-unsecured.py` + restart, try Play from the launcher, then **park it again with `set-mods-off.py`**.

**Pass:** Either verdict is a result. Refused in ~300 ms (`Unverifiable` / `NotInIndex`) = unchanged, KB-8 stands.
Connects = the upstream review landed, and **L76 re-opens by its own terms**, KB-40's hand-install workaround
leaves TW1's critical path, and P34 changes. **Do not leave required mods enabled** — a real player is refused
entry until it is parked back.

**Result:** `NOT RUN`

**Notes:** 


---

# Answered — kept for the record

## E. Free-driving observations

No setup — just drive, and write here.

Worth noting: the F9 messages thread, world markers that look actionable but are not (KB-16), stale map pins
(KB-15), weather differing from what you expect (KB-6), wording anywhere that made you re-read it, and
**anything that made you hesitate about what to do next** — that last one is the most valuable note in the file.

**Notes:**

---

---

# Appendix — recorded runs

Kept verbatim. This is primary evidence: where a summary line above disagrees with this, this is what was seen.

## A1 through A4 — Solo Scheduled Entry / Time Trial Semantics

**Route:** Tip → Trench  
**Distance:** ~6.6 km  
**Entrants:** 1  
**Primary questions:** Does a solo scheduled entry settle as a time trial rather than a one-car race / free race win? Was driver awarded a phantom win? Was the result banner up too long? Did the map flicker?

### Result: PASS — with significant adjacent findings

The primary acceptance criterion passed.

The event started successfully with one entrant and, on completion, settlement explicitly identified the activity as:

> **Tip-to-Trench Time Trial**

This confirms that a solo scheduled entry is no longer treated as a race victory simply because no other drivers entered. The most important settlement semantic is therefore correct. Also, it was considered the first time trial, not a phantom win, result banner disappeared in time gracefully, and map did not flicker

### Finding 1 — Live HUD still presents the activity as a race

During the time trial, the live HUD displayed:

> **P1 of 1**

This makes the activity appear to be a race until settlement, despite the backend ultimately treating it correctly as a time trial.

A solo time trial should not display race-position semantics. The live HUD should communicate that the player is participating in a time trial before they reach the finish.

**Desired direction:** time-trial-oriented information such as elapsed time, progress, delta/PB information where applicable, etc., rather than `P1 of 1`.

**Severity:** Medium  
**Primary test impact:** Does not invalidate the settlement PASS, but presentation/semantics are incomplete.

### Finding 2 — Race progress visualization does not match intended design

The current progress visualization is horizontal and overlaps the speedometer, obscuring useful vehicle information and consuming too much screen space.

This is not the intended design.

The intended race-progress visualization is a **compact vertical line/graph**:

- Start at the bottom.
- Finish at the top.
- Driver markers move vertically along the line according to race progress.
- Multiple drivers should be representable in the same narrow footprint.
- The design should remain usable with a large field rather than expanding substantially as more drivers participate.

The current horizontal implementation should therefore be treated as provisional / incorrect.

**Severity:** Medium

### Finding 3 — Incident detection is substantially too insensitive

Multiple obvious incidents occurred during the run without generating incident notifications.

Observed examples included:

- Minor barrier/wall contact.
- More substantial barrier impacts.
- A major loss of control involving a jump/impact.
- Vehicle flip.
- Leaving the roadway.
- Becoming trapped on the wrong side of a barrier.
- Additional contact while brute-forcing the vehicle back onto the route.

Despite this, incident detection did not reliably register these events.

The desired NCM philosophy is that **incident severity should scale with the event; severity should not determine whether the event exists at all.**

Conceptually:

- Light scrape/contact → small incident.
- Meaningful wall/barrier impact → larger incident.
- Major crash / flip / severe impact → major incident.

NCM should be relatively strict about recording poor driving. This does not necessarily mean severe sporting punishment for every contact. The purpose is to accurately observe and record driving behavior so that poor driving cannot simply disappear from the driver's history.

**Severity:** High

### Finding 4 — Incorrect clean classification

Despite the numerous incidents described above, settlement awarded:

> **Clean Race**

This is incorrect in two ways:

1. The run was clearly not clean.
2. The completed activity was a **time trial**, not a race.

The immediate false-clean result appears related to the incident-detection weakness above.

The semantic treatment also needs clarification. If clean performance is supported for time trials, the result should use an appropriate time-trial or mode-neutral term such as `Clean Time Trial`, `Clean Run`, or `Clean Finish`. If `Clean Race` is intended specifically to represent clean competitive racing around other drivers, a solo time trial should not award it.

**Severity:** High

This finding is especially important because incident/clean-driving data is expected to feed future NCM systems such as driver history, statistics, achievements/badges, Driver Fingerprint behavior, and other progression/identity systems. False `clean` classifications would contaminate those systems upstream.

### Finding 5 — Trench marker registration

**PASS.**

The new Trench marker registered successfully.

Observed waypoint behavior remains understood as an OPEN//77-side issue rather than an NCM marker-registration failure and is not considered a failure of this test.

---

### Test 1 Summary

**PRIMARY GATE: PASS**

Solo scheduled participation correctly settles as a **Time Trial** rather than awarding a one-car race result/win.

However, the run exposed four important adjacent issues:

1. Live HUD incorrectly presents the time trial as `P1 of 1`.
2. Progress visualization is horizontal/oversized and does not match the intended compact vertical design.
3. Incident detection fails to recognize numerous levels of vehicle contact and major crashes.
4. The run incorrectly received `Clean Race` despite being both non-clean and a time trial.

The core solo-settlement change is validated. The associated live presentation and incident/clean-classification systems still require work.

A5 — NOTE/partial. Residual is a one-liner in main.lua:182 (print the table's fields, e.g. ok.ok/ok.error, instead of tostring(ok)); worth checking what keys the table carries first so the line says something true. For KNOWN_BUGS.md: KB-21 stays open as "verified live 2026-09-21 23:20 — venue named, ok= still a table address"

Unexpected external connection: During Practice QA, a second human player connected to NCM Staging despite Warden reporting the server as unlisted/hidden. Player sent “hey” and disconnected approximately one minute later. named dop42No meaningful NCM multiplayer interaction occurred. Visibility/discovery path unknown. Does not constitute multiplayer validation.

and then a third player??? named Borgo

Suspicion is that they are possibly official devs (an official dev in the discord goes by dop)

we need to consider what people see first time in the server. first time they are hit with a questionnaire which is only for tw2. regular joins (and mystery ones) should get normal expected server treatment

---

**Deploy 11 — routes, drag, and concurrent sessions (appended 2026-09-22)**  *(context note; the section headings below are authoritative)*

**Per L78 each item below was given its live-QA line when it was written.** Nothing here has run once.

**Run K first.** K1 decides whether the calendar is showing ten routes at all; everything else in K is cheap once
it does. **L needs two drivers and is the whole point of the change** — a solo run cannot prove any of it.

| § | What | Needs |
|---|---|---|
| **K** | The eight sprint routes, the drag series, the Ukulele rename | solo |
| **L** | Concurrent sessions (IDEA-112) | **two clients, two races** |

---

## §W — Weather authority / KB-6 retest (op77.87; appended 2026-09-22)

**Hard gate:** do not connect weather to race classification, performance, badges, economy, Fishing, or permanent
provenance until W1–W8 pass. Use the temporary `ncm_weather_probe`; every evidence line is prefixed
`[ncm_weather_probe]`. Preserve the executed run in a dated experiment record.

| ID | Check | PASS evidence |
|---|---|---|
| W1 | Two clients in default scope; `ncm.wx.capture default-baseline`. | Both observations match canonical epoch, scope `default`, preset and weather revision; clock/transition differences fit sampling latency. |
| W2 | Force each of `sunny`, `lightclouds`, `cloudy`, `rain`, `heavyclouds`, `fog`, `pollution`, `sandstorm`, capturing during and after each transition. | Both clients project every preset and converge after each transition. |
| W3 | Enable platform scheduling and wait for one natural change; capture before/during/after. | Canonical change is observed by both clients without manual resync. |
| W4 | Start a long transition, disconnect client B, rejoin it mid-transition, then capture. | B joins the same transition at its current remaining time rather than restarting it. |
| W5 | Create bucket 7701 override, move both clients into it, and capture. | Both report `scope=bucket:7701` matching that canonical override. |
| W6 | Move client B back to bucket 0 and capture. | B reacquires default state while A remains on the event override. |
| W7 | Return A to bucket 0, clear bucket 7701, and capture. | Both report default; `getState(7701)` returns the documented unknown-bucket result. |
| W8 | Review every canonical/client tuple and check for stale revision, wrong epoch/scope, divergent preset, or unexplained transition reset. | No discrepancy. Mark KB-6 fixed only with this complete PASS. |

**Executed 2026-09-22: W1–W8 PASS on OPEN//77 op77.87.** Durable evidence: [E26](../archive/experiments/E26_2026-09-22_weather-sync.md).

---

## §X — NCM Weather Service adapter (migration 013; appended 2026-09-22)

**Not run.** This validates NCM policy/persistence; §W already validated the underlying platform synchronization.
Do not attach competitive/economic consumers until this section passes. Use a normal announced server restart, never
a hot resource restart with clients connected (KB-5).

| ID | Check | PASS evidence |
|---|---|---|
| X1 | Boot deployment with no clients; inspect migration and service log. | Migration 013 applies once; service logs one epoch, a non-empty plan, current transition id and approximately seven days of coverage; no `environment_unavailable` or SQL error. |
| X2 | Run `ncm.weather.status`, `weather.status`, and `/ncm.guide` with one client. | NCM is `ready`; platform random weather is off; current plan weather equals canonical weather; Guide payload capability `weather=true` and has one bounded top-level weather block, not per-event copies. |
| X3 | Inspect DB counts and boundaries read-only. | One `weather_plan` default row; transition ids/times are unique and ascending; first row covers now; final coverage is about seven days; observation count is bounded. |
| X4 | Capture the current transition ids/timestamps, perform an announced clean server restart, then inspect again. | Same epoch/seed and all previously published transition rows remain byte-for-byte stable; service selects the row covering current UTC and does not regenerate tomorrow. |
| X5 | If restart occurs during a planned transition, compare canonical transition remaining time. Otherwise use a controlled dev policy only in a later isolated test. | Reconciliation applies only the remaining transition duration, not the full duration from restart. No visual reset/replay. |
| X6 | Leave server running through one planned boundary and capture both clients. | NCM applies the next persisted row once, both clients match canonical, one canonical observation is retained, and the platform random scheduler does not interleave another choice. |
| X7 | Force external drift once through the existing admin weather command, then wait one reconciliation interval. | Service records the canonical change and restores the planned state within approximately 10 seconds; status returns `ready`. |
| X8 | Inspect Guide weather payload size/content and unavailable behavior (DB/environment failure in an isolated test only). | At most 24 hours of forecast and 16 recent rows; `OBSERVED/FORECAST/OUTLOOK`, ordinal confidence, scope/revisions present; failure publishes `state=unavailable` without fabricated conditions. |

## S. Guide information layer, visitor welcome and restart discipline

Everything built after deploy 11 that has not been validated. **§S1–S4 need no weather**; S5–S7 need the Weather
Service live (run §X first). The Guide's own population is already PASS (MASTER_TEST §2.1, deploy 12) — this
section is about the information now riding on it.

### S1 · Authored route descriptions appear — IDEA-104 follow-up

**Do:** Open F6 and select each of the ten routes in turn.

**Pass:** The detail pane shows the **authored prose** — Ukulele reads *"A 6.6 km cross-city run mixing fast straights, chicanes, varied corners and a long, kinked tunnel toward the finish."* The generated line (*"street sprint from X to Y. standing start."*) may appear as a secondary `summary`, **never instead of the prose**. All ten were authored; if any shows only the generated line, that route's description is not reaching the panel.

**Result:** `NOT RUN`

**Notes:** 

### S2 · What car to bring — IDEA-124, L83

**Do:** With a seeded garage, select a City Cup event, then MaiMai Cup, then Hypercar.

**Pass:** Each shows what the championship admits and **how many of them you own** — the payload carries `car = { summary, admits, iOwn, ok }` per row. MaiMai Cup should read as one specific car. **Revoke your MaiMai and re-check:** `ok` goes false, and that must match `ENTER RACE` being absent at the venue — the guide and the venue list must never disagree about whether you can race.

**Result:** `NOT RUN`

**Notes:** 

### S3 · Regs before commitment — IDEA-125

**Do:** Select any event.

**Pass:** Tier (street vs sanctioned), discipline, format, laps, start type and field cap are all visible. **GT and Hypercar read `sanctioned`; City Cup, MaiMai and Drag read `street`** — before this they all said street, because tier was derived from `class` and every cadence series is `calendar`.

**Result:** `NOT RUN`

**Notes:** 

### S4 · The visitor welcome, once and only once — IDEA-131, IDEA-132

**Do:** Join with a driver that has never connected before (a fresh identity, not a reconnect). Then disconnect and rejoin with the same driver.

**Pass:** **First join:** ~6 s after arrival, one `NCM · ALPHA` toast and two chat lines — alpha framing, `/ncm car Sport`, `/ncm return`, F6. **No Driver Profile questionnaire** (shelved, TW2 only). **Second join: nothing.** A returning driver must get no welcome at all; repeating it is the noise we removed in IDEA-127. Then `ncm.q.ask <pid>` from Warden should still offer the questionnaire deliberately.

**Result:** `NOT RUN`

**Notes:** 

### S5 · Weather rides once, not per row — IDEA-133, 11_WEATHER.md

**Do:** With the Weather Service live, open F6 and check the payload/panel.

**Pass:** One weather read model at payload top level, and a **small** per-row cue only — `{ w, family, conf, kind, changes, soonAt }`. If a full forecast is being copied onto every event row, the seam has been misunderstood and the payload will bloat (relevant: the guide publish already failed once on size).

**Result:** `NOT RUN`

**Notes:** 

### S6 · Forecast confidence is ordinal and honest — 11_WEATHER.md forecast model

**Do:** Compare a race starting soon against one several hours out.

**Pass:** Near events read `HIGH`/`OBSERVED` or `FORECAST`; distant ones degrade to `MED`/`LOW` and `OUTLOOK`. **No percentages anywhere** — the architecture defers numeric calibration, and the service emits ordinal confidence. A race four hours out must not be presented as definitively RAIN.

**Result:** `NOT RUN`

**Notes:** 

### S7 · A transition near the start is flagged — IDEA-133 — the brief's real question

**Do:** Find (or force, via the weather console) a change landing within ~10 minutes of an event start.

**Pass:** That event carries `soonAt`, so the panel can say conditions may change — **even though no event has a known duration yet**. `capabilities.weatherWindow` is `false`, so the UI must not claim "conditions during the race"; only "at the start", plus the transition warning. Claiming a during-race forecast from a guessed race length is the thing this was built to avoid.

**Result:** `NOT RUN`

**Notes:** 

### S8 · A restart announces itself — L86

**Do:** With at least one player connected: `ncm.restart 60` in Warden's Live Console, then `bash restart-with-warning.sh 60` on the box. Try `ncm.restart.cancel` first on a separate run.

**Pass:** Every connected player gets a toast **and** chat at 60/30/10/5 and again at zero. Cancel produces "RESTART CANCELLED — carry on" and no further countdown. **Nobody is dropped without warning** — that is the whole rule.

**Result:** `NOT RUN`

**Notes:** 

## T. Vehicle Collection and discovery provenance

Everything in migration 014, none of it ever deployed. **T1–T3 gate the rest**: if discovery does not fire at
all, nothing below it can be judged. KB-53 is the reason T1 exists — the first implementation called a platform
function that does not exist and failed silently forever, so "no discoveries appeared" must never again be
assumed to mean "nobody drove near anything".

### T1 · Discovery fires at all — KB-53, IDEA-134

**Do:** Two clients. Driver B stands still; Driver A pulls up within ~18 m in an NCM-issued car B has never encountered, and stays for 3+ seconds. Watch the server log.

**Pass:** B gets `NEW VEHICLE DISCOVERED` and a `[ncm_league/collection] DISCOVERED driver=… key=…` line. **If nothing happens, run `ncm.collection.probe <B's playerId>` immediately** — it now prints a specific verdict per registered vehicle (`no_snapshot` / `record_mismatch` / `bucket` / `distance`) using the *same* snapshot resolution as the live loop, so the probe and reality can no longer disagree.

**Result:** `NOT RUN`

**Notes:** 

### T2 · The source is recorded, and it is the right driver — spec 1 §A, IDEA-135

**Do:** After T1, read the row: `SELECT vehicle_key, source_driver_id, source_holding FROM vehicle_discovery WHERE ncm_driver_id = '<B>'`.

**Pass:** `source_driver_id` is **A**, and `source_holding` is `issued` for a `/ncm car` vehicle (or `team` for a grid car). The DISCOVERED log line names the same source. A NULL source here is the failure this whole pass exists to prevent — and it cannot be repaired later.

**Result:** `NOT RUN`

**Notes:** 

### T3 · Credit is written once and never rewritten — IDEA-137, spec 1 §A anti-farm

**Do:** With B's discovery already recorded, have a **different** driver C park an identical car next to B for well over the dwell. Then have A leave and return several times.

**Pass:** `encounter_count` rises, `last_encounter_at` moves, and **`source_driver_id` still reads A**. Source is written on INSERT only and is absent from the `ON DUPLICATE KEY UPDATE` clause — if C's id ever appears, later encounters are rewriting history and the standings become unfixable.

**Result:** `NOT RUN`

**Notes:** 

### T4 · Nobody inspires themselves — IDEA-135

**Do:** `/ncm car Sport` as a driver who has never had that machine, then sit beside your own car past the dwell.

**Pass:** The discovery is awarded (you did encounter it) but `source_driver_id` is **NULL** — `Discoveries.credit` refuses with `self`, and the DISCOVERED log line shows `source=none (self)`. The database `CHECK` constraint is the backstop if the code ever stops refusing.

**Result:** `NOT RUN`

**Notes:** 

### T5 · The standings answer all four questions — spec 1 §B, IDEA-136

**Do:** `ncm.inspired` in Warden's Live Console, then `ncm.inspired 1` for a one-day window.

**Pass:** Each line reads *N inspired · N drivers reached · N machines introduced*, sorted, with the window changing the totals and not the all-time record. **Every figure is derived from the rows at read time** — there is no stored counter, so a figure here can never drift from the discoveries that produced it.

**Result:** `NOT RUN`

**Notes:** 

### T6 · A fresh generation publishes, and a partial one recovers — KB-55

**Do:** First boot after migration 014: check `[ncm_league/collection] ready generation=1 vehicles=…`. Then delete a few `vehicle_catalogue_member` rows by hand and restart.

**Pass:** First boot publishes generation 1 and logs `ready`. After the deletion, the next boot logs *completing a partial generation 1 publish: N of M members present* and recovers — it does **not** refuse forever with `catalogue_generation_changed_without_bump`, which is what the original code did and which only manual SQL could undo.

**Result:** `NOT RUN`

**Notes:** 

### T7 · An unreadable collection refuses instead of lying — KB-54

**Do:** Hard to force deliberately; watch for it instead. Any `[ncm_league/collection] discovery read FAILED` line in the log is this case.

**Pass:** When it happens the panel shows nothing rather than `0 / 28 discovered`, and **no** `NEW VEHICLE DISCOVERED` toast fires for a machine the driver already had. An empty collection and an unreadable one must never look the same to a player.

**Result:** `NOT RUN`

**Notes:** 

## Base Market access follow-up — 2026-09-23

PASS: normal tools/ncm-test.ps1 gate, 196 core + 28 access checks per interpreter, 126 resource Lua syntax
checks, 3 inline scripts and 67 panel render assertions; ncm-build.ps1 -Check clean. Access fixtures execute
the real client/server adapters, covering title rejection/recheck, wrong sender/token, duplicate request,
movement, bucket/expiry/disconnect, exact-record creation, two same-model assets, cleanup, DB/create refusal,
nonfinite/distant poses, unsupported geometry, blocked clearance, moving/seated callers.

FAIL: extra tools/ncm-stub.lua guide run expects obsolete Street Sprint row 1; current fixture produces MaiMai
Cup. Also missing weather environment double. Recorded KB-71/IDEA-200; unchanged outside this task's scope.

Live storage read PASS is recorded in MASTER_TEST 2.17 §AB1. Runtime/geometry/UI work remains NOT RUN live in
§AB3–AB9. The official requested .87 API index falls back to .78; no live API or geometry success is inferred.