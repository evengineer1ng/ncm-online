-- NCM Economy v1 host: one idempotent money boundary for entry, settlement, rewards and refunds.
NcmEconomy = {}

local Settle = NcmCore.get("economy.settlement")
local Tags = NcmCore.get("competition.race_tags")
local Markets = NcmCore.get("economy.markets")
local Json = NcmCore.get("vocabulary.json")
local function sid() return NcmCalendar.serverId() end
local function now() return math.floor(Open77.time.unix()) end
local function log(fmt,...) print(("[ncm_league/economy] "..fmt):format(...)) end

function NcmEconomy.ensureStarter(driverId)
    MySQL.insert.await([[INSERT IGNORE INTO ledger
        (ncm_driver_id,server_id,kind,amount,currency,ref,note,idem_key)
        VALUES (?,?,'starter_grant',?,'eddies','economy_v1','NCM starting balance',?)]],
        {driverId,sid(),Markets.STARTER_GRANT,"starter:"..sid()..":"..driverId})
end

function NcmEconomy.balanceOf(driverId)
    if not driverId then return nil end
    return tonumber(MySQL.scalar.await("SELECT COALESCE(SUM(amount),0) FROM ledger WHERE ncm_driver_id=? AND server_id=?",{driverId,sid()})) or 0
end

-- Serialize every NCM debit for a Driver before its balance predicate runs. The ledger remains the only balance
-- truth (L84); this row carries no money, it only gives InnoDB one stable row to lock. Without it, two otherwise
-- atomic purchases/trades can both read the same SUM(amount) and overspend it in concurrent transactions.
function NcmEconomy.withBalanceLocks(tx,driverIds)
    local seen,ordered={},{}
    for _,driverId in ipairs(driverIds or {}) do
        if type(driverId)=="string" and driverId~="" and not seen[driverId] then seen[driverId]=true;ordered[#ordered+1]=driverId end
    end
    table.sort(ordered)
    local out={}
    for _,driverId in ipairs(ordered) do
        out[#out+1]={query="INSERT IGNORE INTO economy_balance_lock (server_id,ncm_driver_id,revision) VALUES (?,?,0)",values={sid(),driverId}}
    end
    for _,driverId in ipairs(ordered) do
        out[#out+1]={query="UPDATE economy_balance_lock SET revision=revision+1 WHERE server_id=? AND ncm_driver_id=?",values={sid(),driverId}}
    end
    for _,step in ipairs(tx or {}) do out[#out+1]=step end
    return out
end

--- An event that DECLARES itself unpaid: no fee, no purse. A Street Call is one by design (impromptu.lua's header),
--- and Economy v1 refused every entry to it with `economy_required` because check-in treated "no economy" as
--- "broken economy" (KB-186). The declaration is required -- a paid series that merely lost its economy block
--- must still refuse rather than quietly start racing for free.
function NcmEconomy.isUnpaid(e)
    return type(e)=="table" and e.economy==nil and (e.unpaid==true or e.class=="impromptu")
end

function NcmEconomy.checkIn(req)
    local fee,why
    if req.unpaid and req.economy==nil then fee=0 else fee,why=Settle.entryFee(req.economy) end
    if fee==nil then return nil,why end
    NcmEconomy.ensureStarter(req.driverId)
    local q
    if req.upgraded then
        q={query=[[UPDATE entry SET state='checked_in',fee=?,checked_in_at=?,asset_id=NULLIF(?,''),car_number=NULLIF(?,0)
            WHERE entry_id=? AND state IN ('interested','withdrawn') AND
            (SELECT COALESCE(SUM(amount),0) FROM ledger WHERE ncm_driver_id=? AND server_id=?)>=?]],
            values={fee,math.floor(req.checkedInAt),req.assetId or "",req.carNumber or 0,req.entryId,req.driverId,sid(),fee}}
    else
        q={query=[[INSERT INTO entry (entry_id,event_id,ncm_driver_id,state,fee,checked_in_at,asset_id,car_number)
            SELECT ?,?,?,'checked_in',?,?,NULLIF(?,''),NULLIF(?,0)
            WHERE (SELECT COALESCE(SUM(amount),0) FROM ledger WHERE ncm_driver_id=? AND server_id=?)>=?]],
            values={req.entryId,req.eventId,req.driverId,fee,math.floor(req.checkedInAt),req.assetId or "",req.carNumber or 0,req.driverId,sid(),fee}}
    end
    local tx={q}
    if fee>0 then tx[#tx+1]={query=[[INSERT IGNORE INTO ledger
        (ncm_driver_id,server_id,kind,amount,currency,ref,note,idem_key,event_id,series_id)
        SELECT ncm_driver_id,?,'event_entry',-fee,'eddies',event_id,'Scheduled event entry',?,event_id,?
        FROM entry WHERE entry_id=? AND state='checked_in' AND fee=?]],
        values={sid(),"entry:"..req.eventId..":"..req.driverId,req.seriesId,req.entryId,fee}} end
    tx=NcmEconomy.withBalanceLocks(tx,{req.driverId})
    local ok,err=MySQL.transaction.await(tx); if not ok then return nil,"transaction:"..tostring(err) end
    local row=MySQL.single.await("SELECT state,fee FROM entry WHERE entry_id=?",{req.entryId})
    if not row or row.state~="checked_in" then return nil,"insufficient_funds" end
    return {fee=tonumber(row.fee) or fee,balance=NcmEconomy.balanceOf(req.driverId)}
end

local function windowId(econ,t)
    local sec=math.max(60,tonumber(econ.repeatWindowSec) or 86400)
    return tostring(math.floor(t/sec)*sec)
end
local function previousBest(driverId,routeId,sessionId)
    return tonumber(MySQL.scalar.await([[SELECT MIN(COALESCE(sr.corrected_ms,sr.total_ms))/1000
        FROM session_result sr JOIN session s ON s.session_id=sr.session_id JOIN event e ON e.event_id=s.event_id
        WHERE sr.ncm_driver_id=? AND e.route_id=? AND sr.state='finished' AND sr.session_id<>?]],
        {driverId,routeId,sessionId}))
end
local function receiptText(receipt)
    local parts={}
    if receipt.intrigueBand then parts[#parts+1]=("Series %s · %d-race signal · purse x%.2f"):format(
        tostring(receipt.intrigueBand),tonumber(receipt.intrigueSample) or 0,tonumber(receipt.purseFactor) or 1) end
    for _,x in ipairs(receipt.lines or {}) do parts[#parts+1]=(x.amount>=0 and "+€$" or "-€$")..math.abs(x.amount).." "..x.label end
    parts[#parts+1]="NET "..(receipt.net>=0 and "+€$" or "-€$")..math.abs(receipt.net)
    return table.concat(parts," · ")
end
NcmEconomy.receiptText=receiptText

function NcmEconomy.settle(rec,results,reason,t)
    local e=rec.plan and rec.plan.e or {}; local econ=e.economy
    if NcmEconomy.isUnpaid(e) then return {} end   -- nothing to pay, and nothing failed (KB-186)
    local valid,why=Settle.validate(econ); if not valid then return nil,"economy:"..tostring(why) end
    -- L250: a mixed Paddock grid is classified against its whole field (NPCs too); its field bonus counts the humans
    local field=tonumber(rec.mixedField) or #results; local tt=field<=1; local win=windowId(econ,t); local paying=rec.kind=="race"
    local tagInput={session={kind=rec.kind,timeTrial=tt,fieldSize=field,gatesTotal=#(rec.s.gates or {})},results={}}
    for i,r in ipairs(results) do
        local copy={}; for k,v in pairs(r) do copy[k]=v end
        copy.incidents=copy.incidents or {}; copy.penalties=copy.penalties or {}; copy.jumpStart=copy.jumpStart==true
        copy.previousBestSec=previousBest(r.driverId,rec.routeId,rec.s.sessionId)
        tagInput.results[i]=copy
    end
    local tagOut=Tags.evaluate(tagInput,{maxTags=4})
    local settlements={}; local tx={{query="UPDATE session SET state='complete',green_at=NULLIF(?,-1),completed_at=?,complete_reason=? WHERE session_id=?",values={rec.s.greenAt or -1,t,reason,rec.s.sessionId}}}
    for i,r in ipairs(results) do
        local state=r.state; if state=="timed" then state="finished" elseif state=="no_time" then state="dns" end
        tx[#tx+1]={query=[[INSERT IGNORE INTO session_result
            (session_id,ncm_driver_id,entry_id,position,state,total_ms,penalty_ms,gap_ms,gates_done,gates_total,jump_start,dnf_reason,
             corrected_ms,incident_ms,incident_count,best_ms,asset_id,attribution_basis,configuration_ref)
            VALUES (?,?,NULLIF(?,''),?,?,NULLIF(?,-1),?,NULLIF(?,-1),?,?,?,NULLIF(?,''),NULLIF(?,-1),?,?,NULLIF(?,-1),NULLIF(?,''),?,NULLIF(?,''))]],
            values={rec.s.sessionId,r.driverId,r.entryId or "",r.position,state,
                r.totalSec and math.floor(r.totalSec*1000) or -1,math.floor((r.penaltySec or 0)*1000),r.gapSec and math.floor(r.gapSec*1000) or -1,
                r.progress or 0,r.gatesTotal or 2,r.jumpStart and 1 or 0,r.dnfReason or "",
                r.correctedSec and math.floor(r.correctedSec*1000) or -1,math.floor((r.incidentSec or 0)*1000),r.incidentCount or 0,
                r.bestSec and math.floor(r.bestSec*1000) or -1,r._assetId or "",r._basis or "unknown",r._configurationRef or ""}}
        if r.entryId and rec.kind=="race" then tx[#tx+1]={query="UPDATE entry SET state=? WHERE entry_id=?",values={state,r.entryId}} end
        if paying then
            local opportunity=(econ.id or e.seriesId)..":"..tostring(rec.routeId)..":"..win
            local paid=tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM ledger WHERE ncm_driver_id=? AND server_id=?
                AND kind='event_completion' AND opportunity_id=?]],{r.driverId,sid(),opportunity})) or 0
            local qualified=(tagOut.drivers[i] and tagOut.drivers[i].qualified) or {}
            local resolved,rwhy=Settle.resolve({economy=econ,fieldSize=field,fieldBonusCount=#results,result=r,tags=qualified,
                repeatCompletion=paid>=(tonumber(econ.fullRateCompletions) or 1)})
            if not resolved then return nil,"resolve:"..tostring(rwhy) end
            local intrigue=(tonumber(econ.intrigueFactor) or 1); local moody=(tonumber(econ.moodyPurseFactor) or 1)
            local receipt={sessionId=rec.s.sessionId,eventId=rec.eventId,timeTrial=resolved.timeTrial,
                intrigueBand=econ.intrigueBand,intrigueScore=econ.intrigueScore,intrigueSample=econ.intrigueSample,
                purseFactor=intrigue*moody,moodyPurseTier=econ.moodyPurseTier,
                lines={},gross=resolved.gross,entryFee=resolved.entryFee,net=resolved.net,tags=(tagOut.drivers[i] and tagOut.drivers[i].tags) or {}}
            receipt.lines[#receipt.lines+1]={kind="event_entry",label="Entry",amount=-resolved.entryFee}
            for _,line in ipairs(resolved.lines) do
                receipt.lines[#receipt.lines+1]=line
                local suffix=line.code
                if line.meta and line.meta.tagId then suffix="tag:"..line.meta.tagId..":"..tostring(econ.version or 1) end
                if line.meta and line.meta.bandId then suffix="target:"..line.meta.bandId end
                -- `NULLIF(?, '')` with an empty-string sentinel, never a bare nil (see `market_knowledge.lua`).
                -- OPEN//77 measures `#values`, and a trailing nil shortens the array rather than becoming SQL
                -- NULL: this statement was raising `parameter_count_mismatch: found 11 placeholders but 10
                -- values` on the live server for every payout line EXCEPT `event_completion`, which is the only
                -- branch that supplies an opportunity. Because the error was uncaught it aborted the whole
                -- settlement transaction, so placement money, field bonuses and clean-driving bounties were not
                -- merely mis-recorded, they were never paid. Found 2026-09-28 in the live log (`KB-168`).
                tx[#tx+1]={query=[[INSERT IGNORE INTO ledger
                    (ncm_driver_id,server_id,kind,amount,currency,ref,note,idem_key,event_id,session_id,series_id,opportunity_id)
                    VALUES (?,?,?,?,'eddies',NULLIF(?,''),?,?,NULLIF(?,''),NULLIF(?,''),NULLIF(?,''),NULLIF(?,''))]],
                    values={r.driverId,sid(),line.kind,line.amount,rec.routeId or "",
                        line.label,"payout:"..rec.s.sessionId..":"..r.driverId..":"..suffix,rec.eventId or "",rec.s.sessionId or "",e.seriesId or "",
                        (line.kind=="event_completion" and opportunity) or ""}}
            end
            -- Racing Week's craze (L303): while the money is unusually high, a race pays more. One auditable line on top
            -- of the positive payout, never a change to Economy v1's resolver; the run's wallet dies at the collapse anyway.
            do
                local okW,wk=pcall(function() return GlobalState.ncmWeek end)
                local m=okW and type(wk)=="table" and tonumber(wk.money) or 1
                local earned=0
                for _,line in ipairs(resolved.lines) do if (line.amount or 0)>0 then earned=earned+line.amount end end
                local bonus=math.floor(earned*(m-1))
                if m>1 and bonus>0 then
                    local label=("Racing Week craze x%.2f"):format(m)
                    receipt.lines[#receipt.lines+1]={kind="craze_bonus",label=label,amount=bonus}
                    receipt.gross=(receipt.gross or 0)+bonus; receipt.net=(receipt.net or 0)+bonus
                    resolved.gross=resolved.gross+bonus; resolved.net=resolved.net+bonus
                    tx[#tx+1]={query=[[INSERT IGNORE INTO ledger
                        (ncm_driver_id,server_id,kind,amount,currency,ref,note,idem_key,event_id,session_id,series_id,opportunity_id)
                        VALUES (?,?,'craze_bonus',?,'eddies',?,?,?,NULLIF(?,''),NULLIF(?,''),NULLIF(?,''),NULL)]],
                        values={r.driverId,sid(),bonus,("week:run%s:h%s"):format(tostring(wk.run),tostring(wk.hours)),label,
                            "payout:"..rec.s.sessionId..":"..r.driverId..":craze",rec.eventId or "",rec.s.sessionId or "",e.seriesId or ""}}
                end
            end
            tx[#tx+1]={query=[[INSERT IGNORE INTO session_settlement
                (session_id,ncm_driver_id,economy_id,economy_version,time_trial,gross,entry_fee,net,receipt_json,tags_json,settled_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)]],values={rec.s.sessionId,r.driverId,econ.id or e.seriesId,econ.version or 1,
                    resolved.timeTrial and 1 or 0,resolved.gross,resolved.entryFee,resolved.net,Json.encode(receipt),Json.encode(receipt.tags),math.floor(t)}}
            settlements[r.driverId]=receipt
        end
    end
    local ok,err=MySQL.transaction.await(tx); if not ok then return nil,"transaction:"..tostring(err) end
    for driverId,receipt in pairs(settlements) do receipt.balance=NcmEconomy.balanceOf(driverId); receipt.text=receiptText(receipt) end
    return settlements
end

function NcmEconomy.refundEvent(eventId,reason)
    local rows=MySQL.query.await("SELECT entry_id,ncm_driver_id,fee FROM entry WHERE event_id=? AND fee>0",{eventId}) or {}
    for _,r in ipairs(rows) do MySQL.insert.await([[INSERT IGNORE INTO ledger
        (ncm_driver_id,server_id,kind,amount,currency,ref,note,idem_key,event_id)
        VALUES (?,?,'entry_refund',?,'eddies',?,?,?,?)]],{r.ncm_driver_id,sid(),tonumber(r.fee) or 0,eventId,
        "Entry refund: "..tostring(reason),"refund:entry:"..tostring(r.entry_id),eventId}) end
    return #rows
end

function NcmEconomy.reward(driverId,kind,amount,idem,refs)
    amount=math.floor(tonumber(amount) or 0); if amount<=0 or type(idem)~="string" or idem=="" then return nil,"invalid_reward" end
    -- Five nullable positions, all sentinelled for the same reason as the payout line above (`KB-168`).
    MySQL.insert.await([[INSERT IGNORE INTO ledger
        (ncm_driver_id,server_id,kind,amount,currency,ref,note,idem_key,event_id,session_id,series_id,opportunity_id)
        VALUES (?,?,?,?,'eddies',NULLIF(?,''),?,?,NULLIF(?,''),NULLIF(?,''),NULLIF(?,''),NULLIF(?,''))]],
        {driverId,sid(),kind,amount,(refs and refs.ref) or "",(refs and refs.note) or kind,idem,
        (refs and refs.eventId) or "",(refs and refs.sessionId) or "",(refs and refs.seriesId) or "",(refs and refs.opportunityId) or ""})
    return true,NcmEconomy.balanceOf(driverId)
end

function NcmEconomy.recover()
    local rows=MySQL.query.await([[SELECT DISTINCT e.event_id FROM event e JOIN session s ON s.event_id=e.event_id
        WHERE e.server_id=? AND e.starts_at<? AND s.state NOT IN ('complete','cancelled')]],{sid(),now()-60}) or {}
    local n=0; for _,r in ipairs(rows) do n=n+NcmEconomy.refundEvent(r.event_id,"server_recovery") end
    if n>0 then log("recovery refunded %d paid entr(ies)",n) end
    return n
end

RegisterCommand("ncm.balance",function(source,args)
    local pid=tonumber(source) or 0; local d=pid>0 and NcmCalendar.resolveDriver(pid) or (args and args[1] and {ncmDriverId=args[1]})
    if not d then return end; NcmEconomy.ensureStarter(d.ncmDriverId); local b=NcmEconomy.balanceOf(d.ncmDriverId)
    if pid>0 then pcall(Open77.chat.send,pid,"[NCM] Balance: €$"..tostring(b)) else log("balance %s = %d",d.ncmDriverId,b) end
end,false)

log("Economy v1 ready")
