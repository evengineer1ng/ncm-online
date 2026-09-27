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
