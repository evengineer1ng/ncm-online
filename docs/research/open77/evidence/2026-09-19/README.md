# Evidence captured 2026-09-19 (NCM Online orientation pass)

Read-only captures from the hosted OPEN//77 devkit MCP (`https://mcp.open2077.net/mcp`, unpinned = latest published build) and GitHub. No server was deployed, no experiment run. `query_open77.py` is the helper used (Python, needs a `User-Agent`; the endpoint returns 403 to a bare urllib agent).

| File | What it shows |
|---|---|
| `mcp-build.txt` | Newest published build is still **2.31.13+op77.78**; index regenerated 2026-09-19 (1622 cards / 91 guides — up from 1607 / 90 on 2026-09-18 at the same build). |
| `changes-78-to-main.txt` | 43 natives exist on `main` and in **no published build**: player models (`Open77.players.setModel`), native map tabs (`Open77.map.addTab`), remote cameras (`Open77.remoteCamera.*`). |
| `freeroam-head.txt` | Freeroam/Race HEAD is unchanged since yesterday's pinned inspection (d3f2a7f, 2026-09-09). |
| `Open77.vehicles.adopt.txt`, `Open77.vehicles.setAdoptPolicy.txt` | Vanilla-car adoption exists since .67 (driver-shape 6 m / any 60 m, per bucket). Contradicts the vehicles guide's "does not exist yet" paragraph (`guide-vehicles-closest-stale-adopt-note.md`) — the guide paragraph is stale. |
| `Open77.vehicles.ai.setSpeed.txt`, `guide-vehicle-ai.md` | AI speed is hard-capped at **0.5..55 m/s (198 km/h)**; no headless physics; fleet scale not guaranteed; 64 points per route; behaviors normal/cautious/aggressive only. |
| `guide-vehicles-who-owns-a-car.md` | Authority lease model: `physicsOwner`, `steward`, `aiDriven`, `epoch`, `leaseMs`; `requestAuthority` is a request, never a steal. |
| `guide-vehicles-drivetrain.md` | RPM, gear, throttle, brake, steering, slip ride on owner motion samples; server validates their bounds; observers get them in read-only client snapshots. |
| `guide-server-mods-excerpt.md` | Trust cap: an **unverified** required mod may contain inert data only (`.archive`, `.xl`, `.tweak/.yaml`, engine INI). CET Lua, `.reds`, `.dll` are refused unless that exact hash is verified. Redistribution is a separate axis (player-fetch). |
| `guide-gamemode-kernel.md` | Gamemode contract: re-derive every client-reported condition, "held for N seconds" rules, per-round routing bucket, `TriggerEvent` local to a VM. |
| `guide-state-bags-audience-caps.md` | Player bag is visible to the whole bucket; 64 keys / 16 KiB per bag; 8192 bags. |
| `guide-server-api-ambient-population.md` | Per-bucket `crowd/traffic/police` density; unconfigured bucket has no population. |
| `guide-remote-camera-excerpt.md` | Guide says "available from .82" while newest published build is .78 — documentation ahead of release. |
| `guide-identity.md` | Durable `userId` (Ed25519-certified by the Master) vs per-connection `playerId`. |
| `Open77.ready.txt`, `Open77.tunables.txt`, `Open77.http.txt` | Join-readiness holds; operator tunables with round-boundary promotion; inbound HTTP routes served by a resource (since .73). |
| `Open77.npcs.create.txt` | NPC creation from any `Character.*` record with `appearance`; readiness asynchronous. |
| `namespaces-*.txt`, `server-config-network.txt` | Full namespace inventory per runtime; `maximumPlayers` schema range 1..1024. |
