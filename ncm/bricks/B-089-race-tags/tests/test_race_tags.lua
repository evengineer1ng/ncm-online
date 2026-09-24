local ROOT = (arg and arg[1]) or "."
local M = NcmCore.get("competition.race_tags")

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = copy(v)
    end
    return out
end

local function hasTag(driver, id)
    for i = 1, #driver.tags do
        if driver.tags[i].id == id then
            return true
        end
    end
    return false
end

local function tagIds(driver)
    local out = {}
    for i = 1, #driver.tags do
        out[i] = driver.tags[i].id
    end
    return table.concat(out, ",")
end

local function race2()
    return {
        session = {
            sessionId = "t-race2", kind = "race", timeTrial = false, fieldSize = 2,
            disciplineId = "street_sprint", tier = "street", gatesTotal = 3, greenAt = 1000.0,
        },
        results = {
            {
                driverId = "a", position = 1, state = "finished", slot = 1,
                totalSec = 100.0, correctedSec = 100.0, incidentCount = 0,
                incidents = {}, penalties = {}, jumpStart = false,
                crossings = { [1] = 1002.0, [2] = 1050.0, [3] = 1100.0 },
            },
            {
                driverId = "b", position = 2, state = "finished", slot = 2,
                totalSec = 106.0, correctedSec = 106.0, incidentCount = 0,
                incidents = {}, penalties = {}, jumpStart = false,
                crossings = { [1] = 1003.0, [2] = 1053.0, [3] = 1106.0 },
            },
        },
    }
end

local function solo()
    return {
        session = {
            sessionId = "t-solo", kind = "race", timeTrial = true, fieldSize = 1,
            disciplineId = "street_sprint", tier = "street", gatesTotal = 3, greenAt = 1000.0,
        },
        results = {
            {
                driverId = "s", position = 1, state = "finished", slot = 1,
                totalSec = 100.0, correctedSec = 100.0, incidentCount = 0,
                incidents = {}, penalties = {}, jumpStart = false,
                crossings = { [1] = 1002.0, [2] = 1050.0, [3] = 1100.0 },
            },
        },
    }
end

local cases = {}

cases.happy_fixture_default_cap = function(T)
    local fx = dofile(ROOT .. "/fixtures/race_4cars.lua")
    local out = M.evaluate(fx)
    T.eq(tagIds(out.drivers[1]), "personal_best,clean_race,close_finish,came_through")
    T.eq(tagIds(out.drivers[2]), "clean_race,close_finish")
    T.eq(tagIds(out.drivers[3]), "heavy_contact")
    T.eq(tagIds(out.drivers[4]), "did_not_finish")
end

cases.happy_fixture_max_five = function(T)
    local fx = dofile(ROOT .. "/fixtures/race_4cars.lua")
    local out = M.evaluate(fx, { maxTags = 5 })
    T.eq(tagIds(out.drivers[1]), "personal_best,clean_race,close_finish,came_through,gained_positions")
end

cases.kb35_solo_dirty_has_no_clean = function(T)
    local fx = dofile(ROOT .. "/fixtures/solo_dirty.lua")
    local out = M.evaluate(fx)
    T.eq(#out.drivers[1].tags, 0)
end

cases.kb35_solo_clean_is_clean_run = function(T)
    local fx = dofile(ROOT .. "/fixtures/solo_clean.lua")
    local out = M.evaluate(fx)
    T.ok(hasTag(out.drivers[1], "clean_run"))
    T.ok(not hasTag(out.drivers[1], "clean_race"))
    T.ok(hasTag(out.drivers[1], "personal_best"))
end

cases.kb38_dirty_race_tough_one_not_clean = function(T)
    local fx = race2()
    local r = fx.results[2]
    r.incidentCount = 3
    r.incidents = {
        { kind = "object", band = 1, dv = 2.0, t = 1010.0, attributed = "self" },
        { kind = "object", band = 1, dv = 2.0, t = 1020.0, attributed = "self" },
        { kind = "object", band = 2, dv = 5.0, t = 1030.0, attributed = "self" },
    }
    local out = M.evaluate(fx)
    T.ok(hasTag(out.drivers[2], "tough_one"))
    T.ok(not hasTag(out.drivers[2], "clean_race"))
end

cases.emits_clean_race = function(T)
    local out = M.evaluate(race2())
    T.ok(hasTag(out.drivers[1], "clean_race"))
end

cases.emits_clean_run = function(T)
    local out = M.evaluate(solo())
    T.ok(hasTag(out.drivers[1], "clean_run"))
end

cases.emits_close_finish = function(T)
    local fx = race2()
    fx.results[2].totalSec = 100.4
    fx.results[2].correctedSec = 100.4
    local out = M.evaluate(fx)
    T.ok(hasTag(out.drivers[1], "close_finish"))
    T.ok(hasTag(out.drivers[2], "close_finish"))
end

cases.emits_clear_win = function(T)
    local out = M.evaluate(race2())
    T.ok(hasTag(out.drivers[1], "clear_win"))
end

cases.emits_gained_positions = function(T)
    local fx = race2()
    fx.results[1].slot = 3
    local out = M.evaluate(fx, { maxTags = 20 })
    T.ok(hasTag(out.drivers[1], "gained_positions"))
end

cases.emits_lost_positions = function(T)
    local fx = race2()
    fx.results[2].position = 3
    fx.results[2].slot = 1
    local out = M.evaluate(fx)
    T.ok(hasTag(out.drivers[2], "lost_positions"))
end

cases.emits_good_start = function(T)
    local fx = race2()
    fx.results[1].slot = 3
    fx.results[1].crossings[1] = 1001.0
    local out = M.evaluate(fx)
    T.ok(hasTag(out.drivers[1], "good_start"))
end

cases.emits_led_every_gate = function(T)
    local out = M.evaluate(race2())
    T.ok(hasTag(out.drivers[1], "led_every_gate"))
end

cases.emits_came_through = function(T)
    local fx = race2()
    fx.results[1].crossings[1] = 1004.0
    fx.results[2].crossings[1] = 1003.0
    local out = M.evaluate(fx)
    T.ok(hasTag(out.drivers[1], "came_through"))
end

cases.emits_heavy_contact = function(T)
    local fx = solo()
    fx.results[1].incidentCount = 1
    fx.results[1].incidents = { { kind = "object", band = 3, dv = 12.0, t = 1020.0, attributed = "self" } }
    local out = M.evaluate(fx)
    T.ok(hasTag(out.drivers[1], "heavy_contact"))
end

cases.emits_tough_one = function(T)
    local fx = solo()
    fx.results[1].incidentCount = 3
    fx.results[1].incidents = {
        { kind = "object", band = 1, dv = 2.0, t = 1010.0, attributed = "self" },
        { kind = "object", band = 1, dv = 2.0, t = 1020.0, attributed = "self" },
        { kind = "object", band = 2, dv = 5.0, t = 1030.0, attributed = "self" },
    }
    local out = M.evaluate(fx)
    T.ok(hasTag(out.drivers[1], "tough_one"))
end

cases.emits_jump_start = function(T)
    local fx = race2()
    fx.results[2].jumpStart = true
    local out = M.evaluate(fx)
    T.ok(hasTag(out.drivers[2], "jump_start"))
end

cases.emits_penalised = function(T)
    local fx = race2()
    fx.results[2].penalties = { { seconds = 5, reason = "race_control", at = 1010.0 } }
    local out = M.evaluate(fx)
    T.ok(hasTag(out.drivers[2], "penalised"))
end

cases.emits_did_not_finish = function(T)
    local fx = race2()
    fx.results[2].state = "dnf"
    fx.results[2].totalSec = nil
    fx.results[2].correctedSec = nil
    local out = M.evaluate(fx)
    T.ok(hasTag(out.drivers[2], "did_not_finish"))
end

cases.emits_personal_best = function(T)
    local fx = solo()
    fx.results[1].previousBestSec = 101.0
    local out = M.evaluate(fx)
    T.ok(hasTag(out.drivers[1], "personal_best"))
end

cases.emits_route_record_and_suppresses_personal_best = function(T)
    local fx = solo()
    fx.results[1].previousBestSec = 101.0
    fx.routeRecordSec = 101.0
    local out = M.evaluate(fx)
    T.ok(hasTag(out.drivers[1], "route_record"))
    T.ok(not hasTag(out.drivers[1], "personal_best"))
end

cases.catalogue_every_id_is_known = function(T)
    local seen = {}
    for i = 1, #M.CATALOGUE do
        local item = M.CATALOGUE[i]
        T.ok(type(item.id) == "string")
        T.ok(type(item.label) == "string")
        T.ok(not seen[item.id])
        seen[item.id] = true
    end
    for i = 1, #M.DEFAULTS.priority do
        T.ok(seen[M.DEFAULTS.priority[i]], "priority id must exist in catalogue")
    end
end

cases.boundary_max_tags_zero = function(T)
    local out = M.evaluate(race2(), { maxTags = 0 })
    T.eq(#out.drivers[1].tags, 0)
    T.eq(#out.drivers[2].tags, 0)
end

cases.boundary_thresholds_are_inclusive = function(T)
    local fx = race2()
    fx.results[2].totalSec = 100.5
    fx.results[2].correctedSec = 100.5
    fx.results[1].slot = 3
    local out = M.evaluate(fx, { maxTags = 20 })
    T.ok(hasTag(out.drivers[1], "close_finish"))
    T.ok(hasTag(out.drivers[1], "gained_positions"))
end

cases.boundary_personal_best_equal_is_not_best = function(T)
    local fx = solo()
    fx.results[1].previousBestSec = 100.0
    local out = M.evaluate(fx)
    T.ok(not hasTag(out.drivers[1], "personal_best"))
end

cases.edge_clear_win_requires_finished_p2 = function(T)
    local fx = race2()
    fx.results[2].state = "dnf"
    local out = M.evaluate(fx)
    T.ok(not hasTag(out.drivers[1], "clear_win"))
end

cases.edge_corrected_time_falls_back_to_total = function(T)
    local fx = race2()
    fx.results[1].correctedSec = nil
    fx.results[2].correctedSec = nil
    fx.results[2].totalSec = 100.4
    local out = M.evaluate(fx)
    T.ok(hasTag(out.drivers[1], "close_finish"))
end

cases.edge_missing_gate_one_suppresses_start_and_led = function(T)
    local fx = race2()
    fx.results[1].slot = 3
    fx.results[1].crossings[1] = nil
    local out = M.evaluate(fx)
    T.ok(not hasTag(out.drivers[1], "good_start"))
    T.ok(not hasTag(out.drivers[1], "led_every_gate"))
    T.ok(not hasTag(out.drivers[1], "came_through"))
end

cases.edge_gate_tie_is_not_led = function(T)
    local fx = race2()
    fx.results[2].crossings[2] = fx.results[1].crossings[2]
    local out = M.evaluate(fx)
    T.ok(not hasTag(out.drivers[1], "led_every_gate"))
end

cases.edge_quali_without_best_has_no_tags = function(T)
    local fx = {
        session = { sessionId = "q", kind = "quali", fieldSize = 1, disciplineId = "ncx_formula", tier = "sanctioned" },
        results = { { driverId = "q1", state = "finished", runs = 0, incidentCount = 0, incidents = {} } },
    }
    local out = M.evaluate(fx)
    T.eq(#out.drivers[1].tags, 0)
end

cases.edge_quali_clean_run_with_absent_incident_count = function(T)
    local fx = {
        session = { sessionId = "q", kind = "quali", fieldSize = 1, disciplineId = "ncx_formula", tier = "sanctioned" },
        results = { { driverId = "q1", state = "finished", bestSec = 55.0, runs = 2, incidents = {} } },
    }
    local out = M.evaluate(fx)
    T.ok(hasTag(out.drivers[1], "clean_run"))
end

cases.edge_missing_time_trial_solo_fallback_diagnostic = function(T)
    local fx = solo()
    fx.session.timeTrial = nil
    local out = M.evaluate(fx)
    T.ok(hasTag(out.drivers[1], "clean_run"))
    T.eq(out.diagnostics[1], "timeTrial absent; fieldSize 1 treated as time trial")
end

cases.invalid_facts_shape_errors = function(T)
    T.errors(function() M.evaluate(false) end, "competition%.race_tags%.evaluate:")
end

cases.invalid_results_missing_errors = function(T)
    T.errors(function() M.evaluate({ session = { kind = "race", timeTrial = false, fieldSize = 2 } }) end,
        "competition%.race_tags%.evaluate:")
end

cases.invalid_row_identity_errors = function(T)
    T.errors(function()
        M.evaluate({ session = { kind = "race", timeTrial = false, fieldSize = 2 }, results = { { state = "finished" } } })
    end, "competition%.race_tags%.evaluate:")
    T.errors(function()
        M.evaluate({ session = { kind = "race", timeTrial = false, fieldSize = 2 }, results = { { driverId = "a" } } })
    end, "competition%.race_tags%.evaluate:")
end

cases.refusal_unknown_session_kind = function(T)
    local result, reason = M.evaluate({ session = { kind = "sprint", fieldSize = 1 }, results = {} })
    T.eq(result, nil)
    T.eq(reason, "unknown_session_kind")
end

cases.never_clean_with_dirty_or_penalised_or_jump_start = function(T)
    local dirty = race2()
    dirty.results[1].incidentCount = 1
    dirty.results[1].incidents = { { kind = "object", band = 1, dv = 2, t = 1010, attributed = "self" } }
    T.ok(not hasTag(M.evaluate(dirty).drivers[1], "clean_race"))

    local penalised = race2()
    penalised.results[1].penalties = { { seconds = 5, reason = "race_control", at = 1010 } }
    T.ok(not hasTag(M.evaluate(penalised).drivers[1], "clean_race"))

    local jumped = race2()
    jumped.results[1].jumpStart = true
    T.ok(not hasTag(M.evaluate(jumped).drivers[1], "clean_race"))
end

cases.never_position_tags_outside_multicar_race = function(T)
    local ids = {
        close_finish = true, clear_win = true, gained_positions = true, lost_positions = true,
        good_start = true, led_every_gate = true, came_through = true,
    }

    local tt = solo()
    tt.results[1].slot = 5
    local ttOut = M.evaluate(tt)
    for i = 1, #ttOut.drivers[1].tags do
        T.ok(not ids[ttOut.drivers[1].tags[i].id])
    end

    local q = {
        session = { sessionId = "q", kind = "quali", fieldSize = 2, disciplineId = "ncx_formula", tier = "sanctioned" },
        results = {
            { driverId = "a", state = "finished", position = 1, slot = 3, bestSec = 50, runs = 2, incidents = {}, incidentCount = 0 },
            { driverId = "b", state = "finished", position = 2, slot = 1, bestSec = 50.1, runs = 2, incidents = {}, incidentCount = 0 },
        },
    }
    local qOut = M.evaluate(q)
    for d = 1, #qOut.drivers do
        for i = 1, #qOut.drivers[d].tags do
            T.ok(not ids[qOut.drivers[d].tags[i].id])
        end
    end

    q.session.kind = "practice"
    local pOut = M.evaluate(q)
    for d = 1, #pOut.drivers do
        for i = 1, #pOut.drivers[d].tags do
            T.ok(not ids[pOut.drivers[d].tags[i].id])
        end
    end
end

cases.never_history_tags_without_history = function(T)
    local out = M.evaluate(solo())
    T.ok(not hasTag(out.drivers[1], "personal_best"))
    T.ok(not hasTag(out.drivers[1], "route_record"))
end

cases.never_tags_dns_or_dsq = function(T)
    local fx = race2()
    fx.results[1].state = "dns"
    fx.results[1].incidents = { { kind = "object", band = 3, dv = 12, t = 1010, attributed = "self" } }
    fx.results[1].incidentCount = 3
    fx.results[2].state = "dsq"
    fx.results[2].jumpStart = true
    fx.results[2].penalties = { { seconds = 5, reason = "race_control", at = 1010 } }
    local out = M.evaluate(fx)
    T.eq(#out.drivers[1].tags, 0)
    T.eq(#out.drivers[2].tags, 0)
end

cases.never_more_than_max_tags = function(T)
    local fx = dofile(ROOT .. "/fixtures/race_4cars.lua")
    local out = M.evaluate(fx, { maxTags = 3 })
    for i = 1, #out.drivers do
        T.ok(#out.drivers[i].tags <= 3)
    end
end

cases.never_contact_specific_label_words = function(T)
    for i = 1, #M.CATALOGUE do
        local label = M.CATALOGUE[i].label:lower()
        T.ok(not label:find("wall", 1, true))
        T.ok(not label:find("car", 1, true))
        T.ok(not label:find("barrier", 1, true))
    end
end

cases.never_clean_conflicts_with_dirty_tags = function(T)
    local fx = race2()
    fx.results[1].incidentCount = 3
    fx.results[1].incidents = {
        { kind = "object", band = 3, dv = 10, t = 1010, attributed = "self" },
        { kind = "object", band = 1, dv = 2, t = 1020, attributed = "self" },
        { kind = "object", band = 1, dv = 2, t = 1030, attributed = "self" },
    }
    fx.results[1].jumpStart = true
    fx.results[1].penalties = { { seconds = 5, reason = "race_control", at = 1010 } }
    local out = M.evaluate(fx, { maxTags = 20 })
    T.ok(not hasTag(out.drivers[1], "clean_race"))
    T.ok(hasTag(out.drivers[1], "heavy_contact"))
    T.ok(hasTag(out.drivers[1], "tough_one"))
    T.ok(hasTag(out.drivers[1], "jump_start"))
    T.ok(hasTag(out.drivers[1], "penalised"))
end

cases.never_led_and_came_through_together = function(T)
    local out = M.evaluate(race2(), { maxTags = 20 })
    for i = 1, #out.drivers do
        T.ok(not (hasTag(out.drivers[i], "led_every_gate") and hasTag(out.drivers[i], "came_through")))
    end
end

cases.never_personal_or_route_record_on_race_dnf = function(T)
    local fx = race2()
    fx.results[2].state = "dnf"
    fx.results[2].previousBestSec = 200.0
    fx.routeRecordSec = 200.0
    local out = M.evaluate(fx, { maxTags = 20 })
    T.ok(not hasTag(out.drivers[2], "personal_best"))
    T.ok(not hasTag(out.drivers[2], "route_record"))
end

cases.catalogue_modes_use_session_kind_vocabulary = function(T)
    local allowed = { race = true, quali = true, practice = true }
    for i = 1, #M.CATALOGUE do
        for j = 1, #M.CATALOGUE[i].modes do
            T.ok(allowed[M.CATALOGUE[i].modes[j]], "catalogue mode must use session kind vocabulary")
        end
    end
end

cases.purity_facts_unchanged = function(T)
    local fx = dofile(ROOT .. "/fixtures/race_4cars.lua")
    local before = copy(fx)
    M.evaluate(fx, { maxTags = 5 })
    T.eq(T.show(fx), T.show(before))
end

cases.determinism_same_input_same_output = function(T)
    local fx = dofile(ROOT .. "/fixtures/race_4cars.lua")
    local a = M.evaluate(fx, { maxTags = 5 })
    local b = M.evaluate(fx, { maxTags = 5 })
    T.eq(T.show(a), T.show(b))
end

return cases
