# server Open77.vehicles.create(definition: table)

Creates a server-authoritative network vehicle.

Requires `world.vehicles`. The definition selects the record, transform, routing bucket, appearance, optional authoritative paint, flags, health, and initial damage. The server allocates the Open77 ID and replicates the canonical vehicle to interested clients. The creator name is retained as provenance and cleanup scope, never as an exclusive mutation lock. The definition also takes the three lifetime keys `ttlMs`, `persistent` and `despawnWhenUnobserved`, so a garage does not need a second call; a definition without them behaves exactly as it did before, and a lifetime that cannot be applied undoes the creation rather than half-honouring it -- the same rule the initial-damage path already follows.

- runtime: server (network)
- permissions: world.vehicles
- since: 2.31.13+op77.45
- reasons it can return: initial_damage_failed, permission_denied:world.vehicles, vehicles_unavailable
- returns: vehicle ID, or `nil, reason`
- guides: armed-vehicles#spawn-a-network-vehicle, data-reference#vehicle-models, vehicle-ai#autonomous-vehicle, vehicle-paint#initial-paint-during-creation, vehicles#server-api, vehicles#vehicle-properties-and-what-cyberpunk-does-not-have

```lua
-- /car: spawn a Quadra a few metres in front of the caller and put them in the driver seat
RegisterCommand("car", function(source)
    local me = Open77.players.get(source)
    if not me or not me.position then return end
    local id, reason = Open77.vehicles.create({
        record = "Vehicle.v_sport1_quadra_turbo_r_player",
        position = { x = me.position.x + 4.0, y = me.position.y, z = me.position.z },
        yaw = me.heading,
        ttlMs = 30 * 60 * 1000, -- gone after 30 minutes if nobody removes it
    })
    if not id then return Open77.chat.send(source, "Spawn failed: " .. reason) end
    Open77.vehicles.warpPlayerIntoVehicle(source, id, Open77.vehicles.seats.driver)
end, false)
```

_answering for build 2.31.13+op77.78 (no index published for 2.31.13+op77.87; serving 2.31.13+op77.78, the newest at or below it)_