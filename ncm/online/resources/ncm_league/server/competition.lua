-- ncm_league / server / competition — the vocabulary in the database (Batch 1; L52–L53, P42).
-- Seeds discipline/format/class/class_vehicle/ruleset from ncm-core's lists (core is the source of truth; the tables
-- make them visible to operators and stable across restarts) and answers "what rules does this event run under".
NcmCompetition = {}

local Core = NcmCore
local Discipline = Core.get("competition.discipline")
local Format = Core.get("competition.format")
local Class = Core.get("competition.class")
local Incidents = Core.get("competition.incidents")

local function log(fmt, ...) print(("[ncm_league/competition] " .. fmt):format(...)) end

local CoreJson = Core.get("vocabulary.json")
local function jsonEncode(t)
    if json and json.encode then return json.encode(t) end
    return CoreJson.encode(t)
end
NcmCompetition.jsonEncode = jsonEncode

-- Rulesets shipped by the packs (ruleset JSON = the knobs the record allows operators to change; L20).
NcmCompetition.RULESETS = {
    street_sprint_v0 = { version = 1, penalties = { jumpStartSec = 5 }, incidents = { baseSec = 2, escalation = 0.5, maxMult = 3 },
                         hold = false, prizes = { win = 0, entryFee = 0 } },
    ncx_invitational_v0 = { version = 1, penalties = { jumpStartSec = 5 }, incidents = { baseSec = 2, escalation = 0.5, maxMult = 3 },
                            hold = { releasePct = 0.75, maxWaitSec = 60 }, prizes = { win = 0, entryFee = 0 } },
}

function NcmCompetition.seed()
    if not MySQL.isReady() then return end
    local n = 0
    for _, d in ipairs(Discipline.LIST) do
        n = n + 1
        pcall(function()
            MySQL.insert.await(
                "INSERT INTO discipline (id, name, course_adapter, classifier, laps_supported, judged, enabled) VALUES (?, ?, ?, ?, ?, ?, ?) " ..
                "ON DUPLICATE KEY UPDATE name = VALUES(name), course_adapter = VALUES(course_adapter), enabled = VALUES(enabled)",
                { d.id, d.name, d.adapter == "eliminations" and "eliminations" or d.adapter, d.adapter, d.adapter == "laps" and 1 or 0, d.judged and 1 or 0, d.enabled and 1 or 0 })
        end)
    end
    for _, f in ipairs(Format.LIST) do
        pcall(function()
            MySQL.insert.await(
                "INSERT INTO format (id, name, sessions_json, enabled) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name), sessions_json = VALUES(sessions_json), enabled = VALUES(enabled)",
                { f.id, f.name, jsonEncode(f.sessions), f.enabled and 1 or 0 })
        end)
    end
    for _, c in ipairs(Class.LIST) do
        pcall(function()
            MySQL.insert.await(
                "INSERT INTO class (id, name, pack_id, top_speed_kph, accel_scale, taper_kph, enabled) VALUES (?, ?, ?, ?, ?, ?, ?) " ..
                "ON DUPLICATE KEY UPDATE name = VALUES(name), top_speed_kph = VALUES(top_speed_kph), accel_scale = VALUES(accel_scale), taper_kph = VALUES(taper_kph), enabled = VALUES(enabled)",
                { c.id, c.name, c.packId, c.topSpeedKph or 0, c.accelScale or 1, c.taperKph or 12, c.enabled and 1 or 0 })
        end)
    end
    local cv = 0
    for _, row in ipairs(Class.vehicleRows()) do
        cv = cv + 1
        pcall(function()
            MySQL.insert.await("INSERT IGNORE INTO class_vehicle (class_id, record, eligible) VALUES (?, ?, 1)", { row.classId, row.record })
        end)
    end
    for id, rs in pairs(NcmCompetition.RULESETS) do
        pcall(function()
            MySQL.insert.await("INSERT INTO ruleset (id, version, json) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE version = VALUES(version), json = VALUES(json)",
                { id, rs.version or 1, jsonEncode(rs) })
        end)
    end
    log("vocabulary seeded: %d disciplines, %d formats, %d classes, %d class vehicles, %d rulesets", n, #Format.LIST, #Class.LIST, cv, 2)
end

--- The ruleset table for an id (core copy; the DB row is a mirror for operators until an editor exists).
function NcmCompetition.ruleset(id)
    return NcmCompetition.RULESETS[id] or NcmCompetition.RULESETS.street_sprint_v0
end

--- Race-kernel rules for an event: hold policy + incident bands from the discipline + ruleset knobs.
function NcmCompetition.rulesFor(e)
    local rs = NcmCompetition.ruleset(e.rulesetId)
    local inc = Incidents.rules(Discipline.incidentRules(e.disciplineId or "street_sprint"))
    for k, v in pairs(rs.incidents or {}) do inc[k] = v end
    local rules = { incidents = inc }
    if rs.penalties and rs.penalties.jumpStartSec then rules.jumpPenaltySec = rs.penalties.jumpStartSec end
    local hold = (e.class == "organized") and rs.hold or false
    if type(hold) == "table" then
        rules.hold = true
        rules.holdReleasePct = hold.releasePct or 0.75
        rules.holdMaxWaitSec = hold.maxWaitSec or 60
    end
    -- Rolling start (Batch 2): the event says so (`rolling` on the post), else the ruleset, else lap disciplines roll by default (P41)
    local d = Discipline.byId(e.disciplineId or "street_sprint")
    local start = e.startType or (rs.start) or ((d and d.adapter == "laps") and "rolling" or "standing")
    rules.start = start
    if start == "rolling" then
        rules.formationM = tonumber(e.formationM) or (rs.formationM) or 300
        rules.paceKph = tonumber(e.paceKph) or (rs.paceKph) or 80
    end
    return rules
end

-- IDEA-113/L83: the machinery a series admits. Series carry an `eligibility` spec (competition.eligibility);
-- absent means "open", which is what the street series are. Looked up by seriesId so an event needs to carry
-- nothing extra.
local Eligibility = Core.get("competition.eligibility")

local function seriesById(seriesId)
    for _, pack in ipairs({ NcmPackStreet }) do
        for _, s in ipairs(pack and pack.series or {}) do
            if s.seriesId == seriesId then return s end
        end
    end
    return nil
end

--- The eligibility spec for an event, or an empty (open) spec.
function NcmCompetition.eligibilityFor(e)
    local s = e and e.seriesId and seriesById(e.seriesId) or nil
    return (s and s.eligibility) or {}
end

--- Can this driver field a legal car for this event? Returns nil when they can, or a reason slug when they
--- cannot (L83: refusal, never substitution). A ledger that cannot be read returns nil -- "we could not ask" is
--- not "no", and locking someone out on a database hiccup would look exactly like a progression bug.
function NcmCompetition.carRefusal(e, driverId)
    if not driverId or not NcmOwnership then return nil end
    -- `records`, not `list`: since IDEA-157 a garage holds physical examples, and two of one legal car is one
    -- option to a championship, not two. `list` would hand duplicates straight to the eligibility count.
    local ids = NcmOwnership.records(driverId)
    local decision = Eligibility.check(NcmCompetition.eligibilityFor(e), ids)
    if decision.ok then return nil end
    return decision.reason, decision.admits
end

--- The performance ceiling to apply at issue time for an event's class (nil = none).
function NcmCompetition.performanceFor(e)
    return Class.performance(e and e.classId or "street_open")
end

-- KB-30 / D7: the ceiling existed as data and was never applied -- `performanceFor` had no caller and
-- `setPerformance` appeared nowhere in NCM, which is why the RB15 still hit its cliff. Two facts from the
-- platform's own governor notes shape this: the cap is **client-local** (it clamps a throttle float inside the
-- client simulating the car, so it is balance, not anti-cheat), and it must reach **every client and every
-- joiner**. GlobalState does both by construction, so the ceilings are published once and each client applies
-- them for itself -- no broadcast to write, no join replay to forget.
function NcmCompetition.publishCeilings()
    local ceilings = Class.recordCeilings()
    local n = 0
    for _ in pairs(ceilings) do n = n + 1 end
    GlobalState.ncmCeilings = { records = ceilings, at = math.floor(Open77.time.unix()) }
    log("class ceilings published: %d record(s)", n)
end
