-- ncm_league / server / stream -- one bounded server-to-client transport for every payload that carries a list.
--
-- KB-59, KB-86, KB-153 and KB-160 are four instances of one bug. A payload grows; it crosses a size ceiling
-- nobody has measured; and it then vanishes with no error, no return value and no log line, leaving the panel
-- showing its empty placeholder. Three of those four were "fixed" by making that one payload smaller, which is
-- a fix with a shelf life, and the fourth (KB-160) recurred at the identical seventeen rows because the ROWS had
-- grown rather than multiplied.
--
-- So the rule is structural rather than per-payload: a payload with a list is sent as a small head plus numbered
-- row packets, and the packets are packed by MEASURED BYTES. Row counts cannot see growth; bytes can.
--
-- The head is the one piece that cannot be split, and it is exactly where KB-86's twenty rows of history sat, so
-- it carries its own tripwire. Anything unbounded that lands in a head will eventually be the thing that breaks.
NcmStream = {}

local Chunks = NcmCore.get("vocabulary.chunks")
local Json = NcmCore.get("vocabulary.json")

local function log(fmt, ...) print(("[ncm_league/stream] " .. fmt):format(...)) end

-- A third of the largest payload ever observed to arrive whole (17,918 bytes), so there is real room between a
-- packet and the ceiling nobody has measured. Not a platform limit -- a deliberately conservative budget.
NcmStream.PACKET_BUDGET_BYTES = 6 * 1024
NcmStream.HEAD_WARN_BYTES = 6 * 1024

--- Encoded size in bytes, or -1 when the value cannot be encoded at all. Server-side only: encoding here is
--- cheap, whereas doing it in a client script slice exceeds the execution budget (KB-63).
function NcmStream.bytes(value)
    local ok, encoded = pcall(Json.encode, value)
    return (ok and type(encoded) == "string") and #encoded or -1
end

local seq = 0

--- Send `payload` to `pid` as a bounded stream on `channel`, splitting the array at `payload[listKey]`.
--- Emits `<channel>.stream.begin { id, head, parts, count }` then `<channel>.stream.part { id, index, items }`.
--- Returns the total encoded size, the head size and the packet count, for the caller's own log line.
function NcmStream.send(pid, channel, payload, listKey, opts)
    if not pid or type(payload) ~= "table" then return -1, -1, 0 end
    opts = opts or {}
    local budget = tonumber(opts.budget) or NcmStream.PACKET_BUDGET_BYTES
    local headWarn = tonumber(opts.headWarn) or NcmStream.HEAD_WARN_BYTES
    local list = type(payload[listKey]) == "table" and payload[listKey] or {}

    local total = NcmStream.bytes(payload)
    if total < 0 then
        -- A payload we cannot even encode locally will certainly not survive the wire. Say so: this is the one
        -- failure mode that used to be indistinguishable from an empty panel.
        log("PAYLOAD NOT ENCODABLE channel=%s player=%s rows=%d", channel, tostring(pid), #list)
    end

    local head = {}
    for k, v in pairs(payload) do if k ~= listKey then head[k] = v end end
    local headBytes = NcmStream.bytes(head)
    if headBytes > headWarn then
        log("HEAD LARGE channel=%s player=%s bytes=%d (warn above %d) -- the head is NOT split; move this field " ..
            "into a row, a separate event or a bounded projection before it drops the whole stream",
            channel, tostring(pid), headBytes, headWarn)
    end

    seq = seq + 1
    local id = ("%d:%d:%s"):format(math.floor(Open77.time.unix()), seq, tostring(pid))
    -- The budget bounds the whole packet on the wire, envelope included (KB-228): measure the envelope with the
    -- largest index it can carry and reserve it.
    local reserve = NcmStream.bytes({ id = id, index = math.max(1, #list), items = {} }) - 2
    local packets, oversized = Chunks.partitionBytes(list, budget, NcmStream.bytes, reserve)
    for _, o in ipairs(oversized) do
        log("ROW OVERSIZED channel=%s player=%s row=%d bytes=%d (budget %d) -- sent alone; one row must never " ..
            "approach the ceiling", channel, tostring(pid), o.index, o.bytes, budget)
    end

    TriggerClientEvent(channel .. ".stream.begin", pid, { id = id, head = head, parts = #packets, count = #list })
    for i, items in ipairs(packets) do
        TriggerClientEvent(channel .. ".stream.part", pid, { id = id, index = i, items = items })
    end
    return total, headBytes, #packets
end
