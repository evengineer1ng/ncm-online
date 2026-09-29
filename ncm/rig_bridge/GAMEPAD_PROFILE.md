# NCM Rig Bridge — gamepad profiles

The gamepad layer is a C++ port of **JoyMoCo** and reads JoyMoCo **profile format v1** unchanged. This file
lists only what Rig Bridge adds or changes. Everything else — staged and threshold gestures, macros,
`hold_until_release`, stick / `gyro_analog` / `pose_stick` mappings, `gyro_steering`, calibration,
filtering, `rumble` and `rumble_effects` — behaves as JoyMoCo's `PROFILE_FORMAT.md` describes.

## Where profiles live

- `profiles/<name>.json` beside `ncm_rig_bridge.dll` are **yours**. The panel's Save writes them; Load reads
  any of them. `profiles/active.txt` names the one loaded at start.
- `profiles/_shipped/default.json` ships with the plugin and is replaced on every update. On first launch
  it is copied to `profiles/default.json`, which is then yours and is never overwritten.

## Additions to JoyMoCo v1

**Device sources.** A condition's `controller` (and a `hold_until_release` gate's) may name a device, not
only a JoyMoCo hand:

| Source | Meaning |
|---|---|
| `left`, `right`, `primary`, `left_leg`, `right_leg`, `controller` | JoyMoCo hands (Joy-Cons, DualSense, Switch Pro) via SDL3 |
| `joystick:<serial or name>` | any SDL3 plain joystick — e.g. `joystick:Evenracing 1.0.0` (the ESP32 rim) |
| `di:<VID:PID>` | any DirectInput device the Rig Bridge polls — e.g. `di:046D:C24F` (G29) |
| `<prefix>:*` | first source whose key starts with `<prefix>:` |

A device's buttons are `b0`, `b1`, … (0-based); hats are `hat<n>_up`, `hat<n>_right`, `hat<n>_down`,
`hat<n>_left`; axes read as `field: "axis<n>"`, normalised −1..1.

**Context.** Every gesture (variant), mapping and `gyro_steering` may carry
`"context": "both" | "driving" | "on_foot"` (default `both`). Driving means the player is mounted. A variant
whose context stops applying releases its hold at once.

**Stick `auto`.** A `stick` mapping's `"stick": "auto"` reads whichever of the source's two stick pairs is
deflected further — how SDL reports a solo Joy-Con's stick depends on its orientation.

**XInput slot.** `"xinput": {"user_index": 0}` is the XInput slot the virtual pad merges into. Buttons OR with
the physical pad; each stick axis and trigger takes whichever is deflected further. The Xbox pad itself is
never a source: it reaches the game natively.

## What JoyMoCo does that the game does differently

There is no ViGEm virtual controller. The virtual pad is merged into the game's own `XInputGetState`, so it
reaches Cyberpunk 2077 and nothing else. The game's rumble on that slot (`XInputSetState`) goes to the
Joy-Cons: large motor → left hand, small → right, scaled by `rumble.scale`, when `rumble.game_generated`.
