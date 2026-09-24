# Evidence provenance

Captured 2026-09-18. The reports are the durable synthesis; these files help a future agent detect source drift and reproduce API queries. No game/account secrets or user save data were captured.

| File | Origin / scope |
|---|---|
| [ncm-source-inventory.json](ncm-source-inventory.json) | Relative path, line count and SHA-256 for 64 Lua files under the working MT_Ecosystem payload; 54,097 lines. Hashes were checked again after documentation work with no changes. This is not a complete asset/redscript inventory or proof of runtime correctness |
| [freeroam-commit.txt](freeroam-commit.txt) | Public [Open2077/freeroam](https://github.com/Open2077/freeroam) source revision inspected: d3f2a7f96ea3b25a614c0f6892798429d8406b69. Manifest, LICENSE, Race README/server/client/config/geometry/tests and web race view were inspected; no executable source vendored |
| [mcp-build.txt](mcp-build.txt) | Actual `open77_build` response from hosted MCP pinned to 2.31.13+op77.78, including docs/index timestamps |
| [api-availability.json](api-availability.json) | Selected names/runtime/since/permission/source-location metadata from official [open77-devkit](https://github.com/Open2077/open77-devkit) generated cards fetched from main. Metadata snapshot is not an engine source checkout or a guarantee of permission enforcement |
| [Open77.vehicles.ai.followRoute.txt](Open77.vehicles.ai.followRoute.txt) | Actual pinned server API card, requested through `open77_api` |
| [Open77.vehicles.setPerformance.txt](Open77.vehicles.setPerformance.txt) | Actual pinned server API card; ceiling semantics/limits |
| [Open77.vehicles.get.txt](Open77.vehicles.get.txt) | Actual pinned server API card; owner-reported motion and no-owner behavior |
| [Open77.players.teleport.txt](Open77.players.teleport.txt) | Actual pinned server API card; description/permission metadata conflict preserved |

Official MCP endpoint: `https://mcp.open2077.net/mcp?build=2.31.13%2Bop77.78`. JSON-RPC method `tools/call`, tool `open77_api`, arguments `{ "name": "Open77.vehicles.get", "runtime": "server" }`. Use [the helper](../query_open77.ps1) or an equivalent read-only MCP client. The response uses SSE `data:` envelopes. Recheck `tools/list` rather than assuming every tool's argument schema. The helper has not been installed or registered as an agent integration; local execution policy prevented direct script launch, and no policy was changed.

The official devkit is MIT licensed; retain upstream attribution when redistributing its material. Freeroam/Race has a different PolyForm Noncommercial license. NCM has published custom Nexus permissions; see the architecture report. These are separate provenance chains.

Large downloaded guide/card bundles and pinned Race files were inspected in a temporary directory and are not needed to understand the assessment. Re-fetch from primary links when deeper implementation investigation is needed; do not depend on another session retaining temp files.
