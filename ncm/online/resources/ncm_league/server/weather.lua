-- NCM Weather Service: persistent policy/plan owner and OPEN//77 environment adapter.
-- Default-world slice only. Event bucket policy is deliberately a later consumer.
NcmWeather = {}

local Weather = NcmCore.get("world.weather")
local SCOPE = "default"
local HORIZON_SEC = 7 * 24 * 60 * 60
local READ_HORIZON_SEC = 24 * 60 * 60
local EXTEND_BELOW_SEC = 24 * 60 * 60
local HISTORY_SEC = 24 * 60 * 60
local HISTORY_MAX = 256
local RECONCILE_MS = 10000

-- Balance data, not locked product constants. Holds are intentionally hours/tens of minutes, not showcase speed.
local POLICY = {
    version = 1,
    transitionSec = 120,
    states = {
        { weather="sunny",       weight=22, minDurationSec=5400, maxDurationSec=14400 },
        { weather="lightclouds", weight=24, minDurationSec=5400, maxDurationSec=14400 },
        { weather="cloudy",      weight=20, minDurationSec=3600, maxDurationSec=10800 },
        { weather="rain",        weight=12, minDurationSec=2700, maxDurationSec=7200 },
        { weather="heavyclouds", weight=10, minDurationSec=2700, maxDurationSec=7200 },
        { weather="fog",         weight=5,  minDurationSec=1800, maxDurationSec=5400 },
        { weather="pollution",   weight=4,  minDurationSec=1800, maxDurationSec=5400 },
        { weather="sandstorm",   weight=3,  minDurationSec=1800, maxDurationSec=3600 },
    },
}

local state = { ready=false, reason="not_started", plan=nil, recent={}, current=nil, applied=nil, revision=0 }
local function log(fmt, ...) print(("[ncm_league/weather] " .. fmt):format(...)) end
local function now() return math.floor(Open77.time.unix()) end

local function loadRows()
    local rows = MySQL.query.await([[SELECT transition_id, starts_at_utc, weather, transition_sec,
        policy_version, generator_version FROM weather_transition WHERE scope = ? ORDER BY starts_at_utc]], {SCOPE}) or {}
    local out = {}
    for _, r in ipairs(rows) do out[#out+1] = {
        id=tostring(r.transition_id), startsAtUtc=tonumber(r.starts_at_utc), weather=tostring(r.weather),
        transitionSec=tonumber(r.transition_sec), policyVersion=tonumber(r.policy_version),
        generatorVersion=tonumber(r.generator_version),
    } end
    return out
end

local function loadPlan()
    local rows = MySQL.query.await("SELECT * FROM weather_plan WHERE scope = ? LIMIT 1", {SCOPE}) or {}
    local m = rows[1]
    if not m then return nil end
    return {
        epoch=tostring(m.epoch), seed=tonumber(m.seed), randomState=tonumber(m.random_state),
        policyVersion=tonumber(m.policy_version), generatorVersion=tonumber(m.generator_version),
        nextIndex=tonumber(m.next_index), coveredUntilUtc=tonumber(m.covered_until_utc), rows=loadRows(),
        lastAppliedId=m.last_applied_id and tostring(m.last_applied_id) or nil,
        forecastRevision=tonumber(m.forecast_revision) or 1,
    }
end

-- The platform caps how many statements one transaction may carry. A seven-day plan is hundreds of rows, so
-- sending them as a single transaction returns `invalid_transaction` (open77/runtime.lua:330) and the whole
-- weather service fails to start -- observed on deploy 2026-09-22. The platform's own code chunks for exactly
-- this reason (`freeroam/pvp/server/ranked.lua` commit(), clamped to 64, default 48); this follows that.
local TX_CHUNK = 48

local function insertRows(rows)
    if #rows == 0 then return true end
    local i = 1
    while i <= #rows do
        local tx = {}
        for k = i, math.min(i + TX_CHUNK - 1, #rows) do
            local r = rows[k]
            tx[#tx+1] = { query=[[INSERT IGNORE INTO weather_transition
                (transition_id, scope, starts_at_utc, weather, transition_sec, policy_version, generator_version)
                VALUES (?, ?, ?, ?, ?, ?, ?)]], values={r.id,SCOPE,r.startsAtUtc,r.weather,r.transitionSec,r.policyVersion,r.generatorVersion} }
        end
        -- transaction.await resolves a failure to `false, reason` rather than raising (oxmysql parity), so the
        -- return value has to be tested, not just the absence of an error.
        local ok, why = MySQL.transaction.await(tx)
        if not ok then return false, tostring(why or "transaction_failed") end
        i = i + TX_CHUNK
    end
    return true
end

local function saveMeta(plan, applied)
    MySQL.update.await([[INSERT INTO weather_plan
        (scope,epoch,seed,random_state,policy_version,generator_version,next_index,covered_until_utc,last_applied_id,forecast_revision,updated_at)
        VALUES (?,?,?,?,?,?,?,?,NULLIF(?, ''),?,?) ON DUPLICATE KEY UPDATE epoch=VALUES(epoch),seed=VALUES(seed),
        random_state=VALUES(random_state),policy_version=VALUES(policy_version),generator_version=VALUES(generator_version),
        next_index=VALUES(next_index),covered_until_utc=VALUES(covered_until_utc),last_applied_id=VALUES(last_applied_id),
        forecast_revision=VALUES(forecast_revision),updated_at=VALUES(updated_at)]],
        -- `last_applied_id` is nil until something has been applied, and a nil in the middle of a Lua table
        -- constructor truncates `#` -- so the 11-placeholder query received 8 values and the platform answered
        -- `invalid_parameters`, taking the whole weather service down at boot. Pass "" and let NULLIF restore
        -- the NULL, which is the idiom this codebase already uses at settlement.
        {SCOPE,plan.epoch,plan.seed,plan.randomState,plan.policyVersion,plan.generatorVersion,plan.nextIndex,
         plan.coveredUntilUtc,applied or plan.lastAppliedId or "",plan.forecastRevision or 1,now()})
end

local function newPlan(t)
    local seed = (t % 2147483646) + 1
    local epoch = "wx-" .. tostring(t)
    local plan = Weather.generate{policy=POLICY,startsAtUtc=t,untilUtc=t+HORIZON_SEC,seed=seed,epoch=epoch}
    plan.forecastRevision = 1
    assert(insertRows(plan.rows), "weather_transition_insert_failed")
    saveMeta(plan)
    return plan
end

local function extendPlan(t)
    local plan = state.plan
    if plan.coveredUntilUtc - t >= EXTEND_BELOW_SEC then return end
    local oldCount = #plan.rows
    local extended, why = Weather.extend(plan, POLICY, t + HORIZON_SEC)
    if not extended then error("weather_extend:" .. tostring(why)) end
    local appended = {}; for i=oldCount+1,#extended.rows do appended[#appended+1]=extended.rows[i] end
    assert(insertRows(appended), "weather_transition_extend_failed")
    extended.forecastRevision = (plan.forecastRevision or 1) + 1
    state.plan = extended; saveMeta(extended, state.applied)
    log("plan extended rows=%d covered_until=%d forecast_revision=%d", #appended, extended.coveredUntilUtc, extended.forecastRevision)
end

local function canonical()
    local ok, value, reason = pcall(Open77.environment.getState)
    if not ok then return nil, tostring(value) end
    if not value then return nil, tostring(reason) end
    return value
end

local function observe(env, reason, transitionId)
    if type(env) ~= "table" then return end
    local t = now(); local transitionSec = math.ceil((tonumber(env.weatherTransitionRemainingMs) or 0)/1000)
    local row = { observedAtUtc=t, scope=tostring(env.scope or SCOPE), weather=tostring(env.weather),
        preset=env.weatherPreset, transitionSec=transitionSec, authorityEpoch=env.authorityEpoch,
        revision=env.revision, reason=reason, planTransitionId=transitionId }
    local previous = state.recent[#state.recent]
    if previous and previous.authorityEpoch == row.authorityEpoch and previous.revision == row.revision
        and previous.weather == row.weather and previous.planTransitionId == row.planTransitionId then
        state.current = row
        return
    end
    state.current = row; state.recent[#state.recent+1] = row
    while #state.recent > HISTORY_MAX or (#state.recent > 0 and state.recent[1].observedAtUtc < t-HISTORY_SEC) do table.remove(state.recent,1) end
    pcall(function() MySQL.insert.await([[INSERT INTO weather_observation
        (observed_at_utc,scope,weather,preset,transition_sec,authority_epoch,authority_revision,reason,plan_transition_id)
        VALUES (?,?,?,?,?,?,?,?,?)]], {t,row.scope,row.weather,row.preset,transitionSec,row.authorityEpoch,row.revision,reason,transitionId}) end)
    pcall(function()
        MySQL.update.await("DELETE FROM weather_observation WHERE scope=? AND observed_at_utc<?", {SCOPE,t-HISTORY_SEC})
        MySQL.update.await([[DELETE FROM weather_observation WHERE scope=? AND observation_id NOT IN
            (SELECT observation_id FROM (SELECT observation_id FROM weather_observation WHERE scope=?
             ORDER BY observed_at_utc DESC, observation_id DESC LIMIT 256) keep_rows)]], {SCOPE,SCOPE})
    end)
end

local function applyCurrent(reason)
    local t = now(); local target = Weather.at(state.plan.rows, t)
    if not target then state.ready=false; state.reason="plan_has_no_current_row"; return false end
    local env = canonical()
    local mustApply = not env or tostring(env.weather) ~= target.weather or state.applied ~= target.id
    if mustApply then
        local elapsed = math.max(0, t-target.startsAtUtc)
        local remaining = math.max(0, (target.transitionSec or 0)-elapsed)
        state.pending = target.id
        local ok, result, why = pcall(Open77.environment.setWeather, target.weather, remaining)
        state.pending = nil
        if not ok or not result then
            state.ready=false; state.reason="environment_unavailable:" .. tostring(ok and why or result)
            log("apply failed transition=%s weather=%s reason=%s", target.id,target.weather,state.reason); return false
        end
        env=result
    end
    local changed = state.applied ~= target.id
    state.applied=target.id; state.plan.lastAppliedId=target.id
    if changed then
        state.revision=state.revision+1
        saveMeta(state.plan,target.id)
    end
    observe(env,reason,target.id)
    state.ready=true; state.reason=nil
    return true
end

local function loadRecent()
    local rows = MySQL.query.await([[SELECT observed_at_utc,scope,weather,preset,transition_sec,authority_epoch,
        authority_revision,reason,plan_transition_id FROM weather_observation WHERE scope=? AND observed_at_utc>=?
        ORDER BY observed_at_utc DESC LIMIT ?]], {SCOPE,now()-HISTORY_SEC,HISTORY_MAX}) or {}
    state.recent={}; for i=#rows,1,-1 do local r=rows[i]; state.recent[#state.recent+1]={
        observedAtUtc=tonumber(r.observed_at_utc),scope=tostring(r.scope),weather=tostring(r.weather),preset=r.preset,
        transitionSec=tonumber(r.transition_sec),authorityEpoch=tonumber(r.authority_epoch),revision=tonumber(r.authority_revision),
        reason=r.reason,planTransitionId=r.plan_transition_id} end
end

function NcmWeather.readModel()
    if not state.ready or not state.plan then return {state="unavailable",reason=state.reason or "not_ready"} end
    local t=now(); local forecast=Weather.forecast(state.plan,t,{horizonSec=READ_HORIZON_SEC,
        confidence={highSec=5400,mediumSec=86400}})
    local recent={}; local first=math.max(1,#state.recent-15)
    for i=first,#state.recent do recent[#recent+1]=state.recent[i] end
    return {state="ready",scope="NIGHT CITY",scopeId=SCOPE,current=state.current,recent=recent,forecast=forecast,
        revision=state.revision,forecastRevision=state.plan.forecastRevision or 1,issuedAtUtc=t,
        modelVersion=Weather.forecastModelVersion,coveredUntilUtc=state.plan.coveredUntilUtc}
end

function NcmWeather.provenance(startedAtUtc,finishedAtUtc,scope,revisions)
    return Weather.provenance(state.plan and state.plan.rows or {},startedAtUtc,finishedAtUtc,scope or SCOPE,revisions)
end

function NcmWeather.start()
    if state.ready then return true end
    local ok, err = pcall(function()
        local t=now(); state.plan=loadPlan() or newPlan(t)
        if state.plan.policyVersion ~= POLICY.version then error("persisted_policy_version_mismatch") end
        loadRecent(); extendPlan(t)
        local froze, result, why=pcall(Open77.environment.setWeatherFrozen,true)
        if not froze or not result then error("cannot_freeze_platform_scheduler:"..tostring(froze and why or result)) end
        if not applyCurrent("service_start") then error(state.reason) end
    end)
    if not ok then state.ready=false; state.reason=tostring(err); log("start failed: %s",state.reason); return nil,state.reason end
    log("ready epoch=%s rows=%d current=%s covered_until=%d",state.plan.epoch,#state.plan.rows,state.applied,state.plan.coveredUntilUtc)
    CreateThread(function() while true do
        Wait(RECONCILE_MS)
        local safe, why=pcall(function() extendPlan(now()); applyCurrent("reconcile") end)
        if not safe then state.ready=false; state.reason=tostring(why); log("reconcile failed: %s",state.reason) end
    end end)
    return true
end

AddEventHandler("onEnvironmentChanged",function(env)
    if state.ready then observe(env,tostring(env and env.reason or "environment_changed"),state.pending or state.applied) end
end)

RegisterCommand("ncm.weather.status",function()
    local m=NcmWeather.readModel(); log("status state=%s reason=%s current=%s plan=%s forecast=%d recent=%d covered_until=%s",
        tostring(m.state),tostring(m.reason),tostring(m.current and m.current.weather),tostring(state.applied),
        #(m.forecast or {}),#(m.recent or {}),tostring(m.coveredUntilUtc))
end,false)
