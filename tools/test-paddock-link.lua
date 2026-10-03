-- Host-adapter regression for ncm_league's half of mixed Paddock grids (L250 steps 3-4; server/paddock_link.lua).
-- The real file against platform and league doubles: a Paddock race adopted as a calendar event, QUALIFY, a qualifying
-- run that enters the driver and tells the Paddock, the Paddock's slots becoming the session's, the pre-grid relay (L296:
-- provisional slots from T-15 min; the T-20 auto-place is gone), and settlement waiting for the whole-field classification.
local root = (arg and arg[1]) or "."
local passed = 0
local function check(label, ok)
    if not ok then error("FAIL " .. label, 0) end
    passed = passed + 1
    print("  PASS " .. label)
end

-- the real core, loaded the way a host does
local Core = dofile(root .. "/ncm/core/init.lua")
for _, f in ipairs(dofile(root .. "/ncm/core/MANIFEST.lua")) do dofile(root .. "/ncm/core/" .. f) end
local Mixed = Core.get("paddock.mixed")

-- ---------------------------------------------------------------- platform doubles
local clock = 1800000000
local events, emitted, chats, toasts, routed, calls = {}, {}, {}, {}, {}, {}
function AddEventHandler(name, fn) events[name] = fn end
function RegisterNetEvent(name, fn) events[name] = fn end
function RegisterCommand() end
function TriggerEvent(name, ...) emitted[#emitted + 1] = { name = name, args = { ... } } end
pregrids = {}
function TriggerClientEvent(name, pid, body)
    if name == "ncm:guide.route" then routed[#routed + 1] = body end
    if name == "ncm:race.pregrid" then pregrids[#pregrids + 1] = { pid = pid, body = body } end
end
local THREADS = {}
function CreateThread(fn) THREADS[#THREADS + 1] = fn end
local function drain() local q = THREADS; THREADS = {}; for _, fn in ipairs(q) do fn() end end
function Wait() end
function GetPlayerName(pid) return "Player" .. pid end
local realPrint = print
local logs = {}
function print(s) logs[#logs + 1] = tostring(s) end
local POS = { [1] = { x = 0, y = 0, z = 0 } }
local SEAT = { [1] = { vehicleId = 77 } }
CARPOS, OTHERS = {}, {}
Open77 = {
    time = { unix = function() return clock end },
    chat = { send = function(pid, m) chats[#chats + 1] = m end },
    notifications = { send = function(pid, d) toasts[#toasts + 1] = d end },
    players = { get = function(pid) return { position = POS[pid], fresh = true } end },
    vehicles = {
        getPlayerSeat = function(pid) return SEAT[pid] end,
        forcePlayerOutOfVehicle = function(pid, vid) calls[#calls + 1] = "out:" .. vid; SEAT[pid] = nil; return true end,
        setTransform = function(vid, tr) calls[#calls + 1] = ("move:%d:%.0f,%.0f"):format(vid, tr.position.x, tr.position.y)
            CARPOS[vid] = { x = tr.position.x, y = tr.position.y, z = tr.position.z }; return true end,
        -- the player ends up where their car is (L285: placement is verified against the player's real position)
        warpPlayerIntoVehicle = function(pid, vid, seat) calls[#calls + 1] = "in:" .. vid .. ":" .. seat; SEAT[pid] = { vehicleId = vid }
            if CARPOS[vid] then POS[pid] = CARPOS[vid] end; return true end,
        -- L288: grid assist refuses a slot another network vehicle stands on
        all = function() return OTHERS end,
    },
}
GlobalState = {}
local SQL = {}
MySQL = {
    query = { await = function() return {} end },
    insert = { await = function(q, v) SQL[#SQL + 1] = { q = q, v = v } return 1 end },
    single = { await = function() return nil end },
    scalar = { await = function() return 0 end },
    update = { await = function() return 1 end },
}

-- ---------------------------------------------------------------- league doubles
local adopted, checkIns = {}, {}
local DRIVER = { ncmDriverId = "0a1b2c3d-4e5f-4061-8a7b-9c0d1e2f3a4b", display = "Owner" }
NcmCalendar = {
    events = {}, settings = { paddockEntries = true },
    serverId = function() return "ncm-devbox" end,
    resolveDriver = function(pid) return pid == 1 and DRIVER or nil end,
    adopt = function(e) if NcmCalendar.events[e.eventId] then return nil, "duplicate_event" end
        NcmCalendar.events[e.eventId] = e; adopted[#adopted + 1] = e; return true end,
    publishNow = function() end,
}
local joined = {}
NcmRace = {
    busySession = function() return nil end,
    practiceJoin = function(e, driver, pid) joined[#joined + 1] = e.eventId return true end,
    practiceLeave = function() end,
    seatedAsset = function() return "11111111-2222-4333-8444-555555555555" end,
}
NcmCompetition = {
    carRefusal = function() return nil end,
    enterMachine = function(e, driverId, prefer) return prefer end,
    economyFor = function(e) return e.economy end,
}
NcmEconomy = { checkIn = function(req) checkIns[#checkIns + 1] = req return { fee = req.economy.entryFee, balance = 900 } end }
-- L252: QUALIFY starts only inside the race's venue ring; the harness driver stands in whichever ring is asked about
NcmGuide = { refreshEntryBag = function() end, pushAll = function() end, venueAt = function() return NcmGuideVenue end }
NcmPackStreet = { series = {
    { seriesId = "city_cup", name = "NCM City Cup", economy = { id = "city_cup_v1", entryFee = 50 } },
    { seriesId = "street_drag", name = "Street Drag", economy = { id = "drag", entryFee = 10 } },
} }

dofile(root .. "/ncm/online/resources/ncm_league/server/paddock_link.lua")
realPrint("paddock link harness")

-- ---------------------------------------------------------------- adoption
local ROOT = "root_hill_abode_505_1229__to__downtown_2362_117"
local startsAt = clock + 3 * 3600
GlobalState.ncmPaddockGuide = {
    { raceId = "pr-street_a-1", seriesId = "street_a", seriesName = "Kabuki Midnight", tier = "street", routeId = ROOT, startsAt = startsAt, state = "scheduled", field = 12 },
    { raceId = "pr-pro_b-2", seriesId = "pro_b", seriesName = "NCM City Cup", tier = "pro", routeId = ROOT, startsAt = startsAt + 600, state = "priced", field = 10 },
    { raceId = "pr-oval-3", seriesId = "street_b", seriesName = "Charter Hill Run", tier = "street", routeId = ROOT, startsAt = startsAt, state = "scheduled", oval = true },
    { raceId = "pr-soon-4", seriesId = "street_c", seriesName = "Corpo Plaza Outlaws", tier = "street", routeId = ROOT, startsAt = clock + 300, state = "scheduled" },
}
local n = NcmPaddockLink.adoptAll(clock)
local e = NcmCalendar.events["paddock:pr-street_a-1"]
-- L261: ovals are adopted; L269 + owner 2026-10-02: entries close at T-1, so a race five minutes out is still open
local ovalE = NcmCalendar.events["paddock:pr-oval-3"]
check(("open Paddock races become calendar events, ovals and a race 5 min out included (%d adopted)"):format(n),
    n == 4 and e and e.class == "paddock" and e.entryClosesAt == startsAt - 60 and ovalE and ovalE.disciplineId == "oval"
    and NcmCalendar.events["paddock:pr-soon-4"] ~= nil)
local pro = NcmCalendar.events["paddock:pr-pro_b-2"]
check("a league named after a championship takes its economy; a street league the fallback (City Cup's)",
    pro.seriesId == "city_cup" and pro.economy.id == "city_cup_v1" and e.seriesId == "paddock_street_a" and e.economy.id == "city_cup_v1")
check("adoption is idempotent", NcmPaddockLink.adoptAll(clock) == 0)

-- ---------------------------------------------------------------- QUALIFY and a run
NcmGuideVenue = nil
check("QUALIFY away from the venue ring is refused (L252)", select(2, NcmPaddockLink.qualify(1, e.eventId)) == "not_at_venue")
NcmGuideVenue = e.eventId
NcmPaddockLink.qualify(1, e.eventId)
check("QUALIFY opens the race's qualifying session and routes the driver to its start", joined[1] == e.eventId and routed[1] and routed[1].name == e.venue.name)
local rec = { eventId = e.eventId, paddockQuali = true }
emitted = {}
NcmPaddockLink.onQualiRun(rec, DRIVER.ncmDriverId, 1, { finished = true, runSec = 161.25, machine = { assetId = "11111111-2222-4333-8444-555555555555" } }, clock)
local en = e.entries[DRIVER.ncmDriverId]
check("the first time ENTERS the driver, through the league's ordinary entry (fee, machine)", en and en.state == "checked_in"
    and #checkIns == 1 and checkIns[1].assetId == "11111111-2222-4333-8444-555555555555" and checkIns[1].economy.entryFee == 50)
local msg = emitted[1] and emitted[1].name == "ncm:paddock.entry" and emitted[1].args[1]
check("and the Paddock hears the entry with the time", msg and msg.raceId == "pr-street_a-1" and msg.qualiMs == 161250 and msg.state == "entered")
emitted = {}
NcmPaddockLink.onQualiRun(rec, DRIVER.ncmDriverId, 1, { finished = true, runSec = 165, machine = {} }, clock + 60)
check("a slower run changes nothing the Paddock needs (no second fee, no announcement)", #emitted == 0 and #checkIns == 1
    and NcmPaddockLink.bests[e.eventId][DRIVER.ncmDriverId] == 161250)
NcmPaddockLink.onQualiRun(rec, DRIVER.ncmDriverId, 1, { finished = true, runSec = 158.5, machine = {} }, clock + 120)
check("a faster one is announced", emitted[1] and emitted[1].args[1].qualiMs == 158500 and #checkIns == 1)

-- ---------------------------------------------------------------- the Paddock's slots
events["ncm:paddock.grid"]("pr-street_a-1", { fieldSize = 12, greenAt = startsAt,
    slots = { [DRIVER.ncmDriverId] = { slot = 3, x = 10, y = 20, z = 1, heading = 90, yaw = 0 } } })
local slots, field = NcmPaddockLink.slotsFor(e, { { driverId = DRIVER.ncmDriverId, entryId = "en1", display = "Owner" },
    { driverId = "ffffffff-0000-4000-8000-000000000000", entryId = "en2", display = "Ghost" } })
check("the session's slots are the Paddock's; an entrant it never gridded gets none", #slots == 1 and slots[1].slot == 3
    and slots[1].x == 10 and slots[1].radiusM == 4 and field == 12)

-- ---------------------------------------------------------------- the pre-grid (L296; no auto-place)
check("the T-20 auto-place is gone (owner, 2026-10-02: \"nor should it be\")", NcmPaddockLink.autoPlace == nil)
events["ncm:paddock.pregrid"]("pr-street_a-1", { fieldSize = 12, provisional = true,
    slots = { [DRIVER.ncmDriverId] = { slot = 12, x = 40, y = 20, z = 1, qualified = true },
              ["ffffffff-0000-4000-8000-000000000000"] = { slot = 11, x = 44, y = 20, z = 1 } } })
pregrids = {}
local sentN = NcmPaddockLink.pushPreGrid(e, { [DRIVER.ncmDriverId] = 1 }, startsAt - 600)
check("before the session forms, an entered driver is sent their provisional slot (and only an entered one)",
    sentN == 1 and pregrids[1] and pregrids[1].pid == 1 and pregrids[1].body.slot == 12 and pregrids[1].body.x == 40
    and pregrids[1].body.paddockRaceId == "pr-street_a-1" and pregrids[1].body.formsAt == startsAt - 50 and pregrids[1].body.qualified == true
    and pregrids[1].body.serverNow == startsAt - 600)   -- KB-320: the client counts from the server's clock
check("re-sent every few seconds, not every tick", NcmPaddockLink.pushPreGrid(e, { [DRIVER.ncmDriverId] = 1 }, startsAt - 599) == 0
    and NcmPaddockLink.pushPreGrid(e, { [DRIVER.ncmDriverId] = 1 }, startsAt - 596) == 1)
check("never after the start", NcmPaddockLink.pushPreGrid(e, { [DRIVER.ncmDriverId] = 1 }, startsAt + 1) == 0)

-- ---------------------------------------------------------------- the result waits for the whole field
local completed
local function completeFn(r, results) completed = { rec = r, results = results } end
local raceRec = { paddock = true, eventId = e.eventId, plan = { e = e }, s = { gates = { {}, {} } }, playerOf = { [DRIVER.ncmDriverId] = 1 } }
local results = { { driverId = DRIVER.ncmDriverId, display = "Owner", position = 1, state = "finished", totalSec = 150.5, progress = 2, gatesTotal = 2 } }
emitted = {}
NcmPaddockLink.awaitClassification(raceRec, results, "complete", clock, completeFn)
local hr = emitted[1] and emitted[1].name == "ncm:paddock.human.result" and emitted[1].args
check("the humans' times go to the Paddock (ms from the one green)", hr and hr[1] == "pr-street_a-1" and hr[2][1].finishMs == 150500)
check("and settlement waits for its answer", completed == nil and raceRec.provisional)
events["ncm:paddock.classified"]("pr-street_a-1", { places = { [DRIVER.ncmDriverId] = 4 }, fieldSize = 12 })
check("the whole field's place and size come back, then settlement runs", completed and completed.results[1].position == 4
    and completed.rec.mixedField == 12 and completed.rec.classified)
completed = nil
drain()
check("the fallback timeout does not settle twice", completed == nil)
local lone = { paddock = true, eventId = e.eventId, plan = { e = e }, s = { gates = { {}, {} } }, playerOf = {} }
NcmPaddockLink.awaitClassification(lone, { { driverId = DRIVER.ncmDriverId, position = 1, state = "dnf", progress = 1, gatesTotal = 2 } }, "complete", clock, completeFn)
drain()
check("with no answer from the Paddock the humans settle alone, after the wait", completed and completed.rec == lone and lone.classified and lone.mixedField == nil)

realPrint(("%d passed, 0 failed"):format(passed))
