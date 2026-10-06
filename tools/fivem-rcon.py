#!/usr/bin/env python3
"""Send one console command to the local NCM Los Santos FXServer over rcon (L319; doc 53).

    python tools/fivem-rcon.py restart ncm_ls_space
    python tools/fivem-rcon.py ncm.ls.status

The password is the one tools/fivem-server.ps1 generated in tools/fivem/rcon.pw (gitignored). Localhost only.
"""
import os
import socket
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
pw = open(os.path.join(HERE, "fivem", "rcon.pw"), encoding="ascii").read().strip()
cmd = " ".join(sys.argv[1:]) or "status"
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(3)
s.sendto(b"\xff\xff\xff\xffrcon " + pw.encode() + b" " + cmd.encode(), ("127.0.0.1", 30120))
try:
    data, _ = s.recvfrom(65535)
    sys.stdout.write(data[4:].decode("utf-8", "replace").removeprefix("print"))
except socket.timeout:
    print("(no reply in 3 s -- is FXServer running, and was it started with rcon? see tools/fivem-server.ps1)")
