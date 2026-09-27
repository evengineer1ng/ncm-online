-- Research Exchange v1: explicit turn-in of existing proof-bearing evidence. Nothing automatic pays.
NcmResearch = {}
local ids=NcmCore.get("vocabulary.ids")
local hostRng=function() return math.random() end
local function sid() return NcmCalendar.serverId() end
local function now() return math.floor(Open77.time.unix()) end
local function tell(pid,text) pcall(Open77.chat.send,pid,"[NCM Research] "..text) end
local function log(fmt,...) print(("[ncm_league/research] "..fmt):format(...)) end

local PROGRAMS={
    identity_field_notes={version=1,reward=150,label="Physical identity field note"},
    capability_field_notes={version=1,reward=100,label="Capability observation"},
}

local function classify(row)
    if row.source_kind~="world_encounter" then return nil end -- catalogue publication never pays
    if row.knowledge_kind=="identity_reveal" then
        return "identity_field_notes","identity:"..tostring(row.vehicle_key)
    end
    if tostring(row.knowledge_kind):match("^observed_") and row.observation_basis=="server_measured" then
        -- One accepted characteristic per physical Machine, not every incremental maximum/configuration.
        return "capability_field_notes",tostring(row.knowledge_kind)..":"..tostring(row.asset_id or row.vehicle_key)
    end
end

function NcmResearch.eligible(driverId)
    local rows=MySQL.query.await([[SELECT e.evidence_id,e.evidence_key,e.vehicle_key,e.asset_id,e.knowledge_kind,
        e.source_kind,e.observation_basis,e.observed_at FROM vehicle_knowledge_evidence e
        WHERE e.ncm_driver_id=? AND e.server_id=? ORDER BY e.observed_at,e.evidence_id]],{driverId,sid()}) or {}
    local out,seen={},{}
    for _,r in ipairs(rows) do
        local pid,identity=classify(r)
        if pid and not seen[pid..":"..identity] then
            local p=PROGRAMS[pid]; local idem=("research:%s:v%d:%s:%s"):format(pid,p.version,driverId,identity)
            local paid=tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM research_submission WHERE idem_key=?",{idem})) or 0
            if paid==0 then
                seen[pid..":"..identity]=true; out[#out+1]={programId=pid,program=p,evidence=r,identity=identity,idem=idem}
            end
        end
    end
    return out
end

function NcmResearch.submit(driverId,index)
    local list=NcmResearch.eligible(driverId); local item=list[tonumber(index) or 0]
    if not item then return nil,"no_eligible_submission" end
    local p=item.program; local r=item.evidence; local submissionId=ids.uuid4(hostRng); local t=now()
    local ok,why=MySQL.transaction.await({
        {query=[[INSERT IGNORE INTO research_submission
            (submission_id,idem_key,ncm_driver_id,server_id,program_id,program_version,evidence_id,evidence_identity,
             consent_scope,state,reason,amount,submitted_at)
            VALUES (?,?,?,?,?,?,?,?,?,'accepted','eligible_personal_first',?,?)]],
         values={submissionId,item.idem,driverId,sid(),item.programId,p.version,r.evidence_id,item.identity,"program_use",p.reward,t}},
        {query=[[INSERT IGNORE INTO ledger
            (ncm_driver_id,server_id,kind,amount,currency,ref,note,idem_key,asset_id,opportunity_id)
            SELECT ncm_driver_id,server_id,'research_reward',amount,'eddies',evidence_id,?,idem_key,NULLIF(?,''),?
            FROM research_submission WHERE idem_key=? AND state='accepted']],
         values={p.label,r.asset_id or "",item.programId..":v"..p.version,item.idem}},
    })
    if not ok then return nil,"transaction:"..tostring(why) end
    return {label=p.label,reward=p.reward,balance=NcmEconomy.balanceOf(driverId),identity=item.identity}
end

RegisterCommand("ncm.research",function(source,args)
    local pid=tonumber(source) or 0; if pid<=0 then return end
    CreateThread(function()
        local d=NcmCalendar.resolveDriver(pid); if not d then tell(pid,"No NCM Driver."); return end
        local index=tonumber(args and args[1])
        if index then
            local item,why=NcmResearch.submit(d.ncmDriverId,index)
            if not item then tell(pid,"Submission refused: "..tostring(why)); return end
            tell(pid,("ACCEPTED · %s · +€$%d · balance €$%d"):format(item.label,item.reward,item.balance))
            pcall(Open77.notifications.send,pid,{type="success",title="RESEARCH ACCEPTED · +€$"..item.reward,message=item.label.." · balance €$"..item.balance,icon="NCM",durationMs=8000})
            return
        end
        local list=NcmResearch.eligible(d.ncmDriverId)
        if #list==0 then tell(pid,"No unsubmitted eligible evidence. Drive, discover and observe; submission is always explicit."); return end
        tell(pid,("%d eligible submission(s). Use /ncm.research <n> to license one to the program."):format(#list))
        for i,item in ipairs(list) do if i<=12 then tell(pid,("%d. %s · %s · €$%d"):format(i,item.program.label,item.identity,item.program.reward)) end end
    end)
end,false)

log("Research Exchange ready: %d program(s)",2)
