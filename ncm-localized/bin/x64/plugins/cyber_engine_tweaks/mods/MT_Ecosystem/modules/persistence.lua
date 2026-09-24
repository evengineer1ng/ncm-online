-- ============================================================
-- MT_Ecosystem: modules/persistence.lua
-- Generic JSON load/save helpers for all MT_Ecosystem modules.
-- Files are stored under the mod's save/ subfolder.
-- Adapted from PermanentVehicleDamage persistence pattern.
-- ============================================================

local Persist = {}

-- CET sets each mod's Lua working directory to the mod root.
-- Use relative paths so io.open works within the sandbox.
local SAVE_DIR = "save\\"

-- ── Internal helpers ─────────────────────────────────────────

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = deepCopy(v)
    end
    return copy
end

local function fileExists(path)
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

local function normalizeRelativePath(filename)
    local cleaned = tostring(filename or "")
    -- Prevent path traversal: strip any ../ sequences
    cleaned = cleaned:gsub("[/\\]%.%.[/\\]", ""):gsub("^%.%.[/\\]", "")
    cleaned = cleaned:gsub("/", "\\")
    cleaned = cleaned:gsub(":", "")
    cleaned = cleaned:gsub("^\\+", "")
    cleaned = cleaned:gsub("\\+", "\\")
    return cleaned
end

local function flattenRelativePath(cleaned)
    if not cleaned:find("\\") then
        return cleaned
    end
    return cleaned:gsub("\\", "__")
end

local function safePath(filename, preferExisting)
    local cleaned = normalizeRelativePath(filename)
    local nestedPath = SAVE_DIR .. cleaned
    if not cleaned:find("\\") then
        return nestedPath
    end

    local flatPath = SAVE_DIR .. flattenRelativePath(cleaned)
    if preferExisting then
        if fileExists(nestedPath) or fileExists(nestedPath .. ".bak") then
            return nestedPath
        end
        if fileExists(flatPath) or fileExists(flatPath .. ".bak") then
            return flatPath
        end
    else
        if fileExists(nestedPath) then
            return nestedPath
        end
    end

    return flatPath
end

local function ensureDir(path)
    local probePath = path .. "\\.dir_probe"
    local probe = io.open(probePath, "a")
    if probe then
        probe:close()
        os.remove(probePath)
        return true
    end
    -- Try multiple approaches to create the directory
    local mkdirAttempts = {
        function() pcall(os.execute, 'mkdir "' .. path .. '"') end,
        function() local h = io.popen('mkdir "' .. path .. '" 2>nul', "r") if h then h:close() end end,
    }
    for _, attempt in ipairs(mkdirAttempts) do
        pcall(attempt)
        probe = io.open(probePath, "a")
        if probe then
            probe:close()
            os.remove(probePath)
            return true
        end
    end
    print("[NCM/Persist] Failed to create save directory: " .. path)
    return false
end

local function ensurePathDir(filePath)
    local dir = filePath:match("^(.*)\\[^\\]+$") or SAVE_DIR:gsub("\\$", "")
    local current = ""
    for segment in dir:gmatch("[^\\]+") do
        current = (current == "") and segment or (current .. "\\" .. segment)
        if not ensureDir(current) then
            return false
        end
    end
    return true
end

local function writeFile(path, content)
    if not ensurePathDir(path) then
        return false
    end
    local handle, err = io.open(path, "w")
    if not handle then
        print("[NCM/Persist] Write failed on " .. path .. ": " .. tostring(err))
        return false
    end
    handle:write(content)
    handle:close()
    return true
end

local function readFile(path)
    local handle, err = io.open(path, "r")
    if not handle then return nil end
    local content = handle:read("*a")
    handle:close()
    return content
end

local function encode(data)
    local ok, result = pcall(json.encode, data)
    if not ok then
        print("[NCM/Persist] JSON encode error: " .. tostring(result))
        return nil
    end
    return result
end

local function decode(str)
    if not str or str == "" then return nil end
    str = tostring(str):gsub("^\239\187\191", "")
    local ok, result = pcall(json.decode, str)
    if not ok then
        print("[NCM/Persist] JSON decode error: " .. tostring(result))
        return nil
    end
    return result
end

-- ── Public API ────────────────────────────────────────────────

--- Initialise: verify we can write to the save/ subfolder.
function Persist.init()
    if ensureDir(SAVE_DIR:gsub("\\$", "")) then
        print("[NCM/Persist] Save path OK: " .. SAVE_DIR)
    else
        print("[NCM/Persist] Warning: cannot write to " .. SAVE_DIR .. " — saves will not persist.")
    end
end

--- Load a table from a JSON file. Returns the decoded table or nil on failure.
--- @param filename string  e.g. "sessions.json" — no directory prefix needed
function Persist.load(filename)
    local path    = safePath(filename, true)
    local content = readFile(path)

    if not content or content == "" then
        return nil
    end
    local data = decode(content)
    if not data then
        -- Attempt backup restore
        local backupPath = path .. ".bak"
        local backup     = readFile(backupPath)
        if backup then
            data = decode(backup)
            if data then
                print("[NCM/Persist] Restored from backup: " .. path)
            end
        end
    end
    return data
end

--- Save a table to a JSON file with a rotating backup.
--- @param filename string  e.g. "sessions.json"
--- @param data     table
--- @return boolean  true on success
function Persist.save(filename, data)
    local path    = safePath(filename, false)
    local encoded = encode(data)
    if not encoded then return false end

    -- Rotate existing file to .bak before overwriting
    local existing = readFile(path)
    if existing and existing ~= "" then
        writeFile(path .. ".bak", existing)
    end

    return writeFile(path, encoded)
end

--- Load a versioned document and optionally migrate it to the requested version.
--- Returns the loaded document, whether it was created fresh, and whether migration ran.
function Persist.loadVersioned(filename, currentVersion, defaultDocument, migrateFn)
    local createdFresh = false
    local migrated = false
    local doc = Persist.load(filename)

    if type(doc) ~= "table" then
        doc = deepCopy(defaultDocument or {})
        if type(doc) ~= "table" then doc = {} end
        doc.version = currentVersion
        return doc, true, false
    end

    local version = tonumber(doc.version) or 0
    if version < currentVersion and type(migrateFn) == "function" then
        local ok, migratedDoc = pcall(migrateFn, deepCopy(doc), version, currentVersion)
        if ok and type(migratedDoc) == "table" then
            doc = migratedDoc
            migrated = true
        else
            print("[NCM/Persist] Version migration failed for " .. tostring(filename) .. ": " .. tostring(migratedDoc))
        end
    end

    if type(doc) ~= "table" then
        doc = deepCopy(defaultDocument or {})
        if type(doc) ~= "table" then doc = {} end
        createdFresh = true
    end
    doc.version = currentVersion
    return doc, createdFresh, migrated
end

--- Deep-copy helper for modules building versioned documents.
function Persist.clone(value)
    return deepCopy(value)
end

--- Check if a save file exists.
--- @param filename string
--- @return boolean
function Persist.exists(filename)
    local handle = io.open(safePath(filename, true), "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

--- Delete a save file and its backup.
--- @param filename string
function Persist.delete(filename)
    local path = safePath(filename, true)
    os.remove(path)
    os.remove(path .. ".bak")
end

return Persist
