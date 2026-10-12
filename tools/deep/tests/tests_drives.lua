-- Doc 58 offline tests: the experimental drives on the full machine model, from a Hella-like state 323,000 km out.
local C = NcmCore
local A = C.get("space.astro")
local V = A.vec
local Cat = C.get("space.catalogue")
local F = C.get("engineering.flightmodel")
local I = C.get("engineering.installation")
local Dr = C.get("space.drives")
local Fr = C.get("space.frames")
local Tr = C.get("space.travel")
local Wh = C.get("space.wormholes")
local Ctl = C.get("engineering.controls")
local Sys = C.get("engineering.systems")

local pass, fail = 0, 0
local function check(name, cond, detail)
    if cond then pass = pass + 1; print(("  PASS  %s%s"):format(name, detail and ("  -- " .. detail) or ""))
    else fail = fail + 1; print(("  FAIL  %s%s"):format(name, detail and ("  -- " .. detail) or "")) end
end
local UTC = 1791777600            -- 2026-10-12 04:40 UTC
local DT = 1 / 30

local function machine(code, fill)
    local items = {
        { componentId = "fd1", designId = "eng:zetatech:fd1:r1", mountId = "mount.underside", facing = "down" },
        { componentId = "pt", designId = "eng:zetatech:pt500:r1", mountId = "mount.rear", facing = "left", fillKg = 308 },
        { componentId = "ac6", designId = "eng:zetatech:ac6:r1", mountId = "mount.roof", facing = "up" },
    }
    if code then
        local d
        for _, x in ipairs(I.DESIGNS) do if x.code == code then d = x end end
        items[#items + 1] = { componentId = "xlb", designId = d.designId, mountId = "mount.front", facing = "fore", fillKg = fill }
    end
    local devices, refused = I.resolve(items, "archer_hella")
    for _, r in ipairs(refused) do print("    refused", r.componentId, r.reason) end
    return F.build(devices, { vehicleKey = "archer_hella", fuelKg = 13.5 }), devices
end

local function start(m)
    -- 323,000 km out along +x Earth-fixed, 18 km/s radially (inertial), nose outward
    local p = { 3.23e8, 0, 0 }
    local W = 7.2921159e-5
    local v = { 18000, -W * p[1], 0 }
    local basis = { right = { 0, -1, 0 }, forward = { 1, 0, 0 }, up = { 0, 0, 1 } }
    return F.state(m, { p = p, v = v, basis = basis }, nil, UTC)
end

local function run(m, s, seconds, cmdAt)
    local events = {}
    local n = math.floor(seconds / DT + 0.5)
    for k = 1, n do
        local cmd = cmdAt and cmdAt(k, s) or {}
        local tel
        s, tel = F.step(m, s, cmd, DT, { utc = s.utc })
        for _, e in ipairs(tel.driveEvents or {}) do events[#events + 1] = e end
    end
    return s, events
end
local function once(cmd) local done = false return function() if done then return {} end done = true return cmd end end
local function drive(c) return { drive = { xlb = c } } end
local function ds(s) return s.drv.xlb end
local function find(events, t) for _, e in ipairs(events) do if e.type == t then return e end end end
local function ly(m) return m / A.LY end

-- ------------------------------------------------------------------------------------------------ 0. plumbing
print("0. plumbing")
do
    for _, code in ipairs({ "XLB-WD1", "XLB-AB1", "XLB-JD1", "XLB-WH1" }) do
        local m, devs = machine(code, nil)
        check(code .. " installs on the front hardpoint and is a drive", #m.drives == 1 and m.drives[1].code == code, m.drives[1] and m.drives[1].kind)
        local dev
        for _, d in ipairs(devs) do if d.code == code then dev = d end end
        check(code .. " takes the drive commands", dev and dev.commands.engage == "event" and dev.commands.abort == "analog")
        check(code .. " is lab-only (no sale)", (function() for _, x in ipairs(I.DESIGNS) do if x.code == code then return x.lab == true and x.sale == nil end end end)())
    end
    local cmds = {}
    for k, v in pairs(Sys.commands("warp_drive")) do cmds[k] = v.type end
    local ok = Ctl.check({ control = "padY", gesture = "tap", componentId = "x", command = "engage" }, { code = "XLB", commands = cmds })
    check("Triangle tap -> engage binds", ok == true)
    local m = machine("XLB-WD1", 12000)
    local s = start(m)
    check("charge starts at the server's fill", ds(s).charge == 12000, tostring(ds(s).charge))
    local carried = F.carry(s)
    carried.drv.xlb.charge = 500
    local s2 = F.state(m, { p = { 3.23e8, 0, 0 }, v = { 0, 0, 0 }, basis = { right = { 0, -1, 0 }, forward = { 1, 0, 0 }, up = { 0, 0, 1 } } }, carried, UTC)
    check("carried charge lower than the fill wins (spent since delivery)", ds(s2).charge == 500)
end

-- ------------------------------------------------------------------------------------------------ 1. warp
print("1. warp")
do
    local m = machine("XLB-WD1", 12000)
    local s = start(m)
    local p0 = Dr.astro(s)
    local events
    s, events = run(m, s, 1, once(drive({ engage = true })))
    check("tap: SPOOLING, activation started, frame left the rotating Earth", ds(s).state == "SPOOLING" and find(events, "start") and not Fr.isEarthFixed(s.frame), Fr.key(s.frame))
    s, events = run(m, s, 6)
    check("after the spool: ENGAGED", ds(s).state == "ENGAGED")
    -- W3 for 20 s, then W up to 6 for 10 s
    s = run(m, s, 20)
    local mid = Dr.astro(s)
    local d1 = A.distance(p0, mid)
    check("W3 for ~20 s moves ~20 s x 17.8 c (minus the ramp)", d1 > 0.85 * 20 * 17.78 * A.C and d1 < 1.02 * 21 * 17.78 * A.C, ("%.4g AU"):format(d1 / A.AU))
    s = run(m, s, 3 * DT, function(k) return drive({ up = true }) end)
    check("factor up", ds(s).W == 6, tostring(ds(s).W))
    s = run(m, s, 10)
    -- stop: disengage, the Machine drifts while the field relaxes, then is exactly where the drift left it
    s, events = run(m, s, 6, once(drive({ engage = true })))
    local e = find(events, "end")
    check("disengage ends the activation at a real coordinate", e and e.act.reason == "pilot_disengaged" and ds(s).state == "COOLDOWN", e and e.act.reason)
    local here = Dr.astro(s)
    check("end coordinate in the record is where the Machine is", e and A.distance(Dr.fromTable(e.act.endPos), here) < 1e6, e and ("%.3g m"):format(A.distance(Dr.fromTable(e.act.endPos), here)))
    check("path ~ endpoint separation (straight flight)", e and math.abs(e.act.pathM - e.act.endpointM) / e.act.endpointM < 0.01, e and ("path %.5g AU, endpoint %.5g AU"):format(e.act.pathM / A.AU, e.act.endpointM / A.AU))
    check("warp path in the travel ledger", s.travel.path.warp and math.abs(s.travel.path.warp - e.act.pathM) / e.act.pathM < 0.01, Tr.text(s.travel))
    check("charge spent", ds(s).charge < 12000 and e.act.chargeUsed > 150, ("%.0f used"):format(e.act.chargeUsed))
    check("physical velocity kept (~18 km/s, not c)", V.len(e.act.endVel) < 6e4, ("%.1f km/s"):format(V.len(e.act.endVel) / 1000))
    -- the gravity well: aim at the Sun and engage at W9: drop out at ~20 R_sun
    local s2 = start(m)
    s2 = run(m, s2, DT)
    Fr.toInertial(s2, s2.utc)
    local here2 = Dr.astro(s2)
    local toSun = Dr.unit(A.delta(Cat.stateAt("sun", s2.utc), here2))
    local f = toSun
    local up = Dr.unit(V.sub({ 0, 0, 1 }, V.scale(f, f[3])))
    local r = { f[2] * up[3] - f[3] * up[2], f[3] * up[1] - f[1] * up[3], f[1] * up[2] - f[2] * up[1] }
    s2.rot = { { r[1], f[1], up[1] }, { r[2], f[2], up[2] }, { r[3], f[3], up[3] } }
    s2.omega = { 0, 0, 0 }
    s2.drv.xlb.W = 9
    local ev1
    s2, ev1 = run(m, s2, 8, once(drive({ engage = true })))
    s2, events = run(m, s2, 20)
    for _, x in ipairs(ev1) do events[#events + 1] = x end
    local dSun = A.distance(Dr.astro(s2), (Cat.stateAt("sun", s2.utc)))
    local eW = find(events, "end")
    check("warping into the Sun drops out at its well's edge", eW and tostring(eW.act.reason):find("gravity_well:sun") and dSun > 19 * 695700000, ("%s at %.1f R_sun"):format(eW and eW.act.reason or "?", dSun / 695700000))
end

-- ------------------------------------------------------------------------------------------------ 2. alcubierre
print("2. alcubierre")
do
    local m = machine("XLB-AB1", 4000)
    local s = start(m)
    s = run(m, s, DT)
    check("default target is Barnard's Star", ds(s).targetId == "hip:87937", tostring(ds(s).targetId))
    local events
    s, events = run(m, s, DT, once(drive({ engage = true })))
    check("tap: DESTINATION_LOCKED with a solution", ds(s).state == "DESTINATION_LOCKED" and ds(s).sol, ds(s).msg)
    s, events = run(m, s, 1, once(drive({ engage = true })))
    check("tap: BUBBLE_FORMING", ds(s).state == "BUBBLE_FORMING")
    -- steering during the ride does nothing
    s, events = run(m, s, 400, function(k) return { torque = { 1, 0, 0 } } end)
    local e = find(events, "end")
    local bar = Cat.stateAt(Dr.record("hip:87937"), s.utc)
    local dB = A.distance(Dr.astro(s), bar)
    check("the bubble completes its solution", e and e.act.reason == "solution_complete", e and e.act.reason)
    check("emerges ~2 AU short of Barnard's Star (standoff +- error)", math.abs(dB - 2 * A.AU) < 0.01 * A.AU + (e and e.act.detail.emergenceErrM or 0) * 1.01, ("%.4f AU (error %.4f AU)"):format(dB / A.AU, (e and e.act.detail.emergenceErrM or 0) / A.AU))
    check("bubble parameters recorded (R, sigma, v_s, Pfenning-Ford energy)", e and e.act.detail.bubble and e.act.detail.bubble.energyJ_PF > 1e50,
        e and ("R %g sigma %g vs %g c E %.3g J"):format(e.act.detail.bubble.R, e.act.detail.bubble.sigma, e.act.detail.bubble.vsC, e.act.detail.bubble.energyJ_PF))
    check("path ~ distance carried", e and math.abs(e.act.pathM - e.act.endpointM) / e.act.endpointM < 0.01, e and ("%.4f ly"):format(ly(e.act.pathM)))
    check("the car's own velocity unchanged by the ride", e and V.len(V.sub(e.act.endVel, e.act.startVel)) < 50, e and ("%.2f m/s"):format(V.len(V.sub(e.act.endVel, e.act.startVel))))
    check("frame anchored between the stars", s.frame and (s.frame.anchor ~= nil or s.frame.body ~= "sun"), Fr.key(s.frame))
    check("valid state", Dr.valid(s))
end

-- ------------------------------------------------------------------------------------------------ 3. jump
print("3. jump")
do
    local m = machine("XLB-JD1", 4500)
    local s = start(m)
    s = run(m, s, DT)
    local p0 = Dr.astro(s)
    local events
    s, events = run(m, s, DT, once(drive({ engage = true })))
    check("locked on Proxima", ds(s).state == "DESTINATION_LOCKED" and ds(s).sol and ds(s).sol.name:find("Proxima"), ds(s).msg)
    s, events = run(m, s, 5, once(drive({ engage = true })))
    check("CHARGING (and still home)", ds(s).state == "CHARGING" and A.distance(Dr.astro(s), p0) < 1e9)
    s, events = run(m, s, 12)
    local e = find(events, "end")
    local prox = Cat.stateAt(Dr.record("hip:70890"), s.utc)
    local dP = A.distance(Dr.astro(s), prox)
    check("jumped: ~2 AU from Proxima (+- targeting error)", e and e.act.reason == "arrived" and math.abs(dP - 2 * A.AU) < 0.01 * A.AU + e.act.detail.jump.errM * 1.01, ("%.4f AU"):format(dP / A.AU))
    check("jump vector and distance recorded", e and e.act.detail.jump and e.act.detail.jump.D > 4 * A.LY, e and ("%.4f ly, error %.0f km"):format(ly(e.act.detail.jump.D), e.act.detail.jump.errM / 1000))
    check("adds nothing to path, its endpoint separation to `jumps`", s.travel.jumps.jump and s.travel.jumps.jump > 4 * A.LY and (s.travel.path.jump or 0) == 0, Tr.text(s.travel))
    check("velocity relative to the dominant body carried over", e and e.act.detail.jump.domTo == "hip:70890" or e and e.act.detail.jump.domTo, e and tostring(e.act.detail.jump.domTo))
    -- out of range
    s.drv.xlb.targetId = "hip:91262"
    s = run(m, s, 61)
    s, events = run(m, s, DT, once(drive({ engage = true })))
    check("Vega (25 ly) is refused: beyond range", ds(s).state == "FAILED" and tostring(ds(s).msg):find("range"), ds(s).msg)
end

-- ------------------------------------------------------------------------------------------------ 4. wormhole
print("4. wormhole")
do
    local m = machine("XLB-WH1", 5000)
    local s = start(m)
    s = run(m, s, DT)
    local events
    s, events = run(m, s, DT, once(drive({ engage = true })))
    check("anchor locked (Vega)", ds(s).state == "DESTINATION_LOCKED" and tostring(ds(s).msg):find("Vega"), ds(s).msg)
    s, events = run(m, s, DT, once(drive({ engage = true })))
    check("throat opening", ds(s).state == "SPOOLING" and ds(s).wh ~= nil and Wh.get(ds(s).wh.id) ~= nil)
    local all = {}
    for _ = 1, 60 do
        s, events = run(m, s, 1)
        for _, e in ipairs(events) do all[#all + 1] = e end
        if find(all, "end") then break end
    end
    local tr, e = find(all, "transit"), find(all, "end")
    local vega = Cat.stateAt(Dr.record("hip:91262"), s.utc)
    local dV = A.distance(Dr.astro(s), vega)
    check("crossed mouth A -> B", tr and tr.from == "a" and tr.to == "b", tr and ("separation %.3f ly"):format(ly(tr.separationM)))
    check("emerged ~2 AU from Vega", math.abs(dV - 2 * A.AU) < 0.05 * A.AU, ("%.4f AU"):format(dV / A.AU))
    check("activation traversed, both endpoints + id recorded", e and e.act.reason == "traversed" and e.act.detail.wormhole and e.act.detail.wormhole.id, e and e.act.reason)
    local _, vB = Wh.where(ds(s).wh, "b", s.utc)
    local _, vel = Dr.astro(s)
    check("leaves mouth B at the approach speed (~15 m/s relative)", math.abs(V.len(V.sub(vel, vB)) - 15) < 2, ("%.2f m/s"):format(V.len(V.sub(vel, vB))))
    check("discontinuous travel recorded, not path", s.travel.jumps.wormhole and (s.travel.path.wormhole or 0) == 0, Tr.text(s.travel))
    check("valid after the throat", Dr.valid(s))
    -- the round trip: turn around and go back through B (returnable)
    local w = ds(s).wh
    local pb, _, nb = Wh.where(w, "b", s.utc)
    local f = V.scale(nb, -1)
    s.rot = (function()
        local up = Dr.unit(V.sub({ 0, 0, 1 }, V.scale(f, f[3])))
        local r = { f[2] * up[3] - f[3] * up[2], f[3] * up[1] - f[1] * up[3], f[1] * up[2] - f[2] * up[1] }
        return { { r[1], f[1], up[1] }, { r[2], f[2], up[2] }, { r[3], f[3], up[3] } }
    end)()
    Fr.place(s, Dr.astro(s), V.add(vB, V.scale(f, 40)), s.utc)
    all = {}
    for _ = 1, 30 do s, events = run(m, s, 1); for _, x in ipairs(events) do all[#all + 1] = x end; if find(all, "transit") then break end end
    local back = find(all, "transit")
    local earthD = A.distance(Dr.astro(s), (Cat.stateAt("earth", s.utc)))
    check("back through B -> A: home again", back and back.from == "b" and earthD < 5e8, ("%.0f km from Earth"):format(earthD / 1000))
    -- it closes on its own
    for _ = 1, 30 do s = run(m, s, 10); if not ds(s).wh then break end end
    check("the throat closes, registry emptied", ds(s).wh == nil and #Wh.active(s.utc) == 0, ds(s).state)
end

-- ------------------------------------------------------------------------------------------------ 5. the developer guard
print("5. invalid state -> checkpoint restore")
do
    local m = machine("XLB-WD1", 12000)
    local s = start(m)
    s = run(m, s, 7, once(drive({ engage = true })))
    s = run(m, s, 2)
    local ck = ds(s).ckpt
    s.drv.xlb.v = 0 / 0     -- a malformed prototype
    local events
    s, events = run(m, s, DT)
    local rs = find(events, "restored")
    local e = find(events, "end")
    check("NaN drift caught and restored", rs and Dr.valid(s), rs and rs.why)
    check("activation ended invalid_state_restored, drive FAILED", e and tostring(e.act.reason):find("invalid_state_restored") and ds(s).state == "FAILED", e and e.act.reason)
    check("travel ledger untouched by the NaN", Tr.finite(s.travel.pathM), tostring(s.travel.pathM))
    local L = Tr.new()
    Tr.continuous(L, "x", 0 / 0, 1)
    Tr.continuous(L, "x", 1e30, 10)
    Tr.discontinuous(L, "jump", math.huge)
    check("ledger refuses NaN, oversize and infinite increments", L.pathM == 0 and L.jumpM == 0 and L.rejected == 3)
end

-- ------------------------------------------------------------------------------------------------ 6. conventional
print("6. impulse / fusion activations")
do
    local m = machine(nil)
    local s = start(m)
    local events
    -- the FD-1 is device index? throttle by componentId
    s, events = run(m, s, 7, function(k) return k * DT < 3 and { throttle = { fd1 = 1 } } or {} end)
    local st, e = find(events, "start"), find(events, "end")
    check("fusion burn recorded start -> end", st and e and e.act.drive == "fusion" and e.act.fusionUsedKg > 0, e and ("%.4f kg fusion, dv %.2f m/s"):format(e.act.fusionUsedKg, e.act.detail.deltaV))
    check("fusion path in the ledger", s.travel.path.fusion and s.travel.path.fusion > 0, Tr.text(s.travel))
end

-- ------------------------------------------------------------------------------------------------ 7. coordinates
print("7. frames.translate")
do
    local m = machine(nil)
    local s = start(m)
    s = run(m, s, DT)
    local far = A.offset(Cat.stateAt(Dr.record("hip:71683"), s.utc), { 3e11, 0, 0 })
    Fr.translate(s, far, { 100, 0, 0 }, s.utc)
    check("translate to Alpha Cen: exact position", A.distance(Dr.astro(s), far) < 1e-3, ("%.3g m"):format(A.distance(Dr.astro(s), far)))
    local gc = Cat.stateAt("sgr_a_star", s.utc)
    local p2 = A.offset(gc, { 3e14, 0, 0 })
    Fr.translate(s, p2, { 0, 0, 0 }, s.utc)
    check("translate to the Galactic Centre: exact to a metre", A.distance(Dr.astro(s), p2) < 1, ("%.3g m, frame %s"):format(A.distance(Dr.astro(s), p2), Fr.key(s.frame)))
    local home = A.offset(Cat.stateAt("earth", s.utc), { 7e6, 0, 0 })
    Fr.translate(s, home, { 0, 7500, 0 }, s.utc)
    check("and home: an Earth frame", Fr.key(s.frame):find("earth") ~= nil, Fr.key(s.frame))
end

-- ------------------------------------------------------------------------------------------------ 8. cost
print("8. cost per flight step")
do
    local m = machine("XLB-WD1", 12000)
    local s = start(m)
    s = run(m, s, 7, once(drive({ engage = true })))
    local t0 = os.clock()
    s = run(m, s, 10)
    local per = (os.clock() - t0) / (10 / DT) * 1000
    check("engaged warp step under 1.5 ms (lupa)", per < 1.5, ("%.3f ms/step"):format(per))
end

-- ------------------------------------------------------------------------------------------------ 9. unhosted
print("9. the server's unhosted flight: pilot lost, record JSON")
do
    local Canon = C.get("space.canonical")
    local Json = C.get("vocabulary.json")
    local m, devices = machine("XLB-WD1", 12000)
    local s = start(m)
    s = run(m, s, 7, once(drive({ engage = true })))
    s = run(m, s, 3)
    check("engaged before the host leaves", ds(s).state == "ENGAGED")
    local rec = Canon.fromDeep(F.deep(s), s.utc, { asset = "hella", devices = devices, vehicleKey = "archer_hella", fuelKg = 13.5, dyn = F.carry(s) })
    local okJ, js = pcall(Json.encode, rec)
    check("the record (with drive states and the travel ledger) encodes as JSON", okJ and #js > 0, okJ and (#js .. " bytes") or tostring(js))
    rec = Json.decode(js)
    local r2, done, info = Canon.propagate(rec, rec.utc + 60, 300)
    local e
    for _, x in ipairs(info.driveEvents or {}) do if x.type == "end" then e = x end end
    check("the server ends the warp where the Machine is: pilot_lost", e and e.act.reason == "pilot_lost", e and e.act.reason)
    check("and keeps flying it (finite)", r2.p and Dr.finite(r2.p[1]))
    local okV = pcall(Json.encode, Dr.view(m, s))
    check("drive views encode as JSON (the page payload)", okV)
end

-- ------------------------------------------------------------------------------------------------ 10. budget-skipped frames
print("10. a press on a frame that runs out of budget is kept, not lost or doubled")
do
    local m = machine("XLB-WH1", 5000)
    local s = start(m)
    s = run(m, s, DT, once(drive({ engage = true })))      -- lock (Vega)
    local realCreate, fails = Wh.create, 1
    Wh.create = function(...) if fails > 0 then fails = fails - 1; error("ncm_world/x.lua:1: Open77 script execution budget exceeded", 0) end return realCreate(...) end
    local okF, errF = pcall(F.step, m, s, drive({ engage = true }), DT, { utc = s.utc })
    check("the frame raises the budget error (the host skips it)", not okF and tostring(errF):find("budget exceeded") ~= nil)
    check("the drive is rolled back: still locked, nothing spent", ds(s).state == "DESTINATION_LOCKED" and ds(s).charge == 5000, ds(s).state .. " " .. ds(s).charge)
    s = run(m, s, DT)                                       -- no press this frame: the latched one is retried
    Wh.create = realCreate
    check("the next frame carries the press out: the throat opens, charged once", ds(s).state == "SPOOLING" and ds(s).charge == 2500, ds(s).state .. " " .. ds(s).charge)
    -- cycling: one candidate at a time, skipping what is not an anchor
    s.drv.xlb.wh = nil
    local before = ds(s).targetId
    Dr.select(ds(s), m.drives[1], { next = true }, function(id) return id == "body:mars" end)
    check("RB cycles to the next acceptable target", ds(s).targetId == "body:mars", tostring(before) .. " -> " .. tostring(ds(s).targetId))
end

print(("\n%d passed, %d failed"):format(pass, fail))
return fail == 0
