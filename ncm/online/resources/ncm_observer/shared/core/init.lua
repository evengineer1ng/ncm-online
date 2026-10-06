-- ncm-core: registry and loader contract.
--
-- This file is the first ncm-core chunk every host loads. It creates ONE global, `NcmCore`,
-- through which every other core module registers itself (`NcmCore.define`) and resolves its
-- dependencies lazily (`NcmCore.get`). Core modules never `require`, never touch `os`/`io`,
-- never read the clock or a random source: hosts inject those (see COMPAT.md).
--
-- Hosts:
--   OPEN//77  - listed as `shared_script` lines in manifest order (see tools/ncm-build.ps1);
--               one VM per resource, so the global is per resource.
--   CET (SP)  - a small `require` shim dofile()s init.lua then each MANIFEST.lua entry.
--   tests     - ncm/core/tests/run.lua does the same under Lua 5.4 and LuaJIT.

local VERSION = "0.0.1"

local Core = rawget(_G, "NcmCore")
if Core and Core.VERSION == VERSION then
    return Core
end

Core = {
    VERSION = VERSION,
    _factories = {},
    _modules = {},
    _resolving = {},
    _order = {},
}

--- Register a module factory. `factory(Core)` runs once, on first `get`, and must return a table.
function Core.define(name, factory)
    if type(name) ~= "string" or name == "" then
        error("NcmCore.define: module name must be a non-empty string", 2)
    end
    if type(factory) ~= "function" then
        error("NcmCore.define: factory for '" .. name .. "' must be a function", 2)
    end
    if Core._factories[name] ~= nil then
        error("NcmCore.define: module '" .. name .. "' is already defined", 2)
    end
    Core._factories[name] = factory
    Core._order[#Core._order + 1] = name
    return true
end

--- Resolve a module by name, instantiating it on first use. Errors on unknown names and cycles.
function Core.get(name)
    local ready = Core._modules[name]
    if ready ~= nil then
        return ready
    end
    local factory = Core._factories[name]
    if factory == nil then
        error("NcmCore.get: unknown module '" .. tostring(name) .. "'", 2)
    end
    if Core._resolving[name] then
        error("NcmCore.get: dependency cycle at '" .. name .. "'", 2)
    end
    Core._resolving[name] = true
    local ok, result = pcall(factory, Core)
    Core._resolving[name] = nil
    if not ok then
        error("NcmCore.get: factory for '" .. name .. "' failed: " .. tostring(result), 2)
    end
    if type(result) ~= "table" then
        error("NcmCore.get: factory for '" .. name .. "' must return a table", 2)
    end
    result.__name = result.__name or name
    Core._modules[name] = result
    return result
end

--- True when a module of that name has been defined (instantiated or not).
function Core.has(name)
    return Core._factories[name] ~= nil
end

--- Names in definition order (useful for diagnostics and the build tool).
function Core.defined()
    local out = {}
    for i = 1, #Core._order do
        out[i] = Core._order[i]
    end
    return out
end

--- Instantiate every defined module (hosts may call this once after loading to fail fast).
function Core.warm()
    local names = Core.defined()
    for i = 1, #names do
        Core.get(names[i])
    end
    return #names
end

rawset(_G, "NcmCore", Core)
return Core
