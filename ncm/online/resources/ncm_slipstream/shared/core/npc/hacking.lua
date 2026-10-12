-- ncm-core module: npc.hacking
--
-- Quickhacking as racecraft for autonomous racers (owner brief 2026-10-08: "The human player must not occupy a
-- privileged ontology"). Three parts, all pure and server-only:
--
--   PROFILE  who this racer is as a hacker, derived deterministically from the persistent Paddock person (hidden attrs,
--            personality, a seeded stream keyed by their id) plus what has happened to them (`evidence.hacks`). Most
--            racers barely hack; some interfere mildly but refuse destruction; a few are aggressive and poor; some
--            defend well; a rare one is frighteningly good. The same racer stays recognisably the same racer.
--   AGENT    a stateful decision loop per racer per race:
--              idle -> assessing -> targeting (waiting for the window) -> uploading -> cooldown
--              defending -> purging, and aborting an own upload when something worse is incoming
--            It never rolls "hack: yes/no". It weighs race situation, target value, the chance the upload completes,
--            cost and danger (cooldown, retaliation, regulation, severity above what this racer will do), and picks
--            the WEAKEST hack that serves the objective. Perception is delayed and estimates are noisy by skill:
--            nobody is clairvoyant; poor hackers start late, pick the wrong car, overreach or fail to notice.
--            Every decision carries a `why` for the operator trace.
--   MODEL    the same decisions for cars outside every player's bubble, resolved statistically onto the race model
--            (owner ruling 2026-10-08: "physical + modelled"; provenance `simulated`).
--
-- The host executes actions through the REAL chrome machinery (ncm_world `chrome.lua`'s ncm route): uploads, ICE,
-- purge and effects are the same ones a human's hacks use.
local Core = NcmCore

Core.define("npc.hacking", function(C)
    local M = { version = "0.1.0" }
    local Chrome = C.get("competition.chrome")
    local Rules = C.get("competition.hackrules")
    local Beh = C.get("npc.behavior")
    local Hash = C.get("vocabulary.hash")

    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
    local function z(a, k) return ((a and a[k]) or 50) / 50 - 1 end

    M.STATES = { idle = true, assessing = true, targeting = true, uploading = true, cooldown = true,
                 defending = true, purging = true, aborting = true }
    M.HACKER_FLOOR = 0.15         -- aptitude below this: this racer never starts an offensive upload
    M.PURGE_COOLDOWN_MS = Chrome.hack("purge").cooldownMs

    -- -------------------------------------------------------------------------------------------- profile
    --- The persistent hacking profile of a Paddock person `{ id, attrs, personality, evidence }`.
    function M.profile(person, seed)
        local a, p = person.attrs or {}, person.personality or {}
        local r = Hash.stream(tostring(seed or "ncm"), "hack-profile", tostring(person.id or "?"))
        -- aptitude has a long tail: u^3 puts ~54 % of racers under 0.15 and ~3 % above 0.8
        local aptitude = clamp(r() ^ 3 + 0.08 * z(a, "adaptability") + 0.05 * z(a, "feedback"), 0, 1)
        local defense = clamp(0.55 * aptitude + 0.35 * r() ^ 1.5 + 0.10 * z(a, "discipline"), 0, 1)
        local sabotage = clamp(0.45 + 0.25 * z(a, "aggression") - 0.25 * z(a, "discipline") - 0.20 * (p.warmth or 0)
            + 0.10 * (p.valor or 0) + 0.15 * (r() - 0.5), 0, 1)
        -- what this racer is WILLING to do to another car: destruction needs cold, aggressive and unruly together
        local maxSeverity = 1 + math.floor(sabotage * 3.2)                         -- 1..4
        if sabotage > 0.78 and (p.warmth or 0) < -0.25 and z(a, "ego") > 0.1 then maxSeverity = 5 end
        local prof = {
            aptitude = aptitude,
            offense = clamp(0.45 * aptitude + 0.25 * z(a, "aggression") + 0.15 * z(a, "ego") - 0.15 * (p.warmth or 0)
                + 0.10 * (r() - 0.5) + 0.2, 0, 1),
            defense = defense,
            sabotage = sabotage,
            maxSeverity = maxSeverity,
            patience = clamp(0.5 + 0.30 * z(a, "discipline") - 0.25 * z(a, "aggression") + 0.20 * (p.temperament or 0), 0, 1),
            timing = clamp(0.20 + 0.60 * aptitude + 0.15 * z(a, "racecraft") + 0.05 * r(), 0, 1),
            targetQuality = clamp(0.25 + 0.45 * aptitude + 0.20 * z(a, "racecraft"), 0, 1),
            risk = Beh.profile(person).riskTolerance,
            retaliation = clamp(0.35 + 0.35 * Beh.profile(person).volatility + 0.20 * z(a, "ego"), 0, 1),
            conservation = clamp(0.5 + 0.30 * z(a, "discipline") - 0.20 * z(a, "aggression"), 0, 1),
            regulatoryAwareness = clamp(0.5 + 0.35 * z(a, "discipline") + 0.20 * (p.authority or 0), 0, 1),
            perceptionMs = math.floor(2600 - 2100 * defense),
            hasIce = defense >= 0.35,
            canPurge = defense >= 0.20,
            stealth = clamp(0.6 * aptitude, 0, 1),
        }
        return M.adapt(prof, person.evidence and person.evidence.hacks)
    end

    --- History bends the profile a little: landed hacks sharpen a hacker; being hacked a lot makes a racer defensive.
    function M.adapt(prof, h)
        if type(h) ~= "table" then return prof end
        local landed, received = tonumber(h.landed) or 0, tonumber(h.received) or 0
        prof.aptitude = clamp(prof.aptitude + math.min(0.10, 0.01 * landed), 0, 1)
        prof.timing = clamp(prof.timing + math.min(0.08, 0.008 * landed), 0, 1)
        prof.defense = clamp(prof.defense + math.min(0.15, 0.015 * received), 0, 1)
        prof.perceptionMs = math.floor(2600 - 2100 * prof.defense)
        prof.hasIce, prof.canPurge = prof.defense >= 0.35, prof.defense >= 0.20
        prof.hackedBy = type(h.by) == "table" and h.by or {}
        return prof
    end

    --- Record what happened into a person's evidence (`evidence.hacks`), the persistent memory `adapt` reads.
    function M.remember(evidence, what, otherId)
        evidence.hacks = evidence.hacks or { used = 0, landed = 0, received = 0, by = {} }
        local h = evidence.hacks
        h.by = h.by or {}
        if what == "used" then h.used = (h.used or 0) + 1
        elseif what == "landed" then h.landed = (h.landed or 0) + 1
        elseif what == "received" then
            h.received = (h.received or 0) + 1
            if otherId then h.by[tostring(otherId)] = (h.by[tostring(otherId)] or 0) + 1 end
        end
        return h
    end

    -- -------------------------------------------------------------------------------------------- agent
    function M.newAgent(id, prof, opts)
        opts = opts or {}
        return { id = id, prof = prof, state = "idle", mood = Beh.newMood(), cooldowns = {}, purgeReadyAt = 0,
                 nextAssessAt = opts.startMs or 0, upload = nil, incoming = {}, hackedBy = {}, lastWhy = nil,
                 seed = tostring(opts.seed or "race"), step = 0 }
    end

    local function rngFor(agent, tag)
        agent.step = agent.step + 1
        return Hash.stream("npc-hack", agent.seed, agent.id, tag, agent.step)
    end

    --- What this racer gains by hitting `o` now (0..1+): position stakes, rivalry, payback. Noisy by target judgement.
    local function targetValue(agent, sit, o, r)
        local P = agent.prof
        local v, why = 0, {}
        local gap = tonumber(o.gapM) or 0                -- + ahead of me, - behind me (along the line)
        if sit.phase == "grid" then
            if math.abs(gap) < 40 then v = v + 0.55; why[#why + 1] = "grid neighbour" end
        elseif gap > 0 and gap < 90 then
            v = v + (1 - gap / 90) * 0.9; why[#why + 1] = ("attacking for P%s (%.0f m ahead)"):format(tostring(o.pos or "?"), gap)
        elseif gap < 0 and gap > -70 and (tonumber(o.closingMps) or 0) > 0.5 then
            v = v + (1 + gap / 70) * 0.8; why[#why + 1] = ("defending (closing %.1f m/s)"):format(o.closingMps)
        end
        local rival = tonumber(o.rival) or 0
        if rival > 0 then v = v + 0.25 * math.min(1, rival / 3); why[#why + 1] = "rival" end
        local payback = (agent.hackedBy[o.id] or 0) + ((P.hackedBy or {})[tostring(o.id)] or 0)
        if payback > 0 then v = v + P.retaliation * 0.6 * math.min(1, payback / 2); why[#why + 1] = "payback" end
        if o.damaged then v = v * 0.5; why[#why + 1] = "already compromised" end
        if sit.phase == "final" then v = v * 1.5; why[#why + 1] = "final stretch" end
        -- judgement: a poor eye misreads who matters
        v = math.max(0, v + r:normal(0, (1 - P.targetQuality) * 0.35))
        return v, table.concat(why, ", ")
    end

    --- The weakest hack that serves `value`, within what this racer will do and the rules they respect.
    local function chooseHack(agent, sit, o, value, r)
        local P = agent.prof
        local level = sit.rules or "allowed"
        local needed = clamp(math.floor(1 + 3.2 * value), 1, 5)
        local options = {}
        for _, h in ipairs(Chrome.offensive(o.human == true and o.bound == true)) do
            local ready = (agent.cooldowns[h.id] or 0) <= sit.nowMs
            local willing = h.severity <= P.maxSeverity
            local offence = Rules.offence(level, h.id)
            -- a law-abiding racer will not commit an offence; a reckless one might if the stakes are high
            local lawful = (not offence) or (P.regulatoryAwareness < 0.35 and value > 0.8)
            if ready and willing and lawful then options[#options + 1] = h end
        end
        if #options == 0 then return nil, "nothing usable (cooldowns / unwilling / rules)" end
        table.sort(options, function(a, b) if a.severity ~= b.severity then return a.severity < b.severity end return a.order < b.order end)
        -- predicted distance when the upload would complete (closing estimate, noisy by timing skill)
        local function fits(h)
            local est = (tonumber(o.dist) or 999) - (tonumber(o.closingMps) or 0) * (h.uploadMs / 1000)
            est = est + r:normal(0, (1 - P.timing) * 8)
            return est <= h.range * 0.95
        end
        local pick
        for _, h in ipairs(options) do if h.severity >= needed and fits(h) then pick = h; break end end
        if not pick then for i = #options, 1, -1 do if fits(options[i]) then pick = options[i]; break end end end
        if not pick then return nil, "no hack would complete in range" end
        -- poor judgement sometimes reaches for the heaviest tool it has
        if r() < (1 - P.timing) * 0.25 then
            for i = #options, 1, -1 do if fits(options[i]) then pick = options[i]; break end end
        end
        return pick, ("needed severity %d, chose %s (%s, sev %d)"):format(needed, pick.id, pick.class, pick.severity)
    end

    local function trace(agent, out, kind, text)
        agent.lastWhy = text
        out[#out + 1] = { op = "trace", kind = kind, why = text, state = agent.state }
    end

    --- One decision step. `sit` (built by the host):
    ---   nowMs, phase ("grid"|"racing"|"final"), greenAtMs, rules, physical,
    ---   self = { vid, speed, damaged },
    ---   others = { { id, vid, human, bound, dist, gapM, closingMps, pos, rival, damaged } },
    ---   incoming = { { key, attacker, hack, startedMs, uploadMs } } (uploads against this racer's car)
    --- Returns a list of actions: { op = "start", hack, target, targetVid, why } | { op = "cancel", why } |
    --- { op = "purge", why } | { op = "trace", kind, why }.
    function M.step(agent, sit)
        local P, out, now = agent.prof, {}, sit.nowMs
        Beh.decay(agent.mood, { volatility = P.retaliation }, 0.25)

        -- ---- DEFENCE first: what is being uploaded onto me, and do I know yet? ----
        local live = {}
        for _, inc in ipairs(sit.incoming or {}) do
            live[inc.key] = true
            local k = agent.incoming[inc.key]
            if not k then
                local r = rngFor(agent, "perceive")
                k = { inc = inc, perceiveAt = inc.startedMs + math.floor(P.perceptionMs * (0.7 + 0.6 * r())), handled = false }
                -- a weak defender may never notice at all
                if r() > 0.25 + 0.75 * P.defense then k.perceiveAt = math.huge end
                agent.incoming[inc.key] = k
            end
            if not k.handled and now >= k.perceiveAt then
                k.handled = true
                local h = Chrome.hack(inc.hack)
                local sev = h and h.severity or 1
                local leftMs = inc.startedMs + inc.uploadMs - now
                if not P.canPurge then
                    trace(agent, out, "defence", ("noticed incoming %s from %s but cannot purge"):format(inc.hack, tostring(inc.attacker)))
                elseif agent.purgeReadyAt > now then
                    trace(agent, out, "defence", ("incoming %s: purge still cooling down"):format(inc.hack))
                elseif sev / 5 < P.conservation * 0.35 and sev <= 1 then
                    trace(agent, out, "defence", ("incoming %s judged not worth a purge"):format(inc.hack))
                elseif leftMs <= 0 then
                    trace(agent, out, "defence", ("noticed %s too late"):format(inc.hack))
                else
                    if agent.upload then
                        out[#out + 1] = { op = "cancel", why = "aborting own upload to defend against " .. inc.hack }
                        agent.upload = nil
                        agent.state = "aborting"
                    end
                    agent.state = "purging"
                    agent.purgeReadyAt = now + M.PURGE_COOLDOWN_MS
                    out[#out + 1] = { op = "purge", why = ("purging incoming %s (sev %d, %.1f s left, from %s)"):format(
                        inc.hack, sev, leftMs / 1000, tostring(inc.attacker)) }
                    Beh.provoke(agent.mood, { volatility = P.retaliation }, "blocked")
                end
            end
        end
        for key in pairs(agent.incoming) do if not live[key] then agent.incoming[key] = nil end end
        if agent.state == "purging" then agent.state = "cooldown"; agent.nextAssessAt = now + 1500 end

        -- ---- OFFENCE ----
        if agent.upload then
            local u = agent.upload
            local o
            for _, x in ipairs(sit.others or {}) do if x.id == u.target then o = x end end
            local h = Chrome.hack(u.hack)
            if not o or (tonumber(o.dist) or 999) > h.range * 1.05 then
                out[#out + 1] = { op = "cancel", why = ("target %s left range during %s"):format(tostring(u.target), u.hack) }
                agent.upload = nil
                agent.state = "cooldown"
                agent.nextAssessAt = now + 2000
            end
            return out
        end
        if agent.state == "targeting" and agent.plan then
            if now >= agent.plan.startAt then
                local pl = agent.plan
                agent.plan = nil
                local o
                for _, x in ipairs(sit.others or {}) do if x.id == pl.target then o = x end end
                local h = Chrome.hack(pl.hack)
                if o and (tonumber(o.dist) or 999) <= h.range then
                    agent.upload = { hack = h.id, target = o.id, startedMs = now }
                    agent.cooldowns[h.id] = now + h.cooldownMs
                    agent.state = "uploading"
                    out[#out + 1] = { op = "start", hack = h.id, target = o.id, targetVid = o.vid, why = pl.why }
                else
                    agent.state = "idle"
                    trace(agent, out, "abort", "planned target no longer in range at the window")
                end
            end
            return out
        end
        if now < agent.nextAssessAt then return out end
        local r = rngFor(agent, "assess")
        agent.nextAssessAt = now + math.floor(800 + 2200 * P.patience * (0.6 + 0.8 * r()))
        if agent.state == "cooldown" then agent.state = "idle" end
        if P.aptitude < M.HACKER_FLOOR or P.offense < 0.2 then
            agent.state = "idle"
            return out            -- not a netrunner: nothing to log every tick
        end
        if sit.rules == "prohibited" and P.regulatoryAwareness >= 0.35 then
            agent.state = "idle"
            return out
        end
        agent.state = "assessing"
        local best, bestV, bestWhy
        for _, o in ipairs(sit.others or {}) do
            if (tonumber(o.dist) or 999) <= 80 then
                local v, why = targetValue(agent, sit, o, r)
                if not bestV or v > bestV then best, bestV, bestWhy = o, v, why end
            end
        end
        if not best then agent.state = "idle"; return out end
        local stakes = sit.phase == "final" and 1 or (sit.phase == "grid" and 0.6 or 0.3)
        local eff = Beh.effective({ riskTolerance = P.risk, clutch = 0.5 }, agent.mood, stakes)
        local h, choiceWhy = chooseHack(agent, sit, best, bestV, r)
        if not h then
            trace(agent, out, "hold", ("considered %s (%s, value %.2f): %s"):format(tostring(best.id), bestWhy, bestV, choiceWhy))
            agent.state = "idle"
            return out
        end
        -- cost and danger: cooldown spent, retaliation, an offence, the chance it does not complete
        local pComplete = clamp(1 - math.max(0, (best.dist or 0) - h.range * 0.6) / (h.range * 0.6), 0.1, 1)
        local cost = P.conservation * h.cooldownMs / 600000 * 0.6
            + (best.retaliates and 0.15 or 0.05) * (1 - eff.risk)
            + (Rules.offence(sit.rules or "allowed", h.id) and P.regulatoryAwareness * 0.6 or 0)
        local utility = bestV * pComplete * (0.6 + 0.8 * P.offense) - cost
        local bar = (1 - P.offense) * 0.55 + 0.05
        if utility < bar then
            trace(agent, out, "hold", ("%s on %s not worth it now (utility %.2f < %.2f; %s)"):format(h.id, tostring(best.id), utility, bar, bestWhy))
            agent.state = "idle"
            return out
        end
        local why = ("%s -> %s: %s; %s; utility %.2f"):format(h.id, tostring(best.id), bestWhy, choiceWhy, utility)
        -- TIMING: on the grid, aim the impact at the green -- by skill, never frame-perfect
        if sit.phase == "grid" and sit.greenAtMs and sit.greenAtMs > now then
            local err = r:normal(0, 1800 * (1 - P.timing))
            local startAt = math.floor(sit.greenAtMs - h.uploadMs + 250 + err)
            if startAt > now then
                agent.plan = { hack = h.id, target = best.id, startAt = startAt, why = why .. (" (timed for the green, err %+.1f s)"):format(err / 1000) }
                agent.state = "targeting"
                trace(agent, out, "plan", agent.plan.why)
                return out
            end
        end
        agent.upload = { hack = h.id, target = best.id, startedMs = now }
        agent.cooldowns[h.id] = now + h.cooldownMs
        agent.state = "uploading"
        out[#out + 1] = { op = "start", hack = h.id, target = best.id, targetVid = best.vid, why = why }
        return out
    end

    --- The host reports how an upload this racer started ended: "impact" | "blocked" | "interrupted" | "purged" | "refused".
    function M.outcome(agent, outcome, nowMs)
        agent.upload = nil
        agent.plan = nil
        agent.state = "cooldown"
        agent.nextAssessAt = nowMs + math.floor(2000 + 6000 * agent.prof.patience)
        agent.lastOutcome = outcome
    end

    --- Something landed on this racer's car. Provocation, and who did it is remembered for the race.
    function M.hit(agent, attackerId, hackId)
        if attackerId then agent.hackedBy[attackerId] = (agent.hackedBy[attackerId] or 0) + 1 end
        local h = Chrome.hack(hackId)
        Beh.provoke(agent.mood, { volatility = agent.prof.retaliation }, (h and h.severity or 1) >= 3 and "contact" or "blocked")
    end

    -- -------------------------------------------------------------------------------------------- model
    --- An exchange between two cars nobody is near, resolved on the race model. `attacker`/`target` are profiles.
    --- Returns { landed, purged, iced, timeLossS, dnf } -- the same hack, the same defences, statistically.
    M.MODEL_LOSS_S = { performance = 2, disruption = 1, propulsion = 3, control = 9, tire = 18 }
    function M.resolveModel(attacker, target, hackId, rng)
        local h = Chrome.hack(hackId)
        if not h then return { landed = false } end
        local pComplete = clamp(0.55 + 0.35 * attacker.timing - 0.10 * (h.uploadMs / 8000), 0.1, 0.95)
        if rng() > pComplete then return { landed = false, reason = "upload broke" } end
        if target.hasIce and rng() < 0.5 then return { landed = false, iced = true, reason = "ICE" } end
        local pNotice = target.canPurge and clamp(target.defense * (h.uploadMs / 3000), 0, 0.9) or 0
        if rng() < pNotice then return { landed = false, purged = true, reason = "purged" } end
        if h.class == "catastrophic" then return { landed = true, dnf = "crash" } end
        local loss = M.MODEL_LOSS_S[h.class] or 2
        return { landed = true, timeLossS = loss * (0.7 + 0.6 * rng()) }
    end

    return M
end)
