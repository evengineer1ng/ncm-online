-- ncm_observer / server / main -- the observer MODE, the targets and the director (doc 46, L307).
--
-- ENTERING is a two-step handshake, so nothing turns a connection into an observer by accident (L307 O-4):
--   1. an explicit request: `ncm.observer on <pid>` on the server console, or `/ncm.observe on` from a client whose
--      user id is on `observerAllow` -- either one only ARMS the connection for 20 s;
--   2. that client confirms it is on foot (`ncm:observer:enter`); only then is the mode set.
-- The mode lives on the CONNECTION: a disconnect ends it, and a reconnect is an ordinary player again.
--
-- IN MODE: invisible (`players.setVisible`), non-solid with no auto-clear (`players.setGhosted`), and listed in
-- `GlobalState.ncmObservers`, which ncm_league (`resolveDriver`), ncm_paddock (`PaddockPlayers.driver`) and ncm_world
-- (`NcmIdentity.get`) read: they resolve no driver for it, so every handler built on them treats it as unbound. The
-- Paddock bubble reads `players.positions` and does not ask -- deliberately: the ghost's presence is what makes a
-- distant race physical (doc 46 §1.2).
--
-- TARGETS come from ncm_paddock's racer snapshot (`ncm:paddock:racers:server`, every 2 s), resolved by the pure
-- `observer.director`. The client follows the target itself; the server only names it and makes the long jumps
-- (`players.teleport` settles streaming; a client teleport does not).
NcmObserver = { observers = {} }

local D = NcmCore.get("observer.director")
local function set(k, d) return ObserverSettings.get(k, d) end
local function log(fmt, ...) print(("[ncm_observer] " .. fmt):format(...)) end
local function now() return (Open77.time and Open77.time.unix and Open77.time.unix()) or math.floor(GetGameTimer() / 1000) end

local observers = NcmObserver.observers  -- pid -> { user, since, entered, spec, auto, target, shotSince, lastJump }
local armed = {}                          -- pid -> expiry (s)
local lastSnap, lastSnapAt = nil, 0

local function publish()
    local out = {}
    for pid, o in pairs(observers) do out[tostring(pid)] = { since = o.since } end
    GlobalState.ncmObservers = out
end

local function tell(pid, text)
    TriggerClientEvent("ncm:observer:say", pid, text)
end

local function allowed(pid)
    local list = tostring(set("observerAllow", "") or "")
    if list == "" then return false end
    if list == "*" then return true end
    local user = tostring(GetPlayerIdentifier(pid) or "")
    for item in list:gmatch("[^,%s]+") do if item == user then return true end end
    return false
end

-- ---------------------------------------------------------------------------------------------------------------
-- The mode
-- ---------------------------------------------------------------------------------------------------------------

function NcmObserver.arm(pid, by)
    pid = tonumber(pid) or 0
    if pid <= 0 or not GetPlayerName(pid) then log("arm refused: no player %s", tostring(pid)); return false end
    if not set("observerEnabled", true) then log("arm refused: observerEnabled is off"); return false end
    if observers[pid] then tell(pid, "Already observing."); return false end
    armed[pid] = now() + 20
    TriggerClientEvent("ncm:observer:armed", pid)
    log("ARMED player=%d (%s) by %s; waiting for the client's on-foot confirmation", pid, tostring(GetPlayerName(pid)), by)
    return true
end

function NcmObserver.enter(pid)
    if not (armed[pid] and armed[pid] >= now()) then log("enter refused: player=%d was not armed", pid); return end
    armed[pid] = nil
    local pos = Open77.players.position(pid)
    local okV, whyV = Open77.players.setVisible(pid, false)
    local okG, whyG = Open77.players.setGhosted(pid, true, { autoClear = false })
    observers[pid] = { user = tostring(GetPlayerIdentifier(pid) or ""), since = now(), entered = pos, auto = false }
    publish()
    TriggerClientEvent("ncm:observer:mode", pid, { on = true })
    log("ENTER player=%d (%s) user=%s at %s | invisible=%s%s ghosted=%s%s", pid, tostring(GetPlayerName(pid)),
        observers[pid].user, pos and ("%.0f,%.0f,%.0f"):format(pos.x, pos.y, pos.z) or "?",
        tostring(okV), okV and "" or (" " .. tostring(whyV)), tostring(okG), okG and "" or (" " .. tostring(whyG)))
end

function NcmObserver.exit(pid, why)
    local o = observers[pid]
    if not o then return end
    observers[pid] = nil
    publish()
    if why ~= "disconnected" then
        pcall(Open77.players.setGhosted, pid, false)
        pcall(Open77.players.setVisible, pid, true)
        TriggerClientEvent("ncm:observer:mode", pid, { on = false })
        if o.entered then
            local ok, p, r = pcall(Open77.players.teleport, pid, o.entered, { fade = true })
            if not (ok and p) then log("exit: teleport home refused: %s", tostring(ok and r or p)) end
        end
    end
    log("EXIT player=%d after %d s (%s)", pid, math.floor(now() - (o.since or now())), tostring(why))
end

function NcmObserver.is(pid) return observers[tonumber(pid) or 0] ~= nil end

-- ---------------------------------------------------------------------------------------------------------------
-- Targets and the director
-- ---------------------------------------------------------------------------------------------------------------

local function jump(pid, o, car, why)
    if not car then return end
    local t = now()
    if o.lastJump and t - o.lastJump < 3 then return end
    local here = Open77.players.position(pid)
    if here then
        local dx, dy = here.x - car.x, here.y - car.y
        if math.sqrt(dx * dx + dy * dy) < set("jumpM", 200) then return end
    end
    o.lastJump = t
    local dest = { x = car.x, y = car.y, z = (car.z or 0) + 12 }
    local ok, p, r = pcall(Open77.players.teleport, pid, dest, { fade = false })
    log("jump player=%d -> %.0f,%.0f,%.0f (%s): %s", pid, dest.x, dest.y, dest.z, why, (ok and p) and "sent" or tostring(ok and r or p))
end

local function setTarget(pid, o, t, why)
    o.target, o.shotSince = t, now()
    t.auto = o.auto and true or nil              -- the panel's DIRECTOR button reads it
    TriggerClientEvent("ncm:observer:target", pid, t)
    local car = D.findCar(lastSnap, t.raceId, t.key)
    log("target player=%d -> %s (%s) in %s [%s]%s", pid, tostring(t.name), t.key, t.raceId, tostring(why or t.why),
        car and (" P%s %s"):format(tostring(car.p), car.v and ("physical v=" .. tostring(car.v)) or "model") or "")
    jump(pid, o, car, "new target")
end

function NcmObserver.watch(pid, text)
    local o = observers[pid]
    if not o then return false, "not observing" end
    local spec, why = D.parse(text)
    if not spec then return false, why end
    o.auto = spec.kind == "auto"
    if not lastSnap then return false, "no racer snapshot yet (is ncm_paddock running?)" end
    local t, why2 = D.resolve(lastSnap, spec, o.target)
    if not t then return false, why2 end
    setTarget(pid, o, t, (o.auto and "auto: " or "") .. t.why)
    return true, t
end

AddEventHandler("ncm:paddock:racers:server", function(snap)
    if type(snap) ~= "table" then return end
    lastSnap, lastSnapAt = snap, now()
end)

local function directorPass()
    if not lastSnap then return end
    local opts = { minShotSec = set("minShotSec", 12), maxShotSec = set("maxShotSec", 45), battleGapMs = set("battleGapMs", 1500), nearM = set("jumpM", 200) }
    for pid, o in pairs(observers) do
        if o.auto then
            local t, why = D.step({ target = o.target, since = o.shotSince }, lastSnap, now(), opts)
            if t then setTarget(pid, o, t, "auto: " .. tostring(why))
            elseif o.target and not D.findCar(lastSnap, o.target.raceId, o.target.key) then
                -- the race ended and nothing else is running: say so instead of freezing on an empty road; the
                -- director stays on and takes the next race the moment one starts
                o.target = nil
                TriggerClientEvent("ncm:observer:target", pid, false)
                tell(pid, "That race is over and nothing else is running. The director will pick up the next race.")
                log("director player=%d: nothing running (%s); waiting", pid, tostring(why))
            end
        elseif o.target and not D.findCar(lastSnap, o.target.raceId, o.target.key) then
            -- a hand-picked car finished or retired: hold the race's leader rather than an empty road
            local t = D.resolve(lastSnap, { kind = "leader" }, o.target)
            if t and t.raceId == o.target.raceId then
                tell(pid, ("%s is done; watching the leader."):format(tostring(o.target.name)))
                setTarget(pid, o, t, "target done")
            else
                tell(pid, "That race is over. F3: pick another race, or press N for the director or Y for your team.")
                o.target = nil
                TriggerClientEvent("ncm:observer:target", pid, false)
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Your team (owner 2026-10-09: "helpful instructions for using it to spot your team")
-- ---------------------------------------------------------------------------------------------------------------
-- The Paddock team this player manages and its contracted drivers, read from the database by the player's user id.
-- It never goes through the resolvers (which, by design, resolve no driver for an observer), so it works in mode.
-- The client marks those drivers wherever they appear in the racer snapshot (car key = person id).

local teamAsked = {}

local function serverId()
    local ok, id = pcall(function() return GlobalState.ncmIdentity and GlobalState.ncmIdentity.serverId end)
    return (ok and id) or "ncm-dev"
end

function NcmObserver.teamOf(pid)
    if not (MySQL and MySQL.isReady and MySQL.isReady()) then return nil, "database" end
    local okU, userId = pcall(GetPlayerIdentifier, pid)
    if not okU or type(userId) ~= "string" or userId == "" then return nil, "no_user" end
    local sid = serverId()
    local b = MySQL.single.await("SELECT ncm_driver_id FROM ncm_driver_binding WHERE server_id = ? AND user_id = ?", { sid, userId })
    if not (b and b.ncm_driver_id) then return { none = true } end
    local a = MySQL.single.await([[SELECT a.paddock_org_id, a.role, o.name, o.tier FROM team_affiliation a
        JOIN paddock_org o ON o.server_id = a.server_id AND o.org_id = a.paddock_org_id
        WHERE a.server_id = ? AND a.ncm_driver_id = ? AND a.effective_to IS NULL AND a.paddock_org_id IS NOT NULL]], { sid, tostring(b.ncm_driver_id) })
    if not a then return { none = true } end
    local drivers = {}
    for _, r in ipairs(MySQL.query.await([[SELECT person_id, display, seat FROM paddock_person WHERE server_id = ? AND org_id = ?
        AND role = 'driver' AND state = 'active' ORDER BY seat, person_id]], { sid, a.paddock_org_id }) or {}) do
        drivers[#drivers + 1] = { k = tostring(r.person_id), name = tostring(r.display or r.person_id), seat = r.seat }
    end
    return { orgId = a.paddock_org_id, name = a.name, tier = a.tier, role = a.role, drivers = drivers }
end

RegisterNetEvent("ncm:observer:team.ask", function()
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    local t = now()
    if teamAsked[pid] and t - teamAsked[pid] < 5 then return end
    teamAsked[pid] = t
    CreateThread(function()
        local ok, team, why = pcall(NcmObserver.teamOf, pid)
        if not ok then log("team lookup FAILED for player=%d: %s", pid, tostring(team)); return end
        if not team then return end
        TriggerClientEvent("ncm:observer:team", pid, team)
        log("team player=%d -> %s", pid, team.none and "none" or (("%s (%d driver(s))"):format(tostring(team.name), #team.drivers)))
    end)
end)

-- ---------------------------------------------------------------------------------------------------------------
-- Events and commands
-- ---------------------------------------------------------------------------------------------------------------

RegisterNetEvent("ncm:observer:ask", function()
    local pid = tonumber(source) or 0
    if observers[pid] then tell(pid, "Already observing."); return end
    if not allowed(pid) then
        log("ask refused: player=%d user=%s is not on observerAllow", pid, tostring(GetPlayerIdentifier(pid)))
        tell(pid, "Observer is not enabled for this account.")
        return
    end
    NcmObserver.arm(pid, "client request")
end)

RegisterNetEvent("ncm:observer:enter", function()
    local pid = tonumber(source) or 0
    NcmObserver.enter(pid)
end)

RegisterNetEvent("ncm:observer:exit", function()
    NcmObserver.exit(tonumber(source) or 0, "client asked")
end)

RegisterNetEvent("ncm:observer:watch", function(text)
    local pid = tonumber(source) or 0
    local ok, res = NcmObserver.watch(pid, tostring(text or ""))
    if ok then tell(pid, ("Watching %s (%s)"):format(tostring(res.name), tostring(res.why)))
    else tell(pid, "Observe: " .. tostring(res)) end
end)

-- the client lost its target (a model car the ghost is far from): make the settling jump for it
RegisterNetEvent("ncm:observer:jump", function()
    local pid = tonumber(source) or 0
    local o = observers[pid]
    if not (o and o.target and lastSnap) then return end
    jump(pid, o, (D.findCar(lastSnap, o.target.raceId, o.target.key)), "client far from target")
end)

-- the client's own account of how the lens is doing, logged (instrument every hop)
RegisterNetEvent("ncm:observer:status", function(st)
    local pid = tonumber(source) or 0
    if not observers[pid] or type(st) ~= "table" then return end
    log("status player=%d mode=%s target=%s src=%s cam=%s hops=%s jumps=%s refusals=%s%s", pid, tostring(st.mode),
        tostring(st.target), tostring(st.src), tostring(st.cam), tostring(st.hops), tostring(st.jumps), tostring(st.refusals),
        st.gear and (" gear=%s rpm=%s thr=%s kph=%s"):format(tostring(st.gear), tostring(st.rpm), tostring(st.thr), tostring(st.kph)) or "")
end)

AddEventHandler("onPlayerDisconnected", function(playerId)
    local pid = tonumber(playerId) or 0
    armed[pid] = nil
    teamAsked[pid] = nil
    NcmObserver.exit(pid, "disconnected")
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= "ncm_observer" then return end
    for pid in pairs(observers) do
        pcall(Open77.players.setGhosted, pid, false)
        pcall(Open77.players.setVisible, pid, true)
    end
    GlobalState.ncmObservers = {}
end)

-- Server console: ncm.observer on|off <pid> | list ;  ncm.observe <pid> <race ..|racer ..|pos n|leader|battle|auto>
RegisterCommand("ncm.observer", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local verb, pid = tostring(args and args[1] or "list"), tonumber(args and args[2])
    if verb == "on" and pid then NcmObserver.arm(pid, "console")
    elseif verb == "off" and pid then NcmObserver.exit(pid, "console")
    else
        local n = 0
        for p, o in pairs(observers) do
            n = n + 1
            log("observer player=%d (%s) for %d s, %s, target %s", p, tostring(GetPlayerName(p)), math.floor(now() - o.since),
                o.auto and "auto" or "manual", o.target and (tostring(o.target.name) .. " in " .. tostring(o.target.raceId)) or "none")
        end
        log("%d observer(s); racer snapshot %s", n, lastSnap and ("%d s old, %d race(s)"):format(math.floor(now() - lastSnapAt), #(lastSnap.races or {})) or "never received")
        if verb ~= "list" then log("usage: ncm.observer on|off <pid> | list") end
    end
end, false)

RegisterCommand("ncm.observe", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid = tonumber(args and args[1])
    local text = table.concat(args or {}, " ", 2)
    if not pid or text == "" then log("usage: ncm.observe <pid> <race <name>|racer <name>|pos <n>|leader|battle|auto>"); return end
    local ok, res = NcmObserver.watch(pid, text)
    if not ok then log("ncm.observe: %s", tostring(res)) end
end, false)

CreateThread(function()
    GlobalState.ncmObservers = {}
    log("ready (enabled=%s, allow=%q)", tostring(set("observerEnabled", true)), tostring(set("observerAllow", "")))
    while true do
        Wait(math.max(1, set("directorTickSec", 2)) * 1000)
        local ok, err = pcall(directorPass)
        if not ok then log("director FAILED: %s", tostring(err)) end
    end
end)
