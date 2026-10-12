-- ncm-core module: space.sport
--
-- Sport forms from what exists (L321; doc 54 §G). Nothing here is unlocked by a date or a tech level: a venue gets a
-- race only when enough machines in the world can physically fly it, and a sanctioned CLASS appears only when the
-- population is big enough that a regulation envelope (a delta-v or thrust-to-weight band) leaves a real field. A seed
-- whose history never produced a vacuum-capable engine has no station racing; one where Los Santos fans spread
-- everywhere has a busy sky ring. Then Snowglobe's racing becomes Race Week EVIDENCE in the common vocabulary
-- (doc 52 §5) -- hidden from players; correlations are for them to discover.
local Core = NcmCore

Core.define("space.sport", function(C)
    local M = { version = "0.1.0" }
    local Race = C.get("space.racesim")

    M.EXHIBITION_MIN = 2
    M.CLASS_MIN = 6

    local function quantile(xs, q)
        local t = {}
        for i, x in ipairs(xs) do t[i] = x end
        table.sort(t)
        if #t == 0 then return nil end
        local idx = math.max(1, math.min(#t, math.floor(q * (#t - 1) + 1.5)))
        return t[idx]
    end

    --- For every venue: who can fly it, and what kind of event that supports.
    --- machines = { { id, orgId, model = <assembled>, models = { sprint = <assembled>, fireball = <assembled> }? } }.
    --- Returns { { venueId, kind, status, eligible = {ids},
    --- refused = { {id, reason} }, envelope? } }.
    function M.formEvents(venues, machines)
        local out = {}
        for _, v in ipairs(venues) do
            local ok, refused, metric = {}, {}, {}
            local useDv = v.kind == "station_ring" or v.kind == "fireball"
            for _, m in ipairs(machines) do
                -- an org enters the machine it built for this discipline when it has one (L322)
                local model = (m.models and m.models[v.kind]) or (not (m.models and (v.kind == "sprint" or v.kind == "fireball")) and m.model) or nil
                local est = model and Race.estimate(model, v) or { eligible = false, reason = "no machine built for " .. v.kind }
                if est.eligible then
                    ok[#ok + 1] = m.id
                    metric[#metric + 1] = useDv and est.cap.deltaVms or est.twr
                else
                    refused[#refused + 1] = { id = m.id, reason = est.reason }
                end
            end
            local ev = { venueId = v.id, kind = v.kind, name = v.name, eligible = ok, refused = refused }
            if #ok >= M.CLASS_MIN then
                ev.status = "class"
                ev.envelope = { metric = useDv and "deltaVms" or "twr",
                                min = quantile(metric, 0.1), max = quantile(metric, 0.9) }
            elseif #ok >= M.EXHIBITION_MIN then
                ev.status = "exhibition"
            else
                ev.status = "none"
            end
            out[#out + 1] = ev
        end
        return out
    end

    --- Snowglobe's contribution to the Race Week, in the common evidence vocabulary (doc 52 §5). Signals are 0..1.
    --- events = formEvents(...); results = { { venueId, rows = racesim.result(...) } }.
    function M.weekEvidence(world, events, results)
        local active, eligibleShare = 0, 0
        local stationVenues = 0
        for _, e in ipairs(events) do
            if e.status ~= "none" then active = active + 1 end
            if e.kind == "station_ring" then
                stationVenues = stationVenues + 1
                eligibleShare = math.max(eligibleShare, #e.eligible / math.max(1, #world.machines))
            end
        end
        local starters, dnfs, physical = 0, 0, 0
        for _, r in ipairs(results or {}) do
            for _, row in ipairs(r.rows) do
                starters = starters + 1
                if row.state == "dnf" then dnfs = dnfs + 1 end
                if row.mode ~= "simulated" then physical = physical + 1 end
            end
        end
        return {
            domain = "snowglobe", visibility = "hidden",
            signals = {
                racing_intensity = #events > 0 and active / #events or 0,
                technological_capability = eligibleShare,
                participation = math.min(1, starters / math.max(1, #world.orgs * math.max(1, #(results or {})))),
                infrastructure_readiness = math.min(1, #world.stations / 3),
                casualties_damage = starters > 0 and dnfs / starters or 0,
            },
            confidence = starters > 0 and (physical > 0 and "observed" or "simulated") or "none",
        }
    end

    return M
end)
