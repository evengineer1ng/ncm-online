-- NCM_RB15_LiveryTest: spawns RB15s with liveries from r6/tweaks/ncm_rb15_liveries.manifest.json
-- (written by wolvenkit-projects/ncm_rb15_liveries/tools/build_liveries.py). Uses the same Codeware
-- DynamicEntitySystem path NCM uses for rivals. Test tool only.

local spawned, liveries, cursor = {}, {}, 0
local function log(msg) print("[RB15Livery] " .. tostring(msg)) end

local function loadManifest()
  local f = io.open("../../../../../r6/tweaks/ncm_rb15_liveries.manifest.json", "r")
  if not f then log("manifest not found; using ncm_test only") liveries = { "ncm_test" } return end
  local raw = f:read("*a"); f:close()
  liveries = {}
  for name in raw:gmatch('"liveries"%s*:%s*%[(.-)%]') do
    for item in name:gmatch('"([%w_]+)"') do liveries[#liveries + 1] = item end
  end
  log("liveries: " .. table.concat(liveries, ", "))
end

local function playerPose(distance, sideOffset)
  local player = Game.GetPlayer(); if not player then return nil end
  local pos, fwd, right = player:GetWorldPosition(), player:GetWorldForward(), player:GetWorldRight()
  local x = pos.x + fwd.x * distance + right.x * (sideOffset or 0)
  local y = pos.y + fwd.y * distance + right.y * (sideOffset or 0)
  return Vector4.new(x, y, pos.z + 0.5, 1.0), math.deg(math.atan(fwd.y, fwd.x)) - 90.0
end

local function spawn(recordName, appearance, distance, side)
  local es = Game.GetDynamicEntitySystem(); if not es then log("DynamicEntitySystem missing") return end
  local pos, yaw = playerPose(distance, side); if not pos then return end
  local spec = DynamicEntitySpec.new()
  spec.recordID = TweakDBID.new(recordName)
  if appearance and appearance ~= "" then spec.appearanceName = appearance end
  spec.position = pos
  spec.orientation = GetSingleton('EulerAngles'):ToQuat(EulerAngles.new(0.0, 0.0, yaw))
  spec.alwaysSpawned, spec.spawnInView, spec.active = true, true, true
  local ok, id = pcall(function() return es:CreateEntity(spec) end)
  if ok and id then spawned[#spawned + 1] = id; log(string.format("spawned %s appearance=%s", recordName, tostring(appearance)))
  else log("spawn failed: " .. tostring(id)) end
end

registerHotkey("rb15l_spawn_stock", "RB15 Livery: spawn STOCK RB15", function()
  spawn("Vehicle.v_sport1_rb15_f1", nil, 8.0, -3.0)
end)

-- cycles through the manifest: each press spawns the next livery, one lane to the right
registerHotkey("rb15l_spawn_next", "RB15 Livery: spawn NEXT livery (stock record + appearanceName)", function()
  if #liveries == 0 then loadManifest() end
  cursor = cursor % #liveries + 1
  spawn("Vehicle.v_sport1_rb15_f1", liveries[cursor], 8.0 + 6.0 * (cursor - 1), 3.0)
end)

registerHotkey("rb15l_spawn_next_record", "RB15 Livery: spawn NEXT livery (per-livery record)", function()
  if #liveries == 0 then loadManifest() end
  cursor = cursor % #liveries + 1
  spawn("Vehicle.v_sport1_rb15_f1_" .. liveries[cursor], nil, 8.0 + 6.0 * (cursor - 1), 3.0)
end)

registerHotkey("rb15l_despawn", "RB15 Livery: despawn all test cars", function()
  local es = Game.GetDynamicEntitySystem()
  for _, id in ipairs(spawned) do pcall(function() es:DeleteEntity(id) end) end
  log("despawned " .. #spawned); spawned = {}
end)

registerForEvent("onInit", function() loadManifest(); log("loaded") end)
