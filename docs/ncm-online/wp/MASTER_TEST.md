# NCM Online — master test (the one validation pass before TW1)

> **STATUS: LEDGER** - living and append-only, current by construction. Covers: *live PASS/FAIL evidence* (L69)
> Authority map: [INDEX.md](../INDEX.md) - classified 2026-09-24 (L125)

## W. Walk-in orientation anchor (IDEA-195/L101)

**Built and offline-green; not deployed.** Full gate remains 181/181 core tests under Lua 5.4 and LuaJIT;
113 resource Lua files parse; 3 inline scripts and 28 panel-render assertions pass.

### W1 · The permanent way back

**NOT RUN.** Join or reconnect with no active entry. PASS when the persistent middle-left Race Guide card reads
`Races are running tonight · F6 Race Guide · New here? /ncm help`. `/ncm help` must be visible without relying
on the one-time welcome toast or chat history.

### W2 · Help is accurate and repeatable

**NOT RUN.** Run `/ncm help` twice, then `/ncm lost`, `/ncm docs`, `/ncm.help`, `/ncm.lost`, and `/ncm.docs`.
PASS when each prints the same six private `[NCM]` lines covering car issue/return, F6 Guide, session-aware GPS,
F10 Collection/discovery, alpha framing and the repeatable command. No broadcast and no toast flood.

### W3 · First contact points home

**NOT RUN.** With a newly minted identity, confirm the one-time alpha toast and its final chat instruction both
name `/ncm help`; reconnect and confirm the first-time welcome does not repeat, while the persistent card remains.

## V. Season identity foundation (IDEA-191/L100)

**Offline PASS; not deployed.** The complete gate is 181/181 core tests under Lua 5.4 and LuaJIT; 113 resource
Lua files parse; 3 inline scripts and 28 panel-render assertions pass.

### V1 · Calendar-quarter resolution

**PASS (offline, 2026-09-22).** `test_seasons.lua` covers Dec 31 → Jan 1/year change, Mar 31 → Apr 1,
Jun 30 → Jul 1, Sep 30 → Oct 1, leap-year February, dates inside all four quarters, strict ID parsing,
half-open bounds and exact 00:00:00 UTC authority. `test_calendar.lua` proves posted events carry `seasonId`.

### V2 · Discovery seasonal/all-time seam

**PASS offline; live query NOT RUN.** The same immutable discovery rows produce all-time and bounded standings.
After deployment run `ncm.inspired`, `ncm.inspired season`, and `ncm.inspired 2027-S2`. PASS when the named
windows use canonical bounds and the all-time result remains unchanged.

### V3 · Closure/recovery

**NOT BUILT / NOT RUN.** Deferred until championship-edition persistence exists. Its future gate includes a
missed-boundary startup, replay and concurrent finalization, one immutable final classification, and no duplicate
settlement. The identity foundation does not mark closure complete.

Opened 2026-09-21. This is the single live-validation document: everything Batch 1 still owes plus every Batch 2
feature as it lands. Run it as one pass — solo (Session A), two clients (Session B), regression (Session C) — log
PASS/FAIL in the Results table at the end and move on; only an everything-blocker interrupts. Feature sections are
added at build time with the same shape as Batch 1: what, files, offline proof, live script with exact commands and
pass lines. Batch 1's original scripts stay in [BATCH-1.md](../archive/wp/BATCH-1.md); their *remaining* steps are copied here.

Offline gate (before any deploy): `powershell -NoProfile -ExecutionPolicy Bypass -File tools\ncm-test.ps1`
(core under Lua 5.4 + LuaJIT, `luac -p` over every resource file) and every `tools\ncm-stub.lua` scenario.

Timing rule for staging: street cadence sprints run at :00/:20/:40 UTC and `ncm.tp <pid> venue` targets the
soonest event — post test events at :02–:14, :22–:34 or :42–:54 UTC.

Cheat sheet: **F6** race guide · **F9** messages (was F7) · **F8** race graph · `/ncm.q a|b|c|d` · `/ncm.inbox` `/ncm.read <n>` `/ncm.accept`
`/ncm.decline` · `/ncm.profile` · `/ncm.telemetry on|off` · `/ncm.gps` (session-aware) · `/ncm.au …` venue
authoring · Warden: `ncm.event.post <route> <min> [sprint|weekend|tworace] [laps]`, `ncm.invite <pid> [team]`,
`ncm.accept <pid>`, `ncm.tp <pid> venue|<pid>`, `ncm.car <pid> <Class> [team]`, `ncm.telemetry`, `ncm.race`,
`ncm.rc.*`. (Batch 2 adds `/ncm.guide`, `/ncm.interest <n>`, `/ncm.practice`, `ncm.scenario …`, `ncm.state`,
`ncm.warp`, `ncm.lights now`, `ncm.incident`, `ncm.trace`, `ncm.world reset` — sections below as they land.)

---

## Part 1 — Batch 1 leftovers (staging = deploy 7, 2026-09-21 16:35 UTC, with all of Batch 2)

Already PASS in BATCH-1.md and not repeated: §5 vocabulary, §1 questionnaire, §2 inbox (incl. the accept guard),
§4 dressing (incl. dressUp at accept / dressDown at retire), §3.1 REPORT TO GRID, §8.1–4 up to a formed race.

### 1.1 Grid reveal: hold-E warp (B1 §3.2) — solo

1. `ncm.event.post troll 6 weekend` → `ncm.invite 1 kimiko` → **F9** ACCEPT → `ncm.tp 1 venue`. (Messages moved F7 → F9 in the Batch 2 fix pass, §2.6 — F7 collided with the camera toggle.)
2. Qualifying forms at T-60: the RB15 stands at the line; walk to its ring (`YOUR CAR · #7 Kimiko`), **hold E**.
   **PASS** = log `yourCar player=1 vehicle=… -> true` and you are in the seat. If chat says `Your car is #7 at slot 1
   — get in`, note *warp FAIL, prompt PASS* and get in by hand.

### 1.2 Weekend to the flag (B1 §8.3–4 end-to-end) — solo, same event

3. Quali open: strip `QUALI · one run · cross the start when ready`; cross once → run → finish → chat `Qualifying: …`
   and log `COMPLETE … kind=quali reason=all_runs_done`. A second crossing of the start is refused (`no_runs_left`).
   **PASS**.
4. Result strip: `race in 2:00 — go to the start line · your grid slot comes from this result`, gold marker + map
   route to the start. **PASS** = you can follow it without knowing the venue.
5. Race forms (`FORMED … kind=race … grid from quali`): chat `Grid is forming … Your car: #7 … slot 1`, ring,
   hold E, lights, race to the stadium, results board (≤ 15 s), then the strip. **PASS**.

### 1.3 Live graph (B1 §7.4) — during 1.2's race

6. Graph strip visible at the bottom of the HUD during the race (one dot, Kimiko colour); **F8** hides, **F8** shows.
   **PASS**.

### 1.4 Telemetry (B1 §6) — during 1.2's race

7. Warden `ncm.telemetry` while driving → `session=… received=N refused=0 | baremetaleven: 60 samples, last client
   …m`. **PASS** = `last client` and `refused=0` (the monotonic fix). Note the line.
8. Client log has `telemetry fields: …` once — paste the field list. **PASS**. Fallback (no such line): samples are
   position-only, `last server` — PASS with note.
9. After the race: `SELECT ncm_driver_id, COUNT(*) FROM telemetry_chunk WHERE session_id='<sid>' GROUP BY 1` ≈
   raceSeconds/10. **PASS** (±2).

### 1.5 Driver dimensions after a real finish (B1 §10) — after 1.2

10. Chat `Driver profile: SR … · clean sessions: 1 · ★ first finish …`; `/ncm.profile` → `Licence: ncx_formula
    rookie (1 clean) · SR … · rating ncx_rb15 … · clean_race, first_finish`. Rows in `driver_sr`, `driver_licence`,
    `driver_rating`, `accomplishment`. **PASS**. (The SR 5.00 → 4.50 seen on 2026-09-21 was two *object* incidents —
    the beached car and a wall, bands 2 and 3 — not the DNS no-shows: zero-fault scoring working as designed, and
    B1 §7.5 answered: object hits fire live.)

### 1.6 Two clients (B1 §8.5, §3.3–4, §7.1–3, §10) — Session B

Client 2 has no WebUI (KB-4): `tools\o77-client.ps1 -Profile ncm-tester2 -Name ncmtester2 -Server 52.60.225.137:11778`,
then in its dev console `resource.emit open77:shell:autoconnect 52.60.225.137:11778 alpha`; drive it from Warden
(`ncm.accept 2`, `ncm.tp 2 venue`, `ncm.car 2 …`).

11. `ncm.event.post tip 4 tworace` + invite/accept both → `PLAN … format=two_race sessions=2`. **PASS**.
12. Holding: client 2 away past T-5 → strip `holding · 1/2 on the grid · lights when 75% are in, or in 0:5x`, log
    `HOLD 1/2`; no lights before the deadline. Then `ncm.tp 2 venue` → countdown within ~2 s. **PASS**. (Alternative:
    leave client 2 away → green at ≤ T+60 with client 2 `DNS absent`.)
13. Race 1: on the first straight drive into each other at a clear speed difference → both `INCIDENT x2 · +4.0 s`
    toasts + banner, server `INCIDENT driver=… band=2 … other=…` ×2. **PASS** = both clients, same band.
14. Finish with the dirty car ahead on the road by less than its incident seconds → results: clean car P1, dirty car
    `(+4s inc)`. **PASS**. SQL: two `incident` rows same band; `session_result.corrected_ms/incident_ms/incident_count`.
15. After race 1: chat `Next: race 2 in N:00 — top 8 reversed`; race 2 forms with the race-1 winner at the back;
    `SELECT kind, ordinal, parent_session_id FROM session WHERE event_id='…'` → 2 rows, second with a parent. **PASS**.
16. `driver_sr` rows for both drivers after race 1. **PASS**.
17. Wall test (optional): hit a barrier hard alone → `INCIDENT x1 (object)`. Note whether it fires.

### 1.7 Street regression — Session C

18. A street sprint from the cadence: at `entry_open` drive to the venue, hold E at the prompt (or `ncm.enter 1`),
    race, results, `/ncm.results`, `/ncm.best`. **PASS**. Run `/ncm.ride` once if time allows (TW1 mode only).

---

## Part 2 — Batch 2 (sections added as each feature is built)

### 2.1 Race Guide: browse, interest, practice (P47, P48, P52)

**What.** **F6** (or `/ncm.guide`) opens the Race Guide: every posted event, numbered, with tier, discipline/format,
route, venue → finish, distance, countdown, "entries open in", how many are on the list / entered. **GET ON THE LIST**
(`/ncm.interest <n>`) is the ordinary entry: a soft list — the map routes you to the venue, practice opens for that
event at once, and at the line (from 15 min before) your entry becomes the physical one under the same id. Leaving the
list: the button again or `/ncm.withdraw`. Practice (`/ncm.practice` for the board): cross the start whenever you like,
unlimited runs, best time on the event's leaderboard, closes the moment the event's first session forms. Invitationals
(NCX) show *by invitation* and take no interest — the seat offer is their entry.

**Files.** core `competition/guide.lua`, `session/practice.lua` (+ `session/quali.lua` join/close, `competition/entry.lua`
upgrade); league `server/guide.lua`, `server/schema/010_guide.lua`, `race.lua` (practice sessions, `GlobalState.ncmPractice`),
`calendar.lua` (upgrade, counts); world `client/panel.lua` + `web/panel.html` (guide page, F6), `client/race.lua`
(`pickView`, `ncm:guide.route`), `client/telemetry.lua` (`NcmClientView`).

**Offline.** `test_guide.lua` (rows/tier/counts, practice window, interest → upgrade → rejoin, practice join/leaderboard/
close); stub `guide` (list → interest → route + practice → run → board → second driver joins/withdraws → venue check-in
upgrades in place → practice closes `session_forming` → race forms with one driver), `guide2` (interest alone never
forms a grid; practice closes `no_entrants`).

**Live (solo, any time — the cadence is always posted).**
1. Press **F6** → the Guide lists the next street sprints (≥3 rows, `street` tag, countdowns ticking). Boot log
   `migration 010 guide applied`. **PASS**. Chat twin: `/ncm.guide` prints the same rows numbered.
2. Click **GET ON THE LIST** on row 1 → chat `You're on the list: … Practice is open: cross the start line whenever
   you like.`, toast `ON THE LIST`, the map routes to the venue (kick only on foot), log `INTEREST player=1 …` and
   `PRACTICE open session=… event=…`. The row turns green with `ON THE LIST · leave`, `1 on the list`. **PASS**.
3. Drive to the venue: HUD strip `PRACTICE · best -- · no run · cross the start`, gold marker at the line, map route
   to it. Cross → `RUN STARTED`; finish → `RUN 0:xx · best …`, chat `Practice: P1 of 1 timed · best … · 1 run(s)`.
   `/ncm.practice` → the board. Second run allowed. SQL `SELECT * FROM practice_run` → one row per run. **PASS**.
4. F6 again: the row shows `practice best 0:xx`. **PASS**.
5. `/ncm.withdraw` → `Off the list …`, row back to GET ON THE LIST, the practice HUD goes; `/ncm.interest 1` again →
   back on (same entry id: `SELECT entry_id, state FROM entry WHERE event_id='…'` shows one row). **PASS**.
6. At `entry_open` (T-15) hold E at the venue prompt (or `ncm.enter 1`) → chat `You're in …`, log `ENTERED … (from
   interest)`; the row shows `CHECKED_IN`. **PASS**. At T-60 the log shows `PRACTICE closed … reason=session_forming`,
   chat `Practice closed (session_forming): P1 of 1 timed · best …`, then `FORMED … entrants=1`. **PASS**.
7. Negative: interest on an NCX invitational row is not offered (button says *by invitation*); `/ncm.interest <ncx row>`
   → `That one is by invitation …`. **PASS**.
8. Two clients (Session B): both interested in the same event → both practise; each sees P1/P2 relative to the other
   in `/ncm.practice`; withdraw of one leaves the other's board intact. **PASS**.

### 2.2 Host kit: scenarios, authored routes, every discipline (L63)

**What.** Warden `ncm.scenario <discipline> <route> [format] [in <min>] [laps <n>]` posts an event and enters
**everyone connected** as checked in (no venue walk, no invites): `gt|street|road`, `badlands|quad`, `rally`, `drift`,
`drag`, `oval`, `time_attack`, or `ncx|formula` (which keeps the invitational's seat offer + team car and auto-accepts
for everyone). `ncm.scenario restart` re-forms the same field on a fresh event ~90 s out; `stop` ends it (cars back,
venue undressed, event closed); `field`/`status` lists who is where. Routes for the non-street disciplines are
**authored in-world**: `/ncm.ar start <key> [name]` at the line, `/ncm.ar gate [name]` at each checkpoint, `/ncm.ar
finish` (point to point) or `/ncm.ar loop` (a ring: start = finish; ovals), `/ncm.ar list|del|tp <key>`. Every line
of the server log for a scenario carries its id (`S1`, `S2` …).

**Files.** core `data/nodes.lua` + `data/roots.lua` (`register`), `course/routes.lua` (intermediate gates, path
length), `competition/discipline.lua` (authored gates ride along; quad/rally/drift enabled); league `server/scenario.lua`,
`schema/011_host_kit.lua` (`custom_route`), `race.lua` (`abortEvent`, `lightsNow`), `organized.lua` (`acceptFor`,
`clearOffers`); world `server/main.lua` (`ncm:warp`, `ncm:worldReset`), `garage.lua` (`returnAll`), `pickup.lua` (`clearAll`).

**Offline.** `test_competition.lua::authored_routes_register_and_carry_their_gates`; stub `hostkit` (post + enter,
lights now, injected incident, rules off/on, trace, restart, stop, authored ring → oval with 2 laps, world reset).

**Live.**
1. Warden `ncm.scenario gt troll in 2` → log `S1 POSTED … entered=1`, chat `S1: Scenario · Street Sprint · Troll Pass
   … You're entered. Start in 2:00`, map routed to the start. **PASS**. At T-60 `FORMED … entrants=1`; `ncm.scenario
   field` lists you with `checked_in`, car, distance. **PASS**.
2. `ncm.lights now` while forming → chat `Race control: lights now.`, countdown starts within a tick wherever you
   stand. **PASS**. Race it to the flag.
3. Author a ring: drive to a roundabout; `/ncm.ar start ring1 Test Ring` at the line, three `/ncm.ar gate` around it,
   `/ncm.ar loop` → chat `Route saved: Test Ring (ring1) · 3 gate(s) · N m · loop`; `/ncm.ar list` shows it. **PASS**.
4. `ncm.scenario oval ring1 laps 2 in 2` → strip shows `L1 · gate …` names as you lap; the finish is only on the last
   line; result after 2 laps. **PASS**. Then `ncm.scenario drag <strip> in 2` on an authored straight (2 gates) and
   `ncm.scenario badlands <route> in 2` on an authored Badlands stage with 2+ gates. **PASS** each = forms, runs, results.
5. `ncm.scenario restart` mid-race → old session `aborted`, chat `S1 stopped (restart)`, then `S2: …` with the same
   field, forms 30 s later. **PASS**. `ncm.scenario stop` → no session, event closed, your car returned. **PASS**.
6. `ncm.scenario ncx troll weekend in 3` → seat offer accepted automatically for everyone, RB15s at the line at T-60
   of qualifying. **PASS**.
7. `ncm.world reset` at any point → sessions ended, cars gone, props/NPCs gone, chat `World reset by the host`; then
   `ncm.scenario …` again works **without a server restart**. **PASS**.
8. Two clients: `ncm.scenario gt troll in 2` enters both; `ncm.warp 2 start` moves client 2 to the line; `ncm.spectate 2`
   takes it out (DNF/left, HUD releases); `ncm.kick 2` disconnects it (if the platform has `players.kick`). **PASS**.

### 2.3 Host kit: state, incidents on demand, tracing, warps

**What.** `ncm.state` dumps every session (phase, hold, per driver: state, progress, best, incident seconds, last
telemetry age and witness); `ncm.incident <pid> <band> [car|object]` injects an incident that lands on the driver like a
real one (toast, corrected time, `incident` row); `ncm.rules incidents off|on` disables/enables the telemetry scan for a
staged contact; `ncm.trace <pid> on` logs every gate report and telemetry batch of that driver; `ncm.warp <pid>
start|finish|grid|<pid>|x,y,z` moves a player (dismounting first); client `/ncm.debug` shows what the client believes
(banner + log line).

**Live.**
9. During any race: `ncm.state` → one block per session, one line per driver. **PASS** = readable at a glance.
10. `ncm.incident 1 2` → toast `INCIDENT x2 · +4.0 s`, strip/graph update, `incident` row with `kind=car`. **PASS**.
11. `ncm.rules incidents off`, drive into the other car → no incident; `on` → the next contact scores. **PASS** (two clients).
12. `ncm.trace 1 on`, cross a gate → log `TRACE gate report … via=client|stream` and `TRACE telemetry … batch=5 ok=true`. **PASS**.
13. `/ncm.debug` on a client → banner `DEBUG · running · racing · next finish 412 m · gps race gate 2` and one log line. **PASS**.
14. `ncm.warp 1 finish` → moved (fade), chat `Moved: host warp finish`; `ncm.warp 1 grid` back to the slot. **PASS**.

### 2.4 Gates from the telemetry stream (no reverse crossings)

**What.** The server now captures crossings itself from consecutive telemetry samples (segment crossing of the next
gate's line; the race start also counts "left the mark" 30 m from where the car sat), whether or not the client
reported; both witnesses log `gate OK … via=client|stream`. A first pass over the line at speed is enough.

**Live.**
15. Practice or race: cross the start once at speed, straight through → `RUN STARTED`/green within a tick; log shows
    `gate OK … via=stream` and/or `via=client` — never a second crossing needed. **PASS**. Repeat 3× with `ncm.scenario
    restart`. **PASS** = 3/3.

### 2.5 Rolling start (owner ask 2026-09-21)

**What.** A start type on the event: `ncm.scenario <discipline> <route> rolling [formation <m>] [pace <kph>]` or
`ncm.event.post <route> <min> [format] rolling`; ovals roll by default (P41). The lights release the roll-out; the
field crosses the start in grid order behind the pole car under the pace cap (80 km/h default, +10 % slack) to a
**green gate** the host places `formation` metres along the course (300 m default). The first car through the green
gate drops the flag for everyone and starts the race clock. Faults are incidents of kind `formation` (band 1, +2 s):
passing a car that started ahead of you before the green; over the cap during the formation (from the telemetry
stream, once per driver). No restarts. HUD: `FORMATION · P2 · hold your place · under 80 km/h · 212 m to the green
flag`, then a `GREEN FLAG` banner; the green gate is marked in green.

**Files.** core `session/race.lua` (rules `start/formationM/paceKph/formationBand/formationSec`, green gate in
`report`, `pace`), `competition/discipline.lua` (`withGreenGate`); league `competition.lua` (`rulesFor` start type),
`race.lua` (course with the green gate for races only, GREEN FLAG / fault announcements, `incident` rows kind
`formation`), `telemetry.lua` (pace from samples), `organized.lua` + `scenario.lua` (`rolling` keyword);
schema 011 (`incident.kind` + formation); client `race.lua` (formation strip, banner, green marker).

**Offline.** `test_race.lua::rolling_start_green_at_the_leader_and_formation_faults`; stub `rolling` (formation over
pace → incident; second car takes the green first → green for all + passing fault; clean pole car wins on corrected
time), `hostkit` (an authored ring rolls by default with the green gate 300 m in).

**Live (two clients).**
16. `ncm.scenario gt troll rolling formation 200 pace 60 in 2` → both entered; at green lights both roll out; strip
    `FORMATION · … under 60 km/h · N m to the green flag`; green marker ahead. **PASS**.
17. Client 2 (behind on the grid) overtakes before the green → both get `GREEN FLAG` when the first car crosses; client 2
    gets `FORMATION · +2.0 s passed before green`; log `GREEN FLAG leader=…`, `FORMATION FAULT …`. **PASS**.
18. Repeat (`ncm.scenario restart`) with client 1 driving 90 km/h in formation → `FORMATION · +2.0 s over pace` once,
    `incident` row `kind=formation`. **PASS**.
19. Race to the flag: times start from the green, not the lights (compare `green_at` in `session` with the GREEN FLAG
    log time); corrected time carries the faults. **PASS**.
20. `ncm.scenario oval ring1 laps 2 in 2` → rolls by default: green gate after ~300 m of lap 1. **PASS**.

### 2.6 Fix pass (carried from the QA docs)

**What.** Messages moved to **F9** (F7 collided with the camera toggle); the inbox reads as a phone thread and shows
open messages plus only the last 6 h of resolved ones (older stay archived); grid cars take their ground z from a
player standing within 80 m of the slot (KB-17 — authored routes already carry a true z); the resolved
`Open77.npcs.damage` member is logged once (KB-13); the SR item was a misdiagnosis (object incidents, by design).

**Live.**
21. **F9** opens Messages, **F7** does nothing NCM-wise; the thread shows bubbles, sender line, state; old resolved
    offers from earlier days are gone. **PASS**.
22. `ncm.scenario gt gt1 in 2` while standing at the Hanford Overpass line → the car spawns on the road, not in the
    air; log `grid car #… z from a player N m away`. **PASS**.
23. After `/ncm.au dress npc …` the log shows `npcs.damage.<name> = <n>` — write the name into KB-13. **PASS**.

---

### 2.7 OPEN//77 weather authority / KB-6 retest

**Live (two clients, op77.87).** Force all eight supported presets; observe a natural scheduled change; disconnect
and rejoin one client during a long transition; place both clients in an overridden bucket; split them between
override/default; reunite them in default and clear the override. At every capture compare scope, epoch, global and
weather revisions, preset, transition and scheduler timing against canonical server state.

24. W1–W8 in `wp/OFFLINE_TEST_QUEUE.md` — **PASS 2026-09-22**. Both clients followed every forced/natural state,
the rejoining client entered the active transition at its current point, bucket isolation/reacquisition worked, and
the cleared bucket returned `unknown_bucket`. No unexplained divergence. Evidence: [E26](../archive/experiments/E26_2026-09-22_weather-sync.md).

### 2.8 NCM Weather Service

**Built, not live-validated.** Migration 013, the persistent seven-day default-world plan, slower policy,
OPEN//77 reconciliation, bounded observations, 24-hour forecast read model and provenance seam are implemented.
Run §X in `wp/OFFLINE_TEST_QUEUE.md`; only then may this row become PASS.

### 2.9 Vehicle Collection — IDEA-134 / L89

**Discovery and provenance are live-validated; the rest is not.** Deploy 13 (2026-09-22 23:58) applied migration
014 cleanly and `[ncm_league/collection] ready generation=1 vehicles=27 radius=18.0m dwell=3s`. Generation 1
published 27 declared / 27 members.

Two clients, 2026-09-23 00:17–00:18, one Caliburn issued via `ncm.car`:

| Check | Result |
|---|---|
| §T1 discovery fires | **PASS** — toast plus `DISCOVERED` log line |
| §T2 source recorded | **PASS** — `source_driver_id` is the holder, `source_holding=issued` |
| §T3 credit not rewritten | **PASS** — `encounter_count` 1→2, source unchanged |
| §T4 no self-credit | **PASS** — the holder's own discovery has `source NULL` (`credit` refused: `self`) |

The owner's report of *one* toast and none afterwards is the pass condition for §T3, not a fault: feedback fires on
first discovery only. `encounter_count` reached 2 rather than 4 because a pass must hold ≤18 m for three
consecutive one-second samples — quick drive-bys correctly do not count.

**Not yet run:** §T5 (`ncm.inspired` standings), §T6 (partial-generation recovery, KB-55), §T7 (unreadable-collection
refusal, KB-54), and the [E27](../archive/experiments/E27_2026-09-22_vehicle-collection-encounter.md) false cases — far,
wrong bucket, unstreamed, ambient traffic, and reconnect/restart persistence. The F10 roster wall is also unverified.

### 2.10 Readiness watchdog — KB-60

*(Labelled §AD, not §R. `OFFLINE_TEST_QUEUE.md` already owns **R** for the platform .87 upgrade — and its
**R4 · KB-39 readiness latch in .87** is adjacent enough to §AD2 to be genuinely confusing. The two QA
documents share ONE letter namespace: OFFLINE defines the items, this file records the live results.)*

**Offline-green, not deployed.** 159/159 core tests on Lua 5.4 and LuaJIT (15 of them new, in
`test_readiness.lua`, the first written against Trip[ABK]'s exact session); 108 resource Lua files parse.

The thing under test is a watchdog, so the test is *does it fire, and does it stay quiet otherwise*. Both halves
matter: a watchdog that cries during every healthy join is worse than none.

| | Check | How | Pass condition |
|---|---|---|---|
| §AD1 | the sweep starts at all | read the log after deploy | **PASS — deploy 19, 2026-09-23 01:35:09 UTC:** `readiness: sweep every 5s over the connected list (KB-60); adopted 0 player(s); platform stage listener=on`. `world.readiness` is in the started-module list; zero script errors; **1 readiness line in the whole boot** on an idle server, which is the first evidence for the §AD2 quiet half |
| §AD2 | a healthy join is silent | join normally, stay 6 min | **PASS — deploy 21, on a real visitor.** `A` (player 2 then 3) joined twice, 03:02:34–03:26:23 and 03:28:20–04:02:13, ~58 min total: **zero `readiness:` lines of any kind**, zero platform heartbeats, zero script errors. Better evidence than the owner's own join, and it clears KB-64. *(Earlier — deploy 19, 01:38:20 — this FAILED:* The owner's own normal join was warned at 47 s and told to reconnect; it became "playable" at 63 s. Both numbers were NCM's `staleStageS` timer, not the player's state — the platform heartbeat fired once at 17 s and stopped. Logged as KB-64, fixed in deploy 20.)* | The 9 quiet minutes after they became playable did pass. **Re-run after redeploy** |
| §AD3 | the advise path fires on a real player | `ncm.readiness.test <pid> appearance_failed` | **PASS — 01:47:36 injected, 01:47:47 warned at 10 s:** `CANNOT PLAY (ncm-ready=yes in-world=yes platform-stage=appearance_failed)`. Owner confirmed **the chat line and the yellow warning toast on the client**. `in-world=yes` is KB-60 reproduced and caught. Bonus: a typo'd stage (`appearanxe_failed`, 01:47:20) was refused — `'appearanxe_failed' is not a stage the appearance shell reports` — so the unvalidated-client-string guard works live |
| §AD4 | terminal wording differs from slow | compare §AD3 against `ncm.readiness.test <pid> appearance_applying` | **PASS — 01:48:14 injected, 01:48:48 warned.** Owner confirmed the wording differed between the two |
| §AD5 | it recovers by itself | wait ~45 s after §AD3 without touching anything | **PASS — 01:49:03:** `reached a playable world after 85s`, then silence. Injected at 01:48:14, stale at +45 s, recovered 4 s later. The evidence expires rather than latching |
| §AD6 | the readout is honest | `ncm.readiness` with two clients connected | **PASS (one client) — 01:48:59:** `player=1 name=easporks PLAYABLE (ncm-ready=yes in-world=yes platform-stage=none) waited=82s warned=2`. Two-client case not run |

**§AD7 — PASS, and it arrived unprompted (01:37:49):** `readiness: platform stage listener is live (first report: player=1 stage=appearance_applying)`, fired by a **genuine** platform report on the owner's own join, alongside the matching `[OP77-INIT-002]` line from `open77_appearance`. **A second resource can listen to that net event** — the one real uncertainty in the KB-60 design, settled by evidence rather than assumption, and settled on the first join after deploy. The stage half of the watchdog is live, not merely registered.

### 2.11 Asset-keyed ownership — IDEA-157 / migration 015

**Offline-green, not deployed.** 173/173 core tests on Lua 5.4 and LuaJIT (10 new in `test_vehicle_assets.lua`);
111 resource Lua files parse. Migration 015 was applied and exercised against the **real MariaDB 10.11** in a
throwaway schema (`ncm_m015_check`, since dropped; `ncm` untouched): statements apply clean, the backfill is
idempotent under replay, `acquired_via` survives it, three examples of one record coexist, and the FK refuses an
orphan owner with `ERROR 1452`.

`owned_vehicle` currently holds **0 rows** on staging, so the backfill is a no-op and this is the cheapest this
migration will ever be.

| | Check | How | Pass condition |
|---|---|---|---|
| §U1 | the migration applies | deploy, read the log | **PASS — deploy 21, 2026-09-23 02:26:53 UTC:** `migration 015 vehicle_assets applied (2 statement(s))`, `ownership ledger ready (asset-keyed, IDEA-157)`, zero errors. `vehicle_asset` exists with PK `asset_id` and all three indexes; `owned_vehicle` retained as rollback (0 rows, so the backfill was correctly a no-op) |
| §U2 | a garage still reads | `ncm.grant <pid> Sport` then `ncm.garage <pid>` | one line per example, each with an 8-char asset id, `key=` and `via=seed` |
| §U3 | **grant stays idempotent** | run the same `ncm.grant` again | `granted 0 new, N already held` — a second seed must not double the garage. This was free when the key was the record and is now a deliberate choice |
| §U4 | **two of one car**, the point of all this | `ncm.mint <pid> <record> 2` then `ncm.garage <pid>` | three examples of that record, three **distinct** asset ids, `N example(s) across M model(s)` with N > M |
| §U5 | a spare is not a second option | with two of one legal car, open the Guide (F6) | the car line's "I own" count is unchanged by the duplicate. This is the defect the migration would have introduced |
| §U6 | the Collection counts machines, not copies | `/ncm.collection` with duplicates held | OWNED is unchanged by the spare — three of one car is one completed slot |
| §U7 | vehicleKey backfill | restart, read the log | `vehicleKey backfill: N resolved, M left NULL` once, then never again (new assets carry their key from mint) |
| §U8 | disposal is per example | `ncm.dispose <assetId>` on one of the duplicates | that asset only; the others remain. Then `ncm.revoke <pid> <record>` removes the rest |
| §U9 | survives a restart | restart, `ncm.garage <pid>` | identical asset ids. They are durable identity or they are nothing |

**Rollback:** `owned_vehicle` is left in place and unread. If §U fails, the old table is still there; nothing
has been renamed or dropped. Dropping it is a one-line follow-up migration once §U passes (IDEA-188).

### 2.12 Race Guide information layer — IDEA-124 / IDEA-125 / 11_WEATHER.md

**Built, offline-green, not deployed.** The car requirements, regulations and weather forecast have ridden in the
Guide payload since deploy 12 with nothing drawing them. This is the client half.

**How the KB-59/61/63 minefield was avoided — by construction, not by care:**

| Limit | Why it cannot bite here |
|---|---|
| KB-59 oversized **net** payload | **zero new payload fields.** `guide.lua` diffed against the live copy: the only change is IDEA-157's `iOwn`, a value not a field |
| KB-63 silent `page:send` drop | same — batch contents unchanged, `ROWS_PER_CHUNK` untouched |
| script execution budget | **no Lua changed.** `client/panel.lua` is byte-identical to the deployed copy |
| KB-61 panel never draws | `guard()` emits `panel:drawn` only if the render does not throw — so every new field is treated as optional, and that is now **enforced by a test** |

**New permanent gate: `tools/panel-render-check.js`**, wired into `ncm-test.ps1`. It stubs a DOM, loads the real
`glyphs.js` and the real inline script, pushes ten payload shapes through the actual render, and asserts
`panel:drawn` fired with no `panel:error` — plus 18 content assertions. **It caught a genuine `guideWx is not
defined` before deploy**, which would have been a panel that never drew, watchdog close, no error anywhere: the
exact KB-61 signature that cost four deploys last time. Negative controls confirmed it fails on an induced throw
and on a percentage appearing in the weather UI. 28 assertions, 0 bad.

| | Check | How | Pass condition |
|---|---|---|---|
| §S1 | authored route descriptions | open F6, select an event | the authored prose, not the generated "street sprint from X to Y" (was runnable before this change) |
| §S2 | what car to bring | select any event | **WHAT TO BRING** block: the eligibility summary plus **YOU OWN N OF THESE** |
| §S3 | the refusal is stated up front | an event the driver has no legal car for | **YOU OWN NONE** and *ENTER RACE WILL NOT BE OFFERED* — L83 refuses rather than substitutes, so it must be learned here, not at the venue |
| §S4 | regulations | select any event | **REGULATIONS** grid: tier, discipline, format, start, laps/field cap, plus the ruleset name flagged *(sporting rules not yet published)* |
| §S5 | weather ribbon | open F6 | current conditions + scope beside the clock, family-coloured |
| §S6 | per-event forecast | select an event inside the horizon | **CONDITIONS AT START** with **ordinal** confidence (HIGH/MED/LOW). **Any percentage is a FAIL** — 11_WEATHER.md defers numeric calibration |
| §S7 | absent weather draws nothing | select an event past the forecast horizon | no forecast block at all — **never a default "sunny"** |
| §S8 | honest unavailable | `ncm.wx` stop / service down | ribbon reads **WEATHER · UNAVAILABLE**, no invented icon. First consumer of `capabilities.weather`, which nothing read until now |
| §S9 | schedule cue | a race whose weather changes mid-event | small family glyph + **CHG** on the card |
| §S10 | nothing regressed | open/close F6 a few times, switch tabs | rows still draw, `panel drawn: guide` in the client log, no `panel:error` |

**Past Races weather stays deferred and that is correct** (11_WEATHER.md): it must read from the finalized event
envelope, not today's service, so it waits on settlement capture rather than on this work.

### 2.13 Onboarding unblock and the stuck venue panel — KB-66 / KB-67

*(Labelled §Y, not §V: a concurrent session claimed §V for Global Seasons and §W for the walk-in help
anchor in `NOW.md`. Two sessions are writing this file — check the letters in `NOW.md` before taking one.)*
**Deployed 23, 2026-09-23 04:39 UTC.**

> **§Y1–§Y7 (KB-66) WILL NOT BE RUN — owner decision, L102.** Chat commands are not an acquisition surface;
> the F6 Market is the onboarding path. The seed-grant stays deployed as an unverified safety net and
> nothing may be built on it. The steps are left here only so that, if it is ever revisited, §Y1's
> cross-resource risk is not rediscovered from scratch.

**§Y8–§Y10 (KB-67) are still live QA** — a defect the owner hit directly, unrelated to acquisition.

| | Check | How | Pass condition |
|---|---|---|---|
| §Y1 | **the event crosses resources at all** | `/ncm car Sport` in chat | **two** log lines: `[ncm_world/garage] issued player=…` **and** `[ncm_league/ownership] KB-66 seed grant driver=… record=… asset=… (1/8 seeded)`. The first without the second means host-wide `TriggerEvent` does **not** carry ncm_world → ncm_league, and the whole fix is inert |
| §Y2 | the player is told, and can act | same | chat: *"This one is yours -- you can enter it in races. Press F6 to find one."* |
| §Y3 | **the race actually accepts them** | F6 → an event that car is legal for | **WHAT TO BRING** reads **YOU OWN 1 OF THESE**, and ENTER/interest is offered. This is the whole point: before this, a visitor with a car was still refused |
| §Y4 | it refreshes immediately | watch the Guide while running `/ncm car` | eligibility updates without waiting for the next calendar publish (`refreshCompetitionViews`) |
| §Y5 | a re-issue is not a second grant | `/ncm car Sport` twice, same record | one `seed grant` line only; `ncm.garage <pid>` shows one example, not two |
| §Y6 | the cap holds | `/ncm car` across classes until 8 seeded | 9th says *"You have the maximum 8 starter vehicles… loaner"*, the car still spawns and drives, and no asset is written |
| §Y7 | seeded stays labelled | `ncm.garage <pid>` | every starter shows `via=seed` — the property that lets all of them be deleted when real supply lands, without touching an earned or bought car |
| §Y8 | **KB-67: the panel closes on race start** | hold E on `history` at a venue, then start a race | the panel goes away; log shows `venue: closed a left-open history panel (KB-67)` |
| §Y9 | and on walking away | open the panel, walk out of the venue radius | same — this was equally broken and equally unrecoverable |
| §Y10 | tap-to-close still works | open the panel, tap E | closes as before; the normal path must not have regressed |

**§Y1 is the one with real platform risk.** Every existing cross-resource `TriggerEvent` in NCM runs
ncm_league → ncm_world (`ncm:gridCars`, `ncm:venueDress`, `ncm:pickup`); this is the first the other way. It is
instrumented rather than assumed — a missing second log line is the answer, and the fallback is to move the
grant into ncm_league's own `/ncm` handling.

### 2.14 Machine Index foundation — IDEA-196 / migration 016

**Offline-green, not deployed.** 186/186 core tests on Lua 5.4 and LuaJIT; 116 resource Lua files parse;
3 inline scripts and 28 panel-render assertions pass. No Scanner or Market UI is included.

| | Check | How | Pass condition |
|---|---|---|---|
| §Z1 | migration and backfill | deploy, inspect migration log and query `vehicle_knowledge_evidence` | migration 016 applies once; every pre-existing discovery has exactly one `identity:<vehicleKey>` evidence row with its original time/source; restart adds none |
| §Z2 | physical discovery regression | encounter a still-unknown registered vehicle | one discovery toast says MACHINE INDEX; summary and evidence rows exist; another encounter increments only `encounter_count` |
| §Z3 | asset identity survives the seam | encounter an NCM vehicle registered with an `assetId` | evidence carries that persistent `assetId`; it never stores the live OPEN//77 vehicle/entity id as asset identity |
| §Z4 | Market reveal, when Market exists | view one model in actual primary stock | model becomes discovered with `source_kind=primary_market`, zero encounters and no source Driver; an absent-stock model remains `???` |
| §Z5 | retry safety | repeat the same reveal/restart path | still one discovery summary and one identity evidence row; no duplicate toast or Discoveries Inspired credit |

§Z4 is now implemented locally through authoritative visible Base Market stock; it still requires a live PASS.

### 2.15 Starter Market network boundary — IDEA-198 / L104

**Built locally; offline-green; not deployed.** These are the mandatory live implementation gates.

| | Check | How | Pass condition |
|---|---|---|---|
| §AA1 | Base is one market | inspect authored market/inventory payload | stable `base_market` identity is present on inventory; no singleton/global-shop storage or API |
| §AA2 | market-scoped query | request Base Market inventory | only assets assigned and available through `base_market` appear; canonical library and unscoped assets do not |
| §AA3 | no catalogue leakage | compare an unknown model absent from stock | it is absent from Market and remains `???` in Machine Index |
| §AA4 | legitimate reveal | view one actual stock row | that model is discovered through `primary_market`; no human source/Inspired credit |
| §AA5 | shared conservation | two clients attempt the last same stock asset | exactly one atomically purchases the existing `assetId`; no copy is minted and the loser gets a truthful stock refusal |
| §AA6 | retry safety | repeat purchase request/restart recovery | one debit, one transfer/history fact, one owner; never duplicate money, title or evidence |
| §AA7 | knowledge boundary | inspect F6 payload as a fresh Driver | Base Market is available; no undiscovered-market names, locked slots or total market count are disclosed |
| §AA8 | three independent gates | inspect an unaffordable or ineligible visible item | visibility, eligibility and affordability are reported as distinct facts/refusals |

### 2.16 NCM Help and in-game problem reporting — L105

**Deployed, 2026-09-23 13:43 UTC.** *(Labelled §Z. Claimed letters live in `NOW.md`; two sessions write this
file.)*

**The server is the support channel.** A player who hits a gameplay problem reports it from inside NCM — no
Discord handle, no GitHub account, no email, and no requirement that the owner is awake.

Offline: 196/196 core tests, 124 resource files parse, **54 panel-render assertions** (21 of them Help, run
against the real page with a stubbed DOM). The harness caught two defects before deploy — see §Z9.

| | Check | How | Pass condition |
|---|---|---|---|
| §Z1 | Help opens | `/ncm help` in chat | the Help panel opens; log shows `help requested by player=N (seq=1)`; two chat lines appear as the fallback trace |
| §Z2 | aliases work | `/ncm lost`, `/ncm docs` | same panel, `seq` increments each time — asking twice must REOPEN, not no-op |
| §Z3 | it is a real page | scroll it | orientation, active-development note, and the controls list scroll properly; no clipped content at the bottom |
| §Z4 | controls are true | compare against what you can actually do | every row is reachable; **the Market row appears only because the Market is loaded**. Nothing operator-only is listed, and `/ncm car` is absent (L102) |
| §Z5 | empty sections do not exist | look for headings | **no "Known problems" and no "Recently changed" heading at all** — nothing is authored yet, and an empty heading is the staleness this design avoids |
| §Z6 | report submits | type a sentence, SUBMIT | **PASS — 2026-09-23 14:03 UTC, first real report.** Owner: *"submission process was smooth."* Row `7a579673` stored, one row, acknowledged in the page |
| §Z7 | the context is useful | `ncm.reports` in the console | **PASS, emphatically — the snapshot alone diagnosed the bug with no follow-up question asked.** `garage{examples:1}` proved the car WAS owned, `market{balance:7500,offers:2}` proved the money moved and stock was consumed, `eligibility{refused:false}` ruled out an entry fault. That triangulation identified KB-68 as a **missing delivery step**, not a payment or ownership fault — from facts, exactly as section 7 requires |
| §Z8 | **it survives leaving** | submit, then disconnect; `ncm.reports` | the report is still there. This is the whole point for an unattended visitor |
| §Z9 | retry cannot duplicate | submit, then press SUBMIT again quickly | one row only. The page reuses its `reportId`; the server writes `INSERT IGNORE` on the primary key |
| §Z10 | refusals are honest | submit an empty box, and a one-word box | refused with a reason; **never "received"**. Nothing says received until the row exists |
| §Z11 | returns to gameplay | ESC | panel closes, input returns, `panel drawn: help in N ms` was logged on open |

**§Z9 note:** two real defects were caught pre-deploy by the render harness, not in the game. A missing
`.value` on the textarea would have thrown during render — meaning no `panel:drawn`, meaning the KB-61
watchdog closes Help, meaning **the recovery surface itself fails silently**. And on success the page cleared
the textarea by dispatching `input`, whose handler wipes the status line, so *"Report received"* was erased
the instant it appeared. Both are the class of bug that only shows up when somebody reports a problem twice.

**Not built, deliberately:** ticket status, replies, assignment, priorities, external integrations, chat
capture, screenshots, or any rendering of `KNOWN_BUGS.md` to players.

### 2.17 Base Market access follow-up — L106 / IDEA-199

**Built locally, not deployed by this session.** Staging package read: `2.31.13+op77.87`.
The older "not deployed" labels in 2.14/2.15 describe their original build sessions; migrations/Market/Help were
subsequently deployed. This follow-up independently read existing live state; it did not replay a purchase.
Historical §Z labels collide: references below use section numbers to disambiguate.

| Check | Result | Evidence / remaining procedure |
|---|---|---|
| §AB1 purchase and Help evidence | **PASS — live stored state read, 2026-09-23** | Report `7a579673-e592-4d3c-8a6f-e02c67a01c62` read in full. MaiMai asset `10000000-0000-4000-8000-000000000001` is owned via purchase; one -2500 debit and one primary_purchase history row; starter +10000, balance 7500; Galena/Hella available. This verifies current rows, not a new contention/restart test. |
| §AB2 identity display | **SQL PASS; new UI NOT RUN live** | Three distinct full UUIDs ending 0001/0002/0003 traverse payload unchanged. Old UI truncated to shared prefix 10000000. Full-ID render fixture passes; inspect cards in game after deploy. |
| §AB3 purchase → Index → CALL → drive | **NOT RUN live** | Buy a remaining asset from a location unsuitable for a car. No runtime appears at checkout; named success teaches F6/F10. Select specific owned asset, move to clear roadway, CALL, identify its logged asset/runtime mapping, enter and drive. Ledger/title/stock/history unchanged by CALL. |
| §AB4 placement and feedback | **NOT RUN live** | Probe on open flat road, parking, wall, narrow alley, steep slope, edge, stacked road, indoors, moving, seated and loading. Capture candidate/refused client logs and server outcome. No clear support/clearance means clean refusal; never blindly use player coordinates or offsets. Validate all three starter models' envelopes. |
| §AB5 idempotence / authority | **NOT RUN live** | Repeat/double CALL, retry delayed response, another player's assetId, disconnected/rebound source, missing DB, unsupported model. One runtime per asset, no persistent mutations; existing car not teleported/deleted while occupied. Two separately owned examples must remain two actions and two IDs. Offline adversarial fixtures pass. |
| §AB6 restart / reconnect / cleanup | **NOT RUN live** | Disconnect/rejoin retains existing runtime access without duplication. Resource stop/restart removes old representations; next call may recreate only the runtime of the same asset. Confirm native cleanup, title/stock/balance/history persistence and failure logging. |
| §AB7 shared-world geometry / streaming | **NOT RUN live** | Two clients observe the called car, including dynamic obstacles/traffic. Probe success is not proof of native stream-in or drivable geometry. Missing APIs or incompatible snapshot fields must refuse, never guess. |
| §AB8 shell / viewport / focus | **NOT RUN live** | All four panels show RACE GUIDE, MARKET, MACHINE INDEX, HELP in that order; navigate each direction, F10 direct, ESC releases focus. Fill Guide schedule/details and scroll: nav stationary, last content reachable. Test actual supported aspect ratios. Offline render assertions pass. |
| §AB9 success / Help copy | **NOT RUN live** | Purchase stays on Market; notification names car and points to Machine Index. Help's "I bought a car" answer describes ownership and specific-asset CALL. |

Offline: normal gate **196 core + 28 access tests per interpreter** (Lua 5.4/LuaJIT), **126 resource Lua files**,
**3 inline scripts**, **67 panel assertions**. `ncm-build.ps1 -Check` clean. Extra legacy
`ncm-stub.lua guide` **FAILS** obsolete Street Sprint first-row fixture and lacks weather environment support
(KB-71); it is not counted as passing. No fresh migration/concurrency proof was needed: transaction SQL/schema
are unchanged. Captured platform contracts: [research evidence](../../research/open77/evidence/2026-09-23-access/README.md).

### 2.18 Call Vehicle, and reaching a start line — KB-72..76 / L107 / L108

**Deployed 2026-09-23.** *(Labelled §AC: §AA and §AB were already claimed by the Market/access session. Claimed letters live in `NOW.md`.)* Offline: 197 core tests,
32 vehicle-access assertions, 67 panel-render assertions, 126 resource files parse.

| | Check | How | Pass condition |
|---|---|---|---|
| §AC1 | **a car actually arrives** | Machine Index → select an owned machine → CALL VEHICLE, standing on an ordinary road | the car appears. Log: `CALL requested`, then `materialized asset=…` |
| §AC2 | the button reacts | watch it during §AC1 | amber **CALLING…** on press, then **green** with a message. Never silent |
| §AC3 | failure is legible | call from inside a tight alley or against a wall | **red**, with a reason — *"no clear space around you"*, *"the ground is too uneven"* — not a generic refusal |
| §AC4 | a road divider works | the exact spot from the report: centre divider of a four-lane road | placed. This was the case that could never succeed (KB-74) |
| §AC5 | the fallback holds | call where the probe cannot run | log shows `falling back to kerb placement`; a car still arrives. Call Vehicle must never be worse than `/ncm car` was |
| §AC6 | **the ring is YOUR race** | express interest in 3 races, none of them the soonest on the server | ring, card and `/ncm.gps` all point at **your soonest entry** (KB-75) |
| §AC7 | withdrawing one keeps the rest | withdraw from one of the three | ring moves to your next live entry; it does **not** vanish |
| §AC8 | gps skips elapsed races | `/ncm.gps` with no live entry | routes to the soonest race that has **not started**, never a past one |
| §AC9 | **the whole menu is always visible** | stand at a venue in any state | all five options render; inapplicable ones greyed **with a reason** (L108). A card showing only HISTORY is a FAIL |
| §AC10 | greyed options are inert | tap-cycle and hold E | cycling lands only on pressable options; holding E on a greyed one explains itself and does nothing |
| §AC11 | **ENTER RACE when eligible** | stand at your race's start line, entries open, with a legal car | ENTER RACE is offered and works. This is the end-to-end case the whole session was chasing |

**§AC11 is the one that matters.** Everything else is in service of a driver being able to start a race.

## Results

| Item | Status | Notes |
|---|---|---|
| 1.1 hold-E warp | **PASS** | `yourCar player=2 vehicle=4294967297 -> true` 17:49:45. Also PASS: invite→F9→accept (single `ACCEPTED`, no double-fire) and `ncm.tp 2 venue` (correct venue once ours was soonest — KB-19 as characterised). Note pid was **2**, not 1 (KB-20). |
| 1.2 weekend to the flag | **PASS** | Quali `COMPLETE … all_runs_done | P1 [KIM] baremetaleven best 1:04.964`; race `FORMED … 2/2 … grid from quali`, `GREEN at 1790013034.082`, `COMPLETE … all_classified | P1 0:40.000`; retire clean (car returned, venue dressDown removed=8). Owner: "better than earlier testing." Defects: KB-22 banner duration, KB-23 suspiciously round race time. |
| 1.3 graph + F8 | **PASS** | Live timing graph visible by default during the race (owner). Needs UI polish to look right — logged as IDEA-055, not a defect. |
| 1.4 telemetry | | fields: |
| 1.5 dimensions after a finish | **PASS (readout) / FAIL (semantics)** | `/ncm.profile` renders: `Licence: ncx_formula rookie (1 clean), street_sprint rookie (0 clean) · SR 4.55 (2 incidents, 1 clean) · rating — · clean_race, first_finish×2, first_win×2`. Readout works. **`first_win×2` on two solo races — IDEA-001 is not an edge case, it is the normal path.** `rating —` confirms the `fieldSize > 1` guard already works, so the fix is narrow. Also KB-26 (licence row for an unraced discipline). |
| 1.6 two clients: tworace / holding / incidents / SR | **PARTIAL — reconstructed, not run to the sheet** | A two-human race did happen (2026-09-22, session `9dba7550`), but it was not driven from this sheet and no step-by-step record was kept, so **items 11, 12, 14, 15 and 17 remain unrun** — the owner must confirm them. What the defect records do evidence: **item 13 FAIL** — contact was detected and scored but **never attributed**; all seven incidents logged `kind=object, other=nil` although one driver flipped the other over a barrier (KB-34, root-caused and fixed 2026-09-21: the scan compared samples taken at different moments). **Item 16 PASS** — SR moved for both drivers and the arithmetic was correct (owner bands 3+3+2 = −0.80; visitor 2+1+3+3 = −0.90). Also observed in the same race: race time `6:37.200` (KB-23, quantisation, fixed), `+2` wrong accomplishments (KB-38, fixed), a phantom overlapping event DNS'ing both drivers (KB-37, fixed), and every `[NCM]` line labelled "Global" with cross-client visibility still unconfirmed (KB-42, open). **This row is not a pass. Re-run 1.6 against the sheet after the fix pass deploys** — it is now also the regression test for four fixes. |
| 1.7 street regression | | |
| 2.1 Race Guide: list / interest / practice / upgrade / withdraw | **PARTIAL — renders again at deploy 18 (2026-09-22, owner-confirmed)** | The Guide had been dark since deploy 12; four stacked defects (KB-59, KB-61, KB-63 and a script-budget ceiling) are now fixed and rows draw. **The information layer is NOT validated: it is in the payload and nothing renders it.** `panel.html` reference counts — `weather` 0, `regs` 0, `car` 0, `description` 3. So §S2 (car), §S3 (regs) and §S5–S7 (weather) **cannot be run until the client work exists**; §S1 (authored route descriptions) **can**, because `r.description` is rendered at panel.html:252. Interest/practice/withdraw still unrun since the rebuild. |
| 2.2 scenarios / authored routes / disciplines / restart / stop / reset | | |
| 2.3 state / incident injection / rules / trace / debug / warp | | |
| 2.4 stream gates: first crossing 3/3 | | |
| 2.5 rolling start: formation / green at leader / faults / oval default | | |
| 2.6 fix pass: F9 / thread / ground z / enum name | **PASS (3 of 4)** | F9 opens Messages — confirmed by owner. Ground z: `grid car #7 z from a player 41 m away: 12.0 (node 13.0)` — KB-17 fix working, car spawned on the road. Enum: `npcs.damage.invulnerable = 2` — KB-13 answered. Phone-thread presentation not yet observed. |
| 2.7 weather authority / KB-6 | **PASS** | Two-client op77.87 W1–W8 complete; all presets, natural scheduling, mid-transition rejoin, bucket override/isolation/reacquisition/clear matched canonical state. [E26](../archive/experiments/E26_2026-09-22_weather-sync.md). |
| 2.8 NCM Weather Service | **PENDING LIVE QA** | Offline: 128/128 core tests on Lua 5.4 and LuaJIT; 100 resource Lua files parse cleanly. Live §X1–X8 not run. |
| 2.9 Vehicle Collection | **PARTIAL — discovery and provenance PASS (deploy 13, 2026-09-23 00:17–00:18)** | §T1 PASS: `DISCOVERED driver=72519ab3 key=rayfield_caliburn record=Vehicle.v_sport1_rayfield_caliburn_player`. §T2 PASS: `source_driver_id=48831609`, `source_holding=issued` — the fact that cannot be backfilled. §T3 PASS: `encounter_count` 1→2 over 117 s with `source_driver_id` **unchanged**, so the `ON DUPLICATE KEY UPDATE` path does not rewrite credit. §T4 PASS (unplanned): the car's own holder discovered it with `source NULL` — `Discoveries.credit` refused with `self`. Owner saw one toast and no repeat, which is the anti-farm rule holding. Offline: 144/144 core tests, 106 resource files parse. **Still to run: §T5 standings, §T6 partial-generation recovery, §T7 unreadable-collection refusal, plus the E27 false cases (far / wrong bucket / ambient / restart).** |
| 2.10 readiness watchdog (KB-60) | **ALL PASS — §AD1–§AD7. §AD2 cleared on a real visitor at deploy 21 (KB-64 fixed).** | Deploy 19, 2026-09-23 01:35–01:49 UTC, owner at one client. **§AD1** sweep up, `world.readiness` loaded, zero script errors. **§AD7 PASS unprompted** — a real platform report proved a second resource *does* receive `open77:appearance:readinessDiagnostic`, which was the design's one open uncertainty. **§AD3 PASS** with chat line + yellow toast owner-confirmed, and a typo'd stage correctly refused. **§AD4, §AD5, §AD6 PASS.** **§AD2 initially FAILED → KB-64** (fixed deploy 20, then **PASSED at deploy 21 on the visitor `A`**: two joins, ~58 min, zero readiness lines): a normal join was warned at 47 s and told to reconnect; `staleStageS=45` was holding a ~15 s heartbeat three times too long. Fixed and shipped in **deploy 20** (01:56 UTC, 163/163 green). **§AD2 re-run is the only thing owed: join once and confirm no `readiness:` line.** Two-client §AD6 still unrun. |
| 2.11 asset-keyed ownership (IDEA-157) | **PARTIAL — §U1 PASS (deploy 21, 02:26 UTC); §U2–§U9 need a client** | Offline: 173/173 core tests, 111 resource files parse. Migration 015 applied and exercised against the real MariaDB in a dropped scratch schema — replay-idempotent, `acquired_via` preserved, duplicates possible, FK refuses orphans. `owned_vehicle` holds 0 rows on staging, so the backfill is a no-op. §U1–§U9 unrun. |
| 2.12 Guide information layer (car/regs/weather) | **DEPLOYED 21 (02:26 UTC) — §S1–§S10 unrun** | Built client-side only: **zero payload fields added, zero Lua changed** — `guide.lua` and `client/panel.lua` diffed against the live copies to prove it, so KB-59/KB-63/script-budget cannot bite. New `tools/panel-render-check.js` in the gate (28 assertions) caught a real pre-deploy `guideWx is not defined` that would have reproduced KB-61. §S1–§S10 unrun. |
| 2.13 onboarding unblock + venue panel (KB-66 / KB-67) | **§Y8–§Y10 PENDING; §Y1–§Y7 WILL NOT BE RUN (L102)** | Deployed 23 (04:39 UTC), 183/183 core tests, 113 files parse, 28 render assertions. KB-66: `/ncm car` now also grants a capped, `seed`-labelled asset via a host-wide event, so a visitor can actually enter a race; the rule is in `data.vehicle_assets.seedDecision` and tested offline. KB-67: the venue teardown now closes on `panelOpen` rather than `lastDrawn`. §Y1–§Y10 unrun. |
| 2.14 Machine Index foundation (IDEA-196) | **OFFLINE-GREEN, NOT DEPLOYED — §Z1–§Z5 pending** | 186/186 core tests under Lua 5.4 and LuaJIT; 116 resource files parse; migration 016 adds idempotent player/model/optional-asset evidence and backfills discovery identity without fabricating specifications. §Z4 waits for real Market stock. |
| 2.15 Starter Market network boundary (IDEA-198) | **OFFLINE-GREEN, NOT DEPLOYED — §AA1–§AA8 pending** | 189/189 core tests under Lua 5.4/LuaJIT; 120 resources parse; 33 panel assertions. Disposable MariaDB proof passed migration 017, grant/purchase retry dedupe and competing-buyer conservation. Three finite `base_market` assets; €$10k starter grant; atomic title/history transfer. |
| 2.16 NCM Help + in-game reporting (L105) | **PARTIAL — §Z6/§Z7 PASS on a real report; §Z8 (survives leaving) still owed** | Deployed 2026-09-23 13:43 UTC, migration 018 applied, `help surface ready (0 notice(s), 0 change(s) authored)`, zero errors. 196/196 core tests, 124 files parse, 54 render assertions. §Z1–§Z11 unrun. |

### 2.17 deployment follow-up — 2026-09-23 14:40 UTC

**DEPLOYMENT / BOOT PASS.** User explicitly requested deployment. Zero connected players reconstructed from
server lifecycle log; last disconnect 14:03 UTC. `tools/deploy-staging.ps1` uploaded resources and restarted
staging; config unchanged. Backup `/opt/ncm/backups/access-20260923T143853Z` contains prior resources and SQL.
Seven key access/UI files matched local hashes. Service active at 14:40:36 UTC; both NCM resources started;
no fresh resource/script errors; migrations pending=[]; scheduler five series.

**§AB6 storage-restart portion PASS:** MaiMai still sold/owned, balance 7500, exactly one purchase debit and
one primary_purchase history row; Galena/Hella available. **Runtime cleanup/reconnect portion remains NOT RUN**:
no called vehicle existed during this restart. §AB3–AB5 and §AB7–AB9 still require live client QA.

The earlier "built locally, not deployed" wording records the implementation session; this deployment update
supersedes deployment status only, not gameplay-validation status. Systemd emitted an existing unit-file-change
warning; no unit configuration was changed or reloaded, and service startup succeeded normally.
| 2.18 Call Vehicle + reaching a start line (KB-72..80) | **§AC11 LIVE PASS for Sewer; consecutive-race panel re-run required** | Sewer completed end to end after the targeted session handoff: client received session `266c48fb...`, transitioned gridded -> countdown -> running, recorded its start origin, crossed gate 2, finished, and retired the targeted view cleanly. The following selected race drew a ring but no panel (KB-80): the ring followed the driver's event while the proximity loop measured against `cal.next[1]`. Fixed by binding proximity to the POI's own venue and deployed 20:20 UTC. Full gate green, deployed hash matches, clean boot, migrations pending=[]. Live confirmation of the next-race panel remains required. §AC1–§AC10 remain unrun. |

## §AD — race navigation lifecycle, withdraw/forfeit, Past Results, Help, node markers (2026-09-23, deploy 21:37 UTC)

All seven rows are **BUILT AND DEPLOYED, NOT RUN LIVE**. Nothing below is done until a live PASS sits beside
it (L69). Offline gate at the point of deployment: 221 core tests under Lua 5.4 and LuaJIT, 34 cross-scope
references 0 bad, 35 access, 17 observer, 137 resource Lua files parsed, 3 inline scripts, 77 panel render
assertions (67 before, +10 for PAST RESULTS). Ten deployed files match local CR-insensitively; clean boot, no
script errors, help surface reports 1 authored notice, race control started.

| Row | What must be observed | State |
|---|---|---|
| §AD1 | **First race.** Race Guide -> venue -> explicit ENTER RACE -> **navigation changes to the course target before the start** (log: `entry navigation player=N event=... -> <gate name>`) -> T-1 staging/grid -> lights -> race -> finish -> result. | NOT RUN |
| §AD2 | **Successive race, same continuous session.** Complete race A, travel to race B, enter B, and confirm navigation targets **B's course**, not A's anything and not a venue. This is the exact Hook failure. | NOT RUN |
| §AD3 | **Withdraw.** Enter -> WITHDRAW at the venue -> confirm not entered (panel shows ENTER RACE again, chat says "Withdrawn") -> re-enter -> confirm entered. | NOT RUN |
| §AD4 | **Forfeit.** Enter -> start -> `/ncm.forfeit` -> confirm on the second call -> race HUD and navigation clean up, ordinary world state returns, result records DNF. Then confirm no stale race/navigation state contaminates the next event. | NOT RUN |
| §AD5 | **Past Results.** Complete an authoritative timed result, open F6 -> PAST RESULTS, confirm it appears with its time, and that a solo run reads TIME TRIAL rather than P1. Sewer (153.052) and Overbridge Curve (82.031) should already be listed on first open. | NOT RUN |
| §AD6 | **Route line.** Observe whether the road route now draws without opening the map, and whether getting into the car re-selects it (client log: `gps destination selected (got in)`). If a route still fails to draw, confirm Help's "Route line not showing?" entry is discoverable and accurate. | NOT RUN |
| §AD7 | **Node markers.** Confirm ~35 NCM locations appear on the world map with their names, that a player can set an ordinary waypoint on one, that `/ncm.nodes` toggles them, and that they never steal the race's GPS selection. | NOT RUN |

**Known limits, stated rather than discovered later.** Forfeit is reachable from chat and from the withdraw
refusal, not from the race HUD (IDEA-210). PAST RESULTS is a list with no per-run detail view (IDEA-211).
`routable`/`track` behaviour is read from the platform's own shipped code and its documented comments; it has
not yet been observed in an NCM client, which is what §AD6 is for.


## §AE — Base Market primary supply, offerings, discovery and the race graph (2026-09-23, deploy 22:11 UTC)

Offline gate: **233 core tests** under Lua 5.4 and LuaJIT (221 before; +7 production, +5 standings), 34
cross-scope references 0 bad, 35 access, 17 observer, **142 resource Lua files**, 3 inline scripts, **88 panel
render assertions** (77 before). Migration 021 applied cleanly to the live world; database backed up first to
`/opt/ncm/backups/supply-20260923T220955Z`.

### Live-verified on staging (supply half)

| Row | What was observed | State |
|---|---|---|
| §AE1 | **Production mints toward the ceiling.** First pass: MaiMai `0/8 -> 4/8`, Galena `1/6 -> 4/6`, Hella `1/4 -> 3/4`. Second tick took all three to `8/8`, `6/6`, `4/4`. | **LIVE PASS** |
| §AE2 | **Partial capacity caps the batch** (acceptance B), twice: Hella tick 28 had batch 2 into 1 free slot and minted **1**; Galena tick 56 had batch 3 into 2 free slots and minted **2**. Neither exceeded its ceiling. | **LIVE PASS** |
| §AE3 | **At the ceiling, production is zero** and stays zero: derived stock sits exactly at 8/6/4 and no further assets appear. | **LIVE PASS** |
| §AE4 | **Every produced unit is a distinct asset.** 19 assets, 19 distinct inventory rows, no duplicates; each carries its own `assetId`, `vehicle_key`, class and deterministic paint. | **LIVE PASS** |
| §AE5 | **Idempotency across restart** (acceptance G). A restart at the ceiling produced **zero** production log lines -- `runTick` returns at the claim check before even the capacity log, so this proves the tick claim and not merely the ceiling. Asset counts and run rows unchanged. | **LIVE PASS** |
| §AE6 | **The existing world is intact** (acceptance I). Bootstrap MaiMai `10000000-...-0001` retains its identity, its owner and its `purchase` provenance. Galena and Hella bootstrap assets were counted as stock, never replaced. | **LIVE PASS** |
| §AE7 | **Stock is derived from real unsold assets**, not a counter: the availability query joins `market_inventory` to `vehicle_asset` and requires `ncm_driver_id IS NULL`. | **LIVE PASS** |

### Owed live QA (player-facing half)

| Row | What must be observed | State |
|---|---|---|
| §AE8 | Open F6 -> MARKET and confirm **MaiMai is back on the shelf** with `AVAILABLE 8 / 8`, alongside Galena and Hella. | **PARTIAL (Development 2026-09-24):** the Market panel loads and lists all three offerings with openable cards. The `8 / 8` figure is an **Online** assertion -- the dev world seeded `stock=3` -- so the count half of this row remains NOT RUN and is not claimed. |
| §AE9 | Buy one. Confirm the exact asset transfers, availability drops by one, and **the offering stays on the shelf**. Then buy a second of the same model and confirm a **different** assetId transfers (acceptance E/F). | NOT RUN |
| §AE10 | Confirm the detail pane states price, available/ceiling, state, next production time and next batch, with one purchase action per individual asset (acceptance D). | NOT RUN |
| §AE11 | Select a stocked offering and confirm the Machine Index records the discovery (acceptance J). | **LIVE PASS (NCM DEVELOPMENT, 2026-09-24)** -- owner opened the card for all three stocked offerings, then opened Machine Index: **three discovered, all corresponding.** This is the first live evidence that discovery fires on player-facing inspection rather than on payload build (`IDEA-215`). Online confirmation still owed (L121: Development proves, Online confirms). |
| §AE12 | Drive a model to `0` available, confirm the offering **remains visible** as SOLD OUT with its next-production information, and confirm selecting it still discovers the model (acceptance D/K). | NOT RUN |
| §AE13 | Race graph (acceptance M/N/O): solo shows one driver and no fabricated company, the strip is vertical and compact, and **the speedometer is visible**. | NOT RUN |

### Deliberately not built

- **§18B throttle/brake meters: blocked on the platform, and the packet's own precondition is not met.**
  OPEN//77 exposes no scripted analog pedal input -- `Open77.input` is digital key state (`isDown`,
  `isCaptured`, `keyFor`) and `Open77.vehicles` has no throttle/brake accessor. `GetAxis` and `throttleKey`
  appear only as internal symbols inside the binaries, in no scripted resource. A digital on/off bar would
  misrepresent a controller, so nothing was built (IDEA-218).
- **§18A start-direction indicator:** documented as IDEA-217, low priority by the owner's own classification
  and not load-bearing now that pre-start course navigation works (L115).
- **§17 race-purse settlement:** explicitly out of scope for this packet.


## §AF — dynamic manufacturer supply (2026-09-23, deploy 22:39 UTC)

Offline gate: **249 core tests** under Lua 5.4 and LuaJIT (233 before; +14 profile simulations, +2 production),
34 cross-scope 0 bad, 35 access, 17 observer, **145 resource Lua files**, 3 inline scripts, **91 panel render
assertions**. Migration 022 applied cleanly; database backed up first to
`/opt/ncm/backups/supply-dynamics-20260923T223843Z`.

The §27 scenario simulations run deterministic market histories through the real profiles and are part of the
gate: stable demand, sustained sellout, demand spike, demand collapse, persistent full inventory, oscillating
demand, low-data cold start, one buyer vs many, ladder integrality, envelope bounds at both ends, a model that
never sells, a big batch into a nearly full shelf, determinism/replay, and single-purchase immunity.

### Live-verified

| Row | What was observed | State |
|---|---|---|
| §AF1 | **No launch replay.** All three alpha lines were recognised as mid-life from their existing production history and resumed at their next index (113 / 57 / 29) with `initial_done = 1`. Asset counts unchanged at 9 / 6 / 4; no initial allocation was minted onto a running offering. | **LIVE PASS** |
| §AF2 | **Manufacturer defaults composed from the catalogue:** Makigai -> `volume_responsive`, Thorton -> `steady_hand`, Archer -> `scarcity_keeper`. | **LIVE PASS** |
| §AF3 | **A restart does not re-roll anything** (addendum section 17). After a restart the committed index, instant, batch, interval and profile were byte-identical, `supply state opened` appears exactly three times in the whole log (once per line, ever), and no assets or runs were added. | **LIVE PASS** |

### Owed live QA

| Row | What must be observed | State |
|---|---|---|
| §AF4 | **A real production event fires and evaluates.** Confirm the ledger row records profile, logic version, signals JSON, decision reason, chosen next batch/interval and whether the envelope clamped it — and that the next committed event moves accordingly while the one just fired was honoured as displayed. | RUNNING (first event due 23:10 UTC) |
| §AF5 | Market detail pane shows current cadence and the "schedules respond to market conditions" line, and never a profile name. Asserted offline; not yet seen by a player. | NOT RUN |
| §AF6 | Over days: a sustained sellout visibly speeds a line up, a glut visibly slows one, and neither leaves its envelope. This is the row that genuinely needs time rather than a session. | NOT RUN |

### Concerns worth stating rather than burying

- **The alpha envelopes are guesses.** `intervalMax` of 8 h / 24 h / 72 h means a glutted line can become very
  slow, and with one player that may read as "the Market stopped working". The floor is real (`intervalMin`
  15 min / 30 min / 60 min) so it always recovers, but the first tuning pass should probably tighten the
  ceilings before population arrives.
- **Cold start is the weakest part.** `minCycles` of 2–4 is only meaningful once events actually fire, which
  on a 2-hour Archer cadence is most of a day. Until then every manufacturer holds its authored schedule,
  which is the safe behaviour but also means the system is untested at speed.
- **The catch-up rule is deliberately lossy.** A line whose committed event is long overdue fires once and
  re-plans from now, rather than replaying every missed event. Ceiling-seeking production makes the shelf
  outcome identical; what is lost is cycle history during an outage, which slightly dilutes the next
  evaluation.


## §AG — vehicle identity, provenance, odometer and lifecycle (2026-09-23, deploy 23:03 UTC)

Offline gate: **258 core tests** under Lua 5.4 and LuaJIT (249 before; +9 identity), 36 cross-scope 0 bad,
35 access, 17 observer, **150 resource Lua files**, 3 inline scripts, **91 panel render assertions**.
Migration 023 syntax-checked against the live MariaDB on a throwaway clone of `vehicle_asset` before it was
applied for real; database backed up first to `/opt/ncm/backups/identity-20260923T230301Z`.

### Live-verified

| Row | What was observed | State |
|---|---|---|
| §AG1 | **Backfill assigned correct provenance to all 19 existing assets, 0 skipped**, ordered by production evidence. | **LIVE PASS** |
| §AG2 | **MaiMai `10000000-...-0001` is NCM #0000001 / makigai #0001 / makigai_maimai #0001**, `origin = production`, `lifecycle = active`, still owned by its buyer. Identity, ownership and provenance untouched (addendum section 7 / test T). | **LIVE PASS** |
| §AG3 | **The three sequences are visibly independent**: archer #0002 is global #4, makigai #0002 is global #6, thorton #0002 is global #10. A manufacturer's first car is not NCM's first car. | **LIVE PASS** |
| §AG4 | **Backfill is idempotent and sequences persist.** After a restart the log still holds 19 backfill lines (not 38), 19 assets carry 19 distinct global ordinals, and `production_sequence` is parked at global 20 / makigai 10 / thorton 7 / archer 5. | **LIVE PASS** |

### Owed live QA

| Row | What must be observed | State |
|---|---|---|
| §AG5 | **Drive a called car and watch the odometer accumulate**, then confirm it survives: leaving and re-CALLing the car, a server restart, and (when a second driver exists) a transfer. Confirm `ncm.odo` and `ncm.provenance` agree with the HUD. | **CONFIRMED (owner, 2026-09-24): "confirmed several times going back to the online server."** Accumulation and survival have been observed repeatedly in ordinary play on both worlds. Logged on the owner's report rather than a fresh scripted run -- **this row was asking for evidence that already existed**, which is a ledger failure, not a testing gap. |
| §AG6 | ~~CALL the car somewhere far away~~ **BADLY AUTHORED -- REWRITTEN 2026-09-24.** Owner: *"ag6 says car is already in world."* Correct: once a machine is in the world you cannot CALL it elsewhere, so the step as written cannot be performed. **What it actually needs to prove:** a position discontinuity must not bank distance. Reachable triggers: `ncm.tp` / host warp while seated, a resume teleport after a race suspension, or a reconnect that relocates the player. Confirm the filtered-discontinuity log names it and the odometer does not move. | NOT RUN -- rewritten, not yet attempted |
| §AG7 | **The odometer panel** (called "instrument cluster" in the spec -- same thing, and the spec's word was confusing: owner, *"i dont know what cluster youre talking about"*) is legible, does **not** cover the speedometer **or the player health HUD**, shows the machine name/serial and lifetime distance, and stays visible through a race start. | **PARTIAL FAIL (Development, 2026-09-24).** It renders and reads correctly -- the owner has been watching it accumulate -- but it **covers the vanilla health HUD** (KB-90). Raised from `bottom: 56px` to `184px`; **needs one look to confirm the new spot**, since guessing the last one is how it landed on the health bar. |
| §AG8 | A newly produced batch carries fresh contiguous serials continuing from #0000019. | RUNNING (next production event due 23:10 UTC) |

### Post-deploy corrections (23:30 UTC, same session)

Two defects were found by the live supply capture and fixed before the identity work shipped:

- **A TINYINT(1) flag reads back as a Lua boolean**, and `tonumber(true)` is nil -- so `initial_done = 1` was
  read as 0 and MaiMai tick 113 ran as an INITIAL allocation on a line that had launched days earlier. It
  minted nothing only because the shelf was full; on a line with capacity it would have re-dropped the launch
  allocation. Flag columns are now read through a `truthy()` helper that accepts either shape.
- **A "decrease" that did not decrease.** The ladder kept every equal-rate (batch, interval) pair as its own
  rung, so a step could land on an identical rate having changed only the shape -- observed live as
  `decrease -> 6x/60min` from `4x/30min`. The ladder now holds one rung per distinct RATE and `grain` decides
  how a manufacturer expresses it, so every step genuinely changes the rate. A follow-on defect surfaced
  immediately: a *hold* was snapping the authored schedule to the ladder's preferred expression of the same
  rate. A hold now returns the current schedule verbatim.

### Stated gaps and deferrals

- **Mileage now accrues for any car that is a persistent asset**, whatever materialised it: the odometer
  takes the CALL/access map plus registrations from any resource (`ncm:odometer.track`). What cannot accrue
  is a vehicle that is not an asset -- NCX team cars are issued equipment with no assetId, and ordinary
  traffic is not NCM's (IDEA-238, owner decision).
- **Admin/progression grants carry no serial** (IDEA-233). Deliberate, so debugging cannot burn a number, but
  it leaves granted cars without a birth certificate. Owner decision.
- **Throttle/brake/steering meters are not feasible** (IDEA-231) — see the report; steering was checked this
  time too, with the same answer.
- **Terminal mechanical failure is architecture only and switched off**, and a test asserts it stays off.

## §AH — Machine attribution, entry-bound machines, owner principal (2026-09-24, NCM Development)

Deployed to **NCM Development only** (migrations 024-027, restart 08:57). Online is untouched.
**Today changed the race settlement path, the entry path and two live tables**, so the regression half matters
more than the new-feature half. Run §AH1-§AH9 first; if any of those fail, stop and say so.

Rows marked **[me]** I verify in the database afterwards — you do not need to check them.

| # | What to do | Expect |
|---|---|---|
| **REGRESSION — most changed, check first** |||
| §AH1 | Join the dev server. | You get in. No error spam. Identity mints under `ncm-devbox`. |
| §AH2 | **F6 -> MARKET.** | Loads, three offerings, cards open. (KB-94 fix) |
| §AH3 | **Machine Index.** | Loads; your discovered models and your owned car are listed. (KB-94 fix) |
| §AH4 | **Race Guide.** | Loads, correct date, races listed. (KB-86 regression guard) |
| §AH5 | `/ncm help`. | Answers. |
| §AH6 | **F10 Collection.** | Loads. |
| §AH7 | **CALL your car** from Machine Index. | It arrives; you can drive it. |
| §AH8 | Look at the **odometer panel**, bottom-left. | **PASS on position** (no complaint about the health HUD after three races). **New finding: the serial it shows is unlabelled** -- see KB-96. |
| §AH9 | Drive a few hundred metres. | The distance climbs. Leave the car and re-enter: it persists. |
| **ENTRY BINDS A MACHINE + A NUMBER (new)** |||
| §AH10 | Sitting **in your car**, enter a race from the venue. | Entry accepted as before. |
| §AH11 | **[me]** | **LIVE PASS.** Three entries, each bound to the Hella. |
| §AH12 | Enter a second race **on foot**, away from your car. | Still accepted — you own an eligible machine. |
| §AH13 | **[me]** | **LIVE PASS.** All three entries carry `car_number = 1` -- the number was reused across events exactly as designed. |
| **THE GRID RULE — you race the car you entered (new, riskiest)** |||
| §AH14 | Enter a race in your car, **stay in it**, let it go green. | **LIVE PASS (Development, 2026-09-24).** Three races, no misfire, no spurious refusal. The riskiest rule shipped today behaved. |
| §AH15 | Watch the server log at green. | One line: `machines at green: 1 attributed, 0 unknown`. |
| §AH16 | **Deliberate violation.** From the server console: `ncm.car <yourPlayerId> Sport` to get a loaner, enter a race in your OWN car, then get into the loaner before green. | Refused the start: chat line + **WRONG MACHINE** toast, classified DNS. Log shows `WRONG MACHINE ... -> refused start`. |
| §AH17 | Same as §AH14 but **get out of the car on foot** just before green. | **Still starts.** An unknown seat is not a violation (KB-72 rule). |
| **ATTRIBUTION (new)** |||
| §AH18 | **Finish a race.** | **LIVE PASS.** Three finished: Hold Your Breath 27.375, Snake in the Grass 192.804, Ukulele 305.387. |
| §AH19 | **[me]** | **LIVE PASS.** All three rows carry `asset_id = 10000000-...` and `attribution_basis = 'recorded'`. Older B-line rows correctly stay NULL -- they predate the column. **The 29-result leak is closed on Development.** |
| §AH20 | During that race, **hit a wall or a barrier** hard enough to register an incident. | Incident toast as usual. |
| §AH21 | **[me]** | **NOT RUN -- zero incidents recorded in the session**, so there was nothing to attribute. Needs a deliberate wall or barrier hit. |
| §AH22 | Run a **practice / time trial** and set a best lap. | Normal. |
| §AH23 | **[me]** | That result row is attributed too — it was the third unwired write site. |
| **OWNER PRINCIPAL — no visible change expected** |||
| §AH24 | Everything involving your car and money still works: CALL, Market browse, purchase if you have funds. | Unchanged. Migration 025 added columns beside the old ones; nothing reads them yet. |
| §AH25 | **[me]** | `vehicle_asset` and `ledger` principal columns stay in step with `ncm_driver_id`. |
| **WATCH FOR ANYTHING** |||
| §AH26 | Any `[ERR]` line in the server log during the session. | There should be none. **One known and expected:** a single `SQL 1146` at boot ONLY if the schema was behind, which it is not any more (KB-92). |
| §AH27 | A wrong-machine refusal you did not deliberately cause. | Should never happen. **Tell me immediately if it does** — that is the rule misfiring and I will make it log-only. |

---

## §AI — driver-input HUD, evidence trust and the zero/unknown invariant (2026-09-24, NCM Development)

**Restart first.** Migration **029** applies on boot (`observation_basis`, plus discovery coordinates), and
the HUD is new client code. Expect `pending=[]` and schema **29** afterwards. Migration **028** applied on the
previous deploy and is already at rest.

Verified before you drive (no session needed): 029 applied **twice** against copies of the real table
definitions -- exit 0 both times, all 3 evidence rows and all 3 discovery rows preserved, all four new columns
`NULL` on every existing row. Gate green, 271 core tests per interpreter.

| # | Do | Expect |
|---|---|---|
| **THE DRIVER-INPUT HUD (new, the point of this pass)** |||
| §AI1 | Get into any car. Look bottom-left, **directly above the odometer**. | A small panel: a steering wheel on the left, two vertical bars (`THR` green, `BRK` red) with a percentage under each. |
| §AI2 | **Neutral.** Hands off, feet off. | Wheel upright. Both bars empty, both reading `0`. |
| §AI3 | **Full throttle.** | `THR` fills to `100` and drains back smoothly when released. |
| §AI4 | **Full brake.** | `BRK` fills to `100` and drains back. |
| §AI5 | **Steer full left, then full right.** | The wheel rotates the same way you are steering, up to about a third of a turn at full lock. **If it rotates the wrong way, say so** -- the sign convention is the one thing I cannot check without you. |
| §AI6 | **Both at once**: throttle and brake together, then steering while braking. | Both bars move independently; the wheel is unaffected by the pedals. |
| §AI7 | **Get out of the car.** | The panel disappears. The odometer below it is unaffected. |
| §AI8 | Drive a full race with it on screen. | No stutter, no frame cost you can feel. It updates at 20 Hz while seated and 2 Hz when not. |
| §AI9 | **If a bar or the wheel shows a dash `--` instead of a number**, that field is genuinely absent on this build. | **Not a bug to fix in the HUD -- report it.** The panel deliberately refuses to draw a resting pedal for a value it could not read. |
| §AI10 | **[me]** Client log, once per session: `input surface: throttle=... brake=... steering=... rpm=... gear=...`. | **Paste that line.** It is the runtime-verification record -- the published cards answer for `op77.78`, this server runs `.87`, and this line is the only proof of what the build actually exposes. Closes §103, owed since it was written. |
| **EVIDENCE PROVENANCE (silent -- nothing visible changes)** |||
| §AI11 | Discover a machine: drive near an unfamiliar car, or open a Market card you have not looked at. | Normal discovery toast. |
| §AI12 | **[me]** `SELECT obs_x, obs_y, observation_basis FROM vehicle_knowledge_evidence ORDER BY observed_at DESC LIMIT 3;` | New rows carry coordinates **and** `observation_basis = 'server_measured'`. **This also closes the live PASS owed for migration 028** -- Development has 3 evidence rows and none has a position yet. |
| §AI13 | **[me]** `SELECT first_obs_x, first_obs_y FROM vehicle_discovery ORDER BY first_discovered_at DESC LIMIT 3;` | The new row has a position; the three older ones stay `NULL` forever. **No backfill is correct behaviour, not a gap.** |
| §AI14 | **[me]** Drive past that same model again days later. | `encounter_count` rises; `first_obs_*` does **not** move. INSERT-only, same rule as `source_driver_id`. |
| **THE ZERO/UNKNOWN INVARIANT** |||
| §AI15 | Sit **stationary** in a car during a race and let telemetry sample you. | Samples are still produced. **A parked car genuinely reading 0 is real evidence and must stay real** -- this is the half of the fix that is easy to break. |
| §AI16 | `/ncm.telemetry` mid-race. | Now reports `sent N · skipped M unreadable`. **`skipped` should be low.** A large or growing count means the vehicle snapshot is frequently unreadable on this build -- tell me, it changes what the HUD can promise. |
| **MARKET DISCOVERY (owed from the previous pass, same restart)** |||
| §AI17 | Open the Market. | Same three offerings, same balance. Nothing should look different. |
| §AI18 | **[me]** `SELECT market_id, source_kind, access_state FROM player_market_knowledge;` | One row per driver: `base_market` / `universal` / `open`. The table has been empty since migration 017. |
| **WATCH FOR ANYTHING** |||
| §AI19 | Any `[ERR]` during boot or the session. | There should be none. |
| §AI20 | Odometer, race HUD, markers, Machine Index, toasts. | All unchanged. The input panel is additive and sits above the odometer without moving it. |

**OWED regardless of this session:** migration 028's *fresh-world* behaviour cannot be proven on a world that
already has rows. That case stays owed (`IDEA-319`).

---

## §AJ — can a WebUI surface reach a local companion? (2026-09-24, NCM Development) — **PASS**

`IDEA-387`. Run `python tools/ws-probe-server.py`, then `/ncm.bridgeprobe` in the client.

| # | Result |
|---|---|
| §AJ1 | **FAIL, expected and informative.** From the **bundled** HUD page (`/ncm.wsprobe`): `ws-live`, `ws-dead`, `wss-dead`, `fetch-http`, `fetch-https` — **all ERROR at ~0ms**, whole matrix in 1ms, listener never saw a TCP connection. Origin `https://r-NN-g-1.cym-ui`, `secureContext=true`. **Not mixed content** — that spares the secure schemes and these failed too. A private scheme with no outbound network. |
| §AJ2 | **PASS.** `WebUI.create({ entry = "http://127.0.0.1:38480/bridge.html" })` accepted and loaded, under the real game browser (`Chrome/144`, distinct from the PowerShell self-test earlier in the same log). |
| §AJ3 | **PASS — the load-bearing one.** `hasBridge=true`. The Lua bridge **is** injected into a non-bundled origin, so `page:send` / `Open77.emit` work exactly as for a bundled page. |
| §AJ4 | **PASS.** Same-origin WebSocket handshake completed; listener logged `Origin: http://127.0.0.1:38480`. |
| §AJ5 | **PASS.** Payload frame received and parsed server-side: `{"origin":"http://127.0.0.1:38480","probe":"ncm-bridge"}`. Proves data flow, not only a handshake. |
| §AJ6 | **No TLS needed.** `secureContext=true` over plain `http://127.0.0.1` — loopback is potentially trustworthy. No certificate, no trust-store change. |

**Conclusion:** the FFB/companion bridge is viable, via the remote-entry inversion rather than the bundled page.
Constraint recorded as `IDEA-393`: **the race HUD stays bundled**; only the bridge surface is remote.

---

## §AK — Driver Card/nameplate first live pass (2026-09-24, NCM Development) — **OWED**

Current offline gate: 285 core tests per interpreter, 165 resource Lua files, five WebUI scripts, 96 existing
panel assertions and 26 Driver Card assertions pass. **Deployment PASS, 16:44 EDT:** Development published the new
resource generation; schema entries 30 includes `030:driver_presentation`, `pending=[]`; both NCM resources,
scheduler and race control started; HTTP health 200; stderr empty; zero boot error matches. This is not a
nameplate PASS. The section still requires **two live clients**. Join both in the same bucket and note their
player IDs. Client A observes Client B unless a row says otherwise.

**First live observation, NCM Online 2026-09-24:** the WebUI-capable first process drew the remote Driver Card,
but its fixed screen-pixel size visibly grew relative to the receding body (**§AK6 FAIL / KB-98**). The server
correctly held and published `baremetaleven -> ncm_default`. The second local process could not draw that card:
its OPEN//77 WebHost disconnected with `pipe_read_failed:109`, imported zero WebUI surfaces and never emitted
the custom-card ready/handoff line (existing KB-4). That is not a missing presentation row and is not recorded
as a Driver Card PASS. The scale correction is deployed to Development and Online; visual re-test remains owed.

**Hotfix promotion PASS, NCM Online 2026-09-25 01:23 UTC:** commit `80ad0aa` was already on `origin/main`;
fresh backups `ncm-db-20260925-012200.sql.gz` and `ncm-resources-20260925-012200.tar.gz` were verified before
promotion. Online published digest `e17702fa…`; the deployed resource contains the distance-scale code; service
active, HTTP health 200, schema 30 / `pending=[]`, zero boot errors. Counts remained 13 drivers / 13 bindings /
19 assets / 29 results / 23 ledger / 14 evidence / 14 discovery, and `baremetaleven -> ncm_default` remained
intact. Deployment is not a visual PASS; §AK6 still needs an observing client with a working WebUI host.

Use the server console command `ncm.card.preview <B-id> <0|1|2|3> [default|selected]`. `selected` is the
explicit Development-only alternate; the command changes no accomplishment or persisted entitlement.

| # | Smallest live proof | PASS condition | State |
|---|---|---|---|
| §AK1 | Put B in front of A after both are gameplay-ready. | One compact NCM card appears over B and **no native text plate appears beside it**. | **OWED — two clients** |
| §AK2 | Compare B's card name with B's current platform name. | Exact current verified presentation name; no UUID/session ID. | **OWED — two clients** |
| §AK3 | Run preview with `0 default`, then `0 selected`. | Baseline and selected banner treatments are visibly distinct, crop cleanly, and both remain readable. | **OWED — two clients** |
| §AK4 | Run preview with `0`, `1`, `2`, then `3 selected`. | All four badge layouts look intentional; never more than three slots render. | **OWED — two clients** |
| §AK5 | Inspect the right-hand instrument region in every variant. | It remains fixed/high-contrast and says **Fingerprint / Unavailable / Insufficient data**; no zero polygon. | **OWED — two clients** |
| §AK6 | Walk/drive B across A's view and toward the ordinary nameplate range limit. | Card tracks B without obvious extra Lua lag; card scale remains proportionate; existing fade/distance/visibility policy is not widened. | **FAIL 2026-09-24 Online — fixed-pixel card grew relative to body (KB-98); correction deployed Online, live re-test owed** |
| §AK7 | Turn A's camera until B is behind it, then return; move B out of stream range and back. | Card disappears when not projected/streamed, returns once, and leaves no stranded DOM card. | **OWED — two clients** |
| §AK8 | Have B leave and rejoin; if practical, force one normal body recreation. | Old card disappears; the new streamed body gets exactly one current card, including late presentation state. | **OWED — two clients** |
| §AK9 | If practical, move B to another routing bucket and back. | A loses the card with the bucket-public bag mirror and regains one after return. | **OWED — two clients / bucket command** |
| §AK10 | `reload ncm_world` once with both connected. | No duplicate/stranded cards; handoff re-establishes. If KB-2/KB-5 fires, record that exact platform failure instead of passing. | **OWED — two clients** |
| §AK11 | Stop `ncm_world` while B remains visible, then start it again. | Native text renderer returns while NCM is stopped; after recovery the NCM card returns and native text is suppressed only after it is ready. | **OWED — two clients** |
| §AK12 | Repeat with a genuinely long and/or non-ASCII platform name when an account is available. | Text remains literal (never markup), Unicode survives, and visual ellipsis keeps the card bounded. | **OWED — suitable account** |
| §AK13 | Check server/client logs during the pass. | Migration 030 is applied; publication reports only banner/badge count/unavailable state; no `[ERR]`, heartbeat timeout or repeated handoff loop. | **OWED — live logs** |

Invalid/missing asset fallback, public-schema privacy, three-badge bound, unavailable Fingerprint, text escaping,
stream cleanup logic and native restoration ordering are already deterministic offline assertions. Do not mutate
a live state bag merely to re-prove malformed input handling.

---

## §AL — Market nullable-binding recovery (2026-09-24, Development + Online) — **LIVE PANEL PASS OWED**

The first Market open after the IDEA-251 promotion failed before any payload reached WebUI. Online evidence was
`open77/runtime.lua:330: invalid_parameters`; the Market service and its three offerings were otherwise healthy.
`KB-99` records the exact cause and correction. Commit `0406562` is pushed and deployed through Development and
the named Online pipeline. The full gate is green under Lua 5.4 and LuaJIT, including a new executable adapter
regression that proves the real universal-market write sends seven dense SQL parameters and restores absent
`source_ref` to SQL `NULL`.

Deployment evidence: Development restarted cleanly at 21:29 EDT with schema 30 / `pending=[]`, Market ready,
HTTP 200 and empty stderr. Fresh Online backups are `ncm-db-20260925-013053.sql.gz` and
`ncm-resources-20260925-013053.tar.gz`. Online restarted at 01:32 UTC; service active, HTTP 200, schema 30, no
post-restart error matches, deployed source hash `0453300b…` equals local, and counts remain 13 drivers / 13
bindings / 19 assets / 29 results / 23 ledger / 14 evidence / 14 discovery. Deployment is not the panel PASS.

| # | Smallest live proof | PASS condition | State |
|---|---|---|---|
| §AL1 | Reconnect to Online after the restart and open Market once. | Market renders its three authored offerings and current balance; server emits no `payload failed` or `invalid_parameters`. | **PARTIAL PASS 01:34 UTC — request completed with no failure; player must confirm the three offerings were visible** |
| §AL2 | After §AL1, query the owner's new `player_market_knowledge` row. | `base_market / universal / NULL / open`; repeated opens create no duplicate and do not rewrite first sight. | **PARTIAL PASS — exact row exists with SQL NULL; repeated-open observation owed** |
| §AL3 | Inspect the post-open Online log. | `panel OK ... panel=market` reaches its drawn report and no new `[ERR]` appears. | **PASS 01:34 UTC — 13 ms, 0 faults; no payload failure, invalid parameters or ERR** |

---

## §AM — platform freeroam eviction (2026-09-25) — **DEVELOPMENT + ONLINE BOOT PASS; CLIENT PASS OWED**

L132 / IDEA-416. The first containment pass was insufficient: `/freeroam`, the forced join kill and both
freeroam resources still loaded. The re-applicable vendor-tree guard now also removes `freeroam` and
`open77_freeroam` from `resources.load` and removes the `freeroam` discovery tag while retaining the separate
`open77_animations` resource.

Development boot at 00:55 EDT: dependency audit `load list OK: 36 resources`; 38 resources started after
platform dependency expansion; zero freeroam resources discovered or started; `open77_animations`, `ncm_world`
and `ncm_league` started; schema 30 / `pending=[]`; HTTP health 200; stderr empty; zero boot error matches.

Online activation at 05:09 UTC followed commits `833642b` and `0ea0def` on `origin/main`, rollback set
`20260925-050408`, a confirmed live whitelist and an empty player set. The normal restart took the platform's
full 90-second SIGTERM timeout, but admitted no player. New boot: 39 resources started after platform expansion;
zero freeroam resources discovered or started; animations and both NCM resources started; schema 30 /
`pending=[]`; zero boot error matches; health 200. The guard remains idempotent and the 36-resource dependency
audit passes. Current canonical counts are 16 drivers/bindings, 21 assets, 33 results, 32 ledger rows and 18
knowledge evidence/discovery rows, all under the sole `ncm-dev` world identity.

| # | Smallest live proof | PASS condition | State |
|---|---|---|---|
| §AM1 | Inspect the effective Development load list and dependency audit. | `freeroam=no`, `open77_freeroam=no`, `open77_animations=yes`; every loaded dependency present. | **PASS — script readback plus 36-resource dependency audit** |
| §AM2 | Restart Development and inspect the complete boot log. | Neither freeroam resource is discovered/started; NCM and animations start; health 200; zero boot errors. | **PASS — 00:55 EDT** |
| §AM3 | Promote the script/config result and restart Online only after a fresh player check. | Online starts without either freeroam resource, retains animations and NCM, stays schema-current and healthy. | **PASS — 05:09 UTC; zero freeroam discoveries/starts, animations + NCM live, schema 30, health 200, zero errors** |
| §AM4 | Join Online once after §AM3. | No scripted death/respawn on join; NCM placement remains. | **OWED — live client** |
| §AM5 | Try `/freeroam`, `/car`, `/race`, `/footrace`, `/pvp` and `/dm`. | None of the platform sandbox surfaces exists or mutates world state. | **OWED — live client** |
| §AM6 | Try `/anim list`, one named animation and `/anim stop`. | Standalone animation command still works; no-argument picker absence is accepted. | **OWED — live client** |
| §AM7 | Die once. | Record the actual current behavior honestly. Reconnect is the expected workaround until NCM owns respawn. | **OWED — live client** |

---

## §AN — Gate 6 physical performance and composition proof (NCM Development) — **NOT RUN**

`IDEA-435` / `IDEA-436`; exact architecture and safety boundary in
`33_PARTS_ENGINEERING_FINAL_RECONCILIATION.md` §7. This section does not authorize a harness, deployment or
Parts implementation. Use one explicit ordinary canonical Development vehicle on a safe straight. The harness
must refuse outside Development and from a player command, capture the exact pre-test profile, enforce a short
TTL, restore on every exit and never call `clearAllPerformance`.

| # | Smallest live proof | PASS condition | State |
|---|---|---|---|
| §AN1 | Baseline the named Hella/MaiMai at full throttle on the same straight; capture `getPerformance`, target ID/record and telemetry. | Vehicle comfortably exceeds the proposed 80 km/h test cap; pre-test profile is recorded. | **NOT RUN — no harness built** |
| §AN2 | Compose one Development limiter input to `{topSpeedKph=80, accelerationScale=0.50, taperKph=12}`, apply it once through server `setPerformance`, then read it back. | Input, final profile and exact matching read-back are logged; no independent writer is invoked. | **NOT RUN** |
| §AN3 | Repeat the baseline drive under §AN2. | Clearly slower pickup and a stable plateau near 80 km/h, with telemetry evidence and no hunting/rubber-banding. | **NOT RUN** |
| §AN4 | Restore the exact captured baseline, then reload/stop the harness. | Read-back returns to baseline; vehicle again exceeds 80 with baseline-like pickup; no profile remains after teardown. | **NOT RUN** |
| §AN5 | Run A only: homologation `{120, 0.80, 15}`. Restore. Run B only: temporary limiter `{90, 0.90, 10}`. Restore. | Read-back and physical behavior match each distinct individual profile. | **NOT RUN** |
| §AN6 | Run A+B through the one composer, using the test-only expected result `{90, 0.72, 10}`. | Final profile differs from A and B; car plateaus near 90 and accelerates more slowly than B-only. Last-writer output is a FAIL. | **NOT RUN** |
| §AN7 | Remove B while A remains, then remove A while B remains; finally remove both. | Recomputes A, then B, then exact baseline. Removing one input never clears the other. | **NOT RUN** |
| §AN8 | Inspect server/client logs and the target after abort, disconnect and resource stop. | Every path produces one restoration receipt; no `[ERR]`, stranded cap, DB/schema write or effect on another vehicle. | **NOT RUN** |

Passing §AN1–§AN4 proves the carrier. Passing §AN5–§AN8 proves composition for the three governor dimensions only.
Neither result proves grip, brakes, suspension, steering, tires or above-native power.

---

## §AO - Gate 6 Development-only input-mediated brake proof - **NOT RUN**

`IDEA-442`; exact semantic/safety boundary in
`34_GATE6_INPUT_AUTHORITY_REQUIRED_MOD_AUDIT.md` sections 8-10. This is a local companion experiment, not a
native brake-force test, not Parts, and not sanctioned enforcement. It needs no NCM server change or schema.
Do not begin until the temporary harness records distinct raw/merged/transformed values and neutralises the
virtual pad on tick failure (`KB-110`, `KB-111`).

Use one ordinary known vehicle, one flat safe straight, repeatable 80 km/h entry and unchanged
weather/damage/setup. Run A/B/A three times each: cap 1.00, cap 0.55, restored cap 1.00.

| # | Smallest live proof | PASS condition | State |
|---|---|---|---|
| §AO1 | Start the test-only companion with cap 1.00; press/release every axis; deliberately stop it once. | Monotonic log carries physical normalised, merged, cap, transformed, virtual-update success and age. Stop/reset leaves every virtual axis neutral. | **NOT RUN - no harness built** |
| §AO2 | Baseline three full-pedal stops from 80 km/h. | Raw and virtual brake reach about 1.00; game snapshot/HUD follows; entry speed, stop time and distance are repeatable enough to distinguish the next condition. | **NOT RUN** |
| §AO3 | Repeat three stops with cap 0.55. | Raw pedal still reaches about 1.00; transformed virtual and game brake remain bounded near 0.55; stopping time/distance materially increase. | **NOT RUN** |
| §AO4 | Restore cap 1.00 and repeat. | Virtual/game brake and physical result return to the baseline envelope. No setting or transformed output survives restart. | **NOT RUN** |
| §AO5 | During a stationary safe check, inject/induce one harness tick failure or disconnect. | Watchdog logs once, neutralises the pad and aborts. No stale throttle/brake/steer remains. | **NOT RUN** |
| §AO6 | Inspect client/companion logs and the vehicle afterward. | No server/schema/Parts write, no Production change, no claim of native brake-force modification. | **NOT RUN** |

Passing AO proves only that command mediation routed through the companion can create a convincing physical
braking consequence. It does not prove controller/keyboard coverage or competitive integrity. A static
low-speed steering clamp may be tested afterward as a separate bounded observation; dynamic steering feedback
is outside AO.

---

## §AP - real RB15 + NCM liveries RequiredMods acceptance - **COMPLETE FOR ITS PURPOSE. AP1-AP4 PASS; AP5-AP6 retired as moot (L145)**

`IDEA-448` / `IDEA-450`; exact forensic result and package hashes in
`35_REQUIREDMODS_FORENSIC_AUDIT.md`. KB-112 proves why the old run failed: NCM advertised public HTTP and the
launcher discarded the URLs before download. This proof is independent of AN/AO and must not delay them. Do not
create a dummy package and do not rebuild the real packages to manufacture a pass. The owner explicitly
authorised the currently whitelisted Online world for the public-HTTPS proof on 2026-09-25 and retained the
launcher/game checks personally; L137 supersedes the earlier Development-only operational limit.

Prerequisites: either loopback HTTP for a same-PC Development proof or a valid HTTPS resource origin for any
remote client; current compatible launcher/server builds; real ArchiveXL and TweakXL dependency packages through
an authorised current path; save and named-file backups; a confirmed empty test world. The evidence must label
which transport was exercised. Production deployment/restart is outside this contract unless separately authorised.

| # | Smallest live proof | PASS condition | State |
|---|---|---|---|
| §AP1 | Before Connect, capture the master row and server boot state for the real two NCM packages plus ArchiveXL/TweakXL: IDs, versions, hashes, byte sizes, classification, usable URLs, four-package digest and `unsecured=true`. Independently GET and hash every advertised blob from the client machine. | Every URL survives launcher sanitation, every exact byte/size matches, dependencies use a real hosted/resource identity rather than absent index IDs, and no secret/Warden endpoint is exposed. Loopback HTTP passes only as a labeled same-PC proof; a remote proof requires HTTPS. | **LIVE PASS 2026-09-25 14:56-15:00 UTC — Online boot: 4 declared, digest `06ab5485585f57f29cb5a1ad30b3e99bcdbd99985216765f76e7d01a268c90a7`, enabled/unsecured true. Master row: four `https://52-60-225-137.sslip.io:11779/...` URLs, correct executable/inert classes, zero players. Let’s Encrypt TLS 1.3 certificate trusted. External full downloads matched all four declared sizes and SHA-256 values; every ETag matched its hash; RB15 Range returned 206 with bytes 0-1023/38537004. Caddy public 11779 -> OPEN//77 loopback 11782; Warden remained loopback 11780.** |
| §AP2 | Case A: with the current manually installed RB15/livery files present and backed up, click Connect, read the warning and explicitly consent. Capture launcher resolution/fetch/cache/inspection/collision/projection receipts. | No `Unverifiable`; all four packages resolve. Any manual-file overlap is named and handled by the world-profile journal rather than silently overwritten. | **LIVE PASS 2026-09-25 (owner) on the consent half; journal half NOT EVIDENCED.** The owner received the unsecured-world warning, then the RequiredMods review/consent UI naming all four packages - TweakXL, ArchiveXL, NCM RB15 Team Liveries, RB15 F1 car only/no ERS - each presented as **Not reviewed**, and chose **Download and Join**. **No `Unverifiable` appeared. `KB-112` is closed as a delivery blocker.** Four `Not reviewed` verdicts match Report 35's `safety=unknown` attestation finding exactly. **Journal half now also PASS, from the launcher's own log (2026-09-25 11:00:59-11:01:01 local = 15:00-15:01 UTC):**
`unsecured world: accepting unreviewed executable content in 'tweakxl' ('red4ext/plugins/TweakXL/TweakXL.dll')` and the same for
`'ArchiveXL' ('red4ext/plugins/ArchiveXL/ArchiveXL.dll')` — **executable-root delivery, evidenced**; then
`modstack: replacing an unmanaged copy of archive/pc/mod/ncm_rb15_liveries.archive (ncm-rb15-liveries)` immediately followed by
`modstack: kept the copy of archive/pc/mod/ncm_rb15_liveries.archive that was already there (705a3c2207b0)`. **The overlap was
named and the existing copy was kept, not silently overwritten** — exactly the PASS condition. Receipt:
`projected 387 file(s) — 2 added, 1 repaired, 0 removed, 3 linked, 0 copied`;
`world 'NCM Online': projected 2 file(s), removed 0, kept 384 in place.` |
| §AP3 | Let the launcher boot/connect. Capture `OP77_WORLD_MODS_DIGEST`/launcher context, RED4ext, ArchiveXL and TweakXL logs; then request/spawn the real RB15 and inspect every NCM team livery in game. | Expected digest is active; loaders initialise; RB15 record exists and drives; expected livery records/appearances are actually available. A file-on-disk check alone is not a PASS. | **PARTIAL 2026-09-25 (owner).** The launcher progressed through **Preparing server mods** and **Preparing your session** and the owner **entered NCM Online** - server log confirms `connected: player=1 name=easporks` at 15:38:26 UTC and `ready:` at 15:38:43. That proves fetch, hash, projection, boot and session entry. It does **not** prove loader initialisation, the RB15 record, or any livery: no RED4ext/ArchiveXL/TweakXL log was captured, no vehicle was spawned, no livery inspected. **Upgraded 2026-09-25 from on-disk artifacts — most of this row never needed a human.**
`<game>/red4ext/logs/red4ext-2026-09-25-11-37-52.log`: `ArchiveXL (version: 1.27.1, author(s): psiberx) has been loaded`,
`TweakXL (version: 1.11.4, author(s): psiberx) has been loaded`, `Open77 (version: 0.0.1…) has been loaded`, `3 plugin(s) loaded`,
then a clean `…has been unloaded` trio at 11:40:14 matching the 11:40:31 disconnect. **The exact declared versions initialised.**
`red4ext/plugins/ArchiveXL/ArchiveXL-2026-09-25-11-37-53.log`: `Loading "fable5.archive.xl"...`,
`Loading "ncm_rb15_liveries.archive.xl"...`, `[Localization] Merging entries from "fable5\rb15\localization\en-us.json"...`.
**Both archives loaded, no errors.** What is left of this row is two in-world observations with no artifact behind them:
**does the RB15 exist and drive, and do the NCM liveries look right.** Both are Online observations; neither needs Solo (`L144`).
**RETIRED 2026-09-25 (`L145`).** The two remaining in-world looks — does the RB15 drive, do the liveries render —
died with their subject: the owner deleted both packages from Warden on Production. **Do not ask anyone to drive an RB15.**
The pipeline half of this row stands as PASS. |
| §AP4 | **RE-SCOPED 2026-09-25 (`L144`, `KB-121`).** Disconnect/reconnect Case A and verify the ten named RB15/livery destinations on disk. The Solo half is separated out as §AP4b. | Reconnect reuses cache without corruption; every pre-existing manual byte is preserved. | **PASS.** *Reconnect:* three further Connects at 11:03:39, 11:28:26 and 11:37:51 each logged `modstack: projected 0 file(s), removed 0, kept 387 in place` — **nothing refetched, nothing rewritten, three times over.** *Manual files:* all ten destinations present and readable; `fable5.archive` 38,821,888 B, `ncm_rb15_liveries.archive` 8,003,584 B, the five RB15 tweaks and the livery tweak all intact. **Their mtimes are 2026-08-14, 08-30, 09-19 and 09-20 — all weeks before the 09-25 join — so the projection did not rewrite them.** |
| §AP4b | Does a world-mod file leak into the Solo profile? | No world file appears in Solo; the Solo profile is unaffected. | **NOT RUN; BLOCKED BY OWNER CHOICE (`L144`) — do not schedule.** The owner does not leave NCM Online. This is an OPEN//77 profile-isolation question rather than an NCM one; the launcher's `World reconcile keeps 343 file(s) from the other layer in place` line shows it maintains layers deliberately. Recorded, not owed. |
| §AP5 | Case B: isolate the manual RB15/livery files and reconnect, to show OPEN//77 alone supplies the set. | — | **RETIRED AS MOOT (`L145`).** The packages are deleted from Production. More importantly the row was mis-framed: the **pipeline** is proven — transport, consent, executable roots, projection, loader init, archive load — and Case B would only have shown whether one already-present file came from the host or from disk. That is custody trivia about a package being deleted, not a capability gap. **NCM has no unproven delivery capability; NCM has unwritten packages.** The first real NCM package carries its own receipt. |
| §AP6 | Park/remove the RequiredMods set, reconnect, restore. | Projection removed cleanly; no unrelated package or save changed. | **SATISFIED BY §AS (`L145`).** The owner removed both packages in Warden; the public manifest now declares two loaders at digest `67ad384b…`, and Development is parked at the empty-set digest. |
| §AP7 | Review all launcher/server/resource/loader logs for both cases. | No `[ERR]`, hash/root/traversal/collision ambiguity, partial fetch, stale pending journal or unexplained foreign-file change. Evidence covers every stage from consent through in-game content and restoration. | **NOT RUN** |

Passing AP proves the existing inert vehicle/livery path and their real executable loader dependencies on the
exercised unsecured world. It does **not** prove a future NCM control extension, secured exact-hash review,
runtime heartbeat/readiness or anti-cheat. Those are later, separate proofs; the real-package proof comes first.

### Re-scope note, 2026-09-25 (`L144`, `KB-121`)

This section was drafted around what a player *sees*. Most of it was recorded by the stack all along, in
`%LOCALAPPDATA%/Open77/launcher.log`, `<game>/red4ext/logs/` and `<game>/red4ext/plugins/ArchiveXL/*.log`, at
higher precision than a human could report. Reading those closed §AP2's journal half, most of §AP3 and all of
the runnable part of §AP4 in one pass, and removed a request that the owner enter Solo — which `L144` had
already ruled out. **Timestamps: the launcher and game logs are local (UTC-4); the NCM server log is UTC. The
join is 11:38 local = 15:38 UTC.**

**Nothing is left. Closed 2026-09-25 (`L145`).** Both remaining items died with their subject when the owner
deleted RB15 and the liveries from Warden. The pipeline is proven; what NCM lacks is packages of its own,
which is a build task and not a proof debt.

---

## §AQ - the KB-113 spawn/location fix, live - **NOT RUN**

`KB-113`; fix deployed to Online 2026-09-25 15:36 UTC and present in the working tree, uncommitted (`KB-115`).
This is the live PASS the fix is owed (L69). **It costs no separate session:** §AP2 requires the owner to click
Connect and join, which is the same join this section observes. Capture both on one Connect.

The five parts of the fix, each with the symptom it removes: `saveLocation` now gates on the `KB-60` readiness
rule rather than on position validity; `Location.valid` gained a vertical band (`minZ = -100`, `maxZ = 1200`)
returning `below_world`/`above_world`, which refuses the already-poisoned row on the way out and is therefore
self-healing without DB surgery; `shouldRestore` refuses `same_session`; `Location.alreadyThere` skips a
teleport within 3 m; and save refusals log once per reason per session, because *saves were entirely silent*,
which is how a write of the world origin hid for two days behind a correctly-worded restore line.

| # | Smallest live proof | PASS condition | State |
|---|---|---|---|
| §AQ1 | Join Online as a driver with a poisoned stored position (Lord Inateur `a5ea6289`, `72519ab3` or `fe4a7a7e` all qualify — the deepest recorded fall was z = -906.4). | The driver arrives where the platform placed them. No origin teleport, no fall. The poisoned row is refused on read with `below_world`/`above_world` named in the log. | **LIVE PASS 2026-09-25 15:38 UTC, server-side.** Driver `72519ab3` joined 2 minutes after the fix deployed and the log reads `location: NOT restoring driver=72519ab3 (below_world) -- default spawn` at 15:38:45. `ready:` placed them at `x=2566.9 y=112.6 z=78.6` — a real position. **The self-healing half is proven:** the poisoned `0.0,3.6,-906.4` row written at 15:29 was refused on read without DB surgery. |
| §AQ2 | Watch the same join for a second arrival. | **No double spawn.** No `fade = true` teleport follows the platform's placement — `alreadyThere` suppresses it within 3 m. This is the owner's *"why do i spawn in twice every time?"*. | **STRONG INDIRECT PASS; visual confirmation still owed.** No restore of any kind fired on the 15:38 join, so no teleport followed the platform's placement and there was nothing that could produce a second arrival. `alreadyThere` was not itself exercised, because the restore was refused earlier in the chain. One owner join reporting "spawned in once" closes this. |
| §AQ3 | Read the `location:` lines for the join window. | A save refusal is **logged with its reason** rather than passing silently. At least one refusal reason appears for a player who has not yet reached a playable world. | **LIVE PASS 2026-09-25 15:38 UTC.** `location: not saving for driver=72519ab3 -- ncm-ready=NO in-world=NO platform-stage=none (not a position anyone is standing at)` at 15:38:36. All three readiness facts are named in one line. **The silence that hid the origin write for two days is gone.** |
| §AQ4 | Drive somewhere distinctive, disconnect deliberately, reconnect. | **L110 works for the first time:** the driver returns to where they logged out, not to the origin and not to the bootstrap spawn. The disconnect save is exempted for anyone who was playable this session; the `same_session` refusal does not eat it. | **NOT RUN** |
| §AQ5 | Confirm the join spawn is NCM's and not a gamemode's. | No `freeroam:join_spawn` marker weapon, no death on join (`KB-100`), and no restore to `-1430.3, 1257.7, 23.6`. | **NOT RUN** |

A PASS here closes `KB-113` and is the first live evidence that `L110` — *where you log out is where you log
in* — has ever actually worked. It does not close `KB-101`, which is the same family and remains recorded.

### The owner's fall-through, resolved against the log (2026-09-25)

The owner reported falling through the world around the RequiredMods join and correctly said the behaviour
predates it. The server log dates it exactly. `easporks` / driver `72519ab3` joined **four** times:

| Join | `ready:` position | What NCM's location system did | Fix deployed? |
|---|---|---|---|
| 15:01:35 | x=2566.9 | `restored ... to 0.0,3.6,0.5` (the origin) | no |
| 15:04:14 | x=2566.9 | `restored ... to 0.0,3.6,0.5` (the origin) | no |
| 15:29:03 | x=2566.9 | `restored ... to 0.0,3.6,-906.4` (**into the fall**) | no |
| **15:38:26** | **x=2566.9 y=112.6 z=78.6** | **save refused with a reason; restore refused `below_world`; no teleport at all** | **yes, 15:36:15** |

**The fall-through is KB-113, it happened on the pre-fix joins, and it did not recur on the post-fix join.**
It is not attributable to RequiredMods, and the two should not be conflated. §AQ4 (log out somewhere
distinctive, reconnect, arrive there) is the remaining substantive row and is still owed — the 15:38 session
lasted two minutes and ended in `connection_closed`, so L110 has still never been observed working.

---

## §AR - are drive-model handling values live, spawn-cached, or restart-bound? - **NOT RUN; SUPERSEDED AS METHOD; DEFERRED BY OWNER (L143)**

`IDEA-455`; rationale and the conflicting evidence in
[36_DRIVEABILITY_MOD_CARRIER_ASSESSMENT.md](../36_DRIVEABILITY_MOD_CARRIER_ASSESSMENT.md) §4.

> **DO NOT SCHEDULE THIS. DO NOT ASK THE OWNER TO RUN IT.** On 2026-09-25 the owner ruled (**L143**) that they
> will not change mod environments or return to single-player to answer a question existing mods may already
> have answered, and set a standing order: **existing-implementation research → forensic source inspection →
> identify the residual unknown → only then propose an experiment.** Applying that order answered this section
> without running it. Report 36 §4 now classifies the drive model as **SPAWN-CACHED**, corroborated by Vehicle
> Physics Config's stated engine limitation and resummon-based UX, by the discovery that Direct Wheel's
> contradicting CET module is **not shipped by its own installer**, and by the live `WheeledPhysics` struct
> being a per-instance copy of the record. The rows below are **retained unrun** so a future session with a
> reason to confirm it directly finds the design already written. Report 36 §11 holds the residual unknown,
> which is about **writing** the live instance and is not this experiment.

**This is an offline single-player experiment.** No server, no OPEN//77, no NCM code, no Production, no Parts,
no schema, no deployment. Back up saves first (AGENTS.md). It exists because Direct Wheel's CET module writes
`vehDriveModelData` flats every frame while driving and its README calls the same values *"(Requires game
restart to apply)"* — both cannot govern the same field on the same build, and the answer decides whether
Parts, Chrome and wear can ever be **felt** in-session or only from the next spawn.

Method: resolve `<vehicle record>.vehDriveModelData`, capture the stock flats, drive a repeatable straight and a
repeatable constant-radius turn, then observe the same car in three states. Halve `maxWheelTurnDeg` — a change
too large to mistake for run variance. Restore the captured values at the end and verify by read-back.

| # | Smallest proof | What each outcome means | State |
|---|---|---|---|
| §AR1 | Write the changed flat **while seated and moving**. Repeat the constant-radius turn without leaving the car. | Turn-in changes ⇒ **LIVE**: handling is a real-time carrier and Report 33 §6.8's recompute-event list transfers wholesale. No change ⇒ continue to §AR2. | **NOT RUN** |
| §AR2 | Dismount and re-mount the same vehicle. Repeat the turn. | Changes now ⇒ read at mount. Still nothing ⇒ continue to §AR3. | **NOT RUN** |
| §AR3 | Despawn and respawn the vehicle. Repeat the turn. | Changes now ⇒ **SPAWN-CACHED**: handling is a *configuration* carrier. Parts and setup still work; **wear and Chrome do not**, and must stay on `setPerformance` or stay simulated. Still nothing ⇒ **RESTART-BOUND** and effectively useless as an NCM carrier. | **NOT RUN** |
| §AR4 | Restore every captured flat. Read each one back. Repeat the turn. | Read-back equals the captured value and the car returns to baseline behaviour within ordinary run variance. A probe that cannot restore is a probe that must not be repeated. | **NOT RUN** |
| §AR5 | While the change is active, observe a **second** vehicle of the same model — AI traffic is sufficient. | The second car is affected too. This is the per-record blast radius (`IDEA-454`) made visible rather than argued, and it is the single fact most likely to be forgotten later. | **NOT RUN** |

Passing §AR proves a **single-player engine behaviour**. It proves nothing about OPEN//77, nothing about
delivery, nothing about multiplayer integrity, and it authorises no carrier. Its entire value is that three
different design futures collapse to one before any of them is designed.

---

## §AS - RB15 withdrawal from public redistribution - **DONE 2026-09-25 by the owner in Warden (L145)**

`IDEA-465`; owner ruling **L142**. NCM has not established sufficient redistribution permission for the exact
RB15 package it was hosting and will cease public redistribution pending permission or provenance resolution.
The NCM liveries are NCM-owned but are RB15 content and park with it (Report 36 §7.1).

**DONE.** The owner deleted both packages directly in Warden on Production rather than through a script. The
public manifest now declares ArchiveXL 1.27.1 and TweakXL 1.11.4 only, at digest
`67ad384b2d8bcc70c2eeedd113e2abc654ce04d23b3fb8098ae81ae2937d499d` (was `06ab5485…`). Development was parked
the same day and restarted: `enabled=false`, `mods:[]`, empty-set digest. Local blobs, declarations, hashes
and authoring sources are untouched on disk - the withdrawal removed a public offer, not NCM's work.

The rows below are kept as the record of what the removal had to satisfy. §AS4's question is answered by
choice: the two loaders **stay staged**, delivering no NCM content today, so the pipeline is already correct
the day NCM's first real package exists.

| # | Smallest live proof | PASS condition | State |
|---|---|---|---|
| §AS1 | Before any change, capture the current four-package declaration, digest, master row and the served blob listing. | A complete pre-withdrawal record exists, so the exact state being left can be reconstructed or restored. | **NOT RUN** |
| §AS2 | Remove `rb15-f1-inert-v10` and `ncm-rb15-liveries` from the Online `requiredMods.packages` declaration through a targeted `tools/staging/` script. Restart. | The server boots with the reduced set; the new digest differs from `06ab5485…`; the master row advertises only the remaining packages. | **NOT RUN** |
| §AS3 | Confirm the two withdrawn blobs are no longer publicly fetchable over HTTPS, and that the retained packages still are. | Withdrawn blob URLs no longer serve bytes; retained package URLs keep exact size/hash/ETag/Range behaviour. No Warden route or secret exposed. | **NOT RUN** |
| §AS4 | Decide and record what remains declared at all. With RB15 and the liveries gone, ArchiveXL and TweakXL have no NCM content to load. | Either the required set is parked entirely, or the retained loaders have a stated purpose. **An empty-purpose required set still costs every joiner the unsecured badge and the consent gate for nothing** (`IDEA-461`). | **NOT RUN** |
| §AS5 | Connect once after the change. | Consent names only what is actually declared; no `Unverifiable`; session entry still works; no stale digest mismatch forces a relaunch loop. | **NOT RUN** |
| §AS6 | Confirm Development's intended package set and documentation no longer treat RB15 as an active NCM dependency. | `IDEA-460`'s Development correction does not reintroduce it; OPS_STAGING, NOW.md and the package tables agree. | **NOT RUN** |
| §AS7 | Verify local preservation. | Every blob, declaration, hash record and authoring source is still on disk and still hash-identical. Withdrawal removed a public offer, not NCM's work. | **NOT RUN** |

Passing AS proves NCM stopped publicly redistributing content it had not established the right to serve. It
proves nothing about permission, which is a separate conversation with the author, and it does not authorise a
substitute open-wheel mod - the owner ruled explicitly against substituting one now.

## §AT - the NCM Carrier, from "does the game still launch" to "a car feels the weather" - **IN PROGRESS**

`L146` / `IDEA-472`. The carrier is one RED4ext plugin carrying drive-model effects, final-command authority
and force feedback. It is built and offline-green; nothing below has been run.

**The carrier is hosted on NCM Online and installed by the launcher. There is no manual copy step.** Development
proved server wiring but its Unlisted/raw-address join has no master catalogue digest (`KB-126`), so the owner
authorised the whitelisted Production world for the actual delivery proof (`L147`).
An earlier draft of this section asked for one "for safety"; that was backwards and it was extra QA invented
on top of the real thing (owner, 2026-09-25). The launcher path is the path that ships, so it is the path
worth testing -- and it is also the more recoverable one, because the uninstall is already written:

```
python tools/staging/publish-carrier.py tools/open77/server --remove
.\tools\build-carrier.ps1 -RestartDevOnly
```

Rejoin and the launcher removes what it projected. A hand-copied DLL has to be hunted down instead.

The load risk itself is unchanged and is handled in code, not by procedure: every startup stage is
independently wrapped, offsets are RTTI-resolved with a credibility bound that refuses rather than writes,
and the plugin declares `RUNTIME_VERSION_INDEPENDENT` so a game patch does not refuse the load outright.
`ncm_carrier.log`, written beside the DLL, is the only diagnostic that survives a failed load -- read it
first, always.

**Everything here runs in NCM Online. Nothing requires Solo** (`L144`).

| # | Operation | Expected | Result |
|---|---|---|---|
| §AT0 | Build, store the exact zip, declare it as the sole required package, and restart the test world. | The DLL builds; the package is stored, declared, and requiredMods is enabled with **RB15 and the liveries absent** (`L142`). The server restarts and the manifest reports a new digest with `ncm-carrier` in it. | **PASS on Development and Production 2026-09-25; current build 0.1.1.** Production was protected first by a verified 63-table database dump and operator-state archive (`L147`). Carrier 0.1.1 is 868,295 bytes, SHA-256 `6966a75d...06301`, 3 files under `red4ext/plugins`; it replaced and pruned 0.1.0. Public HTTPS full download matched hash/size; Range returned 206 with the hash ETag; manifest digest is `e0ad7ec9...bbde2`. Post-restart: 41-resource graph green, zero migrations, no boot errors, 11 machine records. Tooling defects caught before activation: `KB-129`, `KB-130`. |
| §AT1 | From a fully stopped game, launch Cyberpunk and join **NCM Online** through the launcher catalogue. | The consent gate names **NCM Carrier** as executable content into `red4ext/plugins/`; the launcher projects it before process start; **the game launches and the join completes.** `ncm_carrier` appears in `<game>/red4ext/logs/` as loaded, and `red4ext/plugins/ncm_carrier/ncm_carrier.log` names its version, whether the bridge is listening, whether the hook installed, and what device it found. **A declined hook is a PASS** - effects and force feedback do not depend on it. | **PASS ON PRODUCTION WITH 0.1.1, 2026-09-25 20:25 UTC.** Launcher used digest `e0ad7ec9...bbde2`; RED4ext loaded NCM Carrier 0.1.1; validation passed; Open77 reached active; server connected/ready; the plugin log exists and reports bridge up plus device inspection. The `.102` anti-piracy/file-verification change was not the direct failure: lifecycle timing was. The “hook installed” subclaim is invalidated separately by `KB-135` and is not counted as input proof. |
| §AT2 | Still in the world, check the client log. | `carrier_bridge` connects: `carrier <version> | hook=...`. The bridge is on by default now, so no `/ncm.ffb on` is needed. | **PARTIAL PASS.** The client created the surface and logged `companion connected`; the carrier logged `NCM connected to the bridge`. Version/capability receipt is missing because 0.1.1 never calls its own device/health sender (`KB-134`). Transport is proven; typed handshake is not. |
| §AT3 | Open the NCM panel, WHEEL/PEDALS tab. | The wheel is named, classified, and its rung shown against the ladder for that class. An unrecognised wheel reads `unknown` and gets the lowest ceiling - **it is not silently upgraded**. | **NOT RUN** |
| §AT4 | `ncm.machine weather rain` on the server. Then **spawn a fresh car** and drive it. | The server publishes projections; the client pushes them; the carrier log reports `projection v1 on <record>: N applied`. The car has less lateral grip and longer braking. **Spawn-cached: a car already in the world does not change** - that is correct behaviour, not a failure. | **NOT RUN** |
| §AT5 | `ncm.machine weather sunny`, then spawn again. Then disconnect and inspect the carrier log. | Grip returns on the next spawn. On disconnect the carrier restores every captured original and records the restoration count; a subsequent Online launch starts from clean originals before applying the current projection. **No Solo/profile switch is requested** (`L144`). | **NOT RUN** |
| §AT6 | One drive with force feedback armed. Then quit and read the carrier log. | Force is felt: weight building with speed, texture as the tyres let go, engine hum rising with revs. On shutdown the log prints `measured <channel>: peak ... over N frames` for every channel. **This closes `KB-106`** - if `suspLong`/`suspLat` peak far below 0.05 the road channel has been inaudible and `kRoadScale` is wrong. | **NOT RUN** |
| §AT7 | Disconnect, rebuild with any change, `-PublishDev` again, rejoin. | The digest changes, the launcher fetches the new blob rather than reusing the cached one, and the old carrier blob is pruned from the store. **This is the loop the whole thing exists to make cheap** - a code change reaches the game in one command and one join. | **NOT RUN** |

### What passing §AT does and does not establish

It establishes that NCM can ship native code of its own through its own delivery pipeline -- **AT0 and AT1
together are NCM's first own package, delivered by NCM's own launcher path** -- that the record carrier works
end to end, and that force feedback survived moving inside the game.

It does **not** establish per-player differentiation - two drivers of the same model still share one record,
which is Report 36's hardest constraint and the one that sits across the premise of a parts economy. It does
not establish anti-cheat; a client that declines to apply a projection simply has more grip than everyone
else and there is no witness (`IDEA-458`, `L135`). And it does not establish that the flat write is robust -
`IDEA-477` records that this is the least-verified code in the plugin.

**Production is a separate decision on a separate day.** `L146` does not authorise it.

## §AU - live per-instance vehicle physics, from "does the detour fire" to "a car slides on command" - **AU1-AU5 PASS on Production**

`L148` / `IDEA-494`-`IDEA-499`. §AT asks whether a *record* projection reaches a car, and is blocked at
`KB-136` because no projection has ever arrived. §AU is a different route to the same product goal, opened
by re-reading the owner's March 2026 `ManualClutch` experiment: intercept the **physics step** instead of
the **input step**, and change the force the solver is about to apply.

**Every row below ran on NCM Online, on the whitelisted Production world, with the owner driving.** The
first four rows are read-only; only AU5 writes, and only under `L148`'s five properties.

The interception point is `RigidBody::Recalculate`, RED4ext address hash `593628708`, whose single argument
**is** the vehicle's `vehiclePhysicsData`. The hash was verified present in this build's own
`bin/x64/cyberpunk2077_addresses.json` *before* anything resolved it, because
`UniversalRelocBase::Resolve` calls `ShowErrorAndTerminateProcess` on a miss -- a MessageBox and a dead
process that no `try`/`catch` in the plugin can intercept. That pre-check is what keeps the carrier's
cardinal rule intact on a patch day.

| # | Operation | Expected | Result |
|---|---|---|---|
| §AU1 | Attach the detour and write nothing. Log tick rate, and for the fastest body its velocity, mass and the back-pointer at `+0x180`. | The detour fires; the argument is `PhysicsData`; velocity at `+0x18` tracks NCM's own speedometer and mass at `+0x1BC` looks like a car. | **PASS (0.1.2, 2026-09-25).** ~950-1000 calls/s while driving. `v=16.44 [ncm=16.44 d=+0.01]`, `v=24.69 [ncm=24.62 d=+0.07]`, `v=9.07 [ncm=9.07 d=+0.01]` across 0-25 m/s. `mass=1100 kg`, stable. Back-pointer stable for the whole session. One distinct body while driving, ten at world load -- this callsite runs for the player's car, not traffic. No faults, no crash. |
| §AU2 | Capture consecutive calls on one body and read the shape of `force`. | Whatever `force` is, a run of consecutive calls shows it. | **PASS (0.1.3).** A period-16 cycle: one gravity entry, four per-wheel normal loads, a traction pair, a drag pair, zeros. Wheel entries summed to the negation of gravity in all three bursts (183/-184, 182/-182, 182/-182). Units are impulses: `1100 x 9.81 / 60 = 180 N.s` against 182-184 observed. **`force` is sixteen per-contributor writes per frame, not a total** (`IDEA-495`). |
| §AU3 | Identify which wheel is which, and whether a slot keeps its meaning frame to frame. | Cornering separates left from right; braking separates front from rear. | **PASS for ordering; REFUTED for slots (0.1.4-0.1.5).** Ordering is **FL, FR, RR, RL** -- a ring, not row-major -- from three manoeuvres across two cars: (0,3) and (1,2) anti-phase under cornering, a sustained maximum-left loading (1,2), braking loading (0,1). Resting residual `-0.0`, front/rear ~60/40. **Slot indexing is dead:** the thread guard fired immediately and never stopped -- `RigidBody::Recalculate` runs for a single body from **twelve threads**, so cycle length came out 13/14/41/111/402/737 and `modal=14 (17/82)` was noise. Had the guard not existed, that figure would have been reported as a real measurement and a write designed on top of it. |
| §AU4 | Replace the cycle model with per-call classification and validate it by arithmetic. | At 60 fps: ~60 gravity calls, ~240 wheel calls, ~60 complete four-wheel runs, nothing unclassified. | **PASS (0.1.6-0.1.8).** Repeatedly exact: `grav=60 wheel=240 | runs 60 complete, 0 short, 0 long | threads=12 | other=0`. Short runs appear only in the seconds containing hard cornering -- a wheel genuinely off the ground. The horizontal entries decompose cleanly against travel: longitudinal inverts sign under braking (`net=+14.4` accelerating, `net=-14.6` braking) and even resolves the owner's tapped throttle as alternating per-second signs; lateral sits at `avg=0.0-0.2 peak=0.1-2.3` in a straight line and `avg=12.7-19.4 peak=53.9-63.8` cornering. |
| §AU5 | Scale the lateral component by `gripScale` on the player's car, hot-reloaded from config while the game runs. Then set it back to 1.0. | Grip falls without power falling. 1.0 restores default physics exactly, with no restart. | **PASS (0.1.9, 2026-09-26).** `gripScale 1.00 -> 0.70 (WRITING lateral force)` hot-loaded mid-session. `writes=250-320/s`, matching the directed `horiz` count exactly. At 0.70 the owner reported something subtly different but hard to judge; at **0.30, "unmistakable -- unrealistic, over the top understeer"**, which is the expected reading of uniform lateral loss on a front-steered car. `gripScale 0.30 -> 1.00 (inert, no writes)` and the owner reported **instant return to default physics**. No fault, no instability, `[WRITES DISABLED BY FAULT]` never appeared. |

### What §AU establishes, and what it does not

**It establishes live, per-instance, reversible mutation of vehicle physics on an already-spawned car** --
no respawn, no record edit, no TweakDB, no restart. That is the constraint §AT was written around and it is
now sidestepped rather than solved: the record path remains spawn-cached (third-party-confirmed), but the
force path is not spawn-cached at all.

**It does not establish per-wheel friction.** The lateral channel is vehicle-level; the per-corner values
that *are* addressable are normal loads, and scaling those makes a car sag rather than slide. Front/rear
balance is therefore out of reach through this channel (`IDEA-499`).

**It does not connect to NCM.** `gripScale` comes from a JSON file a human edits. Wetness is computed and
published server-side and has never reached the carrier (`KB-136`). Until that transport works, this is a
capability rather than a feature (`IDEA-502`).

**Frame-rate cost of the writes: none measurable.** `grav` per second is the physics frame count, so the
probe measures its own overhead. Driving seconds only: `k=1.00` (no writes) mean 55.6, 21% below 55 frames;
`k=0.30` (writing ~300/s) mean 59.1, 4% below 55. The dips track world streaming -- the same seconds show
the classifier's `zero` count spiking from ~300 to 3,435 and once to 19,320 -- not the writes. If there is
a cost anywhere it is the probe's *reading*, which is why `IDEA-501` proposes switching the measurement
machinery off now that the measurements are done.

## §AV - the three closing experiments: two negatives and a confirmed safety property - **AV1 PASS, AV2 NEGATIVE, AV3 REFUTED**

`L149` / `IDEA-503`-`IDEA-505`. §AU proved a car can be made to slide on command. §AV asks the three questions
that decide what the *shape* of that capability is, and therefore what Parts may be designed against. **Two of
the three came back no.** That is the outcome they were run to produce, and it was cheaper to learn here than
inside a half-built Brakes family.

All three ran on Production with the owner driving, on Carrier **0.1.11 through 0.1.13**. Methodology for AV2
was the owner's: *weaving in a straight line like a formula one car warming up tyres, except it is a poorly
aerodynamic Galena*, with bias set to 0.00, +0.20 and -0.20 in that order.

| # | Operation | Expected | Result |
|---|---|---|---|
| §AV1 | Shift load between the axles by scaling the four per-corner normal-load entries, holding their sum. Confirm the sum still negates gravity. | The residual against gravity stays near zero with a bias applied. If it drifts, the write is wrong and the log says so. | **PASS (0.1.13).** Mean absolute residual **16.08 / 16.19 / 8.90** across bias 0.00 / +0.20 / -0.20, against a gravity impulse of ~180 N.s. Statistically indistinguishable between settings and small against the quantity being redistributed. **The write was arithmetically correct.** It simply had no effect, which is AV2. No fault, no instability, no sag -- the failure mode that killed the naive version of this write in §AU3 did not recur. |
| §AV2 | With the redistribution proven zero-sum, ask the binary that four Part families depend on: **is lateral force in this engine load-dependent?** | If it is, moving 20 percent of the load between axles moves grip between them, and balance, anti-roll, brake bias, per-corner tyre temperature and downforce-as-grip all become expressible without ever finding `insert1`. | **NEGATIVE (0.1.13) -- and the first reading was a false positive.** Duration-controlled lateral capability: bias 0.00 median **111.4** p75 114.2 p90 116.9; +0.20 median **116.8** p75 118.5 p90 119.0; -0.20 median **117.8** p75 120.0 p90 120.6. All within ~5 percent, and if anything the biased runs are marginally *higher*. Yaw-per-unit-steer regression is monotonic in the right direction in the mid speed band (+0.20 slope -0.227, 0.00 slope -0.345, -0.20 slope -0.485) but correlations are only -0.27 to -0.60, because weaving puts yaw out of phase with steer; **it is not load-bearing evidence either way.** **Shifting 20 percent of axle load changed nothing measurable.** |
| §AV3 | Find the orientation quaternion in `+0x20..+0x180` on `vehiclePhysicsData`, to convert world-frame telemetry into body-frame and unlock sideslip. | A four-float group of unit norm that *varies* as the car turns. | **REFUTED (0.1.13).** Every unit-norm candidate in the range -- `+0x80`, `+0xC0/C4/C8/CC`, `+0x100/104/108` -- is **constant**. `quat-vary: every unit-norm candidate is CONSTANT -- none of them is an orientation`. Unit norm plus constancy is the signature of inertia-tensor rows, not attitude. `+0x30` was separately refuted earlier in the session. **There is no orientation quaternion in that range.** It is outside it, stored as a matrix rather than a quaternion, or lives on `vehicleBaseObject`. Note the discriminator itself had to be strengthened mid-session: persistence alone passes a constant, so variance tracking was added -- without it the identity rows would have been reported as an orientation. |

### What §AV establishes

**The per-corner force entries are not a grip channel.** Stated precisely, because the distinction matters:
scaling those entries does not change lateral capability. That is **not** the same as *grip is
load-independent in this engine*. The entries we scale may be the **output** of the suspension rather than
the **input** the tyre model reads, in which case load-dependence exists and we were writing downstream of
it. What §AV2 rules out is **this channel as a control surface**, which is the thing that had to be known
before Parts began.

**Consequence, and it is a real narrowing.** Zero-sum load redistribution is withdrawn as an actuator. No
front/rear balance, no brake bias, no anti-roll, no per-corner tyre temperature and no downforce-as-grip
through this route. `IDEA-499` moves from *plausible* to **refuted for this channel**. `insert1` is now the
only credible per-corner route and is bookmarked in full at `IDEA-503`; `IDEA-505` tells Parts how to ship
correctly whether or not it ever lands.

**No body-frame telemetry.** Without attitude, sideslip angle, body-frame accelerations and any g-g diagram
stay out of reach. Speed, world-frame velocity, angular velocity, per-corner load, driver inputs and mass are
all unaffected and remain available.

### What §AV does not change

§AU stands in full. The lateral `gripScale` write is proven, reversible, per-instance and per-player, and
none of tonight's negatives touch it. **The capability that shipped is the capability we keep.**

## §AW - the force channel widened: two levers confirmed, one refuted, and the reason why - **AW1, AW2 PASS; AW3 NEGATIVE**

`L151`. §AU proved one lever. §AV established the shape of the channel. §AW asks whether the same
interception generalises, and the answer is yes for force along travel and **no, structurally, for anything
needing a moment**.

Driven on Production by the owner, Carrier **0.1.15**, one lever at a time with a return to inert between
each. The carrier logged every change, so what was active is a record rather than a recollection.

| # | Operation | Expected | Result |
|---|---|---|---|
| §AW1 | Scale the along-travel force component while it is PUSHING (`driveScale`), 0.50 / 1.50 / 1.90 / 2.00 / 0.30. | Acceleration changes; cornering grip does not. | **PASS.** Owner: *"drivescale confirmed accel, tried different things"*. Exercised across the full clamp range including both bounds. **This was never speculative and I should have said so earlier: the owner's own March 2026 anti-crawl hook does exactly this** -- decompose against velocity, remove only the forward-pushing component, let braking, drag and lateral pass through. `driveScale` is a re-implementation of something already proven on this engine. |
| §AW2 | Scale the along-travel component while it is RETARDING (`brakeScale`), 0.50 / 2.00. | Stopping distance changes; power does not. | **PASS.** Owner: *"confirmed brake"*. The sign of the longitudinal component is a measured discriminator, not an assumption -- §AU4 had already shown it inverts under braking and resolves a tapped throttle as alternating per-second signs. |
| §AW3 | Shift normal load LEFT/RIGHT, zero-sum (`rollBias` +0.30, the clamp maximum). | The car leans differently. §AV2 says expect no grip change; §AU3 saw these entries make a car sag, so attitude was the open question. | **NEGATIVE, and the write is proven to have fired.** Owner: *"harder to pin down, i could be convinced its changing but not totally certain"*. The log settles it: `writes=240/s` -- exactly four corners x 60 fps -- with left corners scaled x1.30 and right x0.70 on a stationary car (`v=0.0`, `z=[54 54 36 36]`, residual `-0.0`). Maximum bias, every frame, no lean. |

### Why §AW3 failed, and why it closes the question rather than leaving it open

**`force` at `+0x00` carries no position.** All sixteen per-contributor calls accumulate into one Vector3.
A zero-sum redistribution of the four vertical entries therefore produces a **byte-identical net force**, and
it cannot produce a moment because there is nowhere in that field for a moment to live.

That single fact explains three separate results that had looked like three separate mysteries:

- **§AV2** -- front/rear load shift, no change in lateral capability.
- **§AW3** -- left/right load shift at maximum, no change in attitude.
- **§AU3** -- scaling all four entries DOWN made the car sag. Not a suspension response: that write was not
  zero-sum, so it simply removed upward force and the car sank.

**The per-corner normal-load entries are dead as an actuator.** Not unproven -- refuted, with a mechanism.
They remain excellent *telemetry* (`§AU3` identified the corners; weight transfer reads correctly), and
nothing about reading them changes.

**The consequence is a redirection, not a loss.** Anti-roll, yaw balance and brake bias are all **moments**,
so they need a torque channel. `+0x0C` is the only unexamined `Vector3` in a `force / ??? / velocity /
angularVelocity` layout -- exactly where a rigid body keeps its torque accumulator, inside the struct we
already hold and already write. `IDEA-512` is the read-only probe that settles it, shipped in 0.1.16 with an
oracle rather than a hope: integrating `torque_z` must yield a **positive, roughly constant** implied yaw
inertia against the angular velocity at `+0x24`, and a field that merely varies proves nothing -- which is
the trap `§AV3`'s quaternion fell into until variance tracking caught it.

## §AX - the torque candidate at `+0x0C`: three builds, and it does not validate - **REFUTED as a torque**

`IDEA-512`. §AW3 established that `force` at `+0x00` carries no position, so moments cannot live there --
which left the question of where they do live. `+0x0C` is the only unexamined `Vector3` in a
`force / ??? / velocity / angularVelocity` layout, inside the struct the carrier already holds. This section
is the attempt to confirm it, and the attempt failed.

**All three builds were read-only. Nothing was written and `L151` was never engaged.**

| # | Build | Sampling | Result |
|---|---|---|---|
| §AX1 | 0.1.16 | inside the deep-read block | **Invalid measurement.** The deep read is gated twice -- rate-limited 1-in-16 *and* only for the fastest body that window -- yielding 1-8 samples per second, each standing for 0.3-1s of elapsed time, each then multiplied by `dt = 1/60`. The integration was wrong by 20-60x and irregularly so. What survived: the field is **0.000 parked and reaches 71.5 under cornering load**, and its sign agrees with steering **127/165 = 77%** against 50% chance. Neither depends on the broken `dt`. |
| §AX2 | 0.1.17 | on the gravity entry, once per frame | **`impulseZ = +0.000` in every window** while yaw moved by up to 1.4 rad/s. Not a refutation: the gravity entry is the **first** of the sixteen contributor calls, so it catches an accumulator empty. Zero at frame start and non-zero later is what `force` at `+0x00` does. This was *supporting* evidence wearing a null result's clothes. |
| §AX3 | 0.1.18 | peak per frame, gravity entry as the frame BOUNDARY | **REFUTED.** `impulseZ` is now non-zero, so the sampler works -- but the implied yaw inertia across 45 windows is `positive 32/45 (71%)`, range `-109.0 .. +244.6`, mean `30.2`. A real yaw inertia for this 1100 kg car is ~1200-1500 kg.m2. Not constant, not consistently signed, and off by ~40x. |

### What this establishes, and the honest limit of it

**`+0x0C` is not the yaw torque accumulator.** Integrating it does not predict yaw acceleration, which is the
only test that matters. The 71% positive rate is also close enough to §AX1's 77% steer-sign agreement to read
as *"this field loosely tracks yaw direction"* rather than *"this field causes yaw"* -- and many quantities
correlate with yaw without being its torque.

**The limit, stated plainly: §AX3 stacks two unvalidated assumptions.** It assumes the frame PEAK equals the
frame TOTAL, which holds only if the accumulator fills monotonically and is not consumed or reset mid-cycle.
So this refutes *"this offset, sampled this way, is the yaw torque"*. It does not refute *"a torque channel
exists somewhere"*, and it should not be cited as though it did.

**The process finding is worth more than the result.** Twice in this series the instrument changed rather
than the hypothesis, and both times the first reading looked like an answer -- §AX1's wandering inertia was
the sampler, §AX2's clean zero was the sample point. `KB-143` records exactly this class of error and it was
committed twice more one build after being written down. **Three builds and four owner drives spent, no
conclusion reached, and the stopping decision is the correct output.**

### Where moments go from here

Not through more offset guessing. `ApplyTorqueAtPosition` (`3303544265`) is confirmed present in this
build's address table but its signature is unknown, and `IDEA-513` records that
`DrivingForcesHelper::Apply` (`1989218322`) has a **known** signature from the owner's own March 2026
work -- `void __fastcall(uint64_t*, float)`, already hooked successfully on this engine. If moments are
pursued again, that asymmetry should decide the order.

## §AY - Parts reach a car: the instance channel, end to end - **AWAITING LIVE TEST**

`L152`. §AU and §AW proved three force levers with a config file. §AY asks whether a **fitted part** can
move them -- server-composed, per-player, over the wire -- which is the difference between a capability and
a feature.

Carrier **0.1.24** + `ncm_world` on Production. Command: `/ncm.setup`.

> **Read the `L156` amendment at the end of this section before running any step here.** Four expectations
> in the tables below were written against earlier composition rules and are now wrong on purpose --
> §AY1 (family counts), §AY2, §AY6 and §AY14. The amendment restates them.

| # | Operation | Expected | Result |
|---|---|---|---|
| §AY1 | `/ncm.setup` with no arguments. | Chat lists what is fitted (nothing), the three live families with their lever and evidence, and the nine that cannot be felt live. | |
| §AY2 | `/ncm.setup power_unit 1.5`, then drive. | Acceleration increases. `ncm_carrier.log` shows `handling: driveScale 1.000 -> 1.500 (ACTIVE)`. **The whole chain is under test, not the lever** -- §AW1 already proved the lever. | |
| §AY3 | `/ncm.setup brakes 0.5`, then brake hard. | Stopping distance lengthens; power unchanged from §AY2. Two parts now fitted and both expressed at once. | |
| §AY4 | `/ncm.setup tires 1.3`, then corner. | Grip increases. All three levers active simultaneously from three independent parts. | |
| §AY5 | `/ncm.setup suspension 1.2`. | **A named refusal in chat**, not silence and not a plausible number: suspension has no live quantity on the instance channel. Nothing fitted, nothing changed. | |
| §AY6 | `/ncm.setup power_unit 9.0`. | Applied at **2.00**, the clamp maximum, and the log says `CLAMPED from 9.000`. A silently clamped setup is how a player loses trust. | |
| §AY7 | `/ncm.setup clear`, then drive. | Every lever explicitly back to inert; the car feels standard again. Distinct from sending nothing, which would leave the last setup applied. | |
| §AY8 | Fit a part, then `/ncm.ffb off` (drops the bridge). | `handling: cleared to inert` in the carrier log. A driver who loses the server keeps neither advantage nor penalty. | |

**What a PASS here means and what it does not.** It means the path is real and Parts can change how a car
feels, per player, live. It does **not** mean Parts exist as a game system: there is no inventory, no
ownership, no acquisition and no wear, and `/ncm.setup` is a test instrument that fits synthetic components
directly. What it tests is the mechanism the inventory will use, unchanged.

**The failure mode worth watching for**, because it is the one this design is most exposed to: a lever that
moves in the log but not in the car. That would mean the carrier applied a value the physics step never
reached -- a different failure from §AW3's, where the write demonstrably fired and the channel was simply
incapable of the effect. The log line and the felt result are two separate claims and `KB-142` is the
standing reminder to check both.

### §AY amended by `L154`: eleven families, not three

§AY5 was written when nine families were refused. `L154` allows approximation, so **suspension now works**
and the refusal test moves to `steering`, which is the only family left that cannot reach a force. The
table above stands with §AY5 reinterpreted, and these are added:

| # | Operation | Expected | Result |
|---|---|---|---|
| §AY5 | `/ncm.setup steering 1.2` | **A named refusal** citing `KB-135`: response is not force magnitude and input authority is the driver's. **This replaces the old suspension case, which now passes instead of refusing.** | |
| §AY9 | `/ncm.setup suspension 1.3`, then corner. | Grip increases (composes to about **x1.17** -- `1.30^0.6`). Chat says `[approximated]`. | |
| §AY10 | `/ncm.setup aerodynamics 1.4`, then drive a straight and a corner. | **The trade, which is the headline of `L154`:** grip up (about **x1.18**) and top-end drive DOWN (about **x0.92**) from one part. A wing that added grip for free would make the system a joke. | |
| §AY11 | `/ncm.setup aerodynamics 0.7`. | The trade **reverses**: grip about x0.84, drive about x1.09. Stripping aero is a real choice, not a penalty. | |
| §AY12 | `/ncm.setup chassis 1.25`. | All three levers move together (about **x1.09** each) -- mass is the one approximation that genuinely touches everything. | |
| §AY13 | `/ncm.setup aerodynamics` with **no multiplier**. | An explanation rather than a usage scold: the levers and their directions, why the mapping is defensible, and then `cannot:` lines -- including that it has **no speed dependence**. This is `losses` reaching a player. | |
| §AY14 | Fit power_unit 1.25, tires 1.15, brakes 1.2, suspension 1.2, aerodynamics 1.3, chassis 1.1. | A believable complete car: grip clamps at **1.50** (wanted 1.52, and the clamp is logged), drive about **1.22**, brake about **1.25**, `[3 approximated]`. | |

**What §AY13 is really testing.** Not a string. Whether the system can tell a player what a part will
*not* do for them, in the same breath as what it will. `losses` is the whole of `IDEA-505` once
approximation is allowed, and if it never reaches a human it is decoration.

### §AY amended again by `L156`: eleven DIRECTIONS, and levers that constrain each other

**Why this supersedes numbers above rather than adding to them.** `L154` gave nine families a single lever
each, which left `transmission`, `drivetrain`, `cooling` and `electrical` pointing in the *identical*
direction and differing only in magnitude -- one dial with four labels, which no player could tell apart.
`L156` gives every family a direction in the three-lever space and then couples the levers: drive and brake
are capped against grip.

**No carrier change. No wire change.** The plugin still receives three floats and does not know any of this
happened. Everything below is a server-side composition change, so a client already running Carrier 0.1.24
tests it after a resource restart.

**Two expectations from the `L154` table are now WRONG and are restated here**, because a tester working
from a stale number reports a bug that is not one:

| # | Operation | Was (`L154`) | **Now (`L156`)** | Result |
|---|---|---|---|---|
| §AY2 | `/ncm.setup power_unit 1.5` | drive **1.500** | drive **~1.29**, traction-limited, and chat says so. The engine is not being ignored -- it is being told it has no tyres | |
| §AY6 | `/ncm.setup power_unit 9.0` | clamped to **2.00** | **BOTH rules fire and are reported separately**: clamped 9.000 -> 2.000, then limited 2.000 -> **~1.14** by `traction_ceiling` (grip has fallen to ~0.80 under engine mass). A clamp is the carrier's hard bound; a limit is one lever constraining another | |
| §AY9 | suspension 1.3 -> grip x1.17 | grip **x1.155**, and now brake **x1.068**, drive **x1.027** | | |
| §AY14 | complete car, grip **clamps** at 1.50 | grip **1.473**, drive **1.265**, brake **1.445**, `[3 approximated]`, **nothing clamped and nothing limited** -- a balanced build clears the ceilings, which is the shape the couplings are meant to reward | |

New steps. Every number is the module's own output, not an estimate:

| # | Operation | Expected | Result |
|---|---|---|---|
| §AY15 | `/ncm.setup power_unit 2.0` on stock tyres, then drive. | drive **1.246**, not 2.000. Chat: `driveScale held at x1.246 (asked x2.000) -- power that cannot be put down is not power; fit tyres...`. **The headline of `L156`.** | |
| §AY16 | Then `/ncm.setup tires 1.4` and drive again. | Same engine, now **1.545**. Grip 1.306. **Fitting tyres made the engine stronger without touching the engine** -- the emergent build, and the single most important thing to feel here | |
| §AY17 | `/ncm.setup clear`, then `/ncm.setup brakes 2.0`. | brake **1.200**, limited by `brake_grip_limit`. Past the tyre a bigger disc locks up rather than stops | |
| §AY18 | `/ncm.setup clear`, `transmission 1.4`, drive and brake. Then `clear`, `drivetrain 1.4`, same. | **The aliasing test, live.** Both give nearly the same drive (1.183 vs 1.203). The difference: transmission also **brakes** (1.070) and costs no grip; drivetrain costs **turn-in** (grip 0.951) and does nothing for stopping. Before `L156` these were the same part | |
| §AY19 | `/ncm.setup clear`, `tires 1.4`, then brake hard from speed. | Stopping distance **shortens** (brake 1.163). The old table had tyres not touching `brakeScale` at all, which was not a simplification but an error | |
| §AY20 | `/ncm.setup` with no arguments. | A `CEILINGS at grip x1.00` line: drive up to x1.30, brake up to x1.20. **Headroom before the purchase**, not a post-mortem after it | |
| §AY21 | `/ncm.setup power_unit` with no multiplier. | The explanation now ends with `limited by traction_ceiling -- power that cannot be put down is not power; fit tyres...`. A player is warned before spending | |
| §AY22 | `/ncm.setup clear`, `cooling 1.4`, then `clear`, `electrical 1.4`. | **The honest weak case.** Both give drive (1.106 vs 1.125); only cooling touches brake (1.088), because ducting feeds the brakes. If these feel identical, that is a true result and `IDEA-532` is the answer -- these two are the thinnest distinction in the table and the documentation says so | |
| §AY23 | `/ncm.setup aerodynamics 1.4`, then brake hard from speed. | Beyond the `L154` trade, brake is now **1.052**: the same drag that costs top end shortens the stop | |

**What a PASS of §AY15-16 means.** That parts are no longer independent scalars. A build has a shape, the
shape is legible to the player in chat, and the cheapest route to more power can be tyres rather than an
engine. That is a car rather than a menu, out of the same three floats and no new plumbing.

**What it still does not fix, stated so nobody claims it.** Every lever is a CONSTANT. A wing works
identically in a car park and at 200; nothing heats, fades or wears; a gearbox has no discrete gears.
`cooling` and `electrical` are separated by one modest brake term and little else. Those are the two
recurring `losses` entries across the whole table, and `IDEA-532` -- state-dependent levers evaluated in the
carrier from speed, load and time, all of which are already local variables at the write site -- is the work
that would lift them. **`L156` is not a substitute for it; it is what was available without touching the
plugin.**

## §AZ - the binding: Parts follow the Machine, not the fastest car - **AWAITING LIVE TEST**

`KB-146`, `L155` point 2. §AY asked whether a fitted part can reach a force. §AZ asks the question §AY
could not: **does it reach the RIGHT car?**

Until now it did not, and nothing said so. The write went to whichever car-shaped body was most recently
the fastest thing this client simulated. Every previous section passed because in single-player that body
is always yours -- which is exactly why this needs a **two-client** test and cannot be proved alone.

Carrier **0.1.21** + `ncm_world`. `/ncm.setup` unchanged.

### §AZ-A -- one client, the regression the old build would fail

| # | Operation | Expected | Result |
|---|---|---|---|
| §AZ1 | Fit `power_unit 1.5`, drive. Watch `ncm_carrier.log`. | `handling: BOUND to body ... asset=... entity=...`, then acceleration. **The log line naming your assetId is the actual pass** -- feel alone cannot distinguish this build from 0.1.20. | |
| §AZ2 | Get out of the car and walk around. | `handling: unbound by NCM -- inert, bench config stays suppressed`. No writes while on foot. | |
| §AZ3 | Get back in. | Re-BOUND, same asset, parts restored without re-fitting. | |
| §AZ4 | Drive past ordinary NPC traffic at speed, then let a traffic car overtake you. | **Nothing changes.** On 0.1.20 an overtaking car could steal the latch. `binding=matched` stays in `/ncm.status`. | |
| §AZ5 | Stop the NCM resource, or `/ncm.ffb off`, while parts are fitted. | Socket loss -- `cleared to inert ... ncm_carrier.json drives the levers again`. Ownership genuinely returns, unlike §AZ2. | |

### §AZ-B prerequisites -- two things that had to be fixed before this could run at all

Neither was known when §AZ was written, and §AZ-B is impossible without both.

- **`KB-4`** -- `tools/o77-client.ps1` launched the second client with `OP77_WORLD_SERVER=-` and
  `OP77_WORLD_MODS_DIGEST=-`, placeholders guessed on 2026-09-19 and never revisited, while the launcher
  passes a real world id and the server's real required-mods digest every time. The script now resolves
  all of it from the launcher's own state. **Launch client 2 with it and read the line it prints at the
  end**: it counts imported WebUI surfaces, which is the measurement `KB-4` was built on. 0 means the env
  fix was not the cause and the row stands; anything above 0 retires it.
- **`KB-147`** -- both instances load the same carrier from the same directory and could not both bind
  `38480`, so a second client has never had a bridge at all. Fixed in **0.1.22**: the carrier walks
  `38480-38483` and refuses any peer that is not its own process, so the two clients cannot cross-connect.

> **§AZ-B IS BLOCKED as of 2026-09-26, and not by either of the rows below.** `KB-4`'s root cause is
> now known: the second client's `Open77.WebHost.exe` loses a startup race for the GPU adapter, gets
> `adapter_unknown_before_cef:starting_unpinned`, and dies -- so that client imports **0** WebUI surfaces
> where a working one imports 17. **The carrier bridge is itself a WebUI surface**, so a client with no
> WebHost has no bridge, no Parts and no telemetry regardless of ports or env vars. The race has no
> configuration knob and lives in `Open77.dll`, so the next step is the launch-ordering experiment in
> `KB-4`, not more NCM code. Everything else in §AZ-B is ready and waiting on it.

**Check both before driving.** In each client's `ncm_carrier.log`: one should say `bridge listening on
127.0.0.1:38480`, the other `...:38481 (port 38480 was taken -- another game instance?)`. In each client
log, `carrier connected on http://127.0.0.1:<port>/bridge.html`, and **the two ports must differ**. A
`refused a bridge peer from pid ...` line is the guard working, not a fault.

### §AZ-C -- ONE client, two Machines - **PASS 2026-09-26**

**§AZ15-§AZ19 PASS.** Owner, Carrier 0.1.23: *"galena still gutless, maimai zipping around"* -- with the
Galena at `driveScale 0.300` and the MaiMai at `1.600`, neither refitted. The carrier log corroborates every
step rather than the feel standing alone:

```
14:20:15  binding asset=...0002  vehicle=12884901889  entity=10426251
14:20:15  driveScale 1.000 -> 0.300 (ACTIVE)
14:20:15  BOUND to body 000001B0EA183E30 -- forces now apply to this Machine and no other
14:20:21  driveScale 0.300 -> 1.000 (inert)      <- left the car
14:20:21  unbound by NCM -- inert, bench config stays suppressed
14:20:25  binding asset=...0001  vehicle=8589934594  entity=10426266
14:20:25  driveScale 1.000 -> 1.600 (ACTIVE)
14:20:26  BOUND to body 000001B0E79C41F0
```

Two assets, two vehicle ids, two entity ids, two bodies, each carrying its own setup, with the levers
returning to inert in between. `mass=960 kg` on the second bound body is the MaiMai. **`L155` point 1 is
demonstrated: `assetId` is the authoritative Parts key and a setup follows the Machine, not the driver.**
That is the precondition the Foundry identity spine was waiting on.

`KB-146` is confirmed fixed in the same evidence -- the write reaches a positively identified body and goes
inert when the binding drops, rather than following whatever car was fastest.

**Two things the run also settled.** The `engineEntity` field name, which `carrier_bridge.lua` had to guess
from six candidates, resolved on the first: `handling: vehicle entity id resolves from 'engineEntity'`. And
the setup genuinely persists server-side across a disconnect -- the Galena was still gutless on rejoin with
nothing refitted, which is `fitted[assetId]` outliving the delivery route exactly as intended.

**What misled the owner for two sessions, worth recording because it is a testing trap rather than a
defect.** Session 1 ran Carrier 0.1.22, where `KB-149` refused every bridge connection, so nothing applied.
Session 2 ran 0.1.23 and worked, but a setup fitted to the MaiMai at 14:17:23 was left after sixteen seconds
(`handling: no seat` at 14:17:40) without being driven. The result read as a one-session lag -- commands
taking effect only on the NEXT join -- when it was a broken build followed by an untested change. **A
perceived lag between action and effect is worth distrusting when the build changed in between.**

### §AZ-C -- the steps

**Added 2026-09-26 because §AZ-B was blocked and most of it turns out not to need a second client at
all.** The headline claim of `L155` point 1 is *`assetId` is the authoritative Parts key* -- that a setup
follows the **Machine**, not the person driving it. That needs two **Machines**. It does not need two
humans, and waiting for one was a framing error on my part.

Parts are stored as `fitted[assetId]` and delivered through `bindingForAuthority(playerId)`, which refuses
with `ambiguous_authority` if a player somehow holds two live Machines at once. So the supported shape is
**sequential**, and sequential is enough: the driver is the constant, the Machine is the variable.

| # | Operation | Expected | Result |
|---|---|---|---|
| §AZ15 | Take Machine A. `/ncm.setup power_unit 0.6`. Drive. | Noticeably slow. Log names A's `assetId`. | |
| §AZ16 | Swap to Machine B. `/ncm.setup power_unit 1.6`. Drive. | Noticeably fast. Log names B's `assetId`, and `handling: binding asset=B ... entity=` shows a NEW entity. | |
| §AZ17 | Swap back to A **without fitting anything**. | **A is still slow.** This is the whole test: the setup was stored against the Machine and came back with it, and nothing followed the driver. | |
| §AZ18 | Swap to B again, still fitting nothing. | B is still fast. | |
| §AZ19 | While in A, watch the log through the swap. | `handling: UNBOUND` on leaving, `BOUND` on the next Machine. No window where A's levers apply to B. | |
| §AZ20 | Drive A slowly on a busy street and let traffic overtake you. | **The `KB-146` regression, solo.** Binding stays on A; `/ncm.status` keeps `binding=matched`. On 0.1.20 an overtaking car could steal the write. | |

**What a PASS here means.** `assetId` is genuinely the Parts key and the per-instance channel is
Machine-scoped, which is `L155` point 1 demonstrated and the precondition the Foundry identity spine was
waiting on. Two Designs sharing one runtime record can therefore differ per Machine.

**What it does NOT cover, and why §AZ-B still matters eventually:** concurrency. §AZ-C proves the setup
follows the Machine across time; it cannot prove two Machines are independent *at the same instant*, that a
passenger gets no binding, or that a physics-owner handover carries the right setup. Those are
§AZ6/§AZ9/§AZ12 and they need a second human -- a real tester, not a second local client, given `KB-4`.

### §AZ-B -- two clients, which is the part that matters

Two players, two **different** Machines. Give them opposite setups so a swap is unmistakable:
A `driveScale 0.6`, B `driveScale 1.6`.

| # | Operation | Expected | Result |
|---|---|---|---|
| §AZ6 | Both drive at once. | Each feels only their own. A's log names A's asset, B's names B's. | |
| §AZ7 | **A overtakes B**, then B overtakes A. | No change to either. This is the defect's exact shape: on 0.1.20 the faster car could capture the slower driver's write. | |
| §AZ8 | **Swap Machines.** A drives B's car and vice versa. | **The setup follows the MACHINE, not the driver.** A now feels 1.6. This is the single most important assertion for Foundry -- it is what "`assetId` is the authoritative Parts key" means in the seat. | |
| §AZ9 | A becomes a passenger in B's car. | A gets no binding (`physicsOwner` is B). No double-tuning. | |
| §AZ10 | A disconnects mid-drive and reconnects. | Binding re-established from `assetId`; correct setup returns without re-fitting. | |
| §AZ11 | Despawn and re-CALL a Machine. | `dematerialized` unbinds immediately; `materialized` rebinds. | |
| §AZ12 | Kill the NCM resource while both drive. | **Both cars go native within ~2 s**, by lease expiry rather than by being told. Log: `UNBOUND (the binding lease expired)`. | |

### What a PASS means

`assetId` is genuinely the Parts key, and the per-instance channel is safe for two Designs sharing one
runtime record -- which is `L155` point 3's precondition and the green light for the Foundry identity spine.

**The failure mode to watch for**, because it is the one this design cannot self-detect: `binding=waiting`
forever. That means the server published an identity the client could resolve but no body ever matched it
-- most likely `entityOf()` picked a field that is not the engine entity. The client logs which field name
resolved, **once**; if that line never appears, the candidate list in `carrier_bridge.lua` is wrong and no
amount of driving will produce a write. Check the log before concluding the channel is broken.

## §BA - Does a top speed ceiling work AT ALL? - **AWAITING LIVE TEST**

**This is a capability spike, not a feature test.** It answers whether the platform can cap one Machine's
top speed, before any NCM design is built on the assumption that it can.

### Why this section exists

**Nothing in NCM has ever capped a top speed.** Traced 2026-09-26 after the owner challenged a claim that
the mechanism worked:

| Path | Status |
|---|---|
| `setPerformanceClass(record)` -- client, per-record | Called by `client/main.lua`, but `GlobalState.ncmCeilings` **has never reached a client**. `server/state_probe.lua`: *"class ceilings, a shipped feature, have never applied -- KB-30/D7 is silently dead."* Suspected cause: GlobalState replicates a CHANGE, and this key is written once at boot before anyone connects -- *"unreachable by construction"*. Its only producer was the RB15 class, disabled by `KB-144`. Last live run: **154 attempts, 0 applied** |
| `ratedTopSpeed(record)` | **Client-only** -- absent from the server scripting assembly. The server cannot use it as a baseline |
| `setPerformance(id, profile)` -- server, per-instance | **Present in the deployed binary** (`Open77.Server.Scripting.dll` carries `setPerformance` and `topSpeedKph`); both resources hold `world.vehicles`. **Never called by NCM -- zero call sites** |

The 355 km/h figure in `class.lua` is a measured cliff written into a table. It was never enforced, and
citing it as evidence the mechanism works was the error this section corrects.

### The spike

Command: `/ncm.topspeed <kph>` | `/ncm.topspeed clear`. Deliberately not wired into `parts.handling` --
a spike proves a capability; composing it is a later step that needs a PASS to build on.

| # | Operation | Expected | Result |
|---|---|---|---|
| §BA1 | `/ncm.topspeed` with no argument, seated in an NCM Machine. | Reports "no ceiling set by NCM" and the usage line. Proves the binding resolves and `setPerformance` **exists** -- a missing API is a named refusal here, not a silent failure. | |
| §BA2 | `/ncm.topspeed 60`, then drive a long straight flat out. | **The car holds ~60 km/h.** This is the whole question. A refusal names its reason (`vehicle_not_found` would mean NCM Machines are not in the registry the call reads). | |
| §BA3 | Same, watching the approach to the cap. | The taper rolls throttle off over the last 12 km/h rather than at the ceiling. **Does it read as a governor or as a stutter?** The platform refuses a taper under 3 km/h precisely because the limiter hunts; 12 is the default and this is the first look at how it feels. | |
| §BA4 | `/ncm.topspeed 120`, drive again. | Cap moves to ~120. Proves it can be changed live, not only set once. | |
| §BA5 | Get out, get back in, drive. | **Cap still ~120.** Ownership changes on every driver entry and exit; the evidence card claims the ceiling is replicated to every viewer rather than chased across that transition. This is the claim most worth checking. | |
| §BA6 | Disconnect, reconnect, get back in the same Machine. | Cap survives, or it does not -- either answer is useful and neither is currently known. | |
| §BA7 | `/ncm.topspeed clear`, drive. | Full top speed restored. Distinct from setting a high number: `nil` clears the ceiling outright. | |
| §BA8 | Spawn a second Machine of the **same record**, cap only the first. | **Only the first is capped.** The call is keyed by vehicle id, so this should hold by construction -- and it is the same-record concurrency proof `IDEA-530` has been asking for. | |

### What a PASS unlocks, and what a FAIL settles

**PASS:** top speed becomes a declared number per Machine. The plan's Step 2 (an authored `topSpeedKph` in
`data/vehicle_catalogue.lua`, populated once from a client-side `ratedTopSpeed` dump) and Step 6 (parts
scaling it, with a class ruleset still winning) follow. `IDEA-530` closes.

**FAIL:** *"top speed is not reachable on this platform"* is the honest answer and the top-speed half of
the design is dropped rather than quietly reshaped. **Weather and the tyre thermal model do not depend on
this and proceed either way.**

**What this does NOT test:** anything about parts, composition or `parts.handling`. The spike calls the
platform directly on purpose, so a platform failure and an NCM composition failure cannot be confused --
which is the mistake `KB-144` made in the other direction, when eleven ceilings were refused because their
target records were gone and the ceilings themselves were blamed.

## §BB - Tyre temperature: the window, and what it costs - **AWAITING LIVE TEST**

`L159`. One temperature for the whole car, server-side, keyed to `assetId`. The window is a **penalty, not
a boost**: 1.00 in the window, 0.85 fully cold or fully overheated, on grip **and** brake.

The gauge is the fourth item in the bottom-left input cluster, beside BRK and THR.

| # | Operation | Expected | Result |
|---|---|---|---|
| §BB1 | Spawn a Machine, get in, do not move. Look at the cluster. | A **TYRE** bar appears with a lit window band and a needle near the BOTTOM -- a fresh car starts cold and has to earn the window. Reads `-15%` or close to it. | |
| §BB2 | Drive hard for about a minute -- corners, not a straight. | The needle climbs into the lit band over roughly 60 s and the readout reaches **OK**. Cornering should warm it faster than cruising. | |
| §BB3 | Compare the feel cold versus in-window. | **The point of the whole model.** Cold should understeer and stop worse; in the window should not feel *boosted*, it should feel like the penalty stopped. If being in the window feels like a power-up, the model is wrong. | |
| §BB4 | Park for two minutes, then drive. | The needle falls back toward cold and the penalty returns. Cooling continues **while you are out of the car** -- temperature belongs to the Machine, not the drive. | |
| §BB5 | Get out for ten minutes, come back. | Stone cold, at ambient. The long-absence path is closed-form rather than ticked, so this must not be "five seconds cooler". | |
| §BB6 | Drive extremely hard for several minutes. | The needle goes past the window into **hot** and the penalty returns on the other side. Overheating costs the same 15% as freezing. | |
| §BB7 | `/ncm.setup tires 1.4`, then repeat §BB2. | Tyre parts and tyre temperature compose: the thermal penalty multiplies the part, it does not replace it. | |
| §BB8 | Watch the gauge before the first server tick after joining. | **A dash and NO NEEDLE** (`IDEA-361`). A needle resting mid-gauge would read as "your tyres are perfect" when the truth is "we have no reading". | |

**What a PASS means.** Tyre state is a live, per-Machine mechanical property that interacts with fitted
parts and with the weather, and it is legible to the driver without a menu.

**What it explicitly does NOT model**, all enumerated in `parts.thermal.LOSSES`: per-corner or
inside-shoulder temperature (`per_corner` does not exist), slip velocity (this proxies contact-patch work,
so it over-heats under pure rolling), brake temperature as a separate body, track versus air temperature,
pressure, and compound differences.

## §BC - Weather and time of day reach a car - **AWAITING LIVE TEST**

`L158`, `KB-151`. Weather had **never** reached the mechanical path: `setWeather` had one caller and it was
a console command. Now wired, and verified reading live on 2026-09-26 (`weather=sunny secondsOfDay=43223`).

| # | Operation | Expected | Result |
|---|---|---|---|
| §BC1 | Server log after a restart. | One line: `environment read OK: ... weather=<x> secondsOfDay=<n>`. If it says **UNAVAILABLE** or names a refusal, weather is not reaching anything and every step below is void. | |
| §BC2 | `/ncm.machine weather rain`, then corner hard. | Grip falls live, **on the car you are already sitting in** -- the record channel could never do this (spawn-cached). | |
| §BC3 | `/ncm.machine weather sunny`. | Grip returns. The effect is reversible and live in both directions. | |
| §BC4 | `/ncm.setup` with rain set. | The weather contributor appears in the composition, and its contribution is visible rather than folded invisibly into the parts number. | |
| §BC5 | Compare a dry night with a dry afternoon, over a warm-up. | **Day/night has no grip lever by design.** It acts through ambient temperature: tyres should warm more slowly at night and fall out of the window faster. Subtle, and the mechanism is the point. | |
| §BC6 | Rain, then watch the tyre gauge over a minute. | Wet pulls heat out of the tyre: the needle sits lower and the window is harder to hold. Weather and thermal compose. | |

**Known limitation, recorded rather than discovered later.** `wetnessOf` is still BINARY -- 1.0 for the
`wet` family and 0 for everything else -- although `applyWeather` and the instance contributor are both
linear in a continuous 0..1. Drizzle and a downpour are the same number today. The continuous half exists;
only the source is coarse.

## §BD - The race HUD cannot fail silently any more - **PARTIALLY OFFLINE**

`KB-152`. `race.html` carries the lights, strip, board, graph, odometer, driver inputs and the tyre gauge,
and until 2026-09-26 a throw anywhere in it blanked all of them with no log line.

| # | Operation | Expected | Result |
|---|---|---|---|
| §BD1 | `tools/ncm-test.ps1`. | `=== race render check: 28 assertion(s), 0 bad`. | **PASS 2026-09-26 (offline)** |
| §BD2 | Break a payload shape deliberately and re-run. | The gate goes RED and names the failing assertion. | |
| §BD3 | Drive with the HUD up; watch for `race:error` in the client log. | Silence. An error now has somewhere to appear, which is the whole point -- previously there was nowhere. | |
| §BD4 | Join with driver inputs unreadable (no vehicle snapshot fields). | The cluster still shows, with the tyre gauge live and the pedals dashed. Previously an unreadable input hid the whole box and would have taken the gauge with it. | |


## §BE - The road and the tyre are two different things - **AWAITING LIVE TEST**

`L160`. The tyre model already worked; this section tests whether the ROAD is now a separate,
felt thing from the rubber on it, and whether the two can be observed to disagree.

**Nothing here needs a chat command while driving.** The server writes a thermal line every 5 s per moving
car, and it now prints both bodies:

```
thermal asset=00000f v=19.8 m/s lat=7.4 m/s2 load=0.481 T=86.3C pos=+0.04 track=41.2C air=27.1C surf=x0.992
```

`track` and `air` must be DIFFERENT numbers in sun. If they are equal at midday the environment feed is
not delivering `secondsOfDay` and the surface layer is absent rather than inert - which is the designed
behaviour, not a bug, but it means this section cannot run.

| # | Step | Expected | Result |
|---|---|---|---|
| BE1 | Sit in a car at midday, dry. Read one thermal log line. | `track` roughly 15C ABOVE `air`. Sun on asphalt is not air temperature. | |
| BE2 | `/ncm.tyre` while parked. | Three lines: the tyre's own band, a `track ... (air ...)` line, and the raw `weather/wetness/secondsOfDay`. **Both bodies reported**, because one of them explains half of what is felt. | |
| BE3 | `/ncm.machine weather rain`, wait for it to take, read a thermal line. | `track` COLLAPSES toward `air` and then below it - the solar term is removed outright, not reduced. `surf` falls. | |
| BE4 | Same drive, dry midday vs dry pre-dawn (`/ncm.machine time`, if available; otherwise wait or compare sessions). | Tyre settles materially HOTTER at midday on identical driving. Model says 111C vs 74C at sustained brisk cornering. | |
| BE5 | Warm the tyre into the window at midday, then trigger rain and keep driving. | The tyre does NOT instantly change - it has its own time constant - while `track` and `surf` move at once. **This is the whole point of the split: two bodies, two clocks.** | |
| BE6 | Drive hard on a cold wet pre-dawn road with tyres already warmed into the window. | Still short of grip. A tyre in its window on a freezing road is a representable state and must not feel identical to a warm road. | |
| BE7 | Watch for double-charging: compare `surf` in the log against wetness. | `surf` must respond to `track` only. Two conditions with the same track temperature and different wetness must show the SAME `surf`. `L160` point 4. | |

**What would falsify the design rather than the implementation:** if BE5 shows the tyre tracking the road
instantly, the two bodies are not independent and the split bought nothing. If BE6 feels identical to a
warm road, `SURFACE_COLD_DEPTH` is too small to be a mechanic and should either grow or be removed - a
layer nobody can feel is a layer that should not be traced.


## §BF - Parts economy and serialized fitting v1 - **DEPLOYED ONLINE; AWAITING LIVE PASS**

`L162`, `L163`. Online is the current private development surface and `ncm_league.partsEnabled` defaults
**true** there. Deployment is complete; this section still proves migrations, conservation, backfill, recovery
and felt outcomes one row at a time rather than converting deployment into a PASS.

| # | Operation | Expected | Result |
|---|---|---|---|
| BF1 | Apply migrations 031-032 on the private Online development surface, restart twice. | Both migrations apply once; second boot is clean; all pre-existing vehicle identity/ownership/serial/result history is unchanged. | |
| BF2 | Run the factory backfill twice and audit counts. | Every existing MaiMai, Galena and Hella has exactly 11 factory component assets, 19 occupied interfaces and one current revision; the replay creates nothing. Original exposure equals the Machine odometer; unknown historical serial/run/installer/time remains unknown. | |
| BF3 | Audit the launch catalogue. | Exactly 25 immutable Designs with the specified makers, prices, 1.08/1.18/1.30 effects, ceilings, initial stock, batches and cadences. Street/Premium fit all three starters; Sport counts are MaiMai 7, Galena 8, Hella 7. | |
| BF4 | With Parts enabled on Online, open Base Market at 1820×960 with keyboard/mouse, controller and touch-equivalent selection. | Three-column Machine pane above, independently scrollable component pane below, persistent detail at right. Hover/focus/selection parity; every car stays visible with icon + text + green/red outline. | |
| BF5 | Inspect a component and its next unit. | Maker/code/subtitle/family/tier, exact effect, DIRECT/MODELLED limitation, price/stock/ceiling/batch/cadence/time and exact global/maker/design serial plus run provenance agree with database truth. | |
| BF6 | Inspect all three starter cars. | Six reserved metrics are present and say `Not rated`; no placeholder absolute performance number appears. Relative setup projections remain visible and labelled. | |
| BF7 | With no compatible owned Machine, buy a part after the warning; release the hold before 900 ms once, then complete it. | Cancellation spends nothing. Completed hold buys one exact FIFO asset, debits one `component_purchase`, transfers custody once and refreshes Market/Inventory. No extra modal or harder confirmation appears. | |
| BF8 | Double-submit the same purchase and race two buyers for the final unit; separately test insufficient funds. | One asset/one debit/one transfer only; one buyer wins stale stock; retries are idempotent; failed transactions roll back completely. | |
| BF9 | Select a stored compatible part in Parts Inventory and inspect two owned Machines, including an incompatible or unavailable target. | Cards show serialized status/provenance and `FACTORY ORIGINAL` where applicable. Fitment and parked/occupied availability are distinct; incompatible, moving, occupied, unreadable or unowned targets cannot expose a valid fit commit. | |
| BF10 | Fit to a parked, unoccupied Machine; retry the same idempotency key. | One immutable configuration revision is created, all kit positions move atomically, the component effect composes once, displaced factory/aftermarket assets return to Parts Inventory, and the retry creates nothing. | |
| BF11 | Reinstall a displaced factory original, then repeat with two examples of the same model. | The swap is reversible through compatible assets; each physical Machine retains an isolated configuration and handling result. | |
| BF12 | Fit while dematerialized, restart resources/server, reconnect, materialize and transfer authority. | Every path restores exactly the persisted configuration through `NcmHandling.setParts`; no stale in-memory setup survives and no installed asset appears in two places. | |
| BF13 | Drive a configured Machine through odometer flushes, including restart/reconnect boundaries. | Machine distance and every installed component exposure advance in the same durable operation, with neither lost nor duplicated metres. No wear consequence fires. | |
| BF14 | Allow/accelerate production through several batches, including concurrent lines. | Physical assets are minted to runs; global/maker/design ordinals are unique and contiguous for successful allocations; shelf never exceeds ceiling; FIFO order survives restart. | |
| BF15 | Run isolated accelerated R&D clocks across restart boundaries. | Maker first offsets/cadence are respected; the same evaluation cannot reroll; no historical catch-up burst; effects stay quantized/bounded; `no_design`, novelty rejection and undistributed specialist outcomes all occur and persist. | |
| BF16 | Fit representative Street 1.08, Sport 1.18 and Premium 1.30 DIRECT and MODELLED Parts, then run the existing §AY setup drives and §BA top-speed validation. | The serialized assets produce the same bounded composition as the proven setup seam. Claims match felt/read-back evidence; no paid absolute top-speed claim ships ahead of §BA. | |
| BF17 | Disable Parts live after testing. | Purchase/install controls return to `AWAITING LIVE QA`; existing assets/configurations remain conserved and readable; no destructive rollback occurs. | |

**Offline evidence, not a live PASS:** 2026-09-26 catalogue/R&D tests pass under Lua 5.4 and LuaJIT; the
panel render gate exercises split panes, mixed fitment, component provenance/warning, Parts Inventory and the
eligible fit action. Transactional database concurrency and in-game handling remain deliberately unclaimed.

## §BG - Drag split from braking; `dragScale` - **BUILT; AWAITING LIVE PASS**

`IDEA-538`. The carrier's force write site discriminated retarding force by SIGN alone, so aerodynamic drag
was scaled by `brakeScale` along with the brakes: a brake part silently moved terminal velocity, and
`aerodynamics` had to book its drag against `driveScale`, pretending a wing reduces engine power.

**The measurement that authorises the lever** (Galena, 2026-09-26, gear headroom x1.45 applied, `power_unit`
at 1.0): `brakeScale 1.0` -> ~131 km/h, `0.5` -> 139 km/h, `0.3` (clamped from 0.1) -> 142 km/h. Solving
`v(b)/v(1) = 1/sqrt((1-g) + g*b)` independently at each point gives `g = 0.224` and `g = 0.213` -- two
different brake settings agreeing that this hook sees about **22%** of the car's drag. Drag is reachable.

The discriminator is the driver's brake PEDAL, forwarded to the carrier on the machine channel at 30 Hz,
and it **fails closed**: an unknown, stale (>250 ms) or depressed pedal keeps the brake lever. The failure
modes are not symmetric -- scaling drag as braking costs a little top speed, scaling braking as drag means
a car that will not stop.

| # | Operation | Expected | Result |
|---|---|---|---|
| BG1 | Carrier 0.1.28 loaded; drive a car and check the log. | `ncm=` reports a speed rather than `n/a` -- the telemetry feed the FFB split had cut now reaches the Carrier again. | |
| BG2 | `/ncm.setup brakes 0.5`, then a long straight at full throttle. | Terminal velocity is **unchanged** from stock. The brake lever no longer touches drag. | |
| BG3 | From speed, brake hard with `brakes 0.5`. | Stopping distance is visibly longer than stock -- the brake lever still does its own job. | |
| BG4 | `/ncm.setup aerodynamics 1.40`, then a long straight. | Terminal velocity **falls**; cornering grip rises. The wing's cost is now booked as drag. | |
| BG5 | `/ncm.setup aerodynamics 0.80`, then a long straight. | Terminal velocity **rises** above stock. The trade runs both ways. | |
| BG6 | Alt-tab or stall the client mid-brake so frames stop arriving, then brake. | The car still stops normally. A stale pedal must never let braking be scaled as drag. | |
| BG7 | Step out of the car, then back in, and brake. | Braking is normal on the first application; the withdrawn pedal is not remembered as "coasting". | |

## §BH - Machine knowledge, in the Machine Index - **AWAITING LIVE TEST**

**Deployed with migration 033.** Restart first and expect schema **33**, `pending=[]`.

**This section is driveable.** The owner's condition for validating it was that it be player-facing, so the
evidence is now rendered: every owned Machine has an **OBSERVED - THIS MACHINE** block in the Machine Index.
Rows 1-8 need no SQL at all. The `[me]` rows are confirmation, not the test.

Offline evidence: **473 core tests** green under both interpreters, **126 panel render assertions**,
`luac -p` clean over 201 resource files (205 minus the 4 resource manifests), docs authority green.

**Owed and NOT run offline:** migration 033 applied twice against copies of the real table definitions.
`NCM_DB_ROOT` was not injected in the authoring session, so 033 has no equivalent of the dry-run `§AI` did
for 029. Run it first, or accept the boot as the first evidence and say so.

| # | Do | Expect |
|---|---|---|
| **DRIVE IT** |||
| §BH1 | Boot twice, then open Machine Index and select an owned Machine you have never driven. | **`OBSERVED - THIS MACHINE` / `Nothing observed yet`.** Absence is a legitimate state. It must not read `0 km/h`. |
| §BH2 | Drive it above 30 km/h. Re-open the panel. | **`Highest speed observed  ·  96.4 km/h  ·  (-1235, 987)  ·  <date>`.** The coordinates are the feature, not decoration -- they are what lets you ask later whether that reading was a downhill. |
| §BH3 | Drive faster, by more than 5 km/h. Re-open. | The figure **rises**. Drive slower: it does **not** fall. It is a floor on demonstrated capability, not a speedometer. |
| §BH4 | Corner hard, then re-open. | A second row: **`Highest cornering load observed`**, in `m/s²`. Two characteristics, two units, neither borrowing the other's. |
| §BH5 | On the same card, compare the two speed figures. | `Rated top speed  ·  167 km/h · DECLARED` in the metric block, and `Highest speed observed · 156.4 km/h` in the OBSERVED block. **They should disagree, and the observed one should be lower until you really try.** This is the two-source display -- if either is mislabelled, or if the observed figure ever appears marked `DECLARED`, stop and say so. |
| §BH6 | Look at a Machine with no authored figure (a bike). | `Rated top speed · Not rated`. Never `0 km/h`. |
| §BH7 | Sit **stationary** in a car for a full minute, then re-open the panel. | **No new observation, and no `0 km/h` row.** The tyre gauge and odometer behave exactly as before. This is `§AI15`'s invariant one layer up and it is the easiest thing in this pass to break. |
| §BH8 | Restart the resource. Drive the same Machine slower than its recorded best, then beat it. | The stored figure **survives the restart** and only moves when you beat it. It was re-read from the table, not started from nothing. |
| **CONFIRMATION (optional, `[me]`)** |||
| §BH9 | `SELECT knowledge_kind, evidence_json, obs_x, observation_basis, ai_driven, configuration_ref FROM vehicle_knowledge_evidence WHERE knowledge_kind LIKE 'observed[_]%' ORDER BY observed_at DESC LIMIT 5;` | Typed body `{"kind":...,"value":...,"unit":"kph"}`, a real position, `server_measured`, and the configuration. The unit travels with the value. |
| §BH10 | `SELECT COUNT(*) FROM vehicle_knowledge_evidence WHERE ai_driven IS NOT NULL;` before driving. | **0.** Nothing is backfilled; every pre-existing row keeps `ai_driven` NULL -- unknown, not `false`. |
| §BH11 | `/ncm.observations` in the server console. | `wired=observed_lateral_accel,observed_speed_floor`, counters, and the four declared characteristics listed as `declared, no producer`. |
| **CONFIGURATION PROVENANCE (`IDEA-542`)** |||
| §BH12 | Finish a race. **[me]** `SELECT asset_id, attribution_basis, configuration_ref FROM session_result ORDER BY session_id DESC LIMIT 3;` | A real 36-char id matching that Machine's `machine_configuration_current`. A result with no latched machine keeps it NULL. |
| §BH13 | **Fit a part, then race the same Machine again.** Compare the two rows. | **A different `configuration_ref`.** This is the entire point of the column: the earlier lap stays attached to the configuration that set it. If both match, the latch is reading the head at settlement rather than at GREEN. |
| §BH14 | Watch the server log at GREEN. | `machines at green: N attributed, M unknown, K with a configuration`. |
| **COMPONENT MARKET SCOPE (`IDEA-545`)** |||
| §BH15 | Open the Parts market; buy a component. | Identical to before: same 25 Designs, same prices, same supply, purchase succeeds. **This change is meant to be invisible today** -- if anything looks different, that is the finding. |
| **WATCH FOR ANYTHING** |||
| §BH16 | Any `[ERR]` during boot or session; odometer, tyre gauge, race HUD, Market, toasts. | None, and all unchanged. Every addition here is additive and guarded. |

### What a PASS establishes, and what it does not

A PASS establishes that NCM **records and shows** what a machine has been seen doing, with the serialised
machine, the position, the configuration and the authority that produced it -- the provenance `28` section 22
calls irrecoverable -- and that a declaration and an observation can sit on one screen without being mistaken
for each other.

It establishes **nothing about estimation**. There is no envelope, no confidence and no inference, by ruling
(`L164`). It says nothing about the four declared-but-unwired characteristics (`IDEA-544`), which are refused
by their own producer check until a real producer exists. And it is not a claim about any model: every figure
here belongs to one serialised machine (`28` section 11).

## §BI - lap ghosts, PERSONAL BEST - **DEPLOYED ONLINE 2026-09-27 16:10 UTC; AWAITING LIVE PASS**

Deployed: `replay.pose`, `replay.lap`, `data.vehicle_templates`, migration **034** (`ghost_lap`, plus
`practice_run.run_started_at` / `run_finished_at` / `ghost_id`), `ncm_league/server/ghost.lua`,
`ncm_world/client/ghost.lua`, the `race:ghost` HUD channel. Expected schema version after boot: **34**.

Why it is driveable: a ghost needs nothing but a practice session on any route. Set a lap, cross the start
again, and a car should be there. **Two claim paths need exercising, not one** -- practice runs on the
time-attack kernel and a time trial is a race with a field of one on the race kernel, so §BI19-§BI22 are not a
repeat of §BI1.

**Offline evidence:** **492 core tests** green under both Lua 5.4 and LuaJIT (was 473), **46 race render
assertions** (was 28), 126 panel render assertions, 26 nameplate assertions, `luac -p` clean over **210**
resource files, `node --check` over 5 inline script blocks, cross-scope clean over 49 global references,
docs authority green over 74 documents.

**First live attempt FAILED and the fix is deployed (`KB-156`).** The owner ran a time trial on the cut at
16:41 UTC and saw no ghost. Cause: a race session record carried `routeName` but never `routeId`, so the client
refused the session, recorded nothing, prefetched nothing, and the host claimed with an empty route. `ghost_lap`
was confirmed empty -- nothing was mis-stored. Fixed and redeployed **16:55 UTC**; both ends now log the missing
key by name rather than failing silently. **§BI is unchanged and entirely unrun** -- that attempt produced a
defect, not a result.

**Deployed and verified on the live server (2026-09-27 16:10 UTC, redeployed 16:55 UTC with `KB-156` and
migration 035):**
`migration 034 ghost_lap applied (2 statement(s))`, and `migration 033 observation_authority applied` in the
same boot -- **033 had never reached Online before this deploy**, which closes the question of whether it was
there and is worth noting against `§BH`. Boot was clean: `migrations: 2 applied`, `scheduler started: 5 series`,
`race control started`, no WRN and no ERR. Schema confirmed directly against the live database: `ghost_lap`
present with **26 columns**, `practice_run` carrying `run_started_at` / `run_finished_at` / `ghost_id`, and
`schema_migrations` at **34:ghost_lap**.

**Still owed, and the deploy does not substitute for it:** the **twice-applied** dry-run.
034 applied **once**, forward, onto a database with real rows -- which is real evidence and is in one respect
stronger than a scratch run, but it is not the replay proof. The runner writes the version row on success, so a
restart will not replay it; only `tools/test-ghost-migration.ps1` exercises that path, and it still needs
`NCM_DB_ROOT`, which is not injected. 034 is one `CREATE TABLE IF NOT EXISTS` and one
`ALTER ... ADD COLUMN IF NOT EXISTS`, the replay-safe shape schema 019 requires -- but that remains an argument
rather than a measurement.

**Nothing about the ghost's visual model has been observed.** `props.create` returns a successful id for a
model it cannot resolve (`KB-14`), so the candidate list in `data.vehicle_templates` is ordered guesswork
until §BI2 says which string drew. That is why every attempt logs its model string and why a fallback draw is
labelled on the HUD. **§BI2 is the step that decides whether the car is a car.**

| # | Do | Expect |
|---|---|---|
| **DRIVE IT** |||
| §BI1 | Open practice at any route and set one clean lap. | Server log: `[ncm_league/ghost] upload begin player=N ... parts=K`, then `stored ghost=<uuid> driver=... route=... <N>ms poses=<n> <bytes> bytes record=Vehicle....`. **Quote the byte count and the pose count.** The record must be the car you actually drove. |
| §BI2 | Cross the start line again and look. | A car appears at the start and drives away from you. **Quote the client's `ghost prop id=... model=... candidate=i/n readback=...` line.** If the HUD shows `NO CAR MODEL`, the model fell through to `race.route_arrow` and you are chasing a road arrow -- that is a legible failure, not a PASS, and the candidate list needs the model string that does work. |
| §BI3 | Drive straight through where the ghost is. | **Nothing.** No impact, no collision, no damage, no incident logged against either car. It is scenery you cannot touch. |
| §BI4 | Follow it through the fastest direction change on the route. | The heading looks right the whole way and **never spins the wrong way round**. This is the `359 -> 1` seam live; the unit test covers the arithmetic, this covers whether the recorded yaw is the axis we think it is. |
| §BI5 | Watch the HUD strip while chasing. | `PERSONAL BEST · <name>`, the recorded lap time, and a live `Δ` that goes **negative when you are ahead**. It must never appear as `P2` and never appear as a row in the standings board. |
| §BI6 | Deliberately drive well off the racing line, then look at `Δ`. | A **dash**, not a number. Off the line the ghost has no time for where you are, and inventing one would be a confidently wrong instrument. |
| §BI7 | Beat your own lap. | A **second** `stored ghost=` line with a new uuid, and the ghost you chase next lap is the faster one. `ghost_lap` gains a row; nothing is updated in place. |
| §BI8 | Set a lap **slower** than your best. | `upload ... kept out: <N>ms does not beat the stored <M>ms`, and no new row. |
| §BI9 | Reconnect, re-enter practice at the same route. | `[ncm_league/ghost] stream player=N id=... ghost=... poses=n packets=k` and the ghost replays. It survived the restart because it is a row, not a session buffer. |
| §BI10 | Practice at a route you have never set a lap on. | `no stored ghost for route=<id>` on the client and **no row on the HUD**. An explicit absence, distinguishable from a ghost that failed to arrive. |
| §BI11 | `/ncm.ghost off`, then cross the start. | No prop, no row. Then `/ncm.ghost personal` and it comes back. `/ncm.ghost session` should say it is not built yet rather than doing nothing. |
| §BI12 | Leave the session, then stop the resource while a ghost is on screen. | The prop is gone in **both** cases. A resource that claims a prop and never releases it leaves scenery in the world with nothing explaining it. |
| §BI13 | Have a second player stand at the start while your ghost replays. | They see **nothing**. The prop is client-local; a ghost is not a shared entity. |
| **TIME TRIALS (`L166` point 7) -- `KB-156` was found here on the first live attempt** |||
| §BI0 | Before anything else: run one time trial and read the server log. | `time trial ghost invited driver=... route=<a real route id> <N>ms` -- **`route=nil` is `KB-156`** and means no ghost can be keyed to the session. Deploy 2026-09-27 16:55 UTC is the first build where a race record carries `routeId` at all. |
| §BI19 | Enter a posted event **alone** so it runs as a time trial, and finish it. | Server log: `time trial ghost invited driver=... route=... <N>ms`, then a `stored ghost=` line. A time trial is a race with a field of one, on the **race** kernel -- so this exercises a completely different claim path from §BI1, not the same one again. |
| §BI20 | Run the same solo event a second time. | The ghost is **there from green**, not appearing several seconds into the lap. A time trial only becomes recordable at green, so the trace is requested during the countdown; if it shows up late, the prefetch is not working. |
| §BI21 | Take a penalty during a solo time trial, then finish. | The lap is still stored, and `elapsed_ms` is the official time **including** the penalty while the poses span only the driving. The band check must not refuse it -- that is what the kernels' separate `raw` duration exists for. |
| §BI22 | Now run an event with **two or more** drivers. | **No ghost, no ghost row, no invite line.** A contested race is excluded deliberately; a ghost among real competitors could be read as another entrant. |
| **THE FIXED DEFECT (`KB-155`)** |||
| §BI14 | Take a penalty during a practice lap, then finish it. | `practice_run.incident_ms` is **non-zero**. It has been written as 0 for every practice run ever recorded; the kernel now returns the run's own incident time. |
| **CONFIRMATION (optional, `[me]`)** |||
| §BI15 | `SELECT ghost_id, format, route_id, elapsed_ms, incident_ms, pose_count, pose_hz, record, run_started_at, run_finished_at FROM ghost_lap ORDER BY at DESC LIMIT 5;` | `format = 1`, a real `record`, `pose_count` well under 3000, and **`run_started_at` / `run_finished_at` both non-zero and ordered**. Those two columns are the whole point: no stored practice lap before this could be located in time at all. |
| §BI16 | `SELECT run_started_at, run_finished_at, ghost_id FROM practice_run ORDER BY id DESC LIMIT 3;` | Populated, and `ghost_id` set on the row whose lap became a ghost. |
| §BI17 | `SELECT JSON_VALID(poses_json), JSON_LENGTH(poses_json) FROM ghost_lap ORDER BY at DESC LIMIT 1;` | `1` and a length equal to `pose_count`. The `CHECK` constraint is declared; this is whether it is enforced. |
| §BI18 | `/ncm.ghost` in the server console. | `claims pending=0`, the poses-per-packet figure, and the newest stored ghosts listed with their records. |
| §BI23 | `SELECT discipline_id, laps, elapsed_ms, incident_ms, run_finished_at - run_started_at AS raw_s FROM ghost_lap ORDER BY at DESC LIMIT 5;` | For a penalised lap `elapsed_ms` **exceeds** `raw_s * 1000`, and both are present. If they are equal on a lap you were penalised for, the official time and the raw duration have been conflated. |

### What a PASS establishes, and what it does not

A PASS establishes that a lap can be recorded from the car, stored immutably with its interval and its
machine, streamed back after a restart, and replayed as a non-colliding local body with a readable delta --
on **both** kernels, in practice and in a solo time trial, and in neither case during a contested race.

It does **not** establish: that the ghost looks like it should -- it is solid, it has no transparency, and it
carries only a yaw, so it does not bank or pitch (`IDEA-561`); that a ghost is safe to hand to another driver
(`SESSION BEST` and `ROUTE RECORD` are refused in code, not merely absent); or that a stored lap belongs to
the geometry it replays against, since routes are re-authorable in place with no revision (`IDEA-562`).

A ghost drawn from the fallback model is **not** a PASS of §BI2. It is the honest failure mode working.

## §BJ - Economy v1 playable money loop - **BUILT LOCALLY; NOT DEPLOYED; AWAITING LIVE PASS**

Scope: migration **035**, authored Street/GT/Hypercar/NCX economics, paid event check-in, solo and contested
settlement, Race Tag bounties, personal-first Research submissions and the three existing unique-accomplishment
rewards. Fuel, generalized player trade, research contracts/world-first calls and tiered Badges are outside this
section because they are not built.

**Offline evidence:** 504 core tests green under both Lua 5.4 and LuaJIT; 51 cross-scope references clean;
17 QA-observer and 35 vehicle-access tests green; `luac -p` clean over 217 resource files; panel/nameplate/race
render checks green at 129 / 26 / 46 assertions. The full gate was green before this section was appended and
must be rerun after session-close bookkeeping.

| # | Do | Expect | Result |
|---|---|---|---|
| §BJ1 | Deploy and boot twice, then inspect `schema_migrations`, `event`, `ledger`, `session_settlement` and `research_submission`. | Migration 035 applies once, the second boot is a no-op, all new columns/tables/indexes exist, and boot has no economy error. | **NOT RUN** |
| §BJ2 | Open the Guide for a Street, GT, Hypercar and NCX event. | Entry, solo completion, contested completion, P1 and field rule match the authored scale; NCX says sponsored/free entry; practice remains free. | **NOT RUN** |
| §BJ3 | Join as a new Driver and run `/ncm.balance`. | Exactly one €$10,000 starter grant exists and the command agrees with the ledger sum. Reconnect does not grant again. | **NOT RUN** |
| §BJ4 | Check into a paid event, retry the command and reconnect before green. | Entry is debited exactly once; one `entry_fee:<event>:<driver>` ledger row exists and the existing entry is restored without another charge. | **NOT RUN** |
| §BJ5 | Reduce balance below the fee and attempt check-in. | Refused with the required/current balance; neither an entry nor a debit row is created. | **NOT RUN** |
| §BJ6 | Finish a posted event alone. | It settles as a time trial: the solo completion amount pays, no placement/P1 line exists, `time_trial=1`, and qualifying did not pay. | **NOT RUN** |
| §BJ7 | Make that solo finish clean. | The authored `clean_run` bounty pays once, the statement itemises completion/tag/entry/net, and displayed balance equals the ledger sum. | **NOT RUN** |
| §BJ8 | Repeat with contact or a penalty. | Factual negative/penalty Tags may describe the result, but no clean bounty or other unmapped Tag money is minted. | **NOT RUN** |
| §BJ9 | Finish the same route/economy opportunity again in the same window. | The renewable completion path uses the authored repeat floor rather than paying the first-completion amount again. | **NOT RUN** |
| §BJ10 | Finish with two or more Drivers. | It settles as contested: completion, exact placement, capped field and eligible clean lines add correctly; `time_trial=0`. | **NOT RUN** |
| §BJ11 | Exercise P2/P3 and a short field. | Placement and per-entrant field amounts match authored data exactly and never exceed the field cap. | **NOT RUN** |
| §BJ12 | Produce DNF, DNS and DSQ outcomes. | No purse line is paid for any of them; the paid entry remains spent unless the server/event aborts. | **NOT RUN** |
| §BJ13 | Voluntarily withdraw, then re-enter the same event if still allowed. | Withdrawal does not refund; idempotency prevents a second fee for the already-created entry. | **NOT RUN** |
| §BJ14 | Abort or administratively cancel a paid session. | Each affected paid entry is refunded exactly once and the itemised balance is correct. | **NOT RUN** |
| §BJ15 | Stop the resource/server with an unresolved paid session, then boot. | Recovery refunds it exactly once; repeated boots do not create another refund. | **NOT RUN** |
| §BJ16 | Earn first finish, first time trial and first win, then repeat each trigger. | €$100 / €$100 / €$300 pay only after progression persists and exactly once per Driver/server/accomplishment. | **NOT RUN** |
| §BJ17 | Run `/ncm.research` after catalogue-only exposure and after physically discovering a Machine. | Catalogue exposure is absent; eligible physical identity/capability submissions are listed with amount and evidence. | **NOT RUN** |
| §BJ18 | Submit one Research item twice, then improve/refit the same Machine characteristic and try again. | First accepted contribution and reward commit together; repeats produce neither a second contribution nor money. | **NOT RUN** |
| §BJ19 | Reconcile a settled Driver/session directly in SQL. | `session_result`, `session_settlement.receipt_json`, typed ledger references and `SUM(ledger.amount)` agree exactly. | **NOT RUN** |
| §BJ20 | Inspect a completed qualifying session. | Its result persists for sporting use, but it has no non-zero payout ledger row and cannot consume the race opportunity. | **NOT RUN** |
| §BJ21 | Compare one equivalent finish across Street, GT and Hypercar authored tiers. | The configured 1× / 10× / 100× scale is applied without code changes or overflow; exact values remain tuning data. | **NOT RUN** |

### What a PASS establishes, and what it does not

A full PASS proves one Driver can begin with capital, enter and finish paid solo competition, earn through clean
driving, finite Research and career firsts, and spend through the existing Machine/Parts markets without a human
opponent or AI grid. It also proves the same settlement expands to contested fields and survives retries/restarts.

It does not balance the long-run economy, validate million-eddie acquisition time, or prove sinks not yet built.
Those require telemetry and sustained play after this transactional loop is live.

## §BK - Race Guide bounded transport - **DEPLOYED ONLINE 2026-09-27 19:43 UTC; AWAITING LIVE PASS**

Scope: `KB-160`. The Race Guide's server-to-client hop is now a head plus numbered row packets packed by
measured bytes, and the panel refuses to render a date it was never given. This section exists because the same
failure has now happened three times (`KB-59`, `KB-86`, `KB-160`) and twice been declared fixed on the strength
of a smaller payload rather than a bounded one.

**Offline evidence:** full gate green under Lua 5.4 and LuaJIT -- `test_chunks` covers byte-budget packing, the
oversized-row report and the unmeasurable-row case; `panel-render-check` is at 154 assertions including three
that fail if an unseeded clock ever renders a date again; `ncm-stub`'s Guide scenario now reassembles the real
stream and asserts every packet and the head against the ceiling.

**§BN1 WAS RUN ON 2026-09-28 AND IT FAILED: no card, on any press.** The cause was not the key, the page, the
focus handshake or the server's decision -- it was the transport, and it had never worked once for anybody
(`KB-172`). The form was published into a player state bag of **11,515 bytes** against a **4,032**-byte ceiling
(`IDEA-509`), so the platform discarded every write. What makes this worth reading before re-running the section:
**both sides logged something reasonable and neither logged the fault.** The server logged `form opened` eleven
times with no refusal; the client logged `no form arrived within 3000 ms`; `grep ncmBuild` over the whole server
log returned nothing at all. Fixed by `L189` -- the form now streams over `ncm:build` as a 419-byte head plus one
5,496-byte packet, and the 35-node list travels **once** instead of twice.

**So §BN1 is the gate for this whole section again, and it is now also a transport test.** On a re-run, the
client log must show `ncm:build stream begin ... nodes=35`, then `ncm:build stream complete`, then
`opened with 35 node(s)`; the server must show `form published player=<n> nodes=35 bytes=<n> head=<n> packets=1`.
If the card does not appear and **chat is silent**, that is a transport fault, not a refusal -- the client now
says exactly that rather than the old sentence that blamed nobody.

**Read the server line first:** `guide published player=1 rows=<n> bytes=<total> head=<n> packets=<n>`. A
`HEAD LARGE` or `ROW OVERSIZED` line means the next growth will be the one that hurts.

**Already observed live, so §BK2 is half-answered:** `19:48:30 guide published player=1 rows=17 bytes=22574
head=385 packets=5`. The total is above 18 KB, the head is negligible, and the stream is running. What remains is
entirely client-side -- §BK1, §BK3, §BK4, §BK5, §BK6 -- because nothing above proves the packets were received,
reassembled and drawn.

| # | Do | Expect | Result |
|---|---|---|---|
| §BK1 | Deploy, join, open F6 → RACE GUIDE. | The schedule draws with every posted row, and the clock shows today's real date. No 1969, and no "Loading live schedule…" that never resolves. | **NOT RUN** |
| §BK2 | Read the server log for the push. | One `guide published … bytes=… head=… packets=…` line. Total is above 18 KB and the Guide still arrives; head is well under 6 KB; packets is greater than 1. | **NOT RUN** |
| §BK3 | Read the client log for the same push. | `guide stream begin id=… packets=<n>` followed by `guide stream complete id=… rows=<n>`, with `rows` equal to the server's count. No `refused at assembly`. | **NOT RUN** |
| §BK4 | Open the Guide on an event with authored economics and confirm the economy block still reads. | Entry, completion, placement and bounty figures are present — the per-row block that caused `KB-160` is carried, not dropped, now that the hop is bounded. | **NOT RUN** |
| §BK5 | Stop the host with the Guide open, then reopen the Guide. | The panel says `NO HOST TIME YET` and "No schedule has reached this panel", and the driver card says `COUNTDOWN UNAVAILABLE`. It never shows 1969 and never claims a schedule it does not have. | **NOT RUN** |
| §BK6 | Restart `ncm_league` while a client stays connected, then reopen the Guide. | A fresh stream arrives and assembles; a partial stream from the previous generation is discarded rather than drawn with rows missing. | **NOT RUN** |


## §BL - Ambient population and the race corridor - **NOT DEPLOYED; AWAITING LIVE PASS**

Scope: `L177`, `IDEA-635`. `ncm_world` now spawns its own pedestrians and lane traffic around connected players
and clears them out of a race corridor before a start, and asserts the vanilla density switch per routing
bucket beside it. Nothing here has run on a live client.

**Offline evidence:** full gate green under Lua 5.4 and LuaJIT — 52 assertions in `test_ambient` over the pure
director (capsule geometry, the sight rule, budget order, the hold window), a 40-assertion host harness
(`tools/test-ambient.lua`) against platform doubles, and an `ncm-stub` scenario that drives the real
`ncm_league` calendar publication into the real `ncm_world` service across two Lua VMs. The stub scenario was
mutation-checked: shrinking the corridor radius to 1 m makes it fail.

**What no double can answer, and why this section exists.** Every offline test asserts that the service *asked*
the platform for something. Three of the asks have never been made on a live client: whether `joinTraffic`
actually puts our cars on the authored lanes rather than leaving them parked, whether `wander` keeps a
server-created ped on the pavement, and what a populated city costs in frame time during a race. A green gate
says the plumbing is right; it says nothing about any of those.

**Read the server lines first.** `ncm.ambient` prints counts against budget, spawn/despawn/refused/ground-miss
totals, every held corridor with its point count and radius, each bucket's vanilla state, and a live
`getPopulation(0)` read. `ncm.ambient clear` removes everything the resource owns.

| # | Do | Expect | Result |
|---|---|---|---|
| §BL1 | Join and stand still for a minute in a populated district. Run `ncm.ambient`. | Cars and pedestrians appear around you, counts climb toward the per-player caps, and `getPopulation(0)` answers rather than refusing. A refusal naming `world.population` means the permission did not reach the live server. | **NOT RUN** |
| §BL2 | Watch a spawn happen. | Nothing appears inside about 110 m of you. If anything pops into view at conversational distance, `ambientSpawnMinM` is not holding and the number is the first thing to check. | **NOT RUN** |
| §BL3 | Watch the ambient cars for a minute. | They **drive**, on roads, in lanes. Parked cars mean `joinTraffic` was refused or the driver never attached — the server log names which. This is the single most likely thing on this page to be wrong. | **NOT RUN** |
| §BL4 | Watch the pedestrians. | They walk on pavements rather than standing still in the road. A `wander refused` line in the log means they will stand, which is survivable but is not the feature. | **NOT RUN** |
| §BL5 | Have a second player stand on the same corner and compare. | You are both looking at **the same** pedestrians and cars in the same places. This is the whole point of the server-owned layer; if it fails, only the vanilla half is running. | **NOT RUN** |
| §BL6 | Post a race, then stand about 300 m to the side of the racing line as T-4 minutes passes. Run `ncm.ambient`. | One corridor is reported held, with more than one point and a 70 m radius. Ambient population along the route is gone by the time the lights come on. | **NOT RUN** |
| §BL7 | Repeat §BL6 but stand **on** the racing line, looking down it. | Nothing vanishes in front of you. The server logs `n ambient entit(ies) left standing this tick because somebody is close enough to watch them vanish`, and they go once you move away. A car blinking out in view is the failure this rule exists to prevent. | **NOT RUN** |
| §BL7b | While the race is **running**, run `ncm.ambient`. | The held corridor's id reads `session:<sessionId>`, not the route id — a live session is cleared along its own published gates rather than along whatever the calendar said about the route. | **NOT RUN** |
| §BL8 | Drive the race. | No ambient car or pedestrian is on the racing line. None of them appears in the session board, the result, or any standings — they are scenery, not entrants. | **NOT RUN** |
| §BL9 | During the corridor hold, look at the city **away** from the route, and run `ncm.ambient`. | It is **still populated**. The bucket line reads `suppression withheld: shared_bucket` — the vanilla switch has no radius and a race is nearly always in its window, so the shared world is never emptied for one (`KB-165`). Only our own entities are cleared, and only inside the corridor. | **NOT RUN** |
| §BL9b | Post a race and let its slot pass with **nobody entered**, then run `ncm.ambient`. | **No corridor is held.** An empty slot on a 20-minute cadence must not clear a road — if a corridor appears here, every route is being stripped permanently and `isHeldClear` is not reading the entrant count. | **NOT RUN** |
| §BL10 | After the race ends and the hold expires, run `ncm.ambient`. | No corridor is held, the bucket reports `open`, vanilla population is back, and ambient population repopulates around the players. | **NOT RUN** |
| §BL11 | Race with a full field and watch frame time, then run `ncm.ambient` for the counts. | The world holds its budget without hurting the race. Note the numbers that felt right — the shipped defaults (24 cars / 48 peds) are a guess, and this is the test that replaces the guess. | **NOT RUN** |
| §BL12 | `restart ncm_world` with a populated city. | The log reports `stopped: removed n ambient entit(ies)`, nothing is left standing with no owner, and the world repopulates after the restart. | **NOT RUN** |

## §BM - Component Wear & Tear lifecycle - **DEPLOYED ONLINE; BOOT PASS; DRIVING/SERVICE PASS OWED**

Scope: `L178`, migration **038**, core `parts.wear`, the `KB-163` configuration boundary, component service,
downward-only handling consequences, Parts Inventory condition presentation and the compact driving warning strip.
Hard / Medium / Soft tyre compounds and richer stress channels are explicitly outside this section.

**Offline evidence:** 614 core tests pass under Lua 5.4 and LuaJIT, including eight lifecycle assertions;
57 cross-scope references, 17 QA-observer and 35 vehicle-access checks are clean; `luac -p` is clean over 238
resource files; panel/race render checks pass at 157 / 55 assertions and cover condition/service presentation plus
attention/critical warning states. None of that proves the migration against live rows or that a Carrier-applied
wear contributor feels correct in game.

| # | Do | Expect | Result |
|---|---|---|---|
| §BM1 | Deploy and boot twice; inspect `schema_migrations` and `component_service`. | Migration 038 applies once, the second boot is a no-op, the table/index/FKs/check exist, and both resources boot without an unknown `parts.wear` module or missing-table error. | **PASS 2026-09-27/28 Online.** 23:28:03 UTC applied `038 component_wear` once with `pending=[]`; both resources loaded `parts.wear` and started without errors. 00:03:18 UTC logged `no pending migrations`, then `0 applied` with 001–038 and `pending=[]`. `SHOW CREATE TABLE` confirms the primary/unique/asset index, both FKs and JSON-validity check. |
| §BM2 | Record one installed component's exposure, drive more than one checkpoint, stop, re-CALL and restart. | Machine odometer and each component installed for the whole interval rise by the same accepted whole metres; restart/re-CALL add nothing by themselves. | **NOT RUN** |
| §BM3 | Drive less than 250 m after a checkpoint, park, then fit a replacement component. Query both assets. | The outgoing component receives the pending metres before displacement; the incoming component receives zero of that interval. Log contains `checkpoint asset=… (before component fit)`. This is the `KB-163` acceptance test. | **NOT RUN** |
| §BM4 | Force the pre-fit odometer transaction to fail, then attempt the fit. Restore the database and retry. | First attempt refuses with `odometer_checkpoint_failed`, configuration and custody do not change, and the accumulator is retained. Retry commits the same metres once and then fits; no history is lost or doubled. | **NOT RUN** |
| §BM5 | Inspect fresh and currently low-mileage Parts Inventory entries. | They show `NO ACTIVE CONDITION`, exact factual exposure and service count, with no health percentage, predicted failure distance or hidden threshold. | **NOT RUN** |
| §BM6 | In a controlled database copy, raise one tyre asset just past its deterministic threshold and reload/restart. | It derives the same `CONTACT PATCH WORN` condition after every reload; Parts Inventory says ATTENTION, and the driving HUD shows SRV + TYR amber/outline marks. No runtime roll occurs. | **NOT RUN** |
| §BM7 | Measure the same controlled Machine before/after the tyre condition through the Carrier readback/drive. | Grip and braking are reduced, drive is affected only through existing coupling, every multiplier is <= 1, and restoring exposure/service facts restores the exact deterministic result. | **NOT RUN** |
| §BM8 | Raise the controlled condition through critical severity. | SRV and the affected system switch to the filled red/shape-distinct critical state; unrelated system lamps stay absent and the HUD remains legible at 1080p, 1440p and ultrawide. | **NOT RUN** |
| §BM9 | Activate conditions in two assets mapped to the same system, then in two different systems. | The HUD shows one worst-severity lamp for the shared system, then one per system plus the single master lamp — never one lamp per component asset. | **NOT RUN** |
| §BM10 | Service an active stored component from Parts Inventory, retry the same request, then reconnect. | Exactly one negative `component_service` ledger row and one service row exist; exposure is unchanged; `relief_m` advances only the named threshold; the condition clears or reduces; retry/reconnect creates no second charge. | **NOT RUN** |
| §BM11 | Attempt service without enough funds, on a normal component, and on an installed component while occupied/moving. | Each refusal is named; no ledger/service row is created. Park and vacate the installed Machine and the same valid service becomes available. | **NOT RUN** |
| §BM12 | Remove, store and refit a worn/serviced component, then transfer it when trading exists. | Exposure, deterministic threshold and service history follow the physical asset. Refit does not reset or reroll it. Transfer remains pending until the trading system exists. | **NOT RUN** |
| §BM13 | Inspect aero, structure and chassis assets after large mileage. | Exposure rises for provenance, but no ordinary mileage condition, warning or physics consequence appears. | **NOT RUN** |
| §BM14 | Drive/finish with contact, incidents and penalties while holding distance comparable to a clean run. | Wear differs only by accepted distance. Sporting contact does not damage persistent property and a race flag carries no multiplier. | **NOT RUN** |

### What a PASS establishes, and what it does not

A full PASS establishes deterministic component-local mileage wear, persistent service relief, correct attribution
across fit boundaries, conservative physical consequences and private owner-facing presentation on Online. It does
not validate long-run pacing, used-part pricing/trade, engineer workmanship, stress-aware exposure, terminal
failure, crash damage or tyre compounds. Those remain separate decisions/evidence, not implied features.

## §BN - Street Call: a driver builds and posts their own race - **§BN1 FAILED LIVE TWICE ON 2026-09-28; SECOND CAUSE FOUND AND FIXED; NOT YET REDEPLOYED**

Scope: `L179` (the event), `L180` (placement), `L181` (the form), `L193` (the surface and the transport).
`competition.race_builder`, `ncm_league/server/impromptu.lua`, `ncm_world/client/race_builder.lua`, the `#build`
block of `web/venue.html`, `data.nodes.unregister`, `impromptuCooldownSec` / `impromptuMaxOpen`, and three UI
relocations. **No migration** -- `impromptu` has been in the `event.class` enum since schema 003 with no code on
either side of it.

**This section was rewritten after `L181`,** and its input rows again after `L193`. The `L179` step machine no
longer exists; `§BN5`-`§BN12` of that version tested a six-page click-through and are gone rather than adapted.

### Read this before re-running: §BN1 failed twice, for two different reasons, and the first fix hid the second

`KB-172` was real and is fixed: the form was published into a 4,032-byte player state bag at 11,515 bytes, so
nothing ever arrived. `L189` moved it onto `NcmStream` and that half works.

**But the card still never drew, because there are two hops and `L189` only bounded one** (`KB-178`). The client
received the streamed node list correctly and then called `Builder.schemaFromWire`, which re-expands it into
*both* `start` and `finish` -- back to the full 11,515 bytes -- and handed that to the page in a single
`page:send`. `KB-63`: that bridge drops large messages with **no error, no return value and no log line**. So
the page never rendered, never replied `build:drawn`, and the draw watchdog closed the card on every press.

**Two things are worth carrying out of this into how the next one of these is read.** The previous write-up
claimed the earlier six-page version had never worked either, and the owner said it had. **The owner was right**
-- it rendered because each of its steps sent at most five options, a few hundred bytes, under the threshold.
The page count was never the fault, and a size theory that contradicts an observation is a theory to discard.
And `web/build.html` put `ncm_world` at **8 of 8** `kMaximumWebSurfaces` while three transport pages come and
go, so `WebUI.create` could also be refused on timing alone -- a second, independent cause that was sitting
underneath the first two.

`L193`'s fix is structural: **the catalogue never crosses the bridge.** Lua holds the node list, the form, the
cursor and the picker; the page receives at most fourteen form rows or a nine-row picker window, as display
strings, with the route length computed in Lua. No message's size depends on how many nodes exist.

**The interaction model changed as a consequence, and the rows below reflect it.** `venue.html` is
`pointer-events: none` and is never focused -- which is what makes it safe to leave attached during a race
(`KB-67`) -- so there are no dropdowns and no mouse. Arrow keys, Enter, Backspace, Delete and PageUp/PageDown
are read in Lua as **physical device reads that need no focus**, and the pad works through the same path.
**`KB-61` is therefore not testable here, because it is not possible here: there is no focus to hold.** ESC is
deliberately not a close key -- it opens the pause menu. BACKSPACE closes, and F5 still toggles.

**Offline evidence, re-measured 2026-09-28 after `L193`:** full gate **ALL GREEN under both interpreters**;
`luac -p` clean over 255 resource files; `node --check` over 6 inline blocks; panel 219 / race 55 / **venue 53** /
nav 33 render assertions; docs authority OK over 79 documents. The `msgTray` failure noted in the previous
revision of this preamble is resolved. **`venue.html` now has a render harness** (`tools/venue-render-check.js`),
which closes `IDEA-649` for this page and also puts the option list and the history/practice panel under test
for the first time -- they had carried no guard and no harness while hosting three tenants, which is a large part
of why `KB-178` stayed invisible for a build.

**Read the server line first:** `[ncm_league/impromptu] CALLED impromptu:<tag>@<ts> | <route> | <venue> | <n> m |
<k> gate(s) | improvised start | start in <t> | by <driver>`. No such line means nothing was posted, whatever the
card said.

| # | Do | Expect | Result |
|---|---|---|---|
| **THE FORM** ||||
| §BN1 | Press **F5** standing in the street, out of a race. | One card on the **RIGHT**, ~520px wide, headed `STREET CALL / Call a race`, with Start already reading **"Here"** and the cursor resting on **Finish** -- the only field with no default. **If F5 does nothing, try `/ncm.build` or `/ncm.call`** -- a dead key is `IDEA-646`, a dead command is a real fault. (`/ncm.call` was named as a durable route in three documents and had never actually been registered until 2026-09-28; `IDEA-670`.) | **FAILED TWICE 2026-09-28 -- 03:23 UTC no card on eleven presses (cause `KB-172`, fixed by `L189`); still no card after that fix (cause `KB-178`, the client-to-page hop, fixed by `L193`). RE-RUN OWED after redeploy.** |
| §BN2 | Press **DOWN** then **UP**. | The highlight moves between rows and nothing else on screen reacts. **Then check you can still walk and look around with the card open** -- this page never takes focus, so the game keeps its input and `KB-61` is not merely handled but impossible. Client log: `form drawn`. | **NOT RUN** |
| §BN3 | Look at where the card is. | **Not centred, not full screen, not the F6 shell.** The middle of the view is clear. | **NOT RUN** |
| §BN4 | Press **BACKSPACE**. Then F5 again, then F5 once more. | Backspace closes the card. F5 toggles it. Two presses do not leave a card behind. **Then press ESC with the card open: the pause menu opens and the card is left alone** -- ESC is deliberately not bound here, because one control doing two jobs is `KB-32`. | **NOT RUN** |
| §BN5 | Put the cursor on **Start**, press **ENTER**, and page through with PageDown. | A picker opens showing **nine rows at a time** with a `n of 36` counter. **"Here" is first, then every one of the 35 race-legal places**, nearest first, each with its region and distance. If it shows four, the `L179` cap is still in the build. **Nine rows on screen with the count reading 36 is the point of `L193`** -- the other 27 never crossed the bridge. | **NOT RUN** |
| §BN6 | Open the **Finish** picker the same way. | The same 35 places and **no "Here"** -- a finish where you stand is the start (`L181`). The counter reads `n of 35`. Press **BACKSPACE**: the picker closes and the form is still there, unchanged. | **NOT RUN** |
| §BN7 | Look for a "type of race" field. | **There is none.** Not greyed, not defaulted-and-shown: absent. We cannot enforce drag, oval or drift, so the driver is never asked (`L181` point 3). | **NOT RUN** |
| §BN8 | Choose a finish and watch the header. | It reads `Here → <place> · N.NN km` and **POST THE RACE** becomes available. Before a finish is chosen it says *"Choose where it finishes."* and POST is disabled. | **NOT RUN** |
| §BN9 | Now **walk 200 m** with the form still open. | The distance in the header **changes**. "Here" is an intent resolved at submit, not a coordinate captured at open, and the preview must follow you or it is lying. | **NOT RUN** |
| §BN10 | Put the cursor on **Checkpoints** and press ENTER three times, picking a different place for each. | Three numbered rows appear, each with its own picker. The header shows `3 checkpoint(s)` and the distance rises to the sum of the legs, not the crow-flies. **Then put the cursor on Checkpoint 2 and press DELETE**: it is removed, the remaining two renumber, and the cursor lands on the add row rather than nowhere. | **NOT RUN** |
| §BN11 | Reorder your intent: remove the middle checkpoint. | It goes, the remaining two renumber, and the distance recomputes. | **NOT RUN** |
| §BN12 | Keep adding checkpoints past eight. | The button disables itself and reads `maximum 8 checkpoints`. | **NOT RUN** |
| §BN13 | Set Finish to the **same place** as Start (pick a node start, not Here). | A **Laps** row appears, and the header reads `<place> loop`. Set it back to a different finish and Laps disappears -- laps are meaningless on a point-to-point. **The cursor must not jump** when the row appears or vanishes: it is remembered by row key, not position, which is `I4`'s lesson from the venue list. | **NOT RUN** |
| §BN14 | Pick a finish only a few metres from where you stand. | Header goes amber: `... · NN m · too short to be a race`, and POST is disabled. The server enforces 250 m regardless of what any client shows. | **NOT RUN** |
| **POSTING IT** ||||
| §BN15 | Fill it in and press **POST THE RACE**. | The card closes. The `CALLED` line appears with `improvised start` when the start was Here. **Every connected player** gets a toast and a chat line naming the caller, the route and the countdown. Your map routes to the start. | **NOT RUN** |
| §BN16 | Read the `CALLED` line's gate count. | It equals the number of checkpoints you chose. A route with 3 checkpoints must log `3 gate(s)`, not 0 -- that is the difference between a chained route and a straight line between two ends. | **NOT RUN** |
| §BN17 | Open **F6 → RACE GUIDE**. | The called race is an ordinary row with its countdown ticking. It went through `NcmCalendar.adopt`, so nothing downstream should treat it specially. | **NOT RUN** |
| §BN18 | Walk to where you were standing when you posted it. | **There is a venue marker there** -- at your improvised start, not at any authored node. This is the whole of `L181` point 1 in one observation. | **NOT RUN** |
| §BN19 | Stand on the mark as entries open. | The venue card offers **ENTER RACE**. Standing 200 m away must not work: `venueRadiusM` is 60 and `L35` applies to a called race like any other. | **NOT RUN** |
| §BN20 | Let it go green and race it to the flag, through your checkpoints. | It forms, runs, results and settles on the ordinary path, and the HUD names your chosen checkpoints as gates. **Nothing about class `impromptu` should need a special case** -- any step that differs from a scenario event is the finding. | **NOT RUN** |
| §BN21 | After settlement, check the money. | **No purse.** `economy` is deliberately nil; a called race pays nothing and a payout here is a defect, not a feature. | **NOT RUN** |
| §BN22 | Wait a few minutes after the race, then check the server log. | `released route street_call_<tag> (event ...)`. Without that sweep every called race leaks a root and two nodes for the life of the process. | **NOT RUN** |
| §BN23 | After §BN22, open F5 again and look at the Start and Finish lists. | **Your previous improvised start is not in them**, and the lists are still 35 long. Temporary nodes lack the authored `raceLegal` flag, so they are excluded whether or not the sweep has run yet. | **NOT RUN** |
| **THE LIMITS, WHICH ARE THE POINT** ||||
| §BN24 | Immediately after posting, press F5. | Refused in chat: *"You called one recently. Give the street a minute."* No card opens. `impromptuCooldownSec` is 900. | **NOT RUN** |
| §BN25 | With two called races open, have a third attempted. | Refused: *"There are already enough open races on the board."* Both guards exist because one alone does not bound the board (`KB-165`). | **NOT RUN** |
| §BN26 | Open a form, leave it open, let somebody else fill the board, then press POST. | Refused **at submit**, and **the reason appears in red inside the card**, not only in chat. A guard that can only fire on the way in is half a guard (`KB-155`); a refusal the driver cannot see while looking at the form is half a message. | **NOT RUN** |
| §BN27 | Press F5 while in a live race. | Nothing opens (`open ignored: racing`). Then open the form and have a race start around you: it closes itself (`closed (race started)`) rather than sitting over the race HUD. | **NOT RUN** |
| §BN28 | Open the form standing on a venue mark with the venue list showing. | The venue list yields via `NcmClientBuildActive`, and comes back when the form closes. Two surfaces cannot own one screen corner. | **NOT RUN** |
| §BN29 | Restart `ncm_league` with a called race pending, then open F6. | The race is **gone** -- its row closed on boot rather than sitting on the board with no scheduler behind it, and its route was never persisted so it could not be restored. Nobody is told, which is `IDEA-645`. | **NOT RUN** |
| §BN30 | With the form open, `restart ncm_world`. | No card is left behind, and the venue option list works again afterwards. There is no focus to recover -- that is `L193`'s point -- but a card left on screen would keep the option list suppressed, which is the failure this row now looks for. | **NOT RUN** |
| **THE RELOCATIONS (`L180`) -- look, do not command** ||||
| §BN31 | Stand on a venue mark with entries open. | The entry panel is on the **right**, not across the middle of your view. | **NOT RUN** |
| §BN32 | Race, and look at the live race graph. | It is on the **right**, and every driver label reads **leftward, inward**. A name running off the right edge means the mirror is half-applied -- the box moved and the labels did not. | **NOT RUN** |
| **THE TRANSPORT (`L193`, `KB-178`) -- this is the part that failed twice** ||||
| §BN33 | Press F5 and read the SERVER log. | `form published player=<n> nodes=35 bytes=<n> head=<n> packets=<n>`. This half was already fixed by `L189`; a missing line means the server refused and said so in chat. | **NOT RUN** |
| §BN34 | Read the CLIENT log for the same press. | `ncm:build stream begin id=... nodes=35`, then `ncm:build stream complete id=... nodes=35`, then `opened with 35 node(s)`, then **`form drawn`**. | **NOT RUN** |
| §BN35 | **The row that `KB-178` is about: confirm `form drawn` actually arrives.** | `form drawn` appears within 2500 ms of `opened with 35 node(s)`. **If instead you see `FORM DID NOT DRAW in 2500 ms`, the client-to-page hop is broken again** -- check for a `PAGE ERROR` line first, and if there is none, something has started sending the page a payload whose size grows with the catalogue. That is the whole bug, and it is silent by nature. | **NOT RUN** |
| §BN36 | Open a picker and watch the client log while paging through 35 nodes. | **No stream, no batching and no chunk lines at all** -- only the small `build:picker` messages, nine rows at a time. Nothing in this feature should ever need a bounded transport to the page again, because nothing sends the page a list. | **NOT RUN** |
| §BN37 | Count NCM's WebUI surfaces during a session that has used the Carrier bridge, a race and the form. | **Seven, never eight** (`IDEA-570`). No `build WebUI failed` or surface-refusal line anywhere. `web/build.html` is deleted; if anything still references it, that is a stale deploy. | **NOT RUN** |
| §BN38 | With the Street Call card open, walk into a venue ring. | The venue option list does **not** draw underneath or on top of the card. The two share one page and `client/calendar.lua` stands down on `NcmClientBuildActive`; close the card and the option list returns. | **NOT RUN** |
| §BN39 | Open the form, then open the F6 panel on top of it. | The arrow keys drive the F6 panel and **not** the Street Call card -- `race_builder.lua` checks `Open77.input.isCaptured()` before reading a key, so a focused surface keeps its own input. Close F6 and the card responds again. | **NOT RUN** |
| §BN40 | With the card open and Start on **Here**, walk 300 m and watch the header. | The distance updates as you move (refreshed every 700 ms), because a `Here` start is resolved at submit time and a stale length would misreport the route. | **NOT RUN** |
| §BN41 | Drive the whole form with a **controller** only. | D-pad moves and changes, **A** opens a picker and posts, **B** closes, shoulder buttons page through a long list. No keyboard needed at any point. | **NOT RUN** |
| §BN33 | During that race, check the graph against the rest of the HUD. | It clears the vanilla minimap (bottom right) and NCM's own strip/board/banner (top centre). | **NOT RUN** |

### What a PASS establishes, and what it does not

A PASS establishes that a driver can call a real race **from where they are standing**, with any start, any
finish and any chain of checkpoints, in one form; that the improvised start becomes a real venue and is cleaned up
afterwards; and that the result posts through the scheduler, appears on the Guide, is entered at the line and
settles on the ordinary path.

It establishes **nothing about disciplines other than a street sprint** -- drag, oval and drift are not offered
precisely because they cannot be enforced, and `IDEA-648` is where that is revisited. It says nothing about
**Quinn's half**, the one-question pre-built offer (`IDEA-641`), nor about challenging a **specific** driver,
which is the two-entrant case (`IDEA-642`, and the live half of `IDEA-063`). The cooldown and cap are a first
guess at a duty cycle, not a measured one. And a called race **pays nothing**, so it cannot be validated as an
economic loop (`IDEA-643`).

## §BQ - The quest graph: Dex, Setup Stu, Rico, and Messages as a conversation - **DEPLOYED ONLINE 2026-09-28 03:05 UTC; MIGRATION PASSED; PLAYER-FACING PASS OWED**

Scope: `L183`. Core `graph.contacts` / `graph.conversation` / `graph.opening`, **migration 039**,
`ncm_league/server/graph.lua`, MESSAGES as a shell tab in `panel.html`, and the release of F9.

**Migration 039 has now run and is verified (`§BQ1`, `§BQ2` PASS).** `message.from_kind` reads
`enum('team','system','race_control','character','dispatch','driver','market','manufacturer','championship','organizer')`
on the canonical database, `thread_id` exists, and all three new tables are present. That was the gate on
everything below: had the ENUM not widened, every character line would fail its INSERT and the surface would be
empty with no error a player could see.

**Deploying also surfaced `KB-168`, which is why nothing below this line should be trusted from the offline gate
alone.** Four of this feature's own statements passed a nil where OPEN//77 needs a sentinel, so nothing persisted
across a restart; the harness had accepted them because the SQL double was more forgiving than the real bridge.
Fixed and redeployed in the same session, and the harness now models the bridge -- but the *reason* it escaped is
that no live write had happened yet, and that is still true of every step from `§BQ3` down.

**Offline evidence:** 713 core tests green under Lua 5.4 and LuaJIT (70 of them in `test_conversation` and
`test_opening`, including the `L176` pairwise-overlap check over the three authored scripts); **93 host assertions
in `tools/test-quest-graph.lua`**, which found three real defects before any deploy (`KB-167`); `luac -p` clean
over 250 resource files; panel **201** render assertions, up from 157, of which ~40 are the new surface.

**Read the server lines first.** `[ncm_league/graph] quest graph ready: 3 authored contact(s), 8 push(es)` at
boot; then `MET dex by <driver> [solicited]`, `LEAD person:<who> via <contact> for <driver>`,
`curiosity <driver> -> <n> (<category>)`, and `budget refused <contact>.<node> (<intent>): <reason>`. A refusal
line is **normal** and is how the §20 budget reports itself; silence with no line at all is the fault.

**`ncm.graph.push <playerId> <contact> [node]`** is a console command, and most of this section needs it: the real
triggers are behavioural and take real play to satisfy.

| # | Do | Expect | Result |
|---|---|---|---|
| **THE MIGRATION -- everything below depends on this** ||||
| §BQ1 | Start `ncm_league` on the live database and read the migration line. | `migration 039 quest_graph applied (5 statement(s))`. Then confirm in SQL that `message.from_kind` accepts `'character'` and `'driver'`. | **PASS 2026-09-28 03:00 UTC** -- migration line seen; ENUM, `thread_id` and all three tables verified in SQL |
| §BQ2 | Restart `ncm_league` again. | `no pending migrations`. A second run must change nothing. | **PASS 2026-09-28 03:05 UTC** -- `no pending migrations`, `migrations: 0 applied`, `schema entries 39` |
| **DEX -- the unmissable contact (§2)** ||||
| §BQ3 | Join with a driver who has never met anybody. Wait ~20 s. | A toast naming NCM DISPATCH, and `MET dex ... [solicited]` on the server. | **NOT RUN** |
| §BQ4 | Press **F6** and look at the tab strip. | **MESSAGES** sits between WHEEL/PEDALS and **HELP**. Nothing else moved. | **NOT RUN** |
| §BQ5 | Press **F9**. | **Nothing happens.** The key is released; no panel, no error. | **NOT RUN** |
| §BQ6 | Open MESSAGES. | Dex is in the rail with an unread badge; his three messages are in the pane, **oldest at the top**, and the pane is scrolled to the newest. | **NOT RUN** |
| §BQ7 | Read his opening. | Three messages, the draft's own paragraphs, ending *"Want the introduction?"*. **It is not trimmed** -- `L176` struck the word ceiling, and a short Dex here means someone reapplied a withdrawn finding. | **NOT RUN** |
| §BQ8 | Pick **"Put me through."** | Your reply appears **on the right**, in its own bubble, immediately. | **NOT RUN** |
| §BQ9 | Watch the rail. | **Rico appears and has actually spoken** -- his *"First one's free"* is there, not just his name. This is `KB-167`(a): a solicited introduction must not wait out the world's cooldown. | **NOT RUN** |
| §BQ10 | Double-click a reply as fast as you can. | One reply is recorded, not two. Every button disables on the first click. | **NOT RUN** |
| **THE DOMAIN BOUNDARY (§0.4)** ||||
| §BQ11 | Ask Dex *"I have a question"* -> *"Does weather affect racing?"* | He answers the general question **and says to ask Stu about your own setup**. He does not explain your car. | **NOT RUN** |
| §BQ12 | Ask *"Why doesn't this part fit my car?"* and take **Open Setup Stu**. | Stu's thread is selected. Dex did not answer it himself. | **NOT RUN** |
| §BQ13 | Ask *"What's the deal with markets?"* -> *"Are there other markets?"* | *"Yes. Most don't advertise to everybody..."* -- **and no number anywhere.** `L171` lets the Market UI disclose the roster's shape; Dex must not recite a count. | **NOT RUN** |
| **SETUP STU -- the guaranteed handoff (§3)** ||||
| §BQ14 | With Dex answered, wait for the heartbeat (up to 5 min) or force it. | Stu introduces himself. `§3.1` calls this guaranteed, so a Stu who never arrives is a failure even though nothing in the UI says he was coming. | **NOT RUN** |
| §BQ15 | In a stock car, ask *"Take a look at what I'm driving."* | One of the three authored reactions, matching what you are actually in -- or *"Nothing on my screen yet"* if the host knows nothing. **He must not guess.** | **NOT RUN** |
| §BQ16 | Reply once, then read his second beat. | The Quinn/Foreman handoff, including *"instead of waiting on the board"*. That word is a **recorded exemption** (`L183`), not a mistake. | **NOT RUN** |
| §BQ17 | Take **"Send me their line."** | A lead is recorded (`LEAD person:quinn via stu`) and **Quinn does NOT appear in the rail.** Hearing a name is not meeting somebody (`L175`). | **NOT RUN** |
| §BQ18 | Instead, defer it, then reopen Stu. | *"About those race guys..."* is offered and is **highlighted**. No nag arrived while you were away (§2.2). | **NOT RUN** |
| **CROSS-CHARACTER TELEMETRY -- the draft's own headline (§0.7, §8.1)** ||||
| §BQ19 | Ask Stu hardware questions -- *"Where do people find better parts?"*, *"What do you think of this part?"* -- five or more times. | `curiosity <driver> -> n (<category>)` climbs. **Nothing appears in any UI.** §3.4: this is not a meter shown to the player. | **NOT RUN** |
| §BQ20 | Keep playing for ~20 minutes. | **Rico** says *"You ask a lot of questions about hardware."* Nobody told him; it was Stu's conversation. This is the single most important step in the section. | **NOT RUN** |
| §BQ21 | Check the timing of §BQ20. | It did **not** arrive in the same breath as the Stu conversation. §8.1's cooldown exists so Rico reads as a man with ears, not a wiretap. | **NOT RUN** |
| §BQ22 | Walk it to *"Put me in touch"*. | `LEAD person:needle via rico`. Needle does not appear in the rail. | **NOT RUN** |
| §BQ23 | Now wait through two or three more heartbeats. | **Rico does not say it again.** `KB-167`(c): a world-initiated beat is pushed once. | **NOT RUN** |
| **THE CONTEXT SHELF (§2.4)** ||||
| §BQ24 | With at least one lead open, ask Dex *"I have a question."* | *"Who is Needle?"* (or whoever you heard of) sits **above** the generic categories, as a dashed reply. | **NOT RUN** |
| §BQ25 | Ask it. | Dex says what he honestly knows and no more. He does not open a contact who cannot answer. | **NOT RUN** |
| §BQ26 | Look hard at every part of the Messages surface. | **No count, fraction, percentage or score anywhere** -- no "2 leads", no "3/8", no curiosity number (`L171`, `L175`). An **unread count is fine**: that is a fact about an inbox. | **NOT RUN** |
| **THE BUDGET (§20)** ||||
| §BQ27 | On a fresh driver, watch the first ten minutes. | Contacts arrive **one at a time**. Two introductions in one moment is the failure §20 rule 1 exists to prevent. | **NOT RUN** |
| §BQ28 | Read the server log through all of the above. | `budget refused ...` lines appear and name a reason. A budget that never reports refusing anything is a budget that is not running. | **NOT RUN** |
| **NOTICES ARE NOT CONVERSATIONS** ||||
| §BQ29 | Get a seat offer (`ncm.invite`) while a conversation is open. | It appears in the **tray beneath the pane**, keeping ACCEPT / DECLINE -- not as a chat bubble, and not in the rail. | **NOT RUN** |
| §BQ30 | Accept it from there. | It works exactly as before, and the notice leaves the tray. | **NOT RUN** |
| §BQ31 | Read the seat-offer toast. | It says **F6 -> MESSAGES**. No toast anywhere may still say F9. | **NOT RUN** |
| **DURABILITY AND THE FAILURE MODES** ||||
| §BQ32 | Mid-conversation, `restart ncm_league`, then reopen MESSAGES. | The transcript is intact and the conversation is resting where you left it. **This is the `KB-168` regression check** -- it is exactly what a nil-parameter hole breaks, and it passed offline while broken. | **NOT RUN** |
| §BQ33 | Reconnect entirely. | Same. Nobody reintroduces themselves. | **NOT RUN** |
| §BQ34 | Open MESSAGES, leave it open, and `restart ncm_world`. | **Input returns to the game.** The one failure that costs a reconnect (`KB-61`), and worth causing deliberately once. | **NOT RUN** |
| §BQ35 | Stop the database, then open MESSAGES. | The panel draws and says what it can. It does not hang and does not show a blank card. | **NOT RUN** |
| §BQ36 | With MESSAGES open, use the pad: rail, pane, replies. | Focus moves and the transcript scrolls. The shared nav layer owns this and the surface is new to it. | **NOT RUN** |
| §BQ37 | Run `/ncm.msgs.list`, then `/ncm.say dex`. | The chat twins list conversations and the available replies. Essential information must never be reachable through exactly one graphical path. | **NOT RUN** |

### What a PASS establishes, and what it does not

A PASS establishes that **a character can speak to a player at all** -- which nothing in NCM Online could do
before migration 039 -- that a conversation persists and rests rather than progressing, that replies are projected
from live state, that one contact can react to what the player did through another, that hearing a name grants
knowledge and not access, and that Messages is a conversation surface reached from the shell instead of a notice
list behind a function key.

It establishes **nothing about the other fifteen contacts**, all of which remain SPEC and most of which are
blocked on substrate that does not exist -- the Scanner (Flashbulb), physical NPC dialogue (Auntie, Dave),
wagering (Billie), thread steps (Needle's trust test), a claim store that cannot be mistaken for a result
(Knuckles). `graph.contacts` carries each reason. It says nothing about the **#1 Fan** (`IDEA-655`), who is next
and whose only open question is a line of copy. It does not validate the `TUNE` thresholds as *balance* --
§21 is explicit that they are authoring values, and §BQ19's "five or more" is a first guess at a duty cycle, not a
measured one (`IDEA-658`). And it proves nothing about **group threads** (`IDEA-656`): every thread tested here has
exactly two parties, so the renderer has never had to say which of two senders spoke.

---

## §BR - Other drivers on your map and minimap, city tier - **BUILT LOCALLY; NOT DEPLOYED; AWAITING LIVE PASS**

Scope: `L184`, `IDEA-650`-`IDEA-654`. Core `world.presence`, `ncm_world/server/presence.lua`,
`ncm_world/client/players_map.lua`, six `presence*` tunables in `server/identity.lua`. No migration, no new
permission, no new WebUI surface.

**Offline evidence:** 19 assertions in `test_presence` over the pure decision (self and other buckets excluded,
nearest-first ordering, the pin cap and the measured byte budget, name sanitisation, and the
create/move/retitle/remove plan), whole gate green under Lua 5.4 and LuaJIT, `luac -p` clean.

**What no double can answer, which is why this section exists.** Every offline test asserts that the service
decided correctly. Nothing offline can say whether a pin is legible among thirty-odd landmark pins, whether
`CPO_RemotePlayerVariant` renders on the fullscreen map at all, or whether a 5 s pin reads as alive or as
broken to a driver at speed. **This needs two clients**, and §BR2 decides whether the feature works at all.

| # | Do | Expect | Result |
|---|---|---|---|
| §BR1 | Join with one client. Run `ncm.presence` in the server console. | It prints `enabled=true tick=5s`, a payload count that climbs, and one line per connected player with their bucket and position. A `players.positions unavailable` line means the native is missing on this build. | **NOT RUN** |
| §BR2 | Two clients in the street (not in a session), a kilometre or more apart. Open the full map on each. | Each sees ONE pin, in roughly the other's place, carrying the other's display name when highlighted. This is the whole feature. | **NOT RUN** |
| §BR3 | Watch the minimap while the other driver moves. | The same pin is on the minimap and it moves in ~5 s steps. Steps are expected, not a defect: the platform's snapshot is up to 2 s old before our tick adds to it. | **NOT RUN** |
| §BR4 | Run `/ncm.playersprite` on one client and look at both surfaces. | This switches to `remote_player` (`CPO_RemotePlayerVariant`), from a dormant multiplayer HUD. Record honestly whether it renders on the minimap, the fullscreen map, both or neither — that answer is what `IDEA-653` is waiting for. Run it again to return to `vehicle`. | **NOT RUN** |
| §BR5 | Run `/ncm.players` twice. | The pins vanish, a notification says so, and they come back. Nothing else on the map moves: landmarks and any NCM navigation pin are untouched. | **NOT RUN** |
| §BR6 | Start a race on one client and watch that client's map during the session. | Every presence pin disappears for the duration and returns afterwards. A rival pin during a session is the thing `L184` refused. | **NOT RUN** |
| §BR7 | While one client races in its own bucket, look at the map of a client left in the street. | A driver in ANOTHER bucket must never appear. If a pin shows somebody who is not in your world, the bucket filter is not holding. | **NOT RUN** |
| §BR8 | Have a driver disconnect while you watch their pin. | It disappears within about one tick. A pin that stays is a remove failure and accumulates against the 128-blip quota. | **NOT RUN** |
| §BR9 | After twenty minutes with the layer on, run `/ncm.presence` on the client. | `pins` equals `rows`, both no greater than 24, and every landmark pin is still there. A climbing pin count against a flat row count means pins are being created rather than moved. | **NOT RUN** |
| §BR10 | Restart `ncm_world` with the map open. | No stale pins survive into the new generation, and nothing takes the player's input (`KB-61` is the standing hazard for any client surface). | **NOT RUN** |

**If §BR2 fails outright**, read the server line first: no payloads means `positions()` refused; payloads with
`rows=0` for everybody means the bucket filter or the two-second snapshot age, not the pins.

## §BS - Safety Rating that is worth reading - **BUILT LOCALLY; NOT DEPLOYED; AWAITING LIVE PASS**

Scope: `L187`, `KB-171`, `IDEA-090`. Core `driver.progression` (`M.SR` and the SR block of `apply`), plus one
line in `ncm_league/server/progression.lua` that supplies `ctx.distanceM`. No migration, no new command, no new
WebUI surface, no change to incident detection or to corrected time.

**Offline evidence:** `test_quali.sr_is_balanced_in_both_directions` — the distance-scaled gain and its cap, the
car-versus-scenery weighting reproducing the observed -0.80 race as -0.147, the free scenery band moving SR not
at all and announcing no delta, the `maxLoss` floor under a 40-incident wreck, the bare-count fallback charging
as car contact, and the min/max clamps. `progression_licence_sr_rating` and `kb38_once_only_accomplishments_are_granted_once`
still pass unchanged. Whole gate green under Lua 5.4 and LuaJIT, `luac -p` clean, `ncm-build` vendored.

**What no offline test can answer, which is why this section exists.** Every assertion above proves the
arithmetic. None of them can say whether the number now *feels* like it means something to a driver: whether a
clean race reads as a reward, whether a tap reads as a fair cost, or whether the free scenery band reads as
generous or as broken. That is the whole complaint the rebalance answers, and it is a judgement call made at
speed, not in a fixture. **§BS3 and §BS6 are the ones that matter.**

**Blocked-on note.** `KB-34` (car-to-car contact filed as scenery) is fixed but **unverified live**. Until
§BS5 shows `kind=car` with `other` populated, every SR number observed here is a scenery number, and the
car-contact half of `L187` is untested by anything but the fixture. Do not tune again before §BS5 passes.

| Step | Do | Expect | Result |
|---|---|---|---|
| §BS1 | Deploy, boot the server, and read one driver's SR with `/ncm.profile` before racing. | The stored SR is whatever alpha left it at; nothing was migrated and nothing was reset (`L75`). | |
| §BS2 | Read the server's plan line for the first event and note the route length. | `PLAN … route=N m` is non-zero, so `ctx.distanceM` has a real value to scale the gain by. | |
| §BS3 | Run one clean solo time trial on a route of roughly 3 km. | `sr +0.14 → …` in chat and the log, not `+0.05`. **The judgement: does finishing clean read as worth doing?** | |
| §BS4 | Repeat on a route about twice as long, still clean. | A visibly larger gain, capped at `+0.30` once past ~8.3 km. A longer clean race pays more than a short one. | |
| §BS5 | Two clients, deliberate car-to-car contact, one band-3-ish hit each. | **`kind=car` with `other` populated on BOTH drivers** (`KB-34`), and about `-0.18` each — a real cost, recovered by one or two clean races. | |
| §BS6 | One client, scrape a wall once lightly and finish. | The incident is recorded (`sr.incidents` rises, the result carries its seconds) and **SR does not move at all** — no gain, no loss, and no `SR -0.00` line in chat. | |
| §BS7 | Same client, wreck repeatedly against scenery — five or more hits — and finish. | A single modest drop, an order below the old numbers, never worse than `-0.50`. **The judgement: is this still enough of a consequence?** | |
| §BS8 | Retire or disconnect mid-session after contact. | Unfinished sessions earn no clean credit and are charged as before; nothing about the rebalance changed who is `finished`. | |
| §BS9 | Race a quali or practice session with contact. | SR does not move for a non-race session (`apply` returns early); only the race settles the badge. | |
| §BS10 | After a run of clean races, read `/ncm.profile` and the `driver_sr` row. | `sr`, `incidents` and `clean_sessions` agree with the announced deltas, and the `driver_profile.sr` JSON matches the badge. | |
| §BS11 | Drive a clean race with a driver already at 9.9x, and a dirty one with a driver near 0. | The ceiling holds at 10 and the floor at 0; neither overshoots. | |

**If §BS3 shows `+0.05`**, `ctx.distanceM` is not arriving: `rec.course.lengthM` is nil and the event's
`distanceM` is nil too, so read the `PLAN` line from §BS2 before touching the coefficients. **If §BS5 shows
`kind=object`**, stop — that is `KB-34` still live, and no SR reading in this section means what it appears to.

## §BT - Messages reads like a messenger - **DEPLOYED TO ONLINE 2026-09-28 16:41 UTC; AWAITING LIVE PASS**

Scope: `L190`, `KB-173`, `IDEA-671`. `ncm_world/web/panel.html` (the whole Messages block), one query and one
payload field in `ncm_league/server/organized.lua`, one comment in `ncm_world/client/panel.lua`. No migration, no
new command, no new WebUI surface, no change to the quest graph or to what the server projects.

**Offline evidence:** `tools/panel-render-check.js`, 219 assertions green -- the tray renders nothing at all; an
offer appears in the rail under its team's name and does not steal the pane; opening it reads it, shows the
subject and body, and puts `ACCEPT` / `DECLINE` in the composer; answering reports `panel:act` once and disables
both; a resolved offer leaves the rail and the pane falls back to the conversation; history draws at once; an
appended line is **not** on screen until its timer fires, with no reply offered meanwhile; the clock follows the
newest bubble. The harness grew real queued timers and class selectors to assert those last two. Gate green under
both interpreters, `ncm-build -Check` clean.

**What no offline test can answer.** Whether the pacing reads as a conversation or as lag, and whether an offer
that no longer shouts from a tray is still noticed in time to accept it. The toast and the chat line (`/ncm.inbox`,
`/ncm.accept`) are unchanged and remain the safety net; §BT3 is the one that matters.

| # | Do | Expect | Result |
|---|---|---|---|
| §BT1 | Open F6 -> MESSAGES with a Dex conversation already in progress. | The transcript draws instantly, oldest at the top, scrolled to the bottom. A stamp above the first bubble of each gap, a clock on the last bubble only, a `NEW` rule where unread begins. **No second pane under it.** | |
| §BT2 | Pick a reply. | Your line appears at once on the right. Dex's answer follows on its own, behind a typing indicator, one line at a time; the reply buttons come back only after the last line lands. | |
| §BT3 | Have a seat offer arrive while MESSAGES is open on a conversation. | The toast fires as before, the offer appears in the rail as a thread under the **team's name** with an unread badge, and the conversation being read is **not** interrupted or replaced. | |
| §BT4 | Open the offer thread and accept from the composer. | Subject and body are there as a message; `ACCEPT` / `DECLINE` are composer buttons; accepting takes the seat exactly as `/ncm.accept` does, both buttons disable, and the thread leaves the rail once resolved. | |
| §BT5 | Decline an offer instead. | The same, refused: the seat is released and the thread leaves the rail. | |
| §BT6 | Run `/ncm.inbox`. | It lists **offers only** -- no conversation lines, no numbering that counts them (`KB-173`). `/ncm.read 1` reads the offer. | |
| §BT7 | Let an offer expire without answering. | It stops being answerable and leaves the rail; nothing claims it was accepted. | |
| §BT8 | Close the panel mid-arrival and reopen it. | The full transcript is there at once, including the line that was mid-flight. Nothing is lost and nothing re-animates. | |
| §BT9 | With no conversations and no offers at all, open MESSAGES. | "No conversations yet" in the rail and "Nobody has written to you yet." in the pane. No empty tray, no error. | |
| §BT10 | Navigate the whole surface with a pad, then with the keyboard alone. | Rail rows, composer buttons and the tab strip are all reachable; the offer thread is reachable without a mouse (`L142`). | |

**If §BT3 shows the offer taking the pane**, the notice thread is being auto-opened somewhere -- that is the
behaviour the tray had and the reason it was intrusive. **If §BT2 shows every line at once**, the payload is
arriving as a fresh thread rather than an append (check that line ids are stable across `ncm:graph` sends).

## §BU - Dedicated multi-vendor NCM Rig Bridge - **DEPLOYED TO ONLINE 2026-09-28 16:41 UTC; AWAITING LIVE PASS**

Scope: `L185`, `L186`, `L188`, `L191`, `IDEA-661`-`IDEA-665`, `IDEA-667`, `IDEA-672`.
`ncm/rig_bridge/`, `tools/build-rig-bridge.ps1`, and the FFB/Machine port split in
`ncm_world/client/carrier_bridge.lua`. Carrier source and package are explicitly out of scope and unchanged.

**Offline evidence, re-verified independently 2026-09-28:** clean warning-free Release build from a fresh
configure; `Main`, `Query`, `Supports` exports present; imports are Windows system DLLs only (`DINPUT8`,
`IPHLPAPI`, `KERNEL32`, `USER32`, `WS2_32`, `ole32` — no vendor SDK and no redistributable, so the package needs
nothing installed beside it); `ncm_rig_mapping` passes steering centre/extremes, pedal inversion, calibration and
deadzone; package `ncm-rig-bridge-0.1.0.zip` (`sha256 9e86c22c…`) contains DLL, safe config, redscript, README
and notices; `tools/ncm-test.ps1` is green. This is not hardware or in-game evidence.

**Two corrections found by that pass, before any of the rows below were run.** `KB-174`: the three-rung force
ceiling §BU9 asserts was not enforced in code — it is now, at the setter and the loader, from one shared
constant. `KB-175` / `IDEA-673`: the constant-force channel is never fed, so **§BU9 tests speed-scaled centring
and damping only** — do not expect road texture or collision jolts from this build, and do not read their
absence as a §BU9 failure.

| # | Do | Expect | Result |
|---|---|---|---|
| §BU1 | Install the package with FFB left disarmed. Cold-launch the exact Online client. Read the newest `ncm_rig_bridge-<pid>.log`. | Game reaches the menu; one line names every attached DirectInput endpoint with a stable GUID, product name and FFB capability. No Carrier file or log changed. | **NOT RUN** |
| §BU2 | Confirm the G29, separate Thrustmaster pedals and ESP32 rim are all attached concurrently. Move every axis and press mapped rim buttons. | The WHEEL panel names the bound steering, pedal and rim endpoints; no endpoint is selected only by enumeration order. | **NOT RUN** |
| §BU3 | Bind steering, throttle, brake and clutch to their logged GUIDs, using separate devices where appropriate; relaunch. | The same roles restore to the same endpoints. Resting pedals read zero; full travel reaches one; centred steering is zero. | **NOT RUN** |
| §BU4 | Mount one player vehicle with parked/AI/remote vehicles visible. Drive with the rig, then dismount. | Steering/throttle/brake reach only the exact mounted local vehicle. The first injection is logged. Nothing else moves, and injection stops on dismount. | **NOT RUN** |
| §BU5 | Drive with the ordinary gamepad while the rig remains attached, then use both sources. | Gamepad remains usable. The larger requested magnitude wins per axis; Rig Bridge does not zero or seize vanilla input. | **NOT RUN** |
| §BU6 | Unplug and reconnect one pedal/rim endpoint while running. | Input for that endpoint withdraws; no stuck key or pedal remains; after the bounded refresh the same GUID rebinds without restarting the game. | **NOT RUN** |
| §BU7 | Join Development with Carrier and Rig Bridge both loaded. Run `/ncm.carrier`. | FFB/Rig connects in `38520-38523`; Machine/Carrier connects in `38480-38483`; Parts/weather still reach Carrier. No bind-order ambiguity and no ninth WebUI surface. | **NOT RUN** |
| §BU8 | In WHEEL, keep force disarmed and press TEST PULSE. Then arm at rung 1 and press it again. | Disarmed produces no force. Armed produces one short conservative pulse on the selected FFB endpoint only. | **NOT RUN** |
| §BU9 | Drive slowly, then at road speed, at rung 1. Adjust centring and stiffness in the panel. | Spring/damper respond smoothly and the panel round-trips their values. Unknown hardware never exceeds the hard three-rung ceiling — now enforced in `config.hpp` rather than assumed from the panel's values (`KB-174`). **Centring and damping only**: the constant-force channel is unfed in 0.1.0, so silence where road texture would be is expected, not a failure (`KB-175`). | **NOT RUN** |
| §BU10 | While force is active: pause telemetry, dismount, unplug the wheel, disable FFB, and exit the game, one at a time. | Every case releases force; the telemetry watchdog does so within 250 ms. No effect remains latched after process exit. | **NOT RUN** |
| §BU11 | Start two clients on one PC with both plugins. | Each WebUI descendant binds only to its own game's Rig Bridge and Carrier. Cross-process peers are refused and each client finds the next port. | **NOT RUN** |
| §BU12 | Remove/disable only Rig Bridge and launch again. | Gamepad and Carrier still work; the WHEEL page reports no rig listener; missing rig support never zeros steering or prevents joining. | **NOT RUN** |

The external companion retires only after §BU2-§BU10 all pass. A DirectInput miss on one endpoint opens a
provider-specific follow-up for Windows.Gaming.Input or Raw Input; under `L186` it does not invalidate the mod.

## §BV - Health regenerates, and police are allowed to come - **DEPLOYED TO ONLINE 2026-09-28 16:41 UTC; AWAITING LIVE PASS**

Scope: `KB-180` (fixed), `IDEA-677`/`IDEA-678` (probes only). `ncm_world/server/vitals.lua`, the
`playerRegenPerSecond` tunable and the `players.stats.apply` permission in `ncm_world/open77.lua`.

| # | Do | Expect | Result |
|---|---|---|---|
| §BV1 | Join, then read the server console. | `[ncm_world/vitals] player=N health regen 2.00 hp/s (connect)`. **No** `setRegen ... refused` line. A refusal names its reason; `permission` means the manifest change did not deploy. | **NOT RUN** |
| §BV2 | Take damage (crash hard, or admin `health <you> 40`), then stop and wait 60 s. | Health climbs back to full at roughly 2 hp/s. | **NOT RUN** |
| §BV3 | Die, respawn, take damage again, wait 60 s. | Regen still works after the respawn, re-asserted within 20 s by the sweep at worst. | **NOT RUN** |
| §BV4 | (`IDEA-677` probe) Driving on the street, run `ncm.wanted <your player id> 2` in the server console (console-only; `ncm.wanted <id> 0` clears). The console line prints the server policy it set. | NCPD units spawn and pursue. Record whether they do, how long it takes, and whether they have a minimap icon (`IDEA-678`). **This decides whether NCM-driven police is buildable at all.** | **NOT RUN** |

## §BW - Player Exchange: exact heterogeneous barter in F6 - **DEPLOYED TO ONLINE 2026-09-28 16:41 UTC; AWAITING LIVE PASS**

Scope: `IDEA-247`, `L194`, migration 040, `economy.trade`, `ncm_league/server/trade.lua`, the Machine
materialization registry and the F6 **EXCHANGE** tab. Use two real Drivers with disposable test assets. Record
all asset ids before starting; visual sameness is not identity proof.

| # | Do | Expect | Result |
|---|---|---|---|
| §BW1 | Apply migration 040, restart `ncm_league`, then restart it a second time. Inspect the schema/version log. | Migration 040 applies once and replays cleanly. `trade_envelope`, both leg tables, `economy_balance_lock` and all three `trade_id` columns/indexes exist. Both starts log `player Exchange ready`; neither resource errors. | **NOT RUN** |
| §BW2 | With both Drivers online and idle, open F6 on A and choose **EXCHANGE**. Invite B from the roster; B opens F6 > EXCHANGE. | A sees a waiting invitation. B sees A by Driver identity with ACCEPT/DECLINE. The tab is part of the shared F6 shell—not a chat-only route or another WebUI page—and neither client loses input before the panel visibly draws. | **NOT RUN** |
| §BW3 | B declines. Repeat the invitation and accept. | Decline releases both Drivers. Accept opens one shared revision with two clearly separated offer columns, each balance and both confirmation states. `/ncm.exchange`, `/ncm.trade.accept` and `/ncm.trade.cancel` reach the same system as recovery routes. | **NOT RUN** |
| §BW4 | On A, select one stored Machine that has at least two fitted serialized Parts. On B, inspect A's side before confirming. | The exact Machine asset id/ordinal is visible and its exact fitted component ids/codes are listed underneath. They are not separate checkboxes: the card states they move with the Machine. | **NOT RUN** |
| §BW5 | On B, select one exact stored Part and enter a cash amount. On A, inspect the final offer. | Machine + installed Parts on one side and stored Part + cash on the other coexist in one offer. Cash may exist on one side only; money-only, gifts, cash on both sides, duplicates, negative/fractional amounts and an empty counter-side are refused without changing the revision. | **NOT RUN** |
| §BW6 | A confirms, then B edits their cash or Part selection before confirming. | A's confirmation clears immediately, the revision advances, and settlement cannot occur until both Drivers confirm the new exact revision. No old button press carries forward. | **NOT RUN** |
| §BW7 | Confirm the current revision on A only. While it waits, externally alter one offered fact: fit/remove a selected Part, spend below the offered cash, or change Machine commitment. Then B confirms. | Settlement refuses with a specific reason or advances the revision for reconfirmation. Nothing—money, title, custody or history—moves. Both confirmations never authorize different facts. | **NOT RUN** |
| §BW8 | Remove A's Machine from the offer, call it into the world, then try to add/confirm it; store it and add it again. Next check that Machine into an event and try to confirm. | Selection reserves an otherwise stored Machine against a concurrent CALL; an already materialized Machine is refused with `store_machine_first`; a committed Machine is refused with `machine_committed`. Storing/withdrawing makes it eligible again. Nobody's live vehicle disappears or changes owner underneath them. | **NOT RUN** |
| §BW9 | Restore the intended offer and have both Drivers confirm it. Immediately retry confirm and reopen both Exchange panels. | Exactly one settlement occurs. Both panels return idle and both receive one Exchange-complete receipt reference. Retry creates no second ledger row, transfer row or ownership change. | **NOT RUN** |
| §BW10 | Verify by asset id in Machine Index, Parts Inventory and SQL. | B owns the exact Machine and every fitted Part still points to that Machine; A owns B's exact stored Part in storage. Vehicle identity/ordinals, odometer, Part exposure/wear/service and configuration history are preserved. `acquired_via='trade'`; ordinary vehicle/component transfer history and exact trade legs name from/to custody. | **NOT RUN** |
| §BW11 | Compare both balances and ledger rows to the written offer. | The payer has one `player_trade` debit and the payee one equal credit, with `trade:<id>:debit/credit`; net NCM money is zero. `trade_money_leg` and the settled envelope agree with them. | **NOT RUN** |
| §BW12 | Begin another Exchange, make a non-empty offer, then test cancel, expiry, one Driver disconnecting and `restart ncm_league` before confirmation. | Each path releases the other Driver and moves nothing. Memory-only drafts need not survive restart. A fresh invitation works afterward; no stale busy flag remains. | **NOT RUN** |
| §BW13 | Race two simultaneous spending attempts against the same nearly exhausted balance: Exchange vs a Market/Part purchase or event check-in. | The shared `economy_balance_lock` serializes the debits. At most one affordable transaction succeeds; balance never goes negative and the loser moves no asset. | **NOT RUN** |
| §BW14 | Trade B a Machine model B had not previously identified, then inspect B's Machine Index and Market knowledge/access. | Ownership reveals that acquired Machine identity to B with ownership provenance. No undiscovered Market becomes known/open and no private knowledge from A is copied. | **NOT RUN** |

Persistent/offline listings are outside §BW. They require escrow and recovery and remain later work; failure to
offer an offline Driver is expected in this synchronous system, not permission to weaken any row above.


## §BX - NCM quick menu: native radial - **DEPLOYED TO ONLINE 2026-09-28 16:41 UTC; AWAITING LIVE PASS**

Scope: `IDEA-680`, `L195`, `dist/ncm-radial-0.1.0.zip` (required mod `ncm-radial`), resource `ncm_radial`,
`ncm_world/client/quick_actions.lua`. Publish the package with `publish-carrier.py ... --id ncm-radial`, restart,
rejoin, accept the executable-content consent. Keep a controller connected.

| # | Do | Expect | Result |
|---|---|---|---|
| §BX1 | Join. Read `red4ext/plugins/ncm_radial/ncm_radial-<pid>.log`, then run `/ncm.radial`. | Log shows the natives registered, `listening on http://127.0.0.1:38560/radial.html`, `host=RadialWheelController drawn=1` and `resource connected`. `/ncm.radial` reports transport connected, the plugin version and `host=RadialWheelController`. **`host=none` fails this row.** | **NOT RUN** |
| §BX2 | On foot, hold **B**. Keep holding. | A native wheel appears centred, behind a blur, with no browser surface: Hub top, Race graph top-right, Call a race right, Map bottom, GPS left, three open slots with only a short dash. The character does not walk while it is up, and no vanilla weapon-wheel art is visible. | **NOT RUN** |
| §BX3 | Still holding, press W, then D, then S+A together, then flick the mouse left. Then release on GPS. | Each input moves the pointer and highlight to the matching slot (top, right, bottom-left, left), with the name and detail in the centre. Releasing closes the wheel and routes like `/ncm.gps`. Nothing else is triggered. | **NOT RUN** |
| §BX4 | Hold **Start** on the controller, push the right stick up, release. Repeat with the left stick toward Call a race and release. | Start opens the wheel, not a menu. Right stick up highlights Hub and releasing opens the F6 Hub exactly as F6 does. The left stick selects Call a race and releasing opens the Street Call card exactly as F5 does. | **NOT RUN** |
| §BX5 | Open the wheel, aim at Map, and press left click (keyboard) or A (pad) instead of releasing. Next time, aim at an OPEN slot and release. Next time, release without aiming. | Click/A confirms early and the vanilla map opens (the same `Open77.map.open()` the pause menu uses). An open slot and no aim both close the wheel and run nothing. | **NOT RUN** |
| §BX6 | While driving, hold B and use the arrows or mouse to choose Race graph. Then press F5/F6/F8/M and type `/ncm.gps`. | The wheel works in a vehicle and the graph toggles. Driving is not blocked (accepted by design). **Every hotkey and command still works exactly as before.** | **NOT RUN** |
| §BX7 | Open F6, then press B and Start. Close F6. Open the wheel and, while it is up, restart `ncm_radial` from the console. | Neither opens over the focused Hub. After the restart the wheel is gone within 1.5 s, the character can walk, and `/ncm.radial` shows the transport reconnected. No wheel is ever left stranded on screen. | **NOT RUN** |
| §BX8 | Pause menu, then Key bindings: rebind "NCM: quick menu (hold)" to another key, and check for "NCM: quick menu, controller (hold)". Run `/ncm.radial` and `/ncm.radial input` while moving each stick and the mouse. | The keyboard rebinding takes effect without a reconnect, and the wheel's hint shows the new key. Record whether the controller row exists; if it does not, `/ncm.radial pad padBack` changes the button. Record `last block result` and whether mouseDelta reads per frame (returns to 0) or accumulates. | **NOT RUN** |

## §BY - NCM Vision: the scanner's green render, no scanner, no slow motion - **§BY1-§BY2 PASS LIVE (owner, 2026-09-28); §BY3-§BY7 NOT RUN**

Scope: `IDEA-679`, `L196`, `dist/ncm-vision-0.1.0.zip` (required mod `ncm-vision`, redscript only). Publish with
`publish-carrier.py ... --id ncm-vision --display-name "NCM Vision"`, restart, rejoin, accept the
executable-content consent. Other clients nearby help with §BY4.

| # | Do | Expect | Result |
|---|---|---|---|
| §BY1 | Join. Confirm `r6/scripts/ncm_vision/NcmVision.reds` was projected and the game reached the world (no redscript compile error dialog). | The world loads normally. Every other script mod still works: F6 opens, the radial (if deployed) opens, OPEN//77 menus behave. **A compile error dialog fails this row and blocks the rest.** | **PASS** (owner, Online, 2026-09-28: *"green works"*) |
| §BY2 | On foot, hold **Tab** for 5 s, then release. | The world takes the vanilla scanner's green render while held and returns exactly to normal on release. No scanner HUD and no scan panel. Record which parts appear: green grade, vignette, scanlines, pixelation. | **PASS** (owner, Online, 2026-09-28: *"green works"*) |
| §BY3 | Hold Tab and sprint, jump and walk for 5 s. Watch an NPC or a moving car. | **No slow motion**: NPCs, traffic and your own movement run at normal speed. Sprint and jump work (no walk-only restriction). | **NOT RUN** |
| §BY4 | Drive at speed and hold Tab, then tap **Caps Lock** and keep driving for 20 s. Tap Caps Lock again. | Green while driving, from hold and from toggle. Handling, speed and the NCM HUD are unaffected, with no slow motion. The toggle turns off cleanly. Record which vehicles and NPCs get an outline or highlight. | **NOT RUN** |
| §BY5 | Toggle on with Caps Lock, then enter a vehicle, exit it, open and close F6, open the map, and open the pause menu. | Record whether the render survives each transition or is reset to normal by something else. Nothing leaves the world green after a toggle-off, and one Tab press and release always returns to normal. | **NOT RUN** |
| §BY6 | Toggle on, then disconnect to the menu and rejoin. Also die or respawn once while on, if convenient. | The world is never green after a rejoin or respawn until a key is pressed. | **NOT RUN** |
| §BY7 | With chat open, press Tab. With F6 focused, press Tab. | Chat and F6 keep their own Tab behaviour. Record whether the render also toggles underneath (acceptable, but note it). | **NOT RUN** |

## §BZ - NCM Scanner: native reticle and scan-gated discovery - **DEPLOYED TO ONLINE 2026-09-28 17:34 UTC (`ncm-vision` 0.2.1; 0.2.0 failed to load, `KB-182`); AWAITING LIVE PASS**

Scope: `IDEA-679`, `L197`, `dist/ncm-vision-0.2.0.zip` (required mod `ncm-vision`, now a DLL + two scripts), new
resource `ncm_scanner`, `ncm_league/server/collection.lua` (scan handlers; proximity is sighting-only),
`ncm_world/server/ambient.lua` (ambient cars registered). Deploy: publish the package with `publish-carrier.py ...
--id ncm-vision --display-name "NCM Scanner"`, add `ncm_scanner` to `resources.load`, deploy `ncm_league` and
`ncm_world`, restart, rejoin, accept the executable-content consent. Have ambient traffic on, and ideally a
second player with a car.

| # | Do | Expect | Result |
|---|---|---|---|
| §BZ1 | Join. Read `red4ext/plugins/ncm_vision/ncm_vision-<pid>.log`, then run `/ncm.scanner`. | Log: `redscript natives registered`, `listening on http://127.0.0.1:38600/vision.html`, `reds: reticle attached to gameuiCrosshairContainerController`, `resource connected`. `/ncm.scanner` says transport connected and names plugin 0.2.0. **No redscript compile error**, and F6, the radial and every other script mod still work. | **NOT RUN** |
| §BZ2 | On foot, hold **Tab** looking at the sky, then at an NPC. | Green as before, plus a centred corner-bracket reticle. It is dim and bare on the sky and on the NPC, with no text claiming anything. Release: the reticle and the green both go. | **NOT RUN** |
| §BZ3 | Hold Tab on an **NCM ambient traffic car** you have not discovered. Keep it in the reticle about 1.5 s. | Amber brackets and a `UNIDENTIFIED MACHINE` title. A bar fills with `SCANNING nn%`, then cyan: the machine's name and `ENTERS THE MACHINE INDEX`. The `MACHINE ENTERS THE INDEX` toast appears, and F10 shows it discovered. Server log: `SCAN ... kind=networked basis=server_measured first=true`. | **NOT RUN** |
| §BZ4 | Scan the same model again, and a machine you already own. | Cyan straight away: its name and `IN YOUR INDEX`. No bar and no new toast. | **NOT RUN** |
| §BZ5 | Drive slowly beside an undiscovered ambient car for 10 s **without** Tab. | **Nothing is discovered** (the dwell no longer reveals identity). Then drive beside an already-known model: no toast, and `/ncm.collection.probe` still counts it as a candidate. | **NOT RUN** |
| §BZ6 | Hold Tab on a **vanilla per-client traffic car** (not NCM's) that is a catalogue model. Then scan a second one within 20 s. | First: the scan completes and reveals it. Server log: `basis=client_attested`. Second: `SCANNER COOLING DOWN`. A vanilla car that is not in the catalogue says `NO NCM RECORD` and never fills the bar. | **NOT RUN** |
| §BZ7 | Start a scan, then look away before the bar fills. Then scan a car more than 60 m away. | Looking away resets the bar to zero. The far car reads `OUT OF RANGE` with its distance, and the bar does not move. | **NOT RUN** |
| §BZ8 | While **driving**, hold Tab (or toggle Caps Lock) and scan a car ahead. Run `/ncm.scanner` while it is in the reticle. | The reticle works from the driver's seat. Your own car is never the target. Record `/ncm.scanner`'s `entity` against `aimedEntity: engineEntity`: equal, or different but matched by distance. **Either way it must scan.** | **NOT RUN** |
| §BZ9 | With a second player: scan their car. | It resolves as `networked`. On a first discovery the log names them as source (`source=<id> holding=owned`), and they gain a Discoveries Inspired credit. | **NOT RUN** |
| §BZ10 | Stop `ncm_scanner` from the console while holding Tab. Start it again. | The reticle keeps its brackets but loses its text within 1.5 s; the green stays. After restart `/ncm.scanner` reconnects, and scanning works again without a rejoin. | **NOT RUN** |

## §CA - F6 Hub: focus survives redraws, Enter works, WHEEL/PEDALS clicks land first time (`KB-183`) - **DEPLOYED TO ONLINE 2026-09-28 18:15 UTC; AWAITING LIVE PASS**

Scope: `ncm_world/web/ncm-nav.js`, `ncm_world/web/panel.html` (WHEEL tab). Offline: `nav render` and `panel render` green, and the new assertions fail against the previous commit. Needs Rig Bridge connected with a wheel or pedals plugged in, so the tab is streaming.

| # | Do | Expect | Result |
|---|---|---|---|
| §CA1 | F6, WHEEL/PEDALS. Single-click TEST PULSE, the INVERTED/NORMAL toggle and a shell tab, once each, while the wheel is streaming. | Each responds to **one** click. The live axis percentages and FRAMES SENT keep moving while you do it. | **NOT RUN** |
| §CA2 | Keyboard only: Tab to TEST PULSE and press Enter. Tab to another shell tab (e.g. HELP) and press Enter. | The pulse fires, then the tab changes. Enter is never a no-op on a focused control. | **NOT RUN** |
| §CA3 | Tab to a binding's device dropdown. Press Enter, then Right, then Left. | Enter selects the next device and wraps at the end. Right/Left step forward and back. Focus stays on the dropdown, and the binding commits each time. | **NOT RUN** |
| §CA4 | Tab to FORCE and press Right a few times, then Tab away. | The slider moves and does not lose focus. Tab leaves it, and the value is kept (it does not snap back). | **NOT RUN** |
| §CA5 | Leave focus on a control with the ring visible for 10 s while the tab streams. | The ring stays on the same control and does not jump to the top or flicker. | **NOT RUN** |
| §CA6 | On every other F6 tab (Driver File, Race Guide, Market, Exchange, Machine Index, Messages, Help), Tab to any button and press Enter. | It activates. Record any tab where Enter still does nothing. That would be a host key-forwarding problem, not this page. | **NOT RUN** |

## §CB - Wheel FORCE reaches Rig Bridge; the ring follows you; Street Calls can be entered (`KB-184`, `KB-185`, `KB-186`) - **DEPLOYED TO ONLINE 2026-09-28 19:18 UTC; AWAITING LIVE PASS**

Scope: `ncm_world/web/{ncm-nav.js,panel.html}` (client page), `ncm_league/server/{guide,economy,calendar,impromptu}.lua` (server). Offline: `ncm-test` ALL GREEN; the new `nav render` assertions and stub scenario `entrybag` fail on the previous code. **Correction:** the 0.1.1 settings file did not mirror live FORCE/ARM values, so it was never evidence that a panel command arrived. `§CB1`/`§CB3` prove the page control itself; persistence is retested with Rig Bridge 0.1.2 at `§CC2`.

| # | Do | Expect | Result |
|---|---|---|---|
| §CB1 | F6 → WHEEL/PEDALS, arm FFB. Tab to FORCE and press Right until it reads 100%. | The number steps 5% per press and remains at 100% through incoming device-state redraws. This row makes no claim about the 0.1.1 settings file. | **NOT RUN** |
| §CB2 | Superseded by `§CC3` on Rig Bridge 0.1.2. | The old 0.1.1 dynamic-effect stream is not accepted as a rumble test. | **SUPERSEDED by `KB-187` / `§CC`.** |
| §CB3 | Drag FORCE with the mouse to about 50% and release. | The panel remains at about 50% through incoming device-state redraws. One commit, not one per pixel. | **NOT RUN** |
| §CB4 | Express interest in the next two street races in the Guide. Let the first start **without entering it**. | Within ~70 s of the first race's start, the ring, card and route move to the second race's venue by themselves, with no second interest. | **NOT RUN** |
| §CB6 | Rejoin and open the Session Landing Panel. | The newest release reads **Scanner, quick menu and fixes**, above **Player Exchange**. Capabilities list **Call a street race** and **Scan machines**, each with its limit stated. | **NOT RUN** |
| §CB5 | F5, call a Street Call, drive to its start, and enter from the venue options. | `You're in: Street Call …` with `Entry -€$0`. No `economy_required`. The race runs, and the result posts with no settlement error in the server log. | **NOT RUN** |

## §CC - Rig Bridge 0.1.2 restores streamed force feedback (`KB-187`, `IDEA-686`, `L199`) - **SUPERSEDED BY §CD** (0.1.2 could not be felt while the Carrier held the wheel, `KB-188`)

Scope: `dist/ncm-rig-bridge-0.1.2.zip`, SHA-256 `ee818938cdc0e1aa8152b69f21719f993dd6adbefbf49de2354dc2cb7c9bffc5`; native mapping and feel tests pass. This is a behavior fix, not a logging probe. Spring/damper are regression channels; CONSTANT and SINE decide the result. ARM remains session-only by design.

| # | Do | Expect | Result |
|---|---|---|---|
| §CC1 | Publish/install Rig Bridge 0.1.2, cold-launch, join, and inspect its startup line. | RED4ext and the Rig Bridge log both report **0.1.2**. The wheel is named and FFB begins **DISARMED**. | **NOT RUN** |
| §CC2 | Select gear class, set FORCE to 50%, change ENGINE/ROAD/TEXTURE, quit, and cold-launch again. | Class, FORCE and tune values survive in `ncm_rig_bridge.user.json` and return in the panel; ARM does not survive and must be pressed again. | **NOT RUN** |
| §CC3 | Arm, set FORCE to 50%, and drive from idle across ordinary asphalt, rough road and kerbs. | A continuous engine/road SINE texture is felt; it changes in magnitude with the car and does not vanish after a telemetry pause or dismount/remount. | **NOT RUN** |
| §CC4 | At road speed, steer left and right through centre, then press TEST PULSE while stationary. | CONSTANT force pulls toward centre with the correct sign and TEST PULSE gives one bounded jolt. No sustained pull remains afterward. | **NOT RUN** |
| §CC5 | Repeat §CC3-§CC4 at 100%, then disarm and wait past the watchdog. | Both streamed effects scale upward; DISARM removes all four effects and stale telemetry cannot leave force applied. | **NOT RUN** |

## §CD - One owner for wheel FFB, and a channel-by-channel feel calibration (`KB-188`-`KB-192`, `IDEA-687`-`IDEA-689`, `L201`) - **0.1.4 DEPLOYED 21:44 UTC (§CD1 LIVE PASS); 0.1.5 DEPLOYED 22:24 UTC, §CD2-§CD11 AWAITING LIVE PASS**

Scope: Carrier 0.1.29 (`c5f6d004…`) yields haptics to the Rig Bridge; Rig Bridge 0.1.4 (`b568cbc6…`) with the
rebuilt output module and FFB OUTPUT / BASE TORQUE panel rows. 0.1.5 (`96837634…`: per-slider effects, LIVE readouts, rev-following engine, COLLISION, ARM-gated TEST PULSE, `KB-193` panel fix) deployed 22:24 UTC.

**Method for §CD3-§CD10 (`IDEA-688`), on Rig Bridge 0.1.5.** FORCE 100%. The channel under test at 100%, every
other slider at 0, **STIFFNESS included** (a damper resists motion, and vibration is motion, so it mutes what you
are listening for). Press **RESET PEAKS**, do the manoeuvre, then record three things in Result: **what you felt**,
the channel's **LIVE peak %**, and **the value you settle on** after lowering it until it feels right. A felt
problem with a healthy peak is a feel problem; a peak near 0% is a data problem. One channel has no slider:
self-aligning torque (LIVE · CAR WEIGHT: zero when parked, full by about 72 km/h). COLLISION has its own slider. Test the
engine parked to keep torque out of it. Each vibration slider is its own effect; only their SUM is capped at FORCE.

| # | Do | Expect | Result |
|---|---|---|---|
| §CD1 | Rejoin after the deploy, arm, drive. | Force feedback is felt in the car and stays. The Carrier log says the Rig Bridge owns force feedback. | **PASS** (owner, 2026-09-28: *"ffb is back"*) |
| §CD2 | Open WHEEL/PEDALS. Disarmed, press TEST PULSE; arm, press it three times in a row. | FFB OUTPUT reads `OK - 7/7 effects on axis X · Logitech G29` (0.1.4 reads 4/4). Each armed press gives a clear ~0.7 s rumble with left-right kicks, every time without re-arming (monki's *"works only once"*, `IDEA-421`). On 0.1.4 the disarmed press also fires; on 0.1.5 it must not. | **NOT RUN** |
| §CD3 | **CENTRING 100.** Parked: turn the wheel a quarter turn and let go. Then drive slowly and repeat. | A spring. The pull back grows steadily with how far you turn and the wheel returns to centre when released. **Identical parked and moving**: it knows position, not speed. Smooth, no grain or notches (monki's *"sand in the gears"*). Record the value where centring feels natural. | **NOT RUN** |
| §CD4 | **STIFFNESS 100.** Parked: turn slowly, then flick fast. Let go off-centre. | Viscous, like stirring honey. A slow turn is nearly free and a fast flick is heavy. **No return to centre**: released, the wheel stays where you left it. Constant at any speed. Grain or stepping is a failure. | **NOT RUN** |
| §CD5 | **Everything at 0 except FORCE.** Parked, then accelerate to ~80 km/h and steer through a gentle bend. | Parked the wheel is limp. As speed rises, a pull toward centre builds with steering angle, full by about 72 km/h, and it is **the car's own weight**, not a spring: it depends on speed. (Set COLLISION to 0 too, or a bump adds its kick.) This is the baseline under every other row. | **NOT RUN** |
| §CD6 | **ENGINE HUM 100.** Parked: idle, then hold the throttle to rev, release. | A low, slow throb at idle (about 16 Hz, a quarter of full strength) that **rises in pitch and strength** with revs -- about 27 Hz cruising, 48 Hz at the limiter -- and falls back when you release. Felt as the motor, not heard: a steady electric-razor buzz at every rpm means you are on 0.1.4 or the rpm feed is missing (`KB-191`). Record where it stops being annoying. | **NOT RUN** |
| §CD7 | **SLIP 100.** Launch hard from a stop; brake hard enough to lock; handbrake or throw it sideways in a corner. Then cruise straight and gentle. | **Silence while the tyres grip.** A buzz appears the moment they break loose -- wheelspin, lock-up, sliding -- grows with how much they slide, and stops the moment grip returns. Any buzz in gentle straight cruising is a failure (slip noise). | **NOT RUN** |
| §CD8 | **ROAD 100.** Drive over kerbs, rough surfaces and a jump, and brake hard over a bump. | Designed: vibration with each bump, kerb and landing, following the suspension. **Expected today: nothing** -- suspension telemetry has read zero in every session (`KB-192`). Any feel here is news; record it. | **NOT RUN** |
| §CD9 | Combine: set CENTRING, STIFFNESS, ENGINE and SLIP to their recorded values. Drive a lap with a hard corner. | Each channel remains recognisable, and each LIVE row still moves on its own. If one masks another in the hands while both peaks are healthy, note which. These become the shipped defaults. | **NOT RUN** |
| §CD11 | **COLLISION 100.** RESET PEAKS, then: nudge a parked car side-on at low speed, hit one head-on at ~40 km/h, and scrape a wall and a pole. After each, read LIVE · COLLISION peak and the Rig Bridge log. | Every hit is a short, sharp **thud** (~30 Hz, gone within a quarter second), **head-on included**. A side hit adds a jerk of the rim away from the impact. A scrape is light but present. The log shows `collision: dv=… lateral=…` per hit. **Walls/poles: record whether a log line appears at all** -- none means the game does not raise the event for static geometry (`IDEA-690`). | **NOT RUN** |
| §CD10 | A direct-drive owner, if one joins: leave BASE TORQUE on Auto, press TEST PULSE, then repeat §CD3 at FORCE 50%. | FFB OUTPUT names the base or "assumed". Force is gentle but clearly present, never violent, and full FORCE is about 3 Nm (`IDEA-687`). | **NOT RUN** |

## §CE - A ring for every race, the card for the ring you stand in, one entry at a time (`KB-195`-`KB-199`, `IDEA-694`, `L202`) - **BUILT, NOT DEPLOYED; AWAITING LIVE PASS**

Scope: `ncm_league` (guide, calendar, organized, scenario, impromptu, street pack) and `ncm_world` (client calendar,
venue.html) with vendored core. Easiest setup: two races inside twenty minutes at different venues. Use
`ncm.race.now <route>` twice, or wait for the cadence to overlap.

| # | Do | Expect | Result |
|---|---|---|---|
| §CE1 | With two races inside 20 min, drive toward each venue from a few hundred metres away. | Each venue has its own ring, visible from the road well before you arrive (drawn to 500 m). Note the distance at which you first noticed it. | **NOT RUN** |
| §CE2 | Bookmark the SOONER race (A) in the Guide. Drive to the LATER race's (B) ring and stand in it. | The card names B. ENTER RACE is offered. Pressing LEAVE LIST there does nothing to A's bookmark (the Guide still shows you on A's list). | **NOT RUN** |
| §CE3 | At B during its entry window, stop about 2 m outside the drawn ring and try ENTER RACE (the card hides, so use `/ncm.enter`). Then roll inside and enter. | Outside is refused: "You need to be at the start". Inside is accepted. The persistent card turns green and names B. | **NOT RUN** |
| §CE4 | Entered in B, drive to A's ring. Press the first option, then press again within 15 s. | First press: the option reads SWITCH ENTRY, and a toast says you are entered in B and to hold again. The option then reads "Withdraw from B and enter". Second press: you are in A, withdrawn from B, and the card and GPS follow A. | **NOT RUN** |
| §CE5 | With an NCX seat accepted, stand in that event's ring. Press WITHDRAW. | WITHDRAW is enabled, not greyed "You are not entered". Afterwards you are off the grid and the team's seat is free (server log `SEAT RELEASED`). | **NOT RUN** |
| §CE6 | A second player calls a Street Call (F5) near a cadence race venue. | You see a ring at the Street Call's start, and the cadence race keeps its own ring. You can enter the Street Call at its ring. | **NOT RUN** |

## §CF - Persistent fuel, physical refuelling and no-fuel recovery (`IDEA-702`, `L204`) - **BUILT, NOT DEPLOYED; AWAITING LIVE PASS**

Scope: schema 042, `ncm_world` fuel service/client/HUD/station blips, and vendored `economy.fuel`. Deploy the
migration before starting `ncm_world`. Use one owned, issued NCM Machine and note its asset id and balance.

| # | Do | Expect | Result |
|---|---|---|---|
| §CF1 | Join, call the Machine and drive briefly. Open the race/odometer HUD. | FUEL appears beside the odometer, initially 100% for an existing Machine. `machine_fuel` has exactly one row for its asset id. | **NOT RUN** |
| §CF2 | Drive about 1 km normally, then stop long enough for persistence. | Fuel falls by about 0.35 L (roughly 0.6 percentage points of 60 L). Odometer and fuel advance together; no client-reported distance is trusted. | **NOT RUN** |
| §CF3 | Disconnect/rejoin, then restart the resource/server and call the same Machine. | The prior fuel percentage returns both times; it is not reset by session, dismount or resource restart. | **NOT RUN** |
| §CF4 | At a marked station, record balance, sit in the Machine and run `/ncm.refuel` twice. | First call fills the tank and charges exactly missing litres × €$2 with one `fuel_purchase` ledger row. Second call says the tank is full and charges nothing. | **NOT RUN** |
| §CF5 | On a test profile, set/drive fuel to zero. | Fuel reaches 0%, turns red, the engine stops, and both toast and chat say `Stuck? Type /ncm.nofuel for help.` Driving cannot create negative fuel. | **NOT RUN** |
| §CF6 | While empty and away from a station, run `/ncm.nofuel`. | GPS routes to the nearest authored station. With no verified jerry-can capability, the Driver is dismounted and the Machine is stored/towed there; F6 can call the same owned Machine, then `/ncm.refuel` restores it. | **NOT RUN** |
| §CF7 | Open the full map and confirm 53 fuel POIs. Sample every district and physically visit a representative spread; then run an authored sweep over all sites. | Every POI is visible without discovery and sits on a real usable pump/forecourt. The client log reports `53/53` and whether each used SVG or native fallback. Refuelling works at all 81 precise pump points. Record or remove every miss; do not accept the registry from source data alone. | **NOT RUN** |
| §CF8 | (Deployed 2026-09-29 03:08 UTC.) Anywhere, with any fuel level, run `/ncm.fuel` (`IDEA-708`, `KB-203`). | Chat and a toast name the nearest station and its distance; GPS routes there; the Machine is **not** stored and the Driver is **not** moved. Parking at the pumps and `/ncm.refuel` then works as §CF4. | **NOT RUN** |
| §CF9 | On foot in the open, run `/ncm.blips`, open the full map, then check the minimap. Run it again to clear (`KB-203`). | The client log prints `owned blips: N (M active)` with sprite counts. Record which of the four probe pins (west to east `objective`, `quest`, `vendor`, `fast_travel`) appear on the map and on the minimap. That answer picks the sprite for landmarks (§AD7) and fuel (§CF7), or is the platform report if none appear. | **PASS 2026-09-29 03:11 UTC** (owner: all four dropped visibly beside them; log `owned blips: 88 (88 active)`). Led to the `KB-203` world-gate fix. |
| §MK1 | Walk to a physical Autofixer terminal (e.g. Little China, Northside, Japantown). Within ~4 m a toast should read `Press E (pad X) to connect to <market>`; press E (`KB-205`, `IDEA-695`). | `MARKET DISCOVERED ... is now available in F6`. F6 Market's sources column lists Base Market first, then this terminal; selecting it shows only its own Machines and Components (never merged), the title names it, and buying works from anywhere afterwards. A terminal with no toast is a coordinate miss: note where the real terminal stands. | **NOT RUN** |
| §AR1 | Log out somewhere far from the Badlands (e.g. Watson), wait a minute, rejoin (`KB-207`). | The loading screen goes to black and then straight to where you left. No view of the Badlands, no second loading screen. Client log: `[ncm_world/client/arrival] arrival at ...: settled` then `screen returned`; server log `restored ... under cover (settled)`. A black screen longer than ~15 s, or `server restore fallback` in the server log, is a fail -- record it. | **NOT RUN** |
| §LP1 | Join and read the Session Landing panel (`L207`). | A narrow centred panel: What's new (09-29: fuel, Autofixer markets, arrival) then the changelog, then CONTINUE. No progression-reset notice and no capability list. Esc/CONTINUE closes it; it reappears on the next join. | **NOT RUN** |
| §HB1 | Drive until the tyre gauge sits in the window, then push hard until it reads hot/OVERHEATING (`L208`, `IDEA-716`). `/ncm.tyre` shows the numbers. | Cold: the car pushes. In the window: neutral. Overheated: the rear steps out and braking is noticeably longer. Server log `handling` lines show grip above 1.0 and brake below 1.0 when hot. | **NOT RUN** |
| §HB2 | Server console `ncm.machine weather rain`; watch the log for `road wetness` climbing over ~2 min; drive through it. Then `ncm.machine weather sunny` and keep driving (`IDEA-715`). | The car pushes more and stops longer as the road soaks (grip toward 0.80, brake 0.82, drive 0.90), and recovers over ~6 min after the rain stops. | **NOT RUN** |
| §HB3 | On a fully wet road, turn in gently, then floor it mid-corner (`IDEA-715`). | Entry pushes; heavy throttle steps the rear out. Lifting off brings the push back within a fraction of a second. | **NOT RUN** |
| §HB4 | Compare a full tank with a near-empty one on the same corner and straight (`/ncm.refuel` to fill) (`IDEA-717`). | Full: slower out of corners, longer braking, a slight push; the tyres heat faster. Near-empty: livelier. | **NOT RUN** |
| §HB5 | Server console `ncm.machine weather sandstorm`, then `fog` (`IDEA-715`). | Sandstorm: a small push and a slightly lower top speed. Fog: no handling change. | **NOT RUN** |
| §HB6 | Cycle `ncm.machine weather <id>` through sunny, heavyclouds, fog, pollution and sandstorm at the same time of day, running `/ncm.tyre` after each; repeat once at night (`L209`, `IDEA-718`). | The `track` line differs per weather: sunny hottest by day and coldest by night, heavy cloud mild both ways, fog cool and slightly damp (road wetness ~0.15), sandstorm hot. The tyres warm fastest on a sunny afternoon; a clear night pushes. | **NOT RUN** |

## §CG - DEVICES and the GAMEPAD layer: rim, Joy-Cons, variants, rumble presets (`IDEA-705`, `L205`, `KB-201`) - **DEPLOYED TO ONLINE 2026-09-29 02:29 UTC; AWAITING LIVE PASS**

Scope: Rig Bridge 0.1.7 since 2026-09-29 15:18 UTC (`dist/ncm-rig-bridge-0.1.7.zip`, `eea1aba6…`; 0.1.6 was `3dc80f1b…`), Carrier 0.1.30 (`d4431422…`), panel
DEVICES. Joy-Cons paired to Windows before launch. JoyMoCo closed (it would hold the Joy-Cons itself).

| # | Do | Expect | Result |
|---|---|---|---|
| §CG1 | Cold-launch, join, read `ncm_rig_bridge-<pid>.log` and the Carrier log. | Rig Bridge: `XInput hook: ... attached` for at least one module, `SDL3 motion input started`, `SDL3 joystick joystick:Evenracing 1.0.0` (**the `KB-201` question**), `gamepad profile 'default' loaded: 16 variant(s)`, `gamepad API listening`. Carrier: `NCM Rig Bridge is installed and owns rig devices`. **0.1.7 (`KB-209`): NO `SDL3 joystick` line for the G29 or the pedals.** Then ARM FFB and feel it; no replug. | **0.1.6 FAIL 2026-09-29 11:01:** SDL3 opened the G29 and pedals, and ARM killed FFB until a replug (`KB-209`). No Evenracing line (rim not seen or not connected). 0.1.7 NOT RUN. |
| §CG2 | F6 > DEVICES. Collapse and expand each section; close and reopen F6. | Three sections, WHEELBASE & PEDALS, FORCE FEEDBACK, GAMEPAD; collapsed state survives. GAMEPAD shows a status line, not `GAMEPAD LAYER UNREACHABLE`. If it is unreachable, record that line verbatim. | **0.1.6 FAIL 2026-09-29:** `GAMEPAD LAYER UNREACHABLE`; a bundled page cannot fetch (`§AJ1`, `KB-210`). Relay via the bridge surface in 0.1.7; NOT RUN. |
| §CG3 | On foot, press each of the 16 rim buttons in turn. | Each lights its output's dot and does what that Xbox button does in game (map, inventory, D-pad, etc). None doubles or sticks. | **NOT RUN** |
| §CG4 | Set one rim variant to *While driving*. Press it on foot, then in a car. | Silent on foot, works in the car; leaving the car while holding it releases it. | **NOT RUN** |
| §CG5 | RECORD B, *Button press*, press a rim button nobody uses. | Banner reads `Added '<name>'`; B now has two variants and both press B. | **NOT RUN** |
| §CG6 | RECORD B, *Button press*, press Joy-Con Y. Give it rumble `strong-thump`, side Right. | B has a third variant; pressing Joy-Con Y presses B and thumps the right Joy-Con. TEST plays the preset. | **NOT RUN** |
| §CG7 | RECORD X, *Press + motion*: after the countdown hold SR and swing the right Joy-Con. Repeat the swing three more times as new variants. | Each take is added (or rejected with a reason). In game, SR + that swing taps X; SR without the swing does not; a swing without SR does not. | **NOT RUN** |
| §CG8 | Drive into something with RUMBLE on and GAME RUMBLE on. | The game's own rumble reaches the Joy-Cons (large motor left, small right). | **NOT RUN** |
| §CG9 | GYRO STEERING: enable, right Joy-Con, *While driving*. In a car, hold CAPTURE (toggle button) half a second, tilt. | The car steers with the tilt, merged with the wheel (the larger wins); toggling off hands steering back; on foot it does nothing. | **NOT RUN** |
| §CG10 | On foot, move each Joy-Con's stick; change its rotation if it reads sideways. | Left Joy-Con moves the character, right the camera. If a stick is silent, record which. `stick: auto` is the guess under test. | **NOT RUN** |
| §CG11 | SAVE AS `onfoot-test`; NEW EMPTY `blank`; load `default`; load `onfoot-test`. | Files appear in `profiles/`; each load restores exactly what was saved; `active.txt` names the last loaded. | **NOT RUN** |
| §CG12 | Use the Xbox pad normally with the default profile loaded. | Every pad input works once, not twice. | **NOT RUN** |
| §CG13 | CALIBRATE with both Joy-Cons resting flat. | Banner counts down, then `Calibrated 2 controller(s)`; gyro readouts sit near 0 at rest afterwards. | **NOT RUN** |
| §CG14 | Regression: FORCE FEEDBACK section, TEST PULSE armed, drive. | FFB exactly as `§CD`: 7/7 effects, LIVE rows move. | **NOT RUN** |

## §CH - The Paddock, phases 1-2: the season runs; Billie and the manager (`L224`-`L226`, [44_THE_PADDOCK.md](../44_THE_PADDOCK.md)) - **BUILT, OFFLINE-GREEN; DEV SERVER ONLY (`L223`); AWAITING LIVE PASS**

Scope: `ncm_paddock` phase 1 on the Windows development server with two humans (owner and `ncmtester2`). Cases are written ahead of the build so "done" is defined first; later phases add rows.

| # | Do | Expect | Result |
|---|---|---|---|
| §CH1 | Boot dev with `paddockEnabled` on and an empty Paddock. Run `ncm.paddock.status`. | Genesis logs 24/16/12/8 orgs, about 150 drivers and 40 free agents, no denylisted name, and every `ncm_league` subsystem still boots. | **NOT RUN** |
| §CH2 | Read `ncm.paddock.status` at an Eastern night hour, then at a day hour. | At night only Street series have races scheduled or running; by day, Regional and Pro; the Premier feature sits at 15:00 ET. | **NOT RUN** |
| §CH3 | Watch one race window close. | The result appears in RESULTS only after the window closes, with provenance `simulated`; nothing leaked before. | **NOT RUN** |
| §CH4 | Open F6 > PADDOCK > WIRE, STANDINGS, RESULTS and DIRECTORY. | Every view renders; no hidden number appears anywhere; tags appear only with their evidence. | **NOT RUN** |
| §CH5 | Race a human sanctioned event, then inspect its `session_result` row. | Migration 043's condition columns are stamped from the real weather, wetness and time of day. | **NOT RUN** |
| §CH6 | Restart `ncm_paddock` mid-race-window. | No duplicate race and no lost result; the replayed race produces the identical order (event-keyed seed). | **NOT RUN** |
| §CH7 | Leave the server running overnight. | About 45 races in 24 h; Messages received no more Paddock pushes than the budget; quota errors 0. | **NOT RUN** |
| §CH8 | Talk to Rico until he offers a book (4 contested races, or ask him about money); pick *Put me in touch*. | Billie's opening arrives in Messages in her voice; `player_contact` has a `billie` row, state `known`. | **NOT RUN** |
| §CH9 | F6 > PADDOCK > BILLIE'S BOARD within 15 min of a race. | Win, podium and head-to-head lines with prices; no Cancel button anywhere; a driver of a human-managed team shows her refusal and no price. | **NOT RUN** |
| §CH10 | Write paper on one line (hold to confirm); write it again from a second click of the same slip. | One slip, one `billie_stake` ledger row; the second is a no-op. Over the per-slip cap is refused with her line. | **NOT RUN** |
| §CH11 | Wait for that race to close. | The slip settles once: a win pays stake x price (`billie_payout`), a loss pays nothing; one solicited message says which. | **NOT RUN** |
| §CH12 | MY ORG > found a team as the owner. | Fee leaves the wallet; a Street team with two rookies appears in DIRECTORY marked human-run; `team_affiliation` has one active `npc`/`manager` row. | **NOT RUN** |
| §CH13 | Try to found a second team. | Refused: one team at a time (the unique index, not just the UI). | **NOT RUN** |
| §CH14 | Offer a free agent a contract; release a driver; invest in a car area; withdraw 1,500 then 1,000. | Roster moves show under *Waiting for the Cup boundary*; development spends at once; the first withdrawal pays 1,050 after tax, the second is refused by the weekly cap. | **NOT RUN** |
| §CH15 | `ncmtester2`: race a sanctioned event twice for podiums. | Spotlight rises; past 10 a WIRE mention names them; past 25 an NPC star calls them out (one message, an open arc); the next sanctioned result resolves it. | **NOT RUN** |
| §CH16 | Cross a Cup boundary (or wait a week). | Cup standings archive and a Cup title story; queued manager moves apply; NPC owners make visible signings or firings; no quota error in the log. | **NOT RUN** |

## §CI - The life sim M1: places, district climate, people's days, bodies at any place, the hidden trajectory (`L240`, `IDEA-764`-`IDEA-766`, `IDEA-772`, `IDEA-773`) - **§CI1, §CI3, §CI4, §CI11 PASS LIVE (owner, dev, 2026-09-30); the rest NOT RUN; DEV SERVER ONLY (`L223`)**

| # | Do | Expect | Result |
|---|---|---|---|
| §CI1 | Boot the dev server after schema 053. | `migration 053 paddock_life applied`; `life sim up: N places` (N about 300); eight `[ncm_paddock/days]` district readings; every other subsystem as before. | **PASS** (dev, 2026-09-30 14:26 ET, server log: 303 places, city climate *a scene revival*) |
| §CI2 | Console `ncm.life`, then `ncm.life.district Heywood`. | Eight readings, each "regime, condition"; one district's six axes with base and scar, its last causes and its transitions. | **NOT RUN** |
| §CI3 | In the evening, stand at a food stall or street meet in a district where a team has its garage. | Within ~15 s up to four named Paddock people stand there with a Talk prompt; `ncm.life.near <pid>` lists them with their activity (eat, loiter, hang...). | **PASS** (dev, 2026-09-30 15:11-15:38 ET: Eleanor Howard at Fuel Station 19 on a fuel stop, as the offline plan predicted; Jia Guo at Fuel Station 23; four at a Glen food stall. Arrival took up to ~3 min at 8 plans a pass, now 40. Took KB-234 and KB-235 to get here.) |
| §CI4 | Talk to one of them. | A line and "Name · Role, Team"; `ncm.life.player <pid>` shows evidence and the social axis rose; nothing about the trajectory reaches the client. | **PASS** (dev, 15:38 ET: six meetings with Jia Guo recorded in `paddock_meeting`, the first ever; Talk prompts anchored by position after KB-235.) |
| §CI5 | `ncm.life.who <personId>` for that person. | A believable day: sleep in their own night, three meals or fewer, their garage shift at the garage, the current block marked `<- now`. | **NOT RUN** |
| §CI6 | Walk 200 m away, then come back after their block has ended. | The bodies go when you leave; on return the person is wherever their day now says (or gone). | **NOT RUN** |
| §CI7 | At a place whose pin is on a roof or inside a wall: `ncm.life.place <pid> bad`. | Recorded; nobody's new day goes there; bodies stop appearing there. | **NOT RUN** |
| §CI8 | Leave the server up across an Eastern midnight while Paddock races resolve. | One `climate stepped to day N` line per day; `ncm.life.district <race district>` lists `street_race`/`sanctioned_race` among last causes; any regime change is logged with its causes. | **NOT RUN** |
| §CI9 | Between 20:00 and 05:00 Eastern, stand at a street meet. | One `meet_visit` per player per meet per night in `ncm.life.player`. | **NOT RUN** |
| §CI10 | An hour of moving through two districts with Paddock people about. | No quota or `tick FAILED` line from `ncm_paddock/days`; bodies never exceed the cap. | **NOT RUN** |
| §CI11 | Press Tab and hold the reticle on a Paddock person (owner, 2026-09-30: "this should be a scanner / vision surface 100%"). | The reticle locks with their name and role; SCAN DATA shows TEAM, DOING, AT (the map's own station name for fuel), UNTIL, USUALLY, DISTRICT with its climate reading; vanilla pedestrians show nothing; no hidden stat on the wire. | **PASS** (dev, 15:24 ET: `player 1 scanned p00221 (Eleanor Howard, FUEL STOP) at fuel_station_19`; owner: "scanner worked, confirmed".) |

## §CJ - Start opens the F6 hub on a controller (`IDEA-785`) - **BUILT, DEV SERVER ONLY (`L223`); AWAITING LIVE PASS**

| Case | Steps | Pass condition | Result |
|---|---|---|---|
| §CJ1 | On foot with a pad, press Start; press Start again. | The hub opens on the first press and closes on the second; the pad drives normally afterwards (no `KB-182`-style keyboard/mouse takeover). | **NOT RUN** |
| §CJ2 | Seated in a car, and during a Paddock/street race, press Start twice. | Same open/close; nothing else in the game reacts to Start. | **NOT RUN** |
| §CJ3 | Open chat, press Start. | The hub does not open while chat holds input. | **NOT RUN** |
| §CJ4 | Open the hub with F6, move tabs with the pad, close with Start; hold Start for two seconds. | Start closes whatever panel is open; holding does not toggle repeatedly. | **NOT RUN** |

## §CK - Paddock live races without ghosts: host at the grid, mapped report, Pace 0.5.2 (`L243`, `KB-241`-`KB-244`) - **BUILT, DEV SERVER ONLY (`L223`); AWAITING LIVE PASS**

| Case | Steps | Pass condition | Result |
|---|---|---|---|
| §CK1 | Stand at a street grid with Pace when a race stages; watch the lights. | Client log `drive.start ...: 12/12 cars mapped`, no `script execution budget exceeded`; Pace log `accepted drive.start` and `road speed plan ready`; the field moves at green. | **NOT RUN** |
| §CK2 | Be near a route's far end (within 600 m of its line) but more than 250 m from its grid when it stages. | No street run is staged for you; LIVE shows the race moving on the sim model; the result is the sim's. | **NOT RUN** |
| §CK3 | Stand at a grid, then drive well away before the lights. | Server log `N of 12 cars reached the host's game`; under half: the street run is cancelled at once and LIVE switches to the sim; otherwise unseen cars leave the grid. | **NOT RUN** |
| §CK4 | Follow a 2-point street race from the back. | Back-row cars are on the road plan from the start (no `OFF the road plan` at index 0); `past point` lines say `passed on the road` at the finish, not ~130 m early; no ceiling above 44 m/s in the Pace log. | **NOT RUN** |

## §CL - Paddock racers on the engine's race profile (NCM Pace 0.6.0, `L244`, `L245`, `IDEA-788`) - **BUILT, DEV SERVER ONLY (`L223`); AWAITING LIVE PASS**

| Case | Steps | Pass condition | Result |
|---|---|---|---|
| §CL1 | Start the game with Pace 0.6.0. | `red4ext/plugins/TweakXL` log shows `racers.yaml` loaded with no errors; the Pace log has `tdb:` lines and `N of 355 driving flats read`. | **NOT RUN** |
| §CL2 | Stand at a street grid when a race stages. | Server log TRACE `record=Vehicle.ncm_racer_...` for every car; no `refused`; the cars look like their vanilla models. | **NOT RUN** |
| §CL3 | Watch the start and the first kilometre. | Cars pull away on the acceleration curve (no instant 18 m/s); no 10-11 m/s crawl on open road; no donuts after contact. Record pace and how they handle traffic against 21:12/21:18. | **NOT RUN** |

## §CM - Street races on the engine's racer and baked race splines (NCM Pace 0.7.0, `L246`) - **BUILT, DEV SERVER ONLY (`L223`); AWAITING LIVE PASS**

| Case | Steps | Pass condition | Result |
|---|---|---|---|
| §CM1 | Start the game with Pace 0.7.0. | ArchiveXL log lists `ncm_pace_race_splines` and its streaming block with no error; the game loads normally. | **PASS** (owner, dev, 2026-10-01 00:40-00:54: ArchiveXL merged the race-spline block; game loads) |
| §CM2 | Stand at a street grid with Pace when a race stages; watch the lights. | Pace log: `race cmd 1: go, leg 1/N ... spline $/mod/ncm_pace/#leg_...` for every car and `reds: car N: racing leg 0`; NO `command ended FAILURE`; the field moves at green. | **PASS** (owner, dev, 2026-10-01: "they started!" -- Pace 0.8.0, after the NodeRef hash fix, `KB-249`) |
| §CM3 | Follow the race through a checkpoint to the finish. | `race cmd ...: next leg` at each checkpoint; cars follow the road, race each other without rubber banding, and cross the finish (finish gates reported); verdict `physical` with every finisher classified. | **NOT RUN** |
| §CM4 | Owner judgement. | Pace, launch, aggression and racecraft vs 21:12/21:18. | **PARTIAL** (owner: "racing well too"; three CTDs that session are `KB-238`, which also happens with no race) |

## §CN - Street races on the bubble with drivers; nothing driven at the streaming edge (NCM Pace 0.8.1, `L247`, `KB-238`) - **BUILT, DEV SERVER ONLY (`L223`); AWAITING LIVE PASS**

| Case | Steps | Pass condition | Result |
|---|---|---|---|
| §CN1 | Join dev with Pace 0.8.1 in the game folder (hand-installed on dev, `KB-250`). | Pace log header `ncm_pace 0.8.1`; ArchiveXL merges `ncm_pace_race_splines`; game loads. | **NOT RUN** |
| §CN2 | Stand at a street race's start with Pace 30-60 s before the lights. | Server: `pre-grid <id> to slot N`, no `staged ... backend=pace` (no grid run). Every car has a driver; Pace log `drive.start` dynamic with legs, then at green `race cmd 1: go, leg 1/N` per car. | **NOT RUN** |
| §CN3 | Follow at the back; let the front-runners get away. | Past 300 m a car vanishes: server `handed back ... nobody within 300 m` or `its Pace player 1 is ... m away`; Pace `car.remove`. No CTD. | **NOT RUN** |
| §CN4 | Drive ahead down the route and meet the field mid-race. | Cars come in on the road (server `coming in ... from a player`), each with a driver; Pace `car.add ... from point k` and `race cmd: go, leg k/N` on the right leg; they race on. No CTD. | **NOT RUN** |
| §CN5 | Opportunistic: a car streams out and back while near. | Client log `bubble car X re-created here: entity A -> B`; Pace `car.entity` ack and `back: fresh command`; the car keeps racing. No CTD. | **NOT RUN** |
| §CN6 | Let the race close. | `paddock_race.provenance` `mixed` (or `physical`); every car classified; LIVE showed the model throughout. | **NOT RUN** |
| §CN7 | Free roam with `ncm_world` traffic for 30 minutes, no race. | No `KB-238` CTD; ambient cars vanish only beyond ~300 m. | **NOT RUN** |
| §CN9 | Watch a bubble car come in (pre-grid or mid-route) with the client log open. | `bubble car N settled here (3000+ ms); asking for its driver`, then server `driver seated ... ms after it was set down`, then `pace car.add`; the driver appears ~3 s after the car. No CTD through a full race session with hand-offs and returns. | **NOT RUN** |
| §CN8 | Owner judgement over a race session. | No CTD across several races followed at the back and met mid-route. | **NOT RUN** |

## §CQ - League driver pools and attendance (`L249` step 1) - **BUILT, DEV SERVER ONLY (`L223`); AWAITING LIVE CHECK**

| Case | Steps | Pass condition | Result |
|---|---|---|---|
| §CQ1 | Open the PADDOCK tab standings for a street league. | ~56 drivers listed over the season; independents shown as "Independent". | **NOT RUN** |
| §CQ2 | Watch three consecutive races of one street league (LIVE or results). | Different line-ups each race; never the same 12 every time; the field is still full or close to it. | **NOT RUN** |
| §CQ3 | A sanctioned race's results. | Each team fields at most its race seats; teams with nobody available are missing, not padded. | **NOT RUN** |
| §CQ4 | Open the PADDOCK tab. | League names are the approved ones (Kabuki Midnight, Hypercar Championship, ...). | **NOT RUN** |
| §CQ5 | Press F5 (Street Call), set Type to Time trial, start it. | Nobody else is told or sees it in their Race Guide; the caller is entered and runs alone against the clock; no payout. | **NOT RUN** |
| §CQ6 | Look at the Paddock schedule at 07:00 and at 23:00 ET. | A race within 15 minutes at any hour (regional by day, street from 18:00). | **NOT RUN** |

## §CR / §CS - NPCs in the markets; the posted Exchange (`L249` steps 4-5) - **BUILT, DEV SERVER ONLY (`L223`); AWAITING LIVE USE**

| Case | Steps | Pass condition | Result |
|---|---|---|---|
| §CR1 | Leave the server running an evening; open the MARKET. | Some parts/cars that were on the shelf are gone to NPCs (never anything listed under 20 minutes); stock refills on its cadence. | **NOT RUN** |
| §CR2 | Check a team that developed its car. | Its development came with a real part it owns (`npc_money` and the transfer rows agree). | **NOT RUN** |
| §CS1 | F6 -> EXCHANGE -> THE BOARD. | NPC posts (teams and racers: FOR SALE and WANTED) are listed with their prices and time left. | **NOT RUN** |
| §CS2 | Post one of your stored parts for sale. | It appears on the board; an NPC who values it bids within a few minutes; HOLD TO ACCEPT moves the part to them and the eddies to you. | **NOT RUN** |
| §CS3 | Bid on an NPC's FOR SALE post. | The NPC accepts if it clears their floor; the part lands in your Parts storage and your balance drops by the bid. | **NOT RUN** |
| §CS4 | Post a WANTED you can't afford to pay for later, then let an NPC fill it with no money in your account. | The trade does not settle; nothing moves; the post stays up. | **NOT RUN** |


## §CO - Ovals on closed race splines (NCM Pace 0.8.2, `IDEA-790`) - **BUILT LOCALLY; AWAITING LIVE PASS**

Street spline movement in §CM2 did not exercise an oval. Ovals remain in the normal calendar at the tier's authored share; physical live validation remains pending. Dev boot restores deterministic oval slots from the earlier oval-off schedule and excludes only checkpointed non-oval courses.

| Case | Steps | Pass condition | Result |
|---|---|---|---|
| §CO1 | Install Pace 0.8.3 and the matching Paddock resource on dev; wait for a Westbrook Short Ring slot from the normal calendar; stand near the ring before its lights. | Pace header says `0.8.3`; ArchiveXL loads the archive with three closed oval nodes; the pre-grid sits on the roundabout road with seated drivers. Plan part 1 names `$/mod/ncm_pace/#leg_oval_westbrook_short_ring__loop`. | **NOT RUN** |
| §CO2 | Watch one car from green through at least two start-line crossings. | `race cmd 1: go` uses the oval spline; no command `FAILURE`, no island crossing, no repeated command at each mark or lap seam. Physical position and LIVE's LAP count advance together. | **NOT RUN** |
| §CO3 | Follow the field through a full Westbrook race and let cars leave and re-enter the bubble. | Drivers stay seated while physical; a car is handed to the model before its Pace player passes 300 m, then returns near a Pace player on the same lap. No `KB-238` CTD. | **NOT RUN** |
| §CO4 | Let the race close. | Every entrant classified once, provenance reflects the physical/model stretches, and the winner's lap count and finish agree with the model. | **NOT RUN** |
| §CO5 | Repeat §CO2 at Corpo Circle and NCX Octagon. | Both follow their closed spline in the intended direction for two line crossings. NCX's authored ring is inspected for road and wall clearance. | **NOT RUN** |

## §CR - KB-238 native null guard, Pace 0.8.3 - BUILT/INSTALLED DEV; LIVE PASS OWED

Keep the current seat delay and bubble radii for this comparison. The guard fixes the observed dereference; successful racing and a logged interception are separate evidence. A clean race with no interception does not prove this path was exercised. KB-252 (64 lifetime slots) and KB-253 (command cleanup) were not changed.

| Case | Steps | Pass condition | Result |
|---|---|---|---|
| §CR1 | Fresh game launch on dev. | Pace header 0.8.3 and `KB-238 guard ACTIVE`; no inactive/mismatch message. | **NOT RUN** |
| §CR2 | Follow a street race, let racers hand back to the model, then meet them again mid-route. | Drivers remain seated; recreated cars keep racing. No CTD. Record whether `KB-238 guard prevented` appears and the total. | **NOT RUN** |
| §CR3 | Repeat full races including the Kabuki Bridge to Deep Dive leg if scheduled. | Several races complete through repeated returns, no CTD and no new stuck/mount behavior. At least one logged interception is required to demonstrate the faulty path was actually exercised. | **NOT RUN** |
| §CR4 | Free roam with NCM ambient traffic after the races. | Seated ambient drivers continue working; no KB-238 CTD or movement regression. | **NOT RUN** |

Offline 2026-10-01: Release build, existing Pace state tests, five guard checks, native declaration check, installed-bundle redscript compile, executable signatures, and installed DLL hash match all pass. Package SHA256 7bb16746dbc46eafa68c39c665af48e5f9a17796cebf73d05031f1ebe9141bfe. Rollback: LocalAppData/NCM/dev-mods/20261001-160535.

## §CT - Lane-based start grids, qualifying and mixed grids (`L250`) - **STEPS 1-4 BUILT, DEV SERVER ONLY (`L223`); AWAITING LIVE CHECK**

| Case | Steps | Pass condition | Result |
|---|---|---|---|
| §CT1 | Watch the pre-grid of a street race from Hill Abode, and of two other starts. | All NPC cars sit on the road behind the line in lanes, none behind a gate or barrier, none touching; everyone gets a clear launch. | **NOT RUN** |
| §CT2 | F2 Paddock -> LIVE for a race on track; after it, its box score. | Each driver shows a QUALI time (m:ss.ss); the grid order follows the times; box score shows GRID and QUALI. | **NOT RUN** |
| §CT3 | F1 Race Guide -> a Paddock race 1-3 h out -> QUALIFY. Drive to the start, stop on the line (STAGED), go; finish. Then a flying crossing of the line. | The GPS routes to the start; the strip says how to stage; the run counts and a toast says QUALIFYING + ENTERED (fee charged once); the Guide card shows your best and WITHDRAW. A flying crossing starts no run ("STANDING START"). | **NOT RUN** |
| §CT4 | Be at the venue before T-1 of that race. Watch the grid form; let T-20 pass off your slot once. | A beam on your slot, GPS and arrow; NPCs on the other slots, none on yours; at T-20 race control puts you on your slot in your car; one green with the NPCs; after the finish, RESULT P_n of the whole field and pay to match; LIVE and the standings list you. | **NOT RUN** |
