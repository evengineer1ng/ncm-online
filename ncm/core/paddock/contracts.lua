-- ncm-core module: paddock.contracts
-- Driver contracts: what a driver is worth, whether they accept an offer, and who can be poached (FTB1 contracts,
-- silly season). Personality matters: an egotistical driver wants a bigger stage, a loyal one stays put, an unhappy
-- one listens to anyone.
local Core = NcmCore

Core.define("paddock.contracts", function(C)
    local M = { version = "0.1.0" }
    local Attr = C.get("paddock.attributes")
    local World = C.get("paddock.world")
    local Season = C.get("paddock.season")

    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

    --- The wage a driver would expect at a tier.
    function M.askingWage(driver, tier)
        return World.wageFor(tier, Attr.rating(driver.attrs))
    end

    --- Willingness 0..1 to accept `offer` = { orgId, tier, wage, seasons, prestige } from `driver` (with their
    --- current org, if any). Deterministic: the caller rolls against it with its own stream.
    function M.willingness(driver, offer, currentOrg)
        local a = driver.attrs or {}
        local ask = M.askingWage(driver, offer.tier)
        local money = clamp((offer.wage or 0) / math.max(1, ask), 0, 2)          -- 1.0 = fair
        local rankNew = Season.TIERS[offer.tier] and Season.TIERS[offer.tier].rank or 1
        local rankOld = currentOrg and Season.TIERS[currentOrg.tier] and Season.TIERS[currentOrg.tier].rank or 0
        local stage = (rankNew - rankOld) * 0.15 * (0.5 + (a.ego or 50) / 100)
        local prestige = ((offer.prestige or 50) - (currentOrg and currentOrg.prestige or 40)) / 200
        local loyalty = currentOrg and ((a.loyalty or 50) - 50) / 100 * 0.6 or 0
        local unhappy = clamp((50 - (driver.morale or 50)) / 50, 0, 1) * 0.3
        local w = 0.35 + (money - 1) * 0.6 + stage + prestige - loyalty + unhappy
        if driver.state == "free_agent" then w = w + 0.25 end
        return clamp(w, 0, 1)
    end

    --- True when a contracted driver can be approached: final season of the deal, or openly unhappy.
    function M.poachable(driver, seasonOrdinal)
        if driver.state ~= "active" then return driver.state == "free_agent" end
        if (driver.contractEnds or 0) <= (seasonOrdinal or 0) then return true end
        return (driver.morale or 50) < 40
    end

    --- A contract length in seasons a principal would offer: patient owners sign longer.
    function M.lengthFor(principal, rng)
        local patience = (principal and principal.patience or 50)
        return clamp(1 + math.floor(patience / 40) + (rng and rng:int(0, 1) or 0), 1, 3)
    end

    return M
end)
