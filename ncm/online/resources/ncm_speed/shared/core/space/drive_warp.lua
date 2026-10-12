-- ncm-core module: space.drive.warp -- XLB-WD1, the general-purpose continuous FTL drive (doc 58 §5.3).
--
-- FICTION, SAID SO: no real physics gives a steerable superluminal field. The smallest extension NCM makes: a "warp
-- field" that carries the Machine's position along its own forward axis at an effective speed set by the warp factor,
--     v_eff(W) = c * 10^((W - 1) * expo)          (expo 5/8: W1 = 1 c, W5 ~ 316 c, W9 = 100,000 c)
-- while the Machine's PHYSICAL state is untouched: its own velocity, its spin, gravity acting on it, all as before.
-- So the trip is continuous -- every frame the Machine is at a real astronomical coordinate, and stopping anywhere
-- leaves it there -- and steering is pointing: the field follows the car's nose (the AC-6 turns it).
--
-- Character: interplanetary to nearby interstellar; free flight, no destination needed; precise navigation by hand.
-- Limits: the field cannot form or hold inside a gravity well (within `wellRadii` x a body's radius: the Earth inside
-- ~127,000 km, the Sun inside ~0.09 AU) -- crossing that edge drops the Machine out at the edge; the store runs dry at
-- chargePerS x W^2 per second.
--
-- States: OFF -> SPOOLING (field forming, spoolS) -> ENGAGED (W adjustable) -> DISENGAGING (the field relaxes, the
-- Machine still drifting) -> COOLDOWN -> OFF. Tap = engage / disengage; hold (1 s) = emergency abort; up/down = W.
local Core = NcmCore

Core.define("space.drive.warp", function(C)
    local M = {}
    local Dr = C.get("space.drives")
    local A = C.get("space.astro")
    local V = A.vec
    local Fr, Cat, Gr

    local DEF = { factorMin = 1, factorMax = 9, factorStart = 3, expo = 5 / 8, spoolS = 6, rampS = 1.5, disengageS = 3,
        abortS = 0.6, cooldownS = 10, wellRadii = 20, chargePerS = 1, spoolCost = 150, abortHoldS = 1.0, wellEveryS = 0.5 }
    local function P(d, k) local v = d.perf[k]; if v == nil then v = DEF[k] end; return v end

    function M.vOf(d, W) return A.C * 10 ^ ((W - 1) * P(d, "expo")) end

    local function deps() Fr, Cat, Gr = Fr or C.get("space.frames"), Cat or C.get("space.catalogue"), Gr or C.get("space.gravity") end

    -- the bodies near enough to matter, refreshed twice a simulated second (segment tests every step against these)
    local function wells(ctx, ds, apos)
        if ds.wellsAt and math.abs(ctx.s.utc - ds.wellsAt) < P(ctx.d, "wellEveryS") and ds.wellsList then return ds.wellsList end
        local list = {}
        for _, c in ipairs(Gr.contributors(apos, ctx.s.utc)) do
            if (c.rec.radius or 0) > 0 then list[#list + 1] = c.rec.id end
        end
        ds.wellsAt, ds.wellsList = ctx.s.utc, list
        return list
    end
    local function hit(ctx, ds, p0, p1)
        local radii = P(ctx.d, "wellRadii")
        local seg = A.delta(p1, p0)
        local L2 = V.dot(seg, seg)
        for _, id in ipairs(wells(ctx, ds, p0)) do
            local rec = Cat.get(id)
            if rec then
                local R = (rec.radius or 0) * radii
                local w = A.delta((Cat.stateAt(rec, ctx.s.utc)), p0)
                local t = L2 > 0 and math.max(0, math.min(1, V.dot(w, seg) / L2)) or 0
                if V.len(V.sub(w, V.scale(seg, t))) < R then return rec, R end
            end
        end
        return nil
    end

    local function drift(ctx, d, ds, dt)
        local s = ctx.s
        if (ds.v or 0) <= 0 then return nil end
        if Fr.isEarthFixed(s.frame) then Fr.toInertial(s, s.utc) end
        local dir = Dr.forward(s)
        local disp = V.scale(dir, ds.v * dt)
        local p0 = Dr.astro(s)
        local p1 = A.offset(p0, disp)
        local rec = hit(ctx, ds, p0, p1)
        if rec then
            -- the field cannot exist inside the well: it collapses at the edge; the Machine stays where it was
            ds.v, ds.wellHit = 0, rec.id
            return { touched = true, wellRec = rec }
        end
        s.pos = V.add(s.pos, disp)              -- inertial frame: ICRF axes, so the drift adds as it is
        s.gcache, s.altAt = nil, nil
        if not ds.frameAt or math.abs(s.utc - ds.frameAt) >= 0.25 then
            ds.frameAt = s.utc
            local sw = Fr.update(s, s.utc)
            if sw then s.frameSwitched = { to = sw, utc = s.utc } end
        end
        local dm = V.len(disp)
        if ds.act then ds.act.pathM = (ds.act.pathM or 0) + dm end
        ds.peakV = math.max(ds.peakV or 0, ds.v)
        return { touched = true, driftM = dm, driftCap = M.vOf(d, P(d, "factorMax")) * dt }
    end

    function M.step(ctx, d, ds, c, dt)
        deps()
        ctx.d = d
        local s = ctx.s
        ds.W = ds.W or P(d, "factorStart")
        if c.up then ds.W = math.min(P(d, "factorMax"), ds.W + 1) end
        if c.down then ds.W = math.max(P(d, "factorMin"), ds.W - 1) end
        if c.abort and c.abort > 0 then ds.holdT = (ds.holdT or 0) + dt else ds.holdT = 0 end
        local abort = (ds.holdT or 0) >= P(d, "abortHoldS")
        local st = ds.state
        if st == "OFF" then
            ds.v = 0
            if c.engage then
                if (ds.charge or 0) < P(d, "spoolCost") then ds.msg = "not enough charge to form a field"; Dr.set(ctx, d, ds, "FAILED", "no_charge"); return end
                Fr.toInertial(s, s.utc)
                Dr.begin(ctx, d, ds, { detail = { factorStart = ds.W } })
                ds.act.detail.factors = { { t = 0, W = ds.W } }
                Dr.spend(ds, P(d, "spoolCost"))
                ds.msg, ds.wellHit, ds.peakV = "field forming", nil, 0
                Dr.set(ctx, d, ds, "SPOOLING", "engage")
            end
            return
        end
        if st == "SPOOLING" then
            if c.engage or abort then
                Dr.finish(ctx, d, ds, false, "cancelled_in_spool")
                Dr.set(ctx, d, ds, "COOLDOWN", "cancelled")
                return
            end
            -- the field cannot form inside a well either
            local p0 = Dr.astro(s)
            local rec = hit(ctx, ds, p0, p0)
            if rec then
                ds.msg = "inside " .. tostring(rec.name or rec.id) .. "'s gravity well: no field"
                Dr.finish(ctx, d, ds, false, "gravity_well:" .. rec.id)
                Dr.set(ctx, d, ds, "FAILED", "gravity_well")
                return
            end
            if ds.t >= P(d, "spoolS") then
                ds.v = 0
                ds.msg = nil
                Dr.set(ctx, d, ds, "ENGAGED", "field stable")
            end
            return { touched = false }
        end
        if st == "ENGAGED" then
            local target = M.vOf(d, ds.W)
            local k = 1 - math.exp(-dt / P(d, "rampS"))
            ds.v = (ds.v or 0) + (target - (ds.v or 0)) * k
            if ds.act then
                local f = ds.act.detail.factors
                if f[#f].W ~= ds.W and #f < 200 then f[#f + 1] = { t = s.utc - ds.act.startUtc, W = ds.W } end
            end
            if not Dr.spend(ds, P(d, "chargePerS") * ds.W * ds.W * dt) then
                ds.endReason, ds.relax = "charge_exhausted", P(d, "abortS")
                Dr.set(ctx, d, ds, "DISENGAGING", "charge_exhausted")
            elseif abort then
                ds.endReason, ds.relax = "aborted", P(d, "abortS")
                Dr.set(ctx, d, ds, "DISENGAGING", "aborted")
            elseif c.engage then
                ds.endReason, ds.relax = "pilot_disengaged", P(d, "disengageS")
                Dr.set(ctx, d, ds, "DISENGAGING", "disengage")
            end
            local r = drift(ctx, d, ds, dt)
            if r and r.wellRec then
                ds.endReason, ds.relax = "gravity_well:" .. r.wellRec.id, 0.3
                ds.msg = "dropped out at the edge of " .. tostring(r.wellRec.name or r.wellRec.id) .. "'s well"
                Dr.set(ctx, d, ds, "DISENGAGING", "gravity_well")
            end
            Dr.stream(ctx, d, ds, { W = ds.W, vC = (ds.v or 0) / A.C })
            return r or { touched = true }
        end
        if st == "DISENGAGING" then
            local tau = math.max(0.05, (ds.relax or P(d, "disengageS")) / 4)
            ds.v = (ds.v or 0) * math.exp(-dt / tau)
            local r = drift(ctx, d, ds, dt)
            if r and r.wellRec then ds.endReason = "gravity_well:" .. r.wellRec.id end
            Dr.stream(ctx, d, ds, { W = ds.W, vC = (ds.v or 0) / A.C })
            if (ds.v or 0) < A.C * 1e-3 or ds.t >= (ds.relax or P(d, "disengageS")) * 1.5 then
                ds.v = 0
                local reason = ds.endReason or "pilot_disengaged"
                local ok = not reason:find("^charge") and not reason:find("^gravity")
                Dr.finish(ctx, d, ds, ok or reason == "pilot_disengaged", reason, { peakC = (ds.peakV or 0) / A.C, factorEnd = ds.W, wellHit = ds.wellHit })
                ds.endReason, ds.relax = nil, nil
                Dr.set(ctx, d, ds, "COOLDOWN", reason)
            end
            return r or { touched = true }
        end
        return nil
    end

    function M.lost(ctx, d, ds) ds.v = 0 end

    function M.view(ctx, d, ds)
        local s = ctx.s
        local W = ds.W or P(d, "factorStart")
        local k = 0
        if ds.state == "SPOOLING" then k = math.min(1, ds.t / P(d, "spoolS")) elseif ds.state == "ENGAGED" then k = 1
        elseif ds.state == "DISENGAGING" then k = math.max(0, 1 - ds.t / ((ds.relax or P(d, "disengageS")) * 1.2)) end
        return { W = W, vC = (ds.v or 0) / A.C, vTargetC = M.vOf(d, W) / A.C, spool = k,
                 dir = Dr.forwardIcrf(s), wellHit = ds.wellHit }
    end

    return M
end)
