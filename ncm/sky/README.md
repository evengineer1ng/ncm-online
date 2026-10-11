# NCM Sky (package `ncm-sky`)

The universe drawn in REDengine with full orientation (KB-430). Open77 props take a position and a yaw only, so an
Earth that turns under the Machine, or a sky that turns with the clock, cannot be a prop. NCM Sky draws those bodies
itself and turns them on every axis.

| Piece | Where | Job |
|---|---|---|
| `NcmSky.reds` | `r6/scripts/ncm_sky/` | each tick: spawn, turn and move the bodies the scene names; remove the rest |
| `ncm_sky.dll` | `red4ext/plugins/ncm_sky/` | loopback transport (127.0.0.1:38760-38763) + three natives |
| `ncm_sky.archive` | `archive/pc/mod/` | the body templates, authored from the game's own q201 Earth at build time |
| `ncm_sky` resource | `ncm/online/resources/ncm_sky/` | decides the scene from NCM's state and sends it |

It shares no code, state, port range or package with NCM Carrier, NCM Rig Bridge, NCM Radial or NCM Scanner.

## Safety

- **Nothing outlives the feed.** A dropped socket or a stale feed (3 s) empties the scene, and redscript removes
  every body. So does the player detaching.
- **Only its own templates.** A kind the script's table does not name is refused and reported, never guessed.
- **Inside the world box.** The DLL refuses any position beyond 16,000 m on any axis (KB-411).
- **Only this game's process tree may connect.** A second game instance on the same PC walks to the next port.

## Diagnostics

`ncm_sky-<pid>.log` beside the DLL: port, natives, `reds:` lines, each body's spawn / move / refusal.

## Build

`powershell -File tools\build-sky.ps1`: the DLL, the state tests, the native-declaration check, a redscript compile
against vanilla plus every installed script in a scratch cache, the templates (WolvenKit), and
`dist/ncm-sky-<version>.zip`.
