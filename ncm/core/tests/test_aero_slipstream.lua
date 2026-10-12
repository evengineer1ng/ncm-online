-- aero.wake (the phenomenon) and aero.slipstream (the product), L356. These are the brief's A-G checks that can be
-- made deterministic: two identical cars, the follower placed by geometry, the effect read as a force.
local V = 50                                     -- m/s (180 km/h), both cars

local function leader() return { id = "L", x = 0, y = 0, heading = 0, speed = V } end
-- heading 0 travels along +x, so "behind" is -x and "left" is +y
local function follower(gap, offset, heading) return { id = "F", x = -gap, y = offset or 0, heading = heading or 0, speed = V } end

local function q(T, gap, offset, heading)
    local W = T.Core.get("aero.wake")
    return (W.quality(W.geometry(follower(gap, offset, heading), leader())))
end

-- Run a unit for `seconds` held at one geometry; return the state.
local function hold(T, gap, offset, seconds, enabled)
    local W, S = T.Core.get("aero.wake"), T.Core.get("aero.slipstream")
    local st = S.newState()
    for _ = 1, math.floor(seconds / 0.05) do S.step(st, W.best(follower(gap, offset), { leader() }), 0.05, enabled) end
    return st
end

return {
    A_natural_draft_exists_without_any_module = function(T)
        local W, S = T.Core.get("aero.wake"), T.Core.get("aero.slipstream")
        local aligned = q(T, 10, 0)
        local control = q(T, 10, 6)                    -- the same gap, a lane over
        T.ok(aligned > 0.5, ("aligned 10 m back is a strong wake (q=%.3f)"):format(aligned))
        T.ok(control < 0.01, ("a lane over is clean air (q=%.4f)"):format(control))
        local st = S.newState()
        local total, natural, active = S.relief(aligned, st, false)
        T.ok(natural > 0 and active == 0 and total == natural, "no module: natural relief only")
        T.ok(S.towN(total, V) > 50, ("the natural tow is a real force at 180 km/h (%.0f N)"):format(S.towN(total, V)))
    end,

    B_the_module_adds_measurable_relief_on_top = function(T)
        local S = T.Core.get("aero.slipstream")
        local off = hold(T, 10, 0, 4, false)
        local on = hold(T, 10, 0, 4, true)
        local qq = q(T, 10, 0)
        local nOff = S.towN((S.relief(qq, off, false)), V)
        local nOn = S.towN((S.relief(qq, on, true)), V)
        T.eq(on.phase, "active")
        T.ok(nOn > 2.5 * nOff, ("module %.0f N vs natural %.0f N"):format(nOn, nOff))
    end,

    C_geometry_is_continuous_and_vanishes_outside_the_wake = function(T)
        -- lateral sweep at 10 m: monotone down from the centreline, no step bigger than a smooth curve makes
        local prev = q(T, 10, 0)
        for i = 1, 40 do
            local cur = q(T, 10, i * 0.1)
            T.ok(cur <= prev + 1e-9, ("offset %.1f m does not rise (%.4f > %.4f)"):format(i * 0.1, cur, prev))
            T.ok(prev - cur < 0.12, ("offset %.1f m: no jump (%.4f -> %.4f)"):format(i * 0.1, prev, cur))
            prev = cur
        end
        T.ok(prev < 0.01, "4 m off the centreline is outside the wake")
        -- gap sweep: rises from overlap to a peak, then decays smoothly; nothing past the wake's end
        local W = T.Core.get("aero.wake")
        local peakGap, peak = 0, 0
        local last = q(T, 4, 0)
        T.eq(last, 0, "overlapping cars: no wake to sit in")
        for gap = 4.5, 100, 0.25 do
            local cur = q(T, gap, 0)
            T.ok(math.abs(cur - last) < 0.12, ("gap %.1f m: no jump (%.4f -> %.4f)"):format(gap, last, cur))
            if cur > peak then peak, peakGap = cur, gap end
            last = cur
        end
        T.ok(peakGap >= 6 and peakGap <= 10, ("the pocket peaks a few metres back (%.1f m)"):format(peakGap))
        T.eq(q(T, W.CONFIG.maxLengthM + 1, 0), 0, "nothing past the wake's end")
        T.ok(q(T, 30, 0) > q(T, 60, 0) and q(T, 60, 0) > 0, "decays with distance, still there at 60 m at 180 km/h")
        -- a strong high-speed wake is worth far more than clipping the edge of a slow one
        local S = T.Core.get("aero.slipstream")
        local edge = W.quality(W.geometry({ x = -30, y = 2.5, heading = 0, speed = 20 }, { x = 0, y = 0, heading = 0, speed = 20 }))
        T.ok(S.towN(S.relief(q(T, 9, 0), hold(T, 9, 0, 4, true), true), V) > 20 * S.towN(S.relief(edge, hold(T, 30, 2.5, 4, true), true), 20),
            "perfect at 180 km/h >> the edge at 72 km/h")
        -- alignment: a car crossing the wake at an angle gets nothing
        T.ok(q(T, 10, 0, 45) == 0, "a crossing car is not in the wake")
        T.ok(q(T, 10, 0, 10) < q(T, 10, 0, 0), "a few degrees off line costs some of it")
    end,

    acquisition_is_progressive_and_leaving_removes_it = function(T)
        local W, S = T.Core.get("aero.wake"), T.Core.get("aero.slipstream")
        local st = S.newState()
        local seen, locks = {}, {}
        for i = 1, 60 do
            S.step(st, W.best(follower(10, 0), { leader() }), 0.05, true)
            seen[st.phase] = true
            locks[i] = st.lock
        end
        T.ok(seen.acquiring and seen.active, "acquiring, then active")
        T.ok(locks[5] > 0 and locks[5] < locks[10] and locks[10] < 1, "the lock builds over time, not in one step")
        -- leave the wake: the unit says so, then the lock (and the assist) bleed away
        for _ = 1, 10 do S.step(st, W.best(follower(10, 8), { leader() }), 0.05, true) end
        T.eq(st.phase, "lost")
        for _ = 1, 40 do S.step(st, W.best(follower(10, 8), { leader() }), 0.05, true) end
        T.eq(st.lock, 0); T.eq(st.phase, "searching")
        local total, natural, active = S.relief(0, st, true)
        T.eq(total, 0); T.eq(active, 0)
        -- approaching from far behind: detected before acquiring
        local st2, order = S.newState(), {}
        for gap = 80, 9, -1 do
            S.step(st2, W.best(follower(gap, 0), { leader() }), 0.05, true)
            if order[#order] ~= st2.phase then order[#order + 1] = st2.phase end
        end
        T.eq(order[1], "detected", "a distant wake is detected first: " .. table.concat(order, ">"))
    end,

    D_network_notices_follow_hardware = function(T)
        local S = T.Core.get("aero.slipstream")
        -- 1. equipped follower -> unequipped leader: the follower sees its own link, the leader hears nothing
        local a = S.notices(true, false); T.eq(a.follower, "plain"); T.eq(a.leader, nil)
        -- 2. equipped follower -> equipped leader: both know
        local b = S.notices(true, true); T.eq(b.follower, "peer"); T.eq(b.leader, "inbound")
        -- a follower whose unit is not (yet) active tells nobody anything
        local c = S.notices(false, true); T.eq(c.follower, nil); T.eq(c.leader, nil)
        -- 3-5 (NPC/human pairings) use these same rules on the server; see ncm_slipstream/server
    end,

    G_disabled_means_no_lock_no_assist_but_the_air_is_still_there = function(T)
        local S = T.Core.get("aero.slipstream")
        local st = hold(T, 10, 0, 4, true)
        T.eq(st.phase, "active")
        local W = T.Core.get("aero.wake")
        S.step(st, W.best(follower(10, 0), { leader() }), 0.05, false)    -- switched off mid-tow
        T.eq(st.phase, "searching"); T.eq(st.lock, 0)
        local qq = q(T, 10, 0)
        local total, natural, active = S.relief(qq, st, false)
        T.eq(active, 0)
        T.ok(natural > 0 and total == natural, "the natural draft remains")
    end,

    E_F_one_model_for_every_session = function(T)
        -- the wake knows nothing of qualifying, races, ovals or drag strips: same geometry, same answer, so a tow is
        -- available everywhere (no session switch exists to disable it)
        local W = T.Core.get("aero.wake")
        T.ok(W.CONFIG.minSpeed < 20, "a wake from ordinary street speeds")
        T.ok(q(T, 10, 0) > 0, "and at speed")
    end,

    npcs_use_the_same_physics_as_a_target_speed = function(T)
        local S = T.Core.get("aero.slipstream")
        T.eq(S.npcSpeedFactor(0), 1)
        local qq = q(T, 10, 0)
        local st = hold(T, 10, 0, 4, true)
        local f = S.npcSpeedFactor((S.relief(qq, st, true)))
        T.ok(f > 1.03 and f <= S.CONFIG.npcSpeedCap, ("a towed NPC aims faster (x%.3f)"):format(f))
        T.ok(S.npcSpeedFactor((S.relief(qq, S.newState(), false))) < f, "a natural tow is smaller than an equipped one")
        -- a cautious driver will not hold a lock that close; an aggressive one will
        local W = T.Core.get("aero.wake")
        local cautious, bold = S.newState(), S.newState()
        for _ = 1, 80 do
            S.step(cautious, W.best(follower(7, 0), { leader() }), 0.05, true, nil, S.npcPolicy({ aggression = 20 }))
            S.step(bold, W.best(follower(7, 0), { leader() }), 0.05, true, nil, S.npcPolicy({ aggression = 80 }))
        end
        T.eq(cautious.lock, 0); T.eq(bold.phase, "active")
        -- equipment is a team's choice, stable per driver
        T.eq(S.npcEquipped("w", "p00001"), S.npcEquipped("w", "p00001"))
        local n = 0
        for i = 1, 400 do if S.npcEquipped("w", ("p%05d"):format(i)) then n = n + 1 end end
        T.ok(n > 100 and n < 180, ("about a third of drivers run one (%d of 400)"):format(n))
    end,

    direction_comes_from_velocity = function(T)
        local W = T.Core.get("aero.wake")
        -- heading field says one thing, velocity another: the wake follows travel
        local s = W.fromSnapshot(1, { position = { x = 0, y = 0 }, heading = 123, velocity = { x = 0, y = 30 }, speed = 30 })
        T.ok(math.abs(s.heading - 90) < 1e-6)
        local p = W.fromPositions(2, { x = 0, y = 0 }, { x = -10, y = 0 }, 0.25)
        T.ok(math.abs(math.abs(p.heading) - 180) < 1e-6); T.ok(math.abs(p.speed - 40) < 1e-6)
    end,

    the_unit_installs_in_the_bay_on_any_road_car = function(T)
        local I, S = T.Core.get("engineering.installation"), T.Core.get("aero.slipstream")
        local d = I.design(S.DESIGN_ID)
        T.ok(d and d.family == "slipstream" and d.sale and d.sale.market == "base", "an SL-1 for sale on the Base Market")
        local V2 = T.Core.get("data.vehicle_catalogue")
        local fits, total = 0, 0
        for _, e in ipairs(V2.entries()) do
            total = total + 1
            if I.check(d, e.vehicleKey, "mount.electronics", "fore").ok then fits = fits + 1 end
        end
        T.eq(fits, total, "every catalogue car has the bay")
        T.falsy(I.check(d, "archer_hella", "mount.rear", "aft").ok, "not on a hardpoint")
        T.falsy(I.check(I.design("eng:thorton:od6:r1"), "archer_hella", "mount.electronics", "fore").ok, "nothing else in the bay")
        T.ok(I.check(d, "archer_hella", "mount.electronics", "fore").ok)
        T.ok(T.Core.get("engineering.systems").validate(d.perf))
    end,
}
