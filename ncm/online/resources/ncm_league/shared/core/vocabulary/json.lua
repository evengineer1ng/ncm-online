-- ncm-core module: vocabulary.json
-- A small, dependency-free JSON encoder/decoder for the documents NCM persists (onboarding, meta, rulesets).
-- Hosts may provide a faster `json` global; core never assumes one. Arrays are tables with a contiguous 1..n
-- part; empty tables encode as {}. Numbers that are integral encode without a fraction.
local Core = NcmCore

Core.define("vocabulary.json", function(C)
    local M = { version = "0.0.1" }

    local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

    local function isArray(t)
        local n = 0
        for k in pairs(t) do
            if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then return false end
            n = n + 1
        end
        return n == #t and n > 0
    end

    local function encodeValue(v, out)
        local tv = type(v)
        if v == nil then out[#out + 1] = "null"
        elseif tv == "boolean" then out[#out + 1] = v and "true" or "false"
        elseif tv == "number" then
            if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "null"
            elseif math.floor(v) == v and math.abs(v) < 1e15 then out[#out + 1] = string.format("%d", v)
            else out[#out + 1] = string.format("%.6g", v) end
        elseif tv == "string" then
            out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c) return escapes[c] or string.format("\\u%04x", c:byte()) end) .. '"'
        elseif tv == "table" then
            if isArray(v) then
                out[#out + 1] = "["
                for i, x in ipairs(v) do if i > 1 then out[#out + 1] = "," end encodeValue(x, out) end
                out[#out + 1] = "]"
            else
                local keys = {}
                for k in pairs(v) do keys[#keys + 1] = tostring(k) end
                table.sort(keys)
                out[#out + 1] = "{"
                for i, k in ipairs(keys) do
                    if i > 1 then out[#out + 1] = "," end
                    encodeValue(k, out); out[#out + 1] = ":"
                    local val = v[k]
                    if val == nil and tonumber(k) then val = v[tonumber(k)] end
                    encodeValue(val, out)
                end
                out[#out + 1] = "}"
            end
        else
            out[#out + 1] = "null"
        end
    end

    function M.encode(v)
        local out = {}
        encodeValue(v, out)
        return table.concat(out)
    end

    -- decoder
    local function skip(s, i)
        local _, e = s:find("^[ \t\r\n]*", i)
        return e + 1
    end

    local decodeValue

    local function decodeString(s, i)
        local out, j = {}, i + 1
        while true do
            local c = s:sub(j, j)
            if c == "" then return nil, "unterminated string" end
            if c == '"' then return table.concat(out), j + 1 end
            if c == "\\" then
                local n = s:sub(j + 1, j + 1)
                local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
                if n == "u" then
                    local hex = s:sub(j + 2, j + 5)
                    out[#out + 1] = utf8 and utf8.char(tonumber(hex, 16) or 63) or "?"
                    j = j + 6
                else
                    out[#out + 1] = map[n] or n
                    j = j + 2
                end
            else
                out[#out + 1] = c
                j = j + 1
            end
        end
    end

    decodeValue = function(s, i)
        i = skip(s, i)
        local c = s:sub(i, i)
        if c == "{" then
            local obj = {}
            i = skip(s, i + 1)
            if s:sub(i, i) == "}" then return obj, i + 1 end
            while true do
                i = skip(s, i)
                if s:sub(i, i) ~= '"' then return nil, "expected key at " .. i end
                local k, ni = decodeString(s, i)
                if not k then return nil, ni end
                i = skip(s, ni)
                if s:sub(i, i) ~= ":" then return nil, "expected ':' at " .. i end
                local v, nv = decodeValue(s, i + 1)
                if v == nil and type(nv) == "string" then return nil, nv end
                obj[k] = v
                i = skip(s, nv)
                local d = s:sub(i, i)
                if d == "}" then return obj, i + 1 end
                if d ~= "," then return nil, "expected ',' at " .. i end
                i = i + 1
            end
        elseif c == "[" then
            local arr = {}
            i = skip(s, i + 1)
            if s:sub(i, i) == "]" then return arr, i + 1 end
            while true do
                local v, nv = decodeValue(s, i)
                if v == nil and type(nv) == "string" then return nil, nv end
                arr[#arr + 1] = v
                i = skip(s, nv)
                local d = s:sub(i, i)
                if d == "]" then return arr, i + 1 end
                if d ~= "," then return nil, "expected ',' at " .. i end
                i = i + 1
            end
        elseif c == '"' then
            return decodeString(s, i)
        elseif s:sub(i, i + 3) == "true" then return true, i + 4
        elseif s:sub(i, i + 4) == "false" then return false, i + 5
        elseif s:sub(i, i + 3) == "null" then return nil, i + 4
        else
            local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
            if not num or num == "" then return nil, "unexpected character at " .. i end
            return tonumber(num), i + #num
        end
    end

    --- Decode a JSON string. Returns the value (nil for JSON null) or nil, reason.
    function M.decode(s)
        if type(s) == "table" then return s end
        if type(s) ~= "string" then return nil, "not_a_string" end
        local v, i = decodeValue(s, 1)
        if v == nil and type(i) == "string" then return nil, i end
        return v
    end

    return M
end)
