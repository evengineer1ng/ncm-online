-- NCM starter clothing bridge.
--
-- OPEN//77 owns attachment, replication and durable presentation state. NCM only supplies a conservative
-- first outfit when those authoritative equipment records report an empty everyday kit. Existing choices are
-- never replaced: each missing dignity slot is filled independently and the platform validates/persists it.

local STARTER = {
    InnerChest = "Items.Q000_StreetKid_TShirt",
    Legs = "Items.Q000_StreetKid_Pants",
    Feet = "Items.Q000_StreetKid_Shoes",
}

local attempted = false

local function log(fmt, ...)
    print(("[ncm_world/client/apparel] " .. fmt):format(...))
end

RegisterNetEvent("open77:equipment:self", function(equipment)
    if attempted or type(equipment) ~= "table" then return end
    attempted = true
    local granted = {}
    for slot, record in pairs(STARTER) do
        if equipment[slot] == nil or equipment[slot] == false then
            TriggerServerEvent("open77:equipment:slot", slot, record)
            granted[#granted + 1] = slot
        end
    end
    if #granted > 0 then
        table.sort(granted)
        log("starter clothing requested for empty slot(s): %s", table.concat(granted, ","))
    else
        log("saved clothing present; starter grant not needed")
    end
end)

