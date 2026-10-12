-- ncm-core module: presentation.fx
--
-- NCM FX (2026-10-12, owner: "a true vfx and sfx dynamic system we can plug the rest of our physics into ... all kinds
-- of properties that could feed a vfx system, not just one hardcoded plume; we have everything from hop to wormholes").
--
-- ONE CONTRACT, THREE STAGES. Pure: no runtime reads, no randomness, no clock.
--
--   1. EMITTERS. Every physical thing that can be seen or heard says what it is doing, in SI units, from the numbers the
--      physics step already computed -- nothing is invented for presentation:
--        { id, kind, sub, at = {x,y,z} (machine frame: x right, y forward, z up), dir = {x,y,z} (the THRUST axis; the
--          exhaust leaves along -dir), q = { quantities }, edge = { one-shot events this step } }
--      Producers: `fromInstall` (the ground path, engineering.installation), `fromDynamics` (Deep, engineering.dynamics),
--      `fromDrives` (space.drives views), `machine` (the body as a whole: air, heating, Mach, contact, impacts).
--   2. CUES (`presentation.fx_cues`, data). A cue matches emitters, reads ONE driving quantity through thresholds into a
--      TIER (game effects cannot scale at run time, so size is a choice of asset -- the ascent ring's trick), and says
--      what to show and play: a native effect asset per tier, an audio voice whose pitch and gain follow quantities,
--      a screen effect, a camera kick. Sustained cues hold while their condition holds; edge cues fire once.
--   3. BUDGET. The platform keeps at most 32 live effects per client. `select` ranks activations by priority x
--      intensity over distance and keeps what is already playing ahead of a newcomer of equal rank (no flicker).
--
-- Hosts render (ncm_world/client/fx.lua). A host never decides what something looks like; it only draws what this says.
local Core = NcmCore

Core.define("presentation.fx", function(C)
    local M = { version = "0.1.0" }
    local Cues = C.get("presentation.fx_cues")

    M.G0 = 9.80665
    M.CAP = 32               -- the platform's live-effect cap per client
    M.RESERVE_EDGE = 6       -- slots kept free for one-shots (a hop never waits behind a plume)

    local function num(v, d) v = tonumber(v); if v == nil or v ~= v then return d or 0 end; return v end
    local function clamp(x, a, b) if x < a then return a elseif x > b then return b end; return x end
    local function v3(t) t = t or {}; return { num(t[1] or t.x), num(t[2] or t.y), num(t[3] or t.z) } end

    -- ------------------------------------------------------------------------------------------- producers
    local SUSTAINED = { reaction_engine = true, jet = true, propeller = true }

    local function propulsorQ(p, throttle, thrustN, heatFrac, hot, starved, rho)
        local maxN = math.max(1e-6, num(p.thrustN))
        return {
            throttle = clamp(num(throttle), 0, 1), thrustN = math.max(0, num(thrustN)), thrustMaxN = maxN,
            frac = clamp(num(thrustN) / maxN, 0, 1.5), exhaustV = num(p.ispS) * M.G0, propellant = p.propellant or "none",
            heatFrac = clamp(num(heatFrac), 0, 2), hot = hot and true or false, starved = starved and true or false,
            rho = num(rho),
        }
    end

    --- The ground path: `engineering.installation.step` returned `out[componentId] = { thrustN, throttle, heatK, hot,
    --- starved }`; `state.dev[componentId].sinceS == 0` marks a pulse stroke that began this step.
    function M.fromInstall(machineId, devices, out, state, env)
        local em = {}
        env = env or {}
        for _, d in ipairs(devices or {}) do
            local o = (out or {})[d.componentId] or {}
            local st = ((state or {}).dev or {})[d.componentId] or {}
            local p = d.perf or {}
            local lim = num((d.thermal or p.thermal or {}).limitK, 0)
            local heatFrac = lim > 0 and num(o.heatK or st.heatK) / lim or 0
            local e = { id = ("%s:%s"):format(tostring(machineId), tostring(d.componentId)), kind = "propulsor", sub = d.kind,
                at = v3(d.pos), dir = v3(d.axis), edge = {} }
            if SUSTAINED[d.kind] then
                e.q = propulsorQ(p, o.throttle, o.thrustN, heatFrac, o.hot, o.starved, env.rho)
            elseif d.kind == "pulse_reaction" then
                e.kind = "pulse"
                e.q = { forceN = num(p.forceN), active = num(o.thrustN) > 0, propellant = p.propellant or "none",
                    heatFrac = heatFrac, contact = env.contact and true or false, altitude = num(env.altitude) }
                if st.sinceS == 0 then e.edge.fired = true end
            else
                e = nil
            end
            if e then em[#em + 1] = e end
        end
        return em
    end

    --- The Deep path: one `engineering.dynamics.step` (m, s after the step, tel).
    function M.fromDynamics(machineId, m, s, tel, env)
        local em = {}
        env, tel, s = env or {}, tel or {}, s or {}
        local rho = num(tel.rho, num(env.rho))
        local events = {}
        for _, ev in ipairs(tel.events or {}) do events[ev.device] = events[ev.device] or {}; events[ev.device][ev.what] = ev end
        for i, d in ipairs(m.devices or {}) do
            local p = d.perf or {}
            local st = (s.dev or {})[i] or {}
            local lim = num((d.thermal or {}).limitK, 0)
            local heatFrac = lim > 0 and num(st.heatK) / lim or 0
            local ev = events[d.key] or {}
            local e = { id = ("%s:%s"):format(tostring(machineId), tostring(d.key or i)), kind = "propulsor", sub = d.kind,
                at = v3(d.at), dir = v3(d.dir), edge = {} }
            if SUSTAINED[d.kind] then
                local t = st.hot and 0 or num((s.thr or {})[i]) * num(tel.derate, 1)
                local F = 0
                if t > 0 then
                    local Sys = C.get("engineering.systems")
                    F = Sys.thrustAt(p, rho, t)
                    if ev.starved then F = 0 end
                end
                e.q = propulsorQ(p, t, F, heatFrac, st.hot, ev.starved, rho)
            elseif d.kind == "pulse_reaction" then
                e.kind = "pulse"
                e.q = { forceN = num(p.forceN), active = num((s.pulse or {})[i]) > 0, propellant = p.propellant or "none",
                    heatFrac = heatFrac, contact = tel.contact and true or false, altitude = num(env.altitude) }
                if ev.discharge then e.edge.fired = true end
            elseif d.kind == "ground_ram" then
                e.kind = "ram"
                e.q = { contact = tel.contact and true or false, charged = num((s.rams or {})[i]) > 0 }
                if ev.fired then e.edge.fired = true; e.q.energyJ = num(ev.fired.energyJ); e.q.dv = num(ev.fired.dv) end
                if ev.no_contact then e.edge.dry = true end
            else
                e = nil
            end
            if e then em[#em + 1] = e end
        end
        -- attitude sets: a cold-gas puff when they work (their key carries no mount point: they act about the CoM)
        if num(tel.attitudeNm) > 0 then
            local cap = 0
            for _, at in ipairs(m.attitude or {}) do cap = cap + num((at.perf or {}).torqueNm) end
            em[#em + 1] = { id = tostring(machineId) .. ":attitude", kind = "attitude", sub = "attitude_control",
                at = v3(m.com), dir = { 0, 0, 1 }, edge = {},
                q = { frac = cap > 0 and clamp(num(tel.attitudeNm) / cap, 0, 1) or 0, propellant = "n2", rho = rho } }
        end
        return em
    end

    --- The experimental drives (`space.drives` views: { drive, state, spool, bubble, charge, progress, ... }).
    function M.fromDrives(machineId, views)
        local em = {}
        for _, v in ipairs(views or {}) do
            em[#em + 1] = { id = ("%s:drive:%s"):format(tostring(machineId), tostring(v.drive)), kind = "drive", sub = v.drive,
                at = { 0, 2.4, 0.6 }, dir = { 0, 1, 0 }, edge = {},
                q = { state = v.state, spool = num(v.spool), bubble = num(v.bubble), charge = num(v.charge),
                    progress = num(v.progress), factor = num(v.factor) } }
        end
        return em
    end

    --- The body as a whole. q: speed (m/s), rho, qPa, aeroHeatKw, heatFrac, contact, altitude; prev: last step's
    --- machine q (for crossings); impactJ: a collision the host saw this step.
    function M.machine(machineId, q, prev, impactJ)
        q = q or {}
        local speed, rho = num(q.speed), num(q.rho)
        local a = rho > 0.3 and 340 or 295
        local mach = rho > 1e-4 and speed / a or 0
        local e = { id = tostring(machineId) .. ":body", kind = "machine", sub = "body", at = { 0, 1.8, 0.5 }, dir = { 0, 1, 0 },
            edge = {}, q = { speed = speed, rho = rho, mach = mach, qPa = num(q.qPa, 0.5 * rho * speed * speed),
                heatKw = num(q.aeroHeatKw), heatFrac = num(q.heatFrac), contact = q.contact and true or false,
                altitude = num(q.altitude) } }
        local pm = prev and num(prev.mach) or mach
        if pm < 1 and mach >= 1 then e.edge.boom = true end
        if num(impactJ) > 0 then e.edge.impact = true; e.q.impactJ = num(impactJ) end
        return { e }
    end

    -- ------------------------------------------------------------------------------------------- cues
    local function matches(on, e)
        if on.kind and on.kind ~= e.kind then return false end
        if on.sub and not on.sub[e.sub] then return false end
        if on.propellant and not on.propellant[e.q.propellant] then return false end
        if on.state and not on.state[e.q.state] then return false end
        return true
    end

    local function passes(req, q)
        for k, r in pairs(req or {}) do
            local v = q[k]
            if type(r) == "table" then
                if r.gt ~= nil and not (num(v) > r.gt) then return false end
                if r.lt ~= nil and not (num(v) < r.lt) then return false end
                if r.eq ~= nil and v ~= r.eq then return false end
            elseif v ~= r then
                return false
            end
        end
        return true
    end

    --- The tier a value falls in (tiers sorted by `at`); nil below the first.
    function M.tier(tiers, x)
        local pick, idx = nil, nil
        for i, t in ipairs(tiers or {}) do if num(x) >= num(t.at) then pick, idx = t, i end end
        return pick, idx
    end

    local function lerpMap(map, q)
        if not map then return nil end
        local x = num(q[map.q])
        local a, b = map.from[1], map.from[2]
        local u = b ~= a and clamp((x - a) / (b - a), 0, 1) or 1
        return map.to[1] + (map.to[2] - map.to[1]) * u
    end
    M.lerpMap = lerpMap

    --- Every cue activation for these emitters. An activation:
    ---   { key, cue, emitter, tier, asset, edge (bool), priority, intensity 0..1, at, dir, audio = {voice, pitch, gain},
    ---     screen, fov }
    function M.activations(emitters)
        local out = {}
        for _, e in ipairs(emitters or {}) do
            for _, c in ipairs(Cues.CUES) do
                if matches(c.on or {}, e) then
                    local fire = true
                    if c.edge then fire = e.edge and e.edge[c.edge] or false end
                    if fire and passes(c.require, e.q) then
                        local t, idx = M.tier(c.tiers, e.q[c.drive])
                        if t or not c.tiers then
                            local x = num(e.q[c.drive])
                            local top = c.tiers and c.tiers[#c.tiers] or nil
                            local intensity = top and num(top.at) > 0 and clamp(x / num(top.at), 0.1, 1) or 1
                            local asset = t and (t.byPropellant and t.byPropellant[e.q.propellant] or t.asset) or c.asset
                            if t and t.vacuum and num(e.q.rho) < 0.01 then asset = t.vacuum end
                            local a = { key = e.id .. "#" .. c.id, cue = c.id, emitter = e.id, tier = idx or 0, asset = asset,
                                edge = c.edge and true or false, priority = num(c.priority, 5), intensity = intensity,
                                at = e.at, dir = e.dir, exhaust = c.exhaust and true or false, screen = c.screen, fov = c.fov }
                            if c.audio then
                                a.audio = { voice = c.audio.voice, oneShot = c.audio.oneShot and true or false,
                                    pitch = lerpMap(c.audio.pitch, e.q) or 1, gain = lerpMap(c.audio.gain, e.q) or 1 }
                            end
                            out[#out + 1] = a
                        end
                    end
                end
            end
        end
        table.sort(out, function(x, y) return x.key < y.key end)   -- deterministic order (KB-343: never pairs order)
        return out
    end

    --- Choose what plays. `held` = { [key] = true } for what is playing now; `distOf(a)` (optional) metres from the
    --- viewer. Returns the kept activations (sustained first by rank, edges in their reserve).
    function M.select(acts, held, distOf, cap)
        cap = cap or M.CAP
        held = held or {}
        local sustained, edges = {}, {}
        for _, a in ipairs(acts or {}) do
            local d = distOf and num(distOf(a), 0) or 0
            a.rank = a.priority * a.intensity / (1 + d / 50) + (held[a.key] and 0.5 or 0)
            if a.edge then edges[#edges + 1] = a else sustained[#sustained + 1] = a end
        end
        local function byRank(x, y) if x.rank ~= y.rank then return x.rank > y.rank end; return x.key < y.key end
        table.sort(sustained, byRank)
        table.sort(edges, byRank)
        local keep = {}
        local nS = math.max(0, cap - M.RESERVE_EDGE)
        for i = 1, math.min(nS, #sustained) do keep[#keep + 1] = sustained[i] end
        for i = 1, math.min(cap - #keep, #edges) do keep[#keep + 1] = edges[i] end
        return keep
    end

    --- One step's whole plan: emitters -> activations -> selection.
    function M.plan(emitters, held, distOf, cap)
        return M.select(M.activations(emitters), held, distOf, cap)
    end

    -- ------------------------------------------------------------------------------------------- replication
    --- Compact form of a Machine's emitters for other clients (low rate): only what cues read.
    function M.pack(emitters)
        local out = {}
        for _, e in ipairs(emitters or {}) do
            local q = e.q or {}
            out[#out + 1] = { e.id, e.kind, e.sub, e.at, e.dir,
                { thr = q.throttle, f = q.frac, n = q.thrustN, p = q.propellant, h = q.heatFrac, x = q.exhaustV, r = q.rho,
                  a = q.active, s = q.state, sp = q.spool, b = q.bubble, c = q.charge } }
        end
        return out
    end

    function M.unpack(packed)
        local out = {}
        for _, r in ipairs(packed or {}) do
            local z = r[6] or {}
            out[#out + 1] = { id = r[1], kind = r[2], sub = r[3], at = r[4], dir = r[5], edge = {},
                q = { throttle = z.thr, frac = z.f, thrustN = z.n, propellant = z.p, heatFrac = z.h, exhaustV = z.x,
                    rho = z.r, active = z.a, state = z.s, spool = z.sp, bubble = z.b, charge = z.c } }
        end
        return out
    end

    return M
end)
