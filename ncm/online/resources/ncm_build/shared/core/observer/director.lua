-- ncm-core module: observer.director
-- NCM Observer (doc 46, L307): what the ghost watches and where its lens sits. Pure, so every rule is tested offline.
--
-- INPUT is the racer snapshot ncm_paddock already publishes every 2 s (`ncm:paddock:racers`, server/racers.lua):
--   { at, races = { { r, tier, series, cars = { { k, x, y, z, n, p, d?, g?, v?, h?, pid? } } } } }
-- k = person key, n = name, p = place, d = metres along the line, g = gap to the leader in ms, v = the network
-- vehicle id while the car is physical (nil while it lives only in the model), h = 1 for a human.
--
-- TARGETS (a spec the operator types, resolved against one snapshot):
--   race <text>    a race whose id or series contains <text>; watch its leader
--   racer <text>   a car whose name or key contains <text>
--   pos <n>        place n in the race being watched (or the first race)
--   leader         P1 of the race being watched (or the first race)
--   battle         the closest pair of consecutive running cars anywhere; watch the attacker
--   auto           the director below
--   car <race> <key>  one exact car (the Observer panel's click, its next/previous keys)
-- Ties break by race id then key, so the same snapshot always gives the same answer (the spec's "deterministic").
--
-- THE DIRECTOR (auto): hold a shot at least `minShotSec`; leave it early only when the target is gone. After that,
-- cut to a battle that is clearly better (gap below `battleGapMs` and under `cutRatio` of the current one), and cut
-- anyway after `maxShotSec` so the broadcast moves around. With no battle anywhere it watches a leader.
--
-- THE LENS: racer-relative shots need no authoring. A car's basis comes from its orientation quaternion, rotating the
-- platform's local frame (X right, Y forward, Z up -- the scripted-camera offset convention), so no yaw convention is
-- assumed (the tree has two: ncm_world garage.lua and carrier_bridge.lua disagree).
local Core = NcmCore

Core.define("observer.director", function()
    local M = { version = "0.1.0" }

    M.DEFAULTS = {
        minShotSec = 12,      -- no cut before this unless the target is gone
        maxShotSec = 45,      -- a cut after this even to something no better
        battleGapMs = 1500,   -- a pair closer than this is a battle
        cutRatio = 0.6,       -- a new battle must be this much closer than the current one to cut early
    }

    M.MODES = { "chase", "far", "drone", "onboard", "orbit", "side", "front", "low" }

    local function lower(s) return tostring(s or ""):lower() end

    --- Every car in a snapshot, with its race attached, in a stable order.
    function M.flatten(snap)
        local out = {}
        for _, race in ipairs((type(snap) == "table" and snap.races) or {}) do
            for _, car in ipairs(race.cars or {}) do
                out[#out + 1] = { race = race, car = car }
            end
        end
        table.sort(out, function(a, b)
            if a.race.r ~= b.race.r then return tostring(a.race.r) < tostring(b.race.r) end
            if (a.car.p or 999) ~= (b.car.p or 999) then return (a.car.p or 999) < (b.car.p or 999) end
            return tostring(a.car.k) < tostring(b.car.k)
        end)
        return out
    end

    function M.findRace(snap, raceId)
        for _, race in ipairs((type(snap) == "table" and snap.races) or {}) do
            if race.r == raceId then return race end
        end
        return nil
    end

    function M.findCar(snap, raceId, key)
        local race = M.findRace(snap, raceId)
        if not race then return nil end
        for _, car in ipairs(race.cars or {}) do
            if tostring(car.k) == tostring(key) then return car, race end
        end
        return nil, race
    end

    local function byPlace(race)
        local cars = {}
        for _, c in ipairs(race.cars or {}) do cars[#cars + 1] = c end
        table.sort(cars, function(a, b)
            if (a.p or 999) ~= (b.p or 999) then return (a.p or 999) < (b.p or 999) end
            return tostring(a.k) < tostring(b.k)
        end)
        return cars
    end

    local function leaderOf(race)
        local cars = byPlace(race)
        return cars[1]
    end

    --- The gap between two consecutive cars, in ms when both carry a gap, else from distance at `refMps`.
    function M.pairGapMs(ahead, behind, refMps)
        if ahead.g and behind.g then return math.max(0, behind.g - ahead.g) end
        if ahead.d and behind.d then return math.max(0, (ahead.d - behind.d) / (refMps or 30) * 1000) end
        return nil
    end

    --- Every pair of consecutive cars in every race, closest first. Each: { race, ahead, behind, gapMs }.
    function M.battles(snap)
        local out = {}
        for _, race in ipairs((type(snap) == "table" and snap.races) or {}) do
            local cars = byPlace(race)
            for i = 2, #cars do
                local gap = M.pairGapMs(cars[i - 1], cars[i])
                if gap then out[#out + 1] = { race = race, ahead = cars[i - 1], behind = cars[i], gapMs = gap } end
            end
        end
        table.sort(out, function(a, b)
            if a.gapMs ~= b.gapMs then return a.gapMs < b.gapMs end
            if a.race.r ~= b.race.r then return tostring(a.race.r) < tostring(b.race.r) end
            return tostring(a.behind.k) < tostring(b.behind.k)
        end)
        return out
    end

    local function target(race, car, why, extra)
        local t = { raceId = race.r, key = tostring(car.k), name = car.n, why = why }
        for k, v in pairs(extra or {}) do t[k] = v end
        return t
    end

    --- Parse "race westbrook", "racer chang", "pos 6", "p6", "leader", "battle", "auto". Returns spec or nil, reason.
    function M.parse(text)
        local s = lower(text):gsub("^%s+", ""):gsub("%s+$", "")
        if s == "" then return nil, "empty" end
        local kind, rest = s:match("^(%S+)%s*(.-)$")
        if kind:match("^p%d+$") then return { kind = "pos", n = tonumber(kind:sub(2)) } end
        if kind == "leader" or kind == "battle" or kind == "auto" then return { kind = kind } end
        if kind == "pos" then
            local n = tonumber(rest)
            if not n or n < 1 then return nil, "pos needs a number" end
            return { kind = "pos", n = math.floor(n) }
        end
        if kind == "car" then
            -- an exact car: "car <raceId> <key>" (the panel's click, the next/previous keys)
            local raceId, key = rest:match("^(%S+)%s+(%S+)$")
            if not raceId then return nil, "car needs a race id and a key" end
            return { kind = "car", raceId = raceId, key = key }
        end
        if kind == "race" or kind == "racer" then
            if rest == "" then return nil, kind .. " needs a name" end
            return { kind = kind, q = rest }
        end
        return { kind = "racer", q = s }        -- a bare name means a racer
    end

    --- Resolve a spec against a snapshot. `current` (a target or nil) supplies "the race being watched".
    --- Returns target or nil, reason.
    function M.resolve(snap, spec, current)
        if type(spec) ~= "table" then return nil, "no_spec" end
        local races = (type(snap) == "table" and snap.races) or {}
        if #races == 0 then return nil, "no_running_race" end
        local function watchedRace()
            return (current and M.findRace(snap, current.raceId)) or M.flatten(snap)[1].race
        end
        if spec.kind == "car" then
            for _, race in ipairs(races) do
                if lower(race.r) == spec.raceId then
                    for _, car in ipairs(race.cars or {}) do
                        if lower(car.k) == spec.key then return target(race, car, "picked") end
                    end
                    return nil, "car_not_in_race"
                end
            end
            return nil, "no_race_matches"
        end
        if spec.kind == "race" then
            local hit
            for _, race in ipairs(races) do
                if lower(race.r):find(spec.q, 1, true) or lower(race.series):find(spec.q, 1, true) then
                    if not hit or tostring(race.r) < tostring(hit.r) then hit = race end
                end
            end
            if not hit then return nil, "no_race_matches" end
            local lead = leaderOf(hit)
            if not lead then return nil, "race_has_no_cars" end
            return target(hit, lead, "race " .. tostring(hit.series or hit.r))
        elseif spec.kind == "racer" then
            for _, e in ipairs(M.flatten(snap)) do
                if lower(e.car.n):find(spec.q, 1, true) or lower(e.car.k) == spec.q then
                    return target(e.race, e.car, "racer " .. tostring(e.car.n))
                end
            end
            return nil, "no_racer_matches"
        elseif spec.kind == "pos" or spec.kind == "leader" then
            local race = watchedRace()
            local n = spec.kind == "leader" and 1 or spec.n
            local car = byPlace(race)[n]
            if not car then return nil, "no_car_at_place" end
            return target(race, car, "P" .. tostring(n))
        elseif spec.kind == "battle" or spec.kind == "auto" then
            local b = M.battles(snap)[1]
            if not b then
                local lead = leaderOf(watchedRace())
                if not lead then return nil, "no_cars" end
                return target(watchedRace(), lead, "leader (no battle)")
            end
            return target(b.race, b.behind, ("battle P%s-P%s %.1fs"):format(tostring(b.ahead.p), tostring(b.behind.p), b.gapMs / 1000),
                { battleWith = tostring(b.ahead.k), gapMs = b.gapMs })
        end
        return nil, "unknown_spec"
    end

    --- The gap of the battle a target belongs to, recomputed on this snapshot (nil when it is not a battle any more).
    local function currentBattleGap(snap, cur)
        if not (cur and cur.battleWith) then return nil end
        local ahead = M.findCar(snap, cur.raceId, cur.battleWith)
        local behind = M.findCar(snap, cur.raceId, cur.key)
        if not (ahead and behind) then return nil end
        return M.pairGapMs(ahead, behind)
    end

    --- One director step. `state` = { target?, since? } (seconds). Returns newTarget-or-nil (nil = hold), reason.
    function M.step(state, snap, now, opts)
        local o = {}
        for k, v in pairs(M.DEFAULTS) do o[k] = (opts and opts[k]) or v end
        local cur = state and state.target
        local held = (cur and state.since) and (now - state.since) or math.huge
        local alive = cur and M.findCar(snap, cur.raceId, cur.key)
        if not alive then
            local t, why = M.resolve(snap, { kind = "auto" }, cur)
            return t, t and "target gone" or why
        end
        if held < o.minShotSec then return nil, "holding" end
        local best = M.battles(snap)[1]
        local curGap = currentBattleGap(snap, cur)
        if best and best.gapMs <= o.battleGapMs then
            local same = best.race.r == cur.raceId and tostring(best.behind.k) == cur.key
            if not same and (not curGap or best.gapMs < curGap * o.cutRatio or held >= o.maxShotSec) then
                return M.resolve(snap, { kind = "battle" }, cur), "closer battle"
            end
        end
        if held >= o.maxShotSec then
            local t = M.resolve(snap, { kind = "battle" }, cur)
            if t and not (t.raceId == cur.raceId and t.key == cur.key) then return t, "shot too long" end
        end
        return nil, "holding"
    end

    -- -------------------------------------------------------------------------------------------------------------
    -- The lens
    -- -------------------------------------------------------------------------------------------------------------

    --- Rotate v by unit quaternion q ({x,y,z,w}).
    function M.rotate(q, v)
        local qx, qy, qz, qw = q.x or 0, q.y or 0, q.z or 0, q.w or 1
        local vx, vy, vz = v.x or 0, v.y or 0, v.z or 0
        -- t = 2 * cross(q.xyz, v); v' = v + w*t + cross(q.xyz, t)
        local tx = 2 * (qy * vz - qz * vy)
        local ty = 2 * (qz * vx - qx * vz)
        local tz = 2 * (qx * vy - qy * vx)
        return {
            x = vx + qw * tx + (qy * tz - qz * ty),
            y = vy + qw * ty + (qz * tx - qx * tz),
            z = vz + qw * tz + (qx * ty - qy * tx),
        }
    end

    local function norm2(x, y)
        local l = math.sqrt(x * x + y * y)
        if l < 1e-6 then return 0, 1 end
        return x / l, y / l
    end

    --- A car's flat basis: forward and right on the ground plane. From the quaternion when there is one, else from
    --- `fallbackDir` (e.g. the direction of travel between two reads), else world +Y.
    function M.basis(orientation, fallbackDir)
        local fx, fy
        if type(orientation) == "table" and orientation.w then
            local f = M.rotate(orientation, { x = 0, y = 1, z = 0 })
            fx, fy = norm2(f.x, f.y)
        elseif type(fallbackDir) == "table" then
            fx, fy = norm2(fallbackDir.x or 0, fallbackDir.y or 0)
        else
            fx, fy = 0, 1
        end
        -- right-handed, Z up: right = forward x up
        return { x = fx, y = fy, z = 0 }, { x = fy, y = -fx, z = 0 }
    end

    local function at(p, f, r, fwd, side, up)
        return { x = p.x + f.x * fwd + r.x * side, y = p.y + f.y * fwd + r.y * side, z = (p.z or 0) + up }
    end

    --- Where the lens sits and what it looks at, for a car at `pos` with basis f/r. `t` (seconds) turns the orbit.
    --- Returns { pos, look, fov }.
    function M.shot(mode, pos, f, r, t)
        t = t or 0
        if mode == "far" then
            return { pos = at(pos, f, r, -16, 0, 5.5), look = at(pos, f, r, 6, 0, 0.8), fov = 55 }
        elseif mode == "drone" then
            return { pos = at(pos, f, r, -10, 0, 32), look = at(pos, f, r, 12, 0, 0), fov = 60 }
        elseif mode == "onboard" then
            -- the passenger's eyes: right of centre, at head height, looking down the road
            return { pos = at(pos, f, r, 0.05, 0.38, 1.12), look = at(pos, f, r, 40, 0.2, 1.0), fov = 75 }
        elseif mode == "orbit" then
            local a = (t * 0.35) % (2 * math.pi)
            local fwd, side = math.cos(a) * 9, math.sin(a) * 9
            return { pos = at(pos, f, r, fwd, side, 2.2), look = at(pos, f, r, 0, 0, 0.7), fov = 60 }
        elseif mode == "side" then
            return { pos = at(pos, f, r, 1.0, 7.5, 1.4), look = at(pos, f, r, 1.0, 0, 0.7), fov = 60 }
        elseif mode == "front" then
            return { pos = at(pos, f, r, 9, 0, 1.6), look = at(pos, f, r, 0, 0, 0.8), fov = 60 }
        elseif mode == "low" then
            return { pos = at(pos, f, r, 2.6, 0.9, 0.35), look = at(pos, f, r, 30, 0, 0.6), fov = 80 }
        end
        -- chase
        return { pos = at(pos, f, r, -6.5, 0, 2.1), look = at(pos, f, r, 8, 0, 0.9), fov = 65 }
    end

    --- The ghost's body must stay near the car: the world streams around the BODY, not the lens, a scripted camera
    --- refuses past 250 m, and the Paddock bubble materialises cars around player positions. Returns a new body
    --- position when it has fallen more than `maxM` behind or aside, else nil. It lands `aheadM` up the road and
    --- `upM` above it, so with noclip on it never stands where a car will be.
    function M.leapfrog(body, pos, f, opts)
        opts = opts or {}
        local maxM, aheadM, upM = opts.maxM or 60, opts.aheadM or 45, opts.upM or 12
        if not (body and pos) then return nil end
        local dx, dy, dz = body.x - pos.x, body.y - pos.y, (body.z or 0) - (pos.z or 0)
        if math.sqrt(dx * dx + dy * dy + dz * dz) <= maxM then return nil end
        return { x = pos.x + f.x * aheadM, y = pos.y + f.y * aheadM, z = (pos.z or 0) + upM }
    end

    return M
end)
