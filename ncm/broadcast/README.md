# NCM Broadcast (package `ncm-broadcast`)

Race presentation drawn natively in the game's HUD (L235): a name over every race car that is not a player
(Paddock drivers), and an opt-in timing tower for Paddock races and multiplayer sessions. No WebUI page is drawn;
the one hidden transport page belongs to the `ncm_broadcast` resource, inside its own budget of eight surfaces.

| Piece | Where | Job |
|---|---|---|
| `ncm_broadcast.dll` | `red4ext/plugins/ncm_broadcast/` | loopback transport (127.0.0.1:38680-38683); holds the names, the tower and the calibration; seven natives |
| `NcmBroadcast.reds` | `r6/scripts/ncm_broadcast/` | projects each named car with `CameraSystem.ProjectPoint` every frame; draws the tower |
| `NcmBroadcastNatives.reds` | `r6/scripts/ncm_broadcast/` | the natives, **no `module` line** (KB-182) |
| `ncm_broadcast` resource | `ncm/online/resources/ncm_broadcast/` | the transport page, Paddock and session feeds, `/ncm.tower`, `/ncm.names` |

It shares no code, state, port range or package with NCM Carrier, NCM Rig Bridge, NCM Radial, NCM Scanner or
NCM Pace (owner rule: new features ship as new mods).

Build: `tools/build-broadcast.ps1` (C++ tests, the natives/module check, a redscript compile against every installed
script, then the zip). Log: `red4ext/plugins/ncm_broadcast/ncm_broadcast-<pid>.log`; the first projected name writes a
`calibration:` line, and the server's `view` message can correct the projection scale without a rebuild.
