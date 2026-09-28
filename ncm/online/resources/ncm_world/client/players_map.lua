-- ncm_world / client / players_map -- other drivers, on your own map and minimap (`L184`, `IDEA-650`).
--
-- **Why.** NCM Online's honest first impression is an empty city: a tester spawns, drives, and has no way to
-- know whether anybody else is on the server at all. Presence answers that without a single word of UI -- a
-- pin in Watson while you are in Santo Domingo is the whole feature.
--
-- **One blip per driver, moved and never recreated.** The platform allows 128 blips per resource and 512 per
-- client, and `landmarks.lua` already spends one per waypointable node, so a layer that recreated its pins
-- every tick would be a slow leak toward a quota nothing else could then use. `world.presence.reconcile`
-- decides create/move/retitle/remove; this file only performs it.
--
-- **The map and the minimap are the same pin, and that is not a choice we have.** `Open77.blips` draws to
-- HUD, minimap and world map together. There is no per-surface visibility in this engine: `range` gates all
-- three at once and FiveM's `shortRange` is refused by name (`unsupported_option:shortRange`). So "on the
-- map but not the minimap" was never available, and the answer to clutter is the toggle below -- the same
-- answer `/ncm.nodes` gives for landmarks.
--
-- **Suppressed while you are racing, by ruling** (`IDEA-654`). Live pins on the drivers you are racing are a
-- competitive aid -- a rival's exact position through a building is something no mirror gives you -- so the
-- whole layer stands down for the duration of a session. `NcmClientRaceActive` is already NCM's convention
-- for this and `calendar.lua` and `race_builder.lua` both read it. Being client-side, it is a fairness
-- convention rather than an enforced boundary; the honest note is in `server/presence.lua`.
--
-- **The sprite is the one unverified thing here, deliberately.** `remote_player` resolves to
-- `CPO_RemotePlayerVariant`, and the platform's own guide warns that the `CPO_*` variants come from a
-- dormant multiplayer HUD and "must be checked visually in the server's context", and separately that a
-- HUD-only variant can be absent from the fullscreen map. So the default is `vehicle`, which the guide names
-- as map-capable, and the unverified variant sits behind a tunable so it can be looked at on a live client
-- before it is trusted (`IDEA-653`). Per-blip colour is not used at all: `setColor` is unreleased at the
-- documentation build pin, so it is probed and forgotten rather than depended on.
local Core = NcmCore
local P = Core.get("world.presence")

local pins = {}            -- playerId(number) -> { handle, x, y, z, n }
local shown = true         -- the player's own choice, this session
local supported = true     -- false once this build has proved it has no usable blips
local suppressed = false   -- true while a race is live, so the field is not on the map
local lastNote = nil

local function log(fmt, ...)
    print(("[ncm_world/client/players_map] " .. fmt):format(...))
end

local function sprite()
    -- A tunable would be a server decision about a client's art; this is deliberately a local constant with
    -- one alternative, switched by command, so a live visual check costs nobody a restart.
    return NcmPresenceSprite or "vehicle"
end

local function title(row)
    return row.n and tostring(row.n) or "NCM driver"
end

local function drop(id)
    local pin = pins[id]
    if not pin then return end
    if pin.handle then pcall(Open77.blips.remove, pin.handle) end
    pins[id] = nil
end

local function clear(why)
    local n = 0
    for id in pairs(pins) do drop(id); n = n + 1 end
    if n > 0 then log("%d pin(s) cleared (%s)", n, tostring(why)) end
end

local function create(row)
    local ok, handle, reason = pcall(Open77.blips.create, {
        position = { x = row.x, y = row.y, z = row.z },
        sprite = sprite(),
        title = title(row),
        description = "Another NCM driver, seen from the city network. Position is a few seconds old.",
        -- No `range`: the point of the city tier is the driver who is NOT near you. No `routable`: this is
        -- presence, not navigation, and `client/nav.lua` owns the one blip allowed to steer the GPS.
    })
    if not ok or handle == nil then
        -- A build with no blip creation has no presence layer; it is not worth a retry loop, and saying so
        -- once is the difference between a missing feature and a silent one.
        supported = false
        log("blip creation refused (%s); presence layer off for this session",
            tostring((not ok) and handle or reason))
        clear("unsupported")
        return
    end
    pins[tonumber(row.i)] = { handle = handle, x = row.x, y = row.y, z = row.z, n = row.n }
end

local function apply(payload)
    if not supported then return end
    if type(payload) ~= "table" or tonumber(payload.schema) ~= P.SCHEMA then
        -- A schema we cannot read is a server ahead of this client. Drop what we hold rather than leaving
        -- stale pins standing in a city that has moved on.
        clear("schema")
        return
    end
    if suppressed or not shown then clear(suppressed and "racing" or "hidden"); return end

    local plan = P.reconcile(pins, payload.rows, { moveEpsilonM = payload.moveEpsilonM })
    for _, id in ipairs(plan.remove) do drop(id) end
    for _, row in ipairs(plan.create) do create(row) end
    for _, row in ipairs(plan.move) do
        local pin = pins[tonumber(row.i)]
        if pin and pin.handle then
            local ok, moved = pcall(Open77.blips.setPosition, pin.handle, { x = row.x, y = row.y, z = row.z })
            if ok and moved then
                pin.x, pin.y, pin.z = row.x, row.y, row.z
            else
                -- A handle the platform no longer honours is worse than no pin: it would sit at a position
                -- that never updates again. Drop it and let the next tick create a fresh one.
                log("setPosition refused for player %s (%s); dropping the pin", tostring(row.i), tostring(moved))
                drop(tonumber(row.i))
            end
        end
    end
    for _, row in ipairs(plan.retitle) do
        local pin = pins[tonumber(row.i)]
        if pin and pin.handle and pcall(Open77.blips.setTitle, pin.handle, title(row)) then pin.n = row.n end
    end
    lastNote = { rows = #(payload.rows or {}), pins = 0 }
    for _ in pairs(pins) do lastNote.pins = lastNote.pins + 1 end
end

RegisterNetEvent("ncm:presence.city", apply)

-- A live race stands the layer down, and ending one brings it back. Polled rather than event-driven because
-- `NcmClientRaceActive` is a plain global that three files already read; subscribing to a race lifecycle we
-- do not own would be a second source of truth about the same fact.
CreateThread(function()
    while true do
        Wait(1000)
        local racing = NcmClientRaceActive and true or false
        if racing ~= suppressed then
            suppressed = racing
            if suppressed then clear("race started") end
            log("presence %s (%s)", suppressed and "suppressed" or "resumed", racing and "racing" or "race over")
        end
    end
end)

--- Off is not remembered between sessions, on purpose and for the same reason `/ncm.nodes` does not remember
--- it: the default is the useful one, and a toggle that quietly stays off becomes a support question later.
RegisterCommand("ncm.players", function()
    shown = not shown
    if not shown then clear("toggled off") end
    local message = shown
        and "Other drivers are on your map. /ncm.players to hide them."
        or "Other drivers hidden. /ncm.players to show them again."
    log("%s", message)
    pcall(function()
        Open77.exports.call("open77_notifications", "show", { id = "ncm_players", replace = true, type = "info",
            title = "NCM", message = message, icon = "NCM", durationMs = 5000 })
    end)
end, false)

--- The live visual check the blips guide asks for: `CPO_RemotePlayerVariant` comes from a dormant
--- multiplayer HUD, so somebody has to look at it on both surfaces before it can be the default (`IDEA-653`).
RegisterCommand("ncm.playersprite", function(_, args)
    local want = args and args[1]
    NcmPresenceSprite = (type(want) == "string" and want ~= "") and want or
        ((NcmPresenceSprite == "remote_player") and "vehicle" or "remote_player")
    clear("sprite change")
    log("presence sprite is now %s; pins are redrawn on the next tick (about 5 s)", sprite())
end, false)

RegisterCommand("ncm.presence", function()
    log("shown=%s suppressed=%s supported=%s sprite=%s rows=%s pins=%s",
        tostring(shown), tostring(suppressed), tostring(supported), sprite(),
        tostring(lastNote and lastNote.rows), tostring(lastNote and lastNote.pins))
end, false)

-- Leaving the world invalidates every handle, and the platform cleans blips up itself; dropping our records
-- keeps the next world from moving pins that no longer exist.
AddEventHandler("open77:worldReady", function() pins = {} end)

AddEventHandler("onClientResourceStop", function(name)
    if name == GetCurrentResourceName() then clear("resource stop") end
end)
