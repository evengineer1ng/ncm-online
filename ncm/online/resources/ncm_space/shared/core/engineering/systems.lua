-- ncm-core module: engineering.systems
--
-- The physical vocabulary of Engineering II (L321; doc 54 §C, §D). A body (`engineering.body`) says what a thing IS;
-- its `perf` block says what it DOES physically, in SI units, as one of the kinds below. Every kind declares what it
-- consumes, what it produces, what it needs from the world (ground contact, atmosphere, propellant, energy) and what
-- heat it makes. No kind is a capability flag: a machine can hop, fly or maneuver in vacuum only because its assembled
-- systems physically can (`engineering.machine` derives it; `engineering.dynamics` integrates it).
--
--   THE FOUR WAYS TO PUSH (doc 54 §D -- "the hop is not a thruster"):
--     ground_ram        GROUND REACTION. Pushes against terrain. Needs contact. Spends stored energy once per stroke.
--     energy_store      STORED IMPULSE source: bounded energy charged earlier (battery, flywheel, pressure).
--     propeller / jet   ATMOSPHERIC REACTION. Thrust scales with air density; useless in vacuum.
--     reaction_engine   REACTION PROPULSION. Expels propellant; works in vacuum; stops when the tank is empty.
--   and what keeps it alive:
--     propellant_tank   reaction mass / fuel, by type
--     power_source      makes electrical power from fuel (or nothing, for a fixed solar/RTG-like source)
--     radiator          rejects heat: convective part scales with density, radiative part does not (vacuum differs)
--     aero_surface      lift/drag from area and coefficients; density-dependent
--     structure         rated load: forces past it are damage, not performance
local Core = NcmCore

Core.define("engineering.systems", function(C)
    local M = { version = "0.1.0" }

    M.G0 = 9.80665                -- standard gravity, for specific impulse
    M.RHO0 = 1.225                -- sea-level air density, kg/m^3

    --- kind -> { required = {field = "description (unit)"}, optional = {...}, push = mechanism or nil, needs = {...} }
    M.KINDS = {
        reaction_engine = {
            push = "reaction", needs = { "propellant" },
            required = { thrustN = "vacuum thrust (N)", ispS = "specific impulse (s)", propellant = "propellant type" },
            optional = { seaLevelFactor = "thrust at sea level / vacuum (0..1)", heatKw = "heat at full thrust (kW)",
                minThrottle = "lowest stable throttle (0..1)", throttleTauS = "throttle response time constant (s)" },
        },
        jet = {
            push = "atmospheric", needs = { "atmosphere", "propellant" },
            required = { thrustN = "sea-level thrust (N)", ispS = "effective specific impulse on fuel (s)", propellant = "fuel type" },
            optional = { heatKw = "heat at full thrust (kW)" },
        },
        propeller = {
            push = "atmospheric", needs = { "atmosphere", "energy" },
            required = { thrustN = "sea-level static thrust (N)", powerW = "shaft power at full thrust (W)" },
            optional = { heatKw = "heat at full thrust (kW)" },
        },
        -- L324: the Hella's hop as a physical thing. It fires in mid-air (the owner's repeated airborne hop), so it is
        -- NOT a ground ram: it expels reaction mass in one short stroke. One discharge = forceN for pulseS along the
        -- device's thrust axis, paid for in propellant at ispS. A reaction_engine is the sustained cousin.
        pulse_reaction = {
            push = "reaction", needs = { "propellant" },
            required = { forceN = "force during one discharge (N)", pulseS = "length of one discharge (s)",
                ispS = "specific impulse (s)", propellant = "propellant type" },
            optional = { rechargeS = "shortest time between discharges (s)", heatKj = "heat per discharge (kJ)" },
        },
        -- L331: ATTITUDE. A machine turns only if something on it makes torque. A cold-gas reaction-control set: pairs of
        -- small nozzles at `armM` from its centre fire against each other, so it makes torque about every axis and no
        -- net force; each newton-metre costs propellant at the nozzles' Isp (force = torque / arm). Mass, heat and its
        -- place on the car are real like any other part.
        attitude_control = {
            push = "reaction", needs = { "propellant" },
            required = { torqueNm = "torque about each axis at full command (N m)", armM = "nozzle lever arm (m)",
                ispS = "specific impulse of the cold gas (s)", propellant = "propellant type" },
            optional = { heatKw = "heat at full command (kW)" },
        },
        ground_ram = {
            push = "ground", needs = { "contact", "energy" },
            required = { energyJ = "energy one stroke can store (J)", forceN = "peak ram force (N)", strokeM = "stroke (m)" },
            optional = { chargeW = "recharge power drawn from the energy store (W)", heatKw = "heat per firing (kJ, as kW over 1 s)" },
        },
        energy_store = {
            required = { capacityJ = "usable energy (J)", maxPowerW = "peak discharge (W)" },
            optional = { rechargeW = "recharge from a power source (W)" },
        },
        propellant_tank = {
            required = { capacityKg = "propellant capacity (kg)", propellant = "propellant type" },
            optional = { fill = "initial fill (0..1)" },
        },
        power_source = {
            required = { outputW = "electrical output (W)" },
            optional = { propellant = "fuel it burns, if any", consumptionKgPerJ = "fuel per joule (kg/J)", heatKw = "waste heat (kW)" },
        },
        radiator = {
            required = { radiativeKw = "rejection independent of air (kW)" },
            optional = { convectiveKw = "extra rejection at sea-level air density (kW)" },
        },
        aero_surface = {
            needs = { "atmosphere" },
            required = { areaM2 = "reference area (m^2)", cl = "lift coefficient", cd = "drag coefficient" },
        },
        structure = {
            required = { ratedLoadN = "sustained load the structure carries (N)" },
            optional = { impactJ = "impact energy it survives (J)" },
        },
        -- L323 life support (doc 54 §S): a machine above breathable air keeps its crew alive only if it is SEALED and
        -- carries oxygen; a person outside one lives on the suit they wear (`life.breath`).
        pressure_cabin = {
            required = { crew = "seats inside the seal", volumeM3 = "pressurised volume (m^3)" },
            optional = { leakPerS = "fraction of cabin air lost per second" },
        },
        life_support = {
            required = { o2Kg = "breathable oxygen carried (kg)" },
            optional = { scrubKgPerS = "CO2 scrubbing capacity (kg/s)" },
        },
        eva_suit = {
            required = { o2Kg = "suit oxygen (kg)" },
            optional = { packThrustN = "EVA pack thrust (N)", packN2Kg = "EVA pack propellant (kg)", packIspS = "EVA pack Isp (s)" },
        },
    }

    --- L324: what a component of each kind can be TOLD to do. A command is the component's own input -- never a
    --- button and never a capability. `analog` commands take 0..1 and are held; `event` commands fire once.
    --- Controls bind to these (`engineering.controls`); nothing here knows which control, or why.
    M.COMMANDS = {
        reaction_engine = { throttle = { type = "analog", desc = "fraction of full thrust (0..1)" } },
        jet = { throttle = { type = "analog", desc = "fraction of full thrust (0..1)" } },
        propeller = { throttle = { type = "analog", desc = "fraction of full thrust (0..1)" } },
        pulse_reaction = { discharge = { type = "event", desc = "one stroke: forceN for pulseS" } },
        ground_ram = { discharge = { type = "event", desc = "one ram stroke against the ground" } },
    }
    function M.commands(kind) return M.COMMANDS[kind] or {} end

    --- Propellant spent by one discharge of a pulse device (kg): impulse / (Isp g0).
    function M.pulseMass(perf)
        local function n(v) return type(v) == "number" and v == v end
        if not perf or not n(perf.forceN) or not n(perf.pulseS) or not n(perf.ispS) or perf.ispS <= 0 then return 0 end
        return perf.forceN * perf.pulseS / (perf.ispS * M.G0)
    end

    --- Fields that name a thing rather than measure it.
    M.STRING_FIELDS = { propellant = true }

    local function num(v) return type(v) == "number" and v == v end

    --- Validate a body's `perf` against its kind. Returns true, or false + reasons. Unknown kinds are left alone
    --- (gearboxes, adapters ... belong to `engineering.drivetrain`).
    function M.validate(perf)
        if type(perf) ~= "table" or not M.KINDS[perf.kind] then return true end
        local k = M.KINDS[perf.kind]
        local errs = {}
        for field, desc in pairs(k.required) do
            local v = perf[field]
            if M.STRING_FIELDS[field] then
                if type(v) ~= "string" or v == "" then errs[#errs + 1] = perf.kind .. "." .. field .. " is required (" .. desc .. ")" end
            elseif not num(v) or v < 0 then
                errs[#errs + 1] = perf.kind .. "." .. field .. " must be a number >= 0 (" .. desc .. ")"
            end
        end
        if perf.ispS ~= nil and num(perf.ispS) and perf.ispS <= 0 then errs[#errs + 1] = "ispS must be > 0" end
        if perf.seaLevelFactor ~= nil and (not num(perf.seaLevelFactor) or perf.seaLevelFactor < 0 or perf.seaLevelFactor > 1) then
            errs[#errs + 1] = "seaLevelFactor is 0..1"
        end
        if perf.fill ~= nil and (not num(perf.fill) or perf.fill < 0 or perf.fill > 1) then errs[#errs + 1] = "fill is 0..1" end
        if #errs > 0 then return false, errs end
        return true
    end

    --- Mass flow at full thrust for a propellant-burning device (kg/s): F / (Isp g0).
    function M.massFlow(perf)
        if not perf or not num(perf.thrustN) or not num(perf.ispS) or perf.ispS <= 0 then return 0 end
        return perf.thrustN / (perf.ispS * M.G0)
    end

    --- Thrust available from a pushing device at air density `rho` (kg/m^3) and throttle t (0..1), before derating.
    function M.thrustAt(perf, rho, t)
        t = t or 1
        rho = rho or 0
        local f = rho / M.RHO0
        if perf.kind == "reaction_engine" then
            local sl = perf.seaLevelFactor or 1
            -- vacuum thrust, reduced toward the sea-level factor as the air thickens
            return perf.thrustN * t * (1 - (1 - sl) * math.min(1, f))
        elseif perf.kind == "jet" or perf.kind == "propeller" then
            return perf.thrustN * t * f
        end
        return 0
    end

    --- Heat rejected by a radiator at density rho (kW).
    function M.rejectionKw(perf, rho)
        if not perf or perf.kind ~= "radiator" then return 0 end
        return (perf.radiativeKw or 0) + (perf.convectiveKw or 0) * math.min(1, (rho or 0) / M.RHO0)
    end

    function M.pushMechanism(kind) return M.KINDS[kind] and M.KINDS[kind].push or nil end

    return M
end)
