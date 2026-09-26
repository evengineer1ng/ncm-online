-- ncm-core module: parts.compat
--
-- The compatibility resolver. A vehicle states its architecture (`parts.architecture`); a component design
-- states **constraints against that architecture**; this module relates the two. 18_PARTS_ECOSYSTEM:
--
--   > Vehicle models expose a mechanical architecture profile; components declare constraints against it.
--   > The resolver relates them. ... Exact model-specific fitment must remain possible.
--
-- **Nothing here lists fitment.** There is no table of which part fits which car, and there must never be
-- one, because that table is what makes vehicle #83 a thousand-row edit. The only per-model data in the
-- system is the vehicle's own profile, authored once when the vehicle is added.
--
-- ---------------------------------------------------------------------------------------------------
-- A CONSTRAINT
-- ---------------------------------------------------------------------------------------------------
--
--   {
--     requires = { drivetrain = { "rwd", "awd" }, axle_config = { "2x2" } },  -- facet -> allowed values
--     fitsPlatforms    = { "quadra_type66" },   -- optional: exact model-specific fitment
--     excludesPlatforms = { "ncx_rb15" },       -- optional: a platform this will never fit
--   }
--
-- All three parts are optional. **A constraint with none of them fits everything**, which is correct: a
-- universal component is a real thing and should not need to enumerate 27 vehicles to say so.
--
-- `requires` is a conjunction of disjunctions -- every named facet must match one of its allowed values.
-- That shape is deliberate. It expresses *"fits rear- or all-wheel drive, four-wheeled, with a standard or
-- performance brake interface"* directly, and it cannot express *"fits the Galena and the Shion"*, which is
-- a fitment list wearing a disguise. Naming specific machines is what `fitsPlatforms` is for, and keeping
-- that in its own field means an audit can find every component that needed an exception.
--
-- ---------------------------------------------------------------------------------------------------
-- THE THREE OUTCOMES, AND WHY THERE ARE THREE
-- ---------------------------------------------------------------------------------------------------
--
--   `fits`          -- every constraint satisfied.
--   `mismatch`      -- a facet is known and does not match. A real, permanent no.
--   `unknown_facet` -- the vehicle has not had that facet authored yet. **Not a no. A "we cannot say".**
--
-- Collapsing the last two into `false` is the tempting mistake and it would be a bad one: today almost
-- every facet is unauthored (`parts.architecture` derives only what is true by construction), so a boolean
-- resolver would report that nothing fits anything and look like a working system returning an empty world.
-- Keeping them apart means the emptiness is visible and attributable, and `M.explain` names the exact facet
-- somebody needs to go and author.
local Core = NcmCore

Core.define("parts.compat", function(C)
    local M = { version = "0.0.1" }

    local architecture = C.get("parts.architecture")

    M.FITS, M.MISMATCH, M.UNKNOWN_FACET = "fits", "mismatch", "unknown_facet"
    M.UNKNOWN_VEHICLE, M.MALFORMED = "unknown_vehicle", "malformed_constraint"

    local function contains(list, value)
        for _, v in ipairs(list) do if v == value then return true end end
        return false
    end

    --- Is this constraint well formed? Returns `true`, or `false, reason`.
    ---
    --- Checked rather than trusted, because a constraint naming a facet that does not exist -- or a value
    --- outside that facet's closed vocabulary -- would otherwise match nothing forever, and would do it
    --- silently. A component that fits no car is indistinguishable from a component nobody has bought.
    function M.validate(constraint)
        if type(constraint) ~= "table" then return false, "constraint must be a table" end

        local requires = constraint.requires
        if requires ~= nil then
            if type(requires) ~= "table" then return false, "requires must be a table" end
            for facetId, allowed in pairs(requires) do
                if not architecture.isFacet(facetId) then
                    return false, "unknown facet: " .. tostring(facetId)
                end
                if type(allowed) ~= "table" or #allowed == 0 then
                    return false, "facet " .. facetId .. " must allow at least one value"
                end
                for _, value in ipairs(allowed) do
                    if not architecture.isFacetValue(facetId, value) then
                        return false, ("facet %s cannot be %q"):format(facetId, tostring(value))
                    end
                end
            end
        end

        for _, field in ipairs({ "fitsPlatforms", "excludesPlatforms" }) do
            local list = constraint[field]
            if list ~= nil then
                if type(list) ~= "table" or #list == 0 then
                    return false, field .. " must be a non-empty list when present"
                end
                for _, platform in ipairs(list) do
                    if type(platform) ~= "string" or platform == "" then
                        return false, field .. " must contain platform ids"
                    end
                end
            end
        end

        return true
    end

    --- Resolve one constraint against one vehicle.
    ---
    --- Returns `{ outcome, compatible, reason, facet, expected, actual }`. `compatible` is true only for
    --- `fits`; a caller that wants the boolean can take it, and a caller that wants to know *why* has the
    --- rest without a second call.
    function M.resolve(constraint, vehicleKey)
        local ok, why = M.validate(constraint)
        if not ok then
            return { outcome = M.MALFORMED, compatible = false, reason = why }
        end

        local profile = architecture.profile(vehicleKey)
        if not profile then
            return {
                outcome = M.UNKNOWN_VEHICLE, compatible = false,
                reason = "no architecture profile for " .. tostring(vehicleKey),
            }
        end

        -- Exclusions first: an explicit "never this platform" outranks everything, including a facet match.
        local excludes = constraint.excludesPlatforms
        if excludes and contains(excludes, profile.platform) then
            return {
                outcome = M.MISMATCH, compatible = false, facet = "platform",
                actual = profile.platform,
                reason = "excluded from platform " .. profile.platform,
            }
        end

        -- Exact model-specific fitment. The spec requires this remain possible for components that
        -- genuinely need it; it is deliberately a separate field so it can be audited, not a way of life.
        local fits = constraint.fitsPlatforms
        if fits and not contains(fits, profile.platform) then
            return {
                outcome = M.MISMATCH, compatible = false, facet = "platform",
                expected = fits, actual = profile.platform,
                reason = "fits only " .. table.concat(fits, ", "),
            }
        end

        local requires = constraint.requires
        if requires then
            -- Deterministic order, so two callers asking the same question get the same answer. `pairs` is
            -- unordered, and a resolver that names a different blocking facet on each call is untestable
            -- and impossible to explain to a player.
            for _, facetId in ipairs(architecture.FACET_IDS) do
                local allowed = requires[facetId]
                if allowed then
                    local actual = architecture.facet(vehicleKey, facetId)
                    if actual == architecture.UNKNOWN then
                        return {
                            outcome = M.UNKNOWN_FACET, compatible = false, facet = facetId,
                            expected = allowed, actual = architecture.UNKNOWN,
                            reason = ("%s has no authored %s"):format(vehicleKey, facetId),
                        }
                    end
                    if not contains(allowed, actual) then
                        return {
                            outcome = M.MISMATCH, compatible = false, facet = facetId,
                            expected = allowed, actual = actual,
                            reason = ("%s is %s, needs %s"):format(
                                facetId, actual, table.concat(allowed, " or ")),
                        }
                    end
                end
            end
        end

        return { outcome = M.FITS, compatible = true, reason = "fits" }
    end

    --- Does it fit? The boolean shortcut, for callers that genuinely only need yes or no.
    function M.fits(constraint, vehicleKey)
        return M.resolve(constraint, vehicleKey).outcome == M.FITS
    end

    --- Every vehicle a constraint fits, plus the ones it cannot be decided for.
    ---
    --- `undecided` is the honest half and the reason this does not just return a list. Today it will be
    --- long, because most facets are unauthored -- and a caller that ignores it will believe a component
    --- fits three cars when the truth is that it fits three and nobody has checked the other twenty-four.
    function M.applicableVehicles(constraint)
        local fitting, undecided = {}, {}
        local platforms, order = architecture.platforms()
        for _, platform in ipairs(order) do
            for _, vehicleKey in ipairs(platforms[platform]) do
                local result = M.resolve(constraint, vehicleKey)
                if result.outcome == M.FITS then
                    fitting[#fitting + 1] = vehicleKey
                elseif result.outcome == M.UNKNOWN_FACET then
                    undecided[#undecided + 1] = { vehicleKey = vehicleKey, facet = result.facet }
                end
            end
        end
        return { fits = fitting, undecided = undecided }
    end

    --- A human-readable sentence for one resolution. For a diagnostic listing, not for a player-facing UI --
    --- presentation is a separate concern and this deliberately speaks in mechanical terms.
    function M.explain(constraint, vehicleKey)
        local result = M.resolve(constraint, vehicleKey)
        if result.outcome == M.FITS then
            return ("fits %s"):format(vehicleKey)
        elseif result.outcome == M.UNKNOWN_FACET then
            return ("cannot say for %s: %s is not authored yet"):format(vehicleKey, result.facet)
        end
        return ("does not fit %s: %s"):format(vehicleKey, result.reason)
    end

    return M
end)
