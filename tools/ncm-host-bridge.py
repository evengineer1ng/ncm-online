#!/usr/bin/env python3
"""NCM host bridge (L327): the local link between NCM (the dev server) and a physical host on this PC (Assetto Corsa).

NCM stays canonical. This process only: writes AC's race.ini for an embodiment request, hands the AC-side NCM app its
handoff (the Machine's arrival state, its installed components, the NPC field at its current canonical positions), launches
AC, and queues what the AC app reports back (telemetry, departure, results) for the server to poll.

  POST /embody         (server)  -> 200 launched | 409 why not
  GET  /handoff        (AC app)  -> the current handoff JSON
  POST /ac/event       (AC app)  -> queue {type: telemetry|departed|result|probe, ...}
  GET  /events?since=N (server)  -> {"next": M, "events": [...]}
  GET  /status                   -> bridge + AC state

Loopback only. Started by tools/o77-server.ps1 on the development box; log in tools/assetto/bridge.log.
"""
import configparser
import datetime
import io
import json
import os
import shutil
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
AC = r"C:\Program Files (x86)\Steam\steamapps\common\assettocorsa"
DOCS = os.path.join(os.path.expanduser("~"), "Documents", "Assetto Corsa")
RACE_INI = os.path.join(DOCS, "cfg", "race.ini")
APP_SRC = os.path.join(ROOT, "ncm", "assetto", "apps", "lua", "NCM")
APP_DST = os.path.join(AC, "apps", "lua", "NCM")
LOG = os.path.join(ROOT, "tools", "assetto", "bridge.log")
PORT = 47710

lock = threading.Lock()
handoff = None
events = []


def log(fmt, *a):
    line = "%s %s" % (datetime.datetime.now().strftime("%H:%M:%S"), fmt % a)
    print(line, flush=True)
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")


# ---------------------------------------------------------------------------------------------- focus (owner, 2026-10-06)
# "AC opened but did not become the foreground application ... I had to use the Windows key from a tablet." NCM knows
# when the physical representation changes hands, so it moves the foreground with it: AC's window when it exists and
# again when the session is live (the AC app's probes), Cyberpunk's when AC goes away. Windows only lets the foreground
# process hand the foreground on; a hidden background process like this one is refused unless it uses the documented
# workarounds: a synthetic Alt press (the "last input event" rule) plus AttachThreadInput to the current foreground
# thread. Every attempt is VERIFIED (GetForegroundWindow) and logged, never assumed.
import ctypes
from ctypes import wintypes

_u32 = ctypes.windll.user32
_k32 = ctypes.windll.kernel32
_EnumProc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
_u32.GetForegroundWindow.restype = wintypes.HWND
_u32.GetWindowThreadProcessId.restype = wintypes.DWORD


def _pids(image):
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq %s" % image, "/FO", "CSV", "/NH"], capture_output=True, text=True).stdout
    pids = set()
    for line in out.splitlines():
        parts = [p.strip('"') for p in line.split('","')]
        if len(parts) > 1 and parts[0].lower() == image.lower():
            try:
                pids.add(int(parts[1]))
            except ValueError:
                pass
    return pids


def _window_of(image):
    """The largest visible top-level window of a process image, or None."""
    pids = _pids(image)
    if not pids:
        return None
    found = []

    def cb(hwnd, _):
        pid = wintypes.DWORD()
        _u32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value in pids and _u32.IsWindowVisible(hwnd):
            r = wintypes.RECT()
            _u32.GetWindowRect(hwnd, ctypes.byref(r))
            found.append(((r.right - r.left) * (r.bottom - r.top), hwnd))
        return True
    _u32.EnumWindows(_EnumProc(cb), 0)
    return max(found)[1] if found else None


def bring_forward(image, why):
    hwnd = _window_of(image)
    if not hwnd:
        return False
    if _u32.GetForegroundWindow() == hwnd:
        return True
    if _u32.IsIconic(hwnd):
        _u32.ShowWindow(hwnd, 9)                       # SW_RESTORE
    fg = _u32.GetForegroundWindow()
    fg_thread = _u32.GetWindowThreadProcessId(fg, None) if fg else 0
    me = _k32.GetCurrentThreadId()
    target_thread = _u32.GetWindowThreadProcessId(hwnd, None)
    _u32.keybd_event(0x12, 0, 0, 0)                   # Alt down / up: we become the last-input process
    _u32.keybd_event(0x12, 0, 2, 0)
    if fg_thread and fg_thread != me:
        _u32.AttachThreadInput(me, fg_thread, True)
    if target_thread and target_thread != me:
        _u32.AttachThreadInput(me, target_thread, True)
    _u32.BringWindowToTop(hwnd)
    _u32.SetForegroundWindow(hwnd)
    _u32.SetFocus(hwnd)
    if fg_thread and fg_thread != me:
        _u32.AttachThreadInput(me, fg_thread, False)
    if target_thread and target_thread != me:
        _u32.AttachThreadInput(me, target_thread, False)
    ok = _u32.GetForegroundWindow() == hwnd
    log("FOCUS %s (%s): %s", image, why, "foreground" if ok else "REFUSED by Windows (still on another window)")
    return ok


focus_want = {"ac_ready": False}


def handoff_watch():
    """After a launch: AC's window to the front as soon as it exists (its loading screen is AC too), again when the AC
    app says the session is live; when acs.exe has gone, Cyberpunk to the front (the way back is symmetric)."""
    import time
    t0, shown, live_done = time.time(), False, False
    while time.time() - t0 < 180 and not ac_running():
        time.sleep(0.25)
    while ac_running():
        if not shown and _window_of("acs.exe"):
            shown = bring_forward("acs.exe", "AC window appeared")
        if focus_want["ac_ready"] and not live_done:
            live_done = bring_forward("acs.exe", "session live") or live_done
            if live_done:
                focus_want["ac_ready"] = False
        time.sleep(0.25)
    focus_want["ac_ready"] = False
    for _ in range(40):
        if bring_forward("Cyberpunk2077.exe", "AC closed: back to NCM"):
            break
        time.sleep(0.25)


def ac_running():
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq acs.exe"], capture_output=True, text=True).stdout
    return "acs.exe" in out.lower()


def ensure_direct_launch():
    """KB-353: acs.exe started outside Steam is restarted by Steam as the AC LAUNCHER (menu + music), so race.ini never
    runs. steam_appid.txt beside acs.exe lets it start straight into the session (what Content Manager does)."""
    p = os.path.join(AC, "steam_appid.txt")
    if not os.path.exists(p):
        with open(p, "w", encoding="ascii") as f:
            f.write("244210")
    return os.path.exists(p)


def install_app():
    """Copy the AC-side NCM app (and its vendored core, L329) into AC -- only for an ENABLED adapter (consent)."""
    if not os.path.isdir(APP_SRC) or not adapter_enabled():
        return False
    shutil.copytree(APP_SRC, APP_DST, dirs_exist_ok=True)
    return True


# ---------------------------------------------------------------------------------------------- adapters (L329 item 7-9)
# The AC adapter SHIPS with NCM (ncm/assetto) but is only written into an Assetto Corsa installation with the player's
# consent, recorded here with every file it touched so it can be removed cleanly. History stays NCM's either way.
ADAPTERS = os.path.join(ROOT, "tools", "assetto", "adapters.json")
BACKUP = os.path.join(ROOT, "tools", "assetto", "backup")


def adapters():
    try:
        with open(ADAPTERS, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_adapters(a):
    os.makedirs(os.path.dirname(ADAPTERS), exist_ok=True)
    with open(ADAPTERS, "w", encoding="utf-8") as f:
        json.dump(a, f, indent=2)


def adapter_enabled():
    return bool((adapters().get("assetto_corsa") or {}).get("enabled"))


def adapter_enable(why):
    a = adapters()
    rec = a.get("assetto_corsa") or {"files": []}
    os.makedirs(BACKUP, exist_ok=True)
    if os.path.exists(RACE_INI) and not os.path.exists(os.path.join(BACKUP, "race.ini.pre-ncm")) and not rec.get("raceIniBackup"):
        shutil.copyfile(RACE_INI, os.path.join(BACKUP, "race.ini.pre-ncm"))
        rec["raceIniBackup"] = os.path.join(BACKUP, "race.ini.pre-ncm")
    appid = os.path.join(AC, "steam_appid.txt")
    if not os.path.exists(appid):
        rec["steamAppIdCreated"] = True
    rec.update({"enabled": True, "enabledAt": datetime.datetime.now().isoformat(timespec="seconds"), "why": why,
                "appDir": APP_DST})
    a["assetto_corsa"] = rec
    save_adapters(a)
    install_app()
    ensure_direct_launch()
    free_triangle()
    log("ADAPTER assetto_corsa ENABLED (%s): app at %s", why, APP_DST)


def adapter_disable(why):
    a = adapters()
    rec = a.get("assetto_corsa") or {}
    if os.path.isdir(APP_DST):
        shutil.rmtree(APP_DST, ignore_errors=True)
    appid = os.path.join(AC, "steam_appid.txt")
    if rec.get("steamAppIdCreated") and os.path.exists(appid):
        os.remove(appid)
    if rec.get("raceIniBackup") and os.path.exists(rec["raceIniBackup"]):
        shutil.copyfile(rec["raceIniBackup"], RACE_INI)
    if rec.get("hornButtonOriginal"):
        _horn_button(rec["hornButtonOriginal"])
        rec.pop("hornButtonOriginal", None)
    rec.update({"enabled": False, "disabledAt": datetime.datetime.now().isoformat(timespec="seconds"), "disabledWhy": why})
    a["assetto_corsa"] = rec
    save_adapters(a)
    log("ADAPTER assetto_corsa DISABLED (%s): app removed%s%s", why, ", steam_appid.txt removed" if rec.get("steamAppIdCreated") else "",
        ", race.ini restored" if rec.get("raceIniBackup") else " (no pre-NCM race.ini backup exists)")


CONTROLS_INI = os.path.join(DOCS, "cfg", "controls.ini")


def _horn_button(new=None):
    """[ACTION_HORN] XBOXBUTTON in AC's controls.ini: read it, or set it (returns the previous value)."""
    try:
        with open(CONTROLS_INI, encoding="utf-8-sig", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return None
    sec, old = None, None
    for i, line in enumerate(lines):
        t = line.strip()
        if t.startswith("[") and t.endswith("]"):
            sec = t
        elif sec == "[ACTION_HORN]" and t.upper().startswith("XBOXBUTTON="):
            old = t.split("=", 1)[1]
            if new is not None and old != new:
                lines[i] = "XBOXBUTTON=" + new
                with open(CONTROLS_INI, "w", encoding="utf-8") as f:
                    f.write("\n".join(lines) + "\n")
            break
    return old


def free_triangle():
    """KB-359: AC binds the pad's Y to the HORN, and Y is the Machine's Triangle (IA-10 tap, RP-16 hold): pressing it honked
    while the hop fired. Adapter-owned: the original is recorded and put back when the adapter is disabled."""
    a = adapters()
    rec = a.get("assetto_corsa") or {}
    cur = _horn_button()
    if cur and cur.upper() == "Y":
        rec.setdefault("hornButtonOriginal", cur)
        _horn_button("-1")
        a["assetto_corsa"] = rec
        save_adapters(a)
        log("ADAPTER assetto_corsa: AC's horn moved off the pad's Y (Triangle is the Machine's); restored on disable")


def adapter_migrate():
    """The dev install predates consent (owner ran it, L327): record it as enabled, honestly."""
    a = adapters()
    if "assetto_corsa" not in a and os.path.isdir(APP_DST):
        a["assetto_corsa"] = {"enabled": True, "enabledAt": datetime.datetime.now().isoformat(timespec="seconds"),
                              "why": "migrated: installed during L327 development by the owner's runs (no prompt existed)",
                              "steamAppIdCreated": True, "raceIniBackup": None, "appDir": APP_DST,
                              "note": "AC's controls.ini X360 change (2026-10-06) is the owner's pad fix, not adapter-owned"}
        save_adapters(a)
        log("ADAPTER assetto_corsa: existing dev install recorded as enabled (no pre-NCM race.ini backup exists)")


# ---------------------------------------------------------------------------------------------- the universe relay (L329)
universe = {}             # what the NCM server publishes (utc, Race Week, driver records, places)
ac_checkpoint = {"seq": 0, "data": None}
places_out = []           # host-location observations for the server (scan + CSP reports)
ac_commands = []          # commands for the AC app (release ...)
lifecycle = {"from_cyberpunk": False, "cp_launched": False, "cp_ready": False}


def scan_tracks():
    """Every AC track/layout and its ui_track.json geotags, for space.places (never trusted blindly)."""
    root = os.path.join(AC, "content", "tracks")
    out = []
    if not os.path.isdir(root):
        return out
    for t in sorted(os.listdir(root)):
        ui = os.path.join(root, t, "ui")
        for dp, _, fs in os.walk(ui):
            if "ui_track.json" in fs:
                try:
                    with open(os.path.join(dp, "ui_track.json"), encoding="utf-8-sig", errors="replace") as f:
                        d = json.load(f)
                except (OSError, ValueError):
                    d = {}
                layout = os.path.relpath(dp, ui).replace("\\", "/")
                out.append({"host": "assetto_corsa", "track": t, "layout": "" if layout == "." else layout,
                            "name": d.get("name"), "geotags": d.get("geotags")})
    return out


# ---------------------------------------------------------------------------------------------- host lifecycle (L329 item 6)
CP_EXE = r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077\bin\x64\Cyberpunk2077.exe"


def cp_running():
    return bool(_pids("Cyberpunk2077.exe"))


def launch_cyberpunk(why):
    """Cyberpunk into the NCM dev world, exactly as the OPEN//77 launcher does for this PC (its launch log line)."""
    if cp_running() or lifecycle["cp_launched"]:
        return False
    connect, master = "127.0.0.1:11778", "alpha"
    try:
        with open(os.path.join(os.environ.get("LOCALAPPDATA", ""), "Open77", "launcher.log"), encoding="utf-8", errors="replace") as f:
            for line in f:
                if "launched pid" in line and "OP77_CONNECT=" in line:
                    connect = line.split("OP77_CONNECT=")[1].split()[0]
                    if "OP77_CONNECT_MASTER=" in line:
                        master = line.split("OP77_CONNECT_MASTER=")[1].split()[0]
    except OSError:
        pass
    env = dict(os.environ, OP77_CONNECT=connect, OP77_CONNECT_MASTER=master, OP77_WORLD_SERVER="-", OP77_WORLD_MODS_DIGEST="-",
               SteamAppId="1091500", SteamGameId="1091500")
    subprocess.Popen([CP_EXE], cwd=os.path.dirname(CP_EXE), env=env)
    lifecycle["cp_launched"], lifecycle["cp_ready"] = True, False
    log("LIFECYCLE launch Cyberpunk (%s) -> %s/%s, in the background", why, connect, master)
    threading.Thread(target=cp_wake, daemon=True).start()
    return True


def cp_wake():
    """Cyberpunk boots to a 'press any key' screen. Press it for the player without taking the foreground (PostMessage
    to the window); verified only by the server later saying the client resumed."""
    import time
    t0 = time.time()
    while time.time() - t0 < 240 and not lifecycle["cp_ready"]:
        hwnd = _window_of("Cyberpunk2077.exe")
        if hwnd and time.time() - t0 > 45:
            for vk in (0x20, 0x0D):       # space, enter
                _u32.PostMessageW(hwnd, 0x0100, vk, 0)
                _u32.PostMessageW(hwnd, 0x0101, vk, 0)
        time.sleep(5)
    log("LIFECYCLE Cyberpunk %s after %.0f s", "READY" if lifecycle["cp_ready"] else "NOT ready (left running; canonical state kept)", time.time() - t0)


def close_gracefully(image, why, wait_s=45):
    import time
    hwnd = _window_of(image)
    if not hwnd:
        return True
    _u32.PostMessageW(hwnd, 0x0010, 0, 0)      # WM_CLOSE
    log("LIFECYCLE close %s (%s): WM_CLOSE sent", image, why)
    t0 = time.time()
    while time.time() - t0 < wait_s and _pids(image):
        time.sleep(1)
    if _pids(image):
        subprocess.run(["taskkill", "/IM", image], capture_output=True)
        log("LIFECYCLE close %s: still running after %d s, taskkill (graceful) sent", image, wait_s)
        t1 = time.time()
        while time.time() - t1 < 30 and _pids(image):
            time.sleep(1)
    if _pids(image):
        # receipt was verified before we got here and NCM holds the state: ending it loses nothing, leaving it piles hosts up
        subprocess.run(["taskkill", "/F", "/IM", image], capture_output=True)
        log("LIFECYCLE close %s: refused WM_CLOSE and taskkill -- ended (/F); the state was already NCM's", image)
        time.sleep(2)
    gone = not _pids(image)
    log("LIFECYCLE %s %s", image, "closed" if gone else "STILL RUNNING (could not be ended; nothing is lost: NCM holds the state)")
    return gone


def after_physicalized():
    """Cyberpunk -> AC: the AC app has the Machine (airborneSpawn). Only now may Cyberpunk go."""
    if lifecycle["from_cyberpunk"] and cp_running():
        lifecycle["from_cyberpunk"] = False
        threading.Thread(target=close_gracefully, args=("Cyberpunk2077.exe", "AC acknowledged the Machine"), daemon=True).start()


def after_cyberpunk_ready():
    """AC -> Cyberpunk: the server says the Cyberpunk client resumed the Machine. Focus it, release AC, close AC."""
    lifecycle["cp_ready"] = True
    bring_forward("Cyberpunk2077.exe", "Cyberpunk has the Machine")
    if not ac_running():
        lifecycle["cp_launched"] = False
        return   # nothing to release (KB-361)
    with lock:
        ac_commands.append({"cmd": "release", "why": "Cyberpunk has the Machine"})

    def wait_ac():
        import time
        t0 = time.time()
        while time.time() - t0 < 20 and ac_running():
            time.sleep(1)
        if ac_running():
            close_gracefully("acs.exe", "the Machine is in Cyberpunk")
        lifecycle["cp_launched"] = False
    threading.Thread(target=wait_ac, daemon=True).start()


def skin_for(car, key):
    """A real skin folder of `car`, picked by a stable hash of `key` (AC wants one; blank is not safe)."""
    d = os.path.join(AC, "content", "cars", car, "skins")
    skins = sorted(x for x in os.listdir(d) if os.path.isdir(os.path.join(d, x))) if os.path.isdir(d) else []
    if not skins:
        return ""
    h = 0
    for ch in str(key):
        h = (h * 31 + ord(ch)) % 4294967296
    return skins[h % len(skins)]


def write_race_ini(h):
    """Patch AC's OWN race.ini (created by its first run): track, layout, the player's body, the NCM field, the sun."""
    cp = configparser.ConfigParser(strict=False, interpolation=None)
    cp.optionxform = str
    cp.read(RACE_INI, encoding="utf-8-sig")
    venue, body = h["venue"], h["body"]
    st = h.get("state") or {}
    cars = st.get("cars") or []
    for sec in [s for s in cp.sections() if s.startswith("CAR_")]:
        cp.remove_section(sec)
    if not cp.has_section("RACE"):
        cp.add_section("RACE")
    layout = h.get("layout") or ""
    cp["RACE"]["TRACK"] = venue["track"]
    cp["RACE"]["CONFIG_TRACK"] = layout
    cp["RACE"]["MODEL"] = body["car"]
    cp["RACE"]["CARS"] = str(1 + len(cars))
    cp["RACE"]["AI_LEVEL"] = "95"
    cp["RACE"]["FIXED_SETUP"] = "0"
    cp["RACE"]["PENALTIES"] = "0"
    cp["CAR_0"] = {"MODEL": body["car"], "SKIN": skin_for(body["car"], "player"), "DRIVER_NAME": "NCM Machine", "NATIONALITY": "", "AI": "0"}
    for i, c in enumerate(cars, start=1):
        cp["CAR_%d" % i] = {"MODEL": c["car"], "SKIN": skin_for(c["car"], c.get("id") or c["name"]), "DRIVER_NAME": c["name"], "NATIONALITY": "", "AI": "1",
                            "AI_LEVEL": str(int(80 + 20 * float(c.get("pace") or 0.5)))}
    # the session: the laps that are LEFT of the canonical race (the AC lap counter starts at 0: an expression loss)
    laps_left = max(1, int((st.get("laps") or 5) - max(0, (st.get("leaderLap") or 1) - 1)))
    for sec in [s for s in cp.sections() if s.startswith("SESSION_")]:
        cp.remove_section(sec)
    # L330: the session the Racing Week's timetable says is on NOW, for the time it has left
    ses = h.get("session") or {"kind": "race"}
    kind = ses.get("kind") or "race"
    mins = str(max(5, int((ses.get("remainingS") or 1800) / 60)))
    if kind in ("race", "grid"):
        cp["SESSION_0"] = {"NAME": "Race", "TYPE": "3", "LAPS": str(laps_left), "DURATION_MINUTES": "0", "SPAWN_SET": "START"}
    elif kind == "qualifying":
        cp["SESSION_0"] = {"NAME": "Qualify", "TYPE": "2", "DURATION_MINUTES": mins, "SPAWN_SET": "PIT"}
    else:   # practice, track day, closed (dark: no field)
        cp["SESSION_0"] = {"NAME": "Practice" if kind == "practice" else "Track day", "TYPE": "1", "DURATION_MINUTES": mins, "SPAWN_SET": "PIT"}
    if kind == "closed":
        for sec in [s for s in cp.sections() if s.startswith("CAR_") and s != "CAR_0"]:
            cp.remove_section(sec)
        cp["RACE"]["CARS"] = "1"
    if not cp.has_section("LIGHTING"):
        cp.add_section("LIGHTING")
    sun = float(h.get("sunAngle") or 0)
    cp["LIGHTING"]["SUN_ANGLE"] = str(int(max(-80, min(80, sun))))   # vanilla range; CSP time-of-day beyond it: TODO probe
    cp["LIGHTING"]["TIME_MULT"] = "1"
    buf = io.StringIO()
    cp.write(buf, space_around_delimiters=False)
    with open(RACE_INI, "w", encoding="utf-8") as f:
        f.write(buf.getvalue())
    return laps_left


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send_json(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_json(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b"{}"
        try:
            return json.loads(raw.decode("utf-8") or "{}")
        except ValueError:
            return {}

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/handoff":
            with lock:
                return self.send_json(200, handoff or {})
        if u.path == "/events":
            since = int((parse_qs(u.query).get("since") or ["0"])[0])
            with lock:
                return self.send_json(200, {"next": len(events), "events": events[since:]})
        if u.path == "/universe":     # the AC app (L329): the same clock, Race Week and canonical records
            with lock:
                return self.send_json(200, dict(universe, adapter=adapters().get("assetto_corsa") or {}))
        if u.path == "/ac/command":
            with lock:
                out = list(ac_commands)
                ac_commands.clear()
            return self.send_json(200, {"commands": out})
        if u.path == "/canonical":    # the server: AC checkpoints + host-location observations
            since = int((parse_qs(u.query).get("since") or ["0"])[0])
            with lock:
                cp = ac_checkpoint["data"] if ac_checkpoint["seq"] > since else None
                pl = list(places_out)
                places_out.clear()
                return self.send_json(200, {"seq": ac_checkpoint["seq"], "checkpoint": cp, "places": pl})
        if u.path == "/adapter":
            return self.send_json(200, adapters().get("assetto_corsa") or {"enabled": False})
        if u.path == "/status":
            return self.send_json(200, {"ac": AC, "acInstalled": os.path.exists(os.path.join(AC, "acs.exe")),
                                        "csp": os.path.exists(os.path.join(AC, "dwrite.dll")), "firstRunDone": os.path.exists(RACE_INI),
                                        "acRunning": ac_running(), "handoff": bool(handoff), "events": len(events)})
        self.send_json(404, {"error": "no such path"})

    def do_POST(self):
        global handoff
        u = urlparse(self.path)
        body = self.read_json()
        if u.path == "/embody":
            v = body.get("venue") or {}
            if not os.path.exists(RACE_INI):
                log("EMBODY %s refused: Assetto Corsa has never been run on this PC (no %s)", v.get("id"), RACE_INI)
                return self.send_json(409, {"why": "Assetto Corsa needs its first run on this PC"})
            if ac_running():
                return self.send_json(409, {"why": "Assetto Corsa is already running"})
            if not adapter_enabled():
                log("EMBODY %s: the NCM Assetto Corsa adapter is not enabled -- asking the player first", v.get("id"))
                return self.send_json(409, {"why": "adapter_not_enabled", "offer": True})
            with lock:
                handoff = body
                ac_commands.clear()   # KB-361: a 'release' queued at 16:37 (no AC running) closed the 16:50 AC on its first poll
            lifecycle["from_cyberpunk"] = cp_running()
            app = install_app()
            direct = ensure_direct_launch()
            free_triangle()
            if not direct:
                log("EMBODY %s: no steam_appid.txt -- Steam will open the AC launcher instead of the session", v.get("id"))
            laps = write_race_ini(body)
            subprocess.Popen([os.path.join(AC, "acs.exe")], cwd=AC)
            threading.Thread(target=handoff_watch, daemon=True).start()
            log("EMBODY %s/%s body=%s field=%d laps-left=%s sun=%.0f app=%s -> acs.exe launched", v.get("id"), body.get("layout"),
                (body.get("body") or {}).get("car"), len(((body.get("state") or {}).get("cars")) or []), laps, float(body.get("sunAngle") or 0), app)
            return self.send_json(200, {"launched": True, "lapsLeft": laps})
        if u.path == "/universe":
            with lock:
                universe.clear()
                universe.update(body)
            return self.send_json(200, {"ok": True})
        if u.path == "/adapter/enable":
            adapter_enable(str(body.get("why") or "player consent"))
            return self.send_json(200, {"enabled": True})
        if u.path == "/adapter/disable":
            adapter_disable(str(body.get("why") or "player request"))
            return self.send_json(200, {"enabled": False})
        if u.path == "/host/loop":    # the server: the Racing Week reset (L330) -- AC closes, Cyberpunk is where you wake
            log("LIFECYCLE Racing Week reset: AC (if open) closes; Night City next")
            with lock:
                ac_commands.append({"cmd": "loop", "why": body.get("why")})

            def after_loop():
                import time
                t0 = time.time()
                while time.time() - t0 < 20 and ac_running():
                    time.sleep(1)
                if ac_running():
                    close_gracefully("acs.exe", "the Racing Week reset")
                if not cp_running():
                    launch_cyberpunk("the Racing Week reset: you wake in Night City")
            if ac_running():
                threading.Thread(target=after_loop, daemon=True).start()
            return self.send_json(200, {"ok": True})
        if u.path == "/host/ready":   # the server: a host acknowledged the Machine
            if body.get("host") == "cyberpunk":
                log("LIFECYCLE server: Cyberpunk has the Machine (%s)", body.get("why"))
                after_cyberpunk_ready()
            return self.send_json(200, {"ok": True})
        if u.path == "/ac/event":
            with lock:
                body["at"] = datetime.datetime.now().isoformat(timespec="seconds")
                events.append(body)
            if body.get("type") not in ("telemetry", "canonical"):
                log("AC %s %s", body.get("type"), json.dumps(body)[:400])
            # the session is live once the app has started it or placed the Machine: that is when the player must see it
            if body.get("type") == "probe" and body.get("what") in ("autoStart", "airborneSpawn"):
                focus_want["ac_ready"] = True
            if body.get("type") == "probe" and body.get("what") == "airborneSpawn":
                after_physicalized()
            if body.get("type") == "canonical":
                with lock:
                    ac_checkpoint["seq"] += 1
                    ac_checkpoint["data"] = body
            if body.get("type") == "place":
                with lock:
                    places_out.append(body.get("observation") or {})
            if body.get("type") == "approach" and body.get("target") == "night_city":
                launch_cyberpunk("the Machine is approaching Night City from Deep (AC)")
            return self.send_json(200, {"ok": True})
        self.send_json(404, {"error": "no such path"})


if __name__ == "__main__":
    log("NCM host bridge on 127.0.0.1:%d | AC %s | CSP %s | first run done %s", PORT, os.path.exists(AC),
        os.path.exists(os.path.join(AC, "dwrite.dll")), os.path.exists(RACE_INI))
    adapter_migrate()
    scanned = scan_tracks()
    with lock:
        places_out.extend(scanned)
    log("PLACES scanned %d AC track layout(s) for the registry", len(scanned))
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
