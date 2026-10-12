-- ncm-core module: space.drive.wormhole -- XLB-WH1, the wormhole generator (doc 58 §5.6).
--
-- PHYSICAL BASIS: the Morris-Thorne traversable wormhole (Morris & Thorne 1988; Morris, Thorne & Yurtsever 1988): a
-- static throat joining two regions of spacetime, held open by exotic matter. SPECULATIVE, SAID SO: nothing known makes
-- exotic matter in quantity, and nobody knows how to open a throat or pin its far mouth anywhere. NCM's fiction: the
-- XLB-WH1 opens a throat between a mouth it makes beside the Machine and a far mouth pinned to a CATALOGUED MASS (a
-- star, a planet, a black hole) -- an anchor the generator can lock onto. Distance does not enter the cost; the anchor
-- requirement, the throat's lifetime and the far mouth's coordinate precision are the constraints.
--
-- Everything topological lives in space.wormholes (reusable: F-I-S-H-I-N-G / Nessie will place natural ones). This
-- drive only makes one and watches for the Machine crossing a mouth:
--   OFF -> DESTINATION_LOCKED (an anchor is chosen) -> SPOOLING (the throat opening: openS) -> WORMHOLE_OPEN (mouth A
--   sits mouthAheadM ahead, comoving, drifting toward the car at approachMS -- you can also fly into it) -> crossing:
--   ENGAGED (the throat, a moment) -> WORMHOLE_OPEN again, now behind you at the far side, until it closes -> COOLDOWN.
-- Crossing maps position, velocity and attitude through the mouths (space.wormholes.transit): you leave mouth B through
-- its face, moving relative to it as you moved relative to mouth A. Returnable: crossing B takes you back to A.
local Core = NcmCore

Core.define("space.drive.wormhole", function(C)
    local M = {}
    local Dr = C.get("space.drives")
    local Wh = C.get("space.wormholes")
    local A = C.get("space.astro")
    local V = A.vec
    local Fr

    local DEF = { throatR = 15, lifetimeS = 180, openS = 6, collapseS = 4, mouthAheadM = 400, approachMS = 15, throatS = 1.5,
        openCost = 2500, precisionAU = 0.01, cooldownS = 45, abortHoldS = 1.0, returnable = true,
        standoffStarAU = 2, standoffBodyRadii = 10, standoffBlackHoleAU = 2000 }
    local function P(d, k) local v = d.perf[k]; if v == nil then v = DEF[k] end; return v end

    -- any catalogued mass is an anchor; "ahead" points are not (nothing there to pin a mouth to). No position needed.
    local function isAnchor(id)
        if id:find("^ahead:") then return false end
        local rec = Dr.record(id:gsub("^body:", ""))
        return rec ~= nil and (rec.gm or 0) > 0
    end

    local function solve(ctx, d, ds)
        local s = ctx.s
        local rec, tp = Dr.target(ds.targetId, s, s.utc)
        if not rec then return nil, "no anchor" end
        if (rec.gm or 0) <= 0 then return nil, "not an anchor (no mass to pin a mouth to)" end
        local here = Dr.astro(s)
        local dist = A.distance(here, tp)
        local stand = Dr.standoff(rec, d.perf)
        if dist <= stand * 1.5 then return nil, "already at " .. tostring(rec.name or rec.id) end
        return { targetId = ds.targetId, name = rec.name or rec.id, distM = dist, standoffM = stand, cost = P(d, "openCost") }
    end

    -- open: mouth A beside the car, mouth B pinned at the anchor
    local function open(ctx, d, ds)
        local s = ctx.s
        Fr.toInertial(s, s.utc)
        local here, vel = Dr.astro(s)
        local fwd = Dr.forward(s)
        local rec, tp, tv = Dr.target(ds.sol.targetId, s, s.utc)
        local toT = Dr.unit(A.delta(tp, here))
        local r = Dr.rng(d.componentId .. ":" .. ds.n .. ":" .. ds.sol.targetId)
        -- the far mouth's coordinate precision, never more than half the standoff (2026-10-12: 0.01 AU put an Earth exit
        -- 1.09 million km out)
        local err = V.scale(Dr.randomUnit(r), math.min(P(d, "precisionAU") * A.AU * r(), 0.5 * ds.sol.standoffM))
        local pA = A.offset(here, V.scale(fwd, P(d, "mouthAheadM")))
        local vA = V.sub(vel, V.scale(fwd, P(d, "approachMS")))
        local pB = A.offset(A.offset(tp, V.scale(toT, -ds.sol.standoffM)), err)
        local _, vB = Dr.dominant(pB, s.utc)
        local w = Wh.create({
            id = ds.act.id, origin = "artificial", owner = d.componentId, dest = ds.sol.targetId, openedUtc = s.utc,
            throatR = P(d, "throatR"), lifetimeS = P(d, "lifetimeS"), openS = P(d, "openS"), collapseS = P(d, "collapseS"),
            returnable = P(d, "returnable"),
            a = Wh.mouth(pA, vA, V.scale(fwd, -1), s.utc, "vehicle"),
            b = Wh.mouth(pB, vB or tv or { 0, 0, 0 }, toT, s.utc, rec.id),
        })
        Wh.add(w)
        ds.wh = w
        ds.act.detail.wormhole = { id = w.id, a = Dr.posTable(pA), b = Dr.posTable(pB), separationM = A.distance(pA, pB),
            throatR = w.throatR, lifetimeS = w.lifetimeS, anchor = rec.id, precisionErrM = V.len(err), origin = w.origin,
            model = "Morris-Thorne traversable wormhole; exotic matter supply is fiction (doc 58)" }
        return w
    end

    -- the wormhole, whatever the drive's state: abort, crossings, the throat's life
    local function tend(ctx, d, ds, abort)
        local s = ctx.s
        local w = ds.wh
        local st = ds.state
        local phase = Wh.phase(w, s.utc)
        if abort and phase ~= "collapsing" and phase ~= "closed" then
            w.collapseUtc = s.utc
            ds.endReason = ds.endReason or "aborted"
        end
        -- crossing: the segment the Machine moved along this step, against both mouths
        local here, vel = Dr.astro(s)
        local res = nil
        if ds.prev and phase ~= "closed" then
            local side = Wh.crossing(w, Dr.fromTable(ds.prev), here, ds.prevUtc, s.utc)
            if side then
                local rotI = Dr.rotIcrf(s)
                local p2, v2, r2, other = Wh.transit(w, side, here, vel, rotI, s.utc)
                local before = here
                Fr.toInertial(s, s.utc)
                Fr.translate(s, p2, v2, s.utc, r2)
                ds.transits = (ds.transits or 0) + 1
                ds.crossedAt, ds.side = s.utc, other
                local sep = A.distance(before, p2)
                if ds.act then
                    ds.act.detail.transits = ds.act.detail.transits or {}
                    table.insert(ds.act.detail.transits, { from = side, to = other, utc = s.utc, separationM = sep })
                end
                ctx.events[#ctx.events + 1] = { type = "transit", drive = d.label, id = w.id, from = side, to = other, utc = s.utc, separationM = sep }
                Dr.set(ctx, d, ds, "ENGAGED", "crossing the throat")
                here = Dr.astro(s)
                res = { touched = true, jumpM = sep }
            end
        end
        ds.prev, ds.prevUtc = Dr.posTable(here), s.utc
        -- once a second: where the Machine is relative to the near mouth (the client log's answer to "it didn't move me")
        if not ds.diagAt or s.utc - ds.diagAt >= 1 then
            ds.diagAt = s.utc
            local side = ds.side == "b" and "b" or "a"
            local pm, _, nm = Wh.where(w, side, s.utc)
            local rel = A.delta(here, pm)
            local along = rel[1] * nm[1] + rel[2] * nm[2] + rel[3] * nm[3]
            local ph, rad = Wh.phase(w, s.utc)
            ctx.events[#ctx.events + 1] = { type = "diag", drive = d.label, text = ("mouth %s: %.1f m away, %.1f m along its normal (crosses at 0), aperture %.1f m, %s, state %s"):format(
                side, V.len(rel), along, rad, ph, ds.state) }
        end
        st = ds.state
        if st == "SPOOLING" then
            if phase == "open" then Dr.set(ctx, d, ds, "WORMHOLE_OPEN", "stable") end
        elseif st == "ENGAGED" then
            if s.utc - (ds.crossedAt or s.utc) >= P(d, "throatS") then
                if ds.act and ds.transits == 1 then
                    -- the activation's job is done the first time through; the wormhole lives on until it closes
                    Dr.finish(ctx, d, ds, true, "traversed", { transits = ds.transits })
                end
                Dr.set(ctx, d, ds, "WORMHOLE_OPEN", "emerged")
            end
        end
        if phase == "closed" then
            if ds.act then Dr.finish(ctx, d, ds, false, ds.endReason or "collapsed_untraversed") end
            Wh.remove(w.id)
            ds.wh, ds.sol, ds.prev, ds.endReason = nil, nil, nil, nil
            if ds.state ~= "OFF" and ds.state ~= "COOLDOWN" then Dr.set(ctx, d, ds, "COOLDOWN", "wormhole closed") end
        end
        return res
    end

    function M.step(ctx, d, ds, c, dt)
        Fr = Fr or C.get("space.frames")
        local s = ctx.s
        if c.abort and c.abort > 0 then ds.holdT = (ds.holdT or 0) + dt else ds.holdT = 0 end
        local abort = (ds.holdT or 0) >= P(d, "abortHoldS")
        local st = ds.state
        if ds.wh and not Wh.get(ds.wh.id) then ds.wh = Wh.load(ds.wh); if ds.wh then Wh.add(ds.wh) end end
        local tendRes = ds.wh and tend(ctx, d, ds, abort) or nil
        st = ds.state
        if (st == "OFF" or st == "DESTINATION_LOCKED") and (c.next or c.prev) then
            Dr.select(ds, d, c, isAnchor)
            if st == "DESTINATION_LOCKED" then ds.sol = nil; Dr.set(ctx, d, ds, "OFF", "anchor changed") end
            st = ds.state
        end
        if st == "OFF" then
            if c.engage and ds.wh then ds.msg = "a throat is already open (it closes on its own)"; return tendRes end
            if c.engage then
                local sol, why = solve(ctx, d, ds)
                if not sol then ds.msg = "no connection: " .. tostring(why); Dr.set(ctx, d, ds, "FAILED", "no_solution"); return tendRes end
                if (ds.charge or 0) < sol.cost then ds.msg = ("needs %.0f charge, has %.0f"):format(sol.cost, ds.charge or 0); Dr.set(ctx, d, ds, "FAILED", "no_charge"); return tendRes end
                ds.sol, ds.msg = sol, ("anchor: %s, %.4g ly away"):format(sol.name, sol.distM / A.LY)
                Dr.set(ctx, d, ds, "DESTINATION_LOCKED", "anchor locked")
            end
            return tendRes
        end
        if st == "DESTINATION_LOCKED" then
            if abort then ds.sol = nil; Dr.set(ctx, d, ds, "OFF", "unlocked"); return tendRes end
            if c.engage then
                Dr.begin(ctx, d, ds, { target = ds.sol.targetId })
                Dr.spend(ds, ds.sol.cost)
                open(ctx, d, ds)
                ds.transits = 0
                Dr.set(ctx, d, ds, "SPOOLING", "throat opening")
            end
            return tendRes
        end
        if st == "SPOOLING" or st == "WORMHOLE_OPEN" or st == "ENGAGED" then
            if not ds.wh then Dr.set(ctx, d, ds, "COOLDOWN", "no wormhole") end
        end
        return tendRes or { touched = ds.act ~= nil }
    end

    function M.lost(ctx, d, ds)
        -- nobody flying: the throat lives out its life (anything crossing it would still cross); the activation ends
    end

    function M.view(ctx, d, ds)
        local s = ctx.s
        local out = { targetId = ds.targetId, transits = ds.transits }
        if ds.sol then out.solution = { name = ds.sol.name, distM = ds.sol.distM } end
        local w = ds.wh
        if w and s.utc then
            local phase, radius, k = Wh.phase(w, s.utc)
            local here = Dr.astro(s)
            local pa, _, na = Wh.where(w, "a", s.utc)
            local pb, _, nb = Wh.where(w, "b", s.utc)
            out.wormhole = { id = w.id, phase = phase, radius = radius, k = k, throatR = w.throatR,
                a = { rel = A.delta(pa, here), n = na }, b = { rel = A.delta(pb, here), n = nb },
                -- the far side's sky is drawn from here: the mouth's place among the stars, in parsecs from the Sun
                aPc = V.scale(A.metres(pa), 1 / A.PC), bPc = V.scale(A.metres(pb), 1 / A.PC),
                side = ds.side or "a", age = s.utc - (w.openedUtc or s.utc), lifetimeS = w.lifetimeS }
            -- the mouth pair's mapping (rows), so the screen can show the far sky through the near mouth correctly turned
            local function flat(R) return { R[1][1], R[1][2], R[1][3], R[2][1], R[2][2], R[2][3], R[3][1], R[3][2], R[3][3] } end
            out.wormhole.map, out.wormhole.mapBA = flat(Wh.mapping(w.a, w.b)), flat(Wh.mapping(w.b, w.a))
            if ds.crossedAt then out.throat = math.min(1, (s.utc - ds.crossedAt) / P(d, "throatS")) end
        end
        return out
    end

    return M
end)
