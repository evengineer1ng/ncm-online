**LATEST 2026-10-13 06:00 UTC - KB-465/466 + L369 BUILT, NOT YET LIVE: THE AV OUT OF GROUND RACES, SPACE CLIMBS AGAIN, THE COLLAPSE GOES LIVE FROM RUN 4, AN AV FOR EASPORKS.**
- KB-465: the AV sat in the street pool's Tech class, so every open series admitted it (45 -> 46). Aerial machines now stay in the Machine Index but no ground race or class draw takes them. KB-466: `9a4c712` dropped Space from the AV climb on a wrong premise; pellerino's 01:25 UTC flight logged 25 s of `stick lift 0.0` (nothing asked, so Carrier 0.1.40's flight is still unexercised). Space or R again. `1ceb09a`; gate green except KB-463.
- L369: the run-3 rollover played the rewind and moved every Machine home, but the money/garage collapse was a DRY RUN (the L303 default, never flipped). Owner: live from the next reset only -> `ncm_week_collapse live`, `ncm_week_collapse_live_from 4`; first live collapse at run 4's end (2026-10-15 16:00 UTC unless extended), MASTER_TEST §RW15.
- Not deployed: the session's SSH to Lightsail was blocked mid-session by the auto-mode permission classifier.
- **THE ONE NEXT ACTION:** owner runs `bash tools/deep/ops/install-kb465.sh` with nobody online (resources, both convars, mints an Atlus AV for easporks `72519ab3` with a 1,500 L tank and fits the `av` kit), fresh-launches, then §AV1-§AV4 (Space or R climbs) and §AV7. Still owed: KB-464 MARKET check, KB-462 15-minute FPS check.

**LATEST 2026-10-13 04:41 UTC - KB-464 LIVE ON ONLINE: THE MARKET TAB'S PAYLOAD DIED ON THE INSTRUCTION QUOTA; IT NOW YIELDS.**
- Every market push since 04:08 UTC failed `Open77 instruction quota exceeded` (last good 01:25). `ncm_league` market.lua + components.lua yield per line, gearbox variant and component design; a failure now names its stage. `cbcea87`; restarted 04:40 UTC, generation 1, QA `online`, no ERR; backup `/opt/ncm/backups/pre-kb464-20261013T043920Z`.
- **THE ONE NEXT ACTION:** owner joins and opens MARKET: offerings and parts list; the log shows `market] payload player=.. N bytes`, not `payload failed`. Then the KB-462 15-minute FPS check below.

**LATEST 2026-10-13 04:00 UTC - KB-462 LIVE ON ONLINE: THE CLIENT EXPORT FLOOD BEHIND "BAD FPS AND LATENCY" IS FIXED; BARE METAL IS THE WORKING REPO AGAIN (PROXMOX DOWN).**
- The server was idle (~5% CPU, 12-28 ms from the owner's PC). The owner's client lost ~11 ms a frame within ~12 min of a join (125-165 Hz on 10-10, ~45-53 Hz on 10-12): L367's kit loop called `ncm_sky.scene` 10x a second unawaited until the client hit `export_request_limit`, after which venue rings failed too. Fix in `7d943b8` (ncm_build client, ncm_world deep + carrier_bridge); deployed 03:57 UTC with nobody connected, generation 1, QA line `online`, no ERR; backup `/opt/ncm/backups/pre-kb462-20261013T035541Z`.
- Gate: green except KB-463 (migration 081 vs the single-player host's SQL translator; Online unaffected). The build host test no longer hangs.
- **THE ONE NEXT ACTION:** owner fresh-launches, joins Online and plays past 15 minutes; then read the newest `red4ext/logs/open77-*.log`: `Open77 frame:` near the 10-10 rate, `open77_contextmenu` in the tens of us, no `export_request_limit` (KB-462 verify). The L368 AV and L367 install steps below are still owed.

**LATEST 2026-10-12 - L368 BUILT, NOT YET LIVE: THE AV FLIES ON NCM ENGINEERING (F TO BOARD, FLY-BY-WIRE, CARRIER 0.1.39, WORMHOLE DRIVE).**
- The Atlus Trauma Team AV is a Machine: four VL-28 lift fans on its pods, an FC-1 flight computer (core `engineering.flightcontrol`), two FD-1s for the thin air, AC-6, PT-500, XLB-WH1. F boards it (`av_board`). NCM Carrier 0.1.39 expresses torque and switches the AV's physics on. KB-460 (client changes need a full restart) and KB-461 logged.
- **THE ONE NEXT ACTION:** owner runs `bash tools/deep/ops/install-av.sh` with nobody online (it fits pellerino's AV with the `av` kit), relaunches (accept NCM Carrier 0.1.39), and walks §AV1-§AV6.

**LATEST 2026-10-12 - L367 BUILT, NOT YET LIVE: NCM FX + NCM AUDIO, BUILD YOU CAN SEE (KIT + KB-443), MARKETS + EXCHANGE, KB-458 EARTH YAW.**
- Toolchain on the Proxmox VM (VS Build Tools, CMake, Ninja, WolvenKit 8.20): NCM Sky and NCM Audio build from source.
- New: `ncm-audio` (required mod), `ncm_audio`, `ncm_build_kit` (required mod), NCM Sky 0.2.4, migration 081. Underlay v3 (L366 amendment) is also still waiting to be installed.
- Not yet built: working parts on kit pieces; markets back to opening stock at the Week reset; a market soak simulation; players posting their own cars.
- **THE ONE NEXT ACTION:** owner runs `bash tools/deep/ops/install-l367.sh` with nobody online, relaunches, and walks §FX1-§FX3, §BLD7, §MKT1-§MKT3 and §SKY10.

**LATEST 2026-10-12 13:00 UTC - L366 LIVE (NCM SKY 0.2.3, 12:15 UTC); UNDERLAY v3 (HOLE = THE MAP'S EDGE) BUILT, READY TO DEPLOY; NEXT: THE ENGINEERING RECONCILIATION.**
- The first live climb showed the ring only as a lip far beyond the edge (the 9 km circular hole). v3 cuts the hole to the terrain square: `ncm_earth_underlay` 1.0.2, `dist/ncm-earth-underlay.zip` in the resource.
- **THE ONE NEXT ACTION:** owner runs `bash tools/deep/ops/install-underlay.sh` with nobody online and relaunches. Then the engineering conversation (design docs vs what exists; Race Week resets; wardrobe; VFX/SFX; Nessie; Bennu; PvE last).

**LATEST 2026-10-12 12:10 UTC - L366 THE ASCENT RING BUILT (NCM SKY 0.2.3), NOT YET LIVE; KB-457 UNDERLAY v2 LIVE BUT OUT OF DRAW RANGE FROM ALTITUDE.**
- Owner flew back to Earth after the KB-457 install: no Earth on the descent. The true-size underlay is too far away to draw from altitude (v2 is installed and was merged at game start).
- L366: NCM Sky draws the underlay shrunk about the camera from 1.5 km to the seam (kinds 10-14). The redscript compiles against vanilla plus every installed script. Package `dist/ncm-sky-0.2.3.zip` (sha 3701a128...).
- **THE ONE NEXT ACTION:** owner runs `bash tools/deep/ops/install-ascent-ring.sh` with nobody online, relaunches (accept NCM Sky 0.2.3), climbs from Night City: Earth beyond the map from 1.5 km, then the handoff at 12 km. Tune with `ncm_deep_ring_far` if the horizon is clipped (lower) or too near (higher).

**LATEST 2026-10-12 11:20 UTC - KB-457: THE EARTH UNDERLAY'S BLACK VOID FOUND AND FIXED IN THE PACKAGE (v2, NOT YET LIVE); GITHUB MAIN = LIVE SINCE PR #1.**
- PR #1 is merged (main `25b3d62`), and the old branches are deleted. The working repo is the Proxmox clone `~/projects/ncm-online`.
- KB-457: the underlay's streaming box ended at z +9,991 m, below the 12 km Deep seam. v2 adds a pivot marker, and the box now reaches +16 km. The NCWE project and mesh are now in the repo: `ncm/ncwe/ncm_earth_underlay.ncwe`, `ncm/ncwe/custom_meshes/ncm_earth_underlay_5a1366`, `tools/deep/ncwe/build-earth-underlay.py`.
- The live convar `ncm_deep_ascent_z` is still "99999" (the WebGL ascent overlay is off, so the underlay is the only Earth below the seam).
- Still owed: §DRV1-§DRV3, §DRV7; the Sun and planets in the native Deep view (new ncm-sky body kinds plus World Layer meshes).
- **THE ONE NEXT ACTION:** owner runs `bash tools/deep/ops/install-underlay.sh` with nobody online, relaunches, and climbs out of Night City: Earth should show all the way to the seam.

**LATEST 2026-10-12 10:40 UTC - ONE REPO AGAIN: THE PROXMOX VM'S WORK (SUBSTRATE, PROPULSION STABLE, PANELS) RECONCILED WITH THE BARE-METAL CHECKPOINT ON ONE BRANCH (IDEA-1300).**
- Since the bare-metal baseline (checkpoint branch 06c3f8b, 2026-10-11 00:46) everything was built on the Proxmox VM and deployed to Online: the astronomical substrate (L363, doc 60), the experimental propulsion stable (L364, doc 61; §DRV4-§DRV6 PASS: Alcubierre to Barnard's Star, jump to Proxima, wormhole home), the panel fit (L365), KB-449..KB-456. The branch `reconcile/proxmox-live-2026-10-12` carries the live tree; `tools/ncm-build.ps1` keeps a resource's own core data (star chunks).
- The lab Hella (Alabino, ..560c94) carries the XLB-WH1 kit; the Galena (baremetaleven) coasts at ~290,000 km. L362: the Racing Week reset applies to both.
- Still owed: §DRV1-§DRV3 (impulse, fusion, warp), §DRV7 (panels on the 2176x1812 client); NCWE maps (`ncm/ncwe/*.ncwe`): stars and planets in the native Deep view, the Earth underlay on the Race Week map.
- **THE ONE NEXT ACTION:** owner reviews and merges the reconcile PR; then the NCWE map pass (stars/planets natively, underlay on the Race Week map).

**LATEST 2026-10-11 03:50 UTC - KB-448 LIVE ON ONLINE; THE 03:09 REJOIN STAGED THE GALENA INTO THE SPACE STAGE; §SKY7 VISUAL VERDICT OWED.**
- Deployed `ncm_world` server/deep.lua + server/canonical.lua 03:07 (backup `pre-kb448-20261011T030602Z`); `BOOT driver ..3d2be6 is deep` before the join. 03:09:57 `JOIN player=1 resumes deep`, 03:10:03 `ENTER ... frozen true true`, `STAGE ... move true true`; client `stage confirmed by the server after 1 request(s)`; NCM Sky spawned sky_dome, Earth, Moon. FRAME 03:43: via cyberpunk, 62,911 km, thrust 0, energy on curve.
- Open: ENTER used the normal binding, so the KB-448 claim path is unexercised live (and should clear on every accepted ENTER); 3 `vowner-loss` lines in the client log not yet placed in time.
- L362 unchanged: Racing Week rollover resets the Galena; no §SKY9 burn without the owner's approval.
- **THE ONE NEXT ACTION:** owner's §SKY7 verdict (no Night City, stars, Earth ~11-12 deg at ~63,000 km in the WebGL direction), then §SKY8 attitude only.

**LATEST 2026-10-11 03:05 UTC - §SKY7 FAILED ON THE REJOIN (KB-448): THE SERVER REFUSED ENTER FOR THE CAR IT HAD FROZEN ITSELF; FIX STAGED, NOT DEPLOYED.**
- 02:57 rejoin: `JOIN player=1 resumes deep` then `enter refused: not driving a bound Machine`, so no stage; the owner saw 12,100 m over Night City. Fix: the resume's one-shot claim on its own vehicle (`ncm_world` server/deep.lua + server/canonical.lua), host test 30/30, gate ALL GREEN, staged at `/tmp/kb448` with `/tmp/kb448-deploy.sh`.
- **THE ONE NEXT ACTION:** owner quits again in Deep; confirm the server takeover in the database; run `/tmp/kb448-deploy.sh`; wait for `BOOT driver ..3d2be6 is deep`; owner joins: §SKY7 must show `ENTER player=.. : the resumed Machine ... taken from the join's claim` and `STAGE ... move true`.

**LATEST 2026-10-11 02:55 UTC - KB-444 + KB-446 LIVE ON ONLINE; THE GALENA IS STILL IN DEEP (52,000 km, server-flown); OWNER JOINS FOR §SKY7.**
- Owner quit in Deep 02:38:54; server takeover confirmed in the database (host none, `simulated`, utc advancing). Deployed `ncm_world` server/deep.lua (KB-444 stage ack + FRAME, IDEA-1294), client/deepview.lua (stage retry), server/engineering.lua (KB-445) at 02:42 (backup `pre-kb444-20261011T024058Z`). That boot hit KB-446 (presence never loaded: identity at 118 s, canonical gave up at 68 s silently); `canonical.lua` fixed and deployed 02:50 (backup `pre-kb446-20261011T024848Z`, owner approved). 02:51:44 `BOOT driver ..3d2be6 is deep (written 561 s ago)`, `UNHOSTED ... flown 566 s`. Orbit intact (h, e, perigee unchanged); server integrator drift recorded (KB-447).
- L362: the Racing Week rollover resets the Galena normally; the snapshot is evidence only. No §SKY9 burn without the owner's approval.
- **THE ONE NEXT ACTION:** owner fresh-launches and joins Online, then §SKY7 (native space environment), §SKY8 (attitude only). Watch for `STAGE ... move true` and `stage confirmed`.

**LATEST 2026-10-11 02:30 UTC - WHY THE NATIVE VIEW SAT AT 12 KM OVER NIGHT CITY (KB-444); FIXED LOCALLY, NOT DEPLOYED: THE OWNER IS IN DEEP.**
- The owner's Galena is live in Deep on Online (player 3, connected 23:21 UTC): 42,300 km and climbing, thrust 0, 43.4 kg fuel, inertial 3,990 m/s against 4,048 m/s escape, bound on a near-radial ellipse (apogee ~1.69 million km). WebGL shows that; the native view showed the car frozen at the seam (game -352, 498, 12004) because no Deep entry has been staged since KB-438's "stage once" (05:59 UTC): the one stage request beat ENTER (net events are not ordered) and was dropped silently. NCM Sky drew the dome, Earth and Moon at the stage, 16 km away.
- Fix (KB-444): the server acknowledges stages (`ncm:deep.staged`) and says when one arrives early; the client repeats until acknowledged. KB-445 (the TELEMETRY double format) rides along. Files: `ncm_world/server/deep.lua`, `ncm_world/client/deepview.lua`, `ncm_world/server/engineering.lua`. New `tools/test-deep-stage-host.lua` (16). Gate ALL GREEN.
- The state is safe across a restart: the server owns it (`ncm_presence.state_json`: ECEF p + vel, attitude basis, omega, tanks, devices, asset; checkpointed 1 Hz, stored every 5 s), flies it itself 15 s after its host goes, and a join resumes it in Deep (`claimJoin` -> `materializeAt` z 12,100 -> `ncm:deep.resumeCanonical`). Snapshot taken: `/opt/ncm/backups/galena-deep-snapshot-20261011T020758Z.tsv` = `docs/research/open77/snapshots/`. **What WILL erase it:** the Racing Week run 3 rollover (latest 2026-10-12 16:00 UTC, L330 `loopReset`, IDEA-1291), owner's call.
- **THE ONE NEXT ACTION:** owner quits the game while in Deep (do not fly home; the server keeps flying the Galena). Then, with nobody connected, deploy the three files (exact-diff, backup first) and restart; join only after the server logs `BOOT driver ..3d2be6 is deep` (a join before the presence rows load gets a surface restore; resuming into Deep on a join has never yet been seen on Online), then run MASTER_TEST §SKY7 (Earth 15 deg, no Night City), §SKY8 (turn without thrust). §SKY9 (a burn) only with the owner's go-ahead.

**LATEST 2026-10-10 21:30 UTC - THE WORKSHOP IS LIVE ON ONLINE (L361): TEAR DOWN, FABRICATE, PROMOTE, RUN, LIST, ON F9.**
- The uncoded engineering lanes now exist end to end on one bench (core `engineering.projects`, resource `ncm_workshop`, schema 079, F9 WORKSHOP tab), with competency shared with self repair and shown in words. Planned-vs-built table in L361. Deployed with nobody connected; migration 079 applied; `[ncm_workshop] ready`; no ERR. Backup `/opt/ncm/backups/pre-workshop-20261010T212806Z`.
- **THE ONE NEXT ACTION:** owner: F9 > WORKSHOP, tear down a physical add-on and collect the sheet (§WS1-§WS2); keep tearing down that design to stage 3 and fabricate (§WS3). Still owed from earlier today: §SKY3/§SKY6 (space render, centred-mount Guidance) and the F9 > BUILD reason (KB-443).

**LATEST 2026-10-10 21:00 UTC - CENTRED FLOOR-PAN MOUNT LIVE ON ONLINE (L360 addendum 2); BUILD REACHABILITY INSTRUMENTED (KB-443).**
- The underside mount now sits under the Machine's centre of mass, so the owner's FD-1 underside build climbs and flies on Guidance. Fuel note for the owner: every Y press hops the IA-10 first (4 L of car fuel each); the PT-400 feeds only the FD-1.
- **THE ONE NEXT ACTION:** owner climbs to 12 km on the underside FD-1 and checks the space render (§SKY3) and Guidance (§SKY6); opens F9 > BUILD and reads the reason it shows (KB-443). Engineering lanes (reverse engineering, fabrication) are being planned next.

**LATEST 2026-10-10 07:29 UTC - CODEWARE REQUIRED + NCM SKY 0.2.2 + GUIDANCE TRIM LIVE ON ONLINE (L360 addendum, KB-440/442).**
- The 07:07 flight: still no sky (Codeware was ignored by the Online launch, KB-440); Guidance tumbled the FD-1-underside Machine to 17 rad/s and it fell (KB-442: the full front tank puts the thrust line 0.25 m off the centre of mass). Owner ruled: declare Codeware; Guidance caps throttle to what attitude can trim and says why. Deployed, 19 required mods, blobs 206, no ERR; backup `/opt/ncm/backups/pre-sky-guid-20261010T072634Z`.
- **THE ONE NEXT ACTION:** owner fresh-launches (accept Codeware + NCM Sky 0.2.2), flies through 12 km and looks for the stars/Earth (`ncm_sky` log: `spawned ... through Codeware`), then §SKY5: Guidance refuses the belly FD-1 with the reason; remount it rear/aft and Guidance flies.

**LATEST 2026-10-10 06:11 UTC - GEARBOX 0.4.1 HOTFIX LIVE ON ONLINE (KB-441): 0.4.0 manuals sat at 0 km/h with the engine at ~5,000 rpm; the zero native shift time is removed. Owner fresh-launches and drives a manual first.**

**2026-10-10 05:59 UTC - DEEP FIXES + GEARBOX 0.4.0 LIVE ON ONLINE (L360, KB-436..441); LIVE PASS OWED.**
- Owner's 00:29 Deep stay, read from the client logs: no sky ever spawned (KB-440, CET's exEntitySpawner absent), 126 ownership flips in 22 s from re-staging the car on every yaw change (KB-438: the flicker and the 2D flipping), zero thrust the whole stay with 41 kg of fuel aboard (KB-437, now instrumented), and the engineering loop died on the drop back (KB-436: "propulsion broke"). All fixed or instrumented; white frames removed (KB-439).
- Manual gearboxes: each selected gear sliced over seven native gears (NCM Gearbox 0.4.0, IDEA-1284, KB-441).
- Deployed: restart 05:59:38 UTC (nobody connected), `active`, QA line says `online`, `ncm_world` + `ncm_sky` started, 18 required mods (digest `fbcc333d...`) with ncm-sky 0.2.1 and ncm-gearbox 0.4.0, both blobs 206, no ERR since boot. Backup `/opt/ncm/backups/pre-deep-gbx-20261010T055039Z`. The boot line `deep handoff disabled ... (unknown)` appears at every boot (also before the working 04:29 UTC Deep entry) and is not a fault.
- **THE ONE NEXT ACTION:** owner fresh-launches (accept NCM Sky 0.2.1 / NCM Gearbox 0.4.0), flies through 12 km holding the propulsor (§SKY3, §SKY4; the `STAY` lines name any thrust cause), then times a manual 0-100 against the automatic (§SG4).

**LATEST 2026-10-10 04:16 UTC - RIG BRIDGE 0.1.8 AND F9/DEVICES FIXES LIVE ONLINE; CLIENT PASS OWED (KB-432/434/435).**
- The owner's Switch Pro Plus opens F6, proving the gamepad shell path. Its faces were crossed by Rig Bridge's primary-pad map. Owner corrected scope: the face translation now changes **only SDL Switch Pro** (`kTypeSwitchPro`); Sony and every other primary pad keep the old map. Rig Bridge 0.1.8 was built and native pad tests passed. Online declared 0.1.8, restarted active, manifest digest `740de860...`, package SHA-256 `22fd7a3f...`, HTTPS blob returned 206. Backup `/opt/ncm/backups/pre-rig-018-20261010T041032Z`. The owner's 04:13 join tested an already-running game process: client log `ncm_rig_bridge-85184.log` reports **0.1.7**, and the game-folder DLL reverted to its 0.1.7 hash. That is why the face buttons still felt wrong. The finalized 0.1.8 DLL was reinstalled in the closed game after the Online release; a fresh launch/join and log check of 0.1.8 are owed.
- The Maimai's IA-10 still has no hop binding in its saved configuration. The F9 binding UI and DEVICES crash fixes were tested locally; four exact-diff resource files were copied to Online with hash match and backed up at `/opt/ncm/backups/pre-input-ui-20261010T041502Z` after the player disconnected. Online restarted active at 04:16 UTC; `ncm_world`, `ncm_league` and `ncm_build` startup lines appeared, with no new resource-start failure in the inspected tail. Live F9 and DEVICES checks are owed. The top Switch X should be `padY` with Rig Bridge 0.1.8, and the IA-10 must receive `padY tap discharge` to hop.
- **THE ONE NEXT ACTION:** owner freshly launches/joins, confirm Rig Bridge 0.1.8 in the new client log, then bind the Maimai's IA-10 to top-face tap and obtain a live hop PASS. Keep the rim visibility issue open separately.

**EARLIER 2026-10-10 - DEVICES PANEL CRASH FIXED LOCALLY (KB-434); INPUT FIXES STILL NOT LIVE.**
- At 23:39 Toronto, F6 > DEVICES closed with `devices.map is not a function` at `rigShapeOf`; the zero-device array crossed Lua/WebUI as `{}`. Local panel fix normalises that shape in all three render paths; targeted regression payload plus the full panel render harness are ALL GREEN. Not deployed.
- Rig Bridge saw **zero** DirectInput devices in the 23:36 rim session, so the mapped rim Start could not reach F6 then. The later Switch Pro Plus test proves the F6 path itself works. The Maimai still has no Triangle binding; the local F9 binding UI fix is not deployed.
- **THE ONE NEXT ACTION:** prepare isolated Online hotfixes for KB-432 and KB-434, check the rim is again visible to Rig Bridge, then live-test F6 DEVICES, Start and a bound Maimai hop. SKY1 follows those checks.

**EARLIER 2026-10-10 - MAIMAI CONTROLS CORRECTED (KB-432/433); LOCAL F9 FIX, NOT DEPLOYED.**
- The owner's correction identified the Maimai, `..fa26d5`, in the 23:15 and 23:28 Toronto client logs. It has IA-10 **underside/down** and only a gearbox binding (`padLeftThumb:tap`); no Triangle binding, and no propulsor in the delivered configuration. The earlier `..000002` aft-facing IA-10 was another Machine and does not explain the Maimai complaint. F9 offered bind controls only for gearboxes, so fitting propulsion parts never prompted for Triangle. Local fix adds actuator/propulsor button choices and visible current bindings to F9; not deployed or live passed. An attempted second part on the same hardpoint displaces the first; the propulsor's intended mount still needs checking.
- The owner's mapped rim pause button still targets XInput Start (`profiles/default.json`: `E502:BBAB` button 18 -> `start`). Rig Bridge detected four DirectInput devices including this one at 22:49 Toronto, then **zero** at 23:01, 23:11, 23:23 and 23:25. That is why the pad Start never reaches the F6 poll; the physical/driver reason for device disappearance is unknown. Local panel diagnostic logs the Start edge/capture/read state after deployment.
- **THE ONE NEXT ACTION:** restore the rim's DirectInput visibility to Rig Bridge and live-check Start; ship the local F9 binding fix after review so the owner can bind the Maimai IA-10 to Triangle tap and check the propulsor's distinct mount/hold binding. Resume SKY1 after controls work.

**EARLIER 2026-10-10 02:46 UTC - THE NCWE SPACE RENDER v1 IS LIVE ON ONLINE (L358 addendum 2, IDEA-1263, KB-430).**
- Crossing 12 km now puts the Machine inside an NCWE-authored universe: a real J2000 star dome (ESO Milky Way + Bright Star Catalogue), a Blue Marble Earth turning under you with Night City beneath, the LROC Moon on its ephemeris, all turned with the Machine's true attitude by `ncm-sky` 0.2.0 from core `space.sky`. World layer 1.1.0 (27.5 MB) and NCM Sky 0.2.0 both download (206). Backup `/opt/ncm/backups/pre-ncwe-sky-20261010T024224Z`.
- **THE ONE NEXT ACTION:** owner flies through 12 km on Online (fresh launch for the new packages) -- MASTER_TEST Â§SKY1; then the Sun (body + light), the planets, Earth's night side, and whatever the first look shows (fog behind the dome, sizes, orientation).

**LATEST 2026-10-10 02:25 UTC - ONLINE: THRUST FIX, NCM SKY, FLIGHT HARDWARE AT THE AUTOFIXERS; NEXT: THE NCWE UNIVERSE.**
- Deployed Online 02:20 UTC (see the L358 addendum): KB-429 thrust fix, `ncm_sky` + `ncm-sky` 0.1.0 (18 required mods), flight hardware dispersed to the Autofixers (FD-1 Arroyo, RP-16 Rancho 03, AC-6 Rancho 02, IA-10 Little China; SL-1 stays in the Base Market). Space is accessible to everyone; the SKY-1 proof Earth appears only inside the Deep stages.
- **THE ONE NEXT ACTION:** build the NCWE space render (IDEA-1263): real star sphere, Blue Marble Earth, Moon, Sun, planets as NCWE-authored assets in the world layer's bubble, placed and turned from `space.deep` through NCM Sky, replacing NEAR's held-above-a-globe view (KB-430). Owner live checks owed: MASTER_TEST Â§SKY1, Â§BLD.

**LATEST 2026-10-10 02:03 UTC - BUILD (L359) DEPLOYED TO ONLINE.** Owner: "nobodys online in online can you push it there". Shipped `ncm_build` whole (15 data files checked before restart), `ncm_league` (schema 078 + manifest), `ncm_engineering` (F9 BUILD tab), core `build/attach.lua` in those three. Backup `/opt/ncm/backups/pre-build-20261010T020*` (ncm.sql.gz, replaced.tgz). Migration 078 applied; `[ncm_build] ready`. NOT shipped: the KB-429 thrust fix (held), `ncm_sky` / `ncm-sky` (DEV proof only). Next: MASTER_TEST Â§BLD1-Â§BLD6 on Online.

**LATEST 2026-10-10 ~01:55 UTC - BUILD PRIMITIVE (L359, IDEA-1282) ON THE DEVELOPMENT SERVER; NCM SKY SKY-1 ALSO THERE.**
- F9 -> BUILD attaches a catalogue object to an owned Machine with the platform's replicated binding, saved against the Machine (schema 078 applied on DEV), rebuilt on every call, move/remove, chains, limits. Real aero art does not exist in the attachable catalogue (KB-431): wings are plate stand-ins.
- Gate ALL GREEN (core +6, build host 23).
- **THE ONE NEXT ACTION:** owner on DEV: MASTER_TEST Â§BLD1-Â§BLD6 (with the tester identity as the second client), and Â§SKY1.

**LATEST 2026-10-10 ~01:40 UTC - NCM SKY (L358): SKY-1 PROOF ON THE DEVELOPMENT SERVER.**
- Owner chose the native-mod route for space (KB-430). `ncm-sky` 0.1.0 (DLL + redscript + a gameObject Earth template authored from the game's own q201 globe) builds clean and is a required mod on DEV; the `ncm_sky` resource feeds it. KB-429 thrust fix stays held (ships with the space work).
- **THE ONE NEXT ACTION:** owner joins DEV and looks north (MASTER_TEST Â§SKY1). If the Earth nods and turns, build the real sky on it: star sphere, Blue Marble Earth, Sun/Moon/planets from `space.deep`, replacing NEAR.

**LATEST 2026-10-10 ~01:40 UTC - SPACE DIAGNOSED (KB-429 fixed locally, KB-430 open).**
- The owner's last Deep flight was 2026-10-08 21:33 UTC. The server side worked (ENTER, STAGE near, EXIT). The Machine lost thrust on alternate seconds (KB-429: unchanged engineering re-sends reset the client's runtime) and fell out after 23 s. Fixed locally with a test; not deployed.
- The native view could never show Earth or where you are (KB-430): NEAR rides 3.6 m above a 1.9 km game globe with a fixed face under the game starfield; no OpenSpace data reaches it; props are yaw-only.
- **THE ONE NEXT ACTION:** the owner chooses the native-universe approach (KB-430); deploy the KB-429 fix with it or alone.

**LATEST 2026-10-10 00:57 UTC - SCOUTING (L355) AND L357 (TEAM QUEUE CANCEL/SEATS, PLAYER-FACING OBSERVER) DEPLOYED TO ONLINE.**
- Shipped 20 files (hash diff, existing resources only): `ncm_paddock` manager/views/requests, `ncm_world` panel.html, `ncm_observer` (settings, open77 + database.access, server, client, web) and the vendored `paddock/manager.lua` in every resource. Backup `/opt/ncm/backups/pre-mq-observer-20261010T005201Z` (ncm.sql.gz, replaced.tgz).
- Boot clean: `[ncm_observer] ready (enabled=true, allow="*")`; Paddock running; `[ncm_paddock/scouting] 868 career(s) scouted` 2 min after boot. Nobody connected.
- Pre-existing, not from this deploy: `[ncm_paddock/main] tick FAILED: Open77 instruction quota exceeded` (8 in the 24 h before; 1 since) and `exchange trade FAILED` quota lines.
- Racing Week cups: run 3 can end at the latest 1791820800 (2026-10-12 16:00 UTC), earlier at a finale; the owner's queue (promote/release Joshua, sign Arnaud) applies then unless cancelled. The owner said they will cancel all three.
- **THE ONE NEXT ACTION:** owner: MY ORG -> CANCEL the three moves (Â§MQ3), read the scouting on free agents (Â§SC), F3 Observer with Y (Â§OB-T1-3).

**LATEST 2026-10-09 ~23:00 UTC - TEAM QUEUE CANCEL + SEATS, AND A PLAYER-FACING OBSERVER THAT FINDS YOUR TEAM (L357, IDEA-1279/1280, KB-428); BUILT LOCALLY, NOT DEPLOYED.**
- MY ORG: CANCEL on every waiting move; a new seat move replaces the old; the tier's race seats and contract limit are stated; AFTER THE BOUNDARY shows the roster the queue leaves. The boundary now fills an empty race seat from the best reserve (KB-428: the owner's queue on Online, promote Joshua, release Joshua, sign Arnaud, would have left race1 empty).
- Observer: `observerAllow` = `*` (any player may enter via F3, still never automatically); your Paddock drivers in gold; Y jumps to them; ink HUD, how-to card, off-duty note.
- Gate ALL GREEN.
- **Deploy note:** `ncm_paddock/server/views.lua` also carries the undeployed scouting work (L355), so shipping MY ORG ships scouting too.
- **THE ONE NEXT ACTION:** deploy `ncm_paddock` (manager, views, requests, vendored core), `ncm_world` (panel.html, vendored core) and `ncm_observer` to Online, then MASTER_TEST Â§MQ1-Â§MQ3 and Â§OB-T1-Â§OB-T3.

**LATEST 2026-10-09 21:22 UTC - THE SLIPSTREAM MODULE IS LIVE ON ONLINE (L356, IDEA-1278).** Deployed by hash diff (256 files: `ncm_slipstream` new; `ncm_world`, `ncm_league`, `ncm_engineering`, `ncm_paddock` and the vendored core in every resource; NOT `ncm_link`, NOT the scouting `views.lua`). Schema 077 applied, `ncm_slipstream` ready, EDW-SL1 among the engineering designs, three units minted on the Base Market (Eddywright #1-#3, EUR$4,800), no ERR. Outage 21:16:30-21:18:44 (KB-427, nobody connected): the new resource's `shared/core/data/` was filtered out, the KB-423 mistake again. Backup `/opt/ncm/backups/pre-slipstream-20261009T211609Z` (`ncm.sql.gz`, `resources-ncm.tar.gz`). `panel.html` also carries the scouting UI, which falls back to today's display until `views.lua` ships. **THE ONE NEXT ACTION (owner):** MASTER_TEST Â§SS0-Â§SS3 -- buy the SL-1, mount it (F9), get in, hear it boot, follow a car.

**2026-10-09 ~21:00 UTC - THE SLIPSTREAM MODULE BUILT LOCALLY (L356, IDEA-1278, KB-426).**
- An **Eddywright Slipstream SL-1** (EDW-SL1, EUR$4,800, Base Market) installs in a new electronics bay (F9 bench) and boots once per installation in its own voice, with an ink HUD showing the real wake geometry. It locks wakes progressively, adds up to 30 % drag relief on top of the natural 15 %, and talks to other units: humans and Paddock NPCs, all four pairings. Switch on/off on F9 PARTS.
- Draft (`aero.wake`) is separate from the product (`aero.slipstream`). The old coasting-drag slipstream (KB-426) gave no tow on the throttle and is retired. The tow is now a force through the existing Machine wrench lease, so **no Carrier change**.
- New resource **`ncm_slipstream`** (deploy WHOLE: audio, web and vendored core); `ncm_league` schema 077 + market seeding; `ncm_world` (`slipTow` export, engineering lease, carrier_bridge cleanup, product name on the market card); `ncm_engineering` (F9 switch); `ncm_paddock` (NPC wakes in live races and the bubble).
- Gate ALL GREEN (core 1244 incl. 10 aero; new `tools/test-slipstream-host.lua`, 23 checks).
- **THE ONE NEXT ACTION:** deploy those six resources to Online with nobody connected (schema 077 migrates on boot); then MASTER_TEST Â§SS0-Â§SS3, reading `SLIPTRACE` lines for the A/B.

**LATEST 2026-10-09 ~20:00 UTC - SCOUTING REPORTS FOR PADDOCK DRIVERS BUILT LOCALLY (L355, IDEA-1277, KB-425); CALENDAR WEDGE FIXED ON ONLINE (KB-424).**
- **KB-424 (deployed Online 19:23 UTC):** the `ncm_league` calendar had been dead since 07:24 (`calendar.lua:545` every tick, 4,181 times; no event advanced). A duplicate id in `order` (racy `adopt`) was the cause. `adopt` now re-checks after its await, and each tick self-heals `order`. Clean boot, 0 errors after.
- **Scouting (not deployed):** 74% of drivers showed no tag, so hiring was blind. New `paddock.scouting`: a simulated pre-Paddock career from `paddock.sim` (labelled simulated; feeds earned tags), graded word banks plus compound tags from stats the sim reads, and a knowledge level that reveals more for drivers you know (your own read fully). Measured on Online's 868 drivers: 0% bare, 5-6 tags on average, about 2 ms per driver. Views: roster, free agents and profile carry tags, record and knowledge. The panel adds a RECORD column and rows that open the full report.
- Careers are computed by a background warmer in `ncm_paddock/server/views.lua` (free agents first, yielding every 4 races). Views only read the cache: the first build simulated in the view and blew the metered quota (11.1M instructions in one slice); it now peaks at 120k. On a fresh boot, a driver the warmer has not reached shows impressions without a career for a few seconds.
- Gate ALL GREEN under every interpreter (core 1234 incl. 7 new; paddock host 365; view quota max slice 120k).
- **THE ONE NEXT ACTION:** deploy `ncm_paddock` (server/views.lua + shared/core/paddock/scouting.lua + manifest), `ncm_world` (web/panel.html + shared core) and the core in the other vendored resources to Online with nobody connected; then run MASTER_TEST Â§SC0-Â§SC2 as a team manager.

**LATEST 2026-10-09 03:05 UTC - HOW TO PLAY LANDING SCREEN LIVE ON ONLINE (IDEA-1276).** Another session's `ncm_world/web/panel.html` change (What's New/changelog replaced by HOW TO PLAY NCM: four steps, the controls strip incl. F9 Engineering, rotating tips, patch notes behind a link) is deployed. The four stale landing assertions in `tools/panel-render-check.js` were rewritten for the new design; panel render 295/0, gate ALL GREEN. Restart 03:05 with nobody connected. Backup `/opt/ncm/backups/pre-landing-*`. Live look owed on next join.
**LATEST 2026-10-08 - HOW TO PLAY NCM LOGIN SCREEN BUILT LOCALLY; LIVE/RENDER PASS OWED (L354, IDEA-1276).**
- Replaced the What's New landing layout with the permanent four-step Market â†’ Machine Index â†’ Race Guide â†’ race flow, concise italic context, verified control strip, controller navigation prompt, and 53 auto-rotating/manual tips. â€œNeed fuel? Park at a pumpâ€¦â€ is always first; the rest shuffle each time the screen opens.
- Patch notes remain in the existing release data and are hidden behind a small opt-in affordance. Tips are grounded in current features and avoid hidden discovery systems.
- Controls checked in current client code: F6/pad Start hub, F5 Custom Race (Street Call implementation), F9 Engineering, F10 Machine Index, F8 Race Graph, F7 grid snap. Pad navigation is Confirm/Back/D-pad.
- Local files changed: `ncm/online/resources/ncm_world/web/panel.html`, `docs/ncm-online/BACKLOG.md`, `docs/ncm-online/DECISION_RECORD.md`, `docs/ncm-online/NOW.md`.
- No test or live verification run. **THE ONE NEXT ACTION:** render the landing page at desktop and narrow viewport sizes; join Online fresh and verify mouse, keyboard and controller dismissal/navigation, tip rotation, and optional Patch Notes.

**LATEST 2026-10-09 02:09 UTC - ENGINEERING PANEL (F9) LIVE; SELF REPAIR FREE OF LABOUR, ROLLED PER SECTION, DAMAGE WEIGHTED AND VISIBLE (L353, KB-422, KB-423).**
- Owner on today's persistent damage: labour charged for fixing your own car; 100% severity after one ordinary race; a car "100% damaged" that spawns looking new; one flat nerf for every self repair; service and parts crammed into Machine Index. Each was traced to code:
  - severity took the WORST of chassis, the single worst panel, and broken bits / 8, so 7 windows and a tyre read 100% on a car at 55% health;
  - self labour was a flat EUR$60;
  - the one `setup` number was copied to all four scalars and was positive only above 0.985;
  - `setDamage` ran in the same tick as `create`.
- Fixed: severity is now WEIGHTED (chassis .60, body .25, glass .06, lamps .04, tyres .03, panels .02; the owner's car reads ~34%). Self work costs materials only. Workmanship is FOUR independent rolls (grip, drive, brakes, drag), each able to gain or cost, with skill shifting the odds (-8%..+3.5%). Damage is re-applied at 1.5 s and 4 s after a spawn, like paint.
- **Engineering panel** = new resource `ncm_engineering`, F9, docked on the right, CURSOR-only focus (the game keeps the keyboard, so F9/Esc always work; focus follows `eng:drawn`, with a watchdog). Tabs:
  - SERVICE: each car's condition by area, both quotes, the workshop with Route Me There, a bench timer, then the job sheet. The four rolls are written in ink one at a time and stamped.
  - PARTS: the whole Parts Inventory port.
  - BUILD: reserved for civil engineering.
- Machine Index is observation only again: no repair buttons, Parts tab hidden; it points to F9.
- Gate ALL GREEN (core tests incl. 3 new; new `tools/engineering-render-check.js`, 15 assertions; panel render 293).
- **Outage 02:02-02:09 UTC (KB-423):** the deploy file list excluded `*/data/*`, so `ncm_engineering`'s vendored `shared/core/data/*` was missing. OPEN//77 refuses to start when a manifest pattern matches no file, and crash-looped 58 times. Nobody was connected. Fixed by uploading the full core; the boot is identical to the previous one plus `ncm_engineering`. Backup `/opt/ncm/backups/pre-engineering-20261009T020206Z`.
- **THE ONE NEXT ACTION (owner):** relaunch, press F9. Check that the panel docks right and you can still drive and press Esc; then service a damaged stored car at a workshop and watch the job sheet (MASTER_TEST Â§EN). Spawn a damaged car and confirm it LOOKS damaged.

**LATEST 2026-10-09 01:28 UTC - TIMING TOWER BACK (RADIO PORT CLASH), "P1 OF 1" AT RACE START FIXED (KB-420, KB-421).**
- **Tower invisible (on or off):** `ncm_radio.dll` was copied from Broadcast's bridge with its port base (38680) unchanged. Both plugins bound 38680/38681, and both in-game pages scan the same four ports, so the tower lost its plugin. The radio now has its own block, **38720-38723** (DLL + `client/radio.lua`), as NCM Radio **0.1.2**. The pack `VERSION` file now ships too: `Set-Content` silently wrote nothing, so the plugin reported `pack ` and the server warned "clips may be missing".
- **"P1 of 1" until the start:** the league formed the session at T-50 s, but the Paddock's grid landed at T-42 s (it was late; due at T-60). Without the grid the session was the humans alone. `race.lua` now waits for the Paddock grid before forming a mixed race, and forms with the humans alone only at T-15.
- **Publish trap:** `publish-carrier.py --id ncm-radio` drops every declared id that *starts with* `ncm-radio`, including the four voice packages. They were re-declared from the same blobs. Always publish the voices after the main package (OPS_STAGING).
- Online restarted 01:28 UTC with nobody connected. 17 mods, digest `217341fe...`, all five radio blobs 206, no ERR. Backup `/opt/ncm/backups/pre-fix3-20261009T012534Z`. Full gate ALL GREEN.
- **THE ONE NEXT ACTION (owner):** relaunch (NCM Radio 0.1.2 is a ~60 MB download), turn the tower on with `/ncm.tower`, enter a race without qualifying and confirm P12 of 12 from the grid on, with the tower drawn. Then listen to the radio across a race.

**LATEST 2026-10-09 00:56 UTC - RACE WEEK LIVE REWRITTEN TO TALK: THREADS, HANDOFFS, NO HOLLOW BEATS (L348 addendum 4, KB-419).**
- Owner on Online: "zero continuity and constant dead air", Mara's "Tommy?" with no Tommy, then a stinger, "Okay." and two minutes of nothing. Log: every beat (5-28 s) was followed by `40 s quiet`. Pure-slot lines the server cannot fill were silently dropped, leaving replies to nothing. Handoffs had no answer. No `race_start` fact existed at all.
- Fixed in `director.lua` / `facts.lua` / `build_corpus_lua.py`:
  - a breath of about 1-2.5 s between beats;
  - every line said, or the beat does not air;
  - handoff beats (`handoff=` in corpus_data) air only when the named voice can answer, and it answers next;
  - race threads: preview, then start (new fact), then result (tape `raceId`), with no bouncing to other races;
  - the studio continues its section in bible order;
  - repeats rest 45-90 min, then 20 min, then 15 min as the floor, before silence;
  - habitation and quiet are pacing, never the cause of silence;
  - segues are never filler;
  - severe-incident hold is 45 min, not 2 h.
- `tools/sim-radio.lua` (the real pack, a bad Week, Day 3 night): speech 96%, longest silence 2 s, 15/15 races previewed and called. `tools/pool-radio.lua`: about 45 min of studio talk is eligible in any one situation, so loops are expected over a long session. `test-radio` 33/33 in both runtimes; the full gate is ALL GREEN.
- Online restarted 00:56 UTC with nobody connected (owner: "fine to restart im off"). Backup `/opt/ncm/backups/pre-radio2-20261009T005441Z`. Mods unchanged (digest `6ba4aa05...`).
- **THE ONE NEXT ACTION (owner):** listen through a full race and a quiet stretch. Next for variety: the 60 dormant MID-race beats from the race's timed events (`paddock_race.detail_json`), and the `VERSION` file missing from the pack (cosmetic warning).

**LATEST 2026-10-09 00:07 UTC - RACE WEEK LIVE AND THE PER-SERIES PURSES ARE LIVE ON ONLINE (L348, IDEA-1272, KB-411, KB-417, KB-418).**
- **Radio:** the voice pack is complete: 14,015 clips, 9.4 h. 5,685 of 5,689 lines can be performed, and 622 of 623 airable beats locally (Online reports 619, as Online's names differ). Mara is recast to `aud_0_2`: the same design as the owner's `aud_0_0`, and the best of nine takes in `bench_voice.py` (16/16 intelligible, none empty). The render crash was not the voice: libsndfile overflowed the Windows stack writing long OGGs (KB-411, `render.write_ogg` writes in blocks). QC now spells Whisper's digits and compares names by letters (758 of 791 first-pass flags were false). Five clips never voice; their beats drop.
- **The voice pack is split across five required mods**, because OPEN//77 never serves an archive over 64 MiB (KB-418): `ncm-radio` 0.1.1 plus `ncm-radio-voices-1..4` 0.1.1. All five were downloaded back; the main package was hash-checked over public HTTPS. `tools/split-radio-pack.py` is now part of `build-radio.ps1`.
- **Payouts (the other session's IDEA-1272 / KB-417 work):** the six `ncm_league` files and `ncm_world/web/panel.html` are deployed. No migration (`economy_json` is from 035). `test-paddock-link.lua` was updated for the per-series fallback ladder (street_a = Street x1, entry 25). Four docs that had been saved in cp1252 were repaired to UTF-8. Full gate ALL GREEN under both interpreters.
- **Online state:** backup `/opt/ncm/backups/pre-carrier-prod-20261008T235833Z` (DB, operator state, resources). Two restarts (00:01, 00:07 UTC), with nobody connected for either. 17 required mods, digest `6ba4aa05...`; QA `online`; no ERR; `[ncm_radio] on the air: 619 beats ready of 1088, pack 3b887e44f0b6`.
- **THE ONE NEXT ACTION (owner):** relaunch from the launcher (five new radio packages, about 265 MB), join Online and get in a car. Race Week Live should already be playing (MASTER_TEST Â§RW1-Â§RW7). Then enter a race and read the Guide quote and the receipt for Â§BJ21.

**LATEST 2026-10-08 - PER-SERIES RACE ECONOMY BREATHES WITH RESULTS AND MOODY (IDEA-1272, KB-417).**
- Built local event-time pricing. Every newly adopted Paddock race freezes an intrigue score for its series from recent close gaps, current Cup points fight, winner variety/dominance, crash/contact DNFs and real Billie win-slip balance when available. No-history starts at authored baseline. The bounded x0.70-x1.30 factor adjusts both entry and purse; Moody tier `fx.purse` independently adjusts purse only (x0.50-x2.50).
- Authored division fallback ladder: Street x1-x7, Regional x10-x25, Pro x50-x100, Premier x250; named Street/GT/Hypercar series retain the pack ladder. Guide quote and result receipt show the intrigue/purse state; `economy_json` preserves it across restarts. Existing entered events keep their quote.
- Updated Economy v1, decision record, backlog, KB-417 and existing BJ21 acceptance line. **No tests run or deployment/live PASS claimed.**
- **THE ONE NEXT ACTION:** run the full local gate, then validate event pricing, entry debit and receipts on an isolated Development copy; log a live MASTER_TEST BJ21 PASS before treating it as done.
**LATEST 2026-10-08 - STREET PURSES DIFFERENTIATED AS WELL AS TOP TIERS (IDEA-1272, KB-417).**
- Authored multipliers now vary per series: Bedrock/MaiMai Ã—1, City Cup/Street Drag Ã—2, Night City Open Ã—3, Night City GT Ã—25, Hypercar Ã—250. Fees and payout lines scale together; economy IDs bumped for changed series.
- Street still has gritty entry choices, while higher Street formats carry more cost and upside. Moody `fx.purse` remains unwired; intrigue is open pending factual feeds and event quote freeze.
- No tests or deployment run.
- **THE ONE NEXT ACTION:** implement series intrigue from trustworthy race/standing data, quote and freeze the modifier, then wire Moody purse effects through settlement and receipts.
# NOW - the single next-action index

**LATEST 2026-10-08 - TOP-END RACE PURSES RAISED; INTRIGUE AND MOODY WIRING OPEN (IDEA-1272, KB-417).**
- GT scale raised from Ã—10 to Ã—25 and Hypercar from Ã—100 to Ã—250 in `ncm_pack_street`; Street remains at the gritty baseline. The shared constructor scales entry and finish lines; economy IDs bumped to v2.
- Moody `week.moody.effects()` defines purse multipliers, but settlement only consumes the separate Racing Week `money` carrier. Recorded KB-417. Series intrigue still needs factual inputs and an event quote/freeze contract; no human betting-split feed was found, so odds must not be invented (IDEA-1272).
- No tests run and no deployment/live PASS claimed.
- **THE ONE NEXT ACTION:** implement the server-derived per-series intrigue signal, quote before entry and freeze per event; wire active Moody `fx.purse` into payout and receipts while preserving DNF fee loss and solvent Street finishes.


> **STATUS: LEDGER** - living session memory, rewritten at the end of every working session.
> Authority map: [INDEX.md](INDEX.md).

**LATEST 2026-10-08 22:59 UTC - MACHINE INDEX TRANSFER AND BROWSER ACK FIX DEPLOYED; LIVE PASS OWED (KB-416, IDEA-1271).**
- The owner reported Machine Index still broken after the repair rollout and after two packet-size reductions. The live client logged a collection stream begin and a dropped malformed network event, with no collection completion. An earlier attempt also logged 42 panel messages sent and none received by WebUI. The new collection path encodes on the server, sends UTF-8 string fragments of at most 768 bytes, and forwards one browser fragment at a time after acknowledgement, retrying missed sends. Client Lua never serializes the full collection. The local 45-machine render and acknowledgement checks pass.
- Only `ncm_league/server/collection.lua`, `ncm_world/client/panel.lua`, and `ncm_world/web/panel.html` changed on Online. The 22:59 UTC restart loaded the collection resource and all 12 required mods with unchanged digest `9468c869...`. No mod or config change.
- **THE ONE NEXT ACTION:** owner reconnects after the restart and opens Machine Index once. Confirm `collection JSON browser complete`, all 45 slots drawn, repaired car condition and green/red scalar readout, and no malformed event; record a live PASS in MASTER_TEST WL18. If it still fails, use sender/receiver logs and the exact browser fragment count to fix the remaining boundary before claiming resolution.

**LATEST 2026-10-08 22:17 UTC - PAID CHASSIS REPAIR FIX DEPLOYED ONLINE (L350 addendum, IDEA-1269..1270, KB-415).**
- Owner reported paying for REPAIR IT YOURSELF while the car remained damaged, and clarified that repair buffs/nerfs apply to handling scalars. Online now restores full physical chassis damage on a new paid self/shop job; skill-driven workmanship persists four per-Machine handling multipliers, drawn green/red in Machine Index. ROUTE ME THERE sits under the nearest garage distance.
- Migration 076 applied. The earlier paid job left physical damage, then the car took more damage. The audited correction removed only the paid job's residual: stored health 0.891 -> 0.948 and glass mask 31 -> 4, with later damage retained. Workmanship is present. Week reset clears it.
- Online backup `/opt/ncm/backups/pre-carrier-prod-20261008T221006Z` contains verified database, operator state and full resource archive. Only 24 repair files plus a nine-file follow-up changed. Server active, migration 076, no new startup errors; all 12 required mods retained digest `9468c869...` across the pre/post boots, `server.jsonc` digest `c8f38956...` and 31 mod files unchanged. Local `ncm-test` ALL GREEN under both interpreters (1224 core tests each, host/SQL/panel/docs gates).
- **THE ONE NEXT ACTION:** owner joins Online, stores and calls the repaired car, then checks MASTER_TEST Â§WL16's physical damage and colored scalar readout; press ROUTE ME THERE for Â§WL17. A fresh self and shop repair still need live checks. The separate Â§NV and Â§CT visual checks remain queued below.

**LATEST 2026-10-08 (~16:05 ET) - NCM DEEP IN THE GAME'S OWN WORLD, DEPLOYED ONLINE; THE GALENA CARRIES THE HELLA'S FLIGHT FIT; SPACE IS SECRET AGAIN (L352, IDEA-1265..1267, KB-411..413).**
- **Space Lab removed** (it put the player outside REDengine's +-16,384 m box: KB-411). No portals, no package named for space: the world package is now `ncm_world_layer` (NCWE `ncm/ncwe/ncm_world_layer.ncwe`).
- **Native Deep:** past the 12 km seam the car is held in a stage inside the box with the game's Earth at its true angular size (core `space.stage`, `client/deepview.lua`); far out (> 6,000 km) Earth and the Moon are props at their true direction and size. NATIVE is the default camera; chase / high / earth are the WebGL scale views. KSA border gone from Guidance.
- **Galena (..000002) granted** the dev Hella's fit on Online via `ncm_world.ownerGrant` (PT-400, FD-1 hold Triangle, AC-6, IA-10 tap Triangle); tunable cleared. **KB-413 fixed by owner ruling (20:12 UTC):** the FD-1 now sits under the floor facing down (HOLD Triangle climbs on fusion); the IA-10 is in storage.
- Online restarted 20:03 UTC: 12 required mods, QA `online`, scars level 3 -> 696 placed, 0 refused (KB-410's plan-side yield). Backup `pre-carrier-prod-20261008T200000Z`. Gate: core 1222 per interpreter, every check green except the host-boot NPC race timing (KB-412, passes standalone).
- **THE ONE NEXT ACTION (owner):** relaunch from the launcher, hold Triangle in the Galena to climb, then MASTER_TEST Â§NV0-Â§NV5 and Â§CT1-Â§CT3 with screenshots (the face of the Earth under you calibrates IDEA-1266).
- **City takeover live (21:00 UTC, IDEA-1268):** the moodboard on 959 billboards/building screens and 922 lamp banners city-wide (Day 1 map 1.0.1, 33.8 MB); game ads, frames and collision untouched behind them. MASTER_TEST Â§CT1-Â§CT3.
- **Coder next:** IDEA-1266 after the first native screenshots; owner's notes from Â§CT2/Â§CT3 (wrong-facing or floating signs by location).

**EARLIER 2026-10-08 (~09:20 ET) - RACE WEEK DAY 1 MAP + SCARS LIVE ON ONLINE, WITH L349/L350 (L351, IDEA-1260..1263, IDEA-1264).**
- **Day 1 map:** built in NCWE Studio (beta, MCP-driven) over all 35 race nodes and deployed to Online as the world package `ncm_race_week_map` (Online now declares 11 required mods). Parque Del Mar and Downtown hand-dressed; 33 sites by `tools/ncwe/site_dress.py`. Project `ncm/ncwe/race_week_day1.ncwe`; art `tools/ncwe/race_week_art.py`.
- **Scars:** core `week.scars` + `data.race_week_sites`; `ncm_world/server/scars.lua`. First Online sync: run 2, level 2, 10 incidents -> 388 props, 0 refused. Wiped at rollover by run-keyed props.
- **Also on Online now (owner):** L349/L350 vehicle damage/repair/anchor work; migrations 073-075 applied. Backup `/opt/ncm/backups/pre-carrier-prod-20261008T130609Z`. `ncm_radio` and `ncm_link` withheld.
- **KSA retired from the player path (L351);** in-engine space is the next build (IDEA-1263): an empty NCWE space map, the whole OpenSpace universe drawn around the player in native cameras.
- Gate ALL GREEN before deploy (core 1215 per interpreter). KB-407..410 recorded (NCWE crash, 40-item cap, the archivexl dependency that stopped every resource for 7 min, scars instruction quota) -- the last two fixed and verified on Online.
- **Space Lab live on Online (17:04 UTC):** hologram column on the Parque Del Mar beach -> station A (game Earth as from 400 km, 30 km star shell) -> B (prop-scale Earth, Moon, 200 m shell). Launcher download of the Day 1 map package seen in the log (13:41 UTC; half of Â§DY1).
- **THE ONE NEXT ACTION (owner):** launch Online from the launcher and run MASTER_TEST Â§SL1-Â§SL4 (screenshots decide the native-space design) and Â§DY1-Â§DY4 (map installs, Parque Del Mar reads, traffic flows) plus Â§WL0; then `ncm.scars` for Â§DY5.
- **Coder next:** the space map (IDEA-1263); per-site fan zones/hospitality (IDEA-1264).

**EARLIER 2026-10-08 - NPC WEEK DAMAGE AND ENGINEERING LOCAL PASS (L350, IDEA-1254..1258); NO DEPLOY OR LIVE PASS.**
- NPC serialized race cars now accumulate condition from modelled crash/mechanical results and physical health loss. Race/asset/provenance are stored once. A damaged car loses model pace and spawns physically damaged; a wreck or car in service misses the grid. The automatic crash repair bill is removed. Migration 074 stores incidents and scheduled work; migration 075 gives spec entrants separate organiser cars and finite repair budgets. NPC Week archive moves both plus conditions with the cars.
- NPC teams and independents pay from their own balances for quotes split into materials and labour; spec organisers use a finite per-car budget. The garage pass books only affordable jobs, with access/parts time plus short bench time. Pro/premier teams prefer shop service; independents tend to self service. Workmanship uses the team's actual engineer or an independent's developing skill; outcomes normally leave residual damage and a model setup penalty, with a rare bounded buff. Unfunded independents continue damaged or miss a start. Spare team car sourcing remains open (IDEA-1256). Human self work requires attending a mapped garage/workshop with the stored car; Machine Index quotes the nearest site and the material/labour split. The rare positive setup score is not yet applied to human vehicle handling (KB-406).
- Prior gate: core 1206/1206 per interpreter, Lua syntax 0 bad, host boot 64/64, SQL 521 prepared, web render and documentation checks green. The latest spec-car and workshop work needs a fresh gate. MASTER_TEST WL0-WL15 are **NOT RUN**. The workspace contains unrelated edits; nothing was deployed or committed.
- **THE ONE NEXT ACTION:** run the full gate, then validate migrations 074-075 and WL10-WL15 on an isolated Development copy with a database backup. Team loaner sourcing remains open. Online rollout remains pending live evidence.

**EARLIER 2026-10-08 (~05:40 ET) - ONLINE TEMPORAL-LOOP VEHICLE RULE BUILT LOCALLY (L349, IDEA-1248..1253); NO DEPLOY OR LIVE PASS.**
- **Rule:** one chosen Machine through the Week, otherwise last actually driven; its installed Parts and NCM components loaded at its physical trunk follow it. Other cars/loose components archive. Canonical vehicle damage persists within a Week and clears for the surviving car at reset; the Online ledger reopens at â‚¬$10,000. Machine Index offers self and shop repair, no new chat command. Knowledge/observations remain. Sporting standing reset is a provisional interpretation awaiting the owner's answer. Vanilla items have no authoritative trunk bridge yet (IDEA-1252).
- **Built:** migration 073, `week.collapse.onlineAnchor`, authenticated drive checkpoint, `ncm_world/server/vehicle_condition.lua`, immutable `vehicle_repair`, self-work competency, Machine Index buttons, component trunk custody, occupied-car rewind fix (KB-404). Full `ncm-test` ALL GREEN under Lua 5.4 and LuaJIT (core 1204 per runtime, host boot 64/64, SQL 503 translated/prepared, docs authority green); Â§WL0-Â§WL9 all **NOT RUN**. Existing radio/engineering working-tree changes were preserved; none of this was deployed or committed.
- **THE ONE NEXT ACTION:** boot migration 073 in an isolated Development copy with a database backup, then run MASTER_TEST Â§WL0-Â§WL9 and inspect the collapse plan before any live reset. The owner may clarify licence/rating/SR via the pending question; do not quietly promote the provisional standing policy to Online.

**EARLIER 2026-10-08 (~05:00 ET) - RACE WEEK LIVE BUILT: THE DETERMINISTIC TALK STATION IS A ROW IN THE GAME'S RADIO LIST (L348, doc 59, IDEA-1238..1243).**
- **What exists:** the owner's authoring bible imported verbatim ([radio/RACE_WEEK_RADIO_BIBLE.md](radio/RACE_WEEK_RADIO_BIBLE.md)) -> 773 beats / 3,470 lines (compile refuses to drop one); a trigger map (478 beats live on facts NCM emits, 295 dormant); the `ncm_radio` resource (SELECT-only facts, per-listener director, mid-broadcast tune-in); the `ncm-radio` plugin (miniaudio playback, redscript station row index 7700, default-on unless the player ever chose another station). OmniVoice voices on the owner's GPU (`D:/ncm-radio`). Gate ALL GREEN (`test-radio.lua` 22 checks, both interpreters); redscript compiles against vanilla + installed mods. **Nothing heard in game yet; not deployed anywhere; nothing committed.**
- **Update (same session):** cast picked (Mara `aud_0_0` after KB-403; three driver voices); the owner's expanded bible imported (1,088 beats / 5,689 lines, both speaker formats); Â§246 habitation budget in the director; `test-radio.lua` 24 checks. Render chains running on the GPU (`D:/ncm-radio/render-chain*.status`, ~2.5 h).
- **Tagged:** all 623 airable beats hand-read for Â§206 shapes and Â§208 delivery; 11 Â§247 motifs with per-driver show history; a bad Week now silences generic studio jokes. `test-radio.lua` 30 checks, both runtimes; gate ALL GREEN.
- **THE ONE NEXT ACTION (owner):** OK an Online deploy + restart (owner: Online first, not dev) so `ncm_radio` boots there and writes `lexicon.json` (the names to voice).
- **Coder next:** after dev boots: merge `ncm_radio/data/lexicon.json` (`seed_lexicon.py --merge`), `render.py lexicon` for the names, `build_corpus_lua.py`, `tools/build-radio.ps1`, publish `--id ncm-radio` to dev, MASTER_TEST Â§RW0-Â§RW7; then the same to Online.
- **Owner decisions open (doc 59 Â§7):** the whole bible is ~2 h of speech for a 72 h Week (more writing / music beds / sparse station, IDEA-1241); fills for `{SUPPORTED_*}` abstract slots (IDEA-1242); unseen play-by-play framing (below, still open).
- Also fixed in passing: doc 58's banner (`SPEC / AUDIT ONLY` was not a valid status and failed the docs gate).

**EARLIER 2026-10-08 - SIM-ONLY SETTLED RESULTS CLEARED FOR ON-AIR USE (L347, IDEA-1237):** the equal co-hosts may discuss settled results nobody physically witnessed. Preserve simulated provenance internally, but never label it as a simulation/replay to the player. Detailed unseen moment-by-moment play-by-play remains open. Audit: [58_DETERMINISTIC_RACE_WEEK_RADIO_AUDIT.md](58_DETERMINISTIC_RACE_WEEK_RADIO_AUDIT.md). **THE ONE NEXT ACTION:** decide how hosts may frame unseen race action (passes, mistakes, contact), if at all, before authoring those play-by-play segments. No runtime implementation.

**EARLIER 2026-10-08 (~00:40 ET) - L344 NIGHT CITY CHRONICLES BUILT AND SPOKEN THROUGH SPEAKERS:** Narrator, News, Race Control, Street Voices and Garage each had a voice, room and stinger; 16 fixture segments, two DEDUPs; tests 12/12. Audit and architecture are in doc 57; Chronicles reads NCM tables read-only; no server code changed or deployed. Online reads are configured in `chronicles.json` (tape `ncm-dev`, driver baremetaleven), but the canonical run remains owed.


**EARLIER 2026-10-08 (~00:00 ET) - ONLINE HAS DEV'S WHOLE CLIENT STACK, STACKED GEARBOXES AND NPC RACER QUICKHACKING (L341 addenda 1-2, L343); deployed Online 03:58 UTC, dev restarted in sync.**
- **Online now:** 11 required mods (Carrier 0.1.38, Gearbox 0.3.2, Snowglobe 0.0.5, Thrust 0.0.2 added/updated); manuals are manuals (clones ON, sales OPEN); stacked gearboxes installable (driveline mounts; gearbox designs reach markets through physical R&D, first runs ~6/9/15 h after boot); NPC racers hack, defend and purge (L343); destroyed race cars are crash DNFs and Race Week incidents. Owner's ESP32 wheel visible again (KB-397: HidHide) and listed in Devices -> GAMEPAD.
- **THE ONE NEXT ACTION (owner):** join Online, map wheel buttons to X (up) / A (down) in Devices -> GAMEPAD, then a street Paddock race: watch for NPC uploads (INCOMING), purge one, and send the log -- MASTER_TEST Â§HK1-Â§HK5.
- **Coder next:** read the first live `[ncm_paddock/hack]` trace and tune the decision weights from evidence; Â§SG on dev with fabricated boxes; IDEA-1227 when the pair memory has data. Nothing here is committed yet.

**EARLIER 2026-10-07 (21:39 ET) - L342 PHYSICAL MANUFACTURER R&D IS DEPLOYED ON ONLINE AND DEV (commits `14fdb2a`, `f28c409`).** The five roots are unsold; five v2 programmes research attitude, fuel propulsion, impulse, tank and fusion designs. New specs persist in migration 071, competency in 072; the shared core, markets, Panel Parts purchase, client simulation and WIRE stories are wired. Fuelled RP-16/IA-10 roots now use 360 s Isp (dev fuel waiver remains explicit). Online backup `pre-carrier-prod-20261008T012803Z`; migrations 071-072 applied, corrected boot active as `environment = online`, five physical programme rows seeded, first attitude evaluation due **2026-10-08 09:36 ET**. The first boot hit KB-395 (undeclared tunable); fixed in `f28c409`, redeployed and verified. Dev migrated and restarted 21:38 ET. Full gate ALL GREEN (core 1185 per runtime, host boot 64/64, SQL 477/477); **no Â§RN live gameplay PASS yet**. KB-393's missing-identity fallback now fails closed.
- **THE ONE NEXT ACTION (owner):** join Online once and drive a race to validate Baseline 3; after 09:36 ET, open Panel -> Parts and inspect the first R&D attitude offer (Â§RN1-Â§RN2), then buy/mount if it is stocked and affordable.
- **Coder next:** inspect the first accepted physical run, spec and WIRE record on Online; complete Â§RN3-Â§RN6 live checks and dev soak. Keep the existing solo parity work moving; R&D is built, not marked done until live PASS (L69).

**EARLIER 2026-10-07 (21:00 ET) - L341 NCM ONLINE IS ON BASELINE 3 (DEPLOYED 00:51 UTC, `online-baseline-3`), AND ONLINE IS FINALLY `environment = online` (KB-393: it had no tunables.json and always booted as development; fixed 00:56 UTC, owner yes). Backup `pre-carrier-prod-20261008T004829Z`; first boots clean (0 ERR, migrations 059-070, every league subsystem). Contents: dev's whole tree minus `ncm_link` (Los Santos); DEEP AND FLIGHT ON for Online; dev fuel / heat / attitude / fabrication / grant stay development-only; EVERY TYPED TUNING COMMAND REMOVED on all servers (`/ncm.setup`, `/ncm.govern`, `/ncm.topspeed`, gear and mass flats, `/ncm.eng.devfuel`, `/ncm.deep.go`; KB-392 = they were open to any Online player on Baseline 2). Flight parts reach Online only through manufacturer R&D, which cannot make them yet: proposal [56_RND_OVERHAUL.md](56_RND_OVERHAUL.md) for the next coder (IDEA-1223/1224, Q1-Q6). Gate ALL GREEN; dev restarted clean 20:34 (`l384-restart-20261007.stdout.log`).**
- **Online vs dev (hash diff 2026-10-07):** Online was exactly Baseline 2 (`fb23f35`): 1,037 files new, 100 changed, 0 removed; migrations 059-070 pending; required mods identical (digest `7b070f25...`), so no mod republish.
- **THE ONE NEXT ACTION (owner):** join NCM Online once and drive: the launcher needs nothing new (same 8 mods); a race and the Racing Week line should work as on dev. Flight cannot work yet on Online (no flight hardware until doc 56).
- **Coder next:** KB-393's open half (a missing identity must mean NOT development in `ncm_world`), then doc 56 step 1.

**EARLIER 2026-10-07 (late night, later) - SINGLE PLAYER TOWARD DEV-SERVER PARITY (L340), PHASE 1 BUILT AND INSTALLED (3.0.0-alpha.4): the NCM plugins -- Carrier, Rig Bridge, Scanner (Vision), Broadcast, Pace -- were installed but unreachable in single player (no browser: KB-386); `ncm_host` now speaks their sockets itself, so the dev server's resources reach them unchanged. Owner rulings: zero CET, native ink screens, the tape chosen from the menu AND the phone, the V roll parked (IDEA-1222). The "strange man" was OPEN//77's NCMP-Template-M save, not NCM (load AutoSave-15 / ManualSave-63). Gates: host webui 14/14, host boot 60/60, native self-test 0 failures, ncm-test ALL GREEN.**
- **LIVE 19:09: PHASE 1 PASSES** -- `MACHINE CHANNEL BOUND to the NCM Carrier 0.1.37`, scanner / Pace / Broadcast / Rig Bridge transports up, 0 errors (Â§PB1, Â§PB3). The owner's screenshot showed every NCM map pin floating in the sky (KB-387): fixed and installed (map + minimap pins; log readable live).
- **"crazy lag" (KB-388) -> CET REMOVED (L340 phase 2, 3.0.0-alpha.5, INSTALLED):** the game drives NCM natively (redscript runtime, ink Race Week line, NIGHT CITY MOTORSPORTS in the main + pause menus); the CET mod is pruned; NCM 2.0's leftover redscript is parked (it hooked every map pin). Map layers stay off until phase 3 redraws them under a budget.
- **alpha.5's menu popup LOCKED THE GAME (KB-389)** -- all input captured, nothing drawn. **alpha.6 (installed)** has no popup: one pause-menu item that says what it will do and resumes the game.
- **alpha.7 (installed): no NCM button at all -- the tape is set in Mod Settings** (owner: "just put it in mod settings"); the plugin now logs every frame NCM holds > 8 ms with the job that took it (owner: "still laggy at points"). KB-390 records plainly that NO dev-server screen exists in single player yet (F6 hub, Race Guide, race HUD, nameplates, observer, the whole Deep renderer).
- **THE ONE NEXT ACTION (owner):** load YOUR save, Esc -> Settings -> Mod Settings -> Night City Motorsports -> Tape in play = 1 -> Apply; play as normal; send `red4ext/plugins/ncm_host/ncm_host.log` when it hitches (Â§PB6, Â§PB9).
- **Coder next (phase 2):** the redscript runtime replaces CET (tick, game commands, input), the menu entry + phone front doors; then phase 3 screens, phase 4 spawning (plan: L340).

**EARLIER 2026-10-07 (late night) - AEROSPACE RACING IN SINGLE PLAYER BUILT (L339): a field of one of your tape's own machines races Night City -> Pothole -> 120 km in Deep -> Hill Abode, one tower the whole way, NPCs flying their machine's real physics (mass, drag, heat: same parts, different machines, different races); hard landings over Night City reach Race Week. Resource `ncm_aero` (single player only; never on the dev server); the deck has an AEROSPACE RACE section. Package `dist/ncm-3.0.0-alpha.3.zip` (alpha.2 untouched). Gates: core 1182/1182, host boot 60/60, native self-test 0 failures, ncm-test ALL GREEN. NOT installed; no live run.**
- **THE ONE NEXT ACTION (owner):** close Cyberpunk, `tools/install-ncm3-kimiko.ps1 -UpdateNcm`, start from Steam, enter your tape (with a claimed machine), Tape Deck -> AEROSPACE RACE -> Start (MASTER_TEST Â§XR1-Â§XR6; DEV x10 to watch a whole race in ~1.5 min).
- **Coder next:** the player as an entrant (IDEA-1209), the Race Week tolerance line (IDEA-1211), the Moon leg (IDEA-1212). Finding: a thrust/weight ~1.2 machine cannot land Hill Abode under the course pilot (IDEA-1214, a decision).

**EARLIER 2026-10-07 (night) - NCM 3.0 alpha.2 INSTALLED: THE SIMULATION NOW RUNS IN A NATIVE PLUGIN (owner ruling, L338 addendum). Four live boots taught us CET's sandbox has no load/loadstring/setfenv/_G/coroutine (KB-383, KB-384, KB-385), so the NCM resources cannot run inside CET. `ncm_host` (RED4ext, Lua 5.4.7 + SQLite 3.49.1, `ncm/host_native`) runs ncm/host + the resources unchanged; the CET mod is the deck, the Race Week line and the game bindings over `NcmHost_Call`. Native self-test PASS (mount, 5 min, Kimiko claim serialized, 0 errors); CET-side simulation PASS (deck -> NEW TAPE -> RW 01 . D1 -> claim -> V's garage). Installed with -UpdateNcm (2,653 obsolete in-CET files pruned). No live run of alpha.2 yet.**
- **THE ONE NEXT ACTION (owner):** launcher on your own game, start Cyberpunk from Steam, look for `[NCM 3.0] plugin found via ...` in scripting.log and `red4ext/plugins/ncm_host/ncm_host.log`; load a save, NEW TAPE, GARAGE -> Claim Kimiko Racing (Â§TP10). Send both logs if anything fails.
- **Parallel (session cyberpunk2077-a0):** aerospace-course core work (flightbody, loadout, aerocourse) is in ncm/core, NOT vendored and NOT in alpha.2; its ledgers follow this entry (next free: IDEA-1201, KB-386, L339).

**EARLIER 2026-10-07 (late evening) - THE KIMIKO RB15 IS READY TO INSTALL AND CLAIM (L338 addendum): all ten RB15 liveries rebuilt (Kimiko Racing / Orbital Air with its own badges), each a callable player vehicle; NCM 3.0's deck has a GARAGE that claims the car you sit in or any livery as a SERIALIZED machine on the tape (birth certificate, livery colours, passport formula/kimiko) and puts it in V's garage; any car NCM has never seen becomes its own machine. Gate ALL GREEN (host boot 49/49). INSTALLED on this PC 2026-10-07 evening (record install-records/ncm3-kimiko, 1,358 files, one backup; -Uninstall reverses); no live run yet.**
- **THE ONE NEXT ACTION (owner):** close Cyberpunk, run `tools/install-ncm3-kimiko.ps1`, start Cyberpunk from Steam (not the OPEN//77 launcher), bind "NCM: Tape Deck" in CET Bindings, enter a tape, GARAGE -> Claim Kimiko Racing Â· Orbital Air, call it, drive (Â§TP9-Â§TP12). `-Uninstall` puts the game back.
- **Solo stack (owner switched OPEN//77 to his own game, 16:37):** the launcher now owns only 6 loader files (no OPEN//77 client loads). Adjusted for single player, all reversible (record `install-records/ncm3-kimiko/solo-adjust.json`): the new livery manifest restored (Solo had put back the Sept 19 copy); `ncm_thrust` and `ncm_snowglobe` config `enabled=false` (dev-only; Triangle must not push the F1 car); old NCM 2.0 `MT_Ecosystem` moved to `cyber_engine_tweaks/mods_disabled`. For the dev world: set the two configs back to `enabled: true` if wanted.

**EARLIER 2026-10-07 (evening) - L338 NCM 3.0 SINGLE PLAYER, ALPHA BUILT (headless-green, NOT yet run in game): the NCM Host runs the dev server's resources UNCHANGED inside Cyberpunk (CET) over SQLite -- no OPEN//77, no MariaDB. Race Week TAPES: one tape = one continuity = one server_id; the present is CALCULATED on return (core `week.catchup`: every missed verdict judged in order, nothing runs while you are away). The deck is the front door (main menu + on save load; NCM dormant until you choose; CYBERPUNK WITHOUT NCM). Gates: SQL 460/460 statements translate + prepare; boot 37/37 (19 days away -> RW 06 on the deck = RW 06 in the world, a Hella stranded in Deep back in Night City, TAPE 02 isolated, clock regression held). Package `dist/ncm-3.0.0-alpha.1.zip` (not installed). Dev fixes KB-379 (canonical boot), KB-380 (FNV), KB-381 (Week catch-up) reach dev at its next restart; dev not restarted; Online (Lightsail) untouched. Seam report: doc 55.**
- **THE ONE NEXT ACTION (owner):** when you want to see it: back up your CP saves, extract the zip into the game folder, launch Cyberpunk WITHOUT the OPEN//77 launcher, and run MASTER_TEST Â§TP0-Â§TP4 (deck, a tape, the RW line, the pad). Coder next (doc 55 Â§8): the eddies wallet seam (IDEA-1182), then spawning so the Paddock races in single player (IDEA-1188).

**EARLIER 2026-10-07 (14:00 ET) - NIGHT CITY TO KSA, LIVE, END TO END (L336/L337): Guidance flew your Hella to the KSA border in 3 h 34 m, you opted into the deeper layer, KSA started, proved the placement and took the SAME Hella (teal, real size, your FD-1 / PT-400 / AC-6) -- VERIFIED to a micrometre. The Machine Passport is live (AC now picks an ordinary Alfa, not the Maserati). Fixed today: KB-372 Guide crash, KB-373 thrust/weight (FD-1 30 kN, PT-400, coast), KB-374 late self-test, KB-375 consent, KB-376 Guidance steering, KB-378 KSA full tank.**
- **THE ONE NEXT ACTION (owner):** next time you climb out of Night City anyway, look at the ascent (Â§MP5): our Earth is now drawn with the game's own camera, read live (IDEA-1174; no more measurement climbs). Then a Laguna trip to see the passport's AC body (Â§MP1).

**EARLIER 2026-10-07 (01:30 ET) - L335 KSA IS WIRED TO NCM DEEP: KSA installed with the StarMap loader and NCM's own KSA mod; the bridge starts KSA (23 s), places the Machine at the border state Deep hands over and READS IT BACK -- verified to 0 m and 0 m/s on the bench. Guidance now shows a PRE-FLIGHT checklist for the KSA border and will not fly unless every line passes; on dev, holding L3 rehearses the whole handoff in a minute. The border is now KSA's own sphere of influence (854,000 km). Dev 01:28 (`l372-restart-20261007.stdout.log`); bridge 01:26. Online (Lightsail) untouched.**
- **THE ONE NEXT ACTION (owner):** rehearse (Â§KS9): Deep -> D-pad up -> select the KSA border -> A (self-test, KSA opens) -> hold L3. Then the real ~3.8 h flight whenever you want it.

**EARLIER 2026-10-07 (01:05 ET) - L334 DEEP TO THE KSA BORDER BUILT ON DEV: the Earth now rotates in Deep (orbits are real), your Hella carries a Fusion Drive FD-1 (rear, hold Triangle) and a Propellant Tank PT-500 (front) -- the RP-16 is in storage -- and Guidance's first target is the KSA border, Earth's sphere of influence at 925,000 km: ~3.8 h at ~1 g, flown by the server if you log off. In simulation it arrives with 110 kg of 500 kg to spare. The KSA handoff itself waits for your KSA install. Dev restarted 01:01 (`l371-restart-20261007.stdout.log`). Online (Lightsail) untouched.**
- **THE ONE NEXT ACTION (owner):** install KSA from ahwoo.com (free; default path) and say so -- then the probe mod (Â§KS1). Meanwhile: hold Triangle in Night City (Â§KS3), climb into Deep and engage Guidance to the KSA border (Â§KS4-Â§KS6).

**EARLIER 2026-10-07 (00:15 ET) - KB-369 FIXED: A on a Guidance target no longer throws you home -- one slow frame (the engage frame tipped OPEN//77's ~6 ms per-frame budget) is now skipped, not fatal; the engage frame only plans. KB-370: the mod stack was never shuffled -- every installed NCM DLL hash-matches its newest build (Carrier 0.1.37 ...); RED4ext's version line is a stale hard-coded label. Dev restarted 00:14 (`l368-restart-20261007.stdout.log`). Online (Lightsail) untouched.**
- **THE ONE NEXT ACTION (owner):** climb into Deep, pick a target, A: Guidance flies (the log may say `frame over the script budget -- skipped`, harmless). Then Laguna -> AC climb-out (Â§AC16) and the geography (Â§RD1, Â§RD6).

**EARLIER 2026-10-06 (23:55 ET) - KB-368 FIXED: the L332 renderer's tile prefetch blew Open77's per-frame script budget inside the Deep flight frame, crashed the flight on your 23:48 resume and dropped you at 11.5 km over Night City -- that is why the hop "did nothing" (you were falling). Prefetch now runs off the flight frame, one point per frame; geography can never end a flight. Dev restarted 23:54 (`l367-restart-20261007.stdout.log`); bridge 23:40 with tiles. Online (Lightsail) untouched.**
- **THE ONE NEXT ACTION (owner):** rejoin dev; hop in Night City as before; then the Laguna trip and the AC climb-out (Â§AC16) with the new geography on the way (Â§RD1, Â§RD6).

**EARLIER 2026-10-06 (23:42 ET) - KB-367 + L333: AC's hop is now Night City's hop -- a velocity change through the centre of mass that cannot twist the car (the old push carried a moment and AC never damps spin in the air). Owner ruling L333: no part exists in one game only. Bridge restarted 23:40 with the tile cache (L332 live for both renderers). Dev 23:29 (`l366-restart-20261006.stdout.log`). Online (Lightsail) untouched.**
- **THE ONE NEXT ACTION (owner):** fly to Laguna, hop out through the sky (Â§AC16), and on the way look at the new geography (Â§RD1, Â§RD6). If it still tips, the bridge log's `hopSpin` lines say how, and IDEA-1168 is next (the AC-6 holding level, both games).

**EARLIER 2026-10-06 (23:35 ET) - L332 DEEP RENDERER BUILT ON DEV: real geography under you (public-domain imagery to ~1 m in the US, ~30 m elsewhere, prefetched along your path), the planet ray-traced (no facets near the ground), the world drawn at a lower internal resolution and rebuilt with EASU + RCAS, the HUD never upscaled. Headless: 3 km over Laguna = 2.4 m per texel, sharp HUD at 50 % scale. Dev restarted 23:29 (`l366-restart-20261006.stdout.log`). The HOST BRIDGE is NOT restarted (AC was running): until it restarts Deep shows the global image as before. Online (Lightsail) untouched.**
- **THE ONE NEXT ACTION (owner):** close AC; I restart the bridge; then fly the California descent (Â§RD1-Â§RD6) -- the RENDER / GEOGRAPHY lines on the HUD say what it is doing.

**EARLIER 2026-10-06 (19:08 ET) - KB-364 FIXED: racing (ncm_league) had stopped at 19:00:58 -- the AC-6 grant's player-less change event crashed it, so nothing reached the Race Guide. Guarded on both sides; dev restarted 19:07 (`l365-restart-20261006.stdout.log`), racing up, 5 races posted. The AC-6 stays on your Hella. Online (Lightsail) untouched.**
- **THE ONE NEXT ACTION (owner):** open the Race Guide (races should be listed), then fly the Hella in Deep with the AC-6 (Â§EN14, Â§FM3) and the AC hop (Â§AC15).

**EARLIER 2026-10-06 (18:32 ET) - KB-363 + IDEA-1163: THE BENCH IS ON THE PAD. Panel -> Parts now fabricates (dev), mounts with a facing and removes add-ons by holds -- no typing. The AC-6 is ON your Hella (..0003): roof, facing up, revision 9 (granted 19:00:58). Dev restarted 19:00 (`l364-restart-20261006.stdout.log`). Online (Lightsail) untouched.**
- **THE ONE NEXT ACTION (owner):** get in the Hella and fly Deep: the ATTITUDE line shows +/- on all three axes with no waiver label (Â§EN14, Â§FM3). Â§AC15 (the AC hop) is still waiting too.

**EARLIER 2026-10-06 (18:03 ET) - KB-362 FIXED: the AC hop now pushes through the car's centre of mass, straight along its up axis (as in Night City) -- it no longer rolls the car onto its side or roof. Tap Triangle repeatedly to climb; past 6 km going up, Deep takes over. The fix reaches AC at the next embodiment (the bridge copies the app). L331 below is unchanged.**
- **THE ONE NEXT ACTION (owner):** fly to Laguna Seca, land, and hop out through the sky (Â§AC15), then continue Â§FM1.

**EARLIER 2026-10-06 (17:52 ET) - L331 DEEP ON THE FULL MACHINE MODEL: one 6-DOF machine (your install + chassis + tank) in Cyberpunk's Deep, AC's Deep and the server's offline flight; air thins with altitude; off-centre thrust spins it; parts heat up and shut down; Guidance turns the car's real thrust axis. Today's Hella cannot point itself (no yaw/roll) -- on DEV a labelled attitude waiver flies it as before; the new Zetatech AC-6 attitude set (`/ncm.eng.fabricate ac6`) makes it physical. Dev 17:52 (`l360-restart-20261006.stdout.log`). Core 1129 green.**
- **THE ONE NEXT ACTION (owner):** fly as before on the waiver (Â§FM1; the HUD now shows ATTITUDE and AIR), then fabricate + install the AC-6 and fly without the waiver label (Â§FM3).

**EARLIER 2026-10-06 (16:57 ET) - KB-361 + KB-360 FIXED: the join over Laguna now waits for your parts, holds you there (B = stay keeps holding), never queues a stale AC close, and drops you into a Track day / practice session too; the JSON encoder no longer rounds Deep positions to ~10 km (`%.14g`). The vendored core ran in real AC for the first time (CSP: `loaded and ready to run`). Dev + bridge 16:56 (`l359-restart-20261006.stdout.log`). You are canonically at Laguna Seca (run 2).**
- **THE ONE NEXT ACTION (owner):** join dev: you hover ~80 m over Laguna with the prompt (give it a few seconds for your parts); A: AC opens in whatever session Laguna's timetable says and you drop in (Â§RT16); Triangle tap/hold (Â§RT14).

**EARLIER 2026-10-06 (16:35 ET) - L330 THE RACING WEEK IS THE UNIVERSE'S TEMPORAL LOOP: the Earth venues race on the run's SEEDED calendar (posted timetables: practice, qualifying, grid, race, track day; dark unlit circuits closed), you drop into the session the clock says (AC configured to it), Guidance shows each place's timetable; at a reset every Machine -- Night City, Deep, AC, online or not -- is back in Night City (verified live 16:33 on a last-run test record). Dev 16:33 (`l358-restart-20261006.stdout.log`). Gate green (core 1118). You are canonically at Laguna Seca, run 2.**
- **THE ONE NEXT ACTION (owner):** join dev -> over Laguna, A: you drop into whatever session Laguna's timetable says now (Â§RT16); D-pad up to read other venues' timetables (Â§RT15); Triangle hop/hold (Â§RT14).

**EARLIER 2026-10-06 (16:00 ET) - KB-359 + ONE SUN: in AC the hop/RP-16 forces are now scaled to CSP's physics step (they were 0.23x), AC's horn is moved off Y (adapter-owned, restorable), the drop waits for the race start and comes in low (80 m, straight down); Deep's sun and AC's sky follow NCM's real UTC clock (night = night). Owner's 15:38-15:49 run: Cyberpunk -> AC worked, Cyberpunk closed by itself once AC had the Machine, NPCs racing. Dev 16:00 (`l356-restart-20261006.stdout.log`); you are canonically at Laguna Seca. Gate green (core 1114).**
- **THE ONE NEXT ACTION (owner):** join dev (you appear over Laguna with the AC prompt), A: drop in, Triangle tap/hold (Â§RT14), check the sky time (Â§RT13); then up past 6 km and Guidance to Night City (Â§RT2-Â§RT5).

**EARLIER 2026-10-06 (15:30 ET) - L329 ONE UNIVERSE BUILT: one Deep record on the NCM server (presence, unhosted flight -- "autopilot keeps going" -- verified live: the server flew a test Machine 1,009 s to Laguna Seca with no game running), Deep INSIDE Assetto Corsa on the same vendored core (up through AC's sky; Night City in its Guidance), the host lifecycle (Cyberpunk closes once AC has the Machine; launched again ~60 km from Night City), consent-gated adapters + HOST ADAPTERS panel, the place registry (45 layouts: 32 verified, 13 unresolved, live), resume where you are on join. KB-358 fixed. Dev 15:29 (`l355-restart-20261006.stdout.log`); bridge restarted. Gate green (core 1112+).**
- **THE ONE NEXT ACTION (owner):** the round trip, hands off Windows (MASTER_TEST Â§RT1-Â§RT5): Night City -> Laguna Seca -> race -> hop/hold up past 6 km -> Guidance Night City -> keep flying until Cyberpunk takes you. Then Â§RT6 (quit in Deep).

**EARLIER 2026-10-06 (14:30 ET) - L328 POST-LAGUNA PASS BUILT, DEV RESTARTED 14:25 (`l348-restart-20261006.stdout.log`, migration 067 applied). The owner's Laguna run is recorded as Â§AC1-Â§AC4 + Â§AC6 PASS (Â§AC5 FAIL: Triangle did nothing). Built: AC comes to the front by itself (KB-357), no pre-race screen and the drop after the session is live (KB-356), the Machine's own Triangle/RP-16 in AC with heat + propellant (KB-355), real-scale Hella + locator + zoom in Deep, the ascent overlay from 4 km becoming Deep with no white-out, every journey recorded (schema 067). Burn/coast guidance measured worse and reverted (IDEA-1149).**
- **THE ONE NEXT ACTION (owner):** one run, hands off Windows: climb from Night City (watch 4-12 km: Â§AC13), Deep (zoom: Â§AC12), Guidance -> Laguna Seca, A (Â§AC9 focus, Â§AC10 no Drive screen), land, Triangle hop + hold (Â§AC11), back to Deep (Â§AC14 journey line). Say at what altitude REDengine first looks wrong.

**EARLIER 2026-10-06 (13:25 ET) - FIRST FALL FROM THE SKY INTO ASSETTO CORSA (13:19-13:20): straight into Laguna Seca (KB-353 verified), physics allowed, car placed 3,131 m up, 14 NPCs placed -- then the AC app took the arrival height for a climb-out and closed AC (KB-354, fixed in the app; live on the next embodiment). Deep resumed above Laguna Seca as designed.**
- **13:35:** owner asked to skip AC's pre-race screen: the NCM app now presses it (`ac.tryToStart(true)` while `isInMainMenu`, NCM arrivals only; probe `autoStart`). Live next embodiment, unverified.
- **THE ONE NEXT ACTION (owner):** Deep -> Laguna Seca -> A at the prompt: no Drive screen, fall, land, race; climb past 2,500 m to go back to Deep (Â§AC2-Â§AC8).

**EARLIER 2026-10-06 (13:10 ET) - AC LAUNCHES FROM NCM (KB-352 verified 13:03: bridge -> 200, race.ini for Laguna Seca). It opened the AC launcher instead of the session: KB-353, `steam_appid.txt` now beside acs.exe; bridge restarted.**
- **THE ONE NEXT ACTION (owner):** quit AC, then Deep -> Laguna Seca -> A at the prompt: AC should load straight into Laguna Seca with the car in the air (Â§AC1-Â§AC3).

**EARLIER 2026-10-06 (08:07 ET) - KB-352: the race world built (Laguna Seca GT, 14 NPCs, Quattroporte body) but the call to the AC bridge never left the server: `ncm_world` lacked `http.request`. Fixed; dev restarted 08:07 (`l347-restart-20261006.stdout.log`).**
- **THE ONE NEXT ACTION (owner):** climb out, D-pad up, Laguna Seca, A, A at the prompt (Â§AC1).

**EARLIER 2026-10-06 (07:51 ET) - GUIDANCE WORKS: the Hella flew itself to Laguna Seca (07:41 -> 07:45) on the dev heat waiver. AC then failed to open: the server's embody request died on the instruction quota (KB-351, 744 NPC drivers decoded + sorted in one slice); fixed. Also live: freefall rescue (IDEA-1144: falling on foot puts you in your own car) and the dev respawn (KB-350). Dev restarted 07:51 (`l346-restart-20261006.stdout.log`).**
- **THE ONE NEXT ACTION (owner):** climb out, D-pad up, Laguna Seca, A, ride it in, A at the prompt -- Assetto Corsa should open (Â§AC1-Â§AC8).

**EARLIER 2026-10-06 (07:33 ET) - KB-350: DEATH ON DEV WAS PERMANENT (no freeroam = no respawn) and a mid-air saved position killed the owner on each join. The bad save is deleted (owner-approved); `ncm_world/server/life.lua` now respawns a dead player after 3 s at the nearest safe ground point. Dev restarted 07:33 hidden with a log again (`l345-restart-20261006.stdout.log`; no console). Dev heat waiver live (IDEA-1143).**
- **THE ONE NEXT ACTION (owner):** rejoin dev; if dead, you come back within ~8 s. Then Deep -> D-pad up -> Laguna Seca (Â§AC1).
- **Coder next:** KB-350 (1) the saver's airborne test; IDEA-1144 freefall -> back in your car (owner).

**EARLIER 2026-10-06 (07:16 ET) - DEV HEAT WAIVER (owner ruling, IDEA-1143): on the development server installed parts never overheat, like dev fuel; guidance now accepts the one-RP-16 Hella. Convar `ncm_dev_heat 0` turns it off for a heat test; Online untouched. Dev restarted 07:16 in a VISIBLE console window (no stdout log file this run; `ncm.heal 1` works there). Core 1103 green. Open: the owner's saved location is mid-air (2563.8, 107.1, 249.9 saved 06:33:47 in the Hella) and kills them on join; the auto-mode classifier blocked deleting the row -- owner clears it (KB-350 to file: the saver let a slow climb through as grounded).**
- **THE ONE NEXT ACTION (owner):** rejoin dev, climb into Deep, D-pad up, Laguna Seca, A, ride it in, A at the prompt (Â§AC1-Â§AC8).

**EARLIER 2026-10-06 (06:57 ET) - KB-349 FIXED: Guidance flew the Hella into the Earth (06:37 Spa, 06:42 Silverstone). It now flies altitude first, respects RP-16 heat, never goes below 2.5 km over a venue, holds over the venue at the AC prompt, and nothing in Deep can go underground. BUT it now REFUSES the current Hella: one RP-16 can hold 10 kN without overheating against 19 kN of weight. Dev restarted 06:57 (`l343-restart-20261006.stdout.log`). Core 1103 green.**
- **THE ONE NEXT ACTION (owner):** pick how the Hella gets a flyable build (IDEA-1143: more RP-16s, a dev-only heat waiver, or an RP-16 heat balance change); then Â§AC1 again.

**EARLIER 2026-10-06 (06:30 ET) - Â§AC0 PASS (AC first run). AC set to the Xbox pad (was keyboard). Bridge gives every car a real skin. Dev restarted 06:29 with Guidance live (`l342-restart-20261006.stdout.log`); the bridge starts with it.**
- **THE ONE NEXT ACTION (owner):** climb out of Night City, D-pad up in Deep, pick a venue (Laguna Seca is the short one), A, ride it in, A at the prompt (Â§AC1-Â§AC8).

**EARLIER 2026-10-06 (06:15 ET) - L327 BUILT, NOT YET RUN: Deep Guidance (pad) -> 17 Assetto Corsa venues on NCM Earth -> NCM NPC races on the one clock -> the same Machine embodied in AC (in the air, parts as forces) -> back to Deep. CSP 0.2.11 + Content Manager installed (owner downloads). Host bridge running on 127.0.0.1:47710. Core 1099 green. BLOCKED on: AC's first run on this PC, and a dev restart (owner connected).**
- **THE ONE NEXT ACTION (owner):** start Content Manager once (`tools/assetto/ContentManager/Content Manager.exe`), point it at AC, run a quick Monza practice, quit (Â§AC0); then tell the coder to restart dev.

**EARLIER 2026-10-06 (04:15 ET) - Â§DP2 PASS: the owner flew the Hella out of Night City the real way (hop + forward, through 12 km by itself) and on to 15,000 km, escaping Earth at ~9,900 m/s. Deep v0.1 has only Earth -- nothing else is out there yet. The way home is still a command (`/ncm.deep.home`) or a long retro-burn.**
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
- **THE ONE NEXT ACTION (owner):** relaunch Cyberpunk (pad detection), join dev, `/ncm.eng.devfuel`, then `/ncm.deep.go` (Â§DP1).

**EARLIER 2026-10-06 (02:45 ET) - L326 NCM DEEP v0.1 LIVE ON DEV: climb past game z 12 km (or `/ncm.deep.go`) and the Machine leaves REDengine for NCM's real-scale Earth, drawn in-game (WebGL, NASA Blue Marble, Night City at 35.37 N 120.85 W), flown with its own installed components and tank; fall back through 11.5 km and it returns. Dev restarted 02:44 (`l335-restart-20261006.stdout.log`). No live PASS.**
- **THE ONE NEXT ACTION (owner):** build your Machine (L324: fabricate, install, bind), then fly it through Deep: MASTER_TEST Â§DP1-Â§DP5 (and Â§EN1-Â§EN12).

**EARLIER 2026-10-06 (02:40 ET) - Â§DP0 PASS: NCM's universe can be drawn INSIDE Cyberpunk. WebGL in an OPEN//77 WebUI surface runs on the RTX 5060 Ti (ANGLE/D3D11, WebGL2 available) at 60 fps, 1920x1080; owner saw the planet "full scale and quickly". KB-346 verified (the owner joined). Sprite shader fix (`half` is reserved) waits for the next dev restart.**
- **THE ONE NEXT ACTION (owner):** the L324 engineering run (Â§EN1-Â§EN12) whenever ready; it has never had a live session.
- **Coder next (L326 P1):** real Earth imagery + atmosphere in the surface; the Hella sprite; then the handoff at an NCM-chosen altitude.

**EARLIER 2026-10-06 (02:25 ET) - L326: NO SECOND PROGRAM. NCM simulates its own universe just out of REDengine's reach, inside the game; you get there by hitting the vertical bounds + a loading screen. OpenSpace is now a source of understanding/MIT code, not a runtime. PROBE 0 LIVE ON DEV (`prototypes/ncm_deep`, dev-only entry): `/ncm.deep` asks whether WebGL runs in an in-game WebUI surface. Dev restarted 02:24 (nobody on; `l333-restart-20261006.stdout.log`).**
- **KB-346 (02:31):** L324's client script refused every dev join (a handler-less RegisterNetEvent); fixed, gate now checks it, dev restarted. Owner correction: the Hella has reached 60+ km (until out of fuel) -- 33.6 km was one crash, not a ceiling.
- **THE ONE NEXT ACTION (owner):** in Night City (dev) type `/ncm.deep` and watch for 20 s (MASTER_TEST Â§DP0). Then the L324 engineering run.

**EARLIER 2026-10-06 (02:00 ET) - L325: NCM IS A CYBERPUNK MOD; THE SPACE BEYOND NIGHT CITY GOES TO AN OPENSPACE-SCALE UNIVERSE WITH NCM OWNING PHYSICS (owner direction). P0 RUN: OpenSpace 0.22.0 runs here (`tools/openspace/`, 60 fps); an NCM-owned node over Night City's place on Earth took 60 Hz updates from `prototypes/ncm_openspace/probe.py` (MASTER_TEST Â§OS0). OpenSpace is left open on the desktop.**
- **Ruled since:** Night City at 35.37 N, 120.85 W; Machines are Cyberpunk vehicle sprites (104 extracted from the game's own icon atlas, 34/45 roster matched). The sprite billboard loads in OpenSpace but is not yet framed on screen (low-altitude camera = P1).
- **THE ONE NEXT ACTION (owner):** the L324 engineering run (Â§EN1-Â§EN12). Coder: P1 (chase camera + the NCM space runtime flying the Hella sprite).
- **Coder next:** P1, the NCM space runtime (LuaJIT + ncm core) flying a stand-in Machine around OpenSpace's Earth on the pad.

**EARLIER 2026-10-06 (01:25 ET) - L324 BUILT AND LIVE ON DEV: THE FIRST ENGINEERING LOOP. Reaction Propulsor RP-16 + Impulse Actuator IA-10 as serialised component assets; four hardpoints with facings and ratings; install/remove as configuration revisions (schema 065, applied 01:20); controls bind to component commands (tap/hold on one button); the client maps thrust through the car's live axes to a world force; Carrier 0.1.37 applies it at the bound body (installed `dev-mods/20261006-012025`). Fuel from the Machine's own tank. Core 1076 green. Dev restarted 01:20 (nobody on; `l332-restart-20261006.stdout.log`). No live PASS.**
- **THE ONE NEXT ACTION (owner):** MASTER_TEST Â§EN1-Â§EN12 in Night City dev: `/ncm.eng.fabricate rp16`, `/ncm.eng.fabricate ia10`, park + get out, `/ncm.eng.install <ia10> underside down`, `/ncm.eng.install <rp16> rear aft`, `/ncm.eng.bind triangle tap <ia10> discharge`, `/ncm.eng.bind triangle hold <rp16> throttle`, drive.
- **Open:** IDEA-1124 torque channel, IDEA-1125 acquisition route, IDEA-1127 odometer fuel while flying; IDEA-1128 OpenSpace restated as "rendering substrate for an NCM-owned Snowglobe runtime" (after the L324 run); IDEA-1129 presentation vs simulation geometry (decide by playing).

**EARLIER 2026-10-05 (21:45 ET) - PC REBOOT RECOVERY: DEV (`l330-restart-20261005.stdout.log`; `ncm_link` hub REACHABLE, HTTP 200) AND FXSERVER (`fxserver-20261005-214255.log`; license OK, `ncm_ls_space` up, 1 linked driver kept) RESTARTED BY HAND -- NOTHING AUTO-STARTS AFTER A REBOOT. LIGHTSAIL UNTOUCHED (up 15 days, player connected). Â§LK1 already PASS (21:10).**
- **KB-345 (21:57):** the manual drove like an automatic because Carrier was back on 0.1.30 (a full dev hand-install at 20:53 replaced the 0.1.36 spike). 0.1.36 reinstalled. Every other NCM mod already matches its newest build (gearbox 0.3.1, snowglobe 0.0.5, thrust 0.0.2, pace 0.9.2, vision 0.4.0, rig-bridge 0.1.7, broadcast/clock 0.1.0). Check the Carrier log for `NCM Gearbox levers found`.
- **22:10:** KB-345 verified at 22:05 (Carrier 0.1.36 log: `NCM Gearbox levers found`). `ncm_space`: `/ncm.sky` from more than 600 m away now sets a routable GPS pin on the grid instead of opening it (dev restarted, nobody on; `l331-restart-20261005.stdout.log`). The orbiter ran out of propellant on the EVA attempt: Â§EVA2 now says `ncm.machine instrument` first.
- **THE ONE NEXT ACTION (owner):** Â§NCS1 `/ncm.sky` anywhere on dev, follow the pin, `/ncm.sky` again; then Â§EVA2 in LS with `ncm.machine instrument`; then Â§SP1 / Â§FB1.

**EARLIER 2026-10-05 (20:30 ET) - L323: THE SIX SNOWGLOBE HOST BOUNDARIES CLEARED OR NARROWED. THE CROSS-SERVER LINK IS LIVE ON DEV: NIGHT CITY (`ncm_link`) REACHED THE LOS SANTOS SNOWGLOBE HUB AT 20:25 (HTTP 200, FACTS BOTH WAYS). NEW: PLAYER-NPC CONTACT AS PHYSICS, MULTIPLAYER SNOWGLOBE RACES (UNIVERSE-STATE PRESENTATION -- NETWORKED CARS CANNOT SERVE PER-CLIENT FLOATING ORIGINS), CLOCK-SYNCED PHOTO FINISH, LIFE SUPPORT + EVA + BOARDING BY THE RELAY RULE, THREE CITIES SCORING, AND THE BADLANDS SKY SPRINT IN CYBERPUNK (`ncm_space`). DEV RESTARTED TWICE (NOBODY ON; `l329-restart-20261005.stdout.log`). `ncm_ls_space` 0.5.0 LIVE. Dev `server.jsonc` http enabled for 127.0.0.1.**
- **THE ONE NEXT ACTION (owner):** link yourself: `/ncm.link` in Night City (dev), then F8 `ncm.link CODE` in Los Santos (Â§LK1). Then `/ncm.sky` at the Badlands in Cyberpunk (Â§NCS1), and `ncm.eva.drill` in Snowglobe (Â§EVA2).
- **Open for the owner:** L323 Q1 link topology beyond one PC; L322 Q1 relay baton (passenger now works), Q2 Fireball credit; L321 Q1 competency families; L320 Q1 compressed geography.

**EARLIER 2026-10-05 (19:55 ET) - L322 BUILT: SNOWGLOBE SPRINT (PLANES, LANES, FIVE LIGHTS, HERMITE PHOTO FINISH, UNIVERSE TIMING) AND FIREBALL (VALID DISTANCE = ANGLE ABOUT A TURN-RATE-LIMITED AXIS; ANY PLANE; THE SHELL); RELAY EXCHANGE RULE (BATON OPEN); TRIATHLON SCHEMA + SCORING + DISCOVERY GATE; NPC DRIVERS: ONE IDENTITY, PERSONALITY TRANSFERS, COMPETENCY PER DOMAIN, 3D RACECRAFT BOUNDED BY THE MACHINE; ONE RACE AT THREE FIDELITIES (ABSTRACT / TACTICAL / PHYSICAL); UNSEEN SNOWGLOBE HISTORY COMMITTED AS SEED MODS. `ncm_ls_space` 0.4.0 LIVE (rcon). IT IS NPC, NOT MPC (owner).**
- **THE ONE NEXT ACTION (owner):** FiveM: `/ncm.car`, F8 `ncm.machine sprint_dragster`, `ncm.race 5`, stop on the yellow lane marker at LSIA, five lights, hold TRIANGLE (Â§SP1). Then `ncm.machine fireball_racer`, `ncm.race 6` (Â§FB1).
- **Open for the owner:** L322 Q1 relay baton, Q2 Fireball credit (angle vs arc), Q3 point-to-point (open by design); L321 Q1 competency families; L320 Q1 compressed-Earth geography (bit twice now).

**EARLIER 2026-10-05 (19:10 ET) - L321 ENGINEERING II BUILT: MACHINES FROM PHYSICAL SYSTEMS (MASS, CoM, A 6-AXIS WRENCH FROM MOUNT POINTS, PROPELLANT, ENERGY, HEAT, FIRST FAILURE); THE HOP IS NOT A THRUSTER (GROUND / STORED / AIR / REACTION AS PHYSICAL PRECONDITIONS); LINEAGE + REVERSE ENGINEERING ACROSS WORLDS; THE SEED TREE + WORLD COMPOSITION; SNOWGLOBE MOTORSPORT (3D GATES, SEEDED STATIONS AND SKY RINGS, NPC RACES THROUGH PADDOCK.SIM WITH PROVENANCE, SPORT FROM THE CAPABILITY DISTRIBUTION); HOST EXPRESSION LOSSES. DOC 54. CORE ALL GREEN; `ncm_ls_space` 0.3.0 LIVE (rcon refresh + restart; nobody connected). KB-343 (pairs order broke cross-process seeds) FOUND LIVE AND FIXED.**
- **THE ONE NEXT ACTION (owner):** in FiveM, `/ncm.car` then hold TRIANGLE on the orbiter (Â§EG1); then `ncm.machine fan_car`, `ncm.race 3` and fly the Vinewood Sky Ring (Â§SR2).
- **Open for the owner:** L321 Q1 (engineer competency for propulsion / energy_storage / avionics, non-blocking); L320 Q1 (anchors ~370 m apart on a 5 km Earth); economy purses (proposal unbuilt).

**EARLIER 2026-10-05 (17:50 ET) - LOS SANTOS FLIGHT 1 (Â§LS1-Â§LS5): DOORWAY MOVE KEPT DRIVER + OWNERSHIP + VELOCITY; EARTH AND MOON SEEN; GTA's 150 m/s CAP CONFIRMED. L320 RULED: GRAVITY AS A CONCEPT -- COMPRESSED SNOWGLOBE EARTH (5 km, 1 g), RADIAL INVERSE-SQUARE, NCM UNIVERSE VELOCITY SEPARATE FROM GTA's, THE FRAME FOLLOWS THE PLAYER. BUILT AND LIVE (ncm_ls_space 0.2.0 via rcon). TRIANGLE-EXIT BUG FIXED. OPEN: NC and LS anchors are ~370 m apart on a 5 km Earth (L320 Q1).**
- **THE ONE NEXT ACTION (owner):** Â§LS7 (climb, coast, fall back) and Â§LS8 (orbit: pitch toward the horizon until sideways = orbit speed).

**EARLIER 2026-10-05 (17:30 ET) - L319: NCM LOS SANTOS STARTS WITH SPACE. BUILT AND SET UP ON THIS PC: FXServer 35245 + `ncm_ls_space` (NCM core unchanged in FiveM; lift from the F0 rig, torque attitude, server doorway/floating origin, universe altitude, inverse-square gravity, Earth/Moon/Sun stand-ins). Doc 53. NOT YET RUN.**
- **FXServer RUNNING on this PC since 17:10** (license authenticated; `ncm_ls_space` started, space.universe 0.2.0 loaded; log `tools/fivem/server-data/logs/fxserver-20261005-171012.log`).
- **THE ONE NEXT ACTION (owner):** FiveM client, F8 `connect localhost:30120`, F8 `ncm.car`, hold TRIANGLE (Â§LS1-Â§LS6).

**EARLIER 2026-10-05 (16:30 ET) - LOS SANTOS RECON 01 (research only): GRAND THEFT SPACE READ FROM SOURCE -- [docs/research/los_santos/GTS_RECON_01.md](../research/los_santos/GTS_RECON_01.md). GTS = fade + teleport to z 30 km + a camera-following sky dome + a floating origin within 2.5 km (velocity kept) + planets swapped as scenes; it depends on closed ASIs (gravity, bounds) that FiveM cannot run. Nothing in it is licensed for reuse. Five probes listed for when GTA Legacy is installed.**
- **THE ONE NEXT ACTION is unchanged:** the Snowglobe discriminating runs (L317 addendum 8). Los Santos probes wait on the owner.

**EARLIER 2026-10-05 (15:50 ET) - L318 ADDENDUM CAPTURED (DIRECTION ONLY): ONE ONLINE RACE WEEK ACROSS TWO CITIES (SHARED CLOCK, LOCAL CONSEQUENCES, A SHARED RESOLVER); SP AND ONLINE SHARE RULES, NOT TOPOLOGY; THE WORMHOLE IS 'WHAT ELSE COULD THERE BE?' IN SP AND 'WHAT DO YOU WANT?' ONLINE. Doc 52 Â§5; IDEA-1066 to IDEA-1077. Audit: Race Week identity is per server, and local consequences share state with the verdict -- door-keeping rules 6-10.**
- **THE ONE NEXT ACTION is unchanged:** the Snowglobe discriminating runs (L317 addendum 8).

**EARLIER 2026-10-05 (15:30 ET) - L318 CAPTURED (DIRECTION ONLY, NOTHING AUTHORISED): NCM / LOS SANTOS ON FIVEM AS A POSSIBLE SECOND RACING SERVER, WITH SNOWGLOBE AS THE SHARED PROTOCOL (NO THIRD SERVER). DOC 52 RECORDS THE DIRECTION, THE INTERFACES TO PRESERVE AND AN AUDIT: IDENTITIES ARE ALREADY ENGINE-INDEPENDENT; FOUR NARROWINGS NOTED, NONE URGENT. IDEA-1054 to IDEA-1065.**
- **THE ONE NEXT ACTION is unchanged:** the Snowglobe discriminating runs (L317 addendum 8).

**EARLIER 2026-10-05 (15:10 ET) - Â§SG8: SNOWGLOBE 0 WORKS -- THE HELLA REACHED 33,643 m UNIVERSE ALTITUDE (PAST THE 16,384 m CEILING; TWO REBASES), THEN A CLIENT CTD AT 14:56:57 (KB-341, null read in game code `+0x1FA56B`). 2^15 TESTED AND NOT SUPPORTED: 32,768 m was crossed 20 s / 900 m before the crash, and no REDengine-visible number was near it. NEW: vertical speed caps at 99.70 m/s and resets (KB-342).**
- **THE ONE NEXT ACTION:** the discriminating runs (L317 addendum 8): a climb kept under 99 m/s, a long hover at about 13.6 km with no offset, and a repeat of Â§SG8.

**EARLIER 2026-10-05 (14:36 ET) - SNOWGLOBE 0 IS LIVE ON DEV, AUTOMATIC, NO COMMANDS: CLIMB THROUGH 14 km AND THE SERVER REBASES YOU (FLOATING ORIGIN); THE ALTIMETER SHOWS UNIVERSE ALTITUDE PAST 16,384 m; FALL HOME BELOW 3 km. SPEED NOT CARRIED BY OWNER RULING (L317 addendum 7). KB-340: THE TOP-SPEED LOSS IS THE GEARBOX BAND, NOT CARRIER.**
- **THE ONE NEXT ACTION:** Â§SG8. Mash TRIANGLE straight up past 14 km, keep climbing, then fall home.

**EARLIER 2026-10-05 (14:15 ET) - THE DOORWAY IS AN ALTITUDE: `ncm.seamauto <pid> 3000 -2000` (ARM ON THE GROUND; CROSSING 3 km WHILE CLIMBING TRIGGERS THE SERVER MOVE + THE CARRIER RESTORE; RE-ARMS 200 m BELOW). SNOWGLOBE 0.0.4 ADDS AN ALTIMETER. DEV RESTARTED 14:08 (`l326-restart-20261005.stdout.log`, nobody on); 0.0.4 INSTALLED.**
- **THE ONE NEXT ACTION:** Â§SG7. Arm once on the ground, then mash TRIANGLE straight up; no typing in flight.

**EARLIER 2026-10-05 (02:00 ET) - Â§SG5: THE SEAM RESTORE PIPELINE RUNS END TO END, BUT CARRIER REFUSED THE KICK -- THE SERVER MOVE UNBINDS THE CAR UNTIL THE LEASE RETURNS (~4 s). v2 INSTALLED: CARRIER 0.1.36 HOLDS A TARGET VELOCITY UP TO 8 s AND APPLIES IT THE MOMENT THE CAR IS BOUND AGAIN (SNOWGLOBE 0.0.3).**
- **THE ONE NEXT ACTION:** Â§SG6. Climb hard above about 2,500 m (mash TRIANGLE), then in Warden `ncm.seam <pid> -2000`.

**EARLIER 2026-10-05 (01:41 ET) - THE OWNER RACED ON DEV: P3 OF 12, 6:11.494 (5:42.494 + 29.0 s incidents), ALL 77 GATES. SEAM-1c (THE VELOCITY KICK) BUILT AND INSTALLED: SNOWGLOBE 0.0.2 + CARRIER 0.1.35 (record `dev-mods/20261005-014114`).**
- **THE ONE NEXT ACTION:** Â§SG5. Climb above about 2,500 m, then in Warden `ncm.seam <pid> -2000`. Expect a jump, a freeze, then a kick; the RESULT line says how much speed was kept.

**EARLIER 2026-10-05 (01:25 ET) - SEAM-1b ANSWERED (Â§SG4): THE SERVER'S `setTransform` MOVE HOLDS AND KEEPS THE DRIVER; IT ERASES VELOCITY (83.6 -> 0 m/s) AND FREEZES THE CAR ABOUT 3 s (lease churn incl. `validationfailed`). NEXT: VELOCITY RESTORE ON LEASE RETURN, THEN THE FREEZE. The owner is racing on dev: NO restarts.**

**EARLIER 2026-10-05 (01:05 ET) - SEAM-1 ANSWERED: THE GAME'S TELEPORT MOVES THE OCCUPIED CAR AND KEEPS THE DRIVER, BUT OPEN//77's SERVER REVOKES IT IN THE SAME MILLISECOND (`motion_jump`) AND IT SNAPS BACK WITH NO SPEED (Â§SG2, L317 addendum 2). THE SEAM'S MOVE BELONGS TO THE SERVER: `ncm.seam <pid> <dz>` (`vehicles.setTransform`) LIVE: DEV RESTARTED 01:11 WITH THE OWNER'S CONSENT (log `l325-restart-20261005.stdout.log`; 9 NCM resources, 0 errors, 34 open races).**
- **THE ONE NEXT ACTION:** the owner rejoins, climbs above about 2,500 m, and runs `ncm.seam <pid> -2000` in Warden (Â§SG4).

**EARLIER 2026-10-05 (01:00 ET) - KB-339: THE OWNER JOINED 650 m UP (A SAVED MID-FLIGHT LOCATION) AND FELL TO 1 hp, TWICE. FIXED (`world.location.airborne`, 8 m/s vertical) + `ncm.heal <pid>`; LIVE: DEV RESTARTED 00:52 WITH THE OWNER'S CONSENT (log `tools/open77/server/l324-restart-20261005.stdout.log`; all 9 NCM resources started, 0 errors; Paddock 34 open races). SEAM-1 has not fired yet (no J above 3,000 m).**
- **THE ONE NEXT ACTION:** the owner rejoins; in Warden `ncm.heal <pid>` (its log line names the life phase and health ledger, which is KB-339's open half); then Â§SG2.

**EARLIER 2026-10-05 (00:40 ET) - L317 Q1 RULED (THE SEAM BEFORE F2-F3). BUILT, NOT INSTALLED: NCM SNOWGLOBE 0.0.1 (SEAM-1: KEY J MOVES THE OCCUPIED CAR 2 km DOWN MID-AIR WITH THE GAME'S TELEPORT AND MEASURES VELOCITY + SEAT) AND `space.universe` 0.1.0 (6 TESTS, VENDORED).**
- `dist/ncm-snowglobe-0.0.1.zip`: the redscript compiles against vanilla plus every installed script; the natives check passes; 0 warnings. Gate ALL GREEN.
- **INSTALLED 00:40** (record `%LOCALAPPDATA%/NCM/dev-mods/20261005-004015`).
- **THE ONE NEXT ACTION:** launch (Â§SG1). Then climb above 3,000 m with TRIANGLE and press J while rising (Â§SG2), and again while falling (Â§SG3).

**EARLIER 2026-10-05 - L317 CAPTURED (SPEC): THE CEILING IS A DOORWAY. ABOVE A TRANSITION ALTITUDE NCM OWNS POSITION AND REDENGINE SIMULATES A LOCAL BUBBLE (FLOATING ORIGIN); THE SEAM FIRST; MOON THEN SUN (IDEA-1048 to IDEA-1053). NOTHING BUILT.**
- Coder constraints recorded in L317: Night City cannot be shifted, so the city leaves view before any rebase. Moving an occupied car while keeping its velocity is unproven (SEAM-1).
- **THE ONE NEXT ACTION:** the owner rules L317 Q1 (seam before F2-F3?). Then SEAM-1.

**EARLIER 2026-10-04 (23:55 ET) - S0's FIRST ANSWER: THE OWNER FLEW THE HELLA TO NIGHT CITY'S CEILING, z = 16,384 m (2^14), BY MASHING TRIANGLE (2,377 burns, 92 m/s climb, 0 faults). AT THE CEILING THE PLATFORM REVOKES THE CAR'S AUTHORITY EVERY ~2.3 s AND THE SESSION DROPS TO THE MENU (KB-338). L316 addendum 3; MASTER_TEST Â§AX4.**
- **THE ONE NEXT ACTION:** settle whether 2^14 is the engine's or Open77's: the same climb in single player (vanilla + NCM Thrust/Carrier where they load), and the server's `serverrevoke` cause. Â§FL4 (hop while driving) and Â§FL5 (TRIANGLE) also stand; TRIANGLE effectively passed in Â§AX4 (`requested (pad)`).

**EARLIER 2026-10-04 (23:20 ET) - Â§FL3 PASS: THE SPRINGS ALONE LIFT THE HELLA 0.12 m (r = 1.0); r = 3.0 RUNS A STEADY x1.25 OVER FREE-BODY. TRIANGLE IS THE VERTICAL ACTION (IDEA-1047): NCM THRUST 0.0.2 BUILT, NOT INSTALLED.**
- **INSTALLED 23:24** (record `%LOCALAPPDATA%/NCM/dev-mods/20261004-232434`): `ncm-thrust-0.0.2` (pad TRIANGLE / XInput Y + H; the owner's 3.0 / 200 ms) and `ncm-carrier-0.1.34` (KB-337).
- **THE ONE NEXT ACTION:** launch and drive: Â§FL5 (TRIANGLE) and Â§FL4 (hop while driving). F1 must add the suspension term to `actuate.hopPrediction` before any player-facing number.

**EARLIER 2026-10-04 (23:05 ET) - THE HELLA HOPS: F0 PASSES (Â§FL1-Â§FL2, owner "hop confirmed"). 9 burns measured, 0 faults; rise from rest is about 1.9x the free-body prediction because of the suspension (L316 addendum 2). KB-337 (lost burn log lines) is fixed in Carrier 0.1.34, built, not installed.**
- **THE ONE NEXT ACTION:** Â§FL3. In the running game, edit `red4ext/plugins/ncm_thrust/ncm_thrust_config.json` to `"twr": 1.0` and press H once (that measures the suspension's share), then `"twr": 3.0`. Then Â§FL4 (hop while driving). Install Carrier 0.1.34 at the next game quit. The gearbox Â§GB22 is still owed.

**EARLIER 2026-10-04 (late) - L316 RULED (Q1 dev-only experiments, Q3 wormhole != rollover, Q4 you keep the car you are in; Q2 left to S0) AND THE LADDER REORDERED: F0, THE HOP, IS BUILT (NCM THRUST 0.0.1 + CARRIER 0.1.33 LIFT LEVER); S0 INSTRUMENTS BUILT. NOT INSTALLED; NO LIVE PASS. DOC 51 IS THE SPEC.**
- Packed: `dist/ncm-thrust-0.0.1.zip` and `dist/ncm-carrier-0.1.33.zip` (= 0.1.32 + the lift lever; the gearbox path is untouched).
- **INSTALLED on this PC 23:02** (record `%LOCALAPPDATA%/NCM/dev-mods/20261004-230238`; `--uninstall` restores Carrier 0.1.32). RED4ext ignores none of them.
- Not yet on dev: the S0 instruments (`/ncm.altlog`, `ncm.lift`) load at the next dev restart.
- Gate ALL GREEN.
- **THE ONE NEXT ACTION:** the gearbox Â§GB22 is unchanged. At the owner's next game quit, install both zips (Â§FL1) and press H in the Hella (Â§FL2: predicted apex 0.20 m). Then Â§FL3-Â§FL4. Then S0 (Â§AX1-Â§AX5) after a dev restart.

**EARLIER 2026-10-04 (late) - L316 CAPTURED: NCM SNOWGLOBE, THE STARRY SKY, THE SERVER-WIDE DEV WORMHOLE (WHOLE SERVER FOLLOWS), PHYSICS-BASED FLIGHT (IDEA-1034 to IDEA-1042, SPEC). NOTHING BUILT.**
- It conflicts with L314 ("flight ... not to be implemented"). Q1-Q4 are open in DECISION_RECORD L316. Carrier's proven force write (`physics_probe.cpp`) makes the hop experiment (F0) small.
- (Ruled in the addendum above.)

**EARLIER 2026-10-04 (22:09 ET) - GEARBOX 0.3.1 INSTALLED (the band's rpm window, live-tunable); L315 CAPTURED: THE SKIPPING TAPE ON A SLIDING SCALE, ESCALATING SENSITIVITY, THE ERA SLIDER, FLIGHT INTO SPACE AND A NEW SEED (IDEA-1025 to IDEA-1033, SPEC).**
- **L315 Q1-Q4 RULED (addendum):** continuous early ending (time scale and survival are separate axes; changes L310's built rule); sensitivity continuous in normalized age; one week core with per-server clocks; flight discovered through engineering. Amendment: the anomaly is seeded geography (IDEA-1031). Nothing authorized to build.
- **THE ONE NEXT ACTION (gearbox):** the owner drives Â§GB22 and tunes `manual.band`.

**EARLIER 2026-10-04 (21:31 ET) - GEARBOX 0.3.0 INSTALLED: `band`, THE GAME VOICES OUR GEARS (one writer, no tape-skip, if the gear re-reads live).**
- **THE ONE NEXT ACTION (gearbox):** the owner drives Â§GB21. The owner has another idea pending this result.

**EARLIER 2026-10-04 (21:10 ET) - NO PADDOCK RACES SINCE THE 19:00 BOOT (KB-336): THE BOOT THREAD DIED ON THE QUOTA; FIXED AND LIVE (dev restarted 21:10, log `l323-restart-20261004.stdout.log`). GEARBOX 0.2.9 INSTALLED (HUD SHOWS THE LIVE CURVE / CONFIG ERROR).**
- KB-336: `ncm_paddock` hit `instruction quota exceeded` 8 s after boot and never ran. Boot steps now yield; races.load yields every 20 races. Gate ALL GREEN. Nobody on dev at 21:04.
- Gearbox: the curve was never actually heard -- every successful reload after 20:47 had `follow 1.00` (the curve switched off), then the file stopped parsing (`gamma: 01111111`). 0.2.9 puts the live values, a FOLLOW 100% warning and CONFIG ERROR on the HUD.
- **THE ONE NEXT ACTION:** the owner tunes Â§GB20 with `follow` below 0.5 (races are running again).

**EARLIER 2026-10-04 (20:42 ET) - GEARBOX THREAD: 0.2.8 INSTALLED -- ONE CONTINUOUS ENGINE VOICE (`curve`), TUNED LIVE FROM THE CONFIG FILE WHILE DRIVING. (Engineering thread: the 19:30 entry below.)**
- The 0.2.7 blend was "the right idea" but "chopped" (Â§GB19). 0.2.8 slides one smoothed value from lo to hi across each gear, partly following the game's own rpm. Edit `manual.curve` in the installed config, save, and it reloads in-game.
- **THE ONE NEXT ACTION (gearbox):** the owner tunes Â§GB20 by ear and reports the best values; they become the defaults. Â§GB17 (top speed, neutral) is still unreported.

**EARLIER 2026-10-04 (20:31 ET) - GEARBOX THREAD: 0.2.7 INSTALLED ON THIS PC -- THE BLENDED ENGINE VOICE; THE GAME OWNS THE DASH AGAIN; ONE SOURCE OF TRUTH FOR SPEED RULED. (The engineering thread's latest is the 19:30 entry below.)**
- Owner rulings (L306 addendum 20:31): no mirrored gears; the four sound presets compose into one crescendo (`blend`, the default; `manual.blend` in the config); the dash's rpm, gear and speed are the game's; the dash speed is NCM's one source of truth (IDEA-1023; KB-334 for the Online gap). IDEA-1024 = the composable engine voice.
- KB-335: Warden's restart leaves dev down (exit 10, no supervisor).
- **THE ONE NEXT ACTION (gearbox):** the owner drives Â§GB19 (the blend). Then tune `manual.blend` from what they hear and the `trace:` lines. Top speed and neutral (Â§GB17) are still unreported.

**EARLIER 2026-10-04 (19:30 ET) - L314 RULED (R1-R5 + CAUSE/ACTUATOR/STATE/COARSE). ENGINEERING STEPS 2-5 BUILT OFFLINE: `ncm/core/engineering/` body, envelope, drivetrain, fit, actuate, fixtures; 15 tests; gate green; vendored. DOC 50 IS CURRENT.**
- Nothing reads the modules at runtime yet; no live behaviour changed. Fixture geometry is illustrative (IDEA-1022: survey the real cars).
- E1 is still unrun (Â§EN1). **Dev restarted 19:00 ET** (owner: "its free"), logging to `tools/open77/server/l322-restart-20261004.stdout.log` again. Every league subsystem booted, with one pre-existing `ncm_paddock` quota error (46 in the previous boot). `/ncm.mass` and `/ncm.massrun` are live on the next join.
- **THE ONE NEXT ACTION (engineering):** the owner runs Â§EN1 after a dev restart. Then step 6, the read-only Hella/Quadra puzzle surface, which wants real envelopes first (IDEA-1022). The Gearbox thread (Â§GB18) continues in its own session.

**EARLIER 2026-10-04 (18:40 ET) - ENGINEERING ARCHITECTURE PASS STARTED: E1 INSTRUMENT BUILT, DOC 50 PROPOSED (R1-R5 OPEN). THE GEARBOX THREAD (Â§GB18) CONTINUES IN ITS OWN SESSION.**
- E1 from the logs: live mass = the record's `total_mass` (Hella 1800 kg). Unknown: whether a changed record mass changes the driving.
- `/ncm.mass` and `/ncm.massrun` (ncm_world client) are in the tree and NOT yet on a client. Dev reads the tree through its junction, but its current run (17:53) logs to the console only, so connected players could not be checked and dev was not restarted.
- **THE ONE NEXT ACTION (engineering):** at the next dev restart, the owner runs Â§EN1. In parallel, the owner reads doc 50 and rules R1-R5. After that, `engineering.body` / `envelope` / `fit` as pure core with fixtures (doc 50 Â§10.2-Â§10.4).

**EARLIER 2026-10-04 (18:10 ET) - THE HELLA IS A 7-SPEED (refit applied by the owner; log `in a m7`); GEARBOX 0.2.6 INSTALLED: A LIVE ENGINE-SOUND EXPERIMENT.**
- The engine note still has no ramp on the m7 (KB-333). 0.2.6: PAGEUP cycles the sound scale (rpm / limiter / fraction / off), the HUD names it, and a `trace:` line a second logs the game's own blackboard rpm beside ours.
- Dev was restarted at 17:53 (minimized console window; its log is console-only). Warden's restart exits with code 10 and nothing relaunches dev (needs a KB).
- **THE ONE NEXT ACTION:** the owner drives Â§GB18, cycling PAGEUP. Then read the `trace:` lines and fix the scale from data. Top speed and neutral (Â§GB17) are still unreported.

**EARLIER 2026-10-04 (evening) - GEARBOX 0.2.5 + CARRIER 0.1.32 BUILT AND PACKAGED, NOT INSTALLED: THE HELLA'S 7-SPEED, MANUALS THAT REACH THEIR AUTOMATIC'S TOP, THE ENGINE NOTE IN RPM, NEUTRAL KEEPS ITS GRIP.**
- Owner QA of 0.2.4: shift feel ok, a solid 5-speed; engine mute (KB-333); rotation in N (KB-332); capped near 115 where the automatic did 140+ (KB-331).
- `dist/ncm-gearbox-0.2.5.zip`, `dist/ncm-carrier-0.1.32.zip`. Core `machine.gearbox` gained `m7` and `REFIT` (vendored). `ncm.gearbox find|refit` added to ncm_league.
- **THE ONE NEXT ACTION:** the owner quits the game. Then: hand-install both zips (`python tools/dev-hand-install-mods.py --only none --extra-zip dist/ncm-gearbox-0.2.5.zip --extra-zip dist/ncm-carrier-0.1.32.zip`), restart dev (check for players first), `ncm.gearbox find archer_hella`, `ncm.gearbox refit <assetId> m7`. Then the owner drives Â§GB17.

**EARLIER 2026-10-04 (evening) - CIVIL ENGINEERING C1-C4 RULED; THE NIGHT CITY SEED MAP AND EVIDENCE-WEIGHTED INFRASTRUCTURE AWARENESS CAPTURED (L313 addendum, doc 49 Â§8). NOTHING BUILT.**
- Civil engineering joins the Engineering Architecture pass. Anyone builds, and anyone dismantles (on site, per component), for modest money. Every contribution and its effect on races is recorded.
- End of each cycle: export a seed map (built infrastructure + danger heatmap incl. free-roam driving incidents + pins). At rollover the operator picks a seed, or a random draw between known seeds and a blank slate, announced in chat.
- The race sim believes infrastructure effects only in proportion to observed evidence. The wild west at the start. IDEA-1000 to IDEA-1008.
- **THE ONE NEXT ACTION is unchanged:** the owner drives the Hella (Â§GB16). Then shift feel. Then the Engineering Architecture pass (doc 48 Â§5), now with civil engineering as its second domain.

**EARLIER 2026-10-04 (evening) - CITY MEMORY Q1-Q4 RULED (L312 addendum) AND CIVIL ENGINEERING CAPTURED (L313), BOTH IN DOC 49. NOTHING BUILT.**
- Rulings: scar clusters (segment + 8-12 m configurable radius + context) with accumulated burden; v0 is physical incidents only; the scar ledger ends with the campaign and distils into knowledge; Campaign A/B by hand before any automation. Q5 (casualties, memorials) is open.
- Civil engineering: engineering pointed outward. A six-piece snapping kit judged by the race, one grammar with doc 48, attribution not saboteur roles, friction not caps. C1-C4 are open. IDEA-973 to IDEA-999.
- Correction: the incident position is lost one hop earlier than first written. `ncm/core/session/race.lua:328/331` (and `quali.lua:116`) drop x/y/z before `ncm_league/server/race.lua:833` sends a bare count.
- Prerequisite for any civil engineering: E19 (does a placed barrier stop a car?) has never run.
- **THE ONE NEXT ACTION is unchanged:** the owner drives the Hella (Â§GB16). Then shift feel. Then the Engineering Architecture pass (doc 48 Â§5).

**EARLIER 2026-10-04 (16:25 ET) - GEARBOX 0.2.4 INSTALLED ON THIS PC: OWN GEAR INDICATOR, ENGINE NOTE AS A 0..1 FRACTION, A REAL R-N-1..n SELECTOR; NOT YET DRIVEN.**
- **THE ONE NEXT ACTION:** the owner drives the Hella (Â§GB16). Then shift-feel tuning. Then the Engineering Architecture pass (doc 48 Â§5), starting with E1 (mass).

**EARLIER 2026-10-04 (15:53 ET) - GEARBOX 0.2.3 INSTALLED ON THIS PC: DASH WRAPPERS, PROGRESSIVE GEAR SPACING, THE CAR'S OWN SHIFT SOUNDS, ENGINE AUDIO FROM THE VIRTUAL REVS; NOT YET DRIVEN. L311 Q1-Q5 RULED.**
- **THE ONE NEXT ACTION:** the owner drives the Hella (Â§GB15). Then shift-feel tuning. Then the Engineering Architecture pass (doc 48 Â§5), starting with the mass measurement (E1).
- Dev runs the old core gearbox labels until its next restart. The DLL's spec file, which drives the car, is already new.

**EARLIER 2026-10-04 (15:45 ET) - THE MANUAL IS REAL (owner); GEARBOX 0.2.2 PUTS ITS GEAR AND REVS ON THE DASH; ENGINEERING ENVELOPE CAPTURED AS SPEC (L311, doc 48).**
- The owner drove the manual Hella. The log shows `in a m5`, Carrier `levers found`, and over-rev downshifts refused. But the dash showed nothing: the blackboard write lost to the game's own.
- 0.2.2 wraps every vanilla dash gear and rpm callback (10 wrappers, compiled) to draw the virtual gear and rpm. Installed. Not yet seen live.
- The m5 bands are cramped (35/47/63/85/115 km/h). Retune is owed.
- Audio (one long drone) and shift sounds are open (IDEA-972).
- **THE ONE NEXT ACTION:** the owner drives the Hella and says whether the dash shows N/1-5 and the revs (Â§GB14). Then the manual's audio and shift feel. Then the Engineering Architecture pass (doc 48 Â§5) on the owner's word.

**EARLIER 2026-10-04 (15:33 ET) - THE OWNER'S DEV HELLA IS A 5-SPEED MANUAL; CLONES ON BY DEFAULT IN DEVELOPMENT; PAD X/A SHIFTING (GEARBOX 0.2.1); NO LIVE PASS.**
- **THE ONE NEXT ACTION:** the owner calls the Hella and drives it (Â§GB14). No console commands.

**EARLIER 2026-10-04 (15:05 ET) - THE MANUAL IS BUILT (L306 addendum): ONE LONG NATIVE GEAR + VIRTUAL GEARS THROUGH CARRIER; GEARBOX 0.2.0 + CARRIER 0.1.31 INSTALLED ON THIS PC; DEV RESTARTED; NO LIVE PASS.**
- KB-330: my native gear writes crashed the game twice. That approach is retired, and writes are disabled.
- **THE ONE NEXT ACTION:** in Warden, `ncm.gearbox clones on` and `ncm.grant <pid> Vehicle.v_standard2_archer_hella_ncm_gbx_m5`; then call the car and drive it, with LShift up and LCtrl down (Â§GB14).

**EARLIER 2026-10-04 (14:47 ET) - GEARBOX: THE GEAR IS FOUND (ONE BYTE, `0x2D0:0x3A4`) AND HOLDING IT BEATS THE AUTOMATIC, WITH FLICKER (Â§GB12 PASS); 0.1.3 (PHYSICS-STEP HOLD, A/B TRIAL) INSTALLED; NOT RUN.**
- **THE ONE NEXT ACTION:** the owner drives in 2nd or higher, keeps the throttle down through the four 6 s holds, and sends the newest log (Â§GB13).

**EARLIER 2026-10-04 (14:36 ET) - GEARBOX 0.1.2 INSTALLED: THE SCAN CONVERGED ON 2 FIELDS (UNNAMED, A REPORT BUG); 0.1.2 NAMES THEM AND RUNS A 6 s HOLD TRIAL ON EACH.**
- **THE ONE NEXT ACTION:** the owner drives up through 1-4, then keeps accelerating in 2nd/3rd for about 20 s, and sends the newest `ncm_gearbox-<pid>.log` (Â§GB12).

**EARLIER 2026-10-04 (14:28 ET) - GEARBOX: S1 HALF ANSWERED, THE GEAR HAS NO NAME; 0.1.1 (FIND IT BY VALUE) INSTALLED ON THIS PC; NOT RUN.**
- The owner's drive (`ncm_gearbox-53060.log`): the DLL loads and all 44 clones build (Â§GB4 PASS). The census (Â§GB9 PASS) finds no gear field and no gear setter in RTTI.
- 0.1.1 correlates the car's raw memory, one pointer deep, against the HUD gear.
- **THE ONE NEXT ACTION:** the owner drives one car up through 1-4 and back twice, steps out, and sends the newest `ncm_gearbox-<pid>.log` (Â§GB11).

**EARLIER 2026-10-04 (14:21 ET) - NCM GEARBOX 0.1.0 (PHASE 3a: FIND THE GEAR) BUILT AND INSTALLED ON THIS PC; NOT RUN.**
- Holding a gear needs to know where the engine keeps it, and nobody does. 0.1.0 asks:
  - an RTTI census;
  - a per-frame observe of the player's car against the HUD gear;
  - a hold experiment, off until the config names a field.
- **THE ONE NEXT ACTION:** the owner launches, drives through the gears for a minute, and sends `ncm_gearbox-<pid>.log` (Â§GB9). Then the hold experiment (Â§GB10), then the manual's input, clutch, neutral and HUD.

**EARLIER 2026-10-04 (14:13 ET) - NCM GEARBOX SPIKE INSTALLED ON THIS PC (owner asked); dev restarted at 14:08 with the Observer panel + KB-329 (log `l319-restart-20261004.stdout.log`).**
- `dev-hand-install-mods.py --only none --extra-zip dist/ncm-gearbox-0.0.1.zip`: `ncm_gearbox.dll`, `ncm_gearbox_specs.json`, `r6/tweaks/ncm_gearbox/clones.yaml`. Record: `%LOCALAPPDATA%/NCM/dev-mods/20261004-141309`.
- **NEXT:** launch the game and read `red4ext/plugins/ncm_gearbox/ncm_gearbox-<pid>.log` (MASTER_TEST Â§GB4). If the game will not start, run `--uninstall`.

**EARLIER 2026-10-04 - OBSERVER PANEL (F3) + KB-329 FIXED IN CODE; NOW LOADED (14:08 restart); NO LIVE PASS.**
- Owner QA of Observer: the tester got no NCM Pace (KB-329: two games on one PC; a Pace page with no handshake timeout), so the ghost watched model cars over an empty road. When the race ended, the camera froze silently.
- Built:
  - the iRacing-style F3 panel (races, running order, cameras, director) and the strip;
  - rebindable hotkeys;
  - the KB-329 handshake timeout;
  - the silence fixes.
- KB-4 does not reproduce with the launcher's dev values.
- **THE ONE NEXT ACTION:** a restart to load ncm_paddock + ncm_observer (both clients reconnect), then Â§OB9-Â§OB12. To enter from the owner's own client, put its user id in `observerAllow`.

**EARLIER 2026-10-04 (08:41 ET) - DEV RESTARTED: L306 + L308 + L310 LOADED (log `tools/open77/server/l318-restart-20261004.stdout.log`); NO LIVE PASS.**
- Migrations 063 + 064 applied. `ncm_observer ready (allow="")`. `RUN 1 predates Moody: first roll at hour 21`. Radio: `[buoyant / money]`. Expected rate 0.49 crashes/race, 7.1 races/h. Paddock world loaded, 20 open races. Gearbox shelf stamped (144 cars, 35 manual, gated). 0 errors.
- The owner (player 2) was kicked by the restart, with consent.
- **THE ONE NEXT ACTION:** the owner tests MASTER_TEST Â§MW1-Â§MW10, Â§OB1-Â§OB8 and Â§GB1-Â§GB3. Run 1's first verdict is Tue 10-06 12:00 ET.

**EARLIER 2026-10-04 - MOODY, THE VERDICTS AND THE SEVEN-DAY TIMELINE BUILT (L310).**
- A run now ends where a recorded verdict says: each noon from Day 3 to Day 7, p from the state, one seeded draw.
- Moody rolls a public D20 every 4 h. Its faces change purses, calendar, police and limits, and each NPC weighs a lure for themselves.
- Reservoirs feed the curve; the racing radio composes the city's mood every two hours.
- Harness, 20k unattended runs: Day 4 0.26, Day 7 1 in 142. Gate ALL GREEN. Schema 064.
- Q6 defaulted: finales before every possible end.
- **THE ONE NEXT ACTION:** the owner restarts dev at a moment of their choosing. That loads L306 + L308 + L310 and migration 064. Then:
  - MASTER_TEST Â§MW1-Â§MW10 (Moody, verdicts) and Â§OB1-Â§OB8 (Observer);
  - dev's run 1 meets its first verdict at Tue 10-06 12:00 ET (Â§MW6).
- The collapse is still `dryrun`.

**EARLIER 2026-10-04 - MOODY CAPTURED AS SPEC (L309, doc 47, IDEA-946-IDEA-957); NOTHING BUILT; SUPERSEDES DOC 45 Â§0.5-Â§0.6 (OWNER RULING).**
- Racing Week becomes seven advertised days. Hour 72 is an attractor, not a rule. A seeded, state-read continuation judgement runs at each noon. Moody's D20 changes conditions, never outcomes.
- Ruled (L309 addendum): doc 47 supersedes doc 45 Â§0.5-Â§0.6; crowns at every collapse; a countdown before every possible end; reservoirs only where facts feed them. Q6 (the finales) is open. Build order: doc 47 Â§6.
- **The one next action is unchanged:** the dev restart for L306 + L308, then Â§OB1-Â§OB8 with `ncmtester2`.

**EARLIER 2026-10-04 - NCM OBSERVER SLICES 1-2 BUILT (L308): THE MODE, THE EXCLUSION, THE DIRECTOR, THE LENS; NOT DEPLOYED; NO LIVE PASS.**
- New resource `ncm_observer` plus core `observer.director` (11 tests). `ncm_paddock/racers.lua` now carries each car's distance, gap and vehicle id, and raises the snapshot server-side. One observer check added to each of the three driver lookups (league, Paddock, world).
- Gate ALL GREEN. Dev not restarted: L306 is also waiting on the owner's moment.
- **THE ONE NEXT ACTION:** at the owner's chosen restart (which also loads L306), launch `ncmtester2` through the launcher, then `ncm.observer on <pid>` and `ncm.observe <pid> auto` from the console (MASTER_TEST Â§OB1-Â§OB8).
- Not built yet: lane cameras and curation, deterministic commentary with the voice bridge, OBS overlays, the TV loop.

**EARLIER 2026-10-04 - NCM OBSERVER CAPTURED AS SPEC (L307, doc 46, IDEA-928-IDEA-941); NOTHING BUILT.**
- Observer is a non-participating client (`ncmtester2`) that goes to a race, makes it physical through the existing bubble, films it, feeds Radio OS and OBS, and loops the program back onto OPEN//77 TVs.
- Ruled (L307 addendum): commentary is deterministic with an optional voice bridge, and needs no Python; Observer is an on-demand client mode, never accidental. O-2 awaits the owner, O-3 is open. First step if authorised: `ncm.tp` the tester client to a distant dev race (G1 + G2).
- **The one next action is unchanged:** the L306 dev restart and the gearbox spike opt-in below; then the Online hotfix yes/no (L305).

**EARLIER 2026-10-04 (07:30 ET) - NCM GEARBOX (L306): OUR OWN MANUAL TRANSMISSION, PER MACHINE; PHASES 0-1 BUILT, NOT DEPLOYED; NO LIVE PASS.**
- Every car is born automatic or manual: `vehicle_asset.gearbox_*` (schema 063); owned cars â†’ `pre_gearbox` automatic.
- A manual is its own clone record with 4-8 real gears. The market lists `Galena Â· automatic` and `Galena Â· 6-speed manual` as separate cards, with manual sales gated as ARRIVING.
- Spike DLL `ncm/gearbox` 0.0.1 builds the clones at game start. It is packed in `dist/`, never loaded, and not installed.
- Gate ALL GREEN. Dev not restarted: the owner was connected at 07:20.
- **THE ONE NEXT ACTION:** the owner picks a moment to restart dev for L306 (L305 is already loaded; Â§GB1-Â§GB3), and opts in to the spike (Â§GB4: install the zip, launch, send `ncm_gearbox-<pid>.log`).
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
- Then Â§RW17-Â§RW20. Watch that the flag fires on a spread sim field (unobserved so far) and that team car buying settles after the first burst.

**EARLIER 2026-10-04 (02:15 ET) - EVERY RACER ON THE MAP (L304); NPC PART PURCHASES FIXED (KB-328); LOADED ON DEV; NO LIVE PASS.**
- Racer pins: every running race's cars on the map every 2 s (tier icons, humans white, your race green). Boot `tools/open77/server/l316-restart-20261004.stdout.log`: `1 race(s), 12 car(s) on the map`. Live check owed: Â§RW16 (does the minimap show them?).
- KB-328 cause and fix: the shop seeded new independents' cash in memory and then bought against the unsaved database; it now saves first. No SQL 1690 since.

**EARLIER 2026-10-04 (00:10 ET) - KB-327 FIXED: the owner's car vanished because ncm_world hit its 64 MB Lua quota (L301's 12 MB lane index); speed limits now live in their own resource `ncm_speed` with a 3.8 MB compact index. Dev mods restored (KB-326). KB-328 (NPC part purchases, SQL 1690) open.**
- Dev boot `tools/open77/server/l313-restart-20261004.stdout.log`: clean; ncm_world, ncm_speed (`lane index ready`), Paddock S4.
- After any NCM Online session, close the game and run `python tools/dev-hand-install-mods.py` before joining dev (KB-326).

**EARLIER 2026-10-03 (23:25 ET) - W-1..W-4 RULED (L303): CHAMPIONS CROWNED AT HOUR 72, THE HALL OF CHAMPIONS, MAIMAI SPEC, THE MONEY CRAZE, THE COLLAPSE (DRY-RUN) AND THE ENDING; LOADED ON DEV; NO LIVE PASS.**
- Built (doc 45 Â§O-Â§P):
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
- **THE ONE NEXT ACTION:** the owner runs `ncm.week.collapse plan` and `/ncm.anchor` (Â§RW13), then the speed/population tests (Â§RW1-Â§RW9).
  - Dev's run 1 ends Tue 10-06 12:00 ET: the first real crown and a dry-run collapse (Â§RW12).
  - Live collapse only on the owner's word, after reading that plan, with a DB backup (Â§RW15).
  - Hold dev -> Online until the Â§RW cases pass.

**EARLIER 2026-10-03 (22:25 ET) - RACING WEEK IS A CONTINUOUS 72-HOUR CURVE (L302): HISTORY'S CARRIER + THIS RUN'S LIVE SIGNAL; LOADED ON DEV; NO LIVE PASS.**
- Built (doc 45 Â§N):
  - `week.curve`: tolerance = carrier + a bounded deviation pushed by what racing did, human or NPC;
  - the organisers' announced steps (Ã—0.75 â†’ Ã—1.6 â†’ Ã—1.0 â†’ Ã—0.8; penalty â†’ warning â†’ police), latched and fired early by a bad week;
  - police discretion from tolerance;
  - `ncm_world/server/week.lua` and schema 060 (run state + provenance);
  - fact feeds from league, Paddock, chrome and speeding;
  - official chapter labels on the sign.
  - The expected crash cost is measured: 0.50 per Paddock race.
- Dev restarted (log `tools/open77/server/l307-restart-20261003.stdout.log`): `RUN 1 opened at hour 16.39`, `ANNOUNCE opening`, carrier 0.792, no errors. Gate ALL GREEN.
- **THE ONE NEXT ACTION:** the owner joins dev and runs MASTER_TEST Â§RW1-Â§RW9 from Warden's live console (`ncm.week day 1/2/3`, `ncm.week`, `ncm.probe.crowd corpo 15` ...).
  - Hold dev â†’ Online until they pass: these resources sit in `ncm/*` and would ship with the next push.
  - Then E7 (Pace, game closed) for NPC compliance; W-1 / W-4 are still owed for the reset behind the rewind.

**EARLIER 2026-10-03 (22:05 ET) - RACING WEEK: ADVERTISED SPEED LIMITS v1 AND THE POPULATION PROBE LOADED ON DEV (L301); GATE ALL GREEN; NO LIVE PASS.**
- Built (doc 45 Â§M):
  - the derived Day (`week.clock`; `ncm.week <0..3>` pins it);
  - posted limits from the game's 19,432 vehicle lanes (`tools/gen-lane-limits.py`);
  - the Day's sign on the HUD;
  - proportional NCPD wanted capped per Day;
  - Day-1 speeding incidents (schema 059) and Day-2 warnings in races;
  - a `speeding` trajectory signal.
- Also built: the dev-only probe `prototypes/ncm_dev_probe` (E1-E5).
- Dev restarted twice. The first boot died on `os` in the server sandbox (KB-322, fixed). The second (log
  `tools/open77/server/l306-restart-20261003.stdout.log`) was clean: migration 059, `lane index ready: 19432 lanes ... 3.2 s`, `WEEK run=1 day=1`, probe ready.
- **THE ONE NEXT ACTION:** the owner joins dev and works through MASTER_TEST Â§RW1-Â§RW8 from Warden's live console:
  - `ncm.probe.crowd corpo 15` at Corpo Plaza, then `clip` / `pop` / `dress`;
  - the sign at `ncm.week 1/2/3`;
  - a Day-1 and a Day-2 street race.
  Then E7 (a Pace publish, game closed) for NPC compliance; W-1 / W-4 are still owed.

**EARLIER 2026-10-03 (evening) - RACING WEEK SITE POPULATION: A SEEDED JIGSAW; WOLVENKIT HARVEST OF 1,542 VANILLA SOCKETS; NOTHING BUILT.**
- Read [RACING_WEEK_SITE_POPULATION.md](../research/open77/RACING_WEEK_SITE_POPULATION.md) and doc 45 Â§L. Native Communities are baked and client-local, so they are data, not the controller. Server NPCs + workspots + props + effects + sound are the runtime. `tools/harvest-site-sockets.py` (read-only, WolvenKit CLI) wrote `docs/research/open77/evidence/site_sockets.json`. IDEA-875 to IDEA-884.
- Then: experiments E1-E6 on dev (E1 first: 15 crowd NPCs at Corpo Plaza's harvested sockets, two clients) once the owner wants to start; W-1/W-4 rulings still owed.

**EARLIER 2026-10-03 - RACING WEEK (L300): THE OWNER'S THREE-DAY RECONSTRUCTION SPEC AUDITED; PROPOSAL 45 WRITTEN; NOTHING BUILT.**
- Read [45_RACING_WEEK.md](45_RACING_WEEK.md) (PROPOSAL, sections A-K). Finding: the Paddock already holds ~70% of it (the real-time clock and idempotent daily step, seeded climate rolls, a hidden trajectory, Spotlight, the tagged voice bank, and the Index knowledge/possession split). Recommended: the NPC world replays from a fixed historical seed each run; a D-4 hybrid meta (Index knowledge + anchored cars as witnessed at their last race + team identity, no meta-money); a six-rung dev ladder that resets only Spotlight until the economy rulings land.
- Rulings owed before any build: W-1 (does the Paddock replay?), W-4 (the meta model), then W-2/3/5/6/7. IDEA-857 to IDEA-874.
- **THE ONE NEXT ACTION:** unchanged from Baseline 2 below (race once on Online). Racing Week starts at rung 0 (pure `week.clock` + tests, dev only) once the owner rules W-1 and W-4.

**EARLIER 2026-10-03 (08:15 UTC) - NCM ONLINE IS ON BASELINE 2: DEV'S CODE AND ITS 8-MOD STACK (L299).**
- Deployed: backup `/opt/ncm/backups/pre-carrier-prod-20261003T080827Z`; resources at `fb23f35` (tag `online-baseline-2`); 8 required mods, digest `7b070f25...` (identical to dev); migrations 043-058; Paddock GENESIS (Online's own world). First boot clean: no ERR, production minting (KB-311 live), NPC cars minting, 24 races scheduled. All 8 blobs verified over HTTPS. Details and rollback: OPS_STAGING "Online Baseline 2".
- Testers who join need the 8 mods (the launcher installs them; Pace and Broadcast are new to them).
- **THE ONE NEXT ACTION:** the owner joins NCM Online (the launcher installs the new mods) and races once: a street race and an oval (Â§CT19-Â§CT21 on Online), then `tools/npc-economy-audit.ps1`-style checks against Online's world after a day.

**EARLIER 2026-10-02 (23:00 ET) - THE AUDIT'S SEVEN DOORS (L298) AND L296 LOADED ON DEV; PACE 0.8.9; GATE ALL GREEN.**
- Loaded: Pace 0.8.9 published to dev and hand-installed (record `%LOCALAPPDATA%/NCM/dev-mods/20261002-225613`); dev restarted twice (logs `tools/open77/server/l298-restart-20261002.stdout.log`, `l298b-restart-20261002.stdout.log`): schema 058 applied, required mods 8 digest `ce4db77a...`, no errors; the L298 tunables declared (`npcRacerVariants` on). `tools/test-npc-sql.ps1` against MariaDB: 22/22 (mint with 11 factory parts, install, NPC service, purchase, Exchange). NPC cars minting ~6 per 10 s (36 at 22:59, all assigned).
- Built in L298: production fix (KB-311), NPC race cars as real 11-part cars with derived levels and Pace performance variants (KB-313), persisted/strict shopping (KB-312), wages/purses/fees/repairs ledgered (KB-314-316), goals with reasons, wear/service/scrap/trade-in sinks, NPC-to-NPC Exchange, "Last batch" provenance. Also loaded: L296 (pre-grid, ovals, street pace from the road).
- 23:59 ET: dev restarted (log `tools/open77/server/l299-restart-20261003.stdout.log`, 0 errors) with KB-317 fixed -- the oval session view was lost to a refused state-bag write and the owner DNS'd "absent" on their own grid.
- 00:27 ET 2026-10-03: Pace 0.9.0 published + hand-installed (record `%LOCALAPPDATA%/NCM/dev-mods/20261003-002640`), dev restarted (log `l300-restart-20261003.stdout.log`, 0 errors, mods digest `0a32d55d...`) with KB-318 (graceful restream: launch watch, oval-wide bubble, model position while launching).
- **THE ONE NEXT ACTION:** L299 -- the owner lifted the Online freeze (2026-10-03). Stock taken and everything committed and pushed; next, the owner confirms the Online push plan (DB backup, code, 16 migrations, 8 required mods), then deploy.

**EARLIER 2026-10-02 (late night) - NPC ECONOMY AUDIT (L297): SOLD OUT IS A CARDBOARD WALL; REPORT WRITTEN; NO CODE CHANGED BUT THE AUDIT TOOL.**
- Report: [wp/NPC_ECONOMY_AUDIT.md](wp/NPC_ECONOMY_AUDIT.md); tool `tools/npc-economy-audit.ps1` (read-only; output `tools/open77/server/npc-economy-audit-<stamp>.txt`).
- Headline: no vehicle manufactured since 09-24 (KB-311, SQL 1292 in `manufacture`, = KB-281); one vehicle ever sold; teams never buy; NPC parts never reach the raced car; restart re-buys; wages vanish (KB-312-316).
- Then: the owner ranks the audit's doors (fix production first is the recommendation). L296 is still on disk and not loaded: restart dev to load it (Â§CT13-Â§CT15).

**EARLIER 2026-10-02 (night) - PACE FROM THE STREET, THE PRE-GRID, NO AUTO-PLACE, OVALS BACK ON THE CALENDAR (L296); BUILT ON DISK, NOT LOADED; GATE ALL GREEN.**
- Owner, after the evening's races (log `tools/open77/server/l296-restart-20261002.stdout.log`, 41 races, 8 with the owner): "suddenly, quite good ... maybe almost ready to be pushed to online"; NPC speed is real (one win, several flagged DNFs in an unupgraded car). Online stays frozen at Baseline 1 until the owner says otherwise.
- Read from that log: sim pace per route 22.7-40.7 m/s vs a physical field at ~25-33 m/s (KB-303); no ovals scheduled at all (KB-304); auto-place refused the owner every time (KB-307); a chain explosion retired nine NPCs in the owner's win (KB-309, open); the rolling restream did not take (Pace logged the pre-roll, cars at 1-4 m/s after it; restream cost 200-590 m, KB-310, open); racer scales loaded (`42 racer(s) scaled`, 4 skipped); flag windows 30-68 s with no 0:00 hang.
- Built (L296): street sim/quali timed over the baked road line at a learned tier speed (KB-303); the pre-grid from T-15 min (KB-308); auto-place and its text removed (KB-307); ovals back, standing starts, course-change fix (KB-304-306). Server + client Lua only.
- Then: restart dev (no Pace change: `tools/o77-server.ps1`), then race: Â§CT13 (pre-grid), Â§CT14 (an oval, end to end), Â§CT15 (sim/quali pace), and watch Â§CT12's restream. Then the owner's item 4: NPC parts ownership and provenance, NPC finances, the economy (IDEA-851).

**EARLIER 2026-10-02 (late afternoon) - THE FLAG, THE CEREMONY, LIVE ORDER WITHOUT PENALTIES, STAGGERED START (L294); PACE 0.8.7; LOADED ON PRIVATE DEV 16:21 ET.**
- From the 15:45 and 16:00 races (log `tools/open77/server/l293-restart-20261002.stdout.log`): a 4-minute wait to classify (KB-295), the owner always P1 on the tower (KB-296), hand-backs at the 0.50 pace floor driving the streaming churn (KB-297), a lap-one pile-up from a simultaneous launch (KB-298).
- Owner rulings (L294): the live order is without penalties; a classification ceremony shows them (as crossed, then the shuffle, green up / red down); races end at the flag, the leader's crossing + 0.03 s/m (45-240 s), with a countdown.
- Built and loaded: all of the above; Pace 0.8.7 published to dev and hand-installed (record `%LOCALAPPDATA%/NCM/dev-mods/20261002-162146`). Dev restarted 16:21:57 ET (log `l294-restart-20261002.stdout.log`): 42 resources, required mods digest `6cf41347...`, no errors. Nothing committed.
- Also loaded (dev restarted again, log `l295-restart-20261002.stdout.log`): no provisional "P1" while the field is classified (KB-299).
- L295 LOADED ON DEV 17:01 ET (Pace 0.8.8 published and hand-installed, record `%LOCALAPPDATA%/NCM/dev-mods/20261002-170136`; dev restarted, log `l296-restart-20261002.stdout.log`, 42 resources, mods digest `12eeef2b...`, no errors): seamless restream (set-down lead learned per race + Pace 0.8.8 rolling pre-roll, KB-302), flag 0.012 s/m 30-90 s (KB-301), the classified result reaches the HUD (KB-300). To load: with the game closed, `python tools/staging/publish-carrier.py tools/open77/server --zip dist/ncm-pace-0.8.8.zip --version 0.8.8 --id ncm-pace --display-name "NCM Pace" --import-blob --enable`, `python tools/dev-hand-install-mods.py --only ncm-pace`, restart dev.
- Then (superseded): race one mixed street race to the end: Â§CT12 (restream, flag, result), Â§CT10 (position, flag, streaming), Â§CT11 (ceremony), Â§CT7 (pace), Â§CT6 (names). Then read the TweakXL log for `Unknown property` and the Pace log for `racer scales`.

**EARLIER 2026-10-02 (afternoon) - TRUTHFUL RUNNING ORDER + NPC PENALTIES + PACE 0.8.6 LOADED ON PRIVATE DEV 15:25 ET (L293); GATE ALL GREEN; NO LIVE RESULT YET.**
- The 15:00 race (log `tools/open77/server/l292-restart-20261002.stdout.log`): owner crossed first at 3:58.5, classified P3 on +14 s incidents; the tower had shown NPCs finished while they were behind. Causes: model ran bubble cars on their sim clock and handed-back cars at sim pace (KB-293); order ignored penalties and NPCs had none (KB-294); the racer profile was half-applied since 0.8.5 (KB-292).
- L293 built and loaded: racestate 0.2.0 truth rules; one provisional order with penalties for humans and NPCs; NPC incidents by the human scorer; Pace 0.8.6 (corrected profile, more traction/braking/lookahead, NPC-only drive x1.25 / brakes x1.30 / drag x0.80), published to dev and hand-installed (record `%LOCALAPPDATA%/NCM/dev-mods/20261002-152520`); subtle decluttered nameplates (IDEA-845). Dev restarted 15:25:33 ET (log `l293-restart-20261002.stdout.log`): 42 resources, required mods 8 with digest `fe94dbfc...`, no errors. Nothing committed.
- Earlier this afternoon, dev restarted 14:44:53 ET (log `tools/open77/server/l292-restart-20261002.stdout.log`): 42 resources started, no errors and no SQL 1292 in the boot.
- Traced the owner's 13:45 mixed point-to-point race (North Oak Ramp 2 to Tip) through the client log (`red4ext/logs/open77-2026-10-02-13-31-50.log`) and the dev server log (`tools/open77/server/op77-124-start.out.log`).
- L291: the whole mixed field reaches the HUD and tower (KB-282); grid ring permission (KB-283); qualifying views targeted (KB-284); race-end waypoint release (KB-285); NPC names as native anchored cards (IDEA-839); per-phase session-view size log for ovals (IDEA-842).
- L292: racer clones on every street race. The vanilla race profile obeyed lane speed limits, and the 74 m/s ceiling was never applied (KB-287). Nav tracks a node's own map pin instead of a custom waypoint (KB-289). No bubble churn while a player pulls away (KB-286). Reaching the mark during the lights now starts the race (KB-290). Standings name a human driver and label them Privateer (KB-291). Owner test rulings applied (DNS at green everywhere, entry/freeze at T-1, sim ovals 35-40 m/s); `ncm-test` ALL GREEN under Lua 5.4 and LuaJIT (KB-288).
- Then (superseded): launch the game (Pace 0.8.6 is installed), rejoin dev and run one mixed street race: Â§CT9 (truthful order with penalties), Â§CT7 (pace), Â§CT6 (subtle names), Â§CT5 (tower/HUD/ring), Â§CT8 (finish GPS), plus one QUALIFY run (Â§CT3). Then read the TweakXL log for `Unknown property` and the Pace log for `racer scales`.

**EARLIER 2026-10-02 - BOTH SERVERS ON OPEN//77 `2.31.21+op77.124`; DEV CLIENT MODS RESTORED (L290).**
- Pre-upgrade state is preserved in [SERVER_BASELINE_2026-10-02.md](archive/SERVER_BASELINE_2026-10-02.md) and pushed checkpoint commit `6628744` on `checkpoint/pre-op77-upgrade-2026-10-02`. Development still requires eight hosted packages; Online still requires its original three with digest `879af328...`. Online NCM code, required mods, and data remain frozen at Baseline 1.
- The Windows Development server is running on `.124` with 44 loaded resources and unchanged required-mod digest `8dc855d1...`. The raw-address Development join needs local mod installation: all eight packages were installed into the game with a reversible record under `%LOCALAPPDATA%/NCM/dev-mods/20261002-132708`, and their NCM RED4ext plugins were removed from the ignore list. The owner has not yet rejoined to confirm Rig Bridge and Scanner.
- Online is active on `.124`; its three mod blobs still hash correctly, the public HTTPS manifest is unchanged, and the prior server tree is backed up at `/opt/ncm/backups/server-20261002T172506Z`.
- Explained the nearby-player bubble: the Paddock field gets physical vehicles around a player and keeps them present while the player stays close; it is not a separate race type.
- Fixed actual oval bubble spawning to select NCM Pace RaceDrive clones. Corrected the canonical and all four resource session-kernel copies so DNS happens at green, and active drivers are not timed out by the generic short oval limits. Oval limits: 60 minutes, 20-minute finish window, extended while a human keeps moving.
- Paddock grid ring now draws through native marker APIs directly. Restarted private dev at 12:45 ET; 44 Lua resources started and resource generation 1 published. No tests run (not requested).
- Then: rejoin Development and confirm Rig Bridge and Scanner load after the local reinstall. Then live check the grid ring and oval race behavior. The MariaDB SQL 1292 persistence failure (KB-281) remains unresolved.

