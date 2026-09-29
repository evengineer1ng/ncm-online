# NCM Scanner (package `ncm-vision`)

The vanilla scanner's green render and a native reticle in NCM Online, without the scanner (`L196`, `L197`).

- **Hold Tab** for green while held; **tap Caps Lock** to toggle. These are the game's own Vision Hold and
  Vision Toggle bindings, so rebinds carry over. It works on foot and while driving.
- **No scan HUD, no walk-only restriction, no slow motion.** Only `VisionModeSystem.EnterMode(player, Focus)`
  is called; the scanner controller that OPEN//77 refuses is never touched.
- **Machine discovery.** While vision is on, keep an NCM machine in the reticle for about 1.5 s within 60 m to
  identify it. The `ncm_scanner` resource runs the lock and the server decides what you learn.

| Piece | Where | Job |
|---|---|---|
| `NcmVision.reds` | `r6/scripts/ncm_vision/` | green on Tab / Caps Lock, and the look-at report while it is on |
| `NcmScannerReticle.reds` | `r6/scripts/ncm_vision/` | the reticle, drawn in the vanilla crosshair container |
| `ncm_vision.dll` | `red4ext/plugins/ncm_vision/` | loopback transport (127.0.0.1:38600-38603) + three natives |
| `ncm_scanner` resource | `ncm/online/resources/ncm_scanner/` | reads the target, runs the lock, tells the reticle what to say |
| `ncm_league` | `server/collection.lua` | the only place a scan becomes an identity reveal |

It shares no code, state, port range or package with NCM Carrier, NCM Rig Bridge or NCM Radial. It borrows only
their vendored third-party headers (RED4ext.SDK, nlohmann/json) at build time.

## Safety

- **No work while vision is off**, beyond two input listeners. The report tick exists only while the render does.
- **A dropped socket or a stale feed (1.5 s) clears the reticle's text.** The green and the bare brackets stay,
  because they belong to the player's key, not to Lua.
- **Only this game's process tree may connect.** A second game instance on the same PC walks to the next port.
- **The key is never consumed.** OPEN//77 WebUI and resource key mappings still receive Tab.

## Diagnostics

- `ncm_vision-<pid>.log` beside the DLL: port, natives, `reds:` lines (reticle attach), connections.
- `/ncm.scanner` in game: transport, plugin version, the current report, and `aimedEntity` for comparison.

## Build

`powershell -File tools\build-vision.ps1` builds the DLL, runs the state tests, compiles both scripts against the
vanilla bundle and every installed script in a scratch cache, and writes `dist/ncm-vision-<version>.zip`.
