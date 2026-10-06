-- observer.director (doc 46, L307): targets, battles, the auto director and the lens.
local function snap()
    return { at = 1000, races = {
        { r = "R-west", tier = "street", series = "Westbrook Short Ring", cars = {
            { k = "a", n = "Chang Wei", p = 1, d = 900, g = 0, v = 11 },
            { k = "b", n = "Mara Okafor", p = 2, d = 860, g = 1400 },
            { k = "c", n = "Lio Brandt", p = 3, d = 855, g = 1600 },
            { k = "d", n = "Ivy Teller", p = 4, d = 700, g = 6900 },
        } },
        { r = "R-corpo", tier = "pro", series = "Corpo Circle", cars = {
            { k = "e", n = "Sol Reyes", p = 1, d = 300, g = 0 },
            { k = "f", n = "Nika Varga", p = 2, d = 250, g = 2000 },
        } },
    } }
end

local function near(T, a, b, msg) T.ok(math.abs(a - b) < 1e-6, (msg or "") .. " " .. tostring(a) .. " vs " .. tostring(b)) end

return {
    parse_reads_what_the_operator_types = function(T)
        local D = T.Core.get("observer.director")
        T.eq(D.parse("P6").kind, "pos"); T.eq(D.parse("P6").n, 6)
        T.eq(D.parse("pos 3").n, 3)
        T.eq(D.parse("leader").kind, "leader")
        T.eq(D.parse("race Westbrook").q, "westbrook")
        T.eq(D.parse("chang").kind, "racer")
        T.falsy(D.parse(""))
        T.falsy(D.parse("pos x"))
    end,

    resolve_race_racer_pos_leader = function(T)
        local D, s = T.Core.get("observer.director"), snap()
        T.eq(D.resolve(s, D.parse("race corpo")).key, "e")
        T.eq(D.resolve(s, D.parse("racer chang")).key, "a")
        local cur = D.resolve(s, D.parse("race corpo"))
        T.eq(D.resolve(s, D.parse("p2"), cur).key, "f", "pos is in the race being watched")
        T.eq(D.resolve(s, D.parse("leader")).raceId, "R-corpo", "first race by id when nothing is watched")
        local none, why = D.resolve(s, D.parse("p9"), cur)
        T.falsy(none); T.eq(why, "no_car_at_place")
        local _, why2 = D.resolve({ races = {} }, D.parse("leader"))
        T.eq(why2, "no_running_race")
    end,

    battles_are_closest_first_and_watch_the_attacker = function(T)
        local D, s = T.Core.get("observer.director"), snap()
        local b = D.battles(s)
        T.eq(b[1].behind.k, "c"); T.eq(b[1].ahead.k, "b"); T.eq(b[1].gapMs, 200)
        local t = D.resolve(s, D.parse("battle"))
        T.eq(t.key, "c"); T.eq(t.battleWith, "b")
    end,

    battle_gap_falls_back_to_distance = function(T)
        local D = T.Core.get("observer.director")
        T.eq(D.pairGapMs({ d = 100 }, { d = 70 }, 30), 1000)
        T.falsy(D.pairGapMs({}, {}))
    end,

    resolve_is_deterministic = function(T)
        local D = T.Core.get("observer.director")
        local a, b = D.resolve(snap(), D.parse("battle")), D.resolve(snap(), D.parse("battle"))
        T.eq(a.key, b.key); T.eq(a.raceId, b.raceId)
    end,

    director_holds_then_cuts_to_a_closer_battle = function(T)
        local D, s = T.Core.get("observer.director"), snap()
        local lead = D.resolve(s, D.parse("race corpo"))
        T.falsy(D.step({ target = lead, since = 100 }, s, 105), "holds inside minShotSec")
        local t, why = D.step({ target = lead, since = 100 }, s, 120)
        T.eq(t and t.key, "c"); T.eq(why, "closer battle")
    end,

    director_keeps_a_battle_it_is_already_on = function(T)
        local D, s = T.Core.get("observer.director"), snap()
        local cur = D.resolve(s, D.parse("battle"))
        T.falsy(D.step({ target = cur, since = 100 }, s, 130))
    end,

    director_replaces_a_gone_target_at_once = function(T)
        local D, s = T.Core.get("observer.director"), snap()
        local t, why = D.step({ target = { raceId = "R-old", key = "zz" }, since = 100 }, s, 101)
        T.eq(t.key, "c"); T.eq(why, "target gone")
    end,

    rotate_and_basis_follow_the_platform_frame = function(T)
        local D = T.Core.get("observer.director")
        -- identity: forward is +Y, right is +X (X right / Y forward / Z up)
        local f, r = D.basis({ x = 0, y = 0, z = 0, w = 1 })
        near(T, f.x, 0); near(T, f.y, 1); near(T, r.x, 1); near(T, r.y, 0)
        -- 90 degrees about Z (counter-clockwise): forward turns to -X
        local h = math.sqrt(0.5)
        local f2, r2 = D.basis({ x = 0, y = 0, z = h, w = h })
        near(T, f2.x, -1); near(T, f2.y, 0); near(T, r2.x, 0); near(T, r2.y, 1)
        -- no orientation: the direction of travel
        local f3 = D.basis(nil, { x = 3, y = 0 })
        near(T, f3.x, 1); near(T, f3.y, 0)
    end,

    every_shot_sits_off_the_car_and_looks_near_it = function(T)
        local D = T.Core.get("observer.director")
        local pos = { x = 100, y = 200, z = 10 }
        local f, r = D.basis({ x = 0, y = 0, z = 0, w = 1 })
        for _, mode in ipairs(D.MODES) do
            local s = D.shot(mode, pos, f, r, 3)
            local dx, dy = s.pos.x - pos.x, s.pos.y - pos.y
            local off = math.sqrt(dx * dx + dy * dy + (s.pos.z - pos.z) ^ 2)
            T.ok(off > 0.3 and off < 40, mode .. " lens distance " .. off)
            T.ok(s.fov >= 40 and s.fov <= 90, mode .. " fov")
        end
        local chase = D.shot("chase", pos, f, r)
        T.ok(chase.pos.y < pos.y, "chase sits behind")
        local onboard = D.shot("onboard", pos, f, r)
        T.ok(onboard.pos.x > pos.x, "passenger seat is on the right")
    end,

    leapfrog_only_when_the_body_falls_behind = function(T)
        local D = T.Core.get("observer.director")
        local f = { x = 0, y = 1, z = 0 }
        T.falsy(D.leapfrog({ x = 0, y = 30, z = 10 }, { x = 0, y = 0, z = 0 }, f))
        local n = D.leapfrog({ x = 0, y = -80, z = 0 }, { x = 0, y = 0, z = 0 }, f)
        T.eq(n.y, 45); T.eq(n.z, 12)
    end,

    an_exact_car_is_picked_by_race_and_key = function(T)
        local D = T.Core.get("observer.director")
        local s = snap()
        local t = D.resolve(s, D.parse("car R-corpo f"))
        T.eq(t.key, "f"); T.eq(t.raceId, "R-corpo")
        local none, why = D.resolve(s, D.parse("car R-corpo zz"))
        T.falsy(none); T.eq(why, "car_not_in_race")
        T.falsy(D.parse("car R-corpo"))
    end,
}
