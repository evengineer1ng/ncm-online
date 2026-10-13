-- competition.eligibility (IDEA-113, L83): what a championship admits, as data.
local MAIMAI = "Vehicle.v_standard2_makigai_maimai"
local PICKUP = "Vehicle.v_standard25_thorton_colby_pickup"     -- Muscle AND Nomad
local CALIBURN = "Vehicle.v_sport1_rayfield_caliburn"          -- Sport, prestige 5, halo
local AV = "Vehicle.av_zetatech_atlus"                          -- Tech, tagged aerial

return {
    an_empty_spec_admits_every_ground_car = function(T)
        local E = T.Core.get("competition.eligibility")
        local P = T.Core.get("data.vehicle_pool")
        local ground = 0
        for _, r in ipairs(P.allRecords()) do if not P.isAerial(r.id) then ground = ground + 1 end end
        T.eq(#E.recordsFor({}), ground, "an open street series admits every street car")
        T.eq(E.matches({}, MAIMAI), true)
    end,

    a_flight_machine_never_enters_a_ground_race = function(T)
        -- owner, 2026-10-13: "thats a flight machine you allowed to join ground races" (45 eligible became 46)
        local E = T.Core.get("competition.eligibility")
        local P = T.Core.get("data.vehicle_pool")
        local C = T.Core.get("competition.class")
        T.eq(P.isAerial(AV), true)
        for _, spec in ipairs({ {}, { classes = { "Tech" } }, { prestigeMin = 5 } }) do
            local ok, why = E.matches(spec, AV)
            T.eq(ok, false); T.eq(why, "aerial")
        end
        T.eq(E.matches({ records = { AV } }, AV), true, "a spec that names the AV admits it")
        T.eq(E.matches({ tagsAll = { "aerial" } }, AV), true, "an aerial series admits it")
        T.eq(C.eligible("street_open", AV), false)
        T.eq(C.eligible("street_open", MAIMAI), true)
        for _, r in ipairs(P.records("Tech")) do T.eq(r.id ~= AV, true, "no class draw hands out an AV") end
    end,

    an_explicit_list_is_the_whole_answer = function(T)
        -- MaiMai Cup is one-make: nothing else about the car matters.
        local E = T.Core.get("competition.eligibility")
        local spec = { records = { MAIMAI } }
        T.eq(E.matches(spec, MAIMAI), true)
        local ok, why = E.matches(spec, CALIBURN)
        T.eq(ok, false); T.eq(why, "not_in_list")
        T.eq(#E.recordsFor(spec), 1)
    end,

    class_and_prestige_filters_compose = function(T)
        local E = T.Core.get("competition.eligibility")
        -- City Cup: entry-level machinery across the ordinary classes
        local city = { classes = { "Muscle", "Sport", "Tech" }, prestigeMax = 2 }
        T.eq(E.matches(city, MAIMAI), true, "the MaiMai is Tech prestige 1")
        local ok, why = E.matches(city, CALIBURN)
        T.eq(ok, false); T.eq(why, "above_prestige")
        -- Hypercar: the top end only
        local hyper = { prestigeMin = 5 }
        T.eq(E.matches(hyper, CALIBURN), true)
        local ok2, why2 = E.matches(hyper, MAIMAI)
        T.eq(ok2, false); T.eq(why2, "below_prestige")
    end,

    a_multi_class_record_qualifies_through_either_class = function(T)
        -- The correction that came out of building the ownership ledger: the pickup is Muscle AND Nomad, and a
        -- championship naming either one must accept it. A lookup that picked one class would reject it from the
        -- other with nothing in the log to explain why.
        local E = T.Core.get("competition.eligibility")
        T.eq(E.matches({ classes = { "Muscle" } }, PICKUP), true, "admitted as Muscle")
        T.eq(E.matches({ classes = { "Nomad" } }, PICKUP), true, "admitted as Nomad")
        local ok, why = E.matches({ classes = { "Bike" } }, PICKUP)
        T.eq(ok, false); T.eq(why, "wrong_class")
    end,

    tags_any_and_all_differ = function(T)
        local E = T.Core.get("competition.eligibility")
        T.eq(E.matches({ tagsAny = { "halo", "nothing" } }, CALIBURN), true, "any: one match is enough")
        local ok, why = E.matches({ tagsAll = { "halo", "nothing" } }, CALIBURN)
        T.eq(ok, false); T.eq(why, "missing_tag", "all: every tag must be present")
        -- the pickup's tags are the union across its two classes, so both are askable
        T.eq(E.matches({ tagsAll = { "utility", "offroad" } }, PICKUP), true)
    end,

    exclude_beats_everything_else = function(T)
        local E = T.Core.get("competition.eligibility")
        local ok, why = E.matches({ records = { MAIMAI }, exclude = { MAIMAI } }, MAIMAI)
        T.eq(ok, false); T.eq(why, "excluded", "a ban is a ban, even against an explicit allow-list")
    end,

    an_unknown_record_is_never_admitted = function(T)
        local E = T.Core.get("competition.eligibility")
        local ok, why = E.matches({}, "Vehicle.not_a_real_car")
        T.eq(ok, false); T.eq(why, "unknown_record", "absent from the catalogue is not the same as allowed")
        T.eq(E.matches({}, nil), false)
    end,

    eligible_owned_counts_what_the_guide_must_show = function(T)
        -- IDEA-124: the guide answers "what car do I bring" BEFORE commitment, so it needs the count of the
        -- driver's own qualifying cars, not just a yes/no. "9 eligible, you own 3" is planning information.
        local E = T.Core.get("competition.eligibility")
        local mine = { CALIBURN, MAIMAI, PICKUP }
        T.eq(#E.eligibleOwned({}, mine), 3, "an open series admits all three")
        T.eq(#E.eligibleOwned({ records = { MAIMAI } }, mine), 1)
        T.eq(#E.eligibleOwned({ classes = { "Bike" } }, mine), 0, "owning nothing eligible is zero, not an error")
        T.eq(#E.eligibleOwned({}, {}), 0)
        T.eq(#E.eligibleOwned({}, nil), 0)
        -- pool order, so two drivers with the same garage see the same first car
        local a = E.eligibleOwned({}, { PICKUP, MAIMAI })
        local b = E.eligibleOwned({}, { MAIMAI, PICKUP })
        T.eq(table.concat(a, ","), table.concat(b, ","), "garage order does not change the answer")
    end,

    check_separates_the_operators_problem_from_the_drivers = function(T)
        -- L83's two questions. A championship that admits nothing is a broken spec and nobody's fault but ours;
        -- a driver who owns nothing eligible can go and fix it. They must not read as the same refusal.
        local E = T.Core.get("competition.eligibility")
        local broken = E.check({ records = { "Vehicle.not_a_real_car" } }, { MAIMAI })
        T.eq(broken.ok, false); T.eq(broken.reason, "championship_admits_nothing"); T.eq(broken.admits, 0)

        local nothing = E.check({ records = { MAIMAI } }, { CALIBURN })
        T.eq(nothing.ok, false); T.eq(nothing.reason, "no_eligible_car")
        T.eq(nothing.admits, 1, "and it says how many cars would have done, so the refusal can be specific")

        local fine = E.check({ records = { MAIMAI } }, { CALIBURN, MAIMAI })
        T.eq(fine.ok, true); T.eq(fine.record, MAIMAI, "it names the car that qualifies")
    end,

    an_empty_garage_is_refused_not_errored = function(T)
        local E = T.Core.get("competition.eligibility")
        local r = E.check({}, {})
        T.eq(r.ok, false); T.eq(r.reason, "no_eligible_car")
        T.ok(r.admits > 0, "the championship is fine; the garage is empty")
        T.eq(E.firstEligible({}, {}), nil)
        T.eq(E.firstEligible({}, nil), nil)
    end,

    first_eligible_is_stable_not_acquisition_ordered = function(T)
        -- Two drivers owning the same cars must be offered the same one, whatever order they earned them in.
        local E = T.Core.get("competition.eligibility")
        local a = E.firstEligible({}, { CALIBURN, MAIMAI, PICKUP })
        local b = E.firstEligible({}, { PICKUP, MAIMAI, CALIBURN })
        T.eq(a, b, "pool order decides, not garage order")
    end,

    describe_gives_a_player_something_to_act_on = function(T)
        local E = T.Core.get("competition.eligibility")
        T.match(E.describe({ records = { MAIMAI } }), "one specific car")
        T.match(E.describe({ classes = { "Nomad" } }), "a Nomad car")
        T.match(E.describe({ prestigeMin = 5 }), "eligible cars")
    end,

    invalid_input_errors_with_the_module_name = function(T)
        local E = T.Core.get("competition.eligibility")
        T.errors(function() E.matches(nil, MAIMAI) end, "competition%.eligibility%.matches:")
    end,

    evaluation_does_not_mutate_the_spec = function(T)
        local E = T.Core.get("competition.eligibility")
        local spec = { classes = { "Sport" }, prestigeMax = 4, exclude = { CALIBURN } }
        local before = T.show(spec)
        E.check(spec, { MAIMAI, CALIBURN })
        E.recordsFor(spec)
        T.eq(T.show(spec), before)
    end,
}
