-- ncm_world / client / telemetry — the driver's own car, sampled at 5 Hz while racing (L57).
--
-- Samples are positional arrays { t, x, y, z, v, g, og, h } (core telemetry.SAMPLE_FIELDS) sent in batches of five
-- (`ncm:telemetry`). Position comes from the character; speed/gear/on-ground/health from the vehicle snapshot the
-- client may read for the car it sits in (`vehicles.read`). The first time a vehicle snapshot is read, its field
-- names are logged: that is the E4/L57 record of what this build exposes. /ncm.telemetry on|off.
local function log(fmt, ...) print(("[ncm_world/client/telemetry] " .. fmt):format(...)) end

-- Zero survives, absence does not. `competition.machine_knowledge.reading` is the single definition of that
-- rule and is shared with the server write path, so the client and the database cannot disagree about it.
local Reading = NcmCore.get("competition.machine_knowledge").reading

local enabled = true
local batch = {}
local loggedFields = false
local sent, refused = 0, 0
NcmClientTelemetryStatus = function() return ("%s sent=%d"):format(enabled and "on" or "off", sent) end

local function serverNow()
    -- the race HUD keeps the synced clock; fall back to the last published serverNow (IDEA-112: the map carries
    -- one `serverNow` for all live sessions, so this no longer needs to know which session it is in)
    if NcmClientServerNow then return NcmClientServerNow() end
    local ss = GlobalState and GlobalState.ncmSessions or nil
    return (type(ss) == "table" and tonumber(ss.serverNow)) or 0
end

--- The snapshot of the car the local player is sitting in, or nil.
---
--- **This is the one place that reads it**, because two consumers now depend on the same answer: the race
--- sampler below and the driver-input cluster in `race.lua`. Exported as a global (`NcmClientOwnVehicle`)
--- rather than duplicated -- a second copy of the seat/snapshot dance is a second place for the field names
--- to drift out of agreement with the runtime.
local function myVehicle()
    local ok, seat = pcall(Open77.vehicles.getPlayerSeat)
    if not ok or type(seat) ~= "table" then
        local ok2, s2 = pcall(Open77.players.getVehicleSeat)
        if ok2 and type(s2) == "table" then seat = s2 else return nil end
    end
    local vid = seat.vehicleId or seat.vehicle or seat.id
    if not vid then return nil end
    local okV, v = pcall(Open77.vehicles.get, vid)
    if not okV or type(v) ~= "table" then return nil end
    if not loggedFields then
        loggedFields = true
        local keys = {}
        for k, val in pairs(v) do if type(val) ~= "table" then keys[#keys + 1] = k .. "=" .. tostring(val) end end
        table.sort(keys)
        log("telemetry fields: %s", table.concat(keys, " "))
        -- **The runtime-verification record** (`31_CAPABILITY_AUDIT.md` §2, MASTER_TEST §103). The published
        -- API cards answer for `op77.78`; this server runs `.87`. One line, once per session, says what the
        -- build in front of us actually exposes -- and names the three driver-input fields explicitly, so a
        -- missing one is legible at a glance instead of being inferred from a long sorted list.
        local probe = {}
        for _, name in ipairs({ "throttle", "brake", "steering", "rpm", "rpmMax", "gear",
                                "suspensionLongitudinal", "suspensionTransversal", "speed", "onGround" }) do
            probe[#probe + 1] = name .. "=" .. (v[name] ~= nil and type(v[name]) or "ABSENT")
        end
        log("input surface: %s", table.concat(probe, " "))
    end
    return v
end
NcmClientOwnVehicle = myVehicle

--- One sample, or nothing at all.
---
--- **Zero is a measurement; absence is not** (`IDEA-361`, `31_CAPABILITY_AUDIT.md` §7). This function used
--- to read `tonumber(v.speed) or 0`, `tonumber(v.gear) or 0` and `tonumber(v.health) or 1`, so a moment when
--- the vehicle snapshot could not be read at all produced a sample claiming the car was stationary, in
--- neutral and undamaged -- indistinguishable, forever, from a car that genuinely was. The server card is
--- explicit that the motion half is *"zeroed when the vehicle has no owner"*, so this is not hypothetical.
---
--- A **parked car genuinely reading 0 km/h still produces a perfectly valid sample**, which is the half that
--- matters most: the fix is not "reject zero", it is "reject what was never read".
---
--- The sample is all-or-nothing because the wire format is a dense positional array
--- (`core telemetry.SAMPLE_FIELDS`); a hole in the middle of a Lua array constructor has an undefined length
--- and would serialise unpredictably. `decodeBatch` compares timestamps rather than assuming a fixed
--- cadence, so a dropped sample is a gap and not a corruption.
local skipped = 0
local function sample()
    local okP, x, y, z = pcall(Open77.character.position)
    if not okP then skipped = skipped + 1; return nil end
    x, y, z = Reading(x), Reading(y), Reading(z)
    if x == nil or y == nil or z == nil then skipped = skipped + 1; return nil end

    local v = myVehicle()
    if type(v) ~= "table" then skipped = skipped + 1; return nil end

    -- `speed` is metres per second on both sides; `speedKph` is the same number converted once. Prefer the
    -- native unit, fall back to the other, and give up rather than invent one.
    local speed = Reading(v.speed)
    if speed == nil then
        local kph = Reading(v.speedKph)
        speed = kph and (kph / 3.6) or nil
    end
    local gear, health = Reading(v.gear), Reading(v.health)
    local onGround = v.onGround
    if speed == nil or gear == nil or health == nil or type(onGround) ~= "boolean" then
        skipped = skipped + 1
        return nil
    end
    -- Health is documented 0..1; a build that reports a percentage is rescaled, not reinterpreted.
    if health > 1 then health = health / 100 end
    return { serverNow(), x, y, z, speed, gear, onGround, health }
end

CreateThread(function()
    Wait(3000)
    while true do
        -- IDEA-112: only ever the view the HUD picked -- telemetry belongs to the session I am actually in.
        local g = NcmClientView or nil
        local racing = enabled and NcmClientRaceActive and type(g) == "table" and (g.phase == "countdown" or g.phase == "running" or g.phase == "finishing" or g.phase == "open")
        if racing then
            local s = sample()
            if s then batch[#batch + 1] = s end
            if #batch >= 5 then
                TriggerServerEvent("ncm:telemetry", g.sessionId, batch)
                sent = sent + #batch
                batch = {}
            end
            Wait(200)
        else
            if #batch > 0 and type(g) == "table" and g.sessionId then TriggerServerEvent("ncm:telemetry", g.sessionId, batch) end
            batch = {}
            Wait(1000)
        end
    end
end)

RegisterCommand("ncm.telemetry", function(_, args)
    local a = args and args[1] and tostring(args[1]):lower() or nil
    if a == "on" then enabled = true elseif a == "off" then enabled = false end
    -- `skipped` is surfaced deliberately: samples are now dropped rather than fabricated, so the count is
    -- the only way to tell "nothing to report" from "could not read the car".
    log("telemetry %s · sent %d sample(s) · skipped %d unreadable", enabled and "on" or "off", sent, skipped)
end, false)
