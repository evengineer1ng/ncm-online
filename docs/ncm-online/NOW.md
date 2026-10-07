# NOW - the single next-action index

> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md).

**LATEST 2026-10-07 (01:05 ET) - L334 DEEP TO THE KSA BORDER BUILT ON DEV: the Earth now rotates in Deep (orbits are real), your Hella carries a Fusion Drive FD-1 (rear, hold Triangle) and a Propellant Tank PT-500 (front) -- the RP-16 is in storage -- and Guidance's first target is the KSA border, Earth's sphere of influence at 925,000 km: ~3.8 h at ~1 g, flown by the server if you log off. In simulation it arrives with 110 kg of 500 kg to spare. The KSA handoff itself waits for your KSA install. Dev restarted 01:01 (`l371-restart-20261007.stdout.log`). Online (Lightsail) untouched.**
- **THE ONE NEXT ACTION (owner):** install KSA from ahwoo.com (free; default path) and say so -- then the probe mod (§KS1). Meanwhile: hold Triangle in Night City (§KS3), climb into Deep and engage Guidance to the KSA border (§KS4-§KS6).

**EARLIER 2026-10-07 (00:15 ET) - KB-369 FIXED: A on a Guidance target no longer throws you home -- one slow frame (the engage frame tipped OPEN//77's ~6 ms per-frame budget) is now skipped, not fatal; the engage frame only plans. KB-370: the mod stack was never shuffled -- every installed NCM DLL hash-matches its newest build (Carrier 0.1.37 ...); RED4ext's version line is a stale hard-coded label. Dev restarted 00:14 (`l368-restart-20261007.stdout.log`). Online (Lightsail) untouched.**
- **THE ONE NEXT ACTION (owner):** climb into Deep, pick a target, A: Guidance flies (the log may say `frame over the script budget -- skipped`, harmless). Then Laguna -> AC climb-out (§AC16) and the geography (§RD1, §RD6).

**EARLIER 2026-10-06 (23:55 ET) - KB-368 FIXED: the L332 renderer's tile prefetch blew Open77's per-frame script budget inside the Deep flight frame, crashed the flight on your 23:48 resume and dropped you at 11.5 km over Night City -- that is why the hop "did nothing" (you were falling). Prefetch now runs off the flight frame, one point per frame; geography can never end a flight. Dev restarted 23:54 (`l367-restart-20261007.stdout.log`); bridge 23:40 with tiles. Online (Lightsail) untouched.**
- **THE ONE NEXT ACTION (owner):** rejoin dev; hop in Night City as before; then the Laguna trip and the AC climb-out (§AC16) with the new geography on the way (§RD1, §RD6).

**EARLIER 2026-10-06 (23:42 ET) - KB-367 + L333: AC's hop is now Night City's hop -- a velocity change through the centre of mass that cannot twist the car (the old push carried a moment and AC never damps spin in the air). Owner ruling L333: no part exists in one game only. Bridge restarted 23:40 with the tile cache (L332 live for both renderers). Dev 23:29 (`l366-restart-20261006.stdout.log`). Online (Lightsail) untouched.**
- **THE ONE NEXT ACTION (owner):** fly to Laguna, hop out through the sky (§AC16), and on the way look at the new geography (§RD1, §RD6). If it still tips, the bridge log's `hopSpin` lines say how, and IDEA-1168 is next (the AC-6 holding level, both games).

**EARLIER 2026-10-06 (23:35 ET) - L332 DEEP RENDERER BUILT ON DEV: real geography under you (public-domain imagery to ~1 m in the US, ~30 m elsewhere, prefetched along your path), the planet ray-traced (no facets near the ground), the world drawn at a lower internal resolution and rebuilt with EASU + RCAS, the HUD never upscaled. Headless: 3 km over Laguna = 2.4 m per texel, sharp HUD at 50 % scale. Dev restarted 23:29 (`l366-restart-20261006.stdout.log`). The HOST BRIDGE is NOT restarted (AC was running): until it restarts Deep shows the global image as before. Online (Lightsail) untouched.**
- **THE ONE NEXT ACTION (owner):** close AC; I restart the bridge; then fly the California descent (§RD1-§RD6) -- the RENDER / GEOGRAPHY lines on the HUD say what it is doing.

**EARLIER 2026-10-06 (19:08 ET) - KB-364 FIXED: racing (ncm_league) had stopped at 19:00:58 -- the AC-6 grant's player-less change event crashed it, so nothing reached the Race Guide. Guarded on both sides; dev restarted 19:07 (`l365-restart-20261006.stdout.log`), racing up, 5 races posted. The AC-6 stays on your Hella. Online (Lightsail) untouched.**
- **THE ONE NEXT ACTION (owner):** open the Race Guide (races should be listed), then fly the Hella in Deep with the AC-6 (§EN14, §FM3) and the AC hop (§AC15).

**EARLIER 2026-10-06 (18:32 ET) - KB-363 + IDEA-1163: THE BENCH IS ON THE PAD. Panel -> Parts now fabricates (dev), mounts with a facing and removes add-ons by holds -- no typing. The AC-6 is ON your Hella (..0003): roof, facing up, revision 9 (granted 19:00:58). Dev restarted 19:00 (`l364-restart-20261006.stdout.log`). Online (Lightsail) untouched.**
- **THE ONE NEXT ACTION (owner):** get in the Hella and fly Deep: the ATTITUDE line shows +/- on all three axes with no waiver label (§EN14, §FM3). §AC15 (the AC hop) is still waiting too.

**EARLIER 2026-10-06 (18:03 ET) - KB-362 FIXED: the AC hop now pushes through the car's centre of mass, straight along its up axis (as in Night City) -- it no longer rolls the car onto its side or roof. Tap Triangle repeatedly to climb; past 6 km going up, Deep takes over. The fix reaches AC at the next embodiment (the bridge copies the app). L331 below is unchanged.**
- **THE ONE NEXT ACTION (owner):** fly to Laguna Seca, land, and hop out through the sky (§AC15), then continue §FM1.

**EARLIER 2026-10-06 (17:52 ET) - L331 DEEP ON THE FULL MACHINE MODEL: one 6-DOF machine (your install + chassis + tank) in Cyberpunk's Deep, AC's Deep and the server's offline flight; air thins with altitude; off-centre thrust spins it; parts heat up and shut down; Guidance turns the car's real thrust axis. Today's Hella cannot point itself (no yaw/roll) -- on DEV a labelled attitude waiver flies it as before; the new Zetatech AC-6 attitude set (`/ncm.eng.fabricate ac6`) makes it physical. Dev 17:52 (`l360-restart-20261006.stdout.log`). Core 1129 green.**
- **THE ONE NEXT ACTION (owner):** fly as before on the waiver (§FM1; the HUD now shows ATTITUDE and AIR), then fabricate + install the AC-6 and fly without the waiver label (§FM3).

**EARLIER 2026-10-06 (16:57 ET) - KB-361 + KB-360 FIXED: the join over Laguna now waits for your parts, holds you there (B = stay keeps holding), never queues a stale AC close, and drops you into a Track day / practice session too; the JSON encoder no longer rounds Deep positions to ~10 km (`%.14g`). The vendored core ran in real AC for the first time (CSP: `loaded and ready to run`). Dev + bridge 16:56 (`l359-restart-20261006.stdout.log`). You are canonically at Laguna Seca (run 2).**
- **THE ONE NEXT ACTION (owner):** join dev: you hover ~80 m over Laguna with the prompt (give it a few seconds for your parts); A: AC opens in whatever session Laguna's timetable says and you drop in (§RT16); Triangle tap/hold (§RT14).

**EARLIER 2026-10-06 (16:35 ET) - L330 THE RACING WEEK IS THE UNIVERSE'S TEMPORAL LOOP: the Earth venues race on the run's SEEDED calendar (posted timetables: practice, qualifying, grid, race, track day; dark unlit circuits closed), you drop into the session the clock says (AC configured to it), Guidance shows each place's timetable; at a reset every Machine -- Night City, Deep, AC, online or not -- is back in Night City (verified live 16:33 on a last-run test record). Dev 16:33 (`l358-restart-20261006.stdout.log`). Gate green (core 1118). You are canonically at Laguna Seca, run 2.**
- **THE ONE NEXT ACTION (owner):** join dev -> over Laguna, A: you drop into whatever session Laguna's timetable says now (§RT16); D-pad up to read other venues' timetables (§RT15); Triangle hop/hold (§RT14).

**EARLIER 2026-10-06 (16:00 ET) - KB-359 + ONE SUN: in AC the hop/RP-16 forces are now scaled to CSP's physics step (they were 0.23x), AC's horn is moved off Y (adapter-owned, restorable), the drop waits for the race start and comes in low (80 m, straight down); Deep's sun and AC's sky follow NCM's real UTC clock (night = night). Owner's 15:38-15:49 run: Cyberpunk -> AC worked, Cyberpunk closed by itself once AC had the Machine, NPCs racing. Dev 16:00 (`l356-restart-20261006.stdout.log`); you are canonically at Laguna Seca. Gate green (core 1114).**
- **THE ONE NEXT ACTION (owner):** join dev (you appear over Laguna with the AC prompt), A: drop in, Triangle tap/hold (§RT14), check the sky time (§RT13); then up past 6 km and Guidance to Night City (§RT2-§RT5).

**EARLIER 2026-10-06 (15:30 ET) - L329 ONE UNIVERSE BUILT: one Deep record on the NCM server (presence, unhosted flight -- "autopilot keeps going" -- verified live: the server flew a test Machine 1,009 s to Laguna Seca with no game running), Deep INSIDE Assetto Corsa on the same vendored core (up through AC's sky; Night City in its Guidance), the host lifecycle (Cyberpunk closes once AC has the Machine; launched again ~60 km from Night City), consent-gated adapters + HOST ADAPTERS panel, the place registry (45 layouts: 32 verified, 13 unresolved, live), resume where you are on join. KB-358 fixed. Dev 15:29 (`l355-restart-20261006.stdout.log`); bridge restarted. Gate green (core 1112+).**
- **THE ONE NEXT ACTION (owner):** the round trip, hands off Windows (MASTER_TEST §RT1-§RT5): Night City -> Laguna Seca -> race -> hop/hold up past 6 km -> Guidance Night City -> keep flying until Cyberpunk takes you. Then §RT6 (quit in Deep).

**EARLIER 2026-10-06 (14:30 ET) - L328 POST-LAGUNA PASS BUILT, DEV RESTARTED 14:25 (`l348-restart-20261006.stdout.log`, migration 067 applied). The owner's Laguna run is recorded as §AC1-§AC4 + §AC6 PASS (§AC5 FAIL: Triangle did nothing). Built: AC comes to the front by itself (KB-357), no pre-race screen and the drop after the session is live (KB-356), the Machine's own Triangle/RP-16 in AC with heat + propellant (KB-355), real-scale Hella + locator + zoom in Deep, the ascent overlay from 4 km becoming Deep with no white-out, every journey recorded (schema 067). Burn/coast guidance measured worse and reverted (IDEA-1149).**
- **THE ONE NEXT ACTION (owner):** one run, hands off Windows: climb from Night City (watch 4-12 km: §AC13), Deep (zoom: §AC12), Guidance -> Laguna Seca, A (§AC9 focus, §AC10 no Drive screen), land, Triangle hop + hold (§AC11), back to Deep (§AC14 journey line). Say at what altitude REDengine first looks wrong.

**EARLIER 2026-10-06 (13:25 ET) - FIRST FALL FROM THE SKY INTO ASSETTO CORSA (13:19-13:20): straight into Laguna Seca (KB-353 verified), physics allowed, car placed 3,131 m up, 14 NPCs placed -- then the AC app took the arrival height for a climb-out and closed AC (KB-354, fixed in the app; live on the next embodiment). Deep resumed above Laguna Seca as designed.**
- **13:35:** owner asked to skip AC's pre-race screen: the NCM app now presses it (`ac.tryToStart(true)` while `isInMainMenu`, NCM arrivals only; probe `autoStart`). Live next embodiment, unverified.
- **THE ONE NEXT ACTION (owner):** Deep -> Laguna Seca -> A at the prompt: no Drive screen, fall, land, race; climb past 2,500 m to go back to Deep (§AC2-§AC8).

**EARLIER 2026-10-06 (13:10 ET) - AC LAUNCHES FROM NCM (KB-352 verified 13:03: bridge -> 200, race.ini for Laguna Seca). It opened the AC launcher instead of the session: KB-353, `steam_appid.txt` now beside acs.exe; bridge restarted.**
- **THE ONE NEXT ACTION (owner):** quit AC, then Deep -> Laguna Seca -> A at the prompt: AC should load straight into Laguna Seca with the car in the air (§AC1-§AC3).

**EARLIER 2026-10-06 (08:07 ET) - KB-352: the race world built (Laguna Seca GT, 14 NPCs, Quattroporte body) but the call to the AC bridge never left the server: `ncm_world` lacked `http.request`. Fixed; dev restarted 08:07 (`l347-restart-20261006.stdout.log`).**
- **THE ONE NEXT ACTION (owner):** climb out, D-pad up, Laguna Seca, A, A at the prompt (§AC1).

**EARLIER 2026-10-06 (07:51 ET) - GUIDANCE WORKS: the Hella flew itself to Laguna Seca (07:41 -> 07:45) on the dev heat waiver. AC then failed to open: the server's embody request died on the instruction quota (KB-351, 744 NPC drivers decoded + sorted in one slice); fixed. Also live: freefall rescue (IDEA-1144: falling on foot puts you in your own car) and the dev respawn (KB-350). Dev restarted 07:51 (`l346-restart-20261006.stdout.log`).**
- **THE ONE NEXT ACTION (owner):** climb out, D-pad up, Laguna Seca, A, ride it in, A at the prompt -- Assetto Corsa should open (§AC1-§AC8).

**EARLIER 2026-10-06 (07:33 ET) - KB-350: DEATH ON DEV WAS PERMANENT (no freeroam = no respawn) and a mid-air saved position killed the owner on each join. The bad save is deleted (owner-approved); `ncm_world/server/life.lua` now respawns a dead player after 3 s at the nearest safe ground point. Dev restarted 07:33 hidden with a log again (`l345-restart-20261006.stdout.log`; no console). Dev heat waiver live (IDEA-1143).**
- **THE ONE NEXT ACTION (owner):** rejoin dev; if dead, you come back within ~8 s. Then Deep -> D-pad up -> Laguna Seca (§AC1).
- **Coder next:** KB-350 (1) the saver's airborne test; IDEA-1144 freefall -> back in your car (owner).

**EARLIER 2026-10-06 (07:16 ET) - DEV HEAT WAIVER (owner ruling, IDEA-1143): on the development server installed parts never overheat, like dev fuel; guidance now accepts the one-RP-16 Hella. Convar `ncm_dev_heat 0` turns it off for a heat test; Online untouched. Dev restarted 07:16 in a VISIBLE console window (no stdout log file this run; `ncm.heal 1` works there). Core 1103 green. Open: the owner's saved location is mid-air (2563.8, 107.1, 249.9 saved 06:33:47 in the Hella) and kills them on join; the auto-mode classifier blocked deleting the row -- owner clears it (KB-350 to file: the saver let a slow climb through as grounded).**
- **THE ONE NEXT ACTION (owner):** rejoin dev, climb into Deep, D-pad up, Laguna Seca, A, ride it in, A at the prompt (§AC1-§AC8).

**EARLIER 2026-10-06 (06:57 ET) - KB-349 FIXED: Guidance flew the Hella into the Earth (06:37 Spa, 06:42 Silverstone). It now flies altitude first, respects RP-16 heat, never goes below 2.5 km over a venue, holds over the venue at the AC prompt, and nothing in Deep can go underground. BUT it now REFUSES the current Hella: one RP-16 can hold 10 kN without overheating against 19 kN of weight. Dev restarted 06:57 (`l343-restart-20261006.stdout.log`). Core 1103 green.**
- **THE ONE NEXT ACTION (owner):** pick how the Hella gets a flyable build (IDEA-1143: more RP-16s, a dev-only heat waiver, or an RP-16 heat balance change); then §AC1 again.

**EARLIER 2026-10-06 (06:30 ET) - §AC0 PASS (AC first run). AC set to the Xbox pad (was keyboard). Bridge gives every car a real skin. Dev restarted 06:29 with Guidance live (`l342-restart-20261006.stdout.log`); the bridge starts with it.**
- **THE ONE NEXT ACTION (owner):** climb out of Night City, D-pad up in Deep, pick a venue (Laguna Seca is the short one), A, ride it in, A at the prompt (§AC1-§AC8).

**EARLIER 2026-10-06 (06:15 ET) - L327 BUILT, NOT YET RUN: Deep Guidance (pad) -> 17 Assetto Corsa venues on NCM Earth -> NCM NPC races on the one clock -> the same Machine embodied in AC (in the air, parts as forces) -> back to Deep. CSP 0.2.11 + Content Manager installed (owner downloads). Host bridge running on 127.0.0.1:47710. Core 1099 green. BLOCKED on: AC's first run on this PC, and a dev restart (owner connected).**
- **THE ONE NEXT ACTION (owner):** start Content Manager once (`tools/assetto/ContentManager/Content Manager.exe`), point it at AC, run a quick Monza practice, quit (§AC0); then tell the coder to restart dev.

**EARLIER 2026-10-06 (04:15 ET) - §DP2 PASS: the owner flew the Hella out of Night City the real way (hop + forward, through 12 km by itself) and on to 15,000 km, escaping Earth at ~9,900 m/s. Deep v0.1 has only Earth -- nothing else is out there yet. The way home is still a command (`/ncm.deep.home`) or a long retro-burn.**
- **Coder next:** a way home that is a control, not a command; then what the owner picks for space (orbit racing, the Moon, the Nessie).

**EARLIER 2026-10-06 (03:57 ET) - The hop is the old hop again (fires on press, every press restarts it) and the RP-16 pushes 30 kN. Dev 03:57. Online confirmed untouched (dev-only, uncommitted).**
- **THE ONE NEXT ACTION (owner):** fly the Hella: mash Triangle, hold to push forward.

**EARLIER 2026-10-06 (03:48 ET) - DEV FUEL BY DEFAULT: the development server burns no fuel (distance or components) and keeps tanks full (owner ruling). Dev restarted 03:48.**
- **THE ONE NEXT ACTION (owner):** fly: mash Triangle up, hold to push forward; Deep takes over past 12 km.

**EARLIER 2026-10-06 (03:39 ET) - OWNER RULINGS: NO MORE CHAT COMMANDS (play + in-game UI only); the Machine is tap = hop (IA-10 underside/down), hold = forward (RP-16 rear/aft). The coder's lift build broke that and the owner crashed (tank was empty). Restored server-side (configuration revision 8) and the tank filled; dev 03:39.**
- **THE ONE NEXT ACTION (owner):** get in the Hella and fly it -- mash Triangle to climb, hold to push forward; past 12 km Deep takes over by itself.
- **Coder next:** everything the owner needs reachable without typing (an in-game bench for parts/bindings; a way home from Deep that is a control, not a command).

**EARLIER 2026-10-06 (03:25 ET) - First Deep flight (03:2x): the handoff, input and parts all worked (RP-16 to 76%, IA-10 fired) but `/ncm.deep.go` started at the 12 km bound with 500 m to the return, and a Hella with one RP-16 has thrust/weight 0.85 -- it could only fall slower. Fixed: `/ncm.deep.go [km]` (default 30 km); schema 066 lets one control command several components (a multi-propulsor lift build is now possible); HUD shows thrust/weight. Dev restarted 03:25 (`l338-restart-20261006.stdout.log`).**
- **THE ONE NEXT ACTION (owner):** a lift build (two RP-16 facing down + the rear one), `/ncm.eng.devfuel`, `/ncm.deep.go`.

**EARLIER 2026-10-06 (03:16 ET) - First live tries: installs worked after KB-347 (both parts mounted, both bindings). KB-348 (`/ncm.deep.go` stuck white: script budget) fixed, dev restarted 03:16. NEW `/ncm.eng.devfuel` (development only): installed parts burn nothing. FOUND: OPEN//77 did not see the owner's pad in the 02:56 session (`gamepad_not_connected`; 02:32 and 02:46 sessions saw 20/20 controls), so Triangle bindings and the scanner were dead while NCM Thrust (direct XInput) still saw presses -- which the installed parts then superseded: no hop. Relaunching the game is the first remedy; binding H as well covers keyboard.**
- **THE ONE NEXT ACTION (owner):** relaunch Cyberpunk (pad detection), join dev, `/ncm.eng.devfuel`, then `/ncm.deep.go` (§DP1).

**EARLIER 2026-10-06 (02:45 ET) - L326 NCM DEEP v0.1 LIVE ON DEV: climb past game z 12 km (or `/ncm.deep.go`) and the Machine leaves REDengine for NCM's real-scale Earth, drawn in-game (WebGL, NASA Blue Marble, Night City at 35.37 N 120.85 W), flown with its own installed components and tank; fall back through 11.5 km and it returns. Dev restarted 02:44 (`l335-restart-20261006.stdout.log`). No live PASS.**
- **THE ONE NEXT ACTION (owner):** build your Machine (L324: fabricate, install, bind), then fly it through Deep: MASTER_TEST §DP1-§DP5 (and §EN1-§EN12).

**EARLIER 2026-10-06 (02:40 ET) - §DP0 PASS: NCM's universe can be drawn INSIDE Cyberpunk. WebGL in an OPEN//77 WebUI surface runs on the RTX 5060 Ti (ANGLE/D3D11, WebGL2 available) at 60 fps, 1920x1080; owner saw the planet "full scale and quickly". KB-346 verified (the owner joined). Sprite shader fix (`half` is reserved) waits for the next dev restart.**
- **THE ONE NEXT ACTION (owner):** the L324 engineering run (§EN1-§EN12) whenever ready; it has never had a live session.
- **Coder next (L326 P1):** real Earth imagery + atmosphere in the surface; the Hella sprite; then the handoff at an NCM-chosen altitude.

**EARLIER 2026-10-06 (02:25 ET) - L326: NO SECOND PROGRAM. NCM simulates its own universe just out of REDengine's reach, inside the game; you get there by hitting the vertical bounds + a loading screen. OpenSpace is now a source of understanding/MIT code, not a runtime. PROBE 0 LIVE ON DEV (`prototypes/ncm_deep`, dev-only entry): `/ncm.deep` asks whether WebGL runs in an in-game WebUI surface. Dev restarted 02:24 (nobody on; `l333-restart-20261006.stdout.log`).**
- **KB-346 (02:31):** L324's client script refused every dev join (a handler-less RegisterNetEvent); fixed, gate now checks it, dev restarted. Owner correction: the Hella has reached 60+ km (until out of fuel) -- 33.6 km was one crash, not a ceiling.
- **THE ONE NEXT ACTION (owner):** in Night City (dev) type `/ncm.deep` and watch for 20 s (MASTER_TEST §DP0). Then the L324 engineering run.

**EARLIER 2026-10-06 (02:00 ET) - L325: NCM IS A CYBERPUNK MOD; THE SPACE BEYOND NIGHT CITY GOES TO AN OPENSPACE-SCALE UNIVERSE WITH NCM OWNING PHYSICS (owner direction). P0 RUN: OpenSpace 0.22.0 runs here (`tools/openspace/`, 60 fps); an NCM-owned node over Night City's place on Earth took 60 Hz updates from `prototypes/ncm_openspace/probe.py` (MASTER_TEST §OS0). OpenSpace is left open on the desktop.**
- **Ruled since:** Night City at 35.37 N, 120.85 W; Machines are Cyberpunk vehicle sprites (104 extracted from the game's own icon atlas, 34/45 roster matched). The sprite billboard loads in OpenSpace but is not yet framed on screen (low-altitude camera = P1).
- **THE ONE NEXT ACTION (owner):** the L324 engineering run (§EN1-§EN12). Coder: P1 (chase camera + the NCM space runtime flying the Hella sprite).
- **Coder next:** P1, the NCM space runtime (LuaJIT + ncm core) flying a stand-in Machine around OpenSpace's Earth on the pad.

**EARLIER 2026-10-06 (01:25 ET) - L324 BUILT AND LIVE ON DEV: THE FIRST ENGINEERING LOOP. Reaction Propulsor RP-16 + Impulse Actuator IA-10 as serialised component assets; four hardpoints with facings and ratings; install/remove as configuration revisions (schema 065, applied 01:20); controls bind to component commands (tap/hold on one button); the client maps thrust through the car's live axes to a world force; Carrier 0.1.37 applies it at the bound body (installed `dev-mods/20261006-012025`). Fuel from the Machine's own tank. Core 1076 green. Dev restarted 01:20 (nobody on; `l332-restart-20261006.stdout.log`). No live PASS.**
- **THE ONE NEXT ACTION (owner):** MASTER_TEST §EN1-§EN12 in Night City dev: `/ncm.eng.fabricate rp16`, `/ncm.eng.fabricate ia10`, park + get out, `/ncm.eng.install <ia10> underside down`, `/ncm.eng.install <rp16> rear aft`, `/ncm.eng.bind triangle tap <ia10> discharge`, `/ncm.eng.bind triangle hold <rp16> throttle`, drive.
- **Open:** IDEA-1124 torque channel, IDEA-1125 acquisition route, IDEA-1127 odometer fuel while flying; IDEA-1128 OpenSpace restated as "rendering substrate for an NCM-owned Snowglobe runtime" (after the L324 run); IDEA-1129 presentation vs simulation geometry (decide by playing).

**EARLIER 2026-10-05 (21:45 ET) - PC REBOOT RECOVERY: DEV (`l330-restart-20261005.stdout.log`; `ncm_link` hub REACHABLE, HTTP 200) AND FXSERVER (`fxserver-20261005-214255.log`; license OK, `ncm_ls_space` up, 1 linked driver kept) RESTARTED BY HAND -- NOTHING AUTO-STARTS AFTER A REBOOT. LIGHTSAIL UNTOUCHED (up 15 days, player connected). §LK1 already PASS (21:10).**
- **KB-345 (21:57):** the manual drove like an automatic because Carrier was back on 0.1.30 (a full dev hand-install at 20:53 replaced the 0.1.36 spike). 0.1.36 reinstalled. Every other NCM mod already matches its newest build (gearbox 0.3.1, snowglobe 0.0.5, thrust 0.0.2, pace 0.9.2, vision 0.4.0, rig-bridge 0.1.7, broadcast/clock 0.1.0). Check the Carrier log for `NCM Gearbox levers found`.
- **22:10:** KB-345 verified at 22:05 (Carrier 0.1.36 log: `NCM Gearbox levers found`). `ncm_space`: `/ncm.sky` from more than 600 m away now sets a routable GPS pin on the grid instead of opening it (dev restarted, nobody on; `l331-restart-20261005.stdout.log`). The orbiter ran out of propellant on the EVA attempt: §EVA2 now says `ncm.machine instrument` first.
- **THE ONE NEXT ACTION (owner):** §NCS1 `/ncm.sky` anywhere on dev, follow the pin, `/ncm.sky` again; then §EVA2 in LS with `ncm.machine instrument`; then §SP1 / §FB1.

**EARLIER 2026-10-05 (20:30 ET) - L323: THE SIX SNOWGLOBE HOST BOUNDARIES CLEARED OR NARROWED. THE CROSS-SERVER LINK IS LIVE ON DEV: NIGHT CITY (`ncm_link`) REACHED THE LOS SANTOS SNOWGLOBE HUB AT 20:25 (HTTP 200, FACTS BOTH WAYS). NEW: PLAYER-NPC CONTACT AS PHYSICS, MULTIPLAYER SNOWGLOBE RACES (UNIVERSE-STATE PRESENTATION -- NETWORKED CARS CANNOT SERVE PER-CLIENT FLOATING ORIGINS), CLOCK-SYNCED PHOTO FINISH, LIFE SUPPORT + EVA + BOARDING BY THE RELAY RULE, THREE CITIES SCORING, AND THE BADLANDS SKY SPRINT IN CYBERPUNK (`ncm_space`). DEV RESTARTED TWICE (NOBODY ON; `l329-restart-20261005.stdout.log`). `ncm_ls_space` 0.5.0 LIVE. Dev `server.jsonc` http enabled for 127.0.0.1.**
- **THE ONE NEXT ACTION (owner):** link yourself: `/ncm.link` in Night City (dev), then F8 `ncm.link CODE` in Los Santos (§LK1). Then `/ncm.sky` at the Badlands in Cyberpunk (§NCS1), and `ncm.eva.drill` in Snowglobe (§EVA2).
- **Open for the owner:** L323 Q1 link topology beyond one PC; L322 Q1 relay baton (passenger now works), Q2 Fireball credit; L321 Q1 competency families; L320 Q1 compressed geography.

**EARLIER 2026-10-05 (19:55 ET) - L322 BUILT: SNOWGLOBE SPRINT (PLANES, LANES, FIVE LIGHTS, HERMITE PHOTO FINISH, UNIVERSE TIMING) AND FIREBALL (VALID DISTANCE = ANGLE ABOUT A TURN-RATE-LIMITED AXIS; ANY PLANE; THE SHELL); RELAY EXCHANGE RULE (BATON OPEN); TRIATHLON SCHEMA + SCORING + DISCOVERY GATE; NPC DRIVERS: ONE IDENTITY, PERSONALITY TRANSFERS, COMPETENCY PER DOMAIN, 3D RACECRAFT BOUNDED BY THE MACHINE; ONE RACE AT THREE FIDELITIES (ABSTRACT / TACTICAL / PHYSICAL); UNSEEN SNOWGLOBE HISTORY COMMITTED AS SEED MODS. `ncm_ls_space` 0.4.0 LIVE (rcon). IT IS NPC, NOT MPC (owner).**
- **THE ONE NEXT ACTION (owner):** FiveM: `/ncm.car`, F8 `ncm.machine sprint_dragster`, `ncm.race 5`, stop on the yellow lane marker at LSIA, five lights, hold TRIANGLE (§SP1). Then `ncm.machine fireball_racer`, `ncm.race 6` (§FB1).
- **Open for the owner:** L322 Q1 relay baton, Q2 Fireball credit (angle vs arc), Q3 point-to-point (open by design); L321 Q1 competency families; L320 Q1 compressed-Earth geography (bit twice now).

**EARLIER 2026-10-05 (19:10 ET) - L321 ENGINEERING II BUILT: MACHINES FROM PHYSICAL SYSTEMS (MASS, CoM, A 6-AXIS WRENCH FROM MOUNT POINTS, PROPELLANT, ENERGY, HEAT, FIRST FAILURE); THE HOP IS NOT A THRUSTER (GROUND / STORED / AIR / REACTION AS PHYSICAL PRECONDITIONS); LINEAGE + REVERSE ENGINEERING ACROSS WORLDS; THE SEED TREE + WORLD COMPOSITION; SNOWGLOBE MOTORSPORT (3D GATES, SEEDED STATIONS AND SKY RINGS, NPC RACES THROUGH PADDOCK.SIM WITH PROVENANCE, SPORT FROM THE CAPABILITY DISTRIBUTION); HOST EXPRESSION LOSSES. DOC 54. CORE ALL GREEN; `ncm_ls_space` 0.3.0 LIVE (rcon refresh + restart; nobody connected). KB-343 (pairs order broke cross-process seeds) FOUND LIVE AND FIXED.**
- **THE ONE NEXT ACTION (owner):** in FiveM, `/ncm.car` then hold TRIANGLE on the orbiter (§EG1); then `ncm.machine fan_car`, `ncm.race 3` and fly the Vinewood Sky Ring (§SR2).
- **Open for the owner:** L321 Q1 (engineer competency for propulsion / energy_storage / avionics, non-blocking); L320 Q1 (anchors ~370 m apart on a 5 km Earth); economy purses (proposal unbuilt).

**EARLIER 2026-10-05 (17:50 ET) - LOS SANTOS FLIGHT 1 (§LS1-§LS5): DOORWAY MOVE KEPT DRIVER + OWNERSHIP + VELOCITY; EARTH AND MOON SEEN; GTA's 150 m/s CAP CONFIRMED. L320 RULED: GRAVITY AS A CONCEPT -- COMPRESSED SNOWGLOBE EARTH (5 km, 1 g), RADIAL INVERSE-SQUARE, NCM UNIVERSE VELOCITY SEPARATE FROM GTA's, THE FRAME FOLLOWS THE PLAYER. BUILT AND LIVE (ncm_ls_space 0.2.0 via rcon). TRIANGLE-EXIT BUG FIXED. OPEN: NC and LS anchors are ~370 m apart on a 5 km Earth (L320 Q1).**
- **THE ONE NEXT ACTION (owner):** §LS7 (climb, coast, fall back) and §LS8 (orbit: pitch toward the horizon until sideways = orbit speed).

**EARLIER 2026-10-05 (17:30 ET) - L319: NCM LOS SANTOS STARTS WITH SPACE. BUILT AND SET UP ON THIS PC: FXServer 35245 + `ncm_ls_space` (NCM core unchanged in FiveM; lift from the F0 rig, torque attitude, server doorway/floating origin, universe altitude, inverse-square gravity, Earth/Moon/Sun stand-ins). Doc 53. NOT YET RUN.**
- **FXServer RUNNING on this PC since 17:10** (license authenticated; `ncm_ls_space` started, space.universe 0.2.0 loaded; log `tools/fivem/server-data/logs/fxserver-20261005-171012.log`).
- **THE ONE NEXT ACTION (owner):** FiveM client, F8 `connect localhost:30120`, F8 `ncm.car`, hold TRIANGLE (§LS1-§LS6).

**EARLIER 2026-10-05 (16:30 ET) - LOS SANTOS RECON 01 (research only): GRAND THEFT SPACE READ FROM SOURCE -- [docs/research/los_santos/GTS_RECON_01.md](../research/los_santos/GTS_RECON_01.md). GTS = fade + teleport to z 30 km + a camera-following sky dome + a floating origin within 2.5 km (velocity kept) + planets swapped as scenes; it depends on closed ASIs (gravity, bounds) that FiveM cannot run. Nothing in it is licensed for reuse. Five probes listed for when GTA Legacy is installed.**
- **THE ONE NEXT ACTION is unchanged:** the Snowglobe discriminating runs (L317 addendum 8). Los Santos probes wait on the owner.

**EARLIER 2026-10-05 (15:50 ET) - L318 ADDENDUM CAPTURED (DIRECTION ONLY): ONE ONLINE RACE WEEK ACROSS TWO CITIES (SHARED CLOCK, LOCAL CONSEQUENCES, A SHARED RESOLVER); SP AND ONLINE SHARE RULES, NOT TOPOLOGY; THE WORMHOLE IS 'WHAT ELSE COULD THERE BE?' IN SP AND 'WHAT DO YOU WANT?' ONLINE. Doc 52 §5; IDEA-1066 to IDEA-1077. Audit: Race Week identity is per server, and local consequences share state with the verdict -- door-keeping rules 6-10.**
- **THE ONE NEXT ACTION is unchanged:** the Snowglobe discriminating runs (L317 addendum 8).

**EARLIER 2026-10-05 (15:30 ET) - L318 CAPTURED (DIRECTION ONLY, NOTHING AUTHORISED): NCM / LOS SANTOS ON FIVEM AS A POSSIBLE SECOND RACING SERVER, WITH SNOWGLOBE AS THE SHARED PROTOCOL (NO THIRD SERVER). DOC 52 RECORDS THE DIRECTION, THE INTERFACES TO PRESERVE AND AN AUDIT: IDENTITIES ARE ALREADY ENGINE-INDEPENDENT; FOUR NARROWINGS NOTED, NONE URGENT. IDEA-1054 to IDEA-1065.**
- **THE ONE NEXT ACTION is unchanged:** the Snowglobe discriminating runs (L317 addendum 8).

**EARLIER 2026-10-05 (15:10 ET) - §SG8: SNOWGLOBE 0 WORKS -- THE HELLA REACHED 33,643 m UNIVERSE ALTITUDE (PAST THE 16,384 m CEILING; TWO REBASES), THEN A CLIENT CTD AT 14:56:57 (KB-341, null read in game code `+0x1FA56B`). 2^15 TESTED AND NOT SUPPORTED: 32,768 m was crossed 20 s / 900 m before the crash, and no REDengine-visible number was near it. NEW: vertical speed caps at 99.70 m/s and resets (KB-342).**
- **THE ONE NEXT ACTION:** the discriminating runs (L317 addendum 8): a climb kept under 99 m/s, a long hover at about 13.6 km with no offset, and a repeat of §SG8.

**EARLIER 2026-10-05 (14:36 ET) - SNOWGLOBE 0 IS LIVE ON DEV, AUTOMATIC, NO COMMANDS: CLIMB THROUGH 14 km AND THE SERVER REBASES YOU (FLOATING ORIGIN); THE ALTIMETER SHOWS UNIVERSE ALTITUDE PAST 16,384 m; FALL HOME BELOW 3 km. SPEED NOT CARRIED BY OWNER RULING (L317 addendum 7). KB-340: THE TOP-SPEED LOSS IS THE GEARBOX BAND, NOT CARRIER.**
- **THE ONE NEXT ACTION:** §SG8. Mash TRIANGLE straight up past 14 km, keep climbing, then fall home.

**EARLIER 2026-10-05 (14:15 ET) - THE DOORWAY IS AN ALTITUDE: `ncm.seamauto <pid> 3000 -2000` (ARM ON THE GROUND; CROSSING 3 km WHILE CLIMBING TRIGGERS THE SERVER MOVE + THE CARRIER RESTORE; RE-ARMS 200 m BELOW). SNOWGLOBE 0.0.4 ADDS AN ALTIMETER. DEV RESTARTED 14:08 (`l326-restart-20261005.stdout.log`, nobody on); 0.0.4 INSTALLED.**
- **THE ONE NEXT ACTION:** §SG7. Arm once on the ground, then mash TRIANGLE straight up; no typing in flight.

**EARLIER 2026-10-05 (02:00 ET) - §SG5: THE SEAM RESTORE PIPELINE RUNS END TO END, BUT CARRIER REFUSED THE KICK -- THE SERVER MOVE UNBINDS THE CAR UNTIL THE LEASE RETURNS (~4 s). v2 INSTALLED: CARRIER 0.1.36 HOLDS A TARGET VELOCITY UP TO 8 s AND APPLIES IT THE MOMENT THE CAR IS BOUND AGAIN (SNOWGLOBE 0.0.3).**
- **THE ONE NEXT ACTION:** §SG6. Climb hard above about 2,500 m (mash TRIANGLE), then in Warden `ncm.seam <pid> -2000`.

**EARLIER 2026-10-05 (01:41 ET) - THE OWNER RACED ON DEV: P3 OF 12, 6:11.494 (5:42.494 + 29.0 s incidents), ALL 77 GATES. SEAM-1c (THE VELOCITY KICK) BUILT AND INSTALLED: SNOWGLOBE 0.0.2 + CARRIER 0.1.35 (record `dev-mods/20261005-014114`).**
- **THE ONE NEXT ACTION:** §SG5. Climb above about 2,500 m, then in Warden `ncm.seam <pid> -2000`. Expect a jump, a freeze, then a kick; the RESULT line says how much speed was kept.

**EARLIER 2026-10-05 (01:25 ET) - SEAM-1b ANSWERED (§SG4): THE SERVER'S `setTransform` MOVE HOLDS AND KEEPS THE DRIVER; IT ERASES VELOCITY (83.6 -> 0 m/s) AND FREEZES THE CAR ABOUT 3 s (lease churn incl. `validationfailed`). NEXT: VELOCITY RESTORE ON LEASE RETURN, THEN THE FREEZE. The owner is racing on dev: NO restarts.**

**EARLIER 2026-10-05 (01:05 ET) - SEAM-1 ANSWERED: THE GAME'S TELEPORT MOVES THE OCCUPIED CAR AND KEEPS THE DRIVER, BUT OPEN//77's SERVER REVOKES IT IN THE SAME MILLISECOND (`motion_jump`) AND IT SNAPS BACK WITH NO SPEED (§SG2, L317 addendum 2). THE SEAM'S MOVE BELONGS TO THE SERVER: `ncm.seam <pid> <dz>` (`vehicles.setTransform`) LIVE: DEV RESTARTED 01:11 WITH THE OWNER'S CONSENT (log `l325-restart-20261005.stdout.log`; 9 NCM resources, 0 errors, 34 open races).**
- **THE ONE NEXT ACTION:** the owner rejoins, climbs above about 2,500 m, and runs `ncm.seam <pid> -2000` in Warden (§SG4).

**EARLIER 2026-10-05 (01:00 ET) - KB-339: THE OWNER JOINED 650 m UP (A SAVED MID-FLIGHT LOCATION) AND FELL TO 1 hp, TWICE. FIXED (`world.location.airborne`, 8 m/s vertical) + `ncm.heal <pid>`; LIVE: DEV RESTARTED 00:52 WITH THE OWNER'S CONSENT (log `tools/open77/server/l324-restart-20261005.stdout.log`; all 9 NCM resources started, 0 errors; Paddock 34 open races). SEAM-1 has not fired yet (no J above 3,000 m).**
- **THE ONE NEXT ACTION:** the owner rejoins; in Warden `ncm.heal <pid>` (its log line names the life phase and health ledger, which is KB-339's open half); then §SG2.

**EARLIER 2026-10-05 (00:40 ET) - L317 Q1 RULED (THE SEAM BEFORE F2-F3). BUILT, NOT INSTALLED: NCM SNOWGLOBE 0.0.1 (SEAM-1: KEY J MOVES THE OCCUPIED CAR 2 km DOWN MID-AIR WITH THE GAME'S TELEPORT AND MEASURES VELOCITY + SEAT) AND `space.universe` 0.1.0 (6 TESTS, VENDORED).**
- `dist/ncm-snowglobe-0.0.1.zip`: the redscript compiles against vanilla plus every installed script; the natives check passes; 0 warnings. Gate ALL GREEN.
- **INSTALLED 00:40** (record `%LOCALAPPDATA%/NCM/dev-mods/20261005-004015`).
- **THE ONE NEXT ACTION:** launch (§SG1). Then climb above 3,000 m with TRIANGLE and press J while rising (§SG2), and again while falling (§SG3).

**EARLIER 2026-10-05 - L317 CAPTURED (SPEC): THE CEILING IS A DOORWAY. ABOVE A TRANSITION ALTITUDE NCM OWNS POSITION AND REDENGINE SIMULATES A LOCAL BUBBLE (FLOATING ORIGIN); THE SEAM FIRST; MOON THEN SUN (IDEA-1048 to IDEA-1053). NOTHING BUILT.**
- Coder constraints recorded in L317: Night City cannot be shifted, so the city leaves view before any rebase. Moving an occupied car while keeping its velocity is unproven (SEAM-1).
- **THE ONE NEXT ACTION:** the owner rules L317 Q1 (seam before F2-F3?). Then SEAM-1.

**EARLIER 2026-10-04 (23:55 ET) - S0's FIRST ANSWER: THE OWNER FLEW THE HELLA TO NIGHT CITY'S CEILING, z = 16,384 m (2^14), BY MASHING TRIANGLE (2,377 burns, 92 m/s climb, 0 faults). AT THE CEILING THE PLATFORM REVOKES THE CAR'S AUTHORITY EVERY ~2.3 s AND THE SESSION DROPS TO THE MENU (KB-338). L316 addendum 3; MASTER_TEST §AX4.**
- **THE ONE NEXT ACTION:** settle whether 2^14 is the engine's or Open77's: the same climb in single player (vanilla + NCM Thrust/Carrier where they load), and the server's `serverrevoke` cause. §FL4 (hop while driving) and §FL5 (TRIANGLE) also stand; TRIANGLE effectively passed in §AX4 (`requested (pad)`).

**EARLIER 2026-10-04 (23:20 ET) - §FL3 PASS: THE SPRINGS ALONE LIFT THE HELLA 0.12 m (r = 1.0); r = 3.0 RUNS A STEADY x1.25 OVER FREE-BODY. TRIANGLE IS THE VERTICAL ACTION (IDEA-1047): NCM THRUST 0.0.2 BUILT, NOT INSTALLED.**
- **INSTALLED 23:24** (record `%LOCALAPPDATA%/NCM/dev-mods/20261004-232434`): `ncm-thrust-0.0.2` (pad TRIANGLE / XInput Y + H; the owner's 3.0 / 200 ms) and `ncm-carrier-0.1.34` (KB-337).
- **THE ONE NEXT ACTION:** launch and drive: §FL5 (TRIANGLE) and §FL4 (hop while driving). F1 must add the suspension term to `actuate.hopPrediction` before any player-facing number.

**EARLIER 2026-10-04 (23:05 ET) - THE HELLA HOPS: F0 PASSES (§FL1-§FL2, owner "hop confirmed"). 9 burns measured, 0 faults; rise from rest is about 1.9x the free-body prediction because of the suspension (L316 addendum 2). KB-337 (lost burn log lines) is fixed in Carrier 0.1.34, built, not installed.**
- **THE ONE NEXT ACTION:** §FL3. In the running game, edit `red4ext/plugins/ncm_thrust/ncm_thrust_config.json` to `"twr": 1.0` and press H once (that measures the suspension's share), then `"twr": 3.0`. Then §FL4 (hop while driving). Install Carrier 0.1.34 at the next game quit. The gearbox §GB22 is still owed.

**EARLIER 2026-10-04 (late) - L316 RULED (Q1 dev-only experiments, Q3 wormhole != rollover, Q4 you keep the car you are in; Q2 left to S0) AND THE LADDER REORDERED: F0, THE HOP, IS BUILT (NCM THRUST 0.0.1 + CARRIER 0.1.33 LIFT LEVER); S0 INSTRUMENTS BUILT. NOT INSTALLED; NO LIVE PASS. DOC 51 IS THE SPEC.**
- Packed: `dist/ncm-thrust-0.0.1.zip` and `dist/ncm-carrier-0.1.33.zip` (= 0.1.32 + the lift lever; the gearbox path is untouched).
- **INSTALLED on this PC 23:02** (record `%LOCALAPPDATA%/NCM/dev-mods/20261004-230238`; `--uninstall` restores Carrier 0.1.32). RED4ext ignores none of them.
- Not yet on dev: the S0 instruments (`/ncm.altlog`, `ncm.lift`) load at the next dev restart.
- Gate ALL GREEN.
- **THE ONE NEXT ACTION:** the gearbox §GB22 is unchanged. At the owner's next game quit, install both zips (§FL1) and press H in the Hella (§FL2: predicted apex 0.20 m). Then §FL3-§FL4. Then S0 (§AX1-§AX5) after a dev restart.

**EARLIER 2026-10-04 (late) - L316 CAPTURED: NCM SNOWGLOBE, THE STARRY SKY, THE SERVER-WIDE DEV WORMHOLE (WHOLE SERVER FOLLOWS), PHYSICS-BASED FLIGHT (IDEA-1034 to IDEA-1042, SPEC). NOTHING BUILT.**
- It conflicts with L314 ("flight ... not to be implemented"). Q1-Q4 are open in DECISION_RECORD L316. Carrier's proven force write (`physics_probe.cpp`) makes the hop experiment (F0) small.
- (Ruled in the addendum above.)

**EARLIER 2026-10-04 (22:09 ET) - GEARBOX 0.3.1 INSTALLED (the band's rpm window, live-tunable); L315 CAPTURED: THE SKIPPING TAPE ON A SLIDING SCALE, ESCALATING SENSITIVITY, THE ERA SLIDER, FLIGHT INTO SPACE AND A NEW SEED (IDEA-1025 to IDEA-1033, SPEC).**
- **L315 Q1-Q4 RULED (addendum):** continuous early ending (time scale and survival are separate axes; changes L310's built rule); sensitivity continuous in normalized age; one week core with per-server clocks; flight discovered through engineering. Amendment: the anomaly is seeded geography (IDEA-1031). Nothing authorized to build.
- **THE ONE NEXT ACTION (gearbox):** the owner drives §GB22 and tunes `manual.band`.

**EARLIER 2026-10-04 (21:31 ET) - GEARBOX 0.3.0 INSTALLED: `band`, THE GAME VOICES OUR GEARS (one writer, no tape-skip, if the gear re-reads live).**
- **THE ONE NEXT ACTION (gearbox):** the owner drives §GB21. The owner has another idea pending this result.

**EARLIER 2026-10-04 (21:10 ET) - NO PADDOCK RACES SINCE THE 19:00 BOOT (KB-336): THE BOOT THREAD DIED ON THE QUOTA; FIXED AND LIVE (dev restarted 21:10, log `l323-restart-20261004.stdout.log`). GEARBOX 0.2.9 INSTALLED (HUD SHOWS THE LIVE CURVE / CONFIG ERROR).**
- KB-336: `ncm_paddock` hit `instruction quota exceeded` 8 s after boot and never ran. Boot steps now yield; races.load yields every 20 races. Gate ALL GREEN. Nobody on dev at 21:04.
- Gearbox: the curve was never actually heard -- every successful reload after 20:47 had `follow 1.00` (the curve switched off), then the file stopped parsing (`gamma: 01111111`). 0.2.9 puts the live values, a FOLLOW 100% warning and CONFIG ERROR on the HUD.
- **THE ONE NEXT ACTION:** the owner tunes §GB20 with `follow` below 0.5 (races are running again).

**EARLIER 2026-10-04 (20:42 ET) - GEARBOX THREAD: 0.2.8 INSTALLED -- ONE CONTINUOUS ENGINE VOICE (`curve`), TUNED LIVE FROM THE CONFIG FILE WHILE DRIVING. (Engineering thread: the 19:30 entry below.)**
- The 0.2.7 blend was "the right idea" but "chopped" (§GB19). 0.2.8 slides one smoothed value from lo to hi across each gear, partly following the game's own rpm. Edit `manual.curve` in the installed config, save, and it reloads in-game.
- **THE ONE NEXT ACTION (gearbox):** the owner tunes §GB20 by ear and reports the best values; they become the defaults. §GB17 (top speed, neutral) is still unreported.

**EARLIER 2026-10-04 (20:31 ET) - GEARBOX THREAD: 0.2.7 INSTALLED ON THIS PC -- THE BLENDED ENGINE VOICE; THE GAME OWNS THE DASH AGAIN; ONE SOURCE OF TRUTH FOR SPEED RULED. (The engineering thread's latest is the 19:30 entry below.)**
- Owner rulings (L306 addendum 20:31): no mirrored gears; the four sound presets compose into one crescendo (`blend`, the default; `manual.blend` in the config); the dash's rpm, gear and speed are the game's; the dash speed is NCM's one source of truth (IDEA-1023; KB-334 for the Online gap). IDEA-1024 = the composable engine voice.
- KB-335: Warden's restart leaves dev down (exit 10, no supervisor).
- **THE ONE NEXT ACTION (gearbox):** the owner drives §GB19 (the blend). Then tune `manual.blend` from what they hear and the `trace:` lines. Top speed and neutral (§GB17) are still unreported.

**EARLIER 2026-10-04 (19:30 ET) - L314 RULED (R1-R5 + CAUSE/ACTUATOR/STATE/COARSE). ENGINEERING STEPS 2-5 BUILT OFFLINE: `ncm/core/engineering/` body, envelope, drivetrain, fit, actuate, fixtures; 15 tests; gate green; vendored. DOC 50 IS CURRENT.**
- Nothing reads the modules at runtime yet; no live behaviour changed. Fixture geometry is illustrative (IDEA-1022: survey the real cars).
- E1 is still unrun (§EN1). **Dev restarted 19:00 ET** (owner: "its free"), logging to `tools/open77/server/l322-restart-20261004.stdout.log` again. Every league subsystem booted, with one pre-existing `ncm_paddock` quota error (46 in the previous boot). `/ncm.mass` and `/ncm.massrun` are live on the next join.
- **THE ONE NEXT ACTION (engineering):** the owner runs §EN1 after a dev restart. Then step 6, the read-only Hella/Quadra puzzle surface, which wants real envelopes first (IDEA-1022). The Gearbox thread (§GB18) continues in its own session.

**EARLIER 2026-10-04 (18:40 ET) - ENGINEERING ARCHITECTURE PASS STARTED: E1 INSTRUMENT BUILT, DOC 50 PROPOSED (R1-R5 OPEN). THE GEARBOX THREAD (§GB18) CONTINUES IN ITS OWN SESSION.**
- E1 from the logs: live mass = the record's `total_mass` (Hella 1800 kg). Unknown: whether a changed record mass changes the driving.
- `/ncm.mass` and `/ncm.massrun` (ncm_world client) are in the tree and NOT yet on a client. Dev reads the tree through its junction, but its current run (17:53) logs to the console only, so connected players could not be checked and dev was not restarted.
- **THE ONE NEXT ACTION (engineering):** at the next dev restart, the owner runs §EN1. In parallel, the owner reads doc 50 and rules R1-R5. After that, `engineering.body` / `envelope` / `fit` as pure core with fixtures (doc 50 §10.2-§10.4).

**EARLIER 2026-10-04 (18:10 ET) - THE HELLA IS A 7-SPEED (refit applied by the owner; log `in a m7`); GEARBOX 0.2.6 INSTALLED: A LIVE ENGINE-SOUND EXPERIMENT.**
- The engine note still has no ramp on the m7 (KB-333). 0.2.6: PAGEUP cycles the sound scale (rpm / limiter / fraction / off), the HUD names it, and a `trace:` line a second logs the game's own blackboard rpm beside ours.
- Dev was restarted at 17:53 (minimized console window; its log is console-only). Warden's restart exits with code 10 and nothing relaunches dev (needs a KB).
- **THE ONE NEXT ACTION:** the owner drives §GB18, cycling PAGEUP. Then read the `trace:` lines and fix the scale from data. Top speed and neutral (§GB17) are still unreported.

**EARLIER 2026-10-04 (evening) - GEARBOX 0.2.5 + CARRIER 0.1.32 BUILT AND PACKAGED, NOT INSTALLED: THE HELLA'S 7-SPEED, MANUALS THAT REACH THEIR AUTOMATIC'S TOP, THE ENGINE NOTE IN RPM, NEUTRAL KEEPS ITS GRIP.**
- Owner QA of 0.2.4: shift feel ok, a solid 5-speed; engine mute (KB-333); rotation in N (KB-332); capped near 115 where the automatic did 140+ (KB-331).
- `dist/ncm-gearbox-0.2.5.zip`, `dist/ncm-carrier-0.1.32.zip`. Core `machine.gearbox` gained `m7` and `REFIT` (vendored). `ncm.gearbox find|refit` added to ncm_league.
- **THE ONE NEXT ACTION:** the owner quits the game. Then: hand-install both zips (`python tools/dev-hand-install-mods.py --only none --extra-zip dist/ncm-gearbox-0.2.5.zip --extra-zip dist/ncm-carrier-0.1.32.zip`), restart dev (check for players first), `ncm.gearbox find archer_hella`, `ncm.gearbox refit <assetId> m7`. Then the owner drives §GB17.

**EARLIER 2026-10-04 (evening) - CIVIL ENGINEERING C1-C4 RULED; THE NIGHT CITY SEED MAP AND EVIDENCE-WEIGHTED INFRASTRUCTURE AWARENESS CAPTURED (L313 addendum, doc 49 §8). NOTHING BUILT.**
- Civil engineering joins the Engineering Architecture pass. Anyone builds, and anyone dismantles (on site, per component), for modest money. Every contribution and its effect on races is recorded.
- End of each cycle: export a seed map (built infrastructure + danger heatmap incl. free-roam driving incidents + pins). At rollover the operator picks a seed, or a random draw between known seeds and a blank slate, announced in chat.
- The race sim believes infrastructure effects only in proportion to observed evidence. The wild west at the start. IDEA-1000 to IDEA-1008.
- **THE ONE NEXT ACTION is unchanged:** the owner drives the Hella (§GB16). Then shift feel. Then the Engineering Architecture pass (doc 48 §5), now with civil engineering as its second domain.

**EARLIER 2026-10-04 (evening) - CITY MEMORY Q1-Q4 RULED (L312 addendum) AND CIVIL ENGINEERING CAPTURED (L313), BOTH IN DOC 49. NOTHING BUILT.**
- Rulings: scar clusters (segment + 8-12 m configurable radius + context) with accumulated burden; v0 is physical incidents only; the scar ledger ends with the campaign and distils into knowledge; Campaign A/B by hand before any automation. Q5 (casualties, memorials) is open.
- Civil engineering: engineering pointed outward. A six-piece snapping kit judged by the race, one grammar with doc 48, attribution not saboteur roles, friction not caps. C1-C4 are open. IDEA-973 to IDEA-999.
- Correction: the incident position is lost one hop earlier than first written. `ncm/core/session/race.lua:328/331` (and `quali.lua:116`) drop x/y/z before `ncm_league/server/race.lua:833` sends a bare count.
- Prerequisite for any civil engineering: E19 (does a placed barrier stop a car?) has never run.
- **THE ONE NEXT ACTION is unchanged:** the owner drives the Hella (§GB16). Then shift feel. Then the Engineering Architecture pass (doc 48 §5).

**EARLIER 2026-10-04 (16:25 ET) - GEARBOX 0.2.4 INSTALLED ON THIS PC: OWN GEAR INDICATOR, ENGINE NOTE AS A 0..1 FRACTION, A REAL R-N-1..n SELECTOR; NOT YET DRIVEN.**
- **THE ONE NEXT ACTION:** the owner drives the Hella (§GB16). Then shift-feel tuning. Then the Engineering Architecture pass (doc 48 §5), starting with E1 (mass).

**EARLIER 2026-10-04 (15:53 ET) - GEARBOX 0.2.3 INSTALLED ON THIS PC: DASH WRAPPERS, PROGRESSIVE GEAR SPACING, THE CAR'S OWN SHIFT SOUNDS, ENGINE AUDIO FROM THE VIRTUAL REVS; NOT YET DRIVEN. L311 Q1-Q5 RULED.**
- **THE ONE NEXT ACTION:** the owner drives the Hella (§GB15). Then shift-feel tuning. Then the Engineering Architecture pass (doc 48 §5), starting with the mass measurement (E1).
- Dev runs the old core gearbox labels until its next restart. The DLL's spec file, which drives the car, is already new.

**EARLIER 2026-10-04 (15:45 ET) - THE MANUAL IS REAL (owner); GEARBOX 0.2.2 PUTS ITS GEAR AND REVS ON THE DASH; ENGINEERING ENVELOPE CAPTURED AS SPEC (L311, doc 48).**
- The owner drove the manual Hella. The log shows `in a m5`, Carrier `levers found`, and over-rev downshifts refused. But the dash showed nothing: the blackboard write lost to the game's own.
- 0.2.2 wraps every vanilla dash gear and rpm callback (10 wrappers, compiled) to draw the virtual gear and rpm. Installed. Not yet seen live.
- The m5 bands are cramped (35/47/63/85/115 km/h). Retune is owed.
- Audio (one long drone) and shift sounds are open (IDEA-972).
- **THE ONE NEXT ACTION:** the owner drives the Hella and says whether the dash shows N/1-5 and the revs (§GB14). Then the manual's audio and shift feel. Then the Engineering Architecture pass (doc 48 §5) on the owner's word.

**EARLIER 2026-10-04 (15:33 ET) - THE OWNER'S DEV HELLA IS A 5-SPEED MANUAL; CLONES ON BY DEFAULT IN DEVELOPMENT; PAD X/A SHIFTING (GEARBOX 0.2.1); NO LIVE PASS.**
- **THE ONE NEXT ACTION:** the owner calls the Hella and drives it (§GB14). No console commands.

**EARLIER 2026-10-04 (15:05 ET) - THE MANUAL IS BUILT (L306 addendum): ONE LONG NATIVE GEAR + VIRTUAL GEARS THROUGH CARRIER; GEARBOX 0.2.0 + CARRIER 0.1.31 INSTALLED ON THIS PC; DEV RESTARTED; NO LIVE PASS.**
- KB-330: my native gear writes crashed the game twice. That approach is retired, and writes are disabled.
- **THE ONE NEXT ACTION:** in Warden, `ncm.gearbox clones on` and `ncm.grant <pid> Vehicle.v_standard2_archer_hella_ncm_gbx_m5`; then call the car and drive it, with LShift up and LCtrl down (§GB14).

**EARLIER 2026-10-04 (14:47 ET) - GEARBOX: THE GEAR IS FOUND (ONE BYTE, `0x2D0:0x3A4`) AND HOLDING IT BEATS THE AUTOMATIC, WITH FLICKER (§GB12 PASS); 0.1.3 (PHYSICS-STEP HOLD, A/B TRIAL) INSTALLED; NOT RUN.**
- **THE ONE NEXT ACTION:** the owner drives in 2nd or higher, keeps the throttle down through the four 6 s holds, and sends the newest log (§GB13).

**EARLIER 2026-10-04 (14:36 ET) - GEARBOX 0.1.2 INSTALLED: THE SCAN CONVERGED ON 2 FIELDS (UNNAMED, A REPORT BUG); 0.1.2 NAMES THEM AND RUNS A 6 s HOLD TRIAL ON EACH.**
- **THE ONE NEXT ACTION:** the owner drives up through 1-4, then keeps accelerating in 2nd/3rd for about 20 s, and sends the newest `ncm_gearbox-<pid>.log` (§GB12).

**EARLIER 2026-10-04 (14:28 ET) - GEARBOX: S1 HALF ANSWERED, THE GEAR HAS NO NAME; 0.1.1 (FIND IT BY VALUE) INSTALLED ON THIS PC; NOT RUN.**
- The owner's drive (`ncm_gearbox-53060.log`): the DLL loads and all 44 clones build (§GB4 PASS). The census (§GB9 PASS) finds no gear field and no gear setter in RTTI.
- 0.1.1 correlates the car's raw memory, one pointer deep, against the HUD gear.
- **THE ONE NEXT ACTION:** the owner drives one car up through 1-4 and back twice, steps out, and sends the newest `ncm_gearbox-<pid>.log` (§GB11).

**EARLIER 2026-10-04 (14:21 ET) - NCM GEARBOX 0.1.0 (PHASE 3a: FIND THE GEAR) BUILT AND INSTALLED ON THIS PC; NOT RUN.**
- Holding a gear needs to know where the engine keeps it, and nobody does. 0.1.0 asks:
  - an RTTI census;
  - a per-frame observe of the player's car against the HUD gear;
  - a hold experiment, off until the config names a field.
- **THE ONE NEXT ACTION:** the owner launches, drives through the gears for a minute, and sends `ncm_gearbox-<pid>.log` (§GB9). Then the hold experiment (§GB10), then the manual's input, clutch, neutral and HUD.

**EARLIER 2026-10-04 (14:13 ET) - NCM GEARBOX SPIKE INSTALLED ON THIS PC (owner asked); dev restarted at 14:08 with the Observer panel + KB-329 (log `l319-restart-20261004.stdout.log`).**
- `dev-hand-install-mods.py --only none --extra-zip dist/ncm-gearbox-0.0.1.zip`: `ncm_gearbox.dll`, `ncm_gearbox_specs.json`, `r6/tweaks/ncm_gearbox/clones.yaml`. Record: `%LOCALAPPDATA%/NCM/dev-mods/20261004-141309`.
- **NEXT:** launch the game and read `red4ext/plugins/ncm_gearbox/ncm_gearbox-<pid>.log` (MASTER_TEST §GB4). If the game will not start, run `--uninstall`.

**EARLIER 2026-10-04 - OBSERVER PANEL (F3) + KB-329 FIXED IN CODE; NOW LOADED (14:08 restart); NO LIVE PASS.**
- Owner QA of Observer: the tester got no NCM Pace (KB-329: two games on one PC; a Pace page with no handshake timeout), so the ghost watched model cars over an empty road. When the race ended, the camera froze silently.
- Built:
  - the iRacing-style F3 panel (races, running order, cameras, director) and the strip;
  - rebindable hotkeys;
  - the KB-329 handshake timeout;
  - the silence fixes.
- KB-4 does not reproduce with the launcher's dev values.
- **THE ONE NEXT ACTION:** a restart to load ncm_paddock + ncm_observer (both clients reconnect), then §OB9-§OB12. To enter from the owner's own client, put its user id in `observerAllow`.

**EARLIER 2026-10-04 (08:41 ET) - DEV RESTARTED: L306 + L308 + L310 LOADED (log `tools/open77/server/l318-restart-20261004.stdout.log`); NO LIVE PASS.**
- Migrations 063 + 064 applied. `ncm_observer ready (allow="")`. `RUN 1 predates Moody: first roll at hour 21`. Radio: `[buoyant / money]`. Expected rate 0.49 crashes/race, 7.1 races/h. Paddock world loaded, 20 open races. Gearbox shelf stamped (144 cars, 35 manual, gated). 0 errors.
- The owner (player 2) was kicked by the restart, with consent.
- **THE ONE NEXT ACTION:** the owner tests MASTER_TEST §MW1-§MW10, §OB1-§OB8 and §GB1-§GB3. Run 1's first verdict is Tue 10-06 12:00 ET.

**EARLIER 2026-10-04 - MOODY, THE VERDICTS AND THE SEVEN-DAY TIMELINE BUILT (L310).**
- A run now ends where a recorded verdict says: each noon from Day 3 to Day 7, p from the state, one seeded draw.
- Moody rolls a public D20 every 4 h. Its faces change purses, calendar, police and limits, and each NPC weighs a lure for themselves.
- Reservoirs feed the curve; the racing radio composes the city's mood every two hours.
- Harness, 20k unattended runs: Day 4 0.26, Day 7 1 in 142. Gate ALL GREEN. Schema 064.
- Q6 defaulted: finales before every possible end.
- **THE ONE NEXT ACTION:** the owner restarts dev at a moment of their choosing. That loads L306 + L308 + L310 and migration 064. Then:
  - MASTER_TEST §MW1-§MW10 (Moody, verdicts) and §OB1-§OB8 (Observer);
  - dev's run 1 meets its first verdict at Tue 10-06 12:00 ET (§MW6).
- The collapse is still `dryrun`.

**EARLIER 2026-10-04 - MOODY CAPTURED AS SPEC (L309, doc 47, IDEA-946-IDEA-957); NOTHING BUILT; SUPERSEDES DOC 45 §0.5-§0.6 (OWNER RULING).**
- Racing Week becomes seven advertised days. Hour 72 is an attractor, not a rule. A seeded, state-read continuation judgement runs at each noon. Moody's D20 changes conditions, never outcomes.
- Ruled (L309 addendum): doc 47 supersedes doc 45 §0.5-§0.6; crowns at every collapse; a countdown before every possible end; reservoirs only where facts feed them. Q6 (the finales) is open. Build order: doc 47 §6.
- **The one next action is unchanged:** the dev restart for L306 + L308, then §OB1-§OB8 with `ncmtester2`.

**EARLIER 2026-10-04 - NCM OBSERVER SLICES 1-2 BUILT (L308): THE MODE, THE EXCLUSION, THE DIRECTOR, THE LENS; NOT DEPLOYED; NO LIVE PASS.**
- New resource `ncm_observer` plus core `observer.director` (11 tests). `ncm_paddock/racers.lua` now carries each car's distance, gap and vehicle id, and raises the snapshot server-side. One observer check added to each of the three driver lookups (league, Paddock, world).
- Gate ALL GREEN. Dev not restarted: L306 is also waiting on the owner's moment.
- **THE ONE NEXT ACTION:** at the owner's chosen restart (which also loads L306), launch `ncmtester2` through the launcher, then `ncm.observer on <pid>` and `ncm.observe <pid> auto` from the console (MASTER_TEST §OB1-§OB8).
- Not built yet: lane cameras and curation, deterministic commentary with the voice bridge, OBS overlays, the TV loop.

**EARLIER 2026-10-04 - NCM OBSERVER CAPTURED AS SPEC (L307, doc 46, IDEA-928-IDEA-941); NOTHING BUILT.**
- Observer is a non-participating client (`ncmtester2`) that goes to a race, makes it physical through the existing bubble, films it, feeds Radio OS and OBS, and loops the program back onto OPEN//77 TVs.
- Ruled (L307 addendum): commentary is deterministic with an optional voice bridge, and needs no Python; Observer is an on-demand client mode, never accidental. O-2 awaits the owner, O-3 is open. First step if authorised: `ncm.tp` the tester client to a distant dev race (G1 + G2).
- **The one next action is unchanged:** the L306 dev restart and the gearbox spike opt-in below; then the Online hotfix yes/no (L305).

**EARLIER 2026-10-04 (07:30 ET) - NCM GEARBOX (L306): OUR OWN MANUAL TRANSMISSION, PER MACHINE; PHASES 0-1 BUILT, NOT DEPLOYED; NO LIVE PASS.**
- Every car is born automatic or manual: `vehicle_asset.gearbox_*` (schema 063); owned cars → `pre_gearbox` automatic.
- A manual is its own clone record with 4-8 real gears. The market lists `Galena · automatic` and `Galena · 6-speed manual` as separate cards, with manual sales gated as ARRIVING.
- Spike DLL `ncm/gearbox` 0.0.1 builds the clones at game start. It is packed in `dist/`, never loaded, and not installed.
- Gate ALL GREEN. Dev not restarted: the owner was connected at 07:20.
- **THE ONE NEXT ACTION:** the owner picks a moment to restart dev for L306 (L305 is already loaded; §GB1-§GB3), and opts in to the spike (§GB4: install the zip, launch, send `ncm_gearbox-<pid>.log`).
- The Online purchase hotfix (L305) still awaits the owner's yes.

**EARLIER 2026-10-04 (06:20 ET) - EARNED RESULTS, NATURAL PACE, A LIVING NPC ECONOMY (L305); LOADED ON DEV; ONLINE HOTFIX BUILT, AWAITING THE OWNER'S YES; NO LIVE PASS.**
- Dev boot `tools/open77/server/l317-restart-20261004.stdout.log` loaded:
  - simulated races are flagged like live ones;
  - human-anchored pace (regional 21.2, street 22.5 m/s);
  - crash facts from physical races and the learned crash rate (0.49);
  - the wrong-machine warning;
  - team car budgets plus running costs (7 team cars bought in 11 minutes).
- Gate ALL GREEN.
- **THE ONE NEXT ACTION:** the owner says yes or no to the Online hotfix. It covers KB-328/KB-323's hunks only: `markets.lua` + `exchange.lua` against `online-baseline-2`, built in `$TEMP/hotfix`. On yes: DB backup, copy, restart, then confirm 1690 = 0 in the log.
- Then §RW17-§RW20. Watch that the flag fires on a spread sim field (unobserved so far) and that team car buying settles after the first burst.

**EARLIER 2026-10-04 (02:15 ET) - EVERY RACER ON THE MAP (L304); NPC PART PURCHASES FIXED (KB-328); LOADED ON DEV; NO LIVE PASS.**
- Racer pins: every running race's cars on the map every 2 s (tier icons, humans white, your race green). Boot `tools/open77/server/l316-restart-20261004.stdout.log`: `1 race(s), 12 car(s) on the map`. Live check owed: §RW16 (does the minimap show them?).
- KB-328 cause and fix: the shop seeded new independents' cash in memory and then bought against the unsaved database; it now saves first. No SQL 1690 since.

**EARLIER 2026-10-04 (00:10 ET) - KB-327 FIXED: the owner's car vanished because ncm_world hit its 64 MB Lua quota (L301's 12 MB lane index); speed limits now live in their own resource `ncm_speed` with a 3.8 MB compact index. Dev mods restored (KB-326). KB-328 (NPC part purchases, SQL 1690) open.**
- Dev boot `tools/open77/server/l313-restart-20261004.stdout.log`: clean; ncm_world, ncm_speed (`lane index ready`), Paddock S4.
- After any NCM Online session, close the game and run `python tools/dev-hand-install-mods.py` before joining dev (KB-326).

**EARLIER 2026-10-03 (23:25 ET) - W-1..W-4 RULED (L303): CHAMPIONS CROWNED AT HOUR 72, THE HALL OF CHAMPIONS, MAIMAI SPEC, THE MONEY CRAZE, THE COLLAPSE (DRY-RUN) AND THE ENDING; LOADED ON DEV; NO LIVE PASS.**
- Built (doc 45 §O-§P):
  - noon ET runs (run 1 = Sat 10-03 12:00 -> Tue 10-06 12:00 ET);
  - the Cup = the run (`2026-S4-RW001`), with double-points finales and the Hypercar finale last;
  - the crown for NPCs and humans, the hall of champions (schema 061) and `topic_champion` voices;
  - MaiMai Cup spec cars for NPCs and humans;
  - money craze purses;
  - `week.collapse` + the league orchestrator, **dryrun by default**, with the Paddock archive into `<server>#R<n>` and a restart into the historical seed (schema 062);
  - `/ncm.anchor`;
  - the countdown / freeze / glitch / KIMIKO ending (`ncm.week rewind`).
- Defect caused and contained: KB-324 (a bad tunable `apply` value booted the stale `ncm-dev` world for 2 min). Fixed and guarded by the boot refusal and `tools/test-server-sandbox.lua`. KB-323 (Exchange trades hit the quota) is open, not mine.
- Dev boot `tools/open77/server/l310-restart-20261003.stdout.log`: clean, world `ncm-devbox` S4, collapse `dryrun`. Gate ALL GREEN.
- **THE ONE NEXT ACTION:** the owner runs `ncm.week.collapse plan` and `/ncm.anchor` (§RW13), then the speed/population tests (§RW1-§RW9).
  - Dev's run 1 ends Tue 10-06 12:00 ET: the first real crown and a dry-run collapse (§RW12).
  - Live collapse only on the owner's word, after reading that plan, with a DB backup (§RW15).
  - Hold dev -> Online until the §RW cases pass.

**EARLIER 2026-10-03 (22:25 ET) - RACING WEEK IS A CONTINUOUS 72-HOUR CURVE (L302): HISTORY'S CARRIER + THIS RUN'S LIVE SIGNAL; LOADED ON DEV; NO LIVE PASS.**
- Built (doc 45 §N):
  - `week.curve`: tolerance = carrier + a bounded deviation pushed by what racing did, human or NPC;
  - the organisers' announced steps (×0.75 → ×1.6 → ×1.0 → ×0.8; penalty → warning → police), latched and fired early by a bad week;
  - police discretion from tolerance;
  - `ncm_world/server/week.lua` and schema 060 (run state + provenance);
  - fact feeds from league, Paddock, chrome and speeding;
  - official chapter labels on the sign.
  - The expected crash cost is measured: 0.50 per Paddock race.
- Dev restarted (log `tools/open77/server/l307-restart-20261003.stdout.log`): `RUN 1 opened at hour 16.39`, `ANNOUNCE opening`, carrier 0.792, no errors. Gate ALL GREEN.
- **THE ONE NEXT ACTION:** the owner joins dev and runs MASTER_TEST §RW1-§RW9 from Warden's live console (`ncm.week day 1/2/3`, `ncm.week`, `ncm.probe.crowd corpo 15` ...).
  - Hold dev → Online until they pass: these resources sit in `ncm/*` and would ship with the next push.
  - Then E7 (Pace, game closed) for NPC compliance; W-1 / W-4 are still owed for the reset behind the rewind.

**EARLIER 2026-10-03 (22:05 ET) - RACING WEEK: ADVERTISED SPEED LIMITS v1 AND THE POPULATION PROBE LOADED ON DEV (L301); GATE ALL GREEN; NO LIVE PASS.**
- Built (doc 45 §M):
  - the derived Day (`week.clock`; `ncm.week <0..3>` pins it);
  - posted limits from the game's 19,432 vehicle lanes (`tools/gen-lane-limits.py`);
  - the Day's sign on the HUD;
  - proportional NCPD wanted capped per Day;
  - Day-1 speeding incidents (schema 059) and Day-2 warnings in races;
  - a `speeding` trajectory signal.
- Also built: the dev-only probe `prototypes/ncm_dev_probe` (E1-E5).
- Dev restarted twice. The first boot died on `os` in the server sandbox (KB-322, fixed). The second (log
  `tools/open77/server/l306-restart-20261003.stdout.log`) was clean: migration 059, `lane index ready: 19432 lanes ... 3.2 s`, `WEEK run=1 day=1`, probe ready.
- **THE ONE NEXT ACTION:** the owner joins dev and works through MASTER_TEST §RW1-§RW8 from Warden's live console:
  - `ncm.probe.crowd corpo 15` at Corpo Plaza, then `clip` / `pop` / `dress`;
  - the sign at `ncm.week 1/2/3`;
  - a Day-1 and a Day-2 street race.
  Then E7 (a Pace publish, game closed) for NPC compliance; W-1 / W-4 are still owed.

**EARLIER 2026-10-03 (evening) - RACING WEEK SITE POPULATION: A SEEDED JIGSAW; WOLVENKIT HARVEST OF 1,542 VANILLA SOCKETS; NOTHING BUILT.**
- Read [RACING_WEEK_SITE_POPULATION.md](../research/open77/RACING_WEEK_SITE_POPULATION.md) and doc 45 §L. Native Communities are baked and client-local, so they are data, not the controller. Server NPCs + workspots + props + effects + sound are the runtime. `tools/harvest-site-sockets.py` (read-only, WolvenKit CLI) wrote `docs/research/open77/evidence/site_sockets.json`. IDEA-875 to IDEA-884.
- Then: experiments E1-E6 on dev (E1 first: 15 crowd NPCs at Corpo Plaza's harvested sockets, two clients) once the owner wants to start; W-1/W-4 rulings still owed.

**EARLIER 2026-10-03 - RACING WEEK (L300): THE OWNER'S THREE-DAY RECONSTRUCTION SPEC AUDITED; PROPOSAL 45 WRITTEN; NOTHING BUILT.**
- Read [45_RACING_WEEK.md](45_RACING_WEEK.md) (PROPOSAL, sections A-K). Finding: the Paddock already holds ~70% of it (the real-time clock and idempotent daily step, seeded climate rolls, a hidden trajectory, Spotlight, the tagged voice bank, and the Index knowledge/possession split). Recommended: the NPC world replays from a fixed historical seed each run; a D-4 hybrid meta (Index knowledge + anchored cars as witnessed at their last race + team identity, no meta-money); a six-rung dev ladder that resets only Spotlight until the economy rulings land.
- Rulings owed before any build: W-1 (does the Paddock replay?), W-4 (the meta model), then W-2/3/5/6/7. IDEA-857 to IDEA-874.
- **THE ONE NEXT ACTION:** unchanged from Baseline 2 below (race once on Online). Racing Week starts at rung 0 (pure `week.clock` + tests, dev only) once the owner rules W-1 and W-4.

**EARLIER 2026-10-03 (08:15 UTC) - NCM ONLINE IS ON BASELINE 2: DEV'S CODE AND ITS 8-MOD STACK (L299).**
- Deployed: backup `/opt/ncm/backups/pre-carrier-prod-20261003T080827Z`; resources at `fb23f35` (tag `online-baseline-2`); 8 required mods, digest `7b070f25...` (identical to dev); migrations 043-058; Paddock GENESIS (Online's own world). First boot clean: no ERR, production minting (KB-311 live), NPC cars minting, 24 races scheduled. All 8 blobs verified over HTTPS. Details and rollback: OPS_STAGING "Online Baseline 2".
- Testers who join need the 8 mods (the launcher installs them; Pace and Broadcast are new to them).
- **THE ONE NEXT ACTION:** the owner joins NCM Online (the launcher installs the new mods) and races once: a street race and an oval (§CT19-§CT21 on Online), then `tools/npc-economy-audit.ps1`-style checks against Online's world after a day.

**EARLIER 2026-10-02 (23:00 ET) - THE AUDIT'S SEVEN DOORS (L298) AND L296 LOADED ON DEV; PACE 0.8.9; GATE ALL GREEN.**
- Loaded: Pace 0.8.9 published to dev and hand-installed (record `%LOCALAPPDATA%/NCM/dev-mods/20261002-225613`); dev restarted twice (logs `tools/open77/server/l298-restart-20261002.stdout.log`, `l298b-restart-20261002.stdout.log`): schema 058 applied, required mods 8 digest `ce4db77a...`, no errors; the L298 tunables declared (`npcRacerVariants` on). `tools/test-npc-sql.ps1` against MariaDB: 22/22 (mint with 11 factory parts, install, NPC service, purchase, Exchange). NPC cars minting ~6 per 10 s (36 at 22:59, all assigned).
- Built in L298: production fix (KB-311), NPC race cars as real 11-part cars with derived levels and Pace performance variants (KB-313), persisted/strict shopping (KB-312), wages/purses/fees/repairs ledgered (KB-314-316), goals with reasons, wear/service/scrap/trade-in sinks, NPC-to-NPC Exchange, "Last batch" provenance. Also loaded: L296 (pre-grid, ovals, street pace from the road).
- 23:59 ET: dev restarted (log `tools/open77/server/l299-restart-20261003.stdout.log`, 0 errors) with KB-317 fixed -- the oval session view was lost to a refused state-bag write and the owner DNS'd "absent" on their own grid.
- 00:27 ET 2026-10-03: Pace 0.9.0 published + hand-installed (record `%LOCALAPPDATA%/NCM/dev-mods/20261003-002640`), dev restarted (log `l300-restart-20261003.stdout.log`, 0 errors, mods digest `0a32d55d...`) with KB-318 (graceful restream: launch watch, oval-wide bubble, model position while launching).
- **THE ONE NEXT ACTION:** L299 -- the owner lifted the Online freeze (2026-10-03). Stock taken and everything committed and pushed; next, the owner confirms the Online push plan (DB backup, code, 16 migrations, 8 required mods), then deploy.

**EARLIER 2026-10-02 (late night) - NPC ECONOMY AUDIT (L297): SOLD OUT IS A CARDBOARD WALL; REPORT WRITTEN; NO CODE CHANGED BUT THE AUDIT TOOL.**
- Report: [wp/NPC_ECONOMY_AUDIT.md](wp/NPC_ECONOMY_AUDIT.md); tool `tools/npc-economy-audit.ps1` (read-only; output `tools/open77/server/npc-economy-audit-<stamp>.txt`).
- Headline: no vehicle manufactured since 09-24 (KB-311, SQL 1292 in `manufacture`, = KB-281); one vehicle ever sold; teams never buy; NPC parts never reach the raced car; restart re-buys; wages vanish (KB-312-316).
- Then: the owner ranks the audit's doors (fix production first is the recommendation). L296 is still on disk and not loaded: restart dev to load it (§CT13-§CT15).

**EARLIER 2026-10-02 (night) - PACE FROM THE STREET, THE PRE-GRID, NO AUTO-PLACE, OVALS BACK ON THE CALENDAR (L296); BUILT ON DISK, NOT LOADED; GATE ALL GREEN.**
- Owner, after the evening's races (log `tools/open77/server/l296-restart-20261002.stdout.log`, 41 races, 8 with the owner): "suddenly, quite good ... maybe almost ready to be pushed to online"; NPC speed is real (one win, several flagged DNFs in an unupgraded car). Online stays frozen at Baseline 1 until the owner says otherwise.
- Read from that log: sim pace per route 22.7-40.7 m/s vs a physical field at ~25-33 m/s (KB-303); no ovals scheduled at all (KB-304); auto-place refused the owner every time (KB-307); a chain explosion retired nine NPCs in the owner's win (KB-309, open); the rolling restream did not take (Pace logged the pre-roll, cars at 1-4 m/s after it; restream cost 200-590 m, KB-310, open); racer scales loaded (`42 racer(s) scaled`, 4 skipped); flag windows 30-68 s with no 0:00 hang.
- Built (L296): street sim/quali timed over the baked road line at a learned tier speed (KB-303); the pre-grid from T-15 min (KB-308); auto-place and its text removed (KB-307); ovals back, standing starts, course-change fix (KB-304-306). Server + client Lua only.
- Then: restart dev (no Pace change: `tools/o77-server.ps1`), then race: §CT13 (pre-grid), §CT14 (an oval, end to end), §CT15 (sim/quali pace), and watch §CT12's restream. Then the owner's item 4: NPC parts ownership and provenance, NPC finances, the economy (IDEA-851).

**EARLIER 2026-10-02 (late afternoon) - THE FLAG, THE CEREMONY, LIVE ORDER WITHOUT PENALTIES, STAGGERED START (L294); PACE 0.8.7; LOADED ON PRIVATE DEV 16:21 ET.**
- From the 15:45 and 16:00 races (log `tools/open77/server/l293-restart-20261002.stdout.log`): a 4-minute wait to classify (KB-295), the owner always P1 on the tower (KB-296), hand-backs at the 0.50 pace floor driving the streaming churn (KB-297), a lap-one pile-up from a simultaneous launch (KB-298).
- Owner rulings (L294): the live order is without penalties; a classification ceremony shows them (as crossed, then the shuffle, green up / red down); races end at the flag, the leader's crossing + 0.03 s/m (45-240 s), with a countdown.
- Built and loaded: all of the above; Pace 0.8.7 published to dev and hand-installed (record `%LOCALAPPDATA%/NCM/dev-mods/20261002-162146`). Dev restarted 16:21:57 ET (log `l294-restart-20261002.stdout.log`): 42 resources, required mods digest `6cf41347...`, no errors. Nothing committed.
- Also loaded (dev restarted again, log `l295-restart-20261002.stdout.log`): no provisional "P1" while the field is classified (KB-299).
- L295 LOADED ON DEV 17:01 ET (Pace 0.8.8 published and hand-installed, record `%LOCALAPPDATA%/NCM/dev-mods/20261002-170136`; dev restarted, log `l296-restart-20261002.stdout.log`, 42 resources, mods digest `12eeef2b...`, no errors): seamless restream (set-down lead learned per race + Pace 0.8.8 rolling pre-roll, KB-302), flag 0.012 s/m 30-90 s (KB-301), the classified result reaches the HUD (KB-300). To load: with the game closed, `python tools/staging/publish-carrier.py tools/open77/server --zip dist/ncm-pace-0.8.8.zip --version 0.8.8 --id ncm-pace --display-name "NCM Pace" --import-blob --enable`, `python tools/dev-hand-install-mods.py --only ncm-pace`, restart dev.
- Then (superseded): race one mixed street race to the end: §CT12 (restream, flag, result), §CT10 (position, flag, streaming), §CT11 (ceremony), §CT7 (pace), §CT6 (names). Then read the TweakXL log for `Unknown property` and the Pace log for `racer scales`.

**EARLIER 2026-10-02 (afternoon) - TRUTHFUL RUNNING ORDER + NPC PENALTIES + PACE 0.8.6 LOADED ON PRIVATE DEV 15:25 ET (L293); GATE ALL GREEN; NO LIVE RESULT YET.**
- The 15:00 race (log `tools/open77/server/l292-restart-20261002.stdout.log`): owner crossed first at 3:58.5, classified P3 on +14 s incidents; the tower had shown NPCs finished while they were behind. Causes: model ran bubble cars on their sim clock and handed-back cars at sim pace (KB-293); order ignored penalties and NPCs had none (KB-294); the racer profile was half-applied since 0.8.5 (KB-292).
- L293 built and loaded: racestate 0.2.0 truth rules; one provisional order with penalties for humans and NPCs; NPC incidents by the human scorer; Pace 0.8.6 (corrected profile, more traction/braking/lookahead, NPC-only drive x1.25 / brakes x1.30 / drag x0.80), published to dev and hand-installed (record `%LOCALAPPDATA%/NCM/dev-mods/20261002-152520`); subtle decluttered nameplates (IDEA-845). Dev restarted 15:25:33 ET (log `l293-restart-20261002.stdout.log`): 42 resources, required mods 8 with digest `fe94dbfc...`, no errors. Nothing committed.
- Earlier this afternoon, dev restarted 14:44:53 ET (log `tools/open77/server/l292-restart-20261002.stdout.log`): 42 resources started, no errors and no SQL 1292 in the boot.
- Traced the owner's 13:45 mixed point-to-point race (North Oak Ramp 2 to Tip) through the client log (`red4ext/logs/open77-2026-10-02-13-31-50.log`) and the dev server log (`tools/open77/server/op77-124-start.out.log`).
- L291: the whole mixed field reaches the HUD and tower (KB-282); grid ring permission (KB-283); qualifying views targeted (KB-284); race-end waypoint release (KB-285); NPC names as native anchored cards (IDEA-839); per-phase session-view size log for ovals (IDEA-842).
- L292: racer clones on every street race. The vanilla race profile obeyed lane speed limits, and the 74 m/s ceiling was never applied (KB-287). Nav tracks a node's own map pin instead of a custom waypoint (KB-289). No bubble churn while a player pulls away (KB-286). Reaching the mark during the lights now starts the race (KB-290). Standings name a human driver and label them Privateer (KB-291). Owner test rulings applied (DNS at green everywhere, entry/freeze at T-1, sim ovals 35-40 m/s); `ncm-test` ALL GREEN under Lua 5.4 and LuaJIT (KB-288).
- Then (superseded): launch the game (Pace 0.8.6 is installed), rejoin dev and run one mixed street race: §CT9 (truthful order with penalties), §CT7 (pace), §CT6 (subtle names), §CT5 (tower/HUD/ring), §CT8 (finish GPS), plus one QUALIFY run (§CT3). Then read the TweakXL log for `Unknown property` and the Pace log for `racer scales`.

**EARLIER 2026-10-02 - BOTH SERVERS ON OPEN//77 `2.31.21+op77.124`; DEV CLIENT MODS RESTORED (L290).**
- Pre-upgrade state is preserved in [SERVER_BASELINE_2026-10-02.md](archive/SERVER_BASELINE_2026-10-02.md) and pushed checkpoint commit `6628744` on `checkpoint/pre-op77-upgrade-2026-10-02`. Development still requires eight hosted packages; Online still requires its original three with digest `879af328...`. Online NCM code, required mods, and data remain frozen at Baseline 1.
- The Windows Development server is running on `.124` with 44 loaded resources and unchanged required-mod digest `8dc855d1...`. The raw-address Development join needs local mod installation: all eight packages were installed into the game with a reversible record under `%LOCALAPPDATA%/NCM/dev-mods/20261002-132708`, and their NCM RED4ext plugins were removed from the ignore list. The owner has not yet rejoined to confirm Rig Bridge and Scanner.
- Online is active on `.124`; its three mod blobs still hash correctly, the public HTTPS manifest is unchanged, and the prior server tree is backed up at `/opt/ncm/backups/server-20261002T172506Z`.
- Explained the nearby-player bubble: the Paddock field gets physical vehicles around a player and keeps them present while the player stays close; it is not a separate race type.
- Fixed actual oval bubble spawning to select NCM Pace RaceDrive clones. Corrected the canonical and all four resource session-kernel copies so DNS happens at green, and active drivers are not timed out by the generic short oval limits. Oval limits: 60 minutes, 20-minute finish window, extended while a human keeps moving.
- Paddock grid ring now draws through native marker APIs directly. Restarted private dev at 12:45 ET; 44 Lua resources started and resource generation 1 published. No tests run (not requested).
- Then: rejoin Development and confirm Rig Bridge and Scanner load after the local reinstall. Then live check the grid ring and oval race behavior. The MariaDB SQL 1292 persistence failure (KB-281) remains unresolved.
