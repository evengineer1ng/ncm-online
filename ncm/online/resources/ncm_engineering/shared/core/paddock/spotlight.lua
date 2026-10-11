-- ncm-core module: paddock.spotlight
-- Spotlight on human SANCTIONED racing (doc 44 §8). The Paddock watches the humans without ever racing them: a
-- human's sanctioned results earn spotlight; spotlight drives press mentions on WIRE and, past a threshold, an NPC
-- callout that opens an arc. The arc resolves on the human's NEXT sanctioned result, never on an NPC race (L224.1).
local Core = NcmCore

Core.define("paddock.spotlight", function(C)
    local M = { version = "0.1.0", MENTION = 10, CALLOUT = 25, DECAY_PER_DAY = 0.05, ARC_DAYS = 7 }

    local BY_POS = { 10, 6, 4, 2, 1 }

    --- Spotlight earned by one sanctioned result. `r` = { position, state, fieldSize, gridPos, streak }.
    function M.earned(r)
        if r.state ~= "finished" then return 0 end
        local base = BY_POS[r.position] or 0
        if base == 0 then return 0 end
        local field = math.min(2, math.max(0.5, (r.fieldSize or 2) / 6))
        local climb = math.max(0, (r.gridPos or r.position) - r.position) * 0.5
        local streak = math.min(6, (r.streak or 0) * 1.5)
        return base * field + climb + streak
    end

    --- Apply decay for elapsed whole days, then add `gain`. Returns the new score.
    function M.update(score, days, gain)
        local s = (score or 0) * (1 - M.DECAY_PER_DAY) ^ math.max(0, days or 0)
        return math.floor((s + (gain or 0)) * 1000 + 0.5) / 1000
    end

    --- Callout arc states: open -> won | lost | expired.
    function M.openArc(arcId, npcPersonId, humanId, at)
        return { arcId = arcId, state = "open", npcPersonId = npcPersonId, humanId = humanId, openedAt = at,
            resolvesBy = at + M.ARC_DAYS * 86400 }
    end

    --- Resolve an open arc by the human's next sanctioned result, or expire it. Returns the arc (mutated) and
    --- whether it changed.
    function M.resolveArc(arc, result, now)
        if arc.state ~= "open" then return arc, false end
        if result then
            arc.state = (result.state == "finished" and result.position <= 3) and "won" or "lost"
            arc.resolvedAt = now
            return arc, true
        end
        if now >= arc.resolvesBy then
            arc.state, arc.resolvedAt = "expired", now
            return arc, true
        end
        return arc, false
    end

    return M
end)
