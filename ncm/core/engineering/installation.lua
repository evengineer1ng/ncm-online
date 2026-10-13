-- ncm-core module: engineering.installation
--
-- L324: a physical component on a physical Machine. The first playable engineering loop:
--
--   component asset -> compatible (or not) with a mount -> installed at a POSITION with a FACING -> fed from the
--   Machine's own resources -> told what to do through its COMMANDS -> its output is a force in the Machine frame
--   -> the host turns that into a world-space force on the rigid body.
--
-- Nothing here knows the word "flight". A propulsor pushes along its installed thrust axis because that is what it
-- physically does; mounted at the rear facing aft it drives the Machine forward, under the floor facing down it lifts
-- it, on the roof facing left it shoves it sideways. Whatever that turns out to be useful for is the player's
-- discovery, not this file's (doc 54 §D, the L324 brief: "the component does not know its purpose").
--
-- Machine frame (as engineering.machine): x right, y forward, z up, metres, origin at the chassis reference point.
--
-- FACING is where the business end points -- the nozzle, the stroke face. The force on the Machine is the reaction,
-- so the THRUST AXIS is -facing. Stored per installation (machine_configuration_item.install_json), never inferred.
--
-- MOUNTS are discrete hardpoints for now (rear, underside, roof, front). Each carries a position, the facings the
-- body of the car leaves open, and a structural rating. Named mounts are a stand-in for geometry, not a replacement
-- for it: a later pass can make the position free without changing anything that reads `pos` and `axis`.
local Core = NcmCore

Core.define("engineering.installation", function(C)
    local M = { version = "0.1.0" }
    local Sys = C.get("engineering.systems")
    local Vehicles = C.get("data.vehicle_catalogue")

    M.FACINGS = {
        aft = { 0, -1, 0 }, fore = { 0, 1, 0 }, down = { 0, 0, -1 }, up = { 0, 0, 1 },
        left = { -1, 0, 0 }, right = { 1, 0, 0 },
    }
    M.FACING_ORDER = { "aft", "fore", "down", "up", "left", "right" }

    --- The hardpoint standard every v1 mount and v1 add-on component shares. A future standard is a new string.
    M.STANDARD = "hardpoint.h1"

    --- Generic hardpoints for a road car (the Hella is ~4.6 m long). `blocked` facings would fire into the car's
    --- own body. `ratedN` is the sustained force the mount's structure takes; past it the fit is refused.
    M.MOUNTS = {
        { id = "mount.rear",      label = "rear bumper hardpoint", pos = { 0, -2.2, 0.55 }, ratedN = 30000, blocked = { fore = true } },
        -- L360 addendum (owner, 2026-10-10: "put the underside mount on the centre of mass"): the floor-pan hardpoint is
        -- CENTRED -- whatever is installed on it sits directly under the assembled Machine's balance point (tanks, parts
        -- and fill included; engineering.machine), so a drive pushing straight up from it never pitches the Machine.
        -- `pos` keeps its height; its x/y are the nominal place for hosts that do not assemble a Machine.
        { id = "mount.underside", label = "floor-pan hardpoint",   pos = { 0, 0.1, 0.15 },  ratedN = 60000, blocked = { up = true }, centred = true },
        { id = "mount.roof",      label = "roof hardpoint",        pos = { 0, -0.3, 1.45 }, ratedN = 20000, blocked = { down = true } },
        { id = "mount.front",     label = "front bumper hardpoint", pos = { 0, 2.2, 0.55 }, ratedN = 30000, blocked = { aft = true } },
        -- Stacked gearboxes (owner, 2026-10-08: "it needs to be emergent"). Where a box sits in the driveline IS its
        -- arrangement: INLINE boxes follow the car's own box in series (inline.1 first, then inline.2); a SIDE box is a
        -- separate path the driver engages through a bound control (engineering.gearing). A driveline box points the
        -- way the driveline runs, so it is installed facing fore (input toward the engine).
        { id = "mount.driveline.inline.1", label = "driveline, inline after the car's own box", pos = { 0, 0.9, 0.35 }, ratedN = 1e9, driveline = "inline", order = 1 },
        { id = "mount.driveline.inline.2", label = "driveline, inline second",                  pos = { 0, 0.5, 0.35 }, ratedN = 1e9, driveline = "inline", order = 2 },
        { id = "mount.driveline.side.1",   label = "driveline, side path A",                    pos = { 0.3, 0.7, 0.35 }, ratedN = 1e9, driveline = "side", order = 1 },
        { id = "mount.driveline.side.2",   label = "driveline, side path B",                    pos = { -0.3, 0.7, 0.35 }, ratedN = 1e9, driveline = "side", order = 2 },
        -- L356: aero-electronics. Every road car has room behind the dash for a unit; it pushes nothing, so the bay's
        -- rating is irrelevant. It takes electronics only, and electronics go nowhere else.
        { id = "mount.electronics", label = "electronics bay, behind the dash", pos = { 0, 0.8, 0.7 }, ratedN = 1e9, electronics = true },
        -- 2026-10-12 (owner: "aren't we using our engineering parts"): the Zetatech Atlus AV's four ENGINE PODS. Only an
        -- airframe built for them has them (`vehicles`). Positions are the pod nozzles' places on the Atlus body (the
        -- `av_zetatech_atlus__ext01_engines_*` meshes, as the Drive an Aerial Vehicle mod measured them), Machine frame.
        { id = "mount.av.pod.fl", label = "front-left engine pod", pos = { -1.55, 2.2, 1.2 },   ratedN = 60000, blocked = { up = true }, vehicles = { zetatech_atlus_trauma = true } },
        { id = "mount.av.pod.fr", label = "front-right engine pod", pos = { 1.55, 2.2, 1.2 },   ratedN = 60000, blocked = { up = true }, vehicles = { zetatech_atlus_trauma = true } },
        { id = "mount.av.pod.rl", label = "rear-left engine pod", pos = { -1.45, -2.75, 1.0 },  ratedN = 60000, blocked = { up = true }, vehicles = { zetatech_atlus_trauma = true } },
        { id = "mount.av.pod.rr", label = "rear-right engine pod", pos = { 1.45, -2.75, 1.0 },  ratedN = 60000, blocked = { up = true }, vehicles = { zetatech_atlus_trauma = true } },
        -- 2026-10-13 (owner: "we need some fusion drives designed specifically for hauling a trauma team vehicle up"):
        -- two BELLY mounts on the centre line, 2.0 m either side of the balance point (com y -0.27), for the FL-6 lift drives
        { id = "mount.av.belly.f", label = "forward belly lift mount", pos = { 0, 1.73, 0.3 },  ratedN = 80000, blocked = { up = true }, vehicles = { zetatech_atlus_trauma = true } },
        { id = "mount.av.belly.r", label = "aft belly lift mount",     pos = { 0, -2.27, 0.3 }, ratedN = 80000, blocked = { up = true }, vehicles = { zetatech_atlus_trauma = true } },
        -- the cabin's equipment bay, on the centre line over the balance point (a tank or a drive rides here)
        { id = "mount.av.bay", label = "cabin equipment bay", pos = { 0, -0.3, 0.9 }, ratedN = 60000, blocked = { up = true, down = true }, vehicles = { zetatech_atlus_trauma = true } },
    }
    for _, m in ipairs(M.MOUNTS) do m.blocked = m.blocked or {} end
    local mountById = {}
    for _, m in ipairs(M.MOUNTS) do mountById[m.id] = m end
    function M.mount(id) return mountById[id] end
    function M.isMount(interfaceId) return mountById[interfaceId] ~= nil end

    --- Families that install on a mount (add-ons), as opposed to the effect-scalar families that replace a
    --- factory component at a fixed interface (parts.catalogue). Handling composition must never see these.
    M.FAMILIES = { propulsor = true, impulse_actuator = true, attitude = true, tank = true, gearbox = true, slipstream = true,
        exotic_drive = true,    -- doc 58: the lab-only experimental drives
        avionics = true }       -- 2026-10-12: the AV's flight computer
    function M.isAddOnFamily(family) return M.FAMILIES[family] == true end

    --- Driveline kinds (engineering.drivetrain's vocabulary): they change ratios, never push. NCM Gearbox drives them.
    M.DRIVELINE_KINDS = { gearbox = true, range = true }
    function M.isDriveline(kind) return M.DRIVELINE_KINDS[kind] == true end

    --- Electronic kinds (L356): they sense and decide, never push. Installed in the electronics bay, facing fore.
    M.ELECTRONIC_KINDS = { wake_system = true, flight_computer = true }
    function M.isElectronic(kind) return M.ELECTRONIC_KINDS[kind] == true end

    -- ------------------------------------------------------------------------------------------ designs
    --- The first two physical components. Revision 1 of each lineage. Numbers are physical (SI) and are the
    --- balance: a heavier Machine gets less out of the same thrust, and that is the point.
    M.DESIGNS = {
        {
            designId = "eng:zetatech:rp16:r1", lineageId = "eng:zetatech:rp16", revision = 1,
            manufacturer = "Zetatech", makerKey = "zetatech", code = "ZTC-RP16", family = "propulsor",
            name = "Reaction Propulsor RP-16",
            subtitle = "Sustained reaction thrust along its installed axis. Burns the Machine's own fuel.",
            interface = "hardpoint.h1", massKg = 85, envelope = { 0.5, 1.1, 0.5 }, price = 6500,
            -- owner, 2026-10-06: 16 kN (< 1 g on the Hella) "weakened the crap out of" forward push. 30 kN = the rear
            -- hardpoint's rating, ~1.7 g on the 1.8 t body. Same design id: dev balance, not a new revision.
            -- L342: fuelled reaction hardware obeys the world's 360 s chemistry ceiling. The earlier 2000 s
            -- development balance is retired; dev fuel remains an explicit development waiver.
            perf = { kind = "reaction_engine", thrustN = 30000, ispS = 360, propellant = "fuel", seaLevelFactor = 1.0,
                throttleTauS = 0.25, minThrottle = 0, heatKw = 600 },
            thermal = { capacityKjK = 40, rejectKw = 200, limitK = 450, resumeK = 300 },
        },
        {
            designId = "eng:archer:ia10:r1", lineageId = "eng:archer:ia10", revision = 1,
            manufacturer = "Archer", makerKey = "archer", code = "ARC-IA10", family = "impulse_actuator",
            name = "Impulse Actuator IA-10",
            subtitle = "One short reaction stroke per discharge. Works in the air. Burns the Machine's own fuel.",
            interface = "hardpoint.h1", massKg = 40, envelope = { 0.6, 0.6, 0.25 }, price = 3200,
            -- matches the hop the owner already flies (NCM Thrust twr 3.0 x 200 ms on the 1,800 kg Hella body)
            -- rechargeS 0 + `retrigger`: every press starts a fresh stroke even mid-stroke, like NCM Thrust's hop ("interrupted
            -- by the next burn"); owner: waiting out each stroke made the hop "take insane mashing" (3/s measured vs ~8/s).
            perf = { kind = "pulse_reaction", forceN = 53000, pulseS = 0.2, ispS = 360, propellant = "fuel", rechargeS = 0,
                retrigger = true, heatKj = 0 },
        },
        -- L331: the first ATTITUDE part. On the full machine model a car only turns if something on it makes torque;
        -- the Hella's RP-16 and IA-10 sit on the centreline, so without this it cannot point. Reaction-control
        -- micro-thrusters in opposed pairs: torque about every axis, no net force, burning the Machine's own fuel.
        -- Sized from the Hella's inertia (~3,500 kg m^2 in pitch and yaw): a quarter turn in about three seconds.
        {
            designId = "eng:zetatech:ac6:r1", lineageId = "eng:zetatech:ac6", revision = 1,
            manufacturer = "Zetatech", makerKey = "zetatech", code = "ZTC-AC6", family = "attitude",
            name = "Attitude Control Set AC-6",
            subtitle = "Turns the Machine about any axis. Burns the Machine's own fuel.",
            interface = "hardpoint.h1", massKg = 30, envelope = { 0.6, 0.6, 0.3 }, price = 5400,
            perf = { kind = "attitude_control", torqueNm = 1500, armM = 1.0, ispS = 220, propellant = "fuel", heatKw = 40 },
            thermal = { capacityKjK = 20, rejectKw = 25, limitK = 300, resumeK = 150 },
        },
        -- L334 (owner: "the Hella equipped with relevant parts to break through Deep ... to the KSA border", torch
        -- drive ~1 g for ~3-4 h). Sized from the trip: ~2.4 t to Earth's sphere of influence (925,000 km) at a steady
        -- ~1 g is ~145 km/s of delta-v; at Isp 100,000 s (exhaust ~980 km/s) that is ~16 % of the mass, ~380 kg of
        -- propellant. KB-373 (owner ruling 2026-10-07): 30 kN -- the rear hardpoint's full rating -- with a 400 kg tank; at
        -- 28 kN and 500 kg the fitted Hella (2,634 kg: the car, IA-10, AC-6, FD-1, PT-500 full, fuel) had thrust/weight 1.08
        -- and Guidance (SUSTAIN_MIN_TW 1.15) refused every target. Now ~2,534 kg full, T/W 1.21. In Night City and Assetto
        -- Corsa it is the same forward push the RP-16 was (L333: one part, every host).
        -- Fusion-class, Cyberpunk-plausible, said so: the exhaust carries the jet power (~14 GW at full thrust); the
        -- drive itself sheds ~400 kW into its own radiator.
        {
            designId = "eng:zetatech:fd1:r1", lineageId = "eng:zetatech:fd1", revision = 1,
            manufacturer = "Zetatech", makerKey = "zetatech", code = "ZTC-FD1", family = "propulsor",
            name = "Fusion Drive FD-1",
            subtitle = "A fusion torch: 30 kN for hours on a little propellant. Burns fusion pellets from a tank part.",
            interface = "hardpoint.h1", massKg = 150, envelope = { 0.6, 1.4, 0.6 }, price = 48000,
            -- a +-3 deg gimbal: it trims its own thrust line through the centre of mass (the rear mount sits a few cm off
            -- it: ~1.6 kN m at full thrust, more than an AC-6) and steers the Machine with the thrust it is already making
            perf = { kind = "reaction_engine", thrustN = 30000, ispS = 100000, propellant = "fusion", seaLevelFactor = 1.0,
                throttleTauS = 0.5, minThrottle = 0, heatKw = 400, gimbalDeg = 3 },
            thermal = { capacityKjK = 60, rejectKw = 420, limitK = 500, resumeK = 300 },
        },
        -- its propellant, carried in its own tank part (the Machine's fuel tank stays the car's)
        {
            -- KB-373: 400 kg (the 500 kg tank's extra 100 kg held the full Hella under Guidance's thrust/weight 1.15). The
            -- design id keeps "pt500": it is the persistent identity of tanks already built and fitted.
            designId = "eng:zetatech:pt500:r1", lineageId = "eng:zetatech:pt500", revision = 1,
            manufacturer = "Zetatech", makerKey = "zetatech", code = "ZTC-PT500", family = "tank",
            name = "Propellant Tank PT-400",
            subtitle = "400 kg of fusion pellets for a fusion drive. Mounts anywhere it fits.",
            interface = "hardpoint.h1", massKg = 70, envelope = { 1.0, 1.0, 0.5 }, price = 10500,
            perf = { kind = "propellant_tank", capacityKg = 400, propellant = "fusion" },
        },
        -- Stacked gearboxes (owner, 2026-10-08; doc 50 R4). Driveline boxes on a MANUAL Machine (NCM Gearbox drives
        -- them). Every ratio is relative to the car's OWN TOP GEAR (1.0 = the car's top gear through its final drive):
        -- above 1 is shorter (more pull, a lower ceiling), below 1 taller. Where the box sits decides what it does
        -- (engineering.gearing): inline it continues the car's box (a gearbox: the gears after its top -- a 6-speed car
        -- plus the OD-6 is 12 sequential gears) or multiplies it (a range box: every gear in each range); on a side
        -- mount it is a separate path, engaged by whatever control the driver binds to its `engage` command.
        {
            designId = "eng:thorton:od6:r1", lineageId = "eng:thorton:od6", revision = 1,
            manufacturer = "Thorton", makerKey = "thorton", code = "THO-OD6", family = "gearbox",
            name = "Overdrive Box OD-6",
            subtitle = "Six tall ratios. Inline it carries on where the car's own box runs out.",
            interface = "hardpoint.h1", massKg = 62, envelope = { 0.5, 0.7, 0.4 }, price = 7800,
            perf = { kind = "gearbox", ratios = { 0.90, 0.81, 0.73, 0.66, 0.59, 0.53 }, shiftMs = 280, efficiency = 0.97,
                torqueNm = 900, select = { when = "any" } },
        },
        {
            designId = "eng:archer:cr2:r1", lineageId = "eng:archer:cr2", revision = 1,
            manufacturer = "Archer", makerKey = "archer", code = "ARC-CR2", family = "gearbox",
            name = "Crawler Range Box CR-2",
            subtitle = "Low and high range. Inline it doubles every gear the car has; it changes range only at a stop.",
            interface = "hardpoint.h1", massKg = 48, envelope = { 0.45, 0.5, 0.4 }, price = 5200,
            perf = { kind = "range", ranges = { 2.4, 1.0 }, rangeShift = { ms = 900, when = "stationary" }, efficiency = 0.95,
                torqueNm = 1400 },
        },
        {
            designId = "eng:thorton:cs5:r1", lineageId = "eng:thorton:cs5", revision = 1,
            manufacturer = "Thorton", makerKey = "thorton", code = "THO-CS5", family = "gearbox",
            name = "Close-Ratio Sport Box CS-5",
            subtitle = "Five short, close ratios and a quick shift. On a side mount it is a sprint box you engage at will.",
            interface = "hardpoint.h1", massKg = 55, envelope = { 0.5, 0.65, 0.4 }, price = 9600,
            perf = { kind = "gearbox", ratios = { 2.9, 2.2, 1.75, 1.42, 1.18 }, shiftMs = 120, efficiency = 0.98,
                torqueNm = 700, select = { when = "any" } },
        },
        -- L356: the Slipstream Module. An aftermarket product for any road car, sold on the Base Market (`sale`), installed
        -- in the electronics bay. Its numbers are the unit's own (aero.slipstream reads perf over its defaults), so a
        -- later revision -- or an engineer's -- is a new design, never an edited constant.
        -- 2026-10-12 (owner: "make it fly ... aren't we using our engineering parts and vfx"): the AV's lift engines. A
        -- ducted lift fan is an AIR-BREATHING reaction device (`jet`): its reaction mass is the air, so its fuel Isp is far
        -- above the 360 s chemistry ceiling (L342 covers rockets, which carry all their reaction mass), and it pushes nothing
        -- in vacuum. Four give the fitted Atlus (~7.3 t) thrust/weight 1.5 at sea level; its two FD-1s take it the rest of the
        -- way (with them: 2.4 at sea level, 1.2 at the 12 km Deep seam, where the air leaves the fans a quarter of their thrust). The pods swivel (+-20 deg): the
        -- dynamics tilts each engine's thrust line for whatever torque the flight computer asks, so pitch, roll and yaw come
        -- from the engines themselves -- no attitude set needed.
        {
            designId = "eng:zetatech:vl28:r1", lineageId = "eng:zetatech:vl28", revision = 1,
            manufacturer = "Zetatech", makerKey = "zetatech", code = "ZTC-VL28", family = "propulsor",
            name = "AV Lift Engine VL-28",
            subtitle = "A swivelling ducted lift fan for an AV engine pod. 28 kN at sea level, nothing in vacuum. Burns the Machine's own fuel.",
            interface = "hardpoint.h1", massKg = 260, envelope = { 1.2, 1.6, 1.2 }, price = 64000,
            perf = { kind = "jet", thrustN = 28000, ispS = 8000, propellant = "fuel", throttleTauS = 0.35, gimbalDeg = 20, heatKw = 120 },
            thermal = { capacityKjK = 120, rejectKw = 140, limitK = 400, resumeK = 250 },
            lab = true,
        },
        -- 2026-10-13 (owner: "why am i using car fuel to go to space in your model" -> "yes definitely"): the VL-28E. The same
        -- swivelling ducted lift fan, driven by a fusion-electric plant instead of burning the Machine's fuel (L368 fed the
        -- r1 from the car's tank only because it was the one liquid store a Machine had). Its reaction mass is still the air
        -- -- nothing in vacuum, a quarter of its thrust at the 12 km seam -- so it draws almost nothing from the PT-500: the
        -- AV flies on one propellant from the ground to space, and its car tank no longer matters.
        {
            designId = "eng:zetatech:vl28:r2", lineageId = "eng:zetatech:vl28", revision = 2,
            manufacturer = "Zetatech", makerKey = "zetatech", code = "ZTC-VL28E", family = "propulsor",
            name = "AV Lift Engine VL-28E (fusion-electric)",
            subtitle = "The VL-28 lift fan on a fusion-electric drive: 28 kN at sea level, nothing in vacuum. Draws fusion pellets from a tank part, not the car's fuel.",
            interface = "hardpoint.h1", massKg = 280, envelope = { 1.2, 1.6, 1.2 }, price = 88000,
            perf = { kind = "jet", thrustN = 28000, ispS = 400000, propellant = "fusion", throttleTauS = 0.35, gimbalDeg = 20, heatKw = 120 },
            thermal = { capacityKjK = 120, rejectKw = 140, limitK = 400, resumeK = 250 },
            lab = true,
        },
        -- 2026-10-13 (owner: "we need some fusion drives designed specifically for hauling a trauma team vehicle up, it ...
        -- ran out of fuel 3km up"): the flight to 3 km hung the whole ~7.3 t on the four VL-28s (~2 L/s of the car's fuel)
        -- while both FD-1s sat at 0 % -- a torch only joins when the air is too thin for the fans. The FL-6 is a fusion
        -- LIFT drive (`lift = true`: the flight computer flies it with the fans from the ground up, not as a thin-air
        -- reserve). Two on the belly mounts carry ~half the weight at any height (air or not), so the fans burn half the
        -- fuel, and at the 12 km seam -- where the fans keep a quarter of their thrust -- they still lift it on their own
        -- (2 x 60 kN against ~76 kN). Same propellant and Isp class as the FD-1 (the PT-500 feeds it): at a hover's share
        -- (~40 kN) 400 kg lasts ~2.7 h. A wide +-5 deg gimbal helps the fans hold pitch.
        {
            designId = "eng:zetatech:fl6:r1", lineageId = "eng:zetatech:fl6", revision = 1,
            manufacturer = "Zetatech", makerKey = "zetatech", code = "ZTC-FL6", family = "propulsor",
            name = "Fusion Lift Drive FL-6",
            subtitle = "A downward fusion torch built to haul an AV: 60 kN at any height, flown by the flight computer. Burns fusion pellets from a tank part.",
            interface = "hardpoint.h1", massKg = 220, envelope = { 0.8, 1.2, 0.7 }, price = 92000,
            perf = { kind = "reaction_engine", thrustN = 60000, ispS = 100000, propellant = "fusion", seaLevelFactor = 1.0,
                throttleTauS = 0.4, minThrottle = 0, heatKw = 700, gimbalDeg = 5, lift = true },
            thermal = { capacityKjK = 90, rejectKw = 720, limitK = 500, resumeK = 300 },
            lab = true,
        },
        -- ... and the computer that flies them. It pushes nothing: it reads the stick and the Machine's attitude and spin and
        -- commands each engine's throttle and the torque the engines' swivel must make (engineering.flightcontrol). Fly-by-
        -- wire, the way every AV in Night City flies: let go of the stick and it holds itself level and its height.
        {
            designId = "eng:zetatech:fc1:r1", lineageId = "eng:zetatech:fc1", revision = 1,
            manufacturer = "Zetatech", makerKey = "zetatech", code = "ZTC-FC1", family = "avionics",
            name = "AV Flight Computer FC-1",
            subtitle = "Fly-by-wire for a lift-engine Machine: holds it level and at height; the stick asks for attitude and climb.",
            interface = "hardpoint.h1", massKg = 12, envelope = { 0.4, 0.3, 0.15 }, price = 22000,
            perf = { kind = "flight_computer", maxTiltDeg = 22, maxClimbMs = 9, maxYawRateDegS = 45 },
            lab = true,
        },
        -- 2026-10-13 (owner: "it takes way too long to get up there ... vastly slower to increment altimeter than hella"):
        -- the FC-2. The FC-1 held the climb to 9 m/s whatever the engines could do -- with the FL-6s the Atlus has ~3x its
        -- weight in thrust. The FC-2 climbs as fast as 120 m/s (the thrust and the air decide below that) and comes DOWN at
        -- no more than 25 m/s, so letting go near the ground is never a dive.
        {
            designId = "eng:zetatech:fc1:r2", lineageId = "eng:zetatech:fc1", revision = 2,
            manufacturer = "Zetatech", makerKey = "zetatech", code = "ZTC-FC2", family = "avionics",
            name = "AV Flight Computer FC-2",
            subtitle = "Fly-by-wire for a lift-engine Machine, cleared for fast climbs: up to 120 m/s up, 25 m/s down.",
            interface = "hardpoint.h1", massKg = 12, envelope = { 0.4, 0.3, 0.15 }, price = 30000,
            perf = { kind = "flight_computer", maxTiltDeg = 22, maxClimbMs = 120, maxDescentMs = 25, maxYawRateDegS = 45 },
            lab = true,
        },
        {
            designId = "eng:eddywright:sl1:r1", lineageId = "eng:eddywright:sl1", revision = 1,
            manufacturer = "Eddywright", makerKey = "eddywright", code = "EDW-SL1", family = "slipstream",
            name = "Slipstream SL-1",
            subtitle = "Detects another vehicle's wake and exploits it. Recognises other Slipstream units. Let someone else break the air.",
            interface = "hardpoint.h1", massKg = 6, envelope = { 0.3, 0.25, 0.1 }, price = 4800,
            perf = { kind = "wake_system", reliefMax = 0.30, powerW = 180, lockPerS = 0.9, acquireQ = 0.20 },
            sale = { market = "base", tier = "sport" },
        },
        -- Doc 58 (owner, 2026-10-12: "first, make the toys"): the EXPERIMENTAL propulsion stable. `lab = true`: no `sale`,
        -- no R&D programme, no supply -- never on a market. They reach a Machine only through an owner grant kit
        -- (server/engineering.lua, lab_*). Every number below is a prototype setting, not balance. Each carries its own
        -- charge store (`store`, in charge units: component_state.propellant_kg holds what is left) sized for about two
        -- test activations. The physics and the fiction of each are in its space.drive.* module.
        {
            designId = "eng:ncmlab:wd1:r1", lineageId = "eng:ncmlab:wd1", revision = 1, lab = true,
            manufacturer = "NCM Experimental", makerKey = "ncmlab", code = "XLB-WD1", family = "exotic_drive",
            name = "Warp Field Generator WD-1",
            subtitle = "EXPERIMENTAL. Continuous superluminal drift along the Machine's nose; steer by pointing.",
            interface = "hardpoint.h1", massKg = 90, envelope = { 0.8, 0.8, 0.5 }, price = 1,
            perf = { kind = "warp_drive", factorMin = 1, factorMax = 9, factorStart = 3, expo = 5 / 8, spoolS = 6, rampS = 1.5,
                disengageS = 3, abortS = 0.6, cooldownS = 10, wellRadii = 20, chargePerS = 1, spoolCost = 150,
                store = { capacity = 12000, unit = "charge" } },
        },
        {
            designId = "eng:ncmlab:ab1:r1", lineageId = "eng:ncmlab:ab1", revision = 1, lab = true,
            manufacturer = "NCM Experimental", makerKey = "ncmlab", code = "XLB-AB1", family = "exotic_drive",
            name = "Alcubierre Bubble Projector AB-1",
            subtitle = "EXPERIMENTAL. Carries the Machine inside a spacetime bubble along a locked solution.",
            interface = "hardpoint.h1", massKg = 140, envelope = { 1.0, 1.0, 0.6 }, price = 1,
            perf = { kind = "alcubierre_drive", vsC = 1e6, accelS = 10, formS = 15, settleS = 2, collapseS = 2.5, cooldownS = 30,
                R = 6, sigma = 8, decayPerS = 0.0015, tidalRef = 1e-3, failBelow = 0.15, errorFrac = 2e-6, quality = 0.8,
                maxLy = 100, formCost = 1500, perLyCost = 60, defaultTarget = "hip:87937",
                store = { capacity = 4000, unit = "charge" } },
        },
        {
            designId = "eng:ncmlab:jd1:r1", lineageId = "eng:ncmlab:jd1", revision = 1, lab = true,
            manufacturer = "NCM Experimental", makerKey = "ncmlab", code = "XLB-JD1", family = "exotic_drive",
            name = "Jump Drive JD-1",
            subtitle = "EXPERIMENTAL. Charges, then the Machine is somewhere else. Finite range.",
            interface = "hardpoint.h1", massKg = 120, envelope = { 0.9, 0.9, 0.6 }, price = 1,
            perf = { kind = "jump_drive", maxRangeLy = 10, chargeS0 = 10, chargePerLyS = 1, errorFrac = 1e-6, cooldownS = 60,
                arriveS = 1.2, baseCost = 800, perLyCost = 300, defaultTarget = "hip:70890",
                store = { capacity = 4500, unit = "charge" } },
        },
        {
            designId = "eng:ncmlab:wh1:r1", lineageId = "eng:ncmlab:wh1", revision = 1, lab = true,
            manufacturer = "NCM Experimental", makerKey = "ncmlab", code = "XLB-WH1", family = "exotic_drive",
            name = "Wormhole Generator WH-1",
            subtitle = "EXPERIMENTAL. Opens a throat to a far mouth pinned on a catalogued mass. Fly through it.",
            interface = "hardpoint.h1", massKg = 160, envelope = { 1.0, 1.0, 0.7 }, price = 1,
            perf = { kind = "wormhole_drive", throatR = 15, lifetimeS = 180, openS = 6, collapseS = 4, mouthAheadM = 400,
                approachMS = 15, throatS = 1.5, openCost = 2500, precisionAU = 0.01, cooldownS = 45, returnable = true,
                defaultTarget = "hip:91262", store = { capacity = 5000, unit = "charge" } },
        },
    }
    local designById = {}
    for _, d in ipairs(M.DESIGNS) do designById[d.designId] = d end
    function M.design(id) return designById[id] end
    -- Persisted physical Designs are server authority. Registration never mutates an existing Design.
    function M.register(d)
        if type(d) ~= "table" or type(d.designId) ~= "string" or d.designId == "" or
            not M.isAddOnFamily(d.family) or d.interface ~= M.STANDARD or
            type(d.massKg) ~= "number" or d.massKg <= 0 or type(d.price) ~= "number" or d.price <= 0 or
            type(d.envelope) ~= "table" or #d.envelope ~= 3 then return nil, "invalid_physical_design" end
        for _, v in ipairs(d.envelope) do if type(v) ~= "number" or v <= 0 then return nil, "invalid_envelope" end end
        local ok, errs = Sys.validate(d.perf)
        if not ok then return nil, table.concat(errs, "; ") end
        local old = designById[d.designId]
        if old then return old, "already_registered" end
        designById[d.designId] = d
        return d
    end

    --- Peak force a design can put through its mount (N).
    function M.peakForceN(d)
        local p = d and d.perf or {}
        return p.thrustN or p.forceN or 0
    end

    -- ------------------------------------------------------------------------------------------ fitment
    local function neg(v) return { -v[1], -v[2], -v[3] } end

    --- Can design `d` go on `mountId` of a `vehicleKey` Machine, pointing `facing`? Returns a verdict table:
    --- { ok, reason, mount, axis } -- `axis` is the thrust axis in the Machine frame. Every refusal is physical.
    function M.check(d, vehicleKey, mountId, facing)
        if type(d) ~= "table" or not d.perf then return { ok = false, reason = "not an installable component" } end
        if not M.isAddOnFamily(d.family) then return { ok = false, reason = "this component replaces a factory part; fit it with the Parts inventory" } end
        local ok, errs = Sys.validate(d.perf)
        if not ok then return { ok = false, reason = "component data invalid: " .. table.concat(errs, "; ") } end
        if not (vehicleKey and Vehicles.byKey(vehicleKey)) then return { ok = false, reason = "no hardpoint profile for this Machine" } end
        local m = mountById[mountId or ""]
        if not m then return { ok = false, reason = "no such mount (" .. tostring(mountId) .. ")" } end
        if m.vehicles and not m.vehicles[vehicleKey] then return { ok = false, reason = ("this Machine has no %s"):format(m.label) } end
        if d.interface ~= M.STANDARD then return { ok = false, reason = ("interface %s does not mate with %s"):format(tostring(d.interface), M.STANDARD) } end
        local f = M.FACINGS[facing or ""]
        if not f then return { ok = false, reason = "facing must be one of: " .. table.concat(M.FACING_ORDER, ", ") } end
        -- the electronics bay: a unit goes in the bay facing fore, and nothing else goes there
        if M.isElectronic(d.perf.kind) ~= (m.electronics ~= nil) then
            return { ok = false, reason = m.electronics and ("the %s takes electronics, not a %s"):format(m.label, tostring(d.perf.kind))
                or ("an electronic unit goes in the electronics bay, not on the %s"):format(m.label) }
        end
        if m.electronics then
            if facing ~= "fore" then return { ok = false, reason = "an electronic unit is installed facing fore" } end
            return { ok = true, reason = "mates", mount = m, axis = { 0, 0, 0 } }
        end
        -- the driveline: a box goes in the driveline facing fore, and nothing else goes there
        if M.isDriveline(d.perf.kind) ~= (m.driveline ~= nil) then
            return { ok = false, reason = m.driveline and ("the %s takes a gearbox, not a %s"):format(m.label, tostring(d.perf.kind))
                or ("a gearbox sits in the driveline, not on the %s"):format(m.label) }
        end
        if m.driveline then
            if facing ~= "fore" then return { ok = false, reason = "a driveline box faces fore (its input toward the engine)" } end
            return { ok = true, reason = "mates", mount = m, axis = { 0, 0, 0 } }
        end
        if m.blocked[facing] then return { ok = false, reason = ("facing %s from the %s would fire into the Machine's own body"):format(facing, m.label) } end
        local peak = M.peakForceN(d)
        if peak > m.ratedN then
            return { ok = false, reason = ("structural: %.0f kN peak exceeds the %s rating of %.0f kN"):format(peak / 1000, m.label, m.ratedN / 1000) }
        end
        return { ok = true, reason = "mates", mount = m, axis = neg(f) }
    end

    --- Every (mount, facing) a design could take on this Machine, with the verdict for each. For inspection.
    function M.options(d, vehicleKey)
        local out = {}
        for _, m in ipairs(M.MOUNTS) do
            for _, facing in ipairs(M.FACING_ORDER) do
                local v = M.check(d, vehicleKey, m.id, facing)
                out[#out + 1] = { mountId = m.id, facing = facing, ok = v.ok, reason = v.reason }
            end
        end
        return out
    end

    -- ------------------------------------------------------------------------------------------ resolution
    --- Installed items -> devices. `items` = { { componentId, designId, mountId, facing }, ... } (from the
    --- configuration). Items that no longer check out (a design changed, a facing became illegal) are returned in
    --- `refused` with the reason and produce nothing -- never a silent default.
    function M.resolve(items, vehicleKey)
        local devices, refused = {}, {}
        for _, it in ipairs(items or {}) do
            local d = designById[it.designId or ""]
            local v = d and M.check(d, vehicleKey, it.mountId, it.facing) or { ok = false, reason = "unknown design " .. tostring(it.designId) }
            if v.ok then
                local cmds = {}
                for name, spec in pairs(Sys.commands(d.perf.kind)) do cmds[name] = spec.type end
                devices[#devices + 1] = {
                    componentId = it.componentId, designId = d.designId, code = d.code, name = d.name, family = d.family,
                    kind = d.perf.kind, perf = d.perf, thermal = d.thermal, massKg = d.massKg,
                    mountId = it.mountId, facing = it.facing, pos = { v.mount.pos[1], v.mount.pos[2], v.mount.pos[3] },
                    centred = v.mount.centred == true,
                    axis = v.axis, commands = cmds,
                    -- L334: a tank part's own propellant (kg), as the server last recorded it
                    fillKg = (d.perf.kind == "propellant_tank" or d.perf.store) and tonumber(it.fillKg) or nil,   -- doc 58: a drive's charge
                }
            else
                refused[#refused + 1] = { componentId = it.componentId, reason = v.reason }
            end
        end
        table.sort(devices, function(a, b) return tostring(a.componentId) < tostring(b.componentId) end)
        return devices, refused
    end

    function M.addedMassKg(devices)
        local s = 0
        for _, d in ipairs(devices or {}) do s = s + (d.massKg or 0) end
        return s
    end

    -- ------------------------------------------------------------------------------------------ the step
    --- Per-device runtime state (throttle lag, pulse timers, heat). Pure data; the host keeps one per Machine.
    function M.newState(devices)
        local s = { dev = {} }
        for _, d in ipairs(devices or {}) do s.dev[d.componentId] = { throttle = 0, pulseLeft = 0, sinceS = 1e9, heatK = 0, hot = false } end
        return s
    end

    --- Advance every device by dt seconds under `commands` ({ [componentId] = { throttle = 0..1, discharge = true } })
    --- with `fuelKg` available -- a number (the Machine's fuel) or, L334, a table of pools by propellant
    --- ({ fuel = kg, fusion = kg }); each device draws from its own `propellant` (default fuel). The result also
    --- carries `byPropellant` ({ fuel = kg, fusion = kg } spent). Returns { force = {x,y,z} N (Machine frame), torque = {x,y,z} N m about `com`,
    --- propellantKg, pulses, out = { [componentId] = { thrustN, heatK, hot, starved } } }.
    ---
    --- Propellant is checked BEFORE it is spent: a device that cannot be fed for this step produces nothing.
    function M.step(devices, state, commands, dt, fuelKg, com)
        commands = commands or {}
        com = com or { 0, 0, 0.5 }
        local pools = {}
        if type(fuelKg) == "table" then for k, v in pairs(fuelKg) do pools[k] = math.max(0, tonumber(v) or 0) end
        else pools.fuel = math.max(0, tonumber(fuelKg) or 0) end
        local byProp = {}
        local F, T = { 0, 0, 0 }, { 0, 0, 0 }
        local spent, pulses, out = 0, 0, {}
        for _, d in ipairs(devices or {}) do
            local st = state.dev[d.componentId]
            if not st then st = { throttle = 0, pulseLeft = 0, sinceS = 1e9, heatK = 0, hot = false }; state.dev[d.componentId] = st end
            local cmd = commands[d.componentId] or {}
            local p, thrust, starved = d.perf, 0, false
            local heatIn = 0
            local prop = p.propellant or "fuel"
            local fuel = pools[prop] or 0
            if p.kind == "reaction_engine" then
                local want = math.max(0, math.min(1, tonumber(cmd.throttle) or 0))
                if st.hot then want = 0 end
                local tau = p.throttleTauS or 0
                st.throttle = tau > 0 and (st.throttle + (want - st.throttle) * math.min(1, dt / tau)) or want
                if st.throttle < 1e-3 then st.throttle = 0 end
                local f = Sys.thrustAt(p, Sys.RHO0, st.throttle)
                local kg = f / (p.ispS * Sys.G0) * dt
                if kg > fuel then starved = f > 0; f, kg = 0, 0; st.throttle = 0 end
                pools[prop], spent, thrust = fuel - kg, spent + kg, f
                byProp[prop] = (byProp[prop] or 0) + kg
                heatIn = (p.heatKw or 0) * st.throttle * dt
            elseif p.kind == "pulse_reaction" then
                st.sinceS = st.sinceS + dt
                local ready = st.pulseLeft <= 0 or p.retrigger
                if cmd.discharge and ready and st.sinceS >= (p.rechargeS or 0) and not st.hot then
                    local kg = Sys.pulseMass(p)
                    if kg <= fuel then
                        pools[prop], spent, pulses = fuel - kg, spent + kg, pulses + 1
                        byProp[prop] = (byProp[prop] or 0) + kg
                        st.pulseLeft, st.sinceS = p.pulseS, 0
                        heatIn = heatIn + (p.heatKj or 0)
                    else
                        starved = true
                    end
                end
                if st.pulseLeft > 0 then
                    local active = math.min(dt, st.pulseLeft)
                    thrust = p.forceN * active / dt   -- the step's average force: impulse is exact at any frame rate
                    st.pulseLeft = st.pulseLeft - active
                end
            end
            -- heat: in from the device, out through its rejection; past the limit it shuts itself down until cool
            local th = d.thermal
            if th and th.capacityKjK and th.capacityKjK > 0 then
                st.heatK = math.max(0, st.heatK + (heatIn - (th.rejectKw or 0) * dt) / th.capacityKjK)
                if not st.hot and st.heatK >= (th.limitK or 1e9) then st.hot = true end
                if st.hot and st.heatK <= (th.resumeK or 0) then st.hot = false end
            end
            local f = { d.axis[1] * thrust, d.axis[2] * thrust, d.axis[3] * thrust }
            F[1], F[2], F[3] = F[1] + f[1], F[2] + f[2], F[3] + f[3]
            local r = { d.pos[1] - com[1], d.pos[2] - com[2], d.pos[3] - com[3] }
            T[1] = T[1] + r[2] * f[3] - r[3] * f[2]
            T[2] = T[2] + r[3] * f[1] - r[1] * f[3]
            T[3] = T[3] + r[1] * f[2] - r[2] * f[1]
            out[d.componentId] = { thrustN = thrust, throttle = st.throttle, heatK = st.heatK, hot = st.hot, starved = starved }
        end
        return { force = F, torque = T, propellantKg = spent, pulses = pulses, out = out, byPropellant = byProp }
    end

    --- Machine frame -> world, with the host's live basis ({ right, forward, up }, each {x,y,z} or {1,2,3}).
    function M.toWorld(v, frame)
        local function c(a, i, k) return tonumber(a[k] or a[i]) or 0 end
        local r, f, u = frame and frame.right, frame and frame.forward, frame and frame.up
        if type(r) ~= "table" or type(f) ~= "table" or type(u) ~= "table" then return nil end
        return {
            c(r, 1, "x") * v[1] + c(f, 1, "x") * v[2] + c(u, 1, "x") * v[3],
            c(r, 2, "y") * v[1] + c(f, 2, "y") * v[2] + c(u, 2, "y") * v[3],
            c(r, 3, "z") * v[1] + c(f, 3, "z") * v[2] + c(u, 3, "z") * v[3],
        }
    end

    M.FUEL_KG_PER_L = 0.745   -- the Machine tank holds petrol; propellant draws convert at this density

    return M
end)
