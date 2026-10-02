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

local seenState = {}        -- npcId -> last logged stream state (log only on change: first live body, 2026-09-30)

local function attach(npcId, row)
    -- Anchored to the body's canonical standing point, which the server sends: bodies stand still. The entity route
    -- is only a fallback -- live, `Open77.npcs.entity` and `isStreamedIn` both answered false for a body in plain
    -- view (KB-235), which left every Paddock person without a name or a Talk prompt.
    local def = {
        id = "ncm_paddock_" .. tostring(npcId),
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
    }
    if tonumber(row.x) and tonumber(row.y) and tonumber(row.z) then
        def.position = { x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z) }
    else
        local ok, entity = pcall(Open77.npcs.entity, npcId)
        if not ok or not entity then
            if seenState[npcId] ~= "no_entity" then
                seenState[npcId] = "no_entity"
                log("%s (npc %s): no position from the server and no entity: %s", tostring(row.name), tostring(npcId), tostring(entity))
            end
            return
        end
        def.entity = entity
    end
    local res, why = call("create", def)
    if res then
        prompts[npcId] = res.handle
        log("Talk prompt on %s (npc %s) at %s", tostring(row.name), tostring(npcId),
            def.position and ("%.1f,%.1f,%.1f"):format(def.position.x, def.position.y, def.position.z) or "its entity")
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
    local n = 0
    for _ in pairs(next) do n = n + 1 end
    log("bodies: %d from the server", n)
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
            if not bodies[npcId] then drop(npcId) end
        end
        for npcId, row in pairs(bodies) do
            if not prompts[npcId] then attach(npcId, row) end
        end
    end
end)
-- No stop handler: `open77_interactions` sweeps a stopped owner's prompts itself, and an await cannot run there.
