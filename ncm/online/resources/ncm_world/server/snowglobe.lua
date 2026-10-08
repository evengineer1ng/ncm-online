-- ncm_world / server / snowglobe -- Snowglobe 0: the first Night City -> space -> Night City loop (L317; doc 51 §6).
--
-- WHAT IT IS. Above a doorway altitude NCM, not REDengine, owns how high a car is. Night City's hard ceiling is
-- z = 16,384 m (§AX4), so the car's game height cannot be its altitude up there. This keeps, per car, an OFFSET: the
-- altitude the game is no longer showing. Universe altitude = game z + offset. A floating origin in one axis, using
-- the only move the platform accepts for a network car -- the server's own `setTransform` (§SG2: a client teleport is
-- a `motion_jump` and is revoked; §SG4: the server move holds and keeps the driver).
--
--   * climbing through `UP` (14 km game height) -> the car is moved down to `LOW` (4 km); offset += the drop
--   * falling through `DOWN` (3 km) with an offset -> moved up by min(offset, STEP); offset -= that
--   * offset 0 = ordinary Night City again
--
-- WHAT IT DELIBERATELY IS NOT (owner, 2026-10-05: "we control the perspective of speed ... there has been a loading
-- screen at sim"). Speed is not carried through a move -- the server move zeroes it and the car resumes from rest when
-- its lease returns (~3 s). Nothing is hidden: the city stays a blur below. No stars, no planet yet. The point is the
-- loop and the universe altitude, not the look.
--
-- Automatic: on in `development`, every seated car, no command (owner: "why would you make auto mode still require a
-- console command"). `ncm.snowglobe off|on|status` in the console. Never on any other environment.
local Core = NcmCore
local Universe = Core.get("space.universe")

local UP, LOW, DOWN, STEP = 14000, 4000, 3000, 10000
local TICK_MS, COOLDOWN_MS = 200, 6000

local function log(fmt, ...) print(("[ncm_world/snowglobe] " .. fmt):format(...)) end

-- L341: flight ships to Online, so the altitude doorway runs there too (the name is historical).
local function development()
    local ok, id = pcall(function() return GlobalState.ncmIdentity end)
    local env = tostring(ok and type(id) == "table" and id.environment or "development")
    return env == "development" or env == "online"
end

local enabled = true
local cars = {}   -- vehicleId -> { offset, lastZ, lastT, coolUntil, moves, reportAt }
NcmSnowglobe = NcmSnowglobe or {}
--- L324 telemetry: the altitude this car is not showing (0 = ordinary Night City). Universe z = game z + this.
NcmSnowglobe.offset = function(vid) local st = cars[tonumber(vid) or vid]; return st and st.offset or 0 end

local function universeAltitude(b, offset)
    return Universe.altitude(Universe.cityToUniverse({ b.x, b.y, b.z + offset }))
end

local function move(vid, b, dz, why, st)
    local target = { x = b.x, y = b.y, z = b.z + dz }
    local yaw = tonumber(b.yaw or b.heading) or 0
    local ok, moved, reason = pcall(Open77.vehicles.setTransform, vid, { position = target, yaw = yaw })
    if b.flags ~= nil then pcall(Open77.vehicles.update, vid, { flags = b.flags }) end   -- setTransform clears them
    st.moves = st.moves + 1
    log("vehicle=%d %s: game z %.0f -> %.0f | offset now %.0f | universe altitude %.0f m | setTransform -> %s %s",
        vid, why, b.z, target.z, st.offset, universeAltitude(target, st.offset), tostring(ok and moved), tostring(ok and reason or moved))
    return ok and moved
end

local function step(vid, b, now)
    local st = cars[vid]
    if not st then
        st = { offset = 0, moves = 0, coolUntil = 0, reportAt = 0 }
        cars[vid] = st
    end
    local z = tonumber(b.z)
    if not z then return end
    local vz = (st.lastZ and now > st.lastT) and (z - st.lastZ) / ((now - st.lastT) / 1000) or 0
    st.lastZ, st.lastT = z, now
    if now < st.coolUntil then return end
    if z >= UP and vz > 0 then
        local dz = LOW - z
        st.offset = st.offset - dz
        st.coolUntil = now + COOLDOWN_MS
        st.lastZ = nil
        move(vid, b, dz, st.offset == -dz and "THROUGH THE DOORWAY (rebase down)" or "rebase down", st)
    elseif st.offset > 0 and z <= DOWN and vz < 0 then
        -- a remainder under 500 m rides along: a second freeze 4 m above the first is a defect (seen in simulation)
        local up = (st.offset <= STEP + 500) and st.offset or STEP
        st.offset = st.offset - up
        st.coolUntil = now + COOLDOWN_MS
        st.lastZ = nil
        move(vid, b, up, st.offset == 0 and "HOME: back over Night City (rebase up)" or "rebase up", st)
    elseif st.offset > 0 and now >= st.reportAt then
        st.reportAt = now + 10000
        log("vehicle=%d in space: universe altitude %.0f m (game z %.0f + offset %.0f), %+.1f m/s vertical",
            vid, universeAltitude(b, st.offset), z, st.offset, vz)
    end
end

CreateThread(function()
    Wait(5000)
    log("Snowglobe 0 %s: doorway at %d m game height (rebase to %d), home below %d m; development and online",
        development() and (enabled and "ON" or "off") or "inactive (not development/online)", UP, LOW, DOWN)
    while true do
        Wait(TICK_MS)
        if enabled and development() then
            local now = GetGameTimer()
            local okP, players = pcall(Open77.players.all)
            local seen = {}
            if okP and type(players) == "table" then
                for _, pid in ipairs(players) do
                    local okS, seat = pcall(Open77.vehicles.getPlayerSeat, pid)
                    local vid = okS and type(seat) == "table" and tonumber(seat.vehicleId or seat.vehicle or seat.id) or nil
                    if vid and not seen[vid] then
                        seen[vid] = true
                        local okB, b = pcall(Open77.vehicles.get, vid)
                        if okB and type(b) == "table" then step(vid, b, now) end
                    end
                end
            end
        end
    end
end)

AddEventHandler("onVehicleRemoved", function(vid)
    vid = tonumber(vid)
    if vid and cars[vid] then
        if cars[vid].offset > 0 then log("vehicle=%d removed while in space (offset %.0f) -- forgotten", vid, cars[vid].offset) end
        cars[vid] = nil
    end
end)

RegisterCommand("ncm.snowglobe", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local a = args and args[1]
    if a == "off" then enabled = false elseif a == "on" then enabled = true end
    local n = 0
    for vid, st in pairs(cars) do
        if st.offset > 0 then n = n + 1; log("  vehicle=%d offset %.0f, %d move(s)", vid, st.offset, st.moves) end
    end
    log("snowglobe %s (%s); %d car(s) in space", enabled and "ON" or "off", development() and "development/online" or "inactive", n)
end, false)
