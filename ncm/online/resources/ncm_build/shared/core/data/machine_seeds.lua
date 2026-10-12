-- ncm-core module: data.machine_seeds
--
-- L336: AUTHORED passports (provenance `authored`). Two tables, one shape:
--   CYBERPUNK  every catalogue machine (data.vehicle_catalogue keys): body, doors, size, drive, mass/top-speed class and the
--              five character axes (machine.passport.AXES). Cyberpunk's cars are fictional: these are NCM's reading of them.
--   AC_BODY    Assetto Corsa's stock models by folder: what AC's own data does NOT say (body, doors, seats, character).
--              AC's ui_car.json gives brand, power, weight, top speed and tags -- those are ingested as host data by the
--              bridge; this table only adds morphology and character. Variants (_s1, _drift, ...) inherit from their base.
-- Character: econ economy<->exotic, perf utility<->performance, race road<->race, size compact<->large, odd conventional<->unusual.
local Core = NcmCore

Core.define("data.machine_seeds", function(C)
    local M = { version = "0.1.0" }

    local function car(maker, model, body, doors, seats, lengthM, drive, engine, massKg, topKph, econ, perf, race, size, odd, kind)
        return {
            identity = { maker = maker, model = model },
            morphology = { kind = kind or "car", body = body, doors = doors, seats = seats, wheels = (kind == "bike") and 2 or 4, lengthM = lengthM },
            architecture = { drive = drive, engine = engine },
            performance = { massKg = massKg, topKph = topKph },
            character = { econ = econ, perf = perf, race = race, size = size, odd = odd },
        }
    end

    M.CYBERPUNK = {
        -- the owner's Machine: an ordinary, mass-market, conventional four-door saloon -- NOT a luxury or sports saloon
        archer_hella = car("Archer", "Hella EC-D I360", "sedan", 4, 5, 4.7, "fwd", "front", 1500, 167, -0.6, -0.2, -1, 0.1, -0.7),
        archer_bandit = car("Archer", "Bandit", "hatch", 2, 4, 4.0, "fwd", "front", 1200, 170, -0.6, 0.1, -0.8, -0.4, -0.2),
        archer_quartz = car("Archer", "Quartz EC-T2 R660", "coupe", 2, 4, 4.4, "rwd", "front", 1300, 180, -0.4, 0.3, -0.8, -0.2, -0.3),
        makigai_maimai = car("Makigai", "MaiMai P126", "microcar", 2, 2, 2.9, "rwd", "rear", 800, 170, -0.9, -0.4, -1, -1, 0.3),
        makigai_tanishi = car("Makigai", "Tanishi T400 Kuma", "van", 4, 6, 4.6, "awd", "front", 2200, 160, -0.5, -0.8, -1, 0.4, 0.2),
        thorton_galena = car("Thorton", "Galena G240", "coupe", 2, 4, 4.5, "rwd", "front", 1350, 151, -0.9, -0.4, -1, -0.1, -0.5),
        thorton_colby = car("Thorton", "Colby C125", "wagon", 4, 5, 5.0, "rwd", "front", 1700, 167, -0.7, -0.5, -1, 0.4, -0.6),
        thorton_colby_pickup = car("Thorton", "Colby CX410 Butte", "pickup", 2, 3, 5.2, "rwd", "front", 1900, 168, -0.8, -0.8, -1, 0.5, -0.4),
        thorton_mackinaw = car("Thorton", "Mackinaw MTL1", "pickup", 2, 3, 5.8, "awd", "front", 2600, 160, -0.6, -0.8, -1, 0.9, -0.2),
        thorton_merrimac = car("Thorton", "Merrimac Warlock", "suv", 4, 5, 5.2, "awd", "front", 2300, 165, -0.4, -0.6, -1, 0.7, -0.1),
        villefort_columbus = car("Villefort", "Columbus V340-F Freight", "van", 4, 3, 5.4, "rwd", "front", 2300, 167, -0.6, -0.9, -1, 0.7, -0.4),
        villefort_cortes = car("Villefort", "Cortes V5000 Valor", "sedan", 4, 5, 5.1, "rwd", "front", 1800, 193, 0.1, 0.1, -1, 0.5, -0.5),
        villefort_alvarado = car("Villefort", "Alvarado V4F 570 Delegate", "convertible", 2, 4, 5.6, "rwd", "front", 2000, 200, 0.6, 0.2, -1, 0.7, 0.3),
        villefort_deleon = car("Villefort", "Deleon V410 Coupe", "coupe", 2, 4, 5.2, "rwd", "front", 1700, 210, 0.4, 0.5, -0.8, 0.4, 0.1),
        villefort_deleon_sport = car("Villefort", "Deleon Vindicator", "coupe", 2, 4, 5.2, "rwd", "front", 1650, 220, 0.4, 0.6, -0.6, 0.4, 0.1),
        chevillon_thrax = car("Chevillon", "Thrax 388 Jefferson", "sedan", 4, 5, 5.3, "rwd", "front", 1900, 210, 0.4, 0.3, -1, 0.6, -0.3),
        chevillon_emperor = car("Chevillon", "Emperor 620 Ragnar", "sedan", 4, 5, 5.9, "rwd", "front", 2600, 180, 0.5, -0.2, -1, 1, 0.1),
        chevillon_legatus = car("Chevillon", "Legatus 450 Aquila", "suv", 4, 5, 5.4, "awd", "front", 2500, 190, 0.4, -0.2, -1, 0.8, 0),
        mahir_supron = car("Mahir", "Supron FS3", "suv", 4, 5, 4.9, "awd", "front", 2100, 175, -0.4, -0.5, -1, 0.6, -0.3),
        mizutani_hozuki = car("Mizutani", "Hozuki MH1", "hatch", 4, 5, 4.4, "fwd", "front", 1400, 180, -0.3, 0.1, -0.9, -0.2, -0.2),
        mizutani_shion = car("Mizutani", "Shion MZ2", "coupe", 2, 2, 4.5, "rwd", "front", 1400, 230, 0.3, 0.8, -0.3, -0.1, 0),
        mizutani_shion_targa = car("Mizutani", "Shion Targa", "convertible", 2, 2, 4.5, "rwd", "front", 1400, 230, 0.4, 0.8, -0.3, -0.1, 0.1),
        mizutani_shion_nomad = car("Mizutani", "Shion Coyote", "coupe", 2, 2, 4.6, "awd", "front", 1500, 210, 0.2, 0.6, -0.5, 0, 0.5),
        quadra_type66 = car("Quadra", "Type-66 640 TS", "muscle", 2, 2, 4.8, "rwd", "front", 1600, 210, -0.1, 0.7, -0.5, 0.2, 0),
        quadra_type66_avenger = car("Quadra", "Type-66 Avenger", "muscle", 2, 2, 4.8, "rwd", "front", 1650, 215, 0, 0.8, -0.4, 0.2, 0.1),
        quadra_type66_nomad = car("Quadra", "Type-66 Jen Rowley", "muscle", 2, 2, 4.9, "rwd", "front", 1700, 200, -0.1, 0.6, -0.6, 0.3, 0.6),
        quadra_turbo_r = car("Quadra", "Turbo-R V-Tech", "coupe", 2, 2, 4.6, "rwd", "front", 1450, 250, 0.5, 0.9, -0.2, 0, 0),
        quadra_sport_r7 = car("Quadra", "Sport R-7", "coupe", 2, 2, 4.6, "rwd", "front", 1400, 260, 0.6, 0.9, 0, 0, 0.1),
        herrera_outlaw = car("Herrera", "Outlaw GTS", "supercar", 2, 2, 4.6, "rwd", "mid", 1450, 290, 0.6, 0.9, -0.1, 0, 0),
        herrera_riptide = car("Herrera", "Riptide GT2", "supercar", 2, 2, 4.6, "awd", "mid", 1500, 280, 0.6, 0.9, 0, 0, 0.3),
        rayfield_caliburn = car("Rayfield", "Caliburn", "supercar", 2, 2, 4.7, "awd", "mid", 1350, 320, 1, 1, 0.2, 0, 0.6),
        rayfield_aerondight = car("Rayfield", "Aerondight S", "supercar", 2, 2, 4.9, "awd", "mid", 1600, 330, 1, 0.9, 0, 0.2, 0.4),
        yaiba_semimaru = car("Yaiba", "Semimaru", "supercar", 2, 2, 4.7, "awd", "mid", 1400, 320, 1, 1, 0.2, 0, 0.5),
        porsche_911_turbo = car("Porsche", "911 II (930) Turbo", "coupe", 2, 4, 4.3, "rwd", "rear", 1300, 260, 0.6, 0.8, -0.4, -0.2, 0),
        porsche_911_turbo_cabrio = car("Porsche", "911 II (930) Turbo Cabriolet", "convertible", 2, 4, 4.3, "rwd", "rear", 1350, 255, 0.6, 0.8, -0.4, -0.2, 0.1),
        arch_nazare = car("Arch", "Nazaré", "bike", 0, 2, 2.3, "rwd", "mid", 260, 260, 0.6, 0.9, -0.4, -1, 0.5, "bike"),
        brennan_apollo = car("Brennan", "Apollo", "bike", 0, 2, 2.1, "rwd", "mid", 220, 200, -0.4, 0.4, -0.8, -1, -0.3, "bike"),
        brennan_apollo_sport = car("Brennan", "Apollo Scorpion", "bike", 0, 2, 2.1, "rwd", "mid", 210, 215, -0.2, 0.6, -0.6, -1, -0.2, "bike"),
        brennan_apollo_nomad = car("Brennan", "Apollo Nomad", "bike", 0, 2, 2.2, "rwd", "mid", 230, 200, -0.2, 0.4, -0.8, -1, 0.4, "bike"),
        yaiba_kusanagi = car("Yaiba", "Kusanagi CT-3X", "bike", 0, 1, 2.2, "rwd", "mid", 200, 250, 0.4, 0.9, -0.2, -1, 0.1, "bike"),
        yaiba_kusanagi_tyger = car("Yaiba", "Kusanagi Tyger Claws", "bike", 0, 1, 2.2, "rwd", "mid", 200, 250, 0.4, 0.9, -0.2, -1, 0.3, "bike"),
        yaiba_kusanagi_animal = car("Yaiba", "Kusanagi Animals", "bike", 0, 1, 2.2, "rwd", "mid", 200, 250, 0.4, 0.9, -0.2, -1, 0.3, "bike"),
        yaiba_muramasa = car("Yaiba", "Kusanagi Muramasa", "bike", 0, 1, 2.2, "rwd", "mid", 190, 260, 0.5, 1, 0, -1, 0.3, "bike"),
        militech_hellhound = car("Militech", "Hellhound", "suv", 4, 4, 5.6, "awd", "front", 4000, 170, 0.3, -0.4, -1, 1, 0.8, "truck"),
        ncx_rb15 = car("Red Bull Racing", "RB15", "formula", 0, 1, 5.6, "rwd", "mid", 743, 350, 1, 1, 1, -0.2, 0.2, "formula"),
    }

    -- Assetto Corsa stock bodies (what ui_car.json does not say). { body, doors, seats, econ, perf, race, size, odd }
    local function ac(body, doors, seats, econ, perf, race, size, odd)
        return { morphology = { body = body, doors = doors, seats = seats }, character = { econ = econ, perf = perf, race = race, size = size, odd = odd } }
    end
    M.AC_BODY = {
        abarth500 = ac("hatch", 2, 4, -0.5, 0.4, -0.6, -0.9, -0.2),
        alfa_romeo_giulietta_qv = ac("hatch", 4, 5, -0.4, 0.3, -0.7, -0.3, -0.5),
        ks_alfa_mito_qv = ac("hatch", 2, 4, -0.5, 0.3, -0.7, -0.6, -0.4),
        ks_audi_a1s1 = ac("hatch", 2, 4, -0.3, 0.4, -0.6, -0.6, -0.4),
        ks_alfa_giulia_qv = ac("sedan", 4, 5, 0.3, 0.7, -0.5, 0.2, -0.3),
        ks_maserati_quattroporte = ac("sedan", 4, 5, 0.6, 0.5, -0.8, 0.7, -0.2),
        ks_porsche_panamera = ac("sedan", 4, 4, 0.7, 0.6, -0.7, 0.7, -0.1),
        ks_mercedes_190_evo2 = ac("sedan", 4, 2, 0.1, 0.7, 0.8, 0, -0.2),
        bmw_m3_e30 = ac("sedan", 2, 4, -0.1, 0.6, -0.4, -0.2, -0.4),
        bmw_m3_e92 = ac("coupe", 2, 4, 0.2, 0.7, -0.5, 0.1, -0.4),
        bmw_1m = ac("coupe", 2, 4, 0.1, 0.7, -0.5, -0.2, -0.4),
        ks_bmw_m4 = ac("coupe", 2, 4, 0.3, 0.7, -0.5, 0.1, -0.4),
        bmw_z4 = ac("convertible", 2, 2, 0.2, 0.6, -0.6, -0.3, -0.3),
        ks_toyota_ae86 = ac("coupe", 2, 4, -0.7, 0.2, -0.7, -0.4, -0.5),
        ks_toyota_gt86 = ac("coupe", 2, 4, -0.3, 0.5, -0.6, -0.4, -0.5),
        ks_toyota_supra_mkiv = ac("coupe", 2, 4, 0, 0.7, -0.5, -0.1, -0.2),
        ks_mazda_miata = ac("convertible", 2, 2, -0.5, 0.4, -0.6, -0.8, -0.4),
        ks_mazda_mx5_nd = ac("convertible", 2, 2, -0.4, 0.4, -0.6, -0.8, -0.4),
        ks_mazda_rx7_spirit_r = ac("coupe", 2, 2, -0.1, 0.7, -0.5, -0.3, 0),
        ks_nissan_370z = ac("coupe", 2, 2, -0.1, 0.6, -0.6, -0.2, -0.4),
        ks_nissan_skyline_r34 = ac("coupe", 2, 4, 0.1, 0.7, -0.5, -0.1, -0.2),
        ks_nissan_gtr = ac("coupe", 2, 4, 0.4, 0.9, -0.4, 0.1, -0.2),
        ks_ford_mustang_2015 = ac("muscle", 2, 4, 0, 0.6, -0.6, 0.2, -0.4),
        ks_corvette_c7_stingray = ac("coupe", 2, 2, 0.2, 0.8, -0.5, 0, -0.3),
        ks_maserati_alfieri = ac("coupe", 2, 2, 0.6, 0.7, -0.6, 0.2, 0.2),
        ks_maserati_levante = ac("suv", 4, 5, 0.6, 0.4, -0.9, 0.7, -0.2),
        ks_porsche_cayenne = ac("suv", 4, 5, 0.6, 0.5, -0.9, 0.7, -0.2),
        ks_porsche_macan = ac("suv", 4, 5, 0.5, 0.5, -0.9, 0.5, -0.3),
        ks_porsche_718_boxster_s = ac("convertible", 2, 2, 0.4, 0.7, -0.5, -0.3, -0.3),
        ks_porsche_718_cayman_s = ac("coupe", 2, 2, 0.4, 0.7, -0.5, -0.3, -0.3),
        ks_porsche_991_carrera_s = ac("coupe", 2, 4, 0.6, 0.8, -0.4, -0.1, -0.2),
        ks_porsche_991_turbo_s = ac("coupe", 2, 4, 0.7, 0.9, -0.4, -0.1, -0.2),
        ks_porsche_911_gt3_rs = ac("coupe", 2, 2, 0.7, 0.9, 0, -0.1, -0.1),
        ks_porsche_911_r = ac("coupe", 2, 2, 0.8, 0.9, -0.2, -0.1, 0),
        ks_porsche_cayman_gt4_std = ac("coupe", 2, 2, 0.5, 0.8, -0.1, -0.3, -0.2),
        ks_audi_sport_quattro = ac("coupe", 2, 4, 0.3, 0.7, -0.2, -0.2, 0.1),
        ks_audi_r8_plus = ac("supercar", 2, 2, 0.8, 0.9, -0.3, 0, -0.1),
        ferrari_458 = ac("supercar", 2, 2, 0.9, 0.9, -0.3, 0, 0),
        ks_ferrari_488_gtb = ac("supercar", 2, 2, 0.9, 0.9, -0.3, 0, 0),
        ks_ferrari_812_superfast = ac("supercar", 2, 2, 1, 0.9, -0.4, 0.2, 0),
        ferrari_f40 = ac("supercar", 2, 2, 1, 1, -0.2, 0, 0.2),
        ferrari_laferrari = ac("supercar", 2, 2, 1, 1, -0.1, 0, 0.3),
        ks_lamborghini_aventador_sv = ac("supercar", 2, 2, 1, 1, -0.2, 0.1, 0.4),
        ks_lamborghini_huracan_performante = ac("supercar", 2, 2, 1, 0.9, -0.2, 0, 0.2),
        ks_lamborghini_gallardo_sl = ac("supercar", 2, 2, 0.9, 0.9, -0.3, 0, 0.2),
        ks_lamborghini_countach = ac("supercar", 2, 2, 1, 0.8, -0.4, 0, 0.6),
        ks_mclaren_570s = ac("supercar", 2, 2, 0.9, 0.9, -0.3, 0, 0),
        ks_mclaren_p1 = ac("supercar", 2, 2, 1, 1, -0.1, 0, 0.3),
        mclaren_mp412c = ac("supercar", 2, 2, 0.9, 0.9, -0.3, 0, 0),
        mercedes_sls = ac("supercar", 2, 2, 0.9, 0.8, -0.4, 0.1, 0.2),
        ks_pagani_huayra_bc = ac("supercar", 2, 2, 1, 1, -0.1, 0, 0.5),
        pagani_huayra = ac("supercar", 2, 2, 1, 1, -0.2, 0, 0.5),
        ks_porsche_918_spyder = ac("supercar", 2, 2, 1, 1, -0.2, 0, 0.2),
        lotus_elise_sc = ac("convertible", 2, 2, 0.2, 0.8, -0.3, -0.8, 0.1),
        lotus_exige_s = ac("coupe", 2, 2, 0.3, 0.8, -0.2, -0.7, 0.1),
        lotus_evora_s = ac("coupe", 2, 4, 0.4, 0.7, -0.5, -0.3, 0),
        ktm_xbow_r = ac("prototype", 0, 2, 0.4, 0.9, 0.2, -0.9, 0.8),
        ks_abarth_595ss = ac("microcar", 2, 4, -0.8, -0.2, -0.8, -1, 0.1),
    }

    --- The authored AC body for a folder, inheriting from its base (ferrari_458_s3 -> ferrari_458).
    function M.acBody(folder)
        local f = tostring(folder or "")
        while f ~= "" do
            if M.AC_BODY[f] then return M.AC_BODY[f], f end
            local cut = f:match("^(.*)_[^_]+$")
            if not cut then break end
            f = cut
        end
        return nil
    end

    return M
end)
