-- Physical-only Market discovery. No map blips and no proximity discovery: the Driver must press E while
-- standing at a terminal, then the league host independently validates its fresh authoritative position.
local Markets=NcmCore.get("economy.markets")
-- KB-205: "interact" is not an Open77.input control name (isDown refuses it as unsupported_action_key), so
-- the terminal never connected. Physical reads only: E on keyboard, X on a pad, as the race rings use.
local KEYS={"E","padX"}
local shown,wasDown=nil,false
local function notify(market)
 pcall(Open77.exports.call,"open77_notifications","show",{id="ncm_autofixer",replace=true,type="info",
  title="AUTOFIXER TERMINAL",message="Press E (pad X) to connect to "..market.displayName.."."})
end
CreateThread(function()
 while true do
  local ok,x,y=pcall(Open77.character.position);local near=nil
  if ok and type(x)=="number" then
   local best=16
   for _,m in ipairs(Markets.MARKETS) do if not m.universallyKnown then local dx,dy=x-m.x,y-m.y;local d=dx*dx+dy*dy;if d<best then best,near=d,m end end end
  end
  if near and shown~=near.marketId then shown=near.marketId;notify(near) elseif not near then shown=nil end
  local captured=false;pcall(function() captured=Open77.input.isCaptured()==true end)
  local down=false
  if not captured then for _,k in ipairs(KEYS) do local okD,v=pcall(Open77.input.isDown,k);if okD and v==true then down=true end end end
  if near and down and not wasDown then TriggerServerEvent("ncm:market.discover",near.marketId) end
  wasDown=down
  Wait(near and 80 or 500)
 end
end)
