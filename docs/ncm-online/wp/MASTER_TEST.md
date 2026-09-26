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

Carrier **0.1.20** + `ncm_world` on Production. Command: `/ncm.setup`.

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
