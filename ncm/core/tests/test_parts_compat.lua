-- parts.architecture + parts.compat -- derived compatibility, and the honesty of not knowing.
--
-- The invariant these exist to protect is the scaling one from 18_PARTS_ECOSYSTEM: adding vehicle #83 must
-- not mean editing historical components. That is tested directly (`a_new_vehicle_needs_no_component_edits`)
-- rather than argued for in a comment.
--
-- The second invariant is that "not authored yet" never masquerades as "does not fit". Almost every facet is
-- unauthored today, so a resolver that collapsed the two would report an empty world and look like it was
-- working.
local function A(T) return T.Core.get("parts.architecture") end
local function X(T) return T.Core.get("parts.compat") end
local function Cat(T) return T.Core.get("data.vehicle_catalogue") end

local function contains(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

return {
    -- ------------------------------------------------------------------ the facet vocabulary
    every_facet_belongs_to_a_real_family = function(T)
        local M = A(T)
        local ontology = T.Core.get("parts.ontology")
        for _, facet in ipairs(M.FACETS) do
            T.eq(ontology.isFamily(facet.family), true, facet.id .. " names one of the twelve families")
        end
        T.eq(#M.FACET_IDS, #M.FACETS, "")
    end,

    facet_values_are_a_closed_set_except_platform = function(T)
        local M = A(T)
        T.eq(M.isFacetValue("drivetrain", "rwd"), true, "")
        T.eq(M.isFacetValue("drivetrain", "six_wheel_drive"), false, "a typo is not a new architecture")
        T.eq(M.isFacetValue("axle_config", "2x2"), true, "")
        -- platform is an identity, not a category, so it accepts any non-empty string
        T.eq(M.isFacetValue("platform", "quadra_type66"), true, "")
        T.eq(M.isFacetValue("platform", ""), false, "but not an empty one")
        T.eq(M.isFacetValue("not_a_facet", "anything"), false, "")
    end,

    -- ------------------------------------------------------------------ platform derivation
    variants_of_one_machine_share_a_platform = function(T)
        local M = A(T)
        -- Derived from NCM's own vehicleKeys, not authored. This is what stops the component catalogue
        -- growing with every cosmetic variant.
        T.eq(M.platform("quadra_type66_nomad"), "quadra_type66", "the Nomad Type-66 is a Type-66")
        T.eq(M.platform("mizutani_shion_nomad"), "mizutani_shion", "")
        T.eq(M.platform("brennan_apollo_sport"), "brennan_apollo", "")
        T.eq(M.platform("brennan_apollo_nomad"), "brennan_apollo", "")
        -- Neither Kusanagi is itself a catalogue key, but two siblings reduce to the same base, which is
        -- evidence enough that the base is real.
        T.eq(M.platform("yaiba_kusanagi_tyger"), "yaiba_kusanagi", "")
        T.eq(M.platform("yaiba_kusanagi_animal"), "yaiba_kusanagi", "")
    end,

    a_suffix_that_is_not_a_variant_does_not_collapse = function(T)
        local M = A(T)
        -- A pickup is not a trim level of a coupe. `_pickup` is not in the variant list and the two stay
        -- separate platforms, which is the conservative direction to be wrong in.
        T.eq(M.platform("thorton_colby_pickup"), "thorton_colby_pickup", "")
        T.eq(M.platform("thorton_colby"), "thorton_colby", "")
        T.eq(M.platform("thorton_galena"), "thorton_galena", "a machine with no siblings is its own platform")
    end,

    every_vehicle_has_a_platform_and_platforms_cover_every_vehicle = function(T)
        local M, catalogue = A(T), Cat(T)
        local platforms, order = M.platforms()
        local counted = 0
        for _, platform in ipairs(order) do counted = counted + #platforms[platform] end
        T.eq(counted, catalogue.count(), "every catalogue entry sits on exactly one platform")
        T.eq(#order < catalogue.count(), true, "and some platforms carry more than one vehicle")
    end,

    -- ------------------------------------------------------------------ derivation vs invention
    a_bike_is_derived_and_never_guessed = function(T)
        local M = A(T)
        -- True by construction: a motorcycle has two wheels, handlebars and a fork because it is one.
        T.eq(M.facet("yaiba_kusanagi_tyger", "axle_config"), "1x1", "")
        T.eq(M.facet("yaiba_kusanagi_tyger", "steering"), "handlebar", "")
        T.eq(M.facet("yaiba_kusanagi_tyger", "structure"), "motorcycle_frame", "")
        T.eq(M.facetProvenance("yaiba_kusanagi_tyger", "axle_config"), M.DERIVED, "and it says it is derived")
    end,

    a_car_has_four_wheels_but_an_unknown_drivetrain = function(T)
        local M = A(T)
        T.eq(M.facet("thorton_galena", "axle_config"), "2x2", "four wheels is safe to derive")
        T.eq(M.facet("thorton_galena", "steering"), "rack", "so is a steering rack")
        -- This is the point of the module: nothing in this repository says whether a Galena is FWD or RWD,
        -- so it says `unknown` rather than inventing an answer that would look identical to a real one.
        T.eq(M.facet("thorton_galena", "drivetrain"), M.UNKNOWN, "drivetrain layout is not knowable offline")
        T.eq(M.facet("thorton_galena", "propulsion"), M.UNKNOWN, "")
        T.eq(M.facetProvenance("thorton_galena", "drivetrain"), M.UNKNOWN, "")
    end,

    unknown_facets_are_reported_as_a_worklist = function(T)
        local M = A(T)
        local gaps = M.authoringGaps()
        T.eq(#gaps > 0, true, "there is authoring outstanding, and it is enumerable")
        local coverage = M.coverage()
        T.eq(coverage.total, coverage.vehicles * coverage.facets, "")
        T.eq(coverage.known > 0, true, "some facets are genuinely derived")
        T.eq(coverage.known < coverage.total, true, "and most are not yet authored")
    end,

    an_unknown_vehicle_has_no_profile = function(T)
        local M = A(T)
        T.eq(M.profile("delorean"), nil, "")
        T.eq(M.facet("delorean", "drivetrain"), nil, "nil for an unknown vehicle, not `unknown`")
    end,

    -- ------------------------------------------------------------------ constraint validation
    a_constraint_naming_a_nonexistent_facet_is_refused = function(T)
        local M = X(T)
        -- Refused rather than silently matching nothing: a component that fits no car looks exactly like a
        -- component nobody has bought.
        local ok, why = M.validate({ requires = { turbo_count = { "2" } } })
        T.eq(ok, false, "")
        T.eq(type(why) == "string" and why:find("turbo_count", 1, true) ~= nil, true, why or "")

        local ok2 = M.validate({ requires = { drivetrain = { "six_wheel_drive" } } })
        T.eq(ok2, false, "a value outside the closed vocabulary is refused too")
    end,

    a_wellformed_constraint_validates = function(T)
        local M = X(T)
        T.eq(M.validate({ requires = { drivetrain = { "rwd", "awd" } } }), true, "")
        T.eq(M.validate({}), true, "an empty constraint is legal -- it is a universal component")
        T.eq(M.validate({ fitsPlatforms = { "quadra_type66" } }), true, "")
        T.eq(M.validate({ requires = { drivetrain = {} } }), false, "an empty allow-list is not legal")
        T.eq(M.validate("not a table"), false, "")
    end,

    -- ------------------------------------------------------------------ resolution
    a_universal_component_fits_everything = function(T)
        local M, catalogue = X(T), Cat(T)
        for _, entry in ipairs(catalogue.entries()) do
            T.eq(M.fits({}, entry.vehicleKey), true, "a constraint-free component fits " .. entry.vehicleKey)
        end
    end,

    a_derived_facet_resolves_without_any_authoring = function(T)
        local M = X(T)
        local carWheels = { requires = { axle_config = { "2x2" } } }
        T.eq(M.fits(carWheels, "thorton_galena"), true, "a four-wheel component fits a car")
        T.eq(M.fits(carWheels, "yaiba_kusanagi_tyger"), false, "and not a motorcycle")

        local result = M.resolve(carWheels, "yaiba_kusanagi_tyger")
        T.eq(result.outcome, M.MISMATCH, "and that is a real no, not a shrug")
        T.eq(result.facet, "axle_config", "")
        T.eq(result.actual, "1x1", "")
    end,

    an_unauthored_facet_is_not_a_refusal = function(T)
        local M = X(T)
        -- The distinction this module exists for. `mismatch` is permanent; `unknown_facet` is a worklist
        -- item. A boolean resolver would collapse them and report an empty world.
        local result = M.resolve({ requires = { drivetrain = { "rwd" } } }, "thorton_galena")
        T.eq(result.outcome, M.UNKNOWN_FACET, "")
        T.eq(result.compatible, false, "it still is not usable yet")
        T.eq(result.facet, "drivetrain", "and it names what somebody must author")
        T.eq(result.actual, "unknown", "")
    end,

    exact_model_fitment_remains_possible = function(T)
        local M = X(T)
        -- The spec requires this stay available for components that genuinely need it. It lives in its own
        -- field so that an audit can find every component that needed an exception.
        local oneCar = { fitsPlatforms = { "quadra_type66" } }
        T.eq(M.fits(oneCar, "quadra_type66"), true, "")
        T.eq(M.fits(oneCar, "quadra_type66_nomad"), true, "and it follows the platform, not the variant")
        T.eq(M.fits(oneCar, "thorton_galena"), false, "")
    end,

    an_exclusion_outranks_a_facet_match = function(T)
        local M = X(T)
        local notTheFormulaCar = {
            requires = { axle_config = { "2x2" } },
            excludesPlatforms = { "ncx_rb15" },
        }
        T.eq(M.fits(notTheFormulaCar, "thorton_galena"), true, "")
        local result = M.resolve(notTheFormulaCar, "ncx_rb15")
        T.eq(result.outcome, M.MISMATCH, "excluded even though the axle config matches")
        T.eq(result.facet, "platform", "")
    end,

    an_unknown_vehicle_resolves_rather_than_erroring = function(T)
        local M = X(T)
        local result = M.resolve({}, "delorean")
        T.eq(result.outcome, M.UNKNOWN_VEHICLE, "")
        T.eq(result.compatible, false, "")
    end,

    resolution_is_deterministic_about_which_facet_it_blames = function(T)
        local M = X(T)
        -- Two unauthored facets in one constraint. `pairs` is unordered, so without an explicit order the
        -- resolver would name a different facet on different runs and be untestable.
        local constraint = { requires = { drivetrain = { "rwd" }, propulsion = { "combustion" } } }
        local first = M.resolve(constraint, "thorton_galena").facet
        for _ = 1, 8 do
            T.eq(M.resolve(constraint, "thorton_galena").facet, first, "same blocking facet every time")
        end
    end,

    -- ------------------------------------------------------------------ the listing
    applicable_vehicles_reports_the_undecided_as_well = function(T)
        local M = X(T)
        local carOnly = M.applicableVehicles({ requires = { axle_config = { "2x2" } } })
        T.eq(#carOnly.fits > 0, true, "cars fit")
        T.eq(#carOnly.undecided, 0, "and nothing is undecided, because axle_config is derived for all")

        local rwdOnly = M.applicableVehicles({ requires = { drivetrain = { "rwd" } } })
        T.eq(#rwdOnly.fits, 0, "nothing fits yet, because nothing has an authored drivetrain")
        T.eq(#rwdOnly.undecided > 0, true, "but the truth is 'not checked', not 'does not fit'")
        -- Bikes are the exception: `chain` IS derived, so they are a real mismatch rather than undecided.
        for _, row in ipairs(rwdOnly.undecided) do
            T.eq(row.facet, "drivetrain", "")
        end
    end,

    explain_says_which_of_the_three_things_happened = function(T)
        local M = X(T)
        T.eq(M.explain({}, "thorton_galena"):find("fits", 1, true) ~= nil, true, "")
        T.eq(M.explain({ requires = { drivetrain = { "rwd" } } }, "thorton_galena")
                :find("not authored", 1, true) ~= nil, true, "the undecided case says so in words")
        T.eq(M.explain({ requires = { axle_config = { "2x2" } } }, "yaiba_kusanagi_tyger")
                :find("does not fit", 1, true) ~= nil, true, "")
    end,

    -- ------------------------------------------------------------------ the scaling invariant
    a_new_vehicle_needs_no_component_edits = function(T)
        local M, arch = X(T), A(T)
        -- The requirement 18_PARTS_ECOSYSTEM states in full: "when NCM adds vehicle model #83, nobody should
        -- have to edit thousands of historical component definitions." The proof is structural -- a
        -- constraint refers only to facets, never to vehicles -- so the test is that resolution against a
        -- vehicle the constraint has never heard of still produces a defined answer.
        local component = { requires = { axle_config = { "2x2" }, steering = { "rack" } } }
        local decided = 0
        for _, entry in ipairs(T.Core.get("data.vehicle_catalogue").entries()) do
            local result = M.resolve(component, entry.vehicleKey)
            T.eq(result.outcome ~= M.MALFORMED, true, "never malformed for " .. entry.vehicleKey)
            T.eq(result.outcome ~= M.UNKNOWN_VEHICLE, true, "and never an unknown vehicle")
            if result.outcome == M.FITS or result.outcome == M.MISMATCH then decided = decided + 1 end
        end
        T.eq(decided, arch.coverage().vehicles,
             "every vehicle in the catalogue resolves decisively against derived facets alone")
    end,
}
