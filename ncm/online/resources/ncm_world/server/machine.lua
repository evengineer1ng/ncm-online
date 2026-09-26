-- ncm_world / server / machine -- what each car in the fleet currently IS, published for the carrier.
--
-- The server composes; the carrier applies; neither decides the other's business (`L135`). Everything here
-- is `machine.projection`, which is pure and tested offline -- this file only supplies the facts and
-- publishes the result.
--
-- **Why GlobalState and not a per-player event.** The record carrier is per-RECORD and world-wide by
-- nature: rain falls on everyone's Quadra at once, and a class ruleset is a property of the class. That is
-- exactly the shape `GlobalState.ncmCeilings` already has, and `client/main.lua` already runs a loop that
-- reads it. Re-using that path means one publishing mechanism instead of two, and it means a player who
-- joins late gets the current state without anyone having to remember to send it.
--
-- Per-PLAYER facts -- this driver's fitted parts, this driver's wear -- cannot travel this way, because two
-- drivers of the same model would need different values and the record has only one. That is Report 36's
-- hardest constraint and it is not worked around here. When Parts arrive, their per-machine half goes on the
-- command carrier or it waits; it does not quietly get averaged into a record.
--
-- **Spawn-cached.** A projection reaches a car when the car spawns. Changing the weather does not change the
-- car someone is already driving. The design has to live with that rather than pretend otherwise.
local Projection = NcmCore.get("machine.projection")
local Weather = NcmCore.get("world.weather")
local Json = NcmCore.get("vocabulary.json")

local function log(fmt, ...) print(("[ncm_world/machine] " .. fmt):format(...)) end

-- The server Lua sandbox has no `os` -- `os.time()` is a nil index, which is how the first live run of this
-- file died. Every other NCM server module already goes through the platform clock; this one now does too.
local function now() return math.floor(Open77.time.unix()) end

NcmMachine = NcmMachine or {}

-- The live world state the projection composes from. Weather is the only one that moves today; the others
-- are here so that adding them later is a value change rather than a redesign.
local state = {
    weather = nil,          -- an OPEN//77 weather id, e.g. "rain"
    wetness = 0,            -- 0..1, derived from the weather family
}

local published = {}        -- record -> signature, so we only rewrite GlobalState when something changed

--- Rain is a family, not a percentage, so the mapping is stated once, here, and it is deliberately coarse.
--- `world.weather` already classifies every allowed state into dry / wet / obscured / hazardous.
local function wetnessOf(weatherId)
    if type(weatherId) ~= "string" then return 0 end
    local family = Weather.family(weatherId)
    if family == "wet" then return 1.0 end
    -- Obscured is not wet. Fog reduces what a driver can SEE, and pretending it reduces grip would be the
    -- same category error IDEA-057's ceiling approximation made in the other direction.
    return 0
end

--- The fleet NCM actually issues. Taken from the published class ceilings rather than from the whole vehicle
--- catalogue: those are the records NCM has declared a handling truth for, and writing flats on a record no
--- NCM car uses would change someone's personal single-player car for no reason.
local function fleet()
    local ok, ceilings = pcall(function() return GlobalState.ncmCeilings end)
    if not ok or type(ceilings) ~= "table" then return {} end
    -- KB-136: ceilings now publish as both a sorted `entries` array and the historical record-keyed map.
    -- Read either, preferring the array, so that dropping the map once the transport question is settled is
    -- a one-line deletion there rather than a silent empty fleet here.
    if type(ceilings.entries) == "table" then
        local out = {}
        for _, entry in ipairs(ceilings.entries) do
            if type(entry) == "table" and type(entry.path) == "string" then out[entry.path] = entry.profile end
        end
        return out
    end
    if type(ceilings.records) == "table" then return ceilings.records end
    return {}
end

--- Compose and publish. Cheap enough to call on any change; it only writes what moved.
function NcmMachine.recompute(why)
    local records = fleet()
    local out = {}
    local changed, cleared = 0, 0

    for record, ceiling in pairs(records) do
        local envelope, err = Projection.compose({
            record = record,
            weather = { wetness = state.wetness },
            ruleset = { ceiling = type(ceiling) == "table" and ceiling or nil },
        }, { at = now() })

        if not envelope then
            -- Named, never silent. A refusal here means the fleet or the ruleset is malformed, and a car
            -- quietly keeping last week's grip is far worse than a line in the log.
            log("refused for %s: %s", tostring(record), tostring(err))
        elseif not Projection.isEmpty(envelope) then
            out[record] = envelope
            local sig = tostring(#envelope.record.flats) .. "/" .. tostring(state.wetness)
            if published[record] ~= sig then
                published[record] = sig
                changed = changed + 1
            end
        end
    end

    -- A record that stopped having a projection must be told to restore, or it keeps yesterday's rain
    -- forever. The same lesson `client/main.lua` learned about ceilings that stop being published.
    for record in pairs(published) do
        if out[record] == nil then
            out[record] = Projection.clear(record, { at = now() })
            published[record] = nil
            cleared = cleared + 1
        end
    end

    -- ------------------------------------------------------------------------------------------------
    -- **KB-136 ANSWERED, 2026-09-26: the state bag has a SIZE limit and this payload was over it.**
    --
    -- The first honest error this bug ever produced was `state bag write refused: state_value_too_large`,
    -- and `ncm_league/server/race.lua` hit the same wall on 2026-09-23. It was never a map-shape problem and
    -- never the dots in the record path. The publish was simply refused, so a client saw nothing -- which is
    -- indistinguishable from every other failure when the reader logs nothing either.
    --
    -- **What made it too large: `trace`.** `machine.projection` records one entry per flat movement --
    -- carrier, layer, id, from, to, by -- so the audit trail is several times the size of the result, and it
    -- was being shipped to every client eleven times over. **The carrier never reads it.** Nor does it read
    -- `ceiling`, which reaches clients through `ncmCeilings` and `setPerformanceClass` instead.
    --
    -- So the wire form is now exactly what the carrier consumes and nothing else. The full envelope,
    -- `trace` included, stays server-side where the reasoning belongs and can still be inspected with
    -- `ncm.machine`. This is a smaller payload AND a better boundary: the audit trail was never the
    -- client's business (`L135` -- the server composes, the carrier applies).
    -- ------------------------------------------------------------------------------------------------
    local entries = {}
    for record, envelope in pairs(out) do
        local flats = {}
        for _, f in ipairs(envelope.record and envelope.record.flats or {}) do
            flats[#flats + 1] = { id = f.id, suffix = f.suffix, multiplier = f.multiplier }
        end
        entries[#entries + 1] = {
            path = record,
            flats = flats,
            restore = (envelope.record and envelope.record.restore) or false,
            at = envelope.at,
        }
    end
    -- Sorted, so two publications of the same fleet produce identical payloads and a client can compare them
    -- cheaply. `pairs` order is not stable and would make every republish look like a change.
    table.sort(entries, function(a, b) return a.path < b.path end)

    local payload = { version = Projection.ENVELOPE_VERSION, entries = entries }

    -- Measure before writing. The limit is not documented anywhere we can read, so the only way anyone will
    -- ever know how close we are is if the number is in the log on every publish.
    local okSize, encoded = pcall(Json.encode, payload)
    local bytes = okSize and #encoded or -1

    -- **Diagnostic, temporary, delete with the probe.** The payload this replaces -- the full envelopes,
    -- `trace` and all -- is measured but never written, so we can state the ratio instead of guessing at it.
    -- It matters because the old payload WAS accepted by the state bag (it logged success on 2026-09-26 at
    -- 02:04 and 02:21) and still never reached a client. If a value can be written and silently not
    -- replicated, the threshold for replication is lower than the threshold for acceptance, and the number
    -- below is how we find out.
    local okOld, oldEncoded = pcall(Json.encode, { version = Projection.ENVELOPE_VERSION, records = out })
    log("payload: wire %d byte(s), full-envelope %d byte(s)", bytes, okOld and #oldEncoded or -1)

    -- **Never throw.** The previous write was a bare assignment, so a refusal became a script error that
    -- aborted `recompute` -- which is why the `cleared` bookkeeping above could never run either. A refusal
    -- is now a named log line and the function completes.
    local okWrite, writeErr = pcall(function() GlobalState.ncmProjections = payload end)
    if not okWrite then
        log("REFUSED by the state bag at %d byte(s): %s", bytes, tostring(writeErr))
        log("  %d record(s) were not published. KB-136: the payload is over the size limit.", #entries)
        return
    end

    if changed > 0 or cleared > 0 then
        log("published %d record(s) [%s]: %d changed, %d cleared, wetness %.2f, %d byte(s)",
            #entries, tostring(why), changed, cleared, state.wetness, bytes)
    end
end

--- Called by whatever owns the weather. Idempotent: the same weather twice does nothing.
function NcmMachine.setWeather(weatherId)
    local wetness = wetnessOf(weatherId)
    if state.weather == weatherId and state.wetness == wetness then return end
    state.weather = weatherId
    state.wetness = wetness
    log("weather is %s (wetness %.2f)", tostring(weatherId), wetness)
    NcmMachine.recompute("weather")
end

function NcmMachine.state()
    return { weather = state.weather, wetness = state.wetness }
end

-- The ceilings are published by ncm_league at boot and can change with the calendar, so the fleet is not
-- static. Poll rather than depend on an event ncm_league does not currently raise -- a dependency on a
-- client-less resource fails activation, which is the mistake `open77.lua` records at the top of this
-- resource.
CreateThread(function()
    Wait(8000)
    while true do
        NcmMachine.recompute("poll")
        Wait(30000)
    end
end)

RegisterCommand("ncm.machine", function(source, args)
    local action = args and args[1] and tostring(args[1]):lower() or nil
    if action == "weather" and args[2] then
        NcmMachine.setWeather(tostring(args[2]))
        return
    end
    local s = NcmMachine.state()
    local ok, published_ = pcall(function() return GlobalState.ncmProjections end)
    local n = 0
    if ok and type(published_) == "table" and type(published_.records) == "table" then
        for _ in pairs(published_.records) do n = n + 1 end
    end
    log("weather=%s wetness=%.2f records=%d", tostring(s.weather), s.wetness, n)
end, true)
