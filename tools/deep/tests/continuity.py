"""Doc 58 deploy guard: the two live Deep expeditions, propagated by the CURRENT live core and by the drives core,
must end in the same place (the drives add records, never physics, to a Machine without a drive)."""
import sys, json, harness
rows = [l.rstrip("\n").split("\t") for l in open("presence_snapshot.tsv", encoding="utf-8") if l.strip()]
HOURS = float(sys.argv[1]) if len(sys.argv) > 1 else 1.0
def fly(overlay, rec_json):
    lua = harness.runtime(stars=True, overlay=overlay)
    lua.execute('NcmCore.get("space.catalogue").loadAll()')
    f = lua.eval('''function(js, hours)
        local Canon = NcmCore.get("space.canonical")
        local Json = NcmCore.get("vocabulary.json")
        local r = Json.decode(js)
        local t1 = r.utc + hours * 3600
        local done = false
        repeat r, done = Canon.propagate(r, t1, 300) until done
        local A = NcmCore.get("space.astro")
        return string.format("%.6f,%.6f,%.6f|%.9f,%.9f,%.9f|%s|%s", r.p[1], r.p[2], r.p[3], r.vel[1], r.vel[2], r.vel[3], tostring(r.frame and r.frame.body), tostring(r.utc))
    end''')
    return f(rec_json, HOURS)
bad = 0
for d, place, upd, js in rows:
    a = fly(False, js); b = fly(True, js)
    same = a == b
    print(d[-6:], "live :", a); print(d[-6:], "drives:", b); print("  IDENTICAL" if same else "  DIFFERENT")
    pa = [float(x) for x in a.split("|")[0].split(",")]; pb = [float(x) for x in b.split("|")[0].split(",")]
    print("  position difference %.6f m" % sum((x-y)**2 for x, y in zip(pa, pb))**0.5)
    bad += 0 if same else 1
sys.exit(1 if bad else 0)
