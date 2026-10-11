-- ncm-core module: world.presence
--
-- WHO ELSE IS OUT THERE, as pins on the player's own map and minimap (`IDEA-650`, `IDEA-651`, `L184`).
--
-- Pure. It decides which drivers belong on ONE viewer's map this tick, and what the client has to do to
-- the pins it already holds. `ncm_world/server/presence.lua` is the only thing that reads positions off
-- the platform; `ncm_world/client/players_map.lua` is the only thing that touches a blip.
--
-- **THE CITY TIER ONLY, BY RULING** (owner, 2026-09-27, `IDEA-654`). There were two buildable tiers and
-- only one is wanted:
--
--   * the CITY tier -- slow positional pins for everyone in your routing bucket, which is what makes a
--     five-person server feel like a city instead of an empty map. This is the one built.
--   * the FIELD tier -- pins attached to a streamed rival's body during a live session. Deliberately NOT
--     built: a driver who can see a rival's exact position through a building is being handed something
--     no mirror gives them. `Open77.blips.attachToEntity` makes it easy the day it is wanted, which is
--     exactly why the refusal is written down rather than left to look like a missing feature.
--
-- **THE DATA IS ALREADY OLD, SO THE CADENCE IS NOT A RESPONSIVENESS DIAL.** `GetPlayersPositions` /
-- `Open77.players.positions()` answers `{ [playerId] = { x, y, z, bucket } }` for every player whose
-- snapshot is *younger than two seconds*. A pin is therefore up to 2 s stale before any tick of ours adds
-- to it, and at 160 km/h 2 s is 89 m. A 1 Hz broadcast would be 3600 sends per client per hour to answer
-- "who is across town", a question that does not change in five seconds (`KB-165`: a per-tick rule is a
-- permanent rule). Five seconds is the default and it is tunable, so an operator can pay for more.
--
-- **BUCKET IS A CORRECTNESS FILTER, NOT AN OPTIMISATION.** NCM gives a race its own routing bucket
-- (`world.ambient`), and buckets are isolated -- a player in another bucket is not in your world at all.
-- A pin for one is a lie on the map, so a row only crosses when its bucket matches the viewer's. A viewer
-- with no snapshot of their own gets NOTHING, because their own bucket is unknown and guessing it is how
-- a race leaks into the street.
--
-- **BOUNDED BY MEASURED BYTES, NEAREST FIRST.** This is the payload shape that has failed four times
-- (`KB-59`, `KB-86`, `KB-153`, `KB-160`, `IDEA-595`): a list that grows until it silently stops arriving.
-- It is bounded twice here -- a pin count, because blips are a shared quota of 128 per resource and
-- `landmarks.lua` already spends one per waypointable node, and a measured byte budget. When something has
-- to go, the FARTHEST driver goes, because that is the row a viewer misses least.
--
-- A display name is player-supplied text drawn on somebody else's screen, so it is sanitized here rather
-- than at whichever end remembers to.
local Core = NcmCore

Core.define("world.presence", function()
    local M = { version = "0.0.1" }

    -- Wire schema of one row: `{ i = playerId, n = name?, x, y, z }`, coordinates in whole metres.
    -- Bumping this is how a client learns to ignore rows it cannot read.
    M.SCHEMA = 1

    M.DEFAULTS = {
        tickSeconds  = 5,      -- the duty cycle; read the header before lowering it
        maxPins      = 24,     -- blips are a quota shared with landmarks and navigation
        budgetBytes  = 3072,   -- one measured packet, never a row count
        moveEpsilonM = 3,      -- below this, a pin is not worth a native call
        nameBytes    = 24,     -- a map label, not a biography (the platform's own limit is 128)
    }

    local function clampNumber(value, fallback, min, max)
        local n = tonumber(value)
        if n == nil then n = fallback end
        if n < min then n = min elseif n > max then n = max end
        return n
    end

    function M.settings(overrides)
        overrides = type(overrides) == "table" and overrides or {}
        local d = M.DEFAULTS
        return {
            tickSeconds  = clampNumber(overrides.tickSeconds, d.tickSeconds, 2, 60),
            maxPins      = math.floor(clampNumber(overrides.maxPins, d.maxPins, 0, 96)),
            budgetBytes  = math.floor(clampNumber(overrides.budgetBytes, d.budgetBytes, 256, 16384)),
            moveEpsilonM = clampNumber(overrides.moveEpsilonM, d.moveEpsilonM, 0, 200),
            nameBytes    = math.floor(clampNumber(overrides.nameBytes, d.nameBytes, 4, 128)),
        }
    end

    --- A player-chosen name is untrusted text: strip anything unprintable, collapse whitespace, and cut it
    --- to a label. Returns nil when nothing legible survives, which the client reads as "unnamed driver"
    --- rather than drawing a pin with an empty title.
    function M.label(name, limit)
        if type(name) ~= "string" then return nil end
        local clean = name:gsub("%c", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
        if clean == "" then return nil end
        limit = math.floor(tonumber(limit) or M.DEFAULTS.nameBytes)
        if #clean > limit then clean = clean:sub(1, limit):gsub(" $", "") end
        return clean ~= "" and clean or nil
    end

    --- The fallback measure, for a host with no encoder to lend. Deliberately pessimistic: the fixed part
    --- is the JSON skeleton of `{"i":,"n":"","x":,"y":,"z":}` with room for six-figure coordinates, so an
    --- estimate can be wrong without being wrong in the dangerous direction.
    function M.bytes(row)
        if type(row) ~= "table" then return 0 end
        return 38 + (type(row.n) == "string" and #row.n or 0)
    end

    local function planar(a, b)
        local dx, dy = (tonumber(a.x) or 0) - (tonumber(b.x) or 0), (tonumber(a.y) or 0) - (tonumber(b.y) or 0)
        return math.sqrt(dx * dx + dy * dy)
    end

    local function whole(n) return math.floor((tonumber(n) or 0) + 0.5) end

    --- Read a positions table by player id whichever way the host keyed it. The platform answers integer
    --- keys; a stub, a JSON round-trip and a test each have their own opinion, and a silent miss here would
    --- look exactly like "nobody is online".
    local function at(positions, id)
        if type(positions) ~= "table" then return nil end
        return positions[id] or positions[tostring(id)] or positions[tonumber(id) or -1]
    end

    local function bucketOf(row) return tonumber(row and row.bucket) or 0 end

    --- The rows one viewer should receive this tick.
    ---
    --- `positions` is `Open77.players.positions()` as given. `opts.nameFor(playerId)` may return a display
    --- name; `opts.measure(row)` may return a row's true encoded size. Returns `rows, note`, where the note
    --- is diagnostic only -- it exists so a log can say why a map looks emptier than the roster.
    function M.rowsFor(viewerId, positions, opts)
        opts = type(opts) == "table" and opts or {}
        local set = M.settings(opts.settings or opts)
        local measure = type(opts.measure) == "function" and opts.measure or M.bytes
        local note = { considered = 0, sent = 0, droppedForCount = 0, droppedForBytes = 0, bytes = 0 }

        viewerId = tonumber(viewerId)
        local viewer = viewerId and at(positions, viewerId) or nil
        if type(viewer) ~= "table" or tonumber(viewer.x) == nil then
            -- No snapshot of our own means no known bucket, and sending the whole server's positions on a
            -- guess is the one mistake here that cannot be walked back.
            note.reason = "viewer_unlocated"
            return {}, note
        end
        local viewerBucket = bucketOf(viewer)

        local candidates = {}
        for key, pos in pairs(type(positions) == "table" and positions or {}) do
            local id = tonumber(key)
            if id and id ~= viewerId and type(pos) == "table" and tonumber(pos.x) then
                note.considered = note.considered + 1
                if bucketOf(pos) == viewerBucket then
                    candidates[#candidates + 1] = { id = id, pos = pos, d = planar(pos, viewer) }
                end
            end
        end
        -- Nearest first, then by id. The order decides who survives a cap, so it must not depend on
        -- `pairs` iteration order, or two clients would disagree about who is on the map.
        table.sort(candidates, function(a, b)
            if a.d ~= b.d then return a.d < b.d end
            return a.id < b.id
        end)

        local rows = {}
        for _, c in ipairs(candidates) do
            if #rows >= set.maxPins then
                note.droppedForCount = note.droppedForCount + 1
            else
                local row = { i = c.id, x = whole(c.pos.x), y = whole(c.pos.y), z = whole(c.pos.z) }
                local name = opts.nameFor and M.label(opts.nameFor(c.id), set.nameBytes) or nil
                if name then row.n = name end
                local size = tonumber(measure(row)) or 0
                if size <= 0 then size = M.bytes(row) end
                if note.bytes + size > set.budgetBytes and #rows > 0 then
                    note.droppedForBytes = note.droppedForBytes + 1
                else
                    rows[#rows + 1] = row
                    note.bytes = note.bytes + size
                    note.farthestM = math.floor(c.d)
                end
            end
        end
        note.sent = #rows
        return rows, note
    end

    --- What the client must do to the pins it already holds. Pure, so that the quota discipline -- never
    --- recreate a pin you can move -- is a tested property rather than a habit of whoever wrote the client.
    ---
    --- `pins` is `playerId -> { x, y, z, n }` for the pins that exist now.
    function M.reconcile(pins, rows, opts)
        pins = type(pins) == "table" and pins or {}
        rows = type(rows) == "table" and rows or {}
        local set = M.settings(opts and (opts.settings or opts) or nil)
        local plan = { create = {}, move = {}, retitle = {}, remove = {} }
        local keep = {}

        for _, row in ipairs(rows) do
            local id = tonumber(row.i)
            if id then
                keep[id] = true
                local held = pins[id] or pins[tostring(id)]
                if type(held) ~= "table" then
                    plan.create[#plan.create + 1] = row
                else
                    if planar(row, held) >= set.moveEpsilonM then plan.move[#plan.move + 1] = row end
                    if (row.n or "") ~= (held.n or "") then plan.retitle[#plan.retitle + 1] = row end
                end
            end
        end

        for key in pairs(pins) do
            local id = tonumber(key)
            if id and not keep[id] then plan.remove[#plan.remove + 1] = id end
        end
        table.sort(plan.remove)
        return plan
    end

    return M
end)
