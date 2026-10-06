-- ncm_space / server: the Badlands Sky Sprint (L323; doc 54 §S). See open77.lua.
local function log(fmt, ...) print(("[ncm_space] " .. fmt):format(...)) end

local Core = NcmCore
local U = Core.get("space.universe")
local Seed = Core.get("world.seed")
local Gen = Core.get("space.genesis")
local Cal = Core.get("space.calendar")
local Tac = Core.get("space.tactical")
local SP = Core.get("space.sprint")
local Course = Core.get("space.course")
local Fx = Core.get("engineering.fixtures")

local SEED = (GetConvar and GetConvar("ncm_universe_seed", "ncm-los-santos-dev-1")) or "ncm-los-santos-dev-1"
local ANCHOR = "night_city"
local LIGHTS_S = 5
local GRID_TOL_M = 10
local STRAGGLER_S = 30
local STEPS_PER_TICK = 5                     -- KB-336: never a long loop in one slice
local GOTO_M = 600                           -- farther than this, /ncm.sky routes you to the grid first

U.setWorld({ earthRadius = 5000, surfaceG = 9.81 })
local world = Cal.index(Gen.generate(Seed.root(SEED):child("snowglobe")))
local VI
for i, v in ipairs(world.venues) do if v.domain == "night_city" and v.kind == "sprint" then VI = i end end
local venue = world.venues[VI]
local grounded, surveyed = false, false

--- Snap the start plane to the desert floor. The server can only ray-cast collision someone is streaming, so on an
--- empty server this fails and is retried when a player opens the sprint (they are usually on their way there).
local function survey(fromZ)
    local s = venue.spot
    local ok, z = pcall(Open77.world.groundZ, { x = s[1], y = s[2] }, { radius = 400, fromZ = fromZ or (s[3] + 200), timeout = 3000, cache = false })
    if ok and type(z) == "number" then
        venue.spot = { s[1], s[2], z }
        surveyed = true
        log("%s grid surveyed: ground at %.1f m", venue.name, z)
    end
    return surveyed
end

local function tell(src, title, msg, ms)
    pcall(Open77.notifications.send, src, { type = "info", title = title, message = msg, icon = "NCM", durationMs = ms or 3000 })
end

local function positions()
    local ok, p = pcall(Open77.players.positions)
    return ok and type(p) == "table" and p or {}
end

local function pid(src) return "player:" .. tostring(src) end
local function laneLocal(ev, i)
    local u = Course.toWorld(ev.venue.frame, SP.laneSpot(ev.rules, i))
    local l = U.universeToCity(u, ANCHOR)
    return { x = l[1], y = l[2], z = l[3] }, u
end

local L = nil                                -- the event on the grid or racing

local function rebuild()
    local ext = {}
    for _, src in ipairs(L.roster) do
        ext[#ext + 1] = { id = pid(src), person = { id = pid(src), attrs = {}, personality = {} }, design = Fx.MACHINES.instrument_car, external = true }
    end
    L.ev = Cal.event(world, VI, L.slot, { t0 = Open77.time.unix(), startT = LIGHTS_S, external = ext })
    L.race = Tac.new(L.ev)
end

local function compact()
    local out = {}
    for _, id in ipairs(L.race.order) do
        local E = L.race.entrants[id]
        if not E.external then
            local d = E.s.dyn
            local l = U.universeToCity(d.pos, ANCHOR)
            local f = U.earthToLocal(U.anchorFrame(ANCHOR), { d.rot[1][2], d.rot[2][2], d.rot[3][2] })
            out[#out + 1] = { id = id, x = l[1], y = l[2], z = l[3], yaw = math.deg(math.atan(-f[1], f[2])), st = E.s.status }
        end
    end
    return out
end

local function field(src)
    local list, mine = {}, nil
    for i, e in ipairs(L.ev.entrants) do
        local spot = laneLocal(L.ev, i)
        if e.id == pid(src) then mine = spot end
        list[#list + 1] = { id = e.id, name = e.external and (GetPlayerName(tonumber(e.id:sub(8))) or e.id) or (e.person.display or e.id),
            npc = not e.external or nil, lane = i, spot = spot, model = e.design.id }
    end
    local top = laneLocal(L.ev, 1)
    return { name = venue.name, distanceM = venue.distanceM, mySpot = mine, field = list, npcs = compact(), finishZ = top.z + venue.distanceM }
end

local openFor
RegisterCommand("ncm.sky", function(source)
    local src = tonumber(source) or 0
    if src <= 0 then return end
    CreateThread(function() openFor(src) end)       -- the survey waits on a ray-cast: never inside the command itself
end, false)

openFor = function(src)
    if not grounded then pcall(Open77.chat.send, src, "[NCM] The sprint grid is still being surveyed -- try again in a moment."); return end
    if L and L.phase ~= "grid" then pcall(Open77.chat.send, src, "[NCM] " .. venue.name .. " is under way -- wait for the next one."); return end
    -- far away: route the driver there instead of opening a grid they cannot see (the survey also needs them near)
    local me, s = positions()[src], venue.spot
    if me and me.x and ((me.x - s[1]) ^ 2 + (me.y - s[2]) ^ 2) ^ 0.5 > GOTO_M then
        local km = ((me.x - s[1]) ^ 2 + (me.y - s[2]) ^ 2) ^ 0.5 / 1000
        TriggerClientEvent("ncm:sky:goto", src, { x = s[1], y = s[2], z = s[3], name = venue.name })
        tell(src, venue.name, ("GPS set: the grid is %.1f km away in the Badlands. Drive to the pin, then type /ncm.sky again."):format(km), 10000)
        log("player %d is %.1f km from %s: GPS pin sent", src, km, venue.name)
        return
    end
    if not surveyed and not L then survey() end
    if not L then L = { roster = {}, slot = math.floor(Open77.time.unix() / 60) * 100 + src, phase = "grid", last = {}, lastSend = 0 } end
    for _, s in ipairs(L.roster) do if s == src then return end end
    L.roster[#L.roster + 1] = src
    rebuild()
    for _, s in ipairs(L.roster) do TriggerClientEvent("ncm:sky:field", s, field(s)) end
    tell(src, venue.name, ("Your lane is the yellow ring: stop on it for the lights. The finish is %d m straight up -- hold TRIANGLE."):format(venue.distanceM), 12000)
    log("player %d %s %s: %d player(s), %d NPC(s)", src, #L.roster == 1 and "opens" or "joins", venue.name, #L.roster, #L.ev.entrants - #L.roster)
end

RegisterCommand("ncm.sky.quit", function(source)
    local src = tonumber(source) or 0
    if not L then return end
    for i, s in ipairs(L.roster) do if s == src then table.remove(L.roster, i) end end
    if #L.roster == 0 and L.phase == "grid" then L = nil end
end, false)

local function finish()
    local rows = Tac.result(L.race)
    local out = {}
    for _, r in ipairs(rows) do
        local isPlayer = r.id:sub(1, 7) == "player:"
        local name = isPlayer and (GetPlayerName(tonumber(r.id:sub(8))) or r.id) or ((L.race.entrants[r.id].person or {}).display or r.id)
        out[#out + 1] = { position = r.position, name = name, state = r.state, raceS = r.raceS, mode = r.mode, reason = r.reason,
            machine = isPlayer and "instrument" or nil }
        log("  %s P%d %-30s %s %s%s", venue.name, r.position, name, r.raceS and ("%.3f s"):format(r.raceS) or tostring(r.reason or r.state),
            r.mode, isPlayer and " (Thrust instrument)" or "")
        if isPlayer then TriggerEvent("ncm:space.result", tonumber(r.id:sub(8)), venue.name, r.position, r.raceS, r.state) end
    end
    local lines = {}
    for _, r in ipairs(out) do
        lines[#lines + 1] = ("P%d %s %s %s"):format(r.position, r.name, r.raceS and ("%.3f s"):format(r.raceS) or tostring(r.reason or r.state), r.mode)
    end
    for _, s in ipairs(L.roster) do
        TriggerClientEvent("ncm:sky:result", s, out)
        tell(s, venue.name:upper(), table.concat(lines, " | "), 20000)
        for _, l in ipairs(lines) do pcall(Open77.chat.send, s, "[NCM] " .. l) end
    end
    L = nil
end

CreateThread(function()
    -- survey: snap the start plane to the desert floor once
    Wait(3000)
    survey()
    grounded = true
    log("%s ready: grid at %.0f, %.0f, %.0f (%s); /ncm.sky to race", venue.name, venue.spot[1], venue.spot[2], venue.spot[3],
        surveyed and "ground surveyed" or "not surveyed yet -- retried when a player opens it")
    while true do
        Wait(0)
        if L then
            local now = GetGameTimer() / 1000
            -- server-observed positions, 10 Hz: the authority sees where the players are
            if now - (L.lastObs or 0) >= 0.1 then
                local pos = positions()
                for _, src in ipairs(L.roster) do
                    local p = pos[src]
                    if p then
                        local u = U.cityToUniverse({ p.x, p.y, p.z }, ANCHOR)
                        local prev = L.last[src]
                        local w = prev and { (u[1] - prev.u[1]) / (now - prev.t), (u[2] - prev.u[2]) / (now - prev.t), (u[3] - prev.u[3]) / (now - prev.t) } or { 0, 0, 0 }
                        L.last[src] = { u = u, w = w, t = now }
                        if L.phase == "racing" then Tac.observe(L.race, pid(src), now - L.t0, u, w) end
                    end
                end
                L.lastObs = now
            end
            if L.phase == "grid" then
                local all, any = #L.roster > 0, false
                for i, src in ipairs(L.roster) do
                    local me = L.last[src]
                    local _, spot = laneLocal(L.ev, i)
                    local ok = me and U.vec.len(U.vec.sub(me.u, spot)) < GRID_TOL_M
                    all, any = all and ok, any or ok
                end
                if any and not L.firstReady then L.firstReady = now end
                if all or (L.firstReady and now - L.firstReady > STRAGGLER_S) then
                    L.phase, L.t0 = "racing", now
                    for _, s in ipairs(L.roster) do TriggerClientEvent("ncm:sky:lights", s, LIGHTS_S) end
                    local roster = { table.unpack(L.roster) }
                    CreateThread(function()
                        for k = 1, 5 do
                            for _, s in ipairs(roster) do tell(s, "LIGHTS", string.rep("O ", k), 900) end
                            Wait(math.floor(LIGHTS_S * 1000 / 5))
                        end
                        for _, s in ipairs(roster) do tell(s, "GO", "GO -- straight up", 2000) end
                    end)
                    log("%s: lights (%d player(s))", venue.name, #L.roster)
                end
            else
                local n = 0
                while L.race.t < now - L.t0 and n < STEPS_PER_TICK do Tac.step(L.race); n = n + 1 end
                if now - L.lastSend >= 0.1 then
                    L.lastSend = now
                    local npcs = compact()
                    for _, s in ipairs(L.roster) do TriggerClientEvent("ncm:sky:state", s, npcs) end
                end
                if Tac.over(L.race) then finish() end
            end
        end
    end
end)
