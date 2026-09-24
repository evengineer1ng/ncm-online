# Networked vehicle AI âº Networked vehicle AI

`Open77.vehicles.ai` is a server API requiring `world.vehicles`. The server owns destinations, seat reservations and task lifecycle. One nearby ready client executes native driving; observers receive replicated motion under the existing authority lease and routing-bucket rules.

Requires client and server **2.31.13+op77.54** or later, using compatible network protocols. Vehicle and route compatibility varies; fleet-scale traffic is not guaranteed. This API does not activate Delamain quests or the taxi UI. For player-selected destinations, see [Native map and player waypoints](native-map.md).


## Networked vehicle AI âº Autonomous vehicle

```lua
permissions { "world.vehicles" }

local id = assert(Open77.vehicles.create({
    record = "Vehicle.v_standard2_archer_hella_player",
    position = {x=-2140, y=-600, z=8}, bucket=0,
}))
assert(Open77.vehicles.ai.attachDriver(id)) -- driverless
local task, reason = Open77.vehicles.ai.driveTo(id, {
    position = {x=-2100, y=-600, z=8},
    speed = 8, arrivalRadius = 4, timeoutMilliseconds = 120000,
    behavior = "normal",
})
if not task then print(reason) end

Open77.vehicles.ai.on("arrived", function(state)
    print("Arrived: " .. state.vehicleId)
end)
Open77.vehicles.ai.on("failed", function(state)
    print(state.vehicleId, state.reason)
end)
```

Omit `npcId` for a genuinely autonomous car: the driver's seat is empty on every
client. No invisible NPC, character model or hidden actor is required. Use the
visible-driver form below only when you actually want a character at the wheel.

Choose drivable coordinates **including the correct road elevation**; the example
is illustrative, not a validated route. A point above a road can fail native routing.
Tasks wait for a streamed, compatible client to acknowledge native readiness.
There is no headless server physics: without a nearby ready player, no AI moves.
The existing vehicle spawn-settling interval applies before simulator election.

_natives: server:Open77.vehicles.create, server:Open77.vehicles.ai.attachDriver, server:Open77.vehicles.ai.driveTo, server:Open77.vehicles.ai.on Â· permissions: world.vehicles_

## Networked vehicle AI âº Visible driver and passengers

Create an NPC using `Open77.npcs.create`, then call
`attachDriver(vehicleId, {npcId=npcId})`. This also requires `world.npcs`.
The NPC must belong to this resource, be alive, in the vehicle's bucket and have
no active tasks. Its normal AI is suspended and its driver mount is replicated.
Removal restores its previous AI mode and does **not** delete it.

The driver seat is reserved even in driverless mode. Passengers can board;
players cannot claim the driver seat, including by force-warp. Call
`removeDriver` before handing control to a human. AVs and Basilisk are unsupported.
The local entry prompt and mount check also honor this reservation, so approaching
the driver door offers an available passenger seat instead of hijacking the AI.
Vanilla's automatic front-passenger-to-driver seat switch is suppressed while
the driver seat is reserved, including when no NPC is visible.
`stop()` keeps the reservation; only removing the controller releases it.

`civilian_female_relaxed_01` resolves to `Character.Panam`. Pass an explicit NPC ID to select a visible driver, or omit it for a driverless vehicle.


## Networked vehicle AI âº Commands

Mutators require the resource that attached the controller. They return a state
or `nil, reason`; invalid replacement commands leave the current task intact.

| Method | Arguments after vehicleId |
|---|---|
| `attachDriver` | Optional `{npcId}` |
| `driveTo` | `{position={x,y,z}, ...options}` |
| `followRoute` | `{points={{x,y,z},...}, loop=false, ...options}` |
| `follow` / `chase` | `{targetKind="player"|"vehicle"|"npc", targetId=id, distance=8, ...options}` |
| `joinTraffic` | Optional options; indefinite native road-following |
| `setSpeed` | Number, 0.5..55 m/s |
| `setBehavior` | `"normal"`, `"cautious"` or `"aggressive"` |
| `stop` | Keeps the seat/controller; idempotent |
| `removeDriver` | Releases the seat/controller |
| `state` | Read-only; nil when unattached |

Options: `speed` (default 12), `behavior`, `arrivalRadius` (1..20 m, default 4),
`timeoutMilliseconds` (1000..3600000, default 300000). Routes contain 1..64 points.
Follow distance is 3..80 m. Coordinates must be finite and within Â±16000.

Normal uses native avoidance; cautious applies 75% of the speed ceiling;
aggressive enables native `clearTrafficOnPath`. These presets do not implement
police logic, weapons or guaranteed traffic-law compliance. Follow/chase use
native autonomous pathing to server-updated target coordinates, at most twice
per second. No teleport catch-up or scripted ramming. `joinTraffic` uses
indefinite road-following, not ambient population spawning.


## Networked vehicle AI âº State and events

IDs `vehicleId`, `npcId`, `taskId` and `owner` are strings. Other fields:
`revision`, `epoch`, `mode`, `status`, `reason`, `speed`, `behavior`,
destination `x/y/z`, `routeIndex`, `routeCount`, `targetKind`, `targetId`,
and `distance` (native stopping/follow distance, **not** road-route distance).

Statuses: idle, waiting_for_simulator, running, arrived, cancelled, failed,
detached. `ai.on(event, handler)` delivers a decoded state only to the controller's
resource. Events: `waypointReached`, `arrived`, `cancelled`, `failed`,
`blocked`, `resumed`. Query state initially; events are not replayed.

Blocked/no_progress means less than 2 m movement over 8 seconds, not proof of a
collision. It may be a traffic wait or invalid path. Failures include timeout,
unavailable/cross-bucket target, unavailable driver, destroyed vehicle and native
command failure. Losing a simulator does not permit stale-epoch motion; a
replacement must acknowledge readiness. Human-driven authority is unchanged.


## Networked vehicle AI âº Route integration

Choose destinations on reachable road surfaces and wait for vehicle creation and mounting before issuing a task. Handle `blocked`, `failed` and `waiting_for_simulator` states; a nearby point may not have a valid road path.

