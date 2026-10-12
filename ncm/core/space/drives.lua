-- ncm-core module: space.drives
--
-- Doc 58: NCM Deep's experimental propulsion stable. Six ways of moving through the universe, not six speeds:
--   impulse     ARC-IA10 (engineering.dynamics pulse_reaction)  a hard stroke of force; gravity as ever
--   fusion      ZTC-FD1  (engineering.dynamics reaction_engine) sustained thrust; an ordinary trajectory
--   warp        XLB-WD1  (space.drive.warp)        continuous superluminal drift along where the car points
--   alcubierre  XLB-AB1  (space.drive.alcubierre)  a locked solution carried inside a spacetime bubble
--   jump        XLB-JD1  (space.drive.jump)        a discontinuous translation to a locked destination
--   wormhole    XLB-WH1  (space.drive.wormhole)    a connection: open it, fly through it, come out elsewhere
-- Impulse and fusion are unchanged physics; this module only RECORDS their activations. The four exotic drives are
-- devices whose `perf.kind` names their module; each owns a small state machine, run here every flight step on every
-- host (the client while it flies, the server's unhosted flight), after engineering.dynamics has moved the Machine.
--
-- STATES (doc 58 §4): OFF SPOOLING READY ENGAGED DISENGAGING COOLDOWN FAILED, plus each drive's own (DESTINATION_LOCKED,
-- BUBBLE_FORMING, BUBBLE_STABLE, CHARGING, WORMHOLE_OPEN). Every transition that ends an activation carries a
-- termination reason.
--
-- WHAT A DRIVE MAY DO TO A STATE: drift it (space.frames.place: continuous, warp/alcubierre), translate it
-- (space.frames.translate: discontinuous, jump/wormhole), or nothing. Never s.pos directly.
--
-- SAFETY (doc 58 §7, developer-only): entering a drive's first committed state snapshots the Machine (position, velocity,
-- attitude, frame, tanks, charge). After any drive effect the state is checked (`valid`): finite, inside the universe,
-- a rotation, a known frame. An INVALID state is restored from the snapshot and the drive FAILS with
-- `invalid_state_restored`. A surprising but valid result is never restored.
--
-- TELEMETRY: every activation is one record (`act`) -- start, a stream line a second while engaged, end -- returned as
-- events for the host to log and persist (server/deep.lua -> deep_drive_activation).
local Core = NcmCore

Core.define("space.drives", function(C)
    local M = { version = "0.1.0" }
    local A = C.get("space.astro")
    local V = A.vec
    local Fr, Cat, Gr, Tr, D
    local navDone = false
    local function deps()
        if not Fr then
            Fr, Cat, Gr, Tr, D = C.get("space.frames"), C.get("space.catalogue"), C.get("space.gravity"), C.get("space.travel"), C.get("space.deep")
        end
        if not navDone then
            navDone = true
            -- a host WITHOUT the star catalogue (the client) still needs the stars a drive can be pointed at: the nav set,
            -- as star records (same rows, same ids) kept HERE. 2026-10-12 05:58: registering them in space.catalogue made
            -- every catalogue sweep (gravity relevance, spheres of influence, the Deep page's bodies) five times longer
            -- and put the client's Deep frame over OPEN//77's script budget. They are looked up, never registered.
            local okN, N = pcall(C.get, "space.data.navstars")
            if okN and type(N) == "table" then
                local GM_SUN, R_SUN = 132712440041.279419e9, 695700000
                for _, r in ipairs(N) do
                    local id = "hip:" .. r.hip
                    M.NAV[id] = { id = id, name = r.name, kind = "star", parent = nil, gm = r.mass * GM_SUN,
                        radius = R_SUN * r.mass ^ 0.8, mass = r.mass, ephem = { kind = "star", pc = { r.x, r.y, r.z } }, gravity = true,
                        provenance = { "Hipparcos new reduction (nav set, doc 58)" } }
                end
            end
        end
    end
    M.deps = deps
    M.NAV = {}
    --- A record by id: the catalogue's, else the nav set's (a host without the star catalogue).
    function M.record(id)
        deps()
        if Cat.loaded and Cat.loaded() then
            local r = Cat.get(id)
            if r then return r end
        end
        return M.NAV[id] or Cat.get(id)
    end

    --- Destinations a drive can lock, in the order the pad cycles them (each drive keeps those in its range).
    M.TARGETS = { "body:earth", "body:moon", "body:mars", "body:jupiter", "body:saturn", "body:neptune", "ahead:0.05", "hip:70890",
        "hip:71683", "hip:87937", "hip:54035", "hip:32349", "hip:16537", "hip:8102", "hip:37279", "hip:97649", "hip:91262",
        "hip:69673", "hip:24608", "hip:11767", "hip:27989", "ahead:1", "ahead:10", "body:sgr_a_star" }

    M.C = A.C
    M.STREAM_S = 1.0           -- one stream line per simulated second while engaged
    M.VALID_MAX_M = 1e21       -- |pos| in any frame beyond this is not a place (100,000 ly from a frame centre)
    M.VALID_MAX_V = 1e9        -- a PHYSICAL velocity (m/s) beyond 3c is a bug, whatever a drive's effective speed
    M.EARTH_EVERY_S = 5.0     -- the Earth distance (max / current) every 5 simulated seconds: cheap on the server's unhosted flight

    M.KIND_MODULE = {
        warp_drive = "space.drive.warp",
        alcubierre_drive = "space.drive.alcubierre",
        jump_drive = "space.drive.jump",
        wormhole_drive = "space.drive.wormhole",
    }
    M.LABEL = { warp_drive = "warp", alcubierre_drive = "alcubierre", jump_drive = "jump", wormhole_drive = "wormhole" }
    function M.isDrive(kind) return M.KIND_MODULE[kind or ""] ~= nil end
    local impls = {}
    function M.impl(kind)
        local name = M.KIND_MODULE[kind or ""]
        if not name then return nil end
        impls[kind] = impls[kind] or C.get(name)
        return impls[kind]
    end

    -- ------------------------------------------------------------------------------------------- helpers for impls
    local function finite(x) return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge end
    M.finite = finite
    function M.vfinite(v) return type(v) == "table" and finite(v[1]) and finite(v[2]) and finite(v[3]) end
    local function cp3(v) return { v[1], v[2], v[3] } end
    local function cpR(R) return { cp3(R[1]), cp3(R[2]), cp3(R[3]) } end
    M.cp3, M.cpR = cp3, cpR
    function M.unit(a) local l = V.len(a); return l > 0 and V.scale(a, 1 / l) or { 0, 0, 0 } end

    --- Astro position and ICRF velocity of a state now.
    function M.astro(s) deps(); return Fr.toAstro(s, s.utc) end
    --- The Machine's forward axis in ICRF (the state must be inertial).
    function M.forward(s) return M.unit({ s.rot[1][2], s.rot[2][2], s.rot[3][2] }) end
    --- The same in ICRF whatever the frame (an Earth-fixed state's axes turn with the Earth: undo it). Read-only.
    function M.forwardIcrf(s)
        deps()
        local f = M.forward(s)
        if Fr.isEarthFixed(s.frame) and s.utc then
            local th = A.gmst(s.utc)
            local c, sn = math.cos(th), math.sin(th)
            return { c * f[1] - sn * f[2], sn * f[1] + c * f[2], f[3] }
        end
        return f
    end
    --- The rotation (rows) taking ICRF directions to the state's frame axes and back are identities except Earth-fixed.
    function M.rotIcrf(s)
        deps()
        local R = s.rot
        if Fr.isEarthFixed(s.frame) and s.utc then
            local th = A.gmst(s.utc)
            local c, sn = math.cos(th), math.sin(th)
            local out = { {}, {}, {} }
            for j = 1, 3 do
                local x, y, z = R[1][j], R[2][j], R[3][j]
                out[1][j], out[2][j], out[3][j] = c * x - sn * y, sn * x + c * y, z
            end
            return out
        end
        return cpR(R)
    end
    --- The selectable targets for a drive within `maxM` of a point (nil = no limit), keeping ids that resolve here.
    function M.targets(s, maxM)
        deps()
        local out = {}
        local here = M.astro(s)
        for _, id in ipairs(M.TARGETS) do
            local rec, p = M.target(id, s, s.utc)
            if rec and (not maxM or A.distance(here, p) <= maxM) then out[#out + 1] = id end
        end
        return out
    end
    --- Advance a drive's selected target by c.next / c.prev through M.TARGETS, to the next one `ok(id)` accepts -- tested
    --- ONE AT A TIME (2026-10-12: computing every target's position per press blew the client's frame budget).
    function M.select(ds, d, c, ok)
        local list = M.TARGETS
        local cur = ds.targetId or d.perf.defaultTarget
        local i = 1
        for k, id in ipairs(list) do if id == cur then i = k end end
        local step = c.prev and -1 or 1
        for _ = 1, #list do
            i = (i - 1 + step) % #list + 1
            if ok(list[i]) then ds.targetId = list[i]; return ds.targetId end
        end
        return ds.targetId
    end
    --- A target within `maxM` of the Machine (one position computed).
    function M.inRange(s, maxM)
        return function(id)
            local rec, p = M.target(id, s, s.utc)
            return rec ~= nil and (not maxM or A.distance((M.astro(s)), p) <= maxM)
        end
    end
    function M.posTable(p) return { c = { p.c[1], p.c[2], p.c[3] }, o = { p.o[1], p.o[2], p.o[3] } } end
    function M.fromTable(t) return t and A.fromParts(t.c, t.o) or nil end

    --- Deterministic uniform [0, 1) stream from a string seed (Park-Miller; exact in Lua 5.4 and LuaJIT).
    function M.rng(seed)
        local h = 2166136261
        seed = tostring(seed)
        for i = 1, #seed do h = (h * 31 + seed:byte(i)) % 2147483646 end
        local x = h + 1
        return function()
            x = (48271 * x) % 2147483647
            return (x - 1) / 2147483646
        end
    end
    --- A deterministic unit vector from a stream.
    function M.randomUnit(r)
        local z = 2 * r() - 1
        local t = 2 * math.pi * r()
        local q = math.sqrt(math.max(0, 1 - z * z))
        return { q * math.cos(t), q * math.sin(t), z }
    end

    --- The record a target id names: "body:<id>" | "hip:<n>" | "<catalogue id>" | "ahead:<ly>". Returns rec (or a
    --- synthetic one for "ahead"), astro pos, velocity.
    function M.target(id, s, utc)
        deps()
        id = tostring(id or "")
        local ly = tonumber(id:match("^ahead:([%d%.e%+%-]+)$"))
        if ly then
            local p = M.astro(s)
            local apos = A.offset(p, V.scale(M.forward(s), ly * A.LY))
            return { id = id, name = ("%.3g ly ahead"):format(ly), kind = "point", radius = 0 }, apos, { 0, 0, 0 }
        end
        local key = id:gsub("^body:", "")
        -- the nav set first for stars (Cat.get scans the whole star catalogue for an id it has not made yet)
        local rec = M.NAV[key] or Cat.get(key)
        if not rec then return nil end
        local p, v = Cat.stateAt(rec, utc)
        return rec, p, v
    end

    --- Where a drive should put a Machine arriving at `rec` along unit `dir`: short of it by a standoff (a star: AU; a
    --- body: radii), so nothing ever emerges inside a star or a planet.
    function M.standoff(rec, perf)
        if not rec or rec.kind == "point" then return 0 end
        if rec.kind == "black_hole" then return (perf.standoffBlackHoleAU or 2000) * A.AU end
        if rec.kind == "star" or rec.parent == nil then return (perf.standoffStarAU or 2) * A.AU end
        return math.max((perf.standoffBodyRadii or 10) * (rec.radius or 0), perf.standoffBodyMinM or 5e7)
    end

    --- The dominant body (sphere of influence) at a point and its velocity: velocities carry over relative to it.
    function M.dominant(apos, utc)
        deps()
        local rec = Cat.soi(apos, utc)
        local _, v = Cat.stateAt(rec, utc)
        return rec, v or { 0, 0, 0 }
    end

    --- Interdiction: the first body whose surface-scaled sphere (`radii` x its radius) a segment p0 -> p1 enters, or nil.
    --- The candidates are the relevant gravitating bodies around p0 and p1 (space.gravity's relevance).
    function M.wellHit(p0, p1, utc, radii)
        deps()
        local seen, list = {}, {}
        for _, at in ipairs({ p0, p1 }) do
            for _, c in ipairs(Gr.contributors(at, utc)) do
                if not seen[c.rec.id] then seen[c.rec.id] = true; list[#list + 1] = c end
            end
        end
        local seg = A.delta(p1, p0)
        local L2 = V.dot(seg, seg)
        for _, c in ipairs(list) do
            local R = (c.rec.radius or 0) * radii
            if R > 0 then
                local w = A.delta(c.R, p0)
                local t = L2 > 0 and math.max(0, math.min(1, V.dot(w, seg) / L2)) or 0
                local closest = V.sub(w, V.scale(seg, t))
                if V.len(closest) < R then return c.rec, V.len(closest), t end
            end
        end
        return nil
    end

    -- ------------------------------------------------------------------------------------------- build / state
    --- From a flightmodel device list: the drives on this Machine (flightmodel.build calls this).
    function M.fromDevices(devices)
        local out = {}
        for _, d in ipairs(devices or {}) do
            local kind = (d.perf and d.perf.kind) or d.kind
            if M.isDrive(kind) then
                out[#out + 1] = { componentId = tostring(d.componentId or d.code or kind), code = d.code or (d.perf and d.perf.code) or kind,
                    kind = kind, label = M.LABEL[kind], perf = d.perf or {}, fill = tonumber(d.fillKg),
                    capacity = (d.perf and d.perf.store and tonumber(d.perf.store.capacity)) or 0 }
            end
        end
        return out
    end

    --- Per-drive state (JSON-safe), continuing from `carry` (a previous dynamics state's / record's `drv`).
    --- Charge: the server's last word (`fill`) unless the carried value is lower (spent since that delivery).
    function M.init(m, carry)
        local out = {}
        for _, d in ipairs(m.drives or {}) do
            local c = type(carry) == "table" and carry[d.componentId] or nil
            local charge = d.fill or d.capacity
            if type(c) == "table" and finite(tonumber(c.charge)) then charge = math.min(charge, tonumber(c.charge)) end
            local ds = { state = "OFF", t = 0, charge = charge, n = 0 }
            if type(c) == "table" then
                for k, v in pairs(c) do if k ~= "charge" then ds[k] = v end end
            end
            ds.charge = math.max(0, charge)
            -- an activation resumed from a compact record: only its id travelled; the end record says so
            if type(ds.act) == "table" and not ds.act.detail then
                ds.act.detail, ds.act.pathM, ds.act.resumed = { resumedFromRecord = true }, 0, true
            end
            out[d.componentId] = ds
        end
        return out
    end

    -- ------------------------------------------------------------------------------------------- transitions
    function M.set(ctx, d, ds, state, why)
        if ds.state ~= state then
            local from = ds.state
            ds.state, ds.t = state, 0
            ctx.events[#ctx.events + 1] = { type = "state", drive = d.label, code = d.code, componentId = d.componentId,
                from = from, to = state, why = why, utc = ctx.s.utc, act = ds.act and ds.act.id or nil }
        end
    end

    --- Spend charge; false when there is not enough (nothing is spent then).
    function M.spend(ds, units)
        if not finite(units) or units <= 0 then return true end
        if (ds.charge or 0) < units then return false end
        ds.charge = ds.charge - units
        if ds.act then ds.act.chargeUsed = (ds.act.chargeUsed or 0) + units end
        return true
    end

    local function snapshot(s)
        return { pos = cp3(s.pos), vel = cp3(s.vel), rot = cpR(s.rot), omega = cp3(s.omega or { 0, 0, 0 }),
                 frame = Fr.save(s.frame), tanks = (function() local t = {} for i, v in ipairs(s.tanks or {}) do t[i] = v end return t end)(),
                 utc = s.utc }
    end
    local function restore(s, ck)
        s.pos, s.vel, s.rot, s.omega = cp3(ck.pos), cp3(ck.vel), cpR(ck.rot), cp3(ck.omega)
        s.frame = Fr.load_(ck.frame)
        for i, v in ipairs(ck.tanks or {}) do s.tanks[i] = v end
        s.gcache, s.altAt = nil, nil
    end

    --- Start an activation: the developer checkpoint and the start of its record.
    function M.begin(ctx, d, ds, extra)
        deps()
        local s = ctx.s
        ds.n = (ds.n or 0) + 1
        local apos, avel = M.astro(s)
        local earth = Cat.stateAt(Fr.home(), s.utc)
        ds.ckpt = snapshot(s)
        ds.ckpt.charge = ds.charge
        ds.act = {
            id = ("%s-%s-%d-%d"):format(d.label, tostring(d.componentId):sub(-6), math.floor(s.utc or 0), ds.n),
            drive = d.label, code = d.code, componentId = d.componentId, startUtc = s.utc,
            startPos = M.posTable(apos), startVel = cp3(avel), startEarthM = A.distance(apos, earth),
            frameStart = Fr.key(s.frame), chargeStart = ds.charge, chargeUsed = 0, pathM = 0, detail = {},
            fuel0 = ctx.fuel and ctx.fuel() or nil,
        }
        for k, v in pairs(extra or {}) do ds.act[k] = v end
        ds.nextStream = (s.utc or 0) + M.STREAM_S
        ctx.events[#ctx.events + 1] = { type = "start", drive = d.label, act = ds.act, utc = s.utc, checkpoint = ds.ckpt }
        return ds.act
    end

    --- Finish the current activation (ok = success), with the termination reason.
    function M.finish(ctx, d, ds, ok, reason, detail)
        deps()
        local act = ds.act
        if not act then return end
        local s = ctx.s
        local apos, avel = M.astro(s)
        local earth = Cat.stateAt(Fr.home(), s.utc)
        act.endUtc, act.endPos, act.endVel = s.utc, M.posTable(apos), cp3(avel)
        act.endEarthM = A.distance(apos, earth)
        act.frameEnd = Fr.key(s.frame)
        local sp = act.startPos and M.fromTable(act.startPos) or nil
        act.endpointM = sp and A.distance(sp, apos) or nil
        act.simS = (s.utc or 0) - (act.startUtc or 0)
        act.ok, act.reason = ok and true or false, reason
        local f1 = ctx.fuel and ctx.fuel() or nil
        if act.fuel0 and f1 then act.fuelUsedKg, act.fusionUsedKg = act.fuel0.fuel - f1.fuel, act.fuel0.fusion - f1.fusion end
        act.chargeLeft = ds.charge
        local soi = Cat.soi(apos, s.utc)
        act.soiEnd = soi and soi.id or nil
        act.detail = act.detail or {}
        for k, v in pairs(detail or {}) do act.detail[k] = v end
        ctx.events[#ctx.events + 1] = { type = "end", drive = d.label, act = act, utc = s.utc }
        ds.last = { id = act.id, ok = act.ok, reason = reason, endpointM = act.endpointM, pathM = act.pathM, simS = act.simS }
        ds.act, ds.ckpt = nil, nil
    end

    --- A stream line (continuous drives, once a simulated second).
    function M.stream(ctx, d, ds, extra)
        local s = ctx.s
        if not ds.act or (s.utc or 0) < (ds.nextStream or 0) then return end
        ds.nextStream = (s.utc or 0) + M.STREAM_S
        local apos, avel = M.astro(s)
        local ev = { type = "stream", drive = d.label, id = ds.act.id, utc = s.utc, pos = M.posTable(apos), vel = cp3(avel),
                     pathM = ds.act.pathM, charge = ds.charge, state = ds.state }
        for k, v in pairs(extra or {}) do ev[k] = v end
        ctx.events[#ctx.events + 1] = ev
    end

    -- ------------------------------------------------------------------------------------------- validity
    function M.valid(s)
        if not (M.vfinite(s.pos) and M.vfinite(s.vel)) then return false, "non-finite position or velocity" end
        if V.len(s.pos) > M.VALID_MAX_M then return false, ("position %.3g m from its frame centre"):format(V.len(s.pos)) end
        if V.len(s.vel) > M.VALID_MAX_V then return false, ("physical velocity %.3g m/s"):format(V.len(s.vel)) end
        local R = s.rot
        if type(R) ~= "table" then return false, "no attitude" end
        for i = 1, 3 do if not M.vfinite(R[i]) then return false, "non-finite attitude" end end
        local det = R[1][1] * (R[2][2] * R[3][3] - R[2][3] * R[3][2]) - R[1][2] * (R[2][1] * R[3][3] - R[2][3] * R[3][1])
            + R[1][3] * (R[2][1] * R[3][2] - R[2][2] * R[3][1])
        if math.abs(det - 1) > 1e-3 then return false, ("attitude is not a rotation (det %.4f)"):format(det) end
        if s.frame ~= nil then
            if type(s.frame) ~= "table" or s.frame.kind ~= "inertial" then return false, "unknown frame" end
            if s.frame.anchor then
                local a = s.frame.anchor
                for i = 1, 3 do if not finite(a.c[i]) or not finite(a.o[i]) then return false, "non-finite frame anchor" end end
            elseif not M.record(s.frame.body) then return false, "frame body " .. tostring(s.frame.body) .. " unknown" end
        end
        if s.utc and not finite(s.utc) then return false, "non-finite clock" end
        return true
    end

    -- ------------------------------------------------------------------------------------------- conventional drives
    -- Impulse and fusion: their physics is engineering.dynamics (unchanged); here only their activations are recorded,
    -- with the same record as the exotic drives. A burn is one activation from its first thrust to a second without;
    -- a run of impulse strokes less than 1.5 s apart is one activation.
    local function conventional(ctx, m, s, cmd, dt)
        local method
        for i, d in ipairs(m.devices or {}) do
            if d.kind == "pulse_reaction" and ((s.pulse and (s.pulse[i] or 0) > 0) or (cmd and cmd.discharge and (cmd.discharge[i] or cmd.discharge[d.key] or (d.componentId and cmd.discharge[d.componentId])))) then
                method = "impulse"
            elseif d.kind == "reaction_engine" and s.thr and (s.thr[i] or 0) > 0.01 then
                method = method or ((d.perf.propellant == "fusion") and "fusion" or "rocket")
            end
        end
        local cv = s.conv or {}
        s.conv = cv
        local pseudo = { label = cv.method or method, code = cv.method or method, componentId = "conventional" }
        if method and not cv.act then
            cv.method = method
            pseudo.label, pseudo.code = method, method
            local ds = { n = cv.n or 0 }
            M.begin(ctx, pseudo, ds)
            cv.n, cv.act, cv.ckpt = ds.n, ds.act, nil   -- conventional burns are not exotic: no developer restore
            cv.quiet = 0
            cv.nextStream = ds.nextStream
            cv.v0 = cp3(ds.act.startVel)
        elseif cv.act then
            if method then cv.quiet = 0 else cv.quiet = (cv.quiet or 0) + dt end
            if cv.method == "fusion" or cv.method == "rocket" then
                local ds = { act = cv.act, nextStream = cv.nextStream, state = method and "ENGAGED" or "COASTING", charge = 0 }
                M.stream(ctx, pseudo, ds, { throttle = method and 1 or 0 })
                cv.nextStream = ds.nextStream
            end
            if (cv.quiet or 0) >= ((cv.method == "impulse") and 1.5 or 1.0) then
                local ds = { act = cv.act }
                local _, avel = M.astro(s)
                M.finish(ctx, pseudo, ds, true, "burn_complete", { deltaV = V.len(V.sub(avel, cv.v0 or avel)) })
                cv.act, cv.method, cv.v0 = nil, nil, nil
            end
        end
    end

    -- ------------------------------------------------------------------------------------------- the step
    --- One drive step, after engineering.dynamics. cmd.drive = { [componentId] = { engage = true, abort = 1,
    --- up = true, down = true, next = true, prev = true } }. opts.pilot = false: nobody is flying (unhosted) -- an
    --- engaged exotic drive ends with `pilot_lost`. Returns events (also left in s.drvEvents for hosts that only
    --- see the state). `ctx.fuel()` reads fuel/fusion for activation records.
    function M.step(m, s, cmd, dt, opts)
        deps()
        opts = opts or {}
        local events = {}
        if not s.utc then return events end
        local Dyn = C.get("engineering.dynamics")
        local ctx = { m = m, s = s, utc = s.utc, dt = dt, opts = opts, events = events,
            fuel = function() return { fuel = Dyn.propellantLeft(m, s, "fuel"), fusion = Dyn.propellantLeft(m, s, "fusion") } end }
        s.drv = s.drv or M.init(m, nil)
        local pathMethod, driftM, driftCap = nil, 0, 0
        local touched = false
        for _, d in ipairs(m.drives or {}) do
            local ds = s.drv[d.componentId]
            if not ds then ds = M.init({ drives = { d } }, nil)[d.componentId]; s.drv[d.componentId] = ds end
            local impl = M.impl(d.kind)
            local c = (cmd and cmd.drive and cmd.drive[d.componentId]) or {}
            ds.t = (ds.t or 0) + dt
            if ds.targetId == nil then ds.targetId = d.perf.defaultTarget or false end   -- the list is built only when cycled
            -- the shared tail of every machine: a cooldown ends, a failure is shown for a while, then the drive is OFF
            if ds.state == "COOLDOWN" and ds.t >= (d.perf.cooldownS or 10) then M.set(ctx, d, ds, "OFF", "cooled")
            elseif ds.state == "FAILED" and ds.t >= (d.perf.failedHoldS or 6) then M.set(ctx, d, ds, "OFF", "reset") end
            -- 2026-10-12 09:48: a press whose frame ran out of the host's script budget was LOST (four Triangle taps to
            -- open a wormhole did nothing). One-shot commands are latched until a frame completes, and a frame that runs
            -- out of budget rolls the drive (and the Machine's place) back to where it was, so the retry starts clean.
            ds.want = ds.want or {}
            for _, k in ipairs({ "engage", "up", "down", "next", "prev" }) do if c[k] then ds.want[k] = true end end
            local cc = { engage = ds.want.engage, up = ds.want.up, down = ds.want.down, next = ds.want.next, prev = ds.want.prev, abort = c.abort }
            local snap = {}
            for k, v in pairs(ds) do if k ~= "want" then snap[k] = v end end
            local sSnap = { pos = cp3(s.pos), vel = cp3(s.vel), rot = cpR(s.rot), omega = cp3(s.omega or { 0, 0, 0 }), frame = s.frame }
            local nEv = #events
            local okS, res = pcall(impl.step, ctx, d, ds, cc, dt)
            -- a budget error is the FRAME's (the host skips it), not the drive's: undo this drive's step, keep the press
            if not okS and tostring(res):find("budget exceeded", 1, true) then
                for k in pairs(ds) do if k ~= "want" then ds[k] = nil end end
                for k, v in pairs(snap) do ds[k] = v end
                s.pos, s.vel, s.rot, s.omega, s.frame = sSnap.pos, sSnap.vel, sSnap.rot, sSnap.omega, sSnap.frame
                s.gcache, s.altAt = nil, nil
                for i = #events, nEv + 1, -1 do events[i] = nil end
                error(res, 0)
            end
            ds.want = nil
            if not okS then
                local err = tostring(res)
                events[#events + 1] = { type = "error", drive = d.label, error = err:sub(1, 300), utc = s.utc }
                res = { touched = ds.ckpt ~= nil }
                ds.drift = nil
                if ds.act then pcall(M.finish, ctx, d, ds, false, "drive_error: " .. err:sub(1, 120)) end
                M.set(ctx, d, ds, "FAILED", "drive_error")
            end
            if type(res) == "table" then
                if res.touched then touched = true end
                if res.driftM then pathMethod, driftM, driftCap = d.label, driftM + res.driftM, driftCap + (res.driftCap or res.driftM) end
                if res.jumpM then
                    s.travel = s.travel or Tr.new()
                    Tr.discontinuous(s.travel, d.label, res.jumpM)
                end
            end
            -- the developer guard: an invalid state is restored from the activation's checkpoint
            if touched or ds.ckpt then
                local ok, why = M.valid(s)
                if not ok and ds.ckpt then
                    restore(s, ds.ckpt)
                    ds.charge = ds.ckpt.charge or ds.charge
                    events[#events + 1] = { type = "restored", drive = d.label, why = why, act = ds.act and ds.act.id or nil, utc = s.utc }
                    if ds.act then M.finish(ctx, d, ds, false, "invalid_state_restored: " .. tostring(why)) end
                    M.set(ctx, d, ds, "FAILED", "invalid_state_restored")
                    ds.drift = nil
                end
            end
        end
        conventional(ctx, m, s, cmd, dt)
        -- the travel ledger: physical path (speed relative to the frame's centre; the rotating frame's own motion removed),
        -- plus any drive drift; discontinuities were added above
        s.travel = s.travel or Tr.new()
        local vphys = s.vel
        if Fr.isEarthFixed(s.frame) then vphys = D.inertialVel(s.pos, s.vel) end
        local dm = V.len(vphys) * dt
        Tr.continuous(s.travel, (s.conv and s.conv.method) or "coast", dm, dm)
        if driftM > 0 then Tr.continuous(s.travel, pathMethod, driftM, driftCap) end
        if (s.utc or 0) >= (s.earthAt or 0) then
            s.earthAt = (s.utc or 0) + M.EARTH_EVERY_S
            local apos = M.astro(s)
            Tr.earth(s.travel, A.distance(apos, (Cat.stateAt(Fr.home(), s.utc))))
        end
        if #events > 0 then
            s.drvEvents = s.drvEvents or {}
            for _, e in ipairs(events) do s.drvEvents[#s.drvEvents + 1] = e end
        end
        return events
    end

    --- Hosts drain the events a state collected.
    function M.drain(s)
        local e = s.drvEvents or {}
        s.drvEvents = nil
        return e
    end

    --- What the screen needs for each drive: { label, code, state, t, charge, capacity, ... + the impl's view }.
    function M.view(m, s)
        local out = {}
        for _, d in ipairs(m.drives or {}) do
            local ds = s.drv and s.drv[d.componentId]
            if ds then
                local v = { drive = d.label, code = d.code, state = ds.state, t = ds.t, charge = ds.charge, capacity = d.capacity, msg = ds.msg, last = ds.last }
                local impl = M.impl(d.kind)
                if impl.view then
                    local ok, extra = pcall(impl.view, { m = m, s = s, utc = s.utc }, d, ds)
                    if ok and type(extra) == "table" then for k, x in pairs(extra) do v[k] = x end end
                end
                out[#out + 1] = v
            end
        end
        return out
    end

    --- Unhosted: nobody is flying. Every exotic activation in progress ends where the Machine is (`pilot_lost`).
    function M.pilotLost(m, s)
        deps()
        local events = {}
        if not s.utc then return events end
        local ctx = { m = m, s = s, utc = s.utc, dt = 0, opts = {}, events = events }
        for _, d in ipairs(m.drives or {}) do
            local ds = s.drv and s.drv[d.componentId]
            if ds and ds.state ~= "OFF" and ds.state ~= "COOLDOWN" and ds.state ~= "FAILED" then
                local impl = M.impl(d.kind)
                if impl.lost then pcall(impl.lost, ctx, d, ds) end
                if ds.act then M.finish(ctx, d, ds, false, "pilot_lost") end
                ds.drift = nil
                M.set(ctx, d, ds, "COOLDOWN", "pilot_lost")
            end
        end
        return events
    end

    -- what a RECORD keeps of a drive (compact): enough to resume a flight in progress on another host. The activation
    -- record and the developer checkpoint stay with the host that started them (the server stores its own checkpoint):
    -- 2026-10-12 07:13, a jump's full state made the 1 Hz record too big to arrive, and the server took the Machine over.
    local KEEP = { state = true, t = true, charge = true, n = true, W = true, v = true, targetId = true, sol = true, ride = true,
        stab = true, side = true, transits = true, crossedAt = true, prev = true, prevUtc = true, endReason = true,
        collapseReason = true, relax = true, peakV = true, msg = true }
    --- JSON-safe copy of the per-drive states. compact = true: for a persisted record (see KEEP).
    function M.save(drv, compact)
        if type(drv) ~= "table" then return nil end
        local out = {}
        for id, ds in pairs(drv) do
            local c = {}
            for k, v in pairs(ds) do if k ~= "wh" and (not compact or KEEP[k]) then c[k] = v end end
            if compact and ds.act then c.act = { id = ds.act.id, drive = ds.act.drive, startUtc = ds.act.startUtc } end
            if ds.wh then c.wh = C.get("space.wormholes").save(ds.wh) end
            out[id] = c
        end
        return out
    end

    return M
end)
