-- The Paddock street grid against NCM single player's OWN grid code (L232): an assurance, not a re-reading.
--
-- The owner authored every route node in single player and tuned how its AI grid lines up. The first Online street
-- grid ignored both and came out rotated 90 degrees and off the road. This test cuts SP's real functions out of
-- ai_vehicles.lua -- resolveGridForwardHeading, resolveGridBasis, the unified slot-heading offset, and
-- calculateFormation -- runs them with only `tuningValue` and the logger stubbed (the tuning comes from the same SP
-- sources, via data.grid_profiles), and requires paddock.live.gridSlots to put every car of every Paddock route in the
-- same place, facing the same way. If either side changes, the gate fails.
local root = arg[1] or "."
local SP = root .. "/ncm-localized/bin/x64/plugins/cyber_engine_tweaks/mods/MT_Ecosystem/modules/ai_vehicles.lua"
local bad, checks = 0, 0
local function check(label, ok, detail)
    checks = checks + 1
    if not ok then bad = bad + 1; print("  FAIL " .. label .. (detail and ("  -- " .. detail) or "")) else print("  PASS " .. label) end
end

-- ncm-core, the modules this needs
NcmCore = nil
dofile(root .. "/ncm/core/init.lua")
for _, f in ipairs(dofile(root .. "/ncm/core/MANIFEST.lua")) do dofile(root .. "/ncm/core/" .. f) end
local Live = NcmCore.get("paddock.live")
local Profiles = NcmCore.get("data.grid_profiles")
local Routes = NcmCore.get("course.routes")
local Season = NcmCore.get("paddock.season")

-- SP's source, cut by its own function boundaries
local src = assert(io.open(SP, "rb")):read("a")
local function cut(startMarker, endMarker)
    local a = assert(src:find(startMarker, 1, true), "SP source moved: " .. startMarker)
    local b = assert(src:find(endMarker, a, true), "SP source moved: " .. endMarker)
    return src:sub(a, b - 1)
end
local chunk = table.concat({
    cut("local function isFiniteNumber(value)", "local function clamp(value, minValue, maxValue)"),
    cut("local function resolveGridForwardHeading(startNode, finishNode, explicitHeading)", "local RACE_TIER_STRAIGHT_SPEED_MIN_MULT"),
    cut("local function getWholeGridSlotOrdinal(entry, fallbackIndex, playerGridPos)", "local function getSlotIndex(slot, fallback)"),
    cut("calculateFormation = function(startNode, finishNode, count, startType, options)", "local function clonePositionWithZLift(pos, zLift)"),
    "return calculateFormation, resolveGridBasis",
}, "\n")
local PROFILE
local env = setmetatable({
    tuningValue = function(key, _, fallback)
        local v = PROFILE[key]
        if v == nil then v = Profiles.DEFAULTS[key] end
        if v == nil and key == "aiGridForwardAlignmentDot" then v = 0.55 end
        if v == nil then v = fallback end
        return v
    end,
    gridLog = function() end,
    FINAL_SLOT_Z_OFFSET = 0.0,
    -- SP runs under CET's LuaJIT, which has math.atan2; Lua 5.4 spells it math.atan(y, x)
    math = setmetatable({ atan2 = math.atan2 or function(y, x) return math.atan(y, x) end }, { __index = math }),
}, { __index = _G })
local loader = load or loadstring
local fn = assert(loader(chunk, "=sp_grid", "t", env) or (setfenv and setfenv(assert(loadstring(chunk, "=sp_grid")), env)))
local spFormation, spBasis = fn()

print("grid oracle: paddock.live.gridSlots against NCM single player's calculateFormation")
local function angDiff(a, b) local d = (a - b) % 360 if d > 180 then d = d - 360 end return math.abs(d) end
local routeIds = {}
for _, id in pairs(Season.ROUTES) do routeIds[#routeIds + 1] = id end
table.sort(routeIds)
for _, rootId in ipairs(routeIds) do
    local r = assert(Routes.resolve(rootId))
    PROFILE = Profiles.forRoot(rootId)
    local sp = spFormation(r.start, r.finish, 12, "grid", {})
    local mine = Live.gridSlots(r.start, r.finish, 12, PROFILE)
    local worstPos, worstYaw = 0, 0
    for i = 1, 12 do
        local dx, dy = sp[i].x - mine[i].x, sp[i].y - mine[i].y
        worstPos = math.max(worstPos, math.sqrt(dx * dx + dy * dy))
        worstYaw = math.max(worstYaw, angDiff(sp[i].heading, mine[i].yaw))
        if math.abs((sp[i].z or 0) - (mine[i].z or 0)) > 0.01 then worstPos = math.huge end
    end
    check(("%s: every slot where SP puts it (worst %.3f m) facing SP's way (worst %.3f deg)"):format(r.name, worstPos, worstYaw),
        worstPos < 0.01 and worstYaw < 0.01)
end
-- the SP rule for a car set down anywhere on a line (resets, bubble spawns): the same slot offset as the grid
PROFILE = Profiles.forRoot("none")
local b = spBasis({ x = 0, y = 0, heading = 0 }, { x = 0, y = 100 }, {})
check("a car placed along a line takes SP's slot rotation (heading + startSlotHeadingOffsetDeg)",
    angDiff(b.slotHeading, Live.yawFromDir(b.forwardX, b.forwardY)) < 0.01, ("sp %.2f mine %.2f"):format(b.slotHeading, Live.yawFromDir(b.forwardX, b.forwardY)))
print(("grid oracle: %d check(s), %d bad"):format(checks, bad))
os.exit(bad == 0 and 0 or 1)
