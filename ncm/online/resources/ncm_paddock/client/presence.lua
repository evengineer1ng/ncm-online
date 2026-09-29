-- ncm_paddock / client / presence -- a "Talk" prompt on every Paddock person standing at a garage (phase 4).
--
-- The server says who is standing where (`ncm:paddock.bodies`: npc id, name, role, org). An entity prompt only
-- exists while its NPC is streamed here, so this loop attaches one when the body streams in and drops it when the
-- body goes or streams out. `open77_interactions` draws the marker and the card; choosing it asks the server to
-- talk, and the server re-checks distance with canonical positions (the payload is evidence, not authority).
local function log(fmt, ...)
    local ok, line = pcall(string.format, fmt, ...)
    print("[ncm_paddock/presence] " .. (ok and line or tostring(fmt)))
end

local bodies = {}          -- npcId -> { personId, name, role, org }
local prompts = {}         -- npcId -> handle
local failures = 0

local function call(name, ...)
    local promise, why = Open77.exports.call("open77_interactions", name, ...)
    if not promise then return nil, why end
    local result, err = promise:await()
    if type(result) == "table" and result.ok then return result end
    return nil, err or (type(result) == "table" and result.error) or "refused"
end

local function drop(npcId)
    local h = prompts[npcId]
    prompts[npcId] = nil
    if h then call("remove", h) end
end

local function attach(npcId, row)
    local ok, entity = pcall(Open77.npcs.entity, npcId)
    if not ok or not entity then return end
    local res, why = call("create", {
        id = "ncm_paddock_" .. tostring(npcId),
        entity = entity,
        offset = { x = 0.0, y = 0.0, z = 1.85 },
        distance = 2.6,
        markerDistance = 14.0,
        label = "Talk to " .. tostring(row.name),
        description = tostring(row.role) .. ", " .. tostring(row.org),
        key = "E",
        icon = "TALK",
        color = "#FFD84A",
        event = "ncm:paddock.talk.local",
        data = { personId = row.personId },
    })
    if res then
        prompts[npcId] = res.handle
    else
        failures = failures + 1
        if failures <= 5 then log("prompt for %s refused: %s", tostring(row.name), tostring(why)) end
    end
end

RegisterNetEvent("ncm:paddock.bodies", function(msg)
    local next = {}
    for _, r in ipairs(type(msg) == "table" and msg.rows or {}) do
        local id = tonumber(r.npcId)
        if id then next[id] = r end
    end
    bodies = next
end)

AddEventHandler("ncm:paddock.talk.local", function(context)
    local data = type(context) == "table" and context.data or nil
    if type(data) == "table" and data.personId then TriggerServerEvent("ncm:paddock.talk", { personId = data.personId }) end
end)

CreateThread(function()
    Wait(4000)
    TriggerServerEvent("ncm:paddock.bodies.request")
    while true do
        Wait(1000)
        for npcId in pairs(prompts) do
            local ok, streamed = pcall(Open77.npcs.isStreamedIn, npcId)
            if not bodies[npcId] or not (ok and streamed) then drop(npcId) end
        end
        for npcId, row in pairs(bodies) do
            if not prompts[npcId] then
                local ok, streamed = pcall(Open77.npcs.isStreamedIn, npcId)
                if ok and streamed then attach(npcId, row) end
            end
        end
    end
end)
-- No stop handler: `open77_interactions` sweeps a stopped owner's prompts itself, and an await cannot run there.
