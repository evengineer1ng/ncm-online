-- ncm_paddock / server / spotlight -- the Paddock watches the humans without racing them (doc 44 §8, L224.1).
--
-- A cursor walks completed human SANCTIONED races. Each result earns (and time decays) a driver's spotlight. Past
-- the mention line the driver appears on WIRE; past the callout line an NPC star calls them out: a story, an arc
-- and one message. The arc is settled by the human's NEXT sanctioned result -- never by an NPC race -- or expires.
PaddockSpotlight = {}

local U = PaddockUtil
local log = U.logger("spotlight")
local Spot = NcmCore.get("paddock.spotlight")
local Tape = NcmCore.get("paddock.tape")
local Attr = NcmCore.get("paddock.attributes")

-- Sanctioned championships (packs/street.lua `tier = "sanctioned"`, packs/ncx.lua) and organized events.
PaddockSpotlight.SERIES = { night_city_gt = "Night City GT", hypercar = "Hypercar Championship", ncx_invitational = "NCX Invitational" }

local function cursor()
    return tonumber(MySQL.scalar.await("SELECT value FROM paddock_cursor WHERE server_id = ? AND name = 'spotlight'", { U.sid() })) or 0
end
local function setCursor(v)
    MySQL.update.await([[INSERT INTO paddock_cursor (server_id, name, value) VALUES (?, 'spotlight', ?)
        ON DUPLICATE KEY UPDATE value = VALUES(value)]], { U.sid(), tostring(v) })
end

local function displayOf(driverId)
    return tostring(MySQL.scalar.await("SELECT display FROM driver_profile WHERE ncm_driver_id = ? AND server_id = ?",
        { driverId, U.sid() }) or "a driver")
end

-- The NPC who calls a human out: the biggest ego among the top two tiers' race-seat drivers, chosen stably.
local function caller(humanId)
    local w = PaddockStore.world
    local best, bestScore
    for _, oid in ipairs(w.orgOrder) do
        local o = w.orgs[oid]
        if o.lifecycle == "active" and (o.tier == "premier" or o.tier == "pro") then
            for _, p in ipairs(NcmCore.get("paddock.world").drivers(w, oid)) do
                local score = ((p.attrs and p.attrs.ego) or 50) + NcmCore.get("vocabulary.hash").unit(humanId, p.id) * 10
                if not bestScore or score > bestScore then best, bestScore = p, score end
            end
        end
    end
    return best
end

local function resultText(pos, state)
    if state ~= "finished" then return "a DNF" end
    if pos == 1 then return "a win" end
    if pos <= 3 then return "P" .. pos .. " on the podium" end
    return "P" .. pos
end

function PaddockSpotlight.scan(t)
    local from = cursor()
    local names = {}
    for id in pairs(PaddockSpotlight.SERIES) do names[#names + 1] = "'" .. id .. "'" end
    local rows = MySQL.query.await(([[SELECT s.session_id, s.completed_at, e.series_id, sr.ncm_driver_id, sr.position, sr.state,
            (SELECT COUNT(*) FROM session_result x WHERE x.session_id = s.session_id) AS field
        FROM session s JOIN event e ON e.event_id = s.event_id JOIN session_result sr ON sr.session_id = s.session_id
        WHERE e.server_id = ? AND s.state = 'complete' AND s.kind = 'race' AND s.completed_at > ?
          AND (e.series_id IN (%s) OR e.class = 'organized')
        ORDER BY s.completed_at, s.session_id LIMIT 200]]):format(table.concat(names, ",")), { U.sid(), from }) or {}
    if #rows == 0 then return end
    local sid = U.sid()
    local events = {}
    local maxAt = from
    for _, r in ipairs(rows) do
        local driverId, pos, state = r.ncm_driver_id, tonumber(r.position) or 99, r.state
        local at = tonumber(r.completed_at) or t
        if at > maxAt then maxAt = at end
        local cur = MySQL.single.await([[SELECT score, streak, updated_at FROM paddock_spotlight WHERE server_id = ? AND subject_kind = 'driver'
            AND subject_id = ?]], { sid, driverId })
        local score, streak, updated = cur and tonumber(cur.score) or 0, cur and tonumber(cur.streak) or 0, cur and tonumber(cur.updated_at) or at
        streak = (state == "finished" and pos <= 3) and (streak + 1) or 0
        local gain = Spot.earned({ position = pos, state = state, fieldSize = tonumber(r.field) or 2, streak = streak })
        local new = Spot.update(score, math.floor((at - updated) / 86400), gain)
        MySQL.update.await([[INSERT INTO paddock_spotlight (server_id, subject_kind, subject_id, score, streak, last_session_id, updated_at)
            VALUES (?, 'driver', ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE score = VALUES(score), streak = VALUES(streak),
            last_session_id = VALUES(last_session_id), updated_at = VALUES(updated_at)]], { sid, driverId, new, streak, r.session_id, at })
        local series = PaddockSpotlight.SERIES[r.series_id] or "sanctioned racing"
        local human = displayOf(driverId)
        -- an open callout is answered by this result
        local arc = MySQL.single.await([[SELECT * FROM paddock_arc WHERE server_id = ? AND human_id = ? AND state = 'open' AND opened_at < ?]],
            { sid, driverId, at })
        if arc then
            local a = Spot.resolveArc({ state = "open", resolvesBy = tonumber(arc.resolves_by) }, { position = pos, state = state }, at)
            MySQL.update.await("UPDATE paddock_arc SET state = ?, resolved_at = ?, resolved_by_session = ? WHERE server_id = ? AND arc_id = ?",
                { a.state, at, r.session_id, sid, arc.arc_id })
            local npc = PaddockWorld.personName(arc.npc_person_id)
            if a.state == "won" then
                events[#events + 1] = Tape.event("human_mention", arc.arc_id .. ":answer", at, { entities = { { "human", driverId }, { "person", arc.npc_person_id } },
                    facts = { human = human, result = resultText(pos, state) .. ", an answer to " .. npc, series = series }, salienceBonus = 15 })
            else
                PaddockStory.push(driverId, npc .. ": \"Told you.\"", npc .. " saw the result. The Paddock will remember this one.",
                    { thread = "paddock:arc", fromId = arc.npc_person_id })
            end
        end
        if score < Spot.MENTION and new >= Spot.MENTION then
            events[#events + 1] = Tape.event("human_mention", r.session_id .. ":" .. driverId, at, {
                entities = { { "human", driverId } }, facts = { human = human, result = resultText(pos, state), series = series } })
        end
        if new >= Spot.CALLOUT and not arc then
            local open = MySQL.scalar.await("SELECT COUNT(*) FROM paddock_arc WHERE server_id = ? AND human_id = ? AND state = 'open'", { sid, driverId })
            local npc = (tonumber(open) or 0) == 0 and caller(driverId) or nil
            if npc then
                local arcId = "callout:" .. driverId:sub(1, 8) .. ":" .. at
                local ev = Tape.event("callout", arcId, at, { entities = { { "person", npc.id }, { "human", driverId } },
                    facts = { npc = npc.display, npcOrg = PaddockWorld.orgName(npc.orgId), human = human, series = series } })
                events[#events + 1] = ev
                local arcRow = Spot.openArc(arcId, npc.id, driverId, at)
                MySQL.insert.await([[INSERT IGNORE INTO paddock_arc (server_id, arc_id, kind, state, npc_person_id, human_kind, human_id,
                    opened_event_id, opened_at, resolves_by) VALUES (?, ?, 'callout', 'open', ?, 'driver', ?, ?, ?, ?)]],
                    { sid, arcId, npc.id, driverId, ev.id, at, arcRow.resolvesBy })
                PaddockStory.push(driverId, npc.display .. " has something to say",
                    ("\"Let's see you do it again.\" %s of %s is watching your next %s race."):format(npc.display,
                        PaddockWorld.orgName(npc.orgId), series), { thread = "paddock:arc", fromId = npc.id })
            end
        end
    end
    -- callouts nobody answered in time
    MySQL.update.await("UPDATE paddock_arc SET state = 'expired', resolved_at = ? WHERE server_id = ? AND state = 'open' AND resolves_by < ?",
        { t, sid, t })
    setCursor(maxAt)
    PaddockStory.record(events)
    log("scanned %d sanctioned result(s); %d stor(ies)", #rows, #events)
end
