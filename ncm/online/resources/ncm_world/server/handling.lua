-- ncm_world / server / handling -- the per-machine half of Parts, published per player.
--
-- `machine.lua` composes the RECORD channel and publishes it to `GlobalState`, because rain falls on
-- everyone's Quadra at once and a class ruleset is a property of the class. Its own header has said since
-- it shipped:
--
--   > Per-PLAYER facts -- this driver's fitted parts, this driver's wear -- cannot travel this way, because
--   > two drivers of the same model would need different values and the record has only one. ... When Parts
--   > arrive, their per-machine half goes on the command carrier or it waits.
--
-- This is that half. It does not wait any more, and it is not averaged into a record.
--
-- ---------------------------------------------------------------------------------------------------
-- WHY A PLAYER BAG AND NOT GlobalState
-- ---------------------------------------------------------------------------------------------------
--
-- The value IS per-player, so the carrier for it is per-player. `Open77.state.player(id):set(...)` is the
-- same mechanism `ncmPresentation` and `ncmOnboarding` already use, and it has two properties GlobalState
-- does not have here: a joining player's bag is written after they exist, so there is no late-joiner
-- snapshot problem (`KB-30`, and the way `KB-136`'s ceilings half actually failed), and one driver's setup
-- is not shipped to thirty clients that have no use for it.
--
-- ---------------------------------------------------------------------------------------------------
-- WHAT DOES NOT EXIST YET, STATED PLAINLY
-- ---------------------------------------------------------------------------------------------------
--
-- **There is no parts inventory.** Ownership, acquisition, fitting, wear and the garage UI are Parts layer
-- 4 and are not authorised. So this module does not invent one: it holds an in-memory table of what each
-- driver is currently running and exposes `NcmHandling.setParts` for whatever eventually owns that truth to
-- call. Nothing here persists across a restart, and that is correct rather than unfinished -- a persistence
-- schema written before the inventory it stores would be a guess.
--
-- What IS finished is the path: fitted parts -> composed setup -> player bag -> client -> carrier -> force.
-- `/ncm.setup` drives it end to end today so the mechanism can be tested before the economy exists.
local Handling = NcmCore.get("parts.handling")

local function log(fmt, ...) print(("[ncm_world/handling] " .. fmt):format(...)) end
local function now() return math.floor(Open77.time.unix()) end

NcmHandling = NcmHandling or {}

-- playerId -> { parts = {...}, sig = "<signature>" }
local fitted = {}

--- Compose and publish one driver's setup. Cheap; only writes when the applied truth moved.
---
--- `why` is for the log. A publish nobody can explain is how `KB-142` survived three drives.
local function publish(playerId, why)
    local entry = fitted[playerId]
    local parts = entry and entry.parts or {}

    local setup, refusal = Handling.compose({ vehicle = playerId, parts = parts }, { at = now() })
    if not setup then
        -- Named, never silent. A refusal means a part claims a family the live channel cannot express --
        -- suspension asking for a force scale, say -- and a driver quietly getting nothing for a component
        -- they paid for is far worse than a line in the log.
        log("player=%d refused: %s", playerId, tostring(refusal))
        return false, refusal
    end

    local sig = Handling.signature(setup)
    if entry and entry.sig == sig then return true end

    local wire = Handling.wire(setup)
    local ok, err = pcall(function()
        return Open77.state.player(playerId):set("ncmHandling", wire)
    end)
    if not ok then
        -- `KB-136` is the standing reminder that a state-bag write can be REFUSED and look like silence.
        -- This payload is three numbers and a version, so it will not hit the size limit, but the write is
        -- still checked rather than assumed.
        log("player=%d state bag write failed: %s", playerId, tostring(err))
        return false, "state_write_failed"
    end

    if entry then entry.sig = sig end
    log("player=%d (%s): %s", playerId, tostring(why), Handling.explain(setup))
    if #setup.clamped > 0 then
        for _, c in ipairs(setup.clamped) do
            log("player=%d CLAMPED %s: wanted %.3f, applied %.3f",
                playerId, c.lever, c.wanted, c.applied)
        end
    end
    return true
end

--- Set what this driver is running. **The API the parts inventory will call when it exists.**
---
--- `parts` is a list of `{ id = <string>, family = <ontology family>, effect = <multiplier> }`. Passing nil
--- or an empty list is how parts are removed, and it publishes an explicitly inert setup rather than simply
--- going quiet -- the carrier would keep the last one otherwise.
function NcmHandling.setParts(playerId, parts, why)
    local pid = tonumber(playerId) or 0
    if pid <= 0 then return false, "bad_player" end
    fitted[pid] = fitted[pid] or {}
    fitted[pid].parts = parts or {}
    return publish(pid, why or "setParts")
end

--- What this driver is running, for a panel or a command to read back.
function NcmHandling.parts(playerId)
    local entry = fitted[tonumber(playerId) or 0]
    return entry and entry.parts or {}
end

--- Recompose and republish without changing what is fitted. For whatever later makes a setup depend on
--- something other than the parts list -- wear, a class rule, a penalty.
function NcmHandling.recompute(playerId, why)
    local pid = tonumber(playerId) or 0
    if pid <= 0 then return false, "bad_player" end
    if fitted[pid] then fitted[pid].sig = nil end
    return publish(pid, why or "recompute")
end

--- A driver left. Drop the record so a recycled player id cannot inherit somebody else's engine.
AddEventHandler("onPlayerDisconnected", function(playerId)
    local pid = tonumber(playerId) or 0
    if pid > 0 and fitted[pid] then
        fitted[pid] = nil
        log("player=%d disconnected, setup forgotten", pid)
    end
end)

-- ---------------------------------------------------------------------------------------------------
-- `/ncm.setup` -- drive the whole path before the economy exists
-- ---------------------------------------------------------------------------------------------------
--
-- Deliberately a test instrument and named like one. It fits a synthetic part directly, which is exactly
-- what the inventory will do later through `NcmHandling.setParts`, so a PASS here is a PASS of the real
-- mechanism and not of a shortcut around it.
--
--   ncm.setup                      -- what am I running, and what can be felt at all
--   ncm.setup clear                -- remove everything, explicitly
--   ncm.setup <family> <effect>    -- fit one synthetic part, e.g. `ncm.setup power_unit 1.4`
--
-- `effect` is a multiplier, not a balance decision. 18_PARTS_ECOSYSTEM puts component balance out of scope
-- and nothing in this file pretends otherwise.
RegisterNetEvent("ncm:setup", function(family, effect)
    local pid = tonumber(source) or 0
    if pid <= 0 then return end

    -- Chat, the way `main.lua` already answers a player, plus the client event so the answer also lands in
    -- the client log next to the bridge's own lines. `Open77.chat.send` is the proven call here; there is
    -- no `Open77.notify`.
    local function tell(message)
        pcall(Open77.chat.send, pid, "[NCM] " .. message)
        pcall(TriggerClientEvent, "ncm:setup.result", pid, message)
        log("player=%d <- %s", pid, message)
    end

    if family == nil or family == "" then
        local inv = Handling.inventory()
        local live = {}
        for _, entry in ipairs(inv.live) do
            live[#live + 1] = ("%s (%s, %s)"):format(entry.family, entry.lever, entry.evidence)
        end
        local mine = {}
        for _, part in ipairs(NcmHandling.parts(pid)) do
            mine[#mine + 1] = ("%s x%.3f"):format(part.family, part.effect)
        end
        tell(("fitted: %s | felt live: %s | not felt live: %s"):format(
            #mine > 0 and table.concat(mine, ", ") or "nothing",
            table.concat(live, ", "),
            table.concat(inv.notLive, ", ")))
        return
    end

    if family == "clear" then
        NcmHandling.setParts(pid, {}, "ncm.setup clear")
        tell("setup cleared -- every lever explicitly back to inert")
        return
    end

    -- Ask the module, never a hard-coded list here. If a fourth quantity is ever proven, this command
    -- accepts it the moment `parts.handling` does.
    local lever, why = Handling.leverFor(family)
    if not lever then
        tell("cannot: " .. tostring(why))
        return
    end

    local value = tonumber(effect)
    if not value then
        tell(("usage: ncm.setup %s <multiplier>, e.g. 1.25"):format(family))
        return
    end

    local parts = {}
    -- One synthetic part per family: fitting the same family twice replaces rather than stacks, because a
    -- test instrument that quietly compounds is a test instrument that lies.
    for _, part in ipairs(NcmHandling.parts(pid)) do
        if part.family ~= family then parts[#parts + 1] = part end
    end
    parts[#parts + 1] = { id = "test_" .. family, family = family, effect = value }

    local ok, refusal = NcmHandling.setParts(pid, parts, "ncm.setup " .. family)
    if not ok then
        tell("refused: " .. tostring(refusal))
        return
    end
    tell(("fitted test_%s x%.3f -> %s"):format(family, value, lever))
end)

--- A joining driver gets an explicit setup rather than nothing. Without this a fresh client has no
--- `ncmHandling` key at all, and "no key" and "inert" would be indistinguishable to the reader.
---
--- `onPlayerReady` rather than `onPlayerConnected`: the bag belongs to a player who exists, and main.lua
--- already treats this as the moment one does. The short wait is for the same reason `venue.lua` waits --
--- the barrier lifting is not the same as the client being able to receive (`KB-39`, `KB-60`) -- and the
--- client polls its own bag regardless, so a missed write costs a second rather than the feature.
AddEventHandler("onPlayerReady", function(playerId)
    local pid = tonumber(playerId) or 0
    if pid <= 0 then return end
    CreateThread(function()
        Wait(1500)
        NcmHandling.setParts(pid, {}, "joined")
    end)
end)

log("ready -- %d live famil(ies) on the instance channel", #Handling.inventory().live)
