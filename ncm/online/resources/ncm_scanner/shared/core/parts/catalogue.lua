-- NCM component catalogue, v1. Pure launch content plus the mechanical fitment contract used by every host.
local Core = NcmCore

Core.define("parts.catalogue", function(C)
    local M = { version = "1.0.0" }
    local ontology = C.get("parts.ontology")
    local Vehicles = C.get("data.vehicle_catalogue")
    local Markets = C.get("economy.markets")

    M.STARTER_VEHICLES = { "makigai_maimai", "thorton_galena", "archer_hella" }
    M.INTERFACES = {
        power_unit = { "power_unit.core" }, cooling = { "cooling.primary" },
        transmission = { "transmission.main" }, drivetrain = { "drivetrain.final_drive" },
        tires = { "tires.front_axle", "tires.rear_axle" },
        brakes = { "brakes.front_axle", "brakes.rear_axle" },
        suspension = { "suspension.front_axle", "suspension.rear_axle" },
        electrical = { "electrical.powertrain_control" },
        aerodynamics = { "aerodynamics.front", "aerodynamics.rear", "aerodynamics.underbody" },
        structure = { "structure.front", "structure.center", "structure.rear" },
        chassis = { "chassis.front_subframe", "chassis.rear_subframe" },
    }
    M.FAMILIES = { "power_unit", "cooling", "transmission", "drivetrain", "tires", "brakes",
        "suspension", "electrical", "aerodynamics", "structure", "chassis" }

    local content = {
        power_unit   = { maker="Thorton", street=900, sport=2400, premium=4000, sportFits={"thorton_galena","archer_hella"} },
        cooling      = { maker="Makigai", street=400, sport=1200, sportFits={"makigai_maimai","archer_hella"} },
        transmission = { maker="Thorton", street=700, sport=1900, sportFits={"thorton_galena","archer_hella"} },
        drivetrain   = { maker="Thorton", street=650, sport=1800, sportFits={"makigai_maimai","thorton_galena"} },
        tires        = { maker="Makigai", street=600, sport=1800, premium=3400, sportFits={"makigai_maimai","archer_hella"} },
        brakes       = { maker="Archer", street=600, sport=1700, premium=3000, sportFits={"thorton_galena","archer_hella"} },
        suspension   = { maker="Thorton", street=650, sport=1800, sportFits={"makigai_maimai","thorton_galena"} },
        electrical   = { maker="Makigai", street=450, sport=1300, sportFits={"makigai_maimai","thorton_galena"} },
        aerodynamics = { maker="Makigai", street=550, sport=1700, sportFits={"makigai_maimai","thorton_galena"} },
        structure    = { maker="Archer", street=500, sport=1500, sportFits={"makigai_maimai","archer_hella"} },
        chassis      = { maker="Thorton", street=800, sport=2200, sportFits={"thorton_galena","archer_hella"} },
    }
    M.SUPPLY = {
        street={ ceiling=8, initialAllocation=6, batch=4, cadenceSec=1800 },
        sport={ ceiling=5, initialAllocation=3, batch=2, cadenceSec=3600 },
        premium={ ceiling=3, initialAllocation=1, batch=1, cadenceSec=7200 },
    }
    M.EFFECT = { street=1.08, sport=1.18, premium=1.30 }
    M.FIDELITY = ontology.INSTANCE_FIDELITY

    local abbreviations = { power_unit="PWR", cooling="CLG", transmission="TRN", drivetrain="DRV",
        tires="TIR", brakes="BRK", suspension="SUS", electrical="ELC", aerodynamics="AER",
        structure="STR", chassis="CHS" }
    local makerCode = { Makigai="MKG", Thorton="THN", Archer="ARC" }
    local all = M.STARTER_VEHICLES
    local designs, byId = {}, {}
    local function copy(a) local o={} for i,v in ipairs(a or {}) do o[i]=v end return o end
    local function add(family, tier, price, fits)
        local row, effect = content[family], M.EFFECT[tier]
        local id = ("launch:%s:%s"):format(family, tier)
        local d = { designId=id, lineageId=("launch:%s"):format(family), revision=1,
            manufacturer=row.maker, makerKey=row.maker:lower(), family=family, tier=tier, effect=effect,
            code=("%s-%s-%03d"):format(makerCode[row.maker], abbreviations[family], math.floor(effect*100+.5)),
            subtitle=tier:sub(1,1):upper()..tier:sub(2).." System", price=price,
            positions=copy(M.INTERFACES[family]), supportedVehicles=copy(fits),
            distribution="base", origin="launch", fidelity=M.FIDELITY[family] or "modelled" }
        designs[#designs+1], byId[id] = d, d
    end
    for _, family in ipairs(M.FAMILIES) do
        local r=content[family]
        add(family,"street",r.street,all)
        add(family,"sport",r.sport,r.sportFits)
        if r.premium then add(family,"premium",r.premium,all) end
    end

    -- A terminal's component channel is genuinely its own: new immutable Designs, new serialized supply,
    -- and fitment aimed at that terminal's models. Base Market designs are never re-listed elsewhere.
    for marketIndex,market in ipairs(Markets.MARKETS) do
        if not market.universallyKnown then
            for familyIndex,family in ipairs(market.partFamilies or {}) do
                local tier=((marketIndex+familyIndex)%4==0) and "premium" or "sport"
                local effect=M.EFFECT[tier]; local designId=("%s:%s:%s"):format(market.marketId,family,tier)
                local maker=(market.specialty or "Autofixer")
                local d={designId=designId,lineageId=("%s:%s"):format(market.marketId,family),revision=1,
                    manufacturer=maker,makerKey=market.marketId,family=family,tier=tier,effect=effect,
                    code=("AFX-%02d-%s-%03d"):format(marketIndex-1,abbreviations[family],math.floor(effect*100+.5)),
                    subtitle=(market.specialty or "Autofixer").." System",
                    price=(tier=="premium" and (content[family].premium or math.floor(content[family].sport*1.65))) or content[family].sport,
                    positions=copy(M.INTERFACES[family]),supportedVehicles=copy(market.vehicles),
                    distribution="autofixer",marketId=market.marketId,origin="autofixer",fidelity=M.FIDELITY[family] or "modelled"}
                designs[#designs+1],byId[designId]=d,d
            end
        end
    end

    local function has(list, value) for _,v in ipairs(list or {}) do if v==value then return true end end return false end
    function M.designs() return designs end
    function M.byId(id) return byId[id] end
    function M.resolve(designOrId, vehicleKey)
        local d=type(designOrId)=="table" and designOrId or byId[designOrId]
        if not d then return { outcome="malformed", compatible=false, reason="unknown component design" } end
        if not Vehicles.byKey(vehicleKey) then
            return { outcome="unknown_vehicle", compatible=false, reason="no v1 Machine interface profile" }
        end
        if has(d.supportedVehicles,vehicleKey) then return { outcome="fits",compatible=true,reason="all required interfaces match" } end
        return { outcome="mismatch",compatible=false,reason="interface standard or rating does not match" }
    end
    function M.marketAdmissible(designOrId, displayed)
        local fits=0
        for _,key in ipairs(displayed or M.STARTER_VEHICLES) do
            local r=M.resolve(designOrId,key)
            if r.outcome=="unknown_vehicle" or r.outcome=="malformed" then return false,"unresolved:"..key end
            if r.compatible then fits=fits+1 end
        end
        return fits>=2, fits>=2 and nil or "fewer_than_two_supported_starter_architectures"
    end
    function M.factoryDesign(vehicleKey,family)
        if not Vehicles.byKey(vehicleKey) or not M.INTERFACES[family] then return nil end
        return { designId=("factory:%s:%s"):format(vehicleKey,family), lineageId=("factory:%s:%s"):format(vehicleKey,family),
            revision=1, manufacturer="Factory", makerKey="factory", family=family, tier="factory", effect=1.0,
            code=("OEM-%s-%s"):format(vehicleKey,abbreviations[family]), subtitle="Factory Original",
            price=0, positions=copy(M.INTERFACES[family]), supportedVehicles={vehicleKey}, distribution="factory",
            origin="factory", fidelity=M.FIDELITY[family] or "modelled" }
    end
    function M.priceFor(family,effect)
        local r=content[family]; if not r then return nil end
        local e=math.max(.90,math.min(1.40,tonumber(effect) or 1))
        local p30=r.premium or r.sport*1.65
        local a,b,x
        if e<=1.08 then a,b,x=.5*r.street,r.street,(e-.90)/.18
        elseif e<=1.18 then a,b,x=r.street,r.sport,(e-1.08)/.10
        elseif e<=1.30 then a,b,x=r.sport,p30,(e-1.18)/.12
        else a,b,x=p30,1.75*p30,(e-1.30)/.10 end
        return math.max(200,math.floor((a+(b-a)*x)/50+.5)*50)
    end
    -- Physical stock is priced from its root's real bill and the thrust/capacity and mass it supplies.
    function M.pricePhysical(spec, root)
        local p, base = spec.perf or {}, root.perf or {}
        local field = p.thrustN and "thrustN" or (p.forceN and "forceN" or (p.torqueNm and "torqueNm" or "capacityKg"))
        local value = (tonumber(p[field]) or 1) / math.max(1, tonumber(base[field]) or 1)
        local mass = math.max(0.5, math.min(2, (tonumber(base.massKg) or 1) / math.max(1, tonumber(spec.massKg) or 1)))
        return math.max(500, math.floor((tonumber(root.price) or 1000) * math.max(0.7, math.min(1.5, 0.7 * value + 0.3 * mass)) / 50 + 0.5) * 50)
    end
    return M
end)
