# NOW - the single next-action index

> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md) - classified 2026-09-24 (L125).

**LATEST 2026-09-29 (night) - THE PADDOCK PHASES 4-5 BUILT AND RUNNING ON DEV (`L227`, doc 44 §19, `KB-214`, `IDEA-745`-`IDEA-751`).**
Owner rulings: phase 3 (sightings) skipped except what 4-5 need; MASTER_TEST is the 1.0 release bar, not a dev gate.
- **Garages (phase 4):** 83 sites from the game's own pins; 60 orgs rent 36 of them on persisted shifts. Walk up to a garage whose team is on shift and its crew is there with a **Talk** prompt (one line from facts; meetings remembered).
- **Live races (phase 5):** F6 → PADDOCK → RESULTS → NEXT UP → **HOLD: RUN IT LIVE** on a race 2.5-90 min out, then be at the start line (waypoint set). The grid spawns at T-75 s and drives a human ghost's line at each car's own sim pace; the server times every gate; a clean run replaces the sim result as `physical`, otherwise the sim stands.
- **NCM Pace** (`ncm/pace` 0.1.0) is on dev `requiredMods` (4 declared): it drives the same native command uncapped and reports gate times. `liveBackend = auto` picks it when your client has it.
- Gate: `tools/ncm-test.ps1` ALL GREEN (core 830 under 5.4 and LuaJIT; paddock host 168; migration dry-run 043-051 twice; Pace state tests; redscript compiles). Dev boot verified after the KB-214 fix.
**THE ONE NEXT ACTION (Paddock): relaunch through the launcher (it projects NCM Pace), go to a garage on shift, then declare a live street race and watch it; read `ncm_pace-<pid>.log` beside the DLL for P-PACE-2.** Online stays frozen (`L223`).

**LATEST 2026-09-29 (evening) - THE PADDOCK PHASES 1-2 BUILT, OFFLINE-GREEN, NOT DEPLOYED (`L226`, doc 44, `IDEA-738`-`IDEA-744`).**
The NPC motorsport world is built on dev terms:
- 60 orgs and 420 people from the owner's FTB name generator, ported and cleaned (no real drivers, region-first names).
- A 45-race Eastern daily rhythm, a sprint sim, weekly Cups, standings, the tape and WIRE, and earned tags.
- Migration 043 stamps human results; Billie is authored, with her board and slips; manager mode; the doc-14 sanctioned-org schema.
- F6 PADDOCK tab. New resource `ncm_paddock`; schema 043-050 in `ncm_league`.

`tools/ncm-test.ps1` is ALL GREEN (core 819 under 5.4 and LuaJIT, paddock host 64 checks with VM instruction metering, panel render 267).
`tools/test-paddock-migration.ps1` is OWED: it needs `NCM_DB_ROOT`.
**RUNNING ON DEV 2026-09-29 18:56 ET** after two fixes (`KB-213`): migration 046 (SQL 1901) and nil holes that killed genesis. Migrations 043-050 applied; genesis wrote 60 orgs, 420 people, 92 sponsors and 6 series; the first races follow the rhythm (Regional 19:00/19:30, Street from 20:00); Billie's lines are priced. The dev server runs in its own console window. **THE ONE NEXT ACTION (Paddock): run `MASTER_TEST §CH1`-`§CH16` on dev with the owner and `ncmtester2`.** Online stays frozen (`L223`).

**LATEST 2026-09-29 - ONLINE FROZEN AT BASELINE 1; ALL WORK ON DEV (`L223`). PVE IS A NIGHT CITY LIFE SIM (`L222`, `IDEA-730`-`IDEA-734`).** Online is sound for wheel testers (a Thrustmaster tester and two more are planned), so it is frozen exactly as deployed: 374 resource files verified byte-identical to the tree, tagged `online-baseline-1`. `deploy-staging.ps1` now refuses Online without `-ThawOnline`. PvE is modelled on a life sim (inZOI / The Sims 4 in Night City, motorsport-flavoured) with no first arc. Every vanilla system is ruled individually, physical facts may write back when corroborated, and the Paddock comes before the social sim. **DEV CAUGHT UP 2026-09-29 16:07 ET:** dev now declares the same three required mods (blobs copied from Online, hashes verified) and loads `open-voice`. Its database applied migrations 031–042, and every `ncm_league` subsystem started. Dev reproduces Online's one open `SQL 1292` (transaction statement 1/33, logged 24 times on Online), so that defect can now be debugged on dev. Paddock rulings are `L224`: separate circuit, full scale, street at night and sanctioned by day, Billie on NPC races, sim-only first, and garages rented and shared across teams by time of day. **`44_THE_PADDOCK.md` ADOPTED (`L225`); MASTER_TEST §CH written ahead of the build.** **THE ONE NEXT ACTION: build Paddock phase 1 (the season runs) on dev, starting with the pure core modules and their Python-oracle tests.** The earlier live-test queues (markets, map pins, race entry) are Baseline 1 behaviour: test them on Online as players, but fix on dev.

**LATEST 2026-09-29 - PVE RULINGS (`L221`, `IDEA-729`, `KB-212`), RESEARCH ONLY.** Native dialogue approved as the first probe (`IDEA-727`). Native phone deferred: the SP phone lagged the game during development and Foreman's thread still lags (`KB-212`). Sim control over vanilla systems is ruled per system (14-row table in the vision, 12 rows awaiting the owner). The clock goes real-time US Eastern, which the platform clock supports as rate 1.0 plus an anchor (`IDEA-729`). Proven code is reused by reimplementing it in Lua, with the Python originals as test oracles. The [vision](../research/open77/NCM_PVE_WORLD_VISION_AND_SIM_REVIEW.md#questions-for-the-new-model) carries 12 new questions for the new model. **THE ONE NEXT ACTION (PvE): owner answers those questions; then build the native dialogue probe and the real-time clock service, each with MASTER_TEST cases.**

**LATEST 2026-09-29 - PVE VISION RESTRUCTURED AS A SIMULATION STACK OVER NIGHT CITY (`L220`, `IDEA-726`-`IDEA-728`), RESEARCH ONLY.** Owner: PvE leans simulation-based on the owner's Python engines, using CDPR's Night City and engine underneath; and OPEN//77 is not the extent of capability, because NCM ships its own redscript/RED4ext mods. The [vision](../research/open77/NCM_PVE_WORLD_VISION_AND_SIM_REVIEW.md) is now five layers (platform, Night City through three capability tiers, a one-job-per-engine sim stack, fact tapes, expression), with a capability inventory and an engine appendix that adds FTB1. **THE ONE NEXT ACTION (PvE design): run the two isolated native probes - a server-materialised named NPC conversed with through the native choice UI, and an Online thread in the native phone - then write the tick/tape ownership contract.** No runtime changed.

**LATEST 2026-09-29 - LONG-TERM PVE VISION AND FOUR-SIM REVIEW (`L218`-`L219`, `IDEA-722`-`IDEA-725`), RESEARCH ONLY.** The owner clarified that each player has their **own PvE adventure** over a **shared Paddock/city simulation**, with a voluntary driver or manager path, a mix of racing/jobs/turf, existing plus new contacts, shifting shared access/alliances, and known Night City places with mostly original groups. Named physical NPCs should support text conversations with four primary intents, deeper authored choices and frequent evidence-backed variation; no voice acting or mocap. The [deep review and next-coder handoff](../research/open77/NCM_PVE_WORLD_VISION_AND_SIM_REVIEW.md) maps Oracle Kingdom, ForkUniverse, Neikos and FTB2 into that vision, identifies source limitations, and separates shared world facts from individual adventure history. It is PROPOSAL architecture; no source copied from the other sims and no NCM runtime changed. **THE ONE NEXT ACTION (PvE design): reconcile the Paddock attachment with L218-L219 and specify the shared-world / per-player-adventure event ownership contract, including how a private act creates a public consequence and how Messages and a physical NPC read one conversation state.** This is long-term planning, not an “ideal first version” brief.

**FORKUNIVERSE + NEIKOS STATIC REVIEW (`L217`, `IDEA-721`).** ForkUniverse offers stable event/tick-keyed randomness, replay/catch-up equivalence and fact/delta separation. Neikos offers action-driven trajectory and compact scene pressure. Their detailed assessment is [here](../research/open77/ORACLE_KINGDOM_PVE_ASSESSMENT.md#2026-09-29-forkuniverse-and-neikos-comparison). No tests were run in this review.

**ORACLE RACING STANDALONE PROTOTYPE BUILT (`L216`, `IDEA-720`), NOT PORTED TO NCM.** The copied Radio-OS Oracle Kingdom/court source, headless tools and reference UI live in [prototypes/oracle_racing](../../prototypes/oracle_racing/README.md). New `racing_world.py` is a pure racing-social model: immutable simulated/observed event facts, six example NPC roles with private trust/respect/grievance and bounded memories, district standing, cause-linked offers and choices, deterministic replay and Oracle's causal ledger. An accepted offer can lead to a later event along a traced causal path. Initial 100-seed/32-event sweep: mean NPC respect -56.7 to +98.2; 36/600 cap hits; 11/100 seasons without an offer. Six behavioral tests pass. These are prototype results, not NCM validation.

**LATEST 2026-09-29 - ORACLE KINGDOM PvE SOCIAL ASSESSMENT, RESEARCH ONLY (`IDEA-719`, `L215`).** The owner wants Oracle Kingdom's socio-political machinery considered for per-player NPC relationships around the Paddock, primarily social rather than racing. The correct Radio-OS source is `plugins/oracle_kingdom.py` plus `oracle_court.py`; the supplied `_kingdom.py` path is absent. Ten full 500-tick/200-background-civilization seed runs passed with final health 44.2-48.2, nine STABLE eras and one REFORMATION. A separate ten-seed/20-background-civilization run produced 6-11 presence requests per seed. The court-only stress harness falsely reports zero requests because it never advances the Oracle lifecycle out of SLEEPING. There is no Oracle pytest suite or NCM live PASS. The research note is [ORACLE_KINGDOM_PVE_ASSESSMENT.md](../research/open77/ORACLE_KINGDOM_PVE_ASSESSMENT.md). **THE ONE NEXT ACTION (this thread): review the proposed private social-event seam, then build a bounded, pure reducer prototype and a coverage harness only after the Paddock public event contract is defined.** This research does not displace the existing live-test queues below.

**LATEST 2026-09-29 - 20 PHYSICAL AUTOFIXER MARKETS BUILT, OFFLINE TESTING IN PROGRESS, NOT DEPLOYED (`L206`).**
All owner-supplied coordinates are distinct interaction-only Markets: no pin, no proximity discovery, and a fresh
server position check within 6 m after pressing E. Once learned they persist in the F6 Market Network beside Base
Market. The catalogue adds 18 official-data-verified base/update/Phantom Liberty model families; each terminal has
1–3 model offerings. Each also has two newly authored specialty Part families with its own Designs and serialized
supply—no Base Market component is re-listed. F6's remaining Base Market literals were removed from inspect and
component-purchase actions. **THE ONE NEXT ACTION (Markets): finish the full offline gate, then deploy and verify
one terminal interaction, persistence across reconnect, all learned F6 sources, one non-Base vehicle purchase and
one non-Base component production/purchase before broad terminal-by-terminal coordinate QA.**

**LATEST 2026-09-29 (early) - NO MAP PINS AT ALL (`KB-203`): FUEL STATIONS AND LANDMARKS INVISIBLE; `/ncm.fuel` AND A
`/ncm.blips` PROBE BUILT AND DEPLOYED TO ONLINE 2026-09-29 03:08 UTC.** The deploy carried the Autofixer markets update, whose
missing `market.kind` aborted `ncm_league`'s boot for about four minutes (`KB-204`, fixed and live; catalogue generation and one SQL 1292 still open). Owner on Online: no fuel blips (or race nodes), nowhere to refuel. The
client log says all 53 fuel and 35 landmark blips were created; none render, including native `vendor`/`fast_travel`,
so it is not only the SVG path. The platform mappin filter logs only the routable nav blip as allowed; `§AD7` never passed, so
non-routable NCM blips have never been proven visible. `/ncm.fuel` routes GPS to the nearest station at any fuel level
(`IDEA-708`); `/ncm.blips` drops four probe sprites to find one that renders.
**UPDATE 03:18 UTC:** `§CF9` PASSED (all four probe sprites visible), which proved the cause: the layer pins were built in the
pre-game world before the character save replaced it. Pins now wait for the settled real world (deployed). Catalogue
generation bumped to 2; collection ready; proximity stays sighting-only (`L197`).
**THE ONE NEXT ACTION (map pins): rejoin and run `§CF7` (fuel pins, incl. whether SVG icons render), `§AD7` (landmarks)
and `§CF8` (`/ncm.fuel`).**

**LATEST 2026-09-28 (night) - PERSISTENT FUEL THIN SLICE BUILT AND OFFLINE-GREEN, NOT DEPLOYED.** `L204` /
`IDEA-702`: fuel is persistent per Machine and burns only from server-accepted odometer distance. The odometer HUD
now shows FUEL %. Alpha tuning is 60 L, 350 ml/km and €$2/L; station refuelling settles money and fuel together.
Empty fuel persists, stops the engine and sends `Stuck? Type /ncm.nofuel for help.` to toast and chat. The recovery
command routes the nearest station. No verified server-safe jerry-can/equipment method is present yet, so the built
fallback dismounts the Driver and stores/tows the Machine to that station for an F6 call and `/ncm.refuel`. Two
authored candidate station blips are visible from the beginning and remain explicitly unverified in-engine.
Owner correction (`IDEA-704`): two stations were only smoke-test fixtures and are removed. The supplied 5.4a
archive contains 81 current pump points, grouped into 53 anonymous physical station sites for map/recovery while
retaining every pump for refuelling proximity. Only factual coordinates were carried; no third-party name, code,
icon, asset, pricing or interaction logic was copied. All 53 remain live-verification-gated. `KB-200` corrected
the first blip pass before deployment: OPEN//77 expects a manifest-declared `icons/fuel.svg`,
not the WebUI path `web/icons/fuel.svg`. Each station now creates as a map-capable native vendor marker first;
`setIcon` then applies the SVG and logs the exact refusal while leaving that visible fallback intact.
**THE ONE NEXT ACTION (fuel): deploy schema 042 before `ncm_world`, then run `MASTER_TEST §CF1`-`§CF7`; replace
the tow fallback when the owner's jerry-can method/asset is supplied and verified.** `IDEA-703` records ZF
PropForge as the leading candidate asset pipeline: first obtain/test its output and permission, then separately
prove a hand attachment or native item-record path; a spawnable world prop alone is not yet a carried can.

**LATEST 2026-09-28 (late) - PHYSICAL MOTORING NETWORK DIRECTION RECORDED; RECONNAISSANCE ONLY.** Owner direction
`L203`: every Autofixer terminal is its own Market, unmarked until explicit interaction; F6 then remembers it
forever and permits remote purchases. Test drives exist only at that terminal, are timed/geofenced/return-to-origin
and refuse race entry. Two violations plead for the car; strike three triggers a five-star Hellfire response.
Returning clears NCM's penalty but not the active chase; death returns the Machine and clears Hellfire; disconnect
also returns it and clears fugitive state. Keeping the car makes the living Driver a persistent fugitive, and police contact retriggers five stars. Physical garages
and fuel stations are visible from the beginning as distinct NCM-authored SVG map POIs. Bought Parts move to
garage-only fitting charged as a percentage of Part value; that is the first Engineering slice, while earned DIY
remains a large later lane. Linked
GarageCore/YARRG/CMS/Immersive Fuel and map sites are references only; their assets are permission-restricted and
no coordinate is accepted without in-engine verification. `IDEA-695`-`IDEA-701` hold the open implementation
details. **Next action for this thread: author the timer, geofence and fitting percentage as tunable balance values,
then write the bounded discovery + test-drive + paid-fitting work package.** This does not displace the deployed/live-test queue below.

**LATEST 2026-09-28 (late) - RACE ENTRY REBUILT AROUND PLACE: A RING FOR EVERY RACE, THE CARD FOR THE RING YOU
STAND IN, ONE ENTRY AT A TIME. BUILT AND OFFLINE-GREEN, NOT DEPLOYED.** Owner: *"we have been fighting bugs for our
race entries and things are getting lost in translation."* This is a separate workstream from the FFB block below.

- **Root cause (`KB-195`-`KB-199`).** "Which race is this ring/card for?" was answered by time and by driver, never
  by where the driver stood. There was one ring in the world, visible from only 15 m. A bookmark outranked a
  paid entry. `enterPlayer` wrote `ncmEntry` behind the Guide's cache, so the card at one ring could act on
  another race. Team seats could not be withdrawn, and the drawn 6 m ring hid a 30-60 m server allowance.
- **Owner rulings, `L202`:** every race inside 20 min has its own ring, visible from far away (500 m). The card
  belongs to the ring you stand in. Interest is a bookmark. One entry at a time, and a seat counts. Switching is two
  presses. A seat is withdrawable. Street Calls get their own ring. The drawn ring is the entry rule.
- **Offline:** core 765/765 (5.4 + LuaJIT), full `ncm-test.ps1` green, and the new stub scenario `ringcard`. Stub
  drift from `IDEA-685` is unchanged. `entrybag` is green again.

**THE ONE NEXT ACTION (race entry): deploy `ncm_league` + `ncm_world` to Online, then run `MASTER_TEST §CE1`-`§CE6`.**
`§CE1` also answers whether a flat ring is noticeable at a few hundred metres (`IDEA-694`). The FFB action below is
independent and unchanged.

**LATEST 2026-09-28 (late night) - THE RIG BRIDGE BECOMES THE WHOLE INPUT LAYER: JOYMOCO, PORTED. BUILT AND
OFFLINE-GREEN, NOT DEPLOYED (`L205`, `IDEA-705`).** Owner: *"full joymoco capabilities ... its rp fuel."*

- **DEVICES** replaces WHEEL/PEDALS: collapsible WHEELBASE & PEDALS, FORCE FEEDBACK, GAMEPAD. GAMEPAD holds
  recorded **variants** per Xbox output from any device (rim button, Joy-Con button, Joy-Con press-then-swing),
  each with a rumble preset, side and context (driving / on foot / both); gyro steering; stick rotation;
  calibration; game rumble to Joy-Cons; local JSON profiles.
- **How it reaches the game:** a detour on the game's own XInput (it imports XINPUT9_1_0, no
  Windows.Gaming.Input), so no ViGEm driver. Input: SDL3 in-process (Joy-Cons and the rim, which DirectInput
  cannot see in-game, `KB-201`) plus DirectInput. Carrier 0.1.30 starts no SDL when the Rig Bridge is present.
- **Default profile:** the owner's 16 rim bindings from JoyMoCo (the other 11 of the 27 were Xbox-pad
  passthrough, which would double every pad press). JoyMoCo was only read.
- **Offline gate:** pad engine tests (holds, variants, context, staged swing, both recorders, gyro steering,
  XInput merge), feel and mapping tests, clean build, panel harness green with a new DEVICES-sections check.
- **Staged, not deployed:** `dist/ncm-rig-bridge-0.1.6.zip` (`3dc80f1b…`), `dist/ncm-carrier-0.1.30.zip`
  (`d4431422…`) and the panel.

**DEPLOYED TO ONLINE 2026-09-29 02:29 UTC** with the fuel work (18 hash-diffed resource files, migration 042 applied,
`Required mods: 3 declared`, digest `34cfc150…`, backup `backups/pre-devices-fuel-20260929T022746Z`). `ncm_world`
failed its first start (`KB-202`, fuel data module unregistered), fixed and redeployed 02:32:36 UTC, 0 errors.

**0.1.6 FAILED `§CG1`/`§CG2` LIVE (2026-09-29 11:01 local):** SDL3 opened the G29 and ARM killed FFB until a
replug (`KB-209`), and the panel could not reach the gamepad API because a bundled page has no network (`KB-210`).
Both are fixed in **Rig Bridge 0.1.7** (`dist/ncm-rig-bridge-0.1.7.zip`, `eea1aba6…`) plus `panel.html`,
`panel.lua` and `carrier_bridge.lua`. The gate is green. **DEPLOYED TO ONLINE 2026-09-29 15:18 UTC**: digest `ec87d05c…`, 0 errors,
backup `backups/pre-rig-0.1.7-20260929T151707Z`.

**THE ONE NEXT ACTION: rejoin (the launcher installs 0.1.7), then run `MASTER_TEST §CG1`-`§CG14`
from the top (ARM with no replug first), and the fuel rows `§CF1`-`§CF7`.** The rim (`joystick:Evenracing`) did not
appear in the 0.1.6 log either; whether it was connected is unknown (`KB-201`).

**LATEST 2026-09-28 (night) - FFB IS BACK ON THE G29 (LIVE); TUNING IS NEXT, AND IT NOW HAS NUMBERS.**
Owner: *"ffb is back. log the fix. next we tune."*

- **The real cause of "FFB worked once and got lost" was two owners (`KB-188`, `L201`).** The Carrier opened the
  G29 through SDL haptics, which takes it EXCLUSIVELY, and so did the Rig Bridge. Whoever acquired last owned
  the wheel; on vehicle entry that was the Carrier, whose own output had mistaken the pedals for the wheel.
  Carrier 0.1.29 now leaves haptics alone when the Rig Bridge is installed. `KB-187`'s repairs were real but
  could never be felt while the wheel was taken.
- **Rig Bridge output rebuilt as its own module (`KB-189`, `KB-190`).** Own device handle and window, effects
  started once and only updated, X axis, and every DirectInput result shown in the panel's FFB OUTPUT row.
  Direct drive is limited in newton-metres and any wheel identifies itself with no console (`IDEA-687`).
- **Deployed to Online 21:44 UTC** (Carrier 0.1.29, Rig Bridge 0.1.4, `Required mods: 3 declared`, digest
  `9a38fa6d…`). **`§CD1` PASS** (owner). Backups: `server.jsonc.pre-ffb-0.1.4`, `mods/panel.pre-ffb-0.1.4.html`.
- **Rig Bridge 0.1.5 plus panel, DEPLOYED 22:24 UTC** (digest `78d1b0da…`, backup
  `backups/resources-pre-ffb015-20260928T222317Z.tar`, `server.jsonc.pre-ffb-0.1.5`): every vibration slider is its own effect with a LIVE
  now/peak readout and RESET PEAKS (`IDEA-688`); the engine follows revs again, 12-47 Hz, by owner decision
  (*"125 hz is the old one"*, `KB-191`, `IDEA-689`); TEST PULSE is ARM-gated again (`KB-190`); the live
  0.1.4 panel's per-frame rebuild is fixed (`KB-193`); and collisions are rebuilt to be felt from every
  direction, head-on included, with their own COLLISION slider (`KB-194`, `IDEA-690`, `§CD11`).
- **Same deploy carried a parallel session's race-entry work** (owner: expected): 17 hash-diffed resource files in
  `ncm_league`/`ncm_scanner`/`ncm_world` (calendar, entry, venue_options, organized, impromptu, street pack,
  guide, qa rules, client calendar, `venue.html`). No migration. Gate ALL GREEN and `ncm-build -Check` clean first.
- **Open:** ROAD reads zero in every session because suspension telemetry never arrives (`KB-192`).

**THE ONE NEXT ACTION: rejoin (the launcher installs 0.1.5) and run `MASTER_TEST §CD2`-`§CD11` one channel
at a time, recording felt / LIVE peak / chosen value.** `§CD6` decides the engine; `§CD8` is expected silent.
The values from `§CD9` become the shipped defaults. monki's T128 report (`IDEA-421`) is the checklist for a
second wheel.

**LATEST 2026-09-28 - RIG BRIDGE 0.1.2 RESTORES THE DYNAMIC FFB PATH IN CODE; BUILT AND OFFLINE-GREEN,
NOT DEPLOYED, LIVE WHEEL PASS OWED.** Owner: *"dont want a probe, want a fix that restores ffb."*

- **`KB-184` is corrected.** Its keyboard slider defect and fix are real, but its main diagnosis was not. In
  0.1.1 the live setters changed atomics and `persist()` wrote a separate startup `Config`, so `strength 0.020`
  and `armed false` in `ncm_rig_bridge.user.json` were not evidence of the FORCE used by the running wheel. The
  owner's report of raising FORCE stands.
- **`KB-187` / `IDEA-686` / `L199`: behavior fix, not probe.** The SINE stream changed the playing effect's
  period with revs and could restart it from phase zero at the 250 Hz pump cadence. Both SINE and CONSTANT also
  cached a requested value before checking whether DirectInput accepted it. 0.1.2 uses a fixed 125 Hz carrier,
  caps periodic magnitude writes at 50 Hz, lets DirectInput choose its compatibility restart, retries once after
  reacquisition, and records a value as sent only on success. The watchdog now gates effect start, removing the
  armed-but-parked 250 Hz start/stop loop.
- **Settings now mean what they say.** FORCE, class and all tune values update the persisted config. ARM is
  intentionally session-only: every cold launch still begins disarmed.
- **Artifact:** `dist/ncm-rig-bridge-0.1.2.zip`, SHA-256 `ee818938…bffc5`; clean MSVC build and both native tests pass. Hardware remains
  unproven until `MASTER_TEST §CC` records SINE and CONSTANT on the G29.

**THE ONE NEXT ACTION: publish/install Rig Bridge 0.1.2, cold-launch, then run `§CC1`-`§CC5`; `§CC3` (continuous
road/engine texture) and `§CC4` (aligning torque plus TEST PULSE) decide whether FFB is restored.** The external
companion remains the fallback until both pass. This does not erase the already-owed Online rows below.

**LATEST 2026-09-28 (evening) - BUG FIX PASS: THE RING, STREET CALL ENTRY, AND WHY "HIGHEST FORCE" DID NOTHING.
DEPLOYED TO ONLINE 19:18 UTC, WITH THE SESSION LANDING PANEL UPDATED.** Owner: *"venue entry ring doesnt show up unless im there and i re
express interest ... custom races fail to be entered due to some economy reason ... ffb rumble has disappeared
again ... i tried highest force so its not that."* All three were traced from the client, Rig Bridge and Online
server logs of the 14:35 local session, not from docs.

- **`KB-185` ring.** `ncmEntry` was re-derived only on interest or withdraw, so after the race it named had passed
  (city_cup, 18:40 UTC), it went on naming a race that no longer existed, and nothing was ringed. Not caused by the
  F5 work. `NcmGuide.refreshEntryBags` now re-derives it every 5 s, and a running weekend holds its ring.
- **`KB-186` Street Call.** Refused with `economy_required`: a Street Call is unpaid by design, and Economy v1's
  check-in treated "no economy" as "broken". Now an event that **declares** itself unpaid enters free and settles
  to nothing. Any other missing economy still refuses (`L198`).
- **`KB-184` force — CORRECTED by `KB-187`.** Keyboard Left/Right on a slider really did rely on native stepping
  that never happens in the host, and sliders now step in code and commit on release. But `user.json` was a stale
  startup-config record, not live proof; the claim that no FORCE reached the bridge and rumble stayed at 2% is
  withdrawn. Rig Bridge 0.1.2 owns the actual SINE/CONSTANT repair and `§CC` decides it.
- **Gate:** `ncm-test` ALL GREEN. New stub scenario `entrybag` fails on the previous code for both server bugs.
  The stub had silently stopped loading since `1f7ec0a` (shimmed); six older scenarios are red on HEAD too
  (`IDEA-685`).

- **Landing panel** (owner: *"check session landing page, update it and deploy"*): a new release entry, *Scanner,
  quick menu and fixes*, covers the Scanner, the radial, health regen, keyboard F6 and these three fixes. There
  are new `partial` capabilities **Call a street race** and **Scan machines**, each with its limit, and the
  entry-fee line now says scheduled races only. All of it was checked against the core validator.
- **Deploy:** exactly 7 files differed from Online (hash-diffed), and all were this session's. No players were
  connected. No migration. The server is healthy, and after the restart all 357 files are identical. No backup
  was taken; this change touches no data. Required mods still read **3 declared**, digest `917298d8…`, unchanged since
  17:56 UTC. The "4 declared" in the 16:41 note below is stale.

**The remaining next action for this older batch is `MASTER_TEST §CB1`, `§CB3`-`§CB6`; §CB2 is superseded by the
0.1.2 force-output run at §CC.** This rides alongside the
owed §BT-§CA rows below; it does not replace them.

**DEPLOYED 2026-09-28 16:41 UTC to Online (Lightsail):** the whole shared tree, i.e. Exchange (`L194`, migration 040
applied), health regen, the radial resource and F6 renamed Hub, plus two NEW required mods, `ncm-radial` 0.1.0 and
`ncm-vision` 0.1.0 (4 declared now, with Carrier and Rig Bridge). Server healthy: scheduler, race control and
Exchange ready, no errors. Backup `/opt/ncm/backups/pre-carrier-prod-20260928T163834Z`. **Deployed is not done:
the next action for all of it is the live rows `MASTER_TEST §BT-§BY`, with §BX1 (radial host) and §BY1 (no
redscript compile error) first, since a script failure would hit every joining player.**

**Also 2026-09-28 - F6 HUB ACCESSIBILITY FIXED, DEPLOYED TO ONLINE 18:15 UTC (`KB-183`, `IDEA-682`).** Owner: *"i have to
spam click the buttons on [wheel/pedals] ... why can i tab everything but enter does nothing?"* Cause 1: the WHEEL
tab rebuilt every control on every streamed Rig Bridge frame, so a click's press and release hit different nodes.
It now redraws only on structural change and writes the values in place. Cause 2: `ncm-nav.js` held focus by DOM
node, so after any redraw Enter activated a detached node and did nothing. Focus is now keyed and recovered.
Enter also cycles dropdowns, and Left/Right belong to a focused slider or dropdown. `ncm-test` ALL GREEN, and the
new assertions fail on the previous commit. Only `ncm_world/web/{ncm-nav.js,panel.html}` differed from the server (hash-diffed), so nothing else
shipped. Server healthy after restart. **Next action: rejoin and run `MASTER_TEST §CA1-§CA6`.** A pad still cannot move a slider (`IDEA-682`).

**Also 2026-09-28 (parallel session) - NCM QUICK MENU: A NATIVE RADIAL, BUILT AND PACKAGED, LIVE-GATED (`L195`).**
Hold **Start** (pad) or **B** (keyboard), aim, release: Hub (F6, renamed from "race guide"), Race graph, Call a
race, Map, GPS, with three slots open for what is coming. Drawn natively by a **new** required mod `ncm-radial`
(`ncm/radial/`, `dist/ncm-radial-0.1.0.zip`), not WebUI and not Carrier/Rig Bridge; input and decisions live in the
new `ncm_radial` resource; actions run through `ncm_world`'s `quickAction` export over each hotkey's own function.
Offline: DLL clean, state tests pass, redscript compiles against vanilla + OPEN//77, `ncm-test` green. **Its next
action: publish `ncm-radial` to the dev server and run `MASTER_TEST §BX1-§BX8`; §BX1 (host found) decides whether
the rest can run.** The Exchange next action below is unchanged.

Last rewritten: **2026-09-28 (latest) - PLAYER EXCHANGE IS A FULL F6 SYSTEM, OFFLINE-GREEN AND LIVE-GATED.**
Owner: *"implement today"* and *"the exchange panel [must be] built in F6 — don't hack around this with a
narrow vertical slice."*

- **`IDEA-247` is built locally under `L194`.** F6 has a first-class **EXCHANGE** tab: invite/accept/decline,
  exact Machine, fitted-Part bundle, stored-Part and cash offer construction, two clearly separated sides,
  revision-bound hold-to-confirm, refusals and receipts. `/ncm.exchange` and `/ncm.trade.*` are recovery twins,
  not the product. Direct synchronous trade is the complete first system; persistent listings remain a later
  escrow product.
- **Settlement is one durable heterogeneous envelope.** Migration 040 records the exact accepted revision,
  every Machine/component/custody leg and the paired money leg. Both confirmations are invalidated by any edit;
  custody, funds, installed set, race commitment and materialized-Machine state are rechecked before commit.
  Machines keep identity, ordinals, odometer and history; installed Parts move with them and retain wear/service.
- **Atomic means against the rest of NCM too.** `economy_balance_lock` now serializes every debit in Exchange,
  vehicle/Part Markets and event check-in before its ledger balance predicate, closing the concurrent double-spend
  window rather than making Exchange atomic only in isolation. Accepted retries cannot move value twice.
- **Offline gate is ALL GREEN under Lua 5.4 and LuaJIT:** 747 core tests, an 18-assertion real host-adapter
  lifecycle/transaction harness, `luac -p` over 260 resource files, 232 F6 panel render assertions, all other
  render harnesses, docs authority over 79 documents, and `ncm-build -Check` clean. Nothing is deployed and no
  live PASS is claimed.

**THE ONE NEXT ACTION: commit the currently shared working tree, deploy the complete resource tree with migration
040, then run `MASTER_TEST §BW1-§BW14` with two real clients.** The decisive row is §BW9: one exact mixed offer
settles once and a retry moves nothing. The same deploy still carries the older owed §BN/§BT/§BV work; do not
mistake the offline gate for any of those live PASSes.

Alongside it, **2026-09-28 - NCM SCANNER: GREEN LIVE-PASSED; RETICLE AND SCAN-GATED DISCOVERY BUILT AND DEPLOYED,
LIVE-GATED (`L196`, `L197`, `IDEA-679`, `IDEA-681`).** Green on Tab / Caps Lock passed live (`§BY1-§BY2`, owner).
**Owner decision `L197`:** a new Machine enters the Index only by a Scanner hold of about 1.5 s within 60 m.
Proximity is now a sighting of a known machine. NCM ambient cars are registered and scan as `server_measured`;
vanilla per-client cars scan as `client_attested`, rate-limited. `ncm-vision` 0.2.0 (`dist/ncm-vision-0.2.0.zip`)
adds a DLL transport on 38600+ and a native reticle in the crosshair container. The new `ncm_scanner` resource
runs the lock, and `collection.lua` does the only write. The Scanner is also where Chrome hacks will attach
(`IDEA-681`). Offline green: core, DLL tests, and redscript against every installed script. **DEPLOYED TO ONLINE
2026-09-28 17:34 UTC** as `ncm-vision` 0.2.1 with radial 0.1.1 (digest `46cfc058`; 0.2.0 would not load, `KB-182`; backup
`pre-carrier-prod-20260928T172655Z`; see `OPS_STAGING.md`). **Its next action: rejoin (the launcher fetches both packages) and run `MASTER_TEST
§BZ1-§BZ10`, and `§BX` for the radial.** This does not displace the next action above.

Before that, **2026-09-28 (later) - HEALTH NOW REGENERATES; POLICE WERE ALLOWED ALL ALONG, AND WHETHER THEY
CHASE IS NOW ONE CONSOLE COMMAND AWAY FROM AN ANSWER.** Owner: *"player health doesnt regenerate in ncm online
... i never saw a police car come after me. would prefer if they did if thats possible."*

- **`KB-180`, fixed locally.** OPEN//77 health is a server ledger whose regen rate stays at zero until a resource
  calls `Open77.players.setRegen`. freeroam normally does that, NCM doesn't load freeroam, and nothing in NCM
  ever called it. New `ncm_world/server/vitals.lua` sets the new live tunable `playerRegenPerSecond` (default
  **2 hp/s**, so a full pool in ~50 s) on connect, on adopt, and on a 20 s sweep, so a respawn can't strand
  anyone. `players.stats.apply` is added to the manifest.
- **Police (`IDEA-677`/`IDEA-678`), probe built, feature not.** The client log shows `police spawn policy queued:
  blocked=no`, so vanilla dispatch was **permitted**. Twice in that session the platform's map-pin filter
  **denied a police-vehicle pin** (`Zzz04_PreventionVehicleVariant`). A unit may have come with no minimap icon;
  nothing logged proves it either way. NCM *can* force heat with `Open77.players.setWanted`, which
  `open77_prevention` applies on the client. NCM *cannot* read the vanilla heat to react to a crime. The
  console-only `ncm.wanted <id> <0..5>` answers the only question that matters first: do units chase at all?
- **Gate at that point:** `vitals.lua` passed `luac -p`; the then-in-flight Exchange made the full gate red. The
  Exchange is now complete and the whole gate is green, as recorded above.

At that point the next action was deploy + `§BN1`; it now rides the complete deploy named above. `§BV1`-`§BV4`
remain owed, including `ncm.wanted <you> 2` while driving to decide whether `IDEA-677` is buildable.

Before that, **2026-09-28 - THE STREET CALL FORM'S REAL BUG IS FIXED: THERE WERE TWO TRANSPORT HOPS AND
ONLY ONE HAD BEEN BOUNDED.** Owner report: *"f5 panel still broken you said you fixed it. please trace code over
docs."* Tracing the code is what found it, and the docs were wrong in a way worth remembering.

`KB-172`/`L189` was real and is fixed — the form no longer goes out on a 4,032-byte state bag. **But the card
still never drew.** The client received the streamed node list correctly and then called
`Builder.schemaFromWire`, which re-expands it into *both* `start` and `finish` — back to the full **11,515
bytes** — and handed that to the page in one `page:send`. `KB-63`: that bridge drops large messages with **no
error, no return value and no log line**. So the page never rendered, never replied `build:drawn`, and the draw
watchdog closed the card on every press. The schema was reassembled at the last possible moment before the one
hop that could not carry it. That is `KB-178`, and it is the **sixth** instance of the payload-grew-and-vanished
bug.

**The owner was right about the six-page version and the previous write-up was wrong.** It had claimed the
earlier version *"never worked once"*; the owner had seen it render, and it rendered because each step sent at
most five options — a few hundred bytes, under the threshold. **The page count was never the fault.** A size
theory that contradicts an observation is a theory to discard, not an observation to discard. `L181`'s one-form
shape is kept in full.

**Fixed by construction, not by a bigger batch (`L193`): the catalogue never crosses the bridge.**
`client/race_builder.lua` now holds the node list, the form, the cursor and the picker, and sends the page only
what is on screen — at most fourteen form rows or a nine-row picker window, as display strings, with the route
length computed in Lua so node coordinates never cross at all. **No message's size depends on how many nodes
exist**, so there is no size at which this can silently stop drawing again.

**And it gave a WebUI surface back.** `web/build.html` had put `ncm_world` at **8 of 8**
`kMaximumWebSurfaces` (`IDEA-570`) while three transport pages come and go, so `WebUI.create` could also be
refused on timing alone — a second, independent cause underneath the first. On owner direction (*"use venue.html
i dont care just make it work without adding a second page"*) the form is now a block on `web/venue.html`,
shared through the new `NcmVenueSurface`, and `build.html` is deleted. Back to **7 of 8**.

**The interaction model changed as a consequence, and this is the trade to know about.** `venue.html` is
`pointer-events: none` and is never focused — which is what makes it safe to leave attached during a race
(`KB-67`) — so the dropdowns and the mouse are gone. Arrow keys, Enter, Backspace, Delete and PageUp/PageDown
are read in Lua as **physical device reads that need no focus**, and the pad works through the same path; the
keyboard vocabulary was read out of the deployed `Open77.dll` rather than guessed. What that bought is worth
more than the dropdowns: **`KB-61` is not merely handled here, it is impossible — there is no focus to hold, so
there is nothing to soft-lock.**

**`venue.html` also finally has a render harness** (`tools/venue-render-check.js`, **53 assertions**). It had
carried three tenants — the option list, the history/practice panel and the form — with no `guard()` and no
test, which is a large part of why this stayed invisible for a build. It now also covers the option list and the
history/practice panel for the first time. Gate: **ALL GREEN under every interpreter** — `luac -p` over 255
resource files, 219 panel / 55 race / 53 venue / 33 nav assertions, docs authority OK over 79 documents,
`ncm-build -Check` clean.

**THE ONE NEXT ACTION: deploy and run `MASTER_TEST §BN1`, then `§BN33`-`§BN41`.** Nothing here is done —
`§BN1` has now failed live twice for two different reasons, and offline-green is exactly what it looked like
both times. `§BN35` is the row that matters: `form drawn` must arrive within 2500 ms of `opened with 35
node(s)`. If `FORM DID NOT DRAW` appears again, check for a `PAGE ERROR` first; if there is none, something has
started sending the page a payload whose size grows with the catalogue. Per `KB-116` this rides the same deploy
as `L190` (Messages) and `KB-177` (the Carrier port walk). **Commit first — all of this is working-tree only,
which is what `KB-115` is about.**

Before that, **2026-09-28 - THE RIG BRIDGE IS REAL, REBUILT AND NOW ACTUALLY GATE-GREEN; IT IS
INSTALLABLE AND UNPROVEN.** The `L191` build stands up to independent verification. `ncm/rig_bridge/` is a real
independent RED4ext mod — 1,426 lines of C++ plus a 29-line redscript mount boundary, not a stub: generic
DirectInput at 250 Hz, stable instance-GUID multi-device steering/pedal/clutch/button roles, hot-plug
re-enumeration, exact mounted-player vehicle injection through the `UpdateVehicleCameraInput` detour, button
actions via `SendInput`, explicitly armed and watchdog-bounded DirectInput FFB, and a process-tree-guarded
loopback/WebUI control plane on `38520-38523`. Rebuilt clean from a fresh configure, `Query`/`Supports`/`Main`
exported, imports Windows system DLLs only, `ncm_rig_mapping` passes, `dist/ncm-rig-bridge-0.1.0.zip`
(`sha256 9e86c22c…`) assembled. Carrier is untouched on `38480-38483`.

**Three things were not finished, and are now.** (1) `KB-176`: the gate was **red** — document 43's `CURRENT`
banner named no topic and `BACKLOG.md`'s next-free ID had been consumed, so every document claimed green while
`ncm-test` failed. Fixed; `ncm-test` is **ALL GREEN under every interpreter**. (2) `KB-176`: the project had no
`.gitignore`, so 189 build artefacts sat in the commit set, and 149 MB of reference clones in `.tmp-rig-impl/`
with their own nested `.git` were unignored, where `git add -A` would have written broken gitlinks. Both ignored
now; the plugin's commit set is 24 source files. (3) `KB-174`: the three-rung force ceiling `§BU9` promises was
never enforced — the setter and loader clamped to `[0,1]` and the built-in default was 0.35, above the 0.18 top
rung. The ceiling is now one constant in `config.hpp` that the setter, the loader and the reported rung all read.

**One thing is still not built, and it is not a blocker:** `KB-175` / `IDEA-673`. The constant-force channel is
wired and advertised in the panel but nothing ever feeds `feedback.collision`, and `feedback.road` is filled and
never read. **Spring and damper are genuinely fed; road texture and collision jolts are not in 0.1.0.** The owner
chooses between feeding them and deleting the plumbing.

**Nothing has touched hardware and nothing is deployed.** The one next action is unchanged and is
`MASTER_TEST §BU1-§BU3`: install with FFB disarmed, cold-launch the exact Online client, and bind the exact
G29 + separate Thrustmaster pedals + ESP32 rim by the GUIDs in the log. Read `§BU9` with `KB-175` in hand.
Before any of it, **commit** — all of this work exists only in the working tree, which is what `KB-115` is about.
The external companion stays available until native input and output both pass `§BU`. Document 43 is CURRENT
(*physical rig input and force feedback*); `IDEA-672` is the product row.

Before that, **2026-09-27 - MESSAGES READS LIKE A MESSENGER (`L190`). The tray of recent messages is
deleted and incoming lines now arrive.** Two owner complaints about one surface: the bottom pane was *"terrible
and intrusive, not how a real messaging app works"*, and the messaging was *"instantaneous right now and i cant
always tell what the newest message is"*. The first had a real defect under it (`KB-173`): the tray was fed by a
query with **no `thread_id` filter**, so it showed the twenty newest rows in `message` whatever thread they
belonged to -- the open conversation duplicated underneath itself, interleaved with everybody else's lines and a
seat offer. A notice is now a thread from its sender with `ACCEPT` / `DECLINE` in the composer; lines appended to
a transcript already on screen arrive one at a time behind a typing indicator with no reply offered until the
contact has finished; and time is legible (stamp on a gap, clock on the newest bubble only, `NEW` rule where
unread begins). History still draws at once. `tools/panel-render-check.js` grew real queued timers and class
selectors to assert any of it -- 219 assertions green, whole gate green, `ncm-build -Check` clean. **NOT
DEPLOYED; `§BT` owed.** Per `KB-116` it rides the next deploy alongside Street Call's fix.

Before that, 2026-09-28 - **THE WORLD CAN TALK TO THE PLAYER. The quest graph's first slice is built
(`L183`): Dex, Setup Stu and Rico, with Messages rebuilt as a conversation surface inside the F6 shell and F9
released.** Migration 039 widens `message.from_kind`, which was *the* single schema blocker that had kept every
character in NCM Online mute. Three new core modules (`graph.contacts`, `graph.conversation`, `graph.opening`),
one host adapter, one new host harness. **DEPLOYED ONLINE 03:05 UTC; migration 039 applied and verified in SQL**
(`§BQ1`, `§BQ2` PASS). The deploy paid for itself immediately by exposing `KB-168`: **a nil SQL parameter is a
HOLE to OPEN//77's bridge, not NULL**, which had broken four of the new statements outright and two older ones
nobody had noticed — message-exposure pacing had been failing since migration 036, and the `ledger` payout line
was raising an **uncaught** error that aborted settlement transactions, so placement money, field bonuses and
clean-driving bounties were **never paid**. All three fixed and redeployed in the same session. Before that the
same day: wear profile v1 was rejected by its first Online observation (`KB-166`) and profile v2 is staged but
awaits an empty restart (`L182`); players can CALL THEIR OWN RACES (`L179`, `L180`, `L181`), deployed, §BN owed;
component Wear & Tear was built (`L178`), migration 038 deployed, §BM partly owed. Earlier: the ambient population
service (`L177`, not deployed), Economy v1 (`L169`, not deployed), lap ghosts and Parts on the previously deployed
tree with their live sections still owed.

**STREET CALL WAS BROKEN FOR EVERY PLAYER AND IS NOW FIXED IN THE TREE, NOT YET DEPLOYED (`KB-172`, `L189`).**
`§BN1` was run live at 03:23 UTC and failed: F5 produced no card on any of eleven presses, with no chat, no
error and nothing in either log that named a fault. The key, the page, the focus handshake and the server's
decision were all fine. **The form was published into a player state bag of 11,515 bytes against a 4,032-byte
ceiling (`IDEA-509`), so the platform discarded every single write** -- and it had never worked once, for
anybody, since the feature shipped. `schema.start` alone was 5,579 bytes because the 35-node list was sent
twice, once as `start` and once as `finish`, for one sentinel's difference.

It is the **fifth** instance of the bug class `ncm_league/server/stream.lua` was written to end (`KB-59`,
`KB-86`, `KB-153`, `KB-160`) and the first to reach a player: the transport already existed and a new feature
simply did not use it. The form now streams over `ncm:build` (419-byte head + one 5,496-byte packet), the node
list travels once, `NcmStreamRx` is a shared client receiver, and `/ncm.call` -- named as a durable route in
three documents and never actually registered -- exists. 738 core tests green, `ncm-build -Check` clean.
**`§BN1`-`§BN4` are owed on the next deploy**; per `KB-116` this fix cannot be deployed on its own anyway, so
it rides whatever goes up next. `IDEA-669` asks the gate to assert payload size so there is no sixth instance.

**Note for whoever deploys next:** at 23:40 local the concurrent session was mid-edit in
`ncm_world/web/panel.html` and `tools/panel-render-check.js` was failing (`msgTray is not defined`, then the
harness itself throwing). That is their in-flight work, not Street Call's -- but `KB-116` means a deploy ships
it, so **re-run the whole gate green before deploying, not just the core tests.**

**Also assessed 2026-09-27: Carrier never replaced `NCM-Wheel-Support.exe` (`L185`, `KB-169`, document 43).** Its
rig path is disconnected scaffolding: no device poll caller, no controls consumer, no command producer and no
vehicle detour. One in-process SDL/HID diagnostic also failed to acquire the G29, Thrustmaster pedals and ESP32
rim (`KB-140`), but `L186`/`KB-170` correct the first assessment's overreach: that is evidence against the exact
attempt, not against a fully in-process solution. A completed source trace now supplies positive precedent: one
working SDK/pump/detour/FFB RED4ext wheel mod, its DirectInput fork with independently selected wheel and pedals,
and a separate Windows.Gaming.Input mod for multiple arbitrary controllers. Owner direction: **do not reopen
Carrier, and do not make Rig Bridge Logitech-only** (`L188`). A separate multi-vendor NCM Rig Bridge owns the
local high-rate hardware/input/FFB product; Carrier stays the machine-effects mod. Nothing was built. The bounded
next rig action is an in-process read-only P0 that composes the owner's G29, separate Thrustmaster pedals and ESP32
rim using those source-verified provider patterns and preserves stable device identity. This research does not
displace the live queue below.

> **Claim before writing:** decisions through **L227**; MASTER_TEST through **§CH**; next QA letter **§CI**.
> BACKLOG next free **IDEA-752**; known issues through **KB-214**. Read ledger tails before allocating.
> BACKLOG next free **IDEA-686**; known issues through **KB-186**. Read ledger tails before allocating.
>
> The next-free guard matters: overlapping 2026-09-26/27 sessions previously made this block stale several
> times (`IDEA-380`). The docs gate asserts ID uniqueness and the BACKLOG next-free line.

**Also built 2026-09-27, by a session running alongside the quest-graph work: OTHER DRIVERS ARE ON YOUR MAP AND
MINIMAP (`L184`).** The owner asked whether player locations could be shown; the answer was yes, needing no new
permission and no new WebUI surface, and the **city tier** was ruled and built — one slow pin per driver in your
routing bucket from `Open77.players.positions()`, a `/ncm.players` toggle, and the whole layer stood down while
you are racing. The **field tier** (pins attached to a streamed rival during a session) was refused by the same
ruling and must not be built back in by accident. Core `world.presence` + 19 assertions, whole gate green.
**NOW DEPLOYED ONLINE 2026-09-28 03:05 UTC** — it went up with the quest-graph deploy, because
`deploy-staging.ps1` syncs every resource and `ncm_world/open77.lua` already declared it; the boot line
confirms `world.presence` among the loaded modules. It was **vendored** as part of that deploy, which it had
not been (`KB-159`'s shape: the manifest declared `shared/core/world/presence.lua` and the file was absent, so
`ncm_world` would have failed to start). `§BR` is still owed and needs **two clients**. `§BR4` is the open question worth answering while
somebody is there: whether `CPO_RemotePlayerVariant` renders on the minimap, the map, both or neither
(`IDEA-653`). One documentation defect fell out of the two sessions overlapping: `KB-168`.

**Also fixed 2026-09-27, by a third session running alongside those two: SAFETY RATING IS NO LONGER A SHAM
(`L187`, `KB-171`, settling `IDEA-090`).** The owner's diagnosis was arithmetically exact — a clean session paid
**+0.05** against **-0.10 per severity band uncapped**, so one light tap cost two clean races, the observed
two-human race cost **-0.80 and -0.90** in a single start each, and the 5.0 → 10.0 climb needed **100 flawless
starts, about 14 h** at the observed cadence of 21 per 3 h (`KB-165`). Worse, scenery was weighted exactly like
another driver, so in Night City the dominant input to a *safety* rating was wall contact by somebody who never
touched anybody. **Removal was the owner's stated alternative and was rejected on cost:** SR is load-bearing in
`L54` (the only dimension that may gate entry), `L44` (NCX eligibility), `L38` (splitting a field) and `P39`
(which hands griefing to the badge so incident scoring can stay zero-fault). Four rules now govern it — gains
scale with the distance raced clean (0.05 + 0.03/km, capped 0.30); car-to-car contact costs 0.06 per band and
scenery 0.35 of that with one band per session free; no session may cost more than 0.50; and a bare incident
count with no records is charged as car contact, so a detector gap can never read as good behaviour. The
observed -0.80 race becomes **-0.147**, recovered by one clean 6 km race. One core module and one host line;
no migration, no schema change, no command, no touch to incident detection or corrected time. Whole gate green
under both interpreters, `ncm-build` vendored. **NOT DEPLOYED. `§BS` is owed** — and it is **blocked in
substance on `KB-34`**: until §BS5 shows `kind=car` with `other` populated, every SR number anybody reads is a
scenery number and the car-contact half of the rebalance is untested outside its fixture. Residual tuning
questions are parked in `IDEA-666` rather than guessed twice.

## One next action

**Deploy and run MASTER_TEST §BQ1, then §BQ3-§BQ9.** In that order, because `§BQ1` gates everything else:
migration 039 widens `message.from_kind` from three values to ten, and **if that ALTER does not land, every
character line fails its INSERT and the Messages surface is simply empty** -- with no error a player could see and
no line in the log that says why. Confirm the migration line, then confirm in SQL that the column accepts
`'character'`.

Then the four steps that prove the whole shape in about two minutes: join a fresh driver and wait ~20 s for Dex
(`§BQ3`); press **F6** and confirm MESSAGES sits between WHEEL/PEDALS and HELP (`§BQ4`); press **F9** and confirm
**nothing happens** (`§BQ5`); pick *"Put me through"* and confirm **Rico appears AND has actually spoken**
(`§BQ9`) -- not merely that his name is in the rail. That last one is the regression guard for `KB-167`(a), where
the §20 budget rationed away the introduction the player had just asked for.

**Then §BQ19-§BQ23, which is the section worth the most.** Ask Stu about hardware five or more times, keep
playing, and see whether **Rico** brings it up unprompted twenty minutes later. Nobody told him; it was Stu's
conversation. That is the draft's own headline example of a living social web (§0.7, §23), it is the one behaviour
no offline test can prove, and §BQ23 checks the other half -- that he does not then say it again on every
heartbeat.

**What to distrust.** Everything here is proved against doubles, and a double will cheerfully report that a
message was written. The three things a live server can contradict: (a) the ALTER, per above; (b) **pacing** --
`§BQ19`'s "five or more" and the 20-minute cooldown are `TUNE` first guesses from §21, not measured numbers, and
`KB-165`'s lesson is to multiply a per-event rule by the real cadence before believing it; (c) **focus** --
`§BQ34` restarts `ncm_world` with MESSAGES open, which is the one failure that costs a reconnect (`KB-61`), and
this surface has never taken focus before.

**Do not skip §BQ26.** Look hard at the whole surface and confirm there is no count, fraction, percentage or
score anywhere. The hidden hardware-curiosity score and the open-lead count are **server numbers** (`L171`,
`L175`, §3.4); both harnesses walk the payload and assert it, but the harnesses cannot see CSS or a stray label.

**Everything else in `41_QUEST_GRAPH_PASS1.md` is still SPEC and must not be built.** `L183` authorised Appendix
A.8 and nothing more. The fifteen unauthored contacts each carry their blocking reason in `graph/contacts.lua`,
so that list is code rather than prose -- read it there before starting anybody new. The honest next character is
the **#1 Fan** (`IDEA-655`), whose trigger data already exists in Race Tags and whose only real open question is
one line of copy: the draft's *"P8. Seven passes. P1."* cannot be written truthfully, because NCM Online does not
count overtakes.

**One process note, because it paid for itself immediately.** `tools/test-quest-graph.lua` found three real
defects within minutes of existing (`KB-167`), all of them in the adapter between authored data and the database,
and none of them reachable by the 70 offline assertions over the core modules. That is the same gap as `KB-159`.
A `tools/test-*.lua` joins the gate by existing; write it before the adapter, not after.

## Still owed from previous sessions

**Press F5 on Online and run MASTER_TEST §BN1-§BN18** -- open the Street Call form, set a finish, post it, and
walk to your own improvised start,
and check that the `CALLED` line appears in the server log. It is deployed and completely unobserved: no card has
ever been drawn and no impromptu event has ever existed on any world.

Two things to notice in the same session, because they cost nothing extra: the venue entry panel and the live
race graph are both on the **right** now (§BN24-§BN26), and **F5 may collide with something** -- if it does,
`/ncm.build` is the durable route and the collision is `IDEA-646`.

§BK (Race Guide transport) is still owed and is the next thing after this. Ambient population is built but
**not deployed**, so it displaces nothing.

**Then, when the world goes up next: §BL3 is the single most likely thing to be wrong.** Everything about ambient
population is proved offline against doubles, and a double will happily report that `joinTraffic` was called. Only
a live client can say whether the cars actually *drive*. **§BL9 and §BL9b are the `KB-165` regression guards** -
the city away from a race must stay populated, and a slot nobody entered must hold no road at all.

**The Race Guide broke for the third time, and it is fixed and deployed (`KB-160`, 19:43 UTC).** The owner saw no
races and a 1969 date. The date was the misdirection -- the panel had never been told anything at all, and an
unseeded clock is `new Date(0)`. **The server log now proves both halves of the story:** `19:10:13 … rows=16
bytes=21287` on the old build, `19:48:30 … rows=17 bytes=22574 head=385 packets=5` on the new. 22,574 bytes is the
payload that was disappearing; the same 16-17 rows measured 16,826-17,918 bytes before Economy v1's per-row
`economy` block. The real fault was that the **server-to-client hop had never been bounded** -- only the WebUI
hop -- so no amount of measuring would have saved it.

**Read these two lines, in this order:** the server's `guide published … packets=<n>`, then the client's
`ncm:guide stream complete … rows=<n>`. The counts must agree. Then check the clock shows today, not 1969.

**Every list payload is bounded now, not just the Guide** (`IDEA-595`, `server/stream.lua`). Guide, Guide results,
Inbox, Machine Index and Parts inventory all send a head plus byte-budgeted packets through one sender, and the
client reassembles them through one receiver; the whole-payload receivers survive for one mixed-version restart
window and can then go. `partitionBytes` packs by measured bytes because a row-count budget cannot see rows that
grow, which is what broke `KB-86` and `KB-160` at the identical seventeen rows.

Then the previously owed live work, undisplaced: §BJ for Economy v1 on Online, §BI2 (two time-trial runs -- the
first stores the ghost, the second is the first that can show it), §BH for Machine Knowledge, §AZ for Parts, plus
twice-applied migration dry-runs for 033-035 and 038 when `NCM_DB_ROOT` is available.

**The offline harness is the real finding here.** `tools/ncm-stub.lua` is not in the gate, and **six of its
seventeen scenarios fail at HEAD** -- verified against a clean worktree at `b5a68ec`: `onboarding`, `inbox`,
`holding`, `telemetry`, `incidents`, `tworace` (`IDEA-597`). These are the scenarios that drive the real resources
end to end, so NCM's most valuable offline coverage is mostly dark, and that is how a Guide transport regression
shipped unnoticed. `guide`/`guide2` were repaired as part of this work -- they now reassemble the real stream and
assert every packet and head against the ceiling -- and the stub's SQL double now models `ledger` and `entry`, so
Economy v1's funded check-in can actually succeed offline (`IDEA-596`). Fix the other six, then put the stub in
`tools/ncm-test.ps1`: unrunnable coverage is worse than none, because it reads as coverage.

**Economy v1 is ON ONLINE, not only local.** Migration 035 applied at 16:55 UTC in the same deploy that carried
the `KB-156` fix, because `deploy-staging.ps1` ships the working tree rather than a selected change. The owner
accepted that promotion. So §BJ runs against Online: confirm boot, then starter balance, paid/denied/duplicate
check-in, solo and contested settlement, qualifying-without-payout, clean and dirty Tags, repeat floor,
abort/restart refunds, unique-Badge rewards and explicit Research submissions, reconciling receipts, typed
ledger rows and balances in SQL.

The rest of the live queue is not displaced: §BH for Machine Knowledge, §AZ for Parts, plus twice-applied
migration dry-runs for 033-035 and 038 when `NCM_DB_ROOT` is available.

## Street Call: players build their own races - BUILT AND DEPLOYED 2026-09-27 (`L179`, `L180`, `L181`, `IDEA-641`-`IDEA-649`)

> **`L181` REPLACED THE INTERACTION THE SAME DAY IT SHIPPED, and that correction is the useful part of this
> entry.** The first build was a faithful port of single player's six-step Foreman machine and the wrong
> product: it could only start a race at an authored node -- so *race, here, now*, the entire premise, was the
> one thing it could not express -- it offered four routes out of 35 places, it asked which discipline the
> driver wanted when only one can be enforced, and it took six pages to do it. It is now **one form**: the
> start defaults to **where you are standing** (becoming a temporary node, swept afterwards), every
> race-legal node is offered for start, finish and up to eight chained checkpoints, and the type is never
> asked. The event plumbing described below was right and is unchanged. **Cost: the last free WebUI surface**
> (`IDEA-647`) -- a form with dropdowns needs focus, and `venue.html` must never take it.

**The owner's ask:** *"before continuing the PvE, we need the ability for players to set up races themselves as
outlined by Quickie and Foreman to be implemented."*

**`G2` is answered, and single player answered it.** `G2` had been OPEN since `L170`, framed as a conflict: the
`venue_options` ruling forbids trees, and Foreman's constructor is a six-step wizard, so one of them had to give.
Neither did. **Foreman's builder is not a tree** -- `race_commands.lua` keeps the whole constructor in one integer
(`ncm_foreman_builder_step`) and `MTEJournalHandler.reds` renders each step as a flat list of final acts filtered
by it. Choosing "sprint" writes one field and increments a counter. A step machine is not a tree, so the ruling is
satisfied rather than scoped away.

**What shipped.** `competition.race_builder` (pure, 25 tests) is the recovered machine, re-cut for Online:
discipline → class → route → launch → when → summary. Two SP steps are dropped on purpose and say so in code
(`M.OMITTED`): **field size**, because Online fields are human and the field is whoever turns up, and
**difficulty**, whose only job was setting AI tier bands. Class replaced it, because what cars are admitted is the
real lever with a human grid. `route` gained a meaning it did not have in SP -- the nearest suitable starts to the
creator, which is what `P12`/`P17` meant by *"from wherever they stand"*.

**`impromptu` had been authorised since day one and never built.** It has sat in the `EventClass` enum and the
`event.class` column with **zero code on either side of it**. `NcmCalendar.adopt` is the non-cadence route that
`organized` already proves, so no new scheduling concept was needed -- which also answers the standing objection
that the calendar cannot represent an ad-hoc race. It cannot *materialise* one; it can adopt one. **No migration.**

**Three deliberate limits, all in the file header so nobody mistakes them for gaps.** Not invitational (announced
server-wide, entered on the mark, `venueRadiusM = 60`). **Not paid** -- `economy` is nil, because two friends
alternating wins is a money printer and the economy is younger than this feature (`IDEA-643`). Not free of cadence:
`impromptuCooldownSec` 900 bounds one driver and `impromptuMaxOpen` 2 bounds the board, and the second is not
redundant because five drivers each obeying the first would still fill it (`KB-165`).

**`L180` moved three surfaces off the centre of the view**, on one rule: while a player is on their mark or
driving, the middle of the screen is the road. The Street Call card is drawn on `web/venue.html` -- the page that
already holds the ring entry panel -- which makes *"no bigger than the race-entry panel"* structurally true rather
than a number to maintain, and spends **none** of this resource's eight WebUI surfaces. The race graph is
**mirrored, not shifted**: its labels are `nowrap` and overflow the box on purpose, so a right-hand graph with
rightward labels would push driver names off the screen.

**The weakest part, stated plainly: F5.** `KB-62` says three of four NCM function keys collide, that the
collisions move, and that the fix is one binding plus in-page tabs. This could not follow that advice -- the
owner's constraint was that calling a race must not require the F6 shell -- so it took a fifth key chosen against
a stale audit. `/ncm.build` and `/ncm.call` are the durable routes; the re-audit is `IDEA-646`.

**Nothing here has been seen.** No card has been drawn and no impromptu event has ever existed on any world.
**§BN** is the whole of it, 26 rows, and §BN1 is one keypress.

## Component Wear & Tear - BUILT 2026-09-27 (`L178`, `IDEA-631`-`IDEA-634`, `KB-163`)

The owner accepted the odometer as trustworthy and directed Wear to ship now, with Hard / Medium / Soft tyres
later. The complete first-generation distance lifecycle is built locally and **not deployed**; §BM is the live
acceptance contract. This does not displace §BK as the one next action.

- Core `parts.wear` derives condition/severity from immutable exposure, physical asset identity, versioned family
  profiles and append-only service relief. It stores no health, condition or severity and rolls nothing at runtime.
- Eight families wear. Aero, structure and chassis still record exposure but have no routine mileage consequence.
  Tyre compounds and component-keyed thermal swap semantics remain deferred exactly as requested.
- Active conditions feed downward-only grip/drive/brake multipliers into the existing named `wear` layer and sole
  `parts.handling` composer. The Parts Inventory exposes named conditions, service count and priced service without
  exposing thresholds or health percentages; the race HUD shows compact master/system warning marks.
- Migration 038 adds append-only `component_service`. Network service commits one money row and one service row
  transactionally and idempotently, advances the named threshold by bounded `relief_m`, and never alters exposure.
- `KB-163` is fixed locally: fit and installed-part service checkpoint the outgoing configuration first; a failed
  write retains the pending accumulator and refuses the operation. Live sub-250 m attribution proof is §BM3/4.
- Full gate: **614 core tests per interpreter**, 57 cross-scope, 17 QA observer, 35 vehicle access, 238 resource
  files syntax-clean, panel/nameplate/race/nav render checks **157 / 26 / 55 / 33**, all green.

## Ambient population and the race corridor - BUILT 2026-09-27 (`L177`, `IDEA-635`-`IDEA-639`, `KB-164`)

The world is inhabited. `ncm_world` now spawns its own pedestrians and lane traffic around connected players and
clears them out of a race corridor before a start. **Offline-green, undeployed, §BL owed.**

- **The starting instruction was right and the reason matters more than the feature.** The owner said that if
  anything in our docs claims AI traffic is not server-side, it is our own stale writing. It was. `KB-162`
  corrected half of it three days ago; the other half survived untouched and is now `KB-164`. The oracle that
  settled it was **the shipped server's own binary** - `Open77.Server.Scripting.dll` embeds the documented Lua
  prelude as strings, so the installed `2.31.13+op77.102` build answers what the devkit index (pinned at `.78`)
  cannot. That is a reusable move, and cheaper than every other thing tried this week.
- **Two population systems, and conflating them is what caused the error.** The vanilla **density switch** is
  server-owned and replicated per routing bucket (`Open77.world.setPopulation`, `world.population`; `crowd` is a
  real multiplier, `traffic`/`police` are binary and `getPopulation` says so). The vanilla **entities** are
  per-client: nothing on the server can name, move or remove one, and two players on one corner are not looking
  at the same cars. So a race corridor can only be cleared of entities **we** created - which is the whole
  reason the server-owned layer exists, and the thing that makes the world *shared* rather than merely busy.
- **"Despawn in a non-player-visible radius" is honoured with two signals, not one.** A corridor despawn needs
  the projection read (`Open77.npcs.owner(id).readyClients`, which is exact - zero means no client is drawing
  it) **and** a distance past every player's streaming radius. An unknown projection state counts as watched.
  An entity that fails the test is **deferred and reported**, because a corridor that is not clear yet looks
  exactly like one that failed. A car blinking out in front of a driver at racing speed is the failure this
  rule exists to prevent, and it is the one thing no amount of offline testing can forgive.
- **The corridor is the whole lap.** It is a capsule around the route polyline - start, authored intermediates,
  finish - so `ncm_league`'s calendar publication now carries the finish's **coordinates** and the intermediate
  list, not just a name. A radius drawn round the grid box would clear where the cars line up and leave the rest
  of the route exactly as busy as it was.
- **These are not AI racers.** Nothing spawned here enters a session, is scored, or appears in a result. The
  goal is that the courier on the corner is in the same place for two players.
- **The vanilla half is NOT used in the shared world, and `KB-165` is why.** The first version defaulted it on.
  The owner asked the obvious question I had not - *there is always a race, don't you see a conflict?* - and the
  arithmetic is brutal: the five shipped street series run 20/30/60/180-minute cadences at staggered offsets,
  **21 starts in any three-hour window**, and the per-slot hold intervals merge into **one continuous interval,
  100% of the clock**. A bucket-wide switch in a world with a race every twenty minutes is a **permanent**
  switch, so the service would have emptied Night City for good - its own purpose, inverted, by itself. The
  guard is now **structural** (`maySuppress`), not a setting: the shared bucket is never suppressed for a
  corridor, because the switch has no radius and the corridor does. A bucket a race has to itself still is,
  which is exactly `IDEA-638`'s case and now a reason to want it.
- **And a corridor is only held for a race that is really going to happen.** A scheduled slot with **no
  entrants** holds nothing, and a scheduled row stops holding 120 s past its own start - long enough for the
  T-60 session to form and take over - instead of guessing a length for a race that may never have begun.
  Without this, empty slots would have stripped every published route of ambient life too.
- **Evidence:** full gate green under both interpreters. **52** core director assertions (`test_ambient`),
  **40** host assertions against platform doubles (`tools/test-ambient.lua`), and a new `ncm-stub ambient`
  scenario driving the real `ncm_league` publication into the real `ncm_world` service across two Lua VMs -
  mutation-checked against a shrunken corridor and against a race nobody entered.
- **`KB-165` is the one no test would ever have caught, and that is the finding.** Every assertion in all three
  layers looked at **one** race. The defect only exists when you multiply one race by the calendar, and I had
  the bucket-wide limitation written down correctly in three places while never doing that multiplication.
  A constraint recorded is not a constraint applied.
- **Three defects the tests found in my own work, worth recording because none was a typo.** The corridor was a
  union of discs on densified points, so its true half-width collapsed to 54 m mid-segment - on the longest
  straight, where closing speed is highest; it is a capsule now. The budget rule flagged *every* survivor as
  deferred whenever the furthest few were watched, because nothing came off the live count to end the
  condition; the excess is counted once, up front. And the reclaim rule ignored an explicit "a client is
  rendering this", which contradicted the one promise the whole service makes.
- **Two of the tests were passing for the wrong reason and were rewritten, not accepted.** The stub's corridor
  assertion survived shrinking the radius to 1 m - the fixture had put everything *exactly on* the racing line,
  where a corridor of any width clears it; it now sits 50 m to the side and the mutation fails as it should.
  And a no-pop-radius assertion measured where entities *were* rather than where they were *born*: an ambient
  car on `joinTraffic` drives, and driving past the player at 100 m is the behaviour, not a violation.
- **`tools/ncm-stub.lua` gained the server-side `Open77.world`, `npcs.owner`/`get`/`ai`/`damage`,
  `vehicles.owner` and `resource.name`,** plus a tunable-override layer so ambient is **off** by default there:
  it spawns on a timer, and every scenario that counts what is in the world would otherwise count the city too.

**Follow-ons, none of them blocking:** `IDEA-636` real pavement/lane geometry instead of a ring around the
player (35 curated road nodes is coarse flavour, and a ped can settle onto a parapet); `IDEA-637` time-of-day and
weather grading of `crowd`; `IDEA-638` the race-bucket decision above; `IDEA-639` letting ambient NPCs witness
things, which is tempting and easy to overdo - **do not build it before §BL passes**.

## Parts behaviour and Wear & Tear expansion — 2026-09-27, design only

[Document 42](42_PARTS_BEHAVIOR_AND_WEAR_EXPANSION.md) maps all eleven deployed Parts families beyond flat
`effect` scales, defines a relative Hard/Medium/Soft plus rain-compound tyre model, reconciles stress-aware Wear
with `L120`'s immutable exposure / pure-derived condition / `relief_m` decisions, proposes a compact system-warning
taxonomy and traces persistence, service, used-parts economics and pacing. It is **PROPOSAL only**: no schema,
balance, UI, runtime or production behaviour changed, and no decision was added to the decision record.

The smallest coherent architecture is one immutable behavioural profile layer, a few shared context reducers,
component-local state and the existing `parts.handling` composer — not eleven family engines. Tyres are the only
recommended first complete slice. The pass also found `KB-163`: the 250 m / 60 s pending odometer accumulator can
cross a fit transaction and credit the incoming part for distance driven on the outgoing one. Fixing and proving
that accounting boundary is a prerequisite to any Wear consequence, but does not displace the live queue.

## Economy v1 - deployed to Online 2026-09-27 16:55 UTC (`L168`, `L169`, document 40)

- Launch now has a genuine one-human income loop. A scheduled field of one uses time-trial completion/target
  economics and never receives P1; fields of two or more use contested completion, placement and field bonuses.
- Free practice and qualifying mint nothing. Scheduled paid events freeze their authored economics, charge at
  check-in, and settle through one idempotent transactional service with itemized receipts.
- Street begins at €$50 entry, €$250 solo completion and €$300 contested completion. GT and Hypercar use authored
  10× and 100× scales; NCX is sponsor-funded with free entry. All numbers remain observable tuning data.
- Repeating the same route/economy opportunity in its window receives the authored repeat floor instead of an
  unlimited first-completion payment. DNF/DNS/DSQ receive no purse.
- Race Tags are factual first: the runtime evaluator emits all qualified facts separately from its capped display
  set. Settlement consumes only an authored allow-list and cap; initial money rewards clean driving, not negative,
  contact, penalty, placement-duplicate or position-manipulation Tags.
- `/ncm.research` lists and submits finite personal-first physical identity and server-measured capability
  evidence. Catalogue exposure and incremental maxima/configuration revisions cannot farm money.
- Existing first-finish, first-time-trial and first-win accomplishments pay €$100 / €$100 / €$300 exactly once,
  after progression persists. The five-tier Badge reducer is not built.
- Cars and serialized Parts remain the principal progression sinks. Player trade will redistribute existing
  assets/value; fuel should follow measured event economics and retain a bankruptcy road back.

## Character / message archaeology and the lightweight PvE substrate - 2026-09-27, reconnaissance only (`IDEA-598`-`IDEA-615`, `KB-161`, `L170`)

A third read-only pass ran alongside the live queue and **changed no production behaviour**. It recovers the NCM
**single-player character/message system** from its shipped implementation, maps it onto NCM Online, and returns the
structured material needed to author a world graph. Full document:
[docs/research/open77/CHARACTER_ARCHAEOLOGY_AND_PVE_SUBSTRATE.md](../research/open77/CHARACTER_ARCHAEOLOGY_AND_PVE_SUBSTRATE.md).
**Nothing in it was measured in-engine**, so nothing in it is a live PASS; it uses the same PROVEN / AVAILABLE /
PLAUSIBLE / BLOCKED / UNKNOWN ladder as the presentation audit. Platform claims are build-pinned cards answering
for **op77.78** while staging runs **.102**.

- **The SP characters were never the system.** Seven phone contacts (Dex, Quickie Quinn, Foreman, Setup Stu, Rico,
  BookQueen Billie, #1 Fan) are *routing channels* onto `race_commands.lua`, which also answered to F6 and to
  console commands. There is **no dialogue tree**: `ShouldActivateChoiceEntry` is a pure function from quest facts
  to the visible choice set, and an inapplicable choice is **absent, never greyed out** - the same law
  `competition.venue_options` later wrote down independently.
- **The biggest find was not in the brief: DCES.** `contact_events.lua` is an event-driven, budgeted, deterministic
  off-screen character layer - 12 declarative archetypes, 19 named actors in 5 pools, `MAX_ACTIVE_EVENTS=2`, a
  race-gap cooldown, permanent event keys, and outputs that are narrative *and* mechanical. **It is the lightweight
  authored PvE substrate we are looking for, and it already shipped once** (`IDEA-598`).
- **Messages is not "historical work" - it is deployed and in use.** Migration 006's `message` table already has a
  generic sender (`from_kind`/`from_id`), per-message `actions`, `ref_kind`/`ref_id`, `expires_at`, authoritative
  unread state, a `panel.html` mode on **F7**, chat twins, and the `KB-97` privacy fix. **One `ALTER TABLE` on a
  three-value ENUM is the only schema blocker** stopping characters, Dispatch, markets and manufacturers from
  writing to players (`IDEA-599`).
- **Quinn and Foreman already share one race object.** `Racing.openQuickRaceConfig()` *is*
  `Racing.openConfig({sourceType="quick_race"})`; `sourceType` only picks which defaults get seeded. The
  "constructor that opens pre-filled" is **the removal of a UI accident, not a redesign** (`IDEA-602`). The real
  gap is elsewhere: `calendar.materialize` is pure and cadence-derived, so an ad-hoc race **cannot be represented
  at all** (`IDEA-603`).
- **Physical NPCs are far nearer than assumed.** `Open77.npcs` is 36 server + 6 client natives, `npcs.tasks` 27
  more, **`ncm_world` already declares `world.npcs`**, and `npcs.speak` plays a line from the NPC's own voiceset -
  so a text-first contact can still bark. The one UNKNOWN is the prompt/dialogue surface, and it is budget-bound:
  one spare CEF page (`IDEA-605`).
- **Ambient population is still an unpulled lever:** NCM has **never** called `setPopulation`, `traffic` is a
  **binary switch** in 2.31, and the platform's card and guide **contradict each other** about the unconfigured
  default. Run `Open77.world.getPopulation(bucket)` on staging (`IDEA-606`). **-- ANSWERED AND SUPERSEDED
  2026-09-27 by `L177` / `IDEA-635`.** `setPopulation` is now called every tick, per bucket, and `ncm.ambient`
  prints a live `getPopulation(0)` read, which settles the card-versus-guide contradiction the first time it
  runs. What this bullet did **not** say, and should have, is that the switch is *server-owned and replicated*
  at all -- `KB-164`.
- **I got shared traffic wrong, and the owner caught it (`KB-162`).** The pass reported shared AI traffic as
  **BLOCKED** three days after OPEN//77 shipped it - the 2026-09-24 changelog leads with *"Traffic Sync: Shared AI
  traffic is now in."* Two compounding errors: I conflated vanilla *ambient population* traffic (genuinely
  per-client) with **shared AI traffic built from server-created canonical vehicles** (`vehicles.ai.joinTraffic`,
  available since op77.57, whose guide says it *"uses indefinite road-following, not ambient population
  spawning"*); and I read a **24-build-stale index** (`.78` vs staging `.102`) reporting no card as the platform
  saying no. Corrected in place; `IDEA-607` superseded by **`IDEA-616`**. **The rule: a BLOCKED verdict needs a
  positive source, never an absent card.**
- **Billie recovered in full**, including a real softmax book with an 8% overround, escrow, purse-capped loss
  clips, and risk-weighted streak tickets. The portable core is **self-paper**: stake is derived from
  `maxStake(tier) * ratio`, so exposure is bounded by **progression rather than wallet**. Nine multiplayer exploit
  surfaces are catalogued, the sharpest being **record shaping** - the moment she prices *your* probability from
  *your* record, losing on purpose becomes profitable (`IDEA-610`).
- **`KB-161`:** her tier-progression risk term has been dead for every SP player above Gonk, because `betting.lua`
  and `careers.lua` disagree on the tier vocabulary and the lookup has an `or 0.0` default. Same lesson as
  `KB-155` - a guard that cannot report having fired is indistinguishable from a bug. **Not fixed**; this pass
  changed nothing.
- **Two of the three owner decisions were taken the same day; one is still open.** **G1 - DECIDED (`L171`):**
  the sixteen-slot `???` market roster is approved and **supersedes `17_MARKET_NETWORK.md`**, which is CURRENT
  and forbade it by name. Document 17 is **amended in place** in three places, not silently overridden, and the
  **leak condition survives** - the count is now deliberately disclosed, nothing else about an undiscovered
  market may be. Market authoring is unblocked. **G2 - still OPEN:** `venue_options`' "final acts, no trees"
  ruling means a six-step constructor cannot live at a world prompt; owner will return to it, and it blocks the
  surface design of `IDEA-602`/`IDEA-603`. **G3 - DECIDED (`L172`):** self-paper only; NCM never quotes odds on
  another player, so the SP winner board does not port and exploit E7 is disposed of by construction.

Nothing here displaces the live queue above. The cheapest items are additive and reversible: the ENUM widening
(`IDEA-599`), wiring the already-written `player.communication` to the already-deployed bus (`IDEA-600`), porting
the SP voice validator into the gate (`IDEA-601`), the `getPopulation` read (`IDEA-606`), and a few shared
traffic cars on one route to measure density cost (`IDEA-616`).

**The owner then supplied the `op77.102` server package, which settled part of it and corrected my own advice
(`KB-162` amendment).** `.102` has **no traffic resource either** - the resource set is identical to `.87` - so
"read the traffic resource" was never an available action. What it does ship is operator documentation never
shipped before: `server-configuration.md` documents the `replication` block behind the motion-lane work
(`trafficLanes`, `timedMotionWindowMs`, `timedVehicleValidationTicks`, `timedStarvationShareMs`) as **rollback
switches** worth knowing before a regression rather than during one (`IDEA-620`); `metrics.md` makes the traffic
budget **measurable** - per-kind entity counts, active simulators, **maximum per-simulator vehicle count**, AI job
states (`IDEA-618`). The population bindings are confirmed present at `.102`.

**And "grep the binary" turned out to be a bad rule, which I had just written into the research README.**
`joinTraffic`, `attachDriver`, `driveTo` and `npcs.speak` appear as plain strings in **no** server binary while
all are documented and shipping - binding names are not literals. A grep hit is evidence; **a grep miss is not**,
and concluding "there is no traffic API" from its absence would have been the same error as the original BLOCKED
verdict in a new costume. **The next step on traffic is to run the call, not to read more.**

**Incidental and directly relevant after `KB-160`:** `.102` adds
`gamemodes/freeroam/race/server/state_delivery.lua`, the platform's own bounded race-state delivery cache, which
carries **`maxStreams = 16 -- the runtime's per-resource cap`**. NCM just built chunked Guide transport for the
same class of failure and references no per-resource stream cap anywhere (`IDEA-619`).

## Four rulings and the first code off the back of them - 2026-09-27 (`L173`-`L176`)

The owner ruled on the quest-graph gaps and told me to stop proving shapes: *"we move fast and break things or
this will take forever."* Four decisions, two of them built the same session. **Offline-green, undeployed, no
live PASS.**

- **`L173` - NCM counts overtakes. BUILT.** `ncm/core/competition/overtakes.lua`, **17 tests**. It needed **no
  new telemetry**: `session.race` already persists `crossings[gateIndex] = now` per entrant, so running order at
  a gate is that gate's crossing times sorted, and a pass is a pair whose rank inverted across a segment. Pure
  function, no host/schema/network change. Counts `passes` / `passedBy` / `clean` / `contested` / `net` plus a
  time-ordered event list. **A pass counts only where both drivers crossed both gates** - a retirement is not a
  pass on everyone, or the biggest numbers would belong to the luckiest rather than the fastest.
- **`L175` - Leads are a first-class object. BUILT (core + schema).** `ncm/core/player/leads.lua` (**14 tests**)
  plus migration **037**. Identity is the **subject**, not the telling, so two characters naming the same market
  are one lead learned twice - which matters because "multiple unresolved leads" is Glass's trigger and a key on
  the source would count gossip rather than mystery. `source_kind`/`source_ref` survive into the row because
  that is what later characters react to. **Inert until something calls it** (`IDEA-625`).
- **`L174` - the Scanner is authorised**, superseding `28_MACHINE_KNOWLEDGE.md` (*"This is not authorisation to
  build the scanner"*) and `16_MACHINE_INDEX.md`; both amended in place. **Not built.** The deferral is lifted,
  the engineering caution inside it is not: a scan may establish identity and configuration and may not invent
  capability it did not measure. Knowledge half is buildable now; the aiming/scanning half has never been
  measured (`IDEA-624`).
- **`L176` - the voice harness loses its word ceilings and keeps everything else.** The 22-word envelope was an
  artifact of the WolvenKit phone in single player, not a design intent, and the owner's reason inverts the
  usual argument: a uniformly clipped cast has lost exactly the variety the harness existed to protect. The
  **pairwise overlap test at 0.55**, the required/forbidden vocabulary and scenario ownership all survive - they
  are the parts that actually stop two characters sounding the same. **Dex is recharacterised from *terseness*
  to *neutral guidance***, which is the more useful constraint: a long Dex message is fine, an opinionated one
  is not. The violation flagged against document 41's Dex opener is withdrawn.

**One honest note on the leads tests:** the first run failed one case, and the test was wrong rather than the
module - `{sourceRef=nil}` is an empty table in Lua, so the override never applied and the case had been
passing something it was not testing. Fixed with an explicit `NONE` sentinel. It is the same failure shape as
`KB-155`: a check that cannot report having fired.

## Quest graph Pass 1 filed as document 41, with a reconciliation appendix - 2026-09-27 (`IDEA-621`-`IDEA-623`)

The owner supplied `NCM_Quest_Graph_Conversation_Trees_Pass1.md`: the authored world graph built on the character
archaeology - 18 contacts, trigger logic, conversation trees, soft-shut/re-entry rules and payoffs. Filed as
**[41_QUEST_GRAPH_PASS1.md](41_QUEST_GRAPH_PASS1.md)**, STATUS **SPEC**, **preserved unchanged**, with everything
from Appendix A onward added by reconciliation and clearly separated from the draft.

- **The draft is structurally right, and SP already proves it.** Its anti-spam rules (section 20) are almost
  line-for-line what `contact_events.lua` already enforces, and "messages are state projections" is what
  `ShouldActivateChoiceEntry` did. Pass 2 should read DCES before inventing a trigger budget.
- **Section 21's telemetry ask is answered** against real code, in three buckets: observable today (Race Tags'
  16 authored tags, incidents with delta-v bands, odometer at 1 Hz, Economy v1 ledger, provenance, Discoveries
  Inspired, `message.state`); derivable but unstored (head-to-head, consistency, streaks); and **does not
  exist**.
- **`IDEA-621`: NCM Online does not count overtakes.** The draft's best line - *"P8. Seven passes. P1."* -
  cannot currently be written truthfully. Decide before Pass 2 authors a Fan reaction library on it.
- **`IDEA-622`: three characters are gated harder than the draft assumes.** Flashbulb depends entirely on the
  Scanner, which `28_MACHINE_KNOWLEDGE.md` explicitly refuses to authorise; Auntie and Dave need the NPC
  dialogue surface; Zero rests on ghosts whose live proof (§BI) is still owed. Flashbulb has a cheap rescue -
  run the loop on Machine Index discovery, which exists.
- **`IDEA-623`: Knuckles claims results nobody drove**, which `AGENTS.md`'s observed/simulated provenance rule
  makes a storage question, not just a design one.
- **Two collisions with the same day's rulings, both reconciled:** the draft's "do not reveal total market
  count" is superseded by `L171` as a *rule* (though it remains good dialogue writing - Dex still shouldn't
  recite a number), and Billie's "final multiplayer economics model" is now pinned by `L172` to self-paper only,
  so Pass 2 must not author winner-board dialogue.
- **One gift back:** the #1 Fan appearance gag the draft marks "not assumed technically available" is
  reachable - `Open77.clothing.requestSnapshot(playerId)` (server) plus `npcs.setEquipment` compose into it.
- **One voice-harness violation:** Dex's opening message runs ~75 words over six sentences against a persona
  ceiling of 22 words and two sentences. Defensible as an onboarding exception, but it should be a decision.

## Presentation capability audit - 2026-09-27, reconnaissance only (`IDEA-568`-`IDEA-581`, `KB-157`, `KB-158`)

A second, read-only UI/UX investigation ran alongside the live queue and **changed no production behaviour**. It
asks what NCM can *paint with*, not what NCM should *say* — a separate player-visibility audit owns the second
question. Full document: [docs/research/open77/PRESENTATION_CAPABILITY_AUDIT.md](../research/open77/PRESENTATION_CAPABILITY_AUDIT.md),
prototypes in `docs/research/open77/prototypes/`. **Nothing in it was measured in-engine**, so nothing in it is a
live PASS; the proof ladder used is PROVEN (in-tree shipping code) / AVAILABLE / PLAUSIBLE / BLOCKED.

- **NCM is off the platform design system and did not know it.** `open77-ui.css` is a documented token contract
  shipped byte-identical in 11 OPEN//77 resources; NCM ships no copy and re-derived a divergent subset. Consequence
  already visible in source: `panel.html` renders in Bahnschrift Condensed and `nameplates.css` in Arial Narrow,
  because no resource bundles a font and `"Rajdhani"` never resolves in-game (`KB-157`).
- **The binding constraint is eight CEF surfaces per resource, and NCM can already hold seven** — three of them
  invisible 16×16 pages used as transport to the local Carrier. One spare. This governs every future NCM surface.
- **Two latent z-index collisions** on layer `hud`: NCM venue at z720 against the notification toasts, NCM race HUD
  at z730 against `open77_admin`. Not observed misdrawing; logged so it is not rediscovered as a mystery (`KB-158`).
- **NCM is silent and still.** No `sfx`/`vfx`/`effects`/music call anywhere in `ncm/`, zero `@keyframes` in every
  page. The platform proves the exact vanilla race cues by name (`sq024_race_*`, `ui_jingle_quest_*`,
  `ui_menu_onpress`) and 38 keyframe animations in-engine. `Open77.sfx.play2d` takes no quota and no handle.
- **Bigger than expected, and unused:** NCM's own SVG glyphs can be drawn as **native Ink geometry inside the
  vanilla map** via `blips.create{icon=…}`; `Open77.anchors` generalises the per-frame projection NCM already ships
  for Driver Cards; a live NCM page can run on a world television up to `cinema.150ft`; and a curated racing kit
  already exists (`race.firework.burst`, `race.checkpoint`, `race.route_arrow`, `street.traffic_light`, `barrier.*`).
- **Delivery is nearer than the record suggested.** Per `35_REQUIREDMODS_FORENSIC_AUDIT.md`, `Unverifiable` meant the
  launcher discarded a non-loopback plain-`http:` URL — HTTPS is the fix — so client-component techniques (liveries,
  sky holograms, a bundled webfont) are reachable engineering rather than fantasy.

Nothing here displaces the live queue above. The cheapest items are additive and reversible: the token file
(`IDEA-568`), an audio vocabulary (`IDEA-571`), separating the two z-indices (`KB-158`), and declaring
`ui.vanilla.hud` (`IDEA-576`). No decision was taken, so `DECISION_RECORD.md` is unchanged.

**Addendums A-C, added the same day at owner request** (`IDEA-582`-`IDEA-586`): market presentation identity as a
scoped **token override block** rather than a per-market interface — which is the only affordable shape, because a
themed market must cost **zero** WebUI surfaces; the themeable/never-themeable boundary, where the shell, the money
figure and the legibility floors are never a market's to change; and **Player Banners, which already exist in
embryo** — `driver.presentation` ships the registry, `theme` field, entitlement *reason*, validated selection,
persistence, public projection and renderer, and lacks only an earning path, so the delta is one write-once
`banner_grant` table plus a second input to `M.entitlements()`. Banner format is already fixed by the renderer:
206×84 ≈ 2.45:1 at opacity 0.72 under text, so a banner is **a wash, not a picture**. Addendum C codifies the
communication register the repository already writes in. Prototype:
`docs/research/open77/prototypes/market-identity-and-banners.html`.

## Visibility/communication work in progress - NOT mine, and now green again

The working tree carries an **unfinished player-visibility implementation** from a concurrent session that stopped
mid-flight: `core/player/communication.lua` (+ 7 core tests), `ncm_league/server/communication.lua`,
`ncm_league/server/visibility.lua`, migration **036** `player_message_exposure`, the new **DRIVER FILE** shell
surface in `panel.html`, and a tyre readout in `race.html` that now names state, trend and grip cost. It is good
work and it is **uncommitted, undeployed and unfinished** — migration 036 has had no twice-applied dry-run, and
nothing in it has a live PASS.

**It left the gate red; the gate is green again.** Both failures were stale harness expectations, not defects:
`tools/panel-render-check.js` asserted an exact five-entry shell nav and the shell now has six (DRIVER FILE), and
`tools/race-render-check.js` asserted the old tyre copy `"OK"`/`"-15%"` where the readout now says
`"FULL GRIP"`/`"-15% GRIP"`. Both guards were **updated to the new intent rather than loosened**, and the new
behaviour gained cover: the driver panel is now itself checked for the full nav, and the tyre state word and trend
arrow are asserted. Panel **131** assertions (was 129), race **50** (was 46), both 0 bad; whole gate ALL GREEN
under both interpreters, including that session's 7 communication tests.

Anyone resuming that work should read `visibility.lua` first — its `currentCommitment()` copy is the clearest
statement of NCM's voice in the repository, and `IDEA-586` codifies it.

**`KB-159`, found while integrating and worth knowing about:** `player/communication.lua` was in `MANIFEST.lua`
but had **never been vendored** — `tools/ncm-build.ps1` had not been run — so it was missing from both
resources' `shared/core/` and from their generated `shared_script` lists. `NcmCore.get` **raises** on an unknown
module and `ncm_league/server/communication.lua` calls it at file scope, so `ncm_league` would have failed to
start on deploy. Fixed by running the build. **Run `tools\ncm-build.ps1` after touching `MANIFEST.lua`, every
time** — and `IDEA-594` proposes the gate assert it instead of relying on memory.

## Input accessibility and the Session Landing Panel - BUILT 2026-09-27, live input test owed (`IDEA-587`-`IDEA-594`)

Owner implementation request, delivered. Full recon, design and honest test limits are Addendum D of
[docs/research/open77/PRESENTATION_CAPABILITY_AUDIT.md](../research/open77/PRESENTATION_CAPABILITY_AUDIT.md).

- **Every NCM panel mode is now keyboard- and gamepad-navigable**, from one focus-scope push in `panel.html`'s
  `show()` rather than surface by surface: Guide, Market, Machine Index, Driver File, Help, Wheel, Questionnaire,
  Inbox and the new Landing panel. The race HUD and Driver Cards stay passive and take no focus, which is right.
- **A CEF page cannot see a gamepad.** So `client/nav_input.lua` reads the pad (`Open77.input.isDown`/`axis`),
  turns it into semantic actions, and sends those to `web/ncm-nav.js`, which never mentions a button.
- **Pad BACK is authoritative in Lua and does not wait for the page** — the direct extension of `KB-61`, where
  both exits ran through the page and a player had to kill the game. Escape stays owned by `panel.html`.
- **The Landing Panel is a mode of the existing page, not a new surface**, because NCM holds seven of eight
  (`IDEA-570`). Content is authored data in `client/landing_content.lua`, validated by `core/player/landing.lua`;
  a `partial` capability is refused unless it states its limit. Chat twins `/ncm.whatsnew` and `/ncm.alpha`;
  `/ncm.input` prints every pad control and axis for the first live session.
- **Offline evidence:** 522 core tests (+12 landing), panel render **148** (was 131), a new
  `nav-render-check.js` at **33** assertions, 226 resource files, whole gate ALL GREEN under both interpreters.
  The nav harness **caught a real bug on its first run** — a bare half-plane test treated a control 700 px below
  as "to the right"; a directional cone fixed it (`IDEA-589`).
- **Not tested, and this is the limit: no gamepad has touched any of it.** Repeat timings and stick thresholds
  are reasoned, not tuned; the §31 mouse-only / keyboard-only / pad-only matrix is owed in full. One known gap:
  hold-to-confirm controls are not yet completable from a pad (`IDEA-593`).

A build string check worth keeping: the devkit MCP publishes cards only to **op77.78** while staging runs
**.102**, so it reports newer natives as "not in any published build". `setConsumedKeys` is one of those, and
reading the installed `Open77.dll` (2026-09-25) shows it **is** present. When the index lags the deployed build,
grep the binary.

## Offline evidence

- Core: **614 passed, 0 failed** under Lua 5.4 and LuaJIT.
- Cross-scope: **57 checked, 0 bad**; QA observer **17 / 0**; vehicle access **35 / 0**.
- `luac -p`: **238 resource files, 0 bad**.
- Render checks: panel **157**, nameplate **26**, race **55**, nav **33**, all green.
- Documentation authority: **78 valid documents, 518 unique ledger IDs**. The final complete repository gate is
  **ALL GREEN under every interpreter** after session-close bookkeeping.

## Still live and unchanged

- Ghosts are deployed PERSONAL BEST only under `L166`; §BI remains awaiting live driving proof, including the
  exact vehicle visual, non-collision, heading seam, penalty time and both practice/time-trial claim paths.
- Machine Knowledge migration 033 and the first typed observation vocabulary are deployed under `L164`; §BH and
  the twice-applied dry-run remain owed. No estimator, envelopes or confidence were added.
- Parts economy/UI v1 is deployed under `L162`-`L163`; §AZ and later performance work remain owed. Economy v1 did
  not change the Carrier's proven three-lever boundary or resolve the brakeScale/drag coupling (`IDEA-538`).
- Useful live commands remain `/ncm.topspeed 40`, `/ncm.ratedtopspeed`, `/ncm.setup power_unit 2.0`,
  `/ncm.setup tires 1.4` and `/ncm.setup brakes 2.0`.
