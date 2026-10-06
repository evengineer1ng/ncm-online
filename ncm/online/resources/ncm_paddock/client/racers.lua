-- ncm_paddock / client / racers -- every racer on the map and minimap while racing happens (owner, 2026-10-04).
--
-- The server sends every running race's cars every 2 s (`ncm:paddock:racers`, server/racers.lua). Each car is one
-- vanilla map pin with a declared SVG icon:
--   racer_<tier>.svg  an NPC in a race elsewhere in the city (street orange, regional cyan, pro violet, premier gold)
--   racer_human.svg   another player racing
--   racer_rival.svg   anyone in YOUR race (green, larger), so your field stands out from the city's other races
-- Your own car is not drawn: the minimap already shows you. A pin that stopped answering (a world reload kills pins
-- made before it, KB-203) is recreated on the next update. Fullscreen map: the title is the driver, the
-- description their place and series.
local function log(fmt, ...) print(("[ncm_paddock/racers] " .. fmt):format(...)) end

local MAX_PINS = 120
local pins = {}               -- key -> { id, icon, desc }
local warned = false
local iconRefused = 0

local function me()
    local ok, id = pcall(Open77.players.localId)
    return ok and tonumber(id) or nil
end

local function remove(key)
    local pin = pins[key]
    if pin and pin.id then pcall(Open77.blips.remove, pin.id) end
    pins[key] = nil
end

local function create(key, car, icon, size, title, desc)
    local ok, id, why = pcall(Open77.blips.create, {
        position = { x = car.x, y = car.y, z = car.z or 0 }, sprite = "vendor", title = title, description = desc,
    })
    if not ok or not id then
        if not warned then warned = true; log("pin refused: %s", tostring((not ok) and id or why)) end
        return nil
    end
    -- the native sprite stays if the SVG is refused (an icon budget, an old client): a pin is better than none
    local okI, applied, whyI = pcall(Open77.blips.setIcon, id, { asset = icon, size = size })
    if not (okI and applied) then
        iconRefused = iconRefused + 1
        if iconRefused == 1 or iconRefused % 50 == 0 then log("icon refused (%d so far): %s", iconRefused, tostring(okI and whyI or applied)) end
    end
    pins[key] = { id = id, icon = icon, desc = desc }
    return pins[key]
end

RegisterNetEvent("ncm:paddock:racers", function(snap)
    if type(snap) ~= "table" or type(snap.races) ~= "table" then return end
    local self = me()
    local mine
    for _, race in ipairs(snap.races) do
        for _, car in ipairs(race.cars or {}) do if self and tonumber(car.pid) == self then mine = race.r end end
    end
    -- your race first, so the cap never drops your own field
    table.sort(snap.races, function(a, b) return (a.r == mine) and b.r ~= mine end)
    local seen, count = {}, 0
    for _, race in ipairs(snap.races) do
        local ours = race.r == mine
        for _, car in ipairs(race.cars or {}) do
            if not (self and tonumber(car.pid) == self) and count < MAX_PINS then
                count = count + 1
                local key = race.r .. "|" .. tostring(car.k)
                seen[key] = true
                local icon = ours and "icons/racer_rival.svg" or (car.h and "icons/racer_human.svg") or ("icons/racer_" .. tostring(race.tier) .. ".svg")
                local size = ours and 26 or 18
                local desc = ("%s%s"):format(car.p and ("P" .. car.p .. " · ") or "", tostring(race.series or "a race"))
                local pin = pins[key]
                if pin and pin.icon ~= icon then remove(key); pin = nil end
                if pin then
                    local okP, moved = pcall(Open77.blips.setPosition, pin.id, { x = car.x, y = car.y, z = car.z or 0 })
                    if not okP or moved == false then remove(key); pin = nil
                    elseif pin.desc ~= desc then pcall(Open77.blips.setDescription, pin.id, desc); pin.desc = desc end
                end
                if not pin then create(key, car, icon, size, tostring(car.n or "Racer"), desc) end
            end
        end
    end
    for key in pairs(pins) do if not seen[key] then remove(key) end end
end)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end
    for key in pairs(pins) do remove(key) end
end)
