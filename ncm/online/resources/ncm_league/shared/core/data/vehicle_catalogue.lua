-- Durable NCM vehicle identity. vehicleKey names a conceptual machine; records name exact runtime
-- configurations; a live OPEN//77 vehicle id is never accepted here as identity.
local Core = NcmCore

Core.define("data.vehicle_catalogue", function(C)
    local Pool = C.get("data.vehicle_pool")
    -- generation 2 (2026-09-29, KB-204): the Autofixer markets update grew the catalogue 27 -> 45. Bump on every
    -- membership change; the collection refuses a published generation whose size changed underneath it.
    local M = { version = "0.1.0", generation = 2 }

    local META = {
        Vehicle_v_standard2_thorton_galena       = { "Thorton", "Galena" },
        Vehicle_v_standard25_thorton_colby_pickup= { "Thorton", "Colby Pickup" },
        Vehicle_v_standard2_thorton_colby        = { "Thorton", "Colby" },
        Vehicle_v_standard25_villefort_columbus  = { "Villefort", "Columbus" },
        Vehicle_v_sport2_quadra_type66           = { "Quadra", "Type-66" },
        Vehicle_v_sport2_villefort_alvarado      = { "Villefort", "Alvarado" },
        Vehicle_v_sport2_villefort_deleon        = { "Villefort", "Deleon" },
        Vehicle_v_sport1_herrera_outlaw          = { "Herrera", "Outlaw" },
        Vehicle_v_sport2_mizutani_shion          = { "Mizutani", "Shion" },
        Vehicle_v_sport1_quadra_turbo            = { "Quadra", "Turbo-R" },
        Vehicle_v_sport1_rayfield_caliburn       = { "Rayfield", "Caliburn" },
        Vehicle_v_sport1_rayfield_aerondight     = { "Rayfield", "Aerondight" },
        Vehicle_v_standard2_makigai_maimai       = { "Makigai", "MaiMai" },
        Vehicle_v_standard2_archer_hella         = { "Archer", "Hella" },
        Vehicle_v_standard25_mahir_supron        = { "Mahir", "Supron" },
        Vehicle_v_standard2_villefort_cortes     = { "Villefort", "Cortes" },
        Vehicle_v_standard3_chevalier_emperor    = { "Chevillon", "Emperor" },
        Vehicle_v_standard2_chevalier_thrax      = { "Chevillon", "Thrax" },
        Vehicle_v_standard3_thorton_mackinaw     = { "Thorton", "Mackinaw" },
        Vehicle_v_sport2_quadra_type66_nomad     = { "Quadra", "Type-66 Nomad" },
        Vehicle_v_sport2_mizutani_shion_nomad    = { "Mizutani", "Shion Nomad" },
        Vehicle_v_sport1_rb15_f1                 = { "Red Bull Racing", "RB15", "mod" },
        Vehicle_v_sportbike3_brennan_apollo      = { "Brennan", "Apollo" },
        Vehicle_v_sportbike3_brennan_apollo_sport= { "Brennan", "Apollo Sport" },
        Vehicle_v_sportbike3_brennan_apollo_nomad= { "Brennan", "Apollo Nomad" },
        Vehicle_v_sportbike1_yaiba_kusanagi_tyger= { "Yaiba", "Kusanagi Tyger Claw" },
        Vehicle_v_sportbike1_yaiba_kusanagi_animal={ "Yaiba", "Kusanagi Animals" },
        Vehicle_v_sport1_herrera_riptide          = { "Herrera", "Riptide" },
        Vehicle_v_sport1_quadra_sport_r7          = { "Quadra", "Sport R-7" },
        Vehicle_v_sport1_yaiba_semimaru           = { "Yaiba", "Semimaru" },
        Vehicle_v_sport2_mizutani_shion_targa     = { "Mizutani", "Shion Targa" },
        Vehicle_v_sport2_porsche_911turbo         = { "Porsche", "911 Turbo" },
        Vehicle_v_sport2_porsche_911turbo_cabrio  = { "Porsche", "911 Turbo Cabriolet" },
        Vehicle_v_sport2_quadra_type66_avenger    = { "Quadra", "Type-66 Avenger" },
        Vehicle_v_sport2_villefort_deleon_sport   = { "Villefort", "Deleon Vindicator" },
        Vehicle_v_standard2_archer_bandit         = { "Archer", "Quartz Bandit" },
        Vehicle_v_standard2_archer_quartz         = { "Archer", "Quartz" },
        Vehicle_v_standard2_mizutani_hozuki       = { "Mizutani", "Hozuki" },
        Vehicle_v_standard25_thorton_merrimac     = { "Thorton", "Merrimac" },
        Vehicle_v_standard3_makigai_tanishi       = { "Makigai", "Tanishi" },
        Vehicle_v_standard3_militech_hellhound    = { "Militech", "Hellhound" },
        Vehicle_v_utility4_chevalier_legatus      = { "Chevillon", "Legatus" },
        Vehicle_v_sportbike1_yaiba_kusanagi       = { "Yaiba", "Kusanagi CT-3X" },
        Vehicle_v_sportbike1_yaiba_muramasa       = { "Yaiba", "Muramasa" },
        Vehicle_v_sportbike2_arch                 = { "ARCH", "Nazaré" },
    }
    --- **Stable manufacturer identity.** `META[1]` is a DISPLAY NAME and display names are editable; keying
    --- production history off one would mean that renaming "Chevillon" tomorrow silently started a second,
    --- parallel manufacturer sequence and orphaned every serial already issued (addendum section 6).
    ---
    --- So the key is authored, not derived. If a display name ever changes, the LEFT side of a row here
    --- changes and the right side -- the historical identity -- does not. Every manufacturer in META must
    --- appear here; `test_vehicle_catalogue` asserts it, because a missing entry would otherwise mean a new
    --- car quietly minting with no maker sequence at all.
    local MAKER_KEY = {
        ["Thorton"] = "thorton", ["Villefort"] = "villefort", ["Quadra"] = "quadra",
        ["Herrera"] = "herrera", ["Mizutani"] = "mizutani", ["Rayfield"] = "rayfield",
        ["Makigai"] = "makigai", ["Archer"] = "archer", ["Mahir"] = "mahir",
        ["Chevillon"] = "chevillon", ["Red Bull Racing"] = "red_bull_racing",
        ["Brennan"] = "brennan", ["Yaiba"] = "yaiba",
        ["Porsche"] = "porsche", ["Militech"] = "militech", ["ARCH"] = "arch",
    }

    local KEY = {
        Vehicle_v_standard2_thorton_galena="thorton_galena", Vehicle_v_standard25_thorton_colby_pickup="thorton_colby_pickup",
        Vehicle_v_standard2_thorton_colby="thorton_colby", Vehicle_v_standard25_villefort_columbus="villefort_columbus",
        Vehicle_v_sport2_quadra_type66="quadra_type66", Vehicle_v_sport2_villefort_alvarado="villefort_alvarado",
        Vehicle_v_sport2_villefort_deleon="villefort_deleon", Vehicle_v_sport1_herrera_outlaw="herrera_outlaw",
        Vehicle_v_sport2_mizutani_shion="mizutani_shion", Vehicle_v_sport1_quadra_turbo="quadra_turbo_r",
        Vehicle_v_sport1_rayfield_caliburn="rayfield_caliburn", Vehicle_v_sport1_rayfield_aerondight="rayfield_aerondight",
        Vehicle_v_standard2_makigai_maimai="makigai_maimai", Vehicle_v_standard2_archer_hella="archer_hella",
        Vehicle_v_standard25_mahir_supron="mahir_supron", Vehicle_v_standard2_villefort_cortes="villefort_cortes",
        Vehicle_v_standard3_chevalier_emperor="chevillon_emperor", Vehicle_v_standard2_chevalier_thrax="chevillon_thrax",
        Vehicle_v_standard3_thorton_mackinaw="thorton_mackinaw", Vehicle_v_sport2_quadra_type66_nomad="quadra_type66_nomad",
        Vehicle_v_sport2_mizutani_shion_nomad="mizutani_shion_nomad", Vehicle_v_sport1_rb15_f1="ncx_rb15",
        Vehicle_v_sportbike3_brennan_apollo="brennan_apollo", Vehicle_v_sportbike3_brennan_apollo_sport="brennan_apollo_sport",
        Vehicle_v_sportbike3_brennan_apollo_nomad="brennan_apollo_nomad", Vehicle_v_sportbike1_yaiba_kusanagi_tyger="yaiba_kusanagi_tyger",
        Vehicle_v_sportbike1_yaiba_kusanagi_animal="yaiba_kusanagi_animal",
        Vehicle_v_sport1_herrera_riptide="herrera_riptide", Vehicle_v_sport1_quadra_sport_r7="quadra_sport_r7",
        Vehicle_v_sport1_yaiba_semimaru="yaiba_semimaru", Vehicle_v_sport2_mizutani_shion_targa="mizutani_shion_targa",
        Vehicle_v_sport2_porsche_911turbo="porsche_911_turbo", Vehicle_v_sport2_porsche_911turbo_cabrio="porsche_911_turbo_cabrio",
        Vehicle_v_sport2_quadra_type66_avenger="quadra_type66_avenger", Vehicle_v_sport2_villefort_deleon_sport="villefort_deleon_sport",
        Vehicle_v_standard2_archer_bandit="archer_bandit", Vehicle_v_standard2_archer_quartz="archer_quartz",
        Vehicle_v_standard2_mizutani_hozuki="mizutani_hozuki", Vehicle_v_standard25_thorton_merrimac="thorton_merrimac",
        Vehicle_v_standard3_makigai_tanishi="makigai_tanishi", Vehicle_v_standard3_militech_hellhound="militech_hellhound",
        Vehicle_v_utility4_chevalier_legatus="chevillon_legatus", Vehicle_v_sportbike1_yaiba_kusanagi="yaiba_kusanagi",
        Vehicle_v_sportbike1_yaiba_muramasa="yaiba_muramasa", Vehicle_v_sportbike2_arch="arch_nazare",
    }

    local entries, byKey, byRecord = {}, {}, {}
    -- Authoring faults are collected, not raised. This module is loaded at resource start, so an `assert` here
    -- would take the whole league service down -- calendar, races, settlement, weather -- because one new car
    -- lacked a display name. The offline gate asserts these lists are empty (test_vehicle_catalogue), so a
    -- missing entry fails loudly where it is cheap to fix and degrades quietly where it is not.
    local unmapped, conflicts = {}, {}

    local function addRuntime(e, record)
        local owner = byRecord[record]
        if owner and owner ~= e then
            -- two conceptual machines cannot both own one runtime record: resolveRecord would answer whichever
            -- was built last, and discovery would credit the wrong car
            conflicts[#conflicts + 1] = ("record %s claimed by %s and %s"):format(record, owner.vehicleKey, e.vehicleKey)
            return
        end
        if not owner then e.runtimeRecords[#e.runtimeRecords + 1] = record end
        byRecord[record] = e
    end

    for _, p in ipairs(Pool.allRecords()) do
        local lookup = p.id:gsub("%.", "_")
        local m, key = META[lookup], KEY[lookup]
        if not m or not key then
            unmapped[#unmapped + 1] = p.id
        elseif not MAKER_KEY[m[1]] then
            -- Refuse quietly into the fault list rather than mint a car with no manufacturer history.
            conflicts[#conflicts + 1] = ("manufacturer %q has no stable MAKER_KEY (%s)"):format(tostring(m[1]), p.id)
        elseif byKey[key] then
            conflicts[#conflicts + 1] = ("vehicleKey %s claimed twice (%s)"):format(key, p.id)
        else
            local e = {
                vehicleKey = key, displayName = m[2], manufacturer = m[1],
                -- The immutable half of the badge. `manufacturer` is for reading; this is for history.
                manufacturerKey = MAKER_KEY[m[1]],
                -- classes[1] is CLASS_ORDER-stable, so a multi-class machine's headline category never flickers
                category = p.classes[1], categories = p.classes, tags = p.tags, prestige = p.prestige,
                source = m[3] or "native", canonicalGeneration = M.generation, runtimeRecords = {},
            }
            entries[#entries + 1], byKey[key] = e, e
            addRuntime(e, p.id)
            addRuntime(e, p.id .. "_player")
        end
    end
    -- All NCM team liveries and the base/player RB15 are one conceptual machine.
    local rb15 = byKey["ncx_rb15"]
    local LIVERIES = { "arasaka", "herrera", "kang_tao", "militech", "mizutani", "quadra", "rayfield", "thorton", "trauma", "yorinobu" }
    if rb15 then
        for _, suffix in ipairs(LIVERIES) do addRuntime(rb15, "Vehicle.v_sport1_rb15_f1_" .. suffix) end
    end

    function M.entries() return entries end
    function M.byKey(key) return type(key) == "string" and byKey[key] or nil end
    function M.resolveRecord(record) return type(record) == "string" and byRecord[record] or nil end

    -- ---------------------------------------------------------------------------------------------
    -- AUTHORED TOP SPEED (`L157`)
    -- ---------------------------------------------------------------------------------------------
    --
    -- **Top speed is a declared number per car, not an emergent one**, and this is where it is declared.
    -- The governor that applies it (`Open77.vehicles.setPerformance`) takes an absolute km/h, so something
    -- has to hold the baseline that a Machine's parts then scale.
    --
    -- **It is deliberately EMPTY until measured.** The platform exposes `Open77.vehicles.ratedTopSpeed`,
    -- which reads the record's own gearing and rated RPM -- an authored specification rather than a
    -- measurement, which is exactly the right kind of number and exactly why it may be copied in here.
    -- But it is a CLIENT-side call and this is server-side data, so the values arrive by a one-off dump
    -- (`/ncm.ratedtopspeed`) and are then authored, the same way `arch_dump.cpp` already dumps flats for
    -- a human to read rather than for the server to trust at runtime.
    --
    -- **An absent entry means NO CEILING, never a guessed one.** A governor invented from nothing would be
    -- wrong per car and indistinguishable from a real limit, which is worse than having none -- and
    -- `IDEA-328`/`IDEA-331` are explicit that an observation must not quietly become a specification.
    -- ---------------------------------------------------------------------------------------------
    -- AUTHORED top speeds, in km/h. **Specification, never measurement** (`IDEA-328`, `IDEA-331`).
    -- ---------------------------------------------------------------------------------------------
    --
    -- Supplied by the owner 2026-09-27 from published figures for each car, one value per conceptual
    -- machine and repeated for its `_player` variant, because the base car and the player car are
    -- separate TweakDB records that may carry separate drive models.
    --
    -- **An absent record means UNGOVERNED, not zero** (`L157`). The five bikes are deliberately not
    -- here: nobody has confirmed them, and a guessed figure would be indistinguishable from a real one
    -- the moment it was written down. The RB15's twelve livery records are absent for the same reason
    -- plus `L142`, which withdrew the car.
    --
    -- These are what the GOVERNOR aims at. They are not what the gearbox allows -- the gear chain is
    -- deliberately raised above them so that each car is drag-limited rather than gear-limited, and the
    -- governor then places the real ceiling by withholding drive. Headroom above, authority below.
    M.TOP_SPEED_KPH = {
        Vehicle_v_standard2_thorton_galena                         = 151,   -- Galena G240
        Vehicle_v_standard2_thorton_galena_player                  = 151,   -- Galena G240
        Vehicle_v_standard2_thorton_colby                          = 167,   -- Colby C125
        Vehicle_v_standard2_thorton_colby_player                   = 167,   -- Colby C125
        Vehicle_v_standard25_thorton_colby_pickup                  = 168,   -- Colby CX410 Butte
        Vehicle_v_standard25_thorton_colby_pickup_player           = 168,   -- Colby CX410 Butte
        Vehicle_v_standard25_villefort_columbus                    = 167,   -- Columbus V340-F Freight
        Vehicle_v_standard25_villefort_columbus_player             = 167,   -- Columbus V340-F Freight
        Vehicle_v_standard2_villefort_cortes                       = 193,   -- Cortes V5000 Valor
        Vehicle_v_standard2_villefort_cortes_player                = 193,   -- Cortes V5000 Valor
        Vehicle_v_standard2_makigai_maimai                         = 170,   -- MaiMai P126
        Vehicle_v_standard2_makigai_maimai_player                  = 170,   -- MaiMai P126
        Vehicle_v_standard2_archer_hella                           = 167,   -- Hella EC-D I360
        Vehicle_v_standard2_archer_hella_player                    = 167,   -- Hella EC-D I360
        Vehicle_v_standard25_mahir_supron                          = 165,   -- Supron FS3
        Vehicle_v_standard25_mahir_supron_player                   = 165,   -- Supron FS3
        Vehicle_v_standard3_chevalier_emperor                      = 194,   -- Emperor 620 Ragnar
        Vehicle_v_standard3_chevalier_emperor_player               = 194,   -- Emperor 620 Ragnar
        Vehicle_v_standard2_chevalier_thrax                        = 193,   -- Thrax 388 Jefferson
        Vehicle_v_standard2_chevalier_thrax_player                 = 193,   -- Thrax 388 Jefferson
        Vehicle_v_standard3_thorton_mackinaw                       = 181,   -- Mackinaw MTL1
        Vehicle_v_standard3_thorton_mackinaw_player                = 181,   -- Mackinaw MTL1
        Vehicle_v_sport2_quadra_type66                             = 254,   -- Type-66 640 TS
        Vehicle_v_sport2_quadra_type66_player                      = 254,   -- Type-66 640 TS
        Vehicle_v_sport2_quadra_type66_nomad                       = 315,   -- Type-66 Javelina
        Vehicle_v_sport2_quadra_type66_nomad_player                = 315,   -- Type-66 Javelina
        Vehicle_v_sport2_villefort_alvarado                        = 193,   -- Alvarado V4F 570 Delegate
        Vehicle_v_sport2_villefort_alvarado_player                 = 193,   -- Alvarado V4F 570 Delegate
        Vehicle_v_sport2_villefort_deleon                          = 191,   -- Deleon V410-S Coupe
        Vehicle_v_sport2_villefort_deleon_player                   = 191,   -- Deleon V410-S Coupe
        Vehicle_v_sport2_mizutani_shion                            = 281,   -- Shion MZ2
        Vehicle_v_sport2_mizutani_shion_player                     = 281,   -- Shion MZ2
        Vehicle_v_sport2_mizutani_shion_nomad                      = 300,   -- Shion Coyote
        Vehicle_v_sport2_mizutani_shion_nomad_player               = 300,   -- Shion Coyote
        Vehicle_v_sport1_herrera_outlaw                            = 294,   -- Herrera Outlaw
        Vehicle_v_sport1_herrera_outlaw_player                     = 294,   -- Herrera Outlaw
        Vehicle_v_sport1_quadra_turbo                              = 265,   -- Turbo-R 740
        Vehicle_v_sport1_quadra_turbo_player                       = 265,   -- Turbo-R 740
        Vehicle_v_sport1_rayfield_caliburn                         = 337,   -- Rayfield Caliburn
        Vehicle_v_sport1_rayfield_caliburn_player                  = 337,   -- Rayfield Caliburn
        Vehicle_v_sport1_rayfield_aerondight                       = 307,   -- Aerondight Guinevere
        Vehicle_v_sport1_rayfield_aerondight_player                = 307,   -- Aerondight Guinevere
    }

    --- The authored top speed for a record, or nil when nobody has measured it yet.
    function M.topSpeedKph(record)
        if type(record) ~= "string" then return nil end
        return M.TOP_SPEED_KPH[(record:gsub("[%.%-]", "_"))]
    end

    --- The authored top speed for a conceptual MACHINE, or nil when none of its records carries one.
    ---
    --- `entries` has no `record` field -- a machine owns a LIST of runtime records, and the base car and
    --- its `_player` variant are authored with the same figure because they are the same car. So the first
    --- record that answers is the machine's declared figure.
    ---
    --- **This is a DECLARATION, never a measurement** (`L157`, `IDEA-328`, `IDEA-331`). It is what the
    --- governor aims at, sourced from published figures. A surface that shows it must say so, because
    --- `31_CAPABILITY_AUDIT.md` section 5 establishes that the rated figure and the observed one disagree
    --- in a known direction -- torque and drag carry the real terminal velocity higher.
    ---
    --- nil means UNGOVERNED and UNRATED, never zero: the five bikes and the withdrawn RB15 have no
    --- confirmed figure, and a guess would be indistinguishable from a real one.
    function M.declaredTopSpeedKph(entry)
        if type(entry) ~= "table" then return nil end
        for _, record in ipairs(entry.runtimeRecords or {}) do
            local kph = M.topSpeedKph(record)
            if kph then return kph end
        end
        return nil
    end

    --- Which records still have no authored top speed. The dump command reports this so the gap is
    --- visible rather than silently meaning "uncapped forever".
    --- Every runtime record NCM knows, sorted. **`entries` has no `record` field** -- a conceptual machine
    --- owns a LIST of runtime records (`runtimeRecords`), because the base car, its `_player` variant and,
    --- for the RB15, ten liveries are all one Machine. Reading `entry.record` returns nil for every entry,
    --- which is exactly how the first top-speed dump produced zero rows.
    function M.allRecords()
        local out = {}
        for _, entry in ipairs(entries) do
            for _, record in ipairs(entry.runtimeRecords or {}) do out[#out + 1] = record end
        end
        table.sort(out)
        return out
    end

    --- Which records still have no authored top speed, so the gap is visible rather than silently meaning
    --- "uncapped forever".
    function M.withoutTopSpeed()
        local out = {}
        for _, record in ipairs(M.allRecords()) do
            if not M.topSpeedKph(record) then out[#out + 1] = record end
        end
        return out
    end
    function M.count() return #entries end
    function M.slot(entry) return ("g%d:%03d"):format(M.generation, entry._slot or 0) end
    for i, e in ipairs(entries) do e._slot = i end

    --- Pool records this catalogue could not name, and authoring collisions. Both must be empty; the offline
    --- gate enforces that. At runtime they are what `ncm.collection.probe` reports instead of a stack trace.
    function M.unmapped() return unmapped end
    function M.conflicts() return conflicts end
    return M
end)
