-- ncm_aero / server: the aerospace race on the NCM Host (single player). See open77.lua.
--
-- One race at a time. `start` builds a field of the chosen garage machine (`space.aerocourse.event`) and runs it in
-- `space.tactical` on the world clock: race time follows wall time at `rate` (1 in play; the deck's DEV time lab may
-- raise it -- the race is marked DEV when it does). Steps are spent from a per-tick budget, so a slow frame catches up
-- over the next ones and never stalls the world. Twice a second the tower goes to the host (`ncm:host:aero`); every new
-- incident the city can see goes to Race Week (`ncm:week:fact`) as it happens.
local Core = NcmCore
local A = Core.get("space.aerocourse")
local Tac = Core.get("space.tactical")
local U = Core.get("space.universe")

local settings = Open77.tunables.declare({
    -- the NCM Host overrides this to "single_player"; anywhere else (the OPEN//77 dev server) it stays put and we idle
    environment = { value = "development", type = "string", apply = "live" },
})

local function log(fmt, ...) print(("[ncm_aero] " .. fmt):format(...)) end

if settings.environment ~= "single_player" then
    log("not single player (environment %s): aerospace racing stays off", tostring(settings.environment))
    return
end

local BUDGET_MS = 3          -- simulation time per world tick
local MAX_STEPS = 400        -- and never more steps than this in one tick
local PUBLISH_MS = 500

local L = { race = nil, ev = nil, t0 = nil, rate = 1, dev = false, seen = 0, facts = {}, seq = 0, done = false, machine = nil }

local function publish()
    local snap = { running = L.race ~= nil and not L.done, done = L.done, machine = L.machine, rate = L.rate, dev = L.dev }
    if L.race then
        snap.t = L.race.t - L.ev.rules.startT
        snap.lengthKm = L.ev.rules.lengthM / 1000
        snap.names = L.ev.venue.names
        snap.tower = {}
        for i, o in ipairs(Tac.standings(L.race)) do
            local E = L.race.entrants[o.id]
            snap.tower[i] = { position = o.position, id = o.id, name = E.person and E.person.display or o.id, livery = E.livery,
                status = o.status, reason = o.reason, leg = o.leg, gate = o.gate, altKm = (o.altM or 0) / 1000, speed = o.speed,
                gapS = o.gapS, gapKm = o.gapM and o.gapM / 1000 or nil, raceS = o.raceS, heatK = E.s.dyn.heatK, note = E.s.note,
                line = A.line(o) }
        end
        snap.incidents = {}
        for i = math.max(1, #L.race.log - 5), #L.race.log do
            local e = L.race.log[i]
            snap.incidents[#snap.incidents + 1] = { t = e.t - L.ev.rules.startT, kind = e.kind, ids = e.ids, band = e.band, leg = e.leg,
                dnf = e.dnf, city = e.pos and A.inCity(e.pos) or false }
        end
        snap.facts = L.facts
    end
    TriggerEvent("ncm:host:aero", snap)
end

--- New incidents -> Race Week, once each, as they happen.
local function report()
    local log_ = L.race.log
    while L.seen < #log_ do
        L.seen = L.seen + 1
        for _, f in ipairs(A.facts({ log_[L.seen] })) do
            TriggerEvent("ncm:week:fact", f.kind, f.n, "ncm_aero")   -- the source rides along; Race Week reads kind and n
            L.facts[#L.facts + 1] = { kind = f.kind, ids = f.incident.ids, leg = f.incident.leg, band = f.incident.band }
            log("Race Week hears it: %s (%s, %s leg, band %s)", f.kind, table.concat(f.incident.ids, ","), tostring(f.incident.leg),
                tostring(f.incident.band))
        end
    end
end

local function start(opts)
    opts = type(opts) == "table" and opts or {}
    if type(opts.vehicleKey) ~= "string" or opts.vehicleKey == "" then
        log("start refused: no machine (choose one from the tape's garage)")
        return
    end
    L.seq = L.seq + 1
    local id = ("aero:%s:%d:%d"):format(GetConvar("ncm_server_id", "sp"), GetGameTimer(), L.seq)
    local ok, ev = pcall(A.event, { id = id, vehicleKey = opts.vehicleKey, size = tonumber(opts.size) or 12,
        route = { turnAltM = tonumber(opts.turnAltM) or 120000 } })
    if not ok then log("start refused: %s", tostring(ev)); return end
    -- the course runs in the real universe (a Snowglobe test may have compressed it; never in play)
    U.setWorld({})
    L.ev, L.race, L.t0, L.seen, L.facts, L.done = ev, Tac.new(ev), GetGameTimer(), 0, {}, false
    L.machine, L.rate, L.dev = opts.vehicleKey, 1, false
    log("race %s: %d %s, %s -> %s -> Deep (%.0f km) -> %s, %.0f km", id, #ev.entrants, opts.vehicleKey, ev.venue.names.start,
        ev.venue.names.via, (tonumber(opts.turnAltM) or 120000) / 1000, ev.venue.names.finish, ev.rules.lengthM / 1000)
    publish()
end

AddEventHandler("ncm:aero:cmd", function(action, arg)
    if action == "start" then start(arg)
    elseif action == "stop" then
        if L.race then log("race %s stopped at %.0f s", L.ev.id, L.race.t) end
        L.race, L.ev, L.done = nil, nil, false
        publish()
    elseif action == "rate" then
        -- DEV time lab: race time faster than wall time (marked DEV: it is a test of the race, not the race)
        local r = math.max(1, math.min(60, tonumber(arg) or 1))
        if L.race and r ~= L.rate then
            -- keep race time continuous: re-anchor the start so now maps to the current race time
            L.t0 = GetGameTimer() - L.race.t * 1000 / r
        end
        L.rate, L.dev = r, L.dev or r > 1
        publish()
    end
end)

CreateThread(function()
    local lastPub = 0
    while true do
        Wait(0)
        if L.race and not L.done then
            local target = (GetGameTimer() - L.t0) / 1000 * L.rate
            local began, n = GetGameTimer(), 0
            while L.race.t < target and n < MAX_STEPS and GetGameTimer() - began < BUDGET_MS do
                Tac.step(L.race)
                n = n + 1
                if Tac.over(L.race) then break end
            end
            report()
            if Tac.over(L.race) then
                L.done = true
                local rows = Tac.result(L.race)
                local w = rows[1]
                log("race %s over at %.0f s: winner %s (%s) %s", L.ev.id, L.race.t, w and w.id or "-", w and w.state or "-",
                    w and w.raceS and ("%.1f s"):format(w.raceS) or "")
                publish()
            end
        end
        if GetGameTimer() - lastPub >= PUBLISH_MS then
            lastPub = GetGameTimer()
            if L.race then publish() end
        end
    end
end)

log("ready (single player)")
