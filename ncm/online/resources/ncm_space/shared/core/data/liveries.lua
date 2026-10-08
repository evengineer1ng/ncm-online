-- ncm-core module: data.liveries
-- Liveries are APPEARANCES of one machine model, never separate machines (L338; doc 55 §10).
--
-- Three layers of "which car is which":
--   model       the catalogue's vehicleKey (`ncx_rb15`)                       -- what kind of machine
--   appearance  a livery here (`kimiko`), carried by a TweakDB record          -- what it looks like
--   machine     a `vehicle_asset.asset_id`, with its own serial and history    -- which one
-- Two Kimiko RB15s are two machines; a Kimiko RB15 and a Red Bull RB15 share a model.
--
-- The RB15 (Nexus 31543, "RB15 F1 Car Mod Demo" v10) is a third-party mod NCM never redistributes: the Collection
-- points at it. The liveries are NCM's own add-on (`wolvenkit-projects/ncm_rb15_liveries`, built by build_liveries.py),
-- painted on the RB15's UV layout. Each livery record is `Vehicle.v_sport1_rb15_f1_<id>` with appearanceName `<id>`.
-- Colours are what the art shows (hex); `src` says how they were obtained, so a measured value can replace them later.
local Core = NcmCore

Core.define("data.liveries", function(C)
    local M = { version = "0.1.0" }

    -- model -> { recordPrefix, base record, liveries = { id -> spec } }
    M.MODELS = {
        ncx_rb15 = {
            base = "Vehicle.v_sport1_rb15_f1",
            prefix = "Vehicle.v_sport1_rb15_f1_",
            source = { kind = "nexus_mod", nexusId = 31543, name = "RB15 F1 Car Mod Demo", version = "10",
                archive = "fable5.archive", redistribute = false },
            stock = { id = "stock", label = "Red Bull Racing (stock)",
                art = { file = "fable5\\rb15\\textures\\2019_f1_red_bull_rb15_ext_23.xbm", author = "mod author", src = "host_data" } },
            liveries = {
                kimiko = { label = "Kimiko Racing · Orbital Air", team = "kimiko",
                    -- read off the art by eye (navy body, royal-blue flashes, white lettering); measured values may replace them
                    primary = "#0B1530", secondary = "#1146CC", accent = "#E8ECF4",
                    sponsors = { "Orbital Air", "Nokota Manufacturing", "Aoba", "Masala Studios", "Bayside Cachet", "Combat Cab",
                        "New Empire", "EvenRac1ng", "ODD" },
                    wing = "rear wing main plane EVENRAC1NG / ODD; New Empire endplates; navy with royal-blue flashes",
                    art = { file = "rb15_ext_kimiko.png", badges = "rb15_badges_kimiko.png", author = "owner", src = "authored" } },
                archer = { label = "Archer", team = "archer", art = { file = "rb15_ext_archer.png", badges = "rb15_badges_archer.png", src = "authored" } },
                herrera = { label = "Herrera", team = "herrera", art = { file = "rb15_ext_herrera.png", badges = "rb15_badges_herrera.png", src = "authored" } },
                mizutani = { label = "Mizutani", team = "mizutani", art = { file = "rb15_ext_mizutani.png", badges = "rb15_badges_mizutani.png", src = "authored" } },
                quadra = { label = "Quadra", team = "quadra", art = { file = "rb15_ext_quadra.png", badges = "rb15_badges_quadra.png", src = "authored" } },
                raven = { label = "Raven", team = "raven", art = { file = "rb15_ext_raven.png", badges = "rb15_badges_raven.png", src = "authored" } },
                rayfield = { label = "Rayfield", team = "rayfield", art = { file = "rb15_ext_rayfield.png", src = "authored" } },
                spunky_monkey = { label = "Spunky Monkey", team = "spunky_monkey", art = { file = "rb15_ext_spunky_monkey.png", badges = "rb15_badges_spunky_monkey.png", src = "authored" } },
                thorton = { label = "Thorton", team = "thorton", art = { file = "rb15_ext_thorton.png", badges = "rb15_badges_thorton.png", src = "authored" } },
                yorinobu = { label = "Yorinobu", team = "yorinobu", art = { file = "rb15_ext_yorinobu.png", badges = "rb15_badges_yorinobu.png", src = "authored" } },
            },
            -- the order the deck lists them in
            order = { "kimiko", "archer", "herrera", "mizutani", "quadra", "raven", "rayfield", "spunky_monkey", "thorton", "yorinobu" },
        },
    }

    --- Every livery record of a model (for the catalogue's runtime records).
    function M.records(vehicleKey)
        local m = M.MODELS[vehicleKey or ""]
        if not m then return {} end
        local out = {}
        for _, id in ipairs(m.order) do out[#out + 1] = m.prefix .. id end
        return out
    end

    --- The livery a record carries: { model, id, spec } -- `stock` for the base record, nil for records NCM has no livery
    --- registry for (the passport then knows only what the host says). `appearance` (the live appearanceName) wins over
    --- the record suffix when given: a base record spawned with appearanceName "kimiko" IS the Kimiko car.
    function M.fromRecord(record, appearance)
        if type(record) ~= "string" then return nil end
        for key, m in pairs(M.MODELS) do
            local base = record:gsub("_ncm_gbx_%w+$", "")
            if base == m.base or base == m.base .. "_player" or base:sub(1, #m.prefix) == m.prefix then
                local id = (type(appearance) == "string" and m.liveries[appearance] and appearance) or
                    (base:sub(1, #m.prefix) == m.prefix and base:sub(#m.prefix + 1)) or nil
                if id and m.liveries[id] then return { model = key, id = id, spec = m.liveries[id], source = m.source } end
                return { model = key, id = "stock", spec = m.stock, source = m.source }
            end
        end
        return nil
    end

    local function hex(h)
        h = tostring(h or ""):gsub("#", "")
        if #h ~= 6 then return nil end
        return { tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16) }
    end
    M.hex = hex

    --- Passport appearance fields for a livery (a plain description `machine.passport.new` accepts).
    function M.appearance(l)
        if not l then return nil end
        local s = l.spec or {}
        local out = { livery = l.id, liveryLabel = s.label, liveryTeam = s.team, liveryArt = s.art and s.art.file,
            liveryAuthor = s.art and s.art.author, wing = s.wing, sourceMod = l.source and l.source.name,
            sourceNexusId = l.source and l.source.nexusId }
        if s.primary then out.primary = hex(s.primary) end
        if s.secondary then out.secondary = hex(s.secondary) end
        if s.accent then out.accent = hex(s.accent) end
        return out
    end

    return M
end)
