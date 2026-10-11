-- ncm_world / client / deepview -- the NCWE space render (L351 / IDEA-1263, L358): what REDengine shows while the
-- Machine is in Deep.
--
-- client/deep.lua flies the Machine in space.deep as before; this file only decides what the player sees. The car is
-- held (frozen by the server) at the centre of the Deep stage in `ncm_world_layer`, upright with a yaw. Around it, the
-- universe the NCWE world layer carries -- the J2000 star dome (ESO's Milky Way + the Bright Star Catalogue), the
-- Blue Marble Earth, the LROC Moon -- is drawn by the `ncm-sky` package through the `ncm_sky` resource, every body at its
-- true direction and angular size and turned on every axis (core `space.sky`): the Earth turns under the Machine, the
-- sky turns with the clock, and the whole universe swings with the Machine's real pitch and roll.
--
-- Replaces L352's held-above-a-game-globe NEAR view and its Open77 props (KB-430). The WebGL Deep view stays on the
-- camera button, for scale (L351 amendment).
local Sky = NcmCore.get("space.sky")

local function log(fmt, ...) print(("[ncm_world/client/deepview] " .. fmt):format(...)) end

local SEND_MS = 100          -- the scene ten times a second
-- KB-438 (2026-10-10): the car used to be re-staged (server setTransform + flags + freeze) on every 1 deg of yaw. Each
-- move handed the car to the server and back -- 126 ownership flips and vehicle-audio re-attaches in a 22 s stay: the
-- flicker. Now it is staged ONCE per Deep entry, at the heading it came in with, and the universe turns around it.

-- KB-444: the stage request is repeated until the server acknowledges it -- net events are not ordered, and the one
-- request sent in ENTER's frame was dropped (the car stayed frozen at the seam over Night City, the sky 16 km away).
local STAGE_RETRY_MS = 500
local STAGE_TRIES = 40       -- 20 s, then it is said once, loudly

local V = nil                -- { sentAt, sent = { x, y, z, yaw, seq }, acked, tries, stageAt, kinds = "..." }

NcmDeepView = {}

local function requestStage(now)
    V.tries, V.stageAt = (V.tries or 0) + 1, now
    local s = V.sent
    TriggerServerEvent("ncm:deep.stage", { stage = "near", x = s.x, y = s.y, z = s.z, yaw = s.yaw, seq = s.seq })
    if V.tries == STAGE_TRIES + 1 then
        log("STAGE NOT CONFIRMED after %d requests: the car is still at the seam; the sky is drawn at the stage", STAGE_TRIES)
    end
end

RegisterNetEvent("ncm:deep.staged", function(m)
    if not (V and V.sent and type(m) == "table" and m.seq == V.sent.seq) or V.acked then return end
    V.acked = true
    log("stage confirmed by the server after %d request(s)", V.tries or 0)
end)

local function scene(bodies)
    local okC, promise, why = pcall(Open77.exports.call, "ncm_sky", "scene", "deep", bodies)
    if not (okC and promise) and V and not V.warned then
        V.warned = true
        log("ncm_sky unreachable (%s): Deep has no sky", tostring(okC and why or promise))
    end
end

--- Every Deep frame (cheap: rate-limited here; ncm_sky keeps the feed alive on its own).
function NcmDeepView.update(s, utc, now)
    if not s or not s.p then return end
    V = V or { sentAt = 0 }
    if now - V.sentAt < SEND_MS then return end
    V.sentAt = now
    local view = Sky.view(s, utc or 0, nil, V.sent and V.sent.yaw or nil)
    local c = view.car
    if not V.sent then
        V.sent = { x = c[1], y = c[2], z = c[3], yaw = view.yaw, seq = now }
        requestStage(now)
        log("staged once at (%.0f, %.0f, %.0f) heading %.1f deg; the universe turns from here", c[1], c[2], c[3], view.yaw)
    elseif not V.acked and now - (V.stageAt or 0) >= STAGE_RETRY_MS and (V.tries or 0) <= STAGE_TRIES then
        requestStage(now)
    end
    local bodies, kinds = {}, {}
    for _, b in ipairs(view.bodies) do
        bodies[#bodies + 1] = { id = b.id, kind = b.kind, p = { b.p[1], b.p[2], b.p[3] }, q = b.q }
        kinds[#kinds + 1] = b.id .. "=" .. b.kind
    end
    kinds = table.concat(kinds, " ")
    if kinds ~= V.kinds then
        V.kinds = kinds
        log("sky: %s%s", kinds, #view.notes > 0 and (" (" .. table.concat(view.notes, ", ") .. ")") or "")
    end
    scene(bodies)
end

--- Leaving Deep: the sky goes; the server puts the car back in Night City.
function NcmDeepView.clear()
    scene({})
    V = nil
end

AddEventHandler("onClientResourceStop", function(name) if name == GetCurrentResourceName() then NcmDeepView.clear() end end)
