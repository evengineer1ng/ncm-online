-- ncm_world / server / av_board -- getting into an AV with the same key as a car (owner, 2026-10-12: "not chat command,
-- make it same button as entering a car").
--
-- The game's AVs (Zetatech Atlus, Manticore, Excalibur, Valgus, ...) carry a driver seat (`seat_front_left`, the slot
-- quest scenes use) but no player Enter interaction, so walking up to one and pressing F does nothing. This is the
-- missing prompt, done the way the "Drive an Aerial Vehicle" mod does it (an entry area + the enter key -> mount into
-- the seat), except the seat is assigned through OPEN//77's authoritative ledger (`warpPlayerIntoVehicle`), so every
-- client sees the pilot in the cockpit.
--
-- The server says which AV a player on foot is standing at (`ncm:av.near`, on change only); the client draws the
-- hint and sends F (`ncm:av.board` / `ncm:av.leave`). Flight itself is not here: this only seats the pilot.
local RADIUS_M = 9            -- an Atlus is ~12 m long; its centre is ~5 m from the door
local POLL_MS = 400
local near = {}               -- pid -> vehicle id the client was last told about (false = told "none")
local boardedAt = {}          -- pid -> time of the last board, so the F that seated you does not also unseat you

local function log(fmt, ...) print(("[ncm_world/av_board] " .. fmt):format(...)) end

local AERIAL = { "^Vehicle%.av_", "_av$", "_av_", "_heli", "heli_" }
local function isAerial(record)
    if type(record) ~= "string" then return false end
    for _, p in ipairs(AERIAL) do if record:match(p) then return true end end
    return false
end
NcmAvBoard = { isAerial = isAerial }

local function snap(vid)
    local ok, v = pcall(Open77.vehicles.get, vid)
    return ok and type(v) == "table" and v or nil
end

local function seatOf(pid)
    local ok, s = pcall(Open77.vehicles.getPlayerSeat, pid)
    return ok and type(s) == "table" and s.vehicleId and s or nil
end

--- May this player take this AV? An NCM Machine only by its owner; anything else (an admin gift, a world AV) by anyone
--- standing at it -- the same rule as an unlocked car.
local function mayBoard(pid, vid)
    if NcmVehicleAccess and NcmVehicleAccess.assetForVehicle then
        local okA, assetId = pcall(NcmVehicleAccess.assetForVehicle, vid)
        if okA and assetId then
            local okL, cur = pcall(NcmVehicleAccess.liveAsset, assetId)
            if okL and type(cur) == "table" and cur.pid and tonumber(cur.pid) ~= tonumber(pid) then
                return false, "This AV belongs to another driver."
            end
        end
    end
    return true
end

--- The nearest AV within reach of a player on foot, or nil.
local function posOf(v)
    if type(v.position) == "table" then return v.position end
    if type(v.x) == "number" then return { x = v.x, y = v.y, z = v.z } end
end

local function aerialNear(pid)
    if seatOf(pid) then return nil end
    local ok, list = pcall(Open77.vehicles.nearby, pid, RADIUS_M, { limit = 6 })
    if ok and type(list) == "table" then
        for _, e in ipairs(list) do
            local vid = tonumber(type(e) == "table" and (e.id or e.vehicleId) or e)
            local v = vid and snap(vid)
            if v and isAerial(v.record) then return vid, v end
        end
        return nil
    end
    -- `nearby` refused (older build): walk every registered vehicle
    local okP, p = pcall(Open77.players.get, pid)
    local me = okP and type(p) == "table" and p.position
    local okA, all = pcall(Open77.vehicles.all)
    if not (me and okA and type(all) == "table") then return nil end
    local best, bestV, bestD = nil, nil, RADIUS_M
    for _, e in pairs(all) do
        local vid = tonumber(type(e) == "table" and (e.id or e.vehicleId) or e)
        local v = vid and snap(vid)
        local at = v and posOf(v)
        if at and isAerial(v.record) then
            local d = math.sqrt((at.x - me.x) ^ 2 + (at.y - me.y) ^ 2 + (at.z - me.z) ^ 2)
            if d < bestD then best, bestV, bestD = vid, v, d end
        end
    end
    return best, bestV
end

local function displayName(record)
    local okC, Cat = pcall(NcmCore.get, "data.vehicle_catalogue")
    if okC and Cat and Cat.resolveRecord then
        local okR, m = pcall(Cat.resolveRecord, record)
        if okR and type(m) == "table" and m.displayName then
            return ((m.manufacturer and (m.manufacturer .. " ")) or "") .. m.displayName
        end
    end
    return (record or "AV"):gsub("^Vehicle%.", "")
end

CreateThread(function()
    while true do
        Wait(POLL_MS)
        local okP, players = pcall(Open77.players.all)
        if okP and type(players) == "table" then
            local seen = {}
            for _, p in ipairs(players) do
                local pid = tonumber(p)
                if pid then
                    seen[pid] = true
                    local seat = seatOf(pid)
                    local seatV = seat and snap(seat.vehicleId)
                    local state
                    if seatV and isAerial(seatV.record) then
                        state = { vehicleId = seat.vehicleId, seated = true, name = displayName(seatV.record) }
                    else
                        local vid, v = aerialNear(pid)
                        state = vid and { vehicleId = vid, seated = false, name = displayName(v.record) } or false
                    end
                    local key = state and ((state.seated and "s" or "n") .. tostring(state.vehicleId)) or false
                    if near[pid] ~= key then
                        near[pid] = key
                        pcall(TriggerClientEvent, "ncm:av.near", pid, state or {})
                    end
                end
            end
            for pid in pairs(near) do if not seen[pid] then near[pid], boardedAt[pid] = nil, nil end end
        end
    end
end)

local function tell(pid, msg)
    pcall(Open77.notifications.send, pid, { type = "error", title = "AV", message = msg, icon = "NCM", durationMs = 5000 })
end

RegisterNetEvent("ncm:av.board", function()
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    local vid, v = aerialNear(pid)
    if not vid then return end
    local allowed, why = mayBoard(pid, vid)
    if not allowed then tell(pid, why); return end
    local seat = "driver"
    local okF, free = pcall(Open77.vehicles.seatFree, vid, "driver")
    if okF and free == false then
        seat = nil
        local okS, seats = pcall(Open77.vehicles.freeSeats, vid)
        if okS and type(seats) == "table" and seats[1] then seat = seats[1] end
    end
    if not seat then tell(pid, "Every seat is taken."); return end
    local okW, res, whyW = pcall(Open77.vehicles.warpPlayerIntoVehicle, pid, vid, seat)
    log("board pid=%d vid=%s record=%s seat=%s -> %s %s", pid, tostring(vid), tostring(v.record), tostring(seat),
        tostring(okW and res), tostring(okW and whyW or res))
    if okW and res then boardedAt[pid] = GetGameTimer() else tell(pid, "Could not take the seat: " .. tostring(okW and whyW or res)) end
end)

RegisterNetEvent("ncm:av.leave", function()
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    if boardedAt[pid] and GetGameTimer() - boardedAt[pid] < 1500 then return end
    local seat = seatOf(pid)
    local v = seat and snap(seat.vehicleId)
    if not (v and isAerial(v.record)) then return end
    local ok, res, why = pcall(Open77.vehicles.forcePlayerOutOfVehicle, pid, seat.vehicleId)
    log("leave pid=%d vid=%s -> %s %s", pid, tostring(seat.vehicleId), tostring(ok and res), tostring(ok and why or res))
end)
