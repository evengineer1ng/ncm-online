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

local function log(fmt, ...) print(("[ncm_world/machine] " .. fmt):format(...)) end

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
    if not ok or type(ceilings) ~= "table" or type(ceilings.records) ~= "table" then return {} end
    return ceilings.records
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
        }, { at = os.time() })

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
            out[record] = Projection.clear(record, { at = os.time() })
            published[record] = nil
            cleared = cleared + 1
        end
    end

    GlobalState.ncmProjections = { version = Projection.ENVELOPE_VERSION, records = out }

    if changed > 0 or cleared > 0 then
        log("published %d record(s) [%s]: %d changed, %d cleared, wetness %.2f",
            (function() local n = 0; for _ in pairs(out) do n = n + 1 end; return n end)(),
            tostring(why), changed, cleared, state.wetness)
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
