-- ncm_world / server / fx_relay -- NCM FX for everyone watching (core presentation.fx).
--
-- A client whose Machine is doing something visible (a plume, a stroke, a drive) sends its compact emitter state
-- (`presentation.fx.pack`) a few times a second; this relays it to every other player, who draws it on that car.
-- Presentation only: nothing here is trusted or stored, and a sender is rate-limited and size-capped.
local MIN_MS, MAX_BYTES = 150, 6000
local last = {}

local function log(fmt, ...) print(("[ncm_world/fx_relay] " .. fmt):format(...)) end

RegisterNetEvent("ncm:fx.state", function(p)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(p) ~= "table" or type(p.vid) ~= "string" and type(p.vid) ~= "number" then return end
    local t = GetGameTimer()
    if t - (last[pid] or 0) < MIN_MS then return end
    last[pid] = t
    -- KB-452: tables travel as a JSON string (the serializer dropped large numbers); relayed as received
    local blob = type(p.json) == "string" and p.json or nil
    if not blob or #blob > MAX_BYTES then return end
    TriggerClientEvent("ncm:fx.state", -1, { from = pid, vid = tostring(p.vid), owner = tostring(p.owner or pid), json = blob })
end)

AddEventHandler("playerDropped", function() last[tonumber(source) or 0] = nil end)
log("ready")
