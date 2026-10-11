-- ncm-core module: world.readiness
--
-- KB-60: who is connected but cannot actually play, and what should be said to them.
--
-- The KB-39 watchdog was started from `onPlayerReady` -- which is precisely the event that does not
-- fire in the failure it was written for. Our first in-the-wild visitor sat at the platform's
-- `appearance_failed` stage for eleven minutes, was visible to `ncm.where` WITH A POSITION, and the
-- watchdog never started. Two things were wrong and both are fixed here:
--
--   1. the question must be asked by a PERIODIC SWEEP over everyone who is connected, never by a
--      readiness event -- an event cannot report the absence of itself;
--   2. `fresh and position` is not a test of being able to play. That player satisfied it. The signal
--      that mattered was the platform's own `appearance_failed`, which NCM never read.
--
-- This module holds the decision only. It has no clock, no chat and no player list: the host sweeps,
-- feeds in what it observed, and performs the actions that come back. That makes the rule testable
-- offline, which the old thread-per-player watchdog never was.
local Core = NcmCore

Core.define("world.readiness", function(C)
    local M = { version = "0.0.1" }

    --- Readiness-wait stages reported by the platform's appearance shell
    --- (`open77_appearance/client/main.lua`, the [OP77-INIT-002] loop). A stage being reported AT ALL
    --- means that client is still waiting for gameplay readiness, whatever its position says.
    ---
    --- `appearance_failed` is terminal, not slow: the shell's `announce()` opens with
    --- `if announced or failed ~= nil then return end`, so once an appearance restore has failed the
    --- readiness signal is never sent again for that session. There is no retry. Waiting cannot help
    --- and only reconnecting can, so that case is advised almost at once instead of after the grace.
    M.STAGES = {
        player_reset                   = "waiting",
        appearance_record              = "waiting",
        appearance_applying            = "waiting",
        alive_or_gameplay_announcement = "waiting",
        appearance_failed              = "terminal",
    }

    --- Three different graces, because "cannot play" has three different prognoses and only one of them is
    --- worth interrupting somebody over. Deploy 19 live QA (§R2) proved the point against the author: a normal
    --- join reported `appearance_applying` with `reset=complete bootstrap=ready`, was warned at 47 s, and
    --- became playable by itself at 63 s. The diagnosis was right and the advice was wrong — telling someone to
    --- reconnect 15 s before their load completes restarts a nearly-finished load, which is worse than silence.
    ---
    --- So: a fresh NON-TERMINAL stage report means the appearance shell is alive and making progress, and earns
    --- a long grace. Silence with no readiness is the original KB-39 case and keeps the middle one. A terminal
    --- stage will never resolve, so it keeps the short one.
    local DEFAULTS = {
        progressingGraceS = 90,   -- the platform is reporting progress: let it finish
        firstWarnS        = 45,   -- silent limbo, no stage at all (KB-39's original case)
        terminalGraceS    = 10,   -- a terminal stage will not resolve; say so promptly
        repeatS           = 60,
        giveUpS           = 300,
        --- The client's readiness diagnostic is a ~15 s HEARTBEAT, sent only while it is still waiting
        --- (`open77_appearance/client/main.lua`: `readinessWaitTicks % 15`, and the counter resets the moment
        --- it stops waiting). So the report's meaning expires quickly: if we have not heard in appreciably more
        --- than one interval, that client stopped waiting and became ready.
        ---
        --- Deploy 19 live QA: the owner's join produced exactly ONE report, at 17 s, and then silence -- they
        --- were ready right after it. Holding that single heartbeat for 45 s made NCM believe they could not
        --- play until 62 s, warn them at 47 s, and then log "reached a playable world after 63s" when all that
        --- had really expired was this timer. A heartbeat must not outlive its own interval by three times.
        staleStageS       = 25,
    }

    local Tracker = {}
    Tracker.__index = Tracker

    --- opts: any of the DEFAULTS keys, in seconds.
    function M.new(opts)
        opts = type(opts) == "table" and opts or {}
        local cfg = {}
        for key, fallback in pairs(DEFAULTS) do
            local given = tonumber(opts[key])
            cfg[key] = (given and given >= 0) and given or fallback
        end
        return setmetatable({ cfg = cfg, players = {} }, Tracker)
    end

    local function entryFor(self, id, now, name)
        id = tonumber(id)
        if not id then return nil end
        local e = self.players[id]
        if not e then
            e = { id = id, since = now, limboSince = now, warned = 0,
                  nextWarn = self.cfg.firstWarnS, gaveUp = false }
            self.players[id] = e
        end
        if name ~= nil and name ~= "" then e.name = tostring(name) end
        return e
    end

    --- A player joined: start the clock, and forget anything left over on a reused player id.
    function Tracker:connected(id, now, name)
        local e = entryFor(self, id, now, name)
        if not e then return nil end
        e.since, e.limboSince = now, now
        e.ready, e.presumed = nil, nil
        e.stage, e.stageAt, e.stageElapsed = nil, nil, nil
        e.warned, e.nextWarn, e.gaveUp = 0, self.cfg.firstWarnS, false
        return e
    end

    --- A player who was already connected when NCM started. `onPlayerReady` will never fire again for
    --- them, so presume they are past the barrier rather than warning a whole healthy server on reload.
    --- A stage report still overrides the presumption, which is the outcome we want.
    function Tracker:adopt(id, now, name)
        local e = entryFor(self, id, now, name)
        if not e then return nil end
        if not e.ready then e.presumed = true end
        return e
    end

    --- NCM's own readiness barrier lifted for this player (`onPlayerReady`).
    function Tracker:ready(id, now)
        local e = entryFor(self, id, now)
        if not e then return nil end
        e.ready = now
        return e
    end

    --- The platform reported a readiness-wait stage for this player. Returns "waiting" or "terminal"
    --- plus whether the stage changed, or nil when the stage is not one we recognise -- never trust an
    --- unvalidated client string.
    function Tracker:stage(id, stage, now, elapsed)
        local kind = type(stage) == "string" and M.STAGES[stage] or nil
        if not kind then return nil end
        local e = entryFor(self, id, now)
        if not e then return nil end
        local changed = e.stage ~= stage
        e.stage, e.stageAt, e.stageElapsed = stage, now, tonumber(elapsed)
        return kind, changed
    end

    --- What we currently believe about one player. `inWorld` is the host's observation this instant.
    function Tracker:state(id, now, inWorld)
        local e = self.players[tonumber(id) or -1]
        if not e then return { known = false } end
        local kind
        if e.stage and (now - (e.stageAt or 0)) <= self.cfg.staleStageS then
            kind = M.STAGES[e.stage]
        end
        local waiting = kind ~= nil
        local past = (e.ready ~= nil) or (e.presumed == true)
        return {
            known    = true,
            id       = e.id,
            name     = e.name,
            -- Three independent facts, all required. A position on its own was the whole of KB-60.
            playable = past and inWorld == true and not waiting,
            ready    = past,
            inWorld  = inWorld == true,
            waiting  = waiting,
            terminal = kind == "terminal",
            stage    = waiting and e.stage or nil,
            waited   = now - (e.limboSince or e.since or now),
            warned   = e.warned,
            gaveUp   = e.gaveUp == true,
        }
    end

    --- How long this player's situation earns before anybody interrupts them. See DEFAULTS: a platform that is
    --- reporting progress gets the long grace, silence gets the middle one, and a failure that cannot resolve
    --- gets the short one.
    function Tracker:graceFor(state)
        if type(state) ~= "table" then return self.cfg.firstWarnS end
        if state.terminal then return self.cfg.terminalGraceS end
        if state.waiting then return self.cfg.progressingGraceS end
        return self.cfg.firstWarnS
    end

    --- One pass over everyone the host can see.
    --- snapshot: array of { id, name?, inWorld }.  Returns an array of actions, in player-id order:
    ---   { kind = "advise",    ... , terminal, stage, waited, warned }
    ---   { kind = "gaveup",    ... }   stop warning; still connected, still not playable
    ---   { kind = "recovered", ... }   was warned, now playable
    ---   { kind = "vanished",  ... }   tracked, warned, and no longer in the snapshot
    function Tracker:sweep(now, snapshot)
        local actions, seen, ids, byId = {}, {}, {}, {}
        local rows = type(snapshot) == "table" and snapshot or {}

        for i = 1, #rows do
            local row = rows[i]
            local id = type(row) == "table" and tonumber(row.id) or nil
            if id and not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
                byId[id] = row
            end
        end
        table.sort(ids)

        for i = 1, #ids do
            local id = ids[i]
            local row = byId[id]
            local e = entryFor(self, id, now, row.name)
            local st = self:state(id, now, row.inWorld)

            if st.playable then
                if e.warned > 0 then
                    st.kind = "recovered"
                    actions[#actions + 1] = st
                end
                e.limboSince, e.warned, e.nextWarn, e.gaveUp = nil, 0, self.cfg.firstWarnS, false
            else
                if not e.limboSince then
                    e.limboSince = now
                    st.waited = 0
                end
                if not e.gaveUp then
                    -- The FIRST warning waits as long as the prognosis deserves; repeats are a plain cadence.
                    local due
                    if e.warned == 0 then
                        due = st.waited >= self:graceFor(st)
                    else
                        due = st.waited >= e.nextWarn
                    end
                    if due then
                        e.warned = e.warned + 1
                        e.nextWarn = st.waited + self.cfg.repeatS
                        st.warned = e.warned
                        st.kind = "advise"
                        actions[#actions + 1] = st
                    end
                    if st.waited >= self.cfg.giveUpS and e.warned > 0 then
                        e.gaveUp = true
                        local done = self:state(id, now, row.inWorld)
                        done.kind = "gaveup"
                        actions[#actions + 1] = done
                    end
                end
            end
        end

        -- Anyone we were tracking who is no longer connected. `forget` from the disconnect event
        -- normally gets here first; this catches a missed event rather than leaking the entry.
        local gone = {}
        for id in pairs(self.players) do
            if not seen[id] then gone[#gone + 1] = id end
        end
        table.sort(gone)
        for i = 1, #gone do
            local departure = self:forget(gone[i], now)
            if departure then
                departure.kind = "vanished"
                actions[#actions + 1] = departure
            end
        end

        return actions
    end

    --- Drop a player. Returns a departure record when they left while being warned about, else nil --
    --- this is the line worth having in the host log: somebody gave up and went.
    function Tracker:forget(id, now)
        id = tonumber(id)
        local e = id and self.players[id]
        if not e then return nil end
        self.players[id] = nil
        if (e.warned or 0) <= 0 then return nil end
        return {
            known    = true,
            id       = e.id,
            name     = e.name,
            playable = false,
            ready    = e.ready ~= nil or e.presumed == true,
            inWorld  = false,
            waiting  = e.stage ~= nil,
            terminal = M.STAGES[e.stage or ""] == "terminal",
            stage    = e.stage,
            waited   = (now or 0) - (e.limboSince or e.since or now or 0),
            warned   = e.warned,
            gaveUp   = e.gaveUp == true,
        }
    end

    --- Everyone currently tracked, id order. Diagnostics only.
    function Tracker:all()
        local ids = {}
        for id in pairs(self.players) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids
    end

    --- Why we believe this player cannot play, in the host's log voice. The diagnosis KB-60 lacked.
    function M.why(state)
        if type(state) ~= "table" then return "unknown" end
        return ("ncm-ready=%s in-world=%s platform-stage=%s"):format(
            state.ready and "yes" or "NO",
            state.inWorld and "yes" or "NO",
            state.stage or "none")
    end

    --- What to say to the player. Terminal and merely-slow deserve different words: one of them is
    --- worth waiting out and the other is not.
    function M.advice(state)
        if type(state) == "table" and state.terminal then
            return {
                title   = "Character did not load",
                message = "Your character failed to load and the server cannot retry it. Reconnect.",
                chat    = "Your character failed to load, and the server cannot retry it this session -- waiting will not fix it. Please disconnect and reconnect.",
            }
        end
        return {
            title   = "Still loading",
            message = "Your character did not finish loading. Reconnect to retry.",
            chat    = "Your character has not finished loading, so nothing here will respond yet. Please disconnect and reconnect -- it usually works on the second try.",
        }
    end

    return M
end)
