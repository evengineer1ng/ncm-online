-- ncm-core module: economy.npc_garage
-- An NPC's race car as a real car (L298; owner, 2026-10-02: "If Cesar buys sport brakes, do those brakes enter
-- Cesar's inventory, get installed on a specific car, alter that car's drive/brake/grip/etc. characteristics, and
-- then follow that exact car into physical racing? If the answer breaks anywhere along that chain, you've found
-- simulation theatre.").
--
-- The car is a `vehicle_asset` with the same eleven-family machine configuration a player's car has. Everything
-- the Paddock used to keep as four free-floating development levels is now DERIVED from that car:
--   * the model's class standing (its prestige)                     -> the base of every area
--   * the parts installed on it (their `effect`, one per family)   -> above or below the base, per area
--   * the parts' wear (`parts.wear`, from raced distance)           -> the same multipliers a player's car feels
--   * the team's workshop (`tune`, eddies spent on hours, capped)   -> a small, bounded setup bonus
-- and the physical racer's performance variant comes from the same parts through `parts.handling.compose` --
-- the formula a player's car uses.
--
-- Pure rules. The Paddock host (`ncm_paddock/server/npc_cars.lua`) moves the rows and the money.
local Core = NcmCore

Core.define("economy.npc_garage", function(C)
    local M = { version = "0.1.0" }
    local Car = C.get("paddock.car")
    local Cat = C.get("parts.catalogue")
    local Wear = C.get("parts.wear")
    local Handling = C.get("parts.handling")
    local Hash = C.get("vocabulary.hash")
    local Pool = C.get("data.vehicle_pool")
    local Vehicles = C.get("data.vehicle_catalogue")
    local NM = C.get("economy.npc_market")

    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

    -- ------------------------------------------------------------------------------------------------ the model
    -- The tier bands are the Paddock's own (`paddock.season` TIERS band): what a racer of that tier drives.
    --- The catalogue models a racer of `band` may own: { vehicleKey, record, prestige }, stable order.
    function M.modelsFor(band)
        band = band or {}
        local out, seen = {}, {}
        for _, class in ipairs(band.classes or { "Sport" }) do
            for _, r in ipairs(Pool.records(class, band.prestigeMax)) do
                local entry = Vehicles.resolveRecord(r.id)
                if entry and (tonumber(r.prestige) or 1) >= (band.prestigeMin or 0) and not seen[entry.vehicleKey] then
                    seen[entry.vehicleKey] = true
                    out[#out + 1] = { vehicleKey = entry.vehicleKey, record = r.id, prestige = tonumber(r.prestige) or 1 }
                end
            end
        end
        table.sort(out, function(a, b) return a.vehicleKey < b.vehicleKey end)
        return out
    end

    --- The model an NPC starts with: a team's cars share one model (one livery, one programme); an independent's
    --- is their own (hashed on the PERSON -- before L298 every independent hashed the constant "none" and a tier's
    --- independents all drove the same car).
    function M.startingModel(band, seed, kind, id)
        local list = M.modelsFor(band)
        if #list == 0 then return nil end
        return list[1 + Hash.fnv1a32(Hash.key(seed or 0, "npc-car", kind or "person", id or "?")) % #list]
    end

    -- ------------------------------------------------------------------------------------------------ the levels
    -- Where a model of a given prestige sits on the 1..10 development scale (paddock.car), before parts. Street
    -- (prestige 1-2) lands about where `Car.TIER_BASE.street` did, premier (5) where premier did.
    M.PRESTIGE_BASE = { [1] = 2.0, [2] = 3.0, [3] = 4.5, [4] = 6.0, [5] = 8.0 }
    -- Levels per unit of effect above factory: a whole area of sport parts (1.18) is about +2 levels, premium +3.5.
    M.EFFECT_LEVELS = 12
    -- The workshop (team development hours, `tune`) adds at most this much to an area: parts are the car.
    M.TUNE_MAX = 1.0

    --- Wear's bite on one installed part, as a multiplier on its effect (1 = as new). `part` = { asset_id, family,
    --- exposure_m }; `services` = its service rows.
    function M.wearFactor(part, services)
        local state = Wear.evaluate(part, services)
        local c = state and state.conditions and state.conditions[1]
        local profile = Wear.profile(part.family)
        if not c or not profile then return 1 end
        local worst = 1
        for _, floor in pairs(profile.effects or {}) do worst = math.min(worst, floor) end
        return 1 - (1 - worst) * (c.severity or 0)
    end

    --- The car's four development levels from its model and installed parts. `installed` = { { family, effect,
    --- wear = 0..1 multiplier } } -- one per family (a missing family counts as factory). `tune` = { [area] = 0..TUNE_MAX }.
    function M.levels(prestige, installed, tune)
        local base = M.PRESTIGE_BASE[clamp(math.floor(tonumber(prestige) or 1), 1, 5)] or 2
        local byFamily = {}
        for _, p in ipairs(installed or {}) do
            if p.family then byFamily[p.family] = (tonumber(p.effect) or 1) * (tonumber(p.wear) or 1) end
        end
        local car = { progress = {}, tune = {} }
        for _, area in ipairs(Car.AREAS) do
            local fams = NM.AREA_FAMILIES[area] or {}
            local sum = 0
            for _, f in ipairs(fams) do sum = sum + (byFamily[f] or 1) end
            local mean = (#fams > 0) and (sum / #fams) or 1
            local t = clamp(tonumber(tune and tune[area]) or 0, 0, M.TUNE_MAX)
            car[area] = math.floor(clamp(base + (mean - 1) * M.EFFECT_LEVELS + t, 1, Car.MAX_LEVEL) * 10 + 0.5) / 10
            car.progress[area] = 0
            car.tune[area] = t
        end
        return car
    end

    -- ------------------------------------------------------------------------------------- the physical racer
    -- NCM Pace's racer clones come in performance VARIANTS (tools/gen-pace-racers.py): the same model with its
    -- engine and drive model scaled a step further each. The grip lever has no TweakDB handle (KB-292), so a variant
    -- carries drive and brake; drag rides the clone's base scale.
    M.VARIANTS = 4                  -- v0 .. v3
    M.VARIANT_STEP = 0.06           -- drive +6 %, brake +6 % per step over the base racer scale

    --- The composed levers of a configuration (the player formula): `installed` as for `levels`.
    function M.levers(installed)
        local parts = {}
        for i, p in ipairs(installed or {}) do
            if Handling.expressionFor(p.family) then
                parts[#parts + 1] = { id = "npc" .. i, family = p.family, effect = math.max(0.5, (tonumber(p.effect) or 1) * (tonumber(p.wear) or 1)) }
            end
        end
        local setup = Handling.compose({ parts = parts })
        return setup and setup.levers or { gripScale = 1, driveScale = 1, brakeScale = 1, dragScale = 1 }
    end

    --- The racer variant (0..VARIANTS-1) for a configuration: the mean drive/brake gain over factory, in steps.
    function M.variant(installed)
        local lv = M.levers(installed)
        local gain = ((tonumber(lv.driveScale) or 1) + (tonumber(lv.brakeScale) or 1)) / 2 - 1
        return clamp(math.floor(gain / M.VARIANT_STEP + 0.5), 0, M.VARIANTS - 1)
    end

    --- The racer record for a model and variant (Pace's TweakXL clone). An oval has its own clones and driving profile
    --- (owner, 2026-10-03: on point-to-point "a tad" too fast, on ovals "too slow").
    function M.racerRecord(record, variant, oval)
        local base = tostring(record or ""):gsub("^Vehicle%.", oval and "Vehicle.ncm_racer_oval_" or "Vehicle.ncm_racer_")
        if (variant or 0) <= 0 then return base end
        return base .. "_v" .. math.floor(variant)
    end

    -- ------------------------------------------------------------------------------------------------ buying
    --- Does a design fit this model? (the catalogue's mechanical fitment contract -- the player rule)
    function M.fits(designId, vehicleKey)
        local r = Cat.resolve(designId, vehicleKey)
        return r and r.compatible == true
    end

    --- Is `candidate` ({ effect }) an upgrade over what is installed in its family (`installedEffect`, wear
    --- included)? Never a downgrade, never a duplicate: strictly better by a visible margin.
    M.UPGRADE_MARGIN = 0.02
    function M.isUpgrade(installedEffect, candidate)
        return (tonumber(candidate and candidate.effect) or 0) > (tonumber(installedEffect) or 1) + M.UPGRADE_MARGIN
    end

    -- ------------------------------------------------------------------------------------------------ intent
    -- Why an NPC acts (owner: "goal -> need -> search -> affordability -> purchase -> ownership -> installation/use
    -- -> performance/result -> new goal"). A goal names a reason the transaction carries.
    M.REASON = { SERVICE = "service_worn_part", REPLACE = "replace_worn_part", UPGRADE = "upgrade_weakest_area",
        CAR = "replace_car", FIRST_CAR = "first_car" }

    --- The goals for one car, most pressing first. `parts` = { { assetId, family, effect, state = parts.wear
    --- evaluate result, services } }; `car` = derived levels. Worn parts first (critical before attention), then
    --- the weakest area.
    function M.goals(parts, car)
        local out = {}
        for _, p in ipairs(parts or {}) do
            local c = p.state and p.state.conditions and p.state.conditions[1]
            if c then
                local quote = Wear.serviceQuote(p, p.services, c.id)
                out[#out + 1] = { kind = quote and M.REASON.SERVICE or M.REASON.REPLACE, family = p.family, assetId = p.assetId,
                    severity = c.severity or 0, critical = c.status == "critical", quote = quote }
            end
        end
        table.sort(out, function(a, b)
            if a.critical ~= b.critical then return a.critical end
            if a.severity ~= b.severity then return a.severity > b.severity end
            return tostring(a.assetId) < tostring(b.assetId)
        end)
        local weakest = NM.neediest(car)[1]
        if weakest then out[#out + 1] = { kind = M.REASON.UPGRADE, area = weakest.area } end
        return out
    end

    -- ---------------------------------------------------------------------------------------------- money
    -- An NPC entrant's fee per race (paid by the team for its drivers, by an independent for themself). With the
    -- purses (`paddock.finance.PURSE`), an average street independent nets about €$140 a race before running costs.
    M.ENTRY_FEE = { street = 60, regional = 150, pro = 400, premier = 1200 }
    function M.entryFee(tier) return M.ENTRY_FEE[tier] or M.ENTRY_FEE.street end

    --- What a crash costs to put right: a share of the car's value by the damage it took (0..1), plus a wreck's tow.
    M.REPAIR_SHARE, M.WRECK_TOW = 0.12, 400
    function M.repairCost(carValue, damage, wrecked)
        return math.floor((tonumber(carValue) or 10000) * M.REPAIR_SHARE * clamp(tonumber(damage) or 0, 0, 1) + (wrecked and M.WRECK_TOW or 0) + 0.5)
    end

    return M
end)
