-- ncm-core module: driver.presentation
--
-- The public Driver Card contract. Definition, entitlement and displayed selection are deliberately separate:
-- a player choosing what to feature never creates, awards, revokes or edits the underlying accomplishment.
-- Fingerprint V1 is NOT defined here. The six modern dimensions are preserved as design direction only; the
-- public projection carries an explicit unavailable state until evidence/population/window/version rules exist.
local Core = NcmCore

Core.define("driver.presentation", function()
    local M = { version = "0.1.0" }

    M.SCHEMA_VERSION = 1
    M.MAX_DISPLAYED_BADGES = 3
    M.DEFAULT_BANNER_ID = "ncm_default"

    -- Current direction, L130. Not a calculation definition and intentionally absent from the V1 payload.
    M.FINGERPRINT_DIRECTION = {
        status = "direction_only",
        populationRelative = true,
        axes = { "competition", "street", "engineering", "commerce", "culture", "intensity" },
    }

    -- One baseline is enough to prove definition -> entitlement -> selection -> rendering. Future artwork gets
    -- another stable row; it never changes the meaning of an existing id.
    M.BANNERS = {
        ncm_default = {
            id = "ncm_default", label = "NCM Default", theme = "ncm_default",
            image = "assets/banners/ncm-default.svg", crop = "50% 50%",
            entitlement = "baseline", developmentOnly = false,
        },
        ncm_development = {
            id = "ncm_development", label = "Development Preview", theme = "ncm_development",
            image = "assets/banners/ncm-development.svg", crop = "58% 50%",
            entitlement = "development_fixture", developmentOnly = true,
        },
    }

    -- Small legitimate bridge to the accomplishment substrate, not the future badge/prestige catalogue.
    -- The three dev slots exist only for the Development preview command and are never normal entitlements.
    M.BADGES = {
        first_finish = { id = "first_finish", label = "First Finish", glyphId = "finish", accomplishment = "first_finish" },
        first_win = { id = "first_win", label = "First Win", glyphId = "completed", accomplishment = "first_win" },
        first_time_trial = { id = "first_time_trial", label = "First Time Trial", glyphId = "timer", accomplishment = "first_time_trial" },
        dev_slot_1 = { id = "dev_slot_1", label = "Development Slot 1", glyphId = "finish", developmentOnly = true },
        dev_slot_2 = { id = "dev_slot_2", label = "Development Slot 2", glyphId = "completed", developmentOnly = true },
        dev_slot_3 = { id = "dev_slot_3", label = "Development Slot 3", glyphId = "timer", developmentOnly = true },
    }

    local function copyArray(src)
        local out = {}
        for i = 1, #(type(src) == "table" and src or {}) do out[i] = src[i] end
        return out
    end

    local function sortedDefinitions(map)
        local ids, out = {}, {}
        for id in pairs(map) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local source, row = map[id], {}
            for key, value in pairs(source) do row[key] = value end
            out[#out + 1] = row
        end
        return out
    end

    --- Safe catalogue for the client/WebUI. No entitlement or player history is included.
    function M.assets()
        return {
            schemaVersion = M.SCHEMA_VERSION,
            maxDisplayedBadges = M.MAX_DISPLAYED_BADGES,
            defaultBannerId = M.DEFAULT_BANNER_ID,
            banners = sortedDefinitions(M.BANNERS),
            badges = sortedDefinitions(M.BADGES),
        }
    end

    --- Turn authoritative accomplishment kinds into presentation entitlements.
    function M.entitlements(accomplishmentKinds, opts)
        local kinds = {}
        for _, kind in ipairs(type(accomplishmentKinds) == "table" and accomplishmentKinds or {}) do
            if type(kind) == "string" then kinds[kind] = true end
        end
        local entitled = { banners = { [M.DEFAULT_BANNER_ID] = true }, badges = {} }
        for id, banner in pairs(M.BANNERS) do
            if banner.developmentOnly and type(opts) == "table" and opts.development == true then
                entitled.banners[id] = true
            end
        end
        for id, badge in pairs(M.BADGES) do
            if badge.accomplishment and kinds[badge.accomplishment] then entitled.badges[id] = true end
            if badge.developmentOnly and type(opts) == "table" and opts.development == true then
                entitled.badges[id] = true
            end
        end
        return entitled
    end

    local function normalize(selection, entitled)
        selection = type(selection) == "table" and selection or {}
        entitled = type(entitled) == "table" and entitled or { banners = {}, badges = {} }
        local issues = {}
        local bannerId = tostring(selection.bannerId or M.DEFAULT_BANNER_ID)
        if not M.BANNERS[bannerId] or not (entitled.banners and entitled.banners[bannerId]) then
            issues[#issues + 1] = not M.BANNERS[bannerId] and "unknown_banner" or "banner_not_entitled"
            bannerId = M.DEFAULT_BANNER_ID
        end

        local badges, seen = {}, {}
        for _, raw in ipairs(type(selection.displayedBadgeIds) == "table" and selection.displayedBadgeIds or {}) do
            local id = tostring(raw)
            if #badges >= M.MAX_DISPLAYED_BADGES then
                issues[#issues + 1] = "too_many_badges"
                break
            elseif seen[id] then
                issues[#issues + 1] = "duplicate_badge"
            elseif not M.BADGES[id] then
                issues[#issues + 1] = "unknown_badge"
            elseif not (entitled.badges and entitled.badges[id]) then
                issues[#issues + 1] = "badge_not_entitled"
            else
                seen[id] = true
                badges[#badges + 1] = id
            end
        end
        return { bannerId = bannerId, displayedBadgeIds = badges }, issues
    end

    --- Strict validation for a player's selection request. Publishing uses the forgiving projection below.
    function M.validateSelection(selection, entitled)
        local safe, issues = normalize(selection, entitled)
        if #issues > 0 then return nil, issues[1], issues end
        return safe
    end

    --- Intentionally public, bounded presentation. Never add private/profile facts here for convenience.
    function M.publicProjection(selection, entitled)
        local safe = normalize(selection, entitled)
        return {
            schemaVersion = M.SCHEMA_VERSION,
            bannerId = safe.bannerId,
            displayedBadgeIds = copyArray(safe.displayedBadgeIds),
            fingerprint = {
                definitionVersion = 0,
                values = {},
                sampleState = "unavailable",
            },
        }
    end

    --- Defensive client boundary. It accepts only known public asset ids and the current honest Fingerprint
    --- state; entitlement was already enforced by the server and no private fields are copied through.
    function M.sanitizePublicProjection(value)
        value = type(value) == "table" and value or {}
        local all = { banners = {}, badges = {} }
        for id in pairs(M.BANNERS) do all.banners[id] = true end
        for id in pairs(M.BADGES) do all.badges[id] = true end
        local safe = normalize({ bannerId = value.bannerId, displayedBadgeIds = value.displayedBadgeIds }, all)
        return M.publicProjection(safe, all)
    end

    return M
end)
