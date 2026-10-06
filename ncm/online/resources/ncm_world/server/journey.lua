-- ncm_world / server / journey -- a Machine's physical journey, recorded (schema 067; owner, 2026-10-06, "NCM 3.0
-- post-Laguna" item 9). Night City -> Laguna Seca was travelled for real; the same trip must be measurable later as a
-- race. This only RECORDS what Deep and the embodiment host already observe -- no scoring, no XP, no interpolation:
-- departure (the Deep entry) and its time, Guidance, the 1 Hz trajectory, peak altitude/speed, thermal shutdowns,
-- propellant, the arrival envelope, physicalization in the host, touchdown there, departure from it, the outcome.
-- DEVELOPMENT ONLY like Deep itself.
local function log(fmt, ...) print(("[ncm_world/journey] " .. fmt):format(...)) end
local ids = NcmCore.get("vocabulary.ids")
local rng = function() return math.random() end
local TRACE_MAX = 7200            -- two hours at 1 Hz
-- KB-358 (KB-347's shape): a nil in the middle of a Lua parameter list is a hole -- the insert silently failed for every
-- unresolved place (no lat/lon). NULL is spelled out in the statement for each nil value instead.
local function sqlValues(cols, vals, n)
    local marks, out = {}, {}
    for i = 1, n do
        if vals[i] == nil then marks[i] = "NULL" else marks[i] = "?"; out[#out + 1] = vals[i] end
    end
    return "(" .. cols .. ") VALUES (" .. table.concat(marks, ",") .. ")", out
end

NcmJourney = {}
local J = {}                      -- pid -> the journey in progress

local function now() return Open77.time.unix() end
local function serverId()
    local ok, id = pcall(function() return GlobalState.ncmIdentity end)
    return ok and type(id) == "table" and id.serverId or "ncm-devbox"
end

--- The Machine left REDengine: the journey starts at the Deep entry (REDengine owns the climb before it).
function NcmJourney.start(pid, info)
    info = type(info) == "table" and info or {}
    local prof = NcmIdentity and NcmIdentity.get and NcmIdentity.get(pid) or nil
    J[pid] = {
        id = ids.uuid4(rng), driver = prof and prof.ncmDriverId or nil, asset = info.asset, origin = "night_city",
        startedAt = now(), events = { { t = 0, what = "deep_entry", game = info.game, mass = info.mass, devices = info.devices } },
        config = { massKg = info.mass, devices = info.devices },
        trace = {}, peakAlt = 0, peakSpeed = 0, hot = 0, wasHot = false, fuelStart = nil, fuelEnd = nil, acPropellantKg = 0,
    }
    log("START player=%d journey ..%s asset ..%s", pid, J[pid].id:sub(-6), tostring(info.asset or "?"):sub(-6))
end

local function rel(j) return math.floor((now() - j.startedAt) * 10 + 0.5) / 10 end

--- A named moment: guidance_engaged / guidance_refused / arrived / embody_requested / physicalized / ac_ready /
--- touchdown / ac_departed / resumed ...
function NcmJourney.mark(pid, what, data)
    local j = J[pid]
    if not j then return end
    local e = { t = rel(j), what = what }
    for k, v in pairs(type(data) == "table" and data or {}) do e[k] = v end
    j.events[#j.events + 1] = e
    if what == "guidance_engaged" and data and data.venue then j.destination = data.venue end
    if what == "touchdown" and not j.touchdownAt then j.touchdownAt = e.t end
    if what == "physicalized" and not j.physicalizedAt then j.physicalizedAt = e.t end
    if what == "arrived" and not j.arrivedAt then j.arrivedAt = e.t end
end

--- Deep telemetry (1 Hz from the client).
function NcmJourney.sample(pid, t)
    local j = J[pid]
    if not j or type(t) ~= "table" then return end
    local alt, speed = tonumber(t.alt) or 0, tonumber(t.speed) or 0
    if #j.trace < TRACE_MAX then
        j.trace[#j.trace + 1] = { rel(j), math.floor((tonumber(t.lat) or 0) * 1e5) / 1e5, math.floor((tonumber(t.lon) or 0) * 1e5) / 1e5,
            math.floor(alt), math.floor(speed), math.floor(tonumber(t.thrust) or 0) }
    end
    if alt > j.peakAlt then j.peakAlt = alt end
    if speed > j.peakSpeed then j.peakSpeed = speed end
    local hot = tostring(t.devices or ""):find("HOT", 1, true) ~= nil
    if hot and not j.wasHot then j.hot = j.hot + 1; NcmJourney.mark(pid, "thermal_shutdown", { devices = t.devices }) end
    j.wasHot = hot
    local fuel = tonumber(t.fuelKg)
    if fuel then j.fuelStart = j.fuelStart or fuel; j.fuelEnd = fuel end
end

--- The host's own telemetry (Assetto Corsa): touchdown is the first time the Machine is on the ground there.
function NcmJourney.hostSample(pid, ev)
    local j = J[pid]
    if not j or type(ev) ~= "table" then return end
    if not j.touchdownAt and tonumber(ev.height) and tonumber(ev.height) < 3 and j.physicalizedAt then
        NcmJourney.mark(pid, "touchdown", { host = "assetto_corsa", speed = tonumber(ev.speed) })
    end
    if tonumber(ev.propellantKg) then j.acPropellantKg = tonumber(ev.propellantKg) end
end

--- The journey ends (home over Night City, landing elsewhere, the player left). One row.
function NcmJourney.finish(pid, outcome, extra)
    local j = J[pid]
    if not j then return end
    J[pid] = nil
    local ended = now()
    NcmJourney._last = j
    local summary = {
        journeyId = j.id, origin = j.origin, destination = j.destination, outcome = outcome, driverId = j.driver, machineAssetId = j.asset,
        startedAt = j.startedAt, endedAt = ended, elapsedS = ended - j.startedAt,
        arrivalEnvelopeS = j.arrivedAt, physicalizedS = j.physicalizedAt, touchdownS = j.touchdownAt,
        peakAltitudeM = math.floor(j.peakAlt), peakSpeedMs = math.floor(j.peakSpeed), thermalShutdowns = j.hot,
        deepPropellantKg = (j.fuelStart and j.fuelEnd) and (j.fuelStart - j.fuelEnd) or nil, hostPropellantKg = j.acPropellantKg,
        configuration = j.config, events = j.events, extra = extra, provenance = "observed",
    }
    local Json = NcmCore.get("vocabulary.json")
    local okS, sj = pcall(Json.encode, summary)
    local okT, tj = pcall(Json.encode, j.trace)
    log("FINISH player=%d journey ..%s %s -> %s | %s | %.0f s | peak %.1f km, %.0f m/s | thermal %d | physicalized %s, touchdown %s",
        pid, j.id:sub(-6), j.origin, tostring(j.destination or "-"), outcome, ended - j.startedAt, j.peakAlt / 1000, j.peakSpeed, j.hot,
        tostring(j.physicalizedAt or "-"), tostring(j.touchdownAt or "-"))
    if not (okS and MySQL and MySQL.insert) then return end
    CreateThread(function()
        local vals, args = sqlValues("journey_id, server_id, driver_id, machine_asset_id, origin, destination, outcome, started_at, ended_at, elapsed_s, summary_json, trace_json",
            { j.id, serverId(), j.driver, j.asset, j.origin, j.destination, outcome, math.floor(j.startedAt), math.floor(ended),
              ended - j.startedAt, sj, okT and tj or nil }, 12)
        local ok, err = pcall(MySQL.insert.await, "INSERT INTO machine_journey " .. vals, args)
        if not ok then log("could not store journey ..%s: %s", j.id:sub(-6), tostring(err)) end
    end)
end

function NcmJourney.active(pid) return J[pid] ~= nil end
