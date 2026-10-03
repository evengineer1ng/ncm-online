-- ncm-core module: paddock.mixed
-- Mixed NPC/human Paddock grids (L250 steps 3-4; reverses L224.1). Pure: both hosts call it -- ncm_paddock for the
-- grid it freezes and the classification it resolves, ncm_league for the event a Paddock race becomes on its calendar.
--
--   a human's id in the Paddock    `personKey(driverId)`: "h" + 15 hex of the driver's id, the 16 characters a Paddock
--                                  person id may be (schema 045/047), and never an NPC's ("p00123")
--   the grid                       everyone with a qualifying time fastest first (NPC sim times and human best runs
--                                  side by side), then entered-but-unqualified humans in the order they entered
--   the field                      fixed by attendance: each human takes the place of the last NPC who turned up
--   the classification             finishers by time from the one green, then the rest; positions and gaps rewritten
--   the league's event             a Paddock race as an ordinary calendar event of class "paddock": entries and
--                                  qualifying close at T-11 (the Paddock freezes at T-10, so an entry is never late)
local Core = NcmCore

Core.define("paddock.mixed", function(C)
    local M = { version = "0.1.0" }

    M.ENTRY_CLOSE_LEAD_SEC = 60         -- entries and qualifying close at T-1 ...
    M.FREEZE_LEAD_SEC = 60              -- ... then the Paddock freezes the field and grid
    M.GRID_HOLD_SEC = 12                -- a mixed grid's DNS deadline (L296: no auto-place -- a human drives onto the slot,
                                        -- routed to it from T-15 min by the pre-grid)
    M.CLASSIFY_WAIT_SEC = 300           -- the league waits this long for the Paddock's classification, then settles alone
    M.HUMAN_RESULT_WAIT_SEC = 1200      -- the Paddock holds a mixed race's close this long past green for human results
    -- THE FLAG (owner, 2026-10-02: "a certain amount of seconds per meter of time added to end of race after leader
    -- crosses the line, showing the timer counting down"). When the first car crosses the line, everyone else has this
    -- long; whoever is not home then is classified by how far they got. One rule for NPCs and humans.
    -- (0.03 s/m gave 173 s on a 5.75 km race: "way too long", owner 2026-10-02)
    M.FLAG_SEC_PER_M = 0.012            -- 2.5 km -> 30 s, 5.75 km -> 69 s
    M.FLAG_MIN_SEC, M.FLAG_MAX_SEC = 30, 90

    --- Seconds from the leader's crossing to the flag, for a race of lengthM metres.
    function M.finishWindowSec(lengthM)
        return math.floor(math.max(M.FLAG_MIN_SEC, math.min(M.FLAG_MAX_SEC, (tonumber(lengthM) or 0) * M.FLAG_SEC_PER_M)) + 0.5)
    end

    function M.personKey(driverId)
        local hex = tostring(driverId or ""):gsub("[^%w]", "")
        return "h" .. hex:sub(1, 15)
    end

    function M.isHuman(id) return type(id) == "string" and id:sub(1, 1) == "h" end

    --- How many NPCs give up their place: one per human, never more NPCs than there are.
    function M.npcPlaces(npcCount, humanCount)
        return math.max(0, (npcCount or 0) - (humanCount or 0))
    end

    --- The grid. `npcs` = { { id, qualiMs } } (already in the sim's qualifying order); `humans` = { { key, qualiMs?,
    --- enteredAt } }. Returns the ids in grid order and the qualifying map { [id] = ms }.
    function M.gridOrder(npcs, humans)
        local timed, untimed = {}, {}
        for i, n in ipairs(npcs or {}) do timed[#timed + 1] = { id = n.id, ms = n.qualiMs, rank = i, npc = true } end
        for _, h in ipairs(humans or {}) do
            if tonumber(h.qualiMs) then timed[#timed + 1] = { id = h.key, ms = tonumber(h.qualiMs), rank = 0 }
            else untimed[#untimed + 1] = h end
        end
        table.sort(timed, function(a, b)
            if a.ms and b.ms and a.ms ~= b.ms then return a.ms < b.ms end
            if (a.ms ~= nil) ~= (b.ms ~= nil) then return a.ms ~= nil end   -- an NPC with no time (no base) keeps its order behind the timed
            if a.npc ~= b.npc then return b.npc end                       -- a tie goes to the human who set it
            if a.rank ~= b.rank then return a.rank < b.rank end
            return tostring(a.id) < tostring(b.id)
        end)
        table.sort(untimed, function(a, b)
            if (a.enteredAt or 0) ~= (b.enteredAt or 0) then return (a.enteredAt or 0) < (b.enteredAt or 0) end
            return tostring(a.key) < tostring(b.key)
        end)
        local order, quali = {}, {}
        for _, x in ipairs(timed) do order[#order + 1] = x.id; quali[x.id] = x.ms end
        for _, h in ipairs(untimed) do order[#order + 1] = h.key end
        return order, quali
    end

    local RANK = { finished = 1, dnf = 2, dsq = 3, dns = 4 }

    --- The merged classification. `npcEntrants` = the Paddock's result rows ({ id, state, finishMs, progressFrac?, ... });
    --- `humans` = { { key, state, finishMs, progressFrac, grid, dnfReason } }. Returns a new list, positions and gaps
    --- rewritten; NPC rows keep every other field.
    function M.merge(npcEntrants, humans)
        local all = {}
        for i, e in ipairs(npcEntrants or {}) do
            local copy = {}
            for k, v in pairs(e) do copy[k] = v end
            copy._npcRank = i
            all[#all + 1] = copy
        end
        for _, h in ipairs(humans or {}) do
            all[#all + 1] = { id = h.key, orgId = "", human = true, state = h.state or "dns", finishMs = h.finishMs,
                grid = h.grid, dnfReason = h.dnfReason, progressFrac = h.progressFrac or 0, _npcRank = math.huge,
                rawFinishMs = h.rawFinishMs, penaltyMs = h.penaltyMs }
        end
        table.sort(all, function(a, b)
            local ra, rb = RANK[a.state] or 5, RANK[b.state] or 5
            if ra ~= rb then return ra < rb end
            if a.state == "finished" and (a.finishMs or 0) ~= (b.finishMs or 0) then return (a.finishMs or 0) < (b.finishMs or 0) end
            if a.state == "dnf" then
                -- the sim orders its own retirements (just under a whole course each, in its order); a human
                -- retirement goes by how far they got
                -- (a car flagged with the race still on: how far it got, like a human -- `progressFrac` from the model)
                local fa = (a.human or a.progressFrac) and (a.progressFrac or 0) or (1 - (a._npcRank / 1000))
                local fb = (b.human or b.progressFrac) and (b.progressFrac or 0) or (1 - (b._npcRank / 1000))
                if fa ~= fb then return fa > fb end
            end
            if a._npcRank ~= b._npcRank then return a._npcRank < b._npcRank end
            return tostring(a.id) < tostring(b.id)
        end)
        local lead = all[1] and all[1].state == "finished" and all[1].finishMs or nil
        for i, e in ipairs(all) do
            e.position = i
            e.gapMs = (e.state == "finished" and lead and e.finishMs) and (e.finishMs - lead) or nil
            e._npcRank = nil
        end
        return all
    end

    --- The classification ceremony (owner, 2026-10-02: "the full leaderboard pops up as of race finish, and then a
    --- visible shuffle of order based on penalties, green ... moved up and red ... moved down"). From a merged
    --- classification whose rows carry `rawFinishMs` (as they crossed) and `penaltyMs`: every row with `rawPos` (the
    --- order on the road at the flag) and `pos` (the result), `moved` = rawPos - pos (positive = up).
    function M.ceremony(merged)
        local rows = {}
        for _, e in ipairs(merged or {}) do
            rows[#rows + 1] = { id = e.id, pos = e.position, state = e.state, human = e.human or M.isHuman(e.id) or nil,
                finalMs = e.state == "finished" and e.finishMs or nil, penaltyMs = e.penaltyMs or 0,
                rawMs = e.state == "finished" and (e.rawFinishMs or e.finishMs) or nil, dnfReason = e.dnfReason }
        end
        local road = {}
        for i, r in ipairs(rows) do road[i] = r end
        table.sort(road, function(a, b)
            if (a.rawMs ~= nil) ~= (b.rawMs ~= nil) then return a.rawMs ~= nil end
            if a.rawMs and b.rawMs and a.rawMs ~= b.rawMs then return a.rawMs < b.rawMs end
            return a.pos < b.pos
        end)
        for i, r in ipairs(road) do r.rawPos = i; r.moved = i - r.pos end
        return rows
    end

    --- { [key] = position } for the humans of a merged classification, and its field size.
    function M.humanPlaces(merged)
        local out = {}
        for _, e in ipairs(merged or {}) do if e.human or M.isHuman(e.id) then out[e.id] = e.position end end
        return out, #(merged or {})
    end

    --- A Paddock race (a row of GlobalState.ncmPaddockGuide) as a calendar event. `route` = course.routes.resolve of
    --- its route; `pack` = the league series it is named after (economy, eligibility), or nil; `economy` = the
    --- fallback street economy. Returns the event or nil + reason. Ovals use their authored marks and lap count.
    function M.eventFromRow(row, route, now, pack, economy)
        if type(row) ~= "table" or not row.raceId or not tonumber(row.startsAt) then return nil, "bad_row" end
        if not route or not route.start or not route.finish then return nil, "no_route" end
        local startsAt = tonumber(row.startsAt)
        if startsAt - now <= M.ENTRY_CLOSE_LEAD_SEC then return nil, "entries_closed" end
        local s, f = route.start, route.finish
        local venue = route.oval and route.oval.entry or s
        -- Calendar snapshots stay small: publish the four authored oval marks, not the repeated checkpoint list per lap.
        local via = route.oval and route.oval.loop or route.intermediate
        return {
            eventId = "paddock:" .. tostring(row.raceId), paddockRaceId = row.raceId, class = "paddock",
            tier = row.tier == "street" and "street" or "sanctioned",
            seriesId = pack and pack.seriesId or ("paddock_" .. tostring(row.seriesId)),
            paddockSeriesId = row.seriesId, seriesName = row.seriesName, rulesetId = "street_sprint_v0",
            routeId = row.routeId, routeName = row.routeName or route.name,
            startsAt = startsAt, entryOpensAt = now, entryClosesAt = startsAt - M.ENTRY_CLOSE_LEAD_SEC, postedAt = now,
            practiceCloseLeadSec = M.ENTRY_CLOSE_LEAD_SEC,
            venue = { x = venue.x, y = venue.y, z = venue.z, heading = venue.heading or s.heading, name = venue.name or s.name, nodeId = venue.id or s.id },
            finish = { x = f.x, y = f.y, z = f.z, name = f.name, nodeId = f.id },
            via = via, distanceM = route.distanceM or row.distanceM or 0, venueRadiusM = 40,
            state = "entry_open", entries = {}, seatsTotal = tonumber(row.field) or 0,
            disciplineId = row.oval and "oval" or "street_sprint", formatId = "sprint", classId = "street_open",
            laps = row.oval and (tonumber(row.laps) or (route.oval and route.oval.laps) or 1) or 1,
            economy = (pack and pack.economy) or economy, standing = true,
            -- L296: a mixed grid starts STANDING, oval or street -- its NPCs launch from the grid at the lights (Pace,
            -- staggered by row), so a human may not be held to a formation lap beside them. (L79's rolling start is
            -- for the human-only oval events; the laps discipline would otherwise default a Paddock oval to rolling.)
            startType = "standing",
        }
    end

    return M
end)
