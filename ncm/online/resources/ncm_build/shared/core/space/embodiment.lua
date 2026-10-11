-- ncm-core module: space.embodiment
--
-- L327: which Assetto Corsa car EMBODIES an NCM Machine. Deterministic: a Machine's catalogue key resolves to the same AC
-- car every time unless MAP_VERSION changes. The AC car is a body, never the identity: asset_id, history, parts and
-- resources stay NCM's. Exact matches are rare (Cyberpunk cars are fictional); the table picks the closest body type /
-- size / era / role, and anything unlisted falls to a role pool chosen by a stable hash of the key.
--
-- Parts are not translated here (they are not buffs): the AC-side NCM app applies each installed component's force at its
-- mount through CSP `physics.addForce` -- see ncm/assetto/apps/lua/ncm_embody.
local Core = NcmCore

Core.define("space.embodiment", function(C)
    local M = { version = "0.1.0" }
    M.MAP_VERSION = 1

    -- NCM catalogue key -> AC car folder (all present in the 2026-10-06 inventory) + why
    M.MAP = {
        archer_hella = { car = "ks_maserati_quattroporte", why = "big four-door executive saloon" },
        thorton_galena = { car = "ks_toyota_ae86", why = "small rear-drive budget coupe" },
        makigai_maimai = { car = "abarth500", why = "tiny city car" },
        thorton_colby = { car = "ks_ford_mustang_2015", why = "American muscle" },
        thorton_colby_pickup = { car = "ks_ford_mustang_2015", why = "American muscle (no pickup in the AC roster: approximate)" },
        quadra_type66 = { car = "ks_ford_mustang_2015", why = "muscle coupe" },
        quadra_turbo_r = { car = "ks_corvette_c7_stingray", why = "American sports car" },
        quadra_sport_r7 = { car = "ks_corvette_c7_stingray", why = "American sports car" },
        herrera_outlaw = { car = "ks_audi_r8_plus", why = "mid-engine performance GT" },
        mizutani_shion = { car = "ks_nissan_370z", why = "Japanese two-door sports car" },
        rayfield_caliburn = { car = "ks_pagani_huayra_bc", why = "hypercar" },
        rayfield_aerondight = { car = "ks_lamborghini_aventador_sv", why = "hypercar" },
        porsche_911_turbo = { car = "ks_porsche_911_carrera_rsr", why = "classic 911 (the closest era in the roster)" },
        villefort_alvarado = { car = "ks_mercedes_190_evo2", why = "boxy luxury coupe/saloon" },
        villefort_cortes = { car = "ks_porsche_panamera", why = "luxury saloon" },
        chevillon_emperor = { car = "ks_porsche_cayenne", why = "large luxury vehicle" },
        chevillon_thrax = { car = "ks_maserati_quattroporte", why = "luxury saloon" },
        yaiba_kusanagi = { car = "ktm_xbow_r", why = "no motorcycles in AC: the lightest open car instead (expression loss)" },
        ncx_rb15 = { car = "ks_ferrari_sf70h", why = "modern Formula car" },
    }
    M.POOL = { "bmw_m3_e30", "ks_mazda_mx5_nd", "ks_bmw_m4", "ks_toyota_gt86", "ks_audi_a1s1", "ks_alfa_giulia_qv", "ks_nissan_gtr" }

    local function hash(s)
        local h = 2166136261
        for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967296 end   -- plain arithmetic: LuaJIT has no `~`
        return h
    end

    --- The AC body for a Machine. Returns { car, why, exact = false, mapVersion }.
    function M.forMachine(vehicleKey)
        local m = M.MAP[vehicleKey or ""]
        if m then return { car = m.car, why = m.why, exact = false, mapVersion = M.MAP_VERSION } end
        local k = tostring(vehicleKey or "unknown")
        local car = M.POOL[hash(k) % #M.POOL + 1]
        return { car = car, why = "no authored match: a stable pick from the general pool", exact = false, mapVersion = M.MAP_VERSION }
    end

    return M
end)
