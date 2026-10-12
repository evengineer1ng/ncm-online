"""Doc 58 visual previews: run each drive in the offline core and capture what client/drivefx.lua would send to the
page at chosen moments (drive views, the car's position in pc, its attitude), as JSON for preview.html."""
import json, os, harness
lua = harness.runtime(stars=True)
lua.execute('NcmCore.get("space.catalogue").loadAll()')
PREFIX = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "tests_drives.lua"), encoding="utf-8").read().split('-- ------------------------------------------------------------------------------------------------ 0. plumbing')[0]
code = r'''
local Json = C.get("vocabulary.json")
local frames = {}
local function cap(name, m, s, extra)
    local R = Dr.rotIcrf(s)
    local here = Dr.astro(s)
    local pcv = V.scale(A.metres(here), 1 / A.PC)
    local f = { name = name, carPc = pcv, right = { R[1][1], R[2][1], R[3][1] }, fwd = { R[1][2], R[2][2], R[3][2] }, up = { R[1][3], R[2][3], R[3][3] },
                drives = Dr.view(m, s), far = A.distance(here, A.ORIGIN) > 0.02 * A.LY }
    for k, v in pairs(extra or {}) do f[k] = v end
    frames[#frames + 1] = f
end
local function aim(s, dir)
    local f = Dr.unit(dir)
    local up = Dr.unit(V.sub({ 0, 0, 1 }, V.scale(f, f[3])))
    local r = { f[2] * up[3] - f[3] * up[2], f[3] * up[1] - f[1] * up[3], f[1] * up[2] - f[2] * up[1] }
    s.rot = { { r[1], f[1], up[1] }, { r[2], f[2], up[2] }, { r[3], f[3], up[3] } }
    s.omega = { 0, 0, 0 }
end
-- impulse / fusion
do
    local m = machine(nil); local s = start(m); s = run(m, s, DT)
    Fr.toInertial(s, s.utc); aim(s, { 0.3, 0.9, 0.2 })
    cap("1_fusion_burn", m, s, { conv = { method = "fusion", throttle = 1 } })
    cap("0_impulse_kick", m, s, { conv = { method = "impulse", pulse = true } })
end
-- warp
do
    local m = machine("XLB-WD1", 12000); local s = start(m); s = run(m, s, DT)
    Fr.toInertial(s, s.utc); aim(s, Dr.astro(s) and { 0.2, 0.95, 0.25 })
    s = run(m, s, 3, once(drive({ engage = true }))); cap("2a_warp_spool", m, s)
    s = run(m, s, 3.5); cap("2b_warp_engaged_W3", m, s)
    s.drv.xlb.W = 9; s = run(m, s, 4); cap("2c_warp_W9", m, s)
    s = run(m, s, 0.8, once(drive({ engage = true }))); cap("2d_warp_disengaging", m, s)
end
-- alcubierre
do
    local m = machine("XLB-AB1", 4000); local s = start(m); s = run(m, s, DT)
    s = run(m, s, DT, once(drive({ engage = true })))
    local bar = Cat.stateAt("hip:87937", s.utc); Fr.toInertial(s, s.utc); aim(s, A.delta(bar, Dr.astro(s)))
    cap("3a_alcubierre_locked", m, s)
    s = run(m, s, 8, once(drive({ engage = true }))); cap("3b_alcubierre_forming", m, s)
    s = run(m, s, 9.5); cap("3c_alcubierre_stable", m, s)
    s = run(m, s, 60); cap("3d_alcubierre_cruise", m, s)
    for _ = 1, 200 do s = run(m, s, 1); if ds(s).state == "DISENGAGING" then break end end
    s = run(m, s, 0.3); cap("3e_alcubierre_collapse", m, s)
end
-- jump
do
    local m = machine("XLB-JD1", 4500); local s = start(m); s = run(m, s, DT)
    s = run(m, s, DT, once(drive({ engage = true })))
    local prox = Cat.stateAt("hip:70890", s.utc); Fr.toInertial(s, s.utc); aim(s, V.add(A.delta(prox, Dr.astro(s)), V.scale(Dr.unit({0,0,1}), 0)))
    aim(s, V.add(Dr.unit(A.delta(prox, Dr.astro(s))), { 0.15, 0.1, 0.05 }))
    cap("4a_jump_lock", m, s)
    s = run(m, s, 7, once(drive({ engage = true }))); cap("4b_jump_charge_50", m, s)
    s = run(m, s, 6.3); cap("4c_jump_charge_95", m, s)
    s = run(m, s, 1.2); cap("4d_jump_arrived", m, s)
    s = run(m, s, 2); cap("4e_jump_destination_sky", m, s)
end
-- wormhole
do
    local m = machine("XLB-WH1", 5000); local s = start(m); s = run(m, s, DT)
    Fr.toInertial(s, s.utc); aim(s, { 0.3, 0.7, -0.6 })
    s = run(m, s, DT, once(drive({ engage = true })))
    s = run(m, s, 2.5, once(drive({ engage = true }))); cap("5a_wormhole_opening", m, s)
    s = run(m, s, 6); cap("5b_wormhole_open_far", m, s)
    s = run(m, s, 14); cap("5c_wormhole_close", m, s)
    for _ = 1, 400 do s = run(m, s, 0.1); if ds(s).state == "ENGAGED" then break end end
    s = run(m, s, 0.4); cap("5d_wormhole_throat", m, s)
    s = run(m, s, 3); cap("5e_wormhole_emerged_vega", m, s)
    local w = ds(s).wh
    local pb = Wh.where(w, "b", s.utc)
    aim(s, A.delta(pb, Dr.astro(s))); cap("5f_wormhole_exit_mouth_behind", m, s)
end
return Json.encode(frames)
'''
out = lua.execute(PREFIX + code)
open(os.path.expanduser("~/deepwork/drives/preview/frames.json"), "w").write(out)
print(len(out), "bytes")
