-- ncm-core module: replay.lap
-- What a stored ghost IS, whether it may be kept, and how far ahead of it I currently am.
--
-- A ghost is never an entrant and never evidence (L166): it cannot affect timing, collision, standings,
-- ratings or results. Everything here is therefore about identity and comparison, never about scoring.
--
-- The delta is computed BY COURSE PROGRESS, not by elapsed time. Comparing my clock to the ghost's clock
-- answers "how long have we each been driving", which is the same number for both of us and says nothing.
-- The question a driver is asking is "am I ahead of where it was", and that is a comparison at a PLACE.
local Core = NcmCore

Core.define("replay.lap", function(C)
    local M = { version = "0.0.1" }
    local ids = C.get("vocabulary.ids")
    local pose = C.get("replay.pose")
    local tm = C.get("telemetry")

    --- Trust tiers. `personal` is my own lap replayed back to me; the other two hand one driver's line to
    --- another driver and are not built yet (L166). The tier is an argument from the first call so that
    --- adding them later does not change a single call site.
    M.TIERS = { personal = true, session = true, route = true }

    M.MIN_POSES = 4
    M.MIN_ELAPSED_MS = 1000

    local function isText(v, maxLen)
        return type(v) == "string" and #v >= 1 and #v <= (maxLen or 160)
    end

    --- Validate and normalise everything a stored lap must carry to be replayable and attributable later.
    ---
    --- The vehicle `record` is required for a ghost that is meant to wear the car the lap was set in. A lap
    --- with no record could still be replayed as a shape, but it could not be drawn honestly, so it is
    --- refused here rather than silently drawn as somebody else's car.
    function M.manifest(facts)
        if type(facts) ~= "table" then return nil, "not_a_table" end

        local tier = facts.tier or "personal"
        if not M.TIERS[tier] then return nil, "unknown_tier:" .. tostring(tier) end

        if not ids.isUuid(facts.ghostId) then return nil, "ghost_id" end
        if not ids.isUuid(facts.driverId) then return nil, "driver_id" end
        if not isText(facts.routeId, 160) then return nil, "route_id" end

        local format = facts.format or pose.FORMAT
        if format ~= pose.FORMAT then return nil, "unknown_format:" .. tostring(format) end

        local startedAt = tonumber(facts.runStartedAt)
        local finishedAt = tonumber(facts.runFinishedAt)
        if not startedAt or not finishedAt then return nil, "run_boundaries" end
        if finishedAt <= startedAt then return nil, "run_not_forward" end

        local elapsedMs = tonumber(facts.elapsedMs)
        if not elapsedMs or elapsedMs < M.MIN_ELAPSED_MS then return nil, "elapsed_ms" end

        local poseCount = tonumber(facts.poseCount)
        if not poseCount or poseCount < M.MIN_POSES then return nil, "pose_count" end
        if poseCount > pose.MAX_POSES then return nil, "too_many_poses:" .. poseCount end

        if not isText(facts.record, 256) then return nil, "record" end

        local incidentMs = tonumber(facts.incidentMs) or 0
        if incidentMs < 0 then return nil, "incident_ms" end

        return {
            ghostId = facts.ghostId,
            format = format,
            tier = tier,
            driverId = facts.driverId,
            routeId = facts.routeId,
            disciplineId = isText(facts.disciplineId, 96) and facts.disciplineId or nil,
            rulesetId = isText(facts.rulesetId, 96) and facts.rulesetId or nil,
            classId = isText(facts.classId, 96) and facts.classId or nil,
            laps = tonumber(facts.laps) or 1,
            runStartedAt = startedAt,
            runFinishedAt = finishedAt,
            elapsedMs = math.floor(elapsedMs),
            incidentMs = math.floor(incidentMs),
            -- Machine identity, latched when the start line was crossed rather than when the session closed.
            assetId = ids.isUuid(facts.assetId) and facts.assetId or nil,
            record = facts.record,
            appearance = isText(facts.appearance, 128) and facts.appearance or nil,
            configurationRef = ids.isUuid(facts.configurationRef) and facts.configurationRef or nil,
            poseCount = math.floor(poseCount),
            poseHz = tonumber(facts.poseHz) or pose.DEFAULT_HZ,
        }
    end

    --- May this lap be kept and replayed at `tier`?
    ---
    --- Returns `true`, or `false, reason` -- a named refusal, because "the ghost did not appear" is the least
    --- diagnosable failure this feature can have.
    function M.eligible(facts, tier)
        if type(facts) ~= "table" then return false, "not_a_table" end
        tier = tier or facts.tier or "personal"
        if not M.TIERS[tier] then return false, "unknown_tier:" .. tostring(tier) end

        -- Every gate, in order. The session kernel already refuses out-of-order crossings, so a run that
        -- reached the finish has them all; this re-asserts it against the stored facts rather than trusting
        -- that the kernel that produced them was the one we think it was.
        local gatesDone, gatesTotal = tonumber(facts.gatesDone), tonumber(facts.gatesTotal)
        if not gatesDone or not gatesTotal or gatesTotal < 2 then return false, "gates_unknown" end
        if gatesDone < gatesTotal then return false, "gates_incomplete" end

        if not tonumber(facts.runStartedAt) or not tonumber(facts.runFinishedAt) then
            return false, "run_boundaries"
        end
        if (tonumber(facts.runFinishedAt) or 0) <= (tonumber(facts.runStartedAt) or 0) then
            return false, "run_not_forward"
        end

        local poseCount = tonumber(facts.poseCount) or 0
        if poseCount < M.MIN_POSES then return false, "pose_count" end
        if poseCount > pose.MAX_POSES then return false, "too_many_poses" end

        if facts.refusedPoses and (tonumber(facts.refusedPoses) or 0) > 0 then return false, "poses_refused" end
        if facts.disconnected then return false, "disconnected" end
        if facts.dsq then return false, "dsq" end
        if not isText(facts.record, 256) then return false, "record" end

        -- A personal ghost is replayed only to the driver who set it, so their own client's word on their own
        -- line is enough. Handing a line to somebody else is a claim about a third party and needs the
        -- server's own observation to agree -- not built yet, so refuse rather than quietly accept.
        if tier ~= "personal" then
            if not facts.serverCorroborated then return false, "not_corroborated" end
            if not facts.published then return false, "not_published" end
        end

        return true
    end

    --- Is `candidateMs` a new best against `incumbentMs`? One definition, so the client that decides to
    --- upload, the server that decides to store and the HUD that decides what to label cannot disagree.
    function M.better(candidateMs, incumbentMs)
        local c = tonumber(candidateMs)
        if not c or c <= 0 then return false end
        local i = tonumber(incumbentMs)
        if not i or i <= 0 then return true end
        return c < i
    end

    --- Where the ghost was, in metres along the course, at each of its poses: `{ { m, t }, ... }`.
    ---
    --- Built ONCE per ghost and reused, because `telemetry.progress` without a segment hint tries every
    --- segment and this runs over a thousand poses. The hint is threaded from the previous pose for the same
    --- reason it is in the live path: a car cannot teleport between poses.
    ---
    --- Progress is forced non-decreasing. A real lap can wander backwards over a segment boundary by a few
    --- centimetres of projection noise, and a non-monotonic index makes a lookup ambiguous -- two different
    --- times for one place. Clamping loses nothing a ghost needs and makes the lookup total.
    function M.progressIndex(poses, course)
        if type(poses) ~= "table" or #poses == 0 then return nil, "no_poses" end
        if type(course) ~= "table" or type(course.pts) ~= "table" or #course.pts < 2 then
            return nil, "no_course"
        end
        local out, hint, maxM = {}, nil, 0
        for i = 1, #poses do
            local p = poses[i]
            local pr = tm.progress(course, { x = p.x, y = p.y, z = p.z or 0 }, hint)
            hint = pr.seg
            local m = pr.m
            if m < maxM then m = maxM else maxM = m end
            out[i] = { m = m, t = p.t or 0 }
        end
        return out
    end

    --- The ghost's elapsed time, in seconds, at the point `m` metres along the course.
    ---
    --- Binary search plus linear interpolation. Returns nil before the ghost's first metre and after its
    --- last: a place the ghost never reached has no time, and inventing one would put a delta on the HUD
    --- that no lap supports.
    function M.timeAtProgress(index, m)
        if type(index) ~= "table" or #index == 0 or type(m) ~= "number" then return nil end
        if m < index[1].m or m > index[#index].m then return nil end
        local lo, hi = 1, #index
        while hi - lo > 1 do
            local mid = math.floor((lo + hi) / 2)
            if index[mid].m <= m then lo = mid else hi = mid end
        end
        local a, b = index[lo], index[hi]
        local span = b.m - a.m
        if span <= 0 then return a.t end
        return a.t + (b.t - a.t) * ((m - a.m) / span)
    end

    --- Signed milliseconds between me and the ghost at where I am now.
    ---
    --- **Negative means I am ahead** -- I took less time to reach this place than the ghost did. Returns nil
    --- when the ghost has no time for my position, which is the honest answer off the racing line, before its
    --- start and past its finish.
    function M.delta(index, myProgressM, myElapsedSec)
        local ghostSec = M.timeAtProgress(index, myProgressM)
        if not ghostSec or type(myElapsedSec) ~= "number" then return nil end
        return math.floor((myElapsedSec - ghostSec) * 1000 + 0.5)
    end

    return M
end)
