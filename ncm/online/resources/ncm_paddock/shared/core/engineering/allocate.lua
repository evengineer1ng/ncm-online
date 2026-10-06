-- ncm-core module: engineering.allocate
--
-- From an INTENT to per-device throttles, through the machine's real mounts (L322; doc 54 §D, §N). Shared by the
-- player's machine (`ncm_ls_space/client/machine.lua`) and NPC pilots (`space.pilot`), so an NPC can never do what
-- the machine could not: a device only helps in the direction it points and with the lever arm it has.
--   attitude(prep, tauD, lift)        lift = main up-devices at full; tauD = normalised torque asked per body axis;
--                                     each device adds how much its own torque points where you asked
--   vector(prep, rot, aWorld, massKg, rho)
--                                     a desired acceleration in the world: each device's share by how well its
--                                     world direction aligns (squared, so aligned devices carry it), scaled so the
--                                     total along the request is what was asked, never more than full throttle
local Core = NcmCore

Core.define("engineering.allocate", function(C)
    local M = { version = "0.1.0" }
    local Sys = C.get("engineering.systems")

    function M.prepare(model)
        local prep = { model = model, maxTau = { 0, 0, 0 }, main = {} }
        for i, w in ipairs(model.wrench) do
            for a = 1, 3 do prep.maxTau[a] = math.max(prep.maxTau[a], math.abs(w.tau[a])) end
            local d = model.devices[i]
            prep.main[i] = d.kind ~= "ground_ram" and d.dir[3] > 0.5 and (d.perf.thrustN or 0) >= 5000
        end
        return prep
    end

    function M.attitude(prep, tauD, lift)
        local thr = {}
        for i, w in ipairs(prep.model.wrench) do
            local att = 0
            for a = 1, 3 do
                if prep.maxTau[a] > 1e-6 then att = att + (tauD[a] or 0) * w.tau[a] / prep.maxTau[a] end
            end
            local base = (prep.main[i] and lift) and (type(lift) == "number" and lift or 1) or 0
            thr[i] = math.max(0, math.min(1, base + att))
        end
        return thr
    end

    local function rotate(R, v) return { R[1][1] * v[1] + R[1][2] * v[2] + R[1][3] * v[3], R[2][1] * v[1] + R[2][2] * v[2] + R[2][3] * v[3],
        R[3][1] * v[1] + R[3][2] * v[2] + R[3][3] * v[3] } end

    --- Throttles for a desired world acceleration. Returns thr, and the achievable acceleration along the request.
    function M.vector(prep, rot, aWorld, massKg, rho)
        local m = prep.model
        local mag = math.sqrt(aWorld[1] ^ 2 + aWorld[2] ^ 2 + aWorld[3] ^ 2)
        local thr = {}
        if mag < 1e-9 then
            for i = 1, #m.devices do thr[i] = 0 end
            return thr, 0
        end
        local u = { aWorld[1] / mag, aWorld[2] / mag, aWorld[3] / mag }
        local along, raw = 0, {}
        for i, d in ipairs(m.devices) do
            raw[i] = 0
            if d.kind ~= "ground_ram" then
                local wd = rotate(rot, d.dir)
                local c = wd[1] * u[1] + wd[2] * u[2] + wd[3] * u[3]
                if c > 0 then
                    raw[i] = c * c
                    along = along + Sys.thrustAt(d.perf, rho or 0, 1) * raw[i] * c
                end
            end
        end
        local k = along > 0 and math.min(1, mag * massKg / along) or 0
        for i = 1, #m.devices do thr[i] = raw[i] * k end
        return thr, along * k / massKg
    end

    return M
end)
