# server Open77.vehicles.all(bucket?: integer)

Lists authoritative server vehicles.

Returns snapshots ordered by Open77 ID. An optional routing bucket filters the result; omitting it returns every vehicle visible to the resource.

- runtime: server (network)
- permissions: world.vehicles
- since: 2.31.13+op77.45
- reasons it can return: none found in the handler; a refusal it forwards from a callee may still reach you as a second return value
- returns: array of vehicle tables
- guides: vehicles#other-server-calls, vehicles#client-api

```lua
-- /cars: how many server vehicles exist, and how many in the caller's bucket
RegisterCommand("cars", function(source)
    local everywhere = Open77.vehicles.all()
    local here = Open77.vehicles.all(Open77.players.get(source).bucket)
    Open77.chat.send(source, ("%d vehicles on the server, %d in your instance"):format(#everywhere, #here))
end, true)
```

_answering for build 2.31.13+op77.78 (no index published for 2.31.13+op77.87; serving 2.31.13+op77.78, the newest at or below it)_