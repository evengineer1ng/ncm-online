-- ncm-core module: competition.driver
-- The NCM Driver record and the default per-server profile (decision record L11, P2; Q19 default:
-- independent progression dimensions, none gating anything in the first world).
local Core = NcmCore

Core.define("competition.driver", function(C)
    local M = { version = "0.0.1" }
    local ids = C.get("vocabulary.ids")
    local prov = C.get("vocabulary.provenance")

    --- Mint a new NCM Driver. `ctx.rng` is the injected randomness; `ctx.origin` is "sp" or "online".
    function M.mint(ctx)
        if type(ctx) ~= "table" or type(ctx.rng) ~= "function" then
            error("driver.mint: ctx.rng function required", 2)
        end
        prov.Origin.assert(ctx.origin, "driver.mint origin")
        return {
            ncmDriverId = ids.uuid4(ctx.rng),
            origin = ctx.origin,
        }
    end

    --- Default profile dimensions for a driver on one server (Q19 default). JSON-safe.
    function M.defaultDimensions()
        return {
            reputation = 0,
            grades = {},          -- per-discipline grade, e.g. grades.street = "rookie"
            accomplishments = {}, -- array of { id, at }
            experience = 0,
        }
    end

    --- Default safety-rating document (rules.sr owns the math later; this is the stored shape).
    function M.defaultSafety()
        return { sr = 5.0, incidents = 0, distanceM = 0 }
    end

    --- Build the profile record for (driver, server). `display` is the platform-verified name.
    function M.newProfile(ncmDriverId, serverId, display)
        if not ids.isUuid(ncmDriverId) then error("driver.newProfile: ncmDriverId must be a uuid", 2) end
        if not ids.isSlug(serverId) then error("driver.newProfile: serverId must be a slug", 2) end
        if type(display) ~= "string" or display == "" or #display > 64 then
            error("driver.newProfile: display must be a 1..64 char string", 2)
        end
        return {
            ncmDriverId = ncmDriverId,
            serverId = serverId,
            display = display,
            number = nil,
            dimensions = M.defaultDimensions(),
            sr = M.defaultSafety(),
        }
    end

    --- Public read model of a profile (what other players may see). No secrets, small enough for a state bag.
    function M.publicView(profile)
        return {
            driverId = profile.ncmDriverId,
            display = profile.display,
            number = profile.number,
            reputation = profile.dimensions and profile.dimensions.reputation or 0,
            sr = profile.sr and profile.sr.sr or nil,
        }
    end

    return M
end)
