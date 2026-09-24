# client Open77.world.raycast(from: table { x, y, z }, to: table { x, y, z }, options?: table { static?, dynamic?, entities? })

Traces a physics ray between two world points and returns the nearest blocking surface.

Runs `gameSpatialQueriesSystem::SyncRaycastByCollisionGroup`, the same native the combat and camera code use, against the `Static` and `Dynamic` collision groups and keeps the nearer hit. `options` may disable either group (`{ static = true, dynamic = false }`). The result is what the engine's trace publishes: position, surface normal, material name and distance. With `options.entities = true` it also carries `entity` when the ray stopped on an object rather than on world geometry: `engineEntity`, `className`, `kind`, `position`, `distance`, and one of `playerId`, `vehicleId` or `npcId` when Open77 owns the thing. Without that option the returned table is unchanged, so existing resources are unaffected. The entity is not read out of the trace, which carries none: the object standing at the hit point is found with the same object search `Open77.world.nearest` uses, so the search is centred on the local player and a hit more than 250 m away cannot be attributed. A hit on a wall, a road or a railing has no entity at all, which is the ordinary answer and not an error. Synchronous, on the game thread; requires the `world.query` permission.

- runtime: client (game)
- permissions: world.query
- since: 2.31.9+op77.22
- reasons it can return: invalid_from, invalid_to, permission_denied:world.query
- returns: table { hit, position { x, y, z }, normal { x, y, z }, material, distance, entity? } (position, normal, material and distance only when hit is true; entity only when options.entities is set AND the ray stopped on an object), or nil; reason: permission_denied:world.query, invalid_from, invalid_to, ray_entities_unavailable_on_this_host, world_unavailable_on_this_host, or the engine status
- guides: world-queries#what-the-ray-hit

```lua
-- Is there a wall between the player and the target point?
local from = Open77.character.state().position
local hit = Open77.world.raycast(from, target)
if hit and hit.hit and hit.distance < #(vector3(target) - vector3(from)) then
    print("blocked by", hit.material, "at", hit.distance, "m")
end
```

_answering for build 2.31.13+op77.78 (no index published for 2.31.13+op77.87; serving 2.31.13+op77.78, the newest at or below it)_