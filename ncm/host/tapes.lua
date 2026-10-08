-- NCM Host: the Tape Deck's records (L338, doc 55 §5).
--
-- A TAPE is one NCM continuity: one canonical Race Week clock, one history, one `server_id` in the database (every
-- canonical row the resources write is already keyed by server_id, so two tapes are two worlds by construction).
-- It is NOT a Cyberpunk save: loading an older .dat never rewinds a tape, and starting TAPE 02 never rescues TAPE 01.
--
-- This file is the index the deck reads BEFORE any world runs: identity, clock config, and a cache of what the tape
-- looked like when it was last left (timeline rows, the live run's standing, where the player and the primary machine
-- were). The present is then CALCULATED from it -- `week.catchup` over the tape's own seed -- so the deck can say
-- "TAPE 01 · RW 13 · D2 · 18:42" without starting anything. The database stays the authority; on mount the world
-- settles the same verdicts from the same seed and standings, so the deck and the world agree.
--
-- Storage: one JSON document, written to `<path>.tmp` then renamed over `<path>` (the previous copy kept as `.bak`).
-- fs = { read(path) -> text|nil, write(path, text) -> bool, rename(a, b) -> bool, remove(path) }.
local M = { version = "0.1.0", DOC_VERSION = 1 }
M.__index = M

local DEFAULT_DAY = 86400
local BOUNDARY_SOD = 12 * 3600   -- noon US Eastern: the same day boundary as every NCM world (week.clock)

function M.open(fs, path, json)
    local s = setmetatable({ fs = fs, path = path or "save/ncm_tapes.json", json = json }, M)
    s:load()
    return s
end

function M:blank()
    return { version = M.DOC_VERSION, nextOrdinal = 1, tapes = {}, lastMounted = nil, devSkew = 0, firstRunSeen = false,
        devMode = false, recovered = nil }
end

function M:load()
    local function parse(text)
        if not text or text == "" then return nil end
        local ok, doc = pcall(self.json.decode, text)
        if ok and type(doc) == "table" and type(doc.tapes) == "table" then return doc end
        return nil
    end
    local doc = parse(self.fs.read(self.path))
    if not doc then
        local bak = parse(self.fs.read(self.path .. ".bak"))
        if bak then bak.recovered = "restored from .bak"; doc = bak end
    end
    self.doc = doc or self:blank()
    return self.doc
end

function M:save()
    local text = self.json.encode(self.doc)
    local tmp = self.path .. ".tmp"
    if not self.fs.write(tmp, text) then return false, "write_failed" end
    local cur = self.fs.read(self.path)
    if cur and cur ~= "" then self.fs.write(self.path .. ".bak", cur) end
    if self.fs.rename and self.fs.rename(tmp, self.path) then return true end
    -- no atomic rename available: write in place (the .bak above is the recovery copy)
    local ok = self.fs.write(self.path, text)
    if self.fs.remove then self.fs.remove(tmp) end
    return ok
end

local seeded = false
local function rand4()
    if not seeded then math.randomseed(os.time() + math.floor((os.clock() % 1) * 1e6)); seeded = true end
    local s = ""
    for _ = 1, 4 do s = s .. string.format("%x", math.random(0, 15)) end
    return s
end

--- A new continuity starting now: RW 01 · D1 of its own seed. Returns the tape.
function M:create(nowUnix, opts)
    opts = opts or {}
    local d = self.doc
    local ordinal = d.nextOrdinal
    d.nextOrdinal = ordinal + 1
    local id = string.format("T%02d-%s%s", ordinal, rand4(), rand4())
    local tape = {
        id = id, ordinal = ordinal, serverId = "sp-" .. id:lower(),
        epoch = math.floor(opts.epoch or nowUnix), daySeconds = opts.daySeconds or DEFAULT_DAY, boundarySod = BOUNDARY_SOD,
        created = math.floor(nowUnix), lastSeen = math.floor(nowUnix),
        label = opts.label, devAltered = opts.devAltered or false,
        cache = { runs = {}, standing = {}, location = "night_city", machine = nil, place = "surface" },
        history = {},           -- short human log: rollovers seen on return, dev actions, recoveries
    }
    d.tapes[#d.tapes + 1] = tape
    return tape
end

function M:get(id)
    for _, t in ipairs(self.doc.tapes) do if t.id == id then return t end end
    return nil
end

--- Tapes, most recently active first.
function M:list()
    local out = {}
    for _, t in ipairs(self.doc.tapes) do out[#out + 1] = t end
    table.sort(out, function(a, b) return (a.lastSeen or 0) > (b.lastSeen or 0) end)
    return out
end

function M.weekConfig(tape)
    return { epoch = tape.epoch, daySeconds = tape.daySeconds or DEFAULT_DAY, boundarySod = tape.boundarySod or BOUNDARY_SOD }
end

--- The convars a mounted tape gives the resources (week.clock.config reads these; NcmCalendar etc. read serverId
--- through tunables, which the host overrides to the same value).
function M.convars(tape)
    local boundaryHour = math.floor((tape.boundarySod or BOUNDARY_SOD) / 3600)
    return {
        ncm_server_id = tape.serverId,
        ncm_week_epoch = tostring(tape.epoch),
        ncm_week_day_seconds = tostring(tape.daySeconds or DEFAULT_DAY),
        ncm_week_boundary_hour = tostring(boundaryHour),
        ncm_week_verdict = "live",
        ncm_week_collapse = "live",
    }
end

--- The present of a tape at `nowUnix`, calculated (never simulated) from its cache. core = a host NcmCore with
--- week.catchup, week.clock, world.clock and vocabulary.hash. Returns { run, day, hours, wall, secondsRemaining,
--- rolled = runs ended since the tape was last seen, label }.
function M.present(tape, nowUnix, core)
    local Catch, Hash, WClock = core.get("week.catchup"), core.get("vocabulary.hash"), core.get("world.clock")
    local cfg = M.weekConfig(tape)
    local function seedFor(n) return Hash.key(tape.serverId, "racing-week", n) end
    local function standingFor(n)
        local d = tape.cache and tape.cache.standing and tape.cache.standing[tostring(n)]
        if d ~= nil then return { deviation = d } end
        return nil
    end
    local runs = {}
    for k, v in pairs((tape.cache and tape.cache.runs) or {}) do runs[tonumber(k)] = v end
    local p, settled = Catch.present(cfg, runs, nowUnix, seedFor, standingFor)
    if not p then return nil end
    local lastRun = tonumber(tape.cache and tape.cache.lastRun) or 1
    local e = WClock.eastern(math.floor(nowUnix))
    local sod = e.localUnix % 86400
    local wall = string.format("%02d:%02d", math.floor(sod / 3600), math.floor(sod % 3600 / 60))
    local out = { run = p.runIndex, day = p.day, hours = p.hours, wall = wall, secondsRemaining = p.secondsRemaining,
        possibleEnd = p.possibleEnd, rolled = math.max(0, p.runIndex - lastRun), settled = settled }
    out.label = M.label(out)
    return out
end

function M.label(p)
    if not p then return "BEFORE RW 01" end
    return string.format("RW %02d \194\183 D%d \194\183 %s", p.run, p.day, p.wall)
end

--- "1d 4h left" / "3h 12m left" until this Week's next possible end.
function M.remaining(p)
    local s = math.max(0, math.floor(p and p.secondsRemaining or 0))
    local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
    if d > 0 then return string.format("%dd %dh to the next possible end", d, h) end
    return string.format("%dh %02dm to the next possible end", h, m)
end

--- "2 hours ago" for the deck.
function M.ago(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds < 90 then return "just now" end
    if seconds < 5400 then return string.format("%d minutes ago", math.floor(seconds / 60 + 0.5)) end
    if seconds < 36 * 3600 then return string.format("%d hours ago", math.floor(seconds / 3600 + 0.5)) end
    return string.format("%d days ago", math.floor(seconds / 86400 + 0.5))
end

--- Record what the world looked like as the tape is left (called on unmount and periodically while mounted).
--- info = { runs = { [n] = { endUtc, endKind, survived } }, standing = { [n] = deviation }, lastRun, location, place,
---          machine = { assetId, label } }.
function M:remember(tape, nowUnix, info)
    tape.lastSeen = math.floor(nowUnix)
    tape.cache = tape.cache or {}
    if info.runs then
        local r = {}
        for k, v in pairs(info.runs) do r[tostring(k)] = { endUtc = v.endUtc, endKind = v.endKind, survived = v.survived } end
        tape.cache.runs = r
    end
    if info.standing then
        local s = {}
        for k, v in pairs(info.standing) do s[tostring(k)] = v end
        tape.cache.standing = s
    end
    for _, k in ipairs({ "lastRun", "location", "place", "machine" }) do if info[k] ~= nil then tape.cache[k] = info[k] end end
end

function M:note(tape, nowUnix, text)
    tape.history = tape.history or {}
    tape.history[#tape.history + 1] = { at = math.floor(nowUnix), text = text }
    while #tape.history > 50 do table.remove(tape.history, 1) end
end

return M
