-- ncm_world / client / nav -- the one thing that knows where NCM is pointing you, and how.
--
-- **Why this file exists.** Navigation used to be set in two places (`calendar.routeTo` for the street cadence,
-- `race.gpsTo` for the session HUD), both calling `Open77.blips.setWaypoint` directly, and neither able to say
-- what the other had just done. Live QA on 2026-09-23 broke on exactly that seam: two races navigated only
-- after the driver typed `/ncm.gps` and opened/closed the map, and a third kept routing to the start it had
-- already left, so the run was abandoned. One owner, one target, one recipe.
--
-- **The map open/close workaround is not a REDengine limitation.** That was the standing assumption
-- (IDEA-052, L70) and it is wrong. The platform's own race gamemode documents the mechanism in
-- `gamemodes/freeroam/race/client/main.lua`:
--
--   * `Open77.blips.create{ ..., routable = true }` uses "Cyberpunk's custom-waypoint definition, which is what
--     wakes the native GPS pathfinder and its vehicle line effect". A bare `setWaypoint` only moves the pin.
--   * `Open77.blips.track(id)` selects it as the vanilla GPS destination, and must be re-issued after an
--     update, because updating a blip can replace the native mappin underneath the handle.
--   * And the sentence that explains every symptom we have: *"The vanilla GPS controller snapshots
--     pedestrian/vehicle context when tracking starts; selecting the point before the car materializes can
--     leave a valid manually-tracked id with no minimap road route for the whole heat."*
--
-- That is the bug. NCM set the waypoint while the driver was on foot at the venue, the GPS controller
-- snapshotted a pedestrian context, and the road line never appeared for the rest of the run. Opening the map
-- re-snapshotted it, which is why the workaround worked and why it looked like an engine quirk.
--
-- So this module re-tracks whenever the seat context changes, and verifies periodically, exactly as the
-- platform's own code does. `setWaypoint` stays as a fallback for a build without routable blips: it is what
-- we shipped, it half-works, and a missing API must degrade rather than strand a driver with no pin at all.
--
-- L70 still holds: NCM never opens the player's map for them.
local SPRITE = "CustomPositionVariant"   -- the routable sprite the platform's race gamemode uses
local VERIFY_OK_S, VERIFY_FAIL_S = 2.0, 1.0

NcmNav = {}

local target = nil          -- { x, y, z, name, why } -- what we are pointing at
local blipId = nil          -- the routable blip's handle, when the platform gave us one
local blipKey = nil         -- position signature of the blip as it currently stands
local trackedSeated = nil   -- inVehicle() when tracking last started; a change means re-track
local verifyAt = 0
local fellBack = false      -- true once we have decided this build has no routable blips

local function log(fmt, ...)
    print(("[ncm_world/client/nav] " .. fmt):format(...))
end

local function mono() return Open77.time.monotonic() end

--- Seated or on foot. The GPS controller snapshots this when tracking starts, so it is the one piece of
--- context worth watching: crossing it invalidates a route that was correct when it was set.
local function inVehicle()
    local ok, seat = pcall(Open77.players.getVehicleSeat)
    if ok and type(seat) == "table" then return true end
    local ok2, seat2 = pcall(Open77.vehicles.getPlayerSeat)
    return (ok2 and type(seat2) == "table") or false
end

--- Select our blip as the vanilla GPS destination. Re-issued after every update and whenever the seat
--- context changes, which is the whole point of the module.
local function track(why)
    if not blipId then return false end
    -- `blips.track` returns TWO values, `(ok, changedOrReason)`, exactly as the platform's race client reads
    -- them -- so the pcall status is a third. Folding the first two together reads a false `ok` as "no change"
    -- and reports a failed selection as a success.
    local called, ok, changedOrReason = pcall(Open77.blips.track, blipId)
    trackedSeated = inVehicle()
    verifyAt = mono() + ((called and ok) and VERIFY_OK_S or VERIFY_FAIL_S)
    if not called then
        log("track raised (%s): %s", tostring(why), tostring(ok))
        return false
    end
    if not ok then
        log("track failed (%s): %s", tostring(why), tostring(changedOrReason))
        return false
    end
    if changedOrReason == true then
        log("gps destination selected (%s) seated=%s", tostring(why), tostring(trackedSeated))
    end
    return true
end

--- What we shipped before: clear then set, which routes immediately but snapshots whatever context the
--- driver happens to be in (E17, 2026-09-19). Kept only for a build with no routable blips.
local function fallbackWaypoint(p, why)
    pcall(Open77.blips.clearWaypoint)
    Wait(250)
    local ok, reason = pcall(Open77.blips.setWaypoint, { x = p.x, y = p.y, z = p.z })
    log("fallback waypoint (%s) -> %s %s", tostring(why), tostring(ok), tostring(reason))
end

--- Point NCM's navigation at a place. Idempotent: calling it again with the same point only re-verifies
--- tracking, so a 10 Hz HUD may call it every tick without churning the player's map.
--- `p` = { x, y, z, name? }; `why` is a short reason for the log and for /ncm.gps to echo back.
function NcmNav.to(p, why)
    if type(p) ~= "table" or type(p.x) ~= "number" then return false end
    local key = ("%.1f|%.1f|%.1f"):format(p.x, p.y, p.z or 0)
    target = { x = p.x, y = p.y, z = p.z or 0, name = p.name, why = why }
    if fellBack then
        if key ~= blipKey then blipKey = key; CreateThread(function() fallbackWaypoint(p, why) end) end
        return true
    end
    local title = tostring(p.name or "NCM")
    local opts = {
        position = { x = p.x, y = p.y, z = p.z or 0 },
        sprite = SPRITE, title = title, description = tostring(why or "NCM navigation"),
        active = true,
        -- The routable form is the difference between a pin and a route (see the header).
        routable = true,
    }
    if blipId == nil then
        local ok, id, reason = pcall(Open77.blips.create, opts)
        if not ok or id == nil then
            -- No routable blips on this build. Say so once and degrade to the old recipe rather than
            -- leaving the driver with no navigation at all.
            fellBack = true
            log("routable blips unavailable (%s); falling back to setWaypoint", tostring((not ok) and id or reason))
            blipKey = key
            CreateThread(function() fallbackWaypoint(p, why) end)
            return true
        end
        blipId, blipKey = id, key
        log("target %s (%s) at %.0f %.0f", title, tostring(why), p.x, p.y)
        track("created")
    elseif key ~= blipKey then
        local ok, okUpdate, reason = pcall(Open77.blips.update, blipId, opts)
        if not (ok and okUpdate) then
            log("update failed: %s; recreating", tostring((not ok) and okUpdate or reason))
            NcmNav.clear()
            return NcmNav.to(p, why)
        end
        blipKey = key
        log("target %s (%s) at %.0f %.0f", title, tostring(why), p.x, p.y)
        -- An update can replace the native mappin under our handle, so selection has to be re-issued.
        track("advanced")
    end
    return true
end

--- Stop navigating. Removes our blip and releases the vanilla waypoint, so nothing of ours is left on a map
--- after a race ends or the driver leaves a session.
function NcmNav.clear()
    if blipId then pcall(Open77.blips.remove, blipId) end
    blipId, blipKey, target, trackedSeated = nil, nil, nil, nil
    verifyAt = 0
    pcall(Open77.blips.clearWaypoint)
end

--- Where we are pointing, or nil. `/ncm.gps` reads this so a manual refresh re-routes to the live target
--- instead of guessing one from the calendar.
function NcmNav.target() return target end

--- Re-issue the current target. This is what `/ncm.gps` does when there already is one: the point does not
--- change, but tracking is re-selected against the driver's CURRENT seat context, which is the actual
--- content of the old "open and close the map" workaround.
function NcmNav.refresh(why)
    if not target then return false end
    if fellBack then CreateThread(function() fallbackWaypoint(target, why or "refresh") end); return true end
    return track(why or "refresh")
end

-- The watcher. Two jobs, both taken from the platform's own race client: re-track when the seat context
-- crosses (on foot -> seated is the case that used to cost a driver their route for a whole run), and
-- re-verify periodically, because another system may take the GPS selection at any time.
CreateThread(function()
    while true do
        Wait(500)
        if target and blipId and not fellBack then
            local seated = inVehicle()
            if seated ~= trackedSeated then
                track(seated and "got in" or "got out")
            elseif mono() >= verifyAt then
                track("verify")
            end
        end
    end
end)

AddEventHandler("onClientResourceStop", function(name)
    if name == GetCurrentResourceName() then NcmNav.clear() end
end)
