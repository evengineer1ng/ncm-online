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
local Thermal = NcmCore.get("parts.thermal")
local Catalogue = NcmCore.get("data.vehicle_catalogue")

local function log(fmt, ...) print(("[ncm_world/handling] " .. fmt):format(...)) end
local function now() return math.floor(Open77.time.unix()) end

NcmHandling = NcmHandling or {}

local WIRE_VERSION = 2
-- Permanent Machine truth (in memory until Parts inventory/persistence exists):
-- assetId -> { parts = {...}, setup = composed setup }
local fitted = {}
-- Derived component state, keyed by Machine. It is rebuilt from exposure + append-only services and is
-- never itself persisted. `{ contributor, warnings, components }` comes from pure `parts.wear`.
local wear = {}
-- Ephemeral delivery truth: playerId -> { assetId, vehicleId, sig }
local delivered = {}
local publishTyre   -- forward: defined below, called by publishBound
local publishWear   -- forward: same delivery/privacy contract as the tyre feed
local wearSent = {} -- pid -> stable warning signature; declared before publishUnbound captures it

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
    local ok, refusal = write(pid, { v = WIRE_VERSION, bound = false, levers = inertLevers() },
        "unbound", why or "unbound")
    if ok and wearSent[pid]~="none" then wearSent[pid]="none";pcall(TriggerClientEvent,"ncm:wear",pid,false) end
    return ok, refusal
end

--- The live, per-Machine contributors: everything that is NOT a fitted part.
---
--- Assembled here rather than stored, because they change on their own schedule -- weather on minutes,
--- tyre temperature every second -- and a setup that cached them would go stale silently. The composition
--- is cheap; staleness is not.
---
--- **Every contributor is returned even when inert.** A weather layer that vanishes when the road is dry
--- is indistinguishable from a weather layer nobody wired up, which is the `IDEA-516` failure class -- and
--- the weather seam ships deliberately neutral until the weather service passes its own live gate, so this
--- is exactly the case where an absent contributor would hide a real defect for weeks.
local function contributorsFor(assetId)
    local out = {}

    -- Component condition is a named downward-only layer. Missing state is inert, never guessed.
    local lifecycle = wear[assetId]
    if lifecycle and lifecycle.contributor then out.wear = lifecycle.contributor end

    -- Weather and the clock, from the live environment read `KB-151` added. Before that fix this was a
    -- console command and nothing else, so `wetness` was permanently zero in production.
    local wetness, secondsOfDay = 0, nil
    if NcmMachine and NcmMachine.state then
        local c = NcmMachine.state()
        if type(c) == "table" then
            wetness = tonumber(c.wetness) or 0
            secondsOfDay = tonumber(c.secondsOfDay)
        end
    end

    -- Rain, charged directly: water between the rubber and the road.
    out.weather = Handling.weatherContributor(wetness)

    -- The ROAD, charged on its temperature alone (`L160`). Deliberately not given `wetness` as an input:
    -- rain is already billed by the layer above, and reaches this one only by cooling the asphalt.
    --
    -- **Absent when the clock is unknown**, rather than defaulting to a mild afternoon. A server with no
    -- environment feed then shows no surface layer at all, which is a visible absence in the trace --
    -- where a plausible default would have read as a working feature. That is the `KB-151` lesson.
    if secondsOfDay then
        local trackC = Thermal.trackTemperature({ wetness = wetness, secondsOfDay = secondsOfDay })
        out.surface = Handling.surfaceContributor(trackC)
    end

    -- The TYRE, which is a different body with a different clock. It reaches its own temperature by
    -- working, and the road only sets what it is working against.
    if NcmOdometer and NcmOdometer.tyreTemperature then
        local temperature = NcmOdometer.tyreTemperature(assetId)
        if temperature then out.thermal = Handling.thermalContributor(temperature) end
    end

    return out
end

--- Recompose a Machine's setup with its live contributors folded in.
---
--- `fitted[assetId].setup` holds the PARTS-ONLY composition, which is the durable truth. The live layers
--- are applied on top at delivery time, so a change in the weather never rewrites what is installed.
local function liveSetup(assetId)
    local entry = fitted[assetId]
    local parts = entry and entry.parts or {}
    local input = contributorsFor(assetId)
    input.vehicle = assetId
    input.parts = parts
    local setup = Handling.compose(input, { at = now() })
    -- A refusal here would mean a contributor is malformed, not that the parts are. Fall back to the
    -- stored parts-only setup rather than stranding the driver on whatever was last applied.
    if not setup then return entry and entry.setup or Handling.clear(assetId, { at = now() }) end
    return setup
end

-- ---------------------------------------------------------------------------------------------------
-- The GOVERNOR (`L157`) -- top speed leaves by a different carrier than the levers
-- ---------------------------------------------------------------------------------------------------
--
-- Top speed is not a force and is not written by the Carrier. It is an absolute km/h handed to the
-- platform's own per-instance governor, `Open77.vehicles.setPerformance`, which is replicated to every
-- viewer and survives the ownership change that happens on every driver entry and exit.
--
-- **`accelerationScale` is never written.** The platform's rule is that the governor withholds and never
-- adds, and `machine.projection` enforces `MAX_ACCELERATION_SCALE = 1.0` for the same reason. Raising a
-- top speed here lifts a ceiling NCM itself imposed; it does not add power. That distinction is the whole
-- of `L157` and it is why this needs no new authority to add force.
--
-- Unproven live as of 2026-09-26 -- MASTER_TEST section BA is the capability spike, and nothing in NCM had
-- ever successfully capped a top speed when this was written.
local governed = {}   -- assetId -> the last kph applied, so an unchanged ceiling is not rewritten

-- ---------------------------------------------------------------------------------------------------
-- A MANUAL governor target, per Machine, for the period before any baseline is authored.
-- ---------------------------------------------------------------------------------------------------
--
-- `data.vehicle_catalogue.TOP_SPEED_KPH` is deliberately empty and `ratedTopSpeed` has not answered for a
-- single record, so the composed target is nil for every car on the server today. That is correct -- `L157`
-- says an absent entry means NO ceiling rather than a guessed one -- and it would also mean the taper
-- could never be observed, which is not a good enough reason to invent numbers.
--
-- So the override is explicit, per asset, and says so in the log. It is the bench path, exactly like
-- `ncm_carrier.json` is for the three levers: a way to feel a mechanism before the data that will drive
-- it exists. When the catalogue is filled this stays as the tuning hook.
local governOverride = {}

local function applyGovernor(assetId, vehicleId, record, setup)
    if not (Open77.vehicles and type(Open77.vehicles.setPerformance) == "function") then return end

    -- The baseline is the catalogue's AUTHORED number -- a specification. It is never a measurement:
    -- `IDEA-328` draws that line explicitly ("highest observed" is evidence, "top speed" is a claim), and
    -- a governor driven by an observation would convert one into the other silently.
    local baseline = record and Catalogue.topSpeedKph(record) or nil
    local kph = Handling.topSpeedKph(setup, baseline, nil)

    -- No authored baseline means NO CEILING, not a guessed one. A governor invented from nothing is worse
    -- than no governor: it would be wrong per car and nobody could tell it from a real limit.
    local target = kph and math.floor(kph + 0.5) or nil
    if governed[assetId] == target then return end
    governed[assetId] = target

    local profile = target and { topSpeedKph = target, taperKph = 12.0 } or nil
    local ok, accepted, reason = pcall(Open77.vehicles.setPerformance, vehicleId, profile)
    if not ok then
        log("asset=%s governor THREW: %s", assetId, tostring(accepted))
    elseif accepted == false then
        log("asset=%s governor REFUSED: %s", assetId, tostring(reason))
    else
        log("asset=%s governor %s", assetId,
            target and ("topSpeedKph=" .. target) or "cleared")
    end
end

--- Publish the setup belonging to the exact asset/vehicle pair proven by vehicle_access.
local function publishBound(playerId, binding, why, force)
    local pid = tonumber(playerId) or 0
    if pid <= 0 or type(binding) ~= "table" or not validAssetId(binding.assetId)
        or binding.vehicleId == nil then
        return publishUnbound(pid, why or "bad binding", force)
    end

    local entry = fitted[binding.assetId]
    local setup = liveSetup(binding.assetId)
    -- ---- the GOVERNOR target (`L162`)
    --
    -- The record sets the headroom and the instance sets the car. A Machine's baseline top speed comes
    -- from the catalogue, parts scale it, a class ruleset lowers it further when it is more restrictive,
    -- and the carrier tapers drive to land on the result. Absent baseline means ungoverned -- we do not
    -- invent a figure for a car nobody has authored one for.
    -- Same baseline and same composition `applyGovernor` uses, so the platform ceiling and the carrier
    -- taper can never disagree about what this Machine's top speed is supposed to be. If `MASTER_TEST` BA
    -- ever proves `setPerformance` works, the two become belt and braces rather than rivals.
    local baseline = binding.record and Catalogue.topSpeedKph(binding.record) or nil
    setup.governedTopSpeedKph = baseline and Handling.topSpeedKph(setup, baseline, nil) or nil
    -- An explicit override wins over the composed figure, and over its absence. Stated plainly so a
    -- governed car is never mistaken for an authored one.
    local override = governOverride[binding.assetId]
    if override then setup.governedTopSpeedKph = override end
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

    -- The governor rides the same reconcile, and outside the `changed` gate: it has its own idempotence
    -- (`governed[assetId]`) and must survive a re-bind that did not move a lever.
    applyGovernor(binding.assetId, binding.vehicleId, binding.record, setup)
    publishTyre(pid, binding.assetId)
    publishWear(pid, binding.assetId)

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

-- ---------------------------------------------------------------------------------------------------
-- The tyre gauge feed
-- ---------------------------------------------------------------------------------------------------
--
-- A TARGETED net event, not a state bag, and all three reasons matter:
--
--   * `Open77.state.player(pid)` is visible to the **whole routing bucket**, not to that player
--     (`29_STATE_BAG_AUDIENCE_AUDIT`). `KB-97` already moved the odometer off a bag for this reason.
--   * `ncmHandling` sits inside a 4,032-byte ceiling (`IDEA-509`) that NCM was running at 80 percent of.
--   * A continuously varying field would defeat `write()`'s signature suppression and republish the bag
--     twice a second per driver -- the defect recorded above as having already happened once.
--
-- Quantised to a hundredth and suppressed unless it moves, with a heartbeat every two seconds so a page
-- that reloaded mid-drive recovers on its own -- the same shape `client/race.lua` already uses for driver
-- inputs, for the same reasons.
local tyreSent = {}   -- pid -> { key, at }

local TYRE_HEARTBEAT_S = 2

publishTyre = function(playerId, assetId)
    local pid = tonumber(playerId) or 0
    if pid <= 0 then return end
    local temperature = NcmOdometer and NcmOdometer.tyreTemperature
        and NcmOdometer.tyreTemperature(assetId) or nil

    -- **Absent is not zero** (`IDEA-361`). A tyre whose temperature we could not derive must arrive as
    -- nothing, so the gauge can draw a dash -- a needle resting mid-window is the most plausible-looking
    -- wrong value this whole design can produce.
    local payload
    if temperature then
        local position = Thermal.position(temperature)
        payload = {
            p = math.floor(position * 100 + 0.5) / 100,
            m = math.floor(Thermal.gripMultiplier(temperature) * 1000 + 0.5) / 1000,
        }
    end

    local key = payload and ("%.2f"):format(payload.p) or "none"
    local state = tyreSent[pid]
    local t = now()
    if state and state.key == key and (t - state.at) < TYRE_HEARTBEAT_S then return end
    tyreSent[pid] = { key = key, at = t }
    pcall(TriggerClientEvent, "ncm:tyre", pid, payload or false)
end

publishWear = function(playerId, assetId)
    local pid=tonumber(playerId) or 0;if pid<=0 then return end
    local warnings=((wear[assetId] or {}).warnings) or {}
    local public={}
    local keys={}
    for _,w in ipairs(warnings) do
        public[#public+1]={system=w.system,status=w.status,label=w.label}
        keys[#keys+1]=tostring(w.system)..":"..tostring(w.status)
    end
    local sig=table.concat(keys,"|")
    if wearSent[pid]==sig then return end
    wearSent[pid]=sig
    pcall(TriggerClientEvent,"ncm:wear",pid,{warnings=public})
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

--- Replace a Machine's derived lifecycle projection. The source facts live in SQL; this cache only avoids
--- querying eleven assets on every 500 ms authority reconciliation.
function NcmHandling.setWear(assetId, state, why, publish)
    if not validAssetId(assetId) then return false,"bad_asset" end
    wear[assetId]=type(state)=="table" and state or {contributor={source="component_wear"},warnings={},components={}}
    if publish==false then return true end
    if NcmVehicleAccess and NcmVehicleAccess.operatorForAsset then
        local pid,binding=NcmVehicleAccess.operatorForAsset(assetId)
        if pid and binding then return publishBound(pid,binding,why or "setWear",true) end
    end
    return true
end

function NcmHandling.wear(assetId) return validAssetId(assetId) and wear[assetId] or nil end

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
        tyreSent[pid] = nil
        wearSent[pid] = nil
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
--- `/ncm.govern <kph>` -- set this Machine's top speed target directly.
---
--- **This is the instance channel, not TweakDB.** It does not touch a record, it is not spawn-cached, it
--- reaches only the car the caller is bound to, and it survives nothing -- losing the server returns the
--- Machine to ungoverned. Two drivers in the same model can hold different targets at the same time,
--- which is the whole thing the record channel could never do.
RegisterNetEvent("ncm:govern", function(kph)
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    local function tell(message)
        pcall(Open77.chat.send, pid, "[NCM] " .. message)
        pcall(TriggerClientEvent, "ncm:setup.result", pid, message)
        log("player=%d <- %s", pid, message)
    end

    local binding = NcmVehicleAccess and NcmVehicleAccess.bindingForAuthority
        and NcmVehicleAccess.bindingForAuthority(pid) or nil
    if not binding then
        tell("refused: no NCM Machine bound to this client's physics authority")
        return
    end

    local target = tonumber(kph)
    if target and target > 0 then
        -- Bounded so a typo cannot govern a car to walking pace or to something the taper cannot express.
        if target < 20 then target = 20 elseif target > 500 then target = 500 end
        governOverride[binding.assetId] = target
        tell(("governor set to %d km/h -- drive a long straight; the car should run out of legs rather "
            .. "than hit a wall"):format(math.floor(target + 0.5)))
    else
        governOverride[binding.assetId] = nil
        tell("governor cleared -- this Machine is ungoverned again")
    end
    -- Force a republish: the levers have not moved, and without this the unchanged-payload suppression
    -- would swallow the change entirely.
    NcmHandling.reconcilePlayer(pid, "governor", true)
end)

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

-- ---------------------------------------------------------------------------------------------------
-- `/ncm.topspeed` -- the CAPABILITY SPIKE for per-instance top speed
-- ---------------------------------------------------------------------------------------------------
--
-- **Nothing in NCM has ever capped a top speed.** Traced 2026-09-26, and the result was worse than
-- expected:
--
--   * `setPerformanceClass(record, prof)` -- the client, per-record form -- is called by
--     `client/main.lua`, but its data source `GlobalState.ncmCeilings` HAS NEVER REACHED A CLIENT.
--     `server/state_probe.lua` records it: *"class ceilings, a shipped feature, have never applied"*, and
--     the leading hypothesis is that GlobalState replicates a CHANGE, so a key written once at boot before
--     anybody connects is never sent to a later joiner -- "unreachable by construction". Its only producer
--     was the RB15 class, disabled by `KB-144` when the car was withdrawn. Last live run: 154 attempts,
--     zero applied, against records no client had.
--   * `ratedTopSpeed(record)` is CLIENT-ONLY. It is not in the server scripting assembly, so the server
--     cannot use it as a baseline even though its own card recommends it for picking a ceiling.
--   * `setPerformance(id, profile)` -- the SERVER, per-instance form -- is present in the deployed binary
--     (`Open77.Server.Scripting.dll` carries `setPerformance` and `topSpeedKph`) and both resources hold
--     `world.vehicles`. **NCM has never called it. Zero call sites.**
--
-- So this command exists to answer four questions that are currently all guesses, before any design is
-- built on top of them:
--
--   1. Does the call succeed on a server-spawned NCM Machine, or refuse with `vehicle_not_found`?
--   2. Does the cap hold in the car, and does the taper read as a governor or as a stutter?
--   3. Does it survive getting out and back in? Ownership changes on every driver entry and exit, and the
--      evidence card claims the ceiling is replicated to every viewer rather than chased across that.
--   4. Does it survive a reconnect?
--
-- **If this fails, the top-speed half of the plan is dead** and "top speed is not reachable on this
-- platform" becomes the honest answer. Weather and the thermal model do not depend on it.
--
-- Deliberately NOT wired into `parts.handling`. A spike proves a capability; composing it into the parts
-- pipeline is a later step that should only happen once there is a PASS to build on.
local topSpeedApplied = {}   -- assetId -> the last kph asked for, so the command can report honestly

RegisterNetEvent("ncm:topspeed", function(raw)
    local pid = tonumber(source) or 0
    if pid <= 0 then return end

    local function tell(message)
        pcall(Open77.chat.send, pid, "[NCM] " .. message)
        pcall(TriggerClientEvent, "ncm:setup.result", pid, message)
        log("player=%d <- %s", pid, message)
    end

    -- The platform surface has to be present before anything else is worth saying. `type()` rather than a
    -- pcall on the call itself, so "the API is missing" and "the API refused" stay different answers.
    if not (Open77.vehicles and type(Open77.vehicles.setPerformance) == "function") then
        tell("refused: Open77.vehicles.setPerformance is not available on this server build")
        return
    end

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

    if raw == nil or raw == "" then
        local current = topSpeedApplied[binding.assetId]
        tell(("asset %s: %s"):format(binding.assetId:sub(-6),
            current and ("capped at %d km/h"):format(current) or "no ceiling set by NCM"))
        tell("usage: ncm.topspeed <kph>, or `ncm.topspeed clear`. Try 60 on a long straight.")
        return
    end

    -- Clearing is `nil`, and a profile asking for nothing clears too. Both are the platform's own contract;
    -- this sends `nil` because it is the one the card documents first.
    local clearing = (raw == "clear" or raw == "0" or tonumber(raw) == 0)
    local kph = clearing and nil or tonumber(raw)
    if not clearing and not kph then
        tell("usage: ncm.topspeed <kph>, or `ncm.topspeed clear`")
        return
    end
    -- The platform's stated envelope: 0..1000, and the taper is never zero -- below about 3 km/h the
    -- limiter hunts around the ceiling and reads as stutter, which is why the client governor has refused
    -- that band since it shipped. Checked here so a bad number is a sentence rather than a refusal code.
    if kph and (kph < 0 or kph > 1000) then
        tell("refused: topSpeedKph must be 0..1000")
        return
    end

    local profile = kph and { topSpeedKph = kph, taperKph = 12.0 } or nil
    local ok, accepted, reason = pcall(Open77.vehicles.setPerformance, binding.vehicleId, profile)

    -- Three outcomes, kept apart on purpose: the call threw, the call returned false with a reason, or it
    -- worked. Collapsing them is how "it doesn't work" gets recorded when the truth was "we lacked a
    -- permission" -- and `KB-150` is this afternoon's standing reminder about destroying your own evidence.
    if not ok then
        tell("ERROR: setPerformance threw: " .. tostring(accepted))
        log("SPIKE asset=%s vehicle=%s THREW %s",
            binding.assetId, tostring(binding.vehicleId), tostring(accepted))
        return
    end
    if accepted == false then
        tell("REFUSED by the platform: " .. tostring(reason))
        log("SPIKE asset=%s vehicle=%s REFUSED %s",
            binding.assetId, tostring(binding.vehicleId), tostring(reason))
        return
    end

    topSpeedApplied[binding.assetId] = kph
    tell(clearing and "ceiling cleared -- full top speed restored"
        or ("ceiling set to %d km/h (taper 12) -- drive a long straight and see whether it holds"):format(kph))
    log("SPIKE asset=%s vehicle=%s ACCEPTED topSpeedKph=%s",
        binding.assetId, tostring(binding.vehicleId), tostring(kph))

    -- ----------------------------------------------------------------- READ IT BACK
    --
    -- **ACCEPTED IS NOT APPLIED, and the first live run proved it.** `setPerformance` returned true for
    -- `topSpeedKph = 40` and the car did not slow down at all. A call that succeeds and does nothing is
    -- the worst shape a capability can have, because every log line says it worked.
    --
    -- So the spike reads the ceiling back. That splits one unanswerable question into two answerable ones:
    -- if the server does NOT hold 40, the write did not stick and the problem is server-side; if it DOES
    -- hold 40 and the car still runs away, the ceiling is stored and not enforced, and the problem is
    -- between the server and the physics owner. Those have entirely different fixes and nothing else
    -- distinguishes them.
    if type(Open77.vehicles.getPerformance) == "function" then
        local okRead, held = pcall(Open77.vehicles.getPerformance, binding.vehicleId)
        if not okRead then
            tell("read-back THREW: " .. tostring(held))
        elseif type(held) ~= "table" then
            tell(("read-back returned %s -- the server does NOT hold a ceiling for this vehicle")
                :format(type(held)))
        else
            tell(("read-back: topSpeedKph=%s accelerationScale=%s taperKph=%s"):format(
                tostring(held.topSpeedKph), tostring(held.accelerationScale), tostring(held.taperKph)))
            log("SPIKE read-back asset=%s topSpeedKph=%s taperKph=%s", binding.assetId,
                tostring(held.topSpeedKph), tostring(held.taperKph))
        end
    else
        tell("no getPerformance on this build -- cannot tell 'stored' from 'enforced'")
    end
end)

-- ---------------------------------------------------------------------------------------------------
-- `/ncm.tyre` -- what the thermal model actually thinks
-- ---------------------------------------------------------------------------------------------------
--
-- Added after the first live drive reported the gauge "stayed flat cold" through cornering and donuts.
-- The plumbing was fine; the model settled at 54C in a donut, which reads as stone cold forever. **There
-- was no way to see that from inside the game** -- the gauge showed a position and nothing showed the
-- temperature, the load, or the ambient it was being pulled toward.
--
-- A gauge without a readout behind it can only ever tell you that something is wrong, never what.
RegisterNetEvent("ncm:tyre.query", function()
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    local function tell(message)
        pcall(Open77.chat.send, pid, "[NCM] " .. message)
        pcall(TriggerClientEvent, "ncm:setup.result", pid, message)
        log("player=%d <- %s", pid, message)
    end

    local binding
    if NcmVehicleAccess and NcmVehicleAccess.bindingForAuthority then
        binding = NcmVehicleAccess.bindingForAuthority(pid)
    end
    if not binding then
        tell("refused: no NCM Machine bound to this client's physics authority")
        return
    end

    local temperature = NcmOdometer and NcmOdometer.tyreTemperature
        and NcmOdometer.tyreTemperature(binding.assetId) or nil
    if not temperature then
        tell("no tyre temperature for this Machine yet -- the odometer has not sampled it")
        return
    end

    local conditions = (NcmMachine and NcmMachine.state and NcmMachine.state()) or {}
    local world = { wetness = conditions.wetness, secondsOfDay = conditions.secondsOfDay }
    tell(("tyre %s"):format(Thermal.explain(temperature)))
    -- Both bodies, because reporting one of them explains half of what the driver is feeling.
    tell(("track %s   (air %.1fC)"):format(
        Thermal.explainSurface(Thermal.trackTemperature(world)), Thermal.airTemperature(world)))
    tell(("weather=%s wetness=%.2f secondsOfDay=%s"):format(
        tostring(conditions.weather or "?"), tonumber(conditions.wetness) or 0,
        tostring(math.floor(tonumber(conditions.secondsOfDay) or -1))))
    tell(("window %.0fC +/- %.0f, so it costs nothing between %.0fC and %.0fC"):format(
        Thermal.OPTIMUM, Thermal.HALF_WINDOW * 0.2,
        Thermal.OPTIMUM - Thermal.HALF_WINDOW * 0.2, Thermal.OPTIMUM + Thermal.HALF_WINDOW * 0.2))
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
