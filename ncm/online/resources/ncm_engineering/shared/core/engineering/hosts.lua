-- ncm-core module: engineering.hosts
--
-- The cross-runtime physics contract (L321; doc 54 §H). NCM's machine physics is canonical: `engineering.dynamics`
-- says what force, torque and velocity a machine really has. A HOST engine only EXPRESSES that truth through the
-- channels it has, and every place it cannot is an EXPRESSION LOSS -- listed beside the commands, never folded back
-- into the truth (a GTA car capped at 150 m/s does not make the NCM machine slower; the frame keeps its real speed).
--
-- Each host declares what it can do and what was MEASURED about its limits (with the experiment that measured it).
-- Unmeasured limits are `nil` and say so: "unknown" is a fact here, not a default.
local Core = NcmCore

Core.define("engineering.hosts", function(C)
    local M = { version = "0.1.0" }
    local Act = C.get("engineering.actuate")

    M.HOSTS = {
        redengine = {
            id = "redengine", runtime = "Cyberpunk 2077 / OPEN//77", via = "NCM Carrier + NCM Thrust (RED4ext)",
            channels = {
                recordMass = true,          -- Carrier writes the drive model's total_mass (L314, §AX)
                liftLever = true,           -- the gravity-entry lift lever: thrust-to-weight along the car's up
                driveBrakeGripScale = true,
                torque = false,             -- no channel applies a moment: attitude is not expressible yet
                lateralForce = false,
                setVelocity = false,
            },
            limits = {
                worldZ = { value = 16384, source = "§AX4 hard ceiling (2^14); Snowglobe 0 seam above it" },
                speedMs = { value = 99.70, source = "KB-342 measured cap" },
                serverMove = { value = "velocity zeroed, lease revoked ~3 s", source = "§SG seam tests" },
                liftTwr = { value = Act.LIFT_MAX_TWR, source = "engineering.actuate.LIFT_MAX_TWR" },
            },
        },
        rage = {
            id = "rage", runtime = "GTA V Legacy / FiveM", via = "ncm_ls_space (natives only; no ScriptHook, ASI or offsets)",
            channels = {
                recordMass = false,         -- handling mass is readable, not a safe per-entity write
                liftLever = false,
                driveBrakeGripScale = false,
                torque = true,              -- APPLY_FORCE_TO_ENTITY at an offset: a couple is a pure torque
                lateralForce = true,
                setVelocity = true,         -- SET_ENTITY_VELOCITY, used by the Snowglobe frame
                gravityPresets = true,      -- SET_GRAVITY_LEVEL 0-3 only: inverse-square is NCM's integration
            },
            limits = {
                speedMs = { value = 150, source = "§LS2: 146.7 m/s peak; SET_ENTITY_MAX_SPEED does not lift it" },
                presentMs = { value = 140, source = "ncm_ls_space config.presentCap (margin under the cap)" },
                serverMove = { value = "driver, ownership and velocity kept", source = "§LS4 flight 1" },
                worldZ = { value = nil, source = "unknown: not yet measured (GTS_RECON_01 unknown #1)" },
            },
        },
    }

    local function len(v) return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]) end

    --- Express a machine's truth on a host.
    ---   truth = { massKg, forceN = body-frame force {x,y,z}, torqueNm = body {x,y,z}, velMs = {x,y,z} (universe),
    ---             localZ = metres in the host's world, g = 9.81 }
    --- Returns { commands = { ... }, losses = { { quantity, truth, expressed, why } } }.
    function M.express(hostId, truth)
        local h = assert(M.HOSTS[hostId], "hosts: unknown host " .. tostring(hostId))
        local cmd, losses = {}, {}
        local function lose(q, t, e, why) losses[#losses + 1] = { quantity = q, truth = t, expressed = e, why = why } end
        local F, tau = truth.forceN or { 0, 0, 0 }, truth.torqueNm or { 0, 0, 0 }
        local g = truth.g or 9.81
        local speed = truth.velMs and len(truth.velMs) or 0

        if hostId == "redengine" then
            if truth.massKg then cmd.recordMassKg = truth.massKg end
            local twr = (truth.massKg and truth.massKg > 0) and F[3] / (truth.massKg * g) or 0
            local lever = math.max(0, math.min(h.limits.liftTwr.value, twr))
            cmd.liftTwr = lever
            if twr ~= lever then lose("lift", twr, lever, "the lift lever carries 0.." .. h.limits.liftTwr.value .. " thrust-to-weight along up") end
            if math.abs(F[1]) + math.abs(F[2]) > 0 then lose("lateral force", { F[1], F[2] }, { 0, 0 }, "no lateral force channel in Carrier") end
            if len(tau) > 0 then lose("torque", tau, { 0, 0, 0 }, "no torque channel: attitude is not expressible") end
            if speed > h.limits.speedMs.value then lose("speed", speed, h.limits.speedMs.value, h.limits.speedMs.source) end
            if truth.localZ and truth.localZ > h.limits.worldZ.value then
                lose("position", truth.localZ, h.limits.worldZ.value, "above the ceiling: only the Snowglobe seam expresses it")
            end
        elseif hostId == "rage" then
            cmd.force = { F[1], F[2], F[3] }
            -- a pure torque as a couple of equal, opposite forces 2 * arm apart (what ncm_ls_space applies)
            local arm = truth.coupleArmM or 1.6
            cmd.couples = { { axis = "x", forceN = tau[1] / (2 * arm), armM = arm },
                            { axis = "y", forceN = tau[2] / (2 * arm), armM = arm },
                            { axis = "z", forceN = tau[3] / (2 * arm), armM = arm } }
            if truth.velMs then
                local cap = h.limits.presentMs.value
                local k = speed > cap and cap / speed or 1
                cmd.setVelocity = { truth.velMs[1] * k, truth.velMs[2] * k, truth.velMs[3] * k }
                if k < 1 then lose("speed", speed, cap, "presented under the RAGE entity cap; the NCM frame keeps the real speed") end
                -- the frame owns the body: GTA gravity is switched off and NCM's inverse-square is in the velocity
                cmd.gravity = "off"
                lose("gravity model", "inverse-square radial", "GTA gravity off + velocity", "SET_GRAVITY_LEVEL has presets only")
            end
        end
        return { host = hostId, commands = cmd, losses = losses }
    end

    return M
end)
