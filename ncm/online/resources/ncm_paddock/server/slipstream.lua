-- ncm_paddock / server / slipstream -- Paddock NPC cars in each other's (and players') wakes (L356).
--
-- The same physics as a player's car: aero.wake measures every car's wake from the server's own vehicle snapshots
-- (position + velocity, so no heading convention), and aero.slipstream runs the unit on the NPCs whose teams fit an
-- SL-1 (`npcEquipped`, deterministic per driver). The effect channel differs because a platform-driven car takes a
-- SPEED, not a force: the car's current leg speed is multiplied by `npcSpeedFactor(relief)` -- natural relief for
-- every car, the unit's active share on top for an equipped one. Leaving the wake brings the factor back to 1.
--
-- Only cars the server drives with `ai.setSpeed` (the platform backend, the bubble) feel it here; a Pace-driven car is
-- commanded by the Pace plugin on its host's client, and gets no server speed at all.
--
-- The network: an NPC unit that takes a wake tells ncm_slipstream, which tells the wake's owner if the owner carries
-- an enabled unit -- a human (NPC->human) or nobody (NPC->NPC, logged). Every NPC car is registered there by name, so
-- a human's unit can name the NPC whose wake it holds (human->NPC).
--
-- Extension point (not built yet): driver traits beyond the cautious-gap refusal (`aero.slipstream.npcPolicy`), NPCs
-- steering INTO a wake, teammates towing each other, qualifying tow timing.
PaddockSlip = {}

local Wake = NcmCore.get("aero.wake")
local Slip = NcmCore.get("aero.slipstream")
local function log(fmt, ...) print(("[ncm_paddock/slipstream] " .. fmt):format(...)) end

local humans = {}        -- vehicle id (string) -> true: every bound human Machine (from ncm_slipstream)
AddEventHandler("ncm:slip.humans", function(list)
    humans = {}
    for _, v in ipairs(type(list) == "table" and list or {}) do humans[tostring(v)] = true end
end)

--- Give a race car its wake state. `car` is the host's car table; `vid`, `personId` name it.
function PaddockSlip.attach(car, vid, personId)
    local world = PaddockStore and PaddockStore.world
    local p = world and world.people and world.people[personId]
    local equipped = Slip.npcEquipped(world and world.seed, personId)
    car.slip = { vid = vid, personId = personId, st = Slip.newState(), equipped = equipped,
        policy = Slip.npcPolicy(p and p.attrs), factor = 1, legSpeed = nil, activeS = 0, maxFactor = 1, linked = nil }
    TriggerEvent("ncm:slip.npc", vid, { name = PaddockWorld and PaddockWorld.personName(personId) or personId, personId = personId, equipped = equipped })
end

function PaddockSlip.detach(car)
    local s = car and car.slip
    if not s then return end
    if s.linked then TriggerEvent("ncm:slip.npclink", s.vid, s.linked, false) end
    TriggerEvent("ncm:slip.npc", s.vid, nil)
end

--- The speed to command for a leg the plan asks `v` of: remembered as the leg speed, then towed.
function PaddockSlip.leg(car, v)
    local s = car and car.slip
    if not s or not v then return v end
    s.legSpeed = v
    return v * (s.factor or 1)
end

--- One sample of a field. `cars` is a list of host car tables (with .slip); `canSet(car)` says whether this car is
--- still racing under server speed control. Every car with a snapshot is a wake source, racing or not.
function PaddockSlip.step(cars, dt, canSet)
    local snaps, list = {}, {}
    for _, car in ipairs(cars) do
        local s = car.slip
        if s then
            local ok, v = pcall(Open77.vehicles.get, s.vid)
            local w = ok and Wake.fromSnapshot(s.vid, v) or nil
            if w then snaps[s.vid] = w; list[#list + 1] = w end
        end
    end
    for vid in pairs(humans) do
        local n = tonumber(vid) or vid
        if not snaps[n] then
            local ok, v = pcall(Open77.vehicles.get, n)
            local w = ok and Wake.fromSnapshot(n, v) or nil
            if w then list[#list + 1] = w end
        end
    end
    for _, car in ipairs(cars) do
        local s = car.slip
        local me = s and snaps[s.vid]
        if me then
            local others = {}
            for _, w in ipairs(list) do if w.id ~= me.id then others[#others + 1] = w end end
            local best = Wake.best(me, others)
            Slip.step(s.st, best, dt, s.equipped, nil, s.policy)
            local relief = Slip.relief(best and best.q or 0, s.st, s.equipped)
            local f = Slip.npcSpeedFactor(relief)
            if s.st.phase == "active" then s.activeS = s.activeS + dt end
            if f > s.maxFactor then s.maxFactor = f end
            if canSet(car) and s.legSpeed and math.abs(f - s.factor) >= 0.005 then
                pcall(Open77.vehicles.ai.setSpeed, s.vid, s.legSpeed * f)
                s.factor = f
            elseif not canSet(car) then
                s.factor = 1
            end
            -- the network: an equipped NPC's held wake
            if s.equipped and s.st.phase == "active" and s.linked ~= s.st.leader then
                if s.linked then TriggerEvent("ncm:slip.npclink", s.vid, s.linked, false) end
                s.linked = s.st.leader
                TriggerEvent("ncm:slip.npclink", s.vid, s.linked, true)
            elseif s.linked and s.st.phase ~= "active" then
                TriggerEvent("ncm:slip.npclink", s.vid, s.linked, false)
                s.linked = nil
            end
        end
    end
end

--- One line per car at the end of a race: who ran a unit, how long it towed, the most it was worth (MASTER_TEST §SS).
function PaddockSlip.report(cars, raceId)
    for _, car in ipairs(cars) do
        local s = car.slip
        if s and (s.activeS > 0 or s.maxFactor > 1.001) then
            log("SLIPRACE race=%s person=%s unit=%s activeS=%.1f maxSpeedFactor=%.3f", tostring(raceId), tostring(s.personId),
                s.equipped and "yes" or "no", s.activeS, s.maxFactor)
        end
    end
end
