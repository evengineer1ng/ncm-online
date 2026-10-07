-- machine.passport + machine.correspondence (L336): one machine, every host expresses it -- gated, explainable, sticky.
local here = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", "")
local function roster() return dofile(here .. "fixture_ac_roster.lua") end
local TEAL = { 24, 78, 88 }   -- the owner's Hella paint (data.vehicle_config "Deep Teal")

local function mods(T) return T.Core.get("machine.passport"), T.Core.get("machine.correspondence") end
local function acCatalogue(T)
    local P = mods(T)
    local cat = {}
    for _, c in ipairs(roster()) do cat[#cat + 1] = { id = c.id, passport = P.fromAc(c.id, c.ui), variants = c.skins } end
    return cat
end

return {
    every_field_says_where_it_came_from = function(T)
        local P = mods(T)
        local p = P.forMachine("archer_hella", "asset-1", { paint = TEAL, massKg = 1612 })
        local body, f = P.get(p, "morphology", "body")
        T.eq(body, "sedan", "the Hella is a saloon")
        T.eq(f.src, "authored", "and NCM authored that")
        local mass, mf = P.get(p, "performance", "massKg")
        T.eq(mass, 1612, "a MEASURED mass outranks the authored one")
        T.eq(mf.src, "measured", "and says so")
        T.ok(mf.alt and mf.alt.src == "authored", "the authored value is kept, not lost")
    end,

    the_hella_is_not_the_maserati = function(T)
        local P, X = mods(T)
        local me = P.forMachine("archer_hella", "asset-1", { paint = TEAL })
        local ranked = X.rank(me, acCatalogue(T))
        local pos = {}
        for i, r in ipairs(ranked) do pos[r.id] = i end
        T.ok(ranked[1].id ~= "ks_maserati_quattroporte", ("the Hella's AC body is not the Quattroporte (got %s)"):format(ranked[1].id))
        T.ok(pos.ks_maserati_quattroporte > 3, "the luxury saloon ranks below the everyday cars")
        T.ok(pos.alfa_romeo_giulietta_qv < pos.ks_maserati_quattroporte and pos.ks_alfa_giulia_qv < pos.ks_porsche_panamera,
            "ordinary beats glamorous")
        T.ok(ranked[1].reason:find("character", 1, true), "the choice explains itself")
    end,

    the_boring_sedan_beats_the_glamorous_one = function(T)
        local P, X = mods(T)
        local me = P.forMachine("archer_hella", "a", { paint = TEAL })
        local function saloon(id, econ, len)
            return { id = id, passport = P.new({ identity = { maker = "X", model = id },
                morphology = { kind = "car", body = "sedan", doors = 4, seats = 5, wheels = 4, lengthM = len },
                character = { econ = econ, perf = 0, race = -1, size = 0.1, odd = -0.6 }, performance = { topKph = 180 } }, "host_data", 0.8) }
        end
        local r = X.rank(me, { saloon("glamour", 0.8, 4.7), saloon("boring", -0.6, 4.7 * 1.12) })
        T.eq(r[1].id, "boring", "12 % bigger but the same KIND of car wins")
    end,

    a_van_never_wins_a_ferrari = function(T)
        local P, X = mods(T)
        local ferrari = P.fromAc("ferrari_458", { brand = "Ferrari", name = "Ferrari 458 Italia", class = "street",
            tags = { "#Supercars", "rwd", "supercar" }, specs = { bhp = "570bhp", weight = "1573kg", topspeed = "325km/h" } })
        local van = { id = "van", passport = P.new({ morphology = { kind = "car", body = "van", doors = 4, seats = 3, wheels = 4 },
            character = { econ = 0.9, perf = 0.9, race = -0.3, size = 0, odd = 0 }, performance = { topKph = 325, massKg = 1573 } }, "host_data", 0.8) }
        local coupe = { id = "coupe", passport = P.new({ morphology = { kind = "car", body = "coupe", doors = 2, seats = 2, wheels = 4 },
            character = { econ = 0.2, perf = 0.6, race = -0.5, size = 0, odd = 0 }, performance = { topKph = 250, massKg = 1400 } }, "host_data", 0.8) }
        local r = X.rank(ferrari, { van, coupe })
        T.eq(r[1].id, "coupe", "the shape gate keeps the van out even when its numbers line up")
        T.eq(r[#r].tier, "fallback", "the van only ever appears as a fallback")
    end,

    an_exact_model_short_circuits = function(T)
        local P, X = mods(T)
        local mine = P.fromAc("ferrari_458", { brand = "Ferrari", name = "Ferrari 458 Italia", tags = { "#Supercars" }, specs = {} })
        local r = X.rank(mine, acCatalogue(T))
        T.eq(r[1].id, "ferrari_458", "the same car is the same car")
        T.eq(r[1].tier, "exact", "found by identity, not inference")
    end,

    the_paint_picks_the_skin = function(T)
        local P, X = mods(T)
        local red = P.forMachine("archer_hella", "a", { paint = { 140, 20, 20 } })
        local r = X.rank(red, acCatalogue(T))
        local v = r[1].variant
        T.ok(v and v.rgb[1] > v.rgb[2] * 2, ("a red Hella gets a red skin (%s)"):format(v and v.id or "-"))
    end,

    choices_are_sticky_and_revisions_are_explicit = function(T)
        local P, X = mods(T)
        local me = P.forMachine("archer_hella", "a", { paint = TEAL })
        local cat = acCatalogue(T)
        local first, rev = X.decide(me, cat, nil, nil, 100)
        T.ok(first and rev and rev.why:find("first", 1, true), "the first expression is recorded as such")
        -- the established body stays even if another candidate is a little better
        local prior = { id = "ks_alfa_giulia_qv", revision = 1 }
        local keep, rev2 = X.decide(me, cat, prior, nil, 200)
        T.eq(keep.id, "ks_alfa_giulia_qv", "a near-tie does not move the Machine to another body")
        T.eq(rev2, nil, "and no revision is written")
        -- a much worse established body is replaced, with a recorded reason
        local bad = { id = "ks_porsche_cayenne", revision = 3 }
        local better, rev3 = X.decide(me, cat, bad, nil, 300)
        T.ok(better.id ~= "ks_porsche_cayenne" and rev3 and rev3.from == "ks_porsche_cayenne", "a materially better body is a revision")
        T.eq(better.revision, 4, "revisions count up")
    end,

    an_unknown_mod_car_still_travels = function(T)
        local P, X = mods(T)
        local weird = P.forMachine("xyz_superweird_thing_420", "a", { tags = { "sport" }, prestige = 4, paint = { 30, 30, 200 } })
        local _, maker = P.get(weird, "identity", "maker")
        T.eq(maker, nil, "its maker is unknown, not guessed")
        local r = X.rank(weird, acCatalogue(T))
        T.ok(r[1] and r[1].id, ("it still gets a body (%s)"):format(r[1] and r[1].id or "none"))
    end,
}
