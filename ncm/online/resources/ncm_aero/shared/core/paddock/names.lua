-- ncm-core module: paddock.names
-- The backmarker's name generators (FTB `ftb_names.py`, `ftb_sponsors.generate_company_name`), ported (doc 44 §4.2).
--
-- Differences from FTB, all deliberate:
--   * REGION FIRST. FTB drew first name and surname independently, which made "Takuma O'Sullivan". Here a region is
--     drawn from Night City's weights, then gender, then first name and surname from that region. A small share
--     (`MIXED_RATE`) still crosses regions, because Night City is a city of migrants and the odd mixed name is real.
--   * FNV-1a streams, not sha256, so names differ from the Python worlds (acceptable; the DATA is the oracle).
--   * UNIQUENESS is enforced by the caller's `taken` set, and everything downstream is keyed by id, never by name:
--     FTB keyed the championship by driver name and silently merged two drivers who shared one.
--   * No real person: the port drops FTB's real-driver blocks and `denied` checks the assembled full name.
local Core = NcmCore

Core.define("paddock.names", function(C)
    local M = { version = "0.1.0", MIXED_RATE = 0.08 }
    local Data = C.get("paddock.names_data")
    local Hash = C.get("vocabulary.hash")

    -- FTB's gender rates by role (driver 15%, technical staff 25%, principals 10%), kept as data to tune.
    M.FEMALE_RATE = { driver = 0.15, engineer = 0.25, strategist = 0.25, mechanic = 0.25, owner = 0.10,
        principal = 0.10, manager = 0.10 }

    function M.denied(display)
        return type(display) == "string" and Data.REAL_NAME_DENYLIST[string.lower(display)] == true
    end

    local function draw(rng, role)
        local region = rng:weighted(Data.REGION_WEIGHTS).id
        local female = rng:chance(M.FEMALE_RATE[role] or 0.15)
        local pool = Data.region(region)
        local first = rng:pick(female and pool.female or pool.male)
        local surnameRegion = region
        if rng:chance(M.MIXED_RATE) then surnameRegion = rng:weighted(Data.REGION_WEIGHTS).id end
        local last = rng:pick(Data.region(surnameRegion).surnames)
        return { first = first, last = last, display = first .. " " .. last, region = region,
            gender = female and "f" or "m" }
    end

    --- A person's name. `opts.taken` (display -> true) enforces uniqueness; the chosen display is added to it.
    --- Deterministic for (seed, role, id) given the same `taken` set.
    function M.person(seed, role, id, opts)
        opts = opts or {}
        local taken = opts.taken
        local rng = Hash.stream(seed, "name", role, id)
        for _ = 1, 24 do
            local n = draw(rng, role)
            if not M.denied(n.display) and not (taken and taken[n.display]) then
                if taken then taken[n.display] = true end
                return n
            end
        end
        -- A crowded pool: keep the last draw and disambiguate with a middle initial rather than loop forever.
        local n = draw(rng, role)
        local letters = "ABCDEFGHJKLMNPRSTVW"
        for i = 1, #letters do
            local display = n.first .. " " .. letters:sub(i, i) .. ". " .. n.last
            if not (taken and taken[display]) then
                n.display = display
                if taken then taken[display] = true end
                return n
            end
        end
        n.display = n.first .. " " .. n.last .. " " .. tostring(id)
        if taken then taken[n.display] = true end
        return n
    end

    -- The tier's pools. Street is FTB grassroots; Regional is mid; Pro is FTB's top prefixes; Premier uses the
    -- sponsor-style names FTB reserved for its top two tiers.
    local PREFIX_POOL = { street = "street", regional = "mid", pro = "top" }
    local LEAGUE_POOL = { street = "street", regional = "mid", pro = "mid", premier = "top" }

    --- An organization name, unique against `taken`. Returns name, short.
    function M.teamName(seed, tier, idx, taken)
        local rng = Hash.stream(seed, "team", tier, idx)
        for attempt = 1, 40 do
            local name
            if tier == "premier" or (tier == "pro" and attempt > 20) then
                name = rng:pick(Data.SPONSOR_TEAM_NAMES)
            else
                name = rng:pick(Data.TEAM_PREFIXES[PREFIX_POOL[tier] or "street"]) .. " " .. rng:pick(Data.TEAM_SUFFIXES)
            end
            if not (taken and taken[name]) then
                if taken then taken[name] = true end
                return name, M.short(name)
            end
        end
        local name = "Team " .. tostring(idx)
        if taken then taken[name] = true end
        return name, M.short(name)
    end

    --- A three-letter short form: initials of the first three words, else the first three letters.
    function M.short(name)
        local initials = {}
        for word in string.gmatch(name, "%a+") do initials[#initials + 1] = word:sub(1, 1):upper() end
        if #initials >= 3 then return table.concat(initials, "", 1, 3) end
        local letters = name:gsub("[^%a]", ""):upper()
        return letters:sub(1, 3)
    end

    --- FTB `generate_phonetic_surname`: consonant-vowel syllables with an optional final consonant.
    function M.phonetic(rng, syllables)
        local parts = {}
        for i = 1, syllables or 2 do
            parts[#parts + 1] = rng:pick(Data.PHONETIC_CONSONANTS)
            parts[#parts + 1] = rng:pick(Data.PHONETIC_VOWELS)
        end
        if rng:chance(0.4) then parts[#parts + 1] = rng:pick({ "s", "n", "x", "r", "d", "t" }) end
        local s = table.concat(parts)
        return s:sub(1, 1):upper() .. s:sub(2)
    end

    M.INDUSTRIES = { "automotive", "energy", "technology", "finance", "consumer", "industrial", "media", "local" }

    --- FTB `generate_company_name`: four patterns (30/25/20/25). Returns name, short, industry.
    function M.companyName(seed, idx, industry, taken)
        local rng = Hash.stream(seed, "company", idx)
        industry = industry or rng:pick(M.INDUSTRIES)
        for _ = 1, 30 do
            local p, name, short = rng(), nil, nil
            if p < 0.30 then
                local surname = M.phonetic(rng, 2)
                name, short = surname .. " " .. rng:pick(Data.INDUSTRIAL_SUFFIXES), surname
            elseif p < 0.55 then
                local concept = rng:pick(Data.ABSTRACT_CONCEPTS)
                local suffixes = (industry == "technology" or industry == "media") and Data.TECH_SUFFIXES or Data.INDUSTRIAL_SUFFIXES
                name, short = concept .. " " .. rng:pick(suffixes), concept
            elseif p < 0.75 then
                local geo = rng:pick(Data.GEOGRAPHIC_PREFIXES)
                local kw = rng:pick(Data.INDUSTRY_KEYWORDS[industry] or { "Group" })
                name, short = geo .. " " .. kw, geo .. kw:sub(1, 1)
            else
                local concept = rng:pick(Data.ABSTRACT_CONCEPTS)
                name, short = concept .. " " .. rng:pick(Data.MOTORSPORT_CUES), concept
            end
            if not (taken and taken[name]) then
                if taken then taken[name] = true end
                return name, short, industry
            end
        end
        local name = "Sponsor " .. tostring(idx)
        if taken then taken[name] = true end
        return name, name, industry
    end

    --- FTB sponsor personality (`ftb_sponsors` contract behaviour and narrative hooks), each 0..1.
    function M.sponsorPersonality(seed, idx)
        local rng = Hash.stream(seed, "sponsor_personality", idx)
        return {
            loyalty = rng(), pressureThreshold = rng(), performanceDependency = rng(), reputationDependency = rng(),
            prestige = rng(), riskAppetite = rng(), scandalRisk = rng() * 0.5,
        }
    end

    --- FTB `generate_league_name`: region + tier-appropriate type. Unique against `taken`.
    --- Every league's own name (owner, 2026-10-01, L249: approved). Sanctioned leagues carry the Race Guide's
    --- names; street leagues are their districts' night scenes. Keyed by series id, never generated.
    M.LEAGUES = {
        premier = "Hypercar Championship",
        pro_a = "Night City GT", pro_b = "NCM City Cup", pro_c = "Night City Open",
        regional_a = "Bedrock Championship", regional_b = "MaiMai Cup",
        regional_c = "Northside Trophy", regional_d = "Badlands Cup",
        street_a = "Kabuki Midnight", street_b = "Charter Hill Run", street_c = "Corpo Plaza Outlaws",
        street_d = "Glen Blood Mile", street_e = "Pacifica Wreckers",
        street_f = "Night Market Rats", street_g = "No Plates",
    }

    --- A league's name: its authored name (M.LEAGUES), else the old generated one.
    function M.leagueNameFor(seriesId, seed, tier, idx, taken)
        local name = M.LEAGUES[seriesId]
        if name then
            if taken then taken[name] = true end
            return name
        end
        return M.leagueName(seed, tier, idx, taken)
    end

    function M.leagueName(seed, tier, idx, taken)
        local rng = Hash.stream(seed, "league", tier, idx)
        local types = Data.LEAGUE_TYPES[LEAGUE_POOL[tier] or "street"]
        for _ = 1, 30 do
            local name = rng:pick(Data.LEAGUE_REGIONS) .. " " .. rng:pick(types)
            if not (taken and taken[name]) then
                if taken then taken[name] = true end
                return name
            end
        end
        local name = tier .. " Series " .. tostring(idx)
        if taken then taken[name] = true end
        return name
    end

    return M
end)
