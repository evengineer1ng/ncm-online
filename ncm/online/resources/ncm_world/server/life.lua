-- ncm_world / server / life -- KB-350: a dead player comes back. IDEA-1144: a falling one goes back in their car.
--
-- The freeroam gamemode owns respawn on a platform server (`onPlayerLifeStateChanged` dead -> `players.respawn`), but NCM
-- servers do not load freeroam, so a death was permanent: on 2026-10-06 the owner fell from a mid-air saved position,
-- died, and stayed dead and falling through rejoins and `ncm.heal` (health is not life). This brings a dead player back
-- on the ground at the nearest known-safe point, after a short beat so the death reads. A sweep catches anyone whose
-- death event was missed (joined already dead, or died during a restart).
local function log(fmt, ...) print(("[ncm_world/life] " .. fmt):format(...)) end

local RESPAWN_DELAY_MS = 3000
local SWEEP_MS = 5000
-- Ground points the platform's own freeroam ships as spawns (validated positions), one per region.
local SAFE = {
    { name = "Westbrook dealership", x = -1442.2, y = 127.4, z = 18.0, heading = 0 },
    { name = "City Center west", x = -667.14, y = -382.61, z = 9.16, heading = 0 },
    { name = "East laboratory", x = 1669.75, y = -739.12, z = 49.86, heading = 0 },
    { name = "Badlands arena", x = 381.36, y = -2401.79, z = 181.99, heading = 0 },
    { name = "Watson rooftop start", x = -1023.24, y = 1492.81, z = 25.87, heading = 0 },
    { name = "Watson north promenade", x = -469.47, y = 930.99, z = 56.45, heading = -68 },
}

local function nearest(pos)
    local best, bd = SAFE[1], math.huge
    if type(pos) == "table" and tonumber(pos.x) and tonumber(pos.y) then
        for _, p in ipairs(SAFE) do
            local d = (p.x - pos.x) ^ 2 + (p.y - pos.y) ^ 2
            if d < bd then best, bd = p, d end
        end
    end
    return best
end

local pending = {}   -- pid -> true while a respawn is scheduled

local function respawn(pid, why)
    local okL, life = pcall(Open77.players.getLifeState, pid)
    if not okL or type(life) ~= "table" or life.phase ~= "dead" then pending[pid] = nil; return end
    local p = nearest(life.position)
    local ok, done, reason = pcall(Open77.players.respawn, pid, { position = { x = p.x, y = p.y, z = p.z }, heading = p.heading,
        bucket = life.bucket or 0, graceMs = 3000 })
    pending[pid] = nil
    local pos = type(life.position) == "table" and life.position or {}
    log("RESPAWN player=%d (%s): died at %.0f, %.0f, %.0f -> %s | %s %s", pid, why, tonumber(pos.x) or 0, tonumber(pos.y) or 0,
        tonumber(pos.z) or 0, p.name, tostring(ok and done), tostring(ok and reason or done))
end

local function schedule(pid, why)
    if pending[pid] then return end
    pending[pid] = true
    SetTimeout(RESPAWN_DELAY_MS, function() respawn(pid, why) end)
end

AddEventHandler("onPlayerLifeStateChanged", function(playerId, _, phase)
    local pid = tonumber(playerId)
    if pid and phase == "dead" then schedule(pid, "died") end
end)

-- ------------------------------------------------------------------------------------------------ freefall rescue
-- IDEA-1144 (owner, 2026-10-06): "puts me in my vehicle when im falling out of the sky from deep or just generally".
-- A player ON FOOT falling faster than FALL_VZ for FALL_S is put in the driver's seat of their own live Machine,
-- wherever it is -- the only logical place for them. No live Machine: nothing to do here, and the respawn above
-- catches the landing. One rescue per COOLDOWN_S per player.
local FALL_VZ = -25          -- m/s down (a ~32 m drop); ledge hops and stairs never reach it
local FALL_S = 0.5
local TICK_MS = 250
local COOLDOWN_S = 5
local falling = {}           -- pid -> seconds falling
local lastRescue = {}        -- pid -> GetGameTimer() of the last attempt

local function seated(pid)
    local ok, s = pcall(Open77.players.getVehicleSeat, pid)
    if not ok or s == nil or s == false then return false end
    if type(s) == "table" then return (s.vehicleId or s.vehicle or s.id) ~= nil end
    return true
end

local function myMachine(pid)
    if not (NcmVehicleAccess and NcmVehicleAccess.liveAssets) then return nil end
    for _, a in ipairs(NcmVehicleAccess.liveAssets()) do
        if tonumber(a.pid) == pid and a.vehicleId then return a end
    end
    return nil
end

local function rescue(pid, r)
    local now = GetGameTimer()
    if lastRescue[pid] and now - lastRescue[pid] < COOLDOWN_S * 1000 then return end
    lastRescue[pid] = now
    local p, v = r.position, r.velocity
    local a = myMachine(pid)
    if not a then
        log("FREEFALL player=%d at %.0f, %.0f, %.0f (%.0f m/s down): no live Machine to put you in", pid, p.x, p.y, p.z, -v.z)
        return
    end
    local ok, res, reason = pcall(Open77.players.warpIntoVehicle, pid, a.vehicleId, "driver")
    local okV, veh = pcall(Open77.vehicles.get, a.vehicleId)
    local cp = okV and type(veh) == "table" and veh.position or {}
    log("FREEFALL player=%d at %.0f, %.0f, %.0f (%.0f m/s down) -> into asset ..%s (vehicle %s at %.0f, %.0f, %.0f): %s %s",
        pid, p.x, p.y, p.z, -v.z, tostring(a.assetId):sub(-6), tostring(a.vehicleId), tonumber(cp.x) or 0, tonumber(cp.y) or 0,
        tonumber(cp.z) or 0, tostring(ok and res), tostring(ok and reason or res))
end

CreateThread(function()
    while true do
        Wait(TICK_MS)
        local okA, all = pcall(Open77.players.all)
        if okA and type(all) == "table" then
            for _, pid in ipairs(all) do
                pid = tonumber(pid)
                local okR, r = pcall(Open77.players.get, pid)
                local live = okR and type(r) == "table" and r.position and r.velocity and (tonumber(r.ageMs) or 1e9) < 1000
                if live and (tonumber(r.velocity.z) or 0) < FALL_VZ and not seated(pid) then
                    local okL, life = pcall(Open77.players.getLifeState, pid)
                    if okL and type(life) == "table" and life.phase == "alive" then
                        falling[pid] = (falling[pid] or 0) + TICK_MS / 1000
                        if falling[pid] >= FALL_S then falling[pid] = 0; rescue(pid, r) end
                    end
                else
                    falling[pid] = nil
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(SWEEP_MS)
        local okA, all = pcall(Open77.players.all)
        if okA and type(all) == "table" then
            for _, pid in ipairs(all) do
                local okD, dead = pcall(Open77.players.isDead, pid)
                if okD and dead == true then
                    local okL, life = pcall(Open77.players.getLifeState, pid)
                    if okL and type(life) == "table" and life.phase == "dead" then schedule(pid, "sweep: still dead") end
                end
            end
        end
    end
end)
