#!/usr/bin/env python3
"""NCM -> OpenSpace, probe 0 (L325 P0). The first incision of IDEA-1128: NCM owns an object's state; OpenSpace draws it.

Connects to a running OpenSpace (TCP 4681, newline-delimited JSON -- read from OpenSpace's own src/topic/connection.cpp and
openspace-api-js), creates one scene-graph node over Night City's place on Earth, points the camera at it, then moves it
from out here at a fixed rate and reports how fast OpenSpace accepted the updates. Nothing in OpenSpace is modified.

Usage:  python prototypes/ncm_openspace/probe.py [--rate 60] [--seconds 30] [--lat 35.37 --lon -120.85] [--password X]
"""
import argparse
import json
import socket
import time

API_HANDSHAKE = {"type": "apiHandshake", "apiVersion": {"major": 1, "minor": 0, "patch": 0}}


class OpenSpace:
    def __init__(self, host="127.0.0.1", port=4681):
        self.sock = socket.create_connection((host, port), timeout=5)
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.topic = 0
        self.buf = b""
        self.send(API_HANDSHAKE)

    def send(self, obj):
        self.sock.sendall((json.dumps(obj) + "\n").encode("utf-8"))

    def start(self, type_, payload):
        self.topic += 1
        self.send({"topic": self.topic, "type": type_, "payload": payload})
        return self.topic

    def lua(self, script, want=False):
        t = self.start("luascript", {"script": script, "return": want, "shouldBeSynchronized": True})
        return self.read_topic(t) if want else None

    def read_topic(self, topic, timeout=5.0):
        self.sock.settimeout(timeout)
        end = time.time() + timeout
        while time.time() < end:
            while b"\n" in self.buf:
                line, self.buf = self.buf.split(b"\n", 1)
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                if msg.get("topic") == topic:
                    return msg.get("payload")
            chunk = self.sock.recv(65536)
            if not chunk:
                break
            self.buf += chunk
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rate", type=float, default=60.0)
    ap.add_argument("--seconds", type=float, default=30.0)
    ap.add_argument("--lat", type=float, default=35.37)    # IDEA-1133 placeholder: the Central California coast
    ap.add_argument("--lon", type=float, default=-120.85)
    ap.add_argument("--alt", type=float, default=4000.0)   # metres; Cyberpunk's cloud band
    ap.add_argument("--climb", type=float, default=300.0)  # m/s straight up
    ap.add_argument("--password", default=None)
    ap.add_argument("--node", default="NcmMachine")
    a = ap.parse_args()

    os_ = OpenSpace()
    if a.password:
        print("authorize:", os_.read_topic(os_.start("authorize", {"password": a.password})))
    print("version:", os_.lua("return openspace.version and openspace.version() or 'n/a'", want=True))

    os_.lua(f'if openspace.hasSceneGraphNode("{a.node}") then openspace.removeSceneGraphNode("{a.node}") end')
    node = f'''openspace.addSceneGraphNode({{
        Identifier = "{a.node}", Parent = "Earth",
        Transform = {{ Translation = {{ Type = "GlobeTranslation", Globe = "Earth",
            Latitude = {a.lat}, Longitude = {a.lon}, Altitude = {a.alt}, UseHeightmap = false }},
            Rotation = {{ Type = "GlobeRotation", Globe = "Earth", Latitude = {a.lat}, Longitude = {a.lon} }},
            Scale = {{ Type = "StaticScale", Scale = 200 }} }},
        Renderable = {{ Type = "RenderableCartesianAxes", Enabled = true }},
        GUI = {{ Name = "NCM Machine (probe)", Path = "/NCM" }}
    }})'''
    os_.lua(node)
    os_.lua(f'openspace.setPropertyValueSingle("NavigationHandler.OrbitalNavigator.Anchor", "{a.node}")')
    os_.lua('openspace.setPropertyValueSingle("NavigationHandler.OrbitalNavigator.Aim", "")')
    os_.lua('openspace.setPropertyValueSingle("NavigationHandler.OrbitalNavigator.RetargetAnchor", nil)')
    print(f"node {a.node} over ({a.lat}, {a.lon}) at {a.alt:.0f} m; camera anchored. Climbing {a.climb:.0f} m/s at {a.rate:.0f} Hz for {a.seconds:.0f} s")

    period = 1.0 / a.rate
    t0 = time.perf_counter()
    nxt, sent, worst = t0, 0, 0.0
    while True:
        now = time.perf_counter()
        el = now - t0
        if el >= a.seconds:
            break
        alt = a.alt + a.climb * el
        s = time.perf_counter()
        os_.lua(f'openspace.setPropertyValueSingle("Scene.{a.node}.Translation.Altitude", {alt:.3f})')
        worst = max(worst, time.perf_counter() - s)
        sent += 1
        nxt += period
        delay = nxt - time.perf_counter()
        if delay > 0:
            time.sleep(delay)
    el = time.perf_counter() - t0
    back = os_.lua(f'return openspace.propertyValue("Scene.{a.node}.Translation.Altitude")', want=True)
    print(f"sent {sent} updates in {el:.2f} s = {sent / el:.1f} Hz (worst send {worst * 1000:.1f} ms); OpenSpace now reports altitude {back}")


if __name__ == "__main__":
    main()
