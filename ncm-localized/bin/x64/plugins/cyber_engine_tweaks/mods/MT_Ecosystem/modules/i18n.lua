-- Night City Motorsports localization runtime.
-- Catalogs are UTF-8 JSON files under locales/<locale>.json.
local I18N = { locale = "en-us", fallbackLocale = "en-us", catalogs = {}, missing = {} }

local function readFile(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local value = file:read("*a")
    file:close()
    return value
end

local function normalizeLocale(value)
    value = tostring(value or ""):lower():gsub("_", "-")
    local aliases = { en = "en-us", pt = "pt-br", zh = "zh-cn", no = "nb-no" }
    return aliases[value] or value
end

local function placeholders(value)
    local result = {}
    if type(value) ~= "string" then return result end
    for name in value:gmatch("{([%w_]+)}") do result[name] = true end
    return result
end

local function samePlaceholders(a, b)
    local aa, bb = placeholders(a), placeholders(b)
    for key in pairs(aa) do if not bb[key] then return false end end
    for key in pairs(bb) do if not aa[key] then return false end end
    return true
end

local function loadCatalog(locale)
    locale = normalizeLocale(locale)
    if I18N.catalogs[locale] then return I18N.catalogs[locale] end
    local raw = readFile("locales/" .. locale .. ".json")
    if not raw then I18N.catalogs[locale] = {}; return I18N.catalogs[locale] end
    local ok, decoded = pcall(function() return json.decode(raw) end)
    local strings = ok and decoded and (decoded.strings or decoded) or {}
    I18N.catalogs[locale] = strings
    return strings
end

local function detectGameLocale()
    local ok, value = pcall(function()
        local system = Game.GetSettingsSystem()
        local setting = system and system:GetVar("/language", "OnScreen") or nil
        if not setting then return nil end
        if setting.GetValue then return setting:GetValue() end
        return tostring(setting)
    end)
    return ok and normalizeLocale(value) or "en-us"
end

local function pluralForm(locale, n)
    local lang = normalizeLocale(locale):match("^[^-]+")
    n = tonumber(n) or 0
    if lang == "ru" or lang == "uk" then
        local n10, n100 = n % 10, n % 100
        if n10 == 1 and n100 ~= 11 then return "one" end
        if n10 >= 2 and n10 <= 4 and not (n100 >= 12 and n100 <= 14) then return "few" end
        if n10 == 0 or n10 >= 5 or (n100 >= 11 and n100 <= 14) then return "many" end
    elseif lang == "pl" then
        if n == 1 then return "one" end
        local n10, n100 = n % 10, n % 100
        if n10 >= 2 and n10 <= 4 and not (n100 >= 12 and n100 <= 14) then return "few" end
        return "many"
    elseif n == 1 then return "one" end
    return "other"
end

local function interpolate(value, params)
    if type(value) ~= "string" then return value end
    return (value:gsub("{([%w_]+)}", function(name)
        local replacement = params and params[name]
        return replacement == nil and ("{" .. name .. "}") or tostring(replacement)
    end))
end

function I18N.init(override)
    local requested = normalizeLocale(override)
    I18N.locale = (requested == "" or requested == "auto") and detectGameLocale() or requested
    loadCatalog(I18N.fallbackLocale)
    loadCatalog(I18N.locale)
    local ok, reverse = pcall(require, "locales/reverse_index")
    if ok then I18N.setReverse(reverse) end
    print("[NCM/I18N] locale=" .. I18N.locale)
end

function I18N.t(key, params)
    local localValue = loadCatalog(I18N.locale)[key]
    local fallback = loadCatalog(I18N.fallbackLocale)[key]
    if localValue == "" then localValue = nil end
    local value = localValue or fallback
    if value == nil then
        if not I18N.missing[key] then print("[NCM/I18N] missing key: " .. tostring(key)); I18N.missing[key] = true end
        return tostring(key)
    end
    if type(value) ~= "string" then value = value.other or value.one end
    if type(fallback) == "string" and not samePlaceholders(fallback, value) then
        print("[NCM/I18N] placeholder mismatch for " .. key .. "; using English")
        value = fallback
    end
    return interpolate(value, params)
end

function I18N.tp(key, count, params)
    local localValue = loadCatalog(I18N.locale)[key]
    local fallback = loadCatalog(I18N.fallbackLocale)[key]
    local form = pluralForm(I18N.locale, count)
    local value = type(localValue) == "table" and (localValue[form] or localValue.other) or localValue
    if value == nil then value = type(fallback) == "table" and (fallback[form] or fallback.other) or fallback end
    local fallbackValue = type(fallback) == "table" and (fallback[form] or fallback.other) or fallback
    if value == "" then value = fallbackValue end
    if type(value) == "string" and type(fallbackValue) == "string" and not samePlaceholders(fallbackValue, value) then
        print("[NCM/I18N] plural placeholder mismatch for " .. key .. "; using English")
        value = fallbackValue
    end
    params = params or {}; params.count = count
    return interpolate(value or tostring(key), params)
end

-- Transitional adapter: lets legacy presentation boundaries translate exact
-- English values while source is incrementally converted to semantic t() keys.
function I18N.source(value)
    if type(value) ~= "string" then return value end
    local visible, id = value:match("^(.-)(##.*)$")
    visible = visible or value
    local reverse = I18N.reverse or {}
    local key = reverse[visible]
    if not key then return value end
    return I18N.t(key) .. (id or "")
end

function I18N.format(formatValue, ...)
    return string.format(I18N.source(formatValue), ...)
end

function I18N.template(templateValue, params)
    return interpolate(I18N.source(templateValue), params)
end

function I18N.concat(values, separator, first, last)
    local translated = {}
    for index, value in ipairs(values or {}) do translated[index] = I18N.source(value) end
    return table.concat(translated, separator, first, last)
end

function I18N.wrapImGui(api)
    if not api then return api end
    local firstArg = { Text=true, TextWrapped=true, TextDisabled=true, Button=true, SmallButton=true,
        Checkbox=true, BeginTabItem=true, BeginCombo=true, Selectable=true, InputText=true,
        CollapsingHeader=true, RadioButton=true, MenuItem=true }
    return setmetatable({}, { __index = function(_, key)
        local fn = api[key]
        if type(fn) ~= "function" or not firstArg[key] then return fn end
        return function(label, ...) return fn(I18N.source(label), ...) end
    end })
end

function I18N.wrapNativeSettings(api)
    if not api then return api end
    local methods = { addTab=true, addSubcategory=true, addSwitch=true, addRangeInt=true,
        addRangeFloat=true, addSelectorString=true, addSelector=true, addKeyBinding=true }
    return setmetatable({}, { __index = function(_, key)
        local fn = api[key]
        if type(fn) ~= "function" or not methods[key] then return fn end
        return function(...)
            local args = {...}
            -- Argument 1 is the stable settings path. Translate presentation args only.
            for index = 2, #args do if type(args[index]) == "string" then args[index] = I18N.source(args[index]) end end
            return fn(table.unpack(args))
        end
    end })
end

function I18N.setReverse(index) I18N.reverse = index or {} end
return I18N
