-- ncm-core module: economy.settlement
-- Deterministic event economics. It produces facts; the host owns persistence and balances.
local Core = NcmCore

Core.define("economy.settlement", function()
    local M = { version = "1.0.0" }
    local NONPAYING = { dnf=true, dns=true, dsq=true, no_time=true }

    local function money(v, name, allowZero)
        if type(v)~="number" or v~=math.floor(v) or v<0 or (not allowZero and v==0) then
            return nil,"invalid_"..name
        end
        return v
    end
    function M.validate(e)
        if type(e)~="table" then return false,"economy_required" end
        if not money(e.entryFee or 0,"entry_fee",true) then return false,"invalid_entry_fee" end
        for _,k in ipairs({"timeTrialCompletion","raceCompletion"}) do if not money(e[k] or 0,k,true) then return false,"invalid_"..k end end
        if type(e.placement)~="table" or type(e.fieldBonus)~="table" or type(e.tagBounties)~="table" then return false,"tables_required" end
        return true
    end
    function M.entryFee(e) local ok,why=M.validate(e); if not ok then return nil,why end; return e.entryFee or 0 end
    local function add(lines,kind,label,amount,code,meta)
        if amount and amount>0 then lines[#lines+1]={kind=kind,label=label,amount=amount,code=code,meta=meta} end
    end
    function M.resolve(req)
        if type(req)~="table" then return nil,"request_required" end
        local e=req.economy; local ok,why=M.validate(e); if not ok then return nil,why end
        local r=req.result or {}; local field=math.max(0,math.floor(tonumber(req.fieldSize) or 0)); local tt=field<=1
        local lines={}; local classified=not NONPAYING[tostring(r.state)] and r.state=="finished"
        if classified then
            local completion=tt and (e.timeTrialCompletion or 0) or (e.raceCompletion or 0)
            if tt and req.repeatCompletion==true then completion=e.repeatFloor or 0 end
            add(lines,"event_completion","Completion",completion,"completion")
            if not tt then
                local place=e.placement[tonumber(r.position)]
                add(lines,"event_placement","P"..tostring(r.position),place,"placement")
                -- a mixed Paddock grid (L250) places against the whole field but pays its bonus for the humans only
                local fbN=math.max(0,math.floor(tonumber(req.fieldBonusCount) or field))
                local fb=math.min((e.fieldBonus.perEntrant or 0)*fbN,e.fieldBonus.max or 0)
                add(lines,"event_field_bonus","Field bonus",fb,"field")
            end
            local bestTarget=nil
            for _,band in ipairs(e.targets or {}) do
                if tonumber(r.correctedSec or r.totalSec) and tonumber(band.sec)
                    and tonumber(r.correctedSec or r.totalSec)<=band.sec and req.targetPaid~=true then bestTarget=band end
            end
            if bestTarget then add(lines,"event_target",bestTarget.label or "Target",bestTarget.amount,"target",{bandId=bestTarget.id}) end
            local tagTotal=0
            for _,tag in ipairs(req.tags or {}) do
                local amount=e.tagBounties[tag.id]
                local room=math.max(0,(e.maxTagBounty or 0)-tagTotal)
                local paid=math.min(tonumber(amount) or 0,room)
                add(lines,"tag_bonus",tag.label or tag.id,paid,"tag",{tagId=tag.id})
                tagTotal=tagTotal+paid
            end
        end
        local gross=0; for _,line in ipairs(lines) do gross=gross+line.amount end
        return {timeTrial=tt,classified=classified,lines=lines,gross=gross,entryFee=e.entryFee or 0,net=gross-(e.entryFee or 0)}
    end
    return M
end)
