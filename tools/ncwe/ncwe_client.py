"""Minimal stdio MCP client for NCWE Studio (NCWE.Mcp.exe), so Race Week site scripts can batch-query and place.

    from ncwe_client import Ncwe
    with Ncwe() as n:
        n.call("studio_status")
        n.call("traffic", action="query", center=[x, y, z], radius=80)

Tool results come back as parsed JSON (the first text content); images are dropped.
"""
import json, os, subprocess, threading, queue

EXE = os.environ.get("NCWE_MCP", r"C:\Users\eveng\Downloads\NCWE-Studio-0.1.0-beta.1-win-x64\NCWE-Studio-0.1.0-beta.1-win-x64\NCWE.Mcp.exe")


class Ncwe:
    def __init__(self, exe=EXE, timeout=120):
        self.exe, self.timeout, self.n = exe, timeout, 0

    def __enter__(self):
        self.p = subprocess.Popen([self.exe], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.q = queue.Queue()
        threading.Thread(target=lambda: [self.q.put(l) for l in self.p.stdout], daemon=True).start()
        self._rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                 "clientInfo": {"name": "ncm-race-week", "version": "0.1"}})
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        return self

    def __exit__(self, *a):
        self.p.kill()

    def _send(self, o):
        self.p.stdin.write((json.dumps(o) + "\n").encode("utf-8"))
        self.p.stdin.flush()

    def _rpc(self, method, params):
        self.n += 1
        self._send({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params})
        while True:
            m = json.loads(self.q.get(timeout=self.timeout))
            if m.get("id") == self.n:
                if "error" in m:
                    raise RuntimeError(m["error"])
                return m["result"]

    def call(self, tool, **args):
        r = self._rpc("tools/call", {"name": tool, "arguments": args})
        for c in r.get("content", []):
            if c.get("type") == "text":
                try:
                    return json.loads(c["text"])
                except ValueError:
                    return c["text"]
        return None
