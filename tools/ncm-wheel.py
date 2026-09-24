#!/usr/bin/env python3
"""Reference force-feedback companion for NCM Online (IDEA-386).

**This drives no hardware.** It is the shape JoyMoCo's side should take, and a harness for watching the
telemetry arrive before any force is applied to a real wheel. It serves the bridge page, accepts the
same-origin WebSocket, decodes frames and prints what it would have commanded.

Architecture, proven live in MASTER_TEST section AJ (L129): a bundled OPEN//77 WebUI page has NO outbound
network, so the direction is inverted. The companion serves an HTML page; NCM creates a surface whose `entry`
is that URL; `Open77.webui.create` injects the Lua bridge into that origin; the page relays Lua events over a
same-origin socket. No TLS, because loopback is already a secure context.

    python tools/ffb-dev-companion.py [--port 38480] [--class belt]
    then in game:  /ncm.ffb on

--------------------------------------------------------------------------------------------------
SAFETY -- the part to read before connecting a real wheel
--------------------------------------------------------------------------------------------------
This mirrors `ncm/core/driver/feedback.lua`, which is the authority and is covered by the gate. Keep the two
in step; if they ever disagree, the Lua is right.

**SDL haptic magnitude is normalised, and normalised is not equal.** A 0.5 constant force is about a
newton-metre on a belt-drive G29 and about ten on a 20 Nm direct-drive base. The same number is a nudge on one
device and a wrist injury on another. So:

  * ceilings are per device CLASS, and the classes nobody here can test are held far below the ones we can;
  * an unidentified device is assumed to be the most dangerous thing it could be;
  * the rate of change is capped as well as the level, because a spike is what hurts, not a sustained level;
  * tuning is a LADDER, not a slider -- fixed rungs, fixed small step, hard last rung.

Owner's method, 2026-09-24: *"start at the lowest ffb settings, and increment slightly until further is
unnecessary then STOP. An important feature for us should not cost any wrists."*
"""
from __future__ import annotations

import argparse
import base64
import io
import hashlib
import json
import os
import socket
import struct
import sys
import threading
import time

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
CRLF = chr(13) + chr(10)

FRAME_VERSION = 1

# Mirror of driver.feedback. The Lua is authoritative.
CEILING = {"gear": 0.60, "belt": 0.50, "direct_drive": 0.15, "unknown": 0.10}
FLOOR = 0.05
STEP = 0.05
MAX_SLEW_PER_SECOND = 1.5


def ladder(device_class: str) -> list[float]:
    """Every permitted setting for a class, lowest first. A tuning session starts at [0] and stops the moment
    another rung adds nothing."""
    ceiling = CEILING.get(device_class)
    if ceiling is None:
        return []
    out, v = [], FLOOR
    while v <= ceiling + 1e-9:
        out.append(round(v, 3))
        v += STEP
    return out


def clamp(device_class: str, requested) -> float:
    """The only way a magnitude leaves this module."""
    ceiling = CEILING.get(device_class, CEILING["unknown"])
    try:
        v = float(requested)
    except (TypeError, ValueError):
        return 0.0
    if v != v or v in (float("inf"), float("-inf")) or v < 0:
        return 0.0
    return min(v, ceiling)


def slew(previous: float, target, dt: float, max_per_second: float = MAX_SLEW_PER_SECOND) -> float:
    """No sudden full-scale step, ever. An unreadable target HOLDS rather than dropping to zero."""
    try:
        want = float(target)
    except (TypeError, ValueError):
        return previous
    if want != want:
        return previous
    step = max_per_second * max(0.0, dt)
    if step <= 0:
        return previous
    delta = want - previous
    if delta > step:
        return previous + step
    if delta < -step:
        return previous - step
    return want


# --------------------------------------------------------------------------------------------------
# Device discovery. Reporting only -- nothing here opens a haptic effect.
# --------------------------------------------------------------------------------------------------
#
# The companion is the only thing in the system that can see the hardware, so it is the only thing that may
# describe it. **Classification decides the ceiling**, so getting it wrong in the permissive direction is the
# one mistake that matters: anything not confidently recognised stays `unknown`, which carries the lowest cap.
#
# Name matching is crude on purpose. A curated list of substrings we can defend beats a clever heuristic that
# might promote an unknown direct-drive base into the `belt` ceiling.
BELT_OR_GEAR = {
    "g29": "gear", "g920": "gear", "g923": "gear", "g27": "gear", "g25": "gear", "driving force": "gear",
    "t300": "belt", "t150": "belt", "tmx": "belt", "t500": "belt", "thrustmaster": "belt",
    "csl elite": "belt", "clubsport": "belt",
}
DIRECT_DRIVE = ("moza", "simucube", "simagic", "fanatec dd", "podium", "csl dd", "vrs ", "asetek", "cammus")


def classify(name: str) -> str:
    """A device class, or `unknown`. **Never guesses upward.**"""
    n = (name or "").lower()
    for token in DIRECT_DRIVE:
        if token in n:
            return "direct_drive"
    for token, cls in BELT_OR_GEAR.items():
        if token in n:
            return cls
    return "unknown"


def discover():
    """The first haptic-capable device SDL can see, described but NOT opened for output.

    Returns (name, class, capabilities dict) or (None, "unknown", {}). An import failure is reported rather
    than crashing the bridge: telemetry is still worth watching on a machine with no wheel attached.
    """
    try:
        import sdl2
    except Exception as exc:                                    # noqa: BLE001 - diagnostic path
        print("[ffb] SDL unavailable (%s); running without hardware discovery" % exc, flush=True)
        return None, "unknown", {}
    try:
        sdl2.SDL_InitSubSystem(sdl2.SDL_INIT_JOYSTICK | sdl2.SDL_INIT_HAPTIC)
        count = sdl2.SDL_NumHaptics()
        if count < 1:
            print("[ffb] SDL sees no haptic device. On Logitech wheels G HUB must be installed and running.",
                  flush=True)
            return None, "unknown", {}
        for i in range(count):
            raw_i = sdl2.SDL_HapticName(i)
            nm_i = raw_i.decode(errors="replace") if isinstance(raw_i, bytes) else str(raw_i)
            print("[ffb] haptic %d: %s" % (i, nm_i), flush=True)
        raw = sdl2.SDL_HapticName(0)
        name = raw.decode(errors="replace") if isinstance(raw, bytes) else str(raw)
        dev = sdl2.SDL_HapticOpen(0)
        caps = {}
        if dev:
            bits = sdl2.SDL_HapticQuery(dev)
            for label, flag in (("constant", sdl2.SDL_HAPTIC_CONSTANT), ("sine", sdl2.SDL_HAPTIC_SINE),
                                ("leftright", sdl2.SDL_HAPTIC_LEFTRIGHT), ("damper", sdl2.SDL_HAPTIC_DAMPER),
                                ("spring", sdl2.SDL_HAPTIC_SPRING)):
                caps[label] = bool(bits & flag)
            # Closed again immediately. Discovery must not leave a device held open by a process that is not
            # going to drive it.
            sdl2.SDL_HapticClose(dev)
        return name, classify(name), caps
    except Exception as exc:                                    # noqa: BLE001 - diagnostic path
        print("[ffb] device discovery failed: %s" % exc, flush=True)
        return None, "unknown", {}


BRIDGE_HTML = """<!doctype html>
<html><head><meta charset="utf-8"><title>NCM FFB bridge</title></head>
<body style="margin:0;background:transparent">
<script>
// The whole page. It owns no policy and makes no decisions -- it relays Lua events to a same-origin socket
// and reports the socket's state back to Lua, so the client knows whether a companion is actually listening.
(function () {
  var ws = null, ready = false;
  var tell = function (event, detail) {
    try { if (window.Open77 && Open77.emit) Open77.emit(event, { detail: String(detail) }); } catch (e) {}
  };
  var connect = function () {
    try {
      ws = new WebSocket("ws://" + location.host + "/telemetry");
    } catch (e) { tell("ncm:ffb.closed", "construct failed: " + e); return; }
    ws.onopen = function () { ready = true; tell("ncm:ffb.ready", location.origin); };
    // Upward: whatever the companion says about the hardware. Passed through untouched -- this page owns no
    // policy and must not be the place a device class quietly changes.
    ws.onmessage = function (ev) {
      try {
        var msg = JSON.parse(ev.data);
        if (msg && msg.device && window.Open77 && Open77.emit) Open77.emit("ncm:ffb.device", msg.device);
      } catch (e) {}
    };
    ws.onclose = function () { ready = false; tell("ncm:ffb.closed", "socket closed"); setTimeout(connect, 2000); };
    ws.onerror = function () { ready = false; };
  };
  var relay = function (payload) {
    if (!ready || !ws) return;
    try { ws.send(JSON.stringify(payload)); } catch (e) {}
  };
  if (window.Open77 && Open77.on) {
    Open77.on("ncm:ffb.frame", relay);
    // `idle` is sent deliberately instead of going quiet: silence and "no force" are different instructions,
    // and a companion holding the last frame would keep pushing at a wheel whose car it can no longer see.
    Open77.on("ncm:ffb.idle", function (p) { relay({ v: (p && p.v) || 1, idle: true }); });
    // Downward: panel settings and the test pulse take the SAME socket the telemetry came up. One transport,
    // so the two sides cannot disagree about which is authoritative.
    Open77.on("ncm:ffb.settings", function (p) { relay({ cmd: "settings", settings: p || {} }); });
    Open77.on("ncm:ffb.test", function (p) { relay({ cmd: "test", test: p || {} }); });
  }
  connect();
})();
</script>
</body></html>
"""


def _accept_key(key: str) -> str:
    return base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()


def _read_frame(conn: socket.socket):
    head = conn.recv(2)
    if len(head) < 2:
        return None
    opcode = head[0] & 0x0F
    masked = bool(head[1] & 0x80)
    length = head[1] & 0x7F
    if length == 126:
        length = struct.unpack(">H", conn.recv(2))[0]
    elif length == 127:
        length = struct.unpack(">Q", conn.recv(8))[0]
    mask = conn.recv(4) if masked else b"\x00\x00\x00\x00"
    payload = b""
    while len(payload) < length:
        chunk = conn.recv(length - len(payload))
        if not chunk:
            break
        payload += chunk
    return opcode, bytes(b ^ mask[i % 4] for i, b in enumerate(payload))


# --------------------------------------------------------------------------------------------------
# Input: wheel and pedals -> one virtual Xbox 360 pad.
# --------------------------------------------------------------------------------------------------
#
# **This is what makes the support native rather than a companion hack.** Cyberpunk reads an ordinary Xbox
# controller; ViGEmBus lets us present one; SDL reads the real hardware. Nothing about it is NCM-specific,
# which is the point -- the wheel steers the car in menus, in free roam and in someone else's gamemode, not
# only while NCM is looking.
#
# Observed on this machine, game and JoyMoCo both closed:
#     joystick 0  "Sim Pedals"                                   3 axes, all resting at -32768
#     joystick 1  "Logitech G HUB G29 ... Racing Wheel USB"       4 axes, wheel centred at 0
# So pedals are a SEPARATE device from the wheel, and a pedal at rest reads minimum rather than centre.

# --------------------------------------------------------------------------------------------------
# Input: a rig, a gamepad, or both -> one virtual Xbox 360 pad.
# --------------------------------------------------------------------------------------------------
#
# **Nothing about anyone's hardware is hardcoded here.** This is going on a public server, so a rig that
# nobody here has ever seen has to work. Roles are decided by SHAPE, and a profile file only supplies what
# shape cannot tell you -- which button on an unlabelled rim is `a`.
#
#   steering  an axis that rests near centre and travels both ways
#   pedals    axes that rest at one END of travel
#   rim       many buttons and no usable axes
#   gamepad   anything SDL's own GameController database recognises
#
# That last one matters most: a standard Xbox pad needs **no profile and no mapping**, because SDL already
# knows it. The owner's custom rim needs a profile because no database will ever contain it.
#
# **The gamepad is never displaced by the rig.** Both feed the same virtual pad and the larger deflection
# wins, so a driver can hold a controller in their hands and keep the wheel in front of them. On foot the rig
# is suppressed entirely -- a wheel should not be nudging the walk axis while you are walking.

PROFILE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wheel-profiles")

BUTTON_NAMES = ("a", "b", "x", "y", "lb", "rb", "back", "start", "home", "ls", "rs",
                "dpad_up", "dpad_down", "dpad_left", "dpad_right")


def load_profiles(path=None):
    """Every profile we can find, plus the defaults block. Missing or broken files are not fatal: a rig
    still steers without a profile, and refusing to start over a JSON typo would be a poor trade."""
    path = path or os.path.join(PROFILE_DIR, "default.json")
    try:
        with io.open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        return data.get("defaults", {}), data.get("profiles", [])
    except Exception as exc:                                    # noqa: BLE001 - diagnostic path
        print("[in ] no rig profiles loaded (%s); detection only" % exc, flush=True)
        return {}, []


def match_profile(name, profiles, role=None):
    low = (name or "").lower()
    best = None
    for p in profiles:
        if role and p.get("role") != role:
            continue
        for token in p.get("match", []):
            if token.lower() in low:
                # Longest match wins, so "fanatec dd" beats "fanatec".
                if best is None or len(token) > best[0]:
                    best = (len(token), p)
    return best[1] if best else None


class Device:
    """One physical thing, with the role we decided it plays."""

    def __init__(self, index, name, handle, role, profile=None):
        self.index, self.name, self.handle = index, name, handle
        self.role, self.profile = role, profile or {}
        self.rest = {}


class Input:
    """Reads whatever is attached and drives a virtual Xbox 360 pad.

    **Steering range is the setting people will actually argue about.** A 900-degree wheel mapped one-to-one
    onto a thumbstick gives a car that barely turns -- full deflection would need half a turn. Only the middle
    is used: `steer_degrees` per side maps to full deflection, the rest clamps. 45 is one driver's comfort,
    not a fact, so it is adjustable live from the NCM panel.
    """

    def __init__(self, steer_degrees=45.0, wheel_range=900.0, profile_path=None):
        self.steer_degrees = max(5.0, float(steer_degrees))
        self.wheel_range = max(90.0, float(wheel_range))
        self.defaults, self.profiles = load_profiles(profile_path)
        self.steer_deadzone = float(self.defaults.get("steer_deadzone", 0.015))
        self.steer_curve = float(self.defaults.get("steer_curve", 1.3))
        self.pad_deadzone = float(self.defaults.get("gamepad_deadzone", 0.08))
        self.sdl = None
        self.vg = None
        self.pad = None
        self.devices = []
        self.controllers = []
        self.steering = self.pedals = self.rim = None
        self.detected_class = "unknown"
        self.running = False
        self.thread = None
        self.last = {}
        self.pressed = set()
        # **Seat gating.** None means "NCM has not told us anything", and the rig stays live -- the companion
        # must be useful on its own. Only an explicit `False` from a connected bridge suppresses it.
        self.seated = None

    @property
    def scale(self):
        return (self.wheel_range / 2.0) / self.steer_degrees

    def set_steer_degrees(self, degrees):
        self.steer_degrees = max(5.0, min(540.0, float(degrees)))
        return self.steer_degrees

    # ---------------------------------------------------------------- detection
    def _classify(self, sdl2, index, handle, name):
        """Decide what a device IS from how it behaves, not from what it is called."""
        profile = match_profile(name, self.profiles)
        if profile and profile.get("role"):
            return profile["role"], profile

        n_axes = sdl2.SDL_JoystickNumAxes(handle)
        n_buttons = sdl2.SDL_JoystickNumButtons(handle)
        if n_axes == 0 and n_buttons > 0:
            return "rim", profile
        # Sample resting positions: a pedal sits at an end of travel, a wheel sits near centre.
        for _ in range(10):
            sdl2.SDL_JoystickUpdate()
            time.sleep(0.01)
        values = [sdl2.SDL_JoystickGetAxis(handle, a) for a in range(n_axes)]
        extreme = sum(1 for v in values if abs(v) > 24000)
        centred = sum(1 for v in values if abs(v) < 4000)
        if n_axes and extreme >= max(1, n_axes // 2) and centred == 0:
            return "pedals", profile
        if centred and n_buttons < 26:
            return "steering", profile
        if n_buttons >= 26:
            return "rim", profile
        return "other", profile

    def open(self):
        try:
            import sdl2
            import vgamepad as vg
        except Exception as exc:                                # noqa: BLE001 - diagnostic path
            return "input unavailable: %s (is ViGEmBus installed?)" % exc
        self.sdl, self.vg = sdl2, vg
        try:
            sdl2.SDL_Init(sdl2.SDL_INIT_JOYSTICK | sdl2.SDL_INIT_GAMECONTROLLER)
            sdl2.SDL_JoystickEventState(sdl2.SDL_IGNORE)
            sdl2.SDL_GameControllerEventState(sdl2.SDL_IGNORE)

            for i in range(sdl2.SDL_NumJoysticks()):
                raw = sdl2.SDL_JoystickNameForIndex(i)
                nm = (raw.decode(errors="replace") if isinstance(raw, bytes) else str(raw))
                # **A recognised gamepad is taken as a gamepad and never taken apart.** SDL's own database
                # already knows which button is `a` on an Xbox pad; re-deriving that would be worse.
                if sdl2.SDL_IsGameController(i):
                    ctrl = sdl2.SDL_GameControllerOpen(i)
                    if ctrl:
                        self.controllers.append((nm, ctrl))
                        print("[in ] gamepad: %d %s (SDL mapping)" % (i, nm), flush=True)
                        continue
                handle = sdl2.SDL_JoystickOpen(i)
                if not handle:
                    continue
                role, profile = self._classify(sdl2, i, handle, nm)
                dev = Device(i, nm, handle, role, profile)
                tag = (profile or {}).get("name")
                print("[in ] %-8s: %d %s%s" % (role, i, nm, (" [%s]" % tag) if tag else " [detected]"),
                      flush=True)
                if role == "steering" and self.steering is None:
                    self.steering = dev
                    self.detected_class = (profile or {}).get("device_class", "unknown")
                elif role == "pedals" and self.pedals is None:
                    self.pedals = dev
                elif role == "rim" and self.rim is None:
                    self.rim = dev
                else:
                    self.devices.append(dev)

            if self.steering is None and not self.controllers:
                return "nothing usable attached"

            self.pad = vg.VX360Gamepad()
            self._calibrate_pedals()
            return ""
        except Exception as exc:                                # noqa: BLE001 - diagnostic path
            return "input open failed: %s" % exc

    def _calibrate_pedals(self):
        """Learn where 'released' is. **The first read after opening is a lie** -- SDL reports 0 for every
        axis until it has actually polled, and believing that made a released pedal look fully pressed, with
        the virtual pad holding full throttle and full brake at once."""
        if self.pedals is None:
            return
        sdl2 = self.sdl
        count = sdl2.SDL_JoystickNumAxes(self.pedals.handle)
        deadline = time.monotonic() + 2.0
        values = [0] * count
        while time.monotonic() < deadline:
            sdl2.SDL_JoystickUpdate()
            values = [sdl2.SDL_JoystickGetAxis(self.pedals.handle, a) for a in range(count)]
            if any(v != 0 for v in values):
                break
            time.sleep(0.02)
        if all(v == 0 for v in values):
            fallback = int(self.pedals.profile.get("released", -32768))
            values = [fallback] * count
            print("[in ] pedal rest: SDL never reported; assuming %d released" % fallback, flush=True)
        else:
            print("[in ] pedal rest: %s (feet off while this starts)" % (values,), flush=True)
        for a in range(count):
            self.pedals.rest[a] = values[a]

    # ---------------------------------------------------------------- reading
    def _pedal(self, which):
        if self.pedals is None:
            return 0.0
        axis = self.pedals.profile.get("axes", {}).get(which)
        if axis is None:
            axis = {"throttle": 0, "brake": 1, "clutch": 2}.get(which)
        if axis is None or axis not in self.pedals.rest:
            return 0.0
        v = self.sdl.SDL_JoystickGetAxis(self.pedals.handle, axis)
        rest = self.pedals.rest[axis]
        span = 65535.0 if abs(rest) > 16384 else 32767.0
        return max(0.0, min(1.0, abs(v - rest) / span))

    def _steer(self):
        if self.steering is None:
            return 0.0
        axis = self.steering.profile.get("axes", {}).get("steer", 0)
        raw = self.sdl.SDL_JoystickGetAxis(self.steering.handle, axis) / 32767.0
        value = max(-1.0, min(1.0, raw * self.scale))
        if abs(value) < self.steer_deadzone:
            return 0.0
        if self.steer_curve != 1.0:
            value = (1.0 if value > 0 else -1.0) * (abs(value) ** self.steer_curve)
        return value

    def _gamepad_state(self):
        """Whatever the handheld controller is doing, through SDL's own mapping."""
        sdl2 = self.sdl
        state = {"lx": 0.0, "ly": 0.0, "rx": 0.0, "ry": 0.0, "lt": 0.0, "rt": 0.0, "buttons": set()}
        axis_map = {"lx": sdl2.SDL_CONTROLLER_AXIS_LEFTX, "ly": sdl2.SDL_CONTROLLER_AXIS_LEFTY,
                    "rx": sdl2.SDL_CONTROLLER_AXIS_RIGHTX, "ry": sdl2.SDL_CONTROLLER_AXIS_RIGHTY}
        btn_map = {"a": sdl2.SDL_CONTROLLER_BUTTON_A, "b": sdl2.SDL_CONTROLLER_BUTTON_B,
                   "x": sdl2.SDL_CONTROLLER_BUTTON_X, "y": sdl2.SDL_CONTROLLER_BUTTON_Y,
                   "lb": sdl2.SDL_CONTROLLER_BUTTON_LEFTSHOULDER,
                   "rb": sdl2.SDL_CONTROLLER_BUTTON_RIGHTSHOULDER,
                   "back": sdl2.SDL_CONTROLLER_BUTTON_BACK, "start": sdl2.SDL_CONTROLLER_BUTTON_START,
                   "home": sdl2.SDL_CONTROLLER_BUTTON_GUIDE,
                   "ls": sdl2.SDL_CONTROLLER_BUTTON_LEFTSTICK,
                   "rs": sdl2.SDL_CONTROLLER_BUTTON_RIGHTSTICK,
                   "dpad_up": sdl2.SDL_CONTROLLER_BUTTON_DPAD_UP,
                   "dpad_down": sdl2.SDL_CONTROLLER_BUTTON_DPAD_DOWN,
                   "dpad_left": sdl2.SDL_CONTROLLER_BUTTON_DPAD_LEFT,
                   "dpad_right": sdl2.SDL_CONTROLLER_BUTTON_DPAD_RIGHT}
        for _, ctrl in self.controllers:
            for key, axis in axis_map.items():
                v = sdl2.SDL_GameControllerGetAxis(ctrl, axis) / 32767.0
                # **Stick drift is not steering.** A resting Xbox pad reported 0.032 here, and because the
                # merge takes the larger deflection that drift beat a perfectly centred wheel and put a
                # permanent lean into the car. Deadzone first, merge second.
                if abs(v) < self.pad_deadzone:
                    v = 0.0
                if abs(v) > abs(state[key]):
                    state[key] = max(-1.0, min(1.0, v))
            for key, axis in (("lt", sdl2.SDL_CONTROLLER_AXIS_TRIGGERLEFT),
                              ("rt", sdl2.SDL_CONTROLLER_AXIS_TRIGGERRIGHT)):
                v = max(0.0, sdl2.SDL_GameControllerGetAxis(ctrl, axis) / 32767.0)
                if v < self.pad_deadzone:
                    v = 0.0
                state[key] = max(state[key], v)
            for name, btn in btn_map.items():
                if sdl2.SDL_GameControllerGetButton(ctrl, btn):
                    state["buttons"].add(name)
        return state

    def _rim_buttons(self):
        """Rim buttons, per profile. No profile means no rim buttons -- guessing which one is `a` on an
        unknown rim could bind `home` to a paddle and drop a player out of the game."""
        out = set()
        if self.rim is None:
            return out
        mapping = self.rim.profile.get("buttons") or {}
        ignored = set(self.rim.profile.get("ignore_buttons") or [])
        for raw_index, target in mapping.items():
            index = int(raw_index)
            if index in ignored or target not in BUTTON_NAMES:
                continue
            if self.sdl.SDL_JoystickGetButton(self.rim.handle, index):
                out.add(target)
        return out

    # ---------------------------------------------------------------- output
    def _tick(self):
        sdl2 = self.sdl
        sdl2.SDL_JoystickUpdate()
        sdl2.SDL_GameControllerUpdate()

        pad_state = self._gamepad_state()
        # On foot, the rig contributes nothing. Only an explicit `False` from a connected NCM suppresses it;
        # `None` means nobody has said, and the companion has to work on its own.
        rig_live = self.seated is not False
        steer = self._steer() if rig_live else 0.0
        throttle = self._pedal("throttle") if rig_live else 0.0
        brake = self._pedal("brake") if rig_live else 0.0
        rim = self._rim_buttons() if rig_live else set()

        # Larger deflection wins, so holding a controller never fights the wheel in front of you.
        lx = steer if abs(steer) >= abs(pad_state["lx"]) else pad_state["lx"]
        rt = max(throttle, pad_state["rt"])
        lt = max(brake, pad_state["lt"])
        held = rim | pad_state["buttons"]

        self.pad.left_joystick_float(x_value_float=lx, y_value_float=-pad_state["ly"])
        self.pad.right_joystick_float(x_value_float=pad_state["rx"], y_value_float=-pad_state["ry"])
        self.pad.right_trigger_float(value_float=rt)
        self.pad.left_trigger_float(value_float=lt)

        for name in BUTTON_NAMES:
            target = getattr(self.vg.XUSB_BUTTON, "XUSB_GAMEPAD_" + {
                "lb": "LEFT_SHOULDER", "rb": "RIGHT_SHOULDER", "home": "GUIDE",
                "ls": "LEFT_THUMB", "rs": "RIGHT_THUMB",
                "dpad_up": "DPAD_UP", "dpad_down": "DPAD_DOWN",
                "dpad_left": "DPAD_LEFT", "dpad_right": "DPAD_RIGHT",
            }.get(name, name.upper()))
            if name in held and name not in self.pressed:
                self.pressed.add(name)
                self.pad.press_button(button=target)
            elif name not in held and name in self.pressed:
                self.pressed.discard(name)
                self.pad.release_button(button=target)

        self.pad.update()
        self.last = {"steer": lx, "throttle": rt, "brake": lt, "rig": rig_live,
                     "buttons": sorted(self.pressed)}

    def start(self):
        if self.running or self.pad is None:
            return
        self.running = True

        def loop():
            # 120 Hz. Steering latency is the one thing a driver feels directly.
            while self.running:
                try:
                    self._tick()
                except Exception:                               # noqa: BLE001 - never let input die silently
                    pass
                time.sleep(1.0 / 120.0)

        self.thread = threading.Thread(target=loop, daemon=True)
        self.thread.start()
        print("[in ] steering %.0f deg/side (range %.0f, x%.1f, curve %.1f) | %d gamepad(s) merged"
              % (self.steer_degrees, self.wheel_range, self.scale, self.steer_curve, len(self.controllers)),
              flush=True)

    def describe(self):
        return {
            "steering": self.steering.name if self.steering else None,
            "pedals": self.pedals.name if self.pedals else None,
            "rim": self.rim.name if self.rim else None,
            "gamepads": [n for n, _ in self.controllers],
            "steerDegrees": self.steer_degrees,
            "wheelRange": self.wheel_range,
            "rigLive": self.seated is not False,
        }

    def stop(self):
        """Release everything. A virtual pad left holding a trigger is a car left accelerating."""
        self.running = False
        try:
            if self.pad is not None:
                self.pad.reset()
                self.pad.update()
        except Exception:                                       # noqa: BLE001
            pass


class Output:
    """The only thing in this program that can move a wheel.

    **Every safety rule is enforced on the way in, not by the caller.** `write()` takes a level that has
    already been clamped and slewed by `Mixer`, and clamps it again here -- because this is the last place a
    mistake is still cheap, and the cost of a redundant `min()` is nothing against the cost of being wrong.

    Design choices that are safety choices:

      * **A periodic SINE, not a CONSTANT force.** A constant effect is a sustained torque in one direction --
        it fights the driver and it is what wrenches a wrist. A sine oscillates around centre: it is felt as
        texture, and its worst case is a buzz rather than a pull.
      * **The effect is created once and UPDATED**, never re-played per frame. Re-triggering at 30 Hz makes an
        audible click and, worse, restarts the envelope each time.
      * **Stop is idempotent and runs on every exit path** -- idle frame, socket close, process exit,
        exception. A wheel left buzzing after the game closed is the single worst outcome here, and it is the
        one a crash would otherwise produce.
    """

    def __init__(self, device_class: str):
        self.device_class = device_class
        self.sdl = None
        self.haptic = None
        self.name = None
        self.caps = {}
        self.index = None               # None = try every enumerated device
        self.opened_index = None
        self.dev = None
        self.effect_id = None
        self.effect = None
        self.last_sent = -1.0
        self.mode = "none"

    def open(self) -> str:
        """Open the device and leave a silent effect running. Returns "" on success, else why not.

        Three details copied from `anyffb`, which works on this exact hardware and was worth reading before
        guessing:

          * **`SDL_Init(SDL_INIT_HAPTIC)`**, not `SDL_InitSubSystem` on an uninitialised SDL. The latter
            returned *"Haptic error Resetting device"* here.
          * **`SDL_HapticDirection` constructed properly**, not a field assignment into `.dir[0]`.
          * **`length = 0xFFFFFFFF`** and an explicit `SDL_HapticSetGain(100)`.

        **`CONSTANT` is deliberately NOT used as a fallback**, though anyffb offers it. A constant effect is a
        sustained torque in one direction -- it fights the driver rather than texturing the wheel, and it is
        the shape that hurts. LEFTRIGHT and SINE cover every wheel we expect; a device offering neither gets
        no force rather than the dangerous one.
        """
        try:
            import sdl2
            import sdl2.haptic as haptic
            from ctypes import c_long
        except Exception as exc:                                # noqa: BLE001 - diagnostic path
            return "SDL unavailable: %s" % exc
        self.sdl, self.haptic = sdl2, haptic
        try:
            if sdl2.SDL_Init(sdl2.SDL_INIT_HAPTIC) != 0:
                return "SDL_Init(HAPTIC) failed: %s" % sdl2.SDL_GetError()
            count = haptic.SDL_NumHaptics()
            if count < 1:
                return "no haptic device"

            # **Try every index, not just 0.** A wheel commonly enumerates more than once -- the owner's G29
            # appears both as a bare name and as a `... USB` entry -- and only one of those may actually
            # open. Picking index 0 and reporting its failure as "no wheel" would have been wrong twice: the
            # name it reported was right and the handle it could not get was the wrong one.
            attempts = []
            for i in range(count):
                if self.index is not None and i != self.index:
                    continue
                raw = haptic.SDL_HapticName(i)
                nm = raw.decode(errors="replace") if isinstance(raw, bytes) else str(raw)
                dev = haptic.SDL_HapticOpen(i)
                if dev:
                    # **Opening is not the test; creating an effect is.** The G29 enumerates three times on
                    # this machine: index 0 refuses outright, index 1 OPENS and then cannot create an effect
                    # of any shape, and only index 2 -- the `... USB` entry -- actually works. A handle that
                    # opens and does nothing is worse than one that refuses, because it looks like success.
                    probe = haptic.SDL_HapticEffect()
                    probe.type = haptic.SDL_HAPTIC_SINE
                    probe.periodic.type = haptic.SDL_HAPTIC_SINE
                    probe.periodic.direction = haptic.SDL_HapticDirection(
                        haptic.SDL_HAPTIC_CARTESIAN, (c_long * 3)(0, 0, 0))
                    probe.periodic.length = 0xFFFFFFFF
                    probe.periodic.period = 40
                    probe.periodic.magnitude = 0
                    pid = haptic.SDL_HapticNewEffect(dev, probe)
                    if pid >= 0:
                        haptic.SDL_HapticDestroyEffect(dev, pid)
                        self.name, self.dev, self.opened_index = nm, dev, i
                        print("[ffb] haptic %d: %s -- USABLE" % (i, nm), flush=True)
                        break
                    haptic.SDL_HapticClose(dev)
                    attempts.append("%d:%s (opens, cannot create effects)" % (i, nm))
                    print("[ffb] haptic %d: %s -- opens but creates nothing" % (i, nm), flush=True)
                    if not self.name:
                        self.name = nm
                    continue
                err = sdl2.SDL_GetError()
                err = err.decode(errors="replace") if isinstance(err, bytes) else str(err)
                attempts.append("%d:%s (%s)" % (i, nm, err.strip()))
                print("[ffb] haptic %d: %s -- refused (%s)" % (i, nm, err.strip()), flush=True)
                if not self.name:
                    self.name = nm
            if not self.dev:
                return "no haptic index would open -- tried %s" % "; ".join(attempts)
            caps = haptic.SDL_HapticQuery(self.dev)
            self.caps = {
                "constant": bool(caps & haptic.SDL_HAPTIC_CONSTANT),
                "sine": bool(caps & haptic.SDL_HAPTIC_SINE),
                "leftright": bool(caps & haptic.SDL_HAPTIC_LEFTRIGHT),
                "damper": bool(caps & haptic.SDL_HAPTIC_DAMPER),
            }
            haptic.SDL_HapticSetGain(self.dev, 100)

            eff = haptic.SDL_HapticEffect()
            if caps & haptic.SDL_HAPTIC_LEFTRIGHT:
                self.mode = "leftright"
                eff.type = haptic.SDL_HAPTIC_LEFTRIGHT
                eff.leftright.length = 0xFFFFFFFF
                eff.leftright.large_magnitude = 0
                eff.leftright.small_magnitude = 0
            elif caps & haptic.SDL_HAPTIC_SINE:
                self.mode = "sine"
                eff.type = haptic.SDL_HAPTIC_SINE
                eff.periodic.direction = haptic.SDL_HapticDirection(
                    haptic.SDL_HAPTIC_CARTESIAN, (c_long * 3)(0, 0, 0))
                eff.periodic.length = 0xFFFFFFFF
                eff.periodic.period = 40                        # 25 Hz: texture, not a shove
                eff.periodic.magnitude = 0
                eff.periodic.offset = 0
                eff.periodic.phase = 0
            else:
                return "device offers neither LEFTRIGHT nor SINE (CONSTANT is refused on purpose)"

            self.effect = eff
            self.effect_id = haptic.SDL_HapticNewEffect(self.dev, eff)
            if self.effect_id < 0:
                return "SDL_HapticNewEffect failed: %s" % sdl2.SDL_GetError()
            haptic.SDL_HapticRunEffect(self.dev, self.effect_id, 1)
            return ""
        except Exception as exc:                                # noqa: BLE001 - diagnostic path
            return "haptic open failed: %s" % exc

    def write(self, level: float) -> None:
        if self.mode == "none" or self.sdl is None:
            return
        level = clamp(self.device_class, level)                 # last line of defence, deliberately redundant
        if abs(level - self.last_sent) < 0.005:
            return
        self.last_sent = level
        try:
            mag = int(level * 32767)
            if self.mode == "leftright":
                self.effect.leftright.large_magnitude = mag
                self.effect.leftright.small_magnitude = mag
            else:
                self.effect.periodic.magnitude = mag
            self.haptic.SDL_HapticUpdateEffect(self.dev, self.effect_id, self.effect)
        except Exception:                                       # noqa: BLE001 - never let output kill the loop
            self.stop()

    def stop(self) -> None:
        """Silence, by every means available, and safe to call twice."""
        self.last_sent = -1.0
        if self.sdl is None or self.dev is None:
            return
        try:
            self.haptic.SDL_HapticStopAll(self.dev)
        except Exception:                                       # noqa: BLE001
            pass

    def close(self) -> None:
        self.stop()
        try:
            if self.haptic and self.dev:
                self.haptic.SDL_HapticClose(self.dev)
        except Exception:                                       # noqa: BLE001
            pass
        self.dev, self.mode = None, "none"


class Mixer:
    """Telemetry in, a would-be magnitude out. Every channel is optional and ABSENCE IS NOT ZERO: a missing
    channel contributes nothing and leaves the previous level to decay through the slew limiter, rather than
    asserting that the car is idling, straight and gripping."""

    def __init__(self, device_class: str, rung: float, armed: bool = False):
        self.device_class = device_class
        self.rung = rung
        self.level = 0.0
        self.last = time.monotonic()
        self.frames = 0
        self.idles = 0
        self.device_name = None
        self.caps = {}
        self.out = None                 # set by main() only when --arm was given
        self.rig = None                 # set by main(); the mixer gates it on seat state
        # **Force output is opt-in and off.** Everything else in this file runs identically either way, so the
        # difference between watching telemetry and moving a wheel is one flag rather than a code path nobody
        # exercised until the day it mattered.
        self.armed = armed

    def set_rung(self, index) -> float:
        """Move to a rung BY INDEX on this class's ladder. There is deliberately no way to set an arbitrary
        magnitude: the ladder is the safety property, and a free value would be a slider with extra steps."""
        rungs = ladder(self.device_class)
        if not rungs:
            return self.rung
        try:
            i = int(index)
        except (TypeError, ValueError):
            return self.rung
        i = max(1, min(i, len(rungs)))
        self.rung = rungs[i - 1]
        return self.rung

    def describe(self) -> dict:
        rungs = ladder(self.device_class)
        try:
            idx = rungs.index(self.rung) + 1
        except ValueError:
            idx = 1
        out = {
            "name": self.device_name or "no haptic device",
            "class": self.device_class,
            "rung": idx, "rungs": rungs, "armed": self.armed, "haptics": self.caps,
        }
        if self.rig is not None:
            out["rig"] = self.rig.describe()
        return out

    def feed(self, f: dict) -> float:
        now = time.monotonic()
        dt, self.last = now - self.last, now

        if f.get("idle"):
            # An `idle` frame means NCM has a driver who is NOT in a car. That is also the on-foot signal for
            # the rig: a wheel must not nudge the walk axis while someone is walking.
            if self.rig is not None:
                self.rig.seated = False
            self.idles += 1
            self.level = slew(self.level, 0.0, dt)
            self._emit()
            return self.level

        # A real frame means a driver in a car, so the rig is live again.
        if self.rig is not None:
            self.rig.seated = True
        self.frames += 1
        contributions = []
        if isinstance(f.get("engine"), (int, float)):
            contributions.append(0.45 * f["engine"])
        for key, weight in (("slipTotal", 0.8), ("suspLong", 0.3), ("suspLat", 0.3)):
            v = f.get(key)
            if isinstance(v, (int, float)):
                contributions.append(weight * min(1.0, abs(v)))
        if not contributions:
            self.level = slew(self.level, 0.0, dt)
            self._emit()
            return self.level

        # The rung IS the scale. Channel weights sum to roughly 0..1.8, so the lowest rung (0.05) puts a
        # fully-loaded car at about a twentieth of the device maximum -- which is where tuning starts.
        intensity = min(1.0, sum(contributions))
        target = clamp(self.device_class, intensity * self.rung)
        self.level = slew(self.level, target, dt)
        self._emit()
        return self.level

    def _emit(self) -> None:
        """The single point where a level becomes force. Nothing else in this class touches the device, so
        'is force being applied?' has exactly one answer to check."""
        if self.out is not None:
            self.out.write(self.level)

    def silence(self) -> None:
        self.level = 0.0
        if self.out is not None:
            self.out.stop()

    def pulse(self) -> None:
        """A test pulse is a RAMP UP AND BACK DOWN, never a step.

        The slew limiter exists precisely so nothing arrives as a hammer blow, and a 'test' that bypassed it
        would be testing something we never ship. So this walks the same limiter the telemetry path uses, at
        the current rung, and returns to silence."""
        if self.out is None:
            return
        step = 1.0 / 60.0
        level = 0.0
        for target in (self.rung, 0.0):
            for _ in range(60):
                level = slew(level, target, step)
                self.out.write(level)
                time.sleep(step)
                if abs(level - target) < 0.002:
                    break
        self.out.stop()


def serve(conn: socket.socket, addr, mixer: Mixer, port: int) -> None:
    request = b""
    while CRLF.encode() * 2 not in request:
        chunk = conn.recv(4096)
        if not chunk:
            return
        request += chunk
    lines = request.decode(errors="replace").split(CRLF)
    headers = {}
    for line in lines[1:]:
        if ":" in line:
            name, _, value = line.partition(":")
            headers[name.strip().lower()] = value.strip()

    if not headers.get("sec-websocket-key"):
        body = BRIDGE_HTML.encode()
        head = CRLF.join([
            "HTTP/1.1 200 OK",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: " + str(len(body)),
            "Cache-Control: no-store",
            "Connection: close",
        ]) + CRLF + CRLF
        conn.sendall(head.encode() + body)
        print("[ffb] served bridge page to %s" % (lines[0],), flush=True)
        return

    conn.sendall((CRLF.join([
        "HTTP/1.1 101 Switching Protocols",
        "Upgrade: websocket",
        "Connection: Upgrade",
        "Sec-WebSocket-Accept: " + _accept_key(headers["sec-websocket-key"]),
    ]) + CRLF + CRLF).encode())
    print("[ffb] telemetry socket open from %s (origin %s)"
          % (headers.get("user-agent", "?")[:40], headers.get("origin", "?")), flush=True)

    def say(payload: dict) -> None:
        data = json.dumps(payload).encode()
        header = bytearray([0x81])
        if len(data) < 126:
            header.append(len(data))
        elif len(data) < (1 << 16):
            header.append(126)
            header += struct.pack(">H", len(data))
        else:
            header.append(127)
            header += struct.pack(">Q", len(data))
        try:
            conn.sendall(bytes(header) + data)
        except OSError:
            pass

    # The panel cannot draw a wheel it has not been told about, and it must not invent one. Announced on
    # connect and again whenever a setting changes, so the tab is correct without polling.
    say({"device": mixer.describe()})

    last_print = 0.0
    while True:
        frame = _read_frame(conn)
        if frame is None:
            break
        opcode, payload = frame
        if opcode == 0x8:
            break
        if opcode == 0x9:
            conn.sendall(b"\x8a\x00")
            continue
        if opcode != 0x1:
            continue
        try:
            f = json.loads(payload.decode(errors="replace"))
        except Exception:
            continue
        cmd = f.get("cmd")
        if cmd == "settings":
            settings = f.get("settings") or {}
            if settings.get("rung") is not None:
                rung = mixer.set_rung(settings["rung"])
                print("[ffb] rung -> %.2f (%s)" % (rung, mixer.device_class), flush=True)
            if settings.get("steerDegrees") is not None and mixer.rig is not None:
                deg = mixer.rig.set_steer_degrees(settings["steerDegrees"])
                print("[in ] steering -> %.0f deg/side (x%.1f)" % (deg, mixer.rig.scale), flush=True)
            say({"device": mixer.describe()})
            continue
        if cmd == "test":
            # A test pulse is a RAMP, never a step: the slew limiter exists precisely so nothing arrives as a
            # hammer blow, and a "test" that bypassed it would be testing something we never ship.
            print("[ffb] TEST pulse at rung %.2f, ceiling %.2f%s" %
                  (mixer.rung, CEILING.get(mixer.device_class, CEILING["unknown"]),
                   "" if mixer.armed else "  (NOT ARMED -- no force applied)"), flush=True)
            if mixer.armed:
                threading.Thread(target=mixer.pulse, daemon=True).start()
            continue
        if f.get("v") != FRAME_VERSION:
            # A companion that does not recognise the version refuses the stream rather than guessing at it.
            print("[ffb] REFUSED frame version %r (expected %d)" % (f.get("v"), FRAME_VERSION), flush=True)
            continue
        level = mixer.feed(f)
        now = time.monotonic()
        if now - last_print >= 0.5:
            last_print = now
            print("[ffb] %s | thr=%-5s brk=%-5s str=%-6s eng=%-5s slip=%-5s -> magnitude %.3f (cap %.2f)"
                  % ("IDLE " if f.get("idle") else "frame",
                     f.get("throttle"), f.get("brake"), f.get("steering"),
                     None if f.get("engine") is None else round(f["engine"], 2),
                     f.get("slipTotal"), level, CEILING.get(mixer.device_class, CEILING["unknown"])),
                  flush=True)

    # **The game went away. Stop.** A wheel still buzzing after the client closed is the worst outcome
    # this program can produce, and a dropped socket is the likeliest way to reach it.
    mixer.silence()
    print("[ffb] socket closed after %d frame(s), %d idle -- output silenced" % (mixer.frames, mixer.idles),
          flush=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=38480)
    ap.add_argument("--class", dest="device_class", default=None, choices=sorted(CEILING),
                    help="override the detected class. Only ever use this to go LOWER than detection.")
    ap.add_argument("--rung", type=int, default=1, help="1-based rung on this class's ladder (default: lowest)")
    ap.add_argument("--no-input", action="store_true",
                    help="force feedback only; do not present a virtual pad or read the rig.")
    ap.add_argument("--steer-degrees", type=float, default=45.0,
                    help="wheel degrees per side mapped to full stick deflection (default 45).")
    ap.add_argument("--wheel-range", type=float, default=900.0,
                    help="the wheel's physical lock-to-lock range in degrees (default 900).")
    ap.add_argument("--profiles", default=None,
                    help="rig profile JSON. Default: tools/wheel-profiles/default.json")
    ap.add_argument("--monitor", action="store_true",
                    help="print live steering and pedal values. Use it to confirm which axis is which.")
    ap.add_argument("--device", type=int, default=None,
                    help="force a specific SDL haptic index. Default: try every one until one opens.")
    ap.add_argument("--arm", action="store_true",
                    help="permit force output. OFF by default: everything works identically without it.")
    args = ap.parse_args()

    name, detected, caps = discover()
    device_class = args.device_class or detected
    if args.device_class and args.device_class != detected:
        print("[ffb] class OVERRIDDEN: detected %r, using %r" % (detected, args.device_class), flush=True)
    args.device_class = device_class

    rungs = ladder(args.device_class)
    if not rungs:
        print("no ladder for class %r" % args.device_class)
        return 2
    idx = max(1, min(args.rung, len(rungs)))
    rung = rungs[idx - 1]

    print("[ffb] device class : %s" % args.device_class, flush=True)
    print("[ffb] ceiling      : %.2f of device maximum" % CEILING[args.device_class], flush=True)
    print("[ffb] ladder       : %s" % ", ".join("%.2f" % r for r in rungs), flush=True)
    print("[ffb] starting rung: %d of %d (%.2f)  <-- start at 1 and stop when a rung adds nothing"
          % (idx, len(rungs), rung), flush=True)
    if args.device_class in ("unknown", "direct_drive"):
        print("[ffb] NOTE: this class is untested by the authors. The ceiling is deliberately low and is a"
              " starting point for testing, not a tuned value.", flush=True)

    # Input first, and independent of everything else: steering and pedals must work whether or not NCM is
    # running, whether or not force feedback armed, and whether or not the telemetry bridge ever connects.
    rig = None
    if not args.no_input:
        rig = Input(steer_degrees=args.steer_degrees, wheel_range=args.wheel_range,
                    profile_path=args.profiles)
        why_in = rig.open()
        if why_in:
            print("[in ] INPUT UNAVAILABLE: %s" % why_in, flush=True)
            rig = None
        else:
            rig.start()

    mixer = Mixer(args.device_class, rung, armed=args.arm)
    mixer.rig = rig
    mixer.device_name, mixer.caps = name, caps
    if args.arm:
        out = Output(args.device_class)
        out.index = args.device
        why = out.open()
        if why:
            print("[ffb] ARM FAILED: %s" % why, flush=True)
            if "Resetting device" in why or "HapticOpen" in why:
                # Observed 2026-09-24: SDL can NAME the G29 but cannot open its haptics while Cyberpunk is
                # already running. DirectInput force feedback is an exclusive acquisition and the first
                # process to take it keeps it, so the order of startup decides who gets the wheel.
                print("[ffb] SDL can see the device but cannot acquire it. Force feedback is an EXCLUSIVE",
                      flush=True)
                print("[ffb] acquisition -- whichever process takes it first keeps it. Start this companion",
                      flush=True)
                print("[ffb] BEFORE the game (build-ffb-companion.ps1 -InstallStartup does that for you).",
                      flush=True)
                print("[ffb] Also check that Logitech G HUB is running, which Logitech wheels need for SDL",
                      flush=True)
                print("[ffb] haptics to be exposed at all.", flush=True)
            print("[ffb] continuing with telemetry only.", flush=True)
            mixer.armed = False
        else:
            mixer.out = out
            # Output has just opened the device, so it knows the name and capabilities first-hand. Use those
            # rather than the earlier open/close probe -- one open, one source of truth.
            if out.name:
                mixer.device_name, mixer.caps = out.name, out.caps
            print("[ffb] armed via %s effect" % out.mode, flush=True)
    print("[ffb] device       : %s" % (name or "none detected"), flush=True)
    print("[ffb] force output : %s" % ("ARMED" if args.arm else "disarmed (telemetry only)"), flush=True)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.port))
    srv.listen(4)
    print("[ffb] listening on http://127.0.0.1:%d/bridge.html  --  now run /ncm.ffb on in game"
          % args.port, flush=True)
    if args.monitor and rig is not None:
        def watch():
            while True:
                time.sleep(0.25)
                d = rig.last
                if d:
                    print("[in ] raw=%+.3f -> steer=%+.3f | throttle=%.2f | brake=%.2f"
                          % (d.get("raw", 0), d.get("steer", 0), d.get("throttle", 0), d.get("brake", 0)),
                          flush=True)
        threading.Thread(target=watch, daemon=True).start()

    try:
        while True:
            conn, addr = srv.accept()
            threading.Thread(target=serve, args=(conn, addr, mixer, args.port), daemon=True).start()
    except KeyboardInterrupt:
        pass
    finally:
        # Unconditional. Ctrl-C, an unhandled exception, a closed window -- every one of them ends with the
        # wheel quiet, because the alternative is a device left oscillating by a process that no longer runs.
        mixer.silence()
        if mixer.out is not None:
            mixer.out.close()
        if rig is not None:
            rig.stop()
        srv.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
