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

-- ROUND 2, 2026-09-26. Round 1 answered more than it was designed to. Every probe came back `nil` on the
-- client while `ncmProjections` and `ncmCalendar` arrived -- and the two that arrived are the two whose
-- payload CHANGES on every publish (`at` timestamps, `serverNow`). Every probe wrote a byte-identical value
-- each time, and `ncmCeilings` is written once at boot and never again.
--
-- **So the hypothesis is no longer about shape, dots or size. It is that GlobalState replicates a CHANGE,
-- and a client that joins later is never sent a snapshot of a key that has not changed since.** If true,
-- `ncmCeilings` could never have worked: it is published once, before anybody is connected, and then never
-- written again. That is a shipped feature that was unreachable by construction.
--
-- Round 2 tests exactly that, by varying ONE property: four payloads now carry a `tick` that increments on
-- every publish, and `ncmProbeScalar` is deliberately left CONSTANT as the control.
--
--   scalar stays nil, the other four arrive   -> change-detection confirmed; shape, dots and size are fine
--   dotted stays nil while map arrives        -> dotted keys matter as well
--   deep stays nil while the others arrive    -> size matters as well
--   nothing changes                           -> the hypothesis is wrong and the cause is elsewhere
local tick = 0

local function publish()
    -- Each write is its own pcall: if the state bag refuses one shape outright, that refusal is itself the
    -- answer and must not take the other four with it.
    tick = tick + 1
    local results = {}
    local function put(key, value)
        local ok, err = pcall(function() GlobalState[key] = value end)
        results[#results + 1] = ("%s=%s"):format(key, ok and "written" or ("REFUSED:" .. tostring(err)))
    end

    -- THE CONTROL. Constant forever, on purpose. If this one is still `nil` on a client while the others
    -- have arrived, the answer is change-detection and nothing else.
    put("ncmProbeScalar", "ok")

    local deep = deepPayload()
    deep.tick = tick

    put("ncmProbeArray",  { items = { 10, 20, 30 }, tick = tick })
    put("ncmProbeMap",    { records = { alpha = 1, beta = 2 }, tick = tick })
    put("ncmProbeDotted", { records = { [PROBE_RECORD] = 1 }, tick = tick })
    put("ncmProbeDeep",   deep)

    log("published tick %d: %s", tick, table.concat(results, " "))
end

CreateThread(function()
    -- After the resource has settled, and then periodically so a late joiner sees it too.
    Wait(6000)
    publish()
    while true do
        Wait(10000)
        publish()
    end
end)

RegisterCommand("ncm.probe", function() publish() end, true)
