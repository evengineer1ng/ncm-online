-- ncm_world / client / state_probe -- the reading half of the KB-136 discriminator.
-- DELETE THIS FILE, and its server counterpart, when KB-136 closes.
--
-- Reports what each probe payload actually looks like on this client, and does the same for the two real
-- payloads that have never arrived. **The whole point is that it logs on every path, including the boring
-- one.** The bug has been invisible for weeks precisely because the existing loops say nothing when they see
-- nothing, so this one says something even when the answer is "nil".
--
-- It logs a line, waits, and logs again only if the picture CHANGED -- so a working state costs one line and
-- a broken state does not scroll the log for the rest of the session.
local function log(fmt, ...) print(("[ncm_world/probe] " .. fmt):format(...)) end

--- Describe a value the way a diagnosis needs it: the type, and for a table the keys it carries and how many
--- entries each nested table holds. `records:0` versus `records:nil` versus absent are three different bugs
--- and the description has to keep them apart.
local function describe(value)
    local t = type(value)
    if t ~= "table" then
        if t == "nil" then return "nil" end
        if t == "string" then return ("string(%q)"):format(value) end
        return ("%s(%s)"):format(t, tostring(value))
    end

    local keys, n = {}, 0
    for key, inner in pairs(value) do
        n = n + 1
        if n <= 6 then
            if type(inner) == "table" then
                local count = 0
                for _ in pairs(inner) do count = count + 1 end
                local arrayLen = #inner
                keys[#keys + 1] = ("%s=table(n=%d,#=%d)"):format(tostring(key), count, arrayLen)
            else
                keys[#keys + 1] = ("%s=%s"):format(tostring(key), type(inner))
            end
        end
    end
    if n > 6 then keys[#keys + 1] = ("...+%d more"):format(n - 6) end
    return ("table{%s}"):format(table.concat(keys, ","))
end

local function read(key)
    local ok, value = pcall(function() return GlobalState[key] end)
    if not ok then return "PCALL_FAILED" end
    return describe(value)
end

local WATCHED = {
    -- the discriminator, one property at a time
    "ncmProbeScalar", "ncmProbeArray", "ncmProbeMap", "ncmProbeDotted", "ncmProbeDeep",
    -- the two that have never arrived, and the one that works
    "ncmCeilings", "ncmProjections", "ncmCalendar",
}

CreateThread(function()
    Wait(7000)
    local last = nil
    while true do
        local parts = {}
        for _, key in ipairs(WATCHED) do
            parts[#parts + 1] = ("%s=%s"):format(key, read(key))
        end
        local line = table.concat(parts, " | ")
        if line ~= last then
            last = line
            log("%s", line)
        end
        Wait(5000)
    end
end)

RegisterCommand("ncm.probe", function()
    for _, key in ipairs(WATCHED) do log("%s = %s", key, read(key)) end
end, false)
