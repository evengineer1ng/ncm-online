## Complete server Lua API › Ambient population

`Open77.world.setPopulation` requires `world.population`; `getPopulation` is ungated.

An unconfigured bucket has no ambient crowd, traffic or police. Enable population explicitly with the density settings or `bucket.population <bucket> on`.

| Function | Signature | Purpose |
|---|---|---|
| `Open77.world.setPopulation` | `(bucket, { crowd?, traffic?, police? })` | Ambient density for one routing bucket, replicated to every client in it. |
| `getPopulation` | `(bucket)` | Read it back, including what the engine can actually apply. |

```lua
-- An empty staging instance, with no cops to wander into it.
Open77.world.setPopulation(4, { crowd = 0, traffic = 0, police = false })

-- Half the usual pedestrians, vanilla traffic.
Open77.world.setPopulation(0, { crowd = 0.5, traffic = 1, police = true })
```

_natives: server:Open77.world.setPopulation_
