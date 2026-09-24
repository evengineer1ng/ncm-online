# client Open77.character.state(entity?: entity id, or table { engineEntity, radius? })

One complete snapshot of a character.

A single engine pass fills the whole record even when the caller only wanted the speed. That is deliberate: every field then describes the **same instant**, so a caller cannot see a body grounded and airborne in the same breath.

With no argument, answers about the local player. An integer is an **Open77 entity id**.

A table `{ engineEntity = n, radius? }` reads a body Open77 does **not** own -- a vanilla population ped, a traffic car -- addressed by its engine id, because it has no Open77 id to address it with. Those answers carry `source = "observed"` and `owned = false`, `id` is 0, and only what can be read straight off the object is filled in: placement, orientation and health. Locomotion, weapon and vehicle state come from Open77's own replication and are left unset rather than guessed at. The body is located among what is streamed around the local player, so `entity_not_observed` means "not in view from here", which for a vanilla ped is an ordinary outcome and not an error. There is no write counterpart: every mutator is keyed by an Open77 id and answers `npc_not_found` for one of these.

- runtime: client (game)
- permissions: none checked in the handler
- since: 2.31.0+op77.3
- reasons it can return: none found in the handler; a refusal it forwards from a callee may still reach you as a second return value
- returns: table { isPlayer, attached, id, engineId, position, orientation, forward, velocity, speed, groundSpeed, yaw, alive, health, grounded, crouched, sliding, vaulting, air, fall, landing, weaponÃ¢â¬Â¦, inVehicle, seat, driver }; reason, when the first is nil
- guides: README#create-a-resource, client-players#entityplayerid-and-fromentityentityid, clipboard#copy-a-character-transform-from-your-own-resource, debug-runtime#admin-command, world-queries#what-is-it-and-is-it-ours, zones#the-shared-module

```lua
local s = Open77.character.state()
if s.inVehicle and s.driver then
    print("driving at " .. math.floor(s.speed) .. " u/s")
end
```

_answering for build 2.31.13+op77.78 (no index published for 2.31.13+op77.87; serving 2.31.13+op77.78, the newest at or below it)_