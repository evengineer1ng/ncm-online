-- ncm_ls_space / server / events: Snowglobe's own disciplines, run by the authority (L322; doc 54 §L-§P).
--
-- UNSEEN RACING. Every `snowglobeEveryMin` minutes of the shared clock a Snowglobe event is due (`space.calendar`):
-- the venues with Snowglobe disciplines in turn. If no player is racing it, it runs ABSTRACT (`space.racesim`:
-- physics-derived pace through `paddock.sim`), and its outcome -- results, records, Race Week facts, every driver's
-- learning, every org's engineering response -- is COMMITTED as `world.seed` modifications and persisted in the
-- resource KVP. Boot rebuilds the world from the seed plus that history. Nobody has to watch for it to happen.
--
-- RACING IT. `/ncm.race N` on a Sprint or Fireball venue builds the event with the player as an EXTERNAL entrant
-- (their client flies, their client's universe samples are judged here) and the NPC field at TACTICAL fidelity
-- (`space.tactical`: their machines, their drivers' behaviour and competency, `engineering.dynamics`). The server
-- steps the tactical race in real time and streams NPC states to the player's client at 10 Hz, which presents them as
-- local cars. Lights when the player is on the grid; five lights; go. The classification carries provenance: the
-- player `physical`, the NPCs `tactical`. HOST BOUNDARY (doc 54 §Q): the NPC cars are client-local presentation --
-- GTA collisions with them are not reported to NCM in v0; contact between NPCs is NCM's.
local Core = NcmCore
local U = Core.get("space.universe")
local Seed = Core.get("world.seed")
local Gen = Core.get("space.genesis")
local Cal = Core.get("space.calendar")
local Tac = Core.get("space.tactical")
local Race = Core.get("space.racesim")
local Mach = Core.get("engineering.machine")
local Fx = Core.get("engineering.fixtures")
local Hash = Core.get("vocabulary.hash")
local Course = Core.get("space.course")
local C = NcmLsConfig
U.setWorld({ earthRadius = C.earthRadius, surfaceG = C.surfaceG })

local function log(fmt, ...) print(("[ncm_ls_space/snowglobe] " .. fmt):format(...)) end

local world = Cal.index(Gen.generate(Seed.root(C.universeSeed):child("snowglobe"), { sprintSpot = C.sprintSpot }))
local base = Cal.historyBase(world)
local KVP = "ncm_snowglobe_mods:" .. C.universeSeed
local mods = {}
do
    local raw = GetResourceKvpString(KVP)
    if raw and raw ~= "" then mods = json.decode(raw) or {} end
end
local history = Seed.compose(base, mods)
Cal.apply(world, history)
NcmSnowglobe = { world = world }
function NcmSnowglobe.facts() return history and history.facts or {} end

local function commit(newMods)
    for _, m in ipairs(newMods) do mods[#mods + 1] = m end
    SetResourceKvp(KVP, json.encode(mods))
    local rep
    history, rep = Seed.compose(base, mods)
    Cal.apply(world, history)
    if #rep.refused > 0 then log("history: %d mod(s) refused (first: %s)", #rep.refused, tostring(rep.refused[1].reason)) end
end

local nameOf = {}
for _, p in ipairs(world.pilots) do nameOf[p.id] = p.display end
local shortOf = {}
for _, o in ipairs(world.orgs) do shortOf[o.id] = o.short end
local function label(id, orgId) return (nameOf[id] or tostring(id)) .. (orgId and shortOf[orgId] and (" (" .. shortOf[orgId] .. ")") or "") end

local function ranSlot(id)
    for _, e in ipairs(history.events) do if e.id == id then return true end end
    return false
end

-- ------------------------------------------------------------------------------------------ unseen racing
local function venueBusy(vi) return NcmSnowglobeOpen and NcmSnowglobeOpen[vi] ~= nil end

local function runAbstract(vi, slot)
    local ev = Cal.event(world, vi, slot, { t0 = os.time() - C.orbitEpoch })
    if ranSlot(ev.id) then return end
    local entrants = {}
    for _, e in ipairs(ev.entrants) do entrants[#entrants + 1] = { id = e.id, orgId = e.orgId, pilot = e.person, machine = Mach.assemble(e.design) } end
    if #entrants < 2 then
        log("unseen %s (slot %d): fewer than two machines can fly it; no event", ev.venueInfo.name, slot)
        commit({ { id = ev.id .. "#0", at = os.time(), path = "events", op = "append", value = { id = ev.id, venue = ev.venueInfo.name, discipline = ev.discipline, fidelity = "abstract", at = os.time(), rows = {} } } })
        return
    end
    local out = Race.race(ev.venueInfo, entrants, Hash.stream(ev.id, "abstract"))
    local rows = {}
    for _, r in ipairs(Race.result(out)) do
        rows[#rows + 1] = { id = r.id, position = r.position, state = r.state, raceS = r.finishMs and r.finishMs / 1000 or nil,
            reason = r.dnfReason, mode = r.mode, orgId = r.orgId }
    end
    commit(Cal.outcome(world, ev, rows, "abstract", os.time()))
    log("UNSEEN %s at %s (slot %d, abstract): %d starters", ev.discipline:upper(), ev.venueInfo.name, slot, #rows)
    for _, r in ipairs(rows) do
        log("  P%d %-34s %s %s", r.position, label(r.id, r.orgId), r.raceS and ("%.3f s"):format(r.raceS) or tostring(r.reason or r.state), r.mode)
    end
    log("  Race Week facts so far (hidden): race %d, race_crash %d, clean_race %d", history.facts.race, history.facts.race_crash, history.facts.clean_race)
end

CreateThread(function()
    Wait(3000)
    log("Snowglobe history: %d event(s) committed, %d record(s); %d mod(s) in KVP", #history.events, #history.records, #mods)
    local last = nil
    while true do
        local minute = math.floor(os.time() / 60)
        local vi, slot = Cal.due(world, minute, C.snowglobeEveryMin)
        if slot ~= last then
            last = slot
            if not venueBusy(vi) then
                local ok, err = pcall(runAbstract, vi, slot)
                if not ok then log("unseen event failed: %s", tostring(err)) end
            end
        end
        Wait(30000)
    end
end)

-- ------------------------------------------------------------------------------------------ racing it
-- L323: races are keyed by EVENT, not by player. `/ncm.race N` opens venue N's event or JOINS the one already on its
-- grid; every player is an external entrant with their own lane (sprint) or grid slot. Lights when every player is
-- ready, or `C.lightsStragglerS` after the first one is (the rest start where they are). Everyone in the event
-- receives the NPC field AND the other players as universe states and presents them in their own frame: in Snowglobe
-- every client has its own floating origin, so a networked GTA car sits at ONE local position that is right for at
-- most one viewer -- universe-state presentation is how several players share a race above the doorway (doc 54 §S).
-- Contact a client reports against an NPC is checked here against the race's own positions and becomes physics
-- (`space.tactical.contactExternal`). Samples are stamped in SERVER time after a min-RTT clock sync (`ping`).
local open = {}            -- venue index -> the event on its grid or racing
local byPlayer = {}        -- src -> venue index
NcmSnowglobeOpen = open

local function serverS() return GetGameTimer() / 1000 end
local function pid(src) return "player:" .. src end

local function playerPerson(src)
    return { id = pid(src), display = GetPlayerName(src), attrs = {}, personality = {} }
end

local function compact(race)
    local out = {}
    for _, id in ipairs(race.order) do
        local E = race.entrants[id]
        if not E.external then
            local d = E.s.dyn
            out[#out + 1] = { id = id, p = d.pos, v = d.vel, z = { d.rot[1][3], d.rot[2][3], d.rot[3][3] },
                y = { d.rot[1][2], d.rot[2][2], d.rot[3][2] }, st = E.s.status, c = E.s.judge.creditM, n = E.s.note }
        end
    end
    return out
end

-- (re)build the event for the current roster: players take the first lanes, NPCs the rest
local function rebuild(L)
    local ext = {}
    for _, src in ipairs(L.roster) do
        ext[#ext + 1] = { id = pid(src), person = playerPerson(src), design = L.machines[src], external = true }
    end
    L.ev = Cal.event(world, L.vi, L.slot, { t0 = os.time() - C.orbitEpoch, startT = C.lightsS, external = ext })
    L.race = Tac.new(L.ev)
end

local function fieldInfo(L, src)
    local venue = L.ev.venueInfo
    local field = {}
    for i, e in ipairs(L.ev.entrants) do
        local isPlayer = e.external
        local s = isPlayer and tonumber(e.id:sub(8)) or nil
        field[#field + 1] = { id = e.id, name = isPlayer and GetPlayerName(s) or label(e.id, e.orgId), lane = i,
            player = isPlayer or nil, me = (s == src) or nil, serverId = s, machine = e.design.id, purpose = e.design.purpose }
    end
    local info = { vi = L.vi, kind = venue.kind, style = venue.style, name = venue.name, distanceM = venue.distanceM,
        lanes = venue.lanes, startT = C.lightsS, inner = venue.inner, outer = venue.outer, field = field, npcs = compact(L.race),
        eventId = L.ev.id }
    if venue.kind == "sprint" then
        local f = L.ev.venue.frame
        info.frame = { origin = f.origin, x = f.x, y = f.y, z = f.z }
        for i, e in ipairs(L.ev.entrants) do
            if e.id == pid(src) then info.mySpot = Course.toWorld(f, Core.get("space.sprint").laneSpot(L.ev.rules, i)) end
        end
    else
        info.grid = L.ev.venue.gridCentre
    end
    return info
end

local function broadcastField(L)
    for _, src in ipairs(L.roster) do TriggerClientEvent("ncm:ls:ev:field", src, fieldInfo(L, src)) end
end

RegisterNetEvent("ncm:ls:ev:enter", function(vi, machineName)
    local src = source
    vi = tonumber(vi)
    local venue = world.venues[vi or 0]
    if not venue or (venue.kind ~= "sprint" and venue.kind ~= "fireball") then return end
    if venue.domain == "night_city" then
        TriggerClientEvent("ncm:ls:say", src, venue.name .. " is in Night City: race it there.")
        return
    end
    if byPlayer[src] then return end
    local design = Fx.MACHINES[machineName or ""] or Fx.MACHINES[C.machine]
    local L = open[vi]
    if L and (L.phase ~= "grid" or #L.roster >= (venue.lanes or 8)) then
        TriggerClientEvent("ncm:ls:say", src, venue.name .. ": the race is already under way -- wait for the next one.")
        return
    end
    if not L then
        L = { vi = vi, slot = math.floor(os.time() / 60) * 100 + src, roster = {}, machines = {}, ready = {}, lastU = {}, phase = "grid",
              lastSend = 0, offsets = {} }
        open[vi] = L
    end
    L.roster[#L.roster + 1] = src
    L.machines[src] = design
    byPlayer[src] = vi
    rebuild(L)
    log("player %d %s %s (%s): %d player(s), %d NPC(s); %s", src, #L.roster == 1 and "opens" or "joins", venue.name,
        venue.kind, #L.roster, #L.ev.entrants - #L.roster, design.id)
    broadcastField(L)
    if NcmLsLink and NcmLsLink.discover then NcmLsLink.discover(src, "snowglobe_event") end
end)

local function leave(src, why)
    local vi = byPlayer[src]
    byPlayer[src] = nil
    local L = vi and open[vi]
    if not L then return end
    for i, s in ipairs(L.roster) do if s == src then table.remove(L.roster, i) break end end
    log("player %d left %s (%s)", src, L.ev.venueInfo.name, why)
    if L.phase == "grid" then
        if #L.roster == 0 then open[vi] = nil else rebuild(L); broadcastField(L) end
    else
        -- racing: their entrant stays external (frozen where last seen) and is classified by how far they got;
        -- if nobody is left, the NPCs race on unseen and the result still commits
        L.gone = L.gone or {}
        L.gone[pid(src)] = true
    end
end

RegisterNetEvent("ncm:ls:ev:quit", function() leave(source, "quit") end)
AddEventHandler("playerDropped", function() leave(source, "dropped") end)

-- clock sync: the client sends its own time, the server answers with its own
RegisterNetEvent("ncm:ls:ev:ping", function(clientSend)
    TriggerClientEvent("ncm:ls:ev:pong", source, clientSend, serverS())
end)
RegisterNetEvent("ncm:ls:ev:clock", function(offset, rtt)
    local src = source
    local vi = byPlayer[src]
    if vi and open[vi] then open[vi].offsets[src] = { offset = offset, rtt = rtt } end
    log("clock: player %d offset %+.4f s (rtt %.1f ms)", src, tonumber(offset) or 0, (tonumber(rtt) or 0) * 1000)
end)

-- client samples: SERVER time (s, after clock sync), universe position, velocity, and body axes for presentation
RegisterNetEvent("ncm:ls:ev:sample", function(ts, u, w, y, z)
    local src = source
    local vi = byPlayer[src]
    local L = vi and open[vi]
    if not L or type(u) ~= "table" or type(w) ~= "table" then return end
    ts = tonumber(ts)
    local clk = L.offsets[src]
    if ts and clk and math.abs(ts - serverS()) > 0.5 + (clk.rtt or 0) then
        L.rejected = (L.rejected or 0) + 1
        if L.rejected % 50 == 1 then log("sample from player %d rejected: stamped %.3f s from server time", src, ts - serverS()) end
        return
    end
    L.lastU[src] = { u = u, w = w, y = y, z = z }
    if L.phase == "racing" and ts then
        Tac.observe(L.race, pid(src), ts - L.t0S, u, w)
    end
end)

-- contact the client saw between its car and an NPC car: checked against the race, then physics
RegisterNetEvent("ncm:ls:ev:contact", function(npcId, vExt)
    local src = source
    local vi = byPlayer[src]
    local L = vi and open[vi]
    if not L or L.phase ~= "racing" or type(vExt) ~= "table" then return end
    local N = L.race.entrants[npcId]
    local me = L.lastU[src]
    if not N or not me then return end
    local gap = U.vec.len(U.vec.sub(N.s.dyn.pos, me.u))
    if gap > C.contactCheckM then
        log("contact claim from player %d against %s refused: the race has them %.0f m apart", src, label(npcId), gap)
        return
    end
    local r = Tac.contactExternal(L.race, npcId, pid(src), vExt, Mach.assemble(L.machines[src]).wetMassKg)
    if r then
        log("CONTACT player %d -> %s at %.1f m/s: NPC knocked %.2f m/s%s", src, label(npcId), r.vRelMs, r.dvNpc, r.npcOut and " -- OUT" or "")
    end
end)

local function finish(vi, L)
    local rows = Tac.result(L.race)
    local out = {}
    for _, r in ipairs(rows) do
        local isPlayer = r.id:sub(1, 7) == "player:"
        local s = isPlayer and tonumber(r.id:sub(8)) or nil
        out[#out + 1] = { position = r.position, id = r.id, name = isPlayer and (GetPlayerName(s) or r.id) or label(r.id, r.orgId),
            state = r.state, finishMs = r.raceS and math.floor(r.raceS * 1000 + 0.5), raceS = r.raceS, creditM = r.creditM,
            dnfReason = r.reason or (r.dq and "dq") or ((L.gone and L.gone[r.id]) and "left") or nil, mode = r.mode,
            reactS = r.reactS, deadHeat = r.deadHeat, contacts = r.contacts }
        log("  %s P%d %-34s %s %s%s%s", L.ev.venueInfo.name, r.position, out[#out].name,
            r.raceS and ("%.4f s"):format(r.raceS) or tostring(out[#out].dnfReason or r.state), r.mode,
            r.deadHeat and " DEAD HEAT" or "", r.contacts and (" contacts " .. r.contacts) or "")
        if isPlayer and NcmLsLink and NcmLsLink.result then NcmLsLink.result(s, L.ev, out[#out]) end
    end
    for _, e in ipairs(L.race.log) do log("  incident: %s at %.1f s (%s)%s", e.kind, e.t, table.concat(e.ids, " / "), e.external and " [player]" or "") end
    commit(Cal.outcome(world, L.ev, rows, "tactical", os.time()))
    for _, src in ipairs(L.roster) do
        TriggerClientEvent("ncm:ls:race:result", src, out)
        byPlayer[src] = nil
    end
    open[vi] = nil
end

CreateThread(function()
    while true do
        Wait(0)
        local now = serverS()
        for vi, L in pairs(open) do
            if L.phase == "grid" then
                local allReady, anyReady = #L.roster > 0, false
                for _, src in ipairs(L.roster) do
                    local me = L.lastU[src]
                    local ok = false
                    if me then
                        if L.ev.discipline == "sprint" then
                            local i
                            for k, e in ipairs(L.ev.entrants) do if e.id == pid(src) then i = k end end
                            local spot = Course.toWorld(L.ev.venue.frame, Core.get("space.sprint").laneSpot(L.ev.rules, i))
                            ok = U.vec.len(U.vec.sub(me.u, spot)) < C.gridToleranceM
                        else
                            ok = U.vec.len(U.vec.sub(me.u, L.ev.venue.gridCentre)) < C.fireballGridM
                        end
                    end
                    L.ready[src] = ok or nil
                    allReady = allReady and ok
                    anyReady = anyReady or ok
                end
                if anyReady and not L.firstReadyS then L.firstReadyS = now end
                if allReady or (L.firstReadyS and now - L.firstReadyS > C.lightsStragglerS) then
                    L.phase, L.t0S = "racing", now
                    for _, src in ipairs(L.roster) do TriggerClientEvent("ncm:ls:ev:lights", src, C.lightsS, L.t0S) end
                    log("%s: lights (%d player(s)%s)", L.ev.venueInfo.name, #L.roster, allReady and "" or ", stragglers start where they are")
                end
            elseif L.phase == "racing" then
                local target = now - L.t0S
                local n = 0
                while L.race.t < target and n < 40 do Tac.step(L.race); n = n + 1 end
                if (now - L.lastSend) >= 0.1 then
                    L.lastSend = now
                    local npcs = compact(L.race)
                    local remotes = {}
                    for _, src in ipairs(L.roster) do
                        local me = L.lastU[src]
                        if me then remotes[#remotes + 1] = { id = pid(src), serverId = src, p = me.u, v = me.w, y = me.y, z = me.z } end
                    end
                    for _, src in ipairs(L.roster) do
                        local P = L.race.entrants[pid(src)]
                        local j = P and P.s.judge or {}
                        local mine = { c = j.creditM, r = j.radius, coh = j.coherence, oob = j.oobS, y = j.last and j.last.y, st = P and P.s.status }
                        TriggerClientEvent("ncm:ls:ev:state", src, L.race.t, npcs, mine, remotes)
                    end
                end
                if Tac.over(L.race) then finish(vi, L) end
            end
        end
    end
end)
