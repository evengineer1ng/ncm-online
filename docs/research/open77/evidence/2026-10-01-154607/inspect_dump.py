"""Read-only, standard-library inspection of this specific retained crash dump."""
from pathlib import Path
import struct

game = Path(r'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077')
dump = Path.home() / 'AppData/Local/REDEngine/ReportQueue/Cyberpunk2077-20261001-154607-54512-66212/Cyberpunk2077.dmp'
b = dump.read_bytes()
u = lambda o: struct.unpack_from('<I', b, o)[0]
q = lambda o: struct.unpack_from('<Q', b, o)[0]
ranges = []
for i in range(u(8)):
    typ, size, rva = struct.unpack_from('<III', b, u(12) + 12*i)
    if typ == 5:
        for j in range(u(rva)):
            ranges.append(struct.unpack_from('<QII', b, rva+4+16*j))
    if typ == 9:
        off = q(rva+8)
        for j in range(q(rva)):
            at, n = struct.unpack_from('<QQ', b, rva+16+16*j)
            ranges.append((at, n, off))
            off += n
exe = (game / 'bin/x64/Cyberpunk2077.exe').read_bytes()
pe = struct.unpack_from('<I', exe, 60)[0]
sections = []
for i in range(struct.unpack_from('<H', exe, pe+6)[0]):
    o = pe+24+struct.unpack_from('<H', exe, pe+20)[0]+40*i
    vs, va, rs, rp = struct.unpack_from('<IIII', exe, o+8)
    sections.append((va, rs, rp))
base = 0x7ff7b64f0000

def read(at, n):
    for a, s, o in ranges:
        if a <= at and at+n <= a+s:
            return b[o+at-a:o+at-a+n]
    # Only code/readonly data may be obtained from the on-disk executable.
    if base <= at < base+0x3200000:
        for a, s, o in sections:
            if a <= at-base and at-base+n <= a+s:
                return exe[o+at-base-a:o+at-base-a+n]
    return b''

def ptr(at):
    x = read(at, 8)
    return int.from_bytes(x, 'little') if x else 0

def fnv(s):
    h = 14695981039346656037
    for c in s.encode():
        h = ((h ^ c) * 1099511628211) & ((1 << 64)-1)
    return h

names = {}
for p in Path('ncm/carrier/third_party/RED4ext.SDK/include').rglob('*.hpp'):
    import re
    for name in re.findall(r'NAME = "([^"]+)"', p.read_text(errors='replace')):
        names[fnv(name)] = name

for at in [0x28648a20220, 0x29627a58778, 0x28641521c90]:
    print('object', hex(at), 'vtable', hex(ptr(at)), 'entity@48', hex(ptr(at+0x48)))
    cl = ptr(at+0x30)
    for _ in range(12):
        if not cl:
            break
        name = ptr(cl+0x18)
        print('  class', hex(cl), hex(name), names.get(name, '?'))
        cl = ptr(cl+0x10)
target = ptr(base+0x3432070)
print('cast target', hex(target), hex(ptr(target+0x18)), names.get(ptr(target+0x18), '?'))
print('input handle', hex(ptr(0x90accff570)), hex(ptr(0x90accff578)))
print('result handle', hex(ptr(0x90accff520)), hex(ptr(0x90accff528)))
owner = ptr(0x28641521c90+0x50)
print('moveComponent owner', hex(owner), 'entity', hex(ptr(owner+0x48)))
cl = ptr(owner+0x30)
print('owner class', names.get(ptr(cl+0x18), '?'))
for at in [0x29627a58778, owner]:
    print('memory', hex(at), read(at, 192).hex())
