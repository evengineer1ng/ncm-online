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

    def __init__(self, device_class: str, rung: float):
        self.device_class = device_class
        self.rung = rung
        self.level = 0.0
        self.last = time.monotonic()
        self.frames = 0
        self.idles = 0

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
    ap.add_argument("--class", dest="device_class", default="unknown", choices=sorted(CEILING))
    ap.add_argument("--rung", type=int, default=1, help="1-based rung on this class's ladder (default: lowest)")
    args = ap.parse_args()

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

    mixer = Mixer(args.device_class, rung)
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
