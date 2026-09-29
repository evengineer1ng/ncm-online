# NCM Pace (package `ncm-pace`)

Drives a declared live Paddock race's NPC cars on the declaring player's client, uncapped (Paddock phase 5,
[doc 44 §15](../../docs/ncm-online/44_THE_PADDOCK.md)).

A live race can run on either of two backends. The **platform** backend is OPEN//77's own `vehicles.ai.followRoute`,
which the server drives and which is capped at 55 m/s. The **Pace** backend is this plugin: the same native
`AIVehicleDriveToPointAutonomousCommand`, issued by redscript on the client that simulates the cars, with no speed
cap, and with gates timed at the game's own tick rate. `ncm_paddock`'s `liveBackend` tunable picks (`auto` uses Pace
when the declarer's client reports it).

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
- **The DLL decides where each car aims next**, from the plan: a point along the line, moved on 40 m early so the
  planner never brakes for an intermediate point, and 80 m past the finish so a car crosses the line.
- **Redscript issues every command**, in a script frame, exactly as OPEN//77 issues its own. Native code never calls
  script.

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
