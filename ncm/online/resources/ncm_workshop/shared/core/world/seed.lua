-- ncm-core module: world.seed
--
-- The seed as a foundational simulation identity (L321; doc 54 §F): GENERATED BASE STATE + PERSISTENT CAUSAL
-- MODIFICATIONS = CURRENT WORLD.
--
-- A SEED TREE, NOT A STREAM. Every generated fact is drawn from a stream keyed by its PATH in the tree --
--     universe seed / earth / infrastructure / station / 3
-- -- never by its position in a sequence of draws. So adding a subsystem, an extra station or a new kind of fact
-- never reshuffles anything that already existed: an established seed stays itself as NCM grows. Built on
-- `vocabulary.hash` (FNV-1a + Park-Miller, identical under Lua 5.4 and LuaJIT), which `paddock.world` already uses
-- per entity; this module makes the hierarchy explicit and shared.
--
-- COMPOSITION. A world is `compose(base, mods)`: the base is whatever generators produced from the tree (pure,
-- re-derivable at any time); mods are the committed history -- ordered `{id, at, path, op, value}` records (set, add,
-- remove, append) applied by path. The same seed and the same committed history rebuild the same world; the base is
-- never stored, only the mods are. A mod that names a path the base does not have is reported, not invented.
local Core = NcmCore

Core.define("world.seed", function(C)
    local M = { version = "0.1.0" }
    local Hash = C.get("vocabulary.hash")

    local Node = {}
    Node.__index = Node

    local function newNode(path)
        return setmetatable({ path = path }, Node)
    end

    --- The root of a universe's seed tree.
    function M.root(universeSeed)
        return newNode({ tostring(universeSeed) })
    end

    --- A child node: the path extended by every argument (strings or numbers).
    function Node:child(...)
        local p = {}
        for i = 1, #self.path do p[i] = self.path[i] end
        local n = select("#", ...)
        for i = 1, n do p[#p + 1] = tostring((select(i, ...))) end
        return newNode(p)
    end

    function Node:id() return table.concat(self.path, "/") end
    function Node:depth() return #self.path end

    --- A deterministic stream for this node (optionally sub-keyed): `s()`, `s:int(a,b)`, `s:pick(list)`, `s:normal(m,sd)`.
    function Node:stream(...) return Hash.stream("ncm-seed", self:id(), ...) end
    --- One [0,1) draw keyed by this node and the arguments, without a stream.
    function Node:unit(...) return Hash.unit("ncm-seed", self:id(), ...) end
    --- A short stable identifier for things generated here (e.g. a station's id).
    function Node:tag(...) return Hash.commit("ncm-seed", self:id(), ...) end

    -- ---------------------------------------------------------------------------------------- composition
    local function deepCopy(v)
        if type(v) ~= "table" then return v end
        local o = {}
        for k, x in pairs(v) do o[k] = deepCopy(x) end
        return o
    end
    M.deepCopy = deepCopy

    --- A path is "a.b.3.c" or { "a", "b", 3, "c" }. Numeric segments index arrays.
    local function splitPath(path)
        if type(path) == "table" then return path end
        local out = {}
        for seg in tostring(path):gmatch("[^%.]+") do out[#out + 1] = tonumber(seg) or seg end
        return out
    end
    M.splitPath = splitPath

    local function locate(state, segs)
        local t = state
        for i = 1, #segs - 1 do
            if type(t) ~= "table" or t[segs[i]] == nil then return nil end
            t = t[segs[i]]
        end
        return t, segs[#segs]
    end

    --- Apply one modification. Returns true, or false and a reason.
    function M.apply(state, mod)
        local segs = splitPath(mod.path)
        if #segs == 0 then return false, "empty path" end
        local parent, key = locate(state, segs)
        if type(parent) ~= "table" then return false, "no such path: " .. table.concat(segs, ".") end
        local op = mod.op or "set"
        if op == "set" then
            parent[key] = deepCopy(mod.value)
        elseif op == "add" then
            if type(parent[key]) ~= "number" then return false, "add needs a number at " .. tostring(key) end
            parent[key] = parent[key] + (tonumber(mod.value) or 0)
        elseif op == "remove" then
            if type(key) == "number" and type(parent[key]) ~= "nil" and #parent >= key then table.remove(parent, key)
            else parent[key] = nil end
        elseif op == "append" then
            if parent[key] == nil then parent[key] = {} end
            if type(parent[key]) ~= "table" then return false, "append needs a list at " .. tostring(key) end
            local list = parent[key]
            list[#list + 1] = deepCopy(mod.value)
        else
            return false, "unknown op " .. tostring(op)
        end
        return true
    end

    --- The current world: a copy of the generated base with the committed history applied in (at, id) order.
    --- Returns state, { applied = n, refused = { {id, reason} } }.
    function M.compose(base, mods)
        local state = deepCopy(base)
        local ordered = {}
        for i, m in ipairs(mods or {}) do ordered[i] = m end
        table.sort(ordered, function(a, b)
            local ta, tb = tonumber(a.at) or 0, tonumber(b.at) or 0
            if ta ~= tb then return ta < tb end
            return tostring(a.id) < tostring(b.id)
        end)
        local report = { applied = 0, refused = {} }
        for _, m in ipairs(ordered) do
            local ok, why = M.apply(state, m)
            if ok then report.applied = report.applied + 1
            else report.refused[#report.refused + 1] = { id = m.id, reason = why } end
        end
        return state, report
    end

    return M
end)
