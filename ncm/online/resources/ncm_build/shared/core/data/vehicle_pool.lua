-- ncm-core data: data.vehicle_pool
-- NCM's street vehicle pool, carried over from the SP payload (data/vehicle_pool.lua, NCM 2.0).
-- Records are TweakDB ids; prestige 1..5 as in SP; tags are metadata. Hosts decide how a record is
-- spawned (online: the `_player` variant of a record where the catalogue has one).
local Core = NcmCore

Core.define("data.vehicle_pool", function(C)
    local M = { version = "0.0.1" }

    M.CLASS_ORDER = { "Muscle", "Sport", "Tech", "Nomad", "Bike", "Formula" }

    M.RECORDS = {
    Muscle = {
        { id = "Vehicle.v_standard2_thorton_galena",        prestige = 1, tags = { "budget", "starter"         } },
        { id = "Vehicle.v_standard25_thorton_colby_pickup", prestige = 1, tags = { "budget", "utility"         } },
        { id = "Vehicle.v_standard2_thorton_colby",         prestige = 2, tags = { "street", "muscle"          } },
        { id = "Vehicle.v_standard25_villefort_columbus",   prestige = 2, tags = { "street", "utility"         } },
        { id = "Vehicle.v_sport2_quadra_type66",            prestige = 3, tags = { "muscle", "classic"         } },
        { id = "Vehicle.v_sport2_villefort_alvarado",       prestige = 4, tags = { "muscle", "luxury"          } },
        { id = "Vehicle.v_sport2_villefort_deleon",         prestige = 4, tags = { "muscle", "race", "iconic"  } },
    },
    Sport = {
        { id = "Vehicle.v_sport1_herrera_outlaw",           prestige = 2, tags = { "street", "sport"           } },
        { id = "Vehicle.v_sport2_mizutani_shion",           prestige = 3, tags = { "sport", "tech"             } },
        { id = "Vehicle.v_sport1_quadra_turbo",             prestige = 4, tags = { "sport", "race"             } },
        { id = "Vehicle.v_sport1_rayfield_caliburn",        prestige = 5, tags = { "halo", "race", "sport"     } },
        { id = "Vehicle.v_sport1_rayfield_aerondight",      prestige = 5, tags = { "halo", "iconic", "sport"   } },
        { id = "Vehicle.v_sport1_herrera_riptide",          prestige = 4, tags = { "sport", "update"          } },
        { id = "Vehicle.v_sport1_quadra_sport_r7",          prestige = 4, tags = { "sport", "phantom_liberty" } },
        { id = "Vehicle.v_sport1_yaiba_semimaru",           prestige = 5, tags = { "halo", "update"           } },
        { id = "Vehicle.v_sport2_mizutani_shion_targa",     prestige = 4, tags = { "sport", "update"          } },
        { id = "Vehicle.v_sport2_porsche_911turbo",         prestige = 5, tags = { "iconic", "sport"          } },
        { id = "Vehicle.v_sport2_porsche_911turbo_cabrio",  prestige = 5, tags = { "iconic", "phantom_liberty"} },
        { id = "Vehicle.v_sport2_quadra_type66_avenger",    prestige = 4, tags = { "muscle", "sport"          } },
        { id = "Vehicle.v_sport2_villefort_deleon_sport",   prestige = 4, tags = { "muscle", "update"         } },
    },
    Tech = {
        { id = "Vehicle.v_standard2_makigai_maimai",        prestige = 1, tags = { "budget", "tech"            } },
        { id = "Vehicle.v_standard2_archer_hella",          prestige = 2, tags = { "street", "tech"            } },
        { id = "Vehicle.v_standard25_mahir_supron",         prestige = 2, tags = { "street", "tech"            } },
        { id = "Vehicle.v_standard2_villefort_cortes",      prestige = 2, tags = { "street", "tech"            } },
        { id = "Vehicle.v_standard3_chevalier_emperor",     prestige = 3, tags = { "executive", "tech"         } },
        { id = "Vehicle.v_standard2_chevalier_thrax",       prestige = 4, tags = { "executive", "tech", "race" } },
        { id = "Vehicle.v_standard2_archer_bandit",          prestige = 2, tags = { "street", "update"           } },
        { id = "Vehicle.v_standard2_archer_quartz",          prestige = 2, tags = { "street", "tech"             } },
        { id = "Vehicle.v_standard2_mizutani_hozuki",        prestige = 2, tags = { "street", "update"           } },
        { id = "Vehicle.v_standard25_thorton_merrimac",      prestige = 3, tags = { "utility", "phantom_liberty" } },
        { id = "Vehicle.v_standard3_makigai_tanishi",        prestige = 2, tags = { "utility", "phantom_liberty" } },
        { id = "Vehicle.v_standard3_militech_hellhound",     prestige = 5, tags = { "armored", "phantom_liberty" } },
        -- 2026-10-12 (owner: "expand the machine index to include the av flying vehicle from trauma team"): the Trauma
        -- Team AV -- the Zetatech Atlus on the game's own four-wheel vehicle rig. Flies only on NCM's propulsion.
        { id = "Vehicle.av_zetatech_atlus",                  prestige = 5, tags = { "aerial", "trauma_team"     } },
        { id = "Vehicle.v_utility4_chevalier_legatus",       prestige = 4, tags = { "utility", "update"           } },
    },
    Nomad = {
        { id = "Vehicle.v_standard25_thorton_colby_pickup", prestige = 1, tags = { "budget", "offroad"         } },
        { id = "Vehicle.v_standard25_villefort_columbus",   prestige = 2, tags = { "street", "utility"         } },
        { id = "Vehicle.v_standard3_thorton_mackinaw",      prestige = 2, tags = { "offroad", "nomad"          } },
        { id = "Vehicle.v_sport2_quadra_type66_nomad",      prestige = 3, tags = { "offroad", "iconic"         } },
        { id = "Vehicle.v_sport2_mizutani_shion_nomad",     prestige = 4, tags = { "offroad", "premium", "halo"} },
    },
    -- Formula: the RB15 F1 (Nexus 31543, inert repack) + NCM team liveries. Not game data: a client
    -- without the mod spawns nothing (KB-8: hosted mods are not deliverable yet; TW1 installs by hand).
    -- Team liveries are records `Vehicle.v_sport1_rb15_f1_<teamId>` (see competition.teams `livery`).
    Formula = {
        { id = "Vehicle.v_sport1_rb15_f1",                  prestige = 5, tags = { "formula", "rb15", "mod" } },
    },
    Bike = {
        { id = "Vehicle.v_sportbike3_brennan_apollo",               prestige = 1, tags = { "bike", "motorcycle", "street", "apollo"   } },
        { id = "Vehicle.v_sportbike3_brennan_apollo_sport",         prestige = 2, tags = { "bike", "motorcycle", "sport", "apollo"    } },
        { id = "Vehicle.v_sportbike3_brennan_apollo_nomad",         prestige = 4, tags = { "bike", "motorcycle", "nomad", "apollo"    } },
        { id = "Vehicle.v_sportbike1_yaiba_kusanagi_tyger",         prestige = 4, tags = { "bike", "motorcycle", "race", "kusanagi"  } },
        { id = "Vehicle.v_sportbike1_yaiba_kusanagi_animal",        prestige = 4, tags = { "bike", "motorcycle", "race", "yaiba"     } },
        { id = "Vehicle.v_sportbike1_yaiba_kusanagi",               prestige = 4, tags = { "bike", "motorcycle", "sport"              } },
        { id = "Vehicle.v_sportbike1_yaiba_muramasa",               prestige = 5, tags = { "bike", "motorcycle", "update"             } },
        { id = "Vehicle.v_sportbike2_arch",                          prestige = 3, tags = { "bike", "motorcycle", "street"             } },
    },
    }

    function M.classes()
        local out = {}
        for i = 1, #M.CLASS_ORDER do out[i] = M.CLASS_ORDER[i] end
        return out
    end

    function M.isClass(name)
        for _, c in ipairs(M.CLASS_ORDER) do
            if c == name then return true end
        end
        return false
    end

    local index = nil
    --- A record may belong to SEVERAL classes on purpose: the Colby pickup and the Villefort Columbus are both
    --- Muscle and Nomad, and carry different tags in each ("utility" vs "offroad"). Any lookup that returns one
    --- class silently picks a winner, which would make a pickup mysteriously ineligible for a Muscle
    --- championship. So membership is a list and tags are the union.
    local function build()
        if index then return index end
        index = {}
        for _, class in ipairs(M.CLASS_ORDER) do
            for _, r in ipairs(M.RECORDS[class] or {}) do
                local e = index[r.id]
                if not e then
                    e = { id = r.id, classes = {}, prestige = tonumber(r.prestige) or 1, tags = {} }
                    index[r.id] = e
                end
                e.classes[#e.classes + 1] = class
                for _, t in ipairs(r.tags or {}) do
                    local had = false
                    for _, x in ipairs(e.tags) do if x == t then had = true end end
                    if not had then e.tags[#e.tags + 1] = t end
                end
            end
        end
        return index
    end

    --- One record by its TweakDB id: { id, classes = { … }, prestige, tags } or nil.
    --- Ownership and eligibility both need "what is this car?" and neither should parse a record id to find out
    --- (IDEA-113: a parsed id is not a catalogue).
    function M.byRecord(id)
        if type(id) ~= "string" then return nil end
        return build()[id]
    end

    --- Is this record in the given class? The membership question, asked directly.
    function M.inClass(id, class)
        local e = M.byRecord(id)
        if not e then return false end
        for _, c in ipairs(e.classes) do if c == class then return true end end
        return false
    end

    --- Every DISTINCT record in the pool, in CLASS_ORDER of first appearance: { id, classes, prestige, tags }.
    function M.allRecords()
        local seen, out = {}, {}
        for _, class in ipairs(M.CLASS_ORDER) do
            for _, r in ipairs(M.RECORDS[class] or {}) do
                if not seen[r.id] then seen[r.id] = true; out[#out + 1] = build()[r.id] end
            end
        end
        return out
    end

    --- Records of one class, optionally filtered to prestige <= maxPrestige. Returns a new array.
    function M.records(class, maxPrestige)
        local list = M.RECORDS[class]
        if not list then return {} end
        local out = {}
        for _, r in ipairs(list) do
            if maxPrestige == nil or (tonumber(r.prestige) or 1) <= maxPrestige then
                out[#out + 1] = r
            end
        end
        return out
    end

    return M
end)
