# NCM Rig Bridge

NCM Rig Bridge is a dedicated in-process RED4ext mod for physical driving rigs. It does not use a virtual
gamepad and it does not depend on NCM Carrier. DirectInput devices are read at 250 Hz, merged into the local
player vehicle after the game's own input pass, and force feedback is written to the selected DirectInput
device under an explicit arm switch and watchdog.

It is vendor-neutral: Logitech, MOZA, Thrustmaster, Fanatec and custom USB controllers are treated as
DirectInput endpoints rather than as brand-specific products. Steering, throttle, brake and clutch may each
come from a different device. Stable DirectInput instance GUIDs are the preferred bindings; product-name
matching is a convenience fallback.

## Configuration

`ncm_rig_bridge.json` lives beside the DLL. Start once, then read `ncm_rig_bridge-<pid>.log` for every device's
stable GUID and product name. Put the GUID on each axis binding. Supported axis names are `x`, `y`, `z`, `rx`,
`ry`, `rz`, `slider0`, and `slider1`. `minimum` and `maximum` calibrate the physical axis in normalized 0..1
space. Separate pedals are expected and supported.

Buttons may map to game key bindings through entries such as:

```json
{ "deviceGuid": "{...}", "button": 4, "virtualKey": 67, "vehicleOnly": true }
```

`virtualKey` is a Windows virtual-key value. Key-up is always sent during teardown.

## Force feedback

Force feedback starts disarmed. Arm it from NCM's WHEEL panel after confirming the named device, beginning at
the lowest rung. The effect watchdog releases every force if current in-vehicle telemetry stops for 250 ms.

Four effects run, matching the four the NCM Wheel Support companion established on real hardware:

| Effect | Carries |
|---|---|
| `SPRING` | centring stiffness |
| `DAMPER` | resistance to being whipped around |
| `CONSTANT` | self-aligning torque, plus collision jolts from `OnVehicleBumpEvent` |
| `SINE` | road texture: suspension movement, tyre slip and engine hum, at a rev-modulated 12-47 Hz |

Centring survives on steering and speed alone, so the wheel stays alive if the telemetry feed drops.

### `deviceClass` is a safety setting, not a label

`strength` is a fraction of *your device's own maximum*, and the ceiling it is clamped to comes from
`deviceClass`:

| Class | Ceiling |
|---|---|
| `gear` | 0.24 |
| `belt` | 0.20 |
| `direct_drive` | 0.06 |
| `unknown` (default, and any unrecognised value) | 0.04 |

These were measured on a G29 on 2026-09-24 and mirror `ncm/core/driver/feedback.lua`. `unknown` is the
**lowest** ceiling of the four, because a device that has not been identified is assumed to be the most
powerful thing it could be. Declaring a class you do not have raises the ceiling on your own hardware.

At teardown the log prints the peak each channel reached over the session. A channel that peaked near zero
was inaudible for the whole drive, which is the measurement that tells you what to tune.

## Why this is separate

Rig Bridge replaces the external `NCM Wheel Support.exe` companion: same feel model, same ladder, in-process
and with no second executable to launch. It owns only local hardware, local player input and local feel, on
its own loopback port range, and can fail, update or be removed independently of anything else.

## Source lineage

The player-vehicle detour and DirectInput approach were validated against the MIT-licensed
`clevergrant/cp2077-wheel-mod`, `natpoh/cp2077-wheel-mod-moza`, and `jackhumbert/custom_game_controller`
projects. This implementation is new NCM code; their licenses and attribution are recorded in
`THIRD_PARTY_NOTICES.md`.

