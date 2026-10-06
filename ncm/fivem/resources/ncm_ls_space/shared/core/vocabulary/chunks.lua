-- Bounded list transport. The network and WebUI bridges both fail opaquely on large payloads, so callers
-- send whole rows in small packets and rebuild them by numbered part. No JSON work belongs in Lua here.
NcmCore.define("vocabulary.chunks", function()
    local M = {}

    function M.partition(list, rowsPerPart)
        list = type(list) == "table" and list or {}
        rowsPerPart = math.max(1, math.floor(tonumber(rowsPerPart) or 1))
        local out = {}
        for first = 1, #list, rowsPerPart do
            local part = {}
            for i = first, math.min(first + rowsPerPart - 1, #list) do part[#part + 1] = list[i] end
            out[#out + 1] = part
        end
        return out
    end

    -- Row count is the wrong unit. KB-86 broke the Race Guide at 17 rows, KB-160 re-broke it at the same 17
    -- rows because each row had grown, and "small enough today" is the reasoning that produced both. Partition
    -- by MEASURED bytes instead, so a row that grows costs a packet rather than the whole payload.
    --
    -- `measure(row)` returns that row's encoded size. A row larger than the budget on its own cannot be split
    -- here -- it is returned as its own part AND reported in the second return value, so the caller can say so
    -- in the log instead of putting an oversized packet on a wire that drops it without a word.
    --- `reserve` (optional) is what the caller wraps around each part on the wire -- the `{"id":..,"index":..,
    --- "items":}` envelope -- so the budget bounds the PACKET, not just its rows. The part's own brackets and the
    --- comma between rows are counted here. Measuring rows alone let a full packet leave at budget + envelope:
    --- the Race Guide's 6,145-byte packet 3 against a 6,144 budget (KB-228).
    function M.partitionBytes(list, budget, measure, reserve)
        list = type(list) == "table" and list or {}
        budget = math.max(1, math.floor(tonumber(budget) or 1))
        local capacity = math.max(1, budget - math.max(0, math.floor(tonumber(reserve) or 0)))
        local parts, oversized = {}, {}
        local part, used = {}, 2                             -- "[]"
        for i = 1, #list do
            -- An unmeasurable row is assumed to fill the budget: pessimism is the safe direction here, and
            -- callers signal "cannot encode this" with a non-positive size rather than a number we would trust.
            local measured = tonumber(measure and measure(list[i])) or -1
            local bytes = measured > 0 and math.floor(measured) or capacity
            if bytes + 2 > capacity then oversized[#oversized + 1] = { index = i, bytes = bytes } end
            local comma = #part > 0 and 1 or 0
            if #part > 0 and used + comma + bytes > capacity then
                parts[#parts + 1] = part
                part, used, comma = {}, 2, 0
            end
            part[#part + 1] = list[i]
            used = used + comma + bytes
        end
        if #part > 0 then parts[#parts + 1] = part end
        return parts, oversized
    end

    function M.receiver(expected)
        expected = math.max(0, math.floor(tonumber(expected) or 0))
        return { expected = expected, received = 0, parts = {} }
    end

    function M.accept(state, index, items)
        if type(state) ~= "table" or type(state.parts) ~= "table" then return nil, "invalid_state" end
        index = math.floor(tonumber(index) or 0)
        if index < 1 or index > state.expected then return nil, "index_out_of_range" end
        if state.parts[index] ~= nil then return false, "duplicate" end
        if type(items) ~= "table" then return nil, "invalid_items" end
        state.parts[index] = items
        state.received = state.received + 1
        return true
    end

    function M.complete(state)
        return type(state) == "table" and state.received == state.expected
    end

    function M.collect(state)
        if not M.complete(state) then return nil, "incomplete" end
        local out = {}
        for i = 1, state.expected do
            local part = state.parts[i]
            if type(part) ~= "table" then return nil, "missing_part" end
            for _, row in ipairs(part) do out[#out + 1] = row end
        end
        return out
    end

    return M
end)
