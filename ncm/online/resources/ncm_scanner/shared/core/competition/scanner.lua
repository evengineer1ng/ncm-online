-- ncm-core module: competition.scanner
-- The Scanner's two decisions, kept pure so both sides agree and both are tested offline (`L197`, `IDEA-679`).
--
--   * `step` is the CLIENT's lock: which target the reticle holds, how far the scan has progressed, and when it
--     completes. It decides nothing about knowledge; completing only means "ask the server".
--   * `admit` is the SERVER's gate on a completed scan. It is the only place a scan can become an identity
--     reveal, and it re-derives range and bucket from the server's own snapshot wherever one exists.
--
-- Discovery is gated behind the Scanner: proximity no longer reveals identity (it records sightings of machines
-- already known). A scan of a server-owned vehicle is `server_measured`. A scan of a vanilla per-client car is
-- `client_attested` (owner ruling, 2026-09-28): the server cannot see those cars at all, so it checks what it
-- can -- the record is a real catalogue machine, the claimed distance is in range -- and rate-limits the rest.
-- The basis is recorded, so every attested reveal stays distinguishable forever after.
local Core = NcmCore

Core.define("competition.scanner", function()
    local M = { version = "0.1.0" }

    M.LOCK_MS = 1500          -- hold the reticle on one machine this long
    M.RANGE_M = 60.0          -- the scan's reach; the server re-measures networked targets against it
    M.RANGE_SLACK_M = 10.0    -- a moving target's server snapshot trails the client's view; this absorbs it
    M.ATTESTED_GAP_MS = 20000 -- at most one client-attested reveal per driver per 20 s
    M.ATTESTED_PER_HOUR = 30  -- and at most this many per rolling hour

    M.KINDS = { networked = true, vanilla = true }

    -- -------------------------------------------------------------------------------------------------------
    -- Record keys. A vanilla car's record is known only to the client's redscript, as a raw TweakDBID. The
    -- identity half of a TweakDBID is CRC32-B of the record name plus its length (hash | length << 32), and
    -- the Scanner sends exactly that, as a decimal string. The server maps it back to a catalogue record here,
    -- so the catalogue never crosses the wire (`L193`) and a client cannot name a record the server did not
    -- derive for itself.
    --
    -- Portable on purpose: this runs under Lua 5.4 and LuaJIT, so no bitwise operators in the source. Where
    -- the interpreter has a native XOR (Lua 5.4's `~`, reached through `load` so LuaJIT still parses this
    -- file) it is used; otherwise XOR is a nibble table, eight lookups a word.
    --
    -- **Cost matters here** (live, 2026-09-29): the first version XORed bit by bit, ~640 VM instructions per
    -- character, and building the index over the catalogue inside a query handler blew OPEN//77's instruction
    -- quota. The handler died without replying, the index was never built, and every vanilla car read
    -- "READING..." for as long as vision stayed on.
    -- -------------------------------------------------------------------------------------------------------
    local XOR4 = {}
    for a = 0, 15 do
        for b = 0, 15 do
            local r, bit, x, y = 0, 1, a, b
            for _ = 1, 4 do
                if x % 2 ~= y % 2 then r = r + bit end
                x, y, bit = math.floor(x / 2), math.floor(y / 2), bit * 2
            end
            XOR4[a * 16 + b] = r
        end
    end

    local function bxorTable(a, b)
        local r, m = 0, 1
        for _ = 1, 8 do
            local x, y = a % 16, b % 16
            r = r + XOR4[x * 16 + y] * m
            a, b, m = (a - x) / 16, (b - y) / 16, m * 16
        end
        return r
    end

    local bxor = bxorTable
    do
        local compile = load or loadstring
        local ok, fn = pcall(function()
            local chunk = compile and compile("return function(a, b) return math.tointeger(a) ~ math.tointeger(b) end")
            return chunk and chunk()
        end)
        if ok and type(fn) == "function" and pcall(fn, 1, 3) and fn(0xEDB88320, 0xFFFFFFFF) == 0x12477CDF then
            bxor = fn
        end
    end
    M._bxorTable = bxorTable   -- exposed for tests: both paths must agree

    local CRC_TABLE = nil
    local function crcTable()
        if CRC_TABLE then return CRC_TABLE end
        CRC_TABLE = {}
        for i = 0, 255 do
            local c = i
            for _ = 1, 8 do
                if c % 2 == 1 then c = bxor(math.floor(c / 2), 0xEDB88320) else c = math.floor(c / 2) end
            end
            CRC_TABLE[i] = c
        end
        return CRC_TABLE
    end

    function M.crc32(text)
        local tbl, crc = crcTable(), 0xFFFFFFFF
        for i = 1, #text do
            crc = bxor(math.floor(crc / 256), tbl[bxor(crc % 256, text:byte(i))])
        end
        return bxor(crc, 0xFFFFFFFF)
    end

    --- The decimal string the Scanner reports for a record name. Matches `ncm_vision.dll`'s `recordKey`.
    function M.recordKey(name)
        if type(name) ~= "string" or name == "" or #name > 255 then return nil end
        return string.format("%.0f", M.crc32(name) + #name * 4294967296)
    end

    --- key -> record, for every record the catalogue knows. Built once by the server.
    function M.recordIndex(records)
        local index = {}
        for _, r in ipairs(records or {}) do
            local k = M.recordKey(r)
            if k then index[k] = r end
        end
        return index
    end

    --- The same index, a slice at a time: add records[from .. from+count-1] to `index` and return the next
    --- `from`, or nil when done. The server yields between slices so no single call nears the quota.
    function M.recordIndexStep(records, index, from, count)
        local last = math.min(#records, from + count - 1)
        for i = from, last do
            local k = M.recordKey(records[i])
            if k then index[k] = records[i] end
        end
        if last >= #records then return nil end
        return last + 1
    end

    local function num(v) return tonumber(v) end

    --- Advance the client's lock by one observation.
    --- `lock`: the previous state or nil. `obs`: { active, entity, kind, distance } or nil (nothing aimed).
    --- Returns the new state: { entity, kind, startedAt, progress (0..1), complete, reason }.
    ---   * a different entity restarts the lock; the same entity continues it;
    ---   * out of range holds the lock at zero progress with reason `out_of_range`, so the reticle can say so;
    ---   * `complete` is true exactly once per lock, on the step that reaches LOCK_MS.
    function M.step(lock, obs, nowMs)
        nowMs = num(nowMs) or 0
        if type(obs) ~= "table" or not obs.active or obs.entity == nil or obs.entity == "" then
            return { progress = 0, complete = false, reason = (type(obs) == "table" and obs.active) and "no_target" or "idle" }
        end
        if not M.KINDS[obs.kind] then
            return { progress = 0, complete = false, reason = "not_a_machine" }
        end
        local entity = tostring(obs.entity)
        local distance = num(obs.distance)
        local same = type(lock) == "table" and lock.entity == entity
        if distance == nil or distance > M.RANGE_M then
            return { entity = entity, kind = obs.kind, progress = 0, complete = false, reason = "out_of_range" }
        end
        local started = (same and num(lock.startedAt)) or nowMs
        local done = same and lock.done or false
        local progress = math.min(1, math.max(0, (nowMs - started) / M.LOCK_MS))
        local complete = false
        if progress >= 1 and not done then complete, done = true, true end
        return { entity = entity, kind = obs.kind, startedAt = started, progress = progress,
                 complete = complete, done = done, reason = done and "scanned" or "scanning" }
    end

    --- May a completed scan reveal identity? Server-side.
    --- `facts`: {
    ---   kind            "networked" | "vanilla"
    ---   recordKnown     the record resolves to a catalogue machine
    ---   sameBucket      (networked) the target is in the scanner's routing bucket, from the server snapshot
    ---   serverDistance  (networked) metres between the two, from the server's own snapshots
    ---   claimedDistance (vanilla) what the client reported
    ---   recentAttested  (vanilla) array of this driver's previous attested reveal times, ms
    ---   now             ms
    --- }
    --- Returns basis ("server_measured" | "client_attested"), or nil and a distinct reason.
    function M.admit(facts)
        if type(facts) ~= "table" then return nil, "no_facts" end
        if not facts.recordKnown then return nil, "no_ncm_record" end
        if facts.kind == "networked" then
            if not facts.sameBucket then return nil, "other_bucket" end
            local d = num(facts.serverDistance)
            if d == nil then return nil, "no_server_position" end
            if d > M.RANGE_M + M.RANGE_SLACK_M then return nil, "out_of_range" end
            return "server_measured"
        elseif facts.kind == "vanilla" then
            local d = num(facts.claimedDistance)
            if d == nil or d < 0 or d > M.RANGE_M then return nil, "out_of_range" end
            local now = num(facts.now) or 0
            local inHour, last = 0, nil
            for _, at in ipairs(facts.recentAttested or {}) do
                at = num(at)
                if at and now - at < 3600000 then
                    inHour = inHour + 1
                    if not last or at > last then last = at end
                end
            end
            if last and now - last < M.ATTESTED_GAP_MS then return nil, "attested_too_soon" end
            if inHour >= M.ATTESTED_PER_HOUR then return nil, "attested_hourly_limit" end
            return "client_attested"
        end
        return nil, "unknown_kind:" .. tostring(facts.kind)
    end

    return M
end)
