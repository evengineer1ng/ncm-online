# The gamemode kernel and shared server services › The gamemode kernel and shared server services

Organize gamemode rules in server resources and expose reusable services through [server exports](server-exports.md). Open77 does not ship a universal `open77_gamemode` resource.

Keep tightly coupled match state in one resource. Extract reusable services when they need an independent lifecycle and a clear request interface.


## The gamemode kernel and shared server services › Shared server resources are supported

The server runtime now provides `exports(name, fn)`,
`Open77.exports.call(resource, name, ...):await()`, `GetInvokingResource()` and
generation identity. See [server exports](server-exports.md) for a runnable
two-resource example and the precise lifecycle contract.

Shared services can own scores, lobbies or bucket allocation. Values cross resource boundaries by copy. Synchronous exports must not yield; asynchronous calls are deferred and awaited. Validate callers and arguments, and keep state changes atomic before yielding.

`TriggerEvent` remains local to a VM. The host still fans lifecycle/player events
into resources. Export registration does not create a network entry point.
Client services such as `open77_zones` and `open77_worldui` remain client-only
packages; adding server exports does not move their presentation logic to the server.


## The gamemode kernel and shared server services › The scaffolder remains useful

`scripts/new-resource.ps1 -Kind gamemode` creates a resource with a guarded state machine, reload-safe roster handling and a `<name>.status` command.

Use generated code for tightly coupled state-machine rules, and server exports
for reusable services with a clear ownership boundary. See
[writing a gamemode](../docs/writing-a-gamemode.md) section 7. No forced migration
or new dependency is added to existing gamemodes by the runtime change.


## The gamemode kernel and shared server services › The contract every gamemode's server should implement

Apply these lifecycle and authority conventions to each gamemode. See [Writing a gamemode](writing-a-gamemode.md) for examples.

| Convention | Why | Where it lives |
|---|---|---|
| **Reload-safe roster adoption.** Use `Open77.players.all()` for the current roster and retain lazy `ensurePlayer` handling at player-event boundaries. | A reload must not lose track of connected players. | `ensurePlayer` in `resources/gamemodes/pursuit/server/main.lua` and `resources/gamemodes/race/server/main.lua` |
| **`tonumber` every player ID.** IDs arrive from net events and lifecycle handlers as strings. | A raw string key silently diverges from the numeric IDs used everywhere else. | Every `AddEventHandler("onPlayer...", ...)` in both resources |
| **Guarded state transitions, one function.** A single `transition(playerId, target, detail)` that checks an explicit table of allowed edges and logs a refusal instead of corrupting state. | An invalid transition is more useful as a log line than as silent corruption. | `transition` in both resources |
| **Move players with `Open77.players.teleport`.** Never a raw transform write. Kill -> respawn was the ONLY placement primitive before `teleport` existed -- `Open77.players.respawn` refuses unless the player is already dead -- and the modes that still do it are unconverted, not exemplary. | A raw transform write over distance drops the player into unstreamed world and the engine's fall-under-world failsafe silently returns them to the save's spawn. `teleport` carries the fade and waits for the client to report the body settled, without costing a death. | `placeAt` in both resources (kill -> respawn, pre-`teleport`); [Moving a player](server-api.md#moving-a-player) |
| **Re-derive every client-reported condition on the server.** A zone `enter` event, a checkpoint claim, a queue intent -- all are hints. Re-check them against `Open77.players.position` with a few metres of grace before granting anything. | The client is never the authority (writing a gamemode, section 4). | `containsPlayer` (Pursuit) / `checkpointReached` (Race) |
| **Never judge a single position sample.** Every rule is "held continuously for N seconds," evaluated on a fixed tick; an unreadable position freezes an accumulator, never resets it. | `Open77.players.position` is a replicated snapshot, not a live read (writing a gamemode, section 2.5). | Pursuit's win-condition tick; Race's per-second heat-state check |
| **One `<mode>.where`-style diagnostic, early.** Print exactly what the server sees for one player -- position, bucket, the rule's own verdict and reason. | Nearly every confusing failure in this project was answered in one line by such a command (writing a gamemode, section 6). | `pursuit.where`, `race.where` |
| **Isolate a round in its own routing bucket.** Allocate from a reserved range, disable ambient population, release on resolution. | Two rounds must never see each other, and neither should inherit the lobby's crowd. | Pursuit's per-match bucket pool; Race's single heat bucket |


## The gamemode kernel and shared server services › What this means for a new mode

Run the scaffolder and build the state machine your mode needs. Extract a
reusable service when its contract justifies a separate lifecycle; declare the
dependency for startup ordering and use generation-bound server exports to call
it. Keep player readiness and authority checks intact across the new boundary.
Existing shared client presentation services are documented separately:

- [Proximity zones](zones.md) (`open77_zones`)
- [World-anchored POIs](worldui.md) (`open77_worldui`)

