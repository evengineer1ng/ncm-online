-- ncm_world / server / handling -- the per-machine half of Parts, delivered to its current operator.
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
-- WHY ASSET TRUTH THROUGH A PLAYER BAG
-- ---------------------------------------------------------------------------------------------------
--
-- The truth is keyed by permanent `assetId`; the player bag is only the delivery route to whoever currently
-- controls that Machine. `vehicle_access.lua` proves `assetId -> live vehicleId -> driverPlayerId`. This file
-- never infers identity from player id, record, proximity or speed. A seat transfer moves delivery without
-- moving the fitted setup, and no proven binding publishes an explicit inert/unbound envelope.
--
-- ---------------------------------------------------------------------------------------------------
-- WHAT DOES NOT EXIST YET, STATED PLAINLY
-- ---------------------------------------------------------------------------------------------------
--
-- **There is no parts inventory.** Ownership, acquisition, fitting, wear and the garage UI are Parts layer
-- 4 and are not authorised. So this module does not invent one: it holds an in-memory table of what each
-- asset is currently running and exposes `NcmHandling.setParts` for whatever eventually owns that truth to
-- call. Nothing here persists across a restart, and that is correct rather than unfinished -- a persistence
-- schema written before the inventory it stores would be a guess.
--
-- What IS finished is the path: fitted parts -> composed setup -> player bag -> client -> carrier -> force.
-- `/ncm.setup` drives it end to end today so the mechanism can be tested before the economy exists.
local Handling = NcmCore.get("parts.handling")

local function log(fmt, ...) print(("[ncm_world/handling] " .. fmt):format(...)) end
local function now() return math.floor(Open77.time.unix()) end

NcmHandling = NcmHandling or {}

local WIRE_VERSION = 2
-- Permanent Machine truth (in memory until Parts inventory/persistence exists):
-- assetId -> { parts = {...}, setup = composed setup }
local fitted = {}
-- Ephemeral delivery truth: playerId -> { assetId, vehicleId, sig }
local delivered = {}

local function validAssetId(assetId)
    return type(assetId) == "string" and #assetId > 0
end

local function inertLevers()
    return Handling.wire(Handling.clear(nil, { at = now() })).levers
end

local function write(playerId, wire, sig, why)
    local current = delivered[playerId]
    if current and current.sig == sig then return true end
    local ok, accepted = pcall(function()
        return Open77.state.player(playerId):set("ncmHandling", wire)
    end)
    if not ok or accepted == false then
        log("player=%d state bag write failed: %s", playerId, tostring(ok and accepted or accepted))
        return false, "state_write_failed"
    end
    delivered[playerId] = {
        assetId = wire.assetId, vehicleId = wire.vehicleId, bound = wire.bound, sig = sig,
    }
    log("player=%d delivery=%s asset=%s vehicle=%s (%s)", playerId,
        wire.bound and "BOUND" or "INERT", tostring(wire.assetId or "-"),
        tostring(wire.vehicleId or "-"), tostring(why))
    return true
end

--- Explicitly withdraw the native target and restore inert levers. Going silent is unsafe: the Carrier
--- retains its last setup until told otherwise.
local function publishUnbound(playerId, why, force)
    local pid = tonumber(playerId) or 0
    if pid <= 0 then return false, "bad_player" end
    if force and delivered[pid] then delivered[pid].sig = nil end
    return write(pid, { v = WIRE_VERSION, bound = false, levers = inertLevers() },
        "unbound", why or "unbound")
end

--- Publish the setup belonging to the exact asset/vehicle pair proven by vehicle_access.
local function publishBound(playerId, binding, why, force)
    local pid = tonumber(playerId) or 0
    if pid <= 0 or type(binding) ~= "table" or not validAssetId(binding.assetId)
        or binding.vehicleId == nil then
        return publishUnbound(pid, why or "bad binding", force)
    end

    local entry = fitted[binding.assetId]
    local setup = entry and entry.setup or Handling.clear(binding.assetId, { at = now() })
    local wire = Handling.wire(setup)
    wire.v = WIRE_VERSION
    wire.bound = true
    wire.assetId = binding.assetId
    wire.vehicleId = binding.vehicleId
    wire.authorityEpoch = binding.authorityEpoch
    wire.driverPlayerId = binding.driverPlayerId
    wire.configurationRevision = entry and entry.revision or 0
    wire.configurationSignature = Handling.signature(setup)
    local sig = table.concat({ "bound", binding.assetId, tostring(binding.vehicleId),
        tostring(binding.authorityEpoch), tostring(wire.configurationRevision),
        wire.configurationSignature }, "|")
    if force and delivered[pid] then delivered[pid].sig = nil end
    -- `write()` suppresses an unchanged payload, and this must suppress with it. **It did not, and the
    -- production log took two identical lines per second per driver, for as long as anyone sat in a car.**
    -- A heartbeat is not news; only a change is.
    local changed = not (delivered[pid] and delivered[pid].sig == sig)
    local ok, refusal = write(pid, wire, sig, why or "bound")
    if not ok then return false, refusal end
    if not changed then return true end

    log("asset=%s player=%d: %s", binding.assetId, pid, Handling.explain(setup))
    if setup.clamped and #setup.clamped > 0 then
        for _, c in ipairs(setup.clamped) do
            log("asset=%s CLAMPED %s: wanted %.3f, applied %.3f",
                binding.assetId, c.lever, c.wanted, c.applied)
        end
    end
    -- `L156`. A coupling ceiling is not a clamp: the clamp is the carrier's hard bound, this is one lever
    -- constraining another. Logged separately and by name, because "your engine is worth 1.25 of 2.00"
    -- and "your engine was cut to the maximum the plugin allows" are different facts about a car.
    if setup.limited and #setup.limited > 0 then
        for _, l in ipairs(setup.limited) do
            log("asset=%s LIMITED %s: wanted %.3f, applied %.3f by %s (%s=%.3f)",
                binding.assetId, l.lever, l.wanted, l.applied, l.coupling, l.from, l.fromValue)
        end
    end
    return true
end

--- Reconcile a delivery route from authoritative live-vehicle and driver state.
function NcmHandling.reconcilePlayer(playerId, why, force)
    local pid = tonumber(playerId) or 0
    if pid <= 0 then return false, "bad_player" end
    local binding, refusal
    if NcmVehicleAccess and NcmVehicleAccess.bindingForAuthority then
        binding, refusal = NcmVehicleAccess.bindingForAuthority(pid)
    else
        refusal = "vehicle_access_unavailable"
    end
    if not binding then return publishUnbound(pid, why or refusal, force) end
    return publishBound(pid, binding, why, force)
end

--- Set what one physical Machine is running. **This is the API a future Parts inventory will call.**
---
--- `parts` is a list of `{ id, family, effect }`. It is deliberately not persisted here. Validation occurs
--- before replacing the previous setup, so one malformed component cannot poison an asset and strand its
--- current operator on the last native state.
function NcmHandling.setParts(assetId, parts, why)
    if not validAssetId(assetId) then return false, "bad_asset" end
    parts = parts or {}
    if type(parts) ~= "table" then return false, "parts must be a table" end
    local setup, refusal = Handling.compose({ vehicle = assetId, parts = parts }, { at = now() })
    if not setup then
        log("asset=%s refused: %s", assetId, tostring(refusal))
        return false, refusal
    end
    local previous = fitted[assetId]
    fitted[assetId] = { parts = parts, setup = setup, revision = (previous and previous.revision or 0) + 1 }

    -- A parked asset can be configured without inventing an operator. If it is being driven, publish to
    -- the proven current driver rather than to its owner or to whoever invoked the change.
    if NcmVehicleAccess and NcmVehicleAccess.operatorForAsset then
        local pid, binding = NcmVehicleAccess.operatorForAsset(assetId)
        if pid and binding then return publishBound(pid, binding, why or "setParts", true) end
    end
    log("asset=%s stored in memory (%s); no proven current operator", assetId, tostring(why or "setParts"))
    return true
end

function NcmHandling.parts(assetId)
    local entry = validAssetId(assetId) and fitted[assetId] or nil
    return entry and entry.parts or {}
end

--- The composed setup for a Machine, or nil. Needed so a caller can report what the couplings did without
--- recomposing and risking a different answer than the one that was actually published.
function NcmHandling.setup(assetId)
    local entry = validAssetId(assetId) and fitted[assetId] or nil
    return entry and entry.setup or nil
end

function NcmHandling.recompute(assetId, why)
    if not validAssetId(assetId) then return false, "bad_asset" end
    local entry = fitted[assetId]
    return NcmHandling.setParts(assetId, entry and entry.parts or {}, why or "recompute")
end

AddEventHandler("onPlayerDisconnected", function(playerId)
    local pid = tonumber(playerId) or 0
    if pid > 0 then
        delivered[pid] = nil
        -- The asset-keyed fitted setup deliberately survives this resource session. Disconnect changes the
        -- delivery route, not what is installed in the physical Machine.
        log("player=%d disconnected, delivery forgotten; asset setup retained", pid)
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
--   ncm.setup <family>             -- explain one family: its levers, why, and what it CANNOT do
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

    -- The command is a test instrument for a physical Machine, not a character buff. Resolve the exact
    -- active asset through server authority every time; no seat, no NCM asset, no current physics lease or
    -- ambiguous lease is a named refusal and never a player-keyed fallback.
    local binding, bindingWhy
    if NcmVehicleAccess and NcmVehicleAccess.bindingForAuthority then
        binding, bindingWhy = NcmVehicleAccess.bindingForAuthority(pid)
    else
        bindingWhy = "vehicle_access_unavailable"
    end
    if not binding then
        tell("refused: no single active NCM Machine is bound to this client's current physics authority ("
            .. tostring(bindingWhy) .. ")")
        return
    end
    local assetId = binding.assetId

    if family == nil or family == "" then
        local inv = Handling.inventory()
        local mine = {}
        for _, part in ipairs(NcmHandling.parts(assetId)) do
            mine[#mine + 1] = ("%s x%.3f"):format(part.family, part.effect)
        end
        tell(("asset %s fitted: %s"):format(assetId:sub(1, 8),
            #mine > 0 and table.concat(mine, ", ") or "nothing"))

        local direct = {}
        for _, d in ipairs(inv.direct) do direct[#direct + 1] = d.family end
        tell("DIRECT (the lever is the quantity): " .. table.concat(direct, ", "))

        -- Approximated families list the levers AND the direction, because a wing that costs top speed is
        -- the interesting half and a player should see it before fitting one.
        local approx = {}
        for _, d in ipairs(inv.approximated) do
            local bits = {}
            for _, l in ipairs(d.levers) do
                bits[#bits + 1] = (l.direction == "increases" and "+" or "-") .. l.lever
            end
            approx[#approx + 1] = ("%s (%s)"):format(d.family, table.concat(bits, " "))
        end
        tell("APPROXIMATED (a real effect, coarsely modelled): " .. table.concat(approx, ", "))

        for _, d in ipairs(inv.refused) do
            tell(("REFUSED %s: %s"):format(d.family, d.reason))
        end

        -- `L156`: headroom BEFORE the purchase. The levers do not move independently -- drive and brake
        -- are capped against grip -- so a player deciding what to fit needs to know what the car can
        -- currently absorb, not discover it afterwards from a limit message.
        local current = NcmHandling.setup(assetId)
        local levers = (current and current.levers) or Handling.clear(assetId).levers
        local ceilings = Handling.ceilings(levers)
        local headroom = {}
        for _, id in ipairs(Handling.LEVER_IDS) do
            if ceilings[id] then
                headroom[#headroom + 1] = ("%s up to x%.2f (now x%.2f)"):format(
                    id, ceilings[id], levers[id] or 1.0)
            end
        end
        if #headroom > 0 then
            tell(("CEILINGS at grip x%.2f: %s"):format(
                levers.gripScale or 1.0, table.concat(headroom, ", ")))
            tell("grip is what lifts them -- power and brakes act through the same contact patch")
        end
        tell("`ncm.setup <family>` on its own explains one family and what it cannot do")
        return
    end

    if family == "clear" then
        NcmHandling.setParts(assetId, {}, "ncm.setup clear")
        tell("setup cleared -- every lever explicitly back to inert")
        return
    end

    -- Ask the module, never a hard-coded list here. If a fourth quantity is ever proven, or a family's
    -- expression changes, this command follows without an edit.
    local expression, why = Handling.expressionFor(family)
    if not expression then
        tell("cannot: " .. tostring(why))
        return
    end

    local value = tonumber(effect)
    if not value then
        -- No multiplier given: explain the family rather than scolding about usage. **This is where a
        -- player learns what an approximation will not do for them**, which is the whole point of
        -- `losses` -- it is the list of things they might reasonably expect and will not get.
        local d = Handling.describe(family)
        local bits = {}
        for _, l in ipairs(d.levers) do
            bits[#bits + 1] = ("%s %s"):format(l.direction, l.lever)
        end
        tell(("%s [%s]: %s"):format(family, d.fidelity, table.concat(bits, ", ")))
        tell("why: " .. d.rationale)
        for _, loss in ipairs(d.losses) do tell("  cannot: " .. loss) end
        -- The ceiling that can bite this family, said before the money is spent rather than after.
        for _, c in ipairs(d.constrainedBy or {}) do
            tell(("  limited by %s -- %s; %s"):format(c.coupling, c.headline, c.advice))
        end
        tell(("usage: ncm.setup %s <multiplier>, e.g. 1.25"):format(family))
        return
    end

    local parts = {}
    -- One synthetic part per family: fitting the same family twice replaces rather than stacks, because a
    -- test instrument that quietly compounds is a test instrument that lies.
    for _, part in ipairs(NcmHandling.parts(assetId)) do
        if part.family ~= family then parts[#parts + 1] = part end
    end
    parts[#parts + 1] = { id = "test_" .. family, family = family, effect = value }

    local ok, refusal = NcmHandling.setParts(assetId, parts, "ncm.setup " .. family)
    if not ok then
        tell("refused: " .. tostring(refusal))
        return
    end
    local levers = {}
    for _, term in ipairs(expression.terms) do
        levers[#levers + 1] = (term.weight > 0 and "+" or "-") .. term.lever
    end
    tell(("fitted test_%s x%.3f [%s] -> %s"):format(
        family, value, expression.fidelity, table.concat(levers, " ")))

    -- What the car ACTUALLY ended up with, which after `L156` is not always what was asked for. Reporting
    -- only the request is how a player concludes the command does nothing: they fit a 2.0 engine, feel
    -- 1.25, and have been told 2.0.
    local composed = NcmHandling.setup(assetId)
    if composed then
        tell("now: " .. Handling.explain(composed))
        for _, l in ipairs(composed.limited or {}) do
            tell(("%s held at x%.3f (asked x%.3f) -- %s; %s"):format(
                l.lever, l.applied, l.wanted, l.headline, l.advice))
        end
    end
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
        NcmHandling.reconcilePlayer(pid, "joined", true)
    end)
end)

-- Materialisation, removal, seat changes and authority hand-offs do not all have one host event. The access
-- adapter emits the lifecycle edges it owns; a bounded poll reconciles the rest from the platform's
-- authoritative lease table. Rewriting is signature-suppressed, so the steady state costs reads, not bags.
AddEventHandler("ncm:vehicle:materialized", function()
    if not (Open77.players and Open77.players.all) then return end
    for _, playerId in ipairs(Open77.players.all()) do
        NcmHandling.reconcilePlayer(playerId, "vehicle materialized", true)
    end
end)

AddEventHandler("ncm:vehicle:dematerialized", function(assetId)
    for playerId, route in pairs(delivered) do
        if route.assetId == assetId then publishUnbound(playerId, "vehicle dematerialized", true) end
    end
end)

CreateThread(function()
    Wait(2000)
    while true do
        local seen = {}
        if Open77.players and Open77.players.all then
            for _, playerId in ipairs(Open77.players.all()) do
                local pid = tonumber(playerId) or 0
                if pid > 0 then
                    seen[pid] = true
                    NcmHandling.reconcilePlayer(pid, "authority reconciliation")
                end
            end
        end
        -- A player omitted from the current list may be between lifecycle events. Withdraw their target;
        -- the disconnect handler will subsequently remove this delivery cache.
        for pid in pairs(delivered) do
            if not seen[pid] then publishUnbound(pid, "player unavailable") end
        end
        Wait(500)
    end
end)

do
    local inv = Handling.inventory()
    log("ready -- %d direct, %d approximated, %d refused on the instance channel",
        #inv.direct, #inv.approximated, #inv.refused)
end
