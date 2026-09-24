-- Liveries: reads the RB15 livery manifest written by the NCM livery add-on build
-- (r6/tweaks/ncm_rb15_liveries.manifest.json) so the race setup can offer per-rival
-- appearance names. Tolerant of a missing file: only "stock" is offered then.
local Liveries = {}

local STOCK = "stock"          -- means: spawn with the record's own appearance (no override)

local function getModuleDir()
    local dbg = debug
    if dbg and type(dbg.getinfo) == "function" then
        local src = dbg.getinfo(1, "S").source or ""
        if src:sub(1, 1) == "@" then src = src:sub(2) end
        return src:match("^(.*)[/\\][^/\\]+$") or "modules"
    end
    return "modules"
end

-- <game>\bin\x64\plugins\cyber_engine_tweaks\mods\MT_Ecosystem\modules -> <game>\r6\tweaks\...
local MODULE_DIR = getModuleDir()
local GAME_ROOT  = MODULE_DIR:gsub("[/\\]bin[/\\]x64[/\\]plugins[/\\]cyber_engine_tweaks[/\\]mods[/\\]MT_Ecosystem[/\\]modules$", "")
local MANIFEST_PATH = GAME_ROOT .. "\\r6\\tweaks\\ncm_rb15_liveries.manifest.json"
-- relative fallback (CET's io root is the mod folder)
local MANIFEST_PATH_REL = "../../../../../r6/tweaks/ncm_rb15_liveries.manifest.json"

Liveries.STOCK = STOCK
Liveries.manifest = nil
Liveries.loadedFrom = nil

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local raw = f:read("*a"); f:close()
    if not raw or raw == "" then return nil end
    return raw
end

function Liveries.reload()
    Liveries.manifest = nil
    Liveries.loadedFrom = nil
    if not json or not json.decode then return false end
    for _, path in ipairs({ MANIFEST_PATH, MANIFEST_PATH_REL }) do
        local raw = readFile(path)
        if raw then
            local ok, data = pcall(json.decode, raw)
            if ok and type(data) == "table" and type(data.liveries) == "table" then
                Liveries.manifest = data
                Liveries.loadedFrom = path
                print(string.format("[NCM/Liveries] manifest loaded (%d liveries) from %s", #data.liveries, path))
                return true
            end
        end
    end
    print("[NCM/Liveries] no livery manifest found; only stock appearance available")
    return false
end

--- Names offered in the UI: "stock" first, then manifest liveries (probe/test skins last).
function Liveries.list()
    local out = { STOCK }
    local m = Liveries.manifest
    if type(m) == "table" and type(m.liveries) == "table" then
        local tail = {}
        for _, name in ipairs(m.liveries) do
            if name == "probe" or name == "ncm_test" or name:find("^demo_") then tail[#tail + 1] = name
            else out[#out + 1] = name end
        end
        for _, name in ipairs(tail) do out[#out + 1] = name end
    end
    return out
end

function Liveries.isKnown(name)
    if name == nil or name == STOCK or name == "player_01" then return true end
    for _, n in ipairs(Liveries.list()) do if n == name then return true end end
    return false
end

--- Appearance name to pass to the spawner (nil = record default / stock).
function Liveries.appearanceFor(name)
    if name == nil or name == STOCK or name == "player_01" or name == "" then return nil end
    return name
end

--- Derived per-livery vehicle record (Vehicle.v_sport1_rb15_f1_<name>) if the manifest has one.
function Liveries.recordFor(name)
    local m = Liveries.manifest
    if type(m) == "table" and type(m.records) == "table" then return m.records[name] end
    return nil
end

function Liveries.init()
    Liveries.reload()
end

return Liveries
