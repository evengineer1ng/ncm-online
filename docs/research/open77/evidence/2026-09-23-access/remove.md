# server Open77.vehicles.remove(id: integer)

Removes a server-authoritative network vehicle.

Requires `world.vehicles`. Any authorized resource may remove any canonical vehicle, regardless of which resource created it. Removal clears occupancy and authority before notifying streamed clients.

- runtime: server (network)
- permissions: world.vehicles
- since: 2.31.13+op77.45
- reasons it can return: none found in the handler; a refusal it forwards from a callee may still reach you as a second return value
- returns: boolean success
- guides: vehicles#other-server-calls

```lua
-- /dv: delete the vehicle the caller is sitting in
RegisterCommand("dv", function(source)
    local seat = Open77.vehicles.getPlayerSeat(source)
    if not seat then return Open77.chat.send(source, "You are not in a vehicle.") end
    Open77.vehicles.remove(seat.vehicleId)
end, true)
```

_answering for build 2.31.13+op77.78 (no index published for 2.31.13+op77.87; serving 2.31.13+op77.78, the newest at or below it)_