# NCM Radial

The NCM quick menu, drawn natively on the HUD. Hold the quick-menu key (keyboard, default **B**) or button
(controller, default **Start**), point with a stick, WASD/arrows or a mouse flick, and release. Left click or
pad A confirms early. Releasing on nothing closes the wheel and runs nothing.

This package is a **renderer**. It decides nothing:

| Piece | Where | Job |
|---|---|---|
| `ncm_radial` resource | `ncm/online/resources/ncm_radial/` | reads input, decides open/aim/selection, sends state |
| `ncm_radial.dll` | this plugin | loopback transport (127.0.0.1:38560-38563) + two string natives |
| `ncm_radial.reds` | `r6/scripts/ncm_radial/` | draws the wheel inside the vanilla `RadialWheelController` |
| `ncm_world` | `client/quick_actions.lua` | runs the chosen action through its hotkey's own function |

It shares no code, state, port range or package with NCM Carrier or NCM Rig Bridge. It only borrows their
vendored third-party headers (RED4ext.SDK, nlohmann/json) at build time.

## Safety

- **A dropped socket closes the wheel.** If the resource stops or the page dies, the wheel cannot stay on screen.
- **A stale feed closes the wheel.** The resource sends a frame every tick while the wheel is open; after 1.5 s
  without one, the plugin reports it closed. `/ncm.radial` shows `staleClosed=true` when that has happened.
- **Only this game's process tree may connect.** A second game instance on the same PC walks to the next port.
- **The vanilla wheel's children are hidden while NCM's is up and restored exactly on close.** OPEN//77 claims
  the vanilla weapon wheel, so the two are never meant to be open together.

## Diagnostics

- `ncm_radial-<pid>.log` beside the DLL: port, host attach (`host=RadialWheelController drawn=1`), connections.
- `/ncm.radial` in game: transport, plugin version, host, bindings, and what `setActionBlocked` returned.
- `/ncm.radial input`: three seconds of raw stick / mouse-delta readings.
- `/ncm.radial pad <control>`: set the controller button if the platform refuses a pad control as a mapping.

## Build

`powershell -File tools\build-radial.ps1` builds, runs the state tests, compiles the redscript against the
vanilla bundle and the installed OPEN//77 scripts in a scratch cache, and writes `dist/ncm-radial-<version>.zip`.
