-- ncm_world / server / state_probe -- the KB-136 discriminator. DELETE THIS FILE when KB-136 closes.
--
-- **Why this exists instead of a fix.** Two GlobalState payloads have never reached a client: `ncmCeilings`
-- (so class ceilings, a shipped feature, have never applied -- `KB-30`/D7 is silently dead) and
-- `ncmProjections` (so no machine projection has ever been felt). A third, `ncmCalendar`, works.
--
-- The evidence recorded in `KB-136` was *"total silence -- no log line from either branch of the loop"*, and
-- that evidence is **weaker than it was described as being.** Both client loops are written
-- `if records then ... end` with no else, so silence only proves `records` was falsy. It cannot tell apart:
--
--   (a) the payload never replicated at all                  -> a transport problem
--   (b) it replicated but the nested table was dropped        -> a serialisation depth problem
--   (c) it replicated and the map arrived EMPTY               -> a key problem, very likely the dots
--   (d) it replicated fine and the bug is downstream          -> not a transport problem at all
--
-- Those have four different fixes. Guessing would mean changing the publish shape, seeing it work, and never
-- knowing which property mattered -- and the next payload would hit it again. So: five payloads, varying one
-- property at a time, and a client that reports exactly what each one looks like on arrival.
--
--   `ncmProbeScalar`  a bare string.                       Does anything replicate at all?
--   `ncmProbeArray`   a table holding an array.            The known-good control: `ncmCalendar`'s shape.
--   `ncmProbeMap`     a table holding a string-keyed map.  Is it map-ness?
--   `ncmProbeDotted`  the same, keyed `Vehicle.v_...`.     **The prime suspect.** Both broken payloads are
--                                                          keyed by TweakDB record path, which contains a
--                                                          `.`; if the state bag treats keys as paths, a
--                                                          dotted key is where it would break.
--   `ncmProbeDeep`    an array of 11 realistic envelopes.  Separates SIZE and DEPTH from shape, by matching
--                                                          the real projection payload without the map.
--
-- Additive and read-only with respect to everything that exists: five new keys nothing else reads. It cannot
-- affect ceilings, projections, racing or identity.
local function log(fmt, ...) print(("[ncm_world/probe] " .. fmt):format(...)) end

local PROBE_RECORD = "Vehicle.v_probe_car"

--- Eleven entries shaped like a real `machine.projection` envelope, so the deep probe tests size and nesting
--- rather than being a toy. Eleven because that is how many records the real fleet publishes.
local function deepPayload()
    local entries = {}
    for i = 1, 11 do
        entries[i] = {
            path = ("Vehicle.v_probe_%02d"):format(i),
            at = 0,
            restore = false,
            flats = {
                { id = "lateral_grip", suffix = ".frictionMulLateral", value = 0.90 },
                { id = "slip_curve",   suffix = ".slipAngleCurveScale", value = 0.95 },
                { id = "brake_power",  suffix = ".lowVelStoppingDeceleration", value = 0.92 },
            },
        }
    end
    return { version = "probe-1", entries = entries }
end

local function publish()
    -- Each write is its own pcall: if the state bag refuses one shape outright, that refusal is itself the
    -- answer and must not take the other four with it.
    local results = {}
    local function put(key, value)
        local ok, err = pcall(function() GlobalState[key] = value end)
        results[#results + 1] = ("%s=%s"):format(key, ok and "written" or ("REFUSED:" .. tostring(err)))
    end

    put("ncmProbeScalar", "ok")
    put("ncmProbeArray",  { items = { 10, 20, 30 } })
    put("ncmProbeMap",    { records = { alpha = 1, beta = 2 } })
    put("ncmProbeDotted", { records = { [PROBE_RECORD] = 1 } })
    put("ncmProbeDeep",   deepPayload())

    log("published: %s", table.concat(results, " "))
end

CreateThread(function()
    -- After the resource has settled, and then periodically so a late joiner sees it too.
    Wait(6000)
    publish()
    while true do
        Wait(30000)
        publish()
    end
end)

RegisterCommand("ncm.probe", function() publish() end, true)
