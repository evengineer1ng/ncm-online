# server Open77.players.get(playerId: integer)

Everything the host can answer about one player synchronously, with a dated transform.

No permission. The one read a job script makes before it acts. Unlike `Open77.players.position` it never goes quiet on a stale snapshot: it reports `ageMs` and `fresh` and lets the caller pick its own threshold -- `fresh` is true precisely when `position` would have answered, so the old semantics are still reachable from one reading. Always present: `playerId`, `bucket`, `fresh`, `ready`. Present once the player has reported: `ageMs`, `position` `{ x, y, z }`, `heading` (alias `yaw`), `velocity` `{ x, y, z }`, `speed`, `stateFlags`, `flags`, and `supportKind`/`supportId` on a moving support. Present when the host can resolve them: `name`, `identifier`, `userId`. A player who has never sent an accepted snapshot has no `position` and no `ageMs` at all, which is distinguishable from a reading that is merely old. Health (`players.stats.read`), life (`players.life.read`) and vehicle seat (`world.vehicles`) fields are **absent rather than false** without the permission that already guards `getHealth`, `getLifeState` and `getVehicleSeat`. See [the rich read](server-api.md#the-rich-read-and-the-freshness-decision).

- runtime: server (network)
- permissions: none checked in the handler
- since: 2.31.13+op77.67
- reasons it can return: invalid_player_id, player_not_found, sessions_unavailable
- returns: table, or nil; reason: invalid_player_id, player_not_found, sessions_unavailable
- guides: player-freeze#a-ragdoll-is-the-knockdown-with-a-clock, server-api#the-rich-read-and-the-freshness-decision

```lua
local read = Open77.players.get(playerId)
if read and read.position and (read.ageMs or 0) < 5000 then
  -- your freshness threshold, not ours
end
```

_answering for build 2.31.13+op77.78 (no index published for 2.31.13+op77.87; serving 2.31.13+op77.78, the newest at or below it)_