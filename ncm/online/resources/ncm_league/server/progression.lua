-- ncm_league / server / progression — driver dimensions v0 (L54): licence per discipline, SR badge, rating
-- skeleton, accomplishments. Applied after every race session's classification; nothing here gates entry.
NcmProgression = {}

local Core = NcmCore
local P = Core.get("driver.progression")

local function log(fmt, ...) print(("[ncm_league/progression] " .. fmt):format(...)) end
local now = function() return Open77.time.unix() end
local function serverId() return tostring((NcmCalendar and NcmCalendar.serverId and NcmCalendar.serverId()) or "ncm-dev") end
local function tell(pid, text) if pid then pcall(Open77.chat.send, pid, "[NCM] " .. text) end end
local BADGE_REWARDS = { first_finish = 100, first_time_trial = 100, first_win = 300 }

--- Load a driver's dimension state from the tables (defaults when absent).
function NcmProgression.load(driverId)
    local st = P.newState()
    if not MySQL.isReady() then return st end
    pcall(function()
        local sid = serverId()
        for _, r in ipairs(MySQL.query.await("SELECT discipline_id, level, clean_sessions FROM driver_licence WHERE ncm_driver_id = ? AND server_id = ?", { driverId, sid }) or {}) do
            st.licences[r.discipline_id] = { level = r.level, clean = tonumber(r.clean_sessions) or 0 }
        end
        local sr = MySQL.single.await("SELECT sr, incidents, clean_sessions FROM driver_sr WHERE ncm_driver_id = ? AND server_id = ?", { driverId, sid })
        if sr then st.sr = { sr = tonumber(sr.sr) or 5.0, incidents = tonumber(sr.incidents) or 0, clean = tonumber(sr.clean_sessions) or 0 } end
        for _, r in ipairs(MySQL.query.await("SELECT class_id, rating, sessions FROM driver_rating WHERE ncm_driver_id = ? AND server_id = ?", { driverId, sid }) or {}) do
            st.ratings[r.class_id] = { rating = tonumber(r.rating) or 1000, sessions = tonumber(r.sessions) or 0 }
        end
        for _, r in ipairs(MySQL.query.await("SELECT kind, ref_id, at FROM accomplishment WHERE ncm_driver_id = ? AND server_id = ?", { driverId, sid }) or {}) do
            st.accomplishments[#st.accomplishments + 1] = { kind = r.kind, refId = r.ref_id, at = tonumber(r.at) }
        end
    end)
    return st
end

local function save(driverId, st, newAcc, t)
    if not MySQL.isReady() then return false,"database_not_ready" end
    local sid = serverId()
    local ok,err=pcall(function()
        for disc, lic in pairs(st.licences) do
            MySQL.insert.await(
                "INSERT INTO driver_licence (ncm_driver_id, server_id, discipline_id, level, clean_sessions, earned_at) VALUES (?, ?, ?, ?, ?, ?) " ..
                "ON DUPLICATE KEY UPDATE level = VALUES(level), clean_sessions = VALUES(clean_sessions), earned_at = VALUES(earned_at)",
                { driverId, sid, disc, lic.level, lic.clean, math.floor(t) })
        end
        MySQL.insert.await(
            "INSERT INTO driver_sr (ncm_driver_id, server_id, sr, incidents, clean_sessions, updated_at) VALUES (?, ?, ?, ?, ?, ?) " ..
            "ON DUPLICATE KEY UPDATE sr = VALUES(sr), incidents = VALUES(incidents), clean_sessions = VALUES(clean_sessions), updated_at = VALUES(updated_at)",
            { driverId, sid, st.sr.sr, st.sr.incidents, st.sr.clean, math.floor(t) })
        for cid, rt in pairs(st.ratings) do
            MySQL.insert.await(
                "INSERT INTO driver_rating (ncm_driver_id, server_id, class_id, rating, sessions) VALUES (?, ?, ?, ?, ?) " ..
                "ON DUPLICATE KEY UPDATE rating = VALUES(rating), sessions = VALUES(sessions)",
                { driverId, sid, cid, rt.rating, rt.sessions })
        end
        for _, a in ipairs(newAcc or {}) do
            MySQL.insert.await("INSERT IGNORE INTO accomplishment (ncm_driver_id, server_id, kind, ref_kind, ref_id, at) VALUES (?, ?, ?, 'session', ?, ?)",
                { driverId, sid, a.kind, a.refId or "", math.floor(t) })
        end
        -- keep the profile's SR JSON (Driver.publicView) in step with the badge
        MySQL.update.await("UPDATE driver_profile SET sr = JSON_SET(COALESCE(sr, '{}'), '$.sr', ?, '$.incidents', ?) WHERE ncm_driver_id = ? AND server_id = ?",
            { st.sr.sr, st.sr.incidents, driverId, sid })
    end)
    return ok,err
end

--- After a race session completes: every classified driver's dimensions move.
function NcmProgression.apply(rec, results, t)
    local e = rec.plan and rec.plan.e or {}
    -- distanceM feeds the SR gain (exposure earns the badge): the built course length already includes laps,
    -- and the event's route distance is the fallback for a session that never built one.
    local ctx = { disciplineId = e.disciplineId or rec.disciplineId or "street_sprint", classId = e.classId or "street_open", sessionKind = rec.kind, fieldSize = #results, sessionId = rec.s.sessionId, now = t,
                  distanceM = (rec.course and tonumber(rec.course.lengthM)) or tonumber(e.distanceM) }
    for _, r in ipairs(results) do
        local st = NcmProgression.load(r.driverId)
        local before = st.sr.sr
        local newSt, deltas, newAcc = P.apply(st, r, ctx)
        local saved,saveWhy = save(r.driverId, newSt, newAcc, t)
        local pid = rec.playerOf and rec.playerOf[r.driverId]
        for _, a in ipairs(newAcc) do
            local amount = BADGE_REWARDS[a.kind]
            if amount and saved and NcmEconomy then
                local ok, balance = NcmEconomy.reward(r.driverId, "badge_reward", amount,
                    ("badge:%s:%s:unique:%s"):format(r.driverId, a.kind, serverId()),
                    { ref=a.kind, note="Badge: "..a.kind:gsub("_"," "), sessionId=ctx.sessionId })
                if ok and pid then
                    local label=a.kind:gsub("_"," "):gsub("(%a)([%w']*)",function(x,rest)return x:upper()..rest end)
                    NcmComms.send(pid,{id="badge.earned:"..a.kind,category="milestone",priority="informative",
                        title="BADGE EARNED · "..string.upper(label),
                        message=("+€$%d · balance €$%d · the mark is now in your Driver File"):format(amount,balance or 0),
                        reference="driver",surface="both",repeatPolicy={mode="once"}})
                end
            end
        end
        if not saved then log("driver=%s progression save failed; badge money withheld: %s",r.driverId:sub(1,8),tostring(saveWhy)) end
        local lic = newSt.licences[ctx.disciplineId]
        log("driver=%s sr %.2f -> %.2f licence %s (%d clean) accomplishments +%d", r.driverId:sub(1, 8), before, newSt.sr.sr, lic and lic.level or "-", lic and lic.clean or 0, #newAcc)
        if pid then
            local bits = {}
            for _, d in ipairs(deltas) do
                if d.kind == "sr" then bits[#bits + 1] = ("SR %+.2f → %.2f"):format(d.delta, d.sr)
                elseif d.kind == "licence_level" then bits[#bits + 1] = ("licence: %s %s"):format(d.disciplineId, string.upper(d.level))
                elseif d.kind == "licence_clean" then bits[#bits + 1] = ("clean sessions: %d"):format(d.clean) end
            end
            for _, a in ipairs(newAcc) do bits[#bits + 1] = "★ " .. a.kind:gsub("_", " ") end
            if #bits > 0 then tell(pid, "Driver profile: " .. table.concat(bits, " · ")) end
        end
    end
end

local function describeFor(pid)
    local driver = NcmCalendar.resolveDriver(pid)
    if not driver then return "No NCM driver on this session." end
    return P.describe(NcmProgression.load(driver.ncmDriverId))
end

RegisterCommand("ncm.profile", function(source, args)
    local caller = tonumber(source) or 0
    if caller > 0 then tell(caller, describeFor(caller)); return end
    local pid = tonumber(args and args[1])
    if not pid then log("usage: ncm.profile <playerId>"); return end
    log("profile player=%d: %s", pid, describeFor(pid))
end, false)
