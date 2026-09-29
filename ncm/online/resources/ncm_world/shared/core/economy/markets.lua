-- Pure Market Network vocabulary and starter authored data (IDEA-198/L104).
local Core = NcmCore

Core.define("economy.markets", function(C)
    local Catalogue = C.get("data.vehicle_catalogue")
    local M = { version = "0.1.0", BASE_ID = "base_market", STARTER_GRANT = 10000 }

    -- Physical Autofixer terminals. They are deliberately absent from the map and the F6 shell until the
    -- Driver interacts with the terminal; coordinates are world facts, not proximity-discovery radii.
    -- `vehicles` contains distinct models (serialized shelf units replenish independently).
    M.MARKETS = {
        { marketId=M.BASE_ID, displayName="Base Market", universallyKnown=true, kind="primary" },
        { marketId="autofixer_badlands_01", kind="autofixer", displayName="Badlands Autofixer 01", district="Badlands", x=-1805.0,y=-4286.7, specialty="Desert Cooling", partFamilies={"cooling","tires"}, vehicles={"thorton_colby_pickup","thorton_colby"} },
        { marketId="autofixer_badlands_02", kind="autofixer", displayName="Badlands Autofixer 02", district="Badlands", x=-1696.1,y=-5005.2, specialty="Long-Haul Driveline", partFamilies={"drivetrain","transmission"}, vehicles={"villefort_columbus","thorton_mackinaw"} },
        { marketId="autofixer_badlands_03", kind="autofixer", displayName="Badlands Autofixer 03", district="Badlands", x=-116.4,y=-4373.0, specialty="Nomad Chassis", partFamilies={"chassis","suspension"}, vehicles={"quadra_type66_nomad","mizutani_shion_nomad"} },
        { marketId="autofixer_badlands_04", kind="autofixer", displayName="Badlands Autofixer 04", district="Badlands", x=1478.8,y=-1394.9, specialty="Utility Structure", partFamilies={"structure","chassis"}, vehicles={"mahir_supron","thorton_merrimac"} },
        { marketId="autofixer_badlands_05", kind="autofixer", displayName="Badlands Autofixer 05", district="Badlands", x=3446.3,y=-1998.1, specialty="Armored Systems", partFamilies={"structure","cooling"}, vehicles={"militech_hellhound","chevillon_legatus"} },
        { marketId="autofixer_badlands_06", kind="autofixer", displayName="Badlands Autofixer 06", district="Badlands", x=3317.8,y=-1538.3, specialty="Rally Suspension", partFamilies={"suspension","tires"}, vehicles={"archer_bandit","archer_quartz"} },
        { marketId="autofixer_badlands_07", kind="autofixer", displayName="Badlands Autofixer 07", district="Badlands", x=1703.9,y=-765.8, specialty="Torque Workshop", partFamilies={"power_unit","drivetrain"}, vehicles={"quadra_type66","quadra_type66_avenger"} },
        { marketId="autofixer_badlands_08", kind="autofixer", displayName="Badlands Autofixer 08", district="Badlands", x=1209.8,y=-577.1, specialty="Field Electrics", partFamilies={"electrical","cooling"}, vehicles={"makigai_tanishi","mizutani_hozuki"} },
        { marketId="autofixer_dogtown_01", kind="autofixer", displayName="Dogtown Autofixer", district="Dogtown", x=-1384.4,y=-1960.6, specialty="Combat Utility", partFamilies={"structure","power_unit"}, vehicles={"mahir_supron","thorton_merrimac","militech_hellhound"} },
        { marketId="autofixer_glen_01", kind="autofixer", displayName="The Glen Autofixer", district="Heywood / The Glen", x=-1878.1,y=-913.9, specialty="Executive Ride", partFamilies={"suspension","brakes"}, vehicles={"villefort_alvarado","villefort_cortes"} },
        { marketId="autofixer_morro_rock_01", kind="autofixer", displayName="Morro Rock Autofixer", district="Morro Rock", x=-3560.7,y=368.2, specialty="Track Aerodynamics", partFamilies={"aerodynamics","brakes"}, vehicles={"porsche_911_turbo","porsche_911_turbo_cabrio"} },
        { marketId="autofixer_coastview_01", kind="autofixer", displayName="Coastview Autofixer", district="Pacifica / Coastview", x=-1886.5,y=-1912.5, specialty="Street Performance", partFamilies={"power_unit","transmission"}, vehicles={"mizutani_shion","mizutani_shion_targa"} },
        { marketId="autofixer_rancho_01", kind="autofixer", displayName="Rancho Autofixer 01", district="Santo Domingo / Rancho Coronado", x=753.5,y=-1012.5, specialty="Muscle Braking", partFamilies={"brakes","tires"}, vehicles={"villefort_deleon","villefort_deleon_sport"} },
        { marketId="autofixer_rancho_02", kind="autofixer", displayName="Rancho Autofixer 02", district="Santo Domingo / Rancho Coronado", x=322.1,y=-884.6, specialty="Classic Power", partFamilies={"power_unit","cooling"}, vehicles={"quadra_turbo_r","quadra_sport_r7"} },
        { marketId="autofixer_rancho_03", kind="autofixer", displayName="Rancho Autofixer 03", district="Santo Domingo / Rancho Coronado", x=-281.9,y=-1887.5, specialty="Hypercar Control", partFamilies={"brakes","aerodynamics"}, vehicles={"herrera_outlaw","herrera_riptide"} },
        { marketId="autofixer_rancho_04", kind="autofixer", displayName="Rancho Autofixer 04", district="Santo Domingo / Rancho Coronado", x=-148.6,y=-1953.1, specialty="Heavy Chassis", partFamilies={"chassis","structure"}, vehicles={"chevillon_emperor","chevillon_thrax"} },
        { marketId="autofixer_arroyo_01", kind="autofixer", displayName="Arroyo Autofixer", district="Santo Domingo / Arroyo", x=-579.3,y=-735.1, specialty="Industrial Transmission", partFamilies={"transmission","electrical"}, vehicles={"chevillon_legatus","villefort_columbus"} },
        { marketId="autofixer_northside_01", kind="autofixer", displayName="Northside Autofixer", district="Watson / Northside", x=-1483.8,y=1909.5, specialty="Urban Bikes", partFamilies={"tires","brakes"}, vehicles={"brennan_apollo","brennan_apollo_sport","arch_nazare"} },
        { marketId="autofixer_little_china_01", kind="autofixer", displayName="Little China Autofixer", district="Watson / Little China", x=-1357.5,y=1277.8, specialty="Superbike Electronics", partFamilies={"electrical","drivetrain"}, vehicles={"yaiba_kusanagi","yaiba_muramasa","yaiba_kusanagi_tyger"} },
        { marketId="autofixer_japantown_01", kind="autofixer", displayName="Japantown Autofixer", district="Westbrook / Japantown", x=-370.1,y=1453.2, specialty="Prestige Performance", partFamilies={"aerodynamics","power_unit"}, vehicles={"rayfield_caliburn","rayfield_aerondight","yaiba_semimaru"} },
    }

    -- Provisional balancing data. Each slot is one real asset in the alpha_launch allocation.
    M.STARTER_STOCK = {
        { slot = 1, assetId = "10000000-0000-4000-8000-000000000001", vehicleKey = "makigai_maimai", price = 2500 },
        { slot = 2, assetId = "10000000-0000-4000-8000-000000000002", vehicleKey = "thorton_galena", price = 4500 },
        { slot = 3, assetId = "10000000-0000-4000-8000-000000000003", vehicleKey = "archer_hella", price = 7500 },
    }

    function M.byId(id)
        for _, market in ipairs(M.MARKETS) do if market.marketId == id then return market end end
        return nil
    end

    function M.known(markets, grants)
        local out, seen = {}, {}
        for _, market in ipairs(markets or M.MARKETS) do
            if market.universallyKnown then out[#out + 1], seen[market.marketId] = market, true end
        end
        for _, id in ipairs(grants or {}) do
            local market = M.byId(id)
            if market and not seen[id] then out[#out + 1], seen[id] = market, true end
        end
        return out
    end

    -- ---------------------------------------------------------------------------------------------
    -- Market discovery: which markets a Driver has learned of, and on what footing (IDEA-251).
    -- ---------------------------------------------------------------------------------------------
    --
    -- **Exactly one value in each table, because exactly one producer exists.** L127 is the reason: the
    -- `machine_source` enum declared `team_equipment` ahead of any code that wrote it, on a misreading of the
    -- design, and migration 027 had to drop the column. `IDEA-298` introduces restricted and granted access,
    -- and it introduces the vocabulary in the same change as the code that produces it.
    --
    -- `open` is what `purchaseDecision` already calls `marketAccessible`. The two questions stay separate on
    -- purpose: a Driver may know a market exists and still not be able to source from it, which is the whole
    -- mechanism A2 left exclusivity to (`IDEA-298`).
    M.DISCOVERY_SOURCES = { universal = true, physical_terminal = true }
    M.ACCESS_STATES = { open = true }

    function M.accessible(state) return state == "open" end

    --- Validate one durable record of "this Driver knows this market exists". `firstKnownAt` is a first-sight
    --- fact: hosts write it once and never update it, exactly as `vehicle_discovery.first_discovered_at` is
    --- written once. `sourceRef` is optional because a universal market has nothing to point at.
    function M.discovery(fact)
        if type(fact) ~= "table" then return nil, "no_fact" end
        if type(fact.driverId) ~= "string" or fact.driverId == "" then return nil, "no_driver" end
        if type(fact.serverId) ~= "string" or fact.serverId == "" then return nil, "no_server" end
        if type(fact.marketId) ~= "string" or not M.byId(fact.marketId) then
            return nil, "unknown_market:" .. tostring(fact.marketId)
        end
        if not M.DISCOVERY_SOURCES[fact.sourceKind] then
            return nil, "unknown_source:" .. tostring(fact.sourceKind)
        end
        if not M.ACCESS_STATES[fact.accessState] then
            return nil, "unknown_access:" .. tostring(fact.accessState)
        end
        if fact.sourceRef ~= nil and (type(fact.sourceRef) ~= "string" or #fact.sourceRef > 160) then
            return nil, "bad_source_ref"
        end
        local at = tonumber(fact.firstKnownAt)
        if at == nil or at < 0 or math.floor(at) ~= at then return nil, "bad_first_known_at" end
        return { driverId = fact.driverId, serverId = fact.serverId, marketId = fact.marketId,
                 firstKnownAt = at, sourceKind = fact.sourceKind, sourceRef = fact.sourceRef,
                 accessState = fact.accessState }
    end

    function M.validate()
        local marketIds, assets, slots = {}, {}, {}
        for _, market in ipairs(M.MARKETS) do
            if marketIds[market.marketId] then return false, "duplicate_market:" .. market.marketId end
            marketIds[market.marketId] = true
            -- `market.kind` is NOT NULL; a nil here reached MySQL as a hole and aborted ncm_league's boot (KB-204).
            if type(market.kind)~="string" or market.kind=="" or type(market.displayName)~="string" then return false,"missing_kind_or_name:"..market.marketId end
            if not market.universallyKnown then
                if type(market.x)~="number" or type(market.y)~="number" then return false,"bad_coordinates:"..market.marketId end
                if #market.vehicles<1 or #market.vehicles>3 then return false,"bad_model_count:"..market.marketId end
                for _,key in ipairs(market.vehicles) do if not Catalogue.byKey(key) then return false,"unknown_vehicle:"..key end end
                if type(market.partFamilies)~="table" or #market.partFamilies<1 then return false,"missing_parts:"..market.marketId end
            end
        end
        for _, row in ipairs(M.STARTER_STOCK) do
            if assets[row.assetId] then return false, "duplicate_asset:" .. row.assetId end
            if slots[row.slot] then return false, "duplicate_slot:" .. tostring(row.slot) end
            if not Catalogue.byKey(row.vehicleKey) then return false, "unknown_vehicle:" .. row.vehicleKey end
            if type(row.price) ~= "number" or row.price < 0 or math.floor(row.price) ~= row.price then
                return false, "bad_price:" .. tostring(row.slot)
            end
            assets[row.assetId], slots[row.slot] = true, true
        end
        return true
    end

    function M.purchaseDecision(facts)
        if type(facts) ~= "table" then return { ok = false, reason = "invalid" } end
        if not facts.marketKnown then return { ok = false, reason = "market_unknown" } end
        if not facts.marketAccessible then return { ok = false, reason = "market_inaccessible" } end
        if not facts.visible then return { ok = false, reason = "stock_not_visible" } end
        if not facts.available then return { ok = false, reason = "stock_unavailable" } end
        if not facts.eligible then return { ok = false, reason = "not_eligible" } end
        if (tonumber(facts.balance) or 0) < (tonumber(facts.price) or 0) then
            return { ok = false, reason = "unaffordable" }
        end
        return { ok = true }
    end

    return M
end)
