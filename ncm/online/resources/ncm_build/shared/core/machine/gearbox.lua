-- ncm-core module: machine.gearbox
--
-- **NCM's own gearbox (owner, 2026-10-04, L306).** Every machine is born `automatic` or `manual` and stays that way:
-- the gearbox is decided at manufacture, like its colour (L111), stored against the `assetId`, never re-rolled. Two
-- Galenas are one machine-index entry (`vehicleKey`) in two configurations, and every surface that offers a car
-- names which one it is.
--
-- WHAT MAKES IT OURS: gear COUNT and RATIOS are real. A manual spec is its own TweakDB record -- a clone of the
-- model whose gear array has 4 to 8 entries (`tools/gen-gearbox-records.lua`) -- so the engine itself, its RPM and
-- its sound, run the box the driver selects. The NCM Gearbox package holds the native gear; this module is the
-- pure arithmetic both sides agree on.
--
-- THE EMERGENT MATH. The native automatic picks the best gear at every speed, so it IS the envelope; the platform's
-- governor can withhold power and never add it (L157). A manual therefore cannot out-accelerate the automatic at
-- the same speed. What it trades instead (owner ruling 2: automatics untouched):
--   * COVERAGE -- the share of peak power the box keeps on tap across 0..the catalogue top speed (an ideal,
--     gapless box = 1). Torque is roughly flat below the power peak, so power falls with revs: after an upshift
--     the engine lands at `previous top / next top` of its range and pulls only that share of its peak. Few, wide
--     gears leave deep holes; more, closer gears fill them. `coverage(spec)` is the mean of the best gear's share.
--   * OVERDRIVE -- a tall top gear runs past the catalogue top speed ("untapped potential outside the usual
--     envelope"). It opens a hole below it, so it costs coverage. Class, chrome and race caps still win.
-- Pure: no database, no clock, no TweakDB.
local Core = NcmCore

Core.define("machine.gearbox", function(C)
    local Hash = C.get("vocabulary.hash")

    local M = { version = "0.1.0" }

    M.AUTOMATIC, M.MANUAL = "automatic", "manual"
    M.SOURCE_FACTORY = "factory"          -- rolled at manufacture (or for unsold stock when the gearbox arrived)
    M.SOURCE_PRE = "pre_gearbox"          -- owned before L306: automatic, by owner ruling 3
    M.CLONE_TAG = "_ncm_gbx_"             -- `<base record>_ncm_gbx_<spec id>`; spec ids are alphanumeric

    -- The power curve, against the fraction of a gear's redline the engine is at: proportional to revs up to the
    -- peak at PEAK (flat torque), then falling by FADE per unit to the limiter. First gear launches on a slipping
    -- clutch at peak revs, so it pulls full power from a standstill. Placeholders for play data, like every balance
    -- number in `machine/`.
    M.PEAK = 0.85
    M.FADE = 0.6

    --- `firstTop`: first gear's redline speed as a fraction of the top gear's. Ratios are geometric between them.
    --- `overdrive`: the top gear's redline over the catalogue top speed (0.06 = 6 % past it).
    --- `shiftMs`: how long drive is cut for a clean shift.
    M.SPECS = {
        a   = { kind = "automatic", label = "automatic" },
        m4w = { kind = "manual", gears = 4, firstTop = 0.34, overdrive = 0.00, shiftMs = 320, label = "4-speed manual" },
        m5  = { kind = "manual", gears = 5, firstTop = 0.30, overdrive = 0.00, shiftMs = 280, label = "5-speed manual" },
        m5c = { kind = "manual", gears = 5, firstTop = 0.42, overdrive = 0.00, shiftMs = 250, label = "5-speed close-ratio manual" },
        m6  = { kind = "manual", gears = 6, firstTop = 0.28, overdrive = 0.04, shiftMs = 260, label = "6-speed manual" },
        m6o = { kind = "manual", gears = 6, firstTop = 0.26, overdrive = 0.10, shiftMs = 280, label = "6-speed overdrive manual" },
        m7  = { kind = "manual", gears = 7, firstTop = 0.24, overdrive = 0.08, shiftMs = 240, label = "7-speed manual" },
        m7c = { kind = "manual", gears = 7, firstTop = 0.36, overdrive = 0.03, shiftMs = 220, label = "7-speed close-ratio manual" },
        m8  = { kind = "manual", gears = 8, firstTop = 0.30, overdrive = 0.06, shiftMs = 200, label = "8-speed manual" },
    }
    for id, s in pairs(M.SPECS) do s.id = id end

    -- What each machine is produced with, by weight. Keyed by `vehicleKey`, never by record (L99). A model not listed
    -- gets DEFAULT_MIX; a category in AUTOMATIC_ONLY is never built manual (bikes have no clutch pedal to give them,
    -- and the Formula car's sequential box is its own thing).
    M.DEFAULT_MIX = { { "a", 85 }, { "m5", 15 } }
    M.FACTORY = {
        thorton_galena       = { { "a", 60 }, { "m5", 25 }, { "m6", 15 } },
        makigai_maimai       = { { "a", 50 }, { "m5c", 30 }, { "m4w", 20 } },
        archer_hella         = { { "a", 60 }, { "m5", 30 }, { "m6", 10 } },
        thorton_colby        = { { "a", 55 }, { "m5", 30 }, { "m6o", 15 } },
        mizutani_shion       = { { "a", 50 }, { "m6", 30 }, { "m7c", 20 } },
        quadra_type66        = { { "a", 45 }, { "m6", 30 }, { "m6o", 25 } },
        quadra_turbo_r       = { { "a", 45 }, { "m6", 25 }, { "m7c", 15 }, { "m8", 15 } },
        rayfield_caliburn    = { { "a", 70 }, { "m7c", 15 }, { "m8", 15 } },
        rayfield_aerondight  = { { "a", 75 }, { "m8", 25 } },
        herrera_outlaw       = { { "a", 60 }, { "m6", 25 }, { "m8", 15 } },
        villefort_alvarado   = { { "a", 55 }, { "m6o", 30 }, { "m5", 15 } },
    }
    M.AUTOMATIC_ONLY = { Bike = true, Formula = true }

    -- Boxes a machine can be REFITTED with but is never built with (owner, 2026-10-04: "can you make it a seven speed
    -- that can reach its potential?" of the owner's Hella). A refit needs its clone to exist, so the generator builds clones
    -- for these too; the factory mix, and so production and the market, are untouched.
    M.REFIT = {
        archer_hella = { "m7" },
    }
    M.SOURCE_REFIT = "refit"              -- a stamped gearbox replaced by an explicit refit (console, owner)

    function M.spec(id) return type(id) == "string" and M.SPECS[id] or nil end

    --- Every manual spec a model needs a clone for: its factory mix, then its refits. Sorted by first appearance.
    function M.cloneSpecs(vehicleKey, category)
        local out, seen = {}, {}
        local function add(id)
            local s = M.SPECS[id]
            if s and s.kind == M.MANUAL and not seen[id] then seen[id] = true; out[#out + 1] = id end
        end
        for _, m in ipairs(M.mix(vehicleKey, category)) do add(m[1]) end
        if not (category and M.AUTOMATIC_ONLY[category]) then
            for _, id in ipairs(M.REFIT[vehicleKey] or {}) do add(id) end
        end
        return out
    end
    function M.isManual(gb) return type(gb) == "table" and gb.kind == M.MANUAL end

    --- The production mix for a machine: a list of `{ specId, weight }`.
    function M.mix(vehicleKey, category)
        if category and M.AUTOMATIC_ONLY[category] then return { { "a", 1 } } end
        return M.FACTORY[vehicleKey] or M.DEFAULT_MIX
    end

    --- The gearbox a machine was built with. Deterministic in its assetId, so the same car answers the same on every
    --- server and every replay; stored at mint all the same, so a later change to the mix never reaches a built car.
    function M.factoryRoll(assetId, vehicleKey, category)
        local mix = M.mix(vehicleKey, category)
        local total = 0
        for _, m in ipairs(mix) do total = total + m[2] end
        local pick = Hash.fnv1a32("gearbox|" .. tostring(assetId)) % total
        for _, m in ipairs(mix) do
            if pick < m[2] then
                local s = M.SPECS[m[1]]
                return { kind = s.kind, spec = s.id, source = M.SOURCE_FACTORY }
            end
            pick = pick - m[2]
        end
        return { kind = M.AUTOMATIC, spec = "a", source = M.SOURCE_FACTORY }
    end

    --- The car someone owned before gearboxes existed (owner ruling 3).
    function M.preGearbox() return { kind = M.AUTOMATIC, spec = "a", source = M.SOURCE_PRE } end

    --- A database row (`gearbox_kind`, `gearbox_spec`, `gearbox_source`) as a gearbox, or nil when unset.
    function M.fromRow(row)
        if type(row) ~= "table" or type(row.gearbox_kind) ~= "string" or row.gearbox_kind == "" then return nil end
        local s = M.SPECS[row.gearbox_spec] or (row.gearbox_kind == M.AUTOMATIC and M.SPECS.a) or nil
        if not s or s.kind ~= row.gearbox_kind then return nil end
        return { kind = s.kind, spec = s.id, source = row.gearbox_source }
    end

    --- "Galena · 6-speed manual" / "Galena · automatic".
    function M.label(displayName, gb)
        local s = gb and M.SPECS[gb.spec] or M.SPECS.a
        return ("%s · %s"):format(tostring(displayName or "Vehicle"), s.label)
    end

    -- ---------------------------------------------------------------------------------------------------
    -- Records: one clone per manual spec
    -- ---------------------------------------------------------------------------------------------------

    function M.record(baseRecord, gb)
        if type(baseRecord) ~= "string" or not M.isManual(gb) then return baseRecord end
        return baseRecord .. M.CLONE_TAG .. gb.spec
    end

    --- The model record under a clone, and the clone's spec id (nil for a record that is not a clone).
    function M.baseOf(record)
        if type(record) ~= "string" then return record, nil end
        local base, id = record:match("^(.-)" .. M.CLONE_TAG:gsub("_", "%%_") .. "(%w+)$")
        if base and M.SPECS[id] then return base, id end
        return record, nil
    end

    -- ---------------------------------------------------------------------------------------------------
    -- The gearing
    -- ---------------------------------------------------------------------------------------------------

    --- Each gear's redline speed as a fraction of the catalogue top speed. PROGRESSIVE from `firstTop` to 1 (owner QA,
    --- 2026-10-04: the geometric spread put the Hella's 1st and 2nd 12 km/h apart -- 35/47/63/85/115 -- and most
    --- downshifts were refused): road speeds are spread almost evenly, a little wider at the bottom, as a road car's
    --- are. An overdrive is the TOP gear alone made taller (1 + overdrive), as a real overdrive is -- which opens a hole
    --- before it.
    M.SPACING = 0.9
    function M.ratios(spec)
        spec = type(spec) == "string" and M.SPECS[spec] or spec
        if not spec or spec.kind ~= M.MANUAL then return nil end
        local n = spec.gears
        local out = {}
        for i = 1, n do out[i] = spec.firstTop + (1 - spec.firstTop) * ((i - 1) / (n - 1)) ^ M.SPACING end
        out[n] = out[n] * (1 + (spec.overdrive or 0))
        return out
    end

    --- Gear bands in km/h for a catalogue top speed: `{ { gear, topKph } ... }`.
    function M.bands(spec, baseTopKph)
        local r = M.ratios(spec)
        if not r or not tonumber(baseTopKph) then return nil end
        local out = {}
        for i, f in ipairs(r) do out[i] = { gear = i, topKph = f * baseTopKph } end
        return out
    end

    --- The top speed this box can reach, given the catalogue's (automatics: the catalogue's).
    function M.topKph(spec, baseTopKph)
        spec = type(spec) == "string" and M.SPECS[spec] or spec
        if not tonumber(baseTopKph) then return nil end
        if not spec or spec.kind ~= M.MANUAL then return baseTopKph end
        return baseTopKph * (1 + (spec.overdrive or 0))
    end

    --- How efficiently gear `i` (redline fraction `top`) pulls at speed fraction `v`.
    function M.efficiency(i, top, v)
        local x = v / top
        if x > 1 then return 0 end
        if x >= M.PEAK then return 1 - M.FADE * (x - M.PEAK) end
        if i == 1 then return 1 end
        return x / M.PEAK
    end

    --- The share of peak power this box keeps on tap, 0..1, best gear at every speed. An automatic answers 1: it is
    --- not rated, because its gearing is the model's own and untouched (owner ruling 2).
    function M.coverage(spec, steps)
        local r = M.ratios(spec)
        if not r then return 1 end
        steps = steps or 400
        local sum = 0
        for k = 1, steps do
            local v = (k - 0.5) / steps
            local best = 0
            for i, top in ipairs(r) do
                local e = M.efficiency(i, top, v)
                if e > best then best = e end
            end
            sum = sum + best
        end
        return sum / steps
    end

    --- One line for a listing: "6-speed manual · 97 % coverage · top +4 %".
    function M.describe(gb)
        local s = gb and M.SPECS[gb.spec] or M.SPECS.a
        if s.kind ~= M.MANUAL then return s.label end
        local od = (s.overdrive or 0) > 0 and (" · top +%d %%"):format(math.floor(s.overdrive * 100 + 0.5)) or ""
        return ("%s · %d %% coverage%s"):format(s.label, math.floor(M.coverage(s) * 100 + 0.5), od)
    end

    return M
end)
