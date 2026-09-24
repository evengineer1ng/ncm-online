-- ncm-core module: vocabulary.ids
-- Identifier construction and validation. Randomness is injected (an `rng()` returning a
-- number in [0,1)); nothing here reads a clock or a random source on its own.
local Core = NcmCore

Core.define("vocabulary.ids", function(C)
    local M = { version = "0.0.1" }

    local HEX = "0123456789abcdef"

    local function hexByte(n)
        -- n is an integer-valued number 0..255; avoid string.format("%02x") on floats.
        local hi = math.floor(n / 16)
        local lo = n - hi * 16
        return HEX:sub(hi + 1, hi + 1) .. HEX:sub(lo + 1, lo + 1)
    end

    --- Deterministic LCG rng factory (same constants as the SP roster seeding). Returns a
    --- function producing numbers in [0,1). Pure arithmetic, stays inside double precision.
    function M.seededRng(seed)
        local state = math.floor(tonumber(seed) or 0) % 4294967296
        return function()
            state = (1664525 * state + 1013904223) % 4294967296
            return state / 4294967296
        end
    end

    --- RFC 4122 version-4 UUID from the injected rng. Lowercase, hyphenated.
    function M.uuid4(rng)
        if type(rng) ~= "function" then
            error("ids.uuid4: rng function required", 2)
        end
        local bytes = {}
        for i = 1, 16 do
            local r = rng()
            if type(r) ~= "number" or r < 0 or r >= 1 then
                error("ids.uuid4: rng must return a number in [0,1)", 2)
            end
            bytes[i] = math.floor(r * 256)
        end
        bytes[7] = 64 + (bytes[7] % 16)   -- version nibble = 4
        bytes[9] = 128 + (bytes[9] % 64)  -- variant bits = 10xx
        local parts = {}
        for i = 1, 16 do
            parts[i] = hexByte(bytes[i])
        end
        local s = table.concat(parts)
        return s:sub(1, 8) .. "-" .. s:sub(9, 12) .. "-" .. s:sub(13, 16) .. "-" .. s:sub(17, 20) .. "-" .. s:sub(21, 32)
    end

    --- Strict lowercase v4 UUID check.
    function M.isUuid(s)
        if type(s) ~= "string" or #s ~= 36 then
            return false
        end
        return s:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
            and s == s:lower()
    end

    --- Slug used for pack ids, route ids, ruleset ids: lowercase letters, digits, underscore, dash.
    function M.isSlug(s)
        return type(s) == "string" and #s >= 1 and #s <= 96 and s:match("^[a-z0-9][a-z0-9_%-]*$") ~= nil
    end

    --- Revisioned identifier "id@rev" (route@rev, ruleset@rev, pack@version).
    function M.revisioned(id, rev)
        if not M.isSlug(id) then
            error("ids.revisioned: id must be a slug, got " .. tostring(id), 2)
        end
        local n = tonumber(rev)
        if n == nil or n < 0 or math.floor(n) ~= n then
            error("ids.revisioned: rev must be a non-negative integer, got " .. tostring(rev), 2)
        end
        return id .. "@" .. tostring(math.floor(n))
    end

    --- Parse "id@rev" into id, rev. Returns nil, reason on malformed input.
    function M.parseRevisioned(s)
        if type(s) ~= "string" then
            return nil, "not_a_string"
        end
        local id, rev = s:match("^([a-z0-9][a-z0-9_%-]*)@(%d+)$")
        if id == nil then
            return nil, "malformed"
        end
        return id, tonumber(rev)
    end

    --- Settlement key: stable, human-readable, unique per (serverId, sessionId, finalizationVersion).
    function M.settlementKey(serverId, sessionId, finalizationVersion)
        if not M.isSlug(serverId) then
            error("ids.settlementKey: serverId must be a slug", 2)
        end
        if not M.isUuid(sessionId) then
            error("ids.settlementKey: sessionId must be a uuid", 2)
        end
        local v = tonumber(finalizationVersion)
        if v == nil or v < 1 or math.floor(v) ~= v then
            error("ids.settlementKey: finalizationVersion must be a positive integer", 2)
        end
        return serverId .. ":" .. sessionId .. ":v" .. tostring(math.floor(v))
    end

    return M
end)
