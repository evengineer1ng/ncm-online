"""Dump vanilla TweakDB record names (default: Character.*) from CET's string table.

CET ships bin/x64/plugins/cyber_engine_tweaks/tweakdb/tweakdbstr.kark: a KARK (Oodle) blob holding every
TweakDB name. The game's own oo2ext DLL decompresses it. No game data leaves the machine; this is a lookup
for authoring (e.g. `/ncm.au dress npc Character.<record>`, Open77.npcs.create wants a vanilla record).

Usage (64-bit python):  python tools\tweakdb-names.py [prefix] [grep] > out.txt
  python tools\tweakdb-names.py Character. spectator
"""
import ctypes, os, re, struct, sys

GAME = os.environ.get("CP77_DIR", r"C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077")
prefix = sys.argv[1] if len(sys.argv) > 1 else "Character."
needle = sys.argv[2].lower() if len(sys.argv) > 2 else None

dll = ctypes.WinDLL(os.path.join(GAME, "bin", "x64", "oo2ext_7_win64.dll"))
data = open(os.path.join(GAME, "bin", "x64", "plugins", "cyber_engine_tweaks", "tweakdb", "tweakdbstr.kark"), "rb").read()
assert data[:4] == b"KARK", "not a KARK blob"
raw_len = struct.unpack_from("<I", data, 4)[0]
out = ctypes.create_string_buffer(raw_len + 64)
f = dll.OodleLZ_Decompress
f.restype = ctypes.c_int64
f.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int, ctypes.c_int, ctypes.c_int,
              ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int]
n = f(data[8:], len(data) - 8, out, raw_len, 1, 0, 0, None, 0, None, None, None, 0, 3)
assert n == raw_len, f"oodle decoded {n} of {raw_len}"

pat = re.compile(re.escape(prefix).encode() + rb"[A-Za-z0-9_]+")
names = sorted({m.group(0).decode() for m in pat.finditer(out.raw[:n])})
skip = re.compile(r"_inline\d+$|ModGroup|Stat|Preset|Loot|Dummy|Base$")
for name in names:
    if skip.search(name):
        continue
    if needle and needle not in name.lower():
        continue
    print(name)
