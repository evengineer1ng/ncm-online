-- ncm_world / server / identity — the NCM Driver identity service (M2.1).
--
-- On join: hold readiness → find the binding (serverId, userId) → mint + bind + profile when absent →
-- cache → publish the public view on the player's state bag → release the hold.
-- Every write is a single transaction. Nothing from the client is trusted: identity comes from
-- GetPlayerIdentifier(playerId), the name from GetPlayerName(playerId).
NcmIdentity = {}

local Core = NcmCore
local ids = Core.get("vocabulary.ids")
local Driver = Core.get("competition.driver")

local function log(fmt, ...)
    print(("[ncm_world/identity] " .. fmt):format(...))
end

-- Operator-tunable server identity (L14: framework, not server). Slug; keys per-server rows.
local settings = Open77.tunables.declare({
    serverId = { value = "ncm-dev", type = "string", apply = "live" },
})

local function serverId()
    local v = tostring(settings.serverId or "ncm-dev")
    if not ids.isSlug(v) then return "ncm-dev" end
    return v
end

-- Host-provided randomness for minting (Lua 5.4 seeds math.random from time+address at VM start).
local hostRng = function() return math.random() end

local CoreJson = Core.get("vocabulary.json")
local function encode(t)
    if json and json.encode then return json.encode(t) end
    return CoreJson.encode(t)
end

local function decode(s)
    if type(s) == "table" then return s end
    if type(s) ~= "string" or s == "" then return nil end
    if json and json.decode then
        local ok, v = pcall(json.decode, s)
        if ok and type(v) == "table" then return v end
    end
    local v = CoreJson.decode(s)
    return type(v) == "table" and v or nil
end

local cache = {}      -- playerId -> profile record (+ userId)
NcmIdentity.cache = cache

--- Wait until ncm_league's migrations exist (first boot race). Returns true or false.
local function schemaReady()
    for _ = 1, 20 do
        local ok, n = pcall(function()
            return MySQL.scalar.await("SELECT COUNT(*) FROM schema_migrations WHERE version >= 9")
        end)
        if ok and tonumber(n) and tonumber(n) >= 1 then return true end
        Wait(500)
    end
    return false
end

-- Ownership identifiers, added by OPEN//77 op77.102 to prove a player owns a genuine Cyberpunk licence.
--
-- **The binding key is deliberately NOT changed.** `ncm_driver_binding.user_id` has been
-- `GetPlayerIdentifier()` since M2.1, and every driver, profile, SR row and machine in the database hangs
-- off it. If `license` turns out to be a different string, switching to it would orphan every existing
-- driver in one deploy -- silently, because a missing binding just mints a new one and the player finds an
-- empty garage.
--
-- So this observes and reports rather than migrating. It logs, once per player, whether the new `license`
-- identifier matches the key NCM already uses. That answers the question from ordinary play, with no
-- probe session and nothing asked of anyone. **Migrate only on the evidence** -- and if they do differ, the
-- migration is a backfill of a second column, never an in-place key change.
local reportedIdentifiers = {}

local function observeIdentifiers(id, userId)
    if reportedIdentifiers[userId] then return end
    reportedIdentifiers[userId] = true

    local ok, ids = pcall(function()
        if Open77 and Open77.players and Open77.players.identifiers then
            return Open77.players.identifiers(id)
        end
        return nil
    end)
    if not ok or type(ids) ~= "table" then
        -- Absent is not a negative: an older server simply does not have this yet (`IDEA-361`).
        log("identifiers: API not available on this build; binding key unchanged")
        return
    end

    local license = ids.license
    -- Steam and GOG are recorded as PRESENT or ABSENT only. They are account identifiers for a third-party
    -- store and NCM has no use for their values, so it does not write them down.
    log("identifiers: license=%s steam=%s gog=%s | matches binding key: %s",
        tostring(license) ~= "nil" and "present" or "absent",
        ids.steam and "present" or "absent",
        ids.gog and "present" or "absent",
        tostring(license == userId))

    if license ~= nil and license ~= userId then
        log("IDENTITY DIVERGENCE: license differs from the binding key. Do NOT switch the key without a " ..
            "backfill migration -- every existing driver would orphan. See BACKLOG IDEA-479.")
    end
end

--- Load or create the driver for a connected player. Runs inside a thread. Returns profile or nil, reason.
function NcmIdentity.resolve(playerId)
    local id = tonumber(playerId) or 0
    local userId = GetPlayerIdentifier(id)
    local name = GetPlayerName(id)
    if type(userId) ~= "string" or userId == "" then return nil, "no_user_id" end
    if type(name) ~= "string" or name == "" then name = "driver-" .. tostring(id) end
    pcall(observeIdentifiers, id, userId)
    local sid = serverId()

    if not MySQL.isReady() then return nil, "database_not_ready" end
    if not schemaReady() then return nil, "schema_not_ready" end

    local row = MySQL.single.await(
        "SELECT b.ncm_driver_id, p.display, p.number, p.dimensions, p.sr, p.onboarding_json " ..
        "FROM ncm_driver_binding b LEFT JOIN driver_profile p " ..
        "ON p.ncm_driver_id = b.ncm_driver_id AND p.server_id = b.server_id " ..
        "WHERE b.server_id = ? AND b.user_id = ?", { sid, userId })

    local profile
    local minted = false
    if row and row.ncm_driver_id then
        profile = {
            ncmDriverId = row.ncm_driver_id,
            serverId = sid,
            display = row.display or name,
            number = row.number and tonumber(row.number) or nil,
            dimensions = decode(row.dimensions) or Driver.defaultDimensions(),
            sr = decode(row.sr) or Driver.defaultSafety(),
            onboarding = row.onboarding_json and decode(row.onboarding_json) or nil,   -- P29: questionnaire document, never shown
        }
        if not row.display then
            -- binding without a profile (should not happen; heal it)
            MySQL.update.await(
                "INSERT INTO driver_profile (ncm_driver_id, server_id, display, dimensions, sr) VALUES (?, ?, ?, ?, ?)",
                { profile.ncmDriverId, sid, name, encode(profile.dimensions), encode(profile.sr) })
        end
    else
        local d = Driver.mint({ rng = hostRng, origin = "online" })
        profile = Driver.newProfile(d.ncmDriverId, sid, name)
        local ok, reason = MySQL.transaction.await({
            { query = "INSERT INTO ncm_driver (ncm_driver_id, origin) VALUES (?, ?)", values = { d.ncmDriverId, "online" } },
            { query = "INSERT INTO ncm_driver_binding (server_id, user_id, ncm_driver_id) VALUES (?, ?, ?)", values = { sid, userId, d.ncmDriverId } },
            { query = "INSERT INTO driver_profile (ncm_driver_id, server_id, display, dimensions, sr) VALUES (?, ?, ?, ?, ?)",
              values = { d.ncmDriverId, sid, name, encode(profile.dimensions), encode(profile.sr) } },
        })
        if not ok then return nil, "mint_failed:" .. tostring(reason) end
        minted = true
    end

    profile.userId = userId
    profile.playerId = id
    profile.minted = minted
    cache[id] = profile

    -- Public view on the player's bag (visible to the bucket; contains nothing private).
    -- bag:set answers false, reason rather than raising (needs manifest permission "state.write").
    local okBag, setOk, reason = pcall(function()
        local bag = Open77.state.player(id)
        return bag:set("ncm", Driver.publicView(profile))
    end)
    if not okBag then reason = setOk end
    if not okBag or setOk ~= true then log("state bag write failed for player %d: %s", id, tostring(reason)) end

    -- The Driver Card is a second, deliberately narrower public projection. Presentation owns its own
    -- selection/entitlement validation; identity supplies only the resolved durable driver.
    if NcmPresentation and NcmPresentation.publish then
        local okPresentation, presentationReason = NcmPresentation.publish(id, profile)
        if not okPresentation then log("presentation unavailable for player %d: %s", id, tostring(presentationReason)) end
    end

    log("%s player=%d user=%s -> driver=%s display=%s server=%s", minted and "MINTED" or "loaded",
        id, userId, profile.ncmDriverId, profile.display, sid)
    return profile
end

function NcmIdentity.get(playerId)
    return cache[tonumber(playerId) or 0]
end

--- Persist the questionnaire document (onboarding.questionnaire `document`) on the profile and mark the bag.
function NcmIdentity.saveOnboarding(playerId, doc)
    local id = tonumber(playerId) or 0
    local profile = cache[id]
    if not profile then return false, "no_profile" end
    profile.onboarding = doc
    if MySQL.isReady() then
        local ok, err = pcall(function()
            MySQL.update.await("UPDATE driver_profile SET onboarding_json = ? WHERE ncm_driver_id = ? AND server_id = ?",
                { encode(doc), profile.ncmDriverId, profile.serverId })
        end)
        if not ok then log("onboarding save failed for %s: %s", profile.ncmDriverId, tostring(err)) end
    end
    pcall(function() Open77.state.player(id):set("ncmOnboarding", { version = doc.version, complete = true }) end)
    return true
end

--- Does this profile need the questionnaire (never done, or an older version)?
function NcmIdentity.onboardingPending(profile, version)
    if not profile then return false end
    local doc = profile.onboarding
    return not (type(doc) == "table" and tonumber(doc.version) and tonumber(doc.version) >= version)
end

function NcmIdentity.forget(playerId)
    cache[tonumber(playerId) or 0] = nil
end

--- One-line description for chat/console.
function NcmIdentity.describe(profile)
    if not profile then return "no NCM driver" end
    return ("NCM Driver %s | #%s | rep %s | SR %s | id %s"):format(
        tostring(profile.display), tostring(profile.number or "--"),
        tostring(profile.dimensions and profile.dimensions.reputation or 0),
        tostring(profile.sr and profile.sr.sr or "?"), tostring(profile.ncmDriverId))
end
