-- ncm-core module: data.vehicle_templates
-- Which model string draws a given car as a CLIENT-LOCAL PROP, so a ghost wears the car its lap was set in.
--
-- **Why this is a candidate list and not a lookup.** No API card for `Open77.props.create` was ever captured,
-- and the two written sources conflict: the curated catalogue says the alias table is *"a CONVENIENCE, not a
-- whitelist: any string the client can resolve -- including a raw depot path -- is accepted"*, while the Batch 1
-- tester window recorded *"raw `.ent` templates disabled"*. Neither settles what a vehicle template does. So
-- this module answers with an ORDERED LIST of strings to try, the client reports which one drew, and the
-- winner is then authored into `OVERRIDE` as evidence rather than as a guess.
--
-- This matters because of `KB-14`: `props.create` returns a SUCCESSFUL ID for a model it cannot resolve, and
-- every client then fails projection with `template_backend_disabled` and nothing appears. A single guessed
-- model string would therefore fail silently and look like a broken ghost feature.
local Core = NcmCore

Core.define("data.vehicle_templates", function(C)
    local M = { version = "0.0.1" }

    --- The last candidate, always tried, never absent.
    ---
    --- `race.route_arrow` is a curated alias whose MESH HOST is known to spawn -- Batch 1 observed it drawing
    --- as a flat rectangle on the road, because the host drew and only its hologram material did not. That
    --- makes it the one thing in the catalogue we can state will appear. A ghost that falls back to it is
    --- visibly wrong and obviously not a car, which is the correct failure: a driver sees that something is
    --- off and the log says which record had no template.
    M.FALLBACK = "race.route_arrow"

    --- Model strings proven live, keyed by TweakDB record. **Authored only from an observed projection**, one
    --- row per confirmed record, never from inference. Empty until the first live session fills it.
    M.OVERRIDE = {}

    --- Folder under `base\vehicles` for a class token: `sport2` -> `sport`, `standard25` -> `standard`,
    --- `sportbike1` -> `sportbike`. The trailing digits are a variant index, not part of the path.
    local function folderFor(classToken)
        if type(classToken) ~= "string" then return nil end
        return classToken:match("^(%a+)")
    end

    --- Split `Vehicle.v_sport2_mizutani_shion_player` into its basename and class token.
    --- Returns `v_sport2_mizutani_shion`, `sport2` -- the `_player` suffix is a TweakDB record variant and is
    --- not part of the entity template's name.
    function M.parseRecord(record)
        if type(record) ~= "string" then return nil, "not_a_string" end
        local base = record:match("^Vehicle%.(.+)$")
        if not base then return nil, "not_a_vehicle_record" end
        base = base:gsub("_player$", "")
        -- AVs (`Vehicle.av_zetatech_atlus`, 2026-10-12; `av_trauma` never projected on a client) live under base\vehicles\special
        if base:match("^av_") then return base, "special" end
        local token = base:match("^v_(%a+%d*)_")
        if not token then return nil, "no_class_token" end
        return base, token
    end

    --- Every model string worth trying for this record, best first.
    ---
    --- Order is deliberate: proven evidence, then the record itself (cheapest to be true -- the native layer
    --- may resolve a TweakDB record directly), then the depot paths, then the fallback. The two depot shapes
    --- differ only by a trailing underscore, which some stock vehicle templates carry and some do not; trying
    --- both costs one refused projection and removes a whole class of near-miss.
    function M.candidates(record)
        local out = {}
        local function add(s)
            if type(s) == "string" and s ~= "" then
                for i = 1, #out do
                    if out[i] == s then return end
                end
                out[#out + 1] = s
            end
        end

        add(M.OVERRIDE[record])
        add(record)

        local base, token = M.parseRecord(record)
        if base then
            local folder = folderFor(token)
            if folder then
                add("base\\vehicles\\" .. folder .. "\\" .. base .. "_.ent")
                add("base\\vehicles\\" .. folder .. "\\" .. base .. ".ent")
            end
        end

        add(M.FALLBACK)
        return out
    end

    --- The single best guess, for a caller that wants one string and will accept the fallback.
    function M.ghostModelFor(record)
        local list = M.candidates(record)
        return list[1], list
    end

    --- Did this record fall all the way through to the fallback? The client logs this, because a ghost drawn
    --- as a road arrow is a missing template and not a missing feature.
    function M.isFallback(model)
        return model == M.FALLBACK
    end

    --- Authoring faults, asserted empty by the offline gate.
    ---
    --- Collected rather than raised for the same reason `data.vehicle_catalogue` collects its own: this module
    --- loads at resource start, and one unparseable record must not take the league service down.
    function M.validate()
        local faults = {}
        local pool = C.get("data.vehicle_pool")
        local catalogue = C.get("data.vehicle_catalogue")

        for _, p in ipairs(pool.allRecords()) do
            local list = M.candidates(p.id)
            if #list < 2 then
                faults[#faults + 1] = ("record %s yielded only %d candidate(s)"):format(p.id, #list)
            end
            if list[#list] ~= M.FALLBACK then
                faults[#faults + 1] = ("record %s does not end in the fallback"):format(p.id)
            end
            if not M.parseRecord(p.id) then
                faults[#faults + 1] = ("record %s does not parse into a template basename"):format(p.id)
            end
        end

        for record in pairs(M.OVERRIDE) do
            if not catalogue.resolveRecord(record) then
                faults[#faults + 1] = ("OVERRIDE names %s, which no machine claims"):format(record)
            end
            if type(M.OVERRIDE[record]) ~= "string" or M.OVERRIDE[record] == "" then
                faults[#faults + 1] = ("OVERRIDE for %s is not a model string"):format(record)
            end
        end

        return faults
    end

    return M
end)
