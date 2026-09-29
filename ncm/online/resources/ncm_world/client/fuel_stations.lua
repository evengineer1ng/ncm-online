-- Baseline-visible fuel infrastructure. Navigation remains owned by NcmNav; these are passive map POIs.
local locations=NcmCore.get("data.fuel_locations")
local stations=locations.sites
local handles={}
local function log(fmt,...) print(("[ncm_world/client/fuel_stations] "..fmt):format(...)) end
local function create()
 if #handles>0 then return end
 local made,custom,fallback=0,0,0
 for _,s in ipairs(stations) do
  -- Establish visibility first. `vendor` is documented map-capable; unlike a HUD-only variant it appears
  -- on the fullscreen map even when the experimental native SVG adapter is absent.
  local ok,id,reason=pcall(Open77.blips.create,{position={x=s.x,y=s.y,z=s.z},sprite="vendor",
   title=s.name,description="NCM fuel station · park here and type /ncm.refuel"})
  if ok and id then
   handles[#handles+1]=id;made=made+1
   local iconOk,applied,iconReason=pcall(Open77.blips.setIcon,id,{asset="icons/fuel.svg",size=32})
   if iconOk and applied then custom=custom+1
   else
    fallback=fallback+1
    log("SVG refused for %s: %s; native vendor sprite remains",s.id,
     tostring((not iconOk) and applied or iconReason))
   end
  else log("no blip for %s: %s",s.id,tostring((not ok) and id or reason)) end
 end
 log("%d/%d fuel station blip(s): %d SVG, %d native fallback",made,#stations,custom,fallback)
end
local function remove() for _,id in ipairs(handles) do pcall(Open77.blips.remove,id) end handles={} end
-- KB-203: pins made before the character save loads die with the pre-game world; client/landmarks.lua owns
-- the gate that runs this once the player is settled in the real world (and again after a world reload).
NcmMapPins.register("fuel_stations",function() remove();create() end)
AddEventHandler("onClientResourceStop",function(name) if name==GetCurrentResourceName() then remove() end end)
