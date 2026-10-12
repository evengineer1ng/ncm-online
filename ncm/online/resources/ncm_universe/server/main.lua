-- ncm_universe / server / main -- the astronomical substrate on the server, SHADOW MODE (doc 57 §5).
--
-- READ-ONLY. It loads the catalogue (incrementally: OPEN//77 meters instructions per call), reads every Deep record
-- from ncm_presence (SELECT only), and answers questions about them. It never writes a record, never steers, never
-- changes gravity: the Galena and the Hella fly exactly as before (owner brief §10). Totals it keeps (distance
-- travelled, max distance from home) live in memory from this server start; persisting them is a later step.
--
-- Ask it (server console / RCON / Warden console; players may ask the read-only ones in chat with a leading `/`):
--   ncm.astro.where <driver name | id prefix | vehicle key>   where is it, astronomically (the full report)
--   ncm.astro.pulls <same>                                    what is pulling on it, from the universe
--   ncm.astro.near <body id | hip:N | x y z au|ly|pc> [radius au|ly|pc]   what is around a point
--   ncm.astro.body <id | hip:N>                               where is that body now
--   ncm.astro.test <ra deg> <dec deg> <distance> <au|ly|pc>   place a VIRTUAL vehicle there (no record) and report it
--   ncm.astro.status                                          loading progress and what is being watched
local Core = NcmCore
local A = Core.get("space.astro")
local Cat = Core.get("space.catalogue")
local G = Core.get("space.gravity")
local T = Core.get("space.telemetry")
local Json = Core.get("vocabulary.json")
local V = A.vec

local function log(fmt, ...) print(("[ncm_universe] " .. fmt):format(...)) end
local function now() return (Open77.time and Open77.time.unix and Open77.time.unix()) or math.floor(GetGameTimer() / 1000) end

local loadingText, ready = "not started", false
local vehicles = {}          -- driverId -> { rec, name, rep, acc }
local lastScan = 0

-- ------------------------------------------------------------------------------------------------- formatting
local function dist(m)
    m = math.abs(m)
    if m >= 0.05 * A.LY then return ("%.4g ly"):format(m / A.LY) end
    if m >= 0.01 * A.AU then return ("%.4g AU"):format(m / A.AU) end
    if m >= 10000 then return ("%s km"):format(("%.0f"):format(m / 1000):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")) end
    return ("%.1f m"):format(m)
end
local function speed(v) return math.abs(v) >= 1000 and ("%.3f km/s"):format(v / 1000) or ("%.1f m/s"):format(v) end

local function reportLines(name, rep)
    local o = {}
    local w = rep.where
    o[#o + 1] = ("%s -- %s from the Sun (%s), RA %.3f Dec %+.3f, galactic l %.2f b %+.2f; cell (%d,%d,%d)"):format(
        name, dist(w.helioM), w.helioLY >= 0.01 and ("%.4f ly"):format(w.helioLY) or ("%.5f AU"):format(w.helioAU),
        w.raDeg, w.decDeg, w.galLDeg, w.galBDeg, w.cell[1], w.cell[2], w.cell[3])
    o[#o + 1] = ("  speed %s (heliocentric inertial); system: %s; sphere of influence: %s"):format(
        speed(rep.velocity.speed), rep.system.name, rep.soi.name)
    local h = rep.home
    o[#o + 1] = ("  from %s: %s (altitude %s), %s, radial %s"):format(h.name, dist(h.distanceM), dist(h.altitudeM or 0),
        speed(h.relSpeed), (h.radialV >= 0 and "+" or "-") .. speed(math.abs(h.radialV)))
    local ob = rep.soi.orbit
    if ob.bound and ob.impacts then
        o[#o + 1] = ("  about %s: BOUND and coming back -- coasts out to %s from its centre, then falls back to %s"):format(
            rep.soi.name, dist(ob.apoM), rep.soi.name)
    elseif ob.bound then
        o[#o + 1] = ("  about %s: BOUND, e %.4f, apoapsis %s, periapsis %s, period %.2f d"):format(rep.soi.name, ob.e,
            dist(ob.apoM), dist(ob.periM), ob.periodS / 86400)
    else
        o[#o + 1] = ("  about %s: UNBOUND (escape %s at this distance), keeps %s forever"):format(rep.soi.name,
            speed(ob.escapeV), speed(ob.vInf))
    end
    local near = {}
    for i, n in ipairs(rep.nearest) do if i <= 5 then near[#near + 1] = ("%s %s"):format(n.name, dist(n.distanceM)) end end
    o[#o + 1] = "  nearest: " .. table.concat(near, " | ")
    return o
end

local function pullLines(name, rep)
    local o = { ("%s is pulled by %d relevant bodies (net %.4g m/s^2; pulls in different directions partly cancel):"):format(
        name, #rep.pulls, rep.totalAcc) }
    for _, p in ipairs(rep.pulls) do
        o[#o + 1] = ("  %-22s %.4g m/s^2  at %s"):format(p.name, p.acc, dist(p.distanceM))
    end
    o[#o + 1] = ("  felt in its own frame (centred on %s, third-body form): %.4g m/s^2"):format(rep.frameAcc.body, rep.frameAcc.acc)
    return o
end

local function out(source, lines)
    for _, l in ipairs(lines) do
        if (tonumber(source) or 0) > 0 then pcall(Open77.chat.send, source, l) else log("%s", l) end
    end
end

-- ------------------------------------------------------------------------------------------------- the records
local function scan()
    if not (MySQL and MySQL.isReady and MySQL.isReady()) then return end
    local sid = (GlobalState.ncmIdentity and GlobalState.ncmIdentity.serverId) or "ncm-dev"
    local rows = MySQL.query.await([[SELECT p.driver_id, p.state_json, d.display FROM ncm_presence p
        LEFT JOIN driver_profile d ON d.ncm_driver_id = p.driver_id WHERE p.server_id = ? AND p.place = 'deep']], { sid }) or {}
    local seen = {}
    for _, r in ipairs(rows) do
        local ok, rec = pcall(Json.decode, r.state_json or "")
        if ok and type(rec) == "table" and rec.p then
            local v = vehicles[r.driver_id] or { acc = {} }
            v.rec, v.name = rec, ("%s's %s"):format(tostring(r.display or r.driver_id:sub(1, 8)), tostring(rec.vehicleKey or "machine"))
            -- 2026-10-12 (doc 58): each vehicle in its own tick -- a full report among the stars (the Hella at Barnard's
            -- Star) can spend a whole call's instruction quota, and it took the next vehicle's report down with it
            Wait(0)
            local okR, st = pcall(T.fromDeep, rec)
            v.light = nil
            if okR then
                local okP, rep = pcall(T.report, st)
                if okP then v.rep = rep; T.accumulate(v.acc, st, rep)
                else
                    -- never print a stale report: a light line (distances only) instead
                    v.rep = nil
                    if not v.warned then v.warned = true; log("full report unavailable for %s (%s): light ASTRO lines instead", v.name, tostring(rep)) end
                    Wait(0)
                    local okL, light = pcall(function()
                        local A = NcmCore.get("space.astro")
                        local p = st.pos
                        return { sun = A.distance(p, A.ORIGIN), earth = A.distance(p, (Cat.stateAt("earth", st.utc or now()))) }
                    end)
                    if okL then v.light = light end
                end
            end
            vehicles[r.driver_id] = v
            seen[r.driver_id] = true
        end
    end
    for id in pairs(vehicles) do if not seen[id] then vehicles[id] = nil end end
    lastScan = now()
end

local function find(text)
    text = tostring(text or ""):lower()
    if text == "" then return nil end
    for id, v in pairs(vehicles) do
        if id:sub(1, #text) == text or v.name:lower():find(text, 1, true) or tostring(v.rec.vehicleKey):lower():find(text, 1, true) then
            return v
        end
    end
    return nil
end

-- ------------------------------------------------------------------------------------------------- commands
local UNIT = { au = A.AU, ly = A.LY, pc = A.PC, km = 1000, m = 1 }

local function where(source, args)
    if not ready then return out(source, { "the universe is still loading: " .. loadingText }) end
    scan()
    local v = find(table.concat(args or {}, " "))
    if not v then
        local names = {}
        for _, x in pairs(vehicles) do names[#names + 1] = x.name end
        return out(source, { "no Deep vehicle matches. In Deep now: " .. (#names > 0 and table.concat(names, ", ") or "nobody") })
    end
    local lines = reportLines(v.name, v.rep)
    lines[#lines + 1] = ("  travelled %s and max %s from home (since this server start)"):format(dist(v.acc.travelledM or 0), dist(v.acc.maxFromHomeM or 0))
    out(source, lines)
end

local function pulls(source, args)
    if not ready then return out(source, { "the universe is still loading: " .. loadingText }) end
    scan()
    local v = find(table.concat(args or {}, " "))
    if not v then return out(source, { "no Deep vehicle matches" }) end
    out(source, pullLines(v.name, v.rep))
end

local function parsePoint(args)
    -- <id> | <x y z unit>
    if #args >= 4 and tonumber(args[1]) then
        local u = UNIT[tostring(args[4]):lower()] or A.AU
        return A.pos(tonumber(args[1]) * u, tonumber(args[2]) * u, tonumber(args[3]) * u), ("(%s %s %s %s)"):format(args[1], args[2], args[3], args[4]), 5
    end
    local rec = Cat.get(args[1] or "")
    if rec then return (Cat.stateAt(rec, now())), rec.name, 2 end
    return nil
end

local function near(source, args)
    if not ready then return out(source, { "the universe is still loading: " .. loadingText }) end
    local pos, label, nextArg = parsePoint(args or {})
    if not pos then return out(source, { "usage: ncm.astro.near <body id | hip:N | x y z au|ly|pc> [radius au|ly|pc]" }) end
    local r = (tonumber(args[nextArg]) or 1) * (UNIT[tostring(args[nextArg + 1] or "ly"):lower()] or A.LY)
    local hits = Cat.near(pos, r, now())
    local o = { ("%d objects within %s of %s:"):format(#hits, dist(r), label) }
    for i, h in ipairs(hits) do
        if i > 15 then break end
        o[#o + 1] = ("  %-24s %-12s %s"):format(h.rec.name, h.rec.kind, dist(h.d))
    end
    local sys = Cat.system(pos, now())
    o[#o + 1] = ("  system there: %s"):format(sys.name)
    out(source, o)
end

local function body(source, args)
    if not ready then return out(source, { "the universe is still loading: " .. loadingText }) end
    local rec = Cat.get(args and args[1] or "")
    if not rec then return out(source, { "no such body (try: sun, earth, moon, mars, jupiter, io, titan, sgr_a_star, hip:70890)" }) end
    local p, v = Cat.stateAt(rec, now())
    local m = A.metres(p)
    local ra, dec = A.toRadec(m)
    local home = G.home()
    local hp = Cat.stateAt(home, now())
    out(source, { ("%s (%s): %s from the Sun, %s from %s, RA %.3f Dec %+.3f, speed %s; GM %.6g m^3/s^2, radius %s; source: %s"):format(
        rec.name, rec.kind, dist(A.distance(p, A.ORIGIN)), dist(A.distance(p, hp)), home.name, ra, dec, speed(V.len(v)),
        rec.gm or 0, dist(rec.radius or 0), table.concat(rec.provenance or {}, "; ")) })
end

local function test(source, args)
    if not ready then return out(source, { "the universe is still loading: " .. loadingText }) end
    local ra, dec, d = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if not (ra and dec and d) then return out(source, { "usage: ncm.astro.test <ra deg> <dec deg> <distance> <au|ly|pc>" }) end
    local u = UNIT[tostring(args[4] or "ly"):lower()] or A.LY
    local m = V.scale(A.radec(ra, dec), d * u)
    local st = { utc = now(), pos = A.pos(m[1], m[2], m[3]), vel = { 0, 0, 0 }, frame = { kind = "inertial" } }
    local rep = T.report(st)
    local lines = reportLines(("VIRTUAL vehicle at RA %.2f Dec %.2f, %s %s"):format(ra, dec, args[3], args[4] or "ly"), rep)
    for _, l in ipairs(pullLines("  it", rep)) do lines[#lines + 1] = l end
    local q = A.offset(st.pos, { 1, 0, 0 })
    lines[#lines + 1] = ("  precision there: a 1 m step reads %.9f m"):format(A.distance(q, st.pos))
    out(source, lines)
end

local function status(source)
    local n = 0
    for _ in pairs(vehicles) do n = n + 1 end
    out(source, { ("universe: %s; %d bodies registered, %d stars; watching %d Deep vehicle(s); last scan %d s ago (shadow mode: read-only)"):format(
        ready and "ready" or ("loading -- " .. loadingText), #Cat.list(), Cat.starCount(), n, now() - lastScan) })
end

for name, fn in pairs({ ["ncm.astro.where"] = where, ["ncm.astro.pulls"] = pulls, ["ncm.astro.near"] = near,
                        ["ncm.astro.body"] = body, ["ncm.astro.test"] = test, ["ncm.astro.status"] = status }) do
    RegisterCommand(name, function(source, args) local ok, err = pcall(fn, source, args or {}); if not ok then log("%s failed: %s", name, tostring(err)) end end, false)
end

-- ------------------------------------------------------------------------------------------------- threads
CreateThread(function()
    log("loading the universe (shadow mode, read-only)")
    while true do
        local ok, done, text = pcall(Cat.loadStep)
        if not ok then log("load FAILED: %s", tostring(done)); loadingText = "failed"; return end
        loadingText = text or loadingText
        if done then break end
        Wait(0)
    end
    ready = true
    log("universe ready: %d bodies, %d stars", #Cat.list(), Cat.starCount())
    while true do
        local ok, err = pcall(scan)
        if not ok then log("scan failed: %s", tostring(err)) end
        for _, v in pairs(vehicles) do
            if not v.rep and v.light then
                local L = v.light
                log("ASTRO %s: %s from Earth, %s from the Sun (light report: the full one is over the instruction quota out here)", v.name,
                    L.earth >= 9.4607e14 and ("%.4f ly"):format(L.earth / 9.4607e15) or dist(L.earth),
                    L.sun >= 9.4607e14 and ("%.4f ly"):format(L.sun / 9.4607e15) or ("%.5f AU"):format(L.sun / 1.495978707e11))
            end
            if v.rep then
                local r = v.rep
                log("ASTRO %s: %s from %s, %s %s, %s; strongest pull %s; %s", v.name, dist(r.home.distanceM), r.home.name,
                    speed(r.home.relSpeed), r.home.radialV >= 0 and "outward" or "inward", r.soi.orbit.bound and "bound" or "unbound",
                    r.pulls[1] and r.pulls[1].name or "-", r.where.helioLY >= 0.01 and ("%.4f ly from the Sun"):format(r.where.helioLY) or ("%.5f AU from the Sun"):format(r.where.helioAU))
            end
        end
        Wait(60000)
    end
end)
