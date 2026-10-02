-- ncm-core module: competition.race_builder
-- A driver calling their own race: ONE FORM, submitted once (`L181`, superseding `L179`'s interaction shape).
--
-- WHAT THIS WAS, AND WHY IT CHANGED. The first version recovered single player's Foreman constructor faithfully:
-- a six-step machine whose whole state is one integer, each step a flat list of at most five final acts. That was
-- an accurate port and the wrong product. The owner's correction (2026-09-27) is worth keeping verbatim because
-- three separate things were wrong and only one of them was the page count:
--
--   * **"here" is the sane default.** The old builder could only start a race at an authored node, so calling a
--     race where you stand was the one thing it could not do. *"Someone starting a race here and now is not 'ok
--     lets drive 2 km to race start together'."* The start is now the driver's own position unless they say
--     otherwise, and it becomes a temporary node.
--   * **Do not hide the rest.** Offering four nearest routes, *"of which none are guaranteed near"*, is
--     restrictive in both directions at once. The whole node list is exposed, for the start and for the finish.
--   * **Do not ask what type.** *"How do we enforce a drag race?"* -- we cannot. There are no lanes, no staging
--     and no christmas tree, so a discipline picker asked the player to choose something the server could not
--     honour. See `M.DISCIPLINE`.
--   * **One form, not six pages.** A six-page click-through is *"hardly quick"*, which is fatal for a feature
--     whose entire premise is immediacy.
--
-- THE `venue_options` CEILING DOES NOT APPLY HERE, and that is the owner's call, not an oversight. That ruling
-- governs *the prompt you get standing at a venue* -- at most five options, each a final act. This is a form the
-- driver opened deliberately from a hotkey, so it may carry a full list and a submit button. `L179` inherited the
-- ceiling by analogy and the analogy was wrong.
--
-- A ROUTE IS A LIST OF POINTS, which the host already knows how to turn into a course: the `/ncm.ar` host kit
-- authors routes exactly this way (`scenario.lua::registerCustom`), so chaining checkpoints needs no new concept
-- and no new table -- just a longer list. This module produces that list and validates it; it holds no position,
-- reads no database, renders nothing and creates no event.
local Core = NcmCore

Core.define("competition.race_builder", function(C)
    local M = { version = "0.2.0" }
    local Class = C.get("competition.class")
    local Nodes = C.get("data.nodes")
    local Routes = C.get("course.routes")

    --- The sentinel for "where I am standing". Not a node id, and deliberately not a coordinate either: the form
    --- carries the INTENT and the host resolves it against a fresh position at submit time, so a form left open
    --- for five minutes starts the race where the driver is when they confirm, not where they were when they asked.
    M.START_HERE = "__here__"

    --- Derived, never asked. Every player-called race is a point-to-point street sprint because that is the only
    --- discipline whose rules this server can actually enforce: `p2p` needs a start, an ordered gate list and a
    --- finish, all of which a form can express. `drag` needs staged lanes and a launch procedure, `oval` needs a
    --- closed circuit with lap counting, `drift` needs judging. Asking a driver to pick one of those and then
    --- running a sprint regardless would be a lie told in a dropdown.
    M.DISCIPLINE = "street_sprint"

    --- One race, no weekend. A qualifying session called from a street corner is not an impromptu race.
    M.FORMAT = "sprint"

    --- How many checkpoints may be chained between the start and the finish. Bounded because each one becomes a
    --- gate the race kernel evaluates and a point in the route payload, not because a driver would want fewer.
    M.MAX_CHECKPOINTS = 8

    --- Offered in the "green in" dropdown. A race called for *now* cannot be travelled to by anyone else, and one
    --- an hour out is not impromptu -- but 2 minutes is a legitimate "we are both already here" choice.
    M.WHEN_MINUTES = { 2, 5, 10, 20 }
    M.MIN_REMOTE_MINUTES = 5     -- below this, the start must be where the caller is standing
    -- L249 (owner, 2026-10-01): a time trial is ON DEMAND here -- it is no longer what happens when a driver enters a
    -- race alone. A called race is announced to everyone; a time trial is the caller alone, against the clock.
    M.MODES = { { id = "race", label = "Race (announced to everyone)" }, { id = "time_trial", label = "Time trial (alone)" } }
    M.NEAR_START_M = 150

    --- The shortest race worth posting, in metres. A 40 m sprint between two adjacent points is not a race and
    --- would settle in a way nothing downstream expects.
    M.MIN_DISTANCE_M = 250

    local function nonempty(v) return type(v) == "string" and v:match("%S") ~= nil end

    local function posInt(v)
        local n = tonumber(v)
        if n == nil or n ~= n then return nil end
        n = math.floor(n)
        if n < 0 then return nil end
        return n
    end

    local function hasPosition(facts)
        local p = facts and facts.position
        return type(p) == "table" and tonumber(p.x) ~= nil and tonumber(p.y) ~= nil
    end

    -- ---------------------------------------------------------------------------------------------
    -- What the form offers. Complete lists, ordered for convenience -- never truncated.
    -- ---------------------------------------------------------------------------------------------

    --- Every node a race may legally start or finish at. `raceLegal` is the authored flag; runtime nodes created
    --- for a previous Street Call do not carry it, which is what keeps yesterday's temporary start lines out of
    --- today's list without needing to remember them.
    ---
    --- Ordered nearest-first when a position is known, so the useful entries are at the top of a 35-row dropdown,
    --- and alphabetically otherwise so the list is stable. **Ordering is a courtesy; the list is complete.**
    function M.nodeOptions(facts)
        local rows = {}
        for _, n in ipairs(Nodes.LIST) do
            if n.raceLegal == true then
                local d = nil
                if hasPosition(facts) then d = Routes.planarDistance(facts.position, n) end
                rows[#rows + 1] = { id = n.id, name = n.name or n.id, region = n.region or "", distanceM = d,
                                    x = n.x, y = n.y }
            end
        end
        table.sort(rows, function(a, b)
            if a.distanceM and b.distanceM and a.distanceM ~= b.distanceM then return a.distanceM < b.distanceM end
            if (a.distanceM == nil) ~= (b.distanceM == nil) then return a.distanceM ~= nil end
            if a.name ~= b.name then return a.name < b.name end
            return a.id < b.id
        end)
        local out = {}
        for i, r in ipairs(rows) do
            local label = r.name
            if r.region ~= "" then label = label .. " · " .. r.region end
            if r.distanceM then label = ("%s · %.1f km"):format(label, r.distanceM / 1000) end
            -- `x`/`y` ride along so the FORM can show a running route length as points are chained, without a
            -- round trip per change. It is a preview: `M.spec` recomputes the real length server-side and refuses
            -- a route under `M.MIN_DISTANCE_M` regardless of what any client displayed.
            out[i] = { id = r.id, label = label, name = r.name, region = r.region, distanceM = r.distanceM,
                       x = r.x, y = r.y }
        end
        return out
    end

    --- The start list is the node list with HERE on the front. HERE is first because it is the default and the
    --- common case, not because it is special.
    function M.startOptions(facts)
        local out = { { id = M.START_HERE, label = "Here — where I am standing", name = "Here", here = true } }
        for _, o in ipairs(M.nodeOptions(facts)) do out[#out + 1] = o end
        return out
    end

    --- The finish list is the node list, with no HERE. A finish where the caller is standing is the start, and a
    --- race that ends where it begins is a loop -- which is expressed by choosing the same node, not by a second
    --- "here" that would mean something different at submit time (owner: the end *"doesnt need a here node"*).
    function M.finishOptions(facts) return M.nodeOptions(facts) end

    function M.classOptions()
        local out = {}
        for _, c in ipairs(Class.LIST) do
            -- a street event admits street cars; another pack's class is not offerable from a street corner
            if c.enabled and c.packId == "ncm_pack_street" then out[#out + 1] = { id = c.id, label = c.name } end
        end
        return out
    end

    function M.whenOptions()
        local out = {}
        for i, m in ipairs(M.WHEN_MINUTES) do out[i] = { id = m, label = ("In %d min"):format(m) } end
        return out
    end

    --- Everything the page needs to draw the whole form in one pass, so the client holds no catalogue of its own
    --- and cannot drift from the server's idea of what is offerable.
    function M.schema(facts)
        return {
            start = M.startOptions(facts),
            finish = M.finishOptions(facts),
            class = M.classOptions(),
            when = M.whenOptions(),
            mode = M.MODES,
            maxCheckpoints = M.MAX_CHECKPOINTS,
            minDistanceM = M.MIN_DISTANCE_M,
            hasPosition = hasPosition(facts),
        }
    end

    -- ---------------------------------------------------------------------------------------------
    -- The wire form of the schema (`KB-172`)
    -- ---------------------------------------------------------------------------------------------
    --
    -- `M.schema` is the shape the PAGE wants and it is not the shape the WIRE can carry. Two facts force a
    -- split, and neither is negotiable:
    --
    --   * **A player state bag holds 4,032 bytes** (`IDEA-509`: 4,032 accepted, ~5,010 refused). One schema is
    --     11,515 -- `start` alone is 5,579 -- so the bag was refused every time and `ncmBuild` never replicated.
    --     That is `KB-172`, and it is the fifth instance of the payload-grew-and-vanished bug that
    --     `ncm_league/server/stream.lua` exists to end.
    --   * **`start` and `finish` are the same list.** `startOptions` is `HERE` prepended to `nodeOptions`;
    --     `finishOptions` IS `nodeOptions`. Sending both sent 35 identical rows twice for one sentinel's
    --     difference.
    --
    -- So the wire carries the node list ONCE, as the stream's row array, plus a small head. The client calls
    -- `M.schemaFromWire` and gets a value identical to `M.schema`, so nothing downstream of it -- `build.html`
    -- above all -- knows this happened.

    --- The head: everything in the schema that is NOT the node list, plus the blank form the page starts from.
    --- Bounded by construction (two classes, four start times, five scalars), which is what a stream head must
    --- be -- `NcmStream` cannot split a head, and an unbounded one is the next instance of this same bug.
    function M.wire(facts)
        return {
            nodes = M.nodeOptions(facts),
            class = M.classOptions(),
            when = M.whenOptions(),
            mode = M.MODES,
            maxCheckpoints = M.MAX_CHECKPOINTS,
            minDistanceM = M.MIN_DISTANCE_M,
            hasPosition = hasPosition(facts),
            form = M.blank(facts),
        }
    end

    --- Rebuild the page's schema from a received wire payload. The inverse of `M.wire`, and deliberately total:
    --- a stream that arrived with no rows yields empty lists rather than nil, because the page renders a schema
    --- and must never be handed one with holes in it.
    function M.schemaFromWire(value)
        value = type(value) == "table" and value or {}
        local nodes = type(value.nodes) == "table" and value.nodes or {}
        local start = { { id = M.START_HERE, label = "Here — where I am standing", name = "Here", here = true } }
        for _, o in ipairs(nodes) do start[#start + 1] = o end
        return {
            start = start,
            finish = nodes,
            class = type(value.class) == "table" and value.class or {},
            when = type(value.when) == "table" and value.when or {},
            mode = type(value.mode) == "table" and value.mode or M.MODES,
            maxCheckpoints = tonumber(value.maxCheckpoints) or M.MAX_CHECKPOINTS,
            minDistanceM = tonumber(value.minDistanceM) or M.MIN_DISTANCE_M,
            hasPosition = value.hasPosition == true,
        }
    end

    --- A fresh form. The start is HERE, which is the whole point of `L181`.
    function M.blank(facts)
        facts = type(facts) == "table" and facts or {}
        local classes = M.classOptions()
        return {
            start = M.START_HERE,
            checkpoints = {},
            finish = nil,
            classId = classes[1] and classes[1].id or "street_open",
            minutes = 5,
            laps = 1,
            mode = "race",
            creatorId = facts.creatorId,
            createdAt = posInt(facts.now),
        }
    end

    -- ---------------------------------------------------------------------------------------------
    -- Validation and the point list
    -- ---------------------------------------------------------------------------------------------

    local function legalNode(id)
        local n = Nodes.byId(id)
        if n and n.raceLegal == true then return n end
        return nil
    end

    --- Validate and fill in a submitted form. Returns the normalised form, or nil and a reason slug.
    --- Reasons are distinct on purpose: the page shows them, and "you have not chosen a finish" and "that finish
    --- is not a place a race may end" are different mistakes.
    function M.normalize(form, facts)
        if type(form) ~= "table" then return nil, "form_not_table" end
        facts = type(facts) == "table" and facts or {}

        local startId = tostring(form.start or M.START_HERE)
        if startId == M.START_HERE then
            if not hasPosition(facts) then return nil, "position_unknown" end
        elseif not legalNode(startId) then
            return nil, "invalid_start"
        end

        if not nonempty(form.finish) then return nil, "finish_required" end
        local finishNode = legalNode(form.finish)
        if not finishNode then return nil, "invalid_finish" end

        local checkpoints = {}
        local raw = type(form.checkpoints) == "table" and form.checkpoints or {}
        if #raw > M.MAX_CHECKPOINTS then return nil, "too_many_checkpoints" end
        for _, id in ipairs(raw) do
            local n = legalNode(id)
            if not n then return nil, "invalid_checkpoint" end
            checkpoints[#checkpoints + 1] = tostring(id)
        end

        -- A leg of zero length is not a leg. Only ADJACENT repeats are refused: passing the same point twice on a
        -- figure-of-eight is a legitimate route, and forbidding it would rule out a whole shape of race for no
        -- reason. Start == finish is likewise allowed -- that is a loop, and it is why `laps` exists.
        local seq = { startId }
        for _, id in ipairs(checkpoints) do seq[#seq + 1] = id end
        seq[#seq + 1] = tostring(form.finish)
        for i = 2, #seq do
            if seq[i] == seq[i - 1] then return nil, "repeated_point" end
        end

        local classes = M.classOptions()
        local classId = tostring(form.classId or "")
        local classOk = false
        for _, c in ipairs(classes) do if c.id == classId then classOk = true end end
        if not classOk then return nil, "invalid_class" end

        local minutes = posInt(form.minutes)
        if not minutes then return nil, "invalid_minutes" end
        local minutesOk = false
        for _, m in ipairs(M.WHEN_MINUTES) do if m == minutes then minutesOk = true end end
        if not minutesOk then return nil, "invalid_minutes" end
        -- Entries close when the grid forms, a minute before green, so a 2-minute call leaves ONE minute to reach
        -- the line and enter. That only works when the start is where the caller already is; from across town the
        -- call closes empty while they are still driving to it (owner, 2026-09-28: two calls lost this way).
        if minutes < M.MIN_REMOTE_MINUTES and startId ~= M.START_HERE then
            local node = Nodes.byId(startId)
            local p = hasPosition(facts) and facts.position or nil
            local dx = p and node and (tonumber(p.x) - (tonumber(node.x) or 0)) or nil
            local dy = p and node and (tonumber(p.y) - (tonumber(node.y) or 0)) or nil
            if not dx or math.sqrt(dx * dx + dy * dy) > M.NEAR_START_M then return nil, "too_soon_for_start" end
        end

        local laps = posInt(form.laps) or 1
        if laps < 1 then laps = 1 end
        -- laps only mean anything on a closed route; a point-to-point run of 3 laps is not representable
        if startId ~= tostring(form.finish) then laps = 1 end

        local mode = (form.mode == nil or form.mode == "race") and "race" or tostring(form.mode)
        local modeOk = false
        for _, m in ipairs(M.MODES) do if m.id == mode then modeOk = true end end
        if not modeOk then return nil, "invalid_mode" end

        return {
            start = startId,
            checkpoints = checkpoints,
            finish = tostring(form.finish),
            classId = classId,
            minutes = minutes,
            laps = laps,
            mode = mode,
            creatorId = form.creatorId,
            createdAt = posInt(form.createdAt),
        }
    end

    --- The ordered point list for the host's route registrar, in `scenario.lua::registerCustom` shape:
    --- `{ {x, y, z, heading, name}, ... }`, start first, finish last, checkpoints between.
    ---
    --- This is the output that matters. Everything above is about producing a correct one.
    function M.points(form, facts)
        local f, why = M.normalize(form, facts)
        if not f then return nil, why end
        local pts = {}
        if f.start == M.START_HERE then
            local p = facts.position
            pts[1] = {
                x = tonumber(p.x), y = tonumber(p.y), z = tonumber(p.z) or 0,
                heading = tonumber(p.heading) or 0, name = "Street start", here = true,
            }
        else
            local n = Nodes.byId(f.start)
            pts[1] = { x = n.x, y = n.y, z = n.z or 0, heading = n.heading or 0, name = n.name or f.start }
        end
        for _, id in ipairs(f.checkpoints) do
            local n = Nodes.byId(id)
            pts[#pts + 1] = { x = n.x, y = n.y, z = n.z or 0, heading = n.heading or 0, name = n.name or id }
        end
        local fin = Nodes.byId(f.finish)
        pts[#pts + 1] = { x = fin.x, y = fin.y, z = fin.z or 0, heading = fin.heading or 0, name = fin.name or f.finish }
        return pts, nil, f
    end

    --- Path length of the point list, in metres: the sum of the legs, not the crow-flies distance between the ends.
    function M.distanceM(points)
        local total = 0
        for i = 2, #(points or {}) do total = total + Routes.planarDistance(points[i - 1], points[i]) end
        return total
    end

    --- A name for the route, built from its ends. Used as the event's route name and in every announcement.
    function M.routeName(form, facts)
        local f = M.normalize(form, facts)
        if not f then return "Street Call" end
        local fromName = "Here"
        if f.start ~= M.START_HERE then
            local n = Nodes.byId(f.start)
            fromName = (n and n.name) or f.start
        end
        local fin = Nodes.byId(f.finish)
        local toName = (fin and fin.name) or f.finish
        if f.start == f.finish then return ("%s loop"):format(toName) end
        return ("%s → %s"):format(fromName, toName)
    end

    --- The form read back as text, for chat and for the confirmation line.
    function M.summary(form, facts)
        local pts, why, f = M.points(form, facts)
        if not pts then return nil, why end
        local lines = {
            ("Street Call · %s"):format(M.routeName(form, facts)),
            ("Distance: %.1f km%s"):format(M.distanceM(pts) / 1000, f.laps > 1 and (" × " .. f.laps .. " laps") or ""),
        }
        if #f.checkpoints > 0 then
            local names = {}
            for i, id in ipairs(f.checkpoints) do
                local n = Nodes.byId(id)
                names[i] = (n and n.name) or id
            end
            lines[#lines + 1] = ("Via: %s"):format(table.concat(names, ", "))
        end
        local className = f.classId
        for _, c in ipairs(M.classOptions()) do if c.id == f.classId then className = c.label end end
        lines[#lines + 1] = ("Open to: %s"):format(className)
        lines[#lines + 1] = ("Green: in %d min"):format(f.minutes)
        return table.concat(lines, "\n"), nil, f
    end

    --- The host's description of the event to create. NOT an event: no id, no venue, no state, no persistence.
    --- `points` is the whole route; the host registers it and resolves it exactly as it does an authored one.
    function M.spec(form, facts)
        local pts, why, f = M.points(form, facts)
        if not pts then return nil, why end
        local distance = M.distanceM(pts)
        if distance < M.MIN_DISTANCE_M then return nil, "too_short" end
        return {
            class = "impromptu",
            disciplineId = M.DISCIPLINE,
            formatId = M.FORMAT,
            classId = f.classId,
            points = pts,
            routeName = M.routeName(form, facts),
            distanceM = distance,
            laps = f.laps,
            loop = f.start == f.finish,
            startsHere = f.start == M.START_HERE,
            minutes = f.minutes,
            mode = f.mode or "race",       -- L249: "time_trial" = the caller alone, on demand
            creatorId = f.creatorId,
        }
    end

    return M
end)
