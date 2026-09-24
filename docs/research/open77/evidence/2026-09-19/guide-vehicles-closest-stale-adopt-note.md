### Network vehicles › What `closest` can and cannot find

**Only server-spawned vehicles are in the registry.** A player who walks up to a vanilla traffic
car is standing next to something REDengine population spawned on their own client: it has no
canonical id, no replica, and no entry in any of these calls. `closest()` will happily answer with
a registered car forty metres away while the player leans on a taxi, and that is the expected
behaviour rather than a bug.

Two consequences a server creator will otherwise trip over:

- a resource that must not act on the wrong car has to check `distance` itself, because "nearest
  registered" is not "nearest";
- `Open77.vehicles.aimed()` answers `unknown_entity` far more often than `no_target`. The player
  really is looking at a car; that car is simply traffic nobody created.

Adopting vanilla traffic into the registry is a separate capability that does not exist yet.

