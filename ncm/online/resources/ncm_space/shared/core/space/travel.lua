-- ncm-core module: space.travel
--
-- Doc 58 §6: how far a Machine has travelled in Deep, kept apart from where it is. Race Week's Distance Marathon will
-- need to tell these apart, so the ledger never folds one into another:
--   path      metres actually traversed by continuous motion, by method. Physical flight counts its speed relative to
--             the frame it is integrated in (the dominant body; the rotating Earth frame's own motion removed); a warp
--             field and an Alcubierre bubble count the distance their drift carried the Machine.
--   jumps     endpoint separation of DISCONTINUOUS translations (Jump, Wormhole), by method. These add NOTHING to path:
--             the Machine never crossed the space between. Recorded so a scoring rule can choose to count them.
--   earth     current and maximum distance from the Earth's centre.
-- The rule for every increment: finite, non-negative and no larger than the motion that could have produced it (a
-- caller-supplied cap). Anything else is refused and counted in `rejected` -- a NaN or a frame discontinuity can never
-- reach a persistent odometer.
local Core = NcmCore

Core.define("space.travel", function(C)
    local M = { version = "0.1.0" }

    local function finite(x) return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge end
    M.finite = finite

    function M.new()
        return { path = {}, jumps = {}, jumpCount = {}, pathM = 0, jumpM = 0, maxEarthM = 0, earthM = nil, rejected = 0, lastReject = nil }
    end

    --- A ledger from a record (JSON-decoded) or a fresh one; never trusts a non-finite field.
    function M.load(t)
        local L = M.new()
        if type(t) ~= "table" then return L end
        for _, k in ipairs({ "path", "jumps", "jumpCount" }) do
            if type(t[k]) == "table" then for m, v in pairs(t[k]) do if finite(tonumber(v)) and tonumber(v) >= 0 then L[k][m] = tonumber(v) end end end
        end
        for _, k in ipairs({ "pathM", "jumpM", "maxEarthM", "rejected" }) do if finite(tonumber(t[k])) and tonumber(t[k]) >= 0 then L[k] = tonumber(t[k]) end end
        if finite(tonumber(t.earthM)) then L.earthM = tonumber(t.earthM) end
        return L
    end

    local function reject(L, why)
        L.rejected = (L.rejected or 0) + 1
        L.lastReject = why
        return false, why
    end

    --- Continuous motion: `dm` metres by `method`, at most `cap` metres possible in this step.
    function M.continuous(L, method, dm, cap)
        if not finite(dm) or dm < 0 then return reject(L, ("%s: non-finite or negative step %s"):format(tostring(method), tostring(dm))) end
        if finite(cap) and dm > cap * 1.5 + 1e-6 then return reject(L, ("%s: step %.6g m exceeds its cap %.6g m"):format(tostring(method), dm, cap)) end
        if dm == 0 then return true end
        L.path[method] = (L.path[method] or 0) + dm
        L.pathM = (L.pathM or 0) + dm
        return true
    end

    --- A discontinuous translation: endpoint separation `sep` metres by `method` (adds nothing to path).
    function M.discontinuous(L, method, sep)
        if not finite(sep) or sep < 0 then return reject(L, ("%s: non-finite endpoint separation %s"):format(tostring(method), tostring(sep))) end
        L.jumps[method] = (L.jumps[method] or 0) + sep
        L.jumpCount[method] = (L.jumpCount[method] or 0) + 1
        L.jumpM = (L.jumpM or 0) + sep
        return true
    end

    --- Distance from the Earth now.
    function M.earth(L, d)
        if not finite(d) or d < 0 then return reject(L, "earth distance non-finite") end
        L.earthM = d
        if d > (L.maxEarthM or 0) then L.maxEarthM = d end
        return true
    end

    --- JSON-safe copy.
    function M.save(L)
        local out = { path = {}, jumps = {}, jumpCount = {}, pathM = L.pathM, jumpM = L.jumpM, maxEarthM = L.maxEarthM, earthM = L.earthM, rejected = L.rejected }
        for k, v in pairs(L.path or {}) do out.path[k] = v end
        for k, v in pairs(L.jumps or {}) do out.jumps[k] = v end
        for k, v in pairs(L.jumpCount or {}) do out.jumpCount[k] = v end
        return out
    end

    --- One line for a log.
    function M.text(L)
        local AU = 149597870700.0
        local parts = {}
        local keys = {}
        for k in pairs(L.path or {}) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do parts[#parts + 1] = ("%s %.6g km"):format(k, L.path[k] / 1000) end
        local js = {}
        keys = {}
        for k in pairs(L.jumps or {}) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do js[#js + 1] = ("%s x%d %.6g km"):format(k, L.jumpCount[k] or 0, L.jumps[k] / 1000) end
        return ("path %.6g km [%s] | discontinuous %.6g km [%s] | earth %.6g km (max %.6g km = %.4f AU)%s"):format(
            (L.pathM or 0) / 1000, table.concat(parts, ", "), (L.jumpM or 0) / 1000, table.concat(js, ", "),
            (L.earthM or 0) / 1000, (L.maxEarthM or 0) / 1000, (L.maxEarthM or 0) / AU,
            (L.rejected or 0) > 0 and (" | %d increment(s) refused (last: %s)"):format(L.rejected, tostring(L.lastReject)) or "")
    end

    return M
end)
