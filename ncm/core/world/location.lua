-- ncm-core module: world.location
--
-- L110: **where you log out is where you log in.** A property of the world, not of racing -- freeroam and
-- races alike. Leave in Pacifica, return in Pacifica.
--
-- Restoring somebody into a live race session is explicitly NOT the goal. L20's 180 s reconnect grace is a
-- SPORTING rule and stays exactly as it is; this module only decides WHERE a rejoining driver is placed, and
-- continuing a race inside that grace is the driver's choice rather than something done to them.
--
-- **The validation gate is the work, not the storage.** Restoring into geometry, water, a closed interior,
-- mid-air or onto a vehicle that no longer exists is worse than the default spawn, so every restore is a
-- decision with a reason attached -- and a refusal must be loggable, because a silently stranded player looks
-- exactly like a working one (the lesson of KB-72 and KB-76).
--
-- The safety argument that makes this tractable without a server-side raycast: **we never invent a position.**
-- We replay one the player was actually standing at, which was by construction standable ground at the time
-- it was recorded. What can still change underneath it is the world, so the remaining guards are staleness,
-- sanity and arrival separation -- not geometry.
local Core = NcmCore

Core.define("world.location", function(C)
    local M = { version = "0.0.1" }

    local DEFAULTS = {
        maxAgeSec = 7 * 86400,   -- a three-day-old position is not where the player thinks they are; a week is the outer bound
        maxCoord  = 100000,      -- Night City is nowhere near this; anything beyond is corruption, not a place
        minMoveM  = 3.0,         -- do not rewrite storage for a player standing still
    }

    local function finite(n)
        return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
    end

    --- Is this a position we could plausibly have recorded? Shape only; the world is not consulted.
    function M.valid(p, opts)
        local cfg = type(opts) == "table" and opts or {}
        local maxCoord = tonumber(cfg.maxCoord) or DEFAULTS.maxCoord
        if type(p) ~= "table" then return false, "not_a_table" end
        if not (finite(p.x) and finite(p.y) and finite(p.z)) then return false, "not_finite" end
        if math.abs(p.x) > maxCoord or math.abs(p.y) > maxCoord or math.abs(p.z) > maxCoord then
            return false, "out_of_bounds"
        end
        return true
    end

    --- Should this saved location be used for a rejoining driver?
    ---
    --- Returns true, or false plus a reason. Every reason is a thing a host can put in a log and a human can
    --- act on; "no" is never silent.
    ---
    --- saved: { x, y, z, heading?, bucket?, savedAt, inVehicle? }
    function M.shouldRestore(saved, now, opts)
        local cfg = type(opts) == "table" and opts or {}
        local maxAge = tonumber(cfg.maxAgeSec) or DEFAULTS.maxAgeSec
        if type(saved) ~= "table" then return false, "none" end
        local ok, why = M.valid(saved, cfg)
        if not ok then return false, why end
        local at = tonumber(saved.savedAt)
        if not at then return false, "undated" end
        if type(now) ~= "number" then return false, "no_clock" end
        if at > now + 300 then return false, "from_the_future" end   -- a clock stepped; do not trust it
        if now - at > maxAge then return false, "stale" end
        -- A seat is not a place. The vehicle that seat belonged to is very likely gone, and arriving inside a
        -- vehicle that no longer exists is the classic wedge.
        if saved.inVehicle == true then return false, "was_in_vehicle" end
        return true
    end

    --- Where to actually put them. Never the raw saved point: lift slightly, exactly as the race resume does,
    --- so a floating-point floor does not swallow the arrival.
    function M.arrivalPose(saved, opts)
        local ok = M.shouldRestore(saved, tonumber(saved and saved.savedAt) or 0, opts)
        local lift = tonumber(type(opts) == "table" and opts.liftM) or 0.5
        if type(saved) ~= "table" then return nil end
        return {
            x = saved.x, y = saved.y, z = saved.z + lift,
            heading = tonumber(saved.heading) or 0,
            bucket = tonumber(saved.bucket) or 0,
            trusted = ok and true or false,
        }
    end

    --- Is this new position worth writing? Saving every tick is noise; saving nothing loses the session.
    --- Returns true when the player has moved meaningfully, or when nothing has ever been stored.
    function M.worthSaving(previous, current, opts)
        local cfg = type(opts) == "table" and opts or {}
        local minMove = tonumber(cfg.minMoveM) or DEFAULTS.minMoveM
        if not M.valid(current, cfg) then return false, "invalid" end
        if type(previous) ~= "table" then return true end
        if not M.valid(previous, cfg) then return true end
        local dx, dy, dz = current.x - previous.x, current.y - previous.y, current.z - previous.z
        if (dx*dx + dy*dy + dz*dz) < (minMove * minMove) then return false, "unmoved" end
        return true
    end

    M.DEFAULTS = DEFAULTS
    return M
end)
