-- machine.gearbox -- NCM's own gearbox (L306): fixed per machine, real gear counts, the emergent gearing math.
local function G(T) return T.Core.get("machine.gearbox") end

return {
    every_manual_spec_is_well_formed = function(T)
        local M = G(T)
        for id, s in pairs(M.SPECS) do
            T.eq(id:match("^%w+$") ~= nil, true, id .. ": a spec id is alphanumeric (it ends a clone record name)")
            if s.kind == M.MANUAL then
                T.eq(s.gears >= 4 and s.gears <= 8, true, id .. ": 4 to 8 gears")
                T.eq(s.firstTop > 0 and s.firstTop < 1, true, id .. ": first gear tops out below the last")
                T.eq((s.overdrive or 0) >= 0, true, id .. ": overdrive never shortens the top gear")
            else
                T.eq(id, "a", "the only non-manual spec is the automatic")
            end
        end
    end,

    every_factory_mix_names_a_real_machine_and_real_specs = function(T)
        local M = G(T)
        local Cat = T.Core.get("data.vehicle_catalogue")
        for key, mix in pairs(M.FACTORY) do
            T.eq(Cat.byKey(key) ~= nil, true, key .. " is a catalogue vehicleKey")
            for _, m in ipairs(mix) do T.eq(M.SPECS[m[1]] ~= nil, true, key .. ": spec " .. tostring(m[1])) end
        end
    end,

    the_factory_roll_is_stable_and_follows_the_mix = function(T)
        local M = G(T)
        T.eq(M.factoryRoll("asset-1", "thorton_galena").spec, M.factoryRoll("asset-1", "thorton_galena").spec, "same asset, same box")
        local seen, manual = {}, 0
        for i = 1, 2000 do
            local gb = M.factoryRoll("galena-" .. i, "thorton_galena")
            seen[gb.spec] = (seen[gb.spec] or 0) + 1
            T.eq(gb.source, M.SOURCE_FACTORY, "rolled at manufacture")
            if gb.kind == M.MANUAL then manual = manual + 1 end
        end
        T.eq(seen.a ~= nil and seen.m5 ~= nil and seen.m6 ~= nil, true, "every Galena box in the mix is produced")
        T.eq(seen.m8, nil, "nothing outside the Galena's mix")
        T.eq(manual > 700 and manual < 900, true, "about 40 % manual, got " .. manual)
        for i = 1, 50 do
            T.eq(M.factoryRoll("bike-" .. i, "yaiba_kusanagi", "Bike").kind, M.AUTOMATIC, "bikes are never manual")
        end
    end,

    owned_before_the_gearbox_means_automatic = function(T)
        local M = G(T)
        local gb = M.preGearbox()
        T.eq(gb.kind, M.AUTOMATIC, "")
        T.eq(gb.source, M.SOURCE_PRE, "")
    end,

    rows_round_trip_and_refuse_a_mismatch = function(T)
        local M = G(T)
        local gb = M.fromRow({ gearbox_kind = "manual", gearbox_spec = "m6", gearbox_source = "factory" })
        T.eq(gb.spec, "m6", "")
        T.eq(M.fromRow({ gearbox_kind = "automatic", gearbox_spec = "m6" }), nil, "a manual spec cannot be an automatic")
        T.eq(M.fromRow({ gearbox_kind = "manual", gearbox_spec = "zz" }), nil, "an unknown spec is refused")
        T.eq(M.fromRow({}), nil, "unset is nil")
        T.eq(M.fromRow({ gearbox_kind = "automatic" }).spec, "a", "")
    end,

    two_galenas_are_two_labels_and_two_records_of_one_machine = function(T)
        local M = G(T)
        local Cat = T.Core.get("data.vehicle_catalogue")
        local manual = { kind = "manual", spec = "m6" }
        T.eq(M.label("Galena", manual), "Galena · 6-speed manual", "")
        T.eq(M.label("Galena", M.preGearbox()), "Galena · automatic", "")
        local base = "Vehicle.v_standard2_thorton_galena_player"
        local clone = M.record(base, manual)
        T.eq(clone, base .. "_ncm_gbx_m6", "")
        T.eq(M.record(base, M.preGearbox()), base, "an automatic spawns its model record")
        local b, id = M.baseOf(clone)
        T.eq(b, base, "")
        T.eq(id, "m6", "")
        T.eq(select(2, M.baseOf(base)), nil, "a model record is not a clone")
        T.eq(Cat.resolveRecord(clone).vehicleKey, "thorton_galena", "the clone is the same machine")
        T.eq(Cat.topSpeedKph(clone), Cat.topSpeedKph(base), "the catalogue top speed is the model's")
    end,

    more_close_gears_cover_more_of_the_envelope = function(T)
        local M = G(T)
        T.eq(M.coverage(M.SPECS.a), 1, "the automatic is the envelope")
        local c4, c5, c8 = M.coverage("m4w"), M.coverage("m5"), M.coverage("m8")
        T.eq(c4 < c5 and c5 < c8, true, ("4 < 5 < 8 speed: %.3f %.3f %.3f"):format(c4, c5, c8))
        T.eq(c8 <= 1 and c4 > 0.5, true, "bounded")
        T.eq(M.coverage("m5c") > c5, true, "closer ratios, same count: more coverage")
    end,

    overdrive_buys_top_speed_and_pays_in_coverage = function(T)
        local M = G(T)
        T.eq(M.topKph("m6o", 200) > M.topKph("m6", 200), true, "")
        T.eq(M.topKph("a", 200), 200, "automatics are untouched")
        T.eq(M.topKph("m5", 200), 200, "no overdrive, no extra top")
        -- the shipped overdrive box (taller top, wider first) trades coverage for top speed against the plain 6-speed.
        -- (A synthetic same-box comparison held only under the old geometric spread; with the progressive spread of
        -- 2026-10-04 the two differ by under 0.001 -- the real trade is in the shipped specs.)
        T.eq(M.coverage("m6o") < M.coverage("m6"), true, "the overdrive box covers less than the plain 6-speed")
        local bands = M.bands("m6", 200)
        T.eq(#bands, 6, "")
        T.eq(math.abs(bands[6].topKph - 208) < 0.01, true, "top gear redlines at the overdrive")
        for i = 2, 6 do T.eq(bands[i].topKph > bands[i - 1].topKph, true, "gears ascend") end
    end,

    refits_need_a_clone_and_leave_the_factory_alone = function(T)
        local M = G(T)
        local Cat = T.Core.get("data.vehicle_catalogue")
        for key, ids in pairs(M.REFIT) do
            T.eq(Cat.byKey(key) ~= nil, true, key .. " is a catalogue vehicleKey")
            for _, id in ipairs(ids) do T.eq(M.isManual(M.SPECS[id]), true, key .. ": refit " .. tostring(id) .. " is a manual spec") end
        end
        -- the Hella's clones: its factory manuals, then the 7-speed refit; the factory mix itself is unchanged
        T.eq(table.concat(M.cloneSpecs("archer_hella"), ","), "m5,m6,m7", "")
        for _, m in ipairs(M.mix("archer_hella")) do T.eq(m[1] ~= "m7", true, "a refit is never a factory roll") end
        T.eq(#M.cloneSpecs("archer_hella", "Bike"), 0, "an automatic-only category gets no clones, refit or not")
        -- the 7-speed against the Hella's catalogue 167 km/h: first gear near 40, ~20 km/h steps, top gear past 167
        local bands = M.bands("m7", 167)
        T.eq(#bands, 7, "")
        T.eq(bands[1].topKph > 35 and bands[1].topKph < 45, true, "first gear tops out near 40 km/h: " .. bands[1].topKph)
        T.eq(bands[7].topKph > 167, true, "the overdrive top gear runs past the catalogue top speed")
        for i = 2, 7 do
            local step = bands[i].topKph - bands[i - 1].topKph
            T.eq(step > 12 and step < 35, true, ("gear %d is a usable step (%.0f km/h)"):format(i, step))
        end
    end,

    describe_prints_the_trade = function(T)
        local M = G(T)
        T.eq(M.describe(M.preGearbox()), "automatic", "")
        local d = M.describe({ kind = "manual", spec = "m6o" })
        T.eq(d:match("^6%-speed overdrive manual · %d+ %% coverage · top %+10 %%$") ~= nil, true, d)
    end,
}
