-- ncm-core module: machine.passport
--
-- L336 (owner brief 2026-10-07, "anything -> NCM MACHINE -> anything"): the MACHINE PASSPORT. Every vehicle NCM meets --
-- a Cyberpunk catalogue car, an Assetto Corsa car, a GTA vehicle, a KSA body, a modded car nobody authored -- becomes one
-- host-independent description. A host only ever INGESTS (host vehicle -> passport) or EXPRESSES (passport -> its best
-- vehicle, `machine.correspondence`); there is no host-to-host mapping anywhere.
--
-- Every field is { v = value, src = provenance, conf = 0..1 }. Provenance, strongest first in spirit (confidence decides):
--   measured   observed in a host (the Carrier's live mass, a timed run)
--   host_data  read from the host's own data (an AC ui_car.json spec, a TweakDB record)
--   metadata   a name or label (maker, model, year)
--   player     the player said so (a future identification UI) -- provenance, not physics
--   authored   NCM's own table (data.machine_seeds)
--   inferred   derived from other fields or tags
-- A guess never becomes truth: `merge` keeps the higher-confidence value and remembers the other.
local Core = NcmCore

Core.define("machine.passport", function(C)
    local M = { version = "0.1.0" }

    -- The character axes (-1..1). Recognition lives here: "ordinary / mass-market / conventional four-door" is not a spec.
    M.AXES = {
        econ = "economy (-1) <-> exotic (+1)",
        perf = "utility (-1) <-> performance (+1)",
        race = "road (-1) <-> race (+1)",
        size = "compact (-1) <-> large (+1)",
        odd = "conventional (-1) <-> unusual (+1)",
    }
    M.KINDS = { car = true, bike = true, truck = true, formula = true, van = true }
    -- body families (morphology); `machine.correspondence` holds how near each is to each other
    M.BODIES = { sedan = true, hatch = true, wagon = true, coupe = true, convertible = true, suv = true, pickup = true,
        van = true, microcar = true, supercar = true, muscle = true, formula = true, bike = true, prototype = true }

    function M.field(v, src, conf) return { v = v, src = src or "inferred", conf = conf or 0.5 } end

    --- A passport from a flat description: { identity = {...}, morphology = {...}, ... } where each leaf is a plain value
    --- (given `src`, `conf`) or already a field. `meta` = { host, key, assetId }.
    function M.new(desc, src, conf, meta)
        local p = { meta = meta or {}, groups = {} }
        for g, t in pairs(desc or {}) do
            p.groups[g] = {}
            for k, v in pairs(t) do
                if type(v) == "table" and v.v ~= nil and v.src then p.groups[g][k] = v
                else p.groups[g][k] = M.field(v, src, conf) end
            end
        end
        return p
    end

    --- The value of `group.key` (or nil), and its field.
    function M.get(p, group, key)
        local f = p and p.groups and p.groups[group] and p.groups[group][key]
        if f then return f.v, f end
        return nil, nil
    end

    --- Merge `b` into `a`: per field, the higher confidence wins; the loser is kept in `alt` (never silently lost).
    function M.merge(a, b)
        local out = { meta = a.meta or {}, groups = {} }
        for _, src in ipairs({ a, b }) do
            for g, t in pairs(src.groups or {}) do
                out.groups[g] = out.groups[g] or {}
                for k, f in pairs(t) do
                    local cur = out.groups[g][k]
                    if not cur then out.groups[g][k] = f
                    elseif (f.conf or 0) > (cur.conf or 0) then
                        out.groups[g][k] = { v = f.v, src = f.src, conf = f.conf, alt = { v = cur.v, src = cur.src, conf = cur.conf } }
                    elseif f.v ~= cur.v then
                        cur.alt = cur.alt or { v = f.v, src = f.src, conf = f.conf }
                    end
                end
            end
        end
        for k, v in pairs(b.meta or {}) do if out.meta[k] == nil then out.meta[k] = v end end
        return out
    end

    --- The Machine's passport: the authored seed for its catalogue key (or an inference from the catalogue's pool tags when
    --- there is none), then what NCM knows live -- paint, the Foundry install's mass, a measured mass -- merged over it.
    --- live = { paint = { r, g, b } | nil, massKg = n | nil (measured), addedMassKg = n, record = string, prestige, tags,
    ---         livery = data.liveries.appearance(...) | nil }
    function M.forMachine(vehicleKey, assetId, live)
        live = live or {}
        local Seeds = C.get("data.machine_seeds")
        local seed = Seeds.CYBERPUNK[vehicleKey or ""]
        local p
        if seed then
            p = M.new(seed, "authored", 0.75, { host = "cyberpunk", key = vehicleKey, assetId = assetId })
        else
            -- an unseeded record (a modded car NCM never heard of): what the host says, the rest unknown -- never refused
            p = M.new(M.inferFromTags(live.tags, live.prestige), "inferred", 0.35, { host = "cyberpunk", key = vehicleKey, assetId = assetId })
        end
        local over = { appearance = {}, performance = {} }
        -- the livery (data.liveries): an APPEARANCE of this model -- its identity, colours, art provenance, wing
        if type(live.livery) == "table" then
            for k, v in pairs(live.livery) do
                if v ~= nil then over.appearance[k] = M.field(v, "authored", (k == "primary") and 0.9 or 0.85) end
            end
        end
        if live.paint then over.appearance.primary = M.field(live.paint, "host_data", 0.95) end
        if live.massKg then over.performance.massKg = M.field(live.massKg, "measured", 0.95) end
        p = M.merge(p, { groups = over })
        if live.addedMassKg and live.addedMassKg > 0 then
            local base = M.get(p, "performance", "massKg")
            if base then p.groups.performance.massLoadedKg = M.field(base + live.addedMassKg, "inferred", 0.8) end
        end
        return p
    end

    --- The weakest passport: from role tags and prestige only (an unknown record). Fields it cannot say are absent.
    function M.inferFromTags(tags, prestige)
        local set = {}
        for _, t in ipairs(tags or {}) do set[tostring(t):lower()] = true end
        local pr = tonumber(prestige) or 2
        local desc = { morphology = { kind = "car", wheels = 4 }, character = {} }
        if set.bike or set.motorcycle then desc.morphology.kind, desc.morphology.wheels, desc.morphology.body = "bike", 2, "bike" end
        if set.truck or set.pickup then desc.morphology.body = "pickup" end
        desc.character.econ = math.max(-1, math.min(1, (pr - 2.5) / 2))
        if set.sport or set.race then desc.character.perf = 0.6 end
        return desc
    end

    -- ------------------------------------------------------------------------------------------ host ingest: Assetto Corsa
    local function num(s) local n = tostring(s or ""):gsub(",", ""):match("([%d%.]+)"); return tonumber(n) end

    --- An Assetto Corsa car -> passport. `ui` = its ui/ui_car.json (host data: brand, name, class, tags, specs); the body and
    --- character come from the authored stock table (data.machine_seeds.AC_BODY) or are inferred from the tags (any mod).
    function M.fromAc(folder, ui)
        ui = ui or {}
        local Seeds = C.get("data.machine_seeds")
        local tags = {}
        for _, t in ipairs(ui.tags or {}) do tags[tostring(t):lower()] = true end
        local spec = ui.specs or {}
        local bhp, mass = num(spec.bhp), num(spec.weight)
        local host = {
            identity = { maker = M.field(ui.brand, "host_data", 0.95), model = M.field(ui.name, "host_data", 0.95), year = ui.year and M.field(ui.year, "host_data", 0.9) or nil },
            performance = {
                massKg = mass and mass > 300 and M.field(mass, "host_data", 0.8) or nil,
                powerKw = bhp and M.field(bhp * 0.7457, "host_data", 0.8) or nil,
                topKph = num(spec.topspeed) and M.field(num(spec.topspeed), "host_data", 0.8) or nil,
            },
            architecture = { drive = (tags.fwd and "fwd") or (tags.awd and "awd") or (tags.rwd and "rwd") or nil },
            morphology = { kind = "car", wheels = 4 },
        }
        local p = M.new(host, "host_data", 0.8, { host = "assetto_corsa", key = folder })
        local authored = Seeds.acBody(folder)
        if authored then
            p = M.merge(p, M.new(authored, "authored", 0.75))
            -- a variant AC itself calls a race car (an E30 DTM, a GT4 BMW) is a race car, whatever its road base is
            if ui.class == "race" then
                p = M.merge(p, { groups = { character = { race = M.field(0.8, "host_data", 0.85), econ = M.field(0.5, "inferred", 0.8) } } })
            end
            if tags.drift or tags["#drift"] then
                p = M.merge(p, { groups = { character = { odd = M.field(0.4, "host_data", 0.8), perf = M.field(0.8, "host_data", 0.8) } } })
            end
        else
            -- a car nobody authored (a mod): infer from AC's own tags and class
            local body = (tags["hot hatchback"] and "hatch") or (tags["#suv"] and "suv") or ((tags["#supercars"] or tags["#hypercars"] or tags.supercar) and "supercar")
                or (tags.formula or tags["open wheel"]) and "formula" or "coupe"
            local race = (ui.class == "race") and 0.8 or -0.5
            local econ = bhp and math.max(-0.9, math.min(1, (bhp - 300) / 300)) or 0
            p = M.merge(p, M.new({ morphology = { body = body, doors = (body == "hatch" or body == "coupe" or body == "supercar") and 2 or 4 },
                character = { econ = econ, perf = bhp and math.min(1, bhp / 500) or 0.5, race = race } }, "inferred", 0.4))
            if body == "formula" then p.groups.morphology.kind = M.field("formula", "inferred", 0.5) end
        end
        return p
    end

    --- A compact summary for logs and the panel.
    function M.summary(p)
        local function g(gr, k) local v = M.get(p, gr, k); return v end
        return ("%s %s %s (%s, %s doors)"):format(tostring(g("identity", "maker") or "?"), tostring(g("identity", "model") or "?"),
            tostring(g("morphology", "body") or "?"), tostring(g("morphology", "kind") or "?"), tostring(g("morphology", "doors") or "?"))
    end

    return M
end)
