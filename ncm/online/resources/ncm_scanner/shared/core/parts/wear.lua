-- ncm-core: deterministic component wear and service derivation (L120/L178).
--
-- Exposure and service rows are the only stored facts. Conditions, severity, warnings and physics
-- contributors are pure projections of those facts. Tyre compounds deliberately do not live here.
local Core = NcmCore

Core.define("parts.wear", function()
    local M = { version = "1.1.0" }

    local function clamp(v, lo, hi)
        v = tonumber(v) or lo
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    -- First observed pacing, intentionally centralized and versioned. These are gameplay distances, not
    -- claims about real automotive lifetimes. A narrow +/- band made every Machine follow essentially the
    -- same maintenance staircase; v2 instead gives each physical asset a broad, overlapping onset envelope.
    -- Aero/structure/chassis have no ordinary mileage wear.
    M.PROFILE_VERSION = 2
    M.PROFILES = {
        tires =       { id="tire_peak_loss", label="CONTACT PATCH WORN", system="tyre", onsetMinM=750000,  onsetMaxM=7500000,  spanRatio=1.0, serviceIntervalRatio=.5, serviceCost=350, effects={gripScale=.78,brakeScale=.82} },
        brakes =      { id="brake_fade_early", label="BRAKE FADE MARGIN LOW", system="brake", onsetMinM=1000000, onsetMaxM=12000000, spanRatio=1.0, serviceIntervalRatio=.5, serviceCost=450, effects={brakeScale=.72} },
        suspension =  { id="suspension_response_loss", label="SUSPENSION RESPONSE DEGRADED", system="chassis", onsetMinM=2000000,onsetMaxM=30000000,spanRatio=1.0,serviceIntervalRatio=.5, serviceCost=650, effects={gripScale=.82,brakeScale=.94} },
        cooling =     { id="cooling_rejection_loss", label="COOLING MARGIN DEGRADED", system="temperature", onsetMinM=1500000,onsetMaxM=25000000,spanRatio=1.0,serviceIntervalRatio=.5, serviceCost=600, effects={driveScale=.91} },
        drivetrain =  { id="drivetrain_delivery_loss", label="DRIVETRAIN DELIVERY DEGRADED", system="drivetrain", onsetMinM=3000000,onsetMaxM=45000000,spanRatio=1.0,serviceIntervalRatio=.5,serviceCost=850, effects={driveScale=.84,gripScale=.96} },
        transmission ={ id="transmission_efficiency_loss", label="TRANSMISSION EFFICIENCY DEGRADED", system="drivetrain", onsetMinM=4000000,onsetMaxM=55000000,spanRatio=1.0,serviceIntervalRatio=.5,serviceCost=900, effects={driveScale=.85,brakeScale=.95} },
        power_unit =  { id="power_output_fade", label="MOTIVE OUTPUT DEGRADED", system="engine", onsetMinM=6000000,onsetMaxM=80000000,spanRatio=1.0,serviceIntervalRatio=.5,serviceCost=1200,effects={driveScale=.76} },
        electrical =  { id="control_response_loss", label="CONTROL RESPONSE DEGRADED", system="electrical", onsetMinM=2500000,onsetMaxM=60000000,spanRatio=1.0,serviceIntervalRatio=.5,serviceCost=700, effects={driveScale=.90,gripScale=.97} },
    }

    M.SYSTEM_ORDER = { "engine", "drivetrain", "brake", "tyre", "temperature", "electrical", "chassis" }

    -- Portable 32-bit-ish string hash. Only the stable 0..1 fraction matters; this is not security.
    local function fraction(seed)
        -- Small modulus keeps every intermediate exact under Lua's double-number builds as well as LuaJIT.
        local h = 5381
        for i = 1, #seed do h = (h * 33 + seed:byte(i)) % 2147483647 end
        return h / 2147483646
    end

    function M.profile(family) return M.PROFILES[tostring(family or "")] end

    function M.baseThreshold(profile, assetId)
        if type(profile) ~= "table" then return nil end
        -- Broad individuality, fixed forever by physical asset identity + condition id. Families overlap on
        -- purpose: the system must not guarantee that every car asks for the same services in the same order.
        local lo, hi = tonumber(profile.onsetMinM), tonumber(profile.onsetMaxM)
        if not lo or not hi or lo < 1 or hi < lo then return nil end
        local position = fraction(tostring(assetId or "") .. ":" .. tostring(profile.id))
        return math.floor(lo + (hi - lo) * position + .5)
    end

    local function distanceBands(profile, base)
        local span = math.max(1, math.floor(base * (tonumber(profile.spanRatio) or 1) + .5))
        local service = math.max(1, math.floor(base * (tonumber(profile.serviceIntervalRatio) or .5) + .5))
        return span, service
    end

    local function serviceRelief(services, conditionId)
        local total = 0
        for _, service in ipairs(type(services) == "table" and services or {}) do
            if tostring(service.condition_id or service.conditionId or "") == conditionId then
                total = total + math.max(0, tonumber(service.relief_m or service.reliefM) or 0)
            end
        end
        return total
    end

    function M.evaluate(asset, services)
        if type(asset) ~= "table" then return nil, "asset_required" end
        local profile = M.profile(asset.family)
        if not profile then
            return { family=asset.family, assetId=asset.asset_id or asset.assetId,
                exposureM=math.max(0,tonumber(asset.exposure_m or asset.exposureM) or 0), status="normal", conditions={} }
        end
        local assetId = tostring(asset.asset_id or asset.assetId or "")
        if assetId == "" then return nil, "asset_id_required" end
        local exposure = math.max(0, tonumber(asset.exposure_m or asset.exposureM) or 0)
        local base = M.baseThreshold(profile, assetId)
        local span, serviceInterval = distanceBands(profile, base)
        local reliefCap = serviceInterval * 2
        local relief = math.min(reliefCap, serviceRelief(services, profile.id))
        local threshold = base + relief
        local overshoot = math.max(0, exposure - threshold)
        local severity = clamp(overshoot / span, 0, 1)
        local conditions, status = {}, "normal"
        if exposure >= threshold then
            status = severity >= .65 and "critical" or "attention"
            conditions[1] = { id=profile.id, label=profile.label, system=profile.system,
                status=status, severity=severity, sinceExposureM=threshold }
        end
        return { family=asset.family, assetId=assetId, exposureM=exposure, status=status,
            conditions=conditions, baseThresholdM=base, effectiveThresholdM=threshold,
            severitySpanM=span, serviceIntervalM=serviceInterval,
            serviceReliefM=relief, serviceReliefCapM=reliefCap }
    end

    function M.serviceQuote(asset, services, conditionId)
        local state, why = M.evaluate(asset, services)
        if not state then return nil, why end
        local profile = M.profile(asset.family)
        if not profile or profile.id ~= tostring(conditionId or "") then return nil, "condition_unknown" end
        local active = state.conditions[1]
        if not active then return nil, "condition_not_active" end
        local remaining = math.max(0, state.serviceReliefCapM - state.serviceReliefM)
        if remaining < 1 then return nil, "service_relief_exhausted" end
        local overshoot = math.max(0, state.exposureM - state.effectiveThresholdM)
        local relief = math.min(remaining, math.floor(overshoot + state.serviceIntervalM * .35 + .5))
        if relief < 1 then return nil, "no_effective_relief" end
        return { conditionId=profile.id, reliefM=relief,
            cost=math.floor(profile.serviceCost * (1 + active.severity * .75) / 10 + .5) * 10,
            providerKind="network_service", workmanship={grade="standard", profileVersion=M.PROFILE_VERSION} }
    end

    function M.machine(components, servicesByAsset)
        local levers = { gripScale=1, driveScale=1, brakeScale=1, dragScale=1 }
        local systems, states = {}, {}
        for _, asset in ipairs(type(components) == "table" and components or {}) do
            local assetId = tostring(asset.asset_id or asset.assetId or "")
            local state = M.evaluate(asset, type(servicesByAsset) == "table" and servicesByAsset[assetId] or nil)
            states[#states + 1] = state
            local condition = state and state.conditions[1]
            local profile = M.profile(asset.family)
            if condition and profile then
                for lever, floor in pairs(profile.effects or {}) do
                    levers[lever] = levers[lever] * (1 - (1 - floor) * condition.severity)
                end
                local old = systems[condition.system]
                if not old or condition.severity > old.severity then
                    systems[condition.system] = { system=condition.system, status=condition.status,
                        severity=condition.severity, conditionId=condition.id, label=condition.label }
                end
            end
        end
        local warnings = {}
        for _, id in ipairs(M.SYSTEM_ORDER) do if systems[id] then warnings[#warnings+1]=systems[id] end end
        if #warnings > 0 then
            local master = { system="service", status="attention", severity=0, label="SERVICE REQUIRED" }
            for _, warning in ipairs(warnings) do
                if warning.severity > master.severity then master.severity=warning.severity end
                if warning.status == "critical" then master.status="critical";master.label="SERVICE URGENT" end
            end
            table.insert(warnings, 1, master)
        end
        return { contributor={source="component_wear",gripScale=levers.gripScale,driveScale=levers.driveScale,
            brakeScale=levers.brakeScale,dragScale=levers.dragScale}, warnings=warnings, components=states }
    end

    function M.publicState(state)
        if type(state) ~= "table" then return {status="normal",conditions={}} end
        local conditions = {}
        for _, c in ipairs(state.conditions or {}) do conditions[#conditions+1] = {
            id=c.id,label=c.label,system=c.system,status=c.status
        } end
        return { status=state.status or "normal", conditions=conditions }
    end

    return M
end)
