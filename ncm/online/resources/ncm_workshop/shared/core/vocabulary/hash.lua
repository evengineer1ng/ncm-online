-- ncm-core module: vocabulary.hash
-- Stable string hashing and seeded random streams for anything that must replay identically (doc 44, L221).
--
-- FNV-1a 32-bit, computed ARITHMETICALLY. LuaJIT has no `~` operator and a chunk that merely contains one fails to
-- load there, which is why `data/vehicle_config.lua` once rejected FNV outright. XOR comes from a runtime-compiled
-- native `~` where the interpreter has it, else from a nibble table (the KB-211 fix in `competition/scanner.lua`).
-- The multiply by the FNV prime 16777619 = 2^24 + 403 is split so no intermediate exceeds 2^53, which keeps every
-- step exact in a double under both Lua 5.4 and LuaJIT.
--
-- Cost matters on OPEN//77, which meters instructions per handler (KB-211). Hash ONCE per entity to seed a stream,
-- then draw from the stream: a Park-Miller step is a multiply and a modulo.
local Core = NcmCore

Core.define("vocabulary.hash", function()
    local M = { version = "0.1.0" }

    local TWO32 = 4294967296
    local PM_MOD = 2147483647

    local NIB = {}
    for a = 0, 15 do
        NIB[a] = {}
        for b = 0, 15 do
            local r, bit, x, y = 0, 1, a, b
            for _ = 1, 4 do
                if (x % 2) ~= (y % 2) then r = r + bit end
                x, y, bit = math.floor(x / 2), math.floor(y / 2), bit * 2
            end
            NIB[a][b] = r
        end
    end
    -- XOR of an unsigned 32-bit value with one byte: only the low 8 bits change.
    local function xorByteTable(h, byte)
        local low = h % 256
        local lo, hi = low % 16, math.floor(low / 16)
        return h - low + NIB[hi][math.floor(byte / 16)] * 16 + NIB[lo][byte % 16]
    end
    local xorByte = xorByteTable
    do
        local compile = load or loadstring
        local ok, fn = pcall(function()
            local chunk = compile and compile("return function(h, b) return math.tointeger(h) ~ math.tointeger(b) end")
            return chunk and chunk()
        end)
        if ok and type(fn) == "function" and pcall(fn, 1, 3) and fn(0x811c9dc5, 0x61) == 0x811c9da4 then
            xorByte = fn
        end
    end
    M._xorByteTable = xorByteTable   -- exposed for tests: both paths must agree

    --- FNV-1a 32-bit of a string, as an unsigned integer in [0, 2^32).
    function M.fnv1a32(s)
        s = tostring(s)
        local h = 2166136261
        for i = 1, #s do
            h = xorByte(h, s:byte(i))
            -- h * 16777619 mod 2^32 == (h * 403 + (h mod 256) * 2^24) mod 2^32
            h = (h * 403 + (h % 256) * 16777216) % TWO32
        end
        return h
    end

    --- The key parts joined the way every caller joins them, so `key("a", 1)` never collides with `key("a1")`.
    function M.key(...)
        local parts = { ... }
        for i = 1, #parts do parts[i] = tostring(parts[i]) end
        return table.concat(parts, "|")
    end

    --- A Park-Miller state in [1, 2^31-2] from any key parts.
    function M.seed(...)
        local s = M.fnv1a32(M.key(...)) % (PM_MOD - 1)
        return s + 1
    end

    --- A deterministic stream: `r()` -> [0,1), `r:int(a, b)` inclusive, `r:pick(list)`, `r:chance(p)`,
    --- `r:normal(mean, sd)`. Identical under Lua 5.4 and LuaJIT for the same key parts.
    function M.stream(...)
        local state = M.seed(...)
        local s = {}
        local function nextf()
            state = (state * 48271) % PM_MOD
            return (state - 1) / (PM_MOD - 1)
        end
        setmetatable(s, { __call = function() return nextf() end })
        function s.float() return nextf() end
        function s.int(_, a, b)
            if b == nil then a, b = 1, a end
            return a + math.floor(nextf() * (b - a + 1))
        end
        function s.pick(_, list)
            if type(list) ~= "table" or #list == 0 then return nil end
            return list[1 + math.floor(nextf() * #list)]
        end
        function s.chance(_, p) return nextf() < (p or 0) end
        -- Irwin-Hall with 6 draws: bounded, cheap, and close enough to normal for attribute rolls.
        function s.normal(_, mean, sd)
            local acc = 0
            for _ = 1, 6 do acc = acc + nextf() end
            return (mean or 0) + (sd or 1) * (acc - 3) * 1.4142135623730951
        end
        function s.weighted(_, entries, weightKey)
            weightKey = weightKey or "weight"
            local total = 0
            for i = 1, #entries do total = total + (entries[i][weightKey] or 0) end
            if total <= 0 then return nil end
            local pick, acc = nextf() * total, 0
            for i = 1, #entries do
                acc = acc + (entries[i][weightKey] or 0)
                if pick < acc then return entries[i], i end
            end
            return entries[#entries], #entries
        end
        function s.state() return state end
        return s
    end

    --- One [0,1) draw keyed by the parts, without a stream.
    function M.unit(...)
        return (M.seed(...) - 1) / (PM_MOD - 1)
    end

    --- Deterministic pick from a list keyed by the parts.
    function M.pick(list, ...)
        if type(list) ~= "table" or #list == 0 then return nil end
        return list[1 + (M.fnv1a32(M.key(...)) % #list)]
    end

    --- An 8-hex commitment of a value, for publishing that a seed existed without revealing it.
    function M.commit(...)
        return string.format("%08x", M.fnv1a32(M.key("commit", ...)))
    end

    return M
end)
