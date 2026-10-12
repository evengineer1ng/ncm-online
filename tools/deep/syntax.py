import sys, os, lupa.lua54 as L
lua = L.LuaRuntime()
chk = lua.eval('function(src, name) local f, e = load(src, "=" .. name); return e end')
bad = 0
for root, _, files in os.walk(sys.argv[1]):
    for f in files:
        if f.endswith('.lua'):
            p = os.path.join(root, f)
            e = chk(open(p, encoding='utf-8').read(), p)
            if e: print("SYNTAX", e); bad += 1
print("checked; errors:", bad)
