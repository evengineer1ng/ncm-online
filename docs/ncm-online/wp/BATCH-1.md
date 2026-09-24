# Batch 1 — "Opening, incidents, vocabulary"

Built 2026-09-20/21 in one slice (plan: `~/.claude/plans/mighty-chasing-waffle.md`). Every item below has an
offline proof (core tests and/or a stub scenario) and a **live script** with exact commands and pass lines. Run the
validation as one pass — log a fail, move on, come back — unless a fail blocks everything.

Offline proof, all green before deploy:
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\ncm-test.ps1` — 69 core tests, Lua 5.4 + LuaJIT.
- `lua54 tools\ncm-stub.lua <name>` for: `gridcars latearrival pickup authoring onboarding inbox holding dressing telemetry incidents tworace weekend progression` (13 scenarios).

Decision record: L52–L58, P37–P45. Data model: `05_DATA_MODEL.md` (008/009 now Built).

Key / command cheat sheet for testers *(historical — Messages moved to **F9** in the Batch 2 fix pass, §2.6; every F7 below now means F9)*: **F7** messages · **F8** race graph on/off · `/ncm.q a|b|c|d` questionnaire by
chat · `/ncm.inbox`, `/ncm.read <n>`, `/ncm.accept`, `/ncm.decline` · `/ncm.profile` · `/ncm.telemetry on|off` ·
`/ncm.graph`. Console (Warden): `ncm.event.post <route> <min> [sprint|weekend|tworace] [laps]`, `ncm.invite <pid> [team]`,
`ncm.accept <pid>`, `ncm.q <pid> <key>`, `ncm.inbox <pid>`, `ncm.profile <pid>`, `ncm.telemetry`, `ncm.race`, `ncm.rc.*`.

---

## 5 · Competition vocabulary (008) — *built first; everything keys off it*

**What.** Discipline × format × class × ruleset as ids on events (L53); sessions carry kind/ordinal/parent so a format
with several sessions is one plan. Core lists are the truth; the tables mirror them for operators.

**Files.** core `competition/discipline.lua`, `competition/format.lua`, `competition/class.lua`; `competition/calendar.lua`
(materialize carries ids); league `server/competition.lua` (seed, ruleset, rulesFor, performanceFor); `schema/008_competition.lua`;
`calendar.lua` (persist/restore ids, tunables); `organized.lua` (`post` opts, `ncm.event.post <route> <min> [format] [laps]`);
packs `street.lua`, `ncx.lua`.

**Offline.** `test_competition.lua` (ids, oval flattening, drag lanes/straightness/deviation, format plans/grids, class BoP/eligibility,
calendar ids). Stub: every scenario boots through `migration 008/009` and `vocabulary seeded`.

**Live.**
1. After deploy: server log shows `migration 008 competition applied`, `migration 009 dimensions applied`, `vocabulary seeded: 11 disciplines, 5 formats, 4 classes, 18 class vehicles, 2 rulesets`. **PASS** = all three lines.
2. Warden console `ncm.event.post tip 5` → log `POSTED … | ncx_formula/sprint/ncx_rb15`. **PASS** = the three ids appear.

## 1 · Questionnaire → affinity → secret offer

**What.** First join (or a newer questionnaire version) opens the Driver Profile page; six placeholder questions
(owner replaces the copy in `ncm/core/onboarding/questionnaire.lua`); answers → affinity vector → `driver_profile.onboarding_json`;
the sorting hat weighs it within the variety rule. The player is never told about teams or affinity.

**Files.** core `onboarding/questionnaire.lua`; world `identity.lua` (`onboarding`, `saveOnboarding`, `onboardingPending`),
`main.lua` (`ncm:onboarding`, `/ncm.q`, console `ncm.q <pid> <key>`), client `panel.lua` + `web/panel.html`; league
`organized.lua` (`loadAffinity` → `Teams.assignSeat{affinity}`; log `affinity_top=`).

**Offline.** `test_quali.lua::questionnaire_validate_affinity_prompt`; stub `onboarding` (page path, chat path, hat steered to raven).

**Live (solo).**
1. Reset your profile once: SQL `UPDATE driver_profile SET onboarding_json = NULL WHERE display = '<you>'`, rejoin.
2. On ready: chat `Complete your NCM Driver Profile: press F7, or answer here with /ncm.q a|b|c|d.` and the page opens by itself. Click or press A–D through six questions. **PASS** = chat `Profile complete. Welcome to Night City Motorsports.` + toast; client log `panel input: yes`.
3. If clicks do nothing: client log says `panel input: no …` after 12 s → answer with `/ncm.q a` ×6 (chat twin). **PASS** = same completion line. Log it as *page input FAIL, chat twin PASS*.
4. `ncm.event.post tip 6` then `ncm.invite <pid>` (no team). **PASS** = server log `OFFER … affinity_top=<team>` and the offered team is that team.

## 2 · Messages inbox

**What.** `message` rows are the truth; the panel lists them, marks read, accepts/declines offers; toast says NEW MESSAGE · F7.

**Files.** league `organized.lua` (`messageList`, `messageRead`, `pushInbox` → bag `ncmInbox`; net `ncm:inbox`, `ncm:inbox.read`,
`ncm:inbox.act`; chat `/ncm.inbox`, `/ncm.read`; console `ncm.inbox <pid>`); client `panel.lua` (F7, `/ncm.msgs`).

**Offline.** stub `inbox` (list → read → act accept → entry inserted, second act ignored, chat twin).

**Live (solo).**
1. `ncm.invite <pid> kimiko` → toast `NEW MESSAGE · F7`. Press **F7** → the offer is listed, unread. **PASS**.
2. Click **ACCEPT** → chat `You're driving for Kimiko (#7) …`; the message shows `accepted`. **PASS**. Fallback: `/ncm.accept`.
3. `/ncm.inbox` → `Messages: 1 (0 unread)` and `1. [accepted] Kimiko · seat offer · car #7`. **PASS**.

## 3 · Grid reveal + holding

**What.** Organized events hold the lights until ≥75 % of the field is at its mark or 60 s past the scheduled start (tunables
`holdReleasePct`, `holdMaxWaitSec`); absent drivers are DNS at release. Far from the grid: REPORT TO GRID marker + waypoint; near:
your car's ring in your team colour, `YOUR CAR · #7 Kimiko`, hold E → you are warped into the driver seat.

**Files.** core `session/race.lua` (rules `hold`, `holdReleasePct`, `holdMaxWaitSec`; `hold` event; `originalStartsAt`);
league `race.lua` (slots carry colour/number; publish `grid`, `hold`); world `venue.lua` (`GlobalState.ncmVenue`), `garage.lua`
(`ncm:yourCar`); client `race.lua` (markers, strips, `ncm:yourCarPrompt`).

**Offline.** `test_incidents.lua::hold_*`, `street_races_do_not_hold`; stub `holding`.

**Live (two clients; solo variant releases at 100 % immediately).**
1. Both accepted seats; both far from the venue (>60 m). At T‑60: marker **REPORT TO GRID** at the grid point, waypoint set, strip `REPORT TO GRID · #7 · P1 of 2 · 1.2 km to the grid`. **PASS**.
2. Drive in: at <60 m the marker changes to your slot ring in your colour with `YOUR CAR · #7 Kimiko`; hold **E** → log `yourCar player=1 vehicle=… -> true` and you are in the car. **PASS** (if the warp is refused, chat names the car and slot: *warp FAIL, prompt PASS*).
3. Keep client 2 away past T‑5: strip `holding · 1/2 on the grid · lights when 75% are in, or in 0:5x`; log `HOLD 1/2`. **PASS** = no lights before the deadline.
4. `ncm.tp 2 venue` (client 2 arrives) → countdown starts within ~2 s. **PASS**. Alternative: leave client 2 away → green at ≤ T+60 with client 2 `DNS absent`. **PASS**.

## 4 · Venue dressing + loader

**What.** `/ncm.au dress <alias> [yaw] [radius]` places a server prop where you stand (or `/ncm.aw …` at the map waypoint);
`dress npc <template>` places a spectator looking at the grid; `dress list|undo|clear yes|up|down`. The league dresses the venue when
rides go out / the first session forms and undresses when the plan retires. Every platform refusal is logged (E19/E20 data).

**Files.** world `venue.lua` (`meta_json`, `dressCommand`, `dressUp/dressDown`, `ncm:venueDress/Undress`); league `race.lua`
(events at pickup/form/retire); manifest permissions `world.props`, `world.npcs`.

**Offline.** stub `dressing` (3 props + 1 NPC live, bad template refused, undo/down, meta survives reload, dressed at T‑5, undressed at retire, clear).

**Live (solo, at Pacifica).**
1. `/ncm.au venue pacifica_stadium`; stand in the lot: `/ncm.au paddock`, then at the line facing the course: `/ncm.au grid`.
2. `/ncm.au dress barrier.road.jersey`, `/ncm.au dress barrier.road.jersey 90`, `/ncm.au dress race.route_arrow` (aliases corrected 2026-09-21, KB-14) → chat `Placed prop N …` and the props are visible. **PASS** = 3 visible props. Refusals: chat `Saved prop N but the platform refused it: <reason>` → note the alias + reason (**FAIL** for that alias only).
3. `/ncm.au dress npc Character.<template>` (try two templates from the npc catalogue) → `Placed NPC N (…) — looking at the grid.` **PASS** = one standing NPC; refusals logged with reason.
4. `/ncm.au dress down` → all gone; `/ncm.au dress up` → back. **PASS**.
5. `ncm.event.post pacifica 6` (once a Pacifica route exists; else `tip 6`) + invite/accept → at T‑5 log `dressUp venue=… reason=event … props=3 npcs=1 failed=0`; after the result hold `dressDown … reason=session_retired`. **PASS**.

## 6 · Telemetry v0

**What.** Client samples its own car at 5 Hz while racing (position, speed, gear, on‑ground, health), sends batches of five;
server rings per driver, progress along the course, `telemetry_chunk` rows every ~10 s; server position stands in when the client is silent.

**Files.** core `telemetry.lua`; client `client/telemetry.lua`; league `server/telemetry.lua`; manifest `vehicles.read`.

**Offline.** `test_quali.lua::telemetry_progress_ring_and_batches`; stub `telemetry` (monotonic progress, chunk persisted, 5 km jump refused).

**Live (one race).**
1. During any race: client log `telemetry fields: …` once (copy the field list into §Results). **PASS** = the line exists.
2. Warden `ncm.telemetry` during the race → `session=… received=N refused=0 | <driver>: 60 samples, last client …m`. **PASS** = `last client` (not `server`) and progress rising.
3. After the race: SQL `SELECT ncm_driver_id, COUNT(*) FROM telemetry_chunk GROUP BY 1` → ≈ raceSeconds/10 rows per driver. **PASS** (±2).
4. Fallback: if `telemetry fields` never logs, samples are position‑only and `ncm.telemetry` shows `last server` — **PASS with note** (permission `vehicles.read` or `getPlayerSeat` missing on this build).

## 7 · Incident engine + corrected time + live graph

**What.** Zero‑fault contact bands (Δv → ×1/×2/×4; NCX bands 1.5/5/10 m/s), escalation per driver, object hits from hard stops with
no car nearby; seconds go on the **corrected time**, which decides the result. Live graph at the bottom of the HUD: one dot per driver
at corrected progress (F8 toggles).

**Files.** core `competition/incidents.lua`, `session/race.lua` (`incident`, `correctedSec`); league `telemetry.lua::scan`, `race.lua`
(`incident` event, `incident` rows, results columns); client `race.lua` + `web/race.html` (`#graph`, INCIDENT banner).

**Offline.** `test_incidents.lua`; stub `incidents` (both +4 s, dirty faster car loses, 2 incident rows, result columns).

**Live (two clients, one race).**
1. On the first straight, drive into each other at a clear speed difference. Both get toast `INCIDENT x2 · +4.0 s` and banner. **PASS** = both clients, same band. Server log `INCIDENT driver=… band=2 … other=…` ×2.
2. Finish with the dirty car ahead on the road by less than its incident seconds → results board shows the clean car P1, the dirty car `(+4s inc)`. **PASS**.
3. SQL `SELECT ncm_driver_id, band, seconds FROM incident WHERE session_id = '<sid>'` → two rows, same band. `SELECT corrected_ms, incident_ms, incident_count FROM session_result WHERE session_id = '<sid>'`. **PASS**.
4. Graph strip visible during the race with team‑coloured dots; **F8** hides/shows it. **PASS**.
5. Wall test (optional): hit a barrier hard alone → `INCIDENT x1 (object)`. Note whether it fires (health/decel detection is unproven live).

## 8 · Formats: weekend + two‑race

**What (as revised 2026-09-21, owner QA batch 2).** `ncm.event.post <route> <min> weekend` = qualifying (one run; window sized to the
route, `format.windowFor`) → race with the grid from quali. Practice is no longer a plan session (P48: on demand, Batch 2).
`tworace` = race 1 → race 2 with the top 8 reversed. The gap between sessions is the drive from the finish back to the grid
(`format.gapFor`, whole minutes, floor `sessionGapSec` 90 s).

**Files.** core `session/quali.lua`, `competition/format.lua`, `session/grid.lua` (`opts.order`); league `race.lua` (plans, kernels,
`nextSpec`); client `race.lua` (quali/practice strips, run restarts).

**Offline.** `test_quali.lua`, `test_competition.lua::format_plans_and_grids`; stub `weekend`, `tworace`.

**Live.**
1. `ncm.event.post tip 4 weekend` + invite/accept (both) → log `PLAN event=… format=weekend sessions=3`; at T‑60 `FORMED … kind=practice 1/3`; strip `PRACTICE · Tip-to-Trench · 1:00 until the window opens`. **PASS**.
2. Practice open: cross the start → toast `RUN STARTED`; finish → toast `RUN 1:23.4 · best …`; strip shows best. **PASS**.
3. Window closes → `Practice: …` result lines; 90 s later `FORMED … kind=quali 2/3`. Set two runs each; faster driver's best wins. **PASS** = `Qualifying:` lines in chat with both times.
4. `FORMED … kind=race 3/3 … grid from quali` and the faster qualifier is P1 on the grid (chat `Your car: … at slot 1`). **PASS**.
5. `ncm.event.post tip 4 tworace` → after race 1, chat `Next: race 2 in 1:30 — top 8 reversed`; race 2 forms with the race‑1 winner at the back. SQL `SELECT kind, ordinal, parent_session_id FROM session WHERE event_id = '…'` → 2 rows, the second with a parent. **PASS**.

## 9 · Oval + drag adapters (core only)

**What.** `discipline.ovalCourse` flattens laps into one gate list (only the last line is `finish`); `dragCourse` gives lanes,
`straightness` (SP ratio ≤ 1.15), `laneAssignment` (P44), `laneDeviation` → seconds. No host wiring yet.

**Offline.** `test_competition.lua::oval_*`, `drag_*`. **Live.** Not this batch — needs a captured roundabout/strip (`/ncm.aw`). Status: *core only*.

## 10 · Driver dimensions v0 (009)

**What.** After every race session: licence clean‑session counts per discipline (rookie → licensed at 3 → pro at 10), SR ±, rating
skeleton per class, accomplishments (`first_finish`, `first_win`, `clean_race`). Nothing gates.

**Files.** core `driver/progression.lua`; league `server/progression.lua` (`apply`, `/ncm.profile`, console `ncm.profile <pid>`); schema 009.

**Offline.** `test_quali.lua::progression_licence_sr_rating`; stub `progression`.

**Live.** After any race: chat `Driver profile: SR +0.05 → 5.05 · clean sessions: 1 · ★ first finish …`; `/ncm.profile` →
`Licence: ncx_formula rookie (1 clean) · SR 5.05 (0 incidents, 1 clean) · rating ncx_rb15 1004 (1) · clean_race, first_finish…`.
SQL rows in `driver_sr`, `driver_licence`, `driver_rating`, `accomplishment`. **PASS**.

---

## Tester install note (TW1) — what a tester needs

- The game + the OPEN//77 launcher. No extra mods are required for the street tier.
- For NCX (RB15 + liveries) until hosted delivery works (KB‑8): install the RB15 F1 Car Mod Demo v10 and the NCM livery zip into the game folder by hand, then in the launcher's **Mods & profiles → Your own game** switch on: `fable5`, `fable5.archive`, `rb15_f1_*` (5 tweaks), `ncm_rb15_liveries`, `ncm_rb15_liveries.archive`, `zzzz_ncm_rb15_liveries`, and the plugins **ArchiveXL** and **TweakXL**. Leave everything else off.
- Keys: **F7** messages, **F8** race graph. Chat: `/ncm.q`, `/ncm.inbox`, `/ncm.read <n>`, `/ncm.accept`, `/ncm.profile`.
- Telemetry is on while you race (your car's position/speed/gear, 5 Hz, kept per session). `/ncm.telemetry off` disables it.

## Validation runbook (one deploy, three sessions)

**Session A — solo (owner).** Boot lines (§5) → questionnaire (§1) → dressing at Pacifica (§4 steps 1–4) → invite + inbox (§2) →
weekend event (§8 steps 1–4) with grid reveal (§3 steps 1–2), graph (§7 step 4), telemetry (§6), `/ncm.profile` (§10).

**Session B — two clients.** `tworace` (§8 step 5); holding with client 2 away then `ncm.tp 2 venue` (§3 steps 3–4); race 1 with a
deliberate contact (§7 steps 1–3); `driver_sr` rows for both (§10).

**Session C — regression.** A street sprint from the cadence: enter at the venue, race, results, records. Pickup/late‑arrival are
stub‑covered; run `/ncm.ride` once if time allows.

## Results

| Item | Status | Notes |
|---|---|---|
| 5 vocabulary | step 1 PASS · step 2 pending | boot 2026-09-21 00:08 UTC: 008/009 applied, `vocabulary seeded: 11 disciplines, 5 formats, 4 classes, 23 class vehicles, 2 rulesets` (23, not the 18 written above — count in the doc is stale) |
| 1 questionnaire | **PASS** (2–4) | page input: **yes** (clicked through six questions, page opened on its own on ready); server `onboarding complete player=1 version=1 affinity_top=mizutani`, `onboarding_json` 231 bytes; step 4 `OFFER … team=mizutani seat=1 … affinity_top=mizutani`. Owner keeps wording notes in a separate md for the end-of-batch pass. |
| 2 inbox | steps 1–2 PASS · step 3 pending · **accept double-fire FAIL → fixed** | Owner accepted the Mizutani offer via the F7 panel (listed, ACCEPT click worked). Note: owner reports **F7 collides with the game's native camera toggle** — rebind candidate for the fix pass. Second accept (weekend event, 01:10 UTC): two `ncm:inbox.act` in flight → `entry` insert `SQL 1062` on `ux_entry_event_driver`, player saw a database error, the other request logged ACCEPTED. Fix: `offer.busy` guard in `acceptOffer` + one-shot ACCEPT/DECLINE buttons in `panel.html`. |
| 3 reveal + holding | step 1 PASS (solo) · steps 2–4 pending (Session B) · hold bounded (release 60 s after start, DNS absent) confirmed in the log | warp: not exercised yet (car spawned at the start; driver walked to it). REPORT TO GRID at T-60 with the practice banner seen from ~100 m; ring at the start registered as gate 1 (no car to reveal, see §8). |
| 4 dressing | **PASS** (2–5) |  refused aliases/templates: `barrier.jersey`, `race.chevron` (invented names → client `template_backend_disabled`, KB-14); every NPC template refused with `bad argument #10 to 'CreateNpc'` (damagePolicy enum, KB-13). Fix in `venue.lua` (enum lookup, default alias, seated-tp guard KB-12); stub `dressing` green; deployed 01:00 UTC. Retest: `barrier.road.jersey 90`, `barrier.concrete` visible; 3 NPCs spawned (`Character.mq306_spectators_male`, `q101_audience_female`, `sq017_riot_fan_male`); `dress down` removed=3+props, `dress up` `props=5 npcs=3 failed=0`. Rendering notes: plain `barrier.road.jersey` (author heading yaw) not seen on first placement; `race.route_arrow` renders as a flat black rectangle on the road (the host mesh draws, its hologram material does not — screenshot 2026-09-21 12:53 local); try `race.checkpoint` (keeps its StreetSignWidget graph) in the fix pass. NPCs face the grid (owner confirms). Props are not respawned at server boot — by design (league dresses at pickup/form). Prop placement now 2.5 m ahead of the author. |
| 6 telemetry | **FAIL** → fixed, retest pending | fields: (not captured yet). Every client batch refused `time_not_monotonic` (#1…#21): the server's 1 Hz stand-in samples (server clock) sat in the ring, the client's estimated clock lags them, so no client sample ever landed. Fix: monotonic check against the client's own last accepted sample (`rec.tm.lastClient`) with 1 s slack (`CLOCK_SLACK_S`); core tests + stubs telemetry/incidents green. |
| 7 incidents + graph | | |
| 8 formats | steps 1–4 **PASS** (4th run) · step 5 (tworace) pending, Session B | Weekend on `troll` (Troll Pass, ~550 m; Tip-to-Trench is ~6.8 km, too long for a 3-min window): `PLAN … format=weekend sessions=3`, `FORMED … kind=practice 1/3 … cars=0` — no team car for practice/quali (cars were `kind == "race"` only), driver on foot crossed gate 1 (`RUN START` on foot). Fix in `race.lua` (car at the plan's first session) + `garage.lua` (`ncm:yourCar` finds the plan's car from a later session id); stubs weekend/tworace/gridcars green. 2nd run 01:24 UTC: `FORMED … kind=practice … cars=1`, `grid cars … spawned 1/1`, run `0:38.799`, `COMPLETE … window_closed`, `FORMED … kind=quali 2/3` at +90 s. Quali/race not completed: **no marker or map route to the start for practice/quali** (forming drew nothing; open drew only the next gate), so the driver could not find the line from the far end of the course and beached the car; fixed in client `race.lua` (START LINE marker + map route on forming and between runs). Also the street cadence auto-routed the map to Vista Del Drag at `entry_open` while the driver held a seat — fixed in client `calendar.lua` (no cadence pin with `ncmEntry`). Practice results board stays up for the 90-s hold by design (`next: quali in 1:30`). 4th run 14:12 UTC: practice `cars=1`, run `0:55.467`; quali one run `0:41.733`, closed `all_runs_done`; race `FORMED … grid from quali`. Race not started: the league's `gridPoint` was the working venue's authored grid (Pacifica, next to the Troll Pass *finish*), so the HUD took the near branch and never routed to the slot 550 m away → `HOLD 0/1`, owner disconnected 20 s before the 60-s release. Fixed: `venueGrid(start)` only within 120 m of the route start; HUD routes to the slot when far from it; the result strip routes to the next session's start; countdown never sits at 0; staging text no longer says "cross it" before the window opens; board 15 s (P51). Owner QA batch 2 → P47–P52. Windows now sized to the route (`format.windowFor`, P49): `PLAN … route=N m | practice X min, quali X min` in the log. |
| 9 adapters | core only | |
| 10 dimensions | partial | `progression` applied after the DNS race: `sr 4.50 -> 4.50 licence - (0 clean)`. Rows exist; a real finish still needed. SR 5.00 → 4.50 = two object incidents (bands 2, 3: beached car, wall) — by design, and §7.5's wall test answered: it fires. |

### Owner QA batch 2, 4th weekend run (2026-09-21, `ncm_race_weekend_qa_batch_2.md`) — reached race formation

PASS: event, invite, accept, teleport, "stand anywhere", practice routing, practice, quali return routing, quali run + result, dressDown at retire (`removed=8`). BUG: practice start needed a reverse crossing (first pass over the line not registered — client arms at ≤ 60 m and reports; server `captureM` refuses fast crossings? investigate the report/retry path; no facing guidance). FAIL: qualifying → race routing (fixed, see §8). DESIGN → decision record P47–P52 (Race Guide first; on-demand practice; one-run quali with incidents; geography-aware quali → race gap; brief results; no invite/car/chauffeur ceremony on ordinary events). Owner direction for the next pass: **Race Guide, practice redesign, deterministic quali → grid transition** — not more timer complexity.

### Owner QA notes, 3rd weekend run (2026-09-21, `ncm_race_weekend_qa.md`) — blocked at practice start

Blocking, fixed and offline-green (deploy 3): (1) after crossing the start the map still routed to the start line — the HUD now routes to the **next gate** in every phase (forming → start; open → start before a run, finish during one; race → next gate); (2) `/ncm.gps` routed to the street cadence — now session-aware (`NcmClientRaceTarget`); (3) the map kick (KB-1) opened the map mid-drive — now only on foot, never at the wheel; (4) START LINE / REPORT TO GRID showed a dead **E** card — labels removed (KB-16); (5) qualifying is **one run** per driver (owner) — `format.weekend` quali `maxRuns = 1`, second start refused `no_runs_left`, window closes `all_runs_done` once every run is in (core test `quali_one_run_closes_when_every_run_is_in`).

Carried to the fix pass / design: F7 collides with the camera toggle → rebind; message lifecycle (expire/archive old offers) and the production rule for *when teams send offers* → decision record; the Messages page should read as a phone thread, not a menu; car spawned floating at the Troll Pass start (KB-17); stale map pins (KB-15); chauffeur (KB-10/11, P35/36). The "walk 100 m away" step was a test instruction to see the far marker, not a product requirement — dropped from the runbook. Practice → quali turnaround: the driver finishes at the far end; the route back to the start now shows the moment the run ends.

Live notes outside the batch (2026-09-21): chauffeur on the Tip pickup from the default spawn = `ai failed` at 386.8,−2397.8, stalls, Arcade Fire detour failed, hand-over to the driver after ~5 min (P35 failure handling worked; KB-11 confirmed again). Second weekend run (01:2x UTC): the kerb-side ride re-spawned into a wall after `ncm.tp 1 venue` — a dev/test expedient path (P35), not authored spawn/node pairs; the pickup should be suppressed when the passenger is already within the venue radius (fix pass). `dressUp`/`dressDown` act on `ncm_world`'s single working venue (`pacifica_stadium`) whatever the event's venue — TW1 single-venue assumption, fine for now, record in the venue work. No NPC template catalogue exists in the repo; `Open77.npcs.create` takes any vanilla `Character.*` record (API card 2026-09-19). Vanilla names come from CET's string table via `tools	weakdb-names.py Character. <grep>` (17,540 Character records). **Spectator candidates (unarmed crowd/audience records):** `Character.mq306_spectators_male`, `Character.mq306_spectators_female`, `Character.q101_audience_male`, `Character.q101_audience_female`, `Character.q302_basketball_audience_ma|mb|wa`, `Character.sq017_lounge_fan_male_rich`, `Character.sq017_lounge_fan_female_rich`, `Character.sq017_lounge_fan_male_corpo`, `Character.sq017_riot_fan_male|female`, `Character.spaceport_civilian_non_reaction_ma`, `Character.ep1_stadium_civilianguard_non_reaction_ma` (Dogtown stadium guard), `Character.q302_protester_civilian_ma|wa`. Control: `Character.Judy` (proven in the platform's own resources).
