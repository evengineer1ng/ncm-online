-- NCM Host boot gate (L338, doc 55): the OPEN//77 resources, UNCHANGED, run single-player under the NCM Host over
-- SQLite with no game and no OPEN//77 -- and Race Week tapes behave as the brief requires:
--   * a tape mounts: migrations by model, ncm_league + ncm_world + ncm_paddock (+ the small ones) start, player 1 joins
--   * no thread or handler error; the unsupported-API list is measured (and must not grow unnoticed)
--   * Race Week runs on the tape's own clock and seed; quitting and returning 19 days later settles every verdict
--     missed, in order, with no process running in between; the deck's calculated present matches the world's
--   * two tapes are two worlds (server_id isolation); a machine stranded in Deep is back in Night City after rollover
-- LuaJIT + sqlite3.dll only (FFI); under Lua 5.4 it reports a skip.
--   luajit tools/test-host-boot.lua <repo>
local REPO = ((arg and arg[1]) or "."):gsub("\\", "/")
local HOST = REPO .. "/ncm/host/"
local RES = REPO .. "/ncm/online/resources/"

if type(rawget(_G, "jit")) ~= "table" then print("host boot: skipped under " .. _VERSION .. " (needs LuaJIT FFI for SQLite)"); return end
local Driver = dofile(HOST .. "sql/driver_ffi.lua")
local dll = Driver.locate()
if not dll then print("host boot: SKIP -- no sqlite3.dll (set NCM_SQLITE_DLL)"); return end

local VERBOSE = os.getenv("NCM_HOST_VERBOSE") == "1"
local fails, passes = 0, 0
local function check(cond, fmt, ...)
    if cond then passes = passes + 1 else fails = fails + 1; print("  FAIL " .. string.format(fmt, ...)) end
end

local function readFile(p) local f = io.open(p, "rb"); if not f then return nil end; local s = f:read("*a"); f:close(); return s end
local tmpDir = (os.getenv("TEMP") or "."):gsub("\\", "/")
local tapesPath = tmpDir .. "/ncm-host-boot-tapes.json"
os.remove(tapesPath); os.remove(tapesPath .. ".bak")

local Clock = dofile(HOST .. "clock.lua")
local clock = Clock.virtual(1791388800)          -- 2026-10-07 16:00 UTC (12:00 ET)
local logLines = {}
local function log(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    s = ok and s or tostring(fmt)
    logLines[#logLines + 1] = s
    if VERBOSE then print("    " .. s) end
end

local db
local env = {
    load = function(rel) return dofile(HOST .. rel) end,
    read = readFile,
    write = function(p, s) local f = io.open(p, "wb"); if not f then return false end; f:write(s); f:close(); return true end,
    rename = function(a, b) os.remove(b); return os.rename(a, b) end,
    remove = function(p) os.remove(p) end,
    sqlite = function() db = db or assert(Driver.open(dll, ":memory:")); return db end,
    log = log, clock = clock, resourceRoot = RES, tapesPath = tapesPath,
}
local App = dofile(HOST .. "app.lua")
local app = App.new(env)

local function grep(pat)
    local n = 0
    for _, l in ipairs(logLines) do if l:find(pat) then n = n + 1 end end
    return n
end

-- ------------------------------------------------------------------------------------------------ TAPE 01
local t1 = app:newTape()
check(t1.ordinal == 1 and t1.serverId:match("^sp%-t01%-"), "tape 01 minted (%s)", t1.serverId)
local deck0 = app:tapes()
check(#deck0 == 1 and deck0[1].present and deck0[1].present.run == 1 and deck0[1].present.day == 1,
    "a new tape is RW 01 . D1 on the deck before anything runs (%s)", deck0[1].present and deck0[1].present.label or "?")

local okM, whyM = pcall(app.mount, app, t1.id)
check(okM and whyM == true, "tape 01 mounts: %s", tostring(whyM))
local h = app.world
if h then
    h:advance(180, 1)
    local errs = #h.errors
    if errs > 0 then for i = 1, math.min(12, errs) do print(("    error %s %s: %s"):format(h.errors[i].vm, h.errors[i].label, h.errors[i].err:sub(1, 400))) end end
    check(errs == 0, "%d thread/handler error(s) in the first 3 minutes", errs)
    local un = h:unsupportedList()
    print(("  unsupported API calls after boot: %d distinct"):format(#un))
    for _, u in ipairs(un) do print(("    %-58s x%d"):format(u.key, u.n)) end
    check(app.mysql.stats.errors == 0, "%d SQL error(s) at boot", app.mysql.stats.errors)
    -- identity minted on this tape's server id
    local drv = db.query(("SELECT ncm_driver_id FROM ncm_driver_binding WHERE server_id = '%s'"):format(t1.serverId))
    check(#drv == 1, "player 1 has an NCM driver bound on %s (%d)", t1.serverId, #drv)
    local wk = h.global.ncmWeek
    check(type(wk) == "table" and wk.run == 1, "GlobalState.ncmWeek is published for RW 01 (%s)", wk and tostring(wk.run) or "nil")

    -- ---------------------------------------------------------------------------------------------- CLAIM (L338)
    local given = {}
    env.game = nil
    app.env.game = { giveCar = function(rec) given[#given + 1] = rec; return true end }
    -- sitting in a base RB15 that wears the kimiko appearance: the claim is the Kimiko record
    local okC, rec = app:claim("Vehicle.v_sport1_rb15_f1", "kimiko")
    h:advance(5, 1)
    check(okC and rec == "Vehicle.v_sport1_rb15_f1_kimiko", "claiming the car you sit in names its livery record (%s)", tostring(rec))
    local q1 = function(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end
    local count = function(sql) return tonumber(db.scalar(sql)) or 0 end
    local a = db.query(("SELECT asset_id, vehicle_key, production_ordinal, maker_ordinal, model_ordinal, manufacturer_key, " ..
        "ncm_driver_id, paint_primary FROM vehicle_asset WHERE server_id = %s AND record = 'Vehicle.v_sport1_rb15_f1_kimiko'"):format(q1(t1.serverId)))
    check(#a == 1 and a[1].vehicle_key == "ncx_rb15", "one Kimiko RB15 exists on tape 01 as the RB15 model (%d)", #a)
    check(a[1] and a[1].production_ordinal and a[1].maker_ordinal and a[1].model_ordinal, "it is SERIALIZED: NCM #%s, %s #%s, model #%s",
        tostring(a[1] and a[1].production_ordinal), tostring(a[1] and a[1].manufacturer_key), tostring(a[1] and a[1].maker_ordinal),
        tostring(a[1] and a[1].model_ordinal))
    check(a[1] and a[1].ncm_driver_id ~= nil, "and owned by the player")
    check(a[1] and tostring(a[1].paint_primary):upper():find("0B1530", 1, true), "it wears the livery's colours, not a factory roll (%s)", a[1] and tostring(a[1].paint_primary))
    local tr = a[1] and db.query(("SELECT kind FROM vehicle_asset_transfer WHERE asset_id = %s ORDER BY kind"):format(q1(a[1].asset_id))) or {}
    check(#tr == 2 and tr[1].kind == "claim" and tr[2].kind == "production", "birth certificate: production + claim transfers (%d)", #tr)
    check(app.lastClaim and app.lastClaim.assetId == (a[1] and a[1].asset_id) and app.lastClaim.serial ~= nil,
        "the deck hears the claim with its serial (%s)", app.lastClaim and tostring(app.lastClaim.serial))
    check(given[1] == "Vehicle.v_sport1_rb15_f1_kimiko", "and the car goes to V's garage (%s)", tostring(given[1]))
    local pp = a[1] and db.query(("SELECT passport_json FROM machine_passport WHERE asset_id = %s"):format(q1(a[1].asset_id)))[1]
    check(pp and pp.passport_json:find('"kimiko"', 1, true) and pp.passport_json:find("formula", 1, true),
        "its passport says: formula, livery kimiko")
    app:claim("Vehicle.v_sport1_rb15_f1_kimiko"); h:advance(3, 1)
    check(count(("SELECT COUNT(*) FROM vehicle_asset WHERE server_id = %s AND record = 'Vehicle.v_sport1_rb15_f1_kimiko'"):format(q1(t1.serverId))) == 1,
        "claiming it again gives the same machine")
    app:claim("Vehicle.v_sport1_some_nexus_car_ncm_never_saw"); h:advance(3, 1)
    local u = db.query(("SELECT vehicle_key, production_ordinal FROM vehicle_asset WHERE server_id = %s AND record = 'Vehicle.v_sport1_some_nexus_car_ncm_never_saw'"):format(q1(t1.serverId)))
    check(#u == 1 and u[1].vehicle_key == nil and u[1].production_ordinal == nil, "a car NCM never saw still becomes a machine (its own entry, no serial)")
    check(#app:garage() >= 2, "the deck's garage lists the tape's machines (%d)", #app:garage())
    app.env.game = nil

    -- ---------------------------------------------------------------------------------------------- AERO (L339)
    -- a field of one of the tape's OWN machines (whichever the garage has first: core names none), Night City -> Deep ->
    -- Hill Abode, flown by NPCs in ncm_aero on the world clock; its in-city incidents reach Race Week
    local mineKey
    for _, m in ipairs(app:garage()) do if m.vehicleKey and not mineKey then mineKey = m.vehicleKey end end
    check(mineKey ~= nil, "the garage has a catalogue machine to race (%s)", tostring(mineKey))
    local refused, whyR = app:aeroCmd("start", { vehicleKey = "archer_hella_not_owned" })
    check(refused == nil and whyR == "not_in_this_tapes_garage", "a machine that is not yours cannot start a race (%s)", tostring(whyR))
    local rateNo, whyRate = app:aeroCmd("rate", 10)
    check(rateNo == nil and whyRate == "dev_mode_off", "time-lapse is DEV only (%s)", tostring(whyRate))
    local weekFacts = 0
    h:listen("server", "ncm:week:fact", function(_, _, src) if src == "ncm_aero" then weekFacts = weekFacts + 1 end end)
    local snap = app:aeroCmd("start", { vehicleKey = mineKey, size = 6, turnAltM = 120000 })
    check(type(snap) == "table" and snap.running and #(snap.tower or {}) == 6, "a six-car %s field is on the grid (%s)", tostring(mineKey),
        type(snap) == "table" and tostring(#(snap.tower or {})) or tostring(snap))
    local maxAltKm, legs = 0, {}
    for _ = 1, 120 do
        h:advance(10, 1)
        local s = app.aero
        for _, o in ipairs((s and s.tower) or {}) do
            maxAltKm = math.max(maxAltKm, tonumber(o.altKm) or 0)
            legs[o.leg or "?"] = true
        end
        if s and s.done then break end
    end
    local s = app.aero or {}
    check(maxAltKm > 115, "the field reached Deep (%.0f km)", maxAltKm)
    check(legs.deep and legs.reentry and legs.landing, "the tower followed them up, round and home (deep %s, reentry %s, landing %s)",
        tostring(legs.deep), tostring(legs.reentry), tostring(legs.landing))
    check(s.done == true, "the race finished on the world clock (t %.0f s)", tonumber(s.t) or -1)
    local fin = 0
    for _, o in ipairs(s.tower or {}) do if o.status == "finished" then fin = fin + 1 end end
    check(fin >= 1 and s.tower[1].status == "finished", "it has a winner and a classification (%d finished)", fin)
    check(weekFacts == #(s.facts or {}), "every in-city incident reached Race Week, once (%d heard, %d reported)", weekFacts, #(s.facts or {}))
    local aeroErrs = 0
    for _, e in ipairs(h.errors) do if tostring(e.vm):find("ncm_aero", 1, true) then aeroErrs = aeroErrs + 1 end end
    check(aeroErrs == 0, "ncm_aero ran without an error (%d)", aeroErrs)
    local manifest = readFile(RES .. "ncm_aero/open77.lua") or ""
    check(manifest:find("auto_start false", 1, true) ~= nil, "ncm_aero never auto-starts (the dev server does not run it)")
end

local function errorsOf(hh, label)
    local errs = #hh.errors
    if errs > 0 then for i = 1, math.min(10, errs) do print(("    %s error %s %s: %s"):format(label, hh.errors[i].vm, hh.errors[i].label, hh.errors[i].err:sub(1, 300))) end end
    return errs
end
local function q(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end
local function count(sql) return tonumber(db.scalar(sql)) or 0 end
local function deckRow(id) for _, r in ipairs(app:tapes()) do if r.tape.id == id then return r end end end

-- ------------------------------------------------------------------------------------------------ quit, stranded
if h then
    h:advance(600, 5)
    check(errorsOf(h, "tape01") == 0, "tape 01 ran 13 minutes without an error")
    app:unmount("quit")
    check(app.world == nil, "tape 01 unmounted (the player quit)")
    app.store.doc.devMode = true
    local okS, whyS = app:dev("strand_deep")
    check(okS, "dev: the Hella left in Deep with an empty tank (%s)", tostring(whyS))
    check(count(("SELECT COUNT(*) FROM ncm_presence WHERE server_id = %s AND place = 'deep'"):format(q(t1.serverId))) == 1,
        "presence says Deep while the tape is at rest")

    -- ---------------------------------------------------------------------------------------------- 19 days, nothing runs
    clock.advance(19 * 86400 + 3600)
    local row = deckRow(t1.id)
    local p = row and row.present
    check(p and p.run >= 3, "the deck calculates a later Race Week after 19 days with nothing running (RW %s)", p and p.run or "?")
    print(("  deck after 19 days: TAPE %02d  %s  (%s)  last active %s"):format(t1.ordinal, p and p.label or "?", p and app.Tapes.remaining(p) or "?", row and row.ago or "?"))

    local okM2, whyM2 = pcall(app.mount, app, t1.id)
    check(okM2 and whyM2 == true, "tape 01 mounts again: %s", tostring(whyM2))
    h = app.world
    h:advance(30 * 60, 5)
    check(errorsOf(h, "return") == 0, "the return ran 30 minutes without an error")
    local wk = h.global.ncmWeek
    check(wk and p and wk.run == p.run, "the world's Race Week equals the deck's (world %s, deck %s)", wk and wk.run or "?", p and p.run or "?")
    local verdicts = count(("SELECT COUNT(*) FROM racing_week_verdict WHERE server_id = %s"):format(q(t1.serverId)))
    check(p and verdicts >= p.run - 1, "%d verdict(s) recorded for %d rollover(s)", verdicts, p and p.run - 1 or -1)
    local unattended = count(("SELECT COUNT(*) FROM racing_week_verdict WHERE server_id = %s AND state_json LIKE '%%unattended%%'"):format(q(t1.serverId)))
    check(unattended >= 1, "verdicts judged while nobody was there are marked unattended (%d)", unattended)
    local pres = db.query(("SELECT place, location_id FROM ncm_presence WHERE server_id = %s"):format(q(t1.serverId)))[1]
    check(pres and pres.place == "surface" and pres.location_id == "night_city_loop",
        "the stranded Hella is back in Night City after the rollover (%s / %s)", pres and pres.place or "?", pres and pres.location_id or "?")
    local collapsed = db.query(("SELECT run_index, mode, state FROM racing_week_collapse WHERE server_id = %s"):format(q(t1.serverId)))
    check(#collapsed >= 1 and collapsed[#collapsed].mode == "live", "the newest finished Week collapsed live (%d row(s))", #collapsed)
    local closes = count(("SELECT COUNT(*) FROM ledger WHERE server_id = %s AND kind = 'reconstruction_collapse'"):format(q(t1.serverId)))
    check(closes == 0, "single player keeps its money at rollover (no wallet close lines: %d)", closes)
    check(app.lastReturn and app.lastReturn.rolled >= 2, "the return is told plainly: %s rollover(s)", app.lastReturn and app.lastReturn.rolled or "none")
    local t1Runs = count(("SELECT COUNT(*) FROM racing_week_run WHERE server_id = %s"):format(q(t1.serverId)))
    local t1Week = wk and wk.run
    app:unmount("quit")

    -- ---------------------------------------------------------------------------------------------- TAPE 02: another world
    local t2 = app:newTape()
    check(t2.serverId ~= t1.serverId, "tape 02 is another server_id")
    local okM3 = pcall(app.mount, app, t2.id)
    check(okM3, "tape 02 mounts")
    app.world:advance(300, 5)
    check(errorsOf(app.world, "tape02") == 0, "tape 02 ran without an error")
    local wk2 = app.world.global.ncmWeek
    check(wk2 and wk2.run == 1, "tape 02 begins at RW 01 (%s) while tape 01 is at RW %s", wk2 and wk2.run or "?", tostring(t1Week))
    check(count(("SELECT COUNT(*) FROM racing_week_run WHERE server_id = %s"):format(q(t1.serverId))) == t1Runs,
        "tape 02 running never touched tape 01's timeline")
    check(count(("SELECT COUNT(*) FROM ncm_driver_binding WHERE server_id = %s"):format(q(t2.serverId))) == 1,
        "tape 02 has its own driver identity")
    app:unmount("quit")

    -- ---------------------------------------------------------------------------------------------- the clock goes back
    clock.set(clock.unix() - 5 * 86400)
    local okM4 = pcall(app.mount, app, t1.id)
    check(okM4 and app.clockRegressed, "a wall clock five days in the past is caught and held at last seen")
    app.world:advance(120, 5)
    local wk3 = app.world.global.ncmWeek
    check(wk3 and wk3.run >= t1Week, "tape 01 never un-rolls (RW %s, was %s)", wk3 and wk3.run or "?", tostring(t1Week))
    check(errorsOf(app.world, "regress") == 0, "no error after the regression")
    local un = app.world:unsupportedList()
    print(("  unsupported API calls over the whole run: %d distinct"):format(#un))
    for _, u in ipairs(un) do print(("    %-58s x%d"):format(u.key, u.n)) end
    app:unmount("quit")
end

-- the deck's logic (no ImGui needed): rows, the first-run explanation, NEW TAPE never touches another tape
do
    local Deck = dofile(HOST .. "ui/deck.lua")
    app.store.doc.firstRunSeen = false
    local d = Deck.new(Deck.localPort(app))
    local rows = d.rows()
    check(#rows == 4 and rows[#rows].kind == "without" and rows[#rows - 1].kind == "new", "deck rows: 2 tapes, NEW TAPE, WITHOUT NCM (%d)", #rows)
    check(rows[1].text:find("^TAPE %d%d") ~= nil and rows[1].text:find("RW %d%d") ~= nil, "a tape row leads with its Race Week: %s", rows[1].text)
    local before = #app.store.doc.tapes
    d.sel = #rows - 1
    check(d.choose() == "intro" and d.mode == "intro", "NEW TAPE on first run explains Race Week first")
    check(d.choose() == "new" and #app.store.doc.tapes == before + 1 and d.choice.kind == "tape", "BEGIN RW 01 . D1 creates the tape")
    check(Deck.WHY[1]:find("Race Weeks", 1, true) and not table.concat(Deck.WHY, " "):find("Deep"), "the explanation names Race Week and nothing hidden")
    d.sel = #d.rows()
    check(d.choose() == "without", "CYBERPUNK WITHOUT NCM is a choice")
end

-- the tape index survives a corrupt main copy (.bak)
do
    local f = io.open(tapesPath, "wb"); f:write("{ not json"); f:close()
    local again = App.new(env)
    check(#again.store.doc.tapes >= 2 and again.store.doc.recovered ~= nil, "a corrupt tape index is restored from .bak (%d tape(s))", #again.store.doc.tapes)
end

print(("host boot: %d pass, %d FAIL"):format(passes, fails))
if fails > 0 then os.exit(1) end
