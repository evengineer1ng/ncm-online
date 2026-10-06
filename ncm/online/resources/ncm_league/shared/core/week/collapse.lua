-- ncm-core module: week.collapse
-- What a Racing Week leaves behind when it ends (L303; doc 45 §C, §D-4, §P). Pure rules; the host gathers facts.
--
-- A RECONSTRUCTION IS A SERVER-ID NAMESPACE. Everything run-local -- the Paddock world, every car not anchored and the
-- parts on it, NPC-owned assets, open Exchange posts -- is re-keyed from `<server>` to `<server>#R<run>` (`archiveKey`).
-- Nothing is deleted, so a finished run stays inspectable under its own key. What stays on the server key is
-- meta: identity, knowledge (Machine Index, markets, contacts, designs), licence and rating (W-3), history, the hall of
-- champions, team identity, and the anchored cars.
--
-- W-3: SR is pulled halfway back to neutral (a known menace stays flagged; a new week is a chance to redeem).
-- W-4: no meta-money. The wallet closes with one ledger entry and the next run opens with the new-player grant.
--      Anchors: 1 slot, a 2nd after finishing a Day-3 race, a 3rd after a Premier start. A driver who chose nothing
--      keeps their most-raced car (the default -- and every existing garage's founding anchor, W-6).
--      A car granted by a run condition is anchorable only if it won a sanctioned race (`anchor_if_won`).
local Core = NcmCore

Core.define("week.collapse", function()
    local M = { version = "0.1.0", SR_NEUTRAL = 5.0, MAX_ANCHORS = 3 }

    function M.archiveKey(serverId, run) return ("%s#R%03d"):format(tostring(serverId), math.floor(tonumber(run) or 0)) end

    --- Anchor slots from the driver's history: { day3Finish = bool, premierStart = bool }.
    function M.anchorSlots(h)
        h = h or {}
        local n = 1
        if h.day3Finish then n = n + 1 end
        if h.premierStart then n = n + 1 end
        return math.min(M.MAX_ANCHORS, n)
    end

    --- Is a car anchorable? `car` = { conditionGrant = bool, sanctionedWins = n }.
    function M.anchorable(car)
        if car.conditionGrant then return (tonumber(car.sanctionedWins) or 0) > 0, "condition_grant_needs_a_win" end
        return true
    end

    --- The anchors for one driver. `cars` = { { assetId, races, odometerM, conditionGrant, sanctionedWins } },
    --- `chosen` = set of assetIds the driver picked this run, `slots` = n. Chosen first (in the driver's order), then
    --- the most-raced car as the default when nothing was chosen. Returns { { assetId, source } }, refusals.
    function M.anchors(cars, chosen, slots)
        local byId, out, refused = {}, {}, {}
        for _, c in ipairs(cars or {}) do byId[c.assetId] = c end
        local picked = {}
        for _, id in ipairs(chosen or {}) do
            local c = byId[id]
            if c and not picked[id] and #out < slots then
                local ok, why = M.anchorable(c)
                if ok then out[#out + 1] = { assetId = id, source = "chosen" }; picked[id] = true
                else refused[#refused + 1] = { assetId = id, reason = why } end
            end
        end
        if #out == 0 then
            local list = {}
            for _, c in ipairs(cars or {}) do if M.anchorable(c) then list[#list + 1] = c end end
            table.sort(list, function(a, b)
                if (a.races or 0) ~= (b.races or 0) then return (a.races or 0) > (b.races or 0) end
                if (a.odometerM or 0) ~= (b.odometerM or 0) then return (a.odometerM or 0) > (b.odometerM or 0) end
                return tostring(a.assetId) < tostring(b.assetId)
            end)
            if list[1] then out[1] = { assetId = list[1].assetId, source = "default" } end
        end
        return out, refused
    end

    --- W-3: halfway back to neutral.
    function M.srReset(sr)
        sr = tonumber(sr) or M.SR_NEUTRAL
        return M.SR_NEUTRAL + (sr - M.SR_NEUTRAL) / 2
    end

    --- W-4: the wallet's two ledger lines: close the run to zero, open the next with the new-player grant.
    function M.wallet(balance, grant)
        balance = math.floor(tonumber(balance) or 0)
        return { close = -balance, open = math.floor(tonumber(grant) or 0) }
    end

    -- Paddock tables that are NOT run-local: what the Paddock has learned about the physical world, not what happened
    -- in a week. Every other `paddock_*` table moves with the run (and a new one does by default, logged).
    M.PADDOCK_KEEP = { paddock_calibration = true, paddock_place_check = true, paddock_garage_check = true }

    function M.paddockMoves(tables)
        local out = {}
        for _, t in ipairs(tables or {}) do
            if t:match("^paddock_") and not M.PADDOCK_KEEP[t] then out[#out + 1] = t end
        end
        table.sort(out)
        return out
    end

    return M
end)
