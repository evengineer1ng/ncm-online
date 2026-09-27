-- Content pack #1 (street) — the championships NCM runs on its authored roots.
--
-- IDEA-111: the calendar is no longer "a route every 20 minutes". The organizing principle is the CHAMPIONSHIP:
-- a route is a venue/course, a championship is a sporting product that consumes routes, and a scheduled event is
-- one occurrence of a championship at a route and time. Each championship below has its OWN cadence, and they
-- are meant to overlap — independent schedules are what turn the Race Guide into a programming guide rather than
-- a countdown dispenser. `Cal.materialize` is per-series and `Cal.merge` merges them, so concurrency needs no
-- scheduler: it falls out of the cadences. Offsets are staggered only so two championships do not post on the
-- same minute *every* time; they will still coincide, which is intended.
--
-- A championship owns: cadence, route pool, discipline, format, class (BoP), eligibility (what machinery it
-- admits), TIER, capacity and entry window. A route owns geography and nothing else.
--
-- `tier` is L58's street/sanctioned split, declared per championship because it cannot be derived: every cadence
-- series has `class = "calendar"`, so `guide.tierOf` would otherwise call all five of these street. Street is not
-- the lesser mode (L58) -- it is a grittier kind of championship, and the distinction is what eventual rulesets
-- hang off. No `label` overrides here — the
-- roots pack owns route names (IDEA-104).
--
-- Eligibility specs are `competition.eligibility` predicates over `data.vehicle_pool` and are enforced at entry
-- (L83: refused, never substituted). Cadences and fields are provisional design data, not sacred constants.
--
-- NOT PRESENT, and why: **Badlands Rallycross cannot be scheduled yet.** It needs an off-road route and the
-- node bank holds exactly ONE Badlands node (`go_smile_5042_-1044`); a route needs two. Running it on city
-- routes would make it a Nomad-car street series wearing a rallycross name. It waits on route authoring
-- (KB-46 is the same shape of gap for rolling starts). **NCX World Championship** is also absent: it wants an
-- explicit calendar and `validateSeries` requires `cadence.everyMinutes >= 1` (IDEA-114).
local function economy(scale, id)
    scale = scale or 1
    return {
        id = id, version = 1,
        entryFee = 50 * scale,
        timeTrialCompletion = 250 * scale,
        raceCompletion = 300 * scale,
        repeatWindowSec = 86400,
        fullRateCompletions = 1,
        repeatFloor = 50 * scale,
        placement = { [1] = 350 * scale, [2] = 150 * scale, [3] = 75 * scale },
        fieldBonus = { perEntrant = 50 * scale, max = 250 * scale },
        targets = {}, -- route-specific targets are deliberately off until authored times exist
        tagBounties = { clean_run = 50 * scale, clean_race = 75 * scale },
        maxTagBounty = 150 * scale,
    }
end

NcmPackStreet = {
    packId = "ncm_pack_street",
    version = "0.1.0",
    series = {
        {
            -- The accessible production-car championship: what a new driver can actually field.
            seriesId = "city_cup",
            name = "NCM City Cup",
            tier = "street",
            rulesetId = "street_sprint_v0",
            cadence = { everyMinutes = 20, offsetMinutes = 0 },
            disciplineId = "street_sprint", formatId = "sprint", classId = "street_open", laps = 1,   -- L53 vocabulary
            -- entry-performance road machinery: the ordinary classes, nothing exotic. Bikes and Nomad-only cars
            -- are out because this is the road-car championship, not because they are unwelcome elsewhere.
            eligibility = { classes = { "Muscle", "Sport", "Tech" }, prestigeMax = 2 },
            economy = economy(1, "city_cup_v1"),
            capacity = 20,
            -- Eight point-to-point roots, rotated in order: series.routes[(k % #routes) + 1].
            -- The same pool is consumed by every championship below; a route may host several at different times.
            routes = {
                { rootId = "root_tip_1035_3652__to__trench_2899_2711" },                        -- Ukulele
                { rootId = "root_hill_abode_505_1229__to__downtown_2362_117" },                 -- Snake in the Grass
                { rootId = "root_parque_del_mar_2326_1125__to__gold_niwaki_plaza_264_304" },    -- The Cut
                { rootId = "root_hanford_overpass_1281_1107__to__stadium_1326_1656" },          -- Troll Pass
                { rootId = "root_north_tunnel_1450_2467__to__japantown_crossway_373_0" },       -- Sewer
                { rootId = "root_glenview_lofts_1489_964__to__corpo_plaza_1103_19" },           -- Overbridge Curve
                { rootId = "root_gold_niwaki_plaza_264_304__to__parque_del_mar_2326_1125" },    -- Reverse Cut
                { rootId = "root_central_highway_1110_342__to__pothole_1354_476" },             -- Hook
            },
            entryWindow = { opensMinutes = 15, closesMinutes = 1 },
            venueRadiusM = 30,
        },
        {
            -- One-make. The whole point is that the car is not a variable.
            seriesId = "maimai_cup",
            name = "MaiMai Cup",
            tier = "street",
            rulesetId = "street_sprint_v0",
            cadence = { everyMinutes = 30, offsetMinutes = 10 },
            disciplineId = "street_sprint", formatId = "sprint", classId = "street_open", laps = 1,
            eligibility = { records = { "Vehicle.v_standard2_makigai_maimai" } },
            economy = economy(1, "maimai_cup_v1"),
            capacity = 20,
            routes = {
                { rootId = "root_hill_abode_505_1229__to__downtown_2362_117" },                 -- Snake in the Grass
                { rootId = "root_glenview_lofts_1489_964__to__corpo_plaza_1103_19" },           -- Overbridge Curve
                { rootId = "root_central_highway_1110_342__to__pothole_1354_476" },             -- Hook
                { rootId = "root_hanford_overpass_1281_1107__to__stadium_1326_1656" },          -- Troll Pass
            },
            entryWindow = { opensMinutes = 15, closesMinutes = 1 },
            venueRadiusM = 30,
        },
        {
            -- Serious high-performance road/GT. The brief names Mizutani/Quadra/Herrera families; the pool has
            -- no `make` field and reading the maker out of a TweakDB id is the "a parsed id is not a catalogue"
            -- mistake (IDEA-113), so this is expressed by class and prestige until `make` is authored. The top
            -- end is excluded on purpose: prestige 5 is the Hypercar championship's field, not this one.
            seriesId = "night_city_gt",
            name = "Night City GT",
            tier = "sanctioned",
            rulesetId = "street_sprint_v0",
            cadence = { everyMinutes = 60, offsetMinutes = 25 },
            disciplineId = "street_sprint", formatId = "sprint", classId = "street_open", laps = 1,
            eligibility = { classes = { "Sport", "Muscle" }, prestigeMin = 3, prestigeMax = 4 },
            economy = economy(10, "night_city_gt_v1"),
            capacity = 20,
            routes = {
                { rootId = "root_tip_1035_3652__to__trench_2899_2711" },                        -- Ukulele
                { rootId = "root_parque_del_mar_2326_1125__to__gold_niwaki_plaza_264_304" },    -- The Cut
                { rootId = "root_gold_niwaki_plaza_264_304__to__parque_del_mar_2326_1125" },    -- Reverse Cut
                { rootId = "root_north_tunnel_1450_2467__to__japantown_crossway_373_0" },       -- Sewer
                { rootId = "root_hill_abode_505_1229__to__downtown_2362_117" },                 -- Snake in the Grass
            },
            entryWindow = { opensMinutes = 15, closesMinutes = 1 },
            venueRadiusM = 30,
        },
        {
            -- Exotic machinery. `classes = { "Sport" }` rather than a bare `prestigeMin = 5`, because the RB15
            -- is also prestige 5 and the NCX car must never be enterable here.
            seriesId = "hypercar",
            name = "Hypercar Championship",
            tier = "sanctioned",
            rulesetId = "street_sprint_v0",
            cadence = { everyMinutes = 180, offsetMinutes = 40 },
            disciplineId = "street_sprint", formatId = "sprint", classId = "street_open", laps = 1,
            eligibility = { classes = { "Sport" }, prestigeMin = 5 },
            economy = economy(100, "hypercar_v1"),
            capacity = 20,
            routes = {
                { rootId = "root_tip_1035_3652__to__trench_2899_2711" },                        -- Ukulele
                { rootId = "root_parque_del_mar_2326_1125__to__gold_niwaki_plaza_264_304" },    -- The Cut
                { rootId = "root_north_tunnel_1450_2467__to__japantown_crossway_373_0" },       -- Sewer
            },
            entryWindow = { opensMinutes = 15, closesMinutes = 1 },
            venueRadiusM = 30,
        },
        {
            -- Open drag, on the two roots whose own data says `recommendedMode = "drag"` (IDEA-104).
            seriesId = "street_drag",
            name = "Street Drag",
            tier = "street",
            rulesetId = "street_sprint_v0",
            cadence = { everyMinutes = 30, offsetMinutes = 20 },
            disciplineId = "drag", formatId = "sprint", classId = "street_open", laps = 1,
            -- "Open" means every street class, NOT literally everything: a bare `{}` admits the whole pool and
            -- the pool contains the RB15, so an open series would quietly let an NCX Formula car into a street
            -- drag race. Naming the classes is the fix; Formula is entered through NCX and nowhere else.
            eligibility = { classes = { "Muscle", "Sport", "Tech", "Nomad", "Bike" } },
            economy = economy(1, "street_drag_v1"),
            capacity = 20,
            routes = {
                { rootId = "root_vista_del_drag_900_751__to__japantown_crossway_373_0" },       -- B-line
                { rootId = "root_deep_dive_2350_2446__to__trench_2899_2711" },                  -- Hold Your Breath
            },
            entryWindow = { opensMinutes = 15, closesMinutes = 1 },
            venueRadiusM = 30,
        },
    },
}
