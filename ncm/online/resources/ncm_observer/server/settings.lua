-- ncm_observer / server / settings -- the ONE tunables declaration for this resource (a second declare REPLACES the
-- first). `apply` accepts only live / next_round / next_match (KB-324).
ObserverSettings = {}

local ok, settings = pcall(Open77.tunables.declare, {
    observerEnabled = { value = true, type = "boolean", apply = "live" },
    -- user ids (GetPlayerIdentifier) allowed to enter from their own client, comma-separated; "*" = everyone.
    -- Empty = the server console only. Never a default-on: L307 O-4.
    observerAllow = { value = "", type = "string", apply = "live" },
    directorTickSec = { value = 2, type = "integer", min = 1, max = 30, unit = "s", apply = "live" },
    minShotSec = { value = 12, type = "integer", min = 2, max = 300, unit = "s", apply = "live" },
    maxShotSec = { value = 45, type = "integer", min = 5, max = 900, unit = "s", apply = "live" },
    battleGapMs = { value = 1500, type = "integer", min = 100, max = 10000, unit = "ms", apply = "live" },
    -- a server teleport (it settles streaming) when the target is this far from the ghost; nearer, the client hops
    -- must stay below the client's 240 m ask (client/observer.lua), or a ghost 240-jumpM m away is never moved
    jumpM = { value = 200, type = "integer", min = 100, max = 230, unit = "m", apply = "live" },
})
if not ok then print("[ncm_observer/settings] tunables.declare FAILED: " .. tostring(settings)) settings = nil end

function ObserverSettings.get(key, fallback)
    if not settings then return fallback end
    local ok2, v = pcall(function() return settings[key] end)
    if ok2 and v ~= nil then return v end
    return fallback
end
