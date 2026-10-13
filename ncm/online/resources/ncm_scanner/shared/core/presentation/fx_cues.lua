-- ncm-core module: presentation.fx_cues
--
-- NCM FX's DATA (`presentation.fx` reads it; hosts draw it). Three tables:
--
--   CUES    what each physical situation shows and sounds like. A cue matches emitters (`on`), may require quantities
--           (`require`), reads ONE driving quantity (`drive`) into a tier, and names per tier the native effect ASSET
--           to draw (optionally per propellant, and a vacuum variant). Sustained cues hold while their condition
--           holds; `edge` cues fire once on that step's event. `exhaust = true`: draw at the nozzle, pointing out of it.
--           `audio`: a VOICE whose pitch and gain map from quantities (`{ q, from = {a, b}, to = {lo, hi} }`).
--   ASSETS  asset key -> the game's cooked `.effect` path (`Open77.vfx.play` takes a depot path as readily as an
--           alias), `orient` (the effect's authored forward: "y" or "z"), `seen` -- set true only after the effect was
--           looked at in game, the platform's own rule for raw paths (open77_admin config: "not individually validated").
--   VOICES  voice key -> the NCM Audio pack file (looping or one-shot) and, where one fits, a vanilla sound event.
--
-- Balance and look are data: changing a threshold or swapping an asset is one edit here, no code.
local Core = NcmCore

Core.define("presentation.fx_cues", function(C)
    local M = { version = "0.1.0" }

    local CHEM = { fuel = true, kerosene = true, methalox = true, hydrazine = true }

    M.CUES = {
        -- ----------------------------------------------------------------------------- sustained propulsion
        { id = "plume.chemical", on = { kind = "propulsor", sub = { reaction_engine = true }, propellant = CHEM },
          require = { throttle = { gt = 0.02 } }, drive = "thrustN", exhaust = true, priority = 8,
          tiers = {
              { at = 0, asset = "plume_s", vacuum = "plume_vac_s" },
              { at = 8000, asset = "plume_m", vacuum = "plume_vac_m" },
              { at = 25000, asset = "plume_l", vacuum = "plume_vac_l" },
          },
          audio = { voice = "rocket_roar", pitch = { q = "exhaustV", from = { 1500, 4500 }, to = { 0.75, 1.25 } },
                    gain = { q = "frac", from = { 0, 1 }, to = { 0.15, 1.0 } } } },
        { id = "plume.fusion", on = { kind = "propulsor", sub = { reaction_engine = true }, propellant = { fusion = true } },
          require = { throttle = { gt = 0.02 } }, drive = "thrustN", exhaust = true, priority = 9,
          tiers = { { at = 0, asset = "fusion_s" }, { at = 15000, asset = "fusion_l" } },
          audio = { voice = "fusion_hum", pitch = { q = "frac", from = { 0, 1 }, to = { 0.8, 1.2 } },
                    gain = { q = "frac", from = { 0, 1 }, to = { 0.3, 1.0 } } } },
        { id = "plume.jet", on = { kind = "propulsor", sub = { jet = true } },
          require = { throttle = { gt = 0.02 } }, drive = "thrustN", exhaust = true, priority = 7,
          -- 2026-10-12 (owner, first AV flight: "too much fx"): an AV pod's lift fan (28 kN) is the small thruster; the
          -- big one is for a jet past 40 kN
          tiers = { { at = 0, asset = "jet_s" }, { at = 40000, asset = "jet_l" } },
          audio = { voice = "jet_whine", pitch = { q = "throttle", from = { 0, 1 }, to = { 0.7, 1.4 } },
                    gain = { q = "frac", from = { 0, 1 }, to = { 0.2, 1.0 } } } },
        { id = "fan.wash", on = { kind = "propulsor", sub = { propeller = true } },
          require = { throttle = { gt = 0.05 } }, drive = "thrustN", exhaust = true, priority = 4,
          tiers = { { at = 0, asset = "fan_wash" } },
          audio = { voice = "fan", pitch = { q = "throttle", from = { 0, 1 }, to = { 0.6, 1.3 } },
                    gain = { q = "throttle", from = { 0, 1 }, to = { 0.1, 0.8 } } } },
        { id = "heat.shimmer", on = { kind = "propulsor" }, require = { heatFrac = { gt = 0.8 } }, drive = "heatFrac",
          priority = 3, tiers = { { at = 0.8, asset = "heat_shimmer" }, { at = 1.0, asset = "heat_smoke" } } },
        { id = "starved.cough", on = { kind = "propulsor" }, require = { starved = true }, drive = "throttle",
          priority = 2, tiers = { { at = 0, asset = "cough" } }, audio = { voice = "sputter" } },

        -- ----------------------------------------------------------------------------- strokes and the hop
        { id = "pulse.stroke", on = { kind = "pulse" }, edge = "fired", drive = "forceN", exhaust = true, priority = 9,
          tiers = { { at = 0, asset = "pulse_s" }, { at = 40000, asset = "pulse_l" } },
          audio = { voice = "pulse_thump", oneShot = true, pitch = { q = "forceN", from = { 10000, 80000 }, to = { 1.2, 0.8 } } } },
        { id = "pulse.ground", on = { kind = "pulse" }, edge = "fired", require = { contact = true }, drive = "forceN",
          priority = 6, tiers = { { at = 0, asset = "ground_dust" } } },
        { id = "ram.burst", on = { kind = "ram" }, edge = "fired", drive = "energyJ", priority = 9,
          tiers = { { at = 0, asset = "ram_s" }, { at = 20000, asset = "ram_l" } },
          audio = { voice = "ram_thump", oneShot = true, gain = { q = "energyJ", from = { 2000, 60000 }, to = { 0.5, 1.0 } } } },
        { id = "ram.dust", on = { kind = "ram" }, edge = "fired", drive = "energyJ", priority = 6,
          tiers = { { at = 0, asset = "ground_dust" } } },
        { id = "ram.dry", on = { kind = "ram" }, edge = "dry", priority = 2, audio = { voice = "click", oneShot = true } },
        -- KB-470: hard manoeuvres only -- at 5 % the AC-6 puffed steam on every small correction of a hover
        { id = "rcs.puff", on = { kind = "attitude" }, require = { frac = { gt = 0.5 } }, drive = "frac", priority = 4,
          tiers = { { at = 0.5, asset = "rcs_puff" } },
          audio = { voice = "cold_gas", gain = { q = "frac", from = { 0, 1 }, to = { 0.2, 0.9 } } } },

        -- ----------------------------------------------------------------------------- the body in the air
        { id = "entry.glow", on = { kind = "machine" }, require = { heatKw = { gt = 40 } }, drive = "heatKw", priority = 8,
          tiers = { { at = 40, asset = "entry_s" }, { at = 400, asset = "entry_m" }, { at = 3000, asset = "entry_l" } },
          screen = { at = 3000, alias = "heat" },
          audio = { voice = "entry_roar", gain = { q = "qPa", from = { 2000, 60000 }, to = { 0.2, 1.0 } },
                    pitch = { q = "heatKw", from = { 40, 3000 }, to = { 0.8, 1.2 } } } },
        { id = "wind.rush", on = { kind = "machine" }, require = { qPa = { gt = 3000 } }, drive = "qPa", priority = 1,
          audio = { voice = "wind", gain = { q = "qPa", from = { 3000, 40000 }, to = { 0.1, 0.8 } },
                    pitch = { q = "speed", from = { 80, 600 }, to = { 0.8, 1.3 } } } },
        { id = "sonic.boom", on = { kind = "machine" }, edge = "boom", priority = 9,
          tiers = { { at = 0, asset = "boom" } }, drive = "mach", fov = { kick = 6, ms = 250 },
          audio = { voice = "boom", oneShot = true } },
        { id = "impact", on = { kind = "machine" }, edge = "impact", drive = "impactJ", priority = 9,
          tiers = { { at = 0, asset = "impact_s" }, { at = 50000, asset = "impact_l" } },
          audio = { voice = "impact", oneShot = true, gain = { q = "impactJ", from = { 2000, 200000 }, to = { 0.4, 1.0 } } } },

        -- ----------------------------------------------------------------------------- the drives (doc 61)
        { id = "warp.spool", on = { kind = "drive", sub = { warp = true }, state = { SPOOLING = true } }, drive = "spool",
          priority = 7, tiers = { { at = 0.1, asset = "warp_in" } },
          audio = { voice = "drive_rise", pitch = { q = "spool", from = { 0, 1 }, to = { 0.6, 1.6 } } } },
        { id = "warp.field", on = { kind = "drive", sub = { warp = true }, state = { ENGAGED = true } }, drive = "spool",
          priority = 7, tiers = { { at = 0, asset = "field_arc" } }, audio = { voice = "drive_field" } },
        { id = "bubble.form", on = { kind = "drive", sub = { alcubierre = true }, state = { BUBBLE_FORMING = true } },
          drive = "bubble", priority = 8, tiers = { { at = 0, asset = "bubble_form" } },
          audio = { voice = "drive_rise", pitch = { q = "bubble", from = { 0, 1 }, to = { 0.5, 1.2 } } } },
        { id = "bubble.hold", on = { kind = "drive", sub = { alcubierre = true }, state = { BUBBLE_STABLE = true, ENGAGED = true } },
          drive = "bubble", priority = 7, tiers = { { at = 0, asset = "field_arc" } }, audio = { voice = "drive_field" } },
        { id = "jump.charge", on = { kind = "drive", sub = { jump = true }, state = { CHARGING = true } }, drive = "charge",
          priority = 8, tiers = { { at = 0, asset = "charge_s" }, { at = 0.6, asset = "charge_l" } },
          audio = { voice = "drive_rise", pitch = { q = "charge", from = { 0, 1 }, to = { 0.5, 2.0 } } } },
        { id = "jump.fire", on = { kind = "drive", sub = { jump = true }, state = { ENGAGED = true } }, drive = "charge",
          priority = 9, tiers = { { at = 0, asset = "jump_out" } }, fov = { kick = -20, ms = 300 } },
        { id = "wormhole.open", on = { kind = "drive", sub = { wormhole = true }, state = { WORMHOLE_OPEN = true, ENGAGED = true } },
          drive = "progress", priority = 9, tiers = { { at = 0, asset = "mouth" } }, audio = { voice = "mouth_hum" } },
    }

    -- Candidates from the game's 3,426 cooked effects (WolvenKit listing, 2026-10-12). `seen = false` until looked at in
    -- game; a host may prefer a seen asset of the same role. `orient`: the axis the effect is authored to emit along --
    -- "-z" for thrusters (an AV's thrusters fire down; first flight 2026-10-12: drawn as +z, the FD-1's plume went up
    -- through the cabin), "z" for bursts that rise. The q112 parade-barge thruster was a pillar the size of a building:
    -- not used.
    M.ASSETS = {
        plume_s      = { effect = "base\\fx\\quest\\q000\\q000_cargo_av_thruster.effect", orient = "-z", seen = false },
        plume_m      = { effect = "base\\fx\\quest\\q104\\q104_av_thrusters.effect", orient = "-z", seen = false },
        plume_l      = { effect = "base\\fx\\quest\\q000\\q000_cargo_av_main_engine.effect", orient = "-z", seen = false },
        plume_vac_s  = { effect = "base\\fx\\quest\\q000\\q000_cargo_av_thruster.effect", orient = "-z", seen = false },
        plume_vac_m  = { effect = "base\\fx\\quest\\q104\\q104_av_thrusters.effect", orient = "-z", seen = false },
        plume_vac_l  = { effect = "base\\fx\\quest\\q104\\q104_rocket_trail.effect", orient = "-z", seen = false },
        fusion_s     = { effect = "base\\fx\\quest\\q000\\q000_cargo_av_thruster.effect", orient = "-z", seen = false },
        fusion_l     = { effect = "base\\fx\\quest\\q104\\q104_av_thrusters.effect", orient = "-z", seen = false },
        -- KB-470 (owner: "the vfx are obnoxiously overwhelming"): the Trauma Team Atlus's own authored thruster (its
        -- entity's `thrusters` event, on engine-bone slots with no rotation: it fires down -Z like the q000 one), not the
        -- prologue cargo AV's -- four of those burned at hover the whole flight
        jet_s        = { effect = "base\\fx\\vehicles\\av\\v_av_trauma_team_thruster.effect", orient = "-z", seen = false },
        jet_l        = { effect = "base\\fx\\quest\\q104\\q104_av_thrusters.effect", orient = "-z", seen = false },
        fan_wash     = { effect = "weather.dust", orient = "z", seen = false },
        heat_shimmer = { effect = "base\\fx\\quest\\q112\\q112_10_safe_house\\e_steam_jet_hot_small_q112.effect", orient = "-z", seen = false },
        heat_smoke   = { effect = "smoke.machine", orient = "z", seen = false },
        cough        = { effect = "sparks.burst.small", orient = "z", seen = false },
        pulse_s      = { effect = "base\\fx\\devices\\boot_thrusters\\d_boot_thruster_burst.effect", orient = "-z", seen = false },
        pulse_l      = { effect = "base\\fx\\devices\\boot_thrusters\\d_boot_thruster_holo_jump.effect", orient = "-z", seen = false },
        ground_dust  = { effect = "base\\fx\\environment\\debris\\av_landing_debris_and_dust.effect", orient = "z", seen = false },
        ram_s        = { effect = "impact.ground_slam", orient = "z", seen = false },
        ram_l        = { effect = "base\\fx\\gameplay\\player\\landing_very_hard.effect", orient = "z", seen = false },
        rcs_puff     = { effect = "base\\fx\\quest\\q112\\q112_10_safe_house\\e_steam_jet_hot_small_q112.effect", orient = "-z", seen = false },
        entry_s      = { effect = "fire.small", orient = "z", seen = false },
        entry_m      = { effect = "vehicle.fire", orient = "z", seen = false },
        entry_l      = { effect = "fire.large", orient = "z", seen = false },
        boom         = { effect = "explosion.steam", orient = "z", seen = false },
        impact_s     = { effect = "impact.metal", orient = "z", seen = false },
        impact_l     = { effect = "sparks.burst.large", orient = "z", seen = false },
        warp_in      = { effect = "base\\fx\\meshes\\cyberparticles\\cyberparticles_warp_in.effect", orient = "z", seen = false },
        field_arc    = { effect = "electric.arc", orient = "z", seen = false },
        bubble_form  = { effect = "base\\fx\\vehicles\\_crystal_dome\\v_crystal_dome_start_long.effect", orient = "z", seen = false },
        charge_s     = { effect = "electric.emp.small", orient = "z", seen = false },
        charge_l     = { effect = "electric.emp.big", orient = "z", seen = false },
        jump_out     = { effect = "base\\fx\\meshes\\cyberparticles\\cyberparticles_warp_out.effect", orient = "z", seen = false },
        mouth        = { effect = "base\\fx\\characters\\npc\\cyberspace_teleport\\ch_cyberspace_teleport_medium.effect", orient = "z", seen = false },
    }

    -- NCM Audio pack files (ncm/audio/pack, rendered by ncm/audio/tools/render_pack.py); `event`: a vanilla stand-in when
    -- the pack is not installed (no pitch or gain: the engine event carries neither).
    M.VOICES = {
        rocket_roar = { file = "rocket_roar.wav", loop = true },
        fusion_hum  = { file = "fusion_hum.wav", loop = true },
        jet_whine   = { file = "jet_whine.wav", loop = true },
        fan         = { file = "fan.wav", loop = true },
        sputter     = { file = "sputter.wav", loop = true },
        pulse_thump = { file = "pulse_thump.wav", loop = false },
        ram_thump   = { file = "ram_thump.wav", loop = false },
        click       = { file = "click.wav", loop = false },
        cold_gas    = { file = "cold_gas.wav", loop = true },
        entry_roar  = { file = "entry_roar.wav", loop = true },
        wind        = { file = "wind.wav", loop = true },
        boom        = { file = "boom.wav", loop = false },
        impact      = { file = "impact.wav", loop = false },
        drive_rise  = { file = "drive_rise.wav", loop = true },
        drive_field = { file = "drive_field.wav", loop = true },
        mouth_hum   = { file = "mouth_hum.wav", loop = true },
    }

    --- Every asset and voice a cue names exists (the load-time check the tests also run).
    function M.validate()
        local bad = {}
        for _, c in ipairs(M.CUES) do
            for _, t in ipairs(c.tiers or {}) do
                for _, k in ipairs({ t.asset, t.vacuum }) do
                    if k and not M.ASSETS[k] then bad[#bad + 1] = c.id .. ": asset " .. k end
                end
                for _, k in pairs(t.byPropellant or {}) do
                    if not M.ASSETS[k] then bad[#bad + 1] = c.id .. ": asset " .. k end
                end
            end
            if c.audio and not M.VOICES[c.audio.voice] then bad[#bad + 1] = c.id .. ": voice " .. tostring(c.audio.voice) end
        end
        return #bad == 0, bad
    end

    return M
end)
