-- presentation.fx (NCM FX): physics quantities -> cues -> a budgeted plan. Pure and deterministic.
local function rp16()
    return { componentId = "c1", kind = "reaction_engine", pos = { 0, -2.2, 0.55 }, axis = { 0, 1, 0 },
        perf = { kind = "reaction_engine", thrustN = 30000, ispS = 360, propellant = "fuel" },
        thermal = { limitK = 450 } }
end

local function find(acts, cue)
    for _, a in ipairs(acts) do if a.cue == cue then return a end end
    return nil
end

return {
    every_cue_names_a_real_asset_and_voice = function(T)
        local Cues = T.Core.get("presentation.fx_cues")
        local ok, bad = Cues.validate()
        T.ok(ok, table.concat(bad or {}, "; "))
    end,

    a_plume_grows_with_thrust_and_goes_quiet_at_zero = function(T)
        local Fx = T.Core.get("presentation.fx")
        local d = rp16()
        local idle = Fx.activations(Fx.fromInstall("m1", { d }, { c1 = { thrustN = 0, throttle = 0 } }, { dev = {} }, { rho = 1.2 }))
        T.eq(find(idle, "plume.chemical"), nil, "no plume at zero throttle")
        local low = find(Fx.activations(Fx.fromInstall("m1", { d }, { c1 = { thrustN = 3000, throttle = 0.1 } }, { dev = {} }, { rho = 1.2 })), "plume.chemical")
        local high = find(Fx.activations(Fx.fromInstall("m1", { d }, { c1 = { thrustN = 30000, throttle = 1 } }, { dev = {} }, { rho = 1.2 })), "plume.chemical")
        T.ok(low and high, "a plume when it pushes")
        T.eq(low.asset, "plume_s")
        T.eq(high.asset, "plume_l")
        T.ok(high.audio.gain > low.audio.gain, "louder when harder")
        T.ok(high.exhaust, "drawn at the nozzle")
    end,

    vacuum_swaps_the_plume_not_the_tier = function(T)
        local Fx = T.Core.get("presentation.fx")
        local a = find(Fx.activations(Fx.fromInstall("m1", { rp16() }, { c1 = { thrustN = 30000, throttle = 1 } }, { dev = {} }, { rho = 0 })), "plume.chemical")
        T.eq(a.asset, "plume_vac_l")
        T.eq(a.tier, 3)
    end,

    heat_shows_before_it_shuts_down = function(T)
        local Fx = T.Core.get("presentation.fx")
        local cool = Fx.activations(Fx.fromInstall("m1", { rp16() }, { c1 = { thrustN = 30000, throttle = 1, heatK = 100 } }, { dev = {} }, { rho = 1 }))
        local hot = Fx.activations(Fx.fromInstall("m1", { rp16() }, { c1 = { thrustN = 30000, throttle = 1, heatK = 440 } }, { dev = {} }, { rho = 1 }))
        T.eq(find(cool, "heat.shimmer"), nil)
        T.ok(find(hot, "heat.shimmer"), "shimmer above 80 % of the limit")
    end,

    the_hop_is_an_edge_and_kicks_dust_only_on_the_ground = function(T)
        local Fx = T.Core.get("presentation.fx")
        local ia = { componentId = "h1", kind = "pulse_reaction", pos = { 0, 0.1, 0.15 }, axis = { 0, 0, 1 },
            perf = { kind = "pulse_reaction", forceN = 53000, pulseS = 0.2, propellant = "fuel" } }
        local fired = { dev = { h1 = { sinceS = 0 } } }
        local quiet = { dev = { h1 = { sinceS = 0.5 } } }
        local g = Fx.activations(Fx.fromInstall("m1", { ia }, { h1 = { thrustN = 53000 } }, fired, { contact = true }))
        local air = Fx.activations(Fx.fromInstall("m1", { ia }, { h1 = { thrustN = 53000 } }, fired, { contact = false }))
        local none = Fx.activations(Fx.fromInstall("m1", { ia }, { h1 = { thrustN = 0 } }, quiet, { contact = true }))
        T.ok(find(g, "pulse.stroke") and find(g, "pulse.ground"), "stroke + dust on the ground")
        T.ok(find(air, "pulse.stroke") and not find(air, "pulse.ground"), "no dust in the air")
        T.eq(#none, 0, "nothing between strokes")
        T.ok(find(g, "pulse.stroke").edge, "a one-shot")
    end,

    deep_dynamics_feed_the_same_cues = function(T)
        local Fx = T.Core.get("presentation.fx")
        local m = { devices = { { key = "fd1", kind = "reaction_engine", at = { 0, 0.1, 0.15 }, dir = { 0, 0, 1 },
            perf = { kind = "reaction_engine", thrustN = 30000, ispS = 100000, propellant = "fusion" } } },
            attitude = { { key = "ac6", perf = { torqueNm = 4000 } } }, com = { 0, 0, 0.5 } }
        local s = { thr = { 0.8 }, dev = { { heatK = 0 } }, pulse = {}, rams = {} }
        local tel = { rho = 0, derate = 1, events = {}, attitudeNm = 2000 }
        local acts = Fx.activations(Fx.fromDynamics("m1", m, s, tel, {}))
        T.ok(find(acts, "plume.fusion"), "a fusion drive glows")
        T.eq(find(acts, "plume.chemical"), nil, "and is not a chemical plume")
        T.ok(find(acts, "rcs.puff"), "attitude work puffs")
    end,

    the_body_booms_once_through_mach_one_and_glows_coming_home = function(T)
        local Fx = T.Core.get("presentation.fx")
        local before = Fx.machine("m1", { speed = 330, rho = 1.0 })[1]
        local after = Fx.machine("m1", { speed = 350, rho = 1.0 }, before.q)
        T.ok(find(Fx.activations(after), "sonic.boom"), "boom on the crossing")
        T.eq(find(Fx.activations(Fx.machine("m1", { speed = 360, rho = 1.0 }, after[1].q)), "sonic.boom"), nil, "once")
        local entry = Fx.activations(Fx.machine("m1", { speed = 7000, rho = 0.001, aeroHeatKw = 5000 }))
        T.eq(find(entry, "entry.glow").asset, "entry_l")
    end,

    drives_have_their_own_cues = function(T)
        local Fx = T.Core.get("presentation.fx")
        local acts = Fx.activations(Fx.fromDrives("m1", {
            { drive = "jump", state = "CHARGING", charge = 0.7 },
            { drive = "alcubierre", state = "BUBBLE_FORMING", bubble = 0.4 },
            { drive = "wormhole", state = "OFF" } }))
        T.eq(find(acts, "jump.charge").asset, "charge_l")
        T.ok(find(acts, "bubble.form"))
        T.eq(find(acts, "wormhole.open"), nil, "an idle drive shows nothing")
    end,

    the_budget_keeps_room_for_one_shots_and_prefers_what_plays = function(T)
        local Fx = T.Core.get("presentation.fx")
        local acts = {}
        for i = 1, 40 do
            acts[#acts + 1] = { key = ("s%02d"):format(i), priority = 5, intensity = 1, edge = false }
        end
        for i = 1, 3 do acts[#acts + 1] = { key = ("e%d"):format(i), priority = 1, intensity = 1, edge = true } end
        local keep = Fx.select(acts, { s40 = true }, nil, 32)
        T.eq(#keep, 29, "26 sustained + 3 edges")
        local has = {}
        for _, a in ipairs(keep) do has[a.key] = true end
        T.ok(has.e1 and has.e2 and has.e3, "one-shots never wait behind plumes")
        T.ok(has.s40, "what is already playing keeps its slot")
    end,

    replication_round_trips_what_cues_read = function(T)
        local Fx = T.Core.get("presentation.fx")
        local em = Fx.fromInstall("m1", { rp16() }, { c1 = { thrustN = 20000, throttle = 0.7 } }, { dev = {} }, { rho = 1.1 })
        local back = Fx.unpack(Fx.pack(em))
        local a, b = Fx.activations(em), Fx.activations(back)
        T.eq(#a, #b)
        T.eq(find(a, "plume.chemical").asset, find(b, "plume.chemical").asset)
    end,
}
