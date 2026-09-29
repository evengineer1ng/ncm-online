-- ncm-core module: player.communication
--
-- A small policy boundary for player-facing messages. It does not draw anything and it does not know about
-- OPEN//77. Hosts give it an authored message plus the driver's durable exposure row; it answers whether the
-- message should appear, which wording should be used, and how much visual weight it deserves.
--
-- This exists so "tell the player" stops meaning "invent another toast at the call site". Authoritative game
-- state remains with the system that owns it. This module only decides how knowledge of that state is paced.
local Core = NcmCore

Core.define("player.communication", function()
    local M = { version = "0.1.0" }

    M.PRIORITY = {
        ambient = 1,
        informative = 2,
        actionable = 3,
        time_sensitive = 4,
        critical = 5,
    }
    M.DEFAULT_DURATION_MS = { 3200, 4500, 6500, 8500, 11000 }
    M.MODES = { always = true, once = true, cooldown = true, until_ack = true, adaptive = true }

    local function copy(src)
        local out = {}
        for k, v in pairs(type(src) == "table" and src or {}) do out[k] = v end
        return out
    end

    local function nonempty(value)
        return type(value) == "string" and value:match("%S") ~= nil
    end

    function M.normalize(def)
        if type(def) ~= "table" then return nil, "message_not_table" end
        if not nonempty(def.id) then return nil, "missing_id" end
        if not nonempty(def.title) then return nil, "missing_title" end
        if not (nonempty(def.message) or nonempty(def.firstMessage) or nonempty(def.repeatMessage)) then
            return nil, "missing_message"
        end
        local priority = tostring(def.priority or "informative")
        if not M.PRIORITY[priority] then return nil, "invalid_priority" end
        local repeatPolicy = copy(def.repeatPolicy)
        repeatPolicy.mode = tostring(repeatPolicy.mode or "always")
        if not M.MODES[repeatPolicy.mode] then return nil, "invalid_repeat_mode" end
        repeatPolicy.cooldownSec = math.max(0, math.floor(tonumber(repeatPolicy.cooldownSec) or 0))
        repeatPolicy.maxShows = repeatPolicy.maxShows and math.max(1, math.floor(tonumber(repeatPolicy.maxShows) or 1)) or nil
        repeatPolicy.escalateAfter = repeatPolicy.escalateAfter and math.max(1, math.floor(tonumber(repeatPolicy.escalateAfter) or 1)) or nil
        return {
            id = tostring(def.id), category = tostring(def.category or "status"), priority = priority,
            title = tostring(def.title), message = def.message and tostring(def.message) or nil,
            firstMessage = def.firstMessage and tostring(def.firstMessage) or nil,
            repeatMessage = def.repeatMessage and tostring(def.repeatMessage) or nil,
            actionHint = def.actionHint and tostring(def.actionHint) or nil,
            reference = def.reference and tostring(def.reference) or nil,
            surface = tostring(def.surface or "toast"),
            durationMs = tonumber(def.durationMs), repeatPolicy = repeatPolicy,
        }
    end

    local function promoted(priority)
        local rank = math.min(M.PRIORITY.critical, M.PRIORITY[priority] + 1)
        for name, value in pairs(M.PRIORITY) do if value == rank then return name end end
        return priority
    end

    --- Decide what to show from one durable exposure row.
    --- exposure = { shownCount, lastShownAt, acknowledgedAt }; all fields may be absent.
    function M.decide(raw, exposure, at)
        local def, why = M.normalize(raw)
        if not def then return nil, why end
        exposure = type(exposure) == "table" and exposure or {}
        local count = math.max(0, math.floor(tonumber(exposure.shownCount) or 0))
        local last = tonumber(exposure.lastShownAt)
        local acknowledged = tonumber(exposure.acknowledgedAt) ~= nil
        local policy = def.repeatPolicy
        local now = tonumber(at) or 0

        if policy.mode == "once" and count > 0 then return { deliver = false, reason = "already_seen" } end
        if policy.mode == "until_ack" and acknowledged then return { deliver = false, reason = "acknowledged" } end
        if policy.maxShows and count >= policy.maxShows and policy.mode ~= "always" and policy.mode ~= "adaptive" then
            return { deliver = false, reason = "exposure_cap" }
        end
        if last and policy.cooldownSec > 0 and now - last < policy.cooldownSec then
            return { deliver = false, reason = "cooldown" }
        end

        local variant = count == 0 and "first" or "repeat"
        if policy.mode == "adaptive" and acknowledged then variant = "repeat" end
        local priority = def.priority
        if policy.escalateAfter and not acknowledged and count >= policy.escalateAfter then priority = promoted(priority) end
        local message = variant == "first" and (def.firstMessage or def.message or def.repeatMessage)
            or (def.repeatMessage or def.message or def.firstMessage)
        local rank = M.PRIORITY[priority]
        return {
            deliver = true, reason = "eligible", variant = variant,
            presentation = {
                id = def.id, category = def.category, priority = priority, title = def.title,
                message = message, actionHint = def.actionHint, reference = def.reference,
                surface = def.surface,
                durationMs = math.floor(def.durationMs or M.DEFAULT_DURATION_MS[rank]),
            },
        }
    end

    function M.record(exposure, at)
        local out = copy(exposure)
        out.shownCount = math.max(0, math.floor(tonumber(out.shownCount) or 0)) + 1
        out.lastShownAt = math.floor(tonumber(at) or 0)
        return out
    end

    function M.acknowledge(exposure, at)
        local out = copy(exposure)
        out.acknowledgedAt = math.floor(tonumber(at) or 0)
        return out
    end

    return M
end)
