---
title: Wheel & Rig Support
description: NCM Rig Bridge brings DirectInput wheels, pedals and custom rigs with force feedback to NCM Online. What has been tested, what should work, and what doesn't.
status: live
---

# Wheel & Rig Support

You do **not** need a wheel. Keyboard and controller are fully supported. If you have a wheel, NCM supports it
through **NCM Rig Bridge**, a native plugin the launcher installs with NCM's other required mods.

## What Rig Bridge does

- Reads **DirectInput** devices at 250 Hz and merges them into your car after the game's own input pass. There is no
  virtual gamepad.
- **Vendor-neutral:** Logitech, MOZA, Thrustmaster, Fanatec and custom USB controllers are all DirectInput devices.
- **Mix and match:** steering, throttle, brake and clutch can each come from a different device. Separate pedals are
  expected.
- **Buttons** can be mapped to game key bindings.
- **Force feedback** with four effects: centring spring, damper, self-aligning torque plus collision jolts, and road
  texture (suspension, tyre slip, engine). Centring survives on steering and speed alone, so the wheel stays alive if
  telemetry drops.

## Safety first

- **Force feedback starts disarmed.** Arm it from F6 → **DEVICES** after confirming the named device, starting at the
  lowest strength.
- **A watchdog releases every force** if in-vehicle telemetry stops for 250 ms.
- **Strength is capped by device class.** The ceiling is a fraction of your device's own maximum: gear 0.24, belt
  0.20, direct drive 0.06, and unknown 0.04. Unknown gets the lowest cap on purpose: an unidentified device is
  assumed to be the most powerful thing it could be. Declaring a class you don't have raises the ceiling on your
  own hardware.

## Setting it up

F6 → **DEVICES** shows steering, throttle, brake and clutch, force feedback and gamepad settings. Advanced
configuration is in `ncm_rig_bridge.json` next to the plugin. Start the game once, then read the plugin's log for
each device's stable GUID and name. Full reference: [Rig Bridge README](https://github.com/evengineer1ng/ncm-online/blob/main/ncm/rig_bridge/README.md).

## What has been tested

| | Hardware |
|---|---|
| **Tested by the developer** | Logitech G29 (force feedback ceilings were measured on it), Thrustmaster pedals, an Evenracing rig, a FW707-class wheel, Xbox-style gamepads, Switch Pro controller (face-button positions corrected in 0.1.8; a fresh-client recheck is owed) |
| **Should work (untested)** | Any DirectInput wheel or pedal set: MOZA, Fanatec, other Logitech and Thrustmaster wheels, button boxes, custom USB controllers |
| **Not supported** | Devices with no DirectInput interface; anything that depends on a vendor's own SDK features |

## Known limits

- Fixed in 0.1.9, not yet confirmed in play: with a configured wheel unplugged (for example a bound G29 that isn't
  connected), older versions re-acquired every controller every 2 seconds, and buttons stopped working.
- A wheel-rim pause button can fail when Rig Bridge loses the rim. F6 on the keyboard or the controller still works.
- If Cyberpunk can't see your devices at all, check for device-hiding tools such as HidHide before blaming Rig Bridge.

## For developers

`ncm/rig_bridge/` (RED4ext C++, SDL3 for gamepads, its own tests). Feel model: `ncm/core/driver/feedback.lua`.
Authority: `docs/ncm-online/43_RIG_BRIDGE_ASSESSMENT.md`, DECISION_RECORD L185-L191. Lineage and licences:
`ncm/rig_bridge/THIRD_PARTY_NOTICES.md`.
