#!/usr/bin/env python3
"""Minimal loopback WebSocket listener, for the IDEA-387 probe.

THE QUESTION: can a bundled OPEN//77 WebUI page open `ws://127.0.0.1:<port>`?

Official OPEN//77 docs say bundled and remote pages may use fetch/XHR and WS/WSS, and that localhost means
the player's PC rather than the game server. That settles what the PLATFORM allows. It does not settle what
the BROWSER allows, and there is one specific rule that could still refuse us:

    a page served from an https:// origin may not open a ws:// connection (mixed content).

Chromium treats `127.0.0.1` and `localhost` as *potentially trustworthy*, which normally exempts them from
mixed-content blocking -- but that carve-out has moved around across releases and interacts with Private
Network Access. So this is a question about the build in front of us, and the honest way to answer it is to
listen on a port and see whether the page arrives.

No dependency on `websockets`: this speaks just enough RFC 6455 to complete a handshake, read a frame and
answer. It is a diagnostic, not a server -- single connection, no masking on send, no fragmentation, no TLS.

    python tools/ws-probe-server.py [--port 38480]

Leave it running, then in the game client type `/ncm.wsprobe`. The result is printed here AND logged in the
client log, so either side alone is enough to tell what happened.
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


def _accept_key(key: str) -> str:
    return base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()


def _read_frame(conn: socket.socket) -> tuple[int, bytes] | None:
    """One frame. Clients MUST mask, so unmasking is not optional."""
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


def _send_text(conn: socket.socket, text: str) -> None:
    data = text.encode()
    header = bytearray([0x81])
    if len(data) < 126:
        header.append(len(data))
    elif len(data) < (1 << 16):
        header.append(126)
        header += struct.pack(">H", len(data))
    else:
        header.append(127)
        header += struct.pack(">Q", len(data))
    conn.sendall(bytes(header) + data)


def serve(conn: socket.socket, addr) -> None:
    print("[probe] connection from %s:%s" % addr, flush=True)
    request = b""
    while b"\r\n\r\n" not in request:
        chunk = conn.recv(4096)
        if not chunk:
            print("[probe] peer closed during handshake", flush=True)
            return
        request += chunk

    lines = request.decode(errors="replace").split("\r\n")
    headers = {}
    for line in lines[1:]:
        if ":" in line:
            name, _, value = line.partition(":")
            headers[name.strip().lower()] = value.strip()

    # `Origin` is the single most informative header here: it is what the page's own origin actually is, which
    # is precisely the "is the bundled page https?" question, answered by the client rather than guessed.
    print("[probe] request line : %s" % lines[0], flush=True)
    print("[probe] Origin       : %s" % headers.get("origin", "(none sent)"), flush=True)
    print("[probe] User-Agent   : %s" % headers.get("user-agent", "(none)"), flush=True)

    key = headers.get("sec-websocket-key")
    if not key:
        conn.sendall(b"HTTP/1.1 400 Bad Request\r\n\r\n")
        print("[probe] NOT a websocket handshake", flush=True)
        return

    conn.sendall(
        b"HTTP/1.1 101 Switching Protocols\r\n"
        b"Upgrade: websocket\r\n"
        b"Connection: Upgrade\r\n"
        b"Sec-WebSocket-Accept: " + _accept_key(key).encode() + b"\r\n\r\n"
    )
    print("[probe] HANDSHAKE OK -- the page reached us. This is the answer to IDEA-387.", flush=True)

    frames = 0
    started = time.monotonic()
    while True:
        frame = _read_frame(conn)
        if frame is None:
            break
        opcode, payload = frame
        if opcode == 0x8:
            print("[probe] close frame", flush=True)
            break
        if opcode == 0x9:                       # ping -> pong
            conn.sendall(b"\x8a\x00")
            continue
        if opcode != 0x1:
            continue
        frames += 1
        text = payload.decode(errors="replace")
        try:
            body = json.loads(text)
            pretty = json.dumps(body, indent=2, sort_keys=True)
        except Exception:
            pretty = text
        print("[probe] frame %d:\n%s" % (frames, pretty), flush=True)
        _send_text(conn, json.dumps({"ok": True, "echoed": frames}))

    print("[probe] closed after %d frame(s), %.1fs" % (frames, time.monotonic() - started), flush=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=38480)
    ap.add_argument("--host", default="127.0.0.1")
    args = ap.parse_args()

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((args.host, args.port))
    srv.listen(4)
    print("[probe] listening on ws://%s:%d  --  now type /ncm.wsprobe in the game" % (args.host, args.port),
          flush=True)
    try:
        while True:
            conn, addr = srv.accept()
            threading.Thread(target=serve, args=(conn, addr), daemon=True).start()
    except KeyboardInterrupt:
        pass
    finally:
        srv.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
