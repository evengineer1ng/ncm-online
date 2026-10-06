-- ncm_ls_space / server / link: the Snowglobe hub -- the cross-server link between Night City and Los Santos
-- (L323; doc 52 §2, doc 54 §S). Dev topology: both servers run on this PC; the hub lives here, on the FiveM server's
-- own HTTP endpoint (`http://127.0.0.1:30120/ncm_ls_space/...`), and the Night City dev server calls it with its
-- allow-listed outbound HTTP (resource `ncm_link`). LOOPBACK ONLY: anything not from 127.0.0.1 / ::1 is refused --
-- a token and TLS come before this ever leaves the PC (doc 54 §Q).
--
-- What crosses (`world.link`, committed as `world.seed` history in this resource's KVP):
--   identity     a link code issued in one world and claimed in the other joins `ncmDriverId` (NC) and the FiveM
--                license (LS) into one NCM driver -- consensual, in-game, single-use, ten minutes
--   discovery    the domains a driver has legitimately reached (LS on first race / claim; Snowglobe at the doorway or
--                a Snowglobe event)
--   legs         finished races from both servers, as candidate legs for the THREE CITIES event (cross-domain
--                triathlon, `space.multievent`), scored per Race Week; visible only to drivers who discovered all three
--   facts        each world's Race Week evidence, exchanged and LOGGED, never shown (doc 52 §5: the link starts invisible)
local Core = NcmCore
local Seed = Core.get("world.seed")
local Link = Core.get("world.link")
local C = NcmLsConfig

local function log(fmt, ...) print(("[ncm_ls_space/link] " .. fmt):format(...)) end

local KVP = "ncm_link_mods:" .. C.universeSeed
local mods = {}
do
    local raw = GetResourceKvpString(KVP)
    if raw and raw ~= "" then mods = json.decode(raw) or {} end
end
local state = Seed.compose(Link.base(), mods)
local codes = {}                 -- ephemeral
local week = nil                 -- the Race Week number Night City last reported
local ncFacts = {}

local function commit(list)
    if not list then return end
    if list.path then list = { list } end
    for _, m in ipairs(list) do mods[#mods + 1] = m end
    SetResourceKvp(KVP, json.encode(mods))
    state = Seed.compose(Link.base(), mods)
end

local function weekNow() return week or math.floor(os.time() / (7 * 86400)) end

local function licenseOf(src)
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 8) == "license:" then return id end
    end
    return nil
end

NcmLsLink = {}

--- A finished LS or Snowglobe race (from server/events.lua): a leg and a discovery, for a linked driver.
function NcmLsLink.result(src, ev, row)
    local lic = licenseOf(src)
    local driver = lic and Link.driverOf(state, "los_santos", lic)
    if not driver then return end
    local domain = ev.venueInfo.domain == "snowglobe" and "snowglobe" or "los_santos"
    local at = os.time()
    commit(Link.legMod(state, driver, { domain = domain, week = weekNow(), venue = ev.venueInfo.name, position = row.position,
        raceS = row.raceS, state = row.state, at = at }, at))
    commit(Link.discover(state, driver, domain, at))
    log("leg: driver %s -- %s P%s %s (week %d)", driver:sub(1, 8), ev.venueInfo.name, tostring(row.position),
        row.raceS and ("%.3f s"):format(row.raceS) or tostring(row.state), weekNow())
end

--- A linked player went through the doorway: Snowglobe discovered.
function NcmLsLink.discoverDomain(src, domain)
    local lic = licenseOf(src)
    local driver = lic and Link.driverOf(state, "los_santos", lic)
    if not driver then return end
    local m = Link.discover(state, driver, domain, os.time())
    if m then commit(m); log("discovery: driver %s reached %s", driver:sub(1, 8), domain) end
end
function NcmLsLink.discover() end    -- events.lua's per-entry hook: discovery happens on results and the doorway

-- ------------------------------------------------------------------------------------------ in game
RegisterNetEvent("ncm:ls:link:claim", function(code)
    local src = source
    local lic = licenseOf(src)
    if not lic then TriggerClientEvent("ncm:ls:say", src, "link: no FiveM license identifier"); return end
    local list, driver = Link.claim(codes, state, code, "los_santos", lic, os.time(), os.time())
    if not list then
        TriggerClientEvent("ncm:ls:say", src, "link refused: " .. tostring(driver))
        log("claim from player %d refused: %s", src, tostring(driver))
        return
    end
    commit(list)
    log("LINKED: NCM driver %s = night_city %s = los_santos %s", driver, tostring(state.links[Link.key(driver)].night_city), lic)
    TriggerClientEvent("ncm:ls:say", src, "Linked: you are one NCM driver in Night City and Los Santos now.")
end)

RegisterNetEvent("ncm:ls:link:tri", function()
    local src = source
    local lic = licenseOf(src)
    local driver = lic and Link.driverOf(state, "los_santos", lic)
    local ev = Link.threeCities(weekNow())
    if not driver or not Link.visible(state, driver, ev) then
        TriggerClientEvent("ncm:ls:say", src, "Nothing here.")        -- discovery: no spoiler, not even a hint
        return
    end
    local rows = Link.scoreThreeCities(state, ev, weekNow())
    TriggerClientEvent("ncm:ls:say", src, ("THREE CITIES -- Race Week %d (%s)"):format(weekNow(), ev.format))
    for _, r in ipairs(rows) do
        TriggerClientEvent("ncm:ls:say", src, ("  P%d %s%s | %d/3 legs | %d pts"):format(r.position, r.id:sub(1, 8),
            r.id == driver and " (you)" or "", r.legs, r.points))
    end
end)

-- ------------------------------------------------------------------------------------------ HTTP (loopback only)
local function loopback(addr)
    addr = tostring(addr or "")
    return addr:find("^127%.0%.0%.1") or addr:find("^%[::1%]") or addr:find("^::1") or addr:find("^%[::ffff:127%.0%.0%.1%]")
        or addr:find("^::ffff:127%.0%.0%.1")
end

local function reply(res, code, body)
    res.writeHead(code, { ["Content-Type"] = "application/json" })
    res.send(json.encode(body))
end

local ROUTES = {}
ROUTES["GET /health"] = function() return 200, { ok = true, links = #mods, week = weekNow() } end
ROUTES["POST /link/code"] = function(b)
    if type(b.driverId) ~= "string" or #b.driverId < 8 then return 400, { error = "driverId" } end
    local code = Link.issue(codes, b.driverId, "night_city", tostring(b.identity or ""), os.time(), tostring(b.nonce or ""))
    log("code issued for NC driver %s (%s)", b.driverId:sub(1, 8), tostring(b.display or "?"))
    return 200, { code = code, ttl = Link.CODE_TTL_S }
end
ROUTES["POST /facts"] = function(b)
    if b.week then week = tonumber(b.week) end
    ncFacts = b.facts or {}
    local sg = NcmSnowglobe and NcmSnowglobe.facts and NcmSnowglobe.facts() or {}
    log("facts in from Night City (week %s): %s | out: snowglobe race %s crash %s (hidden)", tostring(week), json.encode(ncFacts),
        tostring(sg.race), tostring(sg.race_crash))
    return 200, { week = weekNow(), los_santos = {}, snowglobe = sg }
end
ROUTES["POST /results"] = function(b)
    if type(b.driverId) ~= "string" or type(b.leg) ~= "table" then return 400, { error = "driverId/leg" } end
    local leg = b.leg
    leg.domain, leg.week = "night_city", tonumber(leg.week) or weekNow()
    commit(Link.legMod(state, b.driverId, leg, os.time()))
    log("leg in from Night City: driver %s %s P%s", b.driverId:sub(1, 8), tostring(leg.venue), tostring(leg.position))
    return 200, { ok = true }
end
ROUTES["POST /driver"] = function(b)
    local k = Link.key(b.driverId or "")
    local ev = Link.threeCities(weekNow())
    local visible = Link.visible(state, b.driverId or "", ev)
    local out = { linked = state.links[k] ~= nil, discovered = state.discovered[k] or {}, legs = state.legs[k] and #state.legs[k] or 0 }
    if visible then
        for _, r in ipairs(Link.scoreThreeCities(state, ev, weekNow())) do
            if r.id == b.driverId then out.threeCities = { position = r.position, points = r.points, legs = r.legs } end
        end
    end
    return 200, out
end

SetHttpHandler(function(req, res)
    if not loopback(req.address) then
        log("refused HTTP %s %s from %s (loopback only)", tostring(req.method), tostring(req.path), tostring(req.address))
        return reply(res, 403, { error = "loopback only" })
    end
    local function handle(body)
        local key = tostring(req.method) .. " " .. tostring(req.path):gsub("^/ncm_ls_space", ""):gsub("%?.*$", "")
        local fn = ROUTES[key]
        if not fn then return reply(res, 404, { error = "no route " .. key }) end
        local ok, b = pcall(json.decode, body or "")
        local okRun, code, out = pcall(fn, (ok and type(b) == "table") and b or {})
        if not okRun then log("route %s failed: %s", key, tostring(code)); return reply(res, 500, { error = "internal" }) end
        reply(res, code, out)
    end
    if req.method == "POST" then req.setDataHandler(handle) else handle("") end
end)

CreateThread(function()
    Wait(2000)
    local n = 0
    for _ in pairs(state.links) do n = n + 1 end
    log("hub up on /ncm_ls_space (loopback only): %d linked driver(s), %d mod(s)", n, #mods)
end)
