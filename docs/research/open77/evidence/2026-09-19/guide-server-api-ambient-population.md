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

---

**Note added 2026-09-27 (`KB-164`, `L177`).** This capture was correct and was read as narrower than it is. Two
things it already implies, now confirmed against the shipped `2.31.13+op77.102` prelude and stated here so they
cannot be missed again:

* **This switch is the server's.** The prelude's own words: *"Server-owned and replicated to every client in
  that bucket; the client half is read-only."* `crowd` is a continuous multiplier; `traffic` and `police` are
  binary on 2.31, and `getPopulation` returns `trafficGranularity = "binary"` to say so.
* **It is per bucket and never per radius.** `Open77.world.clearArea`'s `population = true` refuses without one
  (`bucket_required_for_population`) for exactly this reason.

What it does *not* give you is control of an individual vanilla entity: those are spawned per client and have no
canonical id. NCM's race-corridor clearing therefore works on its own server-created NPCs and vehicles - see
`L177` and `ncm_world/server/ambient.lua`.
