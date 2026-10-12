-- Persistent Machine fuel: pure arithmetic only. The host owns storage, vehicle control and presentation.
local Core=NcmCore
Core.define("economy.fuel", function()
    local M = {}
    M.VERSION = 1
    M.DEFAULT_CAPACITY_ML = 60000       -- 60 L
    M.DEFAULT_ML_PER_KM = 350           -- 35 L / 100 km: visible gameplay consumption
    M.LOW_FRACTION = 0.10

    local function finite(n) return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge end
    function M.profile(p)
        p=p or {}; local cap=math.floor(tonumber(p.capacityMl) or M.DEFAULT_CAPACITY_ML)
        local rate=tonumber(p.mlPerKm) or M.DEFAULT_ML_PER_KM
        if cap<1 then cap=M.DEFAULT_CAPACITY_ML end
        if not finite(rate) or rate<=0 then rate=M.DEFAULT_ML_PER_KM end
        return {capacityMl=cap,mlPerKm=rate}
    end
    function M.burn(fuelMl, metres, profile, remainder)
        local p=M.profile(profile);local before=math.max(0,math.min(p.capacityMl,math.floor(tonumber(fuelMl) or p.capacityMl)))
        local raw=math.max(0,tonumber(remainder) or 0)+(math.max(0,tonumber(metres) or 0)*p.mlPerKm/1000)
        local whole=math.floor(raw);local after=math.max(0,before-whole)
        return {beforeMl=before,fuelMl=after,burnedMl=before-after,remainderMl=raw-whole,
            capacityMl=p.capacityMl,fraction=after/p.capacityMl,empty=after<=0,
            becameEmpty=before>0 and after<=0,low=after>0 and after/p.capacityMl<=M.LOW_FRACTION}
    end
    function M.fillCost(fuelMl, profile, centsPerLitre)
        local p=M.profile(profile);local need=math.max(0,p.capacityMl-math.max(0,tonumber(fuelMl) or 0))
        local cents=math.ceil((need/1000)*math.max(0,tonumber(centsPerLitre) or 0))
        return need,cents
    end
    -- `L208`: fuel load heats tyres faster (short term) and wears them faster (long term). Scaled by how
    -- full the tank is, so an empty tank is exactly today's behaviour.
    M.HEAT_AT_FULL = 0.25
    M.TYRE_WEAR_AT_FULL = 0.30
    local function fraction(fuelMl, capacityMl)
        local f, c = tonumber(fuelMl), tonumber(capacityMl) or M.DEFAULT_CAPACITY_ML
        if not f or f ~= f or f <= 0 or not c or c <= 0 then return 0 end
        f = f / c
        if f > 1 then f = 1 end
        return f
    end
    function M.heatFactor(fuelMl, capacityMl) return 1.0 + M.HEAT_AT_FULL * fraction(fuelMl, capacityMl) end
    function M.tyreWearFactor(fuelMl, capacityMl) return 1.0 + M.TYRE_WEAR_AT_FULL * fraction(fuelMl, capacityMl) end

    function M.nearest(position, stations)
        if type(position)~="table" then return nil end
        local best,bestD
        for _,s in ipairs(stations or {}) do
            local dx=(tonumber(s.x) or 0)-(tonumber(position.x) or 0);local dy=(tonumber(s.y) or 0)-(tonumber(position.y) or 0)
            local d=dx*dx+dy*dy;if not bestD or d<bestD then best,bestD=s,d end
        end
        return best,bestD and math.sqrt(bestD) or nil
    end
    return M
end)
