-- ncm-core module: player.leads
-- A Lead is knowledge the player cannot yet use (L175).
--
-- The middle state between "unknown" and "accessible": a market heard of but not reachable, a Part Design whose
-- origin is unknown, a person mentioned but not met, a place named but not found. `17_MARKET_NETWORK.md` already
-- separated knowledge from access ("knowledge and access may diverge") and `28_MACHINE_KNOWLEDGE.md` already
-- models machine knowledge as independent accumulating channels rather than a tier ladder; this is the same
-- shape, generalised, so that one object can carry all of them.
--
-- This module owns the vocabulary and the state machine and nothing else. Persistence belongs to the host, and
-- whether a lead's subject is *actually* accessible is always the owning system's answer, never this one's --
-- a lead records that the player knows of a thing, not what the thing currently permits.
--
-- Deliberately NOT a quest: no steps, no objective text, no ordering, no completion percentage. A lead resolves
-- when its subject becomes known or accessible through ANY route, including routes nobody authored (L175).
local Core = NcmCore

Core.define("player.leads", function()
    local M = { version = "0.1.0" }

    --- What a lead can be about. The subject is (kind, ref) and the ref is that domain's own identifier --
    --- a marketId, a vehicleKey, a designId -- never a display name, because names are editable.
    M.SUBJECTS = {
        market = true,          -- a commercial surface you have heard of
        machine = true,         -- a vehicleKey you know exists but have not encountered
        design = true,          -- a Part Design, typically learned from provenance
        manufacturer = true,
        person = true,          -- an authored contact you have been told about but not met
        place = true,           -- a location named but not found
        event = true,           -- a race/championship you have heard is happening
        research = true,        -- a question worth answering
    }

    --- WHY the player knows. This is the field later characters react to, so it is not optional and it is not
    --- free text: "Rico told you" and "it was stamped on a part you were traded" are different stories.
    M.SOURCES = {
        character = true,       -- someone told you (source_ref = contactId)
        provenance = true,      -- an owned/traded asset carried its origin (IDEA-609)
        observation = true,     -- you saw it
        research = true,        -- you worked it out
        market = true,          -- a commercial surface disclosed it
        event = true,           -- it came out of a race/championship
        world = true,           -- a place or object in the world said so
        dispatch = true,        -- NCM told you (the session-zero lead, L171)
    }

    --- open   -- known, not yet usable
    --- closed -- the subject became known/accessible; the lead did its job
    --- cold   -- authored expiry only; the default is that knowledge is permanent (L175)
    M.STATES = { open = true, closed = true, cold = true }

    M.TERMINAL = { closed = true, cold = true }

    local function nonempty(v)
        return type(v) == "string" and v:match("%S") ~= nil
    end

    local function posInt(v)
        local n = tonumber(v)
        if n == nil or n ~= n then return nil end
        n = math.floor(n)
        if n < 0 then return nil end
        return n
    end

    --- The identity of a lead is its subject, not its telling. Two characters mentioning the same market are one
    --- lead learned twice, not two leads -- otherwise "multiple unresolved leads" (Glass's trigger) would count
    --- gossip rather than mystery.
    function M.key(subjectKind, subjectRef)
        if not M.SUBJECTS[tostring(subjectKind or "")] then return nil, "invalid_subject_kind" end
        if not nonempty(subjectRef) then return nil, "invalid_subject_ref" end
        return tostring(subjectKind) .. ":" .. tostring(subjectRef)
    end

    --- Validate and normalise an authored or emitted lead.
    --- def = { subjectKind, subjectRef, sourceKind, sourceRef?, note?, at? }
    function M.normalize(def)
        if type(def) ~= "table" then return nil, "lead_not_table" end
        local key, why = M.key(def.subjectKind, def.subjectRef)
        if not key then return nil, why end
        local sourceKind = tostring(def.sourceKind or "")
        if not M.SOURCES[sourceKind] then return nil, "invalid_source_kind" end
        -- a character source without a ref is unattributable, and attribution is the whole point of the field
        if sourceKind == "character" and not nonempty(def.sourceRef) then return nil, "character_source_needs_ref" end
        local at = posInt(def.at)
        return {
            key = key,
            subjectKind = tostring(def.subjectKind),
            subjectRef = tostring(def.subjectRef),
            sourceKind = sourceKind,
            sourceRef = nonempty(def.sourceRef) and tostring(def.sourceRef) or nil,
            note = nonempty(def.note) and tostring(def.note) or nil,
            state = "open",
            at = at,
        }
    end

    --- Should this lead be recorded at all?
    --- facts = { existing (a stored lead or nil), subjectAlreadyAccessible (boolean) }
    --- Distinct refusals on purpose (L83): "you can already use this" and "you were already told" are different
    --- facts, and a character reacting to them should be able to tell them apart.
    function M.admit(def, facts)
        local lead, why = M.normalize(def)
        if not lead then return false, why end
        facts = type(facts) == "table" and facts or {}
        if facts.subjectAlreadyAccessible == true then return false, "already_accessible" end
        local existing = facts.existing
        if type(existing) == "table" then
            if M.TERMINAL[tostring(existing.state or "")] then return false, "already_resolved" end
            return false, "already_known"
        end
        return true, nil, lead
    end

    --- Resolve a lead because its subject became reachable. `reason` is free-form for the record; the state is
    --- not. Resolving an already-terminal lead is a no-op rather than an error: leads close from several
    --- directions at once (a character introduces you to a market you had already walked into), and the second
    --- one arriving is normal, not a fault.
    function M.resolve(lead, reason, at)
        if type(lead) ~= "table" then return nil, "lead_not_table" end
        if M.TERMINAL[tostring(lead.state or "")] then return lead, nil end
        lead.state = "closed"
        lead.resolvedReason = nonempty(reason) and tostring(reason) or nil
        lead.resolvedAt = posInt(at)
        return lead, nil
    end

    --- Authored expiry. Rare by design: the default is that knowledge is permanent (L175).
    function M.expire(lead, reason, at)
        if type(lead) ~= "table" then return nil, "lead_not_table" end
        if M.TERMINAL[tostring(lead.state or "")] then return lead, nil end
        lead.state = "cold"
        lead.resolvedReason = nonempty(reason) and tostring(reason) or nil
        lead.resolvedAt = posInt(at)
        return lead, nil
    end

    --- How many leads are open, optionally for one subject kind. This is Glass's trigger (L175) and it is a
    --- COUNT FOR THE SERVER, not a number for the player: L171's leak discipline and L175's "leads must not
    --- become a checklist" both apply, so nothing here should reach a UI as "3 / 8".
    function M.openCount(leads, subjectKind)
        local n = 0
        for _, l in ipairs(type(leads) == "table" and leads or {}) do
            if type(l) == "table" and tostring(l.state or "") == "open" then
                if subjectKind == nil or tostring(l.subjectKind or "") == tostring(subjectKind) then n = n + 1 end
            end
        end
        return n
    end

    --- The unresolved set, newest first -- Dex's context shelf (41_QUEST_GRAPH_PASS1.md section 2.4) is this
    --- list rendered. `limit` is a display bound, not a cap on what the player may know.
    function M.shelf(leads, limit)
        local open = {}
        for _, l in ipairs(type(leads) == "table" and leads or {}) do
            if type(l) == "table" and tostring(l.state or "") == "open" then open[#open + 1] = l end
        end
        table.sort(open, function(a, b)
            local ta, tb = tonumber(a.at) or 0, tonumber(b.at) or 0
            if ta ~= tb then return ta > tb end
            return tostring(a.key) < tostring(b.key)
        end)
        local cap = posInt(limit)
        if cap and cap > 0 then
            local cut = {}
            for i = 1, math.min(cap, #open) do cut[i] = open[i] end
            return cut
        end
        return open
    end

    return M
end)
