-- ncm-core module: player.landing
--
-- The Session Landing Panel's data model: the alpha progression contract, what a player can actually do
-- today, and the release changelog. It draws nothing and it talks to no host API.
--
-- Two deliberate choices:
--
-- **Content is authored data, not layout.** The panel renders whatever this module validates, so adding a
-- release or flipping a capability to `live` never touches markup. The owner asked for exactly this.
--
-- **A capability is only advertised when it is genuinely usable.** `state` is the gate: `live` is offered,
-- `partial` is offered with its limit stated out loud, and `soon` is never advertised as something to go and
-- do -- it exists so the roadmap can be authored in the same file without lying to a player about today.
--
-- Release ordering is by ISO date, not by parsing a version string. A changelog is a human artifact; two
-- releases on one day break a semver sort and do not break a date sort with an explicit sequence tiebreak.
local Core = NcmCore

Core.define("player.landing", function()
    local M = { version = "0.1.0" }

    M.SCHEMA_VERSION = 1

    -- Capability states, in advertising order. The player-facing meaning of each is fixed here so that six
    -- systems cannot each invent their own word for "half finished".
    M.STATES = { live = 3, partial = 2, soon = 1 }

    -- The progression contract. Held here rather than in the page because it is the one piece of copy on this
    -- panel that must not drift: it is the promise the alpha makes to the player.
    --
    -- Framed as provisional, NOT as anti-cheat. A wipe is a development reality, not a punishment.
    M.CONTRACT = {
        id = "alpha_progression",
        eyebrow = "NCM ONLINE // ALPHA",
        headline = "PROGRESSION IS TEMPORARY",
        body = "Everything you earn here -- money, machines, parts, records -- resets for NCM 1.0.",
        detail = "Further resets may happen before then. Exploits, corrupted state, schema changes and " ..
            "balance work can each force one, and NCM keeps that option on purpose. Drive it like a " ..
            "season that ends, because it is one.",
        promise = "What will not reset is what we learn from you driving it.",
    }

    local function trimmed(value, limit)
        if type(value) ~= "string" then return nil end
        local text = value:match("^%s*(.-)%s*$")
        if text == "" then return nil end
        if limit and #text > limit then return nil end
        return text
    end

    local function isoDate(value)
        local text = trimmed(value, 10)
        if not text then return nil end
        local y, m, d = text:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
        if not y then return nil end
        m, d = tonumber(m), tonumber(d)
        if m < 1 or m > 12 or d < 1 or d > 31 then return nil end
        return text
    end

    --- One thing a player can do today. `state` decides whether it is advertised at all.
    function M.normalizeCapability(raw)
        if type(raw) ~= "table" then return nil, "capability_not_table" end
        local id = trimmed(raw.id, 64)
        if not id then return nil, "invalid_capability_id" end
        local label = trimmed(raw.label, 64)
        if not label then return nil, "invalid_capability_label" end
        local state = trimmed(raw.state, 16) or "live"
        if not M.STATES[state] then return nil, "invalid_capability_state" end
        -- A `partial` capability without its limit stated is the failure this field exists to prevent: it
        -- promises a whole feature and delivers a slice, and the player discovers the gap by being confused.
        local limit = trimmed(raw.limit, 160)
        if state == "partial" and not limit then return nil, "partial_capability_needs_a_limit" end
        return {
            id = id, label = label, state = state,
            detail = trimmed(raw.detail, 220), limit = limit,
            reference = trimmed(raw.reference, 64),   -- which NCM surface this is done from
        }
    end

    --- One changelog release. Significant player-facing change only; a redeploy is not a release.
    function M.normalizeRelease(raw)
        if type(raw) ~= "table" then return nil, "release_not_table" end
        local date = isoDate(raw.date)
        if not date then return nil, "invalid_release_date" end
        local title = trimmed(raw.title, 96)
        if not title then return nil, "invalid_release_title" end
        local items = {}
        for _, entry in ipairs(type(raw.items) == "table" and raw.items or {}) do
            if type(entry) == "table" then
                local heading = trimmed(entry.heading, 48)
                local text = trimmed(entry.text, 320)
                if text then items[#items + 1] = { heading = heading, text = text } end
            else
                local text = trimmed(entry, 320)
                if text then items[#items + 1] = { text = text } end
            end
        end
        if #items == 0 then return nil, "release_needs_at_least_one_item" end
        return {
            date = date, title = title, items = items,
            build = trimmed(raw.build, 48),
            seq = math.floor(tonumber(raw.seq) or 0),   -- tiebreak for two releases on one date
            hero = trimmed(raw.hero, 160),              -- optional art; absent renders intentionally
        }
    end

    local function ordered(releases)
        local out = {}
        for _, raw in ipairs(type(releases) == "table" and releases or {}) do
            local release = M.normalizeRelease(raw)
            if release then out[#out + 1] = release end
        end
        -- Newest first. Date descending, then the authored sequence, so the order is total and stable.
        table.sort(out, function(a, b)
            if a.date ~= b.date then return a.date > b.date end
            return a.seq > b.seq
        end)
        return out
    end

    --- The panel's whole payload.
    --- `config` = { capabilities = {...}, releases = {...}, hero? }
    --- `seen`   = { lastReleaseDate? } -- what this driver had already been shown, for "new since you left"
    function M.payload(config, seen)
        config = type(config) == "table" and config or {}
        seen = type(seen) == "table" and seen or {}
        local lastSeen = isoDate(seen.lastReleaseDate)

        local capabilities, offered = {}, 0
        for _, raw in ipairs(type(config.capabilities) == "table" and config.capabilities or {}) do
            local capability = M.normalizeCapability(raw)
            -- `soon` is carried but never counted as something to go and do today.
            if capability then
                capabilities[#capabilities + 1] = capability
                if capability.state ~= "soon" then offered = offered + 1 end
            end
        end
        table.sort(capabilities, function(a, b)
            if M.STATES[a.state] ~= M.STATES[b.state] then return M.STATES[a.state] > M.STATES[b.state] end
            return a.label < b.label
        end)

        local releases = ordered(config.releases)
        local newCount = 0
        for index, release in ipairs(releases) do
            -- "New" is relative to the last release this driver was shown, never to wall-clock time: a player
            -- returning after three months should see three months of releases marked, not none.
            release.isNew = lastSeen ~= nil and release.date > lastSeen
            if release.isNew then newCount = newCount + 1 end
            -- The newest release opens; the rest arrive collapsed so the panel cannot become a vertical wall.
            release.expanded = index == 1
        end

        return {
            schemaVersion = M.SCHEMA_VERSION,
            contract = M.CONTRACT,
            capabilities = capabilities,
            offeredCount = offered,
            releases = releases,
            currentRelease = releases[1] or nil,
            newReleaseCount = newCount,
            -- nil on a first-ever session, which the panel says differently from "nothing changed".
            firstSession = lastSeen == nil,
            hero = trimmed(config.hero, 160) or (releases[1] and releases[1].hero) or nil,
        }
    end

    --- What to persist after the player has seen it. Write-forward only: a player who somehow sees an older
    --- panel than they have already seen must not have their watermark moved backwards.
    function M.advance(seen, payload)
        local previous = isoDate(type(seen) == "table" and seen.lastReleaseDate or nil)
        local current = payload and payload.currentRelease and payload.currentRelease.date or nil
        if not current then return { lastReleaseDate = previous } end
        if previous and previous >= current then return { lastReleaseDate = previous } end
        return { lastReleaseDate = current }
    end

    return M
end)
