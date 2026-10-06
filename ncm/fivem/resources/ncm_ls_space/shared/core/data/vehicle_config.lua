-- ncm-core module: data.vehicle_config
--
-- L111: **vehicle colour is deterministic and supply-constrained.** It is decided when the machine is
-- manufactured, stored against its `assetId`, and never re-rolled. Choice exists only as "pick one of the
-- machines that exist", never as a colour picker.
--
-- The symptom this closes: an owned Makigai MaiMai was brown one session and blue the next, because the engine
-- picks a paint variant per spawn and the machine had no appearance of its own. An owned machine is an
-- individual (L99); its colour is part of which individual it is.
--
-- **Deterministic alone would not have been enough.** Hashing the assetId into 24 bits of RGB is stable and
-- free, and would produce colours no factory ever made. So the hash selects from an AUTHORED PALETTE per
-- machine: what you can get is what that model is produced in. That is the supply constraint, expressed at the
-- only point it can be expressed before the allocation system exists.
--
-- When allocation (IDEA-144-148) lands it becomes the author of a machine's appearance and writes the colour
-- at mint. This module then keeps exactly one job: saying which colours a model is legitimately produced in.
local Core = NcmCore

Core.define("data.vehicle_config", function(C)
    local M = { version = "0.0.1" }

    --- Factory finishes. Restrained on purpose: these are production colours for street machines, not a
    --- customisation catalogue. Each entry is a name plus primary/secondary RGB.
    ---
    --- `secondary` is usually the same as `primary`: two-tone is a deliberate product decision, not a default.
    local function finish(name, p, s)
        return { name = name, primary = p, secondary = s or p }
    end

    -- The shared production range. A model without its own range is produced in these.
    local STOCK = {
        finish("Graphite",    { r = 38,  g = 40,  b = 45  }),
        finish("Bone",        { r = 226, g = 221, b = 208 }),
        finish("Oxide Red",   { r = 140, g = 42,  b = 34  }),
        finish("Deep Teal",   { r = 24,  g = 78,  b = 88  }),
        finish("Sand",        { r = 178, g = 150, b = 102 }),
        finish("Midnight",    { r = 22,  g = 28,  b = 52  }),
    }

    --- Ranges authored per machine. A model listed here is produced ONLY in these finishes.
    --- Keyed by `vehicleKey`, never by TweakDB record: the range belongs to the machine, not to a runtime id
    --- that a mod update could rename (L99).
    local BY_KEY = {
        makigai_maimai = {
            finish("Postbox Red",  { r = 168, g = 46,  b = 40  }),
            finish("Mint",         { r = 148, g = 190, b = 170 }),
            finish("Cream",        { r = 232, g = 224, b = 196 }),
            finish("Slate Blue",   { r = 66,  g = 92,  b = 128 }),
        },
    }

    --- The finishes a machine is produced in. Never empty: an unknown machine falls back to the stock range
    --- rather than to "no colour", because an asset with no finish is the bug this module exists to remove.
    function M.rangeFor(vehicleKey)
        local authored = type(vehicleKey) == "string" and BY_KEY[vehicleKey] or nil
        return authored or STOCK
    end

    --- Stable 32-bit hash of a string, identical on Lua 5.4 and LuaJIT.
    ---
    --- **Arithmetic only, deliberately: djb2 rather than FNV-1a.** FNV needs a bitwise XOR, and LuaJIT is
    --- 5.1-based with no `~` operator at all -- the module would not even load there. The offline gate runs
    --- both interpreters precisely to catch this, and did. Every intermediate stays far below 2^53, so the
    --- result is exact in a double on either runtime.
    ---
    --- An assetId is already a random UUID, so no further entropy is needed; this only has to be stable.
    function M.hash(s)
        local str = tostring(s or "")
        local h = 5381
        for i = 1, #str do
            h = (h * 33 + string.byte(str, i)) % 4294967296
        end
        return h
    end

    --- The finish this particular machine left the factory in.
    ---
    --- Deterministic in the strongest sense: the same assetId always yields the same finish, on any server, in
    --- any process, forever. No stored state is required for it to be stable -- storage exists so that a later
    --- authored or purchased change can override it, not to make it repeatable.
    function M.finishFor(vehicleKey, assetId)
        local range = M.rangeFor(vehicleKey)
        if type(assetId) ~= "string" or assetId == "" then return range[1] end
        local index = (M.hash(assetId) % #range) + 1
        return range[index]
    end

    --- `#RRGGBB` for storage and logs. Hex because a human reading the table should be able to see the colour.
    function M.toHex(rgb)
        if type(rgb) ~= "table" then return nil end
        local function c(v) return math.max(0, math.min(255, math.floor(tonumber(v) or 0))) end
        return string.format("#%02X%02X%02X", c(rgb.r), c(rgb.g), c(rgb.b))
    end

    function M.fromHex(hex)
        if type(hex) ~= "string" then return nil end
        local r, g, b = hex:match("^#?(%x%x)(%x%x)(%x%x)$")
        if not r then return nil end
        return { r = tonumber(r, 16), g = tonumber(g, 16), b = tonumber(b, 16) }
    end

    --- What the host should store when a machine is minted, and what it should apply on every spawn.
    --- `stored` wins when present: allocation, or a later authored change, is the author -- this module only
    --- supplies the factory default.
    function M.paintFor(vehicleKey, assetId, stored)
        local primary = stored and M.fromHex(stored.primary) or nil
        local secondary = stored and M.fromHex(stored.secondary) or nil
        if primary then
            return { primary = primary, secondary = secondary or primary, source = "stored" }
        end
        local f = M.finishFor(vehicleKey, assetId)
        return { primary = f.primary, secondary = f.secondary, name = f.name, source = "factory" }
    end

    return M
end)
