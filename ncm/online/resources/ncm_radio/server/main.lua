-- ncm_radio / server / main -- Race Week Live's transmitter (doc 59 §6, L348).
--
-- Reads NCM's world (facts.lua), lets the director choose each listener's next authored beat, and keeps one
-- programme clock per connected listener. A client that tunes in mid-beat is told how far into the beat the
-- broadcast already is (bible §148: the player joins an already-running broadcast; the station never waits for them,
-- never scolds them for leaving, never recaps because they returned).
--
-- The station is personal (bible §1): one programme per listener, the Week's facts shared, the player's own results
-- theirs. Listening is voluntary: the programme runs whether or not the station is selected; only the client decides
-- whether it is audible.
local ok, settings = pcall(Open77.tunables.declare, {
    -- Must equal ncm_league's and ncm_paddock's `serverId`: every row read is keyed on it (L112).
    serverId = { value = "ncm-dev", type = "string", apply = "live" },
    radioEnabled = { value = true, type = "boolean", apply = "live" },
    pollSeconds = { value = 10, type = "integer", min = 3, max = 120, unit = "s", apply = "live" },
})
local function set(k, d)
    if not ok or type(settings) ~= "table" then return d end
    local v = settings[k]
    if type(v) == "table" then v = v.value end
    if v == nil then return d end
    return v
end

local director
local players = {}          -- pid -> { startedMs, item, hello }
local function log(fmt, ...)
    local okF, line = pcall(string.format, fmt, ...)
    print("[ncm_radio] " .. (okF and line or tostring(fmt)))
end
local function now() return math.floor(Open77.time.unix()) end
local function ms() return GetGameTimer() end

local clockOf = RadioClock.clockOf

-- player id -> NCM Driver (the binding ncm_world writes; restated, resources do not share memory)
local function driverOf(pid)
    local okId, userId = pcall(GetPlayerIdentifier, pid)
    if not okId or type(userId) ~= "string" or userId == "" then return nil end
    local row = MySQL.single.await(
        "SELECT b.ncm_driver_id, p.display FROM ncm_driver_binding b " ..
        "LEFT JOIN driver_profile p ON p.ncm_driver_id = b.ncm_driver_id AND p.server_id = b.server_id " ..
        "WHERE b.server_id = ? AND b.user_id = ?", { set("serverId", "ncm-dev"), userId })
    if not row or not row.ncm_driver_id then return nil end
    return { driverId = row.ncm_driver_id, name = row.display or GetPlayerName(pid) }
end

-- the listener's Race Week career so far, so "first podium" means first (bible §8 player history)
local function statsOf(driverId)
    local s = { starts = 0, podiums = 0, wins = 0, dnfs = 0 }
    local rows = MySQL.query.await([[SELECT r.position, r.state FROM paddock_result r JOIN paddock_entry e
        ON e.server_id = r.server_id AND e.race_id = r.race_id AND e.person_key = r.person_id
        WHERE r.server_id = ? AND e.ncm_driver_id = ?]], { set("serverId", "ncm-dev"), driverId }) or {}
    for _, r in ipairs(rows) do
        s.starts = s.starts + 1
        if r.state ~= "finished" then s.dnfs = s.dnfs + 1
        else
            local p = tonumber(r.position) or 99
            if p == 1 then s.wins = s.wins + 1 end
            if p <= 3 then s.podiums = s.podiums + 1 end
        end
    end
    return s
end

-- Show history per driver, kept across server restarts in this resource's data directory (bible §247).
local function historyPath(driverId) return "history/" .. tostring(driverId):gsub("[^%w%-]", "") .. ".json" end
local function loadHistory(pid, driverId)
    if not driverId then return end
    local okR, text = pcall(Open77.io.read, historyPath(driverId))
    if not okR or type(text) ~= "string" or text == "" then return end
    local okD, h = pcall(json.decode, text)
    if okD and director:restore(pid, h) then log("pid %d: restored show history for %s", pid, tostring(driverId)) end
end
local function saveHistory(pid)
    local p = players[pid]
    if not (p and p.driverId and director) then return end
    local h = director:history(pid)
    if not h then return end
    pcall(Open77.io.makeDirectory, "history")
    local okE, text = pcall(json.encode, h)
    if okE then
        local okW, written, why = pcall(Open77.io.write, historyPath(p.driverId), text)
        if not okW or written == false then log("history not saved for pid %d: %s", pid, tostring(okW and why or written)) end
    end
end

local function send(pid, item, offsetMs)
    TriggerClientEvent("ncm:radio.item", pid, { seq = item.seq, beat = item.beat, clips = item.clips,
        offsetMs = math.max(0, math.floor(offsetMs or 0)), pack = NcmRadioCorpus.pack })
end

local function advance(pid, p)
    local h, m = clockOf(now())
    local item = director:next(pid, now(), { hour = h, minute = m })
    p.item, p.startedMs = item, ms()
    if item.beat ~= "" then
        log("pid %d: %s (%s, %.0f s, then %.0f s quiet)", pid, item.beat, item.trigger or "?", item.totalMs / 1000, item.silenceMs / 1000)
        send(pid, item, 0)
    end
end

RegisterNetEvent("ncm:radio.hello", function(info)
    local pid = tonumber(source)
    if not pid or not director then return end
    info = type(info) == "table" and info or {}
    if info.pack and info.pack ~= NcmRadioCorpus.pack then
        log("pid %d has voice pack %s, the server airs %s: clips may be missing", pid, tostring(info.pack), tostring(NcmRadioCorpus.pack))
    end
    local who = driverOf(pid)
    local L = director:listener(pid, { driverId = who and who.driverId, name = who and who.name,
        stats = who and statsOf(who.driverId) or nil })
    local p = players[pid] or {}
    local fresh = not p.hello
    players[pid] = p
    p.hello = true
    p.driverId = who and who.driverId
    if fresh then loadHistory(pid, p.driverId) end
    log("pid %d (%s) has the station: plugin %s, pack %s", pid, tostring(L.name), tostring(info.version), tostring(info.pack))
    -- join the broadcast where it is, never from the top
    if p.item and p.item.beat ~= "" and ms() - p.startedMs < p.item.totalMs then
        send(pid, p.item, ms() - p.startedMs)
    end
end)

RegisterNetEvent("ncm:radio.listening", function(info)
    local pid = tonumber(source)
    if pid and type(info) == "table" then
        log("pid %d %s", pid, info.on and "tuned in" or "tuned away")
    end
end)

AddEventHandler("playerDropped", function()
    local pid = tonumber(source)
    if pid then pcall(saveHistory, pid); players[pid] = nil; if director then director:drop(pid) end end
end)

CreateThread(function()
    while not (MySQL and MySQL.isReady and MySQL.isReady()) do Wait(1000) end
    if not set("radioEnabled", true) then log("radioEnabled is false: the station is off the air") return end
    RadioFacts.init(set("serverId", "ncm-dev"), clockOf)
    RadioFacts.loadNames()
    director = RadioDirector.new(NcmRadioCorpus)
    -- learn the Week so far silently: the show has memory, the listener is not owed a recap (bible §148)
    local t = now()
    local learned = 0
    for _, f in ipairs(RadioFacts.poll(t)) do director:observe(f, t); learned = learned + 1 end
    local lex = RadioFacts.writeLexicon()
    log("on the air: %d beats ready of %d, pack %s; learned %d facts; lexicon %d names, %d series, %d phrases",
        (function() local n = 0 for _, l in pairs(director.byTrigger) do n = n + #l end return n end)(), #NcmRadioCorpus.beats,
        tostring(NcmRadioCorpus.pack), learned, #(lex.name or {}), #(lex.series or {}), #(lex.phrase or {}))
    local lastPoll, lastStandings, lastLexicon = ms(), 0, ms()
    while true do
        if set("radioEnabled", true) then
            if ms() - lastPoll >= set("pollSeconds", 10) * 1000 then
                lastPoll = ms()
                local tt = now()
                for _, f in ipairs(RadioFacts.poll(tt)) do director:observe(f, tt) end
                if tt - lastStandings >= 3600 then
                    lastStandings = tt
                    local s = RadioFacts.standings(tt)
                    if s then director:observe(s, tt) end
                end
            end
            if ms() - lastLexicon >= 600000 then
                lastLexicon = ms()
                RadioFacts.writeLexicon()
                for pid in pairs(players) do pcall(saveHistory, pid) end
            end
            for pid, p in pairs(players) do
                if p.hello and (not p.item or ms() - p.startedMs >= p.item.totalMs + p.item.silenceMs) then
                    local okA, err = pcall(advance, pid, p)
                    if not okA then log("pid %d: next beat failed: %s", pid, tostring(err)); p.item, p.startedMs = { totalMs = 0, silenceMs = 30000, beat = "" }, ms() end
                end
            end
        end
        Wait(500)
    end
end)
