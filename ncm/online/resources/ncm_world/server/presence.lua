-- ncm_world / server / presence -- the city tier of player presence on the map (`L184`, `IDEA-650`).
--
-- One tick, one bounded payload per player, and no decisions: `world.presence` decides what each viewer
-- should see and this file does nothing but read the platform and put it on a wire.
--
-- **WHY THE SERVER AT ALL, when the client can already see its neighbours.** A client only knows the
-- players streamed around it, which is a couple of hundred metres. The whole point of this feature is the
-- other five kilometres -- somebody in Watson while you are in Santo Domingo -- and `GetPlayersPositions`
-- (`Open77.players.positions()`) is the only thing that knows that. It answers
-- `{ [playerId] = { x, y, z, bucket } }` for every player whose snapshot is younger than two seconds, so
-- one call replaces a loop over the roster and there is nothing to poll per player.
--
-- **NO NEW PERMISSION.** `positions()` checks none in its handler, and the client half needs
-- `ui.vanilla.map`, which this resource has declared since the `/ncm.gps` waypoint. Nothing here is
-- invasive and nothing duplicates a platform system -- OPEN//77's own freeroam gamemode draws location and
-- spawn blips and has never drawn a player.
--
-- **WHAT THIS FILE DELIBERATELY DOES NOT KNOW.** Whether the viewer is in a live session. Suppression
-- during a race is the CLIENT's business (`client/players_map.lua`), because `NcmClientRaceActive` is
-- already NCM's convention for "yield, the player is racing" -- `calendar.lua` and `race_builder.lua` both
-- read it. That makes the racing rule a fairness convention rather than an enforced boundary: the rows
-- still arrive, and a modified client could draw them. Enforcing it server-side means this resource
-- learning session membership from `ncm_league`, which is a cross-resource dependency this feature does not
-- justify on its own (`IDEA-660`).
NcmPresence = {}

local Core = NcmCore
local P = Core.get("world.presence")
local Json = Core.get("vocabulary.json")

local stats = { ticks = 0, sent = 0, rows = 0, bytes = 0, lastTick = 0, unlocated = 0, dropped = 0 }
NcmPresence.stats = stats

local function log(fmt, ...)
    print(("[ncm_world/presence] " .. fmt):format(...))
end

-- Read tunables AT THE POINT OF USE, exactly as `server/ambient.lua` does: `NcmIdentity.settings` is a live
-- proxy behind a metatable, so a local captured at load would freeze the value and make Warden's panel a
-- liar. The declarations themselves live in `server/identity.lua`, because a second
-- `Open77.tunables.declare` in this VM would REPLACE that block rather than extend it.
local function tune(key, fallback)
    local s = NcmIdentity and NcmIdentity.settings
    if not s then return fallback end
    local ok, v = pcall(function() return s[key] end)
    if not ok or v == nil then return fallback end
    return v
end

local function settings()
    return P.settings({
        tickSeconds  = tonumber(tune("presenceTickSeconds", 5)),
        maxPins      = tonumber(tune("presenceMaxPins", 24)),
        budgetBytes  = tonumber(tune("presenceBudgetBytes", 3072)),
        moveEpsilonM = tonumber(tune("presenceMoveEpsilonM", 3)),
        nameBytes    = tonumber(tune("presenceNameBytes", 24)),
    })
end

local function enabled() return tune("presenceEnabled", true) and true or false end

local function encode(value)
    if json and json.encode then
        local ok, text = pcall(json.encode, value)
        if ok and type(text) == "string" then return text end
    end
    return Json.encode(value)
end

--- The real encoded size of one row. The budget has to be MEASURED bytes, not a row count: four outages
--- share the other shape (`KB-59`, `KB-86`, `KB-153`, `KB-160`, `IDEA-595`).
local function measure(row)
    local ok, text = pcall(encode, row)
    if not ok or type(text) ~= "string" then return -1 end
    return #text
end

--- The name on somebody else's map. The same source `identity.lua` trusts for a Driver's name, so presence
--- introduces no second one; `world.presence` sanitizes and cuts it, because this is player-supplied text
--- about to be drawn on another player's screen. `Open77.players.name` is the spelling resources are told to
--- prefer; `GetPlayerName` is its low-level form and is kept as the fallback.
local function nameFor(playerId)
    local ok, name = pcall(Open77.players.name, playerId)
    if ok and type(name) == "string" and name ~= "" then return name end
    local okLegacy, legacy = pcall(GetPlayerName, playerId)
    if okLegacy and type(legacy) == "string" then return legacy end
    return nil
end

local function roster()
    local ok, all = pcall(Open77.players.all)
    if not ok or type(all) ~= "table" then return {} end
    return all
end

--- One pass: read every position once, then answer each viewer from that one snapshot.
function NcmPresence.tick()
    local set = settings()
    local ok, positions = pcall(Open77.players.positions)
    if not ok or type(positions) ~= "table" then
        -- A missing API and a refused call are indistinguishable unless the reason is read, which is the
        -- lesson `machine.lua` learned about `world.environment`. Say which, once per tick at most.
        log("players.positions unavailable: %s", tostring(positions))
        return false
    end

    stats.ticks = stats.ticks + 1
    local okNow, unix = pcall(Open77.time.unix)
    stats.lastTick = okNow and tonumber(unix) or 0
    for _, raw in ipairs(roster()) do
        local playerId = tonumber(raw)
        if playerId then
            local rows, note = P.rowsFor(playerId, positions, {
                settings = set, measure = measure, nameFor = nameFor,
            })
            if note.reason == "viewer_unlocated" then
                -- Loading, respawning, or otherwise not in the world yet. Sending an empty payload still
                -- matters: it is how a client that held pins learns to drop them.
                stats.unlocated = stats.unlocated + 1
            end
            stats.sent = stats.sent + 1
            stats.rows = stats.rows + note.sent
            stats.bytes = stats.bytes + (note.bytes or 0)
            stats.dropped = stats.dropped + (note.droppedForCount or 0) + (note.droppedForBytes or 0)
            pcall(TriggerClientEvent, "ncm:presence.city", playerId, {
                schema = P.SCHEMA,
                rows = rows,
                moveEpsilonM = set.moveEpsilonM,
            })
        end
    end
    return true
end

--- `/ncm.presence` on the server console: what the last tick actually did. Presence is the kind of feature
--- that looks broken from one client and fine from another, and the difference is almost always a bucket.
RegisterCommand("ncm.presence", function(source)
    if tonumber(source) ~= 0 then return end   -- console only; it says where every player is
    local set = settings()
    log("enabled=%s tick=%ds maxPins=%d budget=%dB | ticks=%d payloads=%d rows=%d bytes=%d dropped=%d unlocated=%d",
        tostring(enabled()), set.tickSeconds, set.maxPins, set.budgetBytes,
        stats.ticks, stats.sent, stats.rows, stats.bytes, stats.dropped, stats.unlocated)
    local ok, positions = pcall(Open77.players.positions)
    if ok and type(positions) == "table" then
        for id, pos in pairs(positions) do
            log("  player %s bucket %s at %.0f %.0f", tostring(id), tostring(pos.bucket or 0),
                tonumber(pos.x) or 0, tonumber(pos.y) or 0)
        end
    end
end, true)

CreateThread(function()
    -- Presence is not urgent on join: the first tick can wait for identity and for the client's map layer
    -- to exist, and a pin that appears five seconds late costs nothing.
    Wait(10000)
    log("city presence service up (tick %ds, %d pins max)", settings().tickSeconds, settings().maxPins)
    while true do
        local set = settings()
        if enabled() then
            local okTick, err = pcall(NcmPresence.tick)
            if not okTick then log("tick raised: %s", tostring(err)) end
        end
        -- Re-read the interval every loop so a live tunable change takes effect without a restart.
        Wait(math.floor(set.tickSeconds * 1000))
    end
end)
