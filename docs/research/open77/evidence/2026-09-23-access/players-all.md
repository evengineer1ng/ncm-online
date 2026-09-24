# server Open77.players.all()

Every authenticated player id, ascending.

No permission. `GetPlayers` is the same function. This is the host's roster, so a gamemode no longer needs its own copy assembled from join and leave events.

- runtime: server (network)
- permissions: none checked in the handler
- since: 2.31.13+op77.45
- reasons it can return: none found in the handler; a refusal it forwards from a callee may still reach you as a second return value
- returns: array of player ids
- guides: client-players#alloptions, client-players#relation-to-the-server-api, player-stats#fall-damage

```lua
-- Announce a restart to everyone currently connected
RegisterCommand("announce", function(source, args)
    local text = table.concat(args, " ")
    for _, playerId in ipairs(Open77.players.all()) do
        Open77.notifications.send(playerId, { type = "warning", message = text })
    end
end, true)
```

_answering for build 2.31.13+op77.78 (no index published for 2.31.13+op77.87; serving 2.31.13+op77.78, the newest at or below it)_