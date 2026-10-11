-- ncm_world / client / quick_actions -- the one door the NCM quick menu (the radial) comes through.
--
-- The wheel itself lives in its own resource, `ncm_radial`, because this resource is at 8 of 8 WebUI surfaces
-- (`IDEA-570`) and the wheel's loopback transport needs one. The ACTIONS stay here, where the functions they
-- call already live: every entry below is the very function its hotkey or chat command runs, so the wheel can
-- never do something the hotkey would not. Each owning file publishes its function into `NcmQuickActions` next
-- to its own `RegisterCommand`, so this file carries no logic of its own.
--
-- Returns `ok, reason` so the wheel can say out loud why nothing happened.
local function log(fmt, ...) print(("[ncm_world/client/quick_actions] " .. fmt):format(...)) end

NcmQuickActions = NcmQuickActions or {}

-- The vanilla map is not an NCM surface; open it the way the platform's own pause menu does.
NcmQuickActions.map = function()
    local ok, ticket, reason = pcall(Open77.map.open)
    if not ok then return false, tostring(ticket) end
    if not ticket then return false, tostring(reason or "map_unavailable") end
    return true
end

-- The Engineering panel (`ncm_engineering`) routes to a workshop through NCM's own navigation, never a second one:
-- `NcmNav.to` keeps the GPS selected across getting in and out of a car, which a bare waypoint does not.
exports("routeTo", function(p, why)
    if type(p) ~= "table" or type(p.x) ~= "number" or type(p.y) ~= "number" then return false, "bad_point" end
    if not (NcmNav and NcmNav.to) then return false, "nav_unavailable" end
    local ok, routed = pcall(NcmNav.to, { x = p.x, y = p.y, z = tonumber(p.z) or 0, name = tostring(p.name or "Workshop") }, tostring(why or "workshop"))
    if not ok then return false, tostring(routed) end
    return routed ~= false
end)

-- Engineering on the quick menu, when the wheel ships: the panel lives in its own resource, so the wheel's call
-- comes here and is passed on -- the same F9 path, never a second one.
NcmQuickActions.engineering = function()
    local promise, reason = Open77.exports.call("ncm_engineering", "toggle")
    if not promise and reason then return false, tostring(reason) end
    return true
end

exports("quickAction", function(id)
    local fn = NcmQuickActions[tostring(id or "")]
    if type(fn) ~= "function" then
        log("unknown quick action %s", tostring(id))
        return false, "unknown_action"
    end
    local ok, result, reason = pcall(fn)
    if not ok then
        log("quick action %s raised: %s", tostring(id), tostring(result))
        return false, "raised"
    end
    if result == false then
        log("quick action %s refused: %s", tostring(id), tostring(reason))
        return false, tostring(reason or "refused")
    end
    return true
end)
