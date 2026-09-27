-- The Driver File: one small, on-demand read model for the facts NCM already knows about this player.
-- It owns no gameplay state. Races, money, collection, parts and progression remain authoritative in their
-- existing services; this module only composes their bounded player-facing projections.
NcmVisibility = {}

local Json = NcmCore.get("vocabulary.json")
local Presentation = NcmCore.get("driver.presentation")
local function now() return math.floor(Open77.time.unix()) end
local function sid() return NcmCalendar.serverId() end
local function tell(pid, text) pcall(Open77.chat.send, pid, "[NCM] " .. text) end

local function selectedBadges(driverId)
    local ok, row = pcall(MySQL.single.await,
        "SELECT banner_id,displayed_badges_json FROM driver_presentation WHERE ncm_driver_id=? AND server_id=?",
        {driverId,sid()})
    if not ok or not row then return {} end
    local decoded = type(row.displayed_badges_json)=="string" and Json.decode(row.displayed_badges_json) or nil
    local out = {}
    for _, badgeId in ipairs(type(decoded)=="table" and decoded or {}) do out[tostring(badgeId)] = true end
    return out
end

local function badgeRows(progress, driverId)
    local chosen, out = selectedBadges(driverId), {}
    local firstAt = {}
    for _, a in ipairs(progress.accomplishments or {}) do
        local at = tonumber(a.at) or 0
        if not firstAt[a.kind] or at < firstAt[a.kind] then firstAt[a.kind] = at end
    end
    for id, def in pairs(Presentation.BADGES) do
        if def.accomplishment and firstAt[def.accomplishment] then
            out[#out+1] = {id=id,label=def.label,glyphId=def.glyphId,earnedAt=firstAt[def.accomplishment],displayed=chosen[id]==true}
        end
    end
    table.sort(out,function(a,b) return (a.earnedAt or 0)<(b.earnedAt or 0) end)
    return out
end

local function currentCommitment(pid)
    local rows = NcmGuide.rows(pid)
    local mine
    for _, row in ipairs(rows or {}) do
        if row.myState and row.myState ~= "none" then mine = row; break end
    end
    if not mine then
        return {state="free",eyebrow="THE ROAD IS OPEN",title="Choose the next story.",
            detail="The Race Guide carries the live calendar. Looking costs nothing; each event tells you the machine, weather and money before you commit.",
            action="Open Race Guide",destination="guide"}
    end
    local base = {eventId=mine.eventId,route=mine.routeName,series=mine.seriesName,venue=mine.venueName,
        startsAt=mine.startsAt,entryOpensAt=mine.entryOpensAt,entryClosesAt=mine.entryClosesAt,state=mine.myState,
        destination="guide"}
    if mine.myState == "interested" then
        base.eyebrow,base.title = "ON THE LIST · NOT ENTERED", mine.routeName
        base.detail = "Your venue is marked and practice is open. A list place is not a grid reservation and no fee has been charged."
        base.action = "Ride to "..tostring(mine.venueName)..". At the line, choose ENTER RACE while entries are open. /ncm.gps re-marks the route."
    elseif mine.myState == "checked_in" or mine.myState == "registered" or mine.myState == "provisioned" then
        base.eyebrow,base.title = "ENTERED · THE FIELD KNOWS YOUR NAME", mine.routeName
        base.detail = "Your entry is recorded. Stay available for race control; the next session call will come to you."
        base.action = "Use My Races for timing. You may withdraw before a session holds you; after that, leaving is a forfeit."
    else
        base.eyebrow,base.title = string.upper(tostring(mine.myState):gsub("_"," ")), mine.routeName
        base.detail = "This event is in your file. Race control owns the next transition."
        base.action = "Open My Races for the live state and venue."
    end
    return base
end

local function recentMoney(driverId)
    local ok, rows = pcall(MySQL.query.await, [[SELECT kind,amount,note,UNIX_TIMESTAMP(created_at) AS at
        FROM ledger WHERE ncm_driver_id=? AND server_id=? ORDER BY ledger_id DESC LIMIT 8]], {driverId,sid()})
    if not ok then return {} end
    local out = {}
    for _, row in ipairs(rows or {}) do
        out[#out+1]={kind=tostring(row.kind or "transaction"),amount=tonumber(row.amount) or 0,
            note=tostring(row.note or row.kind or "Transaction"),at=tonumber(row.at) or 0}
    end
    return out
end

local function recordStats(driverId)
    local ok, row = pcall(MySQL.single.await, [[SELECT COUNT(*) AS sessions,
        SUM(CASE WHEN r.state='finished' THEN 1 ELSE 0 END) AS finishes,
        SUM(CASE WHEN r.state='finished' AND r.position=1 AND
          (SELECT COUNT(*) FROM session_result x WHERE x.session_id=r.session_id)>1 THEN 1 ELSE 0 END) AS wins
        FROM session_result r JOIN session s ON s.session_id=r.session_id
        WHERE r.ncm_driver_id=? AND s.state='complete']], {driverId})
    if not ok or not row then return {sessions=0,finishes=0,wins=0} end
    return {sessions=tonumber(row.sessions) or 0,finishes=tonumber(row.finishes) or 0,wins=tonumber(row.wins) or 0}
end

function NcmVisibility.snapshot(pid)
    pid = tonumber(pid) or 0
    local driver = NcmCalendar.resolveDriver(pid)
    if not driver then return nil,"no_driver" end
    NcmEconomy.ensureStarter(driver.ncmDriverId)
    local profile = MySQL.single.await("SELECT display,number FROM driver_profile WHERE ncm_driver_id=? AND server_id=?",
        {driver.ncmDriverId,sid()}) or {}
    local progress = NcmProgression.load(driver.ncmDriverId)
    local collection = NcmCollection.payload(pid) or {}
    local components = NcmComponents.inventory(pid) or {}
    local stored,installed=0,0
    for _, part in ipairs(components.parts or {}) do
        if part.location_kind=="installed" then installed=installed+1 else stored=stored+1 end
    end
    return {
        serverNow=now(),driver={display=profile.display or driver.display or "Driver",number=tonumber(profile.number),
            sr=tonumber(progress.sr and progress.sr.sr) or 5.0},
        balance=NcmEconomy.balanceOf(driver.ncmDriverId),commitment=currentCommitment(pid),
        collection={discovered=tonumber(collection.discovered) or 0,total=tonumber(collection.total) or 0,
            owned=tonumber(collection.owned) or 0,partsStored=stored,partsInstalled=installed},
        stats=recordStats(driver.ncmDriverId),badges=badgeRows(progress,driver.ncmDriverId),
        transactions=recentMoney(driver.ncmDriverId),
        references={
            {id="guide",title="RACE GUIDE",text="The live calendar, your commitments and every official result."},
            {id="market",title="MARKET",text="Local physical stock. A purchase moves one serialized Machine or component into your ownership."},
            {id="collection",title="MACHINE INDEX",text="What you have learned, what you own, the evidence behind it and the parts that fit."},
        },
    }
end

local function push(pid)
    local ok, payload = pcall(NcmVisibility.snapshot,pid)
    if ok and payload then TriggerClientEvent("ncm:visibility.payload",pid,payload)
    else tell(pid,"Driver File unavailable right now: "..tostring(payload)) end
end

RegisterNetEvent("ncm:visibility.request",function() local pid=tonumber(source) or 0;CreateThread(function() push(pid) end) end)
RegisterCommand("ncm.status",function(source,args)
    local pid=tonumber(source) or 0
    if pid<=0 then return end
    CreateThread(function()
        local ok,s=pcall(NcmVisibility.snapshot,pid)
        if not ok or not s then tell(pid,"Driver File unavailable.");return end
        local c=s.commitment or {}
        tell(pid,("%s #%s · €$%d · SR %.2f · %d Machines · Index %d/%d"):format(s.driver.display,
            tostring(s.driver.number or "--"),s.balance or 0,s.driver.sr or 0,s.collection.owned or 0,
            s.collection.discovered or 0,s.collection.total or 0))
        tell(pid,("NOW: %s — %s"):format(c.eyebrow or "",c.action or c.detail or ""))
    end)
end,false)
