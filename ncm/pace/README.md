# NCM Pace (package `ncm-pace`)

Drives a declared live Paddock race's NPC cars on the declaring player's client, uncapped (Paddock phase 5,
[doc 44 §15](../../docs/ncm-online/44_THE_PADDOCK.md)).

A physical Paddock race uses the engine's `AIVehicleRacingCommand` on an ArchiveXL race spline. Street routes use
one baked spline per ordered pair of race nodes. Pace 0.8.2 adds one closed spline per authored oval; the repeated
oval marks count laps while one racing command stays on the loop. NCM racers use isolated TweakXL vehicle and RaceDrive
profile clones: the profile disables AI speed-limit following and raises forward and turning acceleration factors to
3.0 (vanilla Race profile: 2.0), without changing other game vehicles. Cars near a Pace player enter the physical bubble
with a seated driver and return to the continuous model before they leave that player's streaming range. The server
keeps result authority and physical/model provenance. An oval needs Pace 0.8.2 or later to become physical.

Pace 0.8.3 adds the KB-238 native null guard for the inspected Cyberpunk 2.31 executable. The driver's movement
caller can pass a failed vehicle-to-puppet cast to a predicate that dereferences it. At that exact caller only,
an empty handle now returns false; valid handles use the original predicate. The executable timestamp, image size,
and predicate/caller instruction bytes must match before the hook attaches. Other builds are left unpatched with
an explicit error in the Pace log. This guards the demonstrated fault; why the movement path supplies the car
remains under investigation. Live race acceptance is pending in MASTER_TEST section CR.

The startup log must say `KB-238 guard ACTIVE`; `KB-238 guard prevented N null puppet read(s)` counts interceptions.
The hook only increments an atomic counter on the movement thread; the game update writes at most one report per
second. The change does not alter the bubble radii, seat timing, sim, driver records or Pace command lifecycle.

| Piece | Where | Job |
|---|---|---|
| `ncm_pace.dll` | `red4ext/plugins/ncm_pace/` | loopback transport (127.0.0.1:38640-38643), the drive plan, gate timing, five natives |
| `NcmPace.reds` | `r6/scripts/ncm_pace/` | finds each car by EntityID, reports its position, dispatches the command the DLL asks for |
| `NcmPaceNatives.reds` | `r6/scripts/ncm_pace/` | the natives, **no `module` line** (KB-182) |
| `ncm_paddock` client | `ncm/online/resources/ncm_paddock/client/live.lua` | the hidden surface, entity mapping, gate relay |
| `ncm_paddock` server | `server/live.lua` | the race: staging, the go, the server's own timing, the verdict |

It shares no code, state, port range or package with NCM Carrier, NCM Rig Bridge, NCM Radial or NCM Scanner. It
borrows only their vendored third-party headers (RED4ext.SDK, nlohmann/json) at build time.

## Who decides what

- **The server decides the result.** It times every gate itself from canonical positions. This plugin's gate
  reports are evidence: a physical result stands only when both agree within 1.5 s for every finisher.
- **The DLL chooses the current spline** and tracks each car's progress. Redscript sends the engine racing command
  in a script frame; native code never calls script. The engine steers and chooses speed on the spline.

## Safety

- **No plan, no work**: a 2 Hz poll of two integers. 20 Hz only while a plan lists cars.
- **A dropped socket stops every car.** A plan nobody is watching must not keep driving.
- **Only this game's process tree may connect.**

## Open probes

- **P-PACE-1**: the resource maps an OPEN//77 vehicle id to `engineEntity`, which the Scanner already proved equals
  redscript's `EntityID.GetHash`. The first live race confirms it for server-created cars.
- **P-PACE-2**: does the platform leave a native command alone on a car it created with no platform driving job?
  The `reds:` lines in `ncm_pace-<pid>.log` say what happened.

## Build

`powershell -File tools\build-pace.ps1` builds the DLL, runs the state tests, checks the native declarations, compiles
both scripts against the vanilla bundle and every installed script in a scratch cache, and writes
`dist/ncm-pace-<version>.zip`.

The spline archive is baked separately with `tools/bake-race-splines.py`. `tools/bake-oval-splines.py` emits the four
marked nodes for the road router, joins the resulting road legs into closed loops, and writes both the three oval
spline source lines and `ncm_paddock/server/oval_lines_data.lua`. The two city loops follow directed road lanes;
NCX Octagon uses its authored ring because the exported lane graph has no route there. The full candidate archive
contains 1,193 splines. `MASTER_TEST §CO` is the required in-game proof of the closed command and lap seams; no
oval has passed it yet.
