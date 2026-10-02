# Pace road path and braking probe

> **STATUS: CURRENT** - 2026-09-30 dev investigation and road-speed candidate. Live graph load passed; race driving has not yet passed.

## Observed race

- The 17:30 dev Paddock race used 12 native AI vehicles and a two-point start/finish path. Its Pace log held per-car ceilings at 23.2-27.2 m/s (83-98 km/h). The same finish target was reissued about every 0.6 s, dozens of times per car. The owner saw the field wreck repeatedly and reported a starter car capable of 135 km/h.
- `paddock.live.speedPlan` derives each leg's ceiling from a simulated split and scales it by 1.08. With only start and finish, this gives one flat ceiling over the whole street route. The simulation's road-distance estimate and the sparse physical path are different quantities. A higher constant ceiling offers no safe bend approach.
- The native autonomous command includes `maxSpeed`, `minSpeed`, and a destination. The 0.6 s reissue may disrupt the engine planner; that causal effect needs a controlled comparison.

## Road path feasibility

- The owner's installed In-World Navigation mod colors its **player minimap path** using upcoming heading changes. Its [native hook](https://github.com/jackhumbert/in_world_navigation/blob/main/src/red4ext/Hooks/UpdateNavPath.cpp) runs at `MinimapContainerController::UpdateGPSPath`; it [exposes](https://github.com/jackhumbert/in_world_navigation/blob/main/src/red4ext/Main.cpp) `questMappinPoints` and `poiMappinPoints` to scripts. These are an active player destination, not an arbitrary NPC race leg. Copying this buffer would give the wrong route or no route for a Paddock race.
- Pace's **read-only** RTTI probe in the running game found no reflected route method on `gamegpsGPSSystem`, `gamegpsIGPSSystem`, `worldITrafficSystem`, `navRuntimeSystemPathfinding`, or `AIVehicleAgent`. The one matching navigation method was `worldNavigationScriptInterface.CalculatePathOnlyHumanNavmesh(startPoint, endPoint, ...)`; its name and type describe pedestrian navmesh, not a road route. This does not rule out an unreflected native engine route routine.
- The installed `03_night_city.streamingworld` references three cooked traffic files: `all.traffic_persistent`, `all.lane_connections`, and `all.lane_polygons`. WolvenKit serialization of the vanilla archive gives 31,717 indexed lanes. The latter two files contain the directed edges and Vector3 road outlines; the persistent resource's own outline/connection fields are empty. An offline Dijkstra route from North Oak Ramp 2 to Glen Straight used 79 lanes and about 5.7 km of road with junction gaps at most 4.3 m. No checkpoint combination was authored by hand.
- RED4ext `ResourceLoader::LoadAsync` successfully loaded all three files in the dev game. The runtime graph has 33,952 entries; why this exceeds the 31,717 entries in the exported vanilla archive has not been established. A guarded native reader found the sparse entry layout and decoded the 12-byte edge's lane index at offset zero by scoring geometric continuity. It copied 279,906 line points and 51,338 continuous directed edges; a 666-point route for the same dev leg was found in the running game. This verifies a supported resource-load path and a working road-graph algorithm, though comparison to the active player GPS route remains open.
- `ncm/pace/src/road_loader.cpp` copies graph data out of engine resources; `road_graph.cpp` routes race legs; `speed_profile.cpp` derives curvature limits and propagates braking upstream. `State::planRoad` constructs a speed reference when a checkpointed plan completes. Steering remains with the native autonomous driver. Straight speed is raised from the flat 23-27 m/s source ceilings, and unchanged autonomous commands are renewed no more often than three seconds when a road plan is active. This candidate is installed on **dev only** and passes the Pace C++ tests; no live race PASS yet.
- A new state test on a directed road with a right-angle bend caught a real error before racing: reading the speed limit three polyline points ahead sampled the post-corner acceleration and erased braking at the approach. The installed build reads the current backward-propagated limit. Per-car variation now caps straight speed at 38-44 m/s (137-158 km/h); it does not multiply corner speeds beyond the shared lateral-acceleration limit. The C++ suite passes after this correction.

## Next action

Run a checkpointed dev race with the installed candidate. Require a `road speed plan ready` log, sample actual target/vehicle speeds at straights and bend approaches, observe traffic and racer-to-racer interactions, and check for the prior cast-fault CTD. If the speed plan does not activate, identify the failed leg from the race plan and graph before changing speed behavior. Compare the resulting command cadence and collisions to the earlier 0.6 s control. The checkpointed-race CTD remains open until its trigger is isolated or a reproducible regression passes repeatedly.

## 2026-10-01: closed oval splines, Pace 0.8.2 candidate

Street racing on `AIVehicleRacingCommand` passed only its first live movement test (`MASTER_TEST §CM2`). The owner clarified that no oval was used for that proof. The earlier oval attempts used drive-to-point commands, so their failed steering does not predict the closed-spline result.

`tools/bake-oval-splines.py` reads the three authored four-point ovals. For Corpo Circle and Westbrook, the directed lane graph routes each successive pair of marks around the roundabout with no reverse-angle steps or island crossing. Their four route legs are joined at the authored marks after removing each bake's 80 m finish run-out. The resulting closed lines are 987 m (Corpo, 93 source points) and 456 m (Westbrook, 77). NCX Octagon is outside the exported lane graph, so the tool samples its authored polar ring: 475 m and 47 source points. The city lines are about 6-10 m away from the old idealized model ring in places; they are now also the server's model and grid line, so bubble cars start on the spline's road line.

The existing ArchiveXL baker packed all 1,190 street splines plus the three oval nodes into 30 sectors. WolvenKit conversion of sectors 22-23 back to JSON confirmed three `worldRaceSplineNode` entries with `splineData.looped = 1`: 51, 25 and 34 points after thinning. The packed archive SHA-256 is `db720a7f6dbec7d0ec5d85263c999e30bca5cd2ca6e27cd03d1ba9243c95accc`. Pace 0.8.2's dynamic oval plan names one closed spline; its repeated marks still track lap progress, while the same racing command stays held across marks and seams. The server refuses an oval physical car for Pace 0.8.1 or older.

Offline evidence: Pace state tests pass, including the closed-spline seam and entity replacement; the redscript compiles against the installed bundle; the Paddock host harness passes 336 assertions; focused core oval tests pass under Lua 5.4 and LuaJIT. The packaged local candidate is `dist/ncm-pace-0.8.2.zip` (SHA-256 `b8ea128efc08f3f4a745c29c09feeb3e5a85b83c22c9f90c542e9a5d89533d78`). No game session has exercised a looped `AIVehicleRacingCommand`, lap seam, finish, or bubble hand-off. Ovals remain off the schedule until `MASTER_TEST §CO` records live results.

**Next oval action:** test a single closed loop on dev with Pace 0.8.2 installed and the matching `ncm_paddock` resource, starting with Westbrook's 456 m road loop. Require the archive load and spline ref in the log, forward motion through two line crossings with no command `FAILURE` or repeated `next leg`, and agreement between physical lap and model LAP. Then follow a full race to classification and repeat at Corpo and NCX. If the racing command ends at the first seam, inspect its success/failure state and the spline's `looped` behavior in engine before changing lap logic.

## 2026-10-01 15:46:07 ET: KB-238 recurrence, diagnosis only

Evidence: `evidence/2026-10-01-154607/` (client, crash probe, Pace 0.8.2 pid 54512, reports). Minidump remains in LocalAppData/REDEngine/ReportQueue/Cyberpunk2077-20261001-154607-54512-66212.

Same fault: Cyberpunk2077.exe+0x02543394, read 0xC0, RAX=0. Fault thread 66212 differs from vehicle/breadcrumb thread 55424; do not attribute this occurrence to the main thread from earlier reports.

Race pr-regional_d-1790883900, person p00786, vehicle 8589934606, cyberEntity 0x000001430000002A, engineEntity 0x9F4D8D, Pace car 12:

- 15:46:05.468: set down 87 m from player.
- 05.539: engine spawn completes.
- 05.569: client reports settled after **0 ms**, requests driver.
- 05.613: Pace car.add; Pace records a racing command that second on the Kabuki Bridge to Deep Dive street spline.
- About 06.550: vphys obs=1 keepBody=0 (844 ms before fault).
- 06.710: driver 42949672973 mounted; 06.837: inWorkspot=yes.
- 07.394: fault, 684 ms after mount / 557 ms after workspot confirmation.

Two further racers spawn at 98 m and 70 m in the last second; mounts still pending. Last despawn breadcrumb is 24.188 s before fault. No final obs=0 breadcrumb: the earlier universal unobserved-transition explanation is contradicted by this occurrence.

Code: server/settings.lua:98 sets bubbleSeatDelayMs=0; server/bubble.lua:367 passes it to client/live.lua:406-416, which accepts the first nonzero engineEntity immediately. server/bubble.lua:708-730 calls seatDriver, marks car.seated and sends Pace car.add on attachDriver acceptance, BEFORE asynchronous actual mounting. STREAMLINE 'seated' means the server flag, not confirmed seating (05.766 flag versus 06.710 actual mount).

Assessment: another KB-238 signature inside the smaller bubble is confirmed. Spawn/driver lifecycle overlap is the leading hypothesis; zero delay provides no settling protection. This does not prove the breadcrumb vehicle is the faulting object, that three seconds cures it, or that Pace caused it. No symbolized causal stack or faulting-object identity established.

Next diagnostic action: resolve the faulting object/call chain from the retained minidump and compare with these identities. If insufficient, separately authorize a controlled seat-timing comparison retaining drivers. Runtime, settings and deployment unchanged; no live PASS claimed.

## 2026-10-01 follow-up: native fault traced to p00786's vehicle and driver

This supersedes the previous addendum's statement that the exact object is unknown. Owner challenged the timing-only diagnosis and proposed Paddock reconciliation or record selection, noting the preceding race survived many stream changes. No fixes authorized or made.

### Established from native instructions and minidump memory

The actual caller return at exe+0x2698A5A follows a call to exe+0x2543388. Before that it calls exe+0x2E5EC0 with a handle at 0x90ACCFF570. That handle contains object 0x28648A20220. Its reflected class hierarchy is vehicleCarBaseObject -> vehicleWheeledBaseObject -> vehicleBaseObject -> gameObject. EntityID at +0x48 is **0x9F4D8D**, the engine ID of p00786's recreated vehicle 8589934606 (spawn request 323).

The cast helper compares the object's reflected class and parents with the class pointer at exe+0x3432070. In the dump that target's CName is **gamePuppet**. The vehicle fails that cast; the returned handle at 0x90ACCFF520 contains two zeros. The caller passes it onward without a null check. At +0x254338E the callee loads its null object into RAX; at +0x2543394 it reads [RAX+0xC0] and crashes.

The caller's saved state includes object 0x29627A58778, which holds the car's entity ID and a pointer to **moveComponent 0x28641521C90**. The component's owner at +0x50 is 0x28649639F10, entity **0x9F4D8E**: precisely the newly created driver NPC 42949672973 (spawn request 324), whose seat mount/workspot the client confirms. Thus this is the driver movement path encountering its car as a puppet, not merely an unrelated nearby streaming breadcrumb. The helper's semantic name and why this car reaches it are still unproven; no symbols or Open77 native source supplied that answer. Do not label objdump's nearest exported-symbol names as real function names.

Reproduction of the read-only analysis: `evidence/2026-10-01-154607/inspect_dump.py`; outputs `dump-findings.txt`, `fault-disassembly.txt`, `caller-disassembly.txt`, `cast-disassembly.txt`. Class names resolved by matching FNV-1a CNames against the vendored RED4ext SDK; EntityID +0x48 and component owner +0x50 agree with its headers.

### Paddock code trace and competing explanations

- `server/bubble.lua:390` handBack projects real progress, anchors it, then removes the physical car. `paddock.racestate.distanceAt` resumes the original timeline from that observed distance/time; being ahead or behind alone does not divide by a time difference against the physical car. `pointAt` guards zero-length spans; `origT` guards equal distances and returns nil beyond a DNF.
- Pace cars return early from `persevere` before the server teleport/reset path (`bubble.lua:410`). `holds` prevents normal resolution while physical cars remain. No evidence found that model divergence directly produced this native null pointer.
- p00786, p01535 and p00767 had all been physically driven earlier in this race, handed back at 15:45:40, :28 and :43, then recreated at 15:46:05-06. `recordFor` deterministically chooses from tier/class/prestige and org ID, not progress or damage. Driver record choice is keyed by person ID. This argues against a new, first-use record; it does not globally certify the pool. The single-player crash guards include NPC profile/template/spawn-key validation that this host does not replicate.
- Driver creation + attachDriver existed in the September 29 grid code (`5714b3b`), before today's bubble/seat-delay changes. The latest changes cannot explain the entire multi-day history by themselves.
- Confirmed separate defect **KB-252**: car.add appends forever; car.remove retires in place. The preceding 15:30 race reached 64 allocated slots, then eight additions were refused beginning 15:32:51. The crashing 15:45 race had reached index 14 only. The cap is not this immediate fault.
- Confirmed code cleanup gap **KB-253**: car.remove clears entity=0; redscript Tick only calls Apply for a found vehicle. Therefore Release does not run for this removal, and the command reference stays until ReleaseAll. Server removal also issues its client notification, removeDriver, vehicles.remove and npcs.remove without a client release acknowledgment. Native teardown may clean up; a crash consequence is NOT established. Current fault is on the new car/driver, not proven to be an old retained command.

**Conclusion:** the immediate native mechanism is now established: a real Paddock race vehicle fails a gamePuppet cast in its driver's movement path and the null is dereferenced. Paddock causes the physical re-creation and attachment, but sim arithmetic has not been implicated. The remaining root-cause question is why that movement path accepts the car as a puppet candidate (mount/contact/attachment handling); a delay or radius change is not a diagnosis. Next: trace the caller's movement/attachment contract against native symbols/source or a controlled comparison using the same record and driver. No runtime change, deployment, gameplay test, or PASS claimed.

## 2026-10-01 16:05 ET: targeted native guard built and installed (Pace 0.8.3)

Owner authorized implementing a fix for the concrete finding and will test. `ncm/pace/src/puppet_guard.cpp` hooks predicate exe+0x2543388 through RED4ext. It returns false only for an empty handle from return address exe+0x2698A5A. Nonempty handles and other callers go to the original. This preserves the movement caller's existing false branch, rather than dereferencing the failed cast. It guards the established fault, not an assertion that its upstream trigger is understood.

Attachment requires the inspected AMD64 executable PE timestamp 0x68AF45EA, SizeOfImage 0x4EFC000, all 19 predicate prologue bytes and all 37 caller bytes. A mismatch declines the hook with a log. The movement thread increments an atomic interception counter; Running update logs at most once per second. No Lua, sim, seat-delay, radius, car-slot or teardown change in this fix.

Validation: Release build; existing Pace state tests; five guard tests (empty/null handles bypass original only at the intended caller; nonempty true/false and other callers preserve original behavior); native declarations; redscript compilation against installed scripts; both byte signatures compared to the actual executable. All pass. Installed DLL hash matches build: d2cd8c7f382985c0ddd9c571b722151937a022f37e0ae71dcc040fa6a1d6f80f. Package dist/ncm-pace-0.8.3.zip SHA256 7bb16746dbc46eafa68c39c665af48e5f9a17796cebf73d05031f1ebe9141bfe.

Dev package/store declaration updated; installed using dev-hand-install-mods.py --only ncm-pace. Rollback record: C:/Users/eveng/AppData/Local/NCM/dev-mods/20261001-160535. Game was not running. Server was not restarted (the native guard needs only a fresh game launch; server manifest declaration takes effect on its next restart). Public Online unchanged. No live PASS yet: MASTER_TEST section CR requires ACTIVE startup, actual prevention evidence, continued driver/vehicle movement and repeated full races with returns. KB-252/253 remain open.
