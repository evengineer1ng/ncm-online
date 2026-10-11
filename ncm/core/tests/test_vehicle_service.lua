return {
    paid_work_restores_chassis_and_keeps_workmanship_history = function(T)
        local S = T.Core.get("engineering.vehicle_service")
        local body = {}; for i = 1, 30 do body[i] = i == 7 and 0.8 or 0 end
        local before = { health = 0.3, body = body, tires = 1, glass = 2, lights = 0, detachedParts = 4 }
        local quote = S.quote(before, "self")
        T.ok(quote.cost > 0)
        local after, work = S.resolve(before, "self", 0, 0)
        T.eq(after.health, 1)
        T.eq(after.body[7], 0)
        T.eq(after.tires, 0); T.eq(after.glass, 0); T.eq(after.detachedParts, 0)
        T.eq(before.tires, 1, "the service leaves the historical snapshot untouched")
        local done, why = S.resolve(after, "shop", 0, 0)
        T.eq(done, nil); T.eq(why, "already_healthy")
        T.eq(work.provider, "self")
        T.ok(work.setup < 0)
        T.ok(work.scalars.gripScale < 1)
        T.ok(work.scalars.dragScale > 1)
    end,
    healthy_machine_has_no_bill = function(T)
        local S = T.Core.get("engineering.vehicle_service")
        local quote, why = S.quote({ health = 1, body = {}, tires = 0, glass = 0, lights = 0 }, "shop")
        T.eq(quote, nil); T.eq(why, "already_healthy")
    end,
    npc_damage_and_affordability = function(T)
        local S = T.Core.get("engineering.vehicle_service")
        local d = S.accumulate({ health = 0.8 }, S.raceDamage({ dnfReason = "crash" }))
        T.ok(d.health < 0.8)
        T.eq(S.raceDamage({ state = "finished" }), 0)
        T.eq(S.raceDamage({ dnfReason = "mechanical" }), 0.25)
        local poor = S.npcPlan(d, 10000, 0, "street", 200)
        T.eq(poor.action, "wait")
        local independent = S.npcPlan(d, 10000, 10000, "street", 200)
        local team = S.npcPlan(d, 10000, 10000, "premier", 700)
        T.eq(independent.provider, "self"); T.eq(team.provider, "shop")
        -- an independent fixing their own car pays for materials, never their own labour (owner 2026-10-09)
        T.ok(independent.cost > 0 and independent.materials > 0 and independent.labour == 0)
        T.ok(team.labour > 0, "a shop bills its mechanics")
        T.ok(independent.readySeconds > independent.cost * 0)
        T.ok(S.paceFactor(d) < 1)
        local _, priced = S.resolve(d, "self", 200, 0.5, 24000)
        T.eq(priced.cost, S.quote(d, "self", 24000).cost)
    end,
    repair_quality_is_usually_a_penalty = function(T)
        local S = T.Core.get("engineering.vehicle_service")
        local d = { health = 0.35 }
        local low, workLow = S.resolve(d, "self", 100, 0.01)
        local high, workHigh = S.resolve(d, "self", 900, 0.99)
        T.eq(low.health, 1); T.eq(high.health, 1)
        T.ok(workLow.botch)
        T.ok(workLow.setup < 0)
        T.ok(workHigh.setup > 0)
        T.ok(workHigh.scalars.gripScale > 1)
        T.ok(workHigh.scalars.dragScale < 1)
        local Handling = T.Core.get("parts.handling")
        local base = Handling.compose({ vehicle = "test-repair" })
        local damaged = Handling.compose({ vehicle = "test-repair", repair = workLow.scalars })
        T.ok(damaged.levers.gripScale < base.levers.gripScale)
        T.ok(damaged.levers.dragScale > base.levers.dragScale)
    end,
    paid_repair_correction_only_when_no_new_damage = function(T)
        local S = T.Core.get("engineering.vehicle_service")
        local paid = { health=0.7, body={0,0.2}, tires=0 }
        T.ok(S.noWorse({health=0.7,body={0,0.2},tires=0},paid))
        T.ok(not S.noWorse({health=0.6,body={0,0.2},tires=0},paid))
        T.ok(not S.noWorse({health=0.7,body={0,0.2},tires=2},{health=0.7,body={0,0.2},tires=1}))
        local fixed = S.restored(paid)
        T.eq(fixed.health,1); T.eq(fixed.body[2],0)
        T.eq(paid.health,0.7)
    end,
    paid_residual_correction_preserves_later_crash = function(T)
        local S = T.Core.get("engineering.vehicle_service")
        local paid = { health=0.94, body={0.2,0}, glass=27, tires=0 }
        local current = { health=0.891, body={0.3,0.1}, glass=31, tires=2 }
        local corrected = S.correctPaidResidual(current,paid)
        T.ok(math.abs(corrected.health - 0.891/0.94) < 0.0001)
        T.ok(math.abs(corrected.body[1] - 0.1) < 0.0001)
        T.eq(corrected.body[2],0.1)
        T.eq(corrected.glass,4); T.eq(corrected.tires,2)
        T.eq(current.glass,31)
    end,
    self_work_costs_no_labour = function(T)
        local S = T.Core.get("engineering.vehicle_service")
        local d = { health = 0.6, glass = 127, tires = 1 }
        local q = S.quote(d, "self", 10000)
        T.eq(q.labour, 0); T.eq(q.cost, q.materials)
        T.ok(S.quote(d, "shop", 10000).labour > 0)
    end,
    severity_is_weighted_not_worst_of = function(T)
        local S = T.Core.get("engineering.vehicle_service")
        -- the owner's car after one race (2026-10-09): health 0.555, all seven windows, one tyre -- was "100%"
        local s = S.severity({ health = 0.555, body = {}, glass = 127, lights = 0, tires = 1, detachedParts = 0 })
        T.ok(s > 0.25 and s < 0.45, "a hard race is a third of a wreck, not a write-off: " .. s)
        T.ok(S.severity({ health = 1, glass = 127, lights = 255 }) < 0.15, "broken glass and lamps are small jobs")
        local body = {}; for i = 1, 30 do body[i] = 1 end
        T.ok(S.severity({ health = 0, body = body, glass = 127, lights = 255, tires = 15, detachedParts = 15 }) > 0.99, "a wreck is a wreck")
    end,
    workmanship_rolls_each_section = function(T)
        local S = T.Core.get("engineering.vehicle_service")
        local d = { health = 0.5 }
        local seq = { 0.95, 0.10, 0.60, 0.02 }
        local i = 0
        local _, work = S.resolve(d, "self", 300, function() i = i + 1; return seq[i] end, 10000)
        T.eq(#work.sections, 4)
        T.eq(work.sections[1].section, "grip"); T.eq(work.sections[4].section, "drag")
        T.ok(work.sections[1].delta > 0, "a good grip roll helps")
        T.ok(work.sections[4].grade == "botched", "a very low roll botches that section only")
        T.ok(work.scalars.gripScale > 1 and work.scalars.dragScale > 1, "sections differ: grip better, drag worse")
        T.ok(work.sections[1].delta ~= work.sections[2].delta, "not one flat nerf")
        -- over many jobs, a skilled hand gains more often than it loses; an unskilled one the reverse
        local function share(skill)
            local up, n = 0, 0
            local r = 0
            for k = 1, 400 do
                local _, w = S.resolve(d, "self", skill, function() r = (r + 0.6180339887) % 1; return r end, 10000)
                for _, sec in ipairs(w.sections) do n = n + 1; if sec.delta > 0 then up = up + 1 end end
            end
            return up / n
        end
        T.ok(share(0) < 0.5, "a novice more often costs than gains")
        T.ok(share(1000) > 0.6, "an expert usually gains")
        for _, sec in ipairs(work.sections) do T.ok(sec.delta >= -0.08 and sec.delta <= 0.035) end
    end,
}
