-- ncm_world / server / vitals -- passive health regeneration (`KB-180`).
--
-- **WHY THIS EXISTS.** Health on OPEN//77 is not the engine's: it is a server damage ledger, in absolute
-- points out of `maxHealth` (100 by default), and the engine's own out-of-combat regeneration does not feed
-- it. The ledger regenerates at a per-player `DefaultRegenPerSecond` that the owner observed to be zero in
-- practice (the constant's value was not read out of the binary). The official freeroam gamemode is the
-- resource that normally sets it -- and even it ships `regenPerSecond = 0.0`, "0 disables". NCM does not load
-- freeroam, so nobody ever set it, and every kerb, wall and pedestrian a driver hit was permanent until they
-- died or left.
--
-- **WHY A SWEEP AND NOT ONLY A JOIN HOOK.** The rate is per player and nothing documents whether a respawn
-- or a revive resets it; freeroam's own PvP module re-applies it after every placement, which says the
-- authors did not trust it to survive either. A sweep re-asserts the tunable for everyone at a slow cadence,
-- which covers respawns, reloads and a live tunable change with one mechanism and no guessed event names.
-- The platform throttles its own regen publishing (`RegenPublishIntervalMilliseconds`), so a reassert every
-- `SWEEP_S` for a handful of players is not wire traffic worth avoiding.
--
-- Needs `players.stats.apply`. A refusal is logged ONCE per reason, by name, because a missing permission and
-- a missing API are otherwise indistinguishable (the lesson `ambient.lua` and `machine.lua` both carry).

local SWEEP_S = 20

local function log(fmt, ...)
    print(("[ncm_world/vitals] " .. fmt):format(...))
end

local function rate()
    local s = NcmIdentity and NcmIdentity.settings
    local ok, v = pcall(function() return s and s.playerRegenPerSecond end)
    v = ok and tonumber(v) or nil
    if v == nil or v < 0 then return 2.0 end
    return v
end

local refusedOnce = {}

local function apply(playerId, why)
    local id = tonumber(playerId) or 0
    if id <= 0 then return end
    local perSecond = rate()
    local ok, applied, reason = pcall(Open77.players.setRegen, id, perSecond)
    -- Only an explicit `false` (or a throw) is a refusal: freeroam ignores this call's return, so no caller
    -- has ever pinned what a success looks like, and a nil must not be reported as a failure.
    if not ok or applied == false then
        local key = tostring(ok and reason or applied)
        if not refusedOnce[key] then
            refusedOnce[key] = true
            log("setRegen(player=%d, %.2f) refused (%s): %s  (needs the `players.stats.apply` permission)",
                id, perSecond, why, key)
        end
        return
    end
    if why ~= "sweep" then log("player=%d health regen %.2f hp/s (%s)", id, perSecond, why) end
end

AddEventHandler("onPlayerConnected", function(playerId) apply(playerId, "connect") end)

AddEventHandler("onResourceStart", function(name)
    if name ~= GetCurrentResourceName() then return end
    local ok, all = pcall(Open77.players.all)
    if ok and type(all) == "table" then
        for _, pid in ipairs(all) do apply(pid, "adopt") end
    end
    CreateThread(function()
        while true do
            Wait(SWEEP_S * 1000)
            local okAll, players = pcall(Open77.players.all)
            if okAll and type(players) == "table" then
                for _, pid in ipairs(players) do apply(pid, "sweep") end
            end
        end
    end)
end)

-- `IDEA-677` probe, console only: `ncm.wanted <playerId> <0..5>`. Sets the player's NCPD heat through the
-- platform's prevention policy (`open77_prevention` applies it to that player's own `PreventionSystem`), so a
-- live test can answer "will units spawn and chase at all" before anyone designs a trigger. It is not a
-- feature: nothing in NCM raises heat on its own. Police summoned this way are LOCAL to that player's game.
RegisterCommand("ncm.wanted", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local id, level = tonumber(args and args[1]), tonumber(args and args[2])
    level = level and math.floor(level) or nil
    if not id or not level or level < 0 or level > 5 then
        log("usage: ncm.wanted <playerId> <0..5>   (0 clears)")
        return
    end
    local ok, result, reason = pcall(Open77.players.setWanted, id, level)
    if not ok or result == nil or result == false then
        log("setWanted(player=%d, %d) refused: %s", id, level, tostring(ok and reason or result))
        return
    end
    local okGet, policy = pcall(Open77.players.getWanted, id)
    local shown = policy
    if okGet and type(policy) == "table" then
        local parts = {}
        for k, v in pairs(policy) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
        table.sort(parts)
        shown = "{" .. table.concat(parts, " ") .. "}"
    end
    log("player=%d wanted -> %d; server policy now %s", id, level, tostring(shown))
end, false)
