-- Bounded conservative placement probe; never creates a vehicle. No native vehicle-call/AI API assumed.
-- Static + dynamic raycasts sample support and clearance. This is not a volumetric collision guarantee.
--
-- The client proposes; the SERVER disposes. Nothing here is authority: `server/vehicle_access.lua` re-checks
-- ownership, distance, bucket, other players and other vehicles before anything is created (L106). Widening
-- the search below therefore widens where a car MAY be offered, never what may be created.
--
-- **Owner QA, 2026-09-23: far too restrictive.** Standing on the centre divider of a four-lane road, with
-- open tarmac on both sides, a call could not find anywhere to put a Makigai MaiMai -- a car barely three
-- metres long. Four things stacked up, and each was individually defensible:
--
--   * only FOUR candidates, all at exactly 8 m, aligned to the player's facing -- so if you happened to face
--     across the road, every candidate landed in oncoming lanes or past the far kerb;
--   * a 3.0 x 6.0 m footprint required flat ground, for cars that are 3.1-4.5 m long;
--   * `normal.z >= 0.97` -- about 14 degrees -- which ordinary road camber can fail;
--   * 0.20 m of height variation allowed across that whole 3 x 6 m patch, which a crowned road plus a
--     divider kerb exceeds easily.
--
-- The fix is more places to look and an envelope sized to the cars this actually supports, NOT the removal of
-- the checks that stop a car appearing inside geometry.
local DIRECTIONS = {            -- unit vectors in the player's frame: right/forward, cardinals then diagonals
    {0, 1}, {1, 0}, {-1, 0}, {0, -1},
    {0.7071, 0.7071}, {-0.7071, 0.7071}, {0.7071, -0.7071}, {-0.7071, -0.7071},
}
-- The server refuses anything closer than 5 m or further than 12 m, so stay inside that band.
local DISTANCES = { 6, 8, 10 }
local MAX_CANDIDATES = 16       -- bound the worst case: a genuinely enclosed spot must still answer promptly
local BUDGET_MS = 4500          -- ...and the server gives up at 10 s, so answer well inside that

-- Envelope for the Base Market's small starter cars (MaiMai 3.1 m, Hella ~4.3 m, Galena ~4.5 m).
-- Half-extents, so 2.4 m wide x 4.8 m long with margin already included.
local HALF_W, HALF_L = 1.2, 2.4
local STEP = 0.6
local MIN_NORMAL_Z = 0.93       -- ~21 degrees: still refuses banks, kerb faces and walls; allows road camber
local MAX_RELIEF = 0.30         -- height variation tolerated across the footprint

local function nowMs()
    local ok, v = pcall(function() return Open77.time.monotonic() end)
    if ok and type(v) == "number" then return v * 1000 end
    ok, v = pcall(GetGameTimer)
    if ok and type(v) == "number" then return v end
    return nil
end

local function ray(a,b)
    local result = Open77.world.raycast(a,b,{static=true,dynamic=true})
    if type(result) ~= "table" or type(result.hit) ~= "boolean" then error("geometry_unavailable") end
    return result
end
--- Scalar fields of whatever the platform hands back. Sent to the server only on refusal, so the real shape
--- of `Open77.character.state()` is recorded once from the platform instead of assumed.
local function describeState(s)
    if type(s) ~= "table" then return "state=" .. tostring(s) end
    local parts = {}
    for k, v in pairs(s) do
        if type(v) ~= "table" and type(v) ~= "function" then parts[#parts+1] = tostring(k) .. "=" .. tostring(v) end
    end
    table.sort(parts)
    return "{" .. table.concat(parts, " ") .. "}"
end

--- On foot, alive, still, and where we thought.
---
--- **Absent is not a refusal.** This previously demanded `alive == true`, `grounded == true` and
--- `inVehicle == false` from a table whose shape NCM has never verified -- `Open77.character.state()` is
--- called nowhere else in the codebase. A snapshot missing any one of those fields refuses forever, because
--- `nil ~= false` is true: the owner stood still on a road and was told to stand still, and the probe gave up
--- 167 ms in, before a single ray was cast. This is the same defect `p.ready` had on the server side.
---
--- So each condition now refuses only on an explicit negative, and the substance is unchanged: if the
--- platform says you are dead, in a vehicle, airborne or moving, you are refused.
local function stillFrom(s, origin)
    if type(s) ~= "table" then return nil, "no_state" end
    if s.alive == false then return nil, "not_alive" end
    if s.inVehicle == true then return nil, "in_vehicle" end
    if s.grounded == false then return nil, "airborne" end
    if type(s.position) ~= "table" or type(s.position.x) ~= "number" then return nil, "no_position" end
    if type(s.speed) == "number" and s.speed > 0.5 then return nil, "moving" end
    local p = s.position
    if (p.x-origin.x)^2+(p.y-origin.y)^2+(p.z-origin.z)^2 > 1 then return nil, "walked_away" end
    return s
end

local function still(origin)
    return (stillFrom(Open77.character.state(), origin))
end

--- One candidate. Returns a pose, or nil plus the reason it was rejected -- the reason is what lets the
--- player be told something better than "somewhere else".
local function tryCandidate(origin, cx, cy, yaw, point)
    local good, low, high = true, nil, nil
    local ground = {}
    local reason = nil
    local xi = -HALF_W
    while xi <= HALF_W + 1e-6 and good do
        local yi = -HALF_L
        while yi <= HALF_L + 1e-6 do
            local hit = ray(point(cx,cy,xi,yi,origin.z+1), point(cx,cy,xi,yi,origin.z-1.5))
            if not hit.hit or not hit.position or not hit.normal then good=false; reason="no_ground"; break end
            if hit.normal.z < MIN_NORMAL_Z then good=false; reason="sloped"; break end
            local z = hit.position.z
            low = low and math.min(low,z) or z
            high = high and math.max(high,z) or z
            if high-low > MAX_RELIEF then good=false; reason="uneven"; break end
            ground[#ground+1] = {x=xi, y=yi, z=z}
            yi = yi + STEP
        end
        Wait(0)
        xi = xi + STEP
    end
    if not good then return nil, reason end

    -- nothing standing on the footprint
    for i,g in ipairs(ground) do
        if ray(point(cx,cy,g.x,g.y,g.z+.25), point(cx,cy,g.x,g.y,high+2.2)).hit then return nil, "obstructed" end
        if i%6==0 then Wait(0) end
    end
    -- ...and nothing crossing it at car height
    for _,z in ipairs({high+.35, high+1, high+1.8}) do
        local x = -HALF_W
        while x <= HALF_W + 1e-6 do
            if ray(point(cx,cy,x,-HALF_L,z), point(cx,cy,x,HALF_L,z)).hit then return nil, "obstructed" end
            x = x + STEP
        end
        local y = -HALF_L
        while y <= HALF_L + 1e-6 do
            if ray(point(cx,cy,-HALF_W,y,z), point(cx,cy,HALF_W,y,z)).hit then return nil, "obstructed" end
            y = y + STEP
        end
        Wait(0)
    end
    -- and the player can actually see it from where they stand
    if ray({x=origin.x,y=origin.y,z=origin.z+1}, {x=cx,y=cy,z=high+1}).hit then return nil, "not_visible" end
    return {x=cx, y=cy, z=high+.35, yaw=yaw}
end

local function probe(origin)
    local raw = Open77.character.state()
    local s, why = stillFrom(raw, origin)
    if not s then return nil, why, describeState(raw) end
    -- Orientation is cosmetic next to the feature working at all: a car facing north beats no car. If the
    -- platform does not report yaw, candidates are laid out on world axes instead of the player's facing.
    local yaw = tonumber(s.yaw) or 0
    local rad=math.rad(yaw)
    local fx,fy,rx,ry=-math.sin(rad),math.cos(rad),math.cos(rad),math.sin(rad)
    local function point(cx,cy,x,y,z) return {x=cx+rx*x+fx*y, y=cy+ry*x+fy*y, z=z} end

    -- A time budget must never be the thing that breaks the feature it guards. If neither clock is
    -- available we simply fall back to MAX_CANDIDATES, which bounds the work on its own.
    local started = nowMs()
    local tried, lastReason = 0, "no_space"
    -- Nearest first: a car placed six metres away is better than one placed ten, and the common case exits
    -- after a handful of candidates rather than paying for the whole search.
    for _,dist in ipairs(DISTANCES) do
        for _,dir in ipairs(DIRECTIONS) do
            if tried >= MAX_CANDIDATES then return nil, lastReason end
            local at = nowMs()
            if started and at and (at - started) > BUDGET_MS then return nil, "timeout" end
            tried = tried + 1
            local cx = origin.x + rx*(dir[1]*dist) + fx*(dir[2]*dist)
            local cy = origin.y + ry*(dir[1]*dist) + fy*(dir[2]*dist)
            local pose, why = tryCandidate(origin, cx, cy, yaw, point)
            if pose and still(origin) then return pose end
            if why then lastReason = why end
            Wait(0)
        end
    end
    return nil, lastReason
end

RegisterNetEvent("ncm:vehicle.probe",function(token,origin)
    if type(token)~="string" or type(origin)~="table" then return end
    CreateThread(function()
        local ok,pose,why,shape = pcall(probe,origin)
        if ok then
            print(("[ncm_world/access] placement probe %s"):format(pose and "candidate" or ("refused: " .. tostring(why))))
        else
            print("[ncm_world/access] placement probe error: " .. tostring(pose))
            why, shape = "error", tostring(pose)
        end
        TriggerServerEvent("ncm:vehicle.probed", token, ok and pose or nil,
            (not pose) and tostring(why) or nil, (not pose) and shape or nil)
    end)
end)
