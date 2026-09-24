### Network vehicles › Who owns a car

`Open77.vehicles.owner(id)` answers FiveM's `NetworkGetEntityOwner` with more than a number,
because the lease has more than one shape. It requires `world.vehicles` and answers `nil, reason`
for an unknown id.

| Field | Meaning |
|---|---|
| `physicsOwner`, `authorityPlayerId` | The client simulating the car; `0` when parked. Both names carry the same value -- the vehicle read has always said `physicsOwner`, the NPC read says `authorityPlayerId`, and a script reading both should not learn two words. |
| `driver` | The seated controller -- the front-left occupant, or any occupant of an AV -- **whether or not** they own the lease. Absent when nobody is. |
| `steward` | The owner holds the lease without being the driver: the parked-car simulation the platform hands to the nearest occupant, or a script's own grant. |
| `aiDriven` | An NPC drive task holds the lease. |
| `epoch` | The authority epoch that owner holds. |
| `since`, `ageMs` | When the owner last changed, on the `GetGameTimer()` clock, and how long ago that was. |
| `reason` | Why it last changed: `driverclaim`, `driverrelease`, `leaseexpired`, `playerdisconnected`, `validationfailed`, `serverrevoke`, or `none` for a platform steward grant and for a car nobody has owned yet. |
| `leaseMs` | How long the current lease still has, when there is one. |

```lua
-- A speed camera only trusts a car somebody is actually driving.
local owner = Open77.vehicles.owner(id)
if owner and owner.driver and not owner.aiDriven then
    fine(owner.driver, Open77.vehicles.getSpeedKph(id))
end
```

`Open77.vehicles.requestAuthority(id, playerId)` is `NetworkRequestControlOfEntity` as a
**request**. It returns the owner table after the grant, or `nil, reason`, and the reasons are the
election's own eligibility made explicit:

| Reason | Means |
|---|---|
| `driven` | Somebody else is the seated controller. A driven car is never taken from its driver -- this is the rule that makes the call a request rather than an order. |
| `ai_driven` | An NPC drive task holds the lease; re-granting it would strand the task. |
| `not_streamed` | The player has no body for this car yet. A client cannot simulate what it has not spawned. |
| `too_far` | Beyond the 350 m stream-in radius. |
| `wrong_bucket` | The player is in another routing bucket. |
| `player_unavailable` | No fresh position for the player -- the same two-second rule every claim applies. |
| `already_owner` | Not a refusal: the call returns the read, and nothing is re-granted. |
| `invalid_player_id`, `vehicle_not_found` | The usual. |

The requested player being the driver already is the one case that is not a steal, and it is
granted. A grant is a lease like any other: the client keeps it by reporting, which its parked-pose
loop does twice a second once the car has been attached for five seconds, so a grant to a client
that has only just streamed the car in can lapse two seconds later -- and `owner` then says so.
That is what a lease is, not a defect of the request.

```lua
-- Hand a parked car to the player who just bought it, so their client simulates it
-- while they walk around it. Refused by name if somebody is sitting in it.
local read, reason = Open77.vehicles.requestAuthority(id, buyerId)
if read == nil then print("not yet: " .. reason) end
```

There is no `Open77.vehicles.entity(id)`: the client's `Open77.vehicles.get(id).entity` **field**
is the REDengine entity, and `Open77.vehicles.fromEntity(entity)` is the way back, which is all
`NetworkGetNetworkIdFromEntity` ever needed. NPCs have the same read, `Open77.npcs.owner(id)`, in
the same shape (`authorityPlayerId`, `physicsOwner`, `epoch`, `since`, `ageMs`, `reason`,
`leaseMs`, plus `readyClients`, the election's candidates) and no request: an NPC's authority is
elected from the clients whose projection reported ready, and a script has no better information
than the election about which of them should simulate a body.

_natives: server:Open77.vehicles.owner, server:Open77.vehicles.getSpeedKph, server:Open77.vehicles.requestAuthority_
