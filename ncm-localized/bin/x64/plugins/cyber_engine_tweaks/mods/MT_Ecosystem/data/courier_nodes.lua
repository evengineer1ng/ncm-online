local CourierNodes = {}

local COURIER_ROOT = "D:\\SteamLibrary\\steamapps\\common\\Cyberpunk 2077\\bin\\x64\\plugins\\cyber_engine_tweaks\\mods\\make_a_living__courier"
local DROP_POINT_FILE = COURIER_ROOT .. "\\data\\DropPointList.lua"
local DEFAULT_START_WIDTH = 12.0
local DEFAULT_FINISH_WIDTH = 24.0
local DEFAULT_FINISH_ARM = 90.0
local ROAD_ANCHOR_OFFSET = 14.0
local MIN_NEIGHBOR_DIST = 35.0
local MAX_NEIGHBOR_DIST = 420.0
local MAX_NEIGHBOR_DZ = 12.0

local function titleCaseWords(text)
    if not text or text == "" then return "Unknown" end
    local out = text:lower():gsub("(%a)([%w_']*)", function(a, b)
        return a:upper() .. b
    end)
    return out:gsub("_", " ")
end

local function cleanDistrictName(text)
    local normalized = titleCaseWords(text)
    normalized = normalized:gsub("Santo Domingo", "Santo Domingo")
    normalized = normalized:gsub("City Center", "City Center")
    return normalized
end

local function cleanSubdistrictName(text)
    if not text or text == "" then return nil end
    return titleCaseWords(text)
end

local function loadDropPoints()
    local ok, data = pcall(dofile, DROP_POINT_FILE)
    if ok and type(data) == "table" then
        return data
    end
    return {}
end

local function dist2D(a, b)
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function headingDeg(dx, dy)
    return math.deg(math.atan(dy, dx))
end

local function buildLabel(entry)
    local baseName = entry.name or entry.id or "Courier Point"
    local subdistrict = cleanSubdistrictName(entry.subdistrict)
    if subdistrict and baseName ~= subdistrict then
        return subdistrict .. " - " .. baseName
    end
    return baseName
end

local function collectNeighbors(entry, allEntries)
    local neighbors = {}
    for _, other in ipairs(allEntries) do
        if other ~= entry then
            local dz = math.abs((other.loc.z or 0) - (entry.loc.z or 0))
            local d = dist2D(entry.loc, other.loc)
            local sameDistrict = other.district == entry.district
            if sameDistrict and dz <= MAX_NEIGHBOR_DZ and d >= MIN_NEIGHBOR_DIST and d <= MAX_NEIGHBOR_DIST then
                neighbors[#neighbors + 1] = { entry = other, dist = d }
            end
        end
    end
    table.sort(neighbors, function(a, b) return a.dist < b.dist end)
    return neighbors
end

local function deriveRoadAnchor(entry, allEntries)
    local neighbors = collectNeighbors(entry, allEntries)
    if #neighbors == 0 then
        return nil
    end

    local dirX, dirY = 0.0, 0.0
    local samples = math.min(3, #neighbors)
    for i = 1, samples do
        local other = neighbors[i].entry
        local dx = (other.loc.x or 0) - (entry.loc.x or 0)
        local dy = (other.loc.y or 0) - (entry.loc.y or 0)
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0.001 then
            local weight = 1.0 / math.max(neighbors[i].dist, 1.0)
            dirX = dirX + (dx / len) * weight
            dirY = dirY + (dy / len) * weight
        end
    end

    local mag = math.sqrt(dirX * dirX + dirY * dirY)
    if mag <= 0.001 then
        local other = neighbors[1].entry
        dirX = (other.loc.x or 0) - (entry.loc.x or 0)
        dirY = (other.loc.y or 0) - (entry.loc.y or 0)
        mag = math.sqrt(dirX * dirX + dirY * dirY)
        if mag <= 0.001 then
            return nil
        end
    end

    dirX = dirX / mag
    dirY = dirY / mag

    return {
        x = (entry.loc.x or 0) + dirX * ROAD_ANCHOR_OFFSET,
        y = (entry.loc.y or 0) + dirY * ROAD_ANCHOR_OFFSET,
        z = entry.loc.z or 0,
        heading = headingDeg(dirX, dirY),
    }
end

function CourierNodes.all()
    local raw = loadDropPoints()
    local out = {}
    for _, entry in ipairs(raw) do
        if entry.loc and entry.loc.x and entry.loc.y and entry.loc.z then
            local anchor = deriveRoadAnchor(entry, raw)
            if anchor then
                local district = cleanDistrictName(entry.district)
                local subdistrict = cleanSubdistrictName(entry.subdistrict)
                out[#out + 1] = {
                    id = "courier_" .. tostring(entry.id or (#out + 1)):lower():gsub("[^%w_]", "_"),
                    sourceId = entry.id,
                    sourceHash = entry.hash,
                    sourceType = "courier_drop_point",
                    x = anchor.x,
                    y = anchor.y,
                    z = anchor.z,
                    heading = anchor.heading,
                    finishHeading = anchor.heading,
                    startWidthM = DEFAULT_START_WIDTH,
                    finishWidthM = DEFAULT_FINISH_WIDTH,
                    finishArmDistM = DEFAULT_FINISH_ARM,
                    name = buildLabel(entry),
                    region = district,
                    district = district,
                    subdistrict = subdistrict,
                    urban = district ~= "Badlands",
                    waypointable = true,
                    road = true,
                    raceLegal = true,
                    gridAnchor = {
                        x = anchor.x,
                        y = anchor.y,
                        z = anchor.z,
                        heading = anchor.heading,
                    },
                    sourceLoc = {
                        x = entry.loc.x,
                        y = entry.loc.y,
                        z = entry.loc.z,
                        w = entry.loc.w or 1,
                    },
                }
            end
        end
    end
    return out
end

return CourierNodes
