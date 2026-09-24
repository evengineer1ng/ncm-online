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
import hashlib
import json
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
        return {
            "name": self.device_name or "no haptic device",
            "class": self.device_class,
            "rung": idx, "rungs": rungs, "armed": self.armed, "haptics": self.caps,
        }

    def feed(self, f: dict) -> float:
        now = time.monotonic()
        dt, self.last = now - self.last, now

        if f.get("idle"):
            self.idles += 1
            self.level = slew(self.level, 0.0, dt)
            return self.level

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
            return self.level

        # The rung IS the scale. Channel weights sum to roughly 0..1.8, so the lowest rung (0.05) puts a
        # fully-loaded car at about a twentieth of the device maximum -- which is where tuning starts.
        target = clamp(self.device_class, sum(contributions) * self.rung)
        self.level = slew(self.level, target, dt)
        return self.level


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
            rung = mixer.set_rung((f.get("settings") or {}).get("rung"))
            print("[ffb] rung -> %.2f (%s)" % (rung, mixer.device_class), flush=True)
            say({"device": mixer.describe()})
            continue
        if cmd == "test":
            # A test pulse is a RAMP, never a step: the slew limiter exists precisely so nothing arrives as a
            # hammer blow, and a "test" that bypassed it would be testing something we never ship.
            print("[ffb] TEST pulse at rung %.2f, ceiling %.2f%s" %
                  (mixer.rung, CEILING.get(mixer.device_class, CEILING["unknown"]),
                   "" if mixer.armed else "  (NOT ARMED -- no force applied)"), flush=True)
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

    print("[ffb] socket closed after %d frame(s), %d idle" % (mixer.frames, mixer.idles), flush=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=38480)
    ap.add_argument("--class", dest="device_class", default=None, choices=sorted(CEILING),
                    help="override the detected class. Only ever use this to go LOWER than detection.")
    ap.add_argument("--rung", type=int, default=1, help="1-based rung on this class's ladder (default: lowest)")
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

    mixer = Mixer(args.device_class, rung, armed=args.arm)
    mixer.device_name, mixer.caps = name, caps
    print("[ffb] device       : %s" % (name or "none detected"), flush=True)
    print("[ffb] force output : %s" % ("ARMED" if args.arm else "disarmed (telemetry only)"), flush=True)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.port))
    srv.listen(4)
    print("[ffb] listening on http://127.0.0.1:%d/bridge.html  --  now run /ncm.ffb on in game"
          % args.port, flush=True)
    try:
        while True:
            conn, addr = srv.accept()
            threading.Thread(target=serve, args=(conn, addr, mixer, args.port), daemon=True).start()
    except KeyboardInterrupt:
        pass
    finally:
        srv.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
