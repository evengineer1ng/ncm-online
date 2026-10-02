-- ncm_paddock / server / stream -- the bounded list transport, restated for this VM.
--
-- A byte-for-byte copy of `ncm_league/server/stream.lua`'s protocol (head + numbered byte-packed row packets,
-- KB-59/86/153/160), on channel `ncm:paddock`. It is a copy and not a call because resources do not share memory.
-- `ncm_world/client/panel.lua` reassembles it with the same `receiveStream` it uses for the league.
PaddockStream = {}

local Chunks = NcmCore.get("vocabulary.chunks")
local Json = NcmCore.get("vocabulary.json")
local log = PaddockUtil.logger("stream")

PaddockStream.PACKET_BUDGET_BYTES = 6 * 1024
PaddockStream.HEAD_WARN_BYTES = 6 * 1024

function PaddockStream.bytes(value)
    local ok, encoded = pcall(Json.encode, value)
    return (ok and type(encoded) == "string") and #encoded or -1
end

local seq = 0

function PaddockStream.send(pid, channel, payload, listKey)
    if not pid or type(payload) ~= "table" then return -1, -1, 0 end
    local list = type(payload[listKey]) == "table" and payload[listKey] or {}
    local head = {}
    for k, v in pairs(payload) do if k ~= listKey then head[k] = v end end
    local headBytes = PaddockStream.bytes(head)
    if headBytes > PaddockStream.HEAD_WARN_BYTES then
        log("HEAD LARGE channel=%s player=%s bytes=%d -- move this into rows", channel, tostring(pid), headBytes)
    end
    seq = seq + 1
    local id = ("%d:%d:%s"):format(PaddockUtil.now(), seq, tostring(pid))
    -- the whole packet on the wire stays inside the budget, envelope included (KB-228)
    local reserve = PaddockStream.bytes({ id = id, index = math.max(1, #list), items = {} }) - 2
    local packets, oversized = Chunks.partitionBytes(list, PaddockStream.PACKET_BUDGET_BYTES, PaddockStream.bytes, reserve)
    for _, o in ipairs(oversized) do
        log("ROW OVERSIZED channel=%s player=%s row=%d bytes=%d", channel, tostring(pid), o.index, o.bytes)
    end
    TriggerClientEvent(channel .. ".stream.begin", pid, { id = id, head = head, parts = #packets, count = #list })
    for i, items in ipairs(packets) do
        TriggerClientEvent(channel .. ".stream.part", pid, { id = id, index = i, items = items })
    end
    return headBytes, #packets
end
